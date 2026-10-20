extends SceneTree
## The real co-op path with real scene changes (change_scene_to_file) for the HOST:
## map -> "Co-op" button -> lobby scene -> create room -> start -> CoopRun -> battle
## scene -> end screen -> back to the map; and the same with the partner leaving the
## lobby or the match. The guest is a CoopLobby object plus a battle scene in a
## SubViewport (scene changes are global to the tree, one process has one host UI).
## An in-memory database (tests/fake_rtdb.gd) stands in for Firebase.
## godot --headless --fixed-fps 60 --path . --script res://tests/test_coop_flow.gd

const Fake := preload("res://tests/fake_rtdb.gd")
const MAP := "res://scenes/level_select.tscn"
const GAME := "res://scenes/main.tscn"

var fails := 0
var _server := Fake.FakeServer.new()
var _host_net: Fake.FakeTransport = null
var _guest_net: Fake.FakeTransport = null


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_coop_flow.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	GameSettings.config_path = "user://test_coop_flow_settings.cfg"
	GameSettings.set_language("en")
	node_added.connect(
		func(node: Node) -> void:
			if node is Hero:
				(node as Hero).auto_action = false
	)
	_run.call_deferred()


func _net(uid: String) -> Fake.FakeTransport:
	var net := Fake.FakeTransport.new()
	net.server = _server
	net.user_id = uid
	_server.clients.append(net)
	return net


func _co() -> GDScript:
	return load("res://scripts/coop_run.gd") as GDScript


func _scene_is(path: String) -> bool:
	return current_scene != null and current_scene.scene_file_path == path


func _until(cond: Callable, frames: int = 300) -> bool:
	for i in frames:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _goto(path: String) -> void:
	paused = false
	change_scene_to_file(path)
	await _until(func() -> bool: return _scene_is(path) and current_scene.is_node_ready())
	await process_frame


func _button(scene: Node, text: String) -> Button:
	for node in scene.find_children("*", "Button", true, false):
		if (node as Button).text == text and (node as Button).is_visible_in_tree():
			return node as Button
	return null


func _press(scene: Node, text: String) -> bool:
	var button: Button = _button(scene, text)
	if button == null:
		return false
	button.pressed.emit()
	return true


func _label_exists(scene: Node, text: String) -> bool:
	for node in scene.find_children("*", "Label", true, false):
		if (node as Label).text == text and (node as Label).is_visible_in_tree():
			return true
	return false


func _run() -> void:
	_host_net = _net("uidHost")
	_guest_net = _net("uidGuest")
	await _test_map_button()
	_co().set("transport_override", _host_net)
	await _test_full_match()
	await _test_leave_lobby()
	await _test_partner_leaves_match()
	await _test_join_errors()
	_co().set("transport_override", null)
	for node in Fake.FakeTransport.all:
		(node as Node).free()
	Fake.FakeTransport.all.clear()
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


# --- helpers for a match ------------------------------------------------------


## Host through the real UI up to the room; guest as a lobby object. Returns
## {"guest": CoopLobby, "code": String, "screen": Node}.
func _open_room() -> Dictionary:
	await _goto(MAP)
	await _until(func() -> bool: return _button(current_scene, "Co-op") != null)
	check(_press(current_scene, "Co-op"), "map: the Co-op button is pressed")
	await _until(func() -> bool: return _scene_is("res://scenes/coop_lobby.tscn"))
	await process_frame
	check(_scene_is("res://scenes/coop_lobby.tscn"), "the lobby scene is loaded")
	check(_press(current_scene, "Create a room"), "lobby: Create a room")
	var screen: Node = current_scene
	await _until(func() -> bool: return screen.get("lobby") != null)
	var code: String = str(screen.get("lobby").code)
	check(code.length() == 5, "room code %s" % code)
	var guest := CoopLobby.new(_guest_net)
	var joined: Dictionary = await guest.join(code, "Bob", Sim.VERSION)
	check(joined["ok"], "guest joined")
	await process_frame
	return {"guest": guest, "code": code, "screen": screen}


func _start_match(room: Dictionary) -> Dictionary:
	var guest: CoopLobby = room["guest"]
	var guest_config: Array[Dictionary] = [{}]
	guest.started.connect(func(c: Dictionary) -> void: guest_config[0] = c)
	await guest.set_ready(true)
	await process_frame
	check(_press(current_scene, "Start"), "lobby: Start")
	check(
		await _until(func() -> bool: return _scene_is(GAME)), "the battle scene replaced the lobby"
	)
	var host_main: Node = current_scene
	var host_sim: Sim = host_main.get_node("Sim")
	host_sim.manual = true
	var cfg: Dictionary = guest_config[0].duplicate()
	cfg["partner"] = "Ann"
	cfg["name"] = "Bob"
	var view := SubViewport.new()
	view.own_world_3d = true
	view.size = Vector2i(320, 180)
	root.add_child(view)
	var guest_main: Node = (load(GAME) as PackedScene).instantiate()
	guest_main.set("coop_config", cfg)
	guest_main.set("coop_transport", _guest_net)
	guest_main.set("coop_lobby", guest)
	view.add_child(guest_main)
	var guest_sim: Sim = guest_main.get_node("Sim")
	guest_sim.manual = true
	await _until(func() -> bool: return host_sim.running and guest_sim.running)
	return {"host": host_main, "guest": guest_main, "view": view}


func _play(match_nodes: Dictionary, ticks: int) -> void:
	var hs: Sim = match_nodes["host"].get_node("Sim")
	var gs: Sim = match_nodes["guest"].get_node("Sim")
	for i in ticks * 3:
		if hs.tick >= ticks and gs.tick >= ticks:
			break
		hs.advance(1.0 / 30.0)
		gs.advance(1.0 / 30.0)
		if i % 40 == 0:
			await process_frame


func _db_clean(code: String) -> void:
	check(_server.get_at("rooms/" + code) == null, "the room %s is deleted" % code)
	check(_server.get_at("user_rooms/uidHost") == null, "user_rooms of the host is clear")
	check(_server.get_at("user_rooms/uidGuest") == null, "user_rooms of the guest is clear")


func _no_records() -> void:
	var online: Node = root.get_node("Online")
	check(not online.call("has_pending_record"), "no online record is queued")
	check(LevelCatalog.endless_record(1) == 0 and not LevelCatalog.endless, "no endless record")


# --- scenarios ----------------------------------------------------------------


func _test_map_button() -> void:
	print("-- map: the Co-op button")
	_co().set("transport_override", null)
	await _goto(MAP)
	check(_button(current_scene, "Co-op") == null, "no database: no button")
	_co().set("transport_override", _host_net)
	await _goto(MAP)
	var button: Button = _button(current_scene, "Co-op")
	check(button != null and button.size.y >= 84.0, "database: the button is there (>= 84 px)")


func _test_full_match() -> void:
	print("-- map -> lobby -> battle -> end -> map")
	var room: Dictionary = await _open_room()
	var nodes: Dictionary = await _start_match(room)
	var host_main: Node = nodes["host"]
	check(
		host_main.get("coop") != null and host_main.get("coop").session.role == "host",
		"host battle"
	)
	await _play(nodes, 150)
	var hs: Sim = host_main.get_node("Sim")
	var gs: Sim = nodes["guest"].get_node("Sim")
	check(hs.tick >= 150 and gs.tick >= 150, "150 ticks together (%d, %d)" % [hs.tick, gs.tick])
	# Both sides lose the battle at once.
	(host_main.get_node("GameState") as GameState).lose_lives(9999)
	(nodes["guest"].get_node("GameState") as GameState).lose_lives(9999)
	await process_frame
	check(bool(host_main.battle_end.ended) and nodes["guest"].battle_end.ended, "both see the end")
	check(host_main.get_node("HUD/Root/EndScreen").visible, "the host sees the end screen")
	# Back to the map: the real button of the end screen.
	host_main.get_node("HUD/Root/EndScreen").find_child("MapButton", true, false).pressed.emit()
	await nodes["guest"].get("coop").leave()
	check(await _until(func() -> bool: return _scene_is(MAP)), "the host is back on the map")
	await _until(func() -> bool: return _server.get_at("rooms/" + room["code"]) == null)
	_db_clean(room["code"])
	_no_records()
	nodes["view"].free()


func _test_leave_lobby() -> void:
	print("-- leaving the lobby")
	var room: Dictionary = await _open_room()
	var screen: Node = room["screen"]
	var guest: CoopLobby = room["guest"]
	var closed: Array[String] = []
	guest.closed.connect(func(r: String) -> void: closed.append(r))
	check(
		await _until(func() -> bool: return _label_exists(screen, "Guest: Bob   …")),
		"the host sees the guest"
	)
	await guest.leave()
	var waiting: String = "Waiting for a partner. Tell them the room code."
	var is_waiting := func() -> bool: return _label_exists(screen, waiting)
	check(await _until(is_waiting), "the guest left: the host waits again")
	var again := CoopLobby.new(_guest_net)
	check(
		(await again.join(room["code"], "Bob", Sim.VERSION))["ok"], "the same guest can come back"
	)
	await process_frame
	# Now the host leaves: the guest is told.
	var closes: Array[String] = []
	again.closed.connect(func(r: String) -> void: closes.append(r))
	check(_press(screen, "Leave"), "host: Leave")
	await _until(func() -> bool: return not closes.is_empty())
	check(closes == ["host_left"], "the guest is told the host left: %s" % [closes])
	check(_reason_text("host_left") == "The host closed the room.", "...in words")
	await _until(func() -> bool: return _server.get_at("rooms/" + room["code"]) == null)
	_db_clean(room["code"])
	check(_press(current_scene, "Back"), "host: Back to the map")
	check(await _until(func() -> bool: return _scene_is(MAP)), "the host is on the map")


func _reason_text(reason: String) -> String:
	var script := load("res://scripts/coop_lobby_screen.gd") as GDScript
	return script.call("reason_text", reason)


func _test_partner_leaves_match() -> void:
	print("-- the partner leaves the match")
	var room: Dictionary = await _open_room()
	var nodes: Dictionary = await _start_match(room)
	var host_main: Node = nodes["host"]
	await _play(nodes, 90)
	await nodes["guest"].get("coop").leave()
	var hs: Sim = host_main.get_node("Sim")
	for i in 20:
		hs.advance(1.0 / 30.0)
		await process_frame
	check(bool(host_main.battle_end.ended), "the host's battle ended")
	var message: Label = host_main.get_node("HUD/Root/EndScreen").find_child(
		"MessageLabel", true, false
	)
	check(message.text == "The partner left", "message: %s" % message.text)
	host_main.get_node("HUD/Root/EndScreen").find_child("MapButton", true, false).pressed.emit()
	check(await _until(func() -> bool: return _scene_is(MAP)), "the host is back on the map")
	await _until(func() -> bool: return _server.get_at("rooms/" + room["code"]) == null)
	_db_clean(room["code"])
	check(LevelCatalog.stars(1) == 0, "nothing was saved")
	_no_records()
	nodes["view"].free()


func _test_join_errors() -> void:
	print("-- joining a bad room, through the lobby screen")
	await _goto("res://scenes/coop_lobby.tscn")
	var screen: Node = current_scene
	var host_room := CoopLobby.new(_net("uidOther"))
	var made: Dictionary = await host_room.create(1, "Cy", Sim.VERSION)
	check(made["ok"], "another room exists")
	var old := CoopLobby.new(_net("uidOld"))
	old.clock_ms = func() -> float: return 1.0e12  # an hour long gone
	var old_made: Dictionary = await old.create(1, "Old", Sim.VERSION)
	var full := CoopLobby.new(_net("uidFull"))
	check((await full.join(made["code"], "F", Sim.VERSION))["ok"], "the room has a guest")
	var cases := [
		["22222", "Room not found. Check the code."],
		[made["code"], "The room is full: a partner is already there."],
		[old_made["code"], "The room has expired. Ask your partner to create a new one."],
	]
	for case: Array in cases:
		check(_press(screen, "Join with a code"), "Join with a code")
		for letter in str(case[0]):
			_press(screen, letter)
		_press(screen, "Join")
		await _until(func() -> bool: return screen.call("status_text") not in ["", "Connecting…"])
		await process_frame
		check(screen.call("status_text") == case[1], "status: %s" % case[1])
		check(screen.get("lobby") == null, "...no room entered")
		_press(screen, "Back")
		await process_frame

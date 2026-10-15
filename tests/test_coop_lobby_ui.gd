extends SceneTree
## The co-op lobby screen on an in-memory database: two screens (host and guest)
## make a room, join by code typed on the on-screen keyboard, pick a level,
## get ready and start; every error status of the lobby is shown translated; all
## buttons are at least 84 px; both languages have texts for every key used.
## godot --headless --path . --script res://tests/test_coop_lobby_ui.gd

const Fake := preload("res://tests/fake_rtdb.gd")
const SCREEN_PATH := "res://scenes/coop_lobby.tscn"

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_coop_lobby_ui.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	_run.call_deferred()


func _screen(net: Fake.FakeTransport, nick: String) -> Node:
	var screen: Node = (load(SCREEN_PATH) as PackedScene).instantiate()
	screen.transport = net
	screen.nickname = nick
	screen.auto_load = false
	root.add_child(screen)
	return screen


func _net(server: Fake.FakeServer, uid: String) -> Fake.FakeTransport:
	var net := Fake.FakeTransport.new()
	net.server = server
	net.user_id = uid
	server.clients.append(net)
	return net


func _press(screen: Node, path: String) -> void:
	(screen.get_node(path) as Button).pressed.emit()


func _button_named(screen: Node, text: String) -> Button:
	for node in screen.find_children("*", "Button", true, false):
		if (node as Button).text == text and (node as Button).is_visible_in_tree():
			return node as Button
	return null


func _type(screen: Node, code: String) -> void:
	for letter in code:
		var key: Button = _button_named(screen, letter)
		key.pressed.emit()


func _run() -> void:
	GameSettings.set_language("en")
	var server := Fake.FakeServer.new()
	var host_net: Fake.FakeTransport = _net(server, "uidHost")
	var guest_net: Fake.FakeTransport = _net(server, "uidGuest")
	var host: Node = _screen(host_net, "Ann")
	var guest: Node = _screen(guest_net, "Bob")
	await process_frame

	# Every button is large enough for a thumb (84 px, ~48 dp on a phone).
	var small: Array[String] = []
	for screen: Node in [host, guest]:
		for node in screen.find_children("*", "Button", true, false):
			var button := node as Button
			if button.custom_minimum_size.y < 84.0:
				small.append(button.text)
	check(small.is_empty(), "all buttons >= 84 px tall (%s)" % [small])
	var keys := 0
	for node in guest.find_children("*", "Button", true, false):
		var text: String = (node as Button).text
		if text.length() == 1 and CoopLobby.CODE_ALPHABET.contains(text):
			keys += 1
	check(keys == 32, "32 keys on the on-screen keyboard")

	# Host: a room.
	_find(host, "Create a room").pressed.emit()
	await process_frame
	await process_frame
	check(host.lobby != null, "host is in a room")
	var code: String = host.lobby.code
	var room_code: String = (
		(host.find_children("*", "Label", true, false).filter(
			func(n: Node) -> bool: return (n as Label).text.replace(" ", "") == code
		))[0]
		. text
	)
	check(room_code.replace(" ", "") == code, "the code %s is on the screen" % code)
	check(_find(host, "Start").disabled, "Start is disabled while nobody is in")
	check(_text_exists(host, "Waiting for a partner. Tell them the room code."), "status: waiting")

	# Guest: wrong, short, then the right code.
	_find(guest, "Join with a code").pressed.emit()
	check(_find(guest, "Join").disabled, "Join is disabled with an empty code")
	_type(guest, "ABC")
	check(
		guest.typed_code() == "ABC" and _find(guest, "Join").disabled,
		"3 letters: Join stays disabled"
	)
	_find(guest, "⌫").pressed.emit()
	check(guest.typed_code() == "AB", "backspace")
	_type(guest, "CDE")
	check(guest.typed_code().length() == 5, "no more than 5 symbols")
	_type(guest, "F")
	check(guest.typed_code().length() == 5, "a 6th symbol is ignored")
	var wrong: String = "ZZZZZ" if code != "ZZZZZ" else "YYYYY"
	for i in 5:
		_find(guest, "⌫").pressed.emit()
	_type(guest, wrong)
	_find(guest, "Join").pressed.emit()
	await process_frame
	await process_frame
	check(guest.status_text() == "Room not found. Check the code.", "status: room not found")
	check(guest.lobby == null, "...and still no room")
	for i in 5:
		_find(guest, "⌫").pressed.emit()
	_type(guest, code)
	_find(guest, "Join").pressed.emit()
	await process_frame
	await process_frame
	check(guest.lobby != null, "guest joined with the right code")
	check(_text_exists(guest, "Press Ready when you are ready to fight."), "guest: press Ready")
	check(
		_text_exists(host, "The partner is in. Waiting for them to press Ready."),
		"host sees the partner"
	)
	check(_text_exists(host, "Guest: Bob   …"), "player list shows the guest")

	# A third player finds the room full.
	var third_net: Fake.FakeTransport = _net(server, "uidThird")
	var third: Node = _screen(third_net, "Cy")
	await process_frame
	_find(third, "Join with a code").pressed.emit()
	_type(third, code)
	_find(third, "Join").pressed.emit()
	await process_frame
	await process_frame
	check(
		third.status_text() == "The room is full: a partner is already there.", "status: room full"
	)

	# The level: the host picks, the guest has to accept again.
	_find(guest, "Ready").pressed.emit()
	await process_frame
	await process_frame
	check(not _find(host, "Start").disabled, "host may start when the guest is ready")
	LevelCatalog.complete(1, 3)  # level 2 unlocked
	var before: int = host.lobby.snapshot()["level"]
	_find(host, "▶").pressed.emit()
	await process_frame
	await process_frame
	check(int(host.lobby.snapshot()["level"]) == before + 1, "host picked the next level")
	check(_find(host, "Start").disabled, "a new level: the guest must agree again")
	check(_find(guest, "▶") == null, "the guest cannot change the level")
	_find(guest, "Ready").pressed.emit()
	await process_frame
	await process_frame
	check(not _find(host, "Start").disabled, "ready again: Start is enabled")

	# Start: both get the same battle settings through CoopRun.
	var guest_started: Array[Dictionary] = []
	guest.lobby.started.connect(func(c: Dictionary) -> void: guest_started.append(c))
	_find(host, "Start").pressed.emit()
	await process_frame
	await process_frame
	await process_frame
	check(CoopRun.is_pending(), "the battle settings are handed over")
	var config: Dictionary = CoopRun.config
	check(
		config["level"] == before + 1 and config["partner"] != "" and config["name"] != "",
		(
			"config: level %s, name %s, partner %s"
			% [config["level"], config["name"], config["partner"]]
		)
	)
	check(
		guest_started.size() == 1 and guest_started[0]["seed"] == config["seed"],
		"guest got the same seed"
	)
	check(
		LevelCatalog.selected_id == before + 1 and not LevelCatalog.endless,
		"level selected for the battle"
	)
	CoopRun.clear()

	# Closing: a host that leaves closes the room for the guest.
	await _closing_checks(server)

	# Russian: no raw keys on any screen.
	GameSettings.set_language("ru")
	var ru: Node = _screen(_net(server, "uidRu"), "Аня")
	await process_frame
	var raw: Array[String] = []
	for node in ru.find_children("*", "Label", true, false):
		if (node as Label).text.begins_with("COOP_"):
			raw.append((node as Label).text)
	for node in ru.find_children("*", "Button", true, false):
		if (node as Button).text.begins_with("COOP_"):
			raw.append((node as Button).text)
	check(raw.is_empty(), "russian: no untranslated keys %s" % [raw])
	check(
		_find(ru, "Создать комнату") != null and _find(ru, "Войти по коду") != null, "russian: menu"
	)
	for reason: String in _script().REASON_TEXT:
		var text: String = _script().reason_text(reason)
		if text.begins_with("COOP_"):
			raw.append(reason)
	check(raw.is_empty(), "russian: every reason has a text")
	GameSettings.set_language("en")
	for reason: String in _script().REASON_TEXT:
		if _script().reason_text(reason).begins_with("COOP_"):
			raw.append(reason)
	check(raw.is_empty(), "english: every reason has a text")

	for node in Fake.FakeTransport.all:
		(node as Node).free()
	Fake.FakeTransport.all.clear()
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _script() -> GDScript:
	return load("res://scripts/coop_lobby_screen.gd") as GDScript


func _closing_checks(server: Fake.FakeServer) -> void:
	var host: Node = _screen(_net(server, "uidH2"), "Ann")
	var guest: Node = _screen(_net(server, "uidG2"), "Bob")
	await process_frame
	_find(host, "Create a room").pressed.emit()
	await process_frame
	await process_frame
	var code: String = host.lobby.code
	_find(guest, "Join with a code").pressed.emit()
	_type(guest, code)
	_find(guest, "Join").pressed.emit()
	await process_frame
	await process_frame
	check(guest.lobby != null, "second room: guest in")
	_find(host, "Leave").pressed.emit()
	await process_frame
	await process_frame
	await process_frame
	check(guest.lobby == null, "the host left: the guest's room is closed")
	check(guest.status_text() == "The host closed the room.", "status: the host closed the room")
	check(server.get_at("rooms/%s/meta" % code) == null, "the room is gone from the database")
	var expired := CoopLobby.new(_net(server, "uidX"))
	expired.clock_ms = func() -> float: return float(server.now_ms)
	check((await expired.join("22222", "X", Sim.VERSION))["reason"] == "not_found", "unknown code")


func _find(screen: Node, text: String) -> Button:
	return _button_named(screen, text)


func _text_exists(screen: Node, text: String) -> bool:
	for node in screen.find_children("*", "Label", true, false):
		if (node as Label).text == text and (node as Label).is_visible_in_tree():
			return true
	return false

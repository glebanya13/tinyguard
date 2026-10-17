extends SceneTree
## Co-op in the game: two instances of a level (host and guest) in one process,
## each in its own SubViewport world, joined by an in-memory Realtime Database
## (tests/fake_rtdb.gd). The lobby makes the room, both levels start from its
## settings, a scripted bot plays both sides for 3600 ticks (shared gold, wood
## and lives, one knight each) and the state hashes must match. Then: a silent
## partner, a partner that leaves, a diverging simulation, malformed commands,
## and single player untouched (no Online, pause and speed still work).
## LEVEL=<id> godot --headless --fixed-fps 60 --path . --script res://tests/test_coop_integration.gd

const Fake := preload("res://tests/fake_rtdb.gd")
const TOTAL_TICKS := 3600
const HASH_EVERY := 30
const MAIN_PATH := "res://scenes/main.tscn"
const MAP_PATH := "res://scenes/level_select.tscn"
const SAVE := "user://test_coop_integration.cfg"

var fails := 0
var _level: int = 1


class Peer:
	extends RefCounted
	var slot: int = 0
	var net: Fake.FakeTransport = null
	var lobby: CoopLobby = null
	var view: SubViewport = null
	var main: Node = null
	var sim: Sim = null
	var commands: GameCommands = null
	var hero: Hero = null
	var hud: Hud = null
	var gs: GameState = null
	var trace: Dictionary = {}
	var ends: Array[String] = []
	var last_bot: int = -1
	var sworded: bool = false
	var sold: bool = false
	var target_tree: WoodTree = null


## Loaded at run time: the scripts mention autoloads, which exist only once the tree runs.
func _scene(path: String) -> PackedScene:
	return load(path) as PackedScene


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = SAVE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	# The bot plays: nobody swings by himself.
	node_added.connect(
		func(node: Node) -> void:
			if node is Hero:
				(node as Hero).auto_action = false
	)
	_level = int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1
	LevelCatalog.selected_id = _level
	_run.call_deferred()


func _run() -> void:
	_test_wire_commands()
	await _test_match()
	await _test_silence()
	await _test_partner_leaves()
	await _test_desync()
	await _test_offline_unchanged()
	for node in Fake.FakeTransport.all:
		(node as Node).free()
	Fake.FakeTransport.all.clear()
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


# --- helpers ------------------------------------------------------------------


func _make_net(server: Fake.FakeServer, uid: String) -> Fake.FakeTransport:
	var net := Fake.FakeTransport.new()
	net.server = server
	net.user_id = uid
	server.clients.append(net)
	return net


## Host and guest in a room of the in-memory database, match started.
## Returns [host_side, guest_side] with their `started` configs in `config`.
func _start_room(server: Fake.FakeServer, level: int) -> Array:
	var sides: Array = []
	var configs: Array[Dictionary] = [{}, {}]
	for i in 2:
		var side := Peer.new()
		side.slot = i
		side.net = _make_net(server, "uid%s" % ["Host", "Guest"][i])
		side.lobby = CoopLobby.new(side.net)
		side.lobby.clock_ms = func() -> float: return float(server.now_ms)
		var index: int = i
		side.lobby.started.connect(func(c: Dictionary) -> void: configs[index] = c)
		sides.append(side)
	var host: Peer = sides[0]
	var guest: Peer = sides[1]
	var made: Dictionary = await host.lobby.create(level, "Аня", Sim.VERSION)
	check(made["ok"], "lobby: room created (%s)" % made["code"])
	var joined: Dictionary = await guest.lobby.join(made["code"], "Боб", Sim.VERSION)
	check(joined["ok"], "lobby: guest joined")
	await guest.lobby.set_ready(true)
	check(bool(host.lobby.snapshot()["can_start"]), "lobby: host may start")
	await host.lobby.start_match()
	check(
		not configs[0].is_empty() and not configs[1].is_empty(), "lobby: both sides got `started`"
	)
	check(
		configs[0]["seed"] == configs[1]["seed"] and configs[0]["level"] == level,
		"lobby: one seed and level for both"
	)
	host.set_meta("config", configs[0])
	guest.set_meta("config", configs[1])
	return sides


func _boot_side(side: Peer, names: Array) -> void:
	var config: Dictionary = (side.get_meta("config") as Dictionary).duplicate()
	config["name"] = names[side.slot]
	config["partner"] = names[1 - side.slot]
	side.view = SubViewport.new()
	side.view.own_world_3d = true
	side.view.size = Vector2i(640, 360)
	root.add_child(side.view)
	var main: Node = _scene(MAIN_PATH).instantiate()
	main.set("coop_config", config)
	main.set("coop_transport", side.net)
	main.set("coop_lobby", side.lobby)
	side.view.add_child(main)
	side.main = main
	side.sim = main.get_node("Sim")
	side.sim.manual = true  # the test drives the clock
	side.commands = main.get_node("GameCommands")
	side.hero = main.get_node("Level/Hero")
	side.hud = main.get_node("HUD")
	side.gs = main.get_node("GameState")
	side.sim.ticked.connect(
		func(t: int) -> void:
			if t % HASH_EVERY == 0:
				side.trace[t] = side.sim.state_hash()
	)
	side.sim.coop.session.ended.connect(func(r: String) -> void: side.ends.append(r))
	side.sim.coop.session.lockstep.protocol_error.connect(
		func(why: String) -> void:
			print("    protocol error on slot %d: %s at tick %d" % [side.slot, why, side.sim.tick])
	)


func _wait_ready(sides: Array) -> void:
	for i in 300:
		var all_ready := true
		for side: Peer in sides:
			all_ready = all_ready and side.sim.running
		if all_ready:
			return
		await process_frame


func _start_match_pair(level: int, server: Fake.FakeServer = null) -> Array:
	paused = false
	var db: Fake.FakeServer = server if server != null else Fake.FakeServer.new()
	LevelCatalog.selected_id = level
	var sides: Array = await _start_room(db, level)
	for side: Peer in sides:
		await _boot_side(side, ["Аня", "Боб"])
	await _wait_ready(sides)
	return sides


func _free_sides(sides: Array) -> void:
	for side: Peer in sides:
		if is_instance_valid(side.view):
			side.view.free()
	paused = false
	Engine.time_scale = 1.0


## One frame of both sides: the bots decide, then each clock gets 1/30 s.
func _step_pair(sides: Array, with_bot: bool) -> void:
	for side: Peer in sides:
		if with_bot and side.sim.tick != side.last_bot and side.sim.tick % 5 == 0:
			side.last_bot = side.sim.tick
			_bot(side)
	for side: Peer in sides:
		side.sim.advance(1.0 / 30.0)


## Plays until both clocks are at `ticks` (or a guard runs out).
func _play(sides: Array, ticks: int, with_bot: bool = true) -> int:
	var iterations: int = 0
	var limit: int = ticks * 4
	while iterations < limit:
		var done := true
		for side: Peer in sides:
			done = done and side.sim.tick >= ticks
		if done:
			break
		_step_pair(sides, with_bot)
		iterations += 1
		if iterations % 30 == 0:
			await process_frame
	return iterations


# --- the bot ------------------------------------------------------------------


## Walks the knight (by hand: the test has no input) and plays through commands.
func _bot(side: Peer) -> void:
	var sim: Sim = side.sim
	var commands: GameCommands = side.commands
	var hero: Hero = side.hero
	var bm: BuildManager = side.main.get_node("BuildManager")
	var t: int = sim.tick
	# Wood first: walk to a tree and swing.
	if side.gs.wood < 60:
		if side.target_tree == null or not side.target_tree.is_choppable():
			side.target_tree = _nearest_tree(sim, hero)
		if side.target_tree != null:
			var goal: Vector3 = side.target_tree.global_position
			var offset: Vector3 = goal - hero.global_position
			offset.y = 0.0
			if offset.length() > 1.0:
				hero.global_position += (
					offset.normalized() * minf(hero.speed * 5.0 / 30.0 * 0.8, offset.length() - 0.9)
				)
			else:
				hero.try_attack()
	# One whirlwind when slimes come (the guest) and a build / upgrade decision.
	if side.slot == 1 and not sim.enemies.is_empty() and hero.spin_cooldown_left() <= 0.0:
		hero.try_spin()
	if t % 10 == 0:
		for slot in commands.slots:
			if slot.slot_id % 2 != side.slot:
				continue  # each player takes his half of the plots
			var kind: int = (slot.slot_id / 2) % bm.tower_types.size()
			if slot.is_free() and bm.can_build(slot, bm.tower_types[kind]):
				commands.submit(GameCommand.build(slot.slot_id, kind))
				break
			if not slot.is_free() and t % 60 == 0 and bm.can_upgrade(slot):
				commands.submit(GameCommand.upgrade(slot.slot_id))
				break
	# The villagers' wood economy travels as commands too: both players try to hire the same
	# villager in the same tick (the second hire is refused everywhere alike), the guest hires
	# the other one later and each buys a lot of wood.
	if t == 5:
		commands.submit(GameCommand.hire(0))
	if side.slot == 1 and t == 10:
		commands.submit(GameCommand.hire(1))
	if (side.slot == 0 and t == 5) or (side.slot == 1 and t % 100 == 10):
		if side.main.villagers.lots_bought < 2:
			commands.submit(GameCommand.trade_buy(1))
	# Target priority is a command that travels between the players too.
	if t >= 600 and t % 150 == 0:
		for slot in commands.slots:
			if slot.slot_id % 2 == side.slot and not slot.is_free():
				commands.submit(
					GameCommand.set_priority(slot.slot_id, (slot.tower.priority + 1) % 4)
				)
				break
	if side.slot == 1 and t == 1500 and not side.sold and not commands.slots[1].is_free():
		side.sold = true
		commands.submit(GameCommand.sell(1))
	if not side.sworded and t > 800 and side.gs.can_afford(hero.sword_upgrade_cost()):
		side.sworded = true
		commands.submit(GameCommand.sword())
	if side.slot == 1 and t % 90 == 0 and side.gs.wood >= 40:
		commands.submit(GameCommand.trade(1))
	if side.gs.lives < side.gs.starting_lives and side.gs.wood >= side.gs.repair_wood:
		commands.submit(GameCommand.repair())


func _nearest_tree(sim: Sim, hero: Hero) -> WoodTree:
	var best: WoodTree = null
	var best_d: float = INF
	for tree in sim.trees:
		var d: float = tree.global_position.distance_to(hero.global_position)
		if tree.is_choppable() and d < best_d:
			best_d = d
			best = tree
	return best


# --- tests --------------------------------------------------------------------


func _test_wire_commands() -> void:
	print("-- wire commands")
	check(
		GameCommand.from_wire("build", [3], 1, 0) == null, "build with a missing argument refused"
	)
	check(GameCommand.from_wire("sword", [1], 1, 0) == null, "sword with an extra argument refused")
	check(GameCommand.from_wire("buy_wood", [], 1, 0) == null, "buy_wood needs its lots")
	check(
		GameCommand.from_wire("hire", [0, 1], 1, 0) == null, "hire with an extra argument refused"
	)
	var bought: GameCommand = GameCommand.from_wire("buy_wood", [3], 1, 9)
	check(
		bought != null and bought.type == GameCommand.Type.TRADE_BUY and bought.args == [3],
		"buy_wood travels"
	)
	var hired: GameCommand = GameCommand.from_wire("hire", [1], 0, 9)
	check(hired != null and hired.type == GameCommand.Type.HIRE, "hire travels")
	check(
		(
			CoopProtocol.is_valid_command(9, "buy_wood", [2])
			and CoopProtocol.is_valid_command(9, "hire", [0])
		),
		"the protocol knows the new commands"
	)
	check(GameCommand.from_wire("pause", [1], 1, 0) == null, "pause never travels")
	check(GameCommand.from_wire("speed", [2], 1, 0) == null, "speed never travels")
	check(GameCommand.from_wire("nope", [], 1, 0) == null, "unknown command refused")
	var cmd: GameCommand = GameCommand.from_wire("attack", [1000, -2000, 1570], 1, 42)
	check(
		(
			cmd != null
			and cmd.player == 1
			and cmd.tick == 42
			and cmd.type == GameCommand.Type.HERO_ATTACK
		),
		"attack decoded with slot and tick"
	)
	check(GameCommand.build(2, 1).wire_name() == "build", "build -> wire name")
	check(GameCommand.set_pause(true).wire_name() == "", "pause has no wire name")


func _test_match() -> void:
	print("-- co-op match: %d ticks, bots on both sides (level %d)" % [TOTAL_TICKS, _level])
	var server := Fake.FakeServer.new()
	var sides: Array = await _start_match_pair(_level, server)
	var host: Peer = sides[0]
	var guest: Peer = sides[1]
	check(host.sim.running and guest.sim.running, "both levels ready")
	check(host.sim.coop != null and guest.sim.coop != null, "both clocks are in lockstep")
	check(host.sim.seed_value == guest.sim.seed_value, "same seed (%d)" % host.sim.seed_value)
	check(
		(
			host.commands.journal.header == guest.commands.journal.header
			and int(host.commands.journal.header.get("coop", 0)) == 1
		),
		"same journal header (co-op, level, seed)"
	)
	var perks: Dictionary = host.commands.journal.header["perks"]
	var zero := true
	for key: String in perks:
		zero = zero and float(perks[key]) == 0.0
	check(zero, "perks are zero in the header (an even start)")
	check(host.gs.gold == guest.gs.gold and host.gs.lives == guest.gs.lives, "shared start kit")
	check(host.commands.validate_hero and guest.commands.validate_hero, "hero validation is on")
	check(
		host.sim.heroes.size() == 2 and host.sim.heroes[0] == host.hero, "host: knights [me, ghost]"
	)
	check(
		guest.sim.heroes.size() == 2 and guest.sim.heroes[1] == guest.hero,
		"guest: knights [ghost, me]"
	)
	var tag: Label3D = host.main.get_node("Level/PartnerHero").get_child(-1)
	check(tag is Label3D and tag.text == "Боб", "partner's name above the ghost knight")

	# Pause and speed are not shared.
	check(not host.commands.submit(GameCommand.set_pause(true)), "co-op: pause command refused")
	check(not host.commands.submit(GameCommand.set_speed(2)), "co-op: speed command refused")
	host.main.call("_toggle_pause")
	check(not paused and not host.sim.paused, "pause menu does not stop the battle")
	check(host.main.get("_coop_menu_open") == true, "...it only covers the screen")
	host.main.call("_toggle_pause")
	check(not Engine.time_scale > 1.0, "no x2 in co-op")

	var hero_start: Vector3 = host.hero.global_position
	await _play(sides, TOTAL_TICKS)
	var ha: Dictionary = host.trace
	var ga: Dictionary = guest.trace
	var same := 0
	var first_diff := -1
	var common := 0
	for t: int in ha:
		if ga.has(t):
			common += 1
			if ha[t] == ga[t]:
				same += 1
			elif first_diff < 0:
				first_diff = t
	print(
		"    ticks: host %d, guest %d, hashes compared %d" % [host.sim.tick, guest.sim.tick, common]
	)
	check(host.sim.tick >= TOTAL_TICKS and guest.sim.tick >= TOTAL_TICKS, "3600 ticks played")
	check(common >= TOTAL_TICKS / HASH_EVERY - 2, "hash trace on both sides (%d)" % common)
	check(same == common, "every hash equal at the same tick (first mismatch %d)" % first_diff)
	check(
		host.ends.is_empty() and guest.ends.is_empty(),
		"no session ended: %s %s" % [host.ends, guest.ends]
	)
	check(
		absi(host.sim.tick - guest.sim.tick) <= host.sim.coop.session.lockstep.delay + 2,
		"clocks within the input delay"
	)
	if host.sim.tick == guest.sim.tick:
		check(host.sim.state_hash() == guest.sim.state_hash(), "final state hash equal")
		check(
			(
				[host.gs.gold, host.gs.wood, host.gs.lives]
				== [guest.gs.gold, guest.gs.wood, guest.gs.lives]
			),
			"shared gold / wood / lives equal"
		)
	var jh: Array = host.commands.journal.commands
	var jg: Array = guest.commands.journal.commands
	var by_player := [0, 0]
	var kinds := {}
	for cmd: GameCommand in jh:
		by_player[cmd.player] += 1
		kinds[cmd.type] = true
	print(
		(
			"    journal: %d commands (host %d, guest %d), kinds %d"
			% [jh.size(), by_player[0], by_player[1], kinds.size()]
		)
	)
	check(by_player[0] >= 10 and by_player[1] >= 10, "commands of BOTH players were applied")
	check(
		(
			kinds.size() >= 5
			and kinds.has(GameCommand.Type.BUILD)
			and kinds.has(GameCommand.Type.HERO_ATTACK)
		),
		"many kinds of commands (%d)" % kinds.size()
	)
	var hires: Array[int] = []
	var buyers: Array[int] = []
	for cmd: GameCommand in jh:
		if cmd.type == GameCommand.Type.HIRE:
			hires.append(cmd.args[0])
		elif cmd.type == GameCommand.Type.TRADE_BUY:
			buyers.append(cmd.player)
	check(
		hires == [0, 1], "hired villagers 0 and 1, the double hire of 0 was refused: %s" % [hires]
	)
	check(
		buyers.size() == 2 and buyers.has(0) and buyers.has(1),
		"both players bought wood: %s" % [buyers]
	)
	var folk_h: Villagers = host.main.villagers
	var folk_g: Villagers = guest.main.villagers
	check(
		folk_h.wood_economy and folk_g.wood_economy and folk_h.hired_count() == 2,
		"co-op allows the wood economy: %d hired" % folk_h.hired_count()
	)
	check(
		folk_h.lots_bought == folk_g.lots_bought and folk_h.state_ints() == folk_g.state_ints(),
		"villager economy equal on both sides (%d lots)" % folk_h.lots_bought
	)
	check(ha[HASH_EVERY * 10] != ha[HASH_EVERY * 100], "the state changes over time")
	var same_prefix := true
	for i in mini(jh.size(), jg.size()):
		if jh[i].to_array() != jg[i].to_array():
			same_prefix = false
	check(same_prefix and absi(jh.size() - jg.size()) <= 6, "journals agree command by command")
	var slots_h: Array[int] = []
	for tower in host.sim.towers:
		slots_h.append(tower.id)
	check(host.sim.towers.size() >= 2, "towers stand (%d), built by both" % host.sim.towers.size())
	var wm: WaveManager = host.main.get_node("WaveManager")
	check(wm.killed > 0, "a battle happened (%d kills, wave %d)" % [wm.killed, wm.current_wave])
	var ghost: Hero = host.main.get("coop").ghost
	var moved: bool = ghost.position.distance_to(host.hero.position) > 0.3
	check(moved or by_player[1] > 0, "the ghost knight shows the partner")
	check(
		(
			hero_start.distance_to(host.hero.global_position) >= 0.0
			and guest.hero.global_position != hero_start
		),
		"both knights moved by their own players"
	)
	check(
		not host.hud.is_coop_notice_visible() and not guest.hud.is_coop_notice_visible(),
		"no 'waiting for the partner' notice during a good match"
	)
	# Stars: the usual local record, nothing online.
	check(LevelCatalog.endless_record(_level) == 0, "no endless record written")
	_free_sides(sides)


func _test_silence() -> void:
	print("-- a silent partner")
	var sides: Array = await _start_match_pair(_level)
	var host: Peer = sides[0]
	var guest: Peer = sides[1]
	await _play(sides, 120)
	check(host.ends.is_empty(), "play goes on")
	guest.net.set_online(false)  # the guest's phone loses the network
	var seconds: float = 0.0
	var tick_before: int = host.sim.tick
	while seconds < 11.0:
		host.sim.advance(1.0 / 30.0)
		seconds += 1.0 / 30.0
	check(
		host.sim.tick - tick_before <= host.sim.coop.session.lockstep.delay + 1,
		"host waits (stalled)"
	)
	check(host.hud.is_coop_notice_visible(), "after 10 s: 'waiting for the partner' overlay")
	check(host.ends.is_empty(), "...the match is not over yet")
	# The partner comes back.
	guest.net.set_online(true)
	for i in 90:
		_step_pair(sides, false)
		if i % 30 == 0:
			await process_frame
	check(not host.hud.is_coop_notice_visible(), "the overlay goes away when the partner is back")
	check(host.sim.tick > tick_before + 15, "the battle goes on after the pause")
	check(host.ends.is_empty() and guest.ends.is_empty(), "no end after a short drop")
	# And now for good.
	guest.net.set_online(false)
	seconds = 0.0
	while seconds < 31.0:
		host.sim.advance(1.0 / 30.0)
		seconds += 1.0 / 30.0
	check(host.ends == ["lost"], "after 30 s the match ends: %s" % [host.ends])
	check(bool(host.main.battle_end.ended), "battle screen shows the end")
	var message: Label = host.main.get_node("HUD/Root/EndScreen/EndPanel/Content/MessageLabel")
	check(message.text == TranslationServer.translate("COOP_END_LOST"), "message: connection lost")
	check(LevelCatalog.stars(_level) == 0, "nothing was saved for the cut match")
	_free_sides(sides)


func _test_partner_leaves() -> void:
	print("-- the partner leaves")
	var sides: Array = await _start_match_pair(_level)
	var host: Peer = sides[0]
	var guest: Peer = sides[1]
	await _play(sides, 150)
	await guest.main.get("coop").leave()
	for i in 5:
		host.sim.advance(1.0 / 30.0)
		await process_frame
	check(host.ends == ["partner_left"], "host heard the farewell: %s" % [host.ends])
	check(bool(host.main.battle_end.ended), "host sees the end screen")
	var message: Label = host.main.get_node("HUD/Root/EndScreen/EndPanel/Content/MessageLabel")
	check(message.text == TranslationServer.translate("COOP_END_LEFT"), "message: partner left")
	var left: Variant = server_value(
		host, "rooms/%s/net/guest" % host.main.get("coop_config")["code"]
	)
	check(left == null, "the guest's own messages are gone from the database")
	check(LevelCatalog.stars(_level) == 0, "nothing saved")
	_free_sides(sides)


func server_value(side: Peer, path: String) -> Variant:
	return side.net.server.get_at(path)


func _test_desync() -> void:
	print("-- a diverging simulation")
	var sides: Array = await _start_match_pair(_level)
	var host: Peer = sides[0]
	var guest: Peer = sides[1]
	await _play(sides, 100, false)
	check(host.ends.is_empty() and guest.ends.is_empty(), "in sync so far")
	guest.gs.add_gold(7)  # a bug: only the guest's state changed
	await _play(sides, 200, false)
	check(
		host.ends == ["desync"] and guest.ends == ["desync"],
		"both sides see it: %s %s" % [host.ends, guest.ends]
	)
	check(
		host.sim.tick <= 130 and guest.sim.tick <= 130,
		"the match stopped at the first checkpoint (%d, %d)" % [host.sim.tick, guest.sim.tick]
	)
	for side: Peer in sides:
		var message: Label = side.main.get_node("HUD/Root/EndScreen/EndPanel/Content/MessageLabel")
		check(
			message.text == TranslationServer.translate("COOP_END_DESYNC"),
			"message on slot %d" % side.slot
		)
	check(LevelCatalog.stars(_level) == 0, "saves untouched after a desync")
	_free_sides(sides)


func _test_offline_unchanged() -> void:
	print("-- single player and the map are untouched")
	paused = false
	var main: Node = _scene(MAIN_PATH).instantiate()
	root.add_child(main)
	var sim: Sim = main.get_node("Sim")
	sim.manual = true
	for i in 200:
		if sim.running:
			break
		await process_frame
	var commands: GameCommands = main.get_node("GameCommands")
	check(sim.coop == null and commands.coop == null and sim.heroes.is_empty(), "no co-op wiring")
	check(main.get_node_or_null("Level/PartnerHero") == null, "no ghost knight")
	check(commands.submit(GameCommand.set_speed(2)) and sim.speed == 2, "x2 works")
	check(commands.submit(GameCommand.set_pause(true)) and sim.paused, "pause works")
	commands.submit(GameCommand.set_pause(false))
	commands.submit(GameCommand.set_speed(1))
	paused = false
	check(not commands.validate_hero, "no hero validation in single player")
	main.free()
	Engine.time_scale = 1.0
	# The map: no co-op button without a database.
	var online: Node = root.get_node("Online")
	check(online.get("rtdb") == null, "tests run without a configured database")
	var map: Node = _scene(MAP_PATH).instantiate()
	root.add_child(map)
	await process_frame
	check(
		map.find_child("CoopButton", true, false) == null,
		"map: no co-op button without database_url"
	)
	map.free()
	online.set("rtdb", RtdbClient.new())
	var map2: Node = _scene(MAP_PATH).instantiate()
	root.add_child(map2)
	await process_frame
	var button: Button = map2.find_child("CoopButton", true, false) as Button
	check(
		button != null and button.custom_minimum_size.y >= 84.0,
		"map: co-op button (>= 84 px) with a database"
	)
	map2.free()
	(online.get("rtdb") as Node).free()
	online.set("rtdb", null)

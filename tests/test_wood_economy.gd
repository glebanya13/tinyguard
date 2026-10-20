extends SceneTree
## Wood economy of the villagers (docs/ECONOMY_V2.md, stage 1): buying wood (price grows,
## a few lots a battle, a round trip with selling always loses gold), hiring lumberjacks
## (wood only, whole ticks), the modes (campaign and co-op yes, Record Run and daily no),
## the trade card, and old journals that know nothing of it. Replays of a journal full of
## purchases and hires: tests/test_replay.gd; co-op: tests/test_coop_integration.gd.
## LEVEL=<id> godot --headless --fixed-fps 60 --path . --script res://tests/test_wood_economy.gd

## A journal recorded before TRADE_BUY and HIRE existed (sim_version 1). It must play on and
## end in the state hash it always had; the golden number was taken before the change.
const LEGACY_JOURNAL := (
	'{"header":{"sim_version":1,"tick_rate":30,"level":1,"endless":false,"seed":12345,'
	+ '"perks":{}},"commands":[[0,0,0,0,0],[30,0,0,1,1],[60,0,10,0,2],[200,0,0,2,2]]}'
)
const LEGACY_HASH := -3468069466603712493
const LEGACY_TOWERS := 2

var fails := 0
var _level: int = 1


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_wood_economy.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	node_added.connect(
		func(node: Node) -> void:
			if node is Hero:
				(node as Hero).auto_action = false
	)
	_level = int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1
	LevelCatalog.selected_id = _level
	_run.call_deferred()


func _load_level() -> Node:
	for i in 3:
		await process_frame
	paused = false
	var old_scene: Node = current_scene
	change_scene_to_file("res://scenes/main.tscn")
	var sim: Sim = null
	while sim == null:
		await process_frame
		if current_scene != null and current_scene != old_scene and current_scene.has_node("Sim"):
			sim = current_scene.get_node("Sim")
	sim.manual = true
	sim.set_seed(12345)
	for i in 200:
		if sim.running:
			break
		await process_frame
	return current_scene


func _steps(sim: Sim, steps: int) -> void:
	for i in steps:
		sim.step()


func _run() -> void:
	_test_numbers()
	await _test_commands()
	await _test_production()
	await _test_card()
	await _test_modes()
	await _test_legacy_journal()
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


## The numbers of resources/villager_trade.tres and the round-trip rule.
func _test_numbers() -> void:
	print("-- numbers")
	var trade: VillagerTrade = load("res://resources/villager_trade.tres")
	check(trade.wood_per_lot == 10, "a lot is 10 wood")
	check(trade.buy_lot_gold(0) == 14, "first bought lot: 14 gold (%d)" % trade.buy_lot_gold(0))
	check(trade.buy_max_lots == 6, "at most 6 lots a battle")
	check(
		trade.hire_gold == 25 and trade.hire_max == 2 and trade.hire_wood_per_minute == 5,
		"lumberjack: 25 gold, 2 at most, 5 wood a minute"
	)
	var prices: Array[int] = []
	for i in trade.buy_max_lots:
		prices.append(trade.buy_lot_gold(i))
	var rises := true
	for i in range(1, prices.size()):
		rises = rises and prices[i] > prices[i - 1]
	check(rises, "the price rises with every lot %s" % [prices])
	check(
		trade.buy_quote(0, 6) == prices.reduce(func(a: int, b: int) -> int: return a + b),
		"six lots cost %d" % trade.buy_quote(0, 6)
	)
	# Round trip: buy a lot at any point, sell a lot at any point of the sale curve.
	var worst: int = 1000
	for bought in trade.buy_max_lots:
		for sold in 60:
			worst = mini(worst, trade.buy_lot_gold(bought) - trade.lot_gold(sold))
	check(worst >= 8, "buying a lot and selling one back loses at least 8 gold (%d)" % worst)
	# Production is a whole number of ticks.
	check(
		trade.chop_accum_limit() % trade.hire_wood_per_minute == 0,
		(
			"5 wood a minute is a whole number of ticks per wood (%d)"
			% (trade.chop_accum_limit() / trade.hire_wood_per_minute)
		)
	)


## Buying, hiring and their refusals, through the command path.
func _test_commands() -> void:
	print("-- commands (level %d)" % _level)
	var main: Node = await _load_level()
	var sim: Sim = main.get_node("Sim")
	var commands: GameCommands = main.get_node("GameCommands")
	var gs: GameState = main.get_node("GameState")
	var folk: Villagers = main.villagers
	var trade: VillagerTrade = folk.trade
	check(folk.wood_economy, "the wood economy is on in a campaign battle")
	check(folk.get_villagers().size() >= 2, "two villagers to hire")

	# Buying.
	var start_wood: int = gs.wood
	gs.gold = 0
	var journal_size: int = commands.journal.commands.size()
	check(not commands.submit(GameCommand.trade_buy(1)), "no gold: buying refused")
	check(commands.journal.commands.size() == journal_size, "a refused purchase is not journaled")
	check(not commands.submit(GameCommand.trade_buy(0)), "zero lots refused")
	check(not commands.submit(GameCommand.trade_buy(-3)), "negative lots refused")
	check(folk.lots_bought == 0 and gs.wood == start_wood, "nothing changed")
	gs.gold = 1000
	var wood: int = gs.wood
	var first_price: int = trade.buy_lot_gold(0)
	check(commands.submit(GameCommand.trade_buy(1)), "a lot is bought")
	check(
		gs.gold == 1000 - first_price and gs.wood == wood + trade.wood_per_lot,
		"paid %d gold, got %d wood" % [first_price, trade.wood_per_lot]
	)
	check(folk.lots_bought == 1, "one lot counted")
	check(
		folk.buy_price() == trade.buy_lot_gold(1) and folk.buy_price() > first_price,
		"the next lot is dearer"
	)
	check(commands.journal.commands.size() == journal_size + 1, "the purchase is journaled")
	var before: int = gs.gold
	check(commands.submit(GameCommand.trade_buy(50)), "asking for more buys what is allowed")
	check(folk.lots_bought == trade.buy_max_lots, "stops at the limit (%d lots)" % folk.lots_bought)
	check(
		before - gs.gold == trade.buy_quote(1, trade.buy_max_lots - 1), "paid the quote of the rest"
	)
	var after_limit: int = gs.gold
	check(not commands.submit(GameCommand.trade_buy(1)), "the limit of 6 lots a battle holds")
	check(gs.gold == after_limit and folk.buy_lots_left() == 0, "no gold taken over the limit")

	# Gold that covers only part of the request.
	main = await _load_level()
	sim = main.get_node("Sim")
	commands = main.get_node("GameCommands")
	gs = main.get_node("GameState")
	folk = main.villagers
	gs.gold = trade.buy_lot_gold(0) + trade.buy_lot_gold(1) + 1
	wood = gs.wood
	check(commands.submit(GameCommand.trade_buy(5)), "short of gold: buys what it can")
	check(folk.lots_bought == 2 and gs.gold == 1, "two lots, %d gold left" % gs.gold)
	check(gs.wood == wood + 2 * trade.wood_per_lot, "two lots of wood arrived")

	# Round trip on a fresh battle: buy a lot, sell it back.
	main = await _load_level()
	commands = main.get_node("GameCommands")
	gs = main.get_node("GameState")
	folk = main.villagers
	gs.gold = 500
	gs.wood = 0
	commands.submit(GameCommand.trade_buy(1))
	commands.submit(GameCommand.trade(1))
	check(gs.wood == 0, "the lot went back to the villager")
	check(500 - gs.gold >= 8, "buy and sell back lost %d gold (at least 8)" % (500 - gs.gold))

	# Hiring.
	main = await _load_level()
	sim = main.get_node("Sim")
	commands = main.get_node("GameCommands")
	gs = main.get_node("GameState")
	folk = main.villagers
	gs.gold = 24
	check(not commands.submit(GameCommand.hire(0)), "24 gold: hiring refused")
	check(folk.hired_count() == 0 and gs.gold == 24, "nothing changed")
	gs.gold = 100
	check(not commands.submit(GameCommand.hire(-1)), "no such villager (-1)")
	check(
		not commands.submit(GameCommand.hire(folk.get_villagers().size())), "no such villager (n)"
	)
	check(commands.submit(GameCommand.hire(0)), "villager 0 is hired")
	check(gs.gold == 100 - trade.hire_gold and folk.is_hired(0), "paid %d gold" % trade.hire_gold)
	check(folk.get_villagers()[0].is_lumberjack(), "he swings an axe now (visual)")
	check(not commands.submit(GameCommand.hire(0)), "the same villager cannot be hired twice")
	check(gs.gold == 100 - trade.hire_gold, "the repeated hire cost nothing")
	var saved_max: int = trade.hire_max
	trade.hire_max = 1
	check(not commands.submit(GameCommand.hire(1)), "the limit of lumberjacks holds")
	trade.hire_max = saved_max
	check(commands.submit(GameCommand.hire(1)), "villager 1 is hired")
	check(folk.hired_count() == 2, "two lumberjacks")
	check(gs.gold == 100 - 2 * trade.hire_gold, "lumberjacks never pay gold back")
	var live: Array = commands.journal.commands
	check(live[live.size() - 1].type == GameCommand.Type.HIRE, "the hire is journaled")


## Wood from lumberjacks: whole pieces on whole ticks, wood only, never gold.
func _test_production() -> void:
	print("-- production")
	var main: Node = await _load_level()
	var sim: Sim = main.get_node("Sim")
	var commands: GameCommands = main.get_node("GameCommands")
	var gs: GameState = main.get_node("GameState")
	var folk: Villagers = main.villagers
	var trade: VillagerTrade = folk.trade
	var per_wood: int = trade.chop_accum_limit() / trade.hire_wood_per_minute  # ticks per wood
	check(per_wood == 360, "one lumberjack: one wood per 360 ticks (12 s)")
	var hash_idle: int = sim.state_hash()
	var wood: int = gs.wood
	var gold: int = gs.gold
	_steps(sim, 3 * per_wood)
	check(gs.wood == wood, "nobody hired: no wood from villagers")
	gs.gold = 200
	commands.submit(GameCommand.hire(0))
	wood = gs.wood
	gold = gs.gold
	var hash_hired: int = sim.state_hash()
	check(hash_hired != hash_idle, "the hash knows about the lumberjack")
	_steps(sim, per_wood - 1)
	check(gs.wood == wood, "359 ticks: no wood yet")
	_steps(sim, 1)
	check(gs.wood == wood + 1, "tick 360: exactly one wood")
	_steps(sim, 9 * per_wood)
	check(gs.wood == wood + 10, "10 wood in 2 minutes (%d)" % (gs.wood - wood))
	check(gs.gold == gold, "no gold from a lumberjack")
	commands.submit(GameCommand.hire(1))
	wood = gs.wood
	_steps(sim, 3600)
	check(gs.wood == wood + 20, "two lumberjacks: 20 wood in 2 minutes (%d)" % (gs.wood - wood))
	# The accumulator is part of the state: same ticks, different phase, different hash.
	var phase_a: int = sim.state_hash()
	var main2: Node = await _load_level()
	var sim2: Sim = main2.get_node("Sim")
	main2.get_node("GameState").gold = 200
	main2.get_node("GameCommands").submit(GameCommand.hire(0))
	_steps(sim2, 100)
	var h100: int = sim2.state_hash()
	var folk2: Villagers = main2.villagers
	var ints: Array[int] = folk2.state_ints()
	check(
		ints.size() == 1 + 2 * folk2.get_villagers().size(), "state ints: lots, then per villager"
	)
	check(ints[1] == 1 and ints[2] == 100 * trade.hire_wood_per_minute, "progress is an integer")
	_steps(sim2, 1)
	check(sim2.state_hash() != h100, "progress changes the hash")
	check(phase_a != 0, "hash computed")


## The trade card: buttons, prices, the limits shown, and pressing them.
func _test_card() -> void:
	print("-- card")
	var main: Node = await _load_level()
	var sim: Sim = main.get_node("Sim")
	var gs: GameState = main.get_node("GameState")
	var folk: Villagers = main.villagers
	var trade: VillagerTrade = folk.trade
	var list: Array[Villager] = folk.get_villagers()
	gs.gold = 100
	var info: Dictionary = CommandCards.trade(folk, gs, list[0])
	var ids: Array[String] = []
	for spec: Dictionary in info["buttons"]:
		ids.append(String(spec["id"]))
	check(
		ids == ["trade_lot", "trade_all", "buy_lot", "buy_all", "hire", "cancel"],
		"card buttons %s" % [ids]
	)
	var by_id := {}
	for spec: Dictionary in info["buttons"]:
		by_id[String(spec["id"])] = spec
	check(by_id["buy_lot"]["gold"] == 14 and by_id["buy_lot"]["enabled"], "buy a lot: 14 gold")
	check(by_id["hire"]["gold"] == 25 and by_id["hire"]["enabled"], "hire: 25 gold")
	check(
		by_id["buy_all"]["gold"] == trade.buy_quote(0, folk.buy_lots_affordable()),
		"buy all shows the quote of what 100 gold allows"
	)
	check((info["hint"] as String).contains("0/6"), "the hint shows the lots: %s" % info["hint"])
	# Pressing through the card controller, with the knight next to a villager.
	var hero: Hero = main.get_node("Level/Hero")
	var v0: Villager = list[0]
	for other: Villager in list:
		if other != v0:
			other.global_position += Vector3(200.0, 0.0, 200.0)
	hero.global_position = v0.global_position + Vector3(0.8, 0.0, 0.0)
	await process_frame
	await process_frame
	check(main.cards.trade_with == v0, "the card opens next to a villager")
	var wood: int = gs.wood
	main.cards.on_command_pressed(&"buy_lot")
	check(gs.wood == wood + 10 and folk.lots_bought == 1, "the card buys a lot")
	main.cards.on_command_pressed(&"buy_all")
	check(folk.lots_bought > 1, "the card buys what it can (%d lots)" % folk.lots_bought)
	gs.gold = 100
	main.cards.on_command_pressed(&"hire")
	check(folk.is_hired(folk.index_of(v0)), "the card hires this villager")
	info = CommandCards.trade(folk, gs, v0)
	by_id.clear()
	for spec: Dictionary in info["buttons"]:
		by_id[String(spec["id"])] = spec
	check(
		not by_id["hire"]["enabled"] and by_id["hire"].has("label") and info["title"] != "Житель",
		"a hired villager shows 'hired' and a new title (%s)" % info["title"]
	)
	gs.gold = 500
	for i in 10:
		main.cards.on_command_pressed(&"buy_lot")
	info = CommandCards.trade(folk, gs, v0)
	by_id.clear()
	for spec: Dictionary in info["buttons"]:
		by_id[String(spec["id"])] = spec
	check(
		not by_id["buy_lot"]["enabled"] and by_id["buy_lot"]["label"] == "6/6",
		"at the limit the card says 6/6"
	)
	check(sim.tick == 0 or sim.tick > 0, "clock exists")


## Record Run and daily challenge: no buying, no hiring, and nothing is journaled.
func _test_modes() -> void:
	print("-- modes")
	for mode in ["record", "daily"]:
		LevelCatalog.endless = mode == "record"
		LevelCatalog.daily_key = "2026-10-17" if mode == "daily" else ""
		var main: Node = await _load_level()
		var commands: GameCommands = main.get_node("GameCommands")
		var gs: GameState = main.get_node("GameState")
		var folk: Villagers = main.villagers
		gs.gold = 500
		var size: int = commands.journal.commands.size()
		check(not folk.wood_economy, "%s: the wood economy is off" % mode)
		check(not commands.submit(GameCommand.trade_buy(1)), "%s: buying refused" % mode)
		check(not commands.submit(GameCommand.hire(0)), "%s: hiring refused" % mode)
		check(
			gs.gold == 500 and folk.lots_bought == 0 and folk.hired_count() == 0,
			"%s: nothing changed" % mode
		)
		check(commands.journal.commands.size() == size, "%s: nothing journaled" % mode)
		check(folk.state_ints().is_empty(), "%s: the hash is what it always was" % mode)
		var info: Dictionary = CommandCards.trade(folk, gs, folk.get_villagers()[0])
		var ids: Array[String] = []
		for spec: Dictionary in info["buttons"]:
			ids.append(String(spec["id"]))
		check(
			ids == ["trade_lot", "trade_all", "cancel"],
			"%s: card without buy/hire %s" % [mode, ids]
		)
		check(
			info["hint"] == TranslationServer.translate("CARD_TRADE_NO_ECONOMY"),
			"%s: the card says why" % mode
		)
		check(
			commands.submit(GameCommand.trade(1)) == (gs.wood >= 10),
			"%s: selling still works" % mode
		)
	LevelCatalog.endless = false
	LevelCatalog.daily_key = ""
	# A replay takes the mode from its journal header, not from the player's choice.
	var replayed: Node = await _load_level()
	var sim: Sim = replayed.get_node("Sim")
	var header := {
		"sim_version": Sim.VERSION,
		"tick_rate": 30,
		"level": _level,
		"endless": true,
		"seed": 7,
		"perks": {},
	}
	var log := CommandLog.new()
	log.header = header
	sim.begin_replay(log)
	check(not (replayed.villagers as Villagers).wood_economy, "an endless replay: economy off")
	LevelCatalog.endless = false


## An old journal (before these commands) plays on and ends in the hash it always had.
func _test_legacy_journal() -> void:
	print("-- old journal")
	LevelCatalog.selected_id = 1
	var main: Node = await _load_level()
	var sim: Sim = main.get_node("Sim")
	sim.begin_replay(CommandLog.from_json(LEGACY_JOURNAL))
	while sim.tick < 600:
		sim.advance(0.1)
		await process_frame
	check(
		sim.towers.size() == LEGACY_TOWERS, "the old journal builds %d towers" % sim.towers.size()
	)
	check(
		sim.state_hash() == LEGACY_HASH,
		"state hash at tick 600 equals the one from before the change (%d)" % sim.state_hash()
	)
	check(main.villagers.state_ints().is_empty(), "no economy in an old journal")

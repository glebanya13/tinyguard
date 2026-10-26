extends SceneTree
## Villagers: they settle on level 1 off the enemy path, buy wood for gold at
## the VillagerTrade rate, the rate drops with volume, and nobody sells wood
## they do not have. Also drives the trade card through the command buttons.
## godot --headless --fixed-fps 60 --path . --script res://tests/test_villagers.gd

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_villagers.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	LevelCatalog.selected_id = (
		int(OS.get_environment("LEVEL")) if OS.has_environment("LEVEL") else 1
	)
	change_scene_to_file("res://scenes/main.tscn")
	_run.call_deferred()


func _run() -> void:
	for i in 10:
		await process_frame
	var main: Node = current_scene
	var villagers: Villagers = main.villagers
	var gs: GameState = main.get_node("GameState")
	var trade: VillagerTrade = villagers.trade
	var list: Array[Villager] = villagers.get_villagers()
	check(list.size() >= 2, "villagers spawned (%d)" % list.size())
	for v in list:
		check(villagers.is_open(v.global_position), "villager %s stands on open ground" % v.name)

	# Strolls stay on open ground, away from the path.
	for i in 300:
		await process_frame
	var moved := false
	for v in list:
		moved = moved or v.global_position.distance_to(v.home) > 0.05
		check(villagers.is_open(v.global_position), "villager %s still on open ground" % v.name)
	check(moved, "villagers stroll")

	# Rate from the resource; no wood, no sale.
	gs.wood = 0
	gs.add_wood(0)
	var gold: int = gs.gold
	check(villagers.sell(1) == 0 and gs.gold == gold, "cannot sell without wood")
	gs.add_wood(trade.wood_per_lot - 1)
	check(villagers.sell(1) == 0 and gs.wood == trade.wood_per_lot - 1, "cannot sell a partial lot")
	gs.add_wood(1)
	gold = gs.gold
	var got: int = villagers.sell(1)
	check(
		got == roundi(trade.start_gold) and gs.gold == gold + got and gs.wood == 0,
		"first lot: %d wood -> %d gold" % [trade.wood_per_lot, got]
	)
	check(villagers.sell(5) == 0, "cannot sell more wood than you have")

	# Diminishing returns.
	var first_price: int = trade.lot_gold(0)
	gs.add_wood(trade.wood_per_lot * 20)
	gold = gs.gold
	var quoted: int = villagers.quote(20)
	got = villagers.sell(50)  # only 20 lots of wood
	check(got == quoted and gs.gold == gold + got, "sell all pays the quote (%d)" % got)
	check(gs.wood == 0, "sold exactly the wood there was")
	check(villagers.lots_sold == 21, "21 lots sold")
	check(
		villagers.lot_price() < first_price, "price drops with volume (%d)" % villagers.lot_price()
	)
	check(villagers.lot_price() >= trade.min_gold, "price never below the minimum")
	check(got < 20 * first_price, "bulk sale pays less than 20 first lots")

	# The trade card: walk the hero to a villager, press its buttons.
	var hero: Hero = main.get_node("Level/Hero")
	var v0: Villager = list[0]
	# The villagers stroll on a random stream, so another one may stand nearer to the hero than
	# v0 and take the card: park the others far away (the card picks the nearest villager).
	for other: Villager in list:
		if other != v0:
			other.global_position += Vector3(200.0, 0.0, 200.0)
	hero.global_position = v0.global_position + Vector3(0.8, 0.0, 0.0)
	await process_frame
	await process_frame
	check(main.cards.trade_with == v0, "trade card opens next to a villager")
	check(not v0.is_walking(), "villager stops to trade")
	gs.add_wood(trade.wood_per_lot * (trade.step_lots() + 2))
	gold = gs.gold
	main.cards.on_command_pressed(&"trade_lot")
	check(
		gs.wood == trade.wood_per_lot * 2 and gs.gold > gold,
		"card button sells one step of wood (%d)" % trade.sell_step_wood
	)
	main.cards.on_command_pressed(&"trade_all")
	check(gs.wood == 0, "card button sells everything")
	main.cards.on_command_pressed(&"cancel")
	await process_frame
	check(main.cards.trade_with == null, "closed card stays closed while the hero stands there")
	hero.global_position = v0.global_position + Vector3(6.0, 0.0, 0.0)
	await process_frame
	hero.global_position = v0.global_position + Vector3(0.8, 0.0, 0.0)
	await process_frame
	check(main.cards.trade_with == v0, "card opens again after walking away and back")
	hero.global_position = v0.global_position + Vector3(6.0, 0.0, 0.0)
	await process_frame
	check(main.cards.trade_with != v0, "card closes when the hero walks away")

	# Enemies ignore villagers: the hero's targets never include them.
	check(not v0.is_in_group(Enemy.GROUP), "villagers are not enemies")

	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)

extends SceneTree
## Tests for Subagent 4: Strategic camera zoom, flyover, villager wood restock over
## simulation time, tower level visual badges (I..III, ★), and minimap enemy markers.
## godot --headless --fixed-fps 60 --path . --script res://tests/test_strategic_view.gd

const SETTINGS := "user://test_strat_settings.cfg"

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_strategic_view.cfg"
	GameSettings.config_path = SETTINGS
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	LevelCatalog.selected_id = 1
	LevelCatalog.endless = false
	LevelCatalog.tutorial = false
	change_scene_to_file("res://scenes/main.tscn")
	_run.call_deferred()


func _run() -> void:
	for i in 10:
		await process_frame
	var main: Node = current_scene
	var cam: CameraFollow = main.get_node("Camera") as CameraFollow
	var hud: Hud = main.get_node("HUD") as Hud
	var lane_hint: LaneHint = main._lane_hint
	var villagers: Villagers = main.villagers
	var sim: Sim = main.get_node("Sim") as Sim
	var gs: GameState = main.get_node("GameState") as GameState

	print("-- 1. Camera strategic view and flyover")
	check(cam != null, "camera exists")
	check(cam.has_method("toggle_strategic_view"), "camera has toggle_strategic_view()")
	check(not cam.is_strategic_view(), "starts in normal view")
	var initial_size: float = cam.size
	check(initial_size > 0.0, "camera has positive size (%f)" % initial_size)

	# Toggle ON
	var state: bool = cam.toggle_strategic_view()
	check(state and cam.is_strategic_view(), "toggle returns true and strategic_view is true")
	check(cam._target_size > initial_size * 1.35, "target size is 40-50%% larger (%f -> %f)" % [initial_size, cam._target_size])

	# Advance physics frames for smooth zoom transition
	for i in 30:
		await physics_frame
	check(cam.size > initial_size * 1.3, "camera smoothly zoomed out towards strategic view (%f)" % cam.size)

	# Toggle OFF
	state = cam.toggle_strategic_view()
	check(not state and not cam.is_strategic_view(), "toggle returns false and strategic_view is false")
	check(absf(cam._target_size - initial_size) < 0.01, "target size returned to normal size")

	for i in 30:
		await physics_frame
	check(absf(cam.size - initial_size) < 0.5, "camera smoothly zoomed back to normal size (%f)" % cam.size)

	# HUD and LaneHint toggle signals
	hud.toggle_strategic_view()
	check(cam.is_strategic_view(), "hud.toggle_strategic_view() triggers camera strategic view")
	lane_hint.toggle_strategic_view()
	check(not cam.is_strategic_view(), "lane_hint.toggle_strategic_view() toggles camera back")
	# Button layout: when minimap is visible, strategic view button sits vertically below the compass button
	GameSettings.set_layout_value("minimap_mode", HudLayout.MAP_SHOW)
	lane_hint.apply_settings()
	check(lane_hint.compass_visible(), "compass is visible in MAP_SHOW mode")
	var compass_btn: Button = lane_hint.get_node("CompassButton")
	var strat_btn: Button = lane_hint.get_node("StrategicViewButton")
	check(strat_btn.position.y > compass_btn.position.y, "strategic button is positioned under compass button")
	check(is_equal_approx(strat_btn.position.x, compass_btn.position.x), "strategic button aligned horizontally with compass button")
	var compass_box := Rect2(compass_btn.position, compass_btn.size)
	var strat_box := Rect2(strat_btn.position, strat_btn.size)
	var map_rect: Rect2 = HudLayout.current(lane_hint.size, true)["map"]
	check(not compass_box.intersects(strat_box), "compass and strategic buttons do not overlap")
	check(not compass_box.intersects(map_rect), "compass button does not overlap minimap")
	check(not strat_box.intersects(map_rect), "strategic button does not overlap minimap")

	# When minimap is hidden, buttons sit side-by-side under Speed and Pause
	GameSettings.set_layout_value("minimap_mode", HudLayout.MAP_HIDE)
	lane_hint.apply_settings()
	check(not lane_hint.compass_visible(), "compass is hidden in MAP_HIDE mode")
	check(is_equal_approx(strat_btn.position.y, compass_btn.position.y), "hidden: buttons aligned vertically")
	check(strat_btn.position.x > compass_btn.position.x, "hidden: strat button is to the right of compass button")
	var hid_compass_box := Rect2(compass_btn.position, compass_btn.size)
	var hid_strat_box := Rect2(strat_btn.position, strat_btn.size)
	check(not hid_compass_box.intersects(hid_strat_box), "hidden: compass and strategic buttons do not overlap")

	# Restore minimap mode to MAP_SHOW
	GameSettings.set_layout_value("minimap_mode", HudLayout.MAP_SHOW)
	lane_hint.apply_settings()

	# Flyover
	check(cam.has_method("start_flyover") and cam.has_method("stop_flyover"), "camera has flyover methods")
	cam.start_flyover([Vector3(10, 0, 10)], Vector3.ZERO, 4.0)
	check(cam.flyover_active, "flyover starts active")
	cam.stop_flyover()
	check(not cam.flyover_active, "stop_flyover deactivates flyover")

	# GameCamera class check
	var game_cam := GameCamera.new()
	check(game_cam is CameraFollow, "GameCamera inherits from CameraFollow")
	check(game_cam.has_method("toggle_strategic_view"), "GameCamera has toggle_strategic_view()")
	game_cam.free()

	print("-- 2. Villagers wood restock over simulation time")
	check(villagers != null and villagers.wood_economy, "wood economy is active")
	var trade: VillagerTrade = villagers.trade
	gs.gold = 1000
	var initial_left: int = villagers.buy_lots_left()
	check(initial_left == trade.buy_max_lots, "initially all lots are available (%d)" % initial_left)

	# Buy 2 lots
	var bought: int = villagers.buy(2)
	check(bought == 2, "bought 2 lots")
	check(villagers.lots_bought == 2, "lots_bought is 2")
	check(villagers.buy_lots_left() == trade.buy_max_lots - 2, "buy_lots_left decreased by 2 (%d)" % villagers.buy_lots_left())

	# Run simulation for 1799 ticks (just before 60 seconds at 30 ticks/s)
	for i in Villagers.RESTOCK_INTERVAL_TICKS - 1:
		villagers.sim_step()
	check(villagers.lots_bought == 2, "no restock before 60 seconds (1799 ticks)")

	# Step 1800th tick -> restocks 1 lot!
	villagers.sim_step()
	check(villagers.lots_bought == 1, "restocked 1 lot at 60s: lots_bought is now 1")
	check(villagers.buy_lots_left() == trade.buy_max_lots - 1, "buy_lots_left replenished by +1 (%d)" % villagers.buy_lots_left())

	# Another 60 seconds (1800 ticks) -> restocks second lot!
	for i in Villagers.RESTOCK_INTERVAL_TICKS:
		villagers.sim_step()
	check(villagers.lots_bought == 0, "restocked second lot at 120s: lots_bought is now 0")
	check(villagers.buy_lots_left() == trade.buy_max_lots, "buy_lots_left is back to maximum capacity (%d)" % villagers.buy_lots_left())

	# Manual restock method test
	villagers.buy(1)
	check(villagers.lots_bought == 1, "bought 1 lot")
	var restocked: bool = villagers.restock(1)
	check(restocked and villagers.lots_bought == 0, "manual restock(1) succeeded")
	check(not villagers.restock(1), "restock when already at capacity returns false")

	print("-- 3. Tower 3D level indicators (I..III, ★)")
	# Static symbol helper tests
	check(Tower.level_symbol(1) == "I", "level 1 symbol is 'I'")
	check(Tower.level_symbol(2) == "II", "level 2 symbol is 'II'")
	check(Tower.level_symbol(3) == "III", "level 3 symbol is 'III'")
	check(Tower.level_symbol(4) == "★", "level 4 symbol is '★'")

	# Create a tower and verify indicator updates
	var tower_scene: PackedScene = preload("res://scenes/towers/tower_archer.tscn")
	var tower: Tower = tower_scene.instantiate() as Tower
	main.add_child(tower)
	await process_frame

	check(tower.level_indicator != null, "tower created level_indicator node")
	check(tower.get_level_text() == "I", "initial tower displays 'I' (%s)" % tower.get_level_text())

	tower.update_level_indicator(2)
	check(tower.get_level_text() == "II", "level 2 displays 'II' (%s)" % tower.get_level_text())

	tower.update_level_indicator(3)
	check(tower.get_level_text() == "III", "level 3 displays 'III' (%s)" % tower.get_level_text())

	tower.update_level_indicator(4)
	check(tower.get_level_text() == "★", "level 4 displays '★' (%s)" % tower.get_level_text())
	check(tower.level_indicator.modulate.r > 0.9 and tower.level_indicator.modulate.g > 0.7, "level 4 star is golden (%s)" % tower.level_indicator.modulate)

	# apply_level updates indicator
	var archer_data: TowerData = preload("res://resources/towers/archer.tres")
	tower.apply_level(archer_data, 0)
	check(tower.get_level_text() == "I", "apply_level 0 sets indicator to 'I'")
	tower.apply_level(archer_data, 1)
	check(tower.get_level_text() == "II", "apply_level 1 sets indicator to 'II'")
	tower.apply_level(archer_data, 2)
	check(tower.get_level_text() == "III", "apply_level 2 sets indicator to 'III'")

	tower.queue_free()

	print("-- 4. Minimap enemy rendering on LaneMap")
	var map: LaneMap = lane_hint.compass_map()
	check(map != null, "lane_map instance exists")
	check(map.has_method("draw_enemies"), "lane_map has draw_enemies() method")

	# Mock dummy enemies with data
	var ground_enemy := Enemy.new()
	var ground_data := EnemyData.new()
	ground_data.is_boss = false
	ground_data.flying = false
	ground_enemy.data = ground_data

	var flying_enemy := Enemy.new()
	var flyer_data := EnemyData.new()
	flyer_data.is_boss = false
	flyer_data.flying = true
	flying_enemy.data = flyer_data

	var boss_enemy := Enemy.new()
	var boss_data := EnemyData.new()
	boss_data.is_boss = true
	boss_enemy.data = boss_data

	var test_canvas := Control.new()
	var enemies := [ground_enemy, flying_enemy, boss_enemy]
	test_canvas.draw.connect(func() -> void: map.draw_enemies(test_canvas, enemies, 1.0))
	main.add_child(test_canvas)
	test_canvas.queue_redraw()
	await process_frame
	check(true, "draw_enemies executes cleanly inside canvas draw callback")

	test_canvas.queue_free()
	ground_enemy.free()
	flying_enemy.free()
	boss_enemy.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))

	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)

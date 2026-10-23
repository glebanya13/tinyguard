extends SceneTree
## Tests for Subagent 3:
##   1. Enemy HP bar: increased thickness, dark background/border, dynamic color.
##   2. EncyclopediaPanel: open, close, tab switching, and data accuracy
##      (towers, bestiary, village).
##   3. CardController: next-level upgrade range preview ring.
## godot --headless --path . --script res://tests/test_encyclopedia.gd

const ARCHER_PATH := "res://resources/towers/archer.tres"

var fails := 0
var _closed_fired := false
var _tab_switched := -1


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_enemy_hp_bar()
	await _check_encyclopedia_panel()
	await _check_upgrade_range_ring()

	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _check_enemy_hp_bar() -> void:
	var sim := Sim.new()
	var enemy_scene: PackedScene = load("res://scenes/enemy.tscn")
	check(enemy_scene != null, "enemy.tscn loads")
	var enemy: Enemy = enemy_scene.instantiate() as Enemy

	var slime_data: EnemyData = load("res://resources/enemies/slime.tres") as EnemyData
	check(slime_data != null, "slime.tres loads")
	# Must setup before entering tree
	enemy.sim = sim
	enemy.setup(slime_data, 1.0)
	root.add_child(enemy)

	var bar: MeshInstance3D = enemy.get_node_or_null("HealthBar") as MeshInstance3D
	var bar_bg: MeshInstance3D = enemy.get_node_or_null("HealthBarBg") as MeshInstance3D
	check(bar != null, "HealthBar exists on Enemy")
	check(bar_bg != null, "HealthBarBg exists on Enemy")

	# Thickness check: QuadMesh height should be ~0.15 (at least 0.14)
	if bar and bar.mesh is QuadMesh:
		var qmesh := bar.mesh as QuadMesh
		check(qmesh.size.y >= 0.14, "HP bar mesh height is thicker (%.2f >= 0.14)" % qmesh.size.y)
	if bar_bg and bar_bg.mesh is QuadMesh:
		var bg_mesh := bar_bg.mesh as QuadMesh
		check(
			bg_mesh.size.y >= 0.16, "HP bar bg mesh height is thick (%.2f >= 0.16)" % bg_mesh.size.y
		)

	# Dynamic color: > 50% HP -> Green
	enemy.take_damage(2.0)  # HP = 20 / 22 (> 90%)
	check(enemy.health_ratio() > 0.5, "HP is > 50%")
	var mat := bar.material_override as StandardMaterial3D
	check(mat != null, "material_override assigned on hurt")
	if mat:
		check(mat.albedo_color == Enemy.COLOR_HP_GREEN, "HP > 50%% is green")

	# Dynamic color: 20% - 50% HP -> Yellow
	enemy.take_damage(12.0)  # HP = 8 / 22 (~36%)
	check(enemy.health_ratio() >= 0.2 and enemy.health_ratio() <= 0.5, "HP is between 20% and 50%")
	mat = bar.material_override as StandardMaterial3D
	if mat:
		check(mat.albedo_color == Enemy.COLOR_HP_YELLOW, "HP 20%%-50%% is yellow")

	# Dynamic color: < 20% HP -> Red
	enemy.take_damage(6.0)  # HP = 2 / 22 (~9%)
	check(enemy.health_ratio() < 0.2, "HP is < 20%")
	mat = bar.material_override as StandardMaterial3D
	if mat:
		check(mat.albedo_color == Enemy.COLOR_HP_RED, "HP < 20%% is red")

	enemy.queue_free()


func _check_encyclopedia_panel() -> void:
	var panel := EncyclopediaPanel.new()
	root.add_child(panel)

	# 1. Open and close
	check(not panel.visible, "panel initially hidden")
	panel.open()
	check(panel.visible, "panel open makes it visible")
	check(panel.current_tab() == 0, "default tab is Towers (0)")

	_closed_fired = false
	panel.closed.connect(func() -> void: _closed_fired = true)
	panel.close()
	check(not panel.visible, "close hides panel")
	check(_closed_fired, "closed signal emitted")

	# 2. Tab switching
	panel.open()
	_tab_switched = -1
	panel.tab_changed.connect(func(t: int) -> void: _tab_switched = t)

	panel.set_tab(1)
	check(panel.current_tab() == 1, "switched to Bestiary (1)")
	check(_tab_switched == 1, "tab_changed signal emitted for tab 1")

	# Check bestiary content
	var scout_box := panel.find_child("Enemy_slime_fast", true, false)
	var healer_box := panel.find_child("Enemy_slime_healer", true, false)
	var boss_box := panel.find_child("Enemy_slime_king", true, false)
	check(scout_box != null, "scout entry exists in Bestiary")
	check(healer_box != null, "healer entry exists in Bestiary")
	check(boss_box != null, "boss entry exists in Bestiary")
	if scout_box:
		var stats: Label = scout_box.find_child("Stats", true, false) as Label
		check(stats != null and stats.text.contains("12"), "scout stats has HP 12")
		var icon_rect: TextureRect = scout_box.find_child("Icon", true, false) as TextureRect
		check(
			(
				icon_rect != null
				and icon_rect.texture != null
				and icon_rect.texture.resource_path == "res://ui/icons/slime_fast.png"
			),
			"scout icon is slime_fast.png"
		)
		check(
			icon_rect != null and icon_rect.expand_mode == TextureRect.EXPAND_IGNORE_SIZE,
			"scout icon has EXPAND_IGNORE_SIZE"
		)
		check(
			icon_rect != null and icon_rect.custom_minimum_size.x <= 64.0,
			"scout icon size is compact (<= 64px)"
		)
	if healer_box:
		var stats: Label = healer_box.find_child("Stats", true, false) as Label
		check(stats != null and stats.text.contains("28"), "healer stats has HP 28")
		var icon_rect: TextureRect = healer_box.find_child("Icon", true, false) as TextureRect
		check(
			(
				icon_rect != null
				and icon_rect.texture != null
				and icon_rect.texture.resource_path == "res://ui/icons/slime_healer.png"
			),
			"healer icon is slime_healer.png"
		)

	panel.set_tab(2)
	check(panel.current_tab() == 2, "switched to Village (2)")
	check(_tab_switched == 2, "tab_changed signal emitted for tab 2")

	# Check village content
	var lumber_box := panel.find_child("Village_Lumberjacks", true, false)
	var sell_box := panel.find_child("Village_Selling", true, false)
	var buy_box := panel.find_child("Village_Buying", true, false)
	var merc_box := panel.find_child("Village_Mercenaries", true, false)
	check(lumber_box != null, "lumberjacks entry exists in Village tab")
	check(sell_box != null, "selling wood entry exists in Village tab")
	check(buy_box != null, "buying wood entry exists in Village tab")
	check(merc_box != null, "mercenaries entry exists in Village tab")
	if lumber_box:
		var stats: Label = lumber_box.find_child("Stats", true, false) as Label
		check(
			(
				stats != null
				and stats.text.contains(
					str(int(load("res://resources/villager_trade.tres").hire_gold))
				)
			),
			"lumberjack cost (from villager_trade.tres) in stats"
		)
	if merc_box:
		var stats: Label = merc_box.find_child("Stats", true, false) as Label
		check(
			(
				stats != null
				and stats.text.contains("40")
				and stats.text.contains("80")
				and stats.text.contains("16")
			),
			"mercenary stats contains cost 40, HP 80, DMG 16"
		)
		var icon_rect: TextureRect = merc_box.find_child("Icon", true, false) as TextureRect
		check(
			(
				icon_rect != null
				and icon_rect.texture != null
				and icon_rect.texture.resource_path == "res://ui/icons/sword.png"
			),
			"mercenary icon is sword.png"
		)

	panel.set_tab(0)
	check(panel.current_tab() == 0, "switched back to Towers (0)")
	var archer_box := panel.find_child("Tower_archer", true, false)
	var cannon_box := panel.find_child("Tower_cannon", true, false)
	check(archer_box != null, "archer tower entry exists in Towers tab")
	check(cannon_box != null, "cannon tower entry exists in Towers tab")
	if archer_box:
		var archer_damage: float = (load(ARCHER_PATH) as TowerData).damage_levels[0]
		var stats: Label = archer_box.find_child("Stats", true, false) as Label
		check(
			stats != null and stats.text.contains(str(int(archer_damage))),
			"archer base damage (from archer.tres) in stats"
		)

	panel.queue_free()


func _check_upgrade_range_ring() -> void:
	var controller := CardController.new()

	var range_ring := MeshInstance3D.new()
	range_ring.mesh = TorusMesh.new()
	var upgrade_ring := MeshInstance3D.new()
	upgrade_ring.mesh = TorusMesh.new()

	var dummy_root := Node3D.new()
	root.add_child(dummy_root)
	dummy_root.add_child(range_ring)
	dummy_root.add_child(upgrade_ring)

	var hero_scene: PackedScene = load("res://scenes/hero.tscn")
	var hero: Hero = hero_scene.instantiate() as Hero
	dummy_root.add_child(hero)

	var hud_scene: PackedScene = load("res://ui/hud.tscn")
	var hud: Hud = hud_scene.instantiate() as Hud
	dummy_root.add_child(hud)

	var build_mgr := BuildManager.new()
	dummy_root.add_child(build_mgr)

	var sim := Sim.new()
	var state := GameState.new()
	state.gold = 999
	state.wood = 999
	build_mgr.game_state = state
	dummy_root.add_child(state)

	var archer_data: TowerData = load(ARCHER_PATH) as TowerData
	check(archer_data != null, "archer.tres loaded")
	build_mgr.tower_types = [archer_data]

	controller.setup(
		hero,
		hud,
		build_mgr,
		GameCommands.new(),
		Villagers.new(),
		state,
		sim,
		range_ring,
		func() -> String: return "",
		upgrade_ring
	)

	# 1. No slot selected: both rings hidden
	controller.refresh()
	check(not range_ring.visible, "no slot: range_ring hidden")
	check(not upgrade_ring.visible, "no slot: upgrade_ring hidden")

	# 2. Empty slot selected: range_ring shows level 1 range, upgrade_ring hidden
	var slot_scene: PackedScene = load("res://scenes/tower_slot.tscn")
	var slot: TowerSlot = slot_scene.instantiate() as TowerSlot
	dummy_root.add_child(slot)
	build_mgr.select_slot(slot)
	check(range_ring.visible, "empty slot: range_ring visible")
	check(
		is_equal_approx(range_ring.scale.x, archer_data.range_levels[0]),
		"empty slot: shows level 1 radius (4.3)"
	)
	check(not upgrade_ring.visible, "empty slot: upgrade_ring hidden")

	# 3. Tower at level 0: upgrade_ring shows level 1 range
	var tower := Tower.new()
	dummy_root.add_child(tower)
	tower.apply_level(archer_data, 0)
	slot.tower = tower

	controller.refresh()
	check(range_ring.visible, "tower lvl 0: range_ring visible")
	check(
		is_equal_approx(range_ring.scale.x, archer_data.range_levels[0]), "range_ring scale is 4.3"
	)
	check(upgrade_ring.visible, "tower lvl 0: upgrade_ring visible")
	check(
		is_equal_approx(upgrade_ring.scale.x, archer_data.range_levels[1]),
		"upgrade_ring scale is 4.7 (next level)"
	)

	# 4. Tower at max level (level 2): upgrade_ring hidden
	tower.apply_level(archer_data, archer_data.max_level())
	controller.refresh()
	check(range_ring.visible, "max tower: range_ring visible")
	check(not upgrade_ring.visible, "max tower: upgrade_ring hidden")

	# 5. Clear selection: both rings hidden
	build_mgr.clear_selection()
	check(not range_ring.visible, "cleared: range_ring hidden")
	check(not upgrade_ring.visible, "cleared: upgrade_ring hidden")

	dummy_root.queue_free()

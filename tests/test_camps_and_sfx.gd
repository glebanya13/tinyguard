extends SceneTree
## Tests for Subagent 10:
## 1. 3D Camp structures on level: LumberjackCamp and MercenaryCamp.
## 2. Mercenary ally recruitment, addition to simulation, patrol and stats.
## 3. Hero damage reaction: take_damage(), health decrease, damage flash timer, and audio streams.
## 4. Gate hit and projectile impact audio/VFX scenes.

var fails: int = 0


func check(c: bool, msg: String) -> void:
	print("  ok   " if c else "  FAIL ", msg)
	if not c:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("-- 1. Camp structures (LumberjackCamp & MercenaryCamp)")
	var builder := LevelBuilder.new()
	var level: Dictionary = LevelCatalog.get_level(1)
	var root_node := Node3D.new()
	root.add_child(root_node)
	var sim := Sim.new()
	root.add_child(sim)
	var commands := GameCommands.new()
	commands.sim = sim
	root.add_child(commands)
	var wm := WaveManager.new()
	root.add_child(wm)
	var path := Path3D.new()
	root.add_child(path)
	var hero_scene: PackedScene = load("res://scenes/hero.tscn")
	var hero: Hero = hero_scene.instantiate() as Hero
	root.add_child(hero)
	var camera := CameraFollow.new()
	root.add_child(camera)

	builder.build(level, root_node, path, wm, commands, sim, hero, camera)

	check(builder.lumberjack_camp != null, "builder.lumberjack_camp exists")
	check(builder.mercenary_camp != null, "builder.mercenary_camp exists")
	check(builder.lumberjack_camp is CampStructures.LumberjackCamp, "lumberjack camp is LumberjackCamp instance")
	check(builder.mercenary_camp is CampStructures.MercenaryCamp, "mercenary camp is MercenaryCamp instance")
	check(builder.lumberjack_camp.find_child("LogCanopy", true, false) != null, "lumberjack camp has LogCanopy")
	check(builder.mercenary_camp.find_child("Tent", true, false) != null, "mercenary camp has Tent")
	check(builder.mercenary_camp.find_child("WeaponRack", true, false) != null, "mercenary camp has WeaponRack")

	# Check clearance for Level 1
	var c_pos: Vector3 = builder.castle.position
	var lj_pos: Vector3 = builder.lumberjack_camp.position
	var mc_pos: Vector3 = builder.mercenary_camp.position
	var r_lj: float = Vector2(lj_pos.x - c_pos.x, lj_pos.z - c_pos.z).length()
	var r_mc: float = Vector2(mc_pos.x - c_pos.x, mc_pos.z - c_pos.z).length()
	check(r_lj >= 6.0 and r_lj <= 10.5, "lumberjack camp is 6-10m from castle (dist=%.2f)" % r_lj)
	check(r_mc >= 6.0 and r_mc <= 10.5, "mercenary camp is 6-10m from castle (dist=%.2f)" % r_mc)

	var ds_lj: float = LevelBuilder._min_dist_to_slots(Vector2(lj_pos.x, lj_pos.z), level["slots"])
	var ds_mc: float = LevelBuilder._min_dist_to_slots(Vector2(mc_pos.x, mc_pos.z), level["slots"])
	check(ds_lj >= 3.5, "lumberjack camp >= 3.5m from all slots (min_dist=%.2f)" % ds_lj)
	check(ds_mc >= 3.5, "mercenary camp >= 3.5m from all slots (min_dist=%.2f)" % ds_mc)

	var dp_lj: float = LevelBuilder._min_dist_to_paths(Vector2(lj_pos.x, lj_pos.z), level["paths"])
	var dp_mc: float = LevelBuilder._min_dist_to_paths(Vector2(mc_pos.x, mc_pos.z), level["paths"])
	check(dp_lj >= 2.5, "lumberjack camp >= 2.5m from all enemy paths (min_dist=%.2f)" % dp_lj)
	check(dp_mc >= 2.5, "mercenary camp >= 2.5m from all enemy paths (min_dist=%.2f)" % dp_mc)

	# Verify clearance helper across all levels in catalog
	var all_clear := true
	for lvl_id in range(1, 7):
		var test_lvl: Dictionary = LevelCatalog.get_level(lvl_id)
		var test_cpos := Vector3(float(test_lvl["castle"][0]), 0.0, float(test_lvl["castle"][1]))
		var camps_res: Dictionary = LevelBuilder.find_camp_positions(test_lvl, test_cpos)
		var p_lj: Vector3 = camps_res["lumberjack"]
		var p_mc: Vector3 = camps_res["mercenary"]
		var d1: float = LevelBuilder._min_dist_to_slots(Vector2(p_lj.x, p_lj.z), test_lvl["slots"])
		var d2: float = LevelBuilder._min_dist_to_slots(Vector2(p_mc.x, p_mc.z), test_lvl["slots"])
		var p1: float = LevelBuilder._min_dist_to_paths(Vector2(p_lj.x, p_lj.z), test_lvl["paths"])
		var p2: float = LevelBuilder._min_dist_to_paths(Vector2(p_mc.x, p_mc.z), test_lvl["paths"])
		if d1 < 3.5 or d2 < 3.5 or p1 < 2.5 or p2 < 2.5:
			all_clear = false
			print("Clearance failed on level %d: d1=%.2f, d2=%.2f, p1=%.2f, p2=%.2f" % [lvl_id, d1, d2, p1, p2])
	check(all_clear, "all 6 levels satisfy camp clearance (slot >= 3.5m, path >= 2.5m)")

	# Selection rings and Area3D
	var lj_ring: Node = builder.lumberjack_camp.find_child("SelectionRing", true, false)
	var mc_ring: Node = builder.mercenary_camp.find_child("SelectionRing", true, false)
	check(lj_ring != null, "lumberjack camp has SelectionRing")
	check(mc_ring != null, "mercenary camp has SelectionRing")
	check(not (lj_ring as MeshInstance3D).visible, "lumberjack camp SelectionRing starts hidden")
	check(not (mc_ring as MeshInstance3D).visible, "mercenary camp SelectionRing starts hidden")

	builder.lumberjack_camp.select()
	check((lj_ring as MeshInstance3D).visible, "lumberjack camp select() shows SelectionRing")
	builder.lumberjack_camp.deselect()
	check(not (lj_ring as MeshInstance3D).visible, "lumberjack camp deselect() hides SelectionRing")

	builder.mercenary_camp.select()
	check((mc_ring as MeshInstance3D).visible, "mercenary camp select() shows SelectionRing")
	builder.mercenary_camp.deselect()
	check(not (mc_ring as MeshInstance3D).visible, "mercenary camp deselect() hides SelectionRing")

	check(builder.lumberjack_camp.find_child("CampArea", true, false) != null, "lumberjack camp has CampArea (Area3D)")
	check(builder.mercenary_camp.find_child("CampArea", true, false) != null, "mercenary camp has CampArea (Area3D)")

	# Card integration test
	var bm := BuildManager.new()
	root.add_child(bm)
	bm.camera = camera
	bm.lumberjack_camp = builder.lumberjack_camp
	bm.mercenary_camp = builder.mercenary_camp

	bm.select_camp(builder.lumberjack_camp)
	check(bm.selected_camp == builder.lumberjack_camp, "BuildManager selects lumberjack camp")
	check((lj_ring as MeshInstance3D).visible, "lumberjack camp SelectionRing visible after select_camp")

	bm.select_camp(builder.mercenary_camp)
	check(bm.selected_camp == builder.mercenary_camp, "BuildManager selects mercenary camp")
	check(not (lj_ring as MeshInstance3D).visible, "previous camp SelectionRing hidden")
	check((mc_ring as MeshInstance3D).visible, "mercenary camp SelectionRing visible")

	bm.clear_selection()
	check(bm.selected_camp == null, "clear_selection() clears selected camp")
	check(not (mc_ring as MeshInstance3D).visible, "mercenary camp SelectionRing hidden after clear_selection")

	print("-- 2. Mercenary ally recruitment and simulation")
	var gs := GameState.new()
	gs.gold = 100
	var merc: Mercenary = builder.mercenary_camp.hire_mercenary(gs, sim)
	check(merc != null, "hire_mercenary() succeeds with sufficient gold")
	check(gs.gold == 60, "gold decreased by 40 (100 -> 60)")
	check(sim.mercenaries.has(merc), "mercenary registered with Sim")
	check(merc.is_alive(), "hired mercenary is alive")
	check(merc.health == merc.max_health, "mercenary starts at max health (80)")

	# Mercenary damage and flash
	merc.take_damage(20.0, Vector3.FORWARD)
	check(merc.health == 60.0, "mercenary health reduced to 60 after 20 dmg")
	check(merc.is_flashing(), "mercenary is flashing after taking damage")

	# Test CommandCards for camps
	var villagers := Villagers.new()
	villagers.game_state = gs
	root.add_child(villagers)
	var lj_card: Dictionary = CommandCards.lumberjack_camp(villagers, gs)
	check(not lj_card.is_empty(), "CommandCards.lumberjack_camp() returns valid card")
	check(lj_card.has("buttons") and lj_card["buttons"].size() >= 2, "lumberjack camp card has action buttons")

	var mc_card: Dictionary = CommandCards.mercenary_camp(builder.mercenary_camp, gs)
	check(not mc_card.is_empty(), "CommandCards.mercenary_camp() returns valid card")
	var has_hire_btn: bool = false
	for btn in mc_card.get("buttons", []):
		if btn.get("id") == &"hire_mercenary":
			has_hire_btn = true
	check(has_hire_btn, "mercenary camp card has hire_mercenary button")

	# Cleanup test nodes
	bm.queue_free()
	villagers.queue_free()

	print("-- 3. Hero damage reaction and hurt SFX")
	check(hero.health == hero.max_health, "hero starts at max health (100)")
	hero.take_damage(15.0, Vector3.BACK)
	check(hero.health == 85.0, "hero health reduced to 85 after 15 dmg")
	check(hero.is_flashing(), "hero damage flash timer active")

	print("-- 4. Impact VFX and SFX assets")
	var gate_fx: PackedScene = load("res://scenes/fx/gate_hit_fx.tscn")
	check(gate_fx != null, "gate_hit_fx.tscn loads")
	var arrow_fx: PackedScene = load("res://scenes/fx/arrow_hit_fx.tscn")
	check(arrow_fx != null, "arrow_hit_fx.tscn loads")
	var cannon_fx: PackedScene = load("res://scenes/fx/cannon_hit_fx.tscn")
	check(cannon_fx != null, "cannon_hit_fx.tscn loads")
	var frost_fx: PackedScene = load("res://scenes/fx/frost_hit_fx.tscn")
	check(frost_fx != null, "frost_hit_fx.tscn loads")

	var hurt_snd: AudioStream = load("res://assets/audio/hero_hurt.wav")
	check(hurt_snd != null, "hero_hurt.wav audio exists")
	var gate_snd: AudioStream = load("res://assets/audio/gate_hit.wav")
	check(gate_snd != null, "gate_hit.wav audio exists")

	# Clean up
	root_node.queue_free()
	sim.queue_free()
	commands.queue_free()
	wm.queue_free()
	path.queue_free()
	hero.queue_free()
	camera.queue_free()

	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)

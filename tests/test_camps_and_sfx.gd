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

extends SceneTree
## Units in play, through public interfaces: enemy slow, projectiles (hit, miss,
## splash, slow), hero sword and whirlwind, selling and upgrading towers, the
## treasury, the end screen and the Back button on it.
## godot --headless --fixed-fps 60 --path . --script res://tests/test_units.gd

const SAVE := "user://test_units.cfg"
const SLIME := "res://resources/enemies/slime.tres"

var fails := 0
var main: Node = null
var gs: GameState = null
var bm: BuildManager = null
var hero: Hero = null
var sim: Sim = null


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = SAVE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	LevelCatalog.selected_id = 1
	change_scene_to_file("res://scenes/main.tscn")
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


## Runs `n` fixed simulation steps (the test drives the clock itself).
func steps(n: int) -> void:
	for i in n:
		sim.step()
	await process_frame


func enemy_at(path: String, progress: float, speed: float = 0.0, hp_mult: float = 100.0) -> Enemy:
	var e := (load("res://scenes/enemy.tscn") as PackedScene).instantiate() as Enemy
	e.setup(load(path), hp_mult)
	e.speed = speed
	main.get_node("Level/EnemyPath").add_child(e)
	e.place(progress)
	return e


func clear_enemies() -> void:
	for node: Node in get_nodes_in_group(Enemy.GROUP):
		node.free()
	for node: Node in main.get_node("Level").get_children():
		if node is Projectile:
			node.free()


func _run() -> void:
	await frames(10)
	main = current_scene
	gs = main.get_node("GameState")
	bm = main.get_node("BuildManager")
	hero = main.get_node("Level/Hero")
	sim = main.get_node("Sim")
	sim.manual = true
	sim.running = true
	await _test_slow()
	await _test_projectiles()
	await _test_hero()
	_test_towers()
	_test_treasury()
	await _test_end_screen_back()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _test_slow() -> void:
	var fast := enemy_at(SLIME, 2.0)
	var slowed := enemy_at(SLIME, 2.0)
	fast.speed = 3.0
	slowed.speed = 3.0
	slowed.apply_slow(0.5, 5.0)
	slowed.apply_slow(0.9, 5.0)  # a weaker slow never loosens a stronger one
	var f0: float = fast.sim_progress
	var s0: float = slowed.sim_progress
	await steps(30)
	var ratio: float = (slowed.sim_progress - s0) / (fast.sim_progress - f0)
	check(absf(ratio - 0.5) < 0.1, "slow halves the speed (ratio %.2f)" % ratio)
	clear_enemies()
	var brief := enemy_at(SLIME, 2.0)
	brief.speed = 3.0
	brief.apply_slow(0.5, 0.2)
	await steps(30)  # the slow has expired
	var b0: float = brief.sim_progress
	await steps(15)
	var moved: float = brief.sim_progress - b0
	check(absf(moved - 3.0 * 0.5) < 0.2, "slow wears off (moved %.2f m in 0.5 s)" % moved)
	clear_enemies()


func _shot(scene: String, from: Vector3) -> Projectile:
	var p := (load(scene) as PackedScene).instantiate() as Projectile
	p.sim = sim
	main.get_node("Level").add_child(p)
	p.global_position = from
	return p


func _test_projectiles() -> void:
	# Arrow: homes in and hits for its damage.
	var target := enemy_at(SLIME, 4.0)
	var other := enemy_at(SLIME, 6.5)
	await steps(2)
	var arrow := _shot("res://scenes/projectiles/projectile_arrow.tscn", target.get_aim_point())
	arrow.global_position += Vector3(0.0, 1.0, 0.0)
	var hp: float = target.health
	var other_hp: float = other.health
	arrow.launch(target, 7.0)
	await steps(40)
	check(is_equal_approx(hp - target.health, 7.0), "arrow hits for its damage")
	check(not is_instance_valid(arrow), "arrow is gone after the hit")
	check(other.health == other_hp, "arrow hurts only its target")
	# Miss: the target vanishes in flight, the shot disappears harmlessly.
	var doomed := enemy_at(SLIME, 4.0)
	await steps(2)
	var stray := _shot("res://scenes/projectiles/projectile_arrow.tscn", doomed.get_aim_point())
	stray.global_position += Vector3(0.0, 3.0, 0.0)
	stray.launch(doomed, 7.0)
	doomed.free()
	other_hp = other.health
	await steps(10)
	check(not is_instance_valid(stray), "shot at a vanished target is removed")
	check(other.health == other_hp, "a miss hurts nobody else")
	clear_enemies()
	# Cannon: splash on the ground only.
	var centre := enemy_at(SLIME, 3.0)
	var near := enemy_at(SLIME, 3.6)
	var far := enemy_at(SLIME, 6.5)
	var bat := enemy_at("res://resources/enemies/slime_bat.tres", 3.3)
	await steps(2)
	var shell := _shot("res://scenes/projectiles/projectile_cannon.tscn", centre.global_position)
	shell.global_position += Vector3(0.0, 1.0, 0.0)
	var hps: Array[float] = [centre.health, near.health, far.health, bat.health]
	shell.launch(centre, 9.0, 1.2)
	await steps(90)
	check(is_equal_approx(hps[0] - centre.health, 9.0), "shell hits the target")
	check(is_equal_approx(hps[1] - near.health, 9.0), "splash hits a neighbour 0.6 m away")
	check(far.health == hps[2], "splash leaves an enemy 3.5 m away alone")
	check(bat.health == hps[3], "shells do not hit flying enemies")
	clear_enemies()
	# Frost: damage and slow.
	var cold := enemy_at(SLIME, 4.0)
	var warm := enemy_at(SLIME, 4.0)
	await steps(2)
	var shard := _shot("res://scenes/projectiles/projectile_frost.tscn", cold.get_aim_point())
	shard.global_position += Vector3(0.0, 1.0, 0.0)
	shard.launch(cold, 2.0, 0.0, 0.5, 5.0)
	await steps(40)
	cold.speed = 3.0
	warm.speed = 3.0
	var c0: float = cold.sim_progress
	var w0: float = warm.sim_progress
	await steps(20)
	var ratio: float = (cold.sim_progress - c0) / (warm.sim_progress - w0)
	check(absf(ratio - 0.5) < 0.1, "frost shard slows its target (ratio %.2f)" % ratio)
	clear_enemies()


func _test_hero() -> void:
	var a := enemy_at(SLIME, 4.0)
	var b := enemy_at(SLIME, 5.0)
	var c := enemy_at(SLIME, 6.0)
	await steps(2)
	var dir: Vector3 = (b.global_position - a.global_position).normalized()
	hero.global_position = a.global_position - dir
	hero.global_position.y = 0.0
	var damage: float = hero.attack_damage * hero.damage_multiplier
	var hp: Array[float] = [a.health, b.health, c.health]
	check(hero.try_attack(), "sword swings")
	await steps(30)
	check(is_equal_approx(hp[0] - a.health, damage), "sword hits the enemy in reach")
	check(b.health == hp[1] and c.health == hp[2], "sword does not reach enemies 2 m away")
	clear_enemies()
	await steps(40)  # swing cooldown
	var left := enemy_at(SLIME, 4.0)
	var mid := enemy_at(SLIME, 5.0)
	var right := enemy_at(SLIME, 6.0)
	var distant := enemy_at(SLIME, 8.0)
	await steps(2)
	hero.global_position = mid.global_position
	hero.global_position.y = 0.0
	var all: Array[Enemy] = [left, mid, right, distant]
	var before: Array[float] = []
	for e in all:
		before.append(e.health)
	check(hero.try_spin(), "whirlwind starts")
	var spin_damage: float = damage * hero.spin_damage_mult
	check(is_equal_approx(before[0] - left.health, spin_damage), "whirlwind hits the left one")
	check(
		is_equal_approx(before[1] - mid.health, spin_damage), "whirlwind hits the one at the hero"
	)
	check(is_equal_approx(before[2] - right.health, spin_damage), "whirlwind hits the right one")
	check(distant.health == before[3], "whirlwind spares an enemy 3 m away")
	check(not hero.try_spin(), "no second whirlwind during the cooldown")
	clear_enemies()


func _free_slot() -> TowerSlot:
	for node: Node in get_nodes_in_group(TowerSlot.GROUP):
		if (node as TowerSlot).is_free():
			return node as TowerSlot
	return null


func _test_towers() -> void:
	var data: TowerData = bm.tower_types[0]
	var slot: TowerSlot = _free_slot()
	gs.gold = 0
	gs.wood = 0
	check(not bm.build_on(slot, data) and slot.is_free(), "no build without money")
	gs.add_gold(1000)
	gs.add_wood(1000)
	var sold: Array[Vector2i] = []
	bm.tower_sold.connect(func(_s: TowerSlot, refund: Vector2i) -> void: sold.append(refund))
	check(bm.build_on(slot, data), "tower built")
	check(gs.gold == 1000 - data.cost_gold and gs.wood == 1000 - data.cost_wood, "price paid")
	var tower: Tower = slot.tower
	check(tower.level == 0, "new tower is level 1")
	var up: Vector2i = data.upgrade_cost(0)
	var gold: int = gs.gold
	var wood: int = gs.wood
	check(bm.upgrade(slot) and tower.level == 1, "upgrade works")
	check(gs.gold == gold - up.x and gs.wood == wood - up.y, "upgrade price paid")
	check(is_equal_approx(tower.damage, data.damage_levels[1] * bm.damage_multiplier), "damage up")
	# Selling returns SELL_REFUND of everything spent (build + upgrades).
	gold = gs.gold
	wood = gs.wood
	var spent: Vector2i = Vector2i(data.cost_gold + up.x, data.cost_wood + up.y)
	var refund := Vector2i(
		floori(spent.x * Balance.sell_refund()), floori(spent.y * Balance.sell_refund())
	)
	check(bm.sell(slot), "tower sold")
	check(gs.gold == gold + refund.x and gs.wood == wood + refund.y, "refund = 70%% of the spent")
	check(sold.size() == 1 and sold[0] == refund, "tower_sold reports the refund")
	check(slot.is_free() and slot.tower == null, "slot is free after selling")
	check(not bm.sell(slot), "an empty slot cannot be sold")
	check(bm.build_on(slot, data), "a sold slot can be built on again")
	# Top level: no further upgrade, nothing is charged.
	for i in data.max_level():
		bm.upgrade(slot)
	check(slot.tower.level == data.max_level(), "tower reaches the top level")
	gold = gs.gold
	check(not bm.upgrade(slot) and gs.gold == gold, "no upgrade past the top, no charge")
	# Too poor to upgrade: nothing changes.
	check(bm.sell(slot), "top tower sold")
	check(bm.build_on(slot, data), "built again")
	gs.gold = 0
	gs.wood = 0
	check(not bm.upgrade(slot) and slot.tower.level == 0, "no upgrade without money")
	gs.add_gold(1000)
	gs.add_wood(1000)
	bm.sell(slot)


func _test_treasury() -> void:
	Perks.reset()
	var walls: PerkData = Perks.get_perk(&"walls")
	check(not Perks.buy(walls) and Perks.level(&"walls") == 0, "no stars, no perk")
	LevelCatalog.complete(1, 3)
	LevelCatalog.save_endless(1, 999)
	check(Perks.endless_stars(1) == Perks.ENDLESS_MAX_STARS, "endless stars are capped")
	check(Perks.earned_stars() == 3 + Perks.ENDLESS_MAX_STARS, "earned = campaign + endless")
	var free: int = Perks.free_stars()
	check(Perks.buy(walls), "perk bought")
	check(Perks.free_stars() == free - walls.costs[0], "its price is spent")
	check(is_equal_approx(Perks.value(&"walls"), walls.values[0]), "perk value applies")
	check(Perks.buy(walls) and not Perks.buy(walls), "a perk stops at its max level")
	check(Perks.level(&"walls") == walls.max_level() and Perks.next_cost(walls) == -1, "max level")
	var unspent: int = Perks.free_stars()
	check(unspent >= 0, "free stars never negative")
	var greedy: PerkData = Perks.get_perk(&"towers")
	for i in 10:
		Perks.buy(greedy)
	check(Perks.free_stars() >= 0, "buying stops when the stars run out")
	Perks.reset()
	check(Perks.spent_stars() == 0 and Perks.free_stars() == Perks.earned_stars(), "reset refunds")


func tap_key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = pressed
		root.push_input(ev)
		await process_frame


func _test_end_screen_back() -> void:
	var screen: Control = main.get_node("HUD/Root/EndScreen")
	sim.manual = false
	gs.lose_lives(9999)
	await frames(3)
	check(screen.visible and paused, "defeat: end screen shown, game paused")
	await tap_key(KEY_P)
	check(screen.visible and paused and current_scene == main, "pause key does nothing here")
	main.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames(10)
	check(
		current_scene != null and current_scene.scene_file_path.ends_with("level_select.tscn"),
		"Back on the end screen leads to the map"
	)
	check(not paused, "the map is not paused")

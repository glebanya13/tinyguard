extends SceneTree
## The tower placement ghost (workbench -> tower -> placement mode) never repaints real
## towers: with a tower skin worn, the skin material is shared by every tower (and cached
## for the whole session), so the ghost must get its own materials and never recolour the
## skin. Opening the forge in the middle of a placement drops the ghost cleanly, and the
## next ghost is translucent again (not opaque, not stuck red). Also: a tap near (but not
## on) the castle, and a tap on an enemy by its walls, do not pop the forge card up.
## godot --headless --fixed-fps 60 --path . --script res://tests/test_placement_ghost.gd

const SAVE := "user://test_placement_ghost.cfg"
const SKIN := "tower_forest"

var fails := 0
var main: Node = null
var cards: CardController = null
var bm: BuildManager = null
var gs: GameState = null
var sim: Sim = null


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = SAVE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	LevelCatalog.selected_id = 1
	LevelCatalog.endless = false
	LevelCatalog.tutorial = false
	Cosmetics.preview[Cosmetics.TOWER] = SKIN
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _load_main() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await frames(10)
	main = current_scene
	cards = main.cards
	bm = main.get_node("BuildManager")
	gs = main.get_node("GameState")
	sim = main.get_node("Sim")
	(main.get_node("WaveManager") as WaveManager).stop()
	gs.add_gold(5000)
	gs.add_wood(5000)


func _run() -> void:
	var skin: Material = Cosmetics.material_for(SKIN)
	check(skin is StandardMaterial3D, "test skin %s has a material" % SKIN)
	if not skin is StandardMaterial3D:
		quit(1)
		return
	var skin_color: Color = (skin as StandardMaterial3D).albedo_color

	await _load_main()
	var tower: Tower = await _build_real_tower()
	check(tower != null, "a real tower is built")
	if tower == null:
		quit(1)
		return
	check(_all_meshes_use(tower, skin), "the real tower wears the tower skin")

	print("=== ghost over invalid and valid ground ===")
	await _start_placement(0)
	var ghost: Node3D = cards._placement_ghost
	check(ghost != null and is_instance_valid(ghost), "ghost created")
	check(_ghost_is_own(ghost, skin), "ghost meshes use the ghost's own translucent materials")
	var path_curve: Curve3D = sim.wave_manager.get_paths()[0].curve
	cards.on_placement_moved(path_curve.get_point_position(path_curve.point_count / 2))
	await frames(2)
	check(not cards.placement_valid, "ghost over the path is invalid")
	check(_ghost_tint(ghost).r > 0.8 and _ghost_tint(ghost).g < 0.5, "ghost is red over the path")
	cards.on_placement_moved(_valid_spot())
	await frames(2)
	check(cards.placement_valid, "ghost over free ground is valid")
	check(_ghost_tint(ghost).g > 0.8, "ghost is green over free ground")
	check(
		(skin as StandardMaterial3D).albedo_color == skin_color,
		"the shared skin material was not recoloured"
	)
	check(_all_meshes_use(tower, skin), "the real tower still wears the skin (not green)")

	print("=== forge in the middle of a placement, then a new placement ===")
	cards.toggle_forge()
	await frames(2)
	check(cards.forge_open and not cards.placement_mode, "forge replaces the placement")
	check(not is_instance_valid(ghost) or ghost.is_queued_for_deletion(), "old ghost removed")
	cards.toggle_forge()
	await frames(2)
	for attempt in 2:
		await _start_placement(1)
		ghost = cards._placement_ghost
		check(ghost != null and _ghost_is_own(ghost, skin), "ghost #%d is translucent" % attempt)
		cards.on_placement_moved(path_curve.get_point_position(path_curve.point_count / 2))
		await frames(2)
		cards.on_placement_moved(_valid_spot())
		await frames(2)
		check(_ghost_tint(ghost).g > 0.8, "ghost #%d is green again (not stuck red)" % attempt)
		cards.toggle_forge()
		await frames(2)
		cards.toggle_forge()
		await frames(2)
	check(
		(skin as StandardMaterial3D).albedo_color == skin_color,
		"skin material untouched after forge / workbench round trips"
	)
	check(_all_meshes_use(tower, skin), "real tower untouched after forge / workbench round trips")

	print("=== without a skin the ghost is still translucent ===")
	Cosmetics.preview[Cosmetics.TOWER] = ""
	await _start_placement(0)
	ghost = cards._placement_ghost
	check(ghost != null and _ghost_is_own(ghost, null), "ghost without a skin is translucent")
	cards.cancel_placement()
	await frames(2)
	Cosmetics.preview[Cosmetics.TOWER] = SKIN

	print("=== a new scene (continue from the map) ===")
	await _load_main()
	tower = await _build_real_tower()
	check(tower != null and _all_meshes_use(tower, skin), "a tower in the new scene wears the skin")
	check((skin as StandardMaterial3D).albedo_color == skin_color, "skin colour is the original")

	print("=== taps around the castle ===")
	var castle: Vector3 = cards.castle_position
	cards.on_ground_tapped(castle + Vector3(0.6, 0.0, 0.3))
	await frames(2)
	check(cards.forge_open, "a tap on the castle opens the forge")
	cards.toggle_forge()
	await frames(2)
	cards.on_ground_tapped(castle + Vector3(2.2, 0.0, 0.0))
	await frames(2)
	check(not cards.forge_open, "a tap 2.2 m off the castle does not open the forge")
	var slime: EnemyData = load("res://resources/enemies/slime.tres")
	var enemy: Enemy = sim.wave_manager.call("_spawn_enemy", {"data": slime, "hp": 1.0}, 1)
	await frames(2)
	if enemy != null and enemy.is_alive():
		# Set and tap in the same frame: the simulation moves it along its path.
		enemy.global_position = castle + Vector3(1.0, 0.0, 0.0)
		cards.on_ground_tapped(enemy.global_position)
		check(not cards.forge_open, "a tap on an enemy at the castle walls chases it, no forge")
	else:
		print("  skip enemy-at-the-walls tap (no enemy could be spawned)")

	Cosmetics.preview.erase(Cosmetics.TOWER)
	print("\nRESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _start_placement(index: int) -> void:
	cards.toggle_workbench()
	await frames(2)
	cards.on_command_pressed(StringName("build_%d" % index))
	await frames(2)
	check(cards.placement_mode, "placement mode for tower %d" % index)


func _build_real_tower() -> Tower:
	var slot: TowerSlot = null
	for node: Node in get_nodes_in_group(TowerSlot.GROUP):
		var s := node as TowerSlot
		if s != null and s.is_free():
			slot = s
			break
	if slot == null:
		return null
	var commands: GameCommands = main.get_node("GameCommands")
	commands.submit(GameCommand.build(slot.slot_id, 0))
	for i in 30:
		await process_frame
		if not slot.is_free():
			break
	return slot.tower


func _valid_spot() -> Vector3:
	var camps: Array = main.get_tree().get_nodes_in_group(&"camps")
	for x in range(-8, 9):
		for z in range(-8, 9):
			var p := Vector3(float(x), 0.0, float(z))
			if bm.is_valid_tower_placement(
				p, sim.wave_manager.get_paths(), sim.trees, cards.castle_position, camps
			):
				return p
	return Vector3.ZERO


## Meshes of a model, without the ghost's own rings.
func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		if node.name != "FootprintRing" and node.name != "RangeCircle":
			out.append(node as MeshInstance3D)
	return out


func _all_meshes_use(root: Node, material: Material) -> bool:
	var meshes: Array[MeshInstance3D] = _meshes(root)
	if meshes.is_empty():
		return false
	for mi: MeshInstance3D in meshes:
		if mi.material_override != material:
			return false
	return true


## Every tower mesh of the ghost carries a translucent material that is not `skin`.
func _ghost_is_own(ghost: Node, skin: Material) -> bool:
	var meshes: Array[MeshInstance3D] = _meshes(ghost)
	if meshes.is_empty():
		return false
	for mi: MeshInstance3D in meshes:
		var mat := mi.material_override as StandardMaterial3D
		if mat == null or mat == skin or mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			return false
	return true


func _ghost_tint(ghost: Node) -> Color:
	var meshes: Array[MeshInstance3D] = _meshes(ghost)
	if meshes.is_empty():
		return Color.BLACK
	var mat := meshes[0].material_override as StandardMaterial3D
	return mat.albedo_color if mat != null else Color.BLACK

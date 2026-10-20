class_name LevelBuilder
extends RefCounted
## Builds the selected level of resources/levels.json into the scene: terrain and
## decor models, choppable trees (one Grove), enemy paths with portals, the castle,
## tower slots, hero spot and camera bounds. Main reads `portals` and `castle`.

const MODEL_PATH := "res://assets/models/level_%d_%s.glb"
const SLOT_SCENE: PackedScene = preload("res://scenes/tower_slot.tscn")
const TREE_SCENE: PackedScene = preload("res://scenes/wood_tree.tscn")
const CASTLE_SCENE: PackedScene = preload("res://assets/models/castle.glb")
const PORTAL_SCENE: PackedScene = preload("res://assets/models/spawn_portal.glb")
const OUTPOST_SCENE: PackedScene = preload("res://scenes/outpost.tscn")
const NO_SHADOW := preload("res://scripts/no_shadow.gd")
## Height of the path curve above the ground.
const PATH_HEIGHT := 0.05
## Camera look-at area is the level bounds shrunk by this margin.
const CAMERA_MARGIN := 4.0

## Portals / outposts in path order (pulse when a wave comes out of them).
var portals: Array[Node3D] = []
var outposts: Array[Outpost] = []
var castle: Node3D = null

var _level: Dictionary = {}
var _root: Node3D = null
var _sim: Sim = null


static func ground(point: Array, height: float = 0.0) -> Vector3:
	return Vector3(float(point[0]), height, float(point[1]))


## Playable area of the map (metres).
static func map_rect(level: Dictionary) -> Rect2:
	var b: Array = level["bounds"]
	return Rect2(b[0], b[1], b[2], b[3])


## `enemy_path` is the scene's own Path3D (the first route); more routes get siblings.
func build(
	level: Dictionary,
	level_root: Node3D,
	enemy_path: Path3D,
	wave_manager: WaveManager,
	commands: GameCommands,
	sim: Sim,
	hero: Hero,
	camera: Camera3D
) -> void:
	_level = level
	_root = level_root
	_sim = sim
	portals.clear()
	outposts.clear()
	var decor_node: Node3D = null
	var id: int = int(level["id"])
	for part in ["terrain", "decor", "forest"]:
		var scene: PackedScene = load(MODEL_PATH % [id, part])
		var node: Node3D = scene.instantiate()
		# Ground, small props and the far forest cast no shadows (half the triangles
		# of the frame otherwise go to the shadow pass); trees and towers still do.
		node.set_script(NO_SHADOW)
		if part != "terrain":
			node.add_to_group(&"qg_" + part)  # the quality guard may hide them
		_root.add_child(node)
		if part == "decor":
			decor_node = node

	# One Path3D per entry: the scene's EnemyPath for the first, siblings for the rest.
	var paths: Array[Path3D] = []
	for route: PackedVector2Array in LevelCatalog.routes(level):
		var path3d: Path3D = enemy_path
		if not paths.is_empty():
			path3d = Path3D.new()
			path3d.name = "EnemyPath%d" % (paths.size() + 1)
			_root.add_child(path3d)
		var curve := Curve3D.new()
		for point: Vector2 in route:
			curve.add_point(Vector3(point.x, PATH_HEIGHT, point.y))
		path3d.curve = curve
		paths.append(path3d)

		var lane_idx: int = paths.size() - 1
		var first_dir: Vector3 = Vector3(route[1].x - route[0].x, 0.0, route[1].y - route[0].y)
		var portal: Node3D = PORTAL_SCENE.instantiate()
		portal.position = Vector3(route[0].x, 0.0, route[0].y)
		portal.rotation.y = atan2(first_dir.x, first_dir.z)
		_root.add_child(portal)
		portals.append(portal)

		var outpost := OUTPOST_SCENE.instantiate() as Outpost
		outpost.lane = lane_idx
		outpost.sim = _sim
		portal.add_child(outpost)
		outposts.append(outpost)
		if _sim != null:
			_sim.add_outpost(outpost)
	wave_manager.enemy_paths = paths

	if decor_node != null:
		_plant_trees(decor_node, outposts)

	wave_manager.build_air_paths(LevelCatalog.air_routes(level), _root, PATH_HEIGHT)

	var path: Array = level["paths"][0]
	var last_dir: Vector3 = (ground(path[-1]) - ground(path[-2])).normalized()
	castle = CASTLE_SCENE.instantiate()
	castle.position = ground(level["castle"])
	castle.rotation.y = atan2(-last_dir.x, -last_dir.z)
	_root.add_child(castle)
	Cosmetics.apply(castle, Cosmetics.castle_flag())  # banner skin: colours only

	for point: Array in level["slots"]:
		var slot := SLOT_SCENE.instantiate() as TowerSlot
		slot.slot_id = commands.slots.size()
		commands.slots.append(slot)
		slot.position = ground(point, PATH_HEIGHT)
		_root.add_child(slot)

	hero.position = ground(level["hero"])
	camera.bounds = map_rect(level).grow(-CAMERA_MARGIN)
	camera.snap()


## Replaces the Chop_<kind>_<i> markers of the decor model with choppable trees,
## and plants thicket grove trees around each outpost.
## Standing trees are drawn by one Grove (MultiMesh) to save draw calls.
func _plant_trees(decor: Node3D, active_outposts: Array[Outpost] = []) -> void:
	var grove := Grove.new()
	grove.name = "Grove"
	_root.add_child(grove)
	var trees: Array[WoodTree] = []
	var biome: String = _level.get("biome", "meadow")
	for marker: Node in decor.find_children("Chop_*", "Node3D", true, false):
		var spot := marker as Node3D
		var tree := TREE_SCENE.instantiate() as WoodTree
		var kind: String = String(spot.name).get_slice("_", 1)
		tree.variant = StringName(kind if biome == "meadow" else "%s_%s" % [kind, biome])
		tree.model_scale = spot.scale.x
		tree.grove = grove
		tree.sim = _sim
		tree.position = spot.global_position
		_root.add_child(tree)
		trees.append(tree)
		spot.queue_free()

	# Thicket grove trees around each outpost (MultiMesh, <= 24 trees per side)
	for outpost: Outpost in active_outposts:
		var thicket_spots: Array[Vector2] = LevelCatalog.outpost_thickets(_level, outpost.lane)
		for spot: Vector2 in thicket_spots:
			var tree := TREE_SCENE.instantiate() as WoodTree
			var thicket_kind: String = "pine_lite" if biome == "meadow" else "pine_%s" % biome
			if not ResourceLoader.exists(WoodTree.MODEL_PATH % thicket_kind):
				thicket_kind = "pine" if biome == "meadow" else "pine_%s" % biome
			tree.variant = StringName(thicket_kind)
			tree.grove = grove
			tree.sim = _sim
			tree.position = Vector3(spot.x, 0.0, spot.y)
			outpost.add_thicket_tree(tree)
			_root.add_child(tree)
			trees.append(tree)

	grove.build(trees)

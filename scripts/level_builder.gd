class_name LevelBuilder
extends RefCounted
## Builds the selected level of resources/levels.json into the scene: terrain and
## decor models, choppable trees (one Grove), enemy paths with portals, the castle,
## tower slots, hero spot and camera bounds. Main reads `portals` and `castle`.

const SLOT_SCENE: PackedScene = preload("res://scenes/tower_slot.tscn")
const TREE_SCENE: PackedScene = preload("res://scenes/wood_tree.tscn")
const CASTLE_SCENE: PackedScene = preload("res://assets/models/castle.glb")
const PORTAL_SCENE: PackedScene = preload("res://assets/models/spawn_portal.glb")
const NO_SHADOW := preload("res://scripts/no_shadow.gd")
## Height of the path curve above the ground.
const PATH_HEIGHT := 0.05
## Camera look-at area is the level bounds shrunk by this margin.
const CAMERA_MARGIN := 4.0

## Portals in path order (pulse when a wave comes out of them).
var portals: Array[Node3D] = []
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
	var id: int = int(level["id"])
	for part in ["terrain", "decor", "forest"]:
		var scene: PackedScene = LevelPrefetch.take(LevelPrefetch.model_path(id, part))
		var node: Node3D = scene.instantiate()
		# Ground, small props and the far forest cast no shadows (half the triangles
		# of the frame otherwise go to the shadow pass); trees and towers still do.
		node.set_script(NO_SHADOW)
		_root.add_child(node)
		if part == "decor":
			_plant_trees(node)
	LevelPrefetch.release()  # models asked for another level on the map are not kept

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

		var first_dir: Vector3 = Vector3(route[1].x - route[0].x, 0.0, route[1].y - route[0].y)
		var portal: Node3D = PORTAL_SCENE.instantiate()
		portal.position = Vector3(route[0].x, 0.0, route[0].y)
		portal.rotation.y = atan2(first_dir.x, first_dir.z)
		_root.add_child(portal)
		portals.append(portal)
	wave_manager.enemy_paths = paths

	wave_manager.build_air_paths(LevelCatalog.air_routes(level), _root, PATH_HEIGHT)

	var path: Array = level["paths"][0]
	var last_dir: Vector3 = (ground(path[-1]) - ground(path[-2])).normalized()
	castle = CASTLE_SCENE.instantiate()
	castle.position = ground(level["castle"])
	castle.rotation.y = atan2(-last_dir.x, -last_dir.z)
	_root.add_child(castle)

	for point: Array in level["slots"]:
		var slot := SLOT_SCENE.instantiate() as TowerSlot
		slot.slot_id = commands.slots.size()
		commands.slots.append(slot)
		slot.position = ground(point, PATH_HEIGHT)
		_root.add_child(slot)

	hero.position = ground(level["hero"])
	camera.bounds = map_rect(level).grow(-CAMERA_MARGIN)
	camera.snap()


## Replaces the Chop_<kind>_<i> markers of the decor model with choppable trees.
## Standing trees are drawn by one Grove (MultiMesh) to save draw calls.
func _plant_trees(decor: Node3D) -> void:
	var grove := Grove.new()
	grove.name = "Grove"
	_root.add_child(grove)
	var trees: Array[WoodTree] = []
	for marker: Node in decor.find_children("Chop_*", "Node3D", true, false):
		var spot := marker as Node3D
		var tree := TREE_SCENE.instantiate() as WoodTree
		var kind: String = String(spot.name).get_slice("_", 1)
		var biome: String = _level.get("biome", "meadow")
		tree.variant = StringName(kind if biome == "meadow" else "%s_%s" % [kind, biome])
		tree.model_scale = spot.scale.x
		tree.grove = grove
		tree.sim = _sim
		tree.position = spot.global_position
		_root.add_child(tree)
		trees.append(tree)
		spot.queue_free()
	grove.build(trees)

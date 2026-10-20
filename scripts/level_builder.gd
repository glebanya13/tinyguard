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
var lumberjack_camp: CampStructures.LumberjackCamp = null
var mercenary_camp: CampStructures.MercenaryCamp = null

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

	var path: Array = level["paths"][0]
	var last_dir: Vector3 = (ground(path[-1]) - ground(path[-2])).normalized()
	castle = CASTLE_SCENE.instantiate()
	castle.position = ground(level["castle"])
	castle.rotation.y = atan2(-last_dir.x, -last_dir.z)
	_root.add_child(castle)
	Cosmetics.apply(castle, Cosmetics.castle_flag())  # banner skin: colours only

	# Camp structures: lumberjack camp near trees/village, mercenary camp on defense perimeter
	var camp_positions: Dictionary = find_camp_positions(level, castle.position, decor_node, outposts)

	if decor_node != null:
		_plant_trees(decor_node, outposts)

	wave_manager.build_air_paths(LevelCatalog.air_routes(level), _root, PATH_HEIGHT)

	lumberjack_camp = CampStructures.create_lumberjack_camp()
	lumberjack_camp.position = camp_positions["lumberjack"]
	_root.add_child(lumberjack_camp)

	mercenary_camp = CampStructures.create_mercenary_camp()
	mercenary_camp.position = camp_positions["mercenary"]
	mercenary_camp.sim = _sim
	mercenary_camp.hero = hero
	mercenary_camp.gate_position = castle.position
	_root.add_child(mercenary_camp)

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
## Ensures no tree ever spawns within 3.0m of lumberjack_camp or mercenary_camp.
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


## Finds clear positions for lumberjack camp (towards trees) and mercenary camp (defensive flank),
## ensuring both are 6-10m from the castle, at least 3.5m away from any tower slot,
## at least 2.5m away from all enemy paths, and prioritizing distance from trees (dt >= 2.0m).
static func find_camp_positions(
	level: Dictionary,
	castle_pos: Vector3,
	decor: Node3D = null,
	active_outposts: Array = []
) -> Dictionary:
	var slots: Array = level.get("slots", [])
	var paths: Array = level.get("paths", [])
	var bounds: Array = level.get("bounds", [-22.0, -15.0, 44.0, 30.0])
	var trees: Array = level.get("trees", [])
	var min_x: float = float(bounds[0]) + 2.0
	var min_z: float = float(bounds[1]) + 2.0
	var max_x: float = float(bounds[0]) + float(bounds[2]) - 2.0
	var max_z: float = float(bounds[1]) + float(bounds[3]) - 2.0

	var all_trees: Array[Vector2] = []
	for t_val in trees:
		all_trees.append(Vector2(float(t_val[0]), float(t_val[1])))
	if decor != null:
		for marker: Node in decor.find_children("Chop_*", "Node3D", true, false):
			var spot := marker as Node3D
			all_trees.append(Vector2(spot.global_position.x, spot.global_position.z))
	for outpost in active_outposts:
		var lane: int = outpost.lane if outpost is Outpost else int(outpost)
		for spot: Vector2 in LevelCatalog.outpost_thickets(level, lane):
			all_trees.append(spot)

	var radii: Array[float] = [7.0, 8.0, 9.0, 10.0, 6.5, 7.5, 8.5, 9.5, 6.0]

	for min_dt in [2.5, 2.0, 1.5, 1.0, 0.5, 0.0]:
		var candidates: Array[Dictionary] = []
		for r in radii:
			for deg in range(0, 360, 5):
				var rad: float = deg_to_rad(float(deg))
				var x: float = castle_pos.x + r * cos(rad)
				var z: float = castle_pos.z + r * sin(rad)
				if x < min_x or x > max_x or z < min_z or z > max_z:
					continue
				var p2 := Vector2(x, z)
				var ds: float = _min_dist_to_slots(p2, slots)
				if ds < 3.5:
					continue
				var dp: float = _min_dist_to_paths(p2, paths)
				if dp < 2.5:
					continue
				var dt: float = 10.0
				if not all_trees.is_empty():
					for t_pos in all_trees:
						dt = minf(dt, p2.distance_to(t_pos))
					if dt < min_dt:
						continue
				candidates.append({
					"pos": Vector3(x, 0.0, z),
					"p2": p2,
					"r": r,
					"ds": ds,
					"dp": dp,
					"dt": dt
				})

		var best_pair_score: float = -1e9
		var best_lj: Vector3 = Vector3.ZERO
		var best_merc: Vector3 = Vector3.ZERO
		var found_pair := false

		for c1 in candidates:
			for c2 in candidates:
				var sep: float = c1["p2"].distance_to(c2["p2"])
				if sep < 5.0:
					continue
				var score: float = sep + c1["ds"] + c1["dp"] + c2["ds"] + c2["dp"] + c1["dt"] * 0.5 + c2["dt"] * 0.5
				if score > best_pair_score:
					best_pair_score = score
					best_lj = c1["pos"]
					best_merc = c2["pos"]
					found_pair = true

		if found_pair:
			return {
				"lumberjack": best_lj,
				"mercenary": best_merc
			}

	return {
		"lumberjack": castle_pos + Vector3(7.0, 0.0, -4.0),
		"mercenary": castle_pos + Vector3(-7.0, 0.0, 5.0)
	}


static func _dist_to_segment_2d(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	var proj := a + ab * t
	return p.distance_to(proj)


static func _min_dist_to_paths(p: Vector2, paths: Array) -> float:
	var min_d: float = INF
	for route_val in paths:
		var route: Array = route_val as Array
		for i in range(route.size() - 1):
			var a := Vector2(float(route[i][0]), float(route[i][1]))
			var b := Vector2(float(route[i + 1][0]), float(route[i + 1][1]))
			min_d = minf(min_d, _dist_to_segment_2d(p, a, b))
	return min_d


static func _min_dist_to_slots(p: Vector2, slots: Array) -> float:
	var min_d: float = INF
	for s_val in slots:
		var s: Array = s_val as Array
		var s_pos := Vector2(float(s[0]), float(s[1]))
		min_d = minf(min_d, p.distance_to(s_pos))
	return min_d

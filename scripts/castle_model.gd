class_name CastleModel
extends RefCounted
## Look of the castle by upgrade level. castle.glb is the plain castle; castle_lv1..lv4.glb are
## the same body with the decorations of upgrades 1..N baked into ONE mesh (gold bands, caps,
## spires, a crystal), so the castle is one draw call at any level: only the mesh of its body
## node is swapped, the skin (material override) stays. Pure looks: nothing here is simulated.

const PATH := "res://assets/models/castle_lv%d.glb"

static var _meshes: Dictionary = {}


## Body mesh of the castle at `level` (null for 0: the plain model).
static func mesh_for(level: int) -> Mesh:
	if level <= 0 or level > CastleUpgrades.max_level():
		return null
	if not _meshes.has(level):
		var scene: PackedScene = load(PATH % level) as PackedScene
		var root: Node = scene.instantiate()
		var body := _body_of(root)
		_meshes[level] = body.mesh if body != null else null
		root.free()
	return _meshes[level]


## Shows the castle `root` (an instance of castle.glb) at upgrade `level`.
static func show_level(root: Node, level: int) -> void:
	var body := _body_of(root)
	if body == null:
		return
	if not root.has_meta(&"plain_mesh"):
		root.set_meta(&"plain_mesh", body.mesh)  # level 0 comes back from here
	var mesh: Mesh = mesh_for(level)
	body.mesh = mesh if mesh != null else root.get_meta(&"plain_mesh") as Mesh


## The body mesh node of a castle model (the first mesh; the collider is not a mesh).
static func _body_of(root: Node) -> MeshInstance3D:
	var found: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	return found[0] as MeshInstance3D if not found.is_empty() else null

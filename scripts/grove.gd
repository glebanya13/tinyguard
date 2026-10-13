class_name Grove
extends Node3D
## Draws all standing trees of a level with one MultiMeshInstance3D per tree
## model (one draw call each instead of one per tree). A tree that shakes,
## falls or grows hides its instance here and shows its own animated copy.

var _multimeshes: Dictionary = {}  # variant -> MultiMesh
var _slots: Dictionary = {}  # WoodTree -> [variant, index]


## Builds the instances. Call once, after every tree entered the scene tree.
func build(trees: Array[WoodTree]) -> void:
	var by_variant: Dictionary = {}
	for tree in trees:
		by_variant.get_or_add(tree.variant, []).append(tree)
	for variant: StringName in by_variant:
		var list: Array = by_variant[variant]
		var model: Node = WoodTree.model_scene(variant).instantiate()
		var mesh_node := model as MeshInstance3D
		if mesh_node == null:
			mesh_node = model.find_children("*", "MeshInstance3D", true, false)[0]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh_node.mesh
		multimesh.instance_count = list.size()
		model.free()
		for i in list.size():
			var tree: WoodTree = list[i]
			multimesh.set_instance_transform(
				i, global_transform.affine_inverse() * tree.model_transform()
			)
			_slots[tree] = [variant, i]
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		add_child(instance)
		_multimeshes[variant] = multimesh


func set_tree_visible(tree: WoodTree, shown: bool) -> void:
	var slot: Array = _slots.get(tree, [])
	if slot.is_empty():
		return
	var multimesh: MultiMesh = _multimeshes[slot[0]]
	var xform: Transform3D = global_transform.affine_inverse() * tree.model_transform()
	if not shown:
		xform.basis = Basis.from_scale(Vector3.ZERO)
	multimesh.set_instance_transform(slot[1], xform)

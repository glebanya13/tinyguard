extends SceneTree
## Triangles per mesh of models (assets/models/<name>.glb):
## godot --headless --script res://tools/count_tris.gd -- level_1_terrain castle


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var scene: PackedScene = load("res://assets/models/%s.glb" % arg)
		var root: Node = scene.instantiate()
		var total := 0
		print("== ", arg)
		for n in root.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var t := 0
			for s in mi.mesh.get_surface_count():
				var arrays := mi.mesh.surface_get_arrays(s)
				if arrays[Mesh.ARRAY_INDEX] != null:
					t += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
				else:
					t += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			total += t
			print("  %s: %d tris, %d surf" % [n.name, t, mi.mesh.get_surface_count()])
		print("  TOTAL ", total)
	quit()

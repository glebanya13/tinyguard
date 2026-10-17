extends SceneTree
## Texture memory by group (needs a window, NOT --headless): loads the PNGs of every group
## and a few key scenes and prints how much RENDERING_INFO_TEXTURE_MEM_USED grew.
## godot --path . --resolution 1280x720 --script res://tools/probe_tex.gd

var _keep: Array = []


func _mb() -> float:
	return (
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)
		/ 1048576.0
	)


func _group(label: String, dir: String) -> void:
	var before: float = _mb()
	var n := 0
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".png.import") or f.ends_with(".png"):
			var path: String = dir + "/" + f.trim_suffix(".import")
			_keep.append(load(path))
			n += 1
	await process_frame
	await process_frame
	print("%-28s %3d files  +%.2f MB" % [label, n, _mb() - before])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	print("engine start: %.2f MB" % _mb())
	await _group("ui/icons", "res://ui/icons")
	await _group("ui/biomes", "res://ui/biomes")
	await _group("assets/materials", "res://assets/materials")
	await _group("assets/materials/skins", "res://assets/materials/skins")
	var before: float = _mb()
	_keep.append(load("res://ui/theme.tres"))
	_keep.append(load("res://ui/theme_atlas.png"))
	await process_frame
	print("theme + atlas                 +%.2f MB" % (_mb() - before))
	print("total after probes: %.2f MB" % _mb())
	quit()

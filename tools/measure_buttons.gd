extends SceneTree
## Lists visible buttons smaller than 48 dp (84 canvas px = 48 dp on a 1080p, 420 dpi phone;
## canvas height 720) on the map, a level with a selected tower and the tutorial.
## Needs a window: godot --path . --rendering-driver opengl3 --resolution 2160x1080 \
##   --script res://tools/measure_buttons.gd

const MIN_SIDE := 84.0


func _initialize() -> void:
	LevelCatalog.save_path = "user://measure_buttons.cfg"
	LevelCatalog.erase_all()
	Onboarding.set_local_nickname("Тест", "тест", false)
	for id in [1, 2, 3]:
		LevelCatalog.complete(id, 3)
	_run.call_deferred()


func _run() -> void:
	LevelCatalog.selected_id = 3
	change_scene_to_file("res://scenes/level_select.tscn")
	await _frames(30)
	_report("map")
	current_scene.call("_open_treasury")
	await _frames(10)
	_report("treasury")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.get_node("HUD").set("_touch", true)
	root.remove_child(current_scene)
	root.add_child(main)
	current_scene = main
	await _frames(10)
	var gs: GameState = main.get_node("GameState")
	var bm: BuildManager = main.get_node("BuildManager")
	gs.add_gold(500)
	gs.add_wood(500)
	var slot: TowerSlot = get_nodes_in_group(TowerSlot.GROUP)[0]
	bm.select_slot(slot)
	await _frames(10)
	_report("level, free slot")
	bm.build_on(slot, bm.tower_types[0])
	bm.clear_selection()
	bm.select_slot(slot)
	await _frames(10)
	_report("level, tower selected")
	main.get_node("HUD").call("show_pause_menu")
	await _frames(10)
	_report("level, pause menu")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _report(label: String) -> void:
	var scale: float = float(DisplayServer.window_get_size().y) / 720.0
	print("== %s (window %s)" % [label, DisplayServer.window_get_size()])
	var small: int = 0
	for node: Node in _all(root):
		var button := node as BaseButton
		if button == null or not button.is_visible_in_tree():
			continue
		var r: Rect2 = button.get_global_rect()
		if r.size.x < MIN_SIDE or r.size.y < MIN_SIDE:
			small += 1
			print("  small %s %s canvas px" % [button.get_path(), r.size.round()])
	print("  small buttons: %d (1 canvas px = %.2f window px)" % [small, scale])


func _all(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child in node.get_children():
		out.append_array(_all(child))
	return out

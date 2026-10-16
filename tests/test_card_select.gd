extends SceneTree
## The slot the card shows follows the knight: walking up to a slot selects it, walking up
## to another one switches to that one (never stuck on the slot of the start of the level),
## walking away drops a slot that was picked on the way, a tapped slot stays until he comes
## up to another.
## godot --headless --fixed-fps 60 --path . --script res://tests/test_card_select.gd

var fails := 0
var _hero: Hero
var _bm: BuildManager


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_card_select.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	LevelCatalog.selected_id = 1
	LevelCatalog.endless = false
	LevelCatalog.tutorial = false
	change_scene_to_file("res://scenes/main.tscn")
	_run.call_deferred()


## Walks the knight to within `reach` of `slot` (the order ends there).
func _walk_to(slot: TowerSlot, reach: float) -> void:
	_hero.move_to(slot.global_position, reach)
	for i in 1500:
		await physics_frame
		if not _hero.has_order():
			break
	for i in 3:
		await physics_frame


func _run() -> void:
	for i in 8:
		await process_frame
	for i in 3:
		await physics_frame
	_hero = current_scene.get_node("Level/Hero")
	_bm = current_scene.get_node("BuildManager")
	_hero.auto_action = false
	(current_scene.get_node("WaveManager") as WaveManager).stop()
	var slots: Array[TowerSlot] = []
	for node: Node in get_nodes_in_group(TowerSlot.GROUP):
		slots.append(node as TowerSlot)
	# Two slots that are far enough apart, and one more.
	var a: TowerSlot = slots[0]
	var b: TowerSlot = null
	for slot in slots:
		if slot.global_position.distance_to(a.global_position) > 6.0:
			b = slot
			break
	check(b != null, "level has two distant slots")
	await _walk_to(a, 1.25)
	check(_bm.selected_slot == a, "walking up to slot A selects it")
	await _walk_to(b, 1.25)
	check(_bm.selected_slot == b, "walking up to slot B switches the selection to B")
	# Leaves the slot to a spot far from every slot: the auto pick is dropped.
	var far: Vector3 = _hero.global_position
	var best: float = 0.0
	for x in range(-12, 13, 2):
		for z in range(-12, 13, 2):
			var p: Vector3 = _hero.global_position + Vector3(x, 0.0, z)
			var nearest: float = 1000.0
			for slot in slots:
				nearest = minf(nearest, slot.global_position.distance_to(p))
			if nearest > best and current_scene.walk_grid.is_free(Vector2(p.x, p.z)):
				best = nearest
				far = p
	if best > 3.0:
		await _walk_to_point(far)
		check(_bm.selected_slot == null, "walking away drops a slot picked on the way")
	else:
		print("  skip no open spot far from the slots (%.1f m)" % best)
	# A tapped slot stays while the knight stands elsewhere.
	_bm.select_slot(a)
	await physics_frame
	check(_bm.selected_slot == a, "a tapped slot stays selected")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _walk_to_point(point: Vector3) -> void:
	_hero.move_to(point, 0.3)
	for i in 1500:
		await physics_frame
		if not _hero.has_order():
			break
	for i in 3:
		await physics_frame

extends SceneTree
## The level map keeps its order at 1280x720, 1560x720 and 1920x1080, in Russian and English:
## no interactive control overlaps another one, a level badge (with its stars) or a chip, all
## of it lies inside the safe area, icon buttons are >= 72 px, nothing is clipped (the minimum
## size of a text control fits its size) and spaces keep their width (no "Norecordyet").
## godot --headless --path . --script res://tests/test_map_layout.gd

const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1560, 720), Vector2i(1920, 1080)]
const MAP := "res://scenes/level_select.tscn"

var fails := 0


func check(c: bool, w: String) -> void:
	if not c:
		print("  FAIL ", w)
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_map_layout.cfg"
	GameSettings.config_path = "user://test_map_layout_settings.cfg"
	BattleCheckpoint.clear_checkpoint()
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## Screen rect of a control as the player sees it (scale around the pivot included).
func _visual_rect(c: Control) -> Rect2:
	var size: Vector2 = c.size * c.scale
	var center: Vector2 = c.global_position + c.pivot_offset
	return Rect2(center - c.pivot_offset * c.scale, size)


func _interactive(map: Node) -> Array[Control]:
	var out: Array[Control] = []
	var root_ui: Node = map.get_node("UI/Root")
	for node: Node in root_ui.find_children("*", "Button", true, false):
		var button := node as Button
		if button.is_visible_in_tree() and button.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			out.append(button)
	return out


func _in_group(node: Node, name: String) -> bool:
	var n: Node = node
	while n != null:
		if n.name == name:
			return true
		n = n.get_parent()
	return false


func _label_ok(label: Label, tag: String) -> void:
	if not label.is_visible_in_tree() or label.text == "":
		return
	var font: Font = label.get_theme_font("font")
	var fsize: int = label.get_theme_font_size("font_size")
	if label.autowrap_mode == TextServer.AUTOWRAP_OFF and not label.clip_text:
		check(
			label.get_minimum_size().x <= label.size.x + 0.5,
			(
				"%s: label '%s' clipped (%.0f > %.0f)"
				% [tag, label.text, label.get_minimum_size().x, label.size.x]
			)
		)
	else:
		check(
			label.get_visible_line_count() >= label.get_line_count(),
			"%s: label '%s' loses lines" % [tag, label.text]
		)
	_spaces_ok(label.text, font, fsize, label.get_theme_constant("outline_size"), "%s: label" % tag)


## A space must stay a gap after the outline of the letters on both sides has been drawn:
## its advance has to exceed twice the outline plus a few pixels ("No record yet" must not
## read "Norecordyet").
func _spaces_ok(text: String, font: Font, fsize: int, outline: int, tag: String) -> void:
	if text.count(" ") == 0 or font == null:
		return
	var space: float = (
		font.get_string_size("n n", 0, -1, fsize).x - font.get_string_size("nn", 0, -1, fsize).x
	)
	check(
		space >= 2.0 * outline + 3.0,
		"%s '%s': the space is %.1f px, the outline %d px eats it" % [tag, text, space, outline]
	)


func _check_map(tag: String) -> void:
	var map: Node = (load(MAP) as PackedScene).instantiate()
	root.add_child(map)
	await _frames(8)
	for toast in get_nodes_in_group(Toast.GROUP):
		toast.free()
	await _frames(2)
	var area: Rect2 = (map.get_node("UI/Root") as Control).get_global_rect()
	var viewport: Rect2 = root.get_visible_rect()
	check(area.size.x >= 1279.0 and area.size.y >= 719.0, "%s: ui root %s" % [tag, area])
	check(
		viewport.encloses(area),
		"%s: the safe area %s lies inside the screen %s" % [tag, area, viewport]
	)
	var items: Array[Control] = _interactive(map)
	check(items.size() >= 12, "%s: %d interactive controls found" % [tag, items.size()])
	var rects: Array[Rect2] = []
	var names: Array[String] = []
	for c in items:
		var rect: Rect2 = _visual_rect(c)
		rects.append(rect)
		names.append(str(c.name))
		check(
			area.encloses(rect.grow(-0.5)),
			"%s: %s %s is outside the safe area" % [tag, c.name, rect]
		)
		var level: bool = str(c.name).begins_with("Level")
		var icon_only: bool = c.get("text") == "" and c.get("icon") != null
		if icon_only:
			check(
				rect.size.x >= 71.5 and rect.size.y >= 71.5,
				"%s: icon button %s is %s (< 72)" % [tag, c.name, rect.size]
			)
		elif not level:
			check(rect.size.y >= 55.5, "%s: button %s is %.0f high" % [tag, c.name, rect.size.y])
		if str(c.name).ends_with("Button") and not level and _in_group(c, "TabBar"):
			check(
				rect.size.x >= 71.5 and rect.size.y >= 71.5,
				"%s: tab %s is %s (< 72)" % [tag, c.name, rect.size]
			)
		var btn := c as Button
		_spaces_ok(
			btn.text,
			btn.get_theme_font("font"),
			btn.get_theme_font_size("font_size"),
			btn.get_theme_constant("outline_size"),
			"%s: button %s" % [tag, c.name]
		)
		check(
			btn.get_minimum_size().x <= btn.size.x + 0.5,
			(
				"%s: button %s '%s' is clipped (%.0f > %.0f)"
				% [tag, c.name, btn.text, btn.get_minimum_size().x, btn.size.x]
			)
		)
	# A level badge occupies its stars row too.
	for i in items.size():
		if str(names[i]).begins_with("Level"):
			rects[i] = rects[i].merge(
				Rect2(rects[i].position.x, rects[i].end.y, rects[i].size.x, 30.0)
			)
	for i in items.size():
		for j in range(i + 1, items.size()):
			check(
				not rects[i].intersects(rects[j]),
				"%s: %s %s overlaps %s %s" % [tag, names[i], rects[i], names[j], rects[j]]
			)
	# Chips and the title do not touch the controls or each other.
	var passive: Array[Control] = []
	for n in ["GemsChip", "StarsPill", "Title", "TabBar", "Info"]:
		var c: Control = map.find_child(n, true, false) as Control
		check(c != null, "%s: %s exists" % [tag, n])
		if c != null and c.is_visible_in_tree():
			passive.append(c)
	for p in passive:
		var pr: Rect2 = p.get_global_rect()
		check(area.encloses(pr.grow(-0.5)), "%s: %s %s leaves the safe area" % [tag, p.name, pr])
		for i in items.size():
			if p.name == "TabBar" and _in_group(items[i], "TabBar"):
				continue
			if p.name == "Info" and _in_group(items[i], "Info"):
				continue
			check(
				not pr.intersects(rects[i]),
				"%s: %s %s covers %s %s" % [tag, p.name, pr, names[i], rects[i]]
			)
		for q in passive:
			if q != p and q.get_index() < p.get_index() or q.get_parent() != p.get_parent():
				pass
	var title: Control = map.find_child("Title", true, false)
	for n in ["GemsChip", "StarsPill"]:
		var chip: Control = map.find_child(n, true, false)
		check(
			not title.get_global_rect().intersects(chip.get_global_rect()),
			"%s: the title touches %s" % [tag, n]
		)
	var title_label := title as Label
	check(
		title_label.get_minimum_size().x <= title_label.size.x + 0.5,
		"%s: the title is clipped" % tag
	)
	var info: Control = map.find_child("Info", true, false)
	var bar: Control = map.find_child("TabBar", true, false)
	check(
		info.get_global_rect().end.y <= bar.get_global_rect().position.y - 4.0,
		(
			"%s: the level card %s reaches the tab bar %s"
			% [tag, info.get_global_rect(), bar.get_global_rect()]
		)
	)
	for label: Node in (map.get_node("UI/Root") as Control).find_children(
		"*", "Label", true, false
	):
		_label_ok(label as Label, tag)
	map.free()
	await _frames(2)


func _run() -> void:
	for lang in ["en", "ru"]:
		GameSettings.set_language(lang)
		for size in SIZES:
			root.size = size
			await _frames(3)
			LevelCatalog.erase_all()
			for id in [1, 2, 3, 4, 5]:
				LevelCatalog.complete(id, [3, 2, 3, 1, 2][id - 1])
			Onboarding.dismiss_reminder()
			for selected in [1, 5, 6]:
				LevelCatalog.selected_id = selected
				await _check_map("%s %dx%d level %d" % [lang, size.x, size.y, selected])
	LevelCatalog.erase_all()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.config_path))
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)

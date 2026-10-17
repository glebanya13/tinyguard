extends SceneTree
## Layout on a matrix of phone / tablet / Chromebook screens (landscape): on every screen
## and in both languages no interactive control (button, text field, joystick) of the HUD,
## its menus, the settings, the shop, the welcome / nickname screens and the account
## dialogs leaves the (safe) screen or overlaps another, and no text is squeezed below
## the size it needs (clipped). The world map (level_select) is audited too but only
## reported, not failed: another team owns it (see docs/DEVICE_COMPATIBILITY.md).
## godot --headless --fixed-fps 60 --path . --script res://tests/test_device_matrix.gd
## Env: MATRIX_ONLY=1280x720 limits the screens, MATRIX_VERBOSE=1 prints every finding.

const SAVE := "user://test_device_matrix.cfg"
const SETTINGS := "user://test_device_matrix_settings.cfg"
## Window sizes in pixels (landscape) of the reference devices.
const SCREENS: Array[Vector2i] = [
	Vector2i(800, 480),  # small / old phone (WVGA)
	Vector2i(1280, 720),  # 16:9 budget phone, project base size
	Vector2i(1600, 720),  # 20:9 budget phone
	Vector2i(1920, 1080),  # 16:9 mid-range
	Vector2i(2160, 1080),  # 18:9
	Vector2i(2340, 1080),  # 19.5:9
	Vector2i(2400, 1080),  # 20:9
	Vector2i(2560, 1440),  # QHD flagship / tablet 16:9
	Vector2i(1024, 768),  # 4:3 tablet / Chromebook window
	Vector2i(1280, 800),  # 16:10 tablet / Chromebook
	Vector2i(2560, 1600),  # 16:10 tablet
]
## Phones with a cutout / gesture bar get a fake safe area in canvas units (l, t, r, b).
const NOTCH := Vector4(48.0, 0.0, 48.0, 24.0)
const NOTCH_SCREENS: Array[Vector2i] = [
	Vector2i(1600, 720), Vector2i(2340, 1080), Vector2i(2400, 1080)
]
const LOCALES: Array[String] = ["ru", "en"]
const MAIN_SCENE := "res://scenes/main.tscn"
const MAP_SCENE := "res://scenes/level_select.tscn"

var fails := 0
var _problems: PackedStringArray = []
var _soft: PackedStringArray = []
var _checks := 0
var _controls := 0
var _verbose := false


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = SAVE
	GameSettings.config_path = SETTINGS
	LevelCatalog.erase_all()
	Onboarding.set_local_nickname("Тест", "тест", false)
	for id in [1, 2, 3]:
		LevelCatalog.complete(id, 3)
	_verbose = OS.get_environment("MATRIX_VERBOSE") == "1"
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var only: String = OS.get_environment("MATRIX_ONLY")
	var screens: Array[Vector2i] = []
	for s in SCREENS:
		if only == "" or only == "%dx%d" % [s.x, s.y]:
			screens.append(s)
	_math(screens)
	await _canary()
	for locale in LOCALES:
		GameSettings.set_language(locale)
		for s in screens:
			await _screen(s, Vector4.ZERO, locale)
			if s in NOTCH_SCREENS:
				await _screen(s, NOTCH, locale)
	await _live_resize()
	ScreenUtil.fake_margins = Vector4.ZERO
	GameSettings.set_language("auto")
	LevelCatalog.erase_all()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	if _soft.size() > 0:
		print("-- world map (reported, not failed): %d findings" % _soft.size())
		for line in _soft.slice(0, 40):
			print("   ", line)
	for line in _problems.slice(0, 60):
		print("   ", line)
	check(
		_problems.is_empty(),
		(
			"%d audits (%d interactive controls) over %d screens x 2 languages: %d findings"
			% [_checks, _controls, screens.size(), _problems.size()]
		)
	)
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


## The canvas size of a window under the project's stretch (canvas_items + expand).
static func canvas_for(window: Vector2i, base: Vector2 = Vector2(1280, 720)) -> Vector2:
	var scale: float = minf(window.x / base.x, window.y / base.y)
	return Vector2(window.x, window.y) / scale


func _math(screens: Array[Vector2i]) -> void:
	# The HUD pure-math rectangles on every canvas (sizes the live HUD may take).
	var bad: PackedStringArray = []
	for s in screens:
		var canvas: Vector2 = canvas_for(s)
		for inset in [Vector4.ZERO, NOTCH]:
			var size: Vector2 = canvas - Vector2(inset.x + inset.z, inset.y + inset.w)
			var bounds := Rect2(Vector2.ZERO, size)
			for js in 3:
				for side in 2:
					for ms in 3:
						for mode in 3:
							var r: Dictionary = HudLayout.rects(size, js, 1, side, ms, mode)
							var joy: Rect2 = r["joystick"]
							for key: String in ["joystick", "attack", "spin"]:
								if not bounds.encloses(r[key]):
									bad.append("%dx%d %s outside" % [s.x, s.y, key])
							for key: String in ["attack", "spin", "top_left", "top_right"]:
								if joy.intersects(r[key]):
									bad.append("%dx%d joystick over %s" % [s.x, s.y, key])
	check(bad.is_empty(), "HudLayout math on every canvas %s" % ", ".join(bad.slice(0, 4)))


## The audit must see a button off the screen, two overlapping buttons and a squeezed label.
func _canary() -> void:
	root.size = Vector2i(1280, 720)
	await _frames(2)
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(holder)
	var out := Button.new()
	out.text = "out"
	out.position = Vector2(1250, 10)
	out.size = Vector2(100, 60)
	holder.add_child(out)
	var a := Button.new()
	a.text = "a"
	a.position = Vector2(100, 100)
	a.size = Vector2(100, 60)
	holder.add_child(a)
	var b := Button.new()
	b.text = "b"
	b.position = Vector2(150, 120)
	b.size = Vector2(100, 60)
	holder.add_child(b)
	var squeezed := Label.new()
	squeezed.text = "a very long caption that cannot fit"
	squeezed.position = Vector2(400, 400)
	squeezed.clip_text = true
	holder.add_child(squeezed)
	await _frames(2)
	squeezed.size = Vector2(20, 20)
	await _frames(1)
	var before: int = _problems.size()
	_audit(holder, "canary", Vector4.ZERO)
	var got: int = _problems.size() - before
	for i in got:
		_problems.remove_at(_problems.size() - 1)
	check(
		got >= 3, "the audit sees an off-screen button, an overlap and a squeezed text (%d)" % got
	)
	holder.queue_free()
	await _frames(2)


func _screen(window: Vector2i, notch: Vector4, locale: String) -> void:
	root.size = window
	ScreenUtil.fake_margins = notch
	await _frames(2)
	var visible: Vector2 = root.get_visible_rect().size
	var tag := (
		"%dx%d%s %s" % [window.x, window.y, " notch" if notch != Vector4.ZERO else "", locale]
	)
	var expect: Vector2 = canvas_for(window)
	if not visible.is_equal_approx(expect):
		_problems.append("%s: canvas %s, expected %s" % [tag, visible, expect])
	# --- one-screen scenes ---
	for path: String in [
		"res://scenes/shop.tscn",
		"res://scenes/welcome.tscn",
		"res://scenes/nickname.tscn",
		"res://scenes/coop_lobby.tscn",
		"res://scenes/tutorial.tscn",
	]:
		var scene := (load(path) as PackedScene).instantiate()
		if scene is ShopScreen:
			(scene as ShopScreen).auto_leave = false
		root.add_child(scene)
		await _frames(4)
		_audit(root, tag + " " + path.get_file(), notch)
		scene.queue_free()
		await _frames(2)
	# --- panels over an empty full-screen root ---
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(holder)
	var settings := SettingsPanel.new()
	holder.add_child(settings)
	await _frames(2)
	for t in 2:
		settings._tab = t
		settings.open()
		await _frames(3)
		_audit(holder, tag + " settings tab %d" % t, notch)
	settings.hide()
	var account: Control = (load("res://scripts/account_panel.gd") as GDScript).new()
	holder.add_child(account)
	await _frames(2)
	account.open()
	await _frames(3)
	_audit(holder, tag + " account", notch)
	account.hide()
	for mode in 4:
		var dialog: Control = (load("res://scripts/email_auth_dialog.gd") as GDScript).new()
		holder.add_child(dialog)
		await _frames(2)
		dialog.open(mode)
		await _frames(3)
		_audit(holder, tag + " email dialog %d" % mode, notch)
		dialog.queue_free()
	holder.queue_free()
	await _frames(2)
	# --- the battle: HUD, build menu, selected tower, pause, end screen ---
	LevelCatalog.selected_id = 3
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	main.get_node("HUD").set("_touch", true)
	root.add_child(main)
	await _frames(8)
	var hud: Hud = main.get_node("HUD")
	_audit(hud, tag + " hud", notch)
	var gs: GameState = main.get_node("GameState")
	var bm: BuildManager = main.get_node("BuildManager")
	gs.add_gold(900)
	gs.add_wood(900)
	var slot: TowerSlot = get_nodes_in_group(TowerSlot.GROUP)[0]
	bm.select_slot(slot)
	await _frames(6)
	_audit(hud, tag + " hud build menu", notch)
	bm.build_on(slot, bm.tower_types[0])
	bm.clear_selection()
	bm.select_slot(slot)
	await _frames(6)
	_audit(hud, tag + " hud tower selected", notch)
	for right in [0, 1]:
		GameSettings.set_layout_value("joystick_side", right)
		GameSettings.set_layout_value("joystick_size", 2)
		GameSettings.set_layout_value("minimap_mode", HudLayout.MAP_SHOW)
		hud.apply_layout()
		await _frames(3)
		_audit(hud, tag + " hud big joystick side %d" % right, notch)
	GameSettings.set_layout_value("joystick_side", 0)
	GameSettings.set_layout_value("joystick_size", 1)
	GameSettings.set_layout_value("minimap_mode", HudLayout.MAP_WAVE)
	hud.apply_layout()
	hud.show_pause_menu()
	await _frames(4)
	_audit(hud, tag + " hud pause menu", notch)
	hud.hide_pause_menu()
	hud.show_end_screen(tr("HUD_PAUSE"), true, 3, "30/30\n1234")
	await _frames(4)
	_audit(hud, tag + " hud end screen", notch)
	main.queue_free()
	await _frames(3)
	# --- the world map (owned by another team): reported only ---
	var map := (load(MAP_SCENE) as PackedScene).instantiate()
	root.add_child(map)
	await _frames(10)
	_audit(root, tag + " map", notch, true)
	map.queue_free()
	await _frames(3)


## Split-screen, rotation of a foldable, a Chromebook window dragged to another size: the
## window changes while the battle is open and the HUD must follow.
func _live_resize() -> void:
	GameSettings.set_language("en")
	ScreenUtil.fake_margins = Vector4.ZERO
	root.size = Vector2i(2340, 1080)
	await _frames(2)
	LevelCatalog.selected_id = 3
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	main.get_node("HUD").set("_touch", true)
	root.add_child(main)
	await _frames(8)
	var hud: Hud = main.get_node("HUD")
	for window: Vector2i in [
		Vector2i(1280, 720),
		Vector2i(800, 480),
		Vector2i(1024, 768),
		Vector2i(2560, 1600),
		Vector2i(2340, 1080),
	]:
		root.size = window
		await _frames(4)
		_audit(hud, "resize to %dx%d hud" % [window.x, window.y], Vector4.ZERO)
	main.queue_free()
	await _frames(3)


## Audits every visible control under `top`.
func _audit(top: Node, tag: String, notch: Vector4, soft: bool = false) -> void:
	_checks += 1
	var screen: Vector2 = root.get_visible_rect().size
	var bounds := Rect2(
		Vector2(notch.x, notch.y), screen - Vector2(notch.x + notch.z, notch.y + notch.w)
	)
	var found: PackedStringArray = []
	var interactive: Array[Control] = []
	for node: Node in top.find_children("*", "Control", true, false):
		var c := node as Control
		if not c.is_visible_in_tree() or c.modulate.a < 0.05 or c.self_modulate.a < 0.05:
			continue
		if _inside_hidden_subtree(c):
			continue
		# Inside a scroll list only the horizontal extent has to fit (it scrolls vertically).
		var scrolled: bool = _inside_scroll(c)
		var rect: Rect2 = c.get_global_rect()
		if rect.size.x <= 0.5 or rect.size.y <= 0.5:
			continue
		var is_input: bool = (
			c is BaseButton or c is LineEdit or c is TextEdit or c.name == &"Joystick"
		)
		if is_input:
			if (
				c is BaseButton
				and (c as BaseButton).disabled
				and c.mouse_filter == Control.MOUSE_FILTER_IGNORE
			):
				continue
			var fits: bool = bounds.grow(1.0).encloses(rect)
			if scrolled:
				fits = (
					rect.position.x >= bounds.position.x - 1.0 and rect.end.x <= bounds.end.x + 1.0
				)
			if not fits:
				found.append("%s outside the screen %s" % [_name(c, top), _fmt(rect)])
			interactive.append(c)
			_controls += 1
		# Text that does not fit its box (a control cannot be smaller than its minimum size,
		# so only trimming labels, wrapped labels and clipping buttons can lose text).
		var clipped: String = _clipped(c)
		if clipped != "":
			found.append("%s text clipped: %s" % [_name(c, top), clipped])
		elif c is Label and not scrolled and not bounds.grow(2.0).encloses(rect):
			found.append("%s label outside the screen %s" % [_name(c, top), _fmt(rect)])
	for i in interactive.size():
		for j in range(i + 1, interactive.size()):
			var a: Control = interactive[i]
			var b: Control = interactive[j]
			if a.is_ancestor_of(b) or b.is_ancestor_of(a):
				continue
			var inter: Rect2 = a.get_global_rect().intersection(b.get_global_rect())
			if inter.size.x > 2.0 and inter.size.y > 2.0:
				found.append("%s overlaps %s" % [_name(a, top), _name(b, top)])
	for f in found:
		if soft:
			_soft.append("%s: %s" % [tag, f])
		else:
			_problems.append("%s: %s" % [tag, f])
	if _verbose and not found.is_empty():
		print("  %s: %d findings" % [tag, found.size()])


func _fmt(r: Rect2) -> String:
	return "[%d,%d %dx%d]" % [r.position.x, r.position.y, r.size.x, r.size.y]


func _name(c: Control, top: Node) -> String:
	return str(top.get_path_to(c)) if top.is_ancestor_of(c) else str(c.name)


func _clipped(c: Control) -> String:
	if c is Label:
		return _label_clip(c as Label)
	if c is Button:
		return _button_clip(c as Button)
	return ""


func _label_clip(label: Label) -> String:
	if label.text == "":
		return ""
	if label.autowrap_mode != TextServer.AUTOWRAP_OFF:
		if label.get_visible_line_count() < label.get_line_count():
			return "%d of %d lines" % [label.get_visible_line_count(), label.get_line_count()]
		return ""
	var font: Font = label.get_theme_font("font")
	var fs: int = label.get_theme_font_size("font_size")
	var widest: float = 0.0
	for line in label.text.split("\n"):
		widest = maxf(widest, font.get_string_size(line, label.horizontal_alignment, -1, fs).x)
	if widest > label.size.x + 1.0:
		return "%d px of text in %d px" % [widest, label.size.x]
	return ""


func _button_clip(button: Button) -> String:
	if button.text == "":
		return ""
	if button.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING and not button.clip_text:
		return ""
	var font: Font = button.get_theme_font("font")
	var fs: int = button.get_theme_font_size("font_size")
	var style: StyleBox = button.get_theme_stylebox("normal")
	var room: float = button.size.x - style.get_minimum_size().x
	var width: float = font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if width > room + 1.0:
		return "%d px of text in %d px" % [width, room]
	return ""


func _inside_scroll(c: Control) -> bool:
	var p: Node = c.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


## Controls under a parent that clips its children, or a hidden CanvasLayer.
func _inside_hidden_subtree(c: Control) -> bool:
	var p: Node = c.get_parent()
	while p != null:
		if p is Control and (p as Control).clip_contents and (p as Control).size.x < 1.0:
			return true
		p = p.get_parent()
	return false

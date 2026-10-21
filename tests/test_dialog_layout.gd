extends SceneTree
## Every dialog (end screen: victory / defeat / daily summary / record run, pause, settings,
## profile and its confirmations, e-mail forms, shop confirmation, treasury, daily trial,
## streak, achievements, records, co-op lobby, toasts) is opened through the real code on a
## matrix of screens (phones, tablets, Chromebooks) with no cutout, a cutout on the left, on the
## right and on both sides, in Russian and English, and checked:
##   1. the panel lies wholly inside the screen and clear of the cutouts;
##   2. it is centred on the SCREEN: |left gap - right gap| <= 8 px when the centre does not
##      reach a cutout; with a cutout on one side only, the panel moves away from it by the least
##      amount (gap on the cutout side >= the cutout), and never by more than the cutout;
##   3. the dim covers 100 % of the viewport (its rect equals the viewport rect) and blocks touches;
##   4. buttons stay inside the panel, texts are not clipped or squeezed.
## A canary builds the old layout (dim and centre inside a root inset by the safe area): the
## check must fail on it.
## godot --headless --fixed-fps 60 --path . --script res://tests/test_dialog_layout.gd
## Env: DIALOG_ONLY=1280x800 limits the screens, DIALOG_VERBOSE=1 prints every finding.

const SAVE := "user://test_dialog_layout.cfg"
const SETTINGS := "user://test_dialog_layout_settings.cfg"
const SCREENS: Array[Vector2i] = [
	Vector2i(2000, 900),
	Vector2i(2160, 1080),
	Vector2i(2400, 1080),
	Vector2i(1560, 720),
	Vector2i(1280, 720),
	Vector2i(1280, 800),
	Vector2i(1600, 720),
	Vector2i(800, 480),
	Vector2i(2560, 1600),
	Vector2i(1024, 768),
]
## Cutouts in canvas units (left, top, right, bottom): none, left, right, both sides.
const NOTCHES: Array[Vector4] = [
	Vector4.ZERO, Vector4(80, 0, 0, 0), Vector4(0, 0, 80, 0), Vector4(64, 0, 64, 0)
]
const LOCALES: Array[String] = ["ru", "en"]
const HUD_SCENE := "res://ui/hud.tscn"
const MAP_SCENE := "res://scenes/level_select.tscn"
const SHOP_SCENE := "res://scenes/shop.tscn"
const LOBBY_SCENE := "res://scenes/coop_lobby.tscn"
## Tolerance of "centred", in canvas pixels.
const CENTER_TOLERANCE := 8.0

var fails := 0
var _problems: PackedStringArray = []
var _checked := 0
var _dialogs := 0
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
	_verbose = OS.get_environment("DIALOG_VERBOSE") == "1"
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var only: String = OS.get_environment("DIALOG_ONLY")
	var screens: Array[Vector2i] = []
	for s in SCREENS:
		if only == "" or only == "%dx%d" % [s.x, s.y]:
			screens.append(s)
	_math()
	await _canary()
	for locale in LOCALES:
		GameSettings.set_language(locale)
		for s in screens:
			for notch in NOTCHES:
				await _screen(s, notch, locale)
	ScreenUtil.fake_margins = Vector4.ZERO
	GameSettings.set_language("auto")
	LevelCatalog.erase_all()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	for line in _problems.slice(0, 60):
		print("   ", line)
	check(
		_problems.is_empty(),
		(
			"%d dialogs checked (%d audits) on %d screens x %d cutouts x 2 languages: %d findings"
			% [_dialogs, _checked, screens.size(), NOTCHES.size(), _problems.size()]
		)
	)
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


## The pure placement function against the rules above (no scene needed).
func _math() -> void:
	var bad: PackedStringArray = []
	for s in SCREENS:
		var screen := Vector2(s)
		var canvas: Vector2 = Vector2(s) / minf(s.x / 1280.0, s.y / 720.0)
		for notch in NOTCHES:
			var room := Rect2(
				Vector2(notch.x + 16.0, 16.0),
				canvas - Vector2(notch.x + notch.z + 32.0, 32.0 + notch.w)
			)
			for wanted: Vector2 in [Vector2(640, 400), Vector2(920, 700), Vector2(3000, 3000)]:
				var rect: Rect2 = DialogFrame.fit_rect(canvas, room, wanted)
				if not Rect2(Vector2.ZERO, canvas).encloses(rect):
					bad.append("%s %s outside" % [screen, wanted])
				if not room.grow(0.5).encloses(rect):
					bad.append("%s %s leaves the room" % [screen, wanted])
	check(bad.is_empty(), "DialogFrame.fit_rect keeps the panel in the room %s" % ", ".join(bad))


## The check must catch the old layout: a dim and a centred panel inside a root inset by the safe
## area (a strip beside the cutout stays bright and the window sits off the screen centre).
func _canary() -> void:
	root.size = Vector2i(2000, 900)
	ScreenUtil.fake_margins = Vector4(80, 0, 0, 0)
	await _frames(2)
	var inset := Control.new()
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(inset)
	SafeArea.attach(inset)
	await _frames(2)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 300)
	center.add_child(panel)
	await _frames(3)
	var found: PackedStringArray = _geometry(
		panel.get_global_rect(), dim, Vector4(80, 0, 0, 0), "canary"
	)
	check(
		found.size() >= 2,
		"the check sees an uncovered strip and an off-centre window (%d)" % found.size()
	)
	inset.queue_free()
	ScreenUtil.fake_margins = Vector4.ZERO
	await _frames(2)


func _screen(window: Vector2i, notch: Vector4, locale: String) -> void:
	root.size = window
	ScreenUtil.fake_margins = notch
	await _frames(2)
	var tag := (
		"%dx%d %s %s"
		% [
			window.x,
			window.y,
			"notch(%d,%d)" % [notch.x, notch.z] if notch != Vector4.ZERO else "-",
			locale
		]
	)
	await _hud_dialogs(tag, notch)
	await _map_dialogs(tag, notch)
	await _shop_and_lobby(tag, notch)
	await _records_and_toast(tag, notch)


# ---------------------------------------------------------------------------------------------
# Scenarios
# ---------------------------------------------------------------------------------------------


func _hud_dialogs(tag: String, notch: Vector4) -> void:
	var hud: Hud = (load(HUD_SCENE) as PackedScene).instantiate()
	hud.set("_touch", true)
	root.add_child(hud)
	await _frames(4)
	hud.show_pause_menu()
	await _frames(3)
	_check_open(tag + " pause", notch)
	hud._settings_panel._tab = 0
	for t in 3:
		hud._settings_panel._tab = t
		hud._settings_panel.open()
		await _frames(3)
		_check_open(tag + " pause+settings tab %d" % t, notch)
	hud._settings_panel.close()
	hud.hide_pause_menu()
	hud.show_end_screen(
		tr("HUD_VICTORY"), true, 3, tr("END_STARS_TOTAL") % [12, 30] + "\n30/30\n1234"
	)
	await _frames(3)
	_check_open(tag + " victory", notch)
	hud.hide_pause_menu()
	hud.show_end_screen(tr("END_DEFEAT"), false, 0, tr("END_TIP") % tr("TIP_FROST"))
	await _frames(3)
	_check_open(tag + " defeat", notch)
	hud.hide_pause_menu()
	hud.set_record_end(true)
	hud.show_end_screen(
		tr("DAILY_END_BEST"),
		true,
		0,
		(
			tr("DAILY_END_STATS") % [23, 23]
			+ "\n"
			+ tr("DAILY_END_STREAK") % 4
			+ "\n"
			+ tr("DAILY_END_STAR")
			+ "\n"
			+ tr("END_GEMS") % 12
			+ "\n"
			+ tr("END_STATS_1") % [412, 3000]
			+ "\n"
			+ tr("END_STATS_2") % [12, 7, 11, 5]
		)
	)
	await _frames(3)
	_check_open(tag + " daily / record summary", notch)
	hud.hide_pause_menu()
	Toast.show_on(hud.get_node("Root"), tr("ACH_TITLE") % [3, 12], tr("GEMS_PLUS") % 10)
	await _frames(4)
	_check_toast(tag + " hud toast", notch)
	hud.queue_free()
	await _frames(2)


func _map_dialogs(tag: String, notch: Vector4) -> void:
	var map: Node = (load(MAP_SCENE) as PackedScene).instantiate()
	root.add_child(map)
	await _frames(8)
	var opens: Array[Dictionary] = [
		{"name": "treasury", "open": map._open_treasury, "close": map._treasury.hide},
		{"name": "daily", "open": map._daily.open, "close": map._daily.close},
		{"name": "achievements", "open": map._achievements.open, "close": map._achievements.close},
		{"name": "streak", "open": map._gems.panel().open, "close": map._gems.panel().close},
		{"name": "modes", "open": map._modes_panel.open, "close": map._modes_panel.close},
		{"name": "settings", "open": map._settings.open, "close": map._settings.close},
		{"name": "profile", "open": map._account.open, "close": map._account.close},
	]
	for entry in opens:
		(entry["open"] as Callable).call()
		await _frames(3)
		_check_open("%s %s" % [tag, entry["name"]], notch)
		(entry["close"] as Callable).call()
		await _frames(1)
	map._settings._tab = 1
	map._settings.open()
	await _frames(3)
	_check_open(tag + " settings controls", notch)
	map._settings._tab = 2
	map._settings._build()
	await _frames(3)
	_check_open(tag + " settings credits", notch)
	map._settings._tab = 0
	map._settings.close()
	map._account.open()
	await _frames(2)
	map._account._ask_delete()
	await _frames(3)
	_check_open(tag + " profile: delete", notch)
	map._account._ask_sign_out()
	await _frames(3)
	_check_open(tag + " profile: sign out", notch)
	map._account.close()
	for mode in 4:
		map._account.open_dialog(mode)
		await _frames(3)
		_check_open("%s email form %d" % [tag, mode], notch)
		map._account._dialog.close()
		map._account.close()
		await _frames(1)
	map.queue_free()
	await _frames(3)


func _shop_and_lobby(tag: String, notch: Vector4) -> void:
	var shop := (load(SHOP_SCENE) as PackedScene).instantiate() as ShopScreen
	shop.auto_leave = false
	root.add_child(shop)
	await _frames(4)
	shop._confirm.show()
	await _frames(3)
	_check_open(tag + " shop confirm", notch)
	shop.queue_free()
	await _frames(2)
	var lobby: Node = (load(LOBBY_SCENE) as PackedScene).instantiate()
	root.add_child(lobby)
	await _frames(4)
	_check_open(tag + " co-op lobby", notch)
	lobby.queue_free()
	await _frames(2)


func _records_and_toast(tag: String, notch: Vector4) -> void:
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(holder)
	SafeArea.attach(holder)
	var stub := RecordsStub.new()
	root.add_child(stub)
	var panel := RecordsPanel.new()
	panel.online = stub
	holder.add_child(panel)
	await _frames(2)
	panel.open(3, tr("LEVEL_3_NAME") if false else "Зелёная долина")
	var entries: Array = []
	for i in 10:
		entries.append({"name": "Рыцарь Фёдор %d" % i, "wave": 40 - i})
	stub.leaderboard_loaded.emit(3, entries)
	await _frames(3)
	_check_open(tag + " records (10 rows)", notch)
	panel.request()
	stub.leaderboard_failed.emit(3, "timeout")
	await _frames(3)
	_check_open(tag + " records (failed, retry)", notch)
	Toast.show_on(holder, tr("ACH_TITLE") % [3, 12], tr("GEMS_PLUS") % 10)
	await _frames(4)
	_check_toast(tag + " map toast", notch)
	holder.queue_free()
	stub.queue_free()
	await _frames(2)


## A stand-in for the Online module with the signals the records panel listens to.
class RecordsStub:
	extends Node
	signal leaderboard_loaded(level_id: int, entries: Array)
	signal leaderboard_failed(level_id: int, reason: String)
	signal status_changed(text: String)

	func fetch_leaderboard(_level: int) -> void:
		pass

	func player_name() -> String:
		return "Рыцарь Фёдор"

	func cloud_save() -> void:
		pass

	func cloud_load() -> void:
		pass


# ---------------------------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------------------------


func _visible_frames() -> Array[DialogFrame]:
	var out: Array[DialogFrame] = []
	for node: Node in root.find_children("*", "DialogFrame", true, false):
		var frame := node as DialogFrame
		if frame.is_visible_in_tree():
			out.append(frame)
	return out


## Checks every dialog frame that is open now (at least one must be).
func _check_open(tag: String, notch: Vector4) -> void:
	var frames: Array[DialogFrame] = _visible_frames()
	_checked += 1
	if frames.is_empty():
		_problems.append("%s: no dialog is open" % tag)
		return
	for frame in frames:
		_dialogs += 1
		var found: PackedStringArray = _geometry(
			frame.panel.get_global_rect(), frame.dim, notch, tag
		)
		found.append_array(_content(frame, notch))
		for f in found:
			_problems.append("%s: %s" % [tag, f])
		if _verbose and not found.is_empty():
			print("  %s: %d findings" % [tag, found.size()])


func _check_toast(tag: String, notch: Vector4) -> void:
	_checked += 1
	var toasts := get_nodes_in_group(Toast.GROUP)
	if toasts.is_empty():
		_problems.append("%s: no toast" % tag)
		return
	for node in toasts:
		var rect: Rect2 = (node as Control).get_global_rect()
		var screen: Vector2 = root.get_visible_rect().size
		var found: PackedStringArray = _placement(rect, screen, notch, false)
		for f in found:
			_problems.append("%s: toast %s" % [tag, f])
		(node as Node).queue_free()


## Rules 1 and 2: inside the screen, clear of the cutouts, centred on the screen.
func _placement(
	rect: Rect2, screen: Vector2, notch: Vector4, vertical: bool = true
) -> PackedStringArray:
	var found: PackedStringArray = []
	if not Rect2(Vector2.ZERO, screen).grow(0.5).encloses(rect):
		found.append("outside the screen %s on %s" % [_fmt(rect), screen])
	var left: float = rect.position.x
	var right: float = screen.x - rect.end.x
	var top: float = rect.position.y
	var bottom: float = screen.y - rect.end.y
	if left < notch.x - 0.5 or right < notch.z - 0.5:
		found.append(
			(
				"reaches into a cutout (gaps %d / %d, cutouts %d / %d)"
				% [left, right, notch.x, notch.z]
			)
		)
	var centred_gap: float = (screen.x - rect.size.x) / 2.0
	if centred_gap >= maxf(notch.x, notch.z):
		if absf(left - right) > CENTER_TOLERANCE:
			found.append("not centred: gaps %d / %d px" % [left, right])
	else:
		# The centre would touch a cutout: the shift is the least one (up to the larger cutout).
		if absf(left - right) > maxf(notch.x, notch.z) * 2.0 + CENTER_TOLERANCE:
			found.append("shifted too far: gaps %d / %d px" % [left, right])
	if vertical and notch.y == 0.0 and notch.w == 0.0 and absf(top - bottom) > CENTER_TOLERANCE:
		found.append("not centred vertically: gaps %d / %d px" % [top, bottom])
	return found


func _geometry(rect: Rect2, dim: Control, notch: Vector4, _tag: String) -> PackedStringArray:
	var screen: Vector2 = root.get_visible_rect().size
	var found: PackedStringArray = _placement(rect, screen, notch)
	var cover: Rect2 = dim.get_global_rect()
	var want := Rect2(Vector2.ZERO, screen)
	if (
		not cover.position.is_equal_approx(want.position)
		or not cover.size.is_equal_approx(want.size)
	):
		found.append("the dim covers %s, not the whole screen %s" % [_fmt(cover), _fmt(want)])
	if dim.mouse_filter != Control.MOUSE_FILTER_STOP:
		found.append("the dim lets touches through")
	return found


## Rule 4: buttons inside the panel (vertically too, unless the panel scrolls), texts not clipped.
func _content(frame: DialogFrame, notch: Vector4) -> PackedStringArray:
	var found: PackedStringArray = []
	var panel_rect: Rect2 = frame.panel.get_global_rect()
	var scrolls: bool = frame.body.get_combined_minimum_size().y > frame.scroll.size.y + 1.0
	var screen: Vector2 = root.get_visible_rect().size
	var room := Rect2(
		Vector2(notch.x, notch.y), screen - Vector2(notch.x + notch.z, notch.y + notch.w)
	)
	for node: Node in frame.panel.find_children("*", "Control", true, false):
		var c := node as Control
		if not c.is_visible_in_tree() or c.modulate.a < 0.05:
			continue
		var rect: Rect2 = c.get_global_rect()
		if rect.size.x <= 0.5 or rect.size.y <= 0.5:
			continue
		var inner_scroll: bool = _inside_inner_scroll(c, frame)
		if c is BaseButton or c is LineEdit:
			if (c as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE:
				continue
			var fits_x: bool = rect.position.x >= panel_rect.position.x - 1.0
			fits_x = fits_x and rect.end.x <= panel_rect.end.x + 1.0
			var fits_y: bool = rect.position.y >= panel_rect.position.y - 1.0
			fits_y = fits_y and rect.end.y <= panel_rect.end.y + 1.0
			if not fits_x:
				found.append("%s sticks out of the panel sideways %s" % [c.name, _fmt(rect)])
			elif not fits_y and not scrolls and not inner_scroll:
				found.append("%s sticks out of the panel %s" % [c.name, _fmt(rect)])
			if not room.grow(1.0).intersects(rect):
				found.append("%s is off the screen %s" % [c.name, _fmt(rect)])
			if c.size.y < 56.0 and c is Button and (c as Button).text != "":
				found.append("%s is only %d px high" % [c.name, c.size.y])
		var clipped: String = _clipped(c)
		if clipped != "":
			found.append("%s text clipped: %s" % [c.name, clipped])
	return found


func _inside_inner_scroll(c: Control, frame: DialogFrame) -> bool:
	var p: Node = c.get_parent()
	while p != null and p != frame.body:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func _fmt(r: Rect2) -> String:
	return "[%d,%d %dx%d]" % [r.position.x, r.position.y, r.size.x, r.size.y]


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
	var font: Font = button.get_theme_font("font")
	var fs: int = button.get_theme_font_size("font_size")
	var style: StyleBox = button.get_theme_stylebox("normal")
	var room: float = button.size.x - style.get_minimum_size().x
	var width: float = font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if button.icon != null:
		width += button.icon.get_width() + 8.0
	if width > room + 1.0 and button.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING:
		return "%d px of text in %d px" % [width, room]
	if width > room + 1.0 and button.clip_text:
		return "%d px of text in %d px" % [width, room]
	return ""

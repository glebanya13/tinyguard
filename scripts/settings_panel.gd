class_name SettingsPanel
extends Control
## Settings dialog (gear button on the world map and in the pause menu):
## interface language, sound, game version and, when set in GameInfo, links to
## the privacy policy and to the web page for deleting data. Built in code like
## AccountPanel. The language is stored on the device only (GameSettings).

## The language was switched: screens that cache texts should rebuild.
signal language_changed
signal closed
## A joystick / road compass option changed: the HUD re-places them at once.
signal layout_changed

const BUTTON_HEIGHT := 64.0
const CREDITS_ICONS_URL := "https://game-icons.net"
## Rows of the controls tab: label key, setting key, labels of the choices.
const OPTION_ROWS: Array = [
	["SET_JOY_SIZE", "joystick_size", ["SET_SMALL", "SET_MEDIUM", "SET_LARGE"]],
	["SET_JOY_POS", "joystick_pos", ["SET_LOWER", "SET_STANDARD", "SET_HIGHER"]],
	["SET_JOY_SIDE", "joystick_side", ["SET_LEFT", "SET_RIGHT"]],
	["SET_MAP_SIZE", "minimap_size", ["SET_SMALL", "SET_MEDIUM", "SET_LARGE"]],
	["SET_MAP_MODE", "minimap_mode", ["SET_MAP_SHOW", "SET_MAP_HIDE", "SET_MAP_WAVE"]],
]
const FX_KEYS: Array[String] = ["SET_FX_OFF", "SET_FX_MIN", "SET_FX_FULL"]
## Taps on the version line that switch the diagnostics overlay, and the longest gap between two.
const VERSION_TAPS := 5
const VERSION_TAP_GAP_MS := 900
const LANGUAGE_KEYS: Dictionary = {
	"auto": "SET_LANG_AUTO",
	"ru": "SET_LANG_RU",
	"en": "SET_LANG_EN",
}

var _box: VBoxContainer
var _sound_button: Button
var _fx_button: Button
var _preview: Control
var _version_taps: int = 0
var _last_version_tap_ms: int = 0
## 0 = general, 1 = controls (joystick and road compass), 2 = credits.
var _tab: int = 0
var _option_buttons: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	hide()


func open() -> void:
	_build()
	show()


## Back button: closes the panel.
func close() -> void:
	if visible:
		hide()
		closed.emit()


## True when a link row is shown for the given URL constant (tests).
func has_link(kind: String) -> bool:
	return _box != null and _box.find_child("Link_" + kind, true, false) != null


func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_option_buttons.clear()
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.06, 0.14, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(920 if _tab == 1 else 640, 0)
	center.add_child(panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 12)
	panel.add_child(_box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	_box.add_child(header)
	var title := UiKit.ribbon(tr("SET_TITLE"))
	title.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	header.add_child(title)
	header.add_child(_button(tr("SET_DONE"), close, false, 160))

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	_box.add_child(tabs)
	var tab_group := ButtonGroup.new()
	for i in 3:
		var tab := _button(
			tr(["SET_TAB_GENERAL", "SET_TAB_CONTROLS", "SET_TAB_CREDITS"][i]),
			_on_tab.bind(i),
			true,
			0
		)
		tab.name = "Tab_%d" % i
		tab.custom_minimum_size.y = 56.0
		tab.theme_type_variation = &"ToggleButton"
		tab.toggle_mode = true
		tab.button_group = tab_group
		tab.button_pressed = i == _tab
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(tab)
	if _tab == 1:
		_build_controls()
	elif _tab == 2:
		_build_credits()
	else:
		_build_general()


func _on_tab(index: int) -> void:
	if index == _tab:
		return
	_tab = index
	_build()


func _build_general() -> void:
	_box.add_child(UiKit.heading(tr("SET_LANGUAGE")))
	var languages := HBoxContainer.new()
	languages.add_theme_constant_override("separation", 8)
	_box.add_child(languages)
	var group := ButtonGroup.new()
	var current: String = GameSettings.language()
	for code: String in GameSettings.LANGUAGES:
		var button := _button(tr(LANGUAGE_KEYS[code]), _on_language.bind(code), true, 190)
		button.name = "Lang_" + code
		button.theme_type_variation = &"ToggleButton"
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = code == current
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		languages.add_child(button)

	_sound_button = _button("", _on_sound_pressed, true, 0)
	_sound_button.name = "SoundToggle"
	_box.add_child(_sound_button)
	_update_sound_text()

	_fx_button = _button("", _on_fx_pressed, true, 0)
	_fx_button.name = "EffectsToggle"
	_box.add_child(_fx_button)
	_update_fx_text()

	if GameInfo.PRIVACY_URL != "":
		var privacy := _button(tr("SET_PRIVACY"), _open_link.bind(GameInfo.PRIVACY_URL), true, 0)
		privacy.name = "Link_privacy"
		_box.add_child(privacy)
	if GameInfo.DELETION_URL != "":
		var deletion := _button(tr("SET_DELETION"), _open_link.bind(GameInfo.DELETION_URL), true, 0)
		deletion.name = "Link_deletion"
		_box.add_child(deletion)

	var version := UiKit.caption(tr("SET_VERSION") % GameSettings.version())
	version.name = "Version"
	version.mouse_filter = Control.MOUSE_FILTER_STOP
	version.gui_input.connect(_on_version_input.bind(version))
	_box.add_child(version)
	_update_version_text(version)


## Authors: the icons are CC BY 3.0 and must be credited, the fonts are SIL OFL.
func _build_credits() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "CreditsList"
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for key: String in ["CREDITS_ICONS", "CREDITS_ICONS_LICENSE", "CREDITS_FONTS", "CREDITS_OWN"]:
		var line := UiKit.caption(tr(key))
		line.add_theme_font_size_override("font_size", 20)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(line)
	var site := _button("game-icons.net", _open_link.bind(CREDITS_ICONS_URL), true, 0)
	site.name = "Link_game_icons"
	_box.add_child(site)


## Joystick and road compass: rows of big switches on the left, a live outline of the
## screen with the pieces in place on the right.
func _build_controls() -> void:
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	_box.add_child(body)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(rows)
	for spec: Array in OPTION_ROWS:
		rows.add_child(_option_row(spec))
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 8)
	body.add_child(side)
	_preview = LayoutPreview.new()
	side.add_child(_preview)
	var note := UiKit.caption(tr("SET_PREVIEW_NOTE"))
	note.custom_minimum_size.x = LayoutPreview.SIZE.x
	side.add_child(note)


func _option_row(spec: Array) -> Control:
	var key: String = spec[1]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := UiKit.heading(tr(spec[0]), 18)
	label.custom_minimum_size = Vector2(190, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var group := ButtonGroup.new()
	var current: int = GameSettings.layout_value(key)
	var names: Array = spec[2]
	for i in names.size():
		var b := _button(tr(names[i]), _on_option.bind(key, i), true, 124)
		b.name = "Opt_%s_%d" % [key, i]
		b.custom_minimum_size.y = 84.0
		b.add_theme_font_size_override("font_size", 18)
		b.theme_type_variation = &"ToggleButton"
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == current
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
		_option_buttons[b.name] = b
	return row


func _on_option(key: String, index: int) -> void:
	GameSettings.set_layout_value(key, index)
	if _preview != null:
		_preview.queue_redraw()
	layout_changed.emit()


## Five quick taps on the version switch the diagnostics overlay (FPS, memory...) on / off.
func _on_version_input(event: InputEvent, version: Label) -> void:
	var tapped: bool = (
		(event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
		or (
			event is InputEventMouseButton
			and (event as InputEventMouseButton).pressed
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
		)
	)
	if not tapped:
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_version_tap_ms > VERSION_TAP_GAP_MS:
		_version_taps = 0
	_last_version_tap_ms = now
	_version_taps += 1
	if _version_taps >= VERSION_TAPS:
		_version_taps = 0
		GameSettings.set_diagnostics(not GameSettings.diagnostics())
		_update_version_text(version)


func _update_version_text(version: Label) -> void:
	var text: String = tr("SET_VERSION") % GameSettings.version()
	version.text = text + (" [diag]" if GameSettings.diagnostics() else "")


func _on_language(code: String) -> void:
	if GameSettings.language() == code:
		return
	GameSettings.set_language(code)
	_build()
	language_changed.emit()


func _on_sound_pressed() -> void:
	LevelCatalog.set_sound_on(not LevelCatalog.sound_on())
	_update_sound_text()


func _update_sound_text() -> void:
	_sound_button.text = tr("SET_SOUND_ON") if LevelCatalog.sound_on() else tr("SET_SOUND_OFF")


func _on_fx_pressed() -> void:
	GameSettings.set_effects((GameSettings.effects() + 1) % FX_KEYS.size())
	_update_fx_text()


func _update_fx_text() -> void:
	_fx_button.text = tr("SET_FX") % tr(FX_KEYS[GameSettings.effects()])


func _open_link(url: String) -> void:
	GameSettings.open_url(url)


func _button(text: String, action: Callable, secondary: bool, width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(width, BUTTON_HEIGHT)
	if secondary:
		button.theme_type_variation = &"SecondaryButton"
	button.pressed.connect(action)
	return button

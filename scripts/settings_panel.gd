class_name SettingsPanel
extends Control
## Settings dialog (gear button on the world map and in the pause menu):
## interface language, sound, game version and, when set in GameInfo, links to
## the privacy policy and to the web page for deleting data. Built in code like
## AccountPanel. The language is stored on the device only (GameSettings).

## The language was switched: screens that cache texts should rebuild.
signal language_changed
signal closed

const GOLD := Color(0.98, 0.8, 0.4)
const SOFT_COLOR := Color(0.82, 0.86, 0.95)
const BUTTON_HEIGHT := 58.0
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
var _version_taps: int = 0
var _last_version_tap_ms: int = 0


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
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.06, 0.14, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 14)
	panel.add_child(_box)

	var header := HBoxContainer.new()
	_box.add_child(header)
	var title := _label(tr("SET_TITLE"), 36, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_button(tr("SET_DONE"), close, false, 180))

	_box.add_child(_label(tr("SET_LANGUAGE"), 24))
	var languages := HBoxContainer.new()
	languages.add_theme_constant_override("separation", 10)
	_box.add_child(languages)
	var group := ButtonGroup.new()
	var current: String = GameSettings.language()
	for code: String in GameSettings.LANGUAGES:
		var button := _button(tr(LANGUAGE_KEYS[code]), _on_language.bind(code), true, 190)
		button.name = "Lang_" + code
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

	var version := _label(tr("SET_VERSION") % GameSettings.version(), 18, Color(SOFT_COLOR, 0.75))
	version.name = "Version"
	version.mouse_filter = Control.MOUSE_FILTER_STOP
	version.gui_input.connect(_on_version_input.bind(version))
	_box.add_child(version)
	_update_version_text(version)


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


func _label(text: String, size: int, color: Color = Color(1, 0.96, 0.87)) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, action: Callable, secondary: bool, width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(width, BUTTON_HEIGHT)
	button.add_theme_font_size_override("font_size", 21)
	if secondary:
		button.theme_type_variation = &"SecondaryButton"
	button.pressed.connect(action)
	return button

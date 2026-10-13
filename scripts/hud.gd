class_name Hud
extends CanvasLayer
## Wave, gold and lives readouts, the next-wave countdown, the hero's command
## card (build / upgrade / cancel, Warcraft style), the touch joystick and the
## end screen with the restart button.

signal build_pressed
signal upgrade_pressed
signal cancel_pressed
signal restart_pressed
signal joystick_changed(vector: Vector2)

const VICTORY_COLOR := Color(0.98, 0.8, 0.4)
const DEFEAT_COLOR := Color(1.0, 0.5, 0.45)

@onready var _wave_label: Label = $Root/TopBar/WavePill/Row/WaveLabel
@onready var _gold_label: Label = $Root/TopBar/GoldPill/Row/GoldLabel
@onready var _lives_label: Label = $Root/TopBar/LivesPill/Row/LivesLabel
@onready var _next_wave_pill: Control = $Root/NextWavePill
@onready var _next_wave_label: Label = $Root/NextWavePill/Row/NextWaveLabel
@onready var _card: Control = $Root/CommandCard
@onready var _card_title: Label = $Root/CommandCard/Content/Title
@onready var _card_stats: Label = $Root/CommandCard/Content/Stats
@onready var _card_hint: Label = $Root/CommandCard/Content/Hint
@onready var _build_button: Button = $Root/CommandCard/Content/Buttons/BuildButton
@onready var _build_cost: Label = $Root/CommandCard/Content/Buttons/BuildButton/Stack/Cost
@onready var _upgrade_button: Button = $Root/CommandCard/Content/Buttons/UpgradeButton
@onready var _upgrade_cost: Label = $Root/CommandCard/Content/Buttons/UpgradeButton/Stack/Cost
@onready var _cancel_button: Button = $Root/CommandCard/Content/Buttons/CancelButton
@onready var _joystick: Control = $Root/Joystick
@onready var _end_screen: Control = $Root/EndScreen
@onready var _message_label: Label = $Root/EndScreen/EndPanel/Content/MessageLabel
@onready var _restart_button: Button = $Root/EndScreen/EndPanel/Content/RestartButton


func _ready() -> void:
	_build_button.pressed.connect(build_pressed.emit)
	_upgrade_button.pressed.connect(upgrade_pressed.emit)
	_cancel_button.pressed.connect(cancel_pressed.emit)
	_restart_button.pressed.connect(_on_restart_button_pressed)
	_joystick.vector_changed.connect(joystick_changed.emit)
	_build_button.shortcut = _shortcut(&"build_tower")
	_upgrade_button.shortcut = _shortcut(&"upgrade_tower")
	_cancel_button.shortcut = _shortcut(&"cancel_command")
	_build_button.tooltip_text = "Построить башню (B)"
	_upgrade_button.tooltip_text = "Улучшить башню (U)"
	_cancel_button.tooltip_text = "Снять выбор (Esc)"
	_end_screen.hide()
	_next_wave_pill.hide()


func set_wave(wave: int, total: int) -> void:
	_wave_label.text = "Волна %d/%d" % [wave, total]


func set_gold(gold: int) -> void:
	_gold_label.text = str(gold)


func set_lives(lives: int) -> void:
	_lives_label.text = str(lives)


## Countdown to the next wave; seconds < 0 hides it.
func set_next_wave(wave: int, seconds: float) -> void:
	_next_wave_pill.visible = seconds >= 0.0
	if seconds >= 0.0:
		_next_wave_label.text = "Волна %d через %d с" % [wave, ceili(seconds)]


## Fills the command card. Keys: title, stats, hint, build_cost, can_build,
## show_build, upgrade_cost, can_upgrade, show_upgrade, has_selection.
func update_card(info: Dictionary) -> void:
	_card_title.text = info.get("title", "")
	_card_stats.text = info.get("stats", "")
	_card_hint.text = info.get("hint", "")
	# Like a Warcraft worker's card: commands stay in place, disabled without a target.
	_build_button.disabled = not info.get("can_build", false)
	_build_cost.text = str(info.get("build_cost", 0))
	_upgrade_button.disabled = not info.get("can_upgrade", false)
	var upgrade_cost: int = info.get("upgrade_cost", -1)
	_upgrade_cost.text = info.get(
		"upgrade_label", str(upgrade_cost) if upgrade_cost >= 0 else "макс."
	)
	_cancel_button.visible = info.get("has_selection", false)
	_fit_card.call_deferred()


## Victory/defeat screen. The restart button works while the tree is paused.
func show_end_screen(text: String, victory: bool) -> void:
	_message_label.text = text
	_message_label.add_theme_color_override(
		"font_color", VICTORY_COLOR if victory else DEFEAT_COLOR
	)
	_restart_button.disabled = false
	_card.hide()
	_joystick.hide()
	_next_wave_pill.hide()
	_end_screen.show()


## Shrink the bottom-right card to its content (it grows up and to the left).
func _fit_card() -> void:
	var needed: Vector2 = _card.get_combined_minimum_size()
	_card.offset_left = _card.offset_right - needed.x
	_card.offset_top = _card.offset_bottom - needed.y


func _shortcut(action: StringName) -> Shortcut:
	var event := InputEventAction.new()
	event.action = action
	var shortcut := Shortcut.new()
	shortcut.events = [event]
	return shortcut


func _on_restart_button_pressed() -> void:
	# The scene reload happens later in the frame; ignore repeated taps.
	_restart_button.disabled = true
	restart_pressed.emit()

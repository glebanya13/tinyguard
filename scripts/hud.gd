class_name Hud
extends CanvasLayer
## Wave, gold, wood and lives readouts, the next-wave countdown (with a button
## to call the wave early), the boss banner, floating "+gold/+wood" popups,
## the hero's command card (Warcraft style), the attack button, the touch
## joystick and the end screen.

## A command card button was pressed; `id` is the one passed to update_card().
signal command_pressed(id: StringName)
signal attack_pressed
signal next_wave_pressed
signal restart_pressed
signal map_pressed
signal joystick_changed(vector: Vector2)

const VICTORY_COLOR := Color(0.98, 0.8, 0.4)
const DEFEAT_COLOR := Color(1.0, 0.5, 0.45)
const COIN_ICON: Texture2D = preload("res://ui/icons/coin.png")
const WOOD_ICON: Texture2D = preload("res://ui/icons/wood.png")
const COST_COLOR := Color(0.2, 0.13, 0.05)
## Keyboard/gamepad action for each command id.
const SHORTCUTS := {
	&"build_0": &"build_tower",
	&"build_1": &"build_cannon",
	&"build_2": &"build_frost",
	&"upgrade": &"upgrade_tower",
	&"cancel": &"cancel_command",
}

var _button_ids: Array[StringName] = []

@onready var _wave_label: Label = $Root/TopBar/WavePill/Row/WaveLabel
@onready var _gold_label: Label = $Root/TopBar/GoldPill/Row/GoldLabel
@onready var _wood_label: Label = $Root/TopBar/WoodPill/Row/WoodLabel
@onready var _lives_label: Label = $Root/TopBar/LivesPill/Row/LivesLabel
@onready var _next_wave_pill: Control = $Root/NextWavePill
@onready var _next_wave_label: Label = $Root/NextWavePill/Row/NextWaveLabel
@onready var _next_wave_button: Button = $Root/NextWavePill/Row/NextWaveButton
@onready var _boss_banner: Control = $Root/BossBanner
@onready var _popups: Control = $Root/Popups
@onready var _card: Control = $Root/CommandCard
@onready var _card_title: Label = $Root/CommandCard/Content/Title
@onready var _card_stats: Label = $Root/CommandCard/Content/Stats
@onready var _card_hint: Label = $Root/CommandCard/Content/Hint
@onready var _buttons: HBoxContainer = $Root/CommandCard/Content/Buttons
@onready var _attack_button: Button = $Root/AttackButton
@onready var _joystick: Control = $Root/Joystick
@onready var _end_screen: Control = $Root/EndScreen
@onready var _message_label: Label = $Root/EndScreen/EndPanel/Content/MessageLabel
@onready var _restart_button: Button = $Root/EndScreen/EndPanel/Content/RestartButton
@onready var _map_button: Button = $Root/EndScreen/EndPanel/Content/MapButton


func _ready() -> void:
	_restart_button.pressed.connect(_on_end_button_pressed.bind(restart_pressed))
	_map_button.pressed.connect(_on_end_button_pressed.bind(map_pressed))
	_attack_button.pressed.connect(attack_pressed.emit)
	_attack_button.tooltip_text = "Атаковать / рубить (Пробел)"
	_next_wave_button.pressed.connect(next_wave_pressed.emit)
	_next_wave_button.tooltip_text = "Вызвать волну сейчас"
	_joystick.vector_changed.connect(joystick_changed.emit)
	_end_screen.hide()
	_next_wave_pill.hide()
	_boss_banner.hide()


func set_wave(wave: int, total: int) -> void:
	_wave_label.text = "Волна %d/%d" % [wave, total]


func set_gold(gold: int) -> void:
	_gold_label.text = str(gold)


func set_wood(wood: int) -> void:
	_wood_label.text = str(wood)


func set_lives(lives: int) -> void:
	_lives_label.text = str(lives)


## Countdown to the next wave; seconds < 0 hides it.
func set_next_wave(wave: int, seconds: float) -> void:
	_next_wave_pill.visible = seconds >= 0.0
	if seconds >= 0.0:
		_next_wave_label.text = "Волна %d через %d с" % [wave, ceili(seconds)]


func show_boss_banner() -> void:
	_boss_banner.show()
	_boss_banner.modulate.a = 0.0
	_boss_banner.scale = Vector2.ONE * 0.6
	_boss_banner.pivot_offset = _boss_banner.size / 2.0
	var tween := create_tween()
	tween.tween_property(_boss_banner, "modulate:a", 1.0, 0.25)
	tween.parallel().tween_property(_boss_banner, "scale", Vector2.ONE, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(2.2)
	tween.tween_property(_boss_banner, "modulate:a", 0.0, 0.5)
	tween.tween_callback(_boss_banner.hide)


## Floating text that rises from `screen_pos` and fades out.
func popup(text: String, screen_pos: Vector2, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 24)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popups.add_child(label)
	label.position = screen_pos - Vector2(20.0, 20.0)
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", label.position.y - 60.0, 0.9) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tween.tween_callback(label.queue_free)


## Fills the command card. `info` keys: title, stats, hint, and buttons: an
## Array of {id, icon, label?, gold?, wood?, enabled, tooltip}. Buttons are
## rebuilt only when the set of ids changes.
func update_card(info: Dictionary) -> void:
	_card_title.text = info.get("title", "")
	_card_stats.text = info.get("stats", "")
	_card_hint.text = info.get("hint", "")
	_card_hint.visible = _card_hint.text != ""
	var specs: Array = info.get("buttons", [])
	var ids: Array[StringName] = []
	for spec: Dictionary in specs:
		ids.append(spec["id"])
	if ids != _button_ids:
		_button_ids = ids
		for child in _buttons.get_children():
			child.queue_free()
		for spec: Dictionary in specs:
			_buttons.add_child(_make_button(spec))
	for i in specs.size():
		_fill_button(_buttons.get_child(i) as Button, specs[i])
	_fit_card.call_deferred()


## Victory/defeat screen. Its buttons work while the tree is paused.
func show_end_screen(text: String, victory: bool) -> void:
	_message_label.text = text
	_message_label.add_theme_color_override("font_color", VICTORY_COLOR if victory else DEFEAT_COLOR)
	_restart_button.disabled = false
	_map_button.disabled = false
	_card.hide()
	_attack_button.hide()
	_joystick.hide()
	_next_wave_pill.hide()
	_end_screen.show()


func _make_button(spec: Dictionary) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(96, 104)
	button.focus_mode = Control.FOCUS_NONE
	var id: StringName = spec["id"]
	button.pressed.connect(command_pressed.emit.bind(id))
	if SHORTCUTS.has(id):
		button.shortcut = _shortcut(SHORTCUTS[id])
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 0)
	button.add_child(stack)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(0, 58)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(icon)
	var cost := HBoxContainer.new()
	cost.name = "Cost"
	cost.alignment = BoxContainer.ALIGNMENT_CENTER
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost.add_theme_constant_override("separation", 1)
	stack.add_child(cost)
	return button


func _fill_button(button: Button, spec: Dictionary) -> void:
	button.disabled = not spec.get("enabled", false)
	button.tooltip_text = spec.get("tooltip", "")
	(button.find_child("Icon", true, false) as TextureRect).texture = spec.get("icon")
	var cost: HBoxContainer = button.find_child("Cost", true, false)
	for child in cost.get_children():
		child.free()
	if spec.has("label"):
		cost.add_child(_cost_label(spec["label"]))
		return
	cost.add_child(_mini_icon(COIN_ICON))
	cost.add_child(_cost_label(str(spec.get("gold", 0))))
	cost.add_child(_mini_icon(WOOD_ICON))
	cost.add_child(_cost_label(str(spec.get("wood", 0))))


func _mini_icon(texture: Texture2D) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.custom_minimum_size = Vector2(18, 18)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _cost_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", COST_COLOR)
	label.add_theme_constant_override("outline_size", 0)
	label.add_theme_font_size_override("font_size", 17)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Shrink the card to its content (it grows up and to the left of the attack button).
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


func _on_end_button_pressed(next: Signal) -> void:
	# The scene change happens later in the frame; ignore repeated taps.
	_restart_button.disabled = true
	_map_button.disabled = true
	next.emit()

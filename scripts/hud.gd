# gdlint: disable=max-public-methods,max-file-lines
class_name Hud
extends CanvasLayer
## Compact wave, gold, wood and lives chips, speed and pause buttons, a short
## first-steps hint that fades by itself, the wave banner ("Волна 3!", boss
## waves with the king), floating "+gold/+wood" popups, the hero's command card
## (Warcraft style), the attack and whirlwind buttons, the touch joystick and
## the pause / end screen (the forge is opened from the pause menu or with K).

## A command card button was pressed; `id` is the one passed to update_card().
signal command_pressed(id: StringName)
signal attack_pressed
signal spin_pressed
signal restart_pressed
signal map_pressed
signal pause_pressed
signal continue_pressed
signal speed_pressed
signal forge_pressed
signal workbench_pressed

## Strategic camera overview ("General mode") toggled.
signal strategic_view_pressed

## End screen of the Record Run: open the records table on the map.
signal records_pressed
signal next_level_pressed

## Early call of the next wave (only while the field is clear, see main.gd).
signal call_wave_pressed

## "To battle!" of the map inspection: starts the battle once.
signal start_battle_pressed
signal joystick_changed(vector: Vector2)

## The thumb controls were re-placed (settings changed): the road compass follows.
signal layout_changed

const PLAY_ICON: Texture2D = preload("res://ui/icons/play.png")
const BANNER_COLOR := Color(1.0, 0.86, 0.45)
const BOSS_COLOR := Color(1.0, 0.55, 0.5)
const COIN_ICON: Texture2D = preload("res://ui/icons/coin.png")
const WOOD_ICON: Texture2D = preload("res://ui/icons/wood.png")
const COST_COLOR := Color(1.0, 0.97, 0.88)
const CAPTION_COLOR := Color(0.24, 0.15, 0.06)
const GAIN_COLOR := Color(0.56, 0.96, 0.5)
const WARN_COLOR := Color(1.0, 0.62, 0.55)
const INFO_COLOR := Color(0.62, 0.86, 1.0)

## Command card buttons: 84 px is ~48 dp on a 1080p phone (720 px tall canvas).
const CARD_BUTTON_SIZE := Vector2(84, 84)
const CARD_ICON_HEIGHT := 46.0

## A button with a caption under its icon (tower name, "Upgrade", "Sell").
const CARD_CAPTION_SIZE := Vector2(100, 130)
const CARD_CAPTION_ICON_HEIGHT := 60.0
const CARD_CAPTION_FONT := 17
const PLAIN := preload("res://ui/plain_style.tres")
const STAR_ICON: Texture2D = preload("res://ui/icons/star.png")
const STAR_SOUND: AudioStream = preload("res://assets/audio/upgrade.wav")
const SOUND_ON_ICON: Texture2D = preload("res://ui/icons/sound_on.png")
const SOUND_OFF_ICON: Texture2D = preload("res://ui/icons/sound_off.png")
const GEAR_ICON: Texture2D = preload("res://ui/icons/gear.png")
const BOOK_ICON: Texture2D = preload("res://ui/icons/map.png")
const SWORD_ICON: Texture2D = preload("res://ui/icons/sword.png")
const AXE_ICON: Texture2D = preload("res://ui/icons/axe.png")

## Keyboard/gamepad action for each command id.
const SHORTCUTS := {
	&"build_0": &"build_tower",
	&"build_1": &"build_cannon",
	&"build_2": &"build_frost",
	&"build_3": &"build_lightning",
	&"upgrade": &"upgrade_tower",
	&"sword": &"upgrade_tower",
	&"sell": &"sell_tower",
	&"cancel": &"cancel_command",
	&"confirm_build": &"build_tower",
}

## Seconds the first-steps hint stays up after it last changed.
@export var hint_seconds: float = 6.0

## Seconds the wave banner stays fully visible (plus fade in/out).
@export var banner_seconds: float = 2.5

## Record Run: the wave counter reads "Wave N · Record M". `record_best` is the personal record.
var record_mode: bool = false
var record_best: int = 0

var _button_ids: Array[StringName] = []
var _hint_tween: Tween = null
var _hint_text: String = ""
var _banner_tween: Tween = null
var _joystick_visible: bool = false
var _card_hash: int = 0
var _next_level_button: Button = null
var _settings_button: Button = null
var _records_button: Button = null
var _settings_panel: SettingsPanel = null
var _encyclopedia_button: Button = null
var _encyclopedia_panel: EncyclopediaPanel = null
var _threat_vignette: ColorRect = null
var _threat_tween: Tween = null
var _spin_shown: int = -1

## Co-op: "waiting for the partner" notice (built when the mode is switched on).
var _coop_notice: PanelContainer = null
var _coop_label: Label = null

## Touch build: no keyboard hints or hover tooltips.
var _touch: bool = OS.has_feature("mobile")
var _call_wave_button: Button = null
var _wave_timer_pill: PanelContainer = null
var _wave_timer_label: Label = null
var _start_battle_button: Button = null

## Map inspection before the battle: the knight's controls are hidden.
var _inspecting: bool = false
var _joystick_before_inspection: bool = true
var _star_audio: AudioStreamPlayer = null

@onready var _wave_label: Label = $Root/TopBar/WavePill/Row/WaveLabel
@onready var _gold_label: Label = $Root/TopBar/GoldPill/Row/GoldLabel
@onready var _wood_label: Label = $Root/TopBar/WoodPill/Row/WoodLabel
@onready var _lives_label: Label = $Root/TopBar/LivesPill/Row/LivesLabel
@onready var _root: Control = $Root
@onready var _hint_pill: Control = $Root/Hint
@onready var _hint_label: Label = $Root/Hint/Pill/Row/Label
@onready var _banner: Control = $Root/Banner
@onready var _banner_title: Label = $Root/Banner/Row/Title
@onready var _banner_subtitle: Label = $Root/Banner/Subtitle
@onready var _banner_boss: Control = $Root/Banner/Row/BossIcon
@onready var _popups: Control = $Root/Popups
@onready var _card: Control = $Root/CommandCard
@onready var _card_title: Label = $Root/CommandCard/Content/Head/Title
@onready var _card_stats: Label = $Root/CommandCard/Content/Head/Stats
@onready var _card_hint: Label = $Root/CommandCard/Content/Hint
@onready var _buttons: HBoxContainer = $Root/CommandCard/Content/Buttons
@onready var _attack_button: Button = $Root/AttackButton
@onready var _spin_button: Button = $Root/SpinButton
@onready var _workbench_button: Button = $Root/WorkbenchButton
@onready var _spin_icon: Control = $Root/SpinButton/Icon
@onready var _spin_label: Label = $Root/SpinButton/Swirl
@onready var _joystick: Control = $Root/Joystick
@onready var _end_screen: Control = $Root/EndScreen
@onready var _message_label: Label = $Root/EndScreen/Content/MessageLabel
@onready var _stats: Label = $Root/EndScreen/Content/Stats
@onready var _stars: HBoxContainer = $Root/EndScreen/Content/Stars
@onready var _sound_button: Button = $Root/EndScreen/Content/SoundButton
@onready var _continue_button: Button = $Root/EndScreen/Content/ContinueButton
@onready var _forge_button: Button = $Root/EndScreen/Content/ForgeButton
@onready var _speed_button: Button = $Root/TopRight/SpeedButton
@onready var _speed_multiplier: Label = $Root/TopRight/SpeedButton/Multiplier
@onready var _pause_button: Button = $Root/TopRight/PauseButton
@onready var _restart_button: Button = $Root/EndScreen/Content/RestartButton
@onready var _map_button: Button = $Root/EndScreen/Content/MapButton


func _ready() -> void:
	_drop_outlines()
	if _spin_label != null:
		_spin_label.add_theme_constant_override("outline_size", 8)
		_spin_label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
	_star_audio = AudioStreamPlayer.new()
	_star_audio.name = "StarAudio"
	_star_audio.stream = STAR_SOUND
	_star_audio.volume_db = -2.0
	_star_audio.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_star_audio)
	_threat_vignette = ColorRect.new()
	_threat_vignette.name = "ThreatVignette"
	_threat_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_threat_vignette.color = Color(0.85, 0.08, 0.08, 0.0)
	_threat_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_threat_vignette.visible = false
	add_child(_threat_vignette)
	move_child(_threat_vignette, 0)
	_end_screen.z_index = 10  # above the chips, which are layered by kind
	_frame_end_screen()
	_restart_button.pressed.connect(_on_end_button_pressed.bind(restart_pressed))
	_map_button.pressed.connect(_on_end_button_pressed.bind(map_pressed))
	_next_level_button = Button.new()
	_next_level_button.name = "NextLevelButton"
	_next_level_button.custom_minimum_size = Vector2(0, 56)
	_next_level_button.theme_type_variation = &"SuccessButton"
	_next_level_button.text = tr("HUD_NEXT_LEVEL")
	_next_level_button.pressed.connect(_on_end_button_pressed.bind(next_level_pressed))
	var end_content: Node = _end_screen.find_child("Content", true, false)
	if end_content != null:
		end_content.add_child(_next_level_button)
		end_content.move_child(_next_level_button, _map_button.get_index())
	_next_level_button.hide()
	_continue_button.pressed.connect(continue_pressed.emit)
	_sound_button.pressed.connect(_on_sound_pressed)
	_build_settings()
	_build_encyclopedia()
	_continue_button.shortcut = _shortcut(&"pause")
	_pause_button.pressed.connect(pause_pressed.emit)
	_call_wave_button = Button.new()
	_call_wave_button.name = "CallWaveButton"
	_call_wave_button.theme_type_variation = &"SecondaryButton"
	_call_wave_button.icon = PLAY_ICON
	_call_wave_button.expand_icon = true
	_call_wave_button.custom_minimum_size = Vector2(170, 48)
	_call_wave_button.focus_mode = Control.FOCUS_NONE
	_call_wave_button.pressed.connect(func() -> void: call_wave_pressed.emit())
	_call_wave_button.visible = false
	$Root/TopBar.add_child(_call_wave_button)

	_wave_timer_pill = PanelContainer.new()
	_wave_timer_pill.name = "WaveTimerPill"
	_wave_timer_pill.theme_type_variation = &"HudChip"
	_wave_timer_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var timer_row := HBoxContainer.new()
	timer_row.name = "Row"
	timer_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_row.add_theme_constant_override("separation", 6)
	_wave_timer_pill.add_child(timer_row)
	var timer_icon := TextureRect.new()
	timer_icon.name = "Icon"
	timer_icon.custom_minimum_size = Vector2(40, 40)
	timer_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_icon.texture = preload("res://ui/icons/hourglass.png")
	timer_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	timer_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	timer_row.add_child(timer_icon)
	_wave_timer_label = Label.new()
	_wave_timer_label.name = "WaveTimerLabel"
	_wave_timer_label.theme_type_variation = &"NumberLabel"
	_wave_timer_label.text = "0:00"
	timer_row.add_child(_wave_timer_label)
	_wave_timer_pill.visible = false
	$Root/TopBar.add_child(_wave_timer_pill)
	$Root/TopBar.move_child(_wave_timer_pill, $Root/TopBar/WavePill.get_index() + 1)
	_speed_button.pressed.connect(speed_pressed.emit)
	_forge_button.pressed.connect(_on_forge_menu_pressed)
	_pause_button.shortcut = _shortcut(&"pause")
	_speed_button.shortcut = _shortcut(&"speed")
	if not _touch:
		_pause_button.tooltip_text = tr("HUD_PAUSE_TIP")
		_speed_button.tooltip_text = tr("HUD_SPEED_TIP")
		_forge_button.tooltip_text = tr("HUD_FORGE_TIP")
	_attack_button.pressed.connect(attack_pressed.emit)
	_spin_button.pressed.connect(spin_pressed.emit)
	_workbench_button.pressed.connect(workbench_pressed.emit)
	_build_start_battle_button()
	_spin_icon.pivot_offset = _spin_icon.size / 2.0
	if not _touch:
		_attack_button.tooltip_text = tr("HUD_ATTACK_TIP")
		_spin_button.tooltip_text = tr("HUD_SPIN_TIP")
		_workbench_button.tooltip_text = tr("HUD_WORKBENCH_TIP")
	_joystick.vector_changed.connect(joystick_changed.emit)
	_end_screen.hide()
	_banner.hide()
	_hint_pill.hide()
	_card.hide()
	SafeArea.attach(_root)
	_root.resized.connect(apply_layout)
	apply_layout()


## The pause / end menu lives in the common dialog frame: a dim over the whole screen (not only
## over the safe area the HUD root is inset to) and a panel centred on the screen.
func _frame_end_screen() -> void:
	var frame := DialogFrame.attach(_end_screen, 592.0, 0.45)
	# The menu is shown on a paused tree: its scroll must still take the finger (a long victory
	# screen did not scroll on a phone, playtest 2026-10-24).
	frame.process_mode = Node.PROCESS_MODE_ALWAYS
	var content: Control = _end_screen.get_node("Content")
	content.reparent(frame.body, false)
	frame.body.add_theme_constant_override("separation", 0)


func _unhandled_key_input(event: InputEvent) -> void:
	# The forge has no button on the battlefield any more: K opens it directly.
	if event.is_action_pressed(&"forge") and not _end_screen.visible:
		forge_pressed.emit()
		get_viewport().set_input_as_handled()
	elif (
		not _end_screen.visible
		and event is InputEventKey
		and event.pressed
		and not event.echo
		and event.physical_keycode == KEY_B
	):
		workbench_pressed.emit()
		get_viewport().set_input_as_handled()


## `total` 0 = endless (the daily siege, the Record Run).
func set_wave(wave: int, total: int) -> void:
	if total > 0:
		_wave_label.text = "%d/%d" % [wave, total]
	elif record_mode:
		var best: int = maxi(record_best, wave - 1)  # passing the old record moves it along
		_wave_label.text = (
			tr("HUD_RECORD_WAVE") % [wave, best] if best > 0 else tr("HUD_WAVE_ONLY") % wave
		)
	else:
		_wave_label.text = tr("HUD_SIEGE_WAVE") % wave


## The wave clock: `seconds_left` until the next wave (<= 0 hides the timer); the early call
## button is shown only when `can_call` (the field is clear).
func set_call_wave_info(seconds_left: float, bonus_gold: int, can_call: bool = true) -> void:
	if _call_wave_button == null:
		return
	if seconds_left <= 0.0 or _end_screen.visible:
		_call_wave_button.visible = false
		if _wave_timer_pill != null:
			_wave_timer_pill.visible = false
		return
	_call_wave_button.visible = can_call
	_call_wave_button.text = tr("HUD_CALL_WAVE") % [ceili(seconds_left), bonus_gold]
	if _wave_timer_pill != null:
		_wave_timer_pill.visible = true
		var secs: int = ceili(seconds_left)
		var m: int = secs / 60
		var s: int = secs % 60
		_wave_timer_label.text = "%d:%02d" % [m, s]
		if seconds_left <= 5.0:
			_wave_timer_label.modulate = Color(1.0, 0.45, 0.35)
		else:
			_wave_timer_label.modulate = Color.WHITE


func get_call_wave_pos() -> Vector2:
	if (
		_call_wave_button != null
		and is_instance_valid(_call_wave_button)
		and _call_wave_button.is_visible_in_tree()
	):
		return _call_wave_button.global_position + _call_wave_button.size * 0.5
	return Vector2(300.0, 40.0)


func _build_start_battle_button() -> void:
	_start_battle_button = Button.new()
	_start_battle_button.name = "StartBattleButton"
	_start_battle_button.theme_type_variation = &"PrimaryButton"
	_start_battle_button.icon = PLAY_ICON
	_start_battle_button.expand_icon = true
	_start_battle_button.custom_minimum_size = Vector2(240, 64)
	_start_battle_button.anchor_left = 0.5
	_start_battle_button.anchor_right = 0.5
	_start_battle_button.anchor_top = 0.80
	_start_battle_button.anchor_bottom = 0.80
	_start_battle_button.offset_left = -120.0
	_start_battle_button.offset_right = 120.0
	_start_battle_button.offset_top = -32.0
	_start_battle_button.offset_bottom = 32.0
	_start_battle_button.focus_mode = Control.FOCUS_NONE
	_start_battle_button.text = tr("HUD_START_BATTLE")
	_start_battle_button.pressed.connect(
		func() -> void:
			hide_start_battle_button()
			start_battle_pressed.emit()
	)
	_start_battle_button.visible = false
	$Root.add_child(_start_battle_button)


func show_start_battle_button() -> void:
	if _start_battle_button != null:
		_start_battle_button.visible = true
		_start_battle_button.modulate.a = 1.0


## Map inspection on: the joystick and the sword buttons are hidden (the knight waits);
## off: they come back as they were.
func set_inspection(on: bool) -> void:
	if on == _inspecting:
		return
	_inspecting = on
	if on:
		_joystick_before_inspection = _joystick.visible
		_joystick_visible = _joystick.visible
	else:
		_joystick_visible = _joystick_before_inspection
	_apply_inspection()


func _apply_inspection() -> void:
	if _end_screen.visible:
		return  # the menu shows them again on close
	_attack_button.visible = not _inspecting
	_spin_button.visible = not _inspecting
	if _workbench_button:
		_workbench_button.visible = not _inspecting
	_joystick.visible = _joystick_visible and not _inspecting


func hide_start_battle_button() -> void:
	if _start_battle_button != null:
		_start_battle_button.visible = false


## The end screen of the Record Run: "Once more" instead of "Play again" and, when the
## records table exists (online), a button that opens it on the map.
func set_record_end(online: bool) -> void:
	_restart_button.text = tr("HUD_AGAIN")
	if not online or _records_button != null:
		return
	_records_button = Button.new()
	_records_button.name = "RecordsButton"
	_records_button.text = tr("HUD_RECORDS_TABLE")
	_records_button.focus_mode = Control.FOCUS_NONE
	_records_button.theme_type_variation = &"SecondaryButton"
	_records_button.pressed.connect(_on_end_button_pressed.bind(records_pressed))
	_restart_button.add_sibling(_records_button)


func set_gold(gold: int) -> void:
	_gold_label.text = str(gold)


func set_wood(wood: int) -> void:
	_wood_label.text = str(wood)


func set_lives(lives: int) -> void:
	_lives_label.text = str(lives)


## Whirlwind button: seconds left on the cooldown (0 = ready).
func set_spin_cooldown(seconds: float) -> void:
	var shown: int = ceili(seconds)
	if shown == _spin_shown:
		return  # called every frame: touch the controls only when the number changes
	_spin_shown = shown
	var ready: bool = seconds <= 0.0
	_spin_button.disabled = not ready
	_spin_label.text = "" if ready else str(ceili(seconds))
	_spin_icon.modulate.a = 1.0 if ready else 0.35


## Sword for enemies, axe for trees.
func set_attack_mode(tree: bool) -> void:
	var icon: Texture2D = AXE_ICON if tree else SWORD_ICON
	if _attack_button.icon != icon:
		_attack_button.icon = icon


## One-line tip under the top bar; "" hides it. A tip fades out by itself
## after hint_seconds and comes back only when the text changes.
func show_hint(text: String) -> void:
	if text == _hint_text:
		return
	_hint_text = text
	_hint_label.text = text
	if _hint_tween:
		_hint_tween.kill()
	if text == "":
		_hint_pill.hide()
		return
	_hint_pill.show()
	_hint_pill.modulate.a = 0.0
	_hint_tween = create_tween()
	_hint_tween.tween_property(_hint_pill, "modulate:a", 1.0, 0.3)
	_hint_tween.tween_interval(hint_seconds)
	_hint_tween.tween_property(_hint_pill, "modulate:a", 0.0, 0.6)
	_hint_tween.tween_callback(_hint_pill.hide)


## Short centred banner ("Волна 3!" + "Следующая через 30 секунд") that fades
## out after banner_seconds. A boss wave shows the king and a coral title; a
## new banner replaces the one on screen.
func show_banner(title: String, subtitle: String = "", boss: bool = false) -> void:
	_banner_title.text = title
	_banner_title.add_theme_font_size_override("font_size", 48 if title.length() <= 14 else 32)
	_banner_title.add_theme_color_override("font_color", BOSS_COLOR if boss else BANNER_COLOR)
	_banner_subtitle.text = subtitle
	_banner_subtitle.visible = subtitle != ""
	_banner_boss.visible = boss
	if _banner_tween:
		_banner_tween.kill()
	_banner.show()
	_banner.modulate.a = 0.0
	_banner.scale = Vector2.ONE * 0.7
	_banner.pivot_offset = Vector2(_banner.size.x / 2.0, 40.0)
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.25)
	(
		_banner_tween
		. parallel()
		. tween_property(_banner, "scale", Vector2.ONE, 0.35)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	_banner_tween.tween_interval(banner_seconds)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.5)
	_banner_tween.tween_callback(_banner.hide)


## "Achievement!" pill at the top (see Toast).
func show_toast(title: String, text: String) -> void:
	Toast.show_on($Root, title, text)


## Floating text that rises from `screen_pos` and fades out.
func popup(text: String, screen_pos: Vector2, color: Color, icon: Texture2D = null) -> void:
	var label := HBoxContainer.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_constant_override("separation", 2)
	var text_label := Label.new()
	text_label.text = text
	text_label.theme_type_variation = &"NumberLabel"
	text_label.add_theme_color_override("font_color", color)
	text_label.add_theme_font_size_override("font_size", 28)
	label.add_child(text_label)
	if icon:
		label.add_child(_mini_icon(icon, 30.0))
	_popups.add_child(label)
	label.position = screen_pos - Vector2(24.0, 20.0)
	var tween := label.create_tween()
	(
		tween
		. tween_property(label, "position:y", label.position.y - 60.0, 0.9)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tween.tween_callback(label.queue_free)


## Fills the command card. `info` keys: title, stats, hint, and buttons: an
## Array of {id, icon, label?, gold?, wood?, enabled, tooltip}. Buttons are
## rebuilt only when the set of ids changes.
func update_card(info: Dictionary) -> void:
	# Called on every gold/wood change: skip when nothing on the card changed.
	var card_hash: int = info.hash()
	if card_hash == _card_hash:
		return
	_card_hash = card_hash
	_card_title.text = info.get("title", "")
	_card_stats.text = info.get("stats", "")
	_card_hint.text = info.get("hint", "")
	_card_hint.visible = _card_hint.text != ""
	# Red only for problems ("not enough..."), calm blue for information.
	var warn: bool = _card_hint.text.begins_with(tr("CARD_NEED_PREFIX"))
	_card_hint.add_theme_color_override("font_color", WARN_COLOR if warn else INFO_COLOR)
	var specs: Array = info.get("buttons", [])
	_card.visible = not specs.is_empty()
	var ids: Array[StringName] = []
	for spec: Dictionary in specs:
		ids.append(spec["id"])
	if ids != _button_ids:
		_button_ids = ids
		for child in _buttons.get_children():
			_buttons.remove_child(child)
			child.queue_free()
		for spec: Dictionary in specs:
			_buttons.add_child(_make_button(spec))
	for i in specs.size():
		_fill_button(_buttons.get_child(i) as Button, specs[i])
	_fit_card.call_deferred()


func set_speed(multiplier: int) -> void:
	_speed_multiplier.text = "×%d" % multiplier
	_speed_button.modulate = Color(1.15, 1.05, 0.8) if multiplier > 1 else Color.WHITE


## Victory/defeat screen with 0..3 stars and a stats summary. Its buttons work
## while the tree is paused.
func show_end_screen(text: String, victory: bool, stars: int = 0, stats: String = "") -> void:
	clear_leak_flash()
	_show_menu(text, &"RibbonLabelGold" if victory else &"RibbonLabelRed")
	_restart_button.theme_type_variation = &""
	_stats.text = stats
	_stats.show()
	_continue_button.hide()
	_sound_button.hide()
	_settings_button.hide()
	if _encyclopedia_button:
		_encyclopedia_button.hide()
	if _encyclopedia_panel:
		_encyclopedia_panel.close()
	for i in 3:
		var star := TextureRect.new()
		star.texture = STAR_ICON
		star.custom_minimum_size = Vector2(64, 64)
		star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		star.modulate = Color.WHITE if i < stars else Color(0.2, 0.22, 0.3, 0.8)
		_stars.add_child(star)
		if i < stars:
			star.pivot_offset = Vector2(32, 32)
			star.scale = Vector2.ZERO
			var delay: float = 0.3 + 0.25 * i
			var tween := star.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			tween.tween_interval(delay)
			tween.tween_callback(
				func() -> void:
					if LevelCatalog.sound_on() and _star_audio != null:
						_star_audio.pitch_scale = 1.0 + 0.25 * i
						_star_audio.play()
			)
			(
				tween
				. tween_property(star, "scale", Vector2.ONE, 0.35)
				. set_trans(Tween.TRANS_BACK)
				. set_ease(Tween.EASE_OUT)
			)
	_stars.visible = victory and stars > 0
	if _next_level_button != null:
		var can_next: bool = (
			victory
			and stars > 0
			and LevelCatalog.selected_id < LevelCatalog.MAX_LEVEL
			and not record_mode
		)
		_next_level_button.visible = can_next
	_pause_button.hide()
	_speed_button.hide()
	_forge_button.hide()


## Co-op: the battle is shared, so there is no speed button and no restart; the
## menu leaves the match instead of going "to the map".
func set_coop_mode(on: bool) -> void:
	_speed_button.visible = not on
	_restart_button.visible = not on
	_map_button.text = tr("COOP_LEAVE_MATCH") if on else tr("HUD_TO_MAP")
	if not on or _coop_notice != null:
		return
	_coop_notice = PanelContainer.new()
	_coop_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_coop_notice.offset_top = 96.0
	_coop_notice.offset_left = -260.0
	_coop_notice.offset_right = 260.0
	_coop_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coop_label = Label.new()
	_coop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_coop_label.theme_type_variation = &"HeadingLabel"
	_coop_label.add_theme_font_size_override("font_size", 22)
	_coop_label.add_theme_color_override("font_color", WARN_COLOR)
	_coop_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coop_notice.add_child(_coop_label)
	_coop_notice.hide()
	_root.add_child(_coop_notice)


## Co-op: a message over the battle (the partner is silent).
func show_coop_notice(text: String) -> void:
	if _coop_notice == null:
		return
	_coop_label.text = text
	var shift: float = ScreenUtil.screen_center_shift(_root)
	_coop_notice.offset_left = -260.0 + shift
	_coop_notice.offset_right = 260.0 + shift
	_coop_notice.show()


func hide_coop_notice() -> void:
	if _coop_notice != null:
		_coop_notice.hide()


func is_coop_notice_visible() -> bool:
	return _coop_notice != null and _coop_notice.visible


## Pause menu: continue, restart, back to the map.
func show_pause_menu() -> void:
	_show_menu(tr("HUD_PAUSE"), &"RibbonLabel")
	_restart_button.theme_type_variation = &"SecondaryButton"
	_stars.hide()
	_stats.hide()
	_continue_button.show()
	_forge_button.hide()
	_sound_button.hide()  # the sound switch lives in the settings dialog: keeps the menu short
	_settings_button.show()
	if _encyclopedia_button:
		_encyclopedia_button.show()
	_update_sound_label()


func hide_pause_menu() -> void:
	_settings_panel.close()
	if _encyclopedia_panel:
		_encyclopedia_panel.close()
	if _encyclopedia_button:
		_encyclopedia_button.hide()
	_end_screen.hide()
	_card_hash = 0
	_card.visible = not _button_ids.is_empty()
	_attack_button.show()
	_spin_button.show()
	if _workbench_button:
		_workbench_button.show()
	_joystick.visible = _joystick_visible
	_apply_inspection()
	$Root/TopBar.show()
	$Root/TopRight.show()


func _show_menu(text: String, ribbon: StringName) -> void:
	if not _end_screen.visible and not _inspecting:
		_joystick_visible = _joystick.visible
	_message_label.text = text
	_message_label.theme_type_variation = ribbon
	_hint_pill.hide()
	_restart_button.disabled = false
	_map_button.disabled = false
	_card.hide()
	_attack_button.hide()
	_spin_button.hide()
	if _workbench_button:
		_workbench_button.hide()
	if _call_wave_button:
		_call_wave_button.hide()
	if _wave_timer_pill:
		_wave_timer_pill.hide()
	if _start_battle_button:
		_start_battle_button.hide()
	_joystick.hide()
	$Root/TopBar.hide()
	$Root/TopRight.hide()
	_end_screen.show()


## Places the joystick by the saved settings (size, height, side) and keeps its dead zone
## and logic as they are: only the control and its radius scale.
func apply_layout() -> void:
	if _root == null or _joystick == null:
		return
	var r: Dictionary = HudLayout.current(_root.size)
	var rect: Rect2 = r["joystick"]
	var right: bool = GameSettings.joystick_side() == HudLayout.SIDE_RIGHT
	var anchor: float = 1.0 if right else 0.0
	_joystick.custom_minimum_size = rect.size
	_joystick.anchor_left = anchor
	_joystick.anchor_right = anchor
	_joystick.anchor_top = 1.0
	_joystick.anchor_bottom = 1.0
	var from_left: float = rect.position.x - (_root.size.x if right else 0.0)
	_joystick.offset_left = from_left
	_joystick.offset_right = from_left + rect.size.x
	_joystick.offset_top = rect.position.y - _root.size.y
	_joystick.offset_bottom = rect.end.y - _root.size.y
	_joystick.set("radius", rect.size.x * HudLayout.JOY_RADIUS_RATIO)
	if _joystick.has_method("reset_base_position"):
		_joystick.reset_base_position()
	_joystick.queue_redraw()
	layout_changed.emit()


func _make_button(spec: Dictionary) -> Button:
	var button := Button.new()
	button.custom_minimum_size = CARD_BUTTON_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.theme_type_variation = &"SlotButton"
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
	icon.custom_minimum_size = Vector2(0, CARD_ICON_HEIGHT)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(icon)
	var caption := Label.new()
	caption.name = "Caption"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_color_override("font_color", CAPTION_COLOR)
	caption.add_theme_constant_override("outline_size", 0)
	caption.add_theme_font_size_override("font_size", CARD_CAPTION_FONT)
	caption.clip_text = true
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(caption)
	var cost := HBoxContainer.new()
	cost.name = "Cost"
	cost.alignment = BoxContainer.ALIGNMENT_CENTER
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost.add_theme_constant_override("separation", 2)
	var pill := PanelContainer.new()
	pill.name = "CostPill"
	pill.theme_type_variation = &"PricePill"
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pill.add_child(cost)
	stack.add_child(pill)
	return button


func _fill_button(button: Button, spec: Dictionary) -> void:
	button.disabled = not spec.get("enabled", false)
	button.tooltip_text = "" if _touch else spec.get("tooltip", "")
	(button.find_child("Icon", true, false) as TextureRect).texture = spec.get("icon")
	var caption := button.find_child("Caption", true, false) as Label
	caption.text = spec.get("caption", "")
	caption.visible = caption.text != ""
	button.custom_minimum_size = CARD_CAPTION_SIZE if caption.visible else CARD_BUTTON_SIZE
	var gold: int = int(spec.get("gold", 0))
	var wood: int = int(spec.get("wood", 0))
	if gold > 0 and wood > 0:
		button.custom_minimum_size.x = 126.0
	var icon_height: float = CARD_CAPTION_ICON_HEIGHT if caption.visible else CARD_ICON_HEIGHT
	(button.find_child("Icon", true, false) as TextureRect).custom_minimum_size.y = icon_height
	var cost: HBoxContainer = button.find_child("Cost", true, false)
	for child in cost.get_children():
		child.free()
	var pill: Control = cost.get_parent()
	pill.visible = spec.has("label") or gold > 0 or wood > 0
	if spec.has("label"):
		pill.add_theme_stylebox_override("panel", PLAIN)
	else:
		pill.remove_theme_stylebox_override("panel")
	if spec.has("label"):
		var label: String = spec["label"]
		if _touch and label == "Esc":
			label = tr("HUD_CLOSE")
		cost.add_child(_cost_label(label, CAPTION_COLOR))
		return
	# Income (selling) in green instead of a "+" sign: both numbers fit the button.
	var color: Color = GAIN_COLOR if spec.get("gain", false) else COST_COLOR
	if gold > 0:
		cost.add_child(_mini_icon(COIN_ICON))
		cost.add_child(_cost_label(str(gold), color))
	if wood > 0:
		cost.add_child(_mini_icon(WOOD_ICON))
		cost.add_child(_cost_label(str(wood), color))


func _mini_icon(texture: Texture2D, side: float = 18.0) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.custom_minimum_size = Vector2(side, side)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Text on the dark panels needs no outline (it matches the panel colour), and an
## outline doubles the draw calls of every label: it is a separate glyph batch.
func _drop_outlines() -> void:
	for panel: Control in [_card, _hint_pill]:
		for label: Node in panel.find_children("*", "Label", true, false):
			label.add_theme_constant_override("outline_size", 0)
	for panel: Control in [$Root/TopBar, $Root/TopRight]:
		_layer_by_kind(panel)


## Panels, then icons, then texts: 2D batching merges only consecutive draws with one
## texture, so panel-icon-text per chip is 3 calls per chip but 3 calls in all this way.
func _layer_by_kind(root: Control) -> void:
	for icon: Node in root.find_children("*", "TextureRect", true, false):
		(icon as CanvasItem).z_index = 1
	for label: Node in root.find_children("*", "Label", true, false):
		(label as CanvasItem).z_index = 2


func _cost_label(text: String, color: Color = COST_COLOR) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 0)
	label.add_theme_font_size_override("font_size", 16)
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


## "Settings" button of the pause menu and its dialog.
func _build_settings() -> void:
	_settings_button = Button.new()
	_settings_button.name = "SettingsButton"
	_settings_button.process_mode = Node.PROCESS_MODE_ALWAYS
	_settings_button.custom_minimum_size = _sound_button.custom_minimum_size
	_settings_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_settings_button.theme_type_variation = &"SecondaryButton"
	_settings_button.text = tr("HUD_SETTINGS")
	_settings_button.icon = GEAR_ICON
	_settings_button.hide()
	_sound_button.add_sibling(_settings_button)
	_settings_panel = SettingsPanel.new()
	_settings_panel.z_index = 10  # above the chips, which are layered by kind
	_root.add_child(_settings_panel)
	_settings_button.pressed.connect(
		func() -> void:
			$Root/TopBar.hide()
			$Root/TopRight.hide()
			_settings_panel.open()
	)
	_settings_panel.closed.connect(
		func() -> void:
			if not _end_screen.visible:
				$Root/TopBar.show()
				$Root/TopRight.show()
			_update_sound_label()
	)
	_settings_panel.language_changed.connect(_on_language_changed)
	_settings_panel.layout_changed.connect(apply_layout)


func _build_encyclopedia() -> void:
	_encyclopedia_button = Button.new()
	_encyclopedia_button.name = "EncyclopediaButton"
	_encyclopedia_button.process_mode = Node.PROCESS_MODE_ALWAYS
	_encyclopedia_button.custom_minimum_size = _sound_button.custom_minimum_size
	_encyclopedia_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_encyclopedia_button.theme_type_variation = &"SecondaryButton"
	_encyclopedia_button.text = tr("HUD_ENCYCLOPEDIA")
	_encyclopedia_button.icon = BOOK_ICON
	_encyclopedia_button.hide()
	_settings_button.add_sibling(_encyclopedia_button)
	_encyclopedia_panel = EncyclopediaPanel.new()
	_encyclopedia_panel.z_index = 10
	_root.add_child(_encyclopedia_panel)
	_encyclopedia_button.pressed.connect(
		func() -> void:
			$Root/TopBar.hide()
			$Root/TopRight.hide()
			_encyclopedia_panel.open()
	)
	_encyclopedia_panel.closed.connect(
		func() -> void:
			if not _end_screen.visible:
				$Root/TopBar.show()
				$Root/TopRight.show()
	)


func _on_language_changed() -> void:
	_settings_button.text = tr("HUD_SETTINGS")
	if _encyclopedia_button:
		_encyclopedia_button.text = tr("HUD_ENCYCLOPEDIA")
	if _next_level_button != null:
		_next_level_button.text = tr("HUD_NEXT_LEVEL")
	_update_sound_label()
	if _end_screen.visible:
		_message_label.text = tr("HUD_PAUSE")
	_card_hash = 0


func set_hero_knocked_out(knocked_out: bool) -> void:
	_attack_button.disabled = knocked_out
	_spin_button.disabled = knocked_out
	_attack_button.modulate = Color(0.5, 0.5, 0.5, 0.6) if knocked_out else Color.WHITE
	_spin_button.modulate = Color(0.5, 0.5, 0.5, 0.6) if knocked_out else Color.WHITE


func _on_sound_pressed() -> void:
	LevelCatalog.set_sound_on(not LevelCatalog.sound_on())
	_update_sound_label()


func _update_sound_label() -> void:
	_sound_button.text = tr("HUD_SOUND_ON") if LevelCatalog.sound_on() else tr("HUD_SOUND_OFF")
	_sound_button.icon = SOUND_ON_ICON if LevelCatalog.sound_on() else SOUND_OFF_ICON


## Pause menu "Кузница": resume the game, then open the forge card (unless it
## is already the card on screen: forge_pressed toggles it).
func _on_forge_menu_pressed() -> void:
	hide_pause_menu()
	continue_pressed.emit()
	if not _button_ids.has(&"sword"):
		forge_pressed.emit()


func _on_end_button_pressed(next: Signal) -> void:
	# The scene change happens later in the frame; ignore repeated taps.
	_restart_button.disabled = true
	_map_button.disabled = true
	_continue_button.disabled = true
	next.emit()


## Toggles strategic camera view ("General mode").
func toggle_strategic_view() -> void:
	strategic_view_pressed.emit()


## Flashes the threat vignette bright red when the castle leaks/takes damage. (Enemies that are
## about to reach the castle get a "!" over them instead of a dark screen: see LaneHint.)
func flash_leak() -> void:
	if _threat_vignette == null:
		return
	if _threat_tween and _threat_tween.is_valid():
		_threat_tween.kill()
	_threat_vignette.visible = true
	_threat_vignette.color = Color(0.85, 0.08, 0.08, 0.45)
	_threat_tween = create_tween()
	_threat_tween.tween_property(_threat_vignette, "color:a", 0.0, 0.65).set_trans(Tween.TRANS_SINE)
	_threat_tween.tween_callback(_threat_vignette.hide)


## Puts the leak flash out at once (a tween of a paused tree would hold it red on the end screen).
func clear_leak_flash() -> void:
	if _threat_tween and _threat_tween.is_valid():
		_threat_tween.kill()
	if _threat_vignette != null:
		_threat_vignette.color.a = 0.0
		_threat_vignette.visible = false

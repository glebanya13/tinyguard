class_name CalendarPanel
extends Control
## 28-day reward calendar dialog (Stage A of Retention v2).
## Shows a 4x7 grid of 28 steps (coins + gems) that counts visit days cumulatively.
## Allows the player to claim today's reward once per UTC day.

signal closed
signal reward_claimed(step: int, coins: int, gems: int)

const COIN_ICON: Texture2D = preload("res://ui/icons/coin.png")
const GEM_ICON: Texture2D = preload("res://ui/icons/gem.png")
const CHECK_ICON: Texture2D = preload("res://ui/icons/check.png")
const GOLD := Color(0.98, 0.8, 0.4)
const SOFT_COLOR := Color(0.82, 0.86, 0.95)
const OK_COLOR := Color(0.62, 0.95, 0.42)
const BUTTON_HEIGHT := 72.0

## Overridable in tests.
var day: String = ""

var _claim_button: Button = null
var _info_label: Label = null
var _progress_label: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()


func open() -> void:
	if day == "":
		day = Daily.today_key()
	_build()
	show()


func close() -> void:
	if visible:
		hide()
		closed.emit()


func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var frame := DialogFrame.attach(self, 960.0, 0.7)
	var box := frame.body
	box.add_theme_constant_override("separation", 10)

	box.add_child(_label(tr("CALENDAR_TITLE"), 32, GOLD, true))
	var p: Dictionary = PlayerProfile.local()
	var cal_state: Dictionary = p["calendar"]
	var claimed: int = int(cal_state.get("claimed_days", 0))
	var next_s: int = Calendar28.next_step(claimed)
	var can_claim: bool = Calendar28.can_claim(cal_state, day, p["wallet"])

	_progress_label = _label(tr("CALENDAR_PROGRESS") % claimed, 20, Color.WHITE, true)
	_progress_label.name = "ProgressLabel"
	box.add_child(_progress_label)

	var rule := _label(tr("CALENDAR_RULE"), 16, SOFT_COLOR, true)
	box.add_child(rule)

	# 28 days grid: 7 columns x 4 rows
	var grid := GridContainer.new()
	grid.name = "DaysGrid"
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	for step in range(1, Calendar28.CYCLE_DAYS + 1):
		grid.add_child(_build_day_cell(step, claimed, next_s, can_claim))
	box.add_child(grid)

	# Status / Claim action row
	if can_claim:
		var rew: Dictionary = Calendar28.reward_for_step(next_s)
		_claim_button = Button.new()
		_claim_button.name = "ClaimButton"
		_claim_button.text = (
			tr("CALENDAR_CLAIM")
			+ " (+%d 🪙  +%d 💎)" % [int(rew.get("coins", 0)), int(rew.get("gems", 0))]
		)
		_claim_button.focus_mode = Control.FOCUS_NONE
		_claim_button.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
		_claim_button.theme_type_variation = &"PrimaryButton"
		_claim_button.add_theme_font_size_override("font_size", 22)
		_claim_button.pressed.connect(_on_claim_pressed)
		box.add_child(_claim_button)
	else:
		_info_label = _label(tr("CALENDAR_COME_BACK"), 20, OK_COLOR, true)
		_info_label.name = "InfoLabel"
		box.add_child(_info_label)

	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = tr("MAP_CLOSE")
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(0, 64)
	close_button.theme_type_variation = &"SecondaryButton"
	close_button.add_theme_font_size_override("font_size", 20)
	close_button.pressed.connect(close)
	box.add_child(close_button)


func _build_day_cell(step: int, claimed: int, next_s: int, can_claim: bool) -> Control:
	var cell := PanelContainer.new()
	cell.name = "DayCell%d" % step
	cell.theme_type_variation = &"HudChip"
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.custom_minimum_size = Vector2(0, 80)

	var cycle_step: int = Calendar28.step_of(claimed)
	var is_claimed: bool = (step <= cycle_step and claimed > 0)
	var is_today: bool = can_claim and (step == next_s)

	if is_today:
		cell.self_modulate = Color(1.5, 1.3, 0.7)
	elif is_claimed:
		cell.self_modulate = Color(0.65, 0.85, 0.65)
	else:
		cell.self_modulate = Color(0.8, 0.85, 0.95, 0.8)

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	cell.add_child(v)

	var top_row := HBoxContainer.new()
	top_row.alignment = BoxContainer.ALIGNMENT_CENTER
	top_row.add_theme_constant_override("separation", 4)
	var title_color: Color = GOLD if (step % 7 == 0) else (OK_COLOR if is_claimed else SOFT_COLOR)
	top_row.add_child(_label(tr("CALENDAR_DAY") % step, 14, title_color, true))
	if is_claimed:
		var check := TextureRect.new()
		check.texture = CHECK_ICON
		check.custom_minimum_size = Vector2(16, 16)
		check.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		check.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		top_row.add_child(check)
	v.add_child(top_row)

	var rew: Dictionary = Calendar28.reward_for_step(step)
	var rewards_row := HBoxContainer.new()
	rewards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	rewards_row.add_theme_constant_override("separation", 4)

	var coin_ico := TextureRect.new()
	coin_ico.texture = COIN_ICON
	coin_ico.custom_minimum_size = Vector2(16, 16)
	coin_ico.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_ico.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rewards_row.add_child(coin_ico)
	rewards_row.add_child(_label(str(int(rew.get("coins", 0))), 14, Color.WHITE, true))

	var gem_ico := TextureRect.new()
	gem_ico.texture = GEM_ICON
	gem_ico.custom_minimum_size = Vector2(16, 16)
	gem_ico.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gem_ico.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rewards_row.add_child(gem_ico)
	rewards_row.add_child(
		_label(str(int(rew.get("gems", 0))), 14, GOLD if (step % 7 == 0) else Color.WHITE, true)
	)
	v.add_child(rewards_row)

	return cell


func _on_claim_pressed() -> void:
	var p: Dictionary = PlayerProfile.local()
	var res: Dictionary = Calendar28.claim(p["calendar"], day, p["wallet"], p["camp"])
	if bool(res["success"]):
		PlayerProfile.save_local(p)
		reward_claimed.emit(int(res["step"]), int(res["coins"]), int(res["gems"]))
		Toast.show_on(
			self,
			tr("CALENDAR_CLAIMED"),
			"+%d 🪙  +%d 💎" % [int(res["coins"]), int(res["gems"])]
		)
		_build()


func _label(text: String, size: int, color: Color, center: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

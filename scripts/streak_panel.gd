class_name StreakPanel
extends Control
## "Серия дней" card on the map: the 7-day reward row (today's day lit, the gift on day 7),
## the streak length, the active seasonal event, and the three daily quests with their
## progress and rewards. Built in code like DailyPanel; works offline.

signal closed

const GEM_ICON: Texture2D = preload("res://ui/icons/gem.png")
const GOLD := Color(0.98, 0.8, 0.4)
const SOFT_COLOR := Color(0.82, 0.86, 0.95)
const OK_COLOR := Color(0.62, 0.95, 0.42)
const BUTTON_HEIGHT := 84.0

## Overridable in tests.
var day: String = ""


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
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.06, 0.14, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	box.add_child(_label(tr("STREAK_TITLE"), 34, GOLD, true))
	var state: Dictionary = Streak.local()
	var live: int = Streak.live_length(state, day)
	var line := _label(tr("STREAK_LINE") % [live, int(state["best"])], 22, Color.WHITE, true)
	line.name = "StreakLine"
	box.add_child(line)
	box.add_child(_build_days(Streak.day_of_cycle(live)))
	var rule := _label(tr("STREAK_RULE"), 17, SOFT_COLOR, true)
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(rule)
	var event: Dictionary = Events.active(day)
	if not event.is_empty():
		var banner := _label(
			tr("EVENT_BANNER") % [tr(str(event["name_key"])), str(snappedf(float(event["reward_mult"]), 0.1))],
			22,
			Color(1.0, 0.86, 0.45),
			true
		)
		banner.name = "EventBanner"
		box.add_child(banner)

	box.add_child(_label(tr("QUESTS_TITLE"), 28, GOLD, true))
	for def in Quests.for_day(day):
		box.add_child(_quest_row(def))
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = tr("MAP_CLOSE")
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	close_button.theme_type_variation = &"SecondaryButton"
	close_button.add_theme_font_size_override("font_size", 24)
	close_button.pressed.connect(close)
	box.add_child(close_button)


## Seven cells: day number and reward; days before `today_cell` are done, that one is lit.
func _build_days(today_cell: int) -> Control:
	var row := HBoxContainer.new()
	row.name = "Days"
	row.add_theme_constant_override("separation", 8)
	var rewards: Array = Streak.rewards()
	for i in range(1, Streak.WEEK + 1):
		var cell := PanelContainer.new()
		cell.name = "Day%d" % i
		cell.theme_type_variation = &"HudChip"
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.custom_minimum_size = Vector2(0, 110)
		if i == today_cell:
			cell.self_modulate = Color(1.5, 1.25, 0.7)
		elif i < today_cell:
			cell.self_modulate = Color(0.7, 0.9, 0.7)
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", 2)
		cell.add_child(v)
		v.add_child(_label(tr("STREAK_DAY") % i, 18, SOFT_COLOR, true))
		var gem := HBoxContainer.new()
		gem.alignment = BoxContainer.ALIGNMENT_CENTER
		gem.add_theme_constant_override("separation", 4)
		var icon := TextureRect.new()
		icon.texture = GEM_ICON
		icon.custom_minimum_size = Vector2(30, 30)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		gem.add_child(icon)
		gem.add_child(_label(str(int(rewards[i - 1])), 26, GOLD if i == Streak.WEEK else Color.WHITE, true))
		v.add_child(gem)
		if i == Streak.WEEK:
			v.add_child(_label(tr("STREAK_GIFT"), 14, GOLD, true))
		row.add_child(cell)
	return row


func _quest_row(def: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.name = "Quest%d" % int(def["slot"])
	row.add_theme_constant_override("separation", 12)
	var done: bool = Quests.is_done(day, def)
	var text := _label(Quests.text(def), 24, OK_COLOR if done else Color.WHITE, false)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var value: int = mini(Quests.value(day, def), int(def["target"]))
	var progress := _label(
		tr("QUEST_DONE") if done else "%d / %d" % [value, int(def["target"])],
		22,
		OK_COLOR if done else SOFT_COLOR,
		false
	)
	progress.name = "Progress"
	row.add_child(progress)
	var icon := TextureRect.new()
	icon.texture = GEM_ICON
	icon.custom_minimum_size = Vector2(30, 30)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	row.add_child(_label(str(int(def["reward"])), 24, GOLD, false))
	return row


func _label(text: String, size: int, color: Color, centered: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

class_name ModesPanel
extends Control
## Modes selection dialog on the world map:
## Daily Challenge, 2-player Co-op, and Global Leaderboards.

signal daily_selected
signal coop_selected
signal records_selected
signal closed

const DAILY_ICON: Texture2D = preload("res://ui/icons/hourglass.png")
const FRIENDS_ICON: Texture2D = preload("res://ui/icons/friends.png")
const TROPHY_ICON: Texture2D = preload("res://ui/icons/trophy.png")
const GOLD := Color(0.98, 0.8, 0.4)
const SOFT_COLOR := Color(0.82, 0.86, 0.95)
const BUTTON_HEIGHT := 84.0

var coop_available: bool = false
var online_available: bool = false
var _frame: DialogFrame = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	hide()
	if _frame != null:
		_frame.hide()


func open() -> void:
	show()
	if _frame != null:
		_frame.show()


func close() -> void:
	if visible:
		hide()
		if _frame != null:
			_frame.hide()
		closed.emit()


func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_frame = DialogFrame.attach(self, 760.0, 0.7)
	var box := _frame.body
	box.add_theme_constant_override("separation", 12)

	var title := Label.new()
	title.text = tr("MODES_TITLE")
	title.theme_type_variation = &"HeadingLabel"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = tr("MODES_DAILY_DESC")
	subtitle.theme_type_variation = &"CaptionLabel"
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", SOFT_COLOR)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)

	# 1. Daily Challenge Button
	var daily_btn := _mode_button(
		"DailyModeButton", tr("DAILY_BUTTON"), tr("MODES_DAILY_DESC"), DAILY_ICON
	)
	daily_btn.pressed.connect(
		func() -> void:
			close()
			daily_selected.emit()
	)
	box.add_child(daily_btn)

	# 2. Co-op Button (only if database/transport available)
	if coop_available or CoopRun.transport() != null:
		var coop_btn := _mode_button(
			"CoopButton", tr("COOP_BUTTON"), tr("MODES_COOP_DESC"), FRIENDS_ICON
		)
		coop_btn.pressed.connect(
			func() -> void:
				close()
				coop_selected.emit()
		)
		box.add_child(coop_btn)

	# 3. Global Leaderboards Button (if online configured)
	if online_available or Online.is_configured():
		var records_btn := _mode_button(
			"RecordsButton", tr("MAP_RECORDS"), tr("MODES_RECORDS_DESC"), TROPHY_ICON
		)
		records_btn.pressed.connect(
			func() -> void:
				close()
				records_selected.emit()
		)
		box.add_child(records_btn)

	# Close button
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = tr("MAP_CLOSE")
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	close_button.theme_type_variation = &"SecondaryButton"
	close_button.add_theme_font_size_override("font_size", 24)
	close_button.pressed.connect(close)
	box.add_child(close_button)


func _mode_button(
	btn_name: String, title_text: String, desc_text: String, icon_tex: Texture2D
) -> Button:
	var button := Button.new()
	button.name = btn_name
	button.text = title_text
	button.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	button.focus_mode = Control.FOCUS_NONE
	button.theme_type_variation = &"SecondaryButton"
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.icon = icon_tex
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", 48)
	button.add_theme_font_size_override("font_size", 22)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if desc_text != "":
		button.tooltip_text = desc_text
	return button

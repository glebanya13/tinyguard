class_name AchievementsPanel
extends Control
## The list of achievements (from the world map): name, what to do, progress bar
## text; the earned ones are green. Built in code like SettingsPanel.

signal closed

const GOLD := Color(0.98, 0.8, 0.4)
const SOFT_COLOR := Color(0.82, 0.86, 0.95)
const DONE_COLOR := Color(0.62, 0.95, 0.5)
const BUTTON_HEIGHT := 84.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()


## Re-checks the save (a perk may have been bought on the map) and shows the list.
func open() -> void:
	Achievements.check()
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
	var frame := DialogFrame.attach(self, 760.0, 0.7)
	frame.min_height = 600.0
	var box := frame.body
	box.add_theme_constant_override("separation", 10)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := _label(
		tr("ACH_TITLE") % [Achievements.unlocked_count(), Achievements.all().size()], 32, GOLD
	)
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	var metrics: Dictionary = Achievements.metrics()
	var mask: int = Achievements.unlocked_mask()
	for def in Achievements.all():
		list.add_child(_row(def, metrics, Achievements.mask_has(mask, def)))
	var back := Button.new()
	back.name = "CloseButton"
	back.text = tr("MAP_CLOSE")
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	back.add_theme_font_size_override("font_size", 24)
	back.pressed.connect(close)
	box.add_child(back)


func _row(def: Dictionary, metrics: Dictionary, done: bool) -> Control:
	var card := PanelContainer.new()
	card.name = "Row_" + str(def["id"])
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	card.add_child(col)
	var key: String = str(def["key"])
	var head := _label(tr(key), 24, DONE_COLOR if done else GOLD)
	col.add_child(head)
	var desc := _label(tr(key + "_DESC"), 18, SOFT_COLOR)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(desc)
	var line: String = (
		tr("ACH_EARNED")
		if done
		else "%d / %d" % [Achievements.progress(def, metrics), int(def["threshold"])]
	)
	col.add_child(_label(line, 17, Color(SOFT_COLOR, 0.8)))
	return card


func _label(text: String, size: int, color: Color = Color(1, 0.96, 0.87)) -> Label:
	var label := Label.new()
	label.text = text
	UiKit.style_label(label, size, color)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

class_name DailyPanel
extends Control
## "Испытание дня" card on the world map: today's level and modifiers, your best wave
## and time, the streak, the bonus stars, the online board (only with Firebase), and
## the Play button. Built in code like SettingsPanel; works fully offline.

## The player pressed Play: start the challenge of `day` (UTC date).
signal start_requested(day: String)
signal closed

const GOLD := Color(0.98, 0.8, 0.4)
const SOFT_COLOR := Color(0.82, 0.86, 0.95)
const BUTTON_HEIGHT := 84.0
const BOARD_ROWS := 5

## The Online autoload (set by the map; null = offline, as in tests: a script that names
## an autoload does not compile outside the running game).
var online: Node = null
## Overridable in tests.
var day: String = ""

var _board: VBoxContainer = null
var _status: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()


func open() -> void:
	if day == "":
		day = Daily.today_key()
	_build()
	show()
	if _online_on():
		if not online.daily_loaded.is_connected(_on_board):
			online.daily_loaded.connect(_on_board)
		if not online.daily_failed.is_connected(_on_board_failed):
			online.daily_failed.connect(_on_board_failed)
		online.fetch_daily(day)


## Back button: closes the panel.
func close() -> void:
	if visible:
		hide()
		closed.emit()


func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var frame := DialogFrame.attach(self, 720.0, 0.7)
	var box := frame.body
	box.add_theme_constant_override("separation", 10)

	var level: Dictionary = LevelCatalog.get_level(Daily.level_for(day))
	var preset: Dictionary = Daily.preset_for(day)
	box.add_child(_label(tr("DAILY_TITLE"), 34, GOLD))
	box.add_child(_label(tr("DAILY_TODAY") % [day, tr(str(level["name"]))], 22))
	var mod := _label(tr(str(preset["key"])), 26, Color(1.0, 0.86, 0.45))
	mod.name = "ModName"
	box.add_child(mod)
	var desc := _label(tr(str(preset["key"]) + "_DESC"), 19, SOFT_COLOR)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(desc)
	box.add_child(_label(tr("DAILY_GOAL"), 19, SOFT_COLOR))

	var best: int = Daily.best_wave(day)
	var results := _label("", 22)
	results.name = "Results"
	if best > 0:
		var secs: int = Daily.best_time(day)
		results.text = tr("DAILY_BEST") % [best, floori(secs / 60.0), secs % 60]
	else:
		results.text = tr("DAILY_NOT_PLAYED")
	box.add_child(results)
	var streak := _label(tr("DAILY_STREAK") % Daily.live_streak(day), 22)
	streak.name = "Streak"
	box.add_child(streak)
	var bonus := _label(
		tr("DAILY_BONUS") % [Daily.star_wave(), Daily.bonus_stars(), Daily.max_stars()],
		19,
		SOFT_COLOR
	)
	bonus.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(bonus)

	if _online_on():
		box.add_child(_label(tr("DAILY_BOARD"), 22, GOLD))
		_board = VBoxContainer.new()
		_board.name = "Board"
		box.add_child(_board)
		_status = _label(tr("MAP_LOADING"), 18, SOFT_COLOR)
		box.add_child(_status)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	var play := _button(tr("DAILY_PLAY"), func() -> void: start_requested.emit(day), false)
	play.name = "PlayButton"
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(play)
	var back := _button(tr("MAP_CLOSE"), close, true)
	back.name = "CloseButton"
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(back)


func _online_on() -> bool:
	return online != null and online.is_configured()


func _on_board(board_day: String, entries: Array) -> void:
	if _board == null or not is_instance_valid(_board) or board_day != day:
		return
	for child in _board.get_children():
		child.queue_free()
	_status.text = "" if not entries.is_empty() else tr("DAILY_NO_BOARD")
	for i in mini(entries.size(), BOARD_ROWS):
		var row := _label(
			tr("MAP_RECORD_ROW") % [i + 1, entries[i]["name"], entries[i]["wave"]], 20
		)
		if i == 0:
			row.add_theme_color_override("font_color", GOLD)
		_board.add_child(row)


func _on_board_failed(board_day: String, reason: String) -> void:
	if _status == null or not is_instance_valid(_status) or board_day != day:
		return
	_status.text = tr(RecordsPanel.FAIL_KEYS.get(reason, "MAP_REC_FAILED"))


func _label(text: String, size: int, color: Color = Color(1, 0.96, 0.87)) -> Label:
	var label := Label.new()
	label.text = text
	UiKit.style_label(label, size, color)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, action: Callable, secondary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	if secondary:
		button.theme_type_variation = &"SecondaryButton"
	button.pressed.connect(action)
	return button

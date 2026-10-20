class_name RecordsPanel
extends Control
## Records of the Record Run on the world map: top 10 of a level, the cloud save buttons.
## Every outcome of the request is shown, none leaves "Loading…" on the screen: the table, "nobody
## yet", "internet needed", "could not load" with a Retry button (the request has a deadline,
## see OnlineRecords.query_board). The cloud buttons show their result and never block the panel.

signal closed

const GOLD := Color(1.0, 0.88, 0.45)
const SOFT := Color(0.78, 0.84, 0.97)
const OK := Color(0.56, 0.96, 0.5)
const BAD := Color(1.0, 0.62, 0.55)
const SPINNER: Texture2D = preload("res://ui/icons/hourglass.png")
const STATE_IDLE := 0
const STATE_LOADING := 1
const STATE_DONE := 2
## Status text key by failure reason.
const FAIL_KEYS := {
	"offline": "MAP_REC_OFFLINE",
	"disabled": "MAP_REC_DISABLED",
	"denied": "MAP_REC_DENIED",
	"timeout": "MAP_REC_FAILED",
	"error": "MAP_REC_FAILED",
}

## The online module: the creator hands over the Online autoload (tests give a fake one).
var online: Node = null
var level_id: int = 0
var state: int = STATE_IDLE

var _frame: DialogFrame = null
var _title: Label = null
var _list: VBoxContainer = null
var _status_row: HBoxContainer = null
var _spinner: TextureRect = null
var _status: Label = null
var _note: Label = null
var _retry: Button = null
var _to_cloud: Button = null
var _from_cloud: Button = null
var _spin_tween: Tween = null
var _cloud_busy: bool = false
var _level_name: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	online.leaderboard_loaded.connect(_on_loaded)
	online.leaderboard_failed.connect(_on_failed)
	online.status_changed.connect(_on_status)
	hide()


## Shows the table of `level` (a level name for the title) and asks the server for it.
func open(level: int, level_name: String) -> void:
	level_id = level
	_level_name = level_name
	_title.text = tr("MAP_RECORDS_TITLE") % level_name
	_note.text = ""
	show()
	request()


func close() -> void:
	if visible:
		hide()
		_stop_spinner()
		closed.emit()


## (Re)loads the table: shows the progress, clears the old rows.
func request() -> void:
	state = STATE_LOADING
	_clear_rows()
	_retry.hide()
	_set_status(tr("MAP_LOADING"), SOFT, true)
	online.fetch_leaderboard(level_id)


## Text of the status line (tests).
func status_text() -> String:
	return _status.text


func rows() -> int:
	return _list.get_child_count()


func is_retry_visible() -> bool:
	return _retry.visible


func note_text() -> String:
	return _note.text


func _build() -> void:
	_frame = DialogFrame.attach(self, 860.0, 0.6)
	var box := _frame.body
	box.add_theme_constant_override("separation", 10)
	_title = UiKit.ribbon("")
	box.add_child(_title)
	var name_label := Label.new()
	name_label.name = "YourName"
	name_label.text = tr("MAP_YOUR_NAME") % online.player_name()
	box.add_child(name_label)
	_list = VBoxContainer.new()
	_list.name = "Rows"
	_list.custom_minimum_size = Vector2(0, 120)
	box.add_child(_list)
	_status_row = HBoxContainer.new()
	_status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_status_row.add_theme_constant_override("separation", 10)
	box.add_child(_status_row)
	_spinner = TextureRect.new()
	_spinner.texture = SPINNER
	_spinner.custom_minimum_size = Vector2(40, 40)
	_spinner.pivot_offset = Vector2(20, 20)
	_spinner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_spinner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_row.add_child(_spinner)
	_status = Label.new()
	_status.name = "Status"
	_status.theme_type_variation = &"CaptionLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_row.add_child(_status)
	_note = Label.new()
	_note.name = "CloudNote"
	_note.theme_type_variation = &"CaptionLabel"
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_note)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	_retry = _button(tr("MAP_RETRY"), request, false)
	_retry.name = "RetryButton"
	_retry.hide()
	buttons.add_child(_retry)
	_to_cloud = _button(tr("MAP_TO_CLOUD"), _on_to_cloud, true)
	_to_cloud.name = "ToCloudButton"
	buttons.add_child(_to_cloud)
	_from_cloud = _button(tr("MAP_FROM_CLOUD"), _on_from_cloud, true)
	_from_cloud.name = "FromCloudButton"
	buttons.add_child(_from_cloud)
	var back := _button(tr("MAP_CLOSE"), close, false)
	back.name = "CloseButton"
	buttons.add_child(back)


func _button(text: String, action: Callable, secondary: bool) -> Button:
	var button := UiKit.button(text, &"SecondaryButton" if secondary else &"", 170.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	return button


func _clear_rows() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()


func _set_status(text: String, color: Color, loading: bool) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)
	_spinner.visible = loading
	if loading:
		_start_spinner()
	else:
		_stop_spinner()


func _start_spinner() -> void:
	_stop_spinner()
	if not is_inside_tree():
		return
	_spinner.rotation = 0.0
	_spin_tween = create_tween().set_loops()
	_spin_tween.tween_property(_spinner, "rotation", PI, 0.6).set_trans(Tween.TRANS_SINE)
	_spin_tween.tween_property(_spinner, "rotation", TAU, 0.6).set_trans(Tween.TRANS_SINE)


func _stop_spinner() -> void:
	if _spin_tween != null:
		_spin_tween.kill()
		_spin_tween = null


func _on_loaded(level: int, entries: Array) -> void:
	if level != level_id or state != STATE_LOADING:
		return
	state = STATE_DONE
	_clear_rows()
	_retry.hide()
	if entries.is_empty():
		_set_status(tr("MAP_NO_RECORDS"), SOFT, false)
		return
	_set_status("", SOFT, false)
	for i in entries.size():
		var row := Label.new()
		row.text = tr("MAP_RECORD_ROW") % [i + 1, entries[i]["name"], entries[i]["wave"]]
		row.add_theme_font_size_override("font_size", 19)
		if i == 0:
			row.add_theme_color_override("font_color", GOLD)
		_list.add_child(row)


func _on_failed(level: int, reason: String) -> void:
	if level != level_id or state != STATE_LOADING:
		return
	state = STATE_DONE
	_clear_rows()
	var key: String = FAIL_KEYS.get(reason, "MAP_REC_FAILED")
	_set_status(tr(key), BAD, false)
	_retry.visible = reason != "disabled"


func _on_to_cloud() -> void:
	_begin_cloud()
	online.cloud_save()


func _on_from_cloud() -> void:
	_begin_cloud()
	online.cloud_load()


func _begin_cloud() -> void:
	_cloud_busy = true
	_to_cloud.disabled = true
	_from_cloud.disabled = true
	_note.add_theme_color_override("font_color", SOFT)
	_note.text = tr("SYNC_SYNCING")


## The result line of a cloud action ("saved", "updated", the error); other messages of Online (a
## record sent) are shown too, but only while this panel waits for the cloud.
func _on_status(text: String) -> void:
	if not _cloud_busy:
		return
	_note.text = text
	var bad: bool = text in [tr("ONLINE_ERR_OFFLINE"), tr("ONLINE_ERR_NEWER")]
	bad = bad or text in [tr("ONLINE_ERR_SESSION_LOST"), tr("ONLINE_ERR_NOT_CONFIGURED")]
	bad = bad or text == tr("ONLINE_ERR_GENERIC")
	_note.add_theme_color_override("font_color", BAD if bad else OK)
	_cloud_done()  # cloud_save / cloud_load end with exactly one status message


func _cloud_done() -> void:
	_cloud_busy = false
	_to_cloud.disabled = false
	_from_cloud.disabled = false

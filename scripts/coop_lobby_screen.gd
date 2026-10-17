class_name CoopLobbyScreen
extends Control
## Co-op lobby (two players): create a room (a 5-letter code, level choice by
## the host, players and readiness, "Start") or join with a code typed on an
## on-screen keyboard. Built in code. The room logic is CoopLobby; this screen
## only shows its snapshot and turns taps into calls. When the match starts the
## settings go to CoopRun and the battle scene loads. See docs/MULTIPLAYER.md.

const MAP_SCENE := "res://scenes/level_select.tscn"
const GAME_SCENE := "res://scenes/main.tscn"
const BACKDROP: Texture2D = preload("res://ui/app/backdrop.jpg")
const GOLD := Color(0.98, 0.8, 0.4)
const OK_COLOR := Color(0.62, 0.95, 0.42)
const INFO_COLOR := Color(0.62, 0.86, 1.0)
const ERROR_COLOR := Color(1.0, 0.62, 0.55)
const SOFT_COLOR := Color(0.82, 0.86, 0.95)
const KEY_SIZE := Vector2(84, 84)
const KEY_COLUMNS := 8
## Error / closing reasons of CoopLobby -> translation keys.
const REASON_TEXT := {
	"offline": "COOP_ERR_OFFLINE",
	"denied": "COOP_ERR_DENIED",
	"busy": "COOP_ERR_BUSY",
	"invalid": "COOP_ERR_INVALID",
	"not_found": "COOP_ERR_NOT_FOUND",
	"expired": "COOP_ERR_EXPIRED",
	"started": "COOP_ERR_STARTED",
	"full": "COOP_ERR_FULL",
	"version": "COOP_ERR_VERSION",
	"own_room": "COOP_ERR_OWN_ROOM",
	"not_ready": "COOP_ERR_NOT_READY",
	"host_left": "COOP_CLOSED_HOST_LEFT",
	"guest_left": "COOP_CLOSED_GUEST_LEFT",
	"timeout": "COOP_CLOSED_TIMEOUT",
	"closed": "COOP_CLOSED_CLOSED",
}

## Transport of the room (null: Online.rtdb). Tests and screenshots set it first.
var transport: CoopTransport = null
## Nickname shown to the partner (empty: the profile's).
var nickname: String = ""
var lobby: CoopLobby = null
## Load the battle scene when the match starts (tests and screenshots turn it off).
var auto_load: bool = true

var _code_input: String = ""
var _level: int = 1
var _busy: bool = false
var _menu_view: Control
var _join_view: Control
var _room_view: Control
var _status: Label
var _code_label: Label
var _join_button: Button
var _room_code: Label
var _level_label: Label
var _level_prev: Button
var _level_next: Button
var _host_row: Label
var _guest_row: Label
var _ready_button: Button
var _start_button: Button
var _wait_label: Label


func _ready() -> void:
	GameSettings.apply_language()
	theme = load("res://ui/theme.tres")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if transport == null:
		transport = CoopRun.transport()
	if nickname == "":
		nickname = Online.player_name()
	if nickname == "":
		nickname = tr("COOP_UNNAMED")
	_level = clampi(LevelCatalog.selected_id, 1, maxi(LevelCatalog.unlocked(), 1))
	_build()
	_show_view(_menu_view)
	if transport == null or not transport.is_ready():
		_set_status(tr("COOP_ERR_OFFLINE"), ERROR_COLOR)


func _process(delta: float) -> void:
	if lobby != null:
		lobby.process(delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back_pressed()


func _unhandled_key_input(event: InputEvent) -> void:
	if not _join_view.visible or not event is InputEventKey or not event.pressed:
		return
	var key := event as InputEventKey
	if key.keycode == KEY_BACKSPACE:
		_on_backspace()
	elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		_on_join_pressed()
	elif key.unicode > 0:
		var letter: String = String.chr(key.unicode).to_upper()
		if CoopLobby.CODE_ALPHABET.contains(letter):
			_on_key(letter)


## Texts for the status line of a CoopLobby reason ("not_found" -> translated).
static func reason_text(reason: String) -> String:
	return TranslationServer.translate(REASON_TEXT.get(reason, "COOP_ERR_DENIED"))


## Current code as typed (tests).
func typed_code() -> String:
	return _code_input


func status_text() -> String:
	return _status.text


func _build() -> void:
	var bg := TextureRect.new()
	bg.texture = BACKDROP
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margins: Vector4 = ScreenUtil.safe_margins(get_viewport())
	safe.add_theme_constant_override("margin_left", int(margins.x) + 16)
	safe.add_theme_constant_override("margin_top", int(margins.y) + 12)
	safe.add_theme_constant_override("margin_right", int(margins.z) + 16)
	safe.add_theme_constant_override("margin_bottom", int(margins.w) + 12)
	add_child(safe)
	var center := CenterContainer.new()
	safe.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := UiKit.ribbon(tr("COOP_TITLE"))
	box.add_child(title)
	_menu_view = _build_menu()
	_join_view = _build_join()
	_room_view = _build_room()
	box.add_child(_menu_view)
	box.add_child(_join_view)
	box.add_child(_room_view)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 56)
	_status.add_theme_font_size_override("font_size", 22)
	box.add_child(_status)


func _build_menu() -> Control:
	var view := VBoxContainer.new()
	view.add_theme_constant_override("separation", 12)
	var hint := _label(tr("COOP_INTRO"), 22, SOFT_COLOR)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(0, 90)
	view.add_child(hint)
	view.add_child(_button(tr("COOP_CREATE"), _on_create_pressed, 560, false))
	view.add_child(_button(tr("COOP_JOIN"), _on_join_menu_pressed, 560, false))
	view.add_child(_button(tr("COOP_BACK"), _on_back_pressed, 560, true))
	return view


func _build_join() -> Control:
	var view := VBoxContainer.new()
	view.add_theme_constant_override("separation", 8)
	view.add_child(_label(tr("COOP_ENTER_CODE"), 22, SOFT_COLOR))
	_code_label = _label("", 60, GOLD)
	_code_label.custom_minimum_size = Vector2(0, 76)
	view.add_child(_code_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	view.add_child(row)
	var grid := GridContainer.new()
	grid.columns = KEY_COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	row.add_child(grid)
	for i in CoopLobby.CODE_ALPHABET.length():
		var letter: String = CoopLobby.CODE_ALPHABET[i]
		var key := _button(letter, _on_key.bind(letter), 0, false)
		key.custom_minimum_size = KEY_SIZE
		key.add_theme_font_size_override("font_size", 32)
		grid.add_child(key)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	row.add_child(side)
	var erase := _button("⌫", _on_backspace, 0, true)
	erase.custom_minimum_size = KEY_SIZE
	erase.add_theme_font_size_override("font_size", 36)
	side.add_child(erase)
	_join_button = _button(tr("COOP_JOIN_GO"), _on_join_pressed, 0, false)
	_join_button.custom_minimum_size = Vector2(150, 84)
	side.add_child(_join_button)
	var back := _button(tr("COOP_BACK"), _on_back_pressed, 0, true)
	back.custom_minimum_size = Vector2(150, 84)
	side.add_child(back)
	return view


func _build_room() -> Control:
	var view := VBoxContainer.new()
	view.add_theme_constant_override("separation", 8)
	view.add_child(_label(tr("COOP_ROOM_CODE"), 20, SOFT_COLOR))
	_room_code = _label("", 72, GOLD)
	view.add_child(_room_code)
	var level_row := HBoxContainer.new()
	level_row.alignment = BoxContainer.ALIGNMENT_CENTER
	level_row.add_theme_constant_override("separation", 10)
	view.add_child(level_row)
	_level_prev = _button("◀", _on_level_step.bind(-1), 0, true)
	_level_prev.custom_minimum_size = KEY_SIZE
	level_row.add_child(_level_prev)
	_level_label = _label("", 26, Color.WHITE)
	_level_label.custom_minimum_size = Vector2(520, 0)
	level_row.add_child(_level_label)
	_level_next = _button("▶", _on_level_step.bind(1), 0, true)
	_level_next.custom_minimum_size = KEY_SIZE
	level_row.add_child(_level_next)
	_host_row = _label("", 24, Color.WHITE)
	_guest_row = _label("", 24, Color.WHITE)
	view.add_child(_host_row)
	view.add_child(_guest_row)
	_wait_label = _label("", 20, INFO_COLOR)
	view.add_child(_wait_label)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	view.add_child(buttons)
	_ready_button = _button(tr("COOP_READY"), _on_ready_pressed, 280, false)
	buttons.add_child(_ready_button)
	_start_button = _button(tr("COOP_START"), _on_start_pressed, 280, false)
	buttons.add_child(_start_button)
	buttons.add_child(_button(tr("COOP_LEAVE"), _on_back_pressed, 220, true))
	return view


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	UiKit.style_label(label, size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, action: Callable, width: int, secondary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(width, 84)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if secondary:
		button.theme_type_variation = &"SecondaryButton"
	button.pressed.connect(action)
	return button


func _show_view(view: Control) -> void:
	for candidate: Control in [_menu_view, _join_view, _room_view]:
		candidate.visible = candidate == view
	if view == _join_view:
		_refresh_code()


func _set_status(text: String, color: Color = SOFT_COLOR) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


func _can_use_network() -> bool:
	if transport == null or not transport.is_ready():
		_set_status(tr("COOP_ERR_OFFLINE"), ERROR_COLOR)
		return false
	return true


# --- menu / join ----------------------------------------------------------------


func _on_create_pressed() -> void:
	if _busy or not _can_use_network():
		return
	_busy = true
	_set_status(tr("COOP_CONNECTING"), INFO_COLOR)
	var room := CoopLobby.new(transport)
	var made: Dictionary = await room.create(_level, nickname, Sim.VERSION)
	_busy = false
	if not made["ok"]:
		_set_status(reason_text(str(made["reason"])), ERROR_COLOR)
		return
	_adopt(room)
	_set_status("")


func _on_join_menu_pressed() -> void:
	_code_input = ""
	_set_status("")
	_show_view(_join_view)


func _on_key(letter: String) -> void:
	if _code_input.length() < CoopLobby.CODE_LENGTH:
		_code_input += letter
		_refresh_code()


func _on_backspace() -> void:
	_code_input = _code_input.substr(0, _code_input.length() - 1)
	_refresh_code()


func _refresh_code() -> void:
	var cells: PackedStringArray = []
	for i in CoopLobby.CODE_LENGTH:
		cells.append(_code_input[i] if i < _code_input.length() else "·")
	_code_label.text = "  ".join(cells)
	_join_button.disabled = _code_input.length() != CoopLobby.CODE_LENGTH or _busy


func _on_join_pressed() -> void:
	if _busy or _code_input.length() != CoopLobby.CODE_LENGTH or not _can_use_network():
		return
	_busy = true
	_refresh_code()
	_set_status(tr("COOP_CONNECTING"), INFO_COLOR)
	var room := CoopLobby.new(transport)
	var joined: Dictionary = await room.join(_code_input, nickname, Sim.VERSION)
	_busy = false
	_refresh_code()
	if not joined["ok"]:
		_set_status(reason_text(str(joined["reason"])), ERROR_COLOR)
		return
	_adopt(room)
	_set_status("")


func _on_back_pressed() -> void:
	if _busy:
		return
	if lobby != null:
		_leave_room()
	elif _join_view.visible:
		_set_status("")
		_show_view(_menu_view)
	else:
		get_tree().change_scene_to_file(MAP_SCENE)


# --- room -----------------------------------------------------------------------


func _adopt(room: CoopLobby) -> void:
	lobby = room
	lobby.room_changed.connect(_refresh_room)
	lobby.started.connect(_on_started)
	lobby.closed.connect(_on_closed)
	_show_view(_room_view)
	_refresh_room()


func _leave_room() -> void:
	var room: CoopLobby = lobby
	lobby = null
	_show_view(_menu_view)
	_set_status("")
	if room != null:
		room.room_changed.disconnect(_refresh_room)
		room.started.disconnect(_on_started)
		room.closed.disconnect(_on_closed)
		await room.leave()


## Shows the room as CoopLobby.snapshot() sees it.
func _refresh_room() -> void:
	if lobby == null:
		return
	var info: Dictionary = lobby.snapshot()
	if info.is_empty():
		return
	var is_host: bool = info["role"] == "host"
	_room_code.text = "  ".join(str(info["code"]).split(""))
	_level = int(info["level"])
	var level: Dictionary = LevelCatalog.get_level(_level)
	_level_label.text = "%d. %s" % [_level, tr(str(level["name"]))]
	_level_prev.visible = is_host
	_level_next.visible = is_host
	_level_prev.disabled = _level <= 1
	_level_next.disabled = _level >= mini(LevelCatalog.unlocked(), LevelCatalog.levels().size())
	var host: Dictionary = info["host"]
	var guest: Dictionary = info["guest"]
	var host_ready: bool = info["me_ready"] if is_host else info["partner_ready"]
	var guest_ready: bool = info["partner_ready"] if is_host else info["me_ready"]
	_host_row.text = _player_line(tr("COOP_HOST"), host, host_ready)
	_host_row.add_theme_color_override("font_color", OK_COLOR if host_ready else Color.WHITE)
	_guest_row.text = _player_line(tr("COOP_GUEST"), guest, guest_ready)
	_guest_row.add_theme_color_override("font_color", OK_COLOR if guest_ready else Color.WHITE)
	_ready_button.visible = not is_host
	_ready_button.text = tr("COOP_NOT_READY") if info["me_ready"] else tr("COOP_READY")
	_start_button.visible = is_host
	_start_button.disabled = not bool(info["can_start"])
	if is_host:
		if guest.is_empty():
			_wait_label.text = tr("COOP_WAIT_PARTNER")
		elif not guest_ready:
			_wait_label.text = tr("COOP_WAIT_READY")
		else:
			_wait_label.text = tr("COOP_CAN_START")
	else:
		_wait_label.text = tr("COOP_WAIT_START") if info["me_ready"] else tr("COOP_PRESS_READY")


func _player_line(role_name: String, player: Dictionary, ready: bool) -> String:
	if player.is_empty():
		return "%s: %s" % [role_name, tr("COOP_EMPTY_SLOT")]
	var name_text: String = str(player.get("name", ""))
	if name_text == "":
		name_text = tr("COOP_UNNAMED")
	return "%s: %s   %s" % [role_name, name_text, tr("COOP_STATE_READY") if ready else "…"]


func _on_level_step(step: int) -> void:
	if _busy or lobby == null:
		return
	var target: int = clampi(
		_level + step, 1, mini(LevelCatalog.unlocked(), LevelCatalog.levels().size())
	)
	if target == _level:
		return
	_busy = true
	var reply: Dictionary = await lobby.set_level(target)
	_busy = false
	if not reply.get("ok", false):
		_set_status(reason_text("denied"), ERROR_COLOR)


func _on_ready_pressed() -> void:
	if _busy or lobby == null:
		return
	_busy = true
	var want: bool = not bool(lobby.snapshot().get("me_ready", false))
	var reply: Dictionary = await lobby.set_ready(want)
	_busy = false
	if not reply.get("ok", false):
		_set_status(reason_text("denied"), ERROR_COLOR)


func _on_start_pressed() -> void:
	if _busy or lobby == null:
		return
	_busy = true
	_set_status(tr("COOP_STARTING"), INFO_COLOR)
	var reply: Dictionary = await lobby.start_match()
	_busy = false
	if not reply.get("ok", false):
		_set_status(reason_text(str(reply.get("reason", "denied"))), ERROR_COLOR)


func _on_closed(reason: String) -> void:
	lobby = null
	_show_view(_menu_view)
	_set_status(reason_text(reason), ERROR_COLOR)


## Both players are in: remember the settings for the battle scene and go.
func _on_started(config: Dictionary) -> void:
	var info: Dictionary = lobby.snapshot()
	var partner: Dictionary = info["guest"] if config["role"] == "host" else info["host"]
	config["name"] = nickname
	config["partner"] = str(partner.get("name", ""))
	config["partner_skin"] = Cosmetics.sanitize(partner.get("skin", ""), Cosmetics.HERO)
	LevelCatalog.selected_id = int(config["level"])
	LevelCatalog.endless = false
	LevelCatalog.tutorial = false
	CoopRun.config = config
	CoopRun.lobby = lobby
	lobby.room_changed.disconnect(_refresh_room)
	lobby.closed.disconnect(_on_closed)
	lobby = null
	if auto_load:
		get_tree().change_scene_to_file(GAME_SCENE)

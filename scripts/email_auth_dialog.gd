class_name EmailAuthDialog
extends Control
## Compact modal for the email flows: create an account (first launch: email,
## password, nickname), link an email and password to the guest account, sign in on
## another device, ask for a password reset mail. Built in code like the panel; talks to the Online
## autoload and reports up by signals. The password lives only in its field: it
## is cleared on success and on close, never saved and never printed.

## `kind` is "register", "link", "signin" or "reset"; `result` is the Online answer.
signal succeeded(kind: String, result: Dictionary)
signal closed

enum Mode { LINK, SIGN_IN, RESET, REGISTER }

const GOLD := Color(0.98, 0.8, 0.4)
const OK_COLOR := Color(0.62, 0.95, 0.42)
const INFO_COLOR := Color(0.62, 0.86, 1.0)
const ERROR_COLOR := Color(1.0, 0.62, 0.55)
const SOFT_COLOR := Color(0.82, 0.86, 0.95)
const FIELD_HEIGHT := 72.0
const BUTTON_HEIGHT := 84.0
const KINDS := ["link", "signin", "reset", "register"]
const TITLES := ["EMAIL_TITLE_LINK", "EMAIL_TITLE_SIGNIN", "EMAIL_TITLE_RESET", "EMAIL_TITLE_REGISTER"]
const NOTES := ["EMAIL_NOTE_LINK", "EMAIL_NOTE_SIGNIN", "EMAIL_NOTE_RESET", "EMAIL_NOTE_REGISTER"]
const ACTIONS := [
	"EMAIL_ACTION_LINK", "EMAIL_ACTION_SIGNIN", "EMAIL_ACTION_RESET", "EMAIL_ACTION_REGISTER"
]

## The welcome screen opened this dialog: an offline failure also points to the guest option.
var offer_guest: bool = false

var _mode: Mode = Mode.LINK
var _busy: bool = false
var _safe: MarginContainer
var _scroll: ScrollContainer
var _nick: LineEdit
var _title: Label
var _note: Label
var _email: LineEdit
var _password_row: Control
var _password: LineEdit
var _reveal: Button
var _status: Label
var _forgot: Button
var _cancel: Button
var _action: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	hide()


func _process(_delta: float) -> void:
	if not visible:
		return
	# Landscape keyboards cover half the screen: lift the dialog above it.
	var keyboard: float = ScreenUtil.keyboard_height(get_viewport())
	var margins: Vector4 = ScreenUtil.safe_margins(get_viewport())
	_safe.add_theme_constant_override("margin_bottom", int(maxf(margins.w, keyboard)))
	_note.visible = keyboard <= 0.0
	if keyboard > 0.0 and _scroll != null:
		var focused: Control = get_viewport().gui_get_focus_owner()
		if focused != null and is_ancestor_of(focused):
			_scroll.ensure_control_visible(focused)


## Opens the dialog in `mode`; `email` pre-fills the address (e.g. for the reset).
func open(mode: Mode, email: String = "") -> void:
	_mode = mode
	_busy = false
	_email.text = email
	_password.text = ""
	_password.secret = true
	_nick.text = ""
	_nick.visible = mode == Mode.REGISTER
	_reveal.text = tr("EMAIL_SHOW")
	_title.text = tr(TITLES[mode])
	_note.text = tr(NOTES[mode])
	_password_row.visible = mode != Mode.RESET
	_forgot.visible = mode == Mode.SIGN_IN
	_action.text = tr(ACTIONS[mode])
	_set_busy(false)
	_set_status("", SOFT_COLOR)
	show()
	if not OS.has_feature("mobile"):
		_email.grab_focus.call_deferred()


## Closes the dialog (also the Android back button) and wipes the fields.
func close() -> void:
	if _busy:
		return
	_email.text = ""
	_password.text = ""
	_nick.text = ""
	hide()
	closed.emit()


func mode() -> Mode:
	return _mode


func status_text() -> String:
	return _status.text


## Fills the fields (tests, screenshots).
func set_fields(email: String, password: String, nickname: String = "") -> void:
	_email.text = email
	_password.text = password
	_nick.text = nickname


## Sends the form. Input is checked by Online before any request goes out.
func submit() -> void:
	if _busy:
		return
	_set_busy(true)
	_set_status(tr("EMAIL_CHECKING"), INFO_COLOR)
	var password: String = _password.text
	var result: Dictionary = {}
	match _mode:
		Mode.REGISTER:
			result = await Online.register_email(_email.text, password, _nick.text)
		Mode.LINK:
			result = await Online.link_email(_email.text, password)
		Mode.SIGN_IN:
			result = await Online.sign_in_email(_email.text, password)
		Mode.RESET:
			result = await Online.send_password_reset(_email.text)
	password = ""
	_set_busy(false)
	if not result["ok"]:
		var text: String = EmailRules.message(str(result["error"]))
		if str(result.get("message", "")) != "":
			text = str(result["message"])  # e.g. the nickname rule that failed
		elif offer_guest and str(result["error"]) == "offline":
			text += "\n" + tr("EMAIL_OFFLINE_HINT")
		_set_status(text, ERROR_COLOR)
		return
	_email.text = ""
	_password.text = ""
	_nick.text = ""
	hide()
	succeeded.emit(KINDS[_mode], result)
	closed.emit()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.06, 0.14, 0.9)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_safe = MarginContainer.new()
	_safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_safe)
	# Scrolls when the on-screen keyboard leaves less room than the form needs.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_safe.add_child(_scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	_title = _label("", 32, GOLD)
	box.add_child(_title)
	_note = _label("", 18, SOFT_COLOR)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(700, 0)
	box.add_child(_note)

	_email = _field(tr("EMAIL_FIELD_EMAIL"), false)
	_email.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	_email.text_submitted.connect(_on_email_submitted)
	box.add_child(_email)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_password_row = row
	box.add_child(row)
	_password = _field(tr("EMAIL_FIELD_PASSWORD"), true)
	_password.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
	_password.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_password.text_submitted.connect(func(_t: String) -> void: submit())
	row.add_child(_password)
	_reveal = _button(tr("EMAIL_SHOW"), _on_reveal_pressed, true, 190)
	row.add_child(_reveal)

	_nick = _field(tr("EMAIL_FIELD_NICK"), false)
	_nick.max_length = NicknameRules.MAX_LENGTH + 8
	_nick.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	_nick.text_submitted.connect(func(_t: String) -> void: submit())
	_nick.visible = false
	box.add_child(_nick)

	_status = _label("", 18, SOFT_COLOR)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(700, 48)
	box.add_child(_status)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(buttons)
	_forgot = _button(tr("EMAIL_FORGOT"), _on_forgot_pressed, true, 240)
	_forgot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(_forgot)
	_cancel = _button(tr("COMMON_CANCEL"), close, true, 190)
	buttons.add_child(_cancel)
	_action = _button("", submit, false, 280)
	buttons.add_child(_action)


func _on_email_submitted(_text: String) -> void:
	if _mode == Mode.RESET:
		submit()
	elif not OS.has_feature("mobile"):
		_password.grab_focus()


func _on_reveal_pressed() -> void:
	_password.secret = not _password.secret
	_reveal.text = tr("EMAIL_SHOW") if _password.secret else tr("EMAIL_HIDE")


func _on_forgot_pressed() -> void:
	if _busy:
		return
	open(Mode.RESET, _email.text)


func _set_busy(on: bool) -> void:
	_busy = on
	_email.editable = not on
	_password.editable = not on
	_nick.editable = not on
	for button: Button in [_reveal, _forgot, _cancel, _action]:
		button.disabled = on


func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


func _field(placeholder: String, secret: bool) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.secret = secret
	edit.custom_minimum_size = Vector2(0, FIELD_HEIGHT)
	edit.max_length = EmailRules.PASSWORD_MAX if secret else EmailRules.EMAIL_MAX
	edit.add_theme_font_size_override("font_size", 28)
	edit.caret_blink = true
	if secret:
		edit.context_menu_enabled = false  # no copy of the password out of the field
		edit.selecting_enabled = false
		edit.shortcut_keys_enabled = false
	return edit


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, action: Callable, secondary: bool, width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(width, BUTTON_HEIGHT)
	button.add_theme_font_size_override("font_size", 24)
	if secondary:
		button.theme_type_variation = &"SecondaryButton"
	button.pressed.connect(action)
	return button

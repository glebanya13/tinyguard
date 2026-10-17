class_name AccountPanel
extends Control
## "Профиль" panel of the world map: nickname (rename), account type, sync
## status, email link / sign-in / sign-out (EmailAuthDialog), replay of the
## tutorial, privacy policy and account deletion. Built in code like the
## records panel; reports navigation up by signals. Without Firebase the email
## buttons and the sync rows are hidden and the panel is local-only.

signal rename_requested
signal replay_tutorial_requested
## The account (or the local data) was deleted: the game restarts from boot.
signal account_deleted
## Signed out of the email account: local data is gone, the game restarts from boot.
signal signed_out
## Signed in to another account: the map reloads to show its progress.
signal account_switched

const GOLD := Color(0.98, 0.8, 0.4)
const OK_COLOR := Color(0.62, 0.95, 0.42)
const INFO_COLOR := Color(0.62, 0.86, 1.0)
const ERROR_COLOR := Color(1.0, 0.62, 0.55)
const SOFT_COLOR := Color(0.82, 0.86, 0.95)
const DANGER_COLOR := Color(1.0, 0.45, 0.4)
const BUTTON_HEIGHT := 72.0
const VILLAGER_ICON: Texture2D = preload("res://ui/icons/villager.png")

var _name_label: Label
var _name_badge: Label
var _account_label: Label
var _sync_label: Label
var _sync_row: Control
var _link_row: Control
var _link_button: Button
var _signin_button: Button
var _reauth_button: Button
var _signout_button: Button
var _verify_row: Control
var _verify_label: Label
var _verify_button: Button
var _dialog: EmailAuthDialog
var _delete_button: Button
var _sync_button: Button
var _new_guest_button: Button
var _info_label: Label
var _id_label: Label
var _web_label: Label
var _confirm: Control
var _confirm_title: Label
var _confirm_body: Label
var _confirm_status: Label
var _confirm_yes: Button
var _confirm_no: Button
var _busy: bool = false
## What the confirmation asks: "delete" or "signout".
var _confirm_mode: String = "delete"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	Online.sync_state_changed.connect(_on_sync_state.unbind(1))
	Online.account_changed.connect(refresh)
	hide()


func open() -> void:
	refresh()
	Online.refresh_email_status()  # the cached state shows at once, the lookup updates it
	_info_label.text = ""
	_confirm.hide()
	_dialog.hide()
	show()


## Opens the panel with an email form on top (the map's reminder card uses this).
func open_dialog(mode: EmailAuthDialog.Mode) -> void:
	open()
	_dialog.open(mode)


## Back button: closes the confirmation first, then the panel.
func close() -> void:
	if _busy:
		return
	if _dialog.visible:
		_dialog.close()
	elif _confirm.visible:
		_confirm.hide()
	else:
		hide()


func refresh() -> void:
	var p: Dictionary = PlayerProfile.local()
	var nick: String = str(p["nickname"])
	_name_label.text = tr("ACC_NAME") % (nick if nick != "" else "—")
	if bool(p["nicknameConflict"]):
		_set_label(_name_badge, tr("ACC_NAME_TAKEN"), ERROR_COLOR)
	elif not Online.is_configured():
		_set_label(_name_badge, tr("ACC_NAME_LOCAL"), SOFT_COLOR)
	elif bool(p["nicknameVerified"]):
		_set_label(_name_badge, tr("ACC_NAME_VERIFIED"), OK_COLOR)
	else:
		_set_label(_name_badge, tr("ACC_NAME_PENDING"), INFO_COLOR)
	match Online.account_type():
		"local":
			_account_label.text = tr("ACC_TYPE_LOCAL")
		"guest":
			_account_label.text = tr("ACC_TYPE_GUEST")
		"email":
			_account_label.text = tr("ACC_TYPE_EMAIL")
		_:
			_account_label.text = tr("ACC_TYPE_NONE")
	_on_sync_state()
	var configured: bool = Online.is_configured()
	_sync_row.visible = configured
	_update_email_buttons()
	_update_verify_row()
	_delete_button.text = tr("ACC_DELETE_ACCOUNT") if configured else tr("ACC_DELETE_DATA")
	var uid: String = Online.auth.uid if configured else ""
	_id_label.text = tr("ACC_PLAYER_ID") % uid if uid != "" else ""
	_web_label.text = GameInfo.web_deletion_line()
	_web_label.visible = _web_label.text != ""


## True when the email buttons are shown (tests: hidden without Firebase).
func email_controls_visible() -> bool:
	return _link_row.visible


func _update_email_buttons() -> void:
	var type: String = Online.account_type()
	_link_button.visible = type in ["guest", "none"]
	_signin_button.visible = type in ["guest", "none"]
	_reauth_button.visible = type == "email"
	_signout_button.visible = type == "email"
	_link_row.visible = Online.is_configured()


func _update_verify_row() -> void:
	var status: String = Online.email_status()
	_verify_row.visible = status != ""
	if status == "":
		return
	var mail: String = Online.masked_email()
	var text: String = (
		tr("ACC_EMAIL_VERIFIED") if status == "verified" else tr("ACC_EMAIL_UNVERIFIED")
	)
	_set_label(
		_verify_label,
		text if mail == "" else "%s\n%s" % [mail, text],
		OK_COLOR if status == "verified" else INFO_COLOR
	)
	_verify_button.visible = status == "unverified"


func _on_resend_pressed() -> void:
	if _busy:
		return
	var result: Dictionary = await Online.send_verification()
	if result["ok"]:
		_set_label(_info_label, tr("ACC_EMAIL_SENT"), OK_COLOR)
	elif str(result["error"]) == "cooldown":
		_set_label(_info_label, tr("ACC_EMAIL_COOLDOWN"), INFO_COLOR)
	else:
		_set_label(_info_label, EmailRules.message(str(result["error"])), ERROR_COLOR)


func _on_sync_state() -> void:
	if _sync_label == null:
		return
	var state: String = Online.sync_state()
	var color: Color = OK_COLOR if state in ["synced", "off"] else INFO_COLOR
	if state in ["offline", "pending", "session_lost", "newer", "disabled"]:
		color = ERROR_COLOR if state != "pending" else INFO_COLOR
	_set_label(_sync_label, Online.state_text(state), color)
	_sync_button.visible = Online.is_configured()
	_sync_button.disabled = state == "syncing"
	_new_guest_button.visible = state == "session_lost"


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.06, 0.14, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(800, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	box.add_child(header)
	var icon := TextureRect.new()
	icon.texture = VILLAGER_ICON
	icon.custom_minimum_size = Vector2(56, 56)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(icon)
	var title := _label(tr("ACC_TITLE"), 36, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_button(tr("ACC_DONE"), close, false, 180))

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 12)
	box.add_child(name_row)
	_name_label = _label("", 28)
	name_row.add_child(_name_label)
	_name_badge = _label("", 18)
	_name_badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_badge)
	name_row.add_child(_button(tr("ACC_RENAME"), rename_requested.emit, true, 220))

	_account_label = _label("", 20, SOFT_COLOR)
	_account_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_account_label)

	var sync_row := HBoxContainer.new()
	_sync_row = sync_row
	sync_row.add_theme_constant_override("separation", 12)
	box.add_child(sync_row)
	_sync_label = _label("", 20)
	_sync_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sync_row.add_child(_sync_label)
	_new_guest_button = _button(tr("ACC_NEW_GUEST"), _on_new_guest, true, 200)
	sync_row.add_child(_new_guest_button)
	_sync_button = _button(tr("ACC_SYNC"), _on_sync_pressed, true, 260)
	sync_row.add_child(_sync_button)

	var link_row := HBoxContainer.new()
	_link_row = link_row
	link_row.add_theme_constant_override("separation", 12)
	box.add_child(link_row)
	link_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_link_button = _button(
		tr("ACC_LINK_EMAIL"), _open_dialog.bind(EmailAuthDialog.Mode.LINK), true, 250
	)
	link_row.add_child(_link_button)
	_signin_button = _button(
		tr("ACC_SIGNIN_EMAIL"), _open_dialog.bind(EmailAuthDialog.Mode.SIGN_IN), true, 250
	)
	link_row.add_child(_signin_button)
	_reauth_button = _button(
		tr("ACC_SIGNIN_AGAIN"), _open_dialog.bind(EmailAuthDialog.Mode.SIGN_IN), true, 250
	)
	link_row.add_child(_reauth_button)
	_signout_button = _button(tr("ACC_SIGNOUT"), _ask_sign_out, true, 280)
	link_row.add_child(_signout_button)

	var verify_row := HBoxContainer.new()
	_verify_row = verify_row
	verify_row.add_theme_constant_override("separation", 12)
	box.add_child(verify_row)
	_verify_label = _label("", 20)
	_verify_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_verify_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	verify_row.add_child(_verify_label)
	_verify_button = _button(tr("ACC_EMAIL_RESEND"), _on_resend_pressed, true, 330)
	verify_row.add_child(_verify_button)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(actions)
	actions.add_child(_button(tr("ACC_REPLAY_TUTORIAL"), replay_tutorial_requested.emit, true, 300))
	actions.add_child(_button(tr("ACC_PRIVACY"), _on_privacy_pressed, true, 260))
	var delete := _button(tr("ACC_DELETE_ACCOUNT"), _ask_delete, true, 200)
	_delete_button = delete
	delete.add_theme_color_override("font_color", DANGER_COLOR)
	delete.add_theme_color_override("font_hover_color", DANGER_COLOR)
	actions.add_child(delete)

	_info_label = _label("", 18, SOFT_COLOR)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.custom_minimum_size = Vector2(740, 0)
	box.add_child(_info_label)
	_id_label = _label("", 15, Color(SOFT_COLOR, 0.75))
	box.add_child(_id_label)
	_web_label = _label("", 15, Color(SOFT_COLOR, 0.75))
	_web_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_web_label.custom_minimum_size = Vector2(740, 0)
	box.add_child(_web_label)

	_build_confirm()
	_dialog = EmailAuthDialog.new()
	add_child(_dialog)
	_dialog.succeeded.connect(_on_email_done)


func _build_confirm() -> void:
	_confirm = Control.new()
	_confirm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_confirm)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.06, 0.14, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	_confirm_title = _label(tr("ACC_DELETE_ACCOUNT_Q"), 34, DANGER_COLOR)
	box.add_child(_confirm_title)
	_confirm_body = _label("", 20)
	_confirm_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_body.custom_minimum_size = Vector2(620, 0)
	box.add_child(_confirm_body)
	_confirm_status = _label("", 19, INFO_COLOR)
	_confirm_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_status.custom_minimum_size = Vector2(620, 0)
	box.add_child(_confirm_status)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)
	_confirm_no = _button(tr("COMMON_CANCEL"), close, false, 220)
	buttons.add_child(_confirm_no)
	_confirm_yes = _button(tr("ACC_DELETE_FOREVER"), _on_confirmed, true, 280)
	_confirm_yes.add_theme_color_override("font_color", DANGER_COLOR)
	_confirm_yes.add_theme_color_override("font_hover_color", DANGER_COLOR)
	buttons.add_child(_confirm_yes)
	_confirm.hide()


func _open_dialog(mode: EmailAuthDialog.Mode) -> void:
	if not _busy:
		_dialog.open(mode)


func _on_email_done(kind: String, result: Dictionary) -> void:
	match kind:
		"link", "register":
			refresh()
			_set_label(_info_label, tr("ACC_LINKED"), OK_COLOR)
		"signin":
			refresh()
			if bool(result.get("switched", false)):
				account_switched.emit()
			else:
				_set_label(_info_label, tr("ACC_SIGNIN_OK"), OK_COLOR)
		"reset":
			_set_label(_info_label, tr("ACC_RESET_SENT"), OK_COLOR)


func _ask_sign_out() -> void:
	_confirm_mode = "signout"
	_confirm_title.text = tr("ACC_SIGNOUT_Q")
	_confirm_title.add_theme_color_override("font_color", GOLD)
	_confirm_body.text = tr("ACC_SIGNOUT_BODY")
	_confirm_yes.text = tr("ACC_SIGNOUT_YES")
	_confirm_status.text = ""
	_confirm_yes.disabled = false
	_confirm_no.disabled = false
	_confirm.show()


func _on_confirmed() -> void:
	if _confirm_mode == "signout":
		_on_sign_out_confirmed()
	else:
		_on_delete_confirmed()


func _on_sign_out_confirmed() -> void:
	if _busy:
		return
	_busy = true
	_confirm_yes.disabled = true
	_confirm_no.disabled = true
	_set_label(_confirm_status, tr("ACC_SAVING"), INFO_COLOR)
	var result: Dictionary = await Online.sign_out()
	_busy = false
	if result["ok"]:
		signed_out.emit()
		return
	_confirm_no.disabled = false
	_confirm_yes.disabled = false
	_set_label(_confirm_status, EmailRules.message(str(result["error"])), ERROR_COLOR)


func _ask_delete() -> void:
	_confirm_mode = "delete"
	_confirm_yes.text = tr("ACC_DELETE_FOREVER")
	_confirm_title.add_theme_color_override("font_color", DANGER_COLOR)
	var online: bool = Online.is_configured() and Online.auth.uid != ""
	_confirm_title.text = tr("ACC_DELETE_ACCOUNT_Q") if online else tr("ACC_DELETE_DATA_Q")
	_confirm_body.text = tr("ACC_DELETE_BODY_ONLINE") if online else tr("ACC_DELETE_BODY_LOCAL")
	_confirm_status.text = ""
	_confirm_yes.disabled = false
	_confirm_no.disabled = false
	_confirm.show()


func _on_delete_confirmed() -> void:
	if _busy:
		return
	_busy = true
	_confirm_yes.disabled = true
	_confirm_no.disabled = true
	_set_label(_confirm_status, tr("ACC_DELETING"), INFO_COLOR)
	var result: Dictionary = await Online.delete_account()
	_busy = false
	if result["ok"]:
		account_deleted.emit()
		return
	_confirm_no.disabled = false
	_confirm_yes.disabled = false
	var text := tr("ACC_DELETE_FAILED")
	match str(result["reason"]):
		"offline", "unavailable":
			text = tr("ACC_DELETE_OFFLINE")
		"reauth_required":
			text = tr("ACC_DELETE_REAUTH")
		"session_lost", "no_session":
			text = tr("ACC_DELETE_SESSION_LOST")
	_set_label(_confirm_status, text, ERROR_COLOR)


func _on_sync_pressed() -> void:
	_info_label.text = ""
	var result: Dictionary = await Online.sync_now()
	refresh()
	if not result["ok"] and str(result["error"]) == "offline":
		_set_label(_info_label, tr("ACC_SYNC_OFFLINE"), INFO_COLOR)


func _on_new_guest() -> void:
	var result: Dictionary = await Online.start_new_guest()
	refresh()
	if not result["ok"]:
		_set_label(_info_label, tr("ACC_SERVER_OFFLINE"), ERROR_COLOR)


func _on_privacy_pressed() -> void:
	if GameInfo.PRIVACY_URL != "" and GameSettings.open_url(GameInfo.PRIVACY_URL):
		return
	_set_label(_info_label, tr("ACC_PRIVACY_SUMMARY"), SOFT_COLOR)


func _label(text: String, size: int, color: Color = Color(1, 0.96, 0.87)) -> Label:
	var label := Label.new()
	label.text = text
	UiKit.style_label(label, size, color)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, action: Callable, secondary: bool, width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(width, BUTTON_HEIGHT)
	if secondary:
		button.theme_type_variation = &"SecondaryButton"
	if action.is_valid():
		button.pressed.connect(action)
	return button


func _set_label(label: Label, text: String, color: Color) -> void:
	label.text = text
	label.add_theme_color_override("font_color", color)

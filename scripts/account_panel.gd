class_name AccountPanel
extends Control
## "Профиль" panel of the world map: nickname (rename), account type, sync
## status, replay of the tutorial, privacy policy and account deletion.
## Built in code like the records panel; reports navigation up by signals.

signal rename_requested
signal replay_tutorial_requested
## The account (or the local data) was deleted: the game restarts from boot.
signal account_deleted

const GOLD := Color(0.98, 0.8, 0.4)
const OK_COLOR := Color(0.62, 0.95, 0.42)
const INFO_COLOR := Color(0.62, 0.86, 1.0)
const ERROR_COLOR := Color(1.0, 0.62, 0.55)
const SOFT_COLOR := Color(0.82, 0.86, 0.95)
const DANGER_COLOR := Color(1.0, 0.45, 0.4)
const VILLAGER_ICON: Texture2D = preload("res://ui/icons/villager.png")
const PRIVACY_SUMMARY := (
	"Мы храним только: случайный ID гостя, выбранное имя, прогресс и настройки."
	+ " Без рекламы, аналитики, почты и геолокации. Удаление — кнопкой ниже."
)

var _name_label: Label
var _name_badge: Label
var _account_label: Label
var _sync_label: Label
var _sync_row: Control
var _link_row: Control
var _delete_button: Button
var _sync_button: Button
var _new_guest_button: Button
var _info_label: Label
var _id_label: Label
var _confirm: Control
var _confirm_title: Label
var _confirm_body: Label
var _confirm_status: Label
var _confirm_yes: Button
var _confirm_no: Button
var _busy: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	Online.sync_state_changed.connect(_on_sync_state.unbind(1))
	Online.account_changed.connect(refresh)
	hide()


func open() -> void:
	refresh()
	_info_label.text = ""
	_confirm.hide()
	show()


## Back button: closes the confirmation first, then the panel.
func close() -> void:
	if _busy:
		return
	if _confirm.visible:
		_confirm.hide()
	else:
		hide()


func refresh() -> void:
	var p: Dictionary = PlayerProfile.local()
	var nick: String = str(p["nickname"])
	_name_label.text = "Имя: " + (nick if nick != "" else "—")
	if bool(p["nicknameConflict"]):
		_set_label(_name_badge, "занято, выбери другое", ERROR_COLOR)
	elif not Online.is_configured():
		_set_label(_name_badge, "на этом устройстве", SOFT_COLOR)
	elif bool(p["nicknameVerified"]):
		_set_label(_name_badge, "✓ подтверждено", OK_COLOR)
	else:
		_set_label(_name_badge, "ждёт проверки", INFO_COLOR)
	match Online.account_type():
		"local":
			_account_label.text = "Онлайн выключен: всё хранится только на этом устройстве"
		"guest":
			_account_label.text = "Гостевой аккаунт: прогресс в облаке, вход с этого устройства"
		"email":
			_account_label.text = "Аккаунт с почтой: можно войти на другом устройстве"
		_:
			_account_label.text = "Гостевой аккаунт создастся, когда появится связь"
	_on_sync_state()
	var configured: bool = Online.is_configured()
	_sync_row.visible = configured
	_link_row.visible = configured
	_delete_button.text = "Удалить аккаунт" if configured else "Удалить данные"
	var uid: String = Online.auth.uid if configured else ""
	_id_label.text = "ID игрока (для поддержки): " + uid if uid != "" else ""


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
	var title := _label("Профиль", 36, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_button("Готово", close, false, 180))

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 12)
	box.add_child(name_row)
	_name_label = _label("", 28)
	name_row.add_child(_name_label)
	_name_badge = _label("", 18)
	_name_badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_badge)
	name_row.add_child(_button("Сменить имя", rename_requested.emit, true, 220))

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
	_new_guest_button = _button("Новый гость", _on_new_guest, true, 200)
	sync_row.add_child(_new_guest_button)
	_sync_button = _button("Синхронизировать", _on_sync_pressed, true, 260)
	sync_row.add_child(_sync_button)

	var link_row := HBoxContainer.new()
	_link_row = link_row
	link_row.add_theme_constant_override("separation", 12)
	box.add_child(link_row)
	var link := _button("Привязать аккаунт", Callable(), true, 260)
	link.disabled = true
	link_row.add_child(link)
	var link_note := _label(
		"Скоро: вход на другом устройстве. Пока гость живёт на этом телефоне.", 17, SOFT_COLOR
	)
	link_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	link_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	link_row.add_child(link_note)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(actions)
	actions.add_child(_button("Пройти обучение заново", replay_tutorial_requested.emit, true, 300))
	actions.add_child(_button("Конфиденциальность", _on_privacy_pressed, true, 260))
	var delete := _button("Удалить аккаунт", _ask_delete, true, 200)
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

	_build_confirm()


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
	_confirm_title = _label("Удалить аккаунт?", 34, DANGER_COLOR)
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
	_confirm_no = _button("Отмена", close, false, 220)
	buttons.add_child(_confirm_no)
	_confirm_yes = _button("Удалить навсегда", _on_delete_confirmed, true, 280)
	_confirm_yes.add_theme_color_override("font_color", DANGER_COLOR)
	_confirm_yes.add_theme_color_override("font_hover_color", DANGER_COLOR)
	buttons.add_child(_confirm_yes)
	_confirm.hide()


func _ask_delete() -> void:
	var online: bool = Online.is_configured() and Online.auth.uid != ""
	_confirm_title.text = "Удалить аккаунт?" if online else "Удалить данные?"
	_confirm_body.text = (
		(
			"Удалим имя, прогресс, настройки и рекорды — на сервере и на этом устройстве."
			+ " Вернуть их будет нельзя."
		)
		if online
		else "Удалим имя, прогресс и настройки с этого устройства. Вернуть их будет нельзя."
	)
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
	_set_label(_confirm_status, "Удаляем…", INFO_COLOR)
	var result: Dictionary = await Online.delete_account()
	_busy = false
	if result["ok"]:
		account_deleted.emit()
		return
	_confirm_no.disabled = false
	_confirm_yes.disabled = false
	var text := "Не получилось удалить аккаунт. Попробуйте позже."
	match str(result["reason"]):
		"offline", "unavailable":
			text = "Нужен интернет: данные на сервере можно удалить только онлайн. Попробуйте позже."
		"session_lost", "no_session":
			text = (
				"Вход на этом устройстве потерян, поэтому удалить данные на сервере отсюда нельзя."
				+ " Напишите в поддержку и укажите ID игрока из Профиля."
			)
	_set_label(_confirm_status, text, ERROR_COLOR)


func _on_sync_pressed() -> void:
	_info_label.text = ""
	var result: Dictionary = await Online.sync_now()
	refresh()
	if not result["ok"] and str(result["error"]) == "offline":
		_set_label(_info_label, "Нет связи — синхронизируем, когда появится интернет", INFO_COLOR)


func _on_new_guest() -> void:
	var result: Dictionary = await Online.start_new_guest()
	refresh()
	if not result["ok"]:
		_set_label(_info_label, "Нет связи с сервером — попробуйте позже", ERROR_COLOR)


func _on_privacy_pressed() -> void:
	if GameInfo.PRIVACY_URL != "":
		OS.shell_open(GameInfo.PRIVACY_URL)
	else:
		_set_label(_info_label, PRIVACY_SUMMARY, SOFT_COLOR)


func _label(text: String, size: int, color: Color = Color(1, 0.96, 0.87)) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, action: Callable, secondary: bool, width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(width, 58)
	button.add_theme_font_size_override("font_size", 21)
	if secondary:
		button.theme_type_variation = &"SecondaryButton"
	if action.is_valid():
		button.pressed.connect(action)
	return button


func _set_label(label: Label, text: String, color: Color) -> void:
	label.text = text
	label.add_theme_color_override("font_color", color)

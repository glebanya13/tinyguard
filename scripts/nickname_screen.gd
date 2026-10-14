extends Control
## Nickname screen (first launch, a taken name, or "Сменить имя" on the map).
## Live validation with NicknameRules, then Online.reserve_nickname(): the
## server reserves the name (unique, case-insensitive); offline or without
## Firebase the name is kept on the device and reserved later. A taken name is
## never replaced silently: the player picks another one.

const OK_COLOR := Color(0.62, 0.95, 0.42)
const ERROR_COLOR := Color(1.0, 0.62, 0.55)
const INFO_COLOR := Color(0.62, 0.86, 1.0)
const NEUTRAL_COLOR := Color(0.82, 0.86, 0.95)
const DEFAULT_HINT := "3–16 букв или цифр, можно пробел и _"
## Pause on the "nice to meet you" message before moving on (seconds).
const SUCCESS_PAUSE := 0.9

var _busy: bool = false
## After an offline save the button only continues.
var _saved_offline: bool = false
var _tried: bool = false
## "I already have an account" (only with Firebase, only on the first launch).
var _have_account: Button = null
var _dialog: EmailAuthDialog = null

@onready var _safe: MarginContainer = $Safe
@onready var _art: Control = $Safe/Center/Row/Art
@onready var _subtitle: Label = $Safe/Center/Row/Panel/Content/Subtitle
@onready var _edit: LineEdit = $Safe/Center/Row/Panel/Content/NameEdit
@onready var _message: Label = $Safe/Center/Row/Panel/Content/Feedback/Message
@onready var _counter: Label = $Safe/Center/Row/Panel/Content/Feedback/Counter
@onready var _go: Button = $Safe/Center/Row/Panel/Content/GoButton
@onready var _hint: Label = $Safe/Center/Row/Panel/Content/Hint


func _ready() -> void:
	$Safe/Center/Row/Art/GameTitle.text = GameInfo.TITLE
	LevelCatalog.apply_sound()
	_edit.text_changed.connect(_on_text_changed)
	_edit.text_submitted.connect(_on_submitted)
	_go.pressed.connect(_on_go_pressed)
	var profile: Dictionary = PlayerProfile.local()
	_edit.text = str(profile["nickname"])
	_on_text_changed(_edit.text)
	if bool(profile["nicknameConflict"]):
		_show("Имя «%s» уже занято — выбери другое" % profile["nickname"], ERROR_COLOR)
	_apply_safe_area()
	_build_account_entry()
	if not OS.has_feature("mobile"):
		_edit.grab_focus.call_deferred()


func _process(_delta: float) -> void:
	# Landscape keyboards cover half the screen: keep the field above it.
	var keyboard: float = ScreenUtil.keyboard_height(get_viewport())
	var compact: bool = keyboard > 0.0
	_art.visible = not compact
	_subtitle.visible = not compact
	_hint.visible = not compact
	if _have_account != null:
		_have_account.visible = not compact
	var margins: Vector4 = ScreenUtil.safe_margins(get_viewport())
	_safe.add_theme_constant_override("margin_bottom", int(maxf(margins.w, keyboard)))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _busy:
			return
		if _dialog != null and _dialog.visible:
			_dialog.close()
			return
		if Onboarding.rename_mode:
			_leave_to_map()
		else:
			get_tree().quit()  # first launch: a name is needed to go on


## Current text as the player typed it (tests and screenshots set it here).
func set_text(text: String) -> void:
	_edit.text = text
	_on_text_changed(text)


func submit() -> void:
	_on_go_pressed()


## A returning player on a new device signs in with the email linked in the
## profile instead of inventing a name: the account brings its own nickname.
func _build_account_entry() -> void:
	if not Online.is_configured() or Onboarding.rename_mode:
		return
	_have_account = Button.new()
	_have_account.text = "У меня уже есть аккаунт"
	_have_account.focus_mode = Control.FOCUS_NONE
	_have_account.theme_type_variation = &"SecondaryButton"
	_have_account.custom_minimum_size = Vector2(320, 58)
	_have_account.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_have_account.add_theme_font_size_override("font_size", 21)
	_go.add_sibling(_have_account)
	_dialog = EmailAuthDialog.new()
	add_child(_dialog)
	_have_account.pressed.connect(func() -> void: _dialog.open(EmailAuthDialog.Mode.SIGN_IN))
	_dialog.succeeded.connect(_on_signed_in.unbind(2))


func _on_signed_in() -> void:
	Onboarding.go(get_tree(), Onboarding.route(PlayerProfile.local()))


func _apply_safe_area() -> void:
	var margins: Vector4 = ScreenUtil.safe_margins(get_viewport())
	_safe.add_theme_constant_override("margin_left", int(margins.x) + 16)
	_safe.add_theme_constant_override("margin_top", int(margins.y) + 8)
	_safe.add_theme_constant_override("margin_right", int(margins.z) + 16)


func _on_text_changed(text: String) -> void:
	if _saved_offline:
		_saved_offline = false
		_go.text = "Вперёд!"
	var check: Dictionary = NicknameRules.validate(text)
	_counter.text = "%d/%d" % [NicknameRules.clean(text).length(), NicknameRules.MAX_LENGTH]
	_counter.add_theme_color_override(
		"font_color",
		(
			ERROR_COLOR
			if NicknameRules.clean(text).length() > NicknameRules.MAX_LENGTH
			else NEUTRAL_COLOR
		)
	)
	if text.strip_edges() == "":
		_show(DEFAULT_HINT, NEUTRAL_COLOR)
	elif check["ok"]:
		_show("Отличное имя!", OK_COLOR)
	elif check["error"] == "too_short" and not _tried:
		_show(str(check["message"]), NEUTRAL_COLOR)  # still typing
	else:
		_show(str(check["message"]), ERROR_COLOR)
	_go.disabled = _busy or not check["ok"]


func _on_submitted(_text: String) -> void:
	_on_go_pressed()


func _on_go_pressed() -> void:
	if _busy:
		return
	if _saved_offline:
		_finish()
		return
	_tried = true
	var check: Dictionary = NicknameRules.validate(_edit.text)
	if not check["ok"]:
		_on_text_changed(_edit.text)
		return
	_set_busy(true)
	_show("Проверяем имя…", INFO_COLOR)
	var result: Dictionary = await Online.reserve_nickname(_edit.text)
	_set_busy(false)
	match str(result["reason"]):
		"reserved", "local":
			_edit.text = str(PlayerProfile.local()["nickname"])
			_show("Приятно познакомиться, %s!" % _edit.text, OK_COLOR)
			_set_busy(true)  # no second submit while we move on
			await get_tree().create_timer(SUCCESS_PAUSE).timeout
			_finish()
		"offline":
			_saved_offline = true
			_go.text = "Продолжить"
			_go.disabled = false
			_show(
				"Нет связи. Имя сохранено на устройстве — проверим его, когда появится интернет",
				INFO_COLOR
			)
		"taken", "invalid", "rate_limited":
			var error: String = str(result["error"])
			if error == "" or error == "invalid":
				error = "taken" if result["reason"] == "taken" else str(result["reason"])
			var text: String = NicknameRules.message(error)
			_show(text if text != "" else "Не подходит — попробуй другое имя", ERROR_COLOR)
			_go.disabled = true
			_edit.select_all()
			if not OS.has_feature("mobile"):
				_edit.grab_focus()
		_:
			_on_text_changed(_edit.text)


func _set_busy(on: bool) -> void:
	_busy = on
	_edit.editable = not on
	_go.disabled = on
	if on:
		_go.text = "Проверяем…"
	elif not _saved_offline:
		_go.text = "Вперёд!"


func _show(text: String, color: Color) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", color)


func _finish() -> void:
	if Onboarding.rename_mode:
		_leave_to_map()
		return
	Onboarding.go(get_tree(), Onboarding.route(PlayerProfile.local()))


func _leave_to_map() -> void:
	Onboarding.rename_mode = false
	get_tree().change_scene_to_file(Onboarding.MAP_SCENE)

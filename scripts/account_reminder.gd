class_name AccountReminder
extends PanelContainer
## Soft, dismissible card on the world map. For a guest with some progress: "Create an
## account so you do not lose your progress". For an email account whose saved login
## stopped working: "Sign in again". Never blocks anything; "Later" hides it for a
## few days (Onboarding.dismiss_reminder).

signal action_requested(kind: String)
signal dismissed

enum Kind { CREATE, SIGN_IN }

const GOLD := Color(0.98, 0.8, 0.4)
const SOFT_COLOR := Color(0.82, 0.86, 0.95)
const BUTTON_HEIGHT := 72.0

var _kind: Kind = Kind.CREATE
var _title: Label
var _body: Label
var _action: Button
var _later: Button


func _ready() -> void:
	# Bottom left: the corner of the map that has no buttons or levels.
	custom_minimum_size = Vector2(290, 0)
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_left = 16.0
	offset_right = 306.0
	offset_bottom = -128.0
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_title = _label("", 26, GOLD)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(260, 0)
	box.add_child(_title)
	_body = _label("", 19, SOFT_COLOR)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(260, 0)
	box.add_child(_body)
	_action = _button(false, func() -> void: action_requested.emit(_kind_name()))
	box.add_child(_action)
	_later = _button(true, _on_later_pressed)
	_later.text = tr("REMIND_LATER")
	box.add_child(_later)
	hide()


## Shows the card of `kind`.
func present(kind: Kind) -> void:
	_kind = kind
	if kind == Kind.CREATE:
		_title.text = tr("REMIND_TITLE")
		_body.text = tr("REMIND_BODY")
		_action.text = tr("WELCOME_CREATE")
	else:
		_title.text = tr("REMIND_TITLE")
		_body.text = tr("REMIND_SESSION")
		_action.text = tr("WELCOME_SIGNIN")
	show()


func kind() -> Kind:
	return _kind


func _kind_name() -> String:
	return "create" if _kind == Kind.CREATE else "signin"


func _on_later_pressed() -> void:
	Onboarding.dismiss_reminder()
	hide()
	dismissed.emit()


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	UiKit.style_label(label, size, color)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(secondary: bool, action: Callable) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if secondary:
		button.theme_type_variation = &"SecondaryButton"
	button.pressed.connect(action)
	return button

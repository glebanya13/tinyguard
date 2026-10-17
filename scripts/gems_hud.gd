class_name GemsHud
extends Node
## What the map shows about gems and retention, mounted by the map with one call:
## a gem counter chip in the top row, the "Shop" button and the streak plaque in a column
## under it (tap the plaque for the 7-day rewards and the daily quests), and the toasts of
## what the visit paid (day streak reward, reward for past wins). Pure additions: nothing
## of the map's own layout is touched. Theme variations only (ui/theme.tres).

signal shop_requested

const GEM_ICON: Texture2D = preload("res://ui/icons/gem.png")
const FLAG_ICON: Texture2D = preload("res://ui/icons/flag.png")
const BUTTON_HEIGHT := 84.0
const COLUMN_WIDTH := 230.0

## What the last visit paid (Economy.on_app_open()), for tests.
var visit: Dictionary = {}

var _ui_root: Control = null
var _chip_label: Label = null
var _streak_button: Button = null
var _panel: StreakPanel = null
var _column: VBoxContainer = null


## `top_right` is the map's top row; the chip goes first in it. `pay_visit` false: show
## only (tests and screenshots that must not touch the wallet).
func mount(ui_root: Control, top_right: Container, pay_visit: bool = true) -> void:
	_ui_root = ui_root
	var chip := PanelContainer.new()
	chip.name = "GemsChip"
	chip.theme_type_variation = &"HudPill"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.custom_minimum_size = Vector2(130, 60)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	var icon := TextureRect.new()
	icon.texture = GEM_ICON
	icon.custom_minimum_size = Vector2(38, 38)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	_chip_label = Label.new()
	_chip_label.name = "Label"
	_chip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_chip_label)
	top_right.add_child(chip)
	top_right.move_child(chip, 0)

	_column = VBoxContainer.new()
	_column.name = "GemExtras"
	_column.add_theme_constant_override("separation", 8)
	_column.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_column.offset_left = -COLUMN_WIDTH - 16.0
	_column.offset_right = -16.0
	_column.offset_top = 96.0
	ui_root.add_child(_column)
	ui_root.move_child(_column, 0)  # below the dialogs
	var shop := _button(tr("SHOP_BUTTON"), GEM_ICON)
	shop.name = "ShopButton"
	shop.pressed.connect(func() -> void: shop_requested.emit())
	_column.add_child(shop)
	_streak_button = _button("", FLAG_ICON)
	_streak_button.name = "StreakButton"
	_column.add_child(_streak_button)
	_panel = StreakPanel.new()
	_panel.name = "StreakPanel"
	ui_root.add_child(_panel)
	_streak_button.pressed.connect(_panel.open)

	if pay_visit:
		_pay_visit()
	refresh()


## Updates the counter and the plaque (after a sync, a purchase, a battle).
func refresh() -> void:
	_chip_label.text = str(Economy.balance())
	var live: int = Streak.live_length(Streak.local(), Daily.today_key())
	_streak_button.text = tr("STREAK_BUTTON") % live


func is_panel_open() -> bool:
	return _panel != null and _panel.visible


func close_panel() -> void:
	_panel.close()


func panel() -> StreakPanel:
	return _panel


func _pay_visit() -> void:
	visit = Economy.on_app_open()
	if int(visit["backfill"]) > 0:
		Toast.show_on(_ui_root, tr("BACKFILL_TOAST"), tr("GEMS_PLUS") % int(visit["backfill"]))
	var streak: Dictionary = visit["streak"]
	if int(streak.get("reward", 0)) > 0:
		var state: Dictionary = streak["state"]
		var text: String = tr("STREAK_TOAST") % int(state["len"])
		if int(streak["result"]) == Streak.Result.FORGIVEN:
			text = tr("STREAK_FORGIVEN") + "\n" + text
		if int(streak["day"]) == Streak.WEEK:
			text += "\n" + tr("STREAK_GIFT")
		Toast.show_on(_ui_root, text, tr("GEMS_PLUS") % int(visit["gems"]))


func _button(text: String, icon: Texture2D) -> Button:
	var button := Button.new()
	button.text = text
	button.icon = icon
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(COLUMN_WIDTH, BUTTON_HEIGHT)
	button.add_theme_constant_override("icon_max_width", 40)
	button.add_theme_font_size_override("font_size", 24)
	button.theme_type_variation = &"SecondaryButton"
	return button

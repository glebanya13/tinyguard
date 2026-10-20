class_name GemsHud
extends Node
## What the map shows about gems and retention, mounted by the map with one call: a gem
## counter chip in the top bar, the streak plaque (a tab; tap it for the 7-day rewards and the
## daily quests) and the toasts of what the visit paid (day streak reward, reward for past
## wins). The Shop tab of the bottom bar emits shop_requested. Theme variations only
## (ui/theme.tres).

signal shop_requested

const GEM_ICON: Texture2D = preload("res://ui/icons/gem.png")
const COIN_ICON: Texture2D = preload("res://ui/icons/coin.png")

## What the last visit paid (Economy.on_app_open()), for tests.
var visit: Dictionary = {}

var _ui_root: Control = null
var _chip_label: Label = null
var _coin_chip_label: Label = null
var _streak_button: Button = null
var _panel: StreakPanel = null


## `top_right` is the map's top row; the gem chip goes first in it. The caller makes the Shop
## and Streak tabs of the bottom bar and hands them over: the plaque shows the streak length
## and opens the panel. `pay_visit` false: show only (tests and screenshots that must not
## touch the wallet).
func mount(
	ui_root: Control,
	top_right: Container,
	shop_tab: Button,
	streak_tab: Button,
	pay_visit: bool = true
) -> void:
	_ui_root = ui_root
	var chip := PanelContainer.new()
	chip.name = "GemsChip"
	chip.theme_type_variation = &"HudPill"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.custom_minimum_size = Vector2(0, 56)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	var icon := TextureRect.new()
	icon.texture = GEM_ICON
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	_chip_label = Label.new()
	_chip_label.name = "Label"
	_chip_label.theme_type_variation = &"NumberLabel"
	_chip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_chip_label)
	top_right.add_child(chip)
	top_right.move_child(chip, 0)

	var coin_chip := PanelContainer.new()
	coin_chip.name = "CoinsChip"
	coin_chip.theme_type_variation = &"HudPill"
	coin_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_chip.custom_minimum_size = Vector2(0, 56)
	coin_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var coin_row := HBoxContainer.new()
	coin_row.add_theme_constant_override("separation", 6)
	coin_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_chip.add_child(coin_row)
	var coin_icon := TextureRect.new()
	coin_icon.texture = COIN_ICON
	coin_icon.custom_minimum_size = Vector2(40, 40)
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_row.add_child(coin_icon)
	_coin_chip_label = Label.new()
	_coin_chip_label.name = "Label"
	_coin_chip_label.theme_type_variation = &"NumberLabel"
	_coin_chip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_row.add_child(_coin_chip_label)
	top_right.add_child(coin_chip)
	top_right.move_child(coin_chip, 1)

	shop_tab.pressed.connect(func() -> void: shop_requested.emit())
	_streak_button = streak_tab
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
	if _coin_chip_label != null:
		_coin_chip_label.text = str(Camp.local().get("coins", 0))
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

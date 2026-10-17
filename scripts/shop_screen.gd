class_name ShopScreen
extends Control
## "Лавка": the gem shop. Tabs by category, a grid of item cards (colour swatches, name,
## price or state), a turntable preview of the selected item on its real model, one big
## action button (Buy / Wear / Take off), a confirmation before every purchase and a short
## animation after it. Built in code on the shared theme (ui/theme.tres) with its variations
## only. Everything works offline; the wallet syncs with the profile. Cosmetics only: see
## Shop and Cosmetics.

signal left

const MAP_SCENE := "res://scenes/level_select.tscn"
const BACKDROP: Texture2D = preload("res://ui/app/backdrop.jpg")
const GEM_ICON: Texture2D = preload("res://ui/icons/gem.png")
const GOLD := Color(0.98, 0.8, 0.4)
const SOFT_COLOR := Color(0.82, 0.86, 0.95)
const ERROR_COLOR := Color(1.0, 0.62, 0.55)
const OK_COLOR := Color(0.62, 0.95, 0.42)
const RARITY_COLORS := {
	"common": Color(0.85, 0.88, 0.95),
	"rare": Color(0.45, 0.75, 1.0),
	"epic": Color(0.85, 0.55, 1.0),
}
const BUTTON_HEIGHT := 84.0
const CATEGORY_KEYS := {
	"hero": "SHOP_CAT_HERO", "tower": "SHOP_CAT_TOWER", "flag": "SHOP_CAT_FLAG", "fx": "SHOP_CAT_FX"
}
const RARITY_KEYS := {
	"common": "SHOP_RARITY_COMMON", "rare": "SHOP_RARITY_RARE", "epic": "SHOP_RARITY_EPIC"
}
const CARD_SIZE := Vector2(178, 150)
const COLUMNS := 4
const PREVIEW_SIZE := 300.0

## Go back to the map when "Back" is pressed (tests turn it off).
var auto_leave: bool = true

var _category: String = Cosmetics.HERO
var _selected: String = ""
var _tabs: Dictionary = {}
var _cards: Dictionary = {}
var _grid: GridContainer = null
var _balance: Label = null
var _preview: CosmeticPreview = null
var _name_label: Label = null
var _rarity_label: Label = null
var _state_label: Label = null
var _action: Button = null
var _message: Label = null
var _confirm: Control = null
var _confirm_text: Label = null
var _shown_balance: int = 0


func _ready() -> void:
	theme = load("res://ui/theme.tres")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	Cosmetics.refresh()
	_build()
	_select_category(_category)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _confirm != null and _confirm.visible:
			_confirm.hide()
		else:
			_leave()


## Opens the tab of a category and selects the worn item (or the first one).
func select_category(category: String) -> void:
	_select_category(category)


## Selects an item card (also what a tap does).
func select_item(id: String) -> void:
	if not Cosmetics.is_valid(id):
		return
	if str(Cosmetics.get_item(id)["category"]) != _category:
		_select_category(str(Cosmetics.get_item(id)["category"]), id)
		return
	_selected = id
	_refresh()


## The action button of the selected item was pressed: asks before buying.
func press_action() -> void:
	match Shop.state(_selected):
		Shop.State.AVAILABLE:
			if Shop.can_afford(_selected):
				_ask_buy()
			else:
				_message.add_theme_color_override("font_color", ERROR_COLOR)
				_message.text = tr("SHOP_NO_FUNDS")
		Shop.State.OWNED:
			Shop.equip(_selected)
			_refresh()
		Shop.State.EQUIPPED:
			Shop.unequip(_category)
			_refresh()


## Confirmed purchase (the dialog's "Buy"): buys, animates, or rolls back with a message.
func confirm_buy() -> Dictionary:
	_confirm.hide()
	var before: int = Economy.balance()
	var result: Dictionary = Shop.buy(_selected)
	if result["ok"]:
		_message.text = tr("SHOP_HINT")
		_message.add_theme_color_override("font_color", SOFT_COLOR)
		_refresh()
		_celebrate(_selected, before, int(result["gems"]))
		Toast.show_on(
			self, tr("SHOP_BOUGHT"), tr(str(Cosmetics.get_item(_selected)["key"]))
		)
	else:
		_message.add_theme_color_override("font_color", ERROR_COLOR)
		_message.text = tr("SHOP_NO_FUNDS") if result["reason"] == "funds" else tr("SHOP_UNKNOWN")
		_refresh()
	return result


func selected_id() -> String:
	return _selected


func _build() -> void:
	var bg := TextureRect.new()
	bg.texture = BACKDROP
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.06, 0.14, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var safe := MarginContainer.new()
	safe.name = "Safe"
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margins: Vector4 = ScreenUtil.safe_margins(get_viewport())
	safe.add_theme_constant_override("margin_left", int(margins.x) + 16)
	safe.add_theme_constant_override("margin_top", int(margins.y) + 12)
	safe.add_theme_constant_override("margin_right", int(margins.z) + 16)
	safe.add_theme_constant_override("margin_bottom", int(margins.w) + 12)
	add_child(safe)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	safe.add_child(column)
	column.add_child(_build_header())
	column.add_child(_build_tabs())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	body.add_child(_build_grid())
	body.add_child(_build_side())
	_message = _label(tr("SHOP_HINT"), 18, SOFT_COLOR)
	_message.name = "Message"
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(0, 28)
	column.add_child(_message)
	_confirm = _build_confirm()
	add_child(_confirm)


func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var back := _button(tr("SHOP_BACK"), _leave, true, 190)
	back.name = "BackButton"
	row.add_child(back)
	var title := _label(tr("SHOP_TITLE"), 40, GOLD)
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(title)
	var pill := PanelContainer.new()
	pill.theme_type_variation = &"HudPill"
	pill.name = "BalancePill"
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	pill.add_child(inner)
	var icon := TextureRect.new()
	icon.texture = GEM_ICON
	icon.custom_minimum_size = Vector2(44, 44)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	inner.add_child(icon)
	_balance = _label("0", 34, Color.WHITE)
	_balance.name = "Balance"
	_balance.custom_minimum_size = Vector2(90, 0)
	inner.add_child(_balance)
	row.add_child(pill)
	return row


func _build_tabs() -> Control:
	var row := HBoxContainer.new()
	row.name = "Tabs"
	row.add_theme_constant_override("separation", 10)
	for category: String in Cosmetics.categories():
		var tab := _button(
			tr(str(CATEGORY_KEYS[category])), _select_category.bind(category), true, 0
		)
		tab.name = "Tab_" + category
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(tab)
		_tabs[category] = tab
	return row


func _build_grid() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid = GridContainer.new()
	_grid.name = "Grid"
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)
	return scroll


func _build_side() -> Control:
	var panel := PanelContainer.new()
	panel.name = "Side"
	panel.custom_minimum_size = Vector2(PREVIEW_SIZE + 40.0, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	_preview = CosmeticPreview.new()
	_preview.name = "Preview"
	_preview.custom_minimum_size = Vector2(PREVIEW_SIZE, 190)
	box.add_child(_preview)
	_name_label = _label("", 26, Color.WHITE)
	_name_label.name = "ItemName"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_name_label)
	_rarity_label = _label("", 20, SOFT_COLOR)
	_rarity_label.name = "Rarity"
	_rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_rarity_label)
	_state_label = _label("", 20, SOFT_COLOR)
	_state_label.name = "State"
	_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_state_label.hide()  # the state is on the card and on the button
	box.add_child(_state_label)
	_action = _button("", press_action, false, 0)
	_action.name = "ActionButton"
	_action.size_flags_vertical = Control.SIZE_SHRINK_END
	box.add_child(_action)
	return panel


func _build_confirm() -> Control:
	var overlay := Control.new()
	overlay.name = "Confirm"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.hide()
	var shade := ColorRect.new()
	shade.color = Color(0.04, 0.06, 0.14, 0.7)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	_confirm_text = _label("", 30, Color.WHITE)
	_confirm_text.name = "ConfirmText"
	_confirm_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_confirm_text)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	var yes := _button(tr("SHOP_CONFIRM_YES"), confirm_buy, false, 0)
	yes.name = "ConfirmYes"
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(yes)
	var no := _button(tr("SHOP_CONFIRM_NO"), func() -> void: _confirm.hide(), true, 0)
	no.name = "ConfirmNo"
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(no)
	return overlay


func _select_category(category: String, pick: String = "") -> void:
	_category = category
	_message.text = tr("SHOP_HINT")
	_message.add_theme_color_override("font_color", SOFT_COLOR)
	for key: String in _tabs:
		(_tabs[key] as Button).theme_type_variation = &"" if key == category else &"SecondaryButton"
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_cards.clear()
	for item in Cosmetics.in_category(category):
		var card: Control = _make_card(item)
		_grid.add_child(card)
		_cards[str(item["id"])] = card
	var worn: String = Cosmetics.equipped(category)
	var first: Array[Dictionary] = Cosmetics.in_category(category)
	_selected = pick if pick != "" else (worn if worn != "" else str(first[0]["id"]))
	_shown_balance = Economy.balance()
	_refresh()


func _make_card(item: Dictionary) -> Control:
	var id: String = str(item["id"])
	var holder := Control.new()
	holder.name = "Card_" + id
	holder.custom_minimum_size = CARD_SIZE
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	var swatches := HBoxContainer.new()
	swatches.alignment = BoxContainer.ALIGNMENT_CENTER
	swatches.add_theme_constant_override("separation", 6)
	swatches.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for colour in Cosmetics.swatches(item):
		var chip := ColorRect.new()
		chip.color = colour
		chip.custom_minimum_size = Vector2(38, 38)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		swatches.add_child(chip)
	box.add_child(swatches)
	var name_label := _label(tr(str(item["key"])), 20, RARITY_COLORS[str(item["rarity"])])
	name_label.name = "Name"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)
	var status := HBoxContainer.new()
	status.name = "Status"
	status.alignment = BoxContainer.ALIGNMENT_CENTER
	status.add_theme_constant_override("separation", 6)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(status)
	var tap := Button.new()
	tap.name = "Tap"
	tap.flat = true
	tap.focus_mode = Control.FOCUS_NONE
	tap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tap.pressed.connect(select_item.bind(id))
	holder.add_child(tap)
	return holder


func _refresh() -> void:
	_balance.text = str(Economy.balance())
	_shown_balance = Economy.balance()
	for id: String in _cards:
		_update_card(id)
	var item: Dictionary = Cosmetics.get_item(_selected)
	if item.is_empty():
		return
	_preview.show_item(item)
	_name_label.text = tr(str(item["key"]))
	_rarity_label.text = tr(str(RARITY_KEYS[str(item["rarity"])]))
	_rarity_label.add_theme_color_override("font_color", RARITY_COLORS[str(item["rarity"])])
	var price: int = int(item["price"])
	match Shop.state(_selected):
		Shop.State.AVAILABLE:
			var missing: int = price - Economy.balance()
			_state_label.text = ""
			_action.icon = GEM_ICON
			if missing > 0:
				_action.text = tr("SHOP_NEED") % missing
				_action.disabled = true
			else:
				_action.text = tr("SHOP_BUY") % price
				_action.disabled = false
			_action.theme_type_variation = &""
		Shop.State.OWNED:
			_state_label.text = tr("SHOP_OWNED")
			_action.icon = null
			_action.text = tr("SHOP_EQUIP")
			_action.disabled = false
			_action.theme_type_variation = &"GreenButton"
		Shop.State.EQUIPPED:
			_state_label.text = tr("SHOP_EQUIPPED")
			_action.icon = null
			_action.text = tr("SHOP_TAKE_OFF")
			_action.disabled = false
			_action.theme_type_variation = &"SecondaryButton"


func _update_card(id: String) -> void:
	var card: Control = _cards[id]
	var item: Dictionary = Cosmetics.get_item(id)
	var status := card.find_child("Status", true, false) as HBoxContainer
	for child in status.get_children():
		status.remove_child(child)
		child.queue_free()
	match Shop.state(id):
		Shop.State.AVAILABLE:
			var icon := TextureRect.new()
			icon.texture = GEM_ICON
			icon.custom_minimum_size = Vector2(30, 30)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			status.add_child(icon)
			var affordable: bool = Economy.balance() >= int(item["price"])
			status.add_child(
				_label(str(int(item["price"])), 24, Color.WHITE if affordable else ERROR_COLOR, true)
			)
		Shop.State.OWNED:
			status.add_child(_label(tr("SHOP_OWNED"), 20, SOFT_COLOR, true))
		Shop.State.EQUIPPED:
			status.add_child(_label(tr("SHOP_EQUIPPED"), 20, OK_COLOR, true))
	var panel: PanelContainer = card.get_node("Panel") as PanelContainer
	panel.self_modulate = Color(1.35, 1.2, 0.8) if id == _selected else Color.WHITE


func _ask_buy() -> void:
	var item: Dictionary = Cosmetics.get_item(_selected)
	if item.is_empty():
		return
	_confirm_text.text = tr("SHOP_CONFIRM") % [tr(str(item["key"])), int(item["price"])]
	_confirm.show()


## A bought item: its card pops, gems fly off the balance, the balance counts down.
func _celebrate(id: String, from_gems: int, to_gems: int) -> void:
	var card: Control = _cards.get(id)
	if card != null:
		card.pivot_offset = card.size / 2.0
		var pop: Tween = create_tween()
		pop.tween_property(card, "scale", Vector2(1.14, 1.14), 0.12)
		pop.tween_property(card, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)
		for i in 8:
			var gem := TextureRect.new()
			gem.texture = GEM_ICON
			gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			gem.custom_minimum_size = Vector2(28, 28)
			gem.size = Vector2(28, 28)
			gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(gem)
			gem.global_position = card.global_position + card.size / 2.0
			var angle: float = TAU * i / 8.0
			var target: Vector2 = gem.position + Vector2(cos(angle), sin(angle) - 0.8) * 90.0
			var fly: Tween = gem.create_tween().set_parallel()
			fly.tween_property(gem, "position", target, 0.55).set_trans(Tween.TRANS_QUAD)
			fly.tween_property(gem, "modulate:a", 0.0, 0.55)
			fly.chain().tween_callback(gem.queue_free)
	var count: Tween = create_tween()
	count.tween_method(
		func(value: float) -> void: _balance.text = str(roundi(value)), float(from_gems), float(to_gems), 0.5
	)


func _leave() -> void:
	left.emit()
	if auto_leave:
		get_tree().change_scene_to_file(MAP_SCENE)


func _label(text: String, size: int, color: Color, mouse_ignore: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if mouse_ignore:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, action: Callable, secondary: bool, width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(width, BUTTON_HEIGHT)
	button.add_theme_font_size_override("font_size", 26)
	button.add_theme_constant_override("icon_max_width", 36)
	if secondary:
		button.theme_type_variation = &"SecondaryButton"
	button.pressed.connect(action)
	return button

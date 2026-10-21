class_name PerksPanel
extends Control
## The perks / talents dialog panel: upgrades hero, castle, and towers with stars.
## Explains star sources and provides perk upgrade cards.

signal closed

const GOLD := Color(0.98, 0.8, 0.4)
const SOFT_COLOR := Color(0.82, 0.86, 0.95)
const STAR_ICON: Texture2D = preload("res://ui/icons/star.png")
const CHEST_ICON: Texture2D = preload("res://ui/icons/chest.png")

var _frame: DialogFrame = null
var _free_label: Label = null
var _cards: GridContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()


func open() -> void:
	_build()
	show()


func close() -> void:
	if visible:
		hide()
		if _frame != null:
			_frame.hide()
		closed.emit()


func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_frame = DialogFrame.attach(self, 1200.0, 0.6)
	var box := _frame.body
	box.add_theme_constant_override("separation", 8)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	box.add_child(header)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(48, 48)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = CHEST_ICON
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(icon)

	var title := Label.new()
	title.text = tr("MAP_TREASURY_TITLE")
	title.theme_type_variation = &"TitleLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var free_pill := PanelContainer.new()
	free_pill.theme_type_variation = &"HudChip"
	free_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pill_row := HBoxContainer.new()
	pill_row.add_theme_constant_override("separation", 8)
	var star_icon := TextureRect.new()
	star_icon.custom_minimum_size = Vector2(32, 32)
	star_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	star_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	star_icon.texture = STAR_ICON
	pill_row.add_child(star_icon)
	_free_label = Label.new()
	_free_label.theme_type_variation = &"NumberLabel"
	_free_label.text = tr("MAP_FREE_STARS") % Perks.free_stars()
	pill_row.add_child(_free_label)
	free_pill.add_child(pill_row)
	header.add_child(free_pill)

	var hint := Label.new()
	hint.text = tr("MAP_TREASURY_HINT")
	hint.theme_type_variation = &"CaptionLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	var source_hint := Label.new()
	source_hint.text = tr("PERKS_STARS_SOURCE_HINT")
	source_hint.theme_type_variation = &"CaptionLabel"
	source_hint.add_theme_color_override("font_color", GOLD)
	source_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(source_hint)

	_cards = GridContainer.new()
	_cards.name = "Cards"
	_cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("h_separation", 12)
	_cards.add_theme_constant_override("v_separation", 12)
	_cards.columns = 4
	box.add_child(_cards)

	_fill_cards()

	var footer := _frame.footer
	footer.add_theme_constant_override("separation", 12)

	var reset_btn := Button.new()
	reset_btn.text = tr("MAP_REFUND")
	reset_btn.custom_minimum_size = Vector2(180, 54)
	reset_btn.pressed.connect(_on_reset_pressed)
	footer.add_child(reset_btn)

	var close_btn := Button.new()
	close_btn.text = tr("MAP_DONE")
	close_btn.theme_type_variation = &"GreenButton"
	close_btn.custom_minimum_size = Vector2(180, 54)
	close_btn.pressed.connect(close)
	footer.add_child(close_btn)


func _fill_cards() -> void:
	if _cards == null:
		return
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	if _free_label != null:
		_free_label.text = tr("MAP_FREE_STARS") % Perks.free_stars()
	for perk: PerkData in Perks.all():
		_cards.add_child(_perk_card(perk))


func _perk_card(perk: PerkData) -> PanelContainer:
	var level: int = Perks.level(perk.id)
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	var icon := TextureRect.new()
	icon.texture = perk.icon
	icon.custom_minimum_size = Vector2(60, 60)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(icon)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 0)
	head.add_child(texts)
	var title := Label.new()
	title.text = tr(perk.display_name)
	title.theme_type_variation = &"HeadingLabel"
	texts.add_child(title)
	var level_label := Label.new()
	level_label.text = tr("MAP_PERK_LEVEL") % [level, perk.max_level()]
	level_label.theme_type_variation = &"CaptionLabel"
	texts.add_child(level_label)
	var effect := Label.new()
	var now: String = perk.format_value(level)
	effect.text = tr(perk.description) % now
	if level < perk.max_level():
		effect.text += " → " + perk.format_value(level + 1)
	effect.add_theme_font_size_override("font_size", 17)
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(effect)
	var buy := Button.new()
	buy.focus_mode = Control.FOCUS_NONE
	buy.custom_minimum_size = Vector2(0, 84)
	buy.theme_type_variation = &"GreenButton"
	var cost: int = Perks.next_cost(perk)
	if cost < 0:
		buy.text = tr("MAP_PERK_MAX")
		buy.disabled = true
	else:
		buy.text = tr("MAP_PERK_BUY") % cost
		buy.icon = STAR_ICON
		buy.add_theme_constant_override("icon_max_width", 30)
		buy.disabled = not Perks.can_buy(perk)
		buy.pressed.connect(_on_buy_pressed.bind(perk))
	box.add_child(buy)
	return card


func _on_buy_pressed(perk: PerkData) -> void:
	if Perks.buy(perk):
		_fill_cards()


func _on_reset_pressed() -> void:
	Perks.reset()
	_fill_cards()

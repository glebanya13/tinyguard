class_name EncyclopediaPanel
extends Control
## Encyclopedia dialog (guide to towers, bestiary of enemies, and village economy):
## stats, ranges, roles, resistances, and trade rules. Built on DialogFrame.

signal closed
signal tab_changed(tab_index: int)

const GOLD := Color(0.98, 0.8, 0.4)
const SOFT_COLOR := Color(0.82, 0.86, 0.95)
const DIM_TEXT := Color(0.65, 0.72, 0.85)
const HIGHLIGHT_COLOR := Color(0.4, 0.85, 0.95)

const TAB_KEYS: Array[String] = [
	"ENCYCLOPEDIA_TAB_TOWERS",
	"ENCYCLOPEDIA_TAB_BESTIARY",
	"ENCYCLOPEDIA_TAB_VILLAGE",
]

const TOWER_RESOURCES: Array[String] = [
	"res://resources/towers/archer.tres",
	"res://resources/towers/cannon.tres",
	"res://resources/towers/frost.tres",
	"res://resources/towers/lightning.tres",
]

const ENEMY_RESOURCES: Array[Dictionary] = [
	{
		"path": "res://resources/enemies/slime_fast.tres",
		"icon": "res://ui/icons/slime_fast.png",
		"feat": "ENCYCLOPEDIA_FEAT_SCOUT"
	},
	{
		"path": "res://resources/enemies/slime.tres",
		"icon": "res://ui/icons/slime.png",
		"feat": "ENCYCLOPEDIA_FEAT_FIGHTER"
	},
	{
		"path": "res://resources/enemies/slime_bat.tres",
		"icon": "res://ui/icons/slime_bat.png",
		"feat": "ENCYCLOPEDIA_FEAT_FLYER"
	},
	{
		"path": "res://resources/enemies/slime_shield.tres",
		"icon": "res://ui/icons/slime_shield.png",
		"feat": "ENCYCLOPEDIA_FEAT_SHIELD"
	},
	{
		"path": "res://resources/enemies/slime_healer.tres",
		"icon": "res://ui/icons/slime_healer.png",
		"feat": "ENCYCLOPEDIA_FEAT_HEALER"
	},
	{
		"path": "res://resources/enemies/slime_tank.tres",
		"icon": "res://ui/icons/slime.png",
		"feat": "ENCYCLOPEDIA_FEAT_TANK"
	},
	{
		"path": "res://resources/enemies/stone_golem.tres",
		"icon": "res://ui/icons/stone_golem.png",
		"feat": "ENCYCLOPEDIA_FEAT_GOLEM"
	},
	{
		"path": "res://resources/enemies/slime_king.tres",
		"icon": "res://ui/icons/boss.png",
		"feat": "ENCYCLOPEDIA_FEAT_BOSS"
	},
]

var _tab: int = 0
var _box: VBoxContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	hide()


func open() -> void:
	_build()
	show()


func close() -> void:
	if visible:
		hide()
		closed.emit()


func set_tab(index: int) -> void:
	if index == _tab:
		return
	_tab = clampi(index, 0, TAB_KEYS.size() - 1)
	_build()
	tab_changed.emit(_tab)


func current_tab() -> int:
	return _tab


func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var frame := DialogFrame.attach(self, 860.0, 0.7)
	frame.min_height = 540.0
	_box = frame.body
	_box.add_theme_constant_override("separation", 10)

	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 12)
	_box.add_child(header)

	var title := UiKit.ribbon(tr("ENCYCLOPEDIA_TITLE"))
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	header.add_child(title)
	header.add_child(_button(tr("MAP_CLOSE"), close, false, 140))

	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.add_theme_constant_override("separation", 8)
	_box.add_child(tabs)

	var tab_group := ButtonGroup.new()
	for i in TAB_KEYS.size():
		var tab := _button(tr(TAB_KEYS[i]), set_tab.bind(i), true, 0)
		tab.name = "Tab_%d" % i
		tab.custom_minimum_size.y = 52.0
		tab.theme_type_variation = &"ToggleButton"
		tab.toggle_mode = true
		tab.button_group = tab_group
		tab.button_pressed = i == _tab
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(tab)

	if _tab == 0:
		_build_towers()
	elif _tab == 1:
		_build_bestiary()
	else:
		_build_village()


func _build_towers() -> void:
	for res_path in TOWER_RESOURCES:
		var data: TowerData = load(res_path) as TowerData
		if data == null:
			continue
		var card := _card_box("Tower_" + data.resource_path.get_file().get_basename())
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		card.add_child(row)

		if data.icon:
			var icon_rect := TextureRect.new()
			icon_rect.texture = data.icon
			icon_rect.custom_minimum_size = Vector2(56, 56)
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(icon_rect)

		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 4)
		row.add_child(col)

		var name_lbl := _label(tr(data.display_name), 22, GOLD)
		name_lbl.name = "Name"
		col.add_child(name_lbl)

		var role_lbl := _label(tr(data.role), 16, SOFT_COLOR)
		role_lbl.name = "Role"
		role_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(role_lbl)

		var stats_str: String = (
			tr("ENCYCLOPEDIA_TOWER_STATS")
			% [
				roundi(data.damage_levels[0]),
				data.range_levels[0],
				data.interval_levels[0],
				data.cost_gold,
				data.cost_wood
			]
		)
		var stats_lbl := _label(stats_str, 16, HIGHLIGHT_COLOR)
		stats_lbl.name = "Stats"
		col.add_child(stats_lbl)

		var feat_key := ""
		if data.damage_kind == &"arrow":
			feat_key = "ENCYCLOPEDIA_ARCHER_FEAT"
		elif not data.hits_air:
			feat_key = "ENCYCLOPEDIA_CANNON_FEAT"
		elif data.slow_levels[0] < 1.0:
			feat_key = "ENCYCLOPEDIA_FROST_FEAT"
		elif data.chain_levels[0] > 0:
			feat_key = "ENCYCLOPEDIA_LIGHTNING_FEAT"

		if feat_key != "":
			var feat_lbl := _label(tr(feat_key), 15, DIM_TEXT)
			feat_lbl.name = "Feature"
			feat_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			col.add_child(feat_lbl)


func _build_bestiary() -> void:
	for entry in ENEMY_RESOURCES:
		var path: String = entry["path"]
		var data: EnemyData = load(path) as EnemyData
		if data == null:
			continue
		var card := _card_box("Enemy_" + path.get_file().get_basename())
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		card.add_child(row)

		var icon_res: Texture2D = load(entry["icon"]) as Texture2D
		if icon_res:
			var icon_rect := TextureRect.new()
			icon_rect.name = "Icon"
			icon_rect.texture = icon_res
			icon_rect.custom_minimum_size = Vector2(56, 56)
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(icon_rect)

		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 4)
		row.add_child(col)

		var name_lbl := _label(tr(data.display_name), 22, GOLD)
		name_lbl.name = "Name"
		col.add_child(name_lbl)

		var stats_str: String = (
			tr("ENCYCLOPEDIA_ENEMY_STATS") % [roundi(data.health), data.speed, data.reward]
		)
		var stats_lbl := _label(stats_str, 16, HIGHLIGHT_COLOR)
		stats_lbl.name = "Stats"
		col.add_child(stats_lbl)

		var feat_str: String = tr(entry["feat"])
		var feat_lbl := _label(feat_str, 15, SOFT_COLOR)
		feat_lbl.name = "Feature"
		feat_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(feat_lbl)


func _build_village() -> void:
	var trade: VillagerTrade = load("res://resources/villager_trade.tres") as VillagerTrade

	# 1. Lumberjacks
	var card_lumber := _card_box("Village_Lumberjacks")
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 14)
	card_lumber.add_child(row1)

	var icon_axe: Texture2D = load("res://ui/icons/axe.png") as Texture2D
	if icon_axe:
		var axe_rect := TextureRect.new()
		axe_rect.texture = icon_axe
		axe_rect.custom_minimum_size = Vector2(56, 56)
		axe_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		axe_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row1.add_child(axe_rect)

	var col1 := VBoxContainer.new()
	col1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col1.add_theme_constant_override("separation", 4)
	row1.add_child(col1)

	var name1 := _label(tr("ENCYCLOPEDIA_VILLAGE_LUMBER_TITLE"), 22, GOLD)
	name1.name = "Name"
	col1.add_child(name1)

	if trade:
		var stats1_str: String = (
			tr("ENCYCLOPEDIA_VILLAGE_LUMBER_STATS")
			% [trade.hire_gold, trade.hire_wood_per_minute, trade.hire_max]
		)
		var stats1 := _label(stats1_str, 16, HIGHLIGHT_COLOR)
		stats1.name = "Stats"
		col1.add_child(stats1)

	var desc1 := _label(tr("ENCYCLOPEDIA_VILLAGE_LUMBER_DESC"), 15, SOFT_COLOR)
	desc1.name = "Desc"
	desc1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col1.add_child(desc1)

	# 2. Selling wood
	var card_sell := _card_box("Village_Selling")
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 14)
	card_sell.add_child(row2)

	var icon_coin: Texture2D = load("res://ui/icons/coin.png") as Texture2D
	if icon_coin:
		var coin_rect := TextureRect.new()
		coin_rect.texture = icon_coin
		coin_rect.custom_minimum_size = Vector2(56, 56)
		coin_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		coin_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row2.add_child(coin_rect)

	var col2 := VBoxContainer.new()
	col2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col2.add_theme_constant_override("separation", 4)
	row2.add_child(col2)

	var name2 := _label(tr("ENCYCLOPEDIA_VILLAGE_SELL_TITLE"), 22, GOLD)
	name2.name = "Name"
	col2.add_child(name2)

	if trade:
		var stats2_str: String = (
			tr("ENCYCLOPEDIA_VILLAGE_SELL_STATS")
			% [
				trade.wood_per_lot,
				roundi(trade.start_gold),
				roundi((1.0 - trade.price_decay) * 100.0),
				trade.min_gold
			]
		)
		var stats2 := _label(stats2_str, 16, HIGHLIGHT_COLOR)
		stats2.name = "Stats"
		col2.add_child(stats2)

	var desc2 := _label(tr("ENCYCLOPEDIA_VILLAGE_SELL_DESC"), 15, SOFT_COLOR)
	desc2.name = "Desc"
	desc2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col2.add_child(desc2)

	# 3. Buying wood
	var card_buy := _card_box("Village_Buying")
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 14)
	card_buy.add_child(row3)

	var icon_wood: Texture2D = load("res://ui/icons/wood.png") as Texture2D
	if icon_wood:
		var wood_rect := TextureRect.new()
		wood_rect.texture = icon_wood
		wood_rect.custom_minimum_size = Vector2(56, 56)
		wood_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		wood_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row3.add_child(wood_rect)

	var col3 := VBoxContainer.new()
	col3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col3.add_theme_constant_override("separation", 4)
	row3.add_child(col3)

	var name3 := _label(tr("ENCYCLOPEDIA_VILLAGE_BUY_TITLE"), 22, GOLD)
	name3.name = "Name"
	col3.add_child(name3)

	if trade:
		var stats3_str: String = (
			tr("ENCYCLOPEDIA_VILLAGE_BUY_STATS")
			% [
				trade.wood_per_lot,
				roundi(trade.buy_start_gold),
				roundi((trade.buy_growth - 1.0) * 100.0),
				trade.buy_max_lots
			]
		)
		var stats3 := _label(stats3_str, 16, HIGHLIGHT_COLOR)
		stats3.name = "Stats"
		col3.add_child(stats3)

	var desc3 := _label(tr("ENCYCLOPEDIA_VILLAGE_BUY_DESC"), 15, SOFT_COLOR)
	desc3.name = "Desc"
	desc3.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col3.add_child(desc3)

	# 4. Mercenaries
	var card_merc := _card_box("Village_Mercenaries")
	var row4 := HBoxContainer.new()
	row4.add_theme_constant_override("separation", 14)
	card_merc.add_child(row4)

	var icon_sword: Texture2D = load("res://ui/icons/sword.png") as Texture2D
	if icon_sword:
		var sword_rect := TextureRect.new()
		sword_rect.name = "Icon"
		sword_rect.texture = icon_sword
		sword_rect.custom_minimum_size = Vector2(56, 56)
		sword_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sword_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row4.add_child(sword_rect)

	var col4 := VBoxContainer.new()
	col4.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col4.add_theme_constant_override("separation", 4)
	row4.add_child(col4)

	var name4 := _label(tr("ENCYCLOPEDIA_VILLAGE_MERC_TITLE"), 22, GOLD)
	name4.name = "Name"
	col4.add_child(name4)

	var merc_cfg: MercenaryConfig = Mercenary.CONFIG
	var stats4_str: String = (
		tr("ENCYCLOPEDIA_VILLAGE_MERC_STATS")
		% [
			merc_cfg.hire_gold,
			merc_cfg.hire_gold_step,
			merc_cfg.max_alive,
			roundi(merc_cfg.max_health),
			roundi(merc_cfg.attack_damage)
		]
	)
	var stats4 := _label(stats4_str, 16, HIGHLIGHT_COLOR)
	stats4.name = "Stats"
	col4.add_child(stats4)

	var desc4 := _label(tr("ENCYCLOPEDIA_VILLAGE_MERC_DESC"), 15, SOFT_COLOR)
	desc4.name = "Desc"
	desc4.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col4.add_child(desc4)


func _card_box(node_name: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_child(panel)

	var inner := VBoxContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_PASS
	inner.add_theme_constant_override("separation", 6)
	panel.add_child(inner)
	return inner


func _button(text: String, action: Callable, secondary: bool, min_w: int = 0) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	if min_w > 0:
		btn.custom_minimum_size = Vector2(min_w, 48)
	if secondary:
		btn.theme_type_variation = &"SecondaryButton"
	btn.pressed.connect(action)
	return btn


func _label(text: String, size: int, color: Color = Color(1, 0.96, 0.87)) -> Label:
	var label := Label.new()
	label.text = text
	UiKit.style_label(label, size, color)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

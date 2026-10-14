extends Node3D
## Start screen: a 3D island map with one button per level (locked levels
## show a lock, earned stars sit under each button), the star counter, the
## treasury where stars buy permanent perks, and the selected level's card
## with "Play" and, once the level is won, the endless siege.

const GAME_SCENE := "res://scenes/main.tscn"
const LOCK_ICON: Texture2D = preload("res://ui/icons/lock.png")
const STAR_ICON: Texture2D = preload("res://ui/icons/star.png")
const CASTLE_ICON: Texture2D = preload("res://ui/icons/flag.png")
const SOUND_ON_ICON: Texture2D = preload("res://ui/icons/sound_on.png")
const SOUND_OFF_ICON: Texture2D = preload("res://ui/icons/sound_off.png")
const GOLD := Color(0.98, 0.8, 0.4)
const DIM_STAR := Color(0.22, 0.24, 0.34, 0.9)

var _site_buttons: Array[Button] = []
var _sites: Array[Node3D] = []
## Level id of each site button (same order as _site_buttons).
var _site_ids: Array[int] = []
var _selected: int = 0
var _records: Control = null
var _records_list: VBoxContainer = null
var _records_title: Label = null
var _records_status: Label = null

@onready var _map: Node3D = $Map
@onready var _camera: Camera3D = $Camera
@onready var _site_layer: Control = $UI/Root/Sites
@onready var _stars_label: Label = $UI/Root/TopRight/StarsPill/Row/Label
@onready var _treasury_button: Button = $UI/Root/TopRight/TreasuryButton
@onready var _treasury_badge: Label = $UI/Root/TopRight/TreasuryButton/Badge
@onready var _sound_button: Button = $UI/Root/TopRight/SoundButton
@onready var _name_label: Label = $UI/Root/Info/Content/Name
@onready var _subtitle_label: Label = $UI/Root/Info/Content/Subtitle
@onready var _level_stars: HBoxContainer = $UI/Root/Info/Content/Results/Stars
@onready var _record_label: Label = $UI/Root/Info/Content/Results/Record
@onready var _play_button: Button = $UI/Root/Info/Content/Buttons/PlayButton
@onready var _endless_button: Button = $UI/Root/Info/Content/Buttons/EndlessButton
@onready var _treasury: Control = $UI/Root/Treasury
@onready var _free_label: Label = $UI/Root/Treasury/Panel/Content/Header/FreePill/Row/Label
@onready var _cards: GridContainer = $UI/Root/Treasury/Panel/Content/Cards
@onready var _records_button: Button = $UI/Root/TopRight/RecordsButton
@onready var _ui_root: Control = $UI/Root


func _ready() -> void:
	LevelCatalog.apply_sound()
	LevelCatalog.endless = false
	_build_sites()
	_play_button.pressed.connect(_start.bind(false))
	_endless_button.pressed.connect(_start.bind(true))
	_sound_button.pressed.connect(_on_sound_pressed)
	_treasury_button.pressed.connect(_open_treasury)
	$UI/Root/Treasury/Panel/Content/Footer/CloseButton.pressed.connect(_treasury.hide)
	$UI/Root/Treasury/Panel/Content/Footer/ResetButton.pressed.connect(_on_reset_pressed)
	_update_sound_icon()
	_refresh_stars()
	_records_button.visible = Online.is_configured()
	_records_button.pressed.connect(_open_records)
	Online.leaderboard_loaded.connect(_on_leaderboard_loaded)
	Online.status_changed.connect(_on_online_status)
	Online.cloud_loaded.connect(_on_cloud_loaded)
	_select(clampi(LevelCatalog.selected_id, 1, LevelCatalog.unlocked()))


func _process(_delta: float) -> void:
	# Buttons follow their sites; the camera stays still so the map does not jump.
	for i in _site_buttons.size():
		var screen: Vector2 = _camera.unproject_position(_sites[i].global_position)
		_site_buttons[i].position = (screen - _site_buttons[i].size / 2.0).round()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _treasury.visible:
			_treasury.hide()
		elif _records and _records.visible:
			_records.hide()
		else:
			get_tree().quit()  # Android back on the map leaves the game


func _build_sites() -> void:
	var unlocked: int = LevelCatalog.unlocked()
	for level: Dictionary in LevelCatalog.levels():
		var id: int = int(level["id"])
		var site := _map.find_child("Site%d" % id) as Node3D
		if site == null:
			continue
		var button := Button.new()
		button.custom_minimum_size = Vector2(84, 84)
		button.focus_mode = Control.FOCUS_NONE
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 0)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if id > unlocked:
			button.icon = LOCK_ICON
			button.disabled = true
		else:
			button.icon = CASTLE_ICON
			button.pressed.connect(_select.bind(id))
			var stars := _star_row(LevelCatalog.stars(id), 26)
			stars.position = Vector2(2, 84)
			button.add_child(stars)
		_site_layer.add_child(button)
		var number := Label.new()
		number.text = str(id)
		number.add_theme_font_size_override("font_size", 24)
		number.position = Vector2(6, -8)
		number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(number)
		_site_buttons.append(button)
		_sites.append(site)
		_site_ids.append(id)


## Three star icons, the first `earned` lit.
func _star_row(earned: int, size: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 0)
	for i in 3:
		var star := TextureRect.new()
		star.texture = STAR_ICON
		star.custom_minimum_size = Vector2(size, size)
		star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		star.modulate = Color.WHITE if i < earned else DIM_STAR
		row.add_child(star)
	return row


func _select(id: int) -> void:
	_selected = id
	var level: Dictionary = LevelCatalog.get_level(id)
	_name_label.text = "%d. %s" % [id, level["name"]]
	_subtitle_label.text = level["subtitle"]
	for child in _level_stars.get_children():
		child.queue_free()
	_level_stars.add_child(_star_row(LevelCatalog.stars(id), 34))
	var won: bool = LevelCatalog.is_completed(id)
	_endless_button.visible = won
	var record: int = LevelCatalog.endless_record(id)
	if not won:
		_record_label.text = "  Пройдите уровень — откроется бесконечная осада"
	else:
		_record_label.text = (
			"  Осада: рекорд %d волн · звёзд %d/%d"
			% [record, Perks.endless_stars(id), Perks.ENDLESS_MAX_STARS]
		)
	for i in _site_buttons.size():
		_site_buttons[i].modulate = Color(1.15, 1.1, 0.9) if _site_ids[i] == id else Color.WHITE


func _refresh_stars() -> void:
	_stars_label.text = "%d / %d" % [Perks.earned_stars(), Perks.max_stars()]
	_treasury_badge.visible = Perks.any_affordable()


func _open_treasury() -> void:
	_fill_cards()
	_treasury.show()


func _fill_cards() -> void:
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	_free_label.text = "Свободно: %d" % Perks.free_stars()
	for perk: PerkData in Perks.all():
		_cards.add_child(_perk_card(perk))
	_refresh_stars()


func _perk_card(perk: PerkData) -> PanelContainer:
	var level: int = Perks.level(perk.id)
	var card := PanelContainer.new()
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
	title.text = perk.display_name
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_font_size_override("font_size", 23)
	texts.add_child(title)
	var level_label := Label.new()
	level_label.text = "Уровень %d / %d" % [level, perk.max_level()]
	level_label.add_theme_font_size_override("font_size", 16)
	texts.add_child(level_label)
	var effect := Label.new()
	var now: String = perk.format_value(level) if level > 0 else "нет"
	effect.text = perk.description % now
	if level < perk.max_level():
		effect.text += " → " + perk.format_value(level + 1)
	effect.add_theme_font_size_override("font_size", 17)
	box.add_child(effect)
	var buy := Button.new()
	buy.focus_mode = Control.FOCUS_NONE
	buy.custom_minimum_size = Vector2(0, 50)
	buy.add_theme_font_size_override("font_size", 20)
	var cost: int = Perks.next_cost(perk)
	if cost < 0:
		buy.text = "Максимум"
		buy.disabled = true
	else:
		buy.text = "Купить за %d" % cost
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


func _open_records() -> void:
	if _records == null:
		_build_records_panel()
	_records_title.text = "Рекорды осады: " + str(LevelCatalog.get_level(_selected)["name"])
	_records_status.text = "Загрузка…"
	for child in _records_list.get_children():
		child.queue_free()
	_records.show()
	Online.fetch_leaderboard(_selected)


## Online panel (only when Firebase is configured): nickname, top 10 of the
## selected level's endless siege, cloud save / load.
func _build_records_panel() -> void:
	_records = Control.new()
	_records.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_root.add_child(_records)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.06, 0.14, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_records.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(640, 560)
	panel.position = Vector2(-320, -280)
	_records.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_records_title = Label.new()
	_records_title.add_theme_color_override("font_color", GOLD)
	_records_title.add_theme_font_size_override("font_size", 30)
	box.add_child(_records_title)
	var name_row := HBoxContainer.new()
	box.add_child(name_row)
	var name_label := Label.new()
	name_label.text = "Ваше имя:"
	name_row.add_child(name_label)
	var name_edit := LineEdit.new()
	name_edit.text = Online.player_name()
	name_edit.max_length = Online.NAME_MAX
	name_edit.placeholder_text = "Рыцарь"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_submitted.connect(Online.set_player_name)
	name_edit.focus_exited.connect(func() -> void: Online.set_player_name(name_edit.text))
	name_row.add_child(name_edit)
	_records_list = VBoxContainer.new()
	_records_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_records_list)
	_records_status = Label.new()
	_records_status.add_theme_font_size_override("font_size", 18)
	box.add_child(_records_status)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	for spec: Array in [
		["В облако", Online.cloud_save, true],
		["Из облака", Online.cloud_load, true],
		["Закрыть", _records.hide, false]
	]:
		var button := Button.new()
		button.text = spec[0]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(180, 56)
		if spec[2]:
			button.theme_type_variation = &"SecondaryButton"
		button.pressed.connect(spec[1])
		buttons.add_child(button)


func _on_leaderboard_loaded(level_id: int, entries: Array) -> void:
	if _records == null or level_id != _selected:
		return
	for child in _records_list.get_children():
		child.queue_free()
	_records_status.text = (
		"" if not entries.is_empty() else "Пока никто не играл в осаду на этом уровне"
	)
	for i in entries.size():
		var row := Label.new()
		row.text = "%d. %s — %d волн" % [i + 1, entries[i]["name"], entries[i]["wave"]]
		row.add_theme_font_size_override("font_size", 21)
		if i == 0:
			row.add_theme_color_override("font_color", GOLD)
		_records_list.add_child(row)


func _on_online_status(text: String) -> void:
	if _records_status:
		_records_status.text = text


func _on_cloud_loaded(ok: bool) -> void:
	if ok:
		get_tree().reload_current_scene()  # show the restored stars and levels


func _on_sound_pressed() -> void:
	LevelCatalog.set_sound_on(not LevelCatalog.sound_on())
	_update_sound_icon()


func _update_sound_icon() -> void:
	_sound_button.icon = SOUND_ON_ICON if LevelCatalog.sound_on() else SOUND_OFF_ICON


func _start(endless: bool) -> void:
	LevelCatalog.selected_id = _selected
	LevelCatalog.endless = endless
	_play_button.disabled = true
	_endless_button.disabled = true
	get_tree().change_scene_to_file(GAME_SCENE)

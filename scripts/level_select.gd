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
## Seconds for one slow sway of the camera.
const ORBIT_PERIOD := 90.0
const ORBIT_SWAY := 0.12

var _site_buttons: Array[Button] = []
var _sites: Array[Node3D] = []
var _selected: int = 0
var _time: float = 0.0
var _camera_base: Transform3D

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


func _ready() -> void:
	_camera_base = _camera.transform
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
	_select(clampi(LevelCatalog.selected_id, 1, LevelCatalog.unlocked()))


func _process(delta: float) -> void:
	_time += delta
	# Gentle sway so the map feels alive.
	var angle: float = sin(_time * TAU / ORBIT_PERIOD) * ORBIT_SWAY
	_camera.transform = Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO) * _camera_base
	for i in _site_buttons.size():
		var button: Button = _site_buttons[i]
		var bob: float = sin(_time * 2.4 + i) * 4.0 if i + 1 == _selected else 0.0
		var screen: Vector2 = _camera.unproject_position(_sites[i].global_position)
		button.position = screen - button.size / 2.0 + Vector2(0.0, bob)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _treasury.visible:
			_treasury.hide()
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
		_site_buttons[i].modulate = Color(1.15, 1.1, 0.9) if i + 1 == id else Color.WHITE


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

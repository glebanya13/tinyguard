extends Node3D
## Start screen: a 3D island map with a round badge per level (locked levels show a lock,
## earned stars sit under each badge), a top bar (title, gems, stars, cloud state, sound,
## settings, profile), a tab bar at the bottom (Shop, Treasury, Daily trial, Streak,
## Achievements, Co-op, Records) and the card of the selected level on the right: emblem,
## name, stars, record, difficulty segments, "Play" and the "Record Run". The treasury is where
## stars buy permanent perks. Layout rules (docs/UI_STYLE_GUIDE.md): grid 8 px, three levels
## of hierarchy, nothing covers a level badge; tests/test_map_layout.gd checks it.

const GAME_SCENE := "res://scenes/main.tscn"
const COOP_SCENE := "res://scenes/coop_lobby.tscn"
const SHOP_SCENE := "res://scenes/shop.tscn"
const LOCK_ICON: Texture2D = preload("res://ui/icons/lock.png")
const STAR_ICON: Texture2D = preload("res://ui/icons/star.png")
const STAR_EMPTY_ICON: Texture2D = preload("res://ui/icons/star_empty.png")
const SOUND_ON_ICON: Texture2D = preload("res://ui/icons/sound_on.png")
const SOUND_OFF_ICON: Texture2D = preload("res://ui/icons/sound_off.png")
const PROFILE_ICON: Texture2D = preload("res://ui/icons/villager.png")
const GEAR_ICON: Texture2D = preload("res://ui/icons/gear.png")
const DAILY_ICON: Texture2D = preload("res://ui/icons/hourglass.png")
const ACHIEVEMENTS_ICON: Texture2D = preload("res://ui/icons/crown.png")
const TROPHY_ICON: Texture2D = preload("res://ui/icons/trophy.png")
const SHOP_ICON: Texture2D = preload("res://ui/icons/shop.png")
const CHEST_ICON: Texture2D = preload("res://ui/icons/chest.png")
const FLAME_ICON: Texture2D = preload("res://ui/icons/flame.png")
const FRIENDS_ICON: Texture2D = preload("res://ui/icons/friends.png")
const CLOUD_OK_ICON: Texture2D = preload("res://ui/icons/cloud_ok.png")
const CLOUD_OFF_ICON: Texture2D = preload("res://ui/icons/cloud_off.png")
const COIN_ICON: Texture2D = preload("res://ui/icons/coin.png")
const CALENDAR_ICON: Texture2D = preload("res://ui/icons/hourglass.png")
const ModesPanel := preload("res://scripts/modes_panel.gd")
const GOLD := Color(1.0, 0.88, 0.45)
## Tint of the difficulty crown: Hard, Nightmare.
const CROWN_COLORS: Array[Color] = [Color.WHITE, Color(1.0, 0.62, 0.25), Color(0.8, 0.45, 1.0)]
## Layout in canvas pixels (grid 8): the island lives between the top bar, the tab bar and the
## card of the selected level.
const MARGIN := 16.0
const TOP_BAR_BOTTOM := 80.0
const TAB_BAR_HEIGHT := 104.0
const TAB_HEIGHT := 88.0
const CARD_WIDTH := 352.0
const NODE_SIZE := 88.0
const NODE_STARS := 26.0
const NODE_SCALE_CHOSEN := 1.14
const ICON_BUTTON := 72.0
const ICON_BUTTON_ICON := 44

var _site_buttons: Array[Button] = []
var _sites: Array[Node3D] = []
## Level id of each site button (same order as _site_buttons).
var _site_ids: Array[int] = []
var _selected: int = 0
var _records: RecordsPanel = null
var _treasury_frame: DialogFrame = null
var _account: AccountPanel = null
var _settings: SettingsPanel = null
var _encyclopedia: EncyclopediaPanel = null
var _sync_button: Button = null
var _reminder: AccountReminder = null
var _coop_button: Button = null
var _daily: DailyPanel = null
var _achievements: AchievementsPanel = null
var _camp_panel: CampPanel = null
var _calendar_panel: CalendarPanel = null
var _camp_button: Button = null
var _camp_dot: Control = null
var _calendar_button: Button = null
var _calendar_dot: Control = null
var _gems: GemsHud = null
var _modes_panel: ModesPanel = null
var _tab_bar: PanelContainer = null
var _tab_row: HBoxContainer = null
var _treasury_button: Button = null
var _treasury_dot: Control = null
var _daily_dot: Control = null
var _rewards_dot: Control = null
## Campaign difficulty picked for the next battle (0 Normal, 1 Hard, 2 Nightmare).
var _difficulty: int = 0
var _diff_buttons: Array[Button] = []
var _crown_icon: TextureRect = null

@onready var _map: Node3D = $Map
@onready var _camera: Camera3D = $Camera
@onready var _site_layer: Control = $UI/Root/Sites
@onready var _stars_label: Label = $UI/Root/TopRight/StarsPill/Row/Label
@onready var _sound_button: Button = $UI/Root/TopRight/SoundButton
@onready var _hero: TextureRect = $UI/Root/Info/Content/Header/Emblem
@onready var _name_label: Label = $UI/Root/Info/Content/Header/Texts/Name
@onready var _subtitle_label: Label = $UI/Root/Info/Content/Header/Texts/Subtitle
@onready var _level_stars: HBoxContainer = $UI/Root/Info/Content/Results/Stars
@onready var _record_label: Label = $UI/Root/Info/Content/Results/Record
@onready var _segments: HBoxContainer = $UI/Root/Info/Content/Segments
@onready var _diff_info: Label = $UI/Root/Info/Content/DiffInfo
@onready var _play_button: Button = $UI/Root/Info/Content/PlayButton
@onready var _endless_button: Button = $UI/Root/Info/Content/EndlessButton
@onready var _treasury: Control = $UI/Root/Treasury
@onready var _free_label: Label = $UI/Root/Treasury/Content/Header/FreePill/Row/Label
@onready var _cards: GridContainer = $UI/Root/Treasury/Content/Cards
@onready var _ui_root: Control = $UI/Root


func _ready() -> void:
	GameSettings.apply_language()
	LevelCatalog.apply_sound()
	LevelCatalog.endless = false
	LevelCatalog.difficulty = 0
	LevelCatalog.tutorial = false
	LevelCatalog.daily_key = ""
	SafeArea.attach(_ui_root)
	_frame_treasury()
	_achievements = AchievementsPanel.new()
	_ui_root.add_child(_achievements)
	_build_sites()
	_build_account_ui()
	_build_card()
	_build_tabs()
	_play_button.pressed.connect(_start.bind(false))
	_endless_button.pressed.connect(_start.bind(true))
	_sound_button.pressed.connect(_on_sound_pressed)
	_treasury.find_child("CloseButton", true, false).pressed.connect(_treasury.hide)
	_treasury.find_child("ResetButton", true, false).pressed.connect(_on_reset_pressed)
	_update_sound_icon()
	_refresh_stars()
	Online.cloud_loaded.connect(_on_cloud_loaded)
	_select(clampi(LevelCatalog.selected_id, 1, LevelCatalog.unlocked()))
	_ui_root.resized.connect(_fit_camera)
	_fit_camera.call_deferred()
	if LevelCatalog.open_records and Online.is_configured():
		_open_records()  # back from the end screen of a Record Run
	LevelCatalog.open_records = false


## The treasury card is made in the scene; its content moves into the common dialog frame
## (dim over the whole screen, panel centred on the screen).
func _frame_treasury() -> void:
	var frame := DialogFrame.attach(_treasury, 1200.0, 0.6)
	_treasury_frame = frame
	var content: Control = _treasury.get_node("Content")
	content.reparent(frame.body, false)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Close and refund stay in view when the cards scroll.
	content.get_node("Footer").reparent(frame.footer, false)


func _process(_delta: float) -> void:
	# Badges follow their sites; the camera stays still so the map does not jump.
	for i in _site_buttons.size():
		var screen: Vector2 = _camera.unproject_position(_sites[i].global_position)
		_site_buttons[i].position = (screen - _site_buttons[i].size / 2.0).round()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _gems.is_panel_open():
			_gems.close_panel()
		elif _camp_panel and _camp_panel.visible:
			_camp_panel.close()
		elif _calendar_panel and _calendar_panel.visible:
			_calendar_panel.close()
		elif _daily.visible:
			_daily.close()
		elif _achievements.visible:
			_achievements.close()
		elif _treasury.visible:
			_treasury.hide()
		elif _records and _records.visible:
			_records.close()
		elif _settings.visible:
			_settings.close()
		elif _encyclopedia and _encyclopedia.visible:
			_encyclopedia.close()
		elif _account.visible:
			_account.close()
		else:
			get_tree().quit()  # Android back on the map leaves the game


## Shifts and zooms the island (frustum offsets and field of view) so that the centres of all
## the level badges land inside the free area between the top bar, the tab bar and the card,
## with room left for the chosen badge and the stars under it.
func _fit_camera() -> void:
	if _site_buttons.is_empty():
		return
	var area: Rect2 = _ui_root.get_global_rect()
	var half: float = NODE_SIZE * NODE_SCALE_CHOSEN * 0.5
	var free := Rect2(
		area.position + Vector2(MARGIN + half, TOP_BAR_BOTTOM + MARGIN + half),
		(
			area.size
			- Vector2(
				MARGIN * 3.0 + CARD_WIDTH + half * 2.0,
				TOP_BAR_BOTTOM + MARGIN * 2.0 + TAB_BAR_HEIGHT + half * 2.0 + NODE_STARS + 8.0
			)
		)
	)
	_camera.h_offset = 0.0
	_camera.v_offset = 0.0
	_camera.fov = 50.0
	var box: Rect2 = _sites_box()
	var fit: float = minf(free.size.x / maxf(box.size.x, 1.0), free.size.y / maxf(box.size.y, 1.0))
	var zoom: float = clampf(fit, 0.6, 1.45)
	_camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(50.0) * 0.5) / zoom))
	box = _sites_box()
	# The frustum offsets move the picture by a fixed number of pixels per unit.
	var probe: Vector2 = _site_screen(0)
	_camera.h_offset = 1.0
	_camera.v_offset = 1.0
	var moved: Vector2 = _site_screen(0) - probe
	var shift: Vector2 = free.get_center() - box.get_center()
	_camera.h_offset = shift.x / (moved.x if absf(moved.x) > 0.01 else 1.0)
	_camera.v_offset = shift.y / (moved.y if absf(moved.y) > 0.01 else 1.0)
	_process(0.0)


func _site_screen(index: int) -> Vector2:
	return _camera.unproject_position(_sites[index].global_position)


func _sites_box() -> Rect2:
	var box := Rect2(_site_screen(0), Vector2.ZERO)
	for i in range(1, _sites.size()):
		box = box.expand(_site_screen(i))
	return box


## The badges of the levels on the island, each with the stars of the level under it.
func _build_sites() -> void:
	var unlocked: int = LevelCatalog.unlocked()
	for level: Dictionary in LevelCatalog.levels():
		var id: int = int(level["id"])
		var site := _map.find_child("Site%d" % id) as Node3D
		if site == null:
			continue
		var button := Button.new()
		button.name = "Level%d" % id
		button.custom_minimum_size = Vector2(NODE_SIZE, NODE_SIZE)
		button.size = Vector2(NODE_SIZE, NODE_SIZE)
		button.focus_mode = Control.FOCUS_NONE
		button.theme_type_variation = &"NodeBlue"
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_font_size_override("font_size", 36)
		button.add_theme_constant_override("outline_size", 5)
		button.add_theme_constant_override("icon_max_width", 44)
		if id > unlocked:
			button.icon = LOCK_ICON
			button.disabled = true
		else:
			button.text = str(id)
			button.pressed.connect(_select.bind(id))
			var stars := _star_row(LevelCatalog.stars(id), NODE_STARS)
			stars.position = Vector2((NODE_SIZE - NODE_STARS * 3.0) / 2.0, NODE_SIZE + 2.0)
			button.add_child(stars)
			if LevelCatalog.crown(id) > 0:
				var badge := _crown_texture(LevelCatalog.crown(id), 32)
				badge.position = Vector2(NODE_SIZE - 28.0, -14.0)
				button.add_child(badge)
		_site_layer.add_child(button)
		_site_buttons.append(button)
		_sites.append(site)
		_site_ids.append(id)


## Bottom tab bar: icon over a caption, same width and height for all; a red dot on a tab
## says there is something to do. Order: Shop, Treasury, Daily trial, Streak, Achievements,
## then Co-op and Records when there is a database.
func _build_tabs() -> void:
	_tab_bar = PanelContainer.new()
	_tab_bar.name = "TabBar"
	_tab_bar.theme_type_variation = &"TabBarPanel"
	_tab_bar.anchor_left = 0.0
	_tab_bar.anchor_right = 1.0
	_tab_bar.anchor_top = 1.0
	_tab_bar.anchor_bottom = 1.0
	_tab_bar.offset_left = MARGIN
	_tab_bar.offset_right = -MARGIN
	_tab_bar.offset_top = -(TAB_BAR_HEIGHT + 8.0)
	_tab_bar.offset_bottom = -8.0
	_tab_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ui_root.add_child(_tab_bar)
	_ui_root.move_child(_tab_bar, 0)  # below the dialogs
	_tab_row = HBoxContainer.new()
	_tab_row.name = "Tabs"
	_tab_row.add_theme_constant_override("separation", 4)
	_tab_bar.add_child(_tab_row)
	_daily = DailyPanel.new()
	_daily.online = Online
	_ui_root.add_child(_daily)
	_daily.start_requested.connect(_start_daily)
	_camp_panel = CampPanel.new()
	_ui_root.add_child(_camp_panel)
	_calendar_panel = CalendarPanel.new()
	_ui_root.add_child(_calendar_panel)
	_camp_panel.collected.connect(func(_amt: int) -> void:
		_gems.refresh()
		_update_retention_dots()
	)
	_camp_panel.upgraded.connect(func(_lvl: int) -> void:
		_gems.refresh()
		_update_retention_dots()
	)
	_calendar_panel.reward_claimed.connect(func(_s: int, _c: int, _g: int) -> void:
		_gems.refresh()
		_update_retention_dots()
	)
	_modes_panel = ModesPanel.new()
	_ui_root.add_child(_modes_panel)
	_modes_panel.daily_selected.connect(func() -> void: _daily.open())
	_modes_panel.coop_selected.connect(_open_coop)
	_modes_panel.records_selected.connect(_open_records)

	# 1. Rewards Tab (Streak, Quests, Camp, Calendar)
	var streak_tab := _make_tab("StreakButton", "", FLAME_ICON)
	_rewards_dot = _dot(streak_tab)

	# 2. Talents / Treasury Tab
	_treasury_button = _make_tab("TreasuryButton", tr("MAP_TREASURY"), CHEST_ICON)
	_treasury_button.pressed.connect(_open_treasury)
	_treasury_dot = _dot(_treasury_button)

	# 3. Game Modes Tab (Daily Trial, Co-op, Leaderboards)
	var modes_tab := _make_tab("DailyButton", tr("MODES_BUTTON"), DAILY_ICON)
	modes_tab.pressed.connect(_modes_panel.open)
	_daily_dot = _dot(modes_tab)
	_daily_dot.visible = Daily.best_wave(Daily.today_key()) <= 0

	# 4. Shop Tab
	var shop_tab := _make_tab("ShopButton", tr("SHOP_BUTTON"), SHOP_ICON)

	_gems = GemsHud.new()
	_gems.name = "GemsHud"
	add_child(_gems)
	_gems.mount(_ui_root, $UI/Root/TopRight, shop_tab, streak_tab)
	_gems.shop_requested.connect(func() -> void: get_tree().change_scene_to_file(SHOP_SCENE))

	var streak_panel: StreakPanel = _ui_root.get_node_or_null("StreakPanel") as StreakPanel
	if streak_panel != null:
		streak_panel.camp_requested.connect(_camp_panel.open)
		streak_panel.calendar_requested.connect(_calendar_panel.open)
		_camp_button = streak_panel.find_child("CampButton", true, false) as Button
		_calendar_button = streak_panel.find_child("CalendarButton", true, false) as Button
		if _camp_button != null:
			_camp_dot = _dot(_camp_button)
		if _calendar_button != null:
			_calendar_dot = _dot(_calendar_button)


func _make_tab(node_name: String, text: String, icon: Texture2D) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.icon = icon
	button.theme_type_variation = &"TabButton"
	button.focus_mode = Control.FOCUS_NONE
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	button.custom_minimum_size = Vector2(ICON_BUTTON, TAB_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_row.add_child(button)
	return button


## Red notification dot in the top right corner of a tab (hidden until it is needed).
func _dot(tab: Button) -> Control:
	var dot := Panel.new()
	dot.name = "Dot"
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.anchor_left = 1.0
	dot.anchor_right = 1.0
	dot.offset_left = -40.0
	dot.offset_right = -20.0
	dot.offset_top = 8.0
	dot.offset_bottom = 28.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.3, 0.28)
	style.set_corner_radius_all(10)
	style.set_border_width_all(3)
	style.border_color = Color(1.0, 0.97, 0.88)
	dot.add_theme_stylebox_override("panel", style)
	dot.visible = false
	tab.add_child(dot)
	return dot


func _start_daily(day: String) -> void:
	DailyRun.select(day)
	get_tree().change_scene_to_file(GAME_SCENE)


func _open_coop() -> void:
	LevelCatalog.selected_id = _selected
	LevelCatalog.endless = false
	get_tree().change_scene_to_file(COOP_SCENE)


## Three star icons, the first `earned` lit.
func _star_row(earned: int, size: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 0)
	for i in 3:
		var star := TextureRect.new()
		star.texture = STAR_ICON if i < earned else STAR_EMPTY_ICON
		star.custom_minimum_size = Vector2(size, size)
		star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(star)
	return row


func _select(id: int) -> void:
	_selected = id
	var level: Dictionary = LevelCatalog.get_level(id)
	_name_label.text = "%d. %s" % [id, tr(level["name"])]
	_subtitle_label.text = tr(level["subtitle"])
	for child in _level_stars.get_children():
		child.queue_free()
	_level_stars.add_child(_star_row(LevelCatalog.stars(id), 36))
	var biome_path: String = "res://ui/biomes/%s.png" % str(level.get("biome", "meadow"))
	_hero.texture = load(biome_path) if ResourceLoader.exists(biome_path) else null
	var crown: int = LevelCatalog.crown(id)
	_crown_icon.visible = crown > 0
	if crown > 0:
		_crown_icon.modulate = CROWN_COLORS[crown]
		_crown_icon.tooltip_text = tr("MAP_CROWN") % tr(str(Balance.difficulty(crown)["name"]))
	var record: int = LevelCatalog.endless_record(id)
	_record_label.text = (tr("MAP_RECORD_BEST") % record if record > 0 else tr("MAP_RECORD_NONE"))
	if BattleCheckpoint.has_checkpoint(id):
		var cp: Dictionary = BattleCheckpoint.load_checkpoint()
		var cp_endless: bool = bool(cp.get("endless", false))
		var wave: int = int(cp.get("wave", 1))
		if cp_endless:
			_play_button.text = tr("MAP_PLAY")
			_endless_button.text = tr("CHECKPOINT_CONTINUE") % wave
		else:
			_play_button.text = tr("CHECKPOINT_CONTINUE") % wave
			_endless_button.text = tr("MAP_RECORD_RUN")
	else:
		_play_button.text = tr("MAP_PLAY")
		_endless_button.text = tr("MAP_RECORD_RUN")
	if not LevelCatalog.is_difficulty_open(id, _difficulty):
		_difficulty = 0
	_refresh_difficulty(id)
	for i in _site_buttons.size():
		var chosen: bool = _site_ids[i] == id
		var button: Button = _site_buttons[i]
		if not button.disabled:
			var done: bool = LevelCatalog.stars(_site_ids[i]) > 0
			button.theme_type_variation = (
				&"NodeGold" if chosen else (&"NodeGreen" if done else &"NodeBlue")
			)
		button.pivot_offset = button.size * 0.5
		button.scale = Vector2.ONE * NODE_SCALE_CHOSEN if chosen else Vector2.ONE
		if chosen:
			_site_layer.move_child(button, -1)  # above its neighbours, still under the dialogs


func _refresh_stars() -> void:
	_stars_label.text = "%d / %d" % [Perks.earned_stars(), Perks.max_stars()]
	if _treasury_dot != null:
		_treasury_dot.visible = Perks.any_affordable()
	_update_retention_dots()


func _update_retention_dots() -> void:
	var p: Dictionary = PlayerProfile.local()
	var now: int = int(Time.get_unix_time_from_system())
	var pending: int = Camp.pending_coins(p.get("camp", {}), now)
	var can_cal: bool = Calendar28.can_claim(
		p.get("calendar", {}), Daily.today_key(), p.get("wallet", {})
	)

	if _rewards_dot != null:
		_rewards_dot.visible = pending > 0 or can_cal
	if _camp_dot != null:
		_camp_dot.visible = pending > 0
		if _camp_button != null:
			if pending > 0:
				_camp_button.text = tr("MAP_CAMP") + " (+%d)" % pending
			else:
				_camp_button.text = tr("MAP_CAMP")
	if _calendar_dot != null:
		_calendar_dot.visible = can_cal
	if _treasury_dot != null:
		_treasury_dot.visible = Perks.any_affordable()


func _open_treasury() -> void:
	_fill_cards()
	_treasury.show()


func _fill_cards() -> void:
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	_free_label.text = tr("MAP_FREE_STARS") % Perks.free_stars()
	var hint: Label = _treasury.find_child("Hint", true, false) as Label
	if hint != null:
		hint.text = tr("MAP_TREASURY_HINT") + "\n" + tr("PERKS_STARS_SOURCE_HINT")
	for perk: PerkData in Perks.all():
		_cards.add_child(_perk_card(perk))
	# Four columns (two rows) when the screen is wide enough for them, else three.
	var margins: Vector2 = _treasury_frame.panel.get_theme_stylebox("panel").get_minimum_size()
	var room: float = DialogFrame.room(get_viewport()).size.x - margins.x
	_cards.columns = 4
	if _cards.get_combined_minimum_size().x > room:
		_cards.columns = 3
	_refresh_stars()


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


func _open_records() -> void:
	if _records == null:
		_records = RecordsPanel.new()
		_records.online = Online
		_ui_root.add_child(_records)
	_records.open(_selected, tr(str(LevelCatalog.get_level(_selected)["name"])))


func _on_cloud_loaded(ok: bool) -> void:
	if ok:
		get_tree().reload_current_scene()  # show the restored stars and levels


## The soft reminder cards: a guest with progress is invited to create an account; an
## email account whose login expired is invited to sign in again. Dismissible.
func _build_reminder() -> void:
	_reminder = AccountReminder.new()
	_ui_root.add_child(_reminder)
	_reminder.action_requested.connect(_on_reminder_action)
	Online.session_expired.connect(_update_reminder)
	Online.account_changed.connect(_update_reminder)
	_update_reminder()


func _update_reminder() -> void:
	if _reminder == null or not Online.is_configured():
		return
	if Online.account_type() == "email" and Online.sync_state() == "session_lost":
		_reminder.present(AccountReminder.Kind.SIGN_IN)
	elif Online.account_reminder_due():
		_reminder.present(AccountReminder.Kind.CREATE)
	else:
		_reminder.hide()


func _on_reminder_action(kind: String) -> void:
	_reminder.hide()
	if kind == "signin":
		_account.open_dialog(EmailAuthDialog.Mode.SIGN_IN)
	else:
		_account.open_dialog(EmailAuthDialog.Mode.LINK)


func _on_rename_requested() -> void:
	Onboarding.rename_mode = true
	get_tree().change_scene_to_file(Onboarding.NICKNAME_SCENE)


func _on_sound_pressed() -> void:
	LevelCatalog.set_sound_on(not LevelCatalog.sound_on())
	_update_sound_icon()


func _update_sound_icon() -> void:
	_sound_button.icon = SOUND_ON_ICON if LevelCatalog.sound_on() else SOUND_OFF_ICON


## Cloud state, settings and profile buttons in the top bar and the account panel.
func _build_account_ui() -> void:
	var bar: Container = _sound_button.get_parent()
	_sync_button = _icon_button(CLOUD_OK_ICON, "")
	_sync_button.name = "SyncButton"
	_sync_button.visible = false
	_sync_button.pressed.connect(func() -> void: _account.open())
	bar.add_child(_sync_button)
	bar.move_child(_sync_button, _sound_button.get_index())
	_sound_button.custom_minimum_size = Vector2(ICON_BUTTON, ICON_BUTTON)
	var button := _icon_button(PROFILE_ICON, tr("MAP_PROFILE"))
	button.name = "ProfileButton"
	button.pressed.connect(func() -> void: _account.open())
	_sound_button.add_sibling(button)
	_build_settings_ui()
	_account = AccountPanel.new()
	_ui_root.add_child(_account)
	_account.rename_requested.connect(_on_rename_requested)
	_account.replay_tutorial_requested.connect(
		func() -> void: Onboarding.start_tutorial(get_tree())
	)
	_account.account_deleted.connect(
		func() -> void: get_tree().change_scene_to_file(Onboarding.BOOT_SCENE)
	)
	_account.signed_out.connect(
		func() -> void: get_tree().change_scene_to_file(Onboarding.BOOT_SCENE)
	)
	# Show the progress of the account that was signed in to.
	_account.account_switched.connect(func() -> void: get_tree().reload_current_scene())
	Online.sync_state_changed.connect(_on_sync_state)
	Online.start()  # no-op after boot
	_on_sync_state(Online.sync_state())
	_build_reminder()
	if Online.is_configured():
		Online.sync_now()  # pushes progress made in the level


## A square icon button of the top bar (72 px, icon 44 px).
func _icon_button(icon: Texture2D, tip: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(ICON_BUTTON, ICON_BUTTON)
	button.focus_mode = Control.FOCUS_NONE
	button.theme_type_variation = &"IconButton"
	button.icon = icon
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", ICON_BUTTON_ICON)
	button.tooltip_text = tip
	return button


## Gear button next to the sound button and the settings dialog.
func _build_settings_ui() -> void:
	var ach_btn := _icon_button(ACHIEVEMENTS_ICON, tr("ACH_BUTTON"))
	ach_btn.name = "AchievementsButton"
	_sound_button.add_sibling(ach_btn)
	ach_btn.pressed.connect(_achievements.open)

	var book := _icon_button(preload("res://ui/icons/map.png"), tr("ENCYCLOPEDIA_TOOLTIP"))
	book.name = "EncyclopediaButton"
	_sound_button.add_sibling(book)
	_encyclopedia = EncyclopediaPanel.new()
	_ui_root.add_child(_encyclopedia)
	book.pressed.connect(_encyclopedia.open)

	var gear := _icon_button(GEAR_ICON, tr("SET_TOOLTIP"))
	gear.name = "SettingsButton"
	_sound_button.add_sibling(gear)
	_settings = SettingsPanel.new()
	_ui_root.add_child(_settings)
	gear.pressed.connect(_settings.open)
	_settings.closed.connect(_update_sound_icon)
	# Texts built in code are cached: rebuild the map in the new language.
	_settings.language_changed.connect(func() -> void: get_tree().reload_current_scene())


## The cloud icon of the top bar: a tick when everything is saved, a cross when something
## waits for the connection (or the name is taken); the tip says what. Shown only when the
## game has a Firebase project or something is not saved.
func _on_sync_state(state: String) -> void:
	var conflict: bool = bool(PlayerProfile.local()["nicknameConflict"])
	var behind: bool = state in ["pending", "offline", "session_lost", "newer"]
	if state == "offline" and not PlayerProfile.is_pending():
		behind = false  # offline but everything is saved: nothing to nag about on the map
	var bad: bool = conflict or behind
	_sync_button.visible = Online.is_configured() or bad
	_sync_button.icon = CLOUD_OFF_ICON if bad else CLOUD_OK_ICON
	_sync_button.tooltip_text = tr("MAP_NAME_CONFLICT") if conflict else Online.state_text(state)


## The card of the selected level: segments of the difficulty, the crown and the record row.
func _build_card() -> void:
	_play_button.theme_type_variation = &""
	_endless_button.tooltip_text = tr("MAP_RECORD_SUB")
	_crown_icon = _crown_texture(1, 32)
	_crown_icon.custom_minimum_size = Vector2(32, 32)
	_crown_icon.mouse_filter = Control.MOUSE_FILTER_PASS
	_level_stars.get_parent().add_child(_crown_icon)
	_level_stars.get_parent().move_child(_crown_icon, 1)
	var trophy := TextureRect.new()
	trophy.texture = TROPHY_ICON
	trophy.custom_minimum_size = Vector2(28, 28)
	trophy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	trophy.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	trophy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var results: Control = _level_stars.get_parent()
	var record_row := HBoxContainer.new()
	record_row.name = "RecordRow"
	record_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	record_row.add_theme_constant_override("separation", 8)
	results.get_parent().add_child(record_row)
	results.get_parent().move_child(record_row, results.get_index() + 1)
	_record_label.reparent(record_row, false)
	record_row.add_child(trophy)
	record_row.move_child(trophy, 0)
	var group := ButtonGroup.new()
	for i in Balance.difficulty_count():
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, 56)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.theme_type_variation = &"SegmentButton"
		button.text = tr(str(Balance.difficulty(i)["name"]))
		button.add_theme_font_size_override("font_size", 16)
		button.add_theme_constant_override("icon_max_width", 20)
		button.add_theme_constant_override("h_separation", 4)
		button.pressed.connect(_on_difficulty_pressed.bind(i))
		_segments.add_child(button)
		_diff_buttons.append(button)


func _start(endless: bool) -> void:
	LevelCatalog.selected_id = _selected
	LevelCatalog.endless = endless
	LevelCatalog.difficulty = 0 if endless else _difficulty
	var cp: Dictionary = (
		BattleCheckpoint.load_checkpoint() if BattleCheckpoint.has_checkpoint(_selected) else {}
	)
	LevelCatalog.resume_checkpoint = not cp.is_empty() and bool(cp.get("endless", false)) == endless
	_play_button.disabled = true
	_endless_button.disabled = true
	get_tree().change_scene_to_file(GAME_SCENE)


func _refresh_difficulty(id: int) -> void:
	for i in _diff_buttons.size():
		var open: bool = LevelCatalog.is_difficulty_open(id, i)
		var button: Button = _diff_buttons[i]
		button.disabled = not open
		button.icon = null if open else LOCK_ICON
		button.set_pressed_no_signal(i == _difficulty)
	_diff_info.text = _difficulty_info(id, _difficulty)


func _difficulty_info(id: int, index: int) -> String:
	if index == 0:
		# What the next locked one needs, else the plain note.
		for i in range(1, _diff_buttons.size()):
			if not LevelCatalog.is_difficulty_open(id, i):
				return tr("MAP_DIFF_LOCK_%d" % i)
		return tr("MAP_DIFF_BASE")
	var row: Dictionary = Balance.difficulty(index)
	return (
		tr("MAP_DIFF_INFO")
		% [
			_times(float(row["hp"])),
			_times(float(row["count"])),
			_times(float(row["reward"])),
			_times(float(row["lives"])),
		]
	)


## "1.3" / "0.8" without a trailing zero: 1.0 -> "1".
static func _times(value: float) -> String:
	return str(snappedf(value, 0.01))


func _on_difficulty_pressed(index: int) -> void:
	_difficulty = index
	_refresh_difficulty(_selected)


## The crown icon, tinted by the difficulty (1 Hard, 2 Nightmare).
func _crown_texture(level_difficulty: int, size: float) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = ACHIEVEMENTS_ICON
	icon.custom_minimum_size = Vector2(size, size)
	icon.size = Vector2(size, size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = CROWN_COLORS[clampi(level_difficulty, 0, CROWN_COLORS.size() - 1)]
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

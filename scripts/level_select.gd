extends Node3D
## Start screen: a 3D island map with one button per level (locked levels
## show a lock, earned stars sit under each button), the star counter, the
## treasury where stars buy permanent perks, and the selected level's card
## with "Play" and, once the level is won, the endless siege.

const GAME_SCENE := "res://scenes/main.tscn"
const COOP_SCENE := "res://scenes/coop_lobby.tscn"
const LOCK_ICON: Texture2D = preload("res://ui/icons/lock.png")
const STAR_ICON: Texture2D = preload("res://ui/icons/star.png")
const STAR_EMPTY_ICON: Texture2D = preload("res://ui/icons/star_empty.png")
const CASTLE_ICON: Texture2D = preload("res://ui/icons/flag.png")
const SOUND_ON_ICON: Texture2D = preload("res://ui/icons/sound_on.png")
const SOUND_OFF_ICON: Texture2D = preload("res://ui/icons/sound_off.png")
const PROFILE_ICON: Texture2D = preload("res://ui/icons/villager.png")
const GEAR_ICON: Texture2D = preload("res://ui/icons/gear.png")
const DAILY_ICON: Texture2D = preload("res://ui/icons/hourglass.png")
const ACHIEVEMENTS_ICON: Texture2D = preload("res://ui/icons/crown.png")
const GOLD := Color(0.98, 0.8, 0.4)

var _site_buttons: Array[Button] = []
var _sites: Array[Node3D] = []
## Level id of each site button (same order as _site_buttons).
var _site_ids: Array[int] = []
var _selected: int = 0
var _records: Control = null
var _records_list: VBoxContainer = null
var _records_title: Label = null
var _records_status: Label = null
var _account: AccountPanel = null
var _settings: SettingsPanel = null
var _sync_label: Label = null
var _coop_button: Button = null
var _daily: DailyPanel = null
var _achievements: AchievementsPanel = null

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
	GameSettings.apply_language()
	LevelCatalog.apply_sound()
	LevelCatalog.endless = false
	LevelCatalog.tutorial = false
	LevelCatalog.daily_key = ""
	_build_sites()
	_build_account_ui()
	_play_button.pressed.connect(_start.bind(false))
	_endless_button.pressed.connect(_start.bind(true))
	_build_coop_button()
	_build_extras()
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
		if _daily.visible:
			_daily.close()
		elif _achievements.visible:
			_achievements.close()
		elif _treasury.visible:
			_treasury.hide()
		elif _records and _records.visible:
			_records.hide()
		elif _settings.visible:
			_settings.close()
		elif _account.visible:
			_account.close()
		else:
			get_tree().quit()  # Android back on the map leaves the game


## "Кооператив": only with a configured Realtime Database (Online.rtdb); otherwise
## the map is exactly the single-player map.
func _build_coop_button() -> void:
	if CoopRun.transport() == null:
		return
	_coop_button = Button.new()
	_coop_button.name = "CoopButton"
	_coop_button.custom_minimum_size = Vector2(260, 84)
	_coop_button.focus_mode = Control.FOCUS_NONE
	_coop_button.theme_type_variation = &"SecondaryButton"
	_coop_button.text = tr("COOP_BUTTON")
	_coop_button.icon = PROFILE_ICON
	_coop_button.add_theme_constant_override("icon_max_width", 36)
	_coop_button.pressed.connect(_open_coop)
	_play_button.get_parent().add_child(_coop_button)
	var info: Control = $UI/Root/Info
	info.offset_left = -450.0
	info.offset_right = 450.0


## "Испытание дня" and "Достижения": two buttons at the top left and their panels
## (scripts/daily_panel.gd, scripts/achievements_panel.gd). Offline they work as well.
func _build_extras() -> void:
	var row := VBoxContainer.new()
	row.name = "Extras"
	row.add_theme_constant_override("separation", 8)
	row.position = Vector2(16, 84)
	_ui_root.add_child(row)
	_ui_root.move_child(row, 0)  # below the dialogs
	_daily = DailyPanel.new()
	_daily.online = Online
	_ui_root.add_child(_daily)
	_daily.start_requested.connect(_start_daily)
	_achievements = AchievementsPanel.new()
	_ui_root.add_child(_achievements)
	var daily_button := _extra_button(tr("DAILY_BUTTON"), DAILY_ICON, 250)
	daily_button.name = "DailyButton"
	daily_button.pressed.connect(_daily.open)
	row.add_child(daily_button)
	var ach_button := _extra_button(tr("ACH_BUTTON"), ACHIEVEMENTS_ICON, 84)
	ach_button.name = "AchievementsButton"
	ach_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ach_button.tooltip_text = tr("ACH_BUTTON")
	ach_button.text = ""
	ach_button.pressed.connect(_achievements.open)
	row.add_child(ach_button)


func _extra_button(text: String, icon: Texture2D, width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.icon = icon
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(width, 84)
	button.add_theme_constant_override("icon_max_width", 44)
	button.theme_type_variation = &"SecondaryButton"
	return button


func _start_daily(day: String) -> void:
	DailyRun.select(day)
	get_tree().change_scene_to_file(GAME_SCENE)


func _open_coop() -> void:
	LevelCatalog.selected_id = _selected
	LevelCatalog.endless = false
	get_tree().change_scene_to_file(COOP_SCENE)


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
		star.texture = STAR_ICON if i < earned else STAR_EMPTY_ICON
		star.custom_minimum_size = Vector2(size, size)
		star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(star)
	return row


func _select(id: int) -> void:
	_selected = id
	LevelPrefetch.request(id)  # the models load on a worker thread while the card is read
	var level: Dictionary = LevelCatalog.get_level(id)
	_name_label.text = "%d. %s" % [id, tr(level["name"])]
	_subtitle_label.text = tr(level["subtitle"])
	for child in _level_stars.get_children():
		child.queue_free()
	_level_stars.add_child(_star_row(LevelCatalog.stars(id), 34))
	var won: bool = LevelCatalog.is_completed(id)
	_endless_button.visible = won
	var record: int = LevelCatalog.endless_record(id)
	if not won:
		_record_label.text = tr("MAP_NO_ENDLESS")
	else:
		_record_label.text = (
			tr("MAP_ENDLESS_RECORD") % [record, Perks.endless_stars(id), Perks.ENDLESS_MAX_STARS]
		)
	for i in _site_buttons.size():
		var chosen: bool = _site_ids[i] == id
		_site_buttons[i].modulate = Color(1.12, 1.08, 0.92) if chosen else Color.WHITE
		_site_buttons[i].pivot_offset = _site_buttons[i].custom_minimum_size * 0.5
		_site_buttons[i].scale = Vector2(1.16, 1.16) if chosen else Vector2.ONE


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
	_free_label.text = tr("MAP_FREE_STARS") % Perks.free_stars()
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
	title.text = tr(perk.display_name)
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_font_size_override("font_size", 23)
	texts.add_child(title)
	var level_label := Label.new()
	level_label.text = tr("MAP_PERK_LEVEL") % [level, perk.max_level()]
	level_label.add_theme_font_size_override("font_size", 16)
	texts.add_child(level_label)
	var effect := Label.new()
	var now: String = perk.format_value(level) if level > 0 else tr("MAP_PERK_NONE")
	effect.text = tr(perk.description) % now
	if level < perk.max_level():
		effect.text += " → " + perk.format_value(level + 1)
	effect.add_theme_font_size_override("font_size", 17)
	box.add_child(effect)
	var buy := Button.new()
	buy.focus_mode = Control.FOCUS_NONE
	buy.custom_minimum_size = Vector2(0, 84)
	buy.add_theme_font_size_override("font_size", 20)
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
		_build_records_panel()
	_records_title.text = (
		tr("MAP_RECORDS_TITLE") % tr(str(LevelCatalog.get_level(_selected)["name"]))
	)
	_records_status.text = tr("MAP_LOADING")
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
	var name_label := Label.new()
	name_label.text = tr("MAP_YOUR_NAME") % Online.player_name()
	box.add_child(name_label)
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
		[tr("MAP_TO_CLOUD"), Online.cloud_save, true],
		[tr("MAP_FROM_CLOUD"), Online.cloud_load, true],
		[tr("MAP_CLOSE"), _records.hide, false]
	]:
		var button := Button.new()
		button.text = spec[0]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(180, 84)
		if spec[2]:
			button.theme_type_variation = &"SecondaryButton"
		button.pressed.connect(spec[1])
		buttons.add_child(button)


func _on_leaderboard_loaded(level_id: int, entries: Array) -> void:
	if _records == null or level_id != _selected:
		return
	for child in _records_list.get_children():
		child.queue_free()
	_records_status.text = ("" if not entries.is_empty() else tr("MAP_NO_RECORDS"))
	for i in entries.size():
		var row := Label.new()
		row.text = tr("MAP_RECORD_ROW") % [i + 1, entries[i]["name"], entries[i]["wave"]]
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


## Profile button, sync status line and the account panel (scripts/account_panel.gd).
func _build_account_ui() -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(84, 84)
	button.focus_mode = Control.FOCUS_NONE
	button.icon = PROFILE_ICON
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", 48)
	button.tooltip_text = tr("MAP_PROFILE")
	button.pressed.connect(func() -> void: _account.open())
	_sound_button.add_sibling(button)
	_build_settings_ui()
	_sync_label = Label.new()
	_sync_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_sync_label.offset_left = -520.0
	_sync_label.offset_right = -24.0
	_sync_label.offset_top = 78.0
	_sync_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_sync_label.add_theme_font_size_override("font_size", 18)
	_sync_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(_sync_label)
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
	if Online.is_configured():
		Online.sync_now()  # pushes progress made in the level


## Gear button next to the sound button and the settings dialog.
func _build_settings_ui() -> void:
	var gear := Button.new()
	gear.name = "SettingsButton"
	gear.custom_minimum_size = Vector2(64, 60)
	gear.focus_mode = Control.FOCUS_NONE
	gear.icon = GEAR_ICON
	gear.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gear.add_theme_constant_override("icon_max_width", 52)
	gear.tooltip_text = tr("SET_TOOLTIP")
	_sound_button.add_sibling(gear)
	_settings = SettingsPanel.new()
	_ui_root.add_child(_settings)
	gear.pressed.connect(_settings.open)
	_settings.closed.connect(_update_sound_icon)
	# Texts built in code are cached: rebuild the map in the new language.
	_settings.language_changed.connect(func() -> void: get_tree().reload_current_scene())


## Shown only when something is not saved to the cloud (or the name is taken).
func _on_sync_state(state: String) -> void:
	var conflict: bool = bool(PlayerProfile.local()["nicknameConflict"])
	_sync_label.visible = conflict or state in ["pending", "offline", "session_lost", "newer"]
	_sync_label.text = (tr("MAP_NAME_CONFLICT") if conflict else Online.state_text(state))
	_sync_label.add_theme_color_override(
		"font_color", Color(1.0, 0.62, 0.55) if conflict else Color(0.82, 0.86, 0.95)
	)


func _on_rename_requested() -> void:
	Onboarding.rename_mode = true
	get_tree().change_scene_to_file(Onboarding.NICKNAME_SCENE)


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

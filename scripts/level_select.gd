extends Node3D
## Start screen: a 3D island map with one button per level (locked levels
## show a lock, earned stars sit under each button), the star counter, the
## treasury where stars buy permanent perks, and the selected level's card
## with "Play" (campaign, on Normal / Hard / Nightmare) and the Record Run (free mode, every
## wave harder). A big Record Run button sits beside the daily challenge.

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
const TROPHY_ICON: Texture2D = preload("res://ui/icons/trophy.png")
const GOLD := Color(1.0, 0.88, 0.45)
## Width of the left column (daily challenge, record run, achievements, co-op).
const EXTRAS_WIDTH := 264.0
## Tint of the difficulty crown: Hard, Nightmare.
const CROWN_COLORS: Array[Color] = [Color.WHITE, Color(1.0, 0.62, 0.25), Color(0.8, 0.45, 1.0)]

## Seconds the map waits before it starts loading the selected level's models.

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
var _reminder: AccountReminder = null
var _coop_button: Button = null
var _daily: DailyPanel = null
var _achievements: AchievementsPanel = null
## Campaign difficulty picked for the next battle (0 Normal, 1 Hard, 2 Nightmare).
var _difficulty: int = 0
var _diff_buttons: Array[Button] = []
var _diff_info: Label = null
var _crown_icon: TextureRect = null
var _record_button: Button = null
var _hero: TextureRect = null

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
	LevelCatalog.difficulty = 0
	LevelCatalog.tutorial = false
	LevelCatalog.daily_key = ""
	SafeArea.attach(_ui_root)
	_camera.h_offset = -1.6  # island right of the left button column
	_build_sites()
	_build_account_ui()
	_play_button.pressed.connect(_start.bind(false))
	_endless_button.pressed.connect(_start.bind(true))
	_build_difficulty_row()
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
	if LevelCatalog.open_records and Online.is_configured():
		_open_records()  # back from the end screen of a Record Run
	LevelCatalog.open_records = false


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
	_coop_button = _extra_button(tr("COOP_BUTTON"), PROFILE_ICON, EXTRAS_WIDTH)
	_coop_button.name = "CoopButton"
	_coop_button.add_theme_constant_override("icon_max_width", 36)
	_coop_button.pressed.connect(_open_coop)


## "Испытание дня" and "Достижения": two buttons at the top left and their panels
## (scripts/daily_panel.gd, scripts/achievements_panel.gd). Offline they work as well.
func _build_extras() -> void:
	var row := VBoxContainer.new()
	row.name = "Extras"
	row.add_theme_constant_override("separation", 8)
	row.position = Vector2(16, 88)
	_ui_root.add_child(row)
	_ui_root.move_child(row, 0)  # below the dialogs
	_daily = DailyPanel.new()
	_daily.online = Online
	_ui_root.add_child(_daily)
	_daily.start_requested.connect(_start_daily)
	_achievements = AchievementsPanel.new()
	_ui_root.add_child(_achievements)
	var daily_button := _extra_button(tr("DAILY_BUTTON"), DAILY_ICON, EXTRAS_WIDTH)
	daily_button.name = "DailyButton"
	daily_button.pressed.connect(_daily.open)
	row.add_child(daily_button)
	_record_button = _extra_button("", CASTLE_ICON, EXTRAS_WIDTH)
	_record_button.name = "RecordRunButton"
	_record_button.custom_minimum_size = Vector2(EXTRAS_WIDTH, 96)
	_record_button.theme_type_variation = &"GreenButton"  # a mode of its own; gold is "Play"
	_record_button.add_theme_font_size_override("font_size", 16)
	_record_button.add_theme_constant_override("icon_max_width", 32)
	_record_button.add_theme_constant_override("h_separation", 6)
	_record_button.pressed.connect(_start.bind(true))
	row.add_child(_record_button)
	var ach_button := _extra_button(tr("ACH_BUTTON"), ACHIEVEMENTS_ICON, EXTRAS_WIDTH)
	ach_button.name = "AchievementsButton"
	ach_button.tooltip_text = tr("ACH_BUTTON")
	ach_button.pressed.connect(_achievements.open)
	row.add_child(ach_button)
	if _coop_button != null:
		row.add_child(_coop_button)


func _extra_button(text: String, icon: Texture2D, width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.icon = icon
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(width, 84)
	button.add_theme_constant_override("icon_max_width", 36)
	button.add_theme_font_size_override("font_size", 20)
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
		button.theme_type_variation = &"SecondaryButton"
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
			if LevelCatalog.crown(id) > 0:
				var badge := _crown_texture(LevelCatalog.crown(id), 30)
				badge.position = Vector2(56, -10)
				button.add_child(badge)
		_site_layer.add_child(button)
		var number := Label.new()
		number.text = str(id)
		number.theme_type_variation = &"NumberLabel"
		number.add_theme_font_size_override("font_size", 22)
		number.position = Vector2(8, 2)
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
	var level: Dictionary = LevelCatalog.get_level(id)
	_name_label.text = "%d. %s" % [id, tr(level["name"])]
	_subtitle_label.text = tr(level["subtitle"])
	for child in _level_stars.get_children():
		child.queue_free()
	_level_stars.add_child(_star_row(LevelCatalog.stars(id), 44))
	var biome_path: String = "res://ui/biomes/%s.png" % str(level.get("biome", "meadow"))
	_hero.texture = load(biome_path) if ResourceLoader.exists(biome_path) else null
	var crown: int = LevelCatalog.crown(id)
	_crown_icon.visible = crown > 0
	if crown > 0:
		_crown_icon.modulate = CROWN_COLORS[crown]
		_crown_icon.tooltip_text = tr("MAP_CROWN") % tr(str(Balance.difficulty(crown)["name"]))
	var record: int = LevelCatalog.endless_record(id)
	_record_label.text = (tr("MAP_RECORD_BEST") % record if record > 0 else tr("MAP_RECORD_NONE"))
	_update_record_button(id, record)
	if not LevelCatalog.is_difficulty_open(id, _difficulty):
		_difficulty = 0
	_refresh_difficulty(id)
	for i in _site_buttons.size():
		var chosen: bool = _site_ids[i] == id
		if not _site_buttons[i].disabled:
			var done: bool = LevelCatalog.stars(_site_ids[i]) > 0
			_site_buttons[i].theme_type_variation = (
				&"" if chosen else (&"GreenButton" if done else &"SecondaryButton")
			)
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
	var now: String = perk.format_value(level) if level > 0 else tr("MAP_PERK_NONE")
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
	_records_title = UiKit.ribbon("")
	box.add_child(_records_title)
	var name_label := Label.new()
	name_label.text = tr("MAP_YOUR_NAME") % Online.player_name()
	box.add_child(name_label)
	_records_list = VBoxContainer.new()
	_records_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_records_list)
	_records_status = Label.new()
	_records_status.theme_type_variation = &"CaptionLabel"
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
		row.add_theme_font_size_override("font_size", 19)
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
	button.theme_type_variation = &"SecondaryButton"
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
	_sync_label.offset_top = 104.0
	_sync_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_sync_label.theme_type_variation = &"CaptionLabel"
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
	_build_reminder()
	if Online.is_configured():
		Online.sync_now()  # pushes progress made in the level


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


## Gear button next to the sound button and the settings dialog.
func _build_settings_ui() -> void:
	var gear := Button.new()
	gear.name = "SettingsButton"
	gear.custom_minimum_size = Vector2(84, 84)
	gear.focus_mode = Control.FOCUS_NONE
	gear.theme_type_variation = &"SecondaryButton"
	gear.icon = GEAR_ICON
	gear.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gear.add_theme_constant_override("icon_max_width", 48)
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
	var behind: bool = state in ["pending", "offline", "session_lost", "newer"]
	if state == "offline" and not PlayerProfile.is_pending():
		behind = false  # offline but everything is saved: nothing to nag about on the map
	_sync_label.visible = conflict or behind
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
	LevelCatalog.difficulty = 0 if endless else _difficulty
	_play_button.disabled = true
	_endless_button.disabled = true
	_record_button.disabled = true
	get_tree().change_scene_to_file(GAME_SCENE)


## The Record Run button on the map: the selected level and its best result.
func _update_record_button(_id: int, record: int) -> void:
	var sub: String = tr("MAP_RECORD_BTN_SUB") % record if record > 0 else tr("MAP_RECORD_BTN_NEW")
	_record_button.text = tr("MAP_RECORD_RUN") + "\n" + sub


## Difficulty row of the level card: three buttons (a locked one shows a lock) and the line
## with what the picked difficulty changes. Built in code, filled by _refresh_difficulty().
func _build_difficulty_row() -> void:
	var info_panel: Control = $UI/Root/Info
	info_panel.offset_top = -40.0
	info_panel.offset_left = -520.0
	info_panel.offset_right = 520.0
	info_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var content: VBoxContainer = _play_button.get_parent().get_parent()
	var buttons: Control = _play_button.get_parent()
	var results: Control = _level_stars.get_parent()
	_play_button.custom_minimum_size = Vector2(248, 84)
	_endless_button.custom_minimum_size = Vector2(248, 84)
	_endless_button.theme_type_variation = &"SecondaryButton"
	_endless_button.icon = null
	_endless_button.text = tr("MAP_RECORD_RUN")
	_endless_button.tooltip_text = tr("MAP_RECORD_SUB")
	_endless_button.visible = true
	# Three columns: emblem of the biome | name, stars, record, difficulty | Play, Record Run.
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 24)
	content.add_child(main)
	_hero = TextureRect.new()
	_hero.custom_minimum_size = Vector2(176, 176)
	_hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hero.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	main.add_child(_hero)
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 6)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(mid)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_name_label.reparent(mid, false)
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_label.custom_minimum_size.x = 470.0
	_subtitle_label.reparent(mid, false)
	results.reparent(mid, false)
	var trophy := TextureRect.new()
	trophy.texture = TROPHY_ICON
	trophy.custom_minimum_size = Vector2(32, 32)
	trophy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	trophy.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	results.add_child(trophy)
	results.move_child(trophy, 1)
	_record_label.theme_type_variation = &"HeadingLabel"
	results.add_theme_constant_override("separation", 12)
	results.alignment = BoxContainer.ALIGNMENT_BEGIN
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	mid.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var group := ButtonGroup.new()
	for i in Balance.difficulty_count():
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(132, 56)
		button.theme_type_variation = &"ToggleButton"
		button.text = tr(str(Balance.difficulty(i)["name"]))
		button.add_theme_font_size_override("font_size", 18)
		button.add_theme_constant_override("icon_max_width", 22)
		button.add_theme_constant_override("h_separation", 4)
		button.pressed.connect(_on_difficulty_pressed.bind(i))
		row.add_child(button)
		_diff_buttons.append(button)
	_diff_info = Label.new()
	_diff_info.theme_type_variation = &"CaptionLabel"
	_diff_info.add_theme_font_size_override("font_size", 14)
	box.add_child(_diff_info)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 8)
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	main.add_child(side)
	_play_button.reparent(side, false)
	_endless_button.reparent(side, false)
	buttons.queue_free()
	_crown_icon = _crown_texture(1, 34)
	_crown_icon.mouse_filter = Control.MOUSE_FILTER_PASS
	results.add_child(_crown_icon)
	results.move_child(_crown_icon, 2)


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

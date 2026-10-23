class_name CampPanel
extends Control
## Camp dialog (Stage B of Retention v2).
## Displays production rate, accumulation cap, pending coins, and allows the player
## to collect accumulated coins or upgrade camp level.

signal closed
signal collected(amount: int)
signal upgraded(new_level: int)

const COIN_ICON: Texture2D = preload("res://ui/icons/coin.png")
const GOLD := Color(0.98, 0.8, 0.4)
const SOFT_COLOR := Color(0.82, 0.86, 0.95)
const OK_COLOR := Color(0.62, 0.95, 0.42)
const ALERT_COLOR := Color(1.0, 0.6, 0.3)
const BUTTON_HEIGHT := 72.0

## Overridable in tests.
var now_unix: int = 0

var _collect_button: Button = null
var _upgrade_button: Button = null
var _pending_label: Label = null
var _balance_label: Label = null
var _progress_bar: ProgressBar = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()


func open() -> void:
	if now_unix <= 0:
		now_unix = int(Time.get_unix_time_from_system())
	_build()
	show()


func close() -> void:
	if visible:
		hide()
		closed.emit()


func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var frame := DialogFrame.attach(self, 800.0, 0.7)
	var box := frame.body
	box.add_theme_constant_override("separation", 12)

	var p: Dictionary = PlayerProfile.local()
	var camp: Dictionary = p["camp"]
	var level: int = int(camp.get("level", 1))
	var coins: int = int(camp.get("coins", 0))
	var rate: int = Camp.rate_for_level(level)
	var cap_h: int = Camp.cap_hours_for_level(level)
	var cap_coins: int = cap_h * rate
	var pending: int = Camp.pending_coins(camp, now_unix)

	# Header: Title & Level
	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 10)
	header.add_child(_label(tr("CAMP_TITLE"), 32, GOLD, true))
	var lvl_pill := PanelContainer.new()
	lvl_pill.theme_type_variation = &"HudChip"
	var lvl_lbl := _label(tr("CAMP_LEVEL") % level, 18, Color.WHITE, true)
	lvl_pill.add_child(lvl_lbl)
	header.add_child(lvl_pill)
	box.add_child(header)

	# Balance chip
	var bal_row := HBoxContainer.new()
	bal_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bal_row.add_theme_constant_override("separation", 8)
	var coin_ico := TextureRect.new()
	coin_ico.texture = COIN_ICON
	coin_ico.custom_minimum_size = Vector2(28, 28)
	coin_ico.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_ico.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bal_row.add_child(coin_ico)
	_balance_label = _label(tr("COINS_NAME") + ": %d" % coins, 22, Color.WHITE, true)
	_balance_label.name = "BalanceLabel"
	bal_row.add_child(_balance_label)
	box.add_child(bal_row)

	# Stats card (Rate + Cap)
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	var card_v := VBoxContainer.new()
	card_v.add_theme_constant_override("separation", 6)
	card.add_child(card_v)

	var stats_row := HBoxContainer.new()
	stats_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_row.add_theme_constant_override("separation", 24)
	stats_row.add_child(_label(tr("CAMP_RATE") % rate, 18, SOFT_COLOR, true))
	stats_row.add_child(_label(tr("CAMP_CAP") % cap_h, 18, SOFT_COLOR, true))
	card_v.add_child(stats_row)

	# Accumulated display
	_pending_label = _label(
		tr("CAMP_ACCUMULATED") % [pending, cap_coins],
		22,
		GOLD if (pending >= cap_coins and cap_coins > 0) else Color.WHITE,
		true
	)
	_pending_label.name = "PendingLabel"
	card_v.add_child(_pending_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.name = "ProgressBar"
	_progress_bar.custom_minimum_size = Vector2(0, 24)
	_progress_bar.max_value = maxi(cap_coins, 1)
	_progress_bar.value = pending
	_progress_bar.show_percentage = false
	card_v.add_child(_progress_bar)

	if pending >= cap_coins and cap_coins > 0:
		var full_warn := _label(tr("CAMP_FULL"), 18, ALERT_COLOR, true)
		full_warn.name = "FullWarning"
		card_v.add_child(full_warn)
	box.add_child(card)

	# Collect button
	_collect_button = Button.new()
	_collect_button.name = "CollectButton"
	_collect_button.text = tr("CAMP_COLLECT") + ((" (+%d 🪙)" % pending) if pending > 0 else "")
	_collect_button.disabled = pending <= 0
	_collect_button.focus_mode = Control.FOCUS_NONE
	_collect_button.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	_collect_button.theme_type_variation = &"PrimaryButton" if pending > 0 else &"SecondaryButton"
	_collect_button.add_theme_font_size_override("font_size", 22)
	_collect_button.pressed.connect(_on_collect_pressed)
	box.add_child(_collect_button)

	# Upgrade Section
	if level < Camp.MAX_LEVEL:
		var cost: int = Camp.upgrade_cost(level)
		var next_rate: int = Camp.rate_for_level(level + 1)
		var next_cap: int = Camp.cap_hours_for_level(level + 1)
		var up_box := VBoxContainer.new()
		up_box.add_theme_constant_override("separation", 6)
		var up_info := _label(
			tr("CAMP_UPGRADE_NEXT") % [level, level + 1, next_rate, next_cap], 16, SOFT_COLOR, true
		)
		up_box.add_child(up_info)

		_upgrade_button = Button.new()
		_upgrade_button.name = "UpgradeButton"
		_upgrade_button.text = tr("CAMP_UPGRADE") % cost
		_upgrade_button.disabled = coins < cost
		_upgrade_button.focus_mode = Control.FOCUS_NONE
		_upgrade_button.custom_minimum_size = Vector2(0, 64)
		_upgrade_button.theme_type_variation = &"SecondaryButton"
		_upgrade_button.add_theme_font_size_override("font_size", 20)
		_upgrade_button.pressed.connect(_on_upgrade_pressed)
		up_box.add_child(_upgrade_button)
		box.add_child(up_box)
	else:
		var max_lbl := _label(tr("CAMP_MAX_LEVEL"), 18, OK_COLOR, true)
		max_lbl.name = "MaxLevelLabel"
		box.add_child(max_lbl)

	# Close Button
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = tr("MAP_CLOSE")
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(0, 60)
	close_button.theme_type_variation = &"SecondaryButton"
	close_button.add_theme_font_size_override("font_size", 20)
	close_button.pressed.connect(close)
	box.add_child(close_button)


func _on_collect_pressed() -> void:
	var p: Dictionary = PlayerProfile.local()
	var res: Dictionary = Camp.collect(p["camp"], now_unix)
	if int(res["collected"]) > 0:
		PlayerProfile.save_local(p)
		collected.emit(int(res["collected"]))
		Toast.show_on(
			self, tr("CAMP_COLLECTED") % int(res["collected"]), "+%d 🪙" % int(res["collected"])
		)
		_build()


func _on_upgrade_pressed() -> void:
	var p: Dictionary = PlayerProfile.local()
	var ok: bool = Camp.upgrade(p["camp"])
	if ok:
		PlayerProfile.save_local(p)
		var new_lvl: int = int(p["camp"].get("level", 1))
		upgraded.emit(new_lvl)
		Toast.show_on(self, tr("CAMP_UPGRADED") % new_lvl, tr("CAMP_LEVEL") % new_lvl)
		_build()


func _label(text: String, size: int, color: Color, center: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

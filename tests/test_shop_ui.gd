extends SceneTree
## The shop screen and the map hooks: tabs, cards, selection, the buy flow with its
## confirmation and rollback when gems are short, worn state, the gem chip, the Shop
## button and the streak panel on the map, button sizes (>= 84 px).
## godot --headless --path . --script res://tests/test_shop_ui.gd

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_shop_ui.cfg"
	GameSettings.config_path = "user://test_shop_ui_settings.cfg"
	LevelCatalog.erase_all()
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	GameSettings.set_language("ru")
	await _check_shop()
	await _check_map()
	LevelCatalog.erase_all()
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _give(amount: int, key: String) -> void:
	var p: Dictionary = PlayerProfile.local()
	Wallet.claim(p["wallet"], key, amount)
	PlayerProfile.save_local(p)


func _check_shop() -> void:
	var shop := (load("res://scenes/shop.tscn") as PackedScene).instantiate() as ShopScreen
	shop.auto_leave = false
	root.add_child(shop)
	await _frames(3)
	var tabs: HBoxContainer = shop.find_child("Tabs", true, false) as HBoxContainer
	check(
		tabs != null and tabs.get_child_count() == Cosmetics.categories().size(),
		"a tab per category"
	)
	for tab in tabs.get_children():
		check((tab as Button).custom_minimum_size.y >= 84.0, "tab %s is >= 84 px" % tab.name)
	var grid: GridContainer = shop.find_child("Grid", true, false) as GridContainer
	check(grid.get_child_count() == Cosmetics.in_category("hero").size(), "a card per hero skin")
	var action: Button = shop.find_child("ActionButton", true, false) as Button
	check(action.custom_minimum_size.y >= 84.0, "the action button is >= 84 px")
	check(
		(shop.find_child("BackButton", true, false) as Button).custom_minimum_size.y >= 84.0,
		"back is >= 84 px"
	)
	var first: String = shop.selected_id()
	var price: int = int(Cosmetics.get_item(first)["price"])
	check(
		action.disabled and action.text.contains(str(price)),
		"no gems: the button is disabled and says how many are missing (%s)" % action.text
	)
	# A tap on a card selects it.
	var other: String = str(Cosmetics.in_category("hero")[2]["id"])
	(
		(
			(shop.find_child("Card_" + other, true, false) as Control).find_child(
				"Tap", true, false
			)
			as Button
		)
		. pressed
		. emit()
	)
	check(shop.selected_id() == other, "tap selects a card")
	(shop.find_child("Tab_flag", true, false) as Button).pressed.emit()
	check(
		grid.get_child_count() == Cosmetics.in_category("flag").size(),
		"the flag tab lists the banners"
	)
	# Funds: buying without them is refused, nothing changes (rollback).
	var flag: String = str(Cosmetics.in_category("flag")[0]["id"])
	shop.select_item(flag)
	shop.press_action()
	var confirm: Control = shop.find_child("Confirm", true, false) as Control
	check(not confirm.visible, "no confirmation when the button is disabled")
	var refused: Dictionary = shop.confirm_buy()
	check(
		not refused["ok"] and Economy.balance() == 0 and Shop.state(flag) == Shop.State.AVAILABLE,
		"no funds: the purchase rolls back"
	)
	check(
		(shop.find_child("Message", true, false) as Label).text == tr("SHOP_NO_FUNDS"),
		"and says so"
	)
	# With funds: confirm, buy, worn.
	var flag_price: int = int(Cosmetics.get_item(flag)["price"])
	_give(flag_price + 30, "test_gems")
	shop.select_category("flag")
	shop.select_item(flag)
	check(
		not action.disabled and action.text == tr("SHOP_BUY") % flag_price,
		"enough gems: Buy %d" % flag_price
	)
	shop.press_action()
	check(confirm.visible, "a purchase is confirmed first")
	check(
		(shop.find_child("ConfirmText", true, false) as Label).text.contains(str(flag_price)),
		"the confirmation names the price"
	)
	check(
		(shop.find_child("ConfirmYes", true, false) as Button).custom_minimum_size.y >= 84.0,
		"confirm buttons >= 84 px"
	)
	(shop.find_child("ConfirmNo", true, false) as Button).pressed.emit()
	check(not confirm.visible and Shop.state(flag) == Shop.State.AVAILABLE, "cancel buys nothing")
	shop.press_action()
	var bought: Dictionary = shop.confirm_buy()
	check(bought["ok"] and Economy.balance() == 30, "bought, 30 gems left")
	check(
		Shop.state(flag) == Shop.State.EQUIPPED and action.text == tr("SHOP_TAKE_OFF"),
		"worn at once, the button says Take off"
	)
	await create_timer(1.0).timeout  # the animation runs out (real time)
	check((shop.find_child("Balance", true, false) as Label).text == "30", "the balance shows 30")
	shop.press_action()
	check(
		Shop.state(flag) == Shop.State.OWNED and action.text == tr("SHOP_EQUIP"), "taken off: Wear"
	)
	shop.press_action()
	check(Shop.state(flag) == Shop.State.EQUIPPED, "worn again")
	check(get_nodes_in_group(Toast.GROUP).size() >= 1, "a toast confirmed the purchase")
	shop.queue_free()
	await _frames(2)


func _check_map() -> void:
	LevelCatalog.erase_all()
	var map := (load("res://scenes/level_select.tscn") as PackedScene).instantiate()
	root.add_child(map)
	await _frames(4)
	var chip: Node = map.find_child("GemsChip", true, false)
	check(chip != null, "the map shows the gem chip")
	var shop_button: Button = map.find_child("ShopButton", true, false) as Button
	check(
		shop_button != null and shop_button.custom_minimum_size.y >= 84.0,
		"the Shop button is >= 84 px"
	)
	var streak_button: Button = map.find_child("StreakButton", true, false) as Button
	check(
		streak_button != null and streak_button.custom_minimum_size.y >= 84.0,
		"the streak plaque is >= 84 px"
	)
	check(
		streak_button.text == tr("STREAK_BUTTON") % 1,
		"a first visit: streak 1 (%s)" % streak_button.text
	)
	check(
		(
			int((map.find_child("GemsHud", true, false) as GemsHud).visit["gems"])
			== Streak.reward_for(1)
		),
		"the visit paid the day 1 reward"
	)
	check(
		((chip.find_child("Label", true, false)) as Label).text == str(Streak.reward_for(1)),
		"the chip shows the balance"
	)
	check(get_nodes_in_group(Toast.GROUP).size() >= 1, "a toast announced the day's reward")
	streak_button.pressed.emit()
	await _frames(2)
	var panel: StreakPanel = map.find_child("StreakPanel", true, false) as StreakPanel
	check(panel.visible, "the streak panel opens")
	check(panel.find_child("Days", true, false).get_child_count() == 7, "seven reward days")
	check(
		(
			panel.find_child("Quest0", true, false) != null
			and panel.find_child("Quest2", true, false) != null
		),
		"three quests"
	)
	check(panel.find_child("Day1", true, false) != null, "day 1 is lit")
	(panel.find_child("CloseButton", true, false) as Button).pressed.emit()
	check(not panel.visible, "close")
	map.queue_free()
	await _frames(2)

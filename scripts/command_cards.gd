class_name CommandCards
extends RefCounted
## Contents of the HUD command card: the build / upgrade card of a slot, the forge
## and trading with a villager.

const COIN_ICON: Texture2D = preload("res://ui/icons/coin.png")
const UPGRADE_ICON: Texture2D = preload("res://ui/icons/upgrade.png")
const TARGET_ICON: Texture2D = preload("res://ui/icons/flag.png")
const SELL_ICON: Texture2D = preload("res://ui/icons/sell.png")
const SWORD_ICON: Texture2D = preload("res://ui/icons/sword.png")
const HEART_ICON: Texture2D = preload("res://ui/icons/heart.png")
const CANCEL_ICON: Texture2D = preload("res://ui/icons/cancel.png")
const VILLAGER_ICON: Texture2D = preload("res://ui/icons/villager.png")
const WOOD_ICON: Texture2D = preload("res://ui/icons/wood.png")
const SHOP_ICON: Texture2D = preload("res://ui/icons/shop.png")
const AXE_ICON: Texture2D = preload("res://ui/icons/axe.png")


static func _t(key: String) -> String:
	return TranslationServer.translate(key)


## Card of the selected slot: build buttons on a free one, upgrade / priority / sell
## on a tower. `walking` = the knight is on his way to carry out a pressed command.
static func for_slot(slot: TowerSlot, build_manager: BuildManager, walking: bool) -> Dictionary:
	var info := {}
	var buttons: Array[Dictionary] = []
	var tower_types: Array[TowerData] = build_manager.tower_types
	if slot.is_free():
		info["title"] = _t("CARD_PLOT")
		var names: PackedStringArray = []
		for data: TowerData in tower_types:
			names.append(_t(data.display_name))
		info["stats"] = " · ".join(names)
		var short := true
		for i in tower_types.size():
			var data: TowerData = tower_types[i]
			var ok: bool = build_manager.can_build(slot, data)
			short = short and not ok
			(
				buttons
				. append(
					{
						"id": StringName("build_%d" % i),
						"icon": data.icon,
						"caption": _t(data.display_name),
						"gold": data.cost_gold,
						"wood": data.cost_wood,
						"enabled": ok,
						"tooltip":
						(
							_t("CARD_TOWER_TIP")
							% [_t(data.display_name), i + 1, _t(data.role), data.stats_text(0)]
						),
					}
				)
			)
		info["hint"] = _t("CARD_NEED_BOTH") if short else ""
	else:
		var data: TowerData = slot.tower.data
		var level_index: int = slot.tower.level
		var cost: Vector2i = data.upgrade_cost(level_index)
		info["title"] = (
			_t("CARD_TOWER_TITLE") % [_t(data.display_name), level_index + 1, data.max_level() + 1]
		)
		info["stats"] = data.stats_text(level_index)
		var upgrade := {
			"id": &"upgrade",
			"icon": UPGRADE_ICON,
			"caption": _t("CARD_UPGRADE_NAME"),
			"enabled": build_manager.can_upgrade(slot),
			"tooltip": _t("CARD_UPGRADE_TIP")
		}
		if cost.x < 0:
			upgrade["label"] = _t("CARD_MAX")
		else:
			upgrade["gold"] = cost.x
			upgrade["wood"] = cost.y
			upgrade["tooltip"] = _t("CARD_UPGRADE_TIP_NEXT") % data.stats_text(level_index + 1)
			if not upgrade["enabled"]:
				info["hint"] = _t("CARD_NEED_BOTH")
		buttons.append(upgrade)
		var tip: String = TowerData.priority_tooltip(slot.tower.priority)
		var label: String = TowerData.priority_name(slot.tower.priority)
		var spec := {"id": &"priority", "icon": TARGET_ICON, "label": label, "tooltip": tip}
		spec["enabled"] = true
		buttons.append(spec)
		var refund: Vector2i = data.sell_value(level_index)
		buttons.append(
			{
				"id": &"sell",
				"icon": COIN_ICON,
				"caption": _t("CARD_SELL_NAME"),
				"gold": refund.x,
				"wood": refund.y,
				"gain": true,
				"enabled": true,
				"tooltip": _t("CARD_SELL_TIP") % roundi(Balance.sell_refund() * 100.0)
			}
		)
	buttons.append(
		{
			"id": &"cancel",
			"icon": CANCEL_ICON,
			"label": "Esc",
			"enabled": true,
			"tooltip": _t("CARD_DESELECT_TIP")
		}
	)
	if walking:
		info["hint"] = _t("CARD_KNIGHT_WALKS")
	info["buttons"] = buttons
	return info


## Forge card: sword upgrade and castle repair.
static func forge(hero: Hero, game_state: GameState) -> Dictionary:
	var info := {"title": TranslationServer.translate("CARD_FORGE_TITLE")}
	var sword: Vector2i = hero.sword_upgrade_cost()
	var next_damage: String = ""
	if sword.x >= 0:
		var next_index: int = mini(hero.sword_level + 1, hero.sword_damage_levels.size() - 1)
		next_damage = (" → %d" % (hero.sword_damage_levels[next_index] * hero.damage_multiplier))
	info["stats"] = (
		TranslationServer.translate("CARD_FORGE_STATS")
		% [
			hero.attack_damage * hero.damage_multiplier,
			next_damage,
			game_state.lives,
			game_state.starting_lives
		]
	)
	var upgrade := {
		"id": &"sword",
		"icon": SWORD_ICON,
		"enabled": game_state.can_afford(sword),
		"tooltip": TranslationServer.translate("CARD_SWORD_TIP")
	}
	if sword.x < 0:
		upgrade["label"] = TranslationServer.translate("CARD_MAX")
	else:
		upgrade["gold"] = sword.x
		upgrade["wood"] = sword.y
	var repair := {
		"id": &"repair",
		"icon": HEART_ICON,
		"wood": game_state.repair_wood,
		"enabled": game_state.can_repair(),
		"tooltip": TranslationServer.translate("CARD_REPAIR_TIP") % game_state.repair_lives
	}
	info["buttons"] = [
		upgrade,
		repair,
		{
			"id": &"cancel",
			"icon": CANCEL_ICON,
			"label": "Esc",
			"enabled": true,
			"tooltip": TranslationServer.translate("CARD_CLOSE_TIP")
		}
	]
	return info


## Trade card of the villager `who`: sell wood (the price drops with every lot), buy wood
## (dearer, a few lots a battle) and hire him as a lumberjack. The last two exist only where
## Villagers.wood_economy is on (the campaign and co-op); elsewhere the card says so.
static func trade(villagers: Villagers, game_state: GameState, who: Villager = null) -> Dictionary:
	var lot: int = villagers.trade.wood_per_lot
	var lots: int = villagers.lots_affordable()
	var price: int = villagers.lot_price()
	var index: int = villagers.index_of(who) if who != null else -1
	var hired_here: bool = villagers.is_hired(index)
	var info := {
		"title": TranslationServer.translate("CARD_LUMBERJACK" if hired_here else "CARD_VILLAGER")
	}
	info["stats"] = (
		TranslationServer.translate("CARD_TRADE_STATS") % [lot, price, game_state.wood]
	)
	var buttons: Array[Dictionary] = [
		{
			"id": &"trade_lot",
			"icon": VILLAGER_ICON,
			"caption": TranslationServer.translate("CARD_SELL_NAME"),
			"gold": price,
			"gain": true,
			"enabled": lots > 0,
			"tooltip": TranslationServer.translate("CARD_TRADE_LOT_TIP") % [lot, price]
		},
		{
			"id": &"trade_all",
			"icon": SELL_ICON,
			"caption": TranslationServer.translate("CARD_ALL_NAME"),
			"gold": villagers.quote(lots),
			"gain": true,
			"enabled": lots > 0,
			"tooltip":
			TranslationServer.translate("CARD_TRADE_ALL_TIP") % [lots * lot, villagers.quote(lots)]
		},
	]
	if not villagers.wood_economy:
		info["hint"] = TranslationServer.translate("CARD_TRADE_NO_ECONOMY")
	else:
		buttons.append_array(_buy_and_hire(villagers, game_state, index))
		info["hint"] = (
			TranslationServer.translate("CARD_TRADE_ECONOMY")
			% [
				villagers.trade.buy_max_lots - villagers.buy_lots_left(),
				villagers.trade.buy_max_lots,
				villagers.hired_count(),
				villagers.trade.hire_max,
				villagers.trade.hire_wood_per_minute
			]
		)
	buttons.append(
		{
			"id": &"cancel",
			"icon": CANCEL_ICON,
			"label": "Esc",
			"enabled": true,
			"tooltip": TranslationServer.translate("CARD_CLOSE_TIP")
		}
	)
	info["buttons"] = buttons
	return info


## "Buy" buttons (one lot, as many as gold and the limit allow) and "Hire" for villager `index`.
static func _buy_and_hire(villagers: Villagers, game_state: GameState, index: int) -> Array:
	var trade: VillagerTrade = villagers.trade
	var lot: int = trade.wood_per_lot
	var left: int = villagers.buy_lots_left()
	var can: int = villagers.buy_lots_affordable()
	var bought: int = trade.buy_max_lots - left
	var buy_one := {
		"id": &"buy_lot",
		"icon": WOOD_ICON,
		"caption": TranslationServer.translate("CARD_BUY_NAME"),
		"enabled": can > 0,
		"tooltip":
		(
			TranslationServer.translate("CARD_BUY_LOT_TIP")
			% [lot, villagers.buy_price(), bought, trade.buy_max_lots]
		)
	}
	var buy_all := {
		"id": &"buy_all",
		"icon": SHOP_ICON,
		"caption": TranslationServer.translate("CARD_ALL_NAME"),
		"enabled": can > 0,
		"tooltip":
		(
			TranslationServer.translate("CARD_BUY_ALL_TIP")
			% [maxi(can, 1) * lot, villagers.buy_quote(maxi(can, 1))]
		)
	}
	if left <= 0:
		buy_one["label"] = "%d/%d" % [bought, trade.buy_max_lots]
		buy_all["label"] = buy_one["label"]
	else:
		buy_one["gold"] = villagers.buy_price()
		buy_all["gold"] = villagers.buy_quote(maxi(can, 1))
	var hire := {
		"id": &"hire",
		"icon": AXE_ICON,
		"caption": TranslationServer.translate("CARD_HIRE_NAME"),
		"enabled": false,
		"tooltip":
		(
			TranslationServer.translate("CARD_HIRE_TIP")
			% [trade.hire_gold, trade.hire_wood_per_minute, villagers.hired_count(), trade.hire_max]
		)
	}
	if villagers.is_hired(index):
		hire["label"] = TranslationServer.translate("CARD_HIRED")
	elif villagers.hired_count() >= trade.hire_max:
		hire["label"] = "%d/%d" % [villagers.hired_count(), trade.hire_max]
	else:
		hire["gold"] = trade.hire_gold
		hire["enabled"] = index >= 0 and game_state.gold >= trade.hire_gold
	return [buy_one, buy_all, hire]

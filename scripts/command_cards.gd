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
const CASTLE_ICON: Texture2D = preload("res://ui/icons/castle.png")
const HAMMER_ICON: Texture2D = preload("res://ui/icons/hammer.png")


static func _t(key: String) -> String:
	return TranslationServer.translate(key)


## Card of the selected slot: build buttons on a free one, upgrade / priority / sell
## on a tower. `walking` = the knight is on his way to carry out a pressed command.
static func for_slot(
	slot: TowerSlot, build_manager: BuildManager, walking: bool, near_villager: Villager = null
) -> Dictionary:
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
	if near_villager != null:
		(
			buttons
			. append(
				{
					"id": &"talk_villager",
					"icon": VILLAGER_ICON,
					"caption": _t("CARD_TALK_VILLAGER"),
					"enabled": true,
					"tooltip": _t("CARD_TALK_VILLAGER_TIP"),
				}
			)
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
	info["hint"] = castle_line(game_state)
	info["buttons"] = [
		upgrade,
		repair,
		castle_button(game_state),
		{
			"id": &"cancel",
			"icon": CANCEL_ICON,
			"label": "Esc",
			"enabled": true,
			"tooltip": TranslationServer.translate("CARD_CLOSE_TIP")
		}
	]
	return info


## What upgrade number `level` + 1 gives: "+2 lives, armor 1" (armor only if it grows).
static func castle_effect(level: int) -> String:
	var lives: int = CastleUpgrades.lives_bonus(level)
	var text: String = TranslationServer.translate("CARD_CASTLE_LIVES") % lives
	var armor: int = CastleUpgrades.armor_at(level + 1)
	if armor > CastleUpgrades.armor_at(level):
		text += ", " + TranslationServer.translate("CARD_CASTLE_ARMOR") % armor
	return text


## "Castle 2/4 - next: +3 lives, armor 1" (or "maximum").
static func castle_line(game_state: GameState) -> String:
	var level: int = game_state.castle_level
	var top: int = CastleUpgrades.max_level()
	if level >= top:
		return TranslationServer.translate("CARD_CASTLE_STATE_MAX") % [level, top]
	return TranslationServer.translate("CARD_CASTLE_STATE") % [level, top, castle_effect(level)]


## The forge's "Upgrade the castle" button: price, or "max" at the top level.
static func castle_button(game_state: GameState) -> Dictionary:
	var level: int = game_state.castle_level
	var cost: Vector2i = game_state.castle_upgrade_cost()
	var button := {
		"id": &"castle",
		"icon": CASTLE_ICON,
		"caption": TranslationServer.translate("CARD_CASTLE_NAME"),
		"enabled": game_state.can_upgrade_castle(),
	}
	if cost.x < 0:
		button["label"] = TranslationServer.translate("CARD_CASTLE_MAX")
		button["tooltip"] = castle_line(game_state)
	else:
		button["gold"] = cost.x
		button["wood"] = cost.y
		button["tooltip"] = TranslationServer.translate("CARD_CASTLE_TIP") % castle_effect(level)
	return button


## Trade card of the villager `who`: sell wood (the price drops with every lot), buy wood
## (dearer, a few lots a battle) and hire him as a lumberjack. The last two exist only where
## Villagers.wood_economy is on (campaign, co-op, daily); in the Record Run the card says why.
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


## Card of the Lumberjack Camp: trade wood (sell/buy) and hire lumberjacks.
static func lumberjack_camp(villagers: Villagers, game_state: GameState) -> Dictionary:
	if villagers == null or villagers.trade == null:
		return {}
	var lot: int = villagers.trade.wood_per_lot
	var lots: int = villagers.lots_affordable()
	var price: int = villagers.lot_price()
	var next_unhired: int = villagers.first_unhired_index()
	var title_str: String = _t("CARD_LUMBERJACK_CAMP")
	var info := {"title": title_str}
	var stats_template: String = _t("CARD_TRADE_STATS")
	info["stats"] = (stats_template % [lot, price, game_state.wood])
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
		buttons.append_array(_buy_and_hire(villagers, game_state, next_unhired))
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


## Card of the Mercenary Camp: hire allied knight fighters for defense.
static func mercenary_camp(camp: CampStructures.MercenaryCamp, game_state: GameState) -> Dictionary:
	var camp_title: String = _t("CARD_MERCENARY_CAMP")
	var info := {"title": camp_title}
	var hired_total: int = camp.hired_total if camp != null else 0
	var alive_count: int = camp.alive_count() if camp != null else 0
	var max_alive: int = camp.config.max_alive if camp != null else 0
	var cost: int = camp.hire_cost() if camp != null else 0
	var stats_tmpl: String = _t("CARD_MERCENARY_STATS")
	info["stats"] = stats_tmpl % [alive_count, max_alive, hired_total]
	var hint_str: String = _t("CARD_MERCENARY_HINT")
	if camp != null:
		hint_str = hint_str % [roundi(camp.config.max_health), roundi(camp.config.attack_damage)]
	info["hint"] = hint_str
	var tip_tmpl: String = _t("CARD_MERCENARY_TIP")
	var hire_button := {
		"id": &"hire_mercenary",
		"icon": SWORD_ICON,
		"caption": _t("CARD_HIRE_NAME"),
		"enabled": false,
		"tooltip": tip_tmpl % [cost, max_alive]
	}
	if camp != null and not camp.can_hire_more():
		hire_button["label"] = "%d/%d" % [alive_count, max_alive]
	else:
		hire_button["gold"] = cost
		hire_button["enabled"] = game_state.gold >= cost if game_state != null else false
	info["buttons"] = [
		hire_button,
		{
			"id": &"cancel",
			"icon": CANCEL_ICON,
			"label": "Esc",
			"enabled": true,
			"tooltip": _t("CARD_CLOSE_TIP")
		}
	]
	return info


## Card of the Workbench: choose one of the 4 towers to enter placement mode.
static func build_menu(build_manager: BuildManager, game_state: GameState) -> Dictionary:
	var info := {
		"title": _t("CARD_WORKBENCH"),
		"stats": _t("CARD_WORKBENCH_STATS"),
	}
	var buttons: Array[Dictionary] = []
	var tower_types: Array[TowerData] = build_manager.tower_types
	var any_affordable: bool = false
	for i in tower_types.size():
		var data: TowerData = tower_types[i]
		var can_afford: bool = (
			game_state != null and game_state.can_afford(Vector2i(data.cost_gold, data.cost_wood))
		)
		if can_afford:
			any_affordable = true
		(
			buttons
			. append(
				{
					"id": StringName("build_%d" % i),
					"icon": data.icon,
					"caption": _t(data.display_name),
					"gold": data.cost_gold,
					"wood": data.cost_wood,
					"enabled": can_afford,
					"tooltip":
					(
						_t("CARD_TOWER_TIP")
						% [_t(data.display_name), i + 1, _t(data.role), data.stats_text(0)]
					),
				}
			)
		)
	if not any_affordable:
		info["hint"] = _t("CARD_NEED_BOTH")
	(
		buttons
		. append(
			{
				"id": &"cancel",
				"icon": CANCEL_ICON,
				"label": "Esc",
				"enabled": true,
				"tooltip": _t("CARD_CLOSE_TIP"),
			}
		)
	)
	info["buttons"] = buttons
	return info


## Card shown during interactive tower placement mode (Warcraft style).
static func placement_mode(
	data: TowerData, is_valid: bool, can_afford: bool, hint_msg: String
) -> Dictionary:
	var info := {
		"title": _t(data.display_name),
		"stats":
		(
			"%s · %d %s, %d %s"
			% [_t(data.role), data.cost_gold, _t("HUD_GOLD"), data.cost_wood, _t("HUD_WOOD")]
		),
		"hint": hint_msg,
	}
	var buttons: Array[Dictionary] = [
		{
			"id": &"confirm_build",
			"icon": HAMMER_ICON,
			"caption": _t("CARD_CONFIRM_BUILD"),
			"gold": data.cost_gold,
			"wood": data.cost_wood,
			"enabled": is_valid and can_afford,
			"tooltip": _t("CARD_CONFIRM_BUILD_TIP"),
		},
		{
			"id": &"cancel",
			"icon": CANCEL_ICON,
			"label": "Esc",
			"enabled": true,
			"tooltip": _t("CARD_CLOSE_TIP"),
		}
	]
	info["buttons"] = buttons
	return info

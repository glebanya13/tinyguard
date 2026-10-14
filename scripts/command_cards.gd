class_name CommandCards
extends RefCounted
## Contents of the HUD command card for the forge and for trading with a
## villager (the build / upgrade card stays in main.gd).

const SELL_ICON: Texture2D = preload("res://ui/icons/sell.png")
const SWORD_ICON: Texture2D = preload("res://ui/icons/sword.png")
const HEART_ICON: Texture2D = preload("res://ui/icons/heart.png")
const CANCEL_ICON: Texture2D = preload("res://ui/icons/cancel.png")
const VILLAGER_ICON: Texture2D = preload("res://ui/icons/villager.png")


## Forge card: sword upgrade and castle repair.
static func forge(hero: Hero, game_state: GameState) -> Dictionary:
	var info := {"title": "Кузница"}
	var sword: Vector2i = hero.sword_upgrade_cost()
	var next_damage: String = ""
	if sword.x >= 0:
		var next_index: int = mini(hero.sword_level + 1, hero.sword_damage_levels.size() - 1)
		next_damage = (" → %d" % (hero.sword_damage_levels[next_index] * hero.damage_multiplier))
	info["stats"] = (
		"Меч %d%s · стены %d/%d"
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
		"tooltip": "Закалить меч (U)"
	}
	if sword.x < 0:
		upgrade["label"] = "макс."
	else:
		upgrade["gold"] = sword.x
		upgrade["wood"] = sword.y
	var repair := {
		"id": &"repair",
		"icon": HEART_ICON,
		"wood": game_state.repair_wood,
		"enabled": game_state.can_repair(),
		"tooltip": "Починить стены: +%d жизни" % game_state.repair_lives
	}
	info["buttons"] = [
		upgrade,
		repair,
		{
			"id": &"cancel",
			"icon": CANCEL_ICON,
			"label": "Esc",
			"enabled": true,
			"tooltip": "Закрыть (Esc)"
		}
	]
	return info


## Trade card: sell wood to the villager in lots, the price drops with every lot.
static func trade(villagers: Villagers, game_state: GameState) -> Dictionary:
	var lot: int = villagers.trade.wood_per_lot
	var lots: int = villagers.lots_affordable()
	var price: int = villagers.lot_price()
	var info := {"title": "Житель"}
	info["stats"] = (
		"Курс: %d дерева → %d золота · дерева у вас: %d" % [lot, price, game_state.wood]
	)
	info["hint"] = (
		"Чем больше продаёте, тем ниже цена"
		if lots > 0
		else "Не хватает дерева: житель берёт по %d" % lot
	)
	info["buttons"] = [
		{
			"id": &"trade_lot",
			"icon": VILLAGER_ICON,
			"gold": price,
			"gain": true,
			"enabled": lots > 0,
			"tooltip": "Продать %d дерева → +%d золота" % [lot, price]
		},
		{
			"id": &"trade_all",
			"icon": SELL_ICON,
			"gold": villagers.quote(lots),
			"gain": true,
			"enabled": lots > 0,
			"tooltip": "Продать всё: %d дерева → +%d золота" % [lots * lot, villagers.quote(lots)]
		},
		{
			"id": &"cancel",
			"icon": CANCEL_ICON,
			"label": "Esc",
			"enabled": true,
			"tooltip": "Закрыть (Esc)"
		}
	]
	return info

class_name Shop
extends RefCounted
## Buying and wearing cosmetics. The price always comes from the catalog
## (resources/shop.json), never from the caller. The wallet rules apply: no funds, no
## purchase; an item is bought once; only an owned item can be worn. Works offline; the
## wallet syncs with the profile like everything else. See docs/GAME_DESIGN.md.

enum State { AVAILABLE, OWNED, EQUIPPED }


static func state(id: String) -> State:
	var w: Dictionary = Wallet.local()
	if not Wallet.owns(w, id):
		return State.AVAILABLE
	var category: String = str(Cosmetics.get_item(id).get("category", ""))
	return State.EQUIPPED if Wallet.equipped(w, category) == id else State.OWNED


static func can_afford(id: String) -> bool:
	var item: Dictionary = Cosmetics.get_item(id)
	return not item.is_empty() and Economy.balance() >= int(item["price"])


## Buys `id`. Returns {"ok", "reason" ("" | "unknown" | "owned" | "funds"), "gems" left}.
## A bought item is worn at once (the shop shows it right away); that choice is free to undo.
static func buy(id: String) -> Dictionary:
	var item: Dictionary = Cosmetics.get_item(id)
	if item.is_empty():
		return {"ok": false, "reason": "unknown", "gems": Economy.balance()}
	var p: Dictionary = PlayerProfile.local()
	var w: Dictionary = p["wallet"]
	if Wallet.owns(w, id):
		return {"ok": false, "reason": "owned", "gems": Wallet.gems(w)}
	var now: int = int(Time.get_unix_time_from_system())
	if not Wallet.buy(w, id, int(item["price"]), now):
		return {"ok": false, "reason": "funds", "gems": Wallet.gems(w)}
	Wallet.equip(w, str(item["category"]), id)
	PlayerProfile.save_local(p)
	Cosmetics.refresh()
	return {"ok": true, "reason": "", "gems": Wallet.gems(w)}


## Wears an owned item. False if it is unknown or not owned.
static func equip(id: String) -> bool:
	var item: Dictionary = Cosmetics.get_item(id)
	if item.is_empty():
		return false
	var p: Dictionary = PlayerProfile.local()
	if not Wallet.equip(p["wallet"], str(item["category"]), id):
		return false
	PlayerProfile.save_local(p)
	Cosmetics.refresh()
	return true


## Back to the standard look in a slot.
static func unequip(category: String) -> void:
	var p: Dictionary = PlayerProfile.local()
	if Wallet.equip(p["wallet"], category, ""):
		PlayerProfile.save_local(p)
		Cosmetics.refresh()


## Items the player owns / does not own in a category, for the screen.
static func owned_count() -> int:
	var w: Dictionary = Wallet.local()
	var count: int = 0
	for item: Dictionary in Cosmetics.items():
		count += 1 if Wallet.owns(w, str(item["id"])) else 0
	return count

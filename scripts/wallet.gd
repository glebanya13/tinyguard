class_name Wallet
extends RefCounted
## The gem wallet: pure logic on one Dictionary plus its place in the save file. Gems
## are an in-game currency only (never sold). The balance is DERIVED, never stored as a
## number that can drift: gems = sum(claims) - sum(buys), so two devices that merge
## their wallets (key-wise max of every claim and purchase) can never pay a reward
## twice or lose a purchase. Cheating the wallet only hurts the cheater: gems buy
## cosmetics, nothing in the simulation, a record or the daily board depends on them
## (see docs/GAME_DESIGN.md, "Самоцветы").
##
## State (VERSION 1):
## {v, claims: {key: gems paid}, buys: {item id: price paid}, equipped: {slot: item id},
##  log: [{t: unix s, k: key, d: +-gems}] (the last operations, this device only)}
##
## A claim key names one reward ("lv1s2", "ach:hunter", "streak:2026-10-17"), so paying
## it again is a no-op (idempotent). Some keys are "raised" instead: they stand for a
## daily ceiling ("rp:2026-10-17" grows up to the cap). Keys that carry a date older than
## compact_after_days are folded into one "old:yyyy-mm" claim, so the wallet stays small.

const VERSION := 1
const SECTION := "wallet"
const DATA_PATH := "res://resources/economy.json"
const OLD_PREFIX := "old:"
const SECONDS_PER_DAY := 86400

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var json: JSON = load(DATA_PATH)
		_data = json.data
	return _data


static func limit(name: String) -> int:
	return int(data()["limits"][name])


static func empty() -> Dictionary:
	return {"v": VERSION, "claims": {}, "buys": {}, "equipped": {}, "log": []}


## A claim key / item id / slot: 1..48 characters of a-z 0-9 _ : - (also keeps the cloud
## text format "key=value;key=value" unambiguous).
static func is_valid_id(id: String) -> bool:
	if id.is_empty() or id.length() > 48:
		return false
	for i in id.length():
		var c: int = id.unicode_at(i)
		var ok: bool = (c >= 97 and c <= 122) or (c >= 48 and c <= 58) or c == 95 or c == 45  # a-z 0-9 :
		if not ok:
			return false
	return true


## Total of every reward paid so far (clamped).
static func earned(w: Dictionary) -> int:
	return mini(_sum(w["claims"]), limit("max_balance") * 4)


static func spent(w: Dictionary) -> int:
	return mini(_sum(w["buys"]), limit("max_balance") * 4)


## Gems that can be spent now (never below 0, never above max_balance).
static func gems(w: Dictionary) -> int:
	return clampi(earned(w) - spent(w), 0, limit("max_balance"))


static func has_claim(w: Dictionary, key: String) -> bool:
	return (w["claims"] as Dictionary).has(key)


## Pays `amount` gems under `key`, once. Returns the gems paid (0 when the key was
## already paid, the amount is not positive or the key is malformed).
static func claim(w: Dictionary, key: String, amount: int, now: int = 0) -> int:
	if amount <= 0 or not is_valid_id(key) or has_claim(w, key):
		return 0
	if (w["claims"] as Dictionary).size() >= limit("max_claims"):
		return 0
	var paid: int = mini(amount, limit("max_claim"))
	w["claims"][key] = paid
	_log(w, key, paid, now)
	return paid


## Grows the claim `key` by `amount` but never above `cap` (a daily ceiling).
## Returns the gems paid now (0 at the ceiling).
static func raise_claim(w: Dictionary, key: String, amount: int, cap: int, now: int = 0) -> int:
	if amount <= 0 or cap <= 0 or not is_valid_id(key):
		return 0
	var claims: Dictionary = w["claims"]
	if not claims.has(key) and claims.size() >= limit("max_claims"):
		return 0
	var have: int = int(claims.get(key, 0))
	var next: int = mini(have + amount, mini(cap, limit("max_claim")))
	if next <= have:
		return 0
	claims[key] = next
	_log(w, key, next - have, now)
	return next - have


static func owns(w: Dictionary, id: String) -> bool:
	return (w["buys"] as Dictionary).has(id)


## Buys item `id` for `price`. False if it is owned, free-priced wrongly or the gems
## do not suffice; the wallet is untouched then.
static func buy(w: Dictionary, id: String, price: int, now: int = 0) -> bool:
	if not is_valid_id(id) or price < 0 or price > limit("max_claim") or owns(w, id):
		return false
	if gems(w) < price:
		return false
	w["buys"][id] = price
	_log(w, "buy:" + id, -price, now)
	return true


## Wears an owned item in a slot ("" takes the slot back to the default look).
static func equip(w: Dictionary, slot: String, id: String) -> bool:
	if not is_valid_id(slot):
		return false
	if id == "":
		(w["equipped"] as Dictionary).erase(slot)
		return true
	if not owns(w, id):
		return false
	w["equipped"][slot] = id
	return true


static func equipped(w: Dictionary, slot: String) -> String:
	return str((w["equipped"] as Dictionary).get(slot, ""))


## Normalises anything (an old save, the cloud, a test) into a valid wallet: types,
## key shapes, amounts in range, at most max_claims claims.
static func sanitize(raw: Variant) -> Dictionary:
	var w: Dictionary = empty()
	if not raw is Dictionary:
		return w
	var src: Dictionary = raw
	var cap: int = limit("max_claim")
	for pair: Array in [["claims", cap], ["buys", cap]]:
		var field: Variant = src.get(pair[0], {})
		if not field is Dictionary:
			continue
		var keys: Array = (field as Dictionary).keys()
		keys.sort()
		for key: Variant in keys:
			var value: Variant = field[key]
			if (
				value is int
				and is_valid_id(str(key))
				and (w[pair[0]] as Dictionary).size() < limit("max_claims")
			):
				w[pair[0]][str(key)] = clampi(value, 0, int(pair[1]))
	var worn: Variant = src.get("equipped", {})
	if worn is Dictionary:
		for slot: Variant in worn:
			var id: String = str(worn[slot])
			if is_valid_id(str(slot)) and w["buys"].has(id):
				w["equipped"][str(slot)] = id
	var log: Variant = src.get("log", [])
	if log is Array:
		for entry: Variant in log:
			if entry is Dictionary and (w["log"] as Array).size() < limit("log_size"):
				var e: Dictionary = entry
				w["log"].append(
					{"t": int(e.get("t", 0)), "k": str(e.get("k", "")), "d": int(e.get("d", 0))}
				)
	return w


## Merge of two wallets of one player (this device and the cloud): every claim and
## purchase is kept (max per key), so nothing is paid twice and nothing is lost. The
## worn items come from `prefer_b` side when it is the newer one; an item that is not
## owned is taken off. `today` ("yyyy-mm-dd") compacts old dated claims.
static func merge(
	a: Dictionary, b: Dictionary, prefer_b: bool = false, today: String = ""
) -> Dictionary:
	var out: Dictionary = empty()
	for field in ["claims", "buys"]:
		var u: Dictionary = (a[field] as Dictionary).duplicate()
		for key: String in b[field]:
			u[key] = maxi(int(u.get(key, 0)), int(b[field][key]))
		out[field] = u
	out["equipped"] = ((b if prefer_b else a)["equipped"] as Dictionary).duplicate()
	for slot: String in (a if prefer_b else b)["equipped"] as Dictionary:
		if not out["equipped"].has(slot):
			out["equipped"][slot] = (a if prefer_b else b)["equipped"][slot]
	for slot: String in (out["equipped"] as Dictionary).keys():
		if not out["buys"].has(out["equipped"][slot]):
			out["equipped"].erase(slot)
	out["log"] = (a["log"] as Array).duplicate()
	if today != "":
		_drop_folded(out, today)
		compact(out, today)
	return sanitize(out)


## Folds dated claims older than compact_after_days into "old:yyyy-mm" claims.
static func compact(w: Dictionary, today: String) -> void:
	var today_index: int = Daily.day_index(today)
	if today_index < 0:
		return
	var claims: Dictionary = w["claims"]
	for key: String in claims.keys():
		var day: String = dated(key)
		if day == "" or key.begins_with(OLD_PREFIX):
			continue
		if today_index - Daily.day_index(day) > limit("compact_after_days"):
			var month: String = OLD_PREFIX + day.substr(0, 7)
			claims[month] = mini(int(claims.get(month, 0)) + int(claims[key]), limit("max_claim"))
			claims.erase(key)


## The "yyyy-mm-dd" a claim key carries ("" if none).
static func dated(key: String) -> String:
	for part in key.split(":"):
		if part.length() == 10 and Daily.is_valid_key(part):
			return part
	return ""


# --- Cloud form: users/{uid}.wallet (see firestore.rules) ---


## {gems, earned, spent, claims: "k=v;k=v", buys: "id=price;id=price", equipped: "slot=id;..."}
## The three numbers are derived (the rules check their plausibility); the strings carry
## the data that merges.
static func to_cloud(w: Dictionary) -> Dictionary:
	return {
		"gems": gems(w),
		"earned": earned(w),
		"spent": spent(w),
		"claims": encode_map(w["claims"]),
		"buys": encode_map(w["buys"]),
		"equipped": encode_map(w["equipped"]),
	}


static func from_cloud(fields: Variant) -> Dictionary:
	if not fields is Dictionary:
		return empty()
	var src: Dictionary = fields
	return sanitize(
		{
			"claims": decode_map(src.get("claims", ""), true),
			"buys": decode_map(src.get("buys", ""), true),
			"equipped": decode_map(src.get("equipped", ""), false),
		}
	)


static func encode_map(m: Dictionary) -> String:
	var keys: Array = m.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for key: Variant in keys:
		parts.append("%s=%s" % [key, m[key]])
	return ";".join(parts)


static func decode_map(text: Variant, numbers: bool) -> Dictionary:
	var out := {}
	if not text is String or (text as String).length() > 12000:
		return out
	for part in (text as String).split(";", false):
		var pair: PackedStringArray = part.split("=")
		if pair.size() != 2 or not is_valid_id(pair[0]):
			continue
		if numbers:
			if pair[1].is_valid_int():
				out[pair[0]] = int(pair[1])
		else:
			out[pair[0]] = pair[1]
	return out


# --- The save file (section [wallet] of user://progress.cfg) ---


static func from_save(cfg: ConfigFile) -> Dictionary:
	if not cfg.has_section(SECTION):
		return empty()
	return sanitize(
		{
			"claims": decode_map(cfg.get_value(SECTION, "claims", ""), true),
			"buys": decode_map(cfg.get_value(SECTION, "buys", ""), true),
			"equipped": decode_map(cfg.get_value(SECTION, "equipped", ""), false),
			"log": cfg.get_value(SECTION, "log", []),
		}
	)


static func write_to_save(w: Dictionary, cfg: ConfigFile) -> void:
	cfg.set_value(SECTION, "v", VERSION)
	cfg.set_value(SECTION, "claims", encode_map(w["claims"]))
	cfg.set_value(SECTION, "buys", encode_map(w["buys"]))
	cfg.set_value(SECTION, "equipped", encode_map(w["equipped"]))
	cfg.set_value(SECTION, "log", w["log"])


static func local() -> Dictionary:
	return from_save(LevelCatalog.data())


## Writes the wallet into the save (atomic commit by LevelCatalog).
static func save_local(w: Dictionary) -> void:
	write_to_save(w, LevelCatalog.data())
	LevelCatalog.commit()


static func _sum(m: Dictionary) -> int:
	var total: int = 0
	for key: Variant in m:
		total += maxi(int(m[key]), 0)
	return total


static func _log(w: Dictionary, key: String, delta: int, now: int) -> void:
	var log: Array = w["log"]
	log.append({"t": now, "k": key, "d": delta})
	while log.size() > limit("log_size"):
		log.pop_front()


## A raw dated claim whose month is already folded into "old:yyyy-mm" is dropped, so
## merging a compacted wallet with an uncompacted one does not count it twice.
static func _drop_folded(w: Dictionary, today: String) -> void:
	var claims: Dictionary = w["claims"]
	var today_index: int = Daily.day_index(today)
	for key: String in claims.keys():
		var day: String = dated(key)
		if day == "" or key.begins_with(OLD_PREFIX) or today_index < 0:
			continue
		var stale: bool = today_index - Daily.day_index(day) > limit("compact_after_days")
		if stale and claims.has(OLD_PREFIX + day.substr(0, 7)):
			claims.erase(key)

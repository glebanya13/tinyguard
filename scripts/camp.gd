class_name Camp
extends RefCounted
## The Camp (Stage B of Retention v2): passive offline accumulation of treasury coins
## (soft currency for meta-progression). Accumulates coins during player absence based
## on the Unix timestamp of the last collection up to a cap (e.g. 8h default).
## Protects against device clock rollbacks by enforcing monotonic timestamps.
## Data / balance in resources/economy.json ("camp").
##
## State: {"level": 1..5, "last_collect": unix_s, "coins": int, "total_collected": int}

const SECTION := "camp"
const MAX_LEVEL := 5
const MAX_COINS := 999999
const DEFAULT_BATTLE_REWARD := 40

const DEFAULT_RATES: Array[int] = [10, 15, 20, 25, 30]
const DEFAULT_CAPS_HOURS: Array[int] = [8, 10, 12, 14, 16]
const DEFAULT_UPGRADE_COSTS: Array[int] = [0, 150, 350, 750, 1500]


static func empty() -> Dictionary:
	return {"level": 1, "last_collect": 0, "coins": 0, "total_collected": 0}


static func sanitize(raw: Variant) -> Dictionary:
	var c: Dictionary = empty()
	if not raw is Dictionary:
		return c
	var src: Dictionary = raw
	c["level"] = clampi(int(src.get("level", 1)), 1, MAX_LEVEL)
	c["last_collect"] = maxi(int(src.get("last_collect", 0)), 0)
	c["coins"] = clampi(int(src.get("coins", 0)), 0, MAX_COINS)
	c["total_collected"] = maxi(int(src.get("total_collected", 0)), 0)
	return c


static func rate_for_level(level: int) -> int:
	var lvl: int = clampi(level, 1, MAX_LEVEL)
	var rates: Array = Wallet.data().get("camp", {}).get("rates", DEFAULT_RATES)
	if lvl - 1 < rates.size():
		return int(rates[lvl - 1])
	return DEFAULT_RATES[lvl - 1]


static func cap_hours_for_level(level: int) -> int:
	var lvl: int = clampi(level, 1, MAX_LEVEL)
	var caps: Array = Wallet.data().get("camp", {}).get("caps_hours", DEFAULT_CAPS_HOURS)
	if lvl - 1 < caps.size():
		return int(caps[lvl - 1])
	return DEFAULT_CAPS_HOURS[lvl - 1]


static func upgrade_cost(level: int) -> int:
	var lvl: int = clampi(level, 1, MAX_LEVEL)
	var costs: Array = Wallet.data().get("camp", {}).get("upgrade_costs", DEFAULT_UPGRADE_COSTS)
	if lvl < costs.size():
		return int(costs[lvl])
	return 0


static func battle_reward() -> int:
	return int(Wallet.data().get("camp", {}).get("battle_reward", DEFAULT_BATTLE_REWARD))


## Coins accumulated since last_collect up to the cap. Returns 0 if time went backward or
## last_collect is unset.
static func pending_coins(state: Dictionary, now: int) -> int:
	var s: Dictionary = sanitize(state)
	var last: int = int(s["last_collect"])
	if now <= last or last <= 0:
		return 0
	var elapsed: int = now - last
	var cap_sec: int = cap_hours_for_level(int(s["level"])) * 3600
	var effective_sec: int = mini(elapsed, cap_sec)
	var rate: int = rate_for_level(int(s["level"]))
	@warning_ignore("integer_division")
	return (effective_sec * rate) / 3600


## Collects pending coins into state["coins"]. Monotonic: never awards coins
## if now < last_collect.
## Returns {"collected": amount, "coins": balance, "state": state}.
static func collect(state: Dictionary, now: int) -> Dictionary:
	var last: int = int(state.get("last_collect", 0))
	if last <= 0:
		state["last_collect"] = now
		return {"collected": 0, "coins": int(state.get("coins", 0)), "state": state}
	if now < last:
		return {"collected": 0, "coins": int(state.get("coins", 0)), "state": state}
	var amount: int = pending_coins(state, now)
	if amount > 0:
		state["coins"] = clampi(int(state.get("coins", 0)) + amount, 0, MAX_COINS)
		state["total_collected"] = int(state.get("total_collected", 0)) + amount
		state["last_collect"] = now
	return {"collected": amount, "coins": int(state.get("coins", 0)), "state": state}


## Upgrades the camp to the next level if enough coins are available.
static func upgrade(state: Dictionary) -> bool:
	var lvl: int = int(state.get("level", 1))
	if lvl >= MAX_LEVEL:
		return false
	var cost: int = upgrade_cost(lvl)
	var coins: int = int(state.get("coins", 0))
	if coins < cost:
		return false
	state["coins"] = coins - cost
	state["level"] = lvl + 1
	return true


## Adds treasury coins to the balance (e.g. from battle or calendar).
static func add_coins(state: Dictionary, amount: int) -> int:
	if amount <= 0:
		return 0
	var coins: int = int(state.get("coins", 0))
	var next: int = clampi(coins + amount, 0, MAX_COINS)
	state["coins"] = next
	state["total_collected"] = int(state.get("total_collected", 0)) + (next - coins)
	return next - coins


## Merges two camp states (local and cloud). Level, coins, and total take max.
static func merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var x: Dictionary = sanitize(a)
	var y: Dictionary = sanitize(b)
	return {
		"level": maxi(int(x["level"]), int(y["level"])),
		"last_collect": maxi(int(x["last_collect"]), int(y["last_collect"])),
		"coins": maxi(int(x["coins"]), int(y["coins"])),
		"total_collected": maxi(int(x["total_collected"]), int(y["total_collected"]))
	}


static func from_save(cfg: ConfigFile) -> Dictionary:
	if not cfg.has_section(SECTION):
		return empty()
	return sanitize(
		{
			"level": cfg.get_value(SECTION, "level", 1),
			"last_collect": cfg.get_value(SECTION, "last_collect", 0),
			"coins": cfg.get_value(SECTION, "coins", 0),
			"total_collected": cfg.get_value(SECTION, "total_collected", 0)
		}
	)


static func write_to_save(state: Dictionary, cfg: ConfigFile) -> void:
	var s: Dictionary = sanitize(state)
	for key in ["level", "last_collect", "coins", "total_collected"]:
		cfg.set_value(SECTION, key, s[key])


static func local() -> Dictionary:
	return from_save(LevelCatalog.data())


static func save_local(state: Dictionary) -> void:
	write_to_save(state, LevelCatalog.data())
	LevelCatalog.commit()

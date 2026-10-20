class_name Calendar28
extends RefCounted
## 28-day reward calendar (Stage A of Retention v2): counts cumulative visit days (does not
## reset on missed days, unlike streaks). 28 reward steps with treasury coins and gems.
## Claimable once per UTC day (YYYY-MM-DD) with idempotent claim keys ("cal:<date>" in wallet).
## Data in resources/economy.json ("calendar").
##
## State: {"claimed_days": int, "last_claim": "YYYY-MM-DD"}

const SECTION := "calendar"
const CYCLE_DAYS := 28

const DEFAULT_REWARDS: Array[Dictionary] = [
	{"coins": 20, "gems": 5},
	{"coins": 25, "gems": 5},
	{"coins": 30, "gems": 10},
	{"coins": 35, "gems": 10},
	{"coins": 40, "gems": 15},
	{"coins": 45, "gems": 15},
	{"coins": 100, "gems": 50},  # Day 7 milestone
	{"coins": 30, "gems": 10},
	{"coins": 35, "gems": 10},
	{"coins": 40, "gems": 15},
	{"coins": 45, "gems": 15},
	{"coins": 50, "gems": 20},
	{"coins": 60, "gems": 20},
	{"coins": 150, "gems": 75},  # Day 14 milestone
	{"coins": 40, "gems": 15},
	{"coins": 45, "gems": 15},
	{"coins": 50, "gems": 20},
	{"coins": 55, "gems": 20},
	{"coins": 60, "gems": 25},
	{"coins": 70, "gems": 25},
	{"coins": 200, "gems": 100}, # Day 21 milestone
	{"coins": 50, "gems": 20},
	{"coins": 55, "gems": 20},
	{"coins": 60, "gems": 25},
	{"coins": 70, "gems": 25},
	{"coins": 80, "gems": 30},
	{"coins": 90, "gems": 35},
	{"coins": 300, "gems": 150}  # Day 28 grand milestone
]


static func empty() -> Dictionary:
	return {"claimed_days": 0, "last_claim": ""}


static func sanitize(raw: Variant) -> Dictionary:
	var c: Dictionary = empty()
	if not raw is Dictionary:
		return c
	var src: Dictionary = raw
	var last: String = str(src.get("last_claim", ""))
	if Daily.is_valid_key(last):
		c["last_claim"] = last
	c["claimed_days"] = clampi(int(src.get("claimed_days", 0)), 0, 100000)
	return c


static func rewards() -> Array:
	return Wallet.data().get("calendar", {}).get("rewards", DEFAULT_REWARDS)


## Step in the 28-day cycle for a given count of claimed days (1..28, or 0 if 0).
static func step_of(claimed_days: int) -> int:
	return posmod(claimed_days - 1, CYCLE_DAYS) + 1 if claimed_days > 0 else 0


## The next step to be claimed (1..28).
static func next_step(claimed_days: int) -> int:
	return posmod(claimed_days, CYCLE_DAYS) + 1


## Reward definition {coins: int, gems: int} for step (1..28).
static func reward_for_step(step: int) -> Dictionary:
	var r: Array = rewards()
	var idx: int = clampi(step, 1, CYCLE_DAYS) - 1
	if idx < r.size() and r[idx] is Dictionary:
		return r[idx]
	return DEFAULT_REWARDS[idx]


## Whether the player can claim today's reward. Checks date validity, same-day claim,
## clock rollback, and optional wallet claim record.
static func can_claim(state: Dictionary, today: String, wallet: Dictionary = {}) -> bool:
	if not Daily.is_valid_key(today):
		return false
	var s: Dictionary = sanitize(state)
	if s["last_claim"] == today:
		return false
	if not wallet.is_empty() and Wallet.has_claim(wallet, "cal:" + today):
		return false
	if s["last_claim"] != "":
		var gap: int = Daily.day_index(today) - Daily.day_index(str(s["last_claim"]))
		if gap <= 0:
			return false
	return true


## Claims today's step. Idempotent: fails if already claimed today or clock went backwards.
## Pays gems into `wallet` under "cal:<today>" and coins into `camp`.
## Returns {"success": bool, "state": state, "step": int, "coins": int, "gems": int}.
static func claim(
	state: Dictionary, today: String, wallet: Dictionary, camp: Dictionary
) -> Dictionary:
	if not can_claim(state, today, wallet):
		return {"success": false, "state": state, "step": 0, "coins": 0, "gems": 0}
	var next_s: int = next_step(int(state.get("claimed_days", 0)))
	var rew: Dictionary = reward_for_step(next_s)
	var coins: int = int(rew.get("coins", 0))
	var gems: int = int(rew.get("gems", 0))
	if gems > 0:
		Wallet.claim(wallet, "cal:" + today, gems, int(Time.get_unix_time_from_system()))
	if coins > 0:
		Camp.add_coins(camp, coins)
	state["claimed_days"] = int(state.get("claimed_days", 0)) + 1
	state["last_claim"] = today
	return {"success": true, "state": state, "step": next_s, "coins": coins, "gems": gems}


## Merges two calendar states (local and cloud).
static func merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var x: Dictionary = sanitize(a)
	var y: Dictionary = sanitize(b)
	var out: Dictionary = {}
	out["claimed_days"] = maxi(int(x["claimed_days"]), int(y["claimed_days"]))
	var dx: int = Daily.day_index(str(x["last_claim"])) if x["last_claim"] != "" else -1
	var dy: int = Daily.day_index(str(y["last_claim"])) if y["last_claim"] != "" else -1
	out["last_claim"] = y["last_claim"] if dy > dx else x["last_claim"]
	return sanitize(out)


static func from_save(cfg: ConfigFile) -> Dictionary:
	if not cfg.has_section(SECTION):
		return empty()
	return sanitize(
		{
			"claimed_days": cfg.get_value(SECTION, "claimed_days", 0),
			"last_claim": cfg.get_value(SECTION, "last_claim", "")
		}
	)


static func write_to_save(state: Dictionary, cfg: ConfigFile) -> void:
	var s: Dictionary = sanitize(state)
	cfg.set_value(SECTION, "claimed_days", s["claimed_days"])
	cfg.set_value(SECTION, "last_claim", s["last_claim"])


static func local() -> Dictionary:
	return from_save(LevelCatalog.data())


static func save_local(state: Dictionary) -> void:
	write_to_save(state, LevelCatalog.data())
	LevelCatalog.commit()

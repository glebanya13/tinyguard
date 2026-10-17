class_name Quests
extends RefCounted
## Daily quests: three per UTC day, drawn from resources/quests.json by the date alone
## (deterministic, the same on every device, offline too). Progress of the current day
## lives in the save ([quests] section, this device only); a finished quest pays gems
## through Economy under the idempotent claim "q:<day>:<slot>", so it can never pay twice.
## Progress is fed by QuestTracker from battle signals; the simulation knows nothing.

const DATA_PATH := "res://resources/quests.json"
const SECTION := "quests"
## Progress values never exceed this (a sanity clamp of the save).
const MAX_PROGRESS := 100000

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var json: JSON = load(DATA_PATH)
		_data = json.data
	return _data


## The quests of `day`: [{slot, id, metric, target, key, reward}], `count` entries with
## different templates.
static func for_day(day: String) -> Array[Dictionary]:
	var templates: Array = data()["templates"]
	var rewards: Array = Wallet.data()["quests"]["rewards"]
	var count: int = mini(int(Wallet.data()["quests"]["count"]), templates.size())
	var pool: Array = range(templates.size())
	var out: Array[Dictionary] = []
	for slot in count:
		var pick: int = Daily.hash_text("quest:%s:%d" % [day, slot]) % pool.size()
		var template: Dictionary = templates[pool[pick]]
		pool.remove_at(pick)
		var targets: Array = template["targets"]
		var target: int = int(
			targets[Daily.hash_text("target:%s:%d" % [day, slot]) % targets.size()]
		)
		(
			out
			. append(
				{
					"slot": slot,
					"id": str(template["id"]),
					"metric": str(template["metric"]),
					"target": target,
					"key": str(template["key"]),
					"reward": int(rewards[slot]) if slot < rewards.size() else 0,
				}
			)
		)
	return out


## Progress of `day` as {metric: value}; empty when the save holds another day.
static func progress(day: String) -> Dictionary:
	var cfg: ConfigFile = LevelCatalog.data()
	var out := {}
	if str(cfg.get_value(SECTION, "day", "")) != day:
		return out
	for def in for_day(day):
		var metric: String = def["metric"]
		out[metric] = clampi(int(cfg.get_value(SECTION, metric, 0)), 0, MAX_PROGRESS)
	return out


static func value(day: String, def: Dictionary) -> int:
	return int(progress(day).get(str(def["metric"]), 0))


static func is_done(day: String, def: Dictionary) -> bool:
	return value(day, def) >= int(def["target"])


## Adds a batch of battle counters to `day`'s progress: {"kills": n, "towers": n,
## "upgrades": n} are summed, {"wave": w} keeps the highest. Pays quests that just reached
## their target. Returns [{"def": quest, "gems": paid}] of the quests completed now.
static func add(day: String, batch: Dictionary) -> Array[Dictionary]:
	var cfg: ConfigFile = LevelCatalog.data()
	var done_before: Array[bool] = []
	var defs: Array[Dictionary] = for_day(day)
	if str(cfg.get_value(SECTION, "day", "")) != day:
		if cfg.has_section(SECTION):
			cfg.erase_section(SECTION)
		cfg.set_value(SECTION, "day", day)
	for def in defs:
		done_before.append(is_done(day, def))
	for metric: String in batch:
		var have: int = int(cfg.get_value(SECTION, metric, 0))
		var amount: int = maxi(int(batch[metric]), 0)
		var next: int = maxi(have, amount) if metric == "wave" else have + amount
		cfg.set_value(SECTION, metric, clampi(next, 0, MAX_PROGRESS))
	var finished: Array[Dictionary] = []
	for i in defs.size():
		if not done_before[i] and is_done(day, defs[i]):
			var gems: int = Economy.award_quest(day, int(defs[i]["slot"]))
			finished.append({"def": defs[i], "gems": gems})
	LevelCatalog.commit()
	return finished


## "Reach wave 6" / "Kill 60 enemies" for a quest.
static func text(def: Dictionary) -> String:
	return TranslationServer.translate(str(def["key"])) % int(def["target"])

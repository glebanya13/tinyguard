class_name Streak
extends RefCounted
## The day streak: consecutive UTC days the player opened the game (checked in). Pure
## logic on one Dictionary plus its place in the save and the cloud profile; the days
## are the same UTC dates Daily uses. Missing one day is forgiven once per week (the
## streak goes on); a longer gap starts over. The reward of a day is paid through the
## wallet under the claim "streak:<date>", so checking in twice a day, or on two
## devices, pays once. Data: resources/economy.json ("streak").
##
## State: {last: "yyyy-mm-dd" of the last check-in, len: days in a row, best: longest,
##         grace: week number (day index / 7) of the missed day last forgiven}

enum Result { FIRST, SAME_DAY, NEXT, FORGIVEN, RESET, CLOCK_BACK }

const SECTION := "streak"
const WEEK := 7
const MAX_LEN := 1000


static func empty() -> Dictionary:
	return {"last": "", "len": 0, "best": 0, "grace": -1}


static func sanitize(raw: Variant) -> Dictionary:
	var s: Dictionary = empty()
	if not raw is Dictionary:
		return s
	var src: Dictionary = raw
	var last: String = str(src.get("last", ""))
	if Daily.is_valid_key(last):
		s["last"] = last
		s["len"] = clampi(int(src.get("len", 0)), 0, MAX_LEN)
	s["best"] = clampi(maxi(int(src.get("best", 0)), int(s["len"])), 0, MAX_LEN)
	s["grace"] = clampi(int(src.get("grace", -1)), -1, 1000000)
	return s


## Registers a visit on `today`. Returns {"state", "result" (Result), "day" (1..7, the
## day of the reward cycle), "reward" (gems of that day, 0 when there is none today)}.
## Does not touch the wallet or the disk.
static func check_in(state: Dictionary, today: String) -> Dictionary:
	var s: Dictionary = sanitize(state)
	var result: int = Result.FIRST
	var now: int = Daily.day_index(today)
	if now < 0:
		return {"state": s, "result": Result.CLOCK_BACK, "day": 0, "reward": 0}
	if s["last"] != "":
		var gap: int = now - Daily.day_index(str(s["last"]))
		if gap <= 0:
			var same: int = Result.SAME_DAY if gap == 0 else Result.CLOCK_BACK
			return {"state": s, "result": same, "day": day_of_cycle(int(s["len"])), "reward": 0}
		if gap == 1:
			s["len"] = int(s["len"]) + 1
			result = Result.NEXT
		elif gap == 2 and _week_of(now - 1) != int(s["grace"]):
			s["len"] = int(s["len"]) + 1
			s["grace"] = _week_of(now - 1)
			result = Result.FORGIVEN
		else:
			s["len"] = 1
			result = Result.RESET
	else:
		s["len"] = 1
	s["len"] = mini(int(s["len"]), MAX_LEN)
	s["last"] = today
	s["best"] = maxi(int(s["best"]), int(s["len"]))
	return {
		"state": s,
		"result": result,
		"day": day_of_cycle(int(s["len"])),
		"reward": reward_for(int(s["len"])),
	}


## 1..7: the place of a streak length in the weekly reward cycle.
static func day_of_cycle(length: int) -> int:
	return posmod(length - 1, WEEK) + 1 if length > 0 else 0


static func rewards() -> Array:
	return Wallet.data()["streak"]["rewards"]


## Gems of the day that makes the streak `length` long (day 7 is the gift).
static func reward_for(length: int) -> int:
	var day: int = day_of_cycle(length)
	return int(rewards()[day - 1]) if day > 0 else 0


## The streak as shown on `today`: it is alive on the day of the last check-in, the next
## day, and the day after that when the forgiveness is still available; else 0.
static func live_length(state: Dictionary, today: String) -> int:
	var s: Dictionary = sanitize(state)
	if s["last"] == "":
		return 0
	var gap: int = Daily.day_index(today) - Daily.day_index(str(s["last"]))
	if gap <= 1:
		return int(s["len"])
	if gap == 2 and _week_of(Daily.day_index(today) - 1) != int(s["grace"]):
		return int(s["len"])
	return 0


## Two streaks of one player: the one that checked in later wins; the same day, the
## longer one; the best length and the used forgiveness only grow.
static func merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var x: Dictionary = sanitize(a)
	var y: Dictionary = sanitize(b)
	var out: Dictionary = x.duplicate()
	var dx: int = Daily.day_index(str(x["last"])) if x["last"] != "" else -1
	var dy: int = Daily.day_index(str(y["last"])) if y["last"] != "" else -1
	if dy > dx or (dy == dx and int(y["len"]) > int(x["len"])):
		out["last"] = y["last"]
		out["len"] = y["len"]
	out["best"] = maxi(int(x["best"]), int(y["best"]))
	out["grace"] = maxi(int(x["grace"]), int(y["grace"]))
	return sanitize(out)


static func from_save(cfg: ConfigFile) -> Dictionary:
	return sanitize(
		{
			"last": cfg.get_value(SECTION, "last", ""),
			"len": cfg.get_value(SECTION, "len", 0),
			"best": cfg.get_value(SECTION, "best", 0),
			"grace": cfg.get_value(SECTION, "grace", -1),
		}
	)


static func write_to_save(s: Dictionary, cfg: ConfigFile) -> void:
	for key in ["last", "len", "best", "grace"]:
		cfg.set_value(SECTION, key, s[key])


static func local() -> Dictionary:
	return from_save(LevelCatalog.data())


static func _week_of(day_index: int) -> int:
	@warning_ignore("integer_division")
	return day_index / WEEK

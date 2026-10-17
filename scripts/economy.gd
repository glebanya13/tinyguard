class_name Economy
extends RefCounted
## Where gems come from. Every function turns one game event into wallet claims under
## idempotent keys (see Wallet), so a replayed result, a second device or a repeated
## sync never pays a reward twice. Amounts and ceilings are data (resources/economy.json).
## Repeating sources have a daily ceiling; one-time sources (first stars, crowns, siege
## milestones, achievements) have a key each. During a seasonal event (Events) awards
## are multiplied. Nothing here touches the simulation: it runs when a battle ENDS.
##
## Claim keys: lv<id>s<1..3> first stars, lv<id>c<1..2> crowns, rp:<day> repeat wins
## (daily ceiling), sg<id>w<n> siege milestones, sgr<id>:<day> record bonus,
## dch:<day> daily challenge, dchw:<day> its wave bonus, ach:<id> achievements,
## streak:<day> day streak, q:<day>:<n> daily quests.

## Gems paid since the last reset_tally() (the end screen shows "+N").
static var _tally: int = 0


static func reset_tally() -> void:
	_tally = 0


## Gems earned since reset_tally().
static func tally() -> int:
	return _tally


static func balance() -> int:
	return Wallet.gems(Wallet.local())


static func level_star_reward(level_id: int, star: int) -> int:
	var cfg: Dictionary = Wallet.data()["level_stars"]
	return int(cfg["base"][star - 1]) + int(cfg["per_level"]) * (level_id - 1)


static func crown_reward(level_id: int, crown: int) -> int:
	var cfg: Dictionary = Wallet.data()["level_crowns"]
	return int(cfg["base"][crown - 1]) + int(cfg["per_level"]) * (level_id - 1)


static func siege_reward(step: int) -> int:
	var cfg: Dictionary = Wallet.data()["siege"]
	return int(cfg["base"]) + int(cfg["per_step"]) * (step - 1)


static func achievement_reward(def: Dictionary) -> int:
	var cfg: Dictionary = Wallet.data()["achievements"]
	var rarity: String = str(cfg["rarity"].get(str(def.get("id", "")), cfg["default"]))
	return int(cfg[rarity])


## A won campaign level: stars not paid yet (1..stars), the difficulty crown(s), else the
## small repeat reward up to its daily ceiling. Returns the gems paid.
static func award_level_win(level_id: int, stars: int, difficulty: int = 0) -> int:
	var p: Dictionary = PlayerProfile.local()
	var w: Dictionary = p["wallet"]
	var paid: int = 0
	for star in range(1, clampi(stars, 0, 3) + 1):
		paid += _claim(w, "lv%ds%d" % [level_id, star], level_star_reward(level_id, star))
	for crown in range(1, clampi(difficulty, 0, LevelCatalog.MAX_DIFFICULTY) + 1):
		paid += _claim(w, "lv%dc%d" % [level_id, crown], crown_reward(level_id, crown))
	if paid == 0:
		var repeat: Dictionary = Wallet.data()["repeat_win"]
		paid += _raise(
			w, "rp:" + Daily.today_key(), int(repeat["reward"]), int(repeat["daily_cap"])
		)
	return _finish(p, paid)


## Siege (Record Run) waves: one reward per 5 waves, once per level, and a bonus for a
## new personal record once per level and day.
static func award_siege(level_id: int, waves: int, new_record: bool = false) -> int:
	var cfg: Dictionary = Wallet.data()["siege"]
	var p: Dictionary = PlayerProfile.local()
	var w: Dictionary = p["wallet"]
	var paid: int = 0
	@warning_ignore("integer_division")
	var steps: int = mini(waves / int(cfg["every_waves"]), int(cfg["max_steps"]))
	for step in range(1, steps + 1):
		paid += _claim(w, "sg%dw%d" % [level_id, step], siege_reward(step))
	if new_record and waves > 0:
		paid += _claim(w, "sgr%d:%s" % [level_id, Daily.today_key()], int(cfg["record_bonus"]))
	return _finish(p, paid)


## The daily challenge: a reward for the day's first finished run and a wave bonus that
## grows with the best wave of the day (up to its cap).
static func award_daily(day: String, waves: int) -> int:
	if not Daily.is_valid_key(day) or waves < 1:
		return 0
	var cfg: Dictionary = Wallet.data()["daily_challenge"]
	var p: Dictionary = PlayerProfile.local()
	var w: Dictionary = p["wallet"]
	var paid: int = _claim(w, "dch:" + day, int(cfg["base"]))
	@warning_ignore("integer_division")
	var bonus: int = waves / 2 * int(cfg["per_two_waves"])
	paid += _raise_to(w, "dchw:" + day, bonus, int(cfg["wave_bonus_cap"]))
	return _finish(p, paid)


static func award_achievement(def: Dictionary) -> int:
	var p: Dictionary = PlayerProfile.local()
	var paid: int = _claim(p["wallet"], "ach:" + str(def["id"]), achievement_reward(def))
	return _finish(p, paid)


## Reward of daily quest number `index` (0-based) of `day`, once.
static func award_quest(day: String, index: int) -> int:
	var rewards: Array = Wallet.data()["quests"]["rewards"]
	if index < 0 or index >= rewards.size() or not Daily.is_valid_key(day):
		return 0
	var p: Dictionary = PlayerProfile.local()
	var paid: int = _claim(p["wallet"], "q:%s:%d" % [day, index], int(rewards[index]))
	return _finish(p, paid)


## Pays what progress made before gems existed (or on another device that has not
## synced yet) is worth: first stars, crowns, siege milestones, achievements. No event
## multiplier. Returns the gems paid (0 on every later call).
static func backfill() -> int:
	var p: Dictionary = PlayerProfile.local()
	var w: Dictionary = p["wallet"]
	var prog: Dictionary = p["progression"]
	var paid: int = 0
	for id: String in prog["stars"]:
		for star in range(1, int(prog["stars"][id]) + 1):
			paid += _claim(w, "lv%ss%d" % [id, star], level_star_reward(int(id), star), false)
	for id: String in prog.get("crowns", {}):
		for crown in range(1, int(prog["crowns"][id]) + 1):
			paid += _claim(w, "lv%sc%d" % [id, crown], crown_reward(int(id), crown), false)
	var cfg: Dictionary = Wallet.data()["siege"]
	for id: String in prog["endless"]:
		@warning_ignore("integer_division")
		var steps: int = mini(int(prog["endless"][id]) / int(cfg["every_waves"]), int(cfg["max_steps"]))
		for step in range(1, steps + 1):
			paid += _claim(w, "sg%sw%d" % [id, step], siege_reward(step), false)
	for def in Achievements.all():
		if Achievements.mask_has(int(p["achievements"]), def):
			paid += _claim(w, "ach:" + str(def["id"]), achievement_reward(def), false)
	return _finish(p, paid, false)


## Called when the map opens: backfill, then the day's streak check-in with its reward.
## Returns {"backfill": gems, "streak": Streak.check_in() result or {}, "gems": paid today}.
static func on_app_open() -> Dictionary:
	var out := {"backfill": backfill(), "streak": {}, "gems": 0}
	var today: String = Daily.today_key()
	var p: Dictionary = PlayerProfile.local()
	var visit: Dictionary = Streak.check_in(p["streak"], today)
	p["streak"] = visit["state"]
	var paid: int = 0
	if int(visit["reward"]) > 0:
		paid = _claim(p["wallet"], "streak:" + today, int(visit["reward"]))
	out["streak"] = visit
	out["gems"] = paid
	_finish(p, paid, true, true)
	return out


## Scaled by the event multiplier of today (or not).
static func scaled(amount: int, event: bool = true) -> int:
	if not event:
		return amount
	return roundi(float(amount) * Events.reward_mult(Daily.today_key()))


static func _claim(w: Dictionary, key: String, amount: int, event: bool = true) -> int:
	return Wallet.claim(w, key, scaled(amount, event), int(Time.get_unix_time_from_system()))


static func _raise(w: Dictionary, key: String, amount: int, cap: int) -> int:
	return Wallet.raise_claim(
		w, key, scaled(amount), scaled(cap), int(Time.get_unix_time_from_system())
	)


## Brings the claim `key` up to `target` (never above `cap`).
static func _raise_to(w: Dictionary, key: String, target: int, cap: int) -> int:
	var have: int = int((w["claims"] as Dictionary).get(key, 0))
	return Wallet.raise_claim(
		w, key, maxi(scaled(target) - have, 0), scaled(cap), int(Time.get_unix_time_from_system())
	)


static func _finish(p: Dictionary, paid: int, count: bool = true, force: bool = false) -> int:
	if paid > 0 or force:
		Wallet.compact(p["wallet"], Daily.today_key())
		PlayerProfile.save_local(p)
	if count:
		_tally += paid
	return paid

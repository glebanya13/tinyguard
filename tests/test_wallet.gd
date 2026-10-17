extends SceneTree
## The gem wallet and where gems come from: claims are idempotent, spending needs funds,
## a merge of two devices never pays twice or loses a purchase, the cloud form clamps
## garbage, the profile carries the wallet (schema 3, migration from 2), and Economy pays
## each event once. godot --headless --path . --script res://tests/test_wallet.gd

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_wallet.cfg"
	_wipe()
	_run.call_deferred()


func _wipe() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path + suffix))
	LevelCatalog.erase_all()


func _run() -> void:
	_check_pure()
	_check_merge()
	_check_cloud()
	_check_profile()
	_check_economy()
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _check_pure() -> void:
	var w: Dictionary = Wallet.empty()
	check(Wallet.gems(w) == 0, "an empty wallet has 0 gems")
	check(Wallet.claim(w, "lv1s1", 15) == 15, "claim pays")
	check(Wallet.claim(w, "lv1s1", 15) == 0, "the same claim again pays nothing (idempotent)")
	check(Wallet.gems(w) == 15 and Wallet.earned(w) == 15, "balance 15")
	check(Wallet.claim(w, "Bad Key", 5) == 0, "a malformed key is refused")
	check(Wallet.claim(w, "x", 0) == 0 and Wallet.claim(w, "y", -4) == 0, "no zero or negative")
	check(Wallet.claim(w, "big", 99999) == Wallet.limit("max_claim"), "one claim is clamped")
	var w2: Dictionary = Wallet.empty()
	check(Wallet.raise_claim(w2, "rp:2026-10-17", 8, 20) == 8, "raise pays")
	check(Wallet.raise_claim(w2, "rp:2026-10-17", 8, 20) == 8, "raise pays again")
	check(Wallet.raise_claim(w2, "rp:2026-10-17", 8, 20) == 4, "raise stops at the ceiling")
	check(Wallet.raise_claim(w2, "rp:2026-10-17", 8, 20) == 0, "nothing above the ceiling")
	check(Wallet.gems(w2) == 20, "ceiling total 20")
	var w3: Dictionary = Wallet.empty()
	Wallet.claim(w3, "a", 100, 5)
	check(not Wallet.buy(w3, "item_a", 150), "cannot buy without funds")
	check(
		not Wallet.owns(w3, "item_a") and Wallet.gems(w3) == 100,
		"a refused purchase changes nothing"
	)
	check(Wallet.buy(w3, "item_a", 60, 6), "buy with funds")
	check(Wallet.gems(w3) == 40 and Wallet.spent(w3) == 60, "balance after buying")
	check(not Wallet.buy(w3, "item_a", 60), "an item is bought once")
	check(not Wallet.buy(w3, "item_b", -5), "no negative price")
	check(not Wallet.equip(w3, "hero", "item_b"), "cannot wear what is not owned")
	check(Wallet.equip(w3, "hero", "item_a") and Wallet.equipped(w3, "hero") == "item_a", "wear")
	check(Wallet.equip(w3, "hero", "") and Wallet.equipped(w3, "hero") == "", "take off")
	check((w3["log"] as Array).size() == 2, "history keeps the operations")
	for i in 40:
		Wallet.claim(w3, "k%d" % i, 1)
	check((w3["log"] as Array).size() <= Wallet.limit("log_size"), "history is bounded")
	var garbage: Dictionary = Wallet.sanitize(
		{
			"claims": {"ok": 5, "BAD": 5, "neg": -9, "str": "x", "huge": 10 ** 12},
			"buys": 7,
			"equipped": {"s": "nope"}
		}
	)
	check(
		garbage["claims"] == {"ok": 5, "neg": 0, "huge": Wallet.limit("max_claim")},
		"sanitize: %s" % [garbage["claims"]]
	)
	check(garbage["buys"].is_empty() and garbage["equipped"].is_empty(), "sanitize drops junk")
	check(Wallet.sanitize("not a dict") == Wallet.empty(), "sanitize: a non-dictionary")
	var many: Dictionary = Wallet.empty()
	for i in Wallet.limit("max_claims") + 50:
		Wallet.claim(many, "c%d" % i, 1)
	check(many["claims"].size() == Wallet.limit("max_claims"), "the number of claims is capped")
	var top: Dictionary = Wallet.empty()
	for i in 300:
		Wallet.claim(top, "t%d" % i, 5000)
	check(Wallet.gems(top) == Wallet.limit("max_balance"), "the balance is capped")


func _check_merge() -> void:
	var a: Dictionary = Wallet.empty()
	var b: Dictionary = Wallet.empty()
	Wallet.claim(a, "lv1s1", 15)
	Wallet.claim(b, "lv1s1", 15)  # the same reward earned on another device
	Wallet.claim(b, "lv2s1", 18)
	Wallet.claim(a, "ach:hunter", 25)
	var m: Dictionary = Wallet.merge(a, b)
	check(
		Wallet.gems(m) == 15 + 18 + 25, "merge: the same reward counts once (%d)" % Wallet.gems(m)
	)
	Wallet.buy(a, "hero_ember", 40)
	Wallet.equip(a, "hero", "hero_ember")
	m = Wallet.merge(a, b)
	check(
		Wallet.owns(m, "hero_ember") and Wallet.gems(m) == 18 + 25 + 15 - 40,
		"merge keeps purchases"
	)
	check(Wallet.equipped(m, "hero") == "hero_ember", "merge keeps the worn item")
	var m2: Dictionary = Wallet.merge(b, a)
	check(Wallet.gems(m2) == Wallet.gems(m), "merge is symmetric in gems")
	check(
		Wallet.merge(m, m) == m or Wallet.gems(Wallet.merge(m, m)) == Wallet.gems(m),
		"merge is idempotent"
	)
	# The cloud side is newer and wears nothing: its choice wins; an unowned item is dropped.
	var cloud: Dictionary = Wallet.empty()
	m = Wallet.merge(a, cloud, true)
	check(
		Wallet.equipped(m, "hero") == "hero_ember",
		"an empty newer side does not unequip a bought item"
	)
	var c: Dictionary = Wallet.empty()
	Wallet.claim(c, "x", 100)
	Wallet.buy(c, "flag_one", 10)
	Wallet.equip(c, "flag", "flag_one")
	m = Wallet.merge(a, c, true)
	check(
		Wallet.equipped(m, "flag") == "flag_one" and Wallet.equipped(m, "hero") == "hero_ember",
		"slots combine"
	)
	# Old dated claims fold into one monthly claim; merging never counts them twice.
	var old: Dictionary = Wallet.empty()
	Wallet.claim(old, "streak:2026-08-01", 5)
	Wallet.claim(old, "streak:2026-08-02", 10)
	Wallet.claim(old, "streak:2026-10-15", 20)
	var folded: Dictionary = Wallet.empty()
	folded["claims"] = old["claims"].duplicate()
	Wallet.compact(folded, "2026-10-17")
	check(
		folded["claims"].has("old:2026-08") and folded["claims"]["old:2026-08"] == 15,
		"old days fold: %s" % [folded["claims"]]
	)
	check(
		folded["claims"].has("streak:2026-10-15") and Wallet.earned(folded) == 35,
		"recent days stay"
	)
	m = Wallet.merge(folded, old, false, "2026-10-17")
	check(Wallet.earned(m) == 35, "merging a folded and an unfolded wallet: %d" % Wallet.earned(m))
	check(
		Wallet.dated("q:2026-10-17:2") == "2026-10-17" and Wallet.dated("lv1s1") == "", "dated keys"
	)


func _check_cloud() -> void:
	var w: Dictionary = Wallet.empty()
	Wallet.claim(w, "lv1s1", 15)
	Wallet.claim(w, "ach:first_win", 25)
	Wallet.buy(w, "hero_ember", 30)
	Wallet.equip(w, "hero", "hero_ember")
	var cloud: Dictionary = Wallet.to_cloud(w)
	check(cloud["gems"] == 10 and cloud["earned"] == 40 and cloud["spent"] == 30, "cloud totals")
	check(cloud.keys().size() == 6 and not cloud.has("log"), "the cloud form has no log")
	check(
		cloud["claims"] == "ach:first_win=25;lv1s1=15",
		"claims text is sorted: %s" % cloud["claims"]
	)
	var back: Dictionary = Wallet.from_cloud(cloud)
	check(back["claims"] == w["claims"] and back["buys"] == w["buys"], "cloud round trip")
	check(Wallet.equipped(back, "hero") == "hero_ember", "worn item round trip")
	var evil: Dictionary = Wallet.from_cloud(
		{
			"gems": 99999999,
			"claims": "a=999999999;B=5;c=x;d=3;;=4",
			"buys": "z=1;z=2",
			"equipped": "hero=ghost"
		}
	)
	check(
		evil["claims"] == {"a": Wallet.limit("max_claim"), "d": 3},
		"from_cloud clamps and drops junk: %s" % [evil["claims"]]
	)
	check(
		Wallet.gems(evil) <= Wallet.limit("max_balance"),
		"from_cloud: the balance is not taken from the number"
	)
	check(evil["equipped"].is_empty(), "from_cloud: worn but not owned is dropped")
	check(
		Wallet.from_cloud("junk") == Wallet.empty() and Wallet.from_cloud(null) == Wallet.empty(),
		"from_cloud: junk"
	)
	check(Wallet.decode_map("x".repeat(20000), true).is_empty(), "a huge text is ignored")


func _check_profile() -> void:
	_wipe()
	var p: Dictionary = PlayerProfile.local()
	check(
		(
			int(p["schemaVersion"]) == PlayerProfile.SCHEMA_VERSION
			and PlayerProfile.SCHEMA_VERSION >= 3
		),
		"schema 3"
	)
	check(
		p["wallet"] == Wallet.empty() or Wallet.gems(p["wallet"]) == 0,
		"a fresh profile has an empty wallet"
	)
	Wallet.claim(p["wallet"], "lv1s3", 40)
	Wallet.buy(p["wallet"], "hero_ember", 30)
	Wallet.equip(p["wallet"], "hero", "hero_ember")
	p["streak"] = {"last": "2026-10-16", "len": 4, "best": 6, "grace": -1}
	PlayerProfile.save_local(p)
	LevelCatalog._save = null  # forget the cache: read the file again
	LevelCatalog._save_loaded_from = ""
	var q: Dictionary = PlayerProfile.local()
	check(
		Wallet.gems(q["wallet"]) == 10 and Wallet.equipped(q["wallet"], "hero") == "hero_ember",
		"wallet survives a save and reload"
	)
	check(q["streak"]["len"] == 4 and q["streak"]["best"] == 6, "streak survives a save and reload")
	var sync: Dictionary = PlayerProfile.syncable(q)
	check(
		sync.has("wallet") and sync["wallet"].has("claims") and not sync["wallet"].has("log"),
		"syncable carries the cloud wallet"
	)
	check(
		PlayerProfile.SYNC_KEYS.has("wallet") and PlayerProfile.SYNC_KEYS.has("streak"),
		"wallet and streak are sync keys"
	)
	var fields: Dictionary = PlayerProfile.to_cloud_fields(q)
	check(fields.has("wallet") and fields.has("streak"), "encoded for Firestore")
	# Two devices: the cloud paid the same reward and one more; nothing is paid twice.
	var cloud_p: Dictionary = PlayerProfile.empty()
	Wallet.claim(cloud_p["wallet"], "lv1s3", 40)
	Wallet.claim(cloud_p["wallet"], "lv2s1", 18)
	cloud_p["streak"] = {"last": "2026-10-17", "len": 2, "best": 2, "grace": -1}
	cloud_p["updatedAt"] = int(q["updatedAt"]) + 10
	var merged: Dictionary = PlayerProfile.merge(q, cloud_p)
	check(
		Wallet.earned(merged["wallet"]) == 58 and Wallet.gems(merged["wallet"]) == 28,
		"profile merge: wallets union (%d)" % Wallet.gems(merged["wallet"])
	)
	check(
		merged["streak"]["last"] == "2026-10-17" and merged["streak"]["best"] == 6,
		"profile merge: the later streak, the best length"
	)
	# from_cloud clamps and migrates an old (schema 2) document without a wallet.
	var old_doc: Dictionary = PlayerProfile.from_cloud(
		{"schemaVersion": 2, "progression": {"unlocked": 3}}
	)
	check(
		(
			old_doc["wallet"] == Wallet.empty()
			and int(old_doc["schemaVersion"]) == PlayerProfile.SCHEMA_VERSION
		),
		"schema 2 cloud document migrates"
	)
	var rich: Dictionary = PlayerProfile.from_cloud(
		{
			"schemaVersion": 3,
			"wallet": {"claims": "a=9999999999", "buys": "", "equipped": ""},
			"streak": {"last": "bogus", "len": 99999}
		}
	)
	check(
		Wallet.gems(rich["wallet"]) == Wallet.limit("max_claim"),
		"from_cloud: a huge claim is clamped"
	)
	check(
		rich["streak"]["last"] == "" and rich["streak"]["len"] == 0,
		"from_cloud: a bad streak is dropped"
	)
	# A schema-2 save file (no wallet section) loads with an empty wallet.
	_wipe()
	var cfg: ConfigFile = LevelCatalog.data()
	cfg.set_value("profile", "schema", 2)
	cfg.set_value("progress", "unlocked", 3)
	LevelCatalog.commit()
	var m2: Dictionary = PlayerProfile.local()
	check(
		int(m2["schemaVersion"]) == PlayerProfile.SCHEMA_VERSION and Wallet.gems(m2["wallet"]) == 0,
		"a schema 2 save migrates"
	)


func _check_economy() -> void:
	_wipe()
	Economy.reset_tally()
	var one: int = Economy.award_level_win(1, 1, 0)
	check(one == Economy.level_star_reward(1, 1), "1 star pays the 1-star reward (%d)" % one)
	check(
		Economy.award_level_win(1, 1, 0) > 0 and Economy.award_level_win(1, 1, 0) > 0,
		"a repeat pays the small reward"
	)
	var cap: int = int(Wallet.data()["repeat_win"]["daily_cap"])
	var repeat_total: int = 0
	for i in 20:
		repeat_total += Economy.award_level_win(1, 1, 0)
	check(
		repeat_total + 2 * int(Wallet.data()["repeat_win"]["reward"]) <= cap,
		"repeat wins stop at the daily ceiling"
	)
	check(Economy.award_level_win(1, 1, 0) == 0, "at the ceiling nothing more")
	var upgrade: int = Economy.award_level_win(1, 3, 0)
	check(
		upgrade == Economy.level_star_reward(1, 2) + Economy.level_star_reward(1, 3),
		"better stars pay only the difference"
	)
	check(
		Economy.award_level_win(1, 3, 1) == Economy.crown_reward(1, 1),
		"a first Hard win pays the crown"
	)
	check(Economy.award_level_win(1, 3, 1) == 0, "the crown pays once (ceiling reached)")
	check(
		Economy.award_level_win(1, 3, 2) == Economy.crown_reward(1, 2), "Nightmare pays its crown"
	)
	check(Economy.award_siege(1, 4, false) == 0, "4 waves of a siege: no milestone")
	check(
		Economy.award_siege(1, 12, false) == Economy.siege_reward(1) + Economy.siege_reward(2),
		"12 waves: two milestones"
	)
	check(Economy.award_siege(1, 12, false) == 0, "milestones pay once")
	check(
		Economy.award_siege(1, 12, true) == int(Wallet.data()["siege"]["record_bonus"]),
		"a record bonus, once per day"
	)
	check(Economy.award_siege(1, 12, true) == 0, "the record bonus pays once a day")
	check(
		Economy.award_siege(1, 9999, false) > 0 and Economy.award_siege(1, 9999, false) == 0,
		"milestones are capped by max_steps"
	)
	var d1: int = Economy.award_daily("2026-10-17", 10)
	check(
		d1 == int(Wallet.data()["daily_challenge"]["base"]) + 5,
		"daily challenge: base + wave bonus (%d)" % d1
	)
	var d2: int = Economy.award_daily("2026-10-17", 14)
	check(d2 == 2, "a better run adds only the difference (%d)" % d2)
	check(Economy.award_daily("2026-10-17", 14) == 0, "the same result pays nothing")
	check(
		Economy.award_daily("garbage", 14) == 0 and Economy.award_daily("2026-10-18", 0) == 0,
		"bad input pays nothing"
	)
	var def: Dictionary = Achievements.get_def("hunter")
	check(Economy.award_achievement(def) == Economy.achievement_reward(def), "achievement pays")
	check(Economy.award_achievement(def) == 0, "achievement pays once")
	check(Economy.tally() > 0, "the tally counts")
	# Backfill pays progress made before gems existed, once, and never what is claimed.
	_wipe()
	LevelCatalog.complete(1, 3, 1)
	LevelCatalog.complete(2, 2, 0)
	LevelCatalog.save_endless(1, 11)
	var back: int = Economy.backfill()
	var expected: int = (
		Economy.level_star_reward(1, 1)
		+ Economy.level_star_reward(1, 2)
		+ Economy.level_star_reward(1, 3)
		+ Economy.crown_reward(1, 1)
		+ Economy.level_star_reward(2, 1)
		+ Economy.level_star_reward(2, 2)
		+ Economy.siege_reward(1)
		+ Economy.siege_reward(2)
	)
	check(back == expected, "backfill pays old progress (%d of %d)" % [back, expected])
	check(Economy.backfill() == 0, "backfill pays once")
	check(
		Economy.award_level_win(1, 3, 1) > 0 and Economy.balance() >= expected,
		"claims made by the backfill are not paid again"
	)
	var before: int = Economy.balance()
	Economy.award_siege(1, 11, false)
	check(Economy.balance() == before, "siege milestones paid by the backfill are not paid again")
	# An event multiplies awards; the lump of old progress is not multiplied.
	check(Economy.scaled(100, false) == 100, "no multiplier without the flag")
	_wipe()

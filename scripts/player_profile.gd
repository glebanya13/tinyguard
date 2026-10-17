class_name PlayerProfile
extends RefCounted
## Versioned player profile: one Dictionary used for the local save and the
## cloud document users/{uid}. Progression stays where LevelCatalog and Perks
## keep it (sections progress/perks/settings of user://progress.cfg); the
## [profile] section adds identity and onboarding fields. See docs/ACCOUNTS.md.
##
## Shape (schemaVersion 3; 2 added progression.crowns, 3 added wallet and streak):
## {schemaVersion, nickname, nicknameNormalized, createdAt, updatedAt (unix s),
##  onboardingCompleted, tutorialVersionCompleted,
##  progression: {unlocked, stars: {"1": 3}, endless: {"1": 23}, perks: {"axe": 1},
##                dailyStars: 2 (bonus stars of the daily challenge),
##                crowns: {"1": 2} (highest difficulty won above Normal: 1 Hard, 2 Nightmare)},
##  achievements: bit mask of unlocked achievements (resources/achievements.json),
##  wallet: gems, purchases and worn cosmetics (scripts/wallet.gd; the cloud form is
##          Wallet.to_cloud), streak: the day streak (scripts/streak.gd),
##  settings: {sound},
##  local only: nicknameVerified (reserved on the server), nicknameConflict
##  (the server said the name is taken), newer (cloud written by a newer app)}
## The Firebase uid is the stable id; the nickname is only a display name.

const SCHEMA_VERSION := 3
const SECTION := "profile"
## Upper bound for a stars / endless / perk value read from the cloud (the rules cap them too).
const MAX_CLOUD_VALUE := 5000
## Highest difficulty crown (1 Hard, 2 Nightmare; LevelCatalog.MAX_DIFFICULTY).
const MAX_CROWN := 2
## Tutorial version a player who already had progress before profiles existed
## is treated as having seen (they skip the tutorial).
const LEGACY_TUTORIAL_VERSION := 1
const SYNC_KEYS: Array[String] = [
	"schemaVersion",
	"onboardingCompleted",
	"tutorialVersionCompleted",
	"progression",
	"settings",
	"achievements",
	"wallet",
	"streak"
]


static func empty() -> Dictionary:
	return {
		"schemaVersion": SCHEMA_VERSION,
		"nickname": "",
		"nicknameNormalized": "",
		"nicknameVerified": false,
		"nicknameConflict": false,
		"createdAt": 0,
		"updatedAt": 0,
		"onboardingCompleted": false,
		"tutorialVersionCompleted": 0,
		"progression":
		{"unlocked": 1, "stars": {}, "endless": {}, "perks": {}, "dailyStars": 0, "crowns": {}},
		"settings": {"sound": true},
		"achievements": 0,
		"wallet": Wallet.empty(),
		"streak": Streak.empty(),
	}


## Profile of a save file, migrated to SCHEMA_VERSION. A save without the
## [profile] section is schema 0 (written before profiles existed).
static func from_save(cfg: ConfigFile) -> Dictionary:
	var p: Dictionary = empty()
	var prog: Dictionary = p["progression"]
	prog["unlocked"] = maxi(int(cfg.get_value("progress", "unlocked", 1)), 1)
	if cfg.has_section("progress"):
		for key: String in cfg.get_section_keys("progress"):
			var id: String = key.get_slice("_", 1)
			if key.begins_with("stars_") or key.begins_with("won_"):
				var stars: int = int(cfg.get_value("progress", "stars_" + id, 0))
				if stars == 0 and bool(cfg.get_value("progress", "won_" + id, false)):
					stars = 1  # won before stars existed
				if stars > 0:
					prog["stars"][id] = clampi(stars, 0, 3)
			elif key.begins_with("endless_"):
				prog["endless"][id] = maxi(int(cfg.get_value("progress", key, 0)), 0)
			elif key.begins_with("crown_"):
				var crown: int = clampi(int(cfg.get_value("progress", key, 0)), 0, MAX_CROWN)
				if crown > 0:
					prog["crowns"][id] = crown
	if cfg.has_section("perks"):
		for key: String in cfg.get_section_keys("perks"):
			prog["perks"][key] = maxi(int(cfg.get_value("perks", key, 0)), 0)
	p["settings"]["sound"] = bool(cfg.get_value("settings", "sound", true))
	prog["dailyStars"] = clampi(
		int(cfg.get_value(Daily.SECTION, "bonus_stars", 0)), 0, Daily.max_stars()
	)
	p["achievements"] = maxi(int(cfg.get_value(SECTION, "achievements", 0)), 0)
	p["wallet"] = Wallet.from_save(cfg)
	p["streak"] = Streak.from_save(cfg)
	if not cfg.has_section(SECTION):
		p["schemaVersion"] = 0
		p["legacyName"] = str(cfg.get_value("online", "name", ""))
		return migrate(p)
	p["schemaVersion"] = int(cfg.get_value(SECTION, "schema", SCHEMA_VERSION))
	p["nickname"] = str(cfg.get_value(SECTION, "nickname", ""))
	p["nicknameNormalized"] = str(cfg.get_value(SECTION, "nickname_normalized", ""))
	p["nicknameVerified"] = bool(cfg.get_value(SECTION, "nickname_verified", false))
	p["nicknameConflict"] = bool(cfg.get_value(SECTION, "nickname_conflict", false))
	p["createdAt"] = int(cfg.get_value(SECTION, "created_at", 0))
	p["updatedAt"] = int(cfg.get_value(SECTION, "updated_at", 0))
	p["onboardingCompleted"] = bool(cfg.get_value(SECTION, "onboarding_completed", false))
	p["tutorialVersionCompleted"] = int(cfg.get_value(SECTION, "tutorial_version", 0))
	return migrate(p)


## Writes the profile back into a save file (does not commit it).
static func write_to_save(p: Dictionary, cfg: ConfigFile) -> void:
	var prog: Dictionary = p["progression"]
	cfg.set_value("progress", "unlocked", int(prog["unlocked"]))
	for id: String in prog["stars"]:
		cfg.set_value("progress", "won_" + id, true)
		cfg.set_value("progress", "stars_" + id, int(prog["stars"][id]))
	for id: String in prog["endless"]:
		cfg.set_value("progress", "endless_" + id, int(prog["endless"][id]))
	if cfg.has_section("perks"):
		cfg.erase_section("perks")
	for id: String in prog["perks"]:
		cfg.set_value("perks", id, int(prog["perks"][id]))
	for id: String in prog.get("crowns", {}):
		cfg.set_value("progress", "crown_" + id, int(prog["crowns"][id]))
	cfg.set_value("settings", "sound", bool(p["settings"]["sound"]))
	if int(prog.get("dailyStars", 0)) > 0:
		cfg.set_value(Daily.SECTION, "bonus_stars", int(prog["dailyStars"]))
	cfg.set_value(SECTION, "achievements", int(p["achievements"]))
	Wallet.write_to_save(p["wallet"], cfg)
	Streak.write_to_save(p["streak"], cfg)
	cfg.set_value(SECTION, "schema", int(p["schemaVersion"]))
	cfg.set_value(SECTION, "nickname", str(p["nickname"]))
	cfg.set_value(SECTION, "nickname_normalized", str(p["nicknameNormalized"]))
	cfg.set_value(SECTION, "nickname_verified", bool(p["nicknameVerified"]))
	cfg.set_value(SECTION, "nickname_conflict", bool(p["nicknameConflict"]))
	cfg.set_value(SECTION, "created_at", int(p["createdAt"]))
	cfg.set_value(SECTION, "updated_at", int(p["updatedAt"]))
	cfg.set_value(SECTION, "onboarding_completed", bool(p["onboardingCompleted"]))
	cfg.set_value(SECTION, "tutorial_version", int(p["tutorialVersionCompleted"]))


## Brings any older profile up to SCHEMA_VERSION, one step at a time. A profile
## from a newer app is returned unchanged with "newer" set: never downgrade it.
static func migrate(p: Dictionary) -> Dictionary:
	var out: Dictionary = p.duplicate(true)
	var version: int = int(out.get("schemaVersion", 0))
	if version > SCHEMA_VERSION:
		out["newer"] = true
		return out
	if version < 1:
		out = _migrate_0_to_1(out)
	if version < 2:
		out = _migrate_1_to_2(out)
	if version < 3:
		out = _migrate_2_to_3(out)
	out["schemaVersion"] = SCHEMA_VERSION
	return out


## Per-field merge of two profiles of the same player (local and cloud).
## Progression only grows (max of unlocked, stars, records); perks come from
## the side that spent more stars on them (newer side on a tie); settings from
## the newer side; onboarding flags only move forward; a nickname reserved on
## the server wins over an unverified local one, but a pending local rename
## to another name is kept until the server answers.
static func merge(local: Dictionary, cloud: Dictionary) -> Dictionary:
	var out: Dictionary = local.duplicate(true)
	var cloud_newer: bool = int(cloud.get("updatedAt", 0)) > int(local.get("updatedAt", 0))
	var a: Dictionary = local["progression"]
	var b: Dictionary = cloud.get("progression", {})
	var prog: Dictionary = out["progression"]
	prog["unlocked"] = maxi(int(a["unlocked"]), int(b.get("unlocked", 1)))
	for key in ["stars", "endless", "crowns"]:
		var merged: Dictionary = (a.get(key, {}) as Dictionary).duplicate()
		var other: Dictionary = b.get(key, {})
		for id: String in other:
			merged[id] = maxi(int(merged.get(id, 0)), int(other[id]))
		prog[key] = merged
	prog["dailyStars"] = maxi(int(a.get("dailyStars", 0)), int(b.get("dailyStars", 0)))
	out["achievements"] = int(local.get("achievements", 0)) | int(cloud.get("achievements", 0))
	out["wallet"] = Wallet.merge(
		local.get("wallet", Wallet.empty()),
		cloud.get("wallet", Wallet.empty()),
		cloud_newer,
		Daily.today_key()
	)
	out["streak"] = Streak.merge(local.get("streak", {}), cloud.get("streak", {}))
	var local_spent: int = spent_stars(a["perks"])
	var cloud_spent: int = spent_stars(b.get("perks", {}))
	if cloud_spent > local_spent or (cloud_spent == local_spent and cloud_newer):
		prog["perks"] = (b.get("perks", {}) as Dictionary).duplicate()
	if cloud_newer and cloud.has("settings"):
		out["settings"] = (cloud["settings"] as Dictionary).duplicate()
	out["onboardingCompleted"] = (
		bool(local["onboardingCompleted"]) or bool(cloud.get("onboardingCompleted", false))
	)
	out["tutorialVersionCompleted"] = maxi(
		int(local["tutorialVersionCompleted"]), int(cloud.get("tutorialVersionCompleted", 0))
	)
	var cloud_name: String = str(cloud.get("nickname", ""))
	var pending_rename: bool = (
		str(local["nickname"]) != ""
		and not bool(local["nicknameVerified"])
		and str(local["nicknameNormalized"]) != str(cloud.get("nicknameNormalized", ""))
	)
	if cloud_name != "" and not pending_rename:
		out["nickname"] = cloud_name
		out["nicknameNormalized"] = str(cloud.get("nicknameNormalized", ""))
		out["nicknameVerified"] = true
		out["nicknameConflict"] = false
	var created: Array[int] = []
	for t: int in [int(local["createdAt"]), int(cloud.get("createdAt", 0))]:
		if t > 0:
			created.append(t)
	out["createdAt"] = created.min() if not created.is_empty() else 0
	out["updatedAt"] = maxi(int(local["updatedAt"]), int(cloud.get("updatedAt", 0)))
	out["schemaVersion"] = SCHEMA_VERSION
	return out


## The part of a profile the client syncs (nickname fields belong to the server).
static func syncable(p: Dictionary) -> Dictionary:
	var out := {}
	for key in SYNC_KEYS:
		out[key] = p[key]
	# The wallet syncs in its cloud form (no log, derived totals); see Wallet.to_cloud.
	out["wallet"] = Wallet.to_cloud(p["wallet"])
	return out


static func content_hash(p: Dictionary) -> String:
	return JSON.stringify(syncable(p), "", true).md5_text()


## Client-owned fields of users/{uid} in Firestore's typed form.
static func to_cloud_fields(p: Dictionary) -> Dictionary:
	return FirestoreClient.encode_fields(syncable(p))


## users/{uid} fields (already decoded) -> profile, migrated.
static func from_cloud(fields: Dictionary) -> Dictionary:
	var p: Dictionary = empty()
	p["schemaVersion"] = int(fields.get("schemaVersion", 0))
	for key in ["nickname", "nicknameNormalized"]:
		p[key] = str(fields.get(key, ""))
	p["nicknameVerified"] = p["nickname"] != ""
	p["createdAt"] = int(fields.get("createdAt", 0))
	p["updatedAt"] = int(fields.get("updatedAt", 0))
	p["onboardingCompleted"] = bool(fields.get("onboardingCompleted", false))
	p["tutorialVersionCompleted"] = int(fields.get("tutorialVersionCompleted", 0))
	var prog: Dictionary = (
		fields.get("progression", {}) if fields.get("progression") is Dictionary else {}
	)
	var out_prog: Dictionary = p["progression"]
	out_prog["unlocked"] = maxi(int(prog.get("unlocked", 1)), 1)
	if prog.get("dailyStars") is int:
		out_prog["dailyStars"] = clampi(int(prog["dailyStars"]), 0, Daily.max_stars())
	if fields.get("achievements") is int:
		# Only bits of achievements this app knows (the cloud is not trusted).
		p["achievements"] = int(fields["achievements"]) & Achievements.known_mask()
	for key in ["stars", "endless", "perks", "crowns"]:
		var source: Variant = prog.get(key, {})
		if source is Dictionary:
			for id: Variant in source:
				var value: Variant = source[id]
				if value is int:
					# A level has 0..3 stars; the cloud is not trusted to stay in range.
					var top: int = MAX_CLOUD_VALUE
					if key == "stars":
						top = 3
					elif key == "crowns":
						top = MAX_CROWN
					out_prog[key][str(id)] = clampi(value, 0, top)
	p["wallet"] = Wallet.from_cloud(fields.get("wallet"))
	p["streak"] = Streak.sanitize(fields.get("streak"))
	var settings: Variant = fields.get("settings", {})
	if settings is Dictionary:
		p["settings"]["sound"] = bool((settings as Dictionary).get("sound", true))
	if p["schemaVersion"] == 0:
		p["legacyName"] = ""
	return migrate(p)


## A cloud save from older versions (saves/{uid}: the whole progress.cfg text).
## Empty Dictionary if the text does not parse.
static func from_legacy_text(text: String) -> Dictionary:
	var cfg := ConfigFile.new()
	if text == "" or cfg.parse(text) != OK:
		return {}
	var p: Dictionary = from_save(cfg)
	p["nickname"] = ""  # a legacy cloud name was never reserved
	p["nicknameNormalized"] = ""
	p["nicknameVerified"] = false
	return p


## Stars spent on a set of perk levels ({"axe": 2, ...}).
static func spent_stars(perks: Dictionary) -> int:
	var total: int = 0
	for id: String in perks:
		var perk: PerkData = Perks.get_perk(StringName(id))
		if perk == null:
			continue
		for i in mini(int(perks[id]), perk.costs.size()):
			total += perk.costs[i]
	return total


static func has_progress(p: Dictionary) -> bool:
	var prog: Dictionary = p["progression"]
	return (
		int(prog["unlocked"]) > 1
		or not (prog["stars"] as Dictionary).is_empty()
		or not (prog["endless"] as Dictionary).is_empty()
	)


# --- The local profile (LevelCatalog's save file) ---


static func local() -> Dictionary:
	return from_save(LevelCatalog.data())


## Writes the local profile, refreshing updatedAt when the synced content changed.
static func save_local(p: Dictionary) -> void:
	var cfg: ConfigFile = LevelCatalog.data()
	var digest: String = content_hash(p)
	if digest != str(cfg.get_value(SECTION, "content_hash", "")) or int(p["updatedAt"]) == 0:
		p["updatedAt"] = maxi(int(Time.get_unix_time_from_system()), int(p["updatedAt"]))
		cfg.set_value(SECTION, "content_hash", digest)
	write_to_save(p, cfg)
	LevelCatalog.commit()


## Persists the migrated profile and a fresh updatedAt after local play.
## Idempotent; returns the local profile.
static func touch_local() -> Dictionary:
	var p: Dictionary = local()
	save_local(p)
	return p


## True when local progress changed since the last successful cloud sync.
static func is_pending() -> bool:
	var cfg: ConfigFile = LevelCatalog.data()
	return content_hash(local()) != str(cfg.get_value(SECTION, "synced_hash", ""))


static func mark_synced(p: Dictionary) -> void:
	LevelCatalog.data().set_value(SECTION, "synced_hash", content_hash(p))
	LevelCatalog.commit()


## Schema 2: difficulty crowns. Nothing to convert (an old save has none); the field exists.
static func _migrate_1_to_2(p: Dictionary) -> Dictionary:
	var prog: Dictionary = p.get("progression", {})
	if not prog.get("crowns") is Dictionary:
		prog["crowns"] = {}
	p["progression"] = prog
	return p


## Schema 3: the gem wallet and the day streak. Nothing to convert (older saves have
## neither); Economy.backfill pays the rewards of progress made before gems existed.
static func _migrate_2_to_3(p: Dictionary) -> Dictionary:
	if not p.get("wallet") is Dictionary:
		p["wallet"] = Wallet.empty()
	if not p.get("streak") is Dictionary:
		p["streak"] = Streak.empty()
	return p


static func _migrate_0_to_1(p: Dictionary) -> Dictionary:
	var veteran: bool = has_progress(p)
	var legacy: Dictionary = NicknameRules.validate(str(p.get("legacyName", "")))
	p.erase("legacyName")
	p["nickname"] = legacy["nickname"] if legacy["ok"] else ""
	p["nicknameNormalized"] = legacy["normalized"] if legacy["ok"] else ""
	p["nicknameVerified"] = false
	p["nicknameConflict"] = false
	p["onboardingCompleted"] = veteran
	p["tutorialVersionCompleted"] = LEGACY_TUTORIAL_VERSION if veteran else 0
	if int(p.get("createdAt", 0)) == 0:
		p["createdAt"] = int(Time.get_unix_time_from_system())
	return p

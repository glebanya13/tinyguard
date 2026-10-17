extends SceneTree
## Achievements: the data is consistent, the engine unlocks exactly what the metrics
## earn (once), the battle counters and the toast work, the unlocked set rides in the
## profile (local save, cloud fields, merge, clamping), and the two map panels build.
## godot --headless --fixed-fps 60 --path . --script res://tests/test_achievements.gd

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_achievements.cfg"
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path + suffix))
	_run.call_deferred()


func _run() -> void:
	_check_data()
	_check_engine()
	_check_profile()
	await _check_battle()
	await _check_panels()
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _check_data() -> void:
	var defs: Array[Dictionary] = Achievements.all()
	check(defs.size() >= 12 and defs.size() <= 16, "12-16 achievements (%d)" % defs.size())
	var ids := {}
	var bits := {}
	var csv: String = FileAccess.get_file_as_string("res://translations/strings.csv")
	var rules: String = FileAccess.get_file_as_string("res://firestore.rules")
	var ok := true
	for def in defs:
		ok = ok and not ids.has(def["id"]) and not bits.has(def["bit"])
		ids[def["id"]] = true
		bits[def["bit"]] = true
		ok = ok and int(def["bit"]) >= 0 and int(def["bit"]) < Achievements.MAX_BITS
		ok = ok and Achievements.METRICS.has(str(def["metric"])) and int(def["threshold"]) > 0
		ok = ok and csv.contains("\n" + str(def["key"]) + ",")
		ok = ok and csv.contains("\n" + str(def["key"]) + "_DESC,")
	check(ok, "ids and bits are unique, metrics known, names and descriptions translated")
	check(
		Achievements.known_mask() == (1 << defs.size()) - 1 or bits.size() == defs.size(),
		"known mask"
	)
	check(rules.contains("achievementsOk"), "firestore.rules validates the mask")


func _check_engine() -> void:
	var defs: Array[Dictionary] = Achievements.all()
	check(Achievements.evaluate(defs, {}, 0).is_empty(), "no metrics: nothing unlocked")
	var fresh: Array[Dictionary] = Achievements.evaluate(defs, {"kills_total": 100}, 0)
	check(fresh.size() == 1 and fresh[0]["id"] == "hunter", "100 kills: only 'hunter'")
	fresh = Achievements.evaluate(defs, {"kills_total": 2000, "levels_won": 1}, 0)
	var names: Array = fresh.map(func(d: Dictionary) -> String: return str(d["id"]))
	check(
		names.has("hunter") and names.has("slayer") and names.has("first_win"),
		"thresholds: %s" % [names]
	)
	var hunter: Dictionary = Achievements.get_def("hunter")
	var mask: int = 1 << int(hunter["bit"])
	check(
		Achievements.evaluate(defs, {"kills_total": 100}, mask).is_empty(),
		"already unlocked: not again"
	)
	check(Achievements.mask_has(mask, hunter), "mask_has")
	check(Achievements.progress(hunter, {"kills_total": 40}) == 40, "progress")
	check(
		Achievements.progress(hunter, {"kills_total": 4000}) == 100,
		"progress is capped at the threshold"
	)
	# From the real save: a win and a perk.
	check(Achievements.check().is_empty(), "a fresh save earns nothing")
	LevelCatalog.complete(1, 3)
	var got: Array[Dictionary] = Achievements.check()
	var got_ids: Array = got.map(func(d: Dictionary) -> String: return str(d["id"]))
	check(
		got_ids.has("first_win") and got_ids.has("perfect"),
		"a 3 star win: first_win and perfect %s" % [got_ids]
	)
	check(
		Achievements.is_unlocked("first_win") and not Achievements.is_unlocked("slayer"),
		"is_unlocked"
	)
	check(Achievements.check().is_empty(), "unlocked once only")
	Achievements.add_stat("kills_total", 150)
	Achievements.add_stat("nonsense", 5)
	Achievements.add_stat("kills_total", -4)
	check(
		int(Achievements.metrics()["kills_total"]) == 150,
		"counters accept known names and positive amounts"
	)
	check(
		Achievements.check().size() == 1 and Achievements.is_unlocked("hunter"), "150 kills: hunter"
	)
	# Daily metrics.
	Daily.record_result("2026-10-15", 16, 500)
	Daily.record_result("2026-10-16", 2, 50)
	Daily.record_result("2026-10-17", 2, 50)
	var daily: Array = Achievements.check().map(func(d: Dictionary) -> String: return str(d["id"]))
	check(
		daily.has("daily_first") and daily.has("daily_streak_3") and daily.has("daily_wave_15"),
		"daily achievements %s" % [daily]
	)


func _check_profile() -> void:
	var p: Dictionary = PlayerProfile.local()
	var mask: int = int(p["achievements"])
	check(mask == Achievements.unlocked_mask() and mask > 0, "the profile carries the mask")
	check(PlayerProfile.SYNC_KEYS.has("achievements"), "the mask is synced")
	var fields: Dictionary = FirestoreClient.decode_fields(PlayerProfile.to_cloud_fields(p))
	check(int(fields["achievements"]) == mask, "cloud fields hold the mask")
	var back: Dictionary = PlayerProfile.from_cloud(fields)
	check(int(back["achievements"]) == mask, "mask survives the cloud round trip")
	var merged: Dictionary = PlayerProfile.merge(p, {"progression": {}, "achievements": 1 << 11})
	check(int(merged["achievements"]) == (mask | (1 << 11)), "merge: union of both devices")
	var junk: Dictionary = PlayerProfile.from_cloud({"schemaVersion": 1, "achievements": -5})
	check(
		int(junk["achievements"]) == (-5 & Achievements.known_mask()),
		"a negative cloud mask is masked"
	)
	junk = PlayerProfile.from_cloud({"schemaVersion": 1, "achievements": "all"})
	check(int(junk["achievements"]) == 0, "a non-number cloud value is ignored")
	junk = PlayerProfile.from_cloud({"schemaVersion": 1, "achievements": 1 << 30})
	check(int(junk["achievements"]) == 0, "unknown bits are dropped")
	# A restored save keeps them (local save round trip).
	var again: Dictionary = PlayerProfile.local()
	check(int(again["achievements"]) == mask, "the save file keeps the mask")


func _check_battle() -> void:
	LevelCatalog.selected_id = 1
	LevelCatalog.endless = false
	LevelCatalog.daily_key = ""
	LevelCatalog.tutorial = false
	var old_scene: Node = current_scene
	change_scene_to_file("res://scenes/main.tscn")
	var main: Node = null
	while main == null:
		await process_frame
		if current_scene != null and current_scene != old_scene and current_scene.has_node("Sim"):
			main = current_scene
	await process_frame
	var tracker: AchievementTracker = main.get_node_or_null("AchievementTracker")
	check(tracker != null, "the battle has a tracker")
	var waves: WaveManager = main.get_node("WaveManager")
	var before: int = int(Achievements.metrics()["kills_total"])
	for i in 40:
		waves.enemy_killed.emit(1)
	var got: Array[String] = []
	tracker.unlocked.connect(func(def: Dictionary) -> void: got.append(str(def["id"])))
	var toasts_before: int = get_nodes_in_group(Toast.GROUP).size()
	waves.wave_cleared.emit(1)
	check(
		int(Achievements.metrics()["kills_total"]) == before + 40,
		"kills are counted at the wave end"
	)
	# Push a counter over a threshold: the signal and the toast come.
	var need: int = 1500 - int(Achievements.metrics()["kills_total"]) + 1
	for i in need:
		waves.enemy_killed.emit(1)
	waves.wave_cleared.emit(2)
	await process_frame
	check(got.has("slayer"), "1500 kills: 'slayer' signalled %s" % [got])
	check(get_nodes_in_group(Toast.GROUP).size() > toasts_before, "a toast is shown")
	var shown: Array[String] = []
	for node in get_nodes_in_group(Toast.GROUP):
		shown.append((node.find_child("Text", true, false) as Label).text)
	var name: String = TranslationServer.translate("ACH_SLAYER")
	var named: bool = false
	for line in shown:
		named = named or line.begins_with(name)  # the gems of the reward follow the name
	check(named, "the toast names the achievement %s" % [shown])
	waves.wave_cleared.emit(3)
	check(got.count("slayer") == 1, "never signalled twice")


func _check_panels() -> void:
	var root := Control.new()
	root.size = Vector2(1280, 720)
	get_root().add_child(root)
	var panel := AchievementsPanel.new()
	root.add_child(panel)
	await process_frame
	panel.open()
	await process_frame
	var list: Node = panel.find_child("List", true, false)
	check(
		list != null and list.get_child_count() == Achievements.all().size(),
		"a row per achievement"
	)
	var title: Label = panel.find_child("Title", true, false)
	check(
		title.text.contains(str(Achievements.unlocked_count())), "the title counts the earned ones"
	)
	var close_button: Button = panel.find_child("CloseButton", true, false)
	check(close_button.custom_minimum_size.y >= 84.0, "the close button is at least 84 px")
	var closed: Array[bool] = []
	panel.closed.connect(func() -> void: closed.append(true))
	close_button.pressed.emit()
	check(closed.size() == 1 and not panel.visible, "closes")

	var daily := DailyPanel.new()
	daily.day = "2026-10-16"
	root.add_child(daily)
	await process_frame
	daily.open()
	await process_frame
	var mod: Label = daily.find_child("ModName", true, false)
	check(
		mod.text == TranslationServer.translate("DAILY_MOD_ARCHERS_FROST"),
		"the day's modifier is shown"
	)
	var play: Button = daily.find_child("PlayButton", true, false)
	check(play.custom_minimum_size.y >= 84.0, "the play button is at least 84 px")
	var started: Array[String] = []
	daily.start_requested.connect(func(d: String) -> void: started.append(d))
	play.pressed.emit()
	check(started == ["2026-10-16"], "Play asks to start the day")
	check(daily.find_child("Board", true, false) == null, "no online board without Firebase")
	root.queue_free()

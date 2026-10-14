extends SceneTree
## Stars, perks bought with them and the endless siege.
## godot --headless --fixed-fps 60 --path . --script res://tests/test_meta.gd

const SAVE := "user://test_meta.cfg"

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = SAVE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	_run.call_deferred()


func _run() -> void:
	check(Perks.earned_stars() == 0 and Perks.free_stars() == 0, "no stars at first")
	LevelCatalog.complete(1, 3)
	LevelCatalog.save_endless(1, 23)
	check(Perks.endless_stars(1) == 2, "endless: 23 waves = 2 stars")
	check(Perks.earned_stars() == 5, "3 campaign + 2 endless stars")
	var gold: PerkData = Perks.get_perk(&"gold_start")
	check(Perks.buy(gold) and Perks.level(&"gold_start") == 1, "bought +15 gold")
	check(Perks.free_stars() == 4, "1 star spent")
	check(not Perks.buy(Perks.get_perk(&"axe")) or Perks.free_stars() >= 0, "never below zero")
	check(gold.format_value(1) == "+15", "perk value text")
	check(Perks.get_perk(&"sword").format_value(2) == "+40%", "percent perk text")

	LevelCatalog.selected_id = 1
	LevelCatalog.endless = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 10:
		await process_frame
	var main := current_scene
	var gs: GameState = main.get_node("GameState")
	var wm: WaveManager = main.get_node("WaveManager")
	check(gs.gold == 15, "perk gives starting gold (%d)" % gs.gold)
	check(wm.plan.endless and wm.get_total_waves() > 1000, "endless plan")
	check(
		wm.plan.is_boss_wave(10) and not wm.plan.is_boss_wave(15), "endless bosses every 10 waves"
	)
	main._waves_cleared = 31
	gs.lose_lives(999)
	await process_frame
	check(LevelCatalog.endless_record(1) == 31, "endless record saved")
	check(Perks.endless_stars(1) == 3, "record raises stars")
	Perks.reset()
	check(Perks.spent_stars() == 0, "perks reset")
	LevelCatalog.endless = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)

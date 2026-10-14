extends SceneTree
## Online module without network: disabled without firebase.cfg, parsing of
## Firestore replies, nickname cleanup, cloud restore of the progress text.
## godot --headless --path . --script res://tests/test_online.gd

const SAVE := "user://test_online.cfg"

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
	var online: Node = root.get_node("Online")
	if not FileAccess.file_exists("res://firebase.cfg"):
		check(not online.is_configured(), "offline without firebase.cfg")
	var reply: Variant = JSON.parse_string(
		(
			'[{"document": {"fields": {"name": {"stringValue": "Аня"},'
			+ ' "wave": {"integerValue": "42"}}}},'
			+ ' {"document": {"fields": {"name": {"stringValue": "Bo"},'
			+ ' "wave": {"integerValue": "7"}}}}, {"readTime": "x"}]'
		)
	)
	var rows: Array = online.parse_leaderboard(reply)
	check(
		rows.size() == 2 and rows[0]["name"] == "Аня" and rows[0]["wave"] == 42,
		"leaderboard parsed"
	)
	check(online.parse_leaderboard(null).is_empty(), "bad reply -> empty board")
	check(
		online.clean_name("  Сэр\tЛанселот Озёрный Великий ") == "СэрЛанселот Озёр", "name cleaned"
	)
	var doc: Variant = JSON.parse_string(
		'{"fields": {"progress": {"stringValue": "[a]\\nb=1\\n"}}}'
	)
	check(online.parse_save(doc) == "[a]\nb=1\n", "save text parsed")
	LevelCatalog.complete(1, 2)
	var text: String = LevelCatalog.data().encode_to_text()
	LevelCatalog.complete(2, 3)
	check(
		LevelCatalog.replace_with(text) and LevelCatalog.stars(2) == 0,
		"cloud restore replaces progress"
	)
	check(LevelCatalog.stars(1) == 2, "restored stars kept")
	check(not LevelCatalog.replace_with("[[[ broken"), "broken cloud text rejected")
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE) + suffix)
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)

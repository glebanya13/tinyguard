extends SceneTree
## The online board of the daily challenge against the fake Firebase (no network): a
## result is sent and kept only upwards, a lost network keeps it queued, a result for
## another day is refused and dropped, the board is read best first, account deletion
## removes the entries, and nothing is sent without Firebase.
## godot --headless --path . --script res://tests/test_daily_online.gd

const Fakes := preload("res://tests/fakes.gd")
const SAVE := "user://test_daily_online.cfg"
const SESSION := "user://test_daily_online_session.cfg"

var fails := 0
var _board: Array = []
var _board_day: String = ""


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = SAVE
	SessionStore.path = SESSION
	_clean()
	_run.call_deferred()


func _clean() -> void:
	LevelCatalog.erase_all()
	SessionStore.clear()


func _online(fake: Fakes.FakeFirebase) -> Node:
	var online: Node = root.get_node("Online")
	var t := Fakes.FakeTransport.new()
	t.handler = fake.handle
	online.setup("test-key", "test-project", t)
	online.auth.backoff_scale = 0.0
	online.firestore.backoff_scale = 0.0
	return online


func _run() -> void:
	var today: String = Daily.today_key()
	var path: String = "daily/%s/scores/uid1" % today
	var online: Node = root.get_node("Online")
	if not online.daily_loaded.is_connected(_on_board):
		online.daily_loaded.connect(_on_board)

	# Without Firebase nothing happens (the game is fully offline).
	_clean()
	var silent := Fakes.FakeTransport.new()
	silent.handler = Fakes.FakeFirebase.new().handle
	online.setup("", "", silent)
	await online.submit_daily(today, 5)
	check(
		not online.has_pending_daily() and silent.calls.is_empty(),
		"no Firebase: nothing queued or sent"
	)
	await online.fetch_daily(today)
	check(_board.is_empty() and _board_day == today, "no Firebase: an empty board")

	# A normal result.
	_clean()
	var fake := Fakes.FakeFirebase.new()
	online = _online(fake)
	await online.start()
	await online.submit_daily(today, 7)
	check(fake.docs.has(path) and fake.docs[path]["wave"] == 7, "the result is on the board")
	check(fake.docs[path]["name"] == "Рыцарь", "anonymous name")
	check(not online.has_pending_daily(), "the queue is empty after sending")
	await online.submit_daily(today, 9)
	check(fake.docs[path]["wave"] == 9, "a better result replaces it")
	await online.submit_daily(today, 5)
	check(fake.docs[path]["wave"] == 9, "a worse result never lowers it (refused by the rules)")
	check(not online.has_pending_daily(), "a refused result is dropped, not retried forever")

	# The network is lost: the result waits in the save and goes out later.
	fake.offline = true
	await online.submit_daily(today, 12)
	check(
		online.has_pending_daily() and fake.docs[path]["wave"] == 9,
		"offline: queued, board unchanged"
	)
	await online.flush_daily()
	check(online.has_pending_daily(), "still offline: still queued")
	fake.offline = false
	await online.flush_daily()
	check(
		fake.docs[path]["wave"] == 12 and not online.has_pending_daily(), "back online: sent once"
	)
	var commits: int = fake.all_commits.size()
	await online.flush_daily()
	check(fake.all_commits.size() == commits, "an empty queue sends nothing")

	# The queue survives a restart of the game (it is in the save file).
	fake.offline = true
	await online.submit_daily(today, 14)
	LevelCatalog._save = null  # reload from disk
	check(online.has_pending_daily(), "the queue is in the save file")
	fake.offline = false
	await online.flush_daily()
	check(fake.docs[path]["wave"] == 14, "sent after the restart")

	# Another day than the server's today is refused and dropped.
	await online.submit_daily("2020-01-01", 6)
	check(not fake.docs.has("daily/2020-01-01/scores/uid1"), "an old day is refused")
	check(not online.has_pending_daily(), "...and dropped")
	var tomorrow: String = Daily.key_for(int(Time.get_unix_time_from_system()) + 86400)
	await online.submit_daily(tomorrow, 6)
	check(not fake.docs.has("daily/%s/scores/uid1" % tomorrow), "a future day is refused")
	# One hour after midnight is still today's grace for yesterday.
	var midnight: int = int(Time.get_unix_time_from_datetime_string(today + "T00:00:00"))
	fake.server_time = midnight + 1800
	var yesterday: String = Daily.yesterday_key(today)
	await online.submit_daily(yesterday, 3)
	check(
		fake.docs.has("daily/%s/scores/uid1" % yesterday),
		"yesterday is accepted just after midnight"
	)
	fake.server_time = midnight + 7200
	await online.submit_daily(yesterday, 4)
	check(fake.docs["daily/%s/scores/uid1" % yesterday]["wave"] == 3, "...but not two hours after")
	fake.server_time = 0
	# A bad day text or wave is not sent at all.
	var sent: int = fake.all_commits.size()
	await online.submit_daily("not-a-day", 5)
	await online.submit_daily(today, 0)
	check(
		fake.all_commits.size() == sent and not online.has_pending_daily(), "bad input is ignored"
	)

	# A result queued by another account is not sent by this one.
	var cfg: ConfigFile = LevelCatalog.data()
	cfg.set_value(online.DAILY_SECTION, "day", today)
	cfg.set_value(online.DAILY_SECTION, "wave", 99)
	cfg.set_value(online.DAILY_SECTION, "uid", "someone-else")
	await online.flush_daily()
	check(
		fake.docs[path]["wave"] == 14 and not online.has_pending_daily(),
		"another account's queue is dropped"
	)

	# Reading the board: best first.
	fake.docs["daily/%s/scores/uid7" % today] = {"name": "Ann", "wave": 20}
	fake.docs["daily/%s/scores/uid8" % today] = {"name": "Bob", "wave": 3}
	await online.fetch_daily(today)
	check(
		_board.size() == 3 and _board[0]["name"] == "Ann" and _board[2]["wave"] == 3,
		"board order %s" % [_board]
	)
	check(_board[1]["wave"] == 14, "own entry in the middle")
	fake.offline = true
	await online.fetch_daily(today)
	check(_board.is_empty(), "offline: an empty board, no error")
	fake.offline = false

	# Deleting the account removes the entries.
	var gone: Dictionary = await online.delete_account()
	check(gone["ok"], "account deleted")
	check(not fake.docs.has(path), "today's entry is deleted with the account")

	_clean()
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE) + suffix)
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _on_board(day: String, entries: Array) -> void:
	_board_day = day
	_board = entries

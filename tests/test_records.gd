extends SceneTree
## Endless record queue: run start + record survive a lost network, are sent once,
## a run that never started online stays local. Fake server, no network.
## godot --headless --path . --script res://tests/test_records.gd

const Fakes := preload("res://tests/fakes.gd")
const SAVE := "user://test_records.cfg"
const SESSION := "user://test_records_session.cfg"

var fails := 0


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
	online.retry_base = 0.02
	return online


func _score_commits(fake: Fakes.FakeFirebase) -> int:
	var n := 0
	for writes: Array in fake.all_commits:
		for w: Dictionary in writes:
			if "/scores/" in str(w.get("update", {}).get("name", "")):
				n += 1
	return n


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout  # game time, like the retry timer


func _run() -> void:
	await _test_normal()
	await _test_network_lost()
	await _test_restart()
	await _test_refused()
	await _test_offline_run()
	await _test_new_run_drops_old()
	_clean()
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE) + suffix)
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _test_normal() -> void:
	_clean()
	var fake := Fakes.FakeFirebase.new()
	var online: Node = _online(fake)
	await online.start()
	check(await online.start_run(2), "run started")
	await online.submit_record(2, 9)
	check(fake.docs["leaderboards/level_2/scores/uid1"]["wave"] == 9, "record on the board")
	check(not online.has_pending_record(), "queue empty after sending")
	await online.flush_records()
	check(_score_commits(fake) == 1, "no duplicate send")


func _test_network_lost() -> void:
	_clean()
	var fake := Fakes.FakeFirebase.new()
	var online: Node = _online(fake)
	await online.start()
	await online.start_run(1)
	fake.offline = true
	await online.submit_record(1, 7)
	check(online.has_pending_record(), "network lost: record stays queued")
	check(not fake.docs.has("leaderboards/level_1/scores/uid1"), "nothing on the board yet")
	var tries: int = fake.all_commits.size()
	await _wait(0.3)
	check(fake.all_commits.size() == tries, "offline: nothing reaches the server")
	fake.offline = false
	await _wait(0.5)
	check(
		(
			fake.docs.has("leaderboards/level_1/scores/uid1")
			and fake.docs["leaderboards/level_1/scores/uid1"]["wave"] == 7
		),
		"network back: the retry delivers the record"
	)
	check(not online.has_pending_record() and _score_commits(fake) == 1, "queue cleared, sent once")
	# A higher record replaces the queued lower one.
	fake.offline = true
	await online.submit_record(1, 8)
	await online.submit_record(1, 11)
	fake.offline = false
	await _wait(0.8)
	check(fake.docs["leaderboards/level_1/scores/uid1"]["wave"] == 11, "the best queued wave wins")


func _test_restart() -> void:
	_clean()
	var fake := Fakes.FakeFirebase.new()
	var online: Node = _online(fake)
	await online.start()
	await online.start_run(3)
	fake.offline = true
	await online.submit_record(3, 5)
	check(online.has_pending_record(), "queued before the 'restart'")
	# New app start with the network back: start() flushes the queue.
	fake.offline = false
	online = _online(fake)
	await online.start()
	await _wait(0.2)
	check(
		fake.docs.has("leaderboards/level_3/scores/uid1"), "queued record sent at the next launch"
	)
	check(not online.has_pending_record(), "queue cleared after the launch")


func _test_refused() -> void:
	_clean()
	var fake := Fakes.FakeFirebase.new()
	var online: Node = _online(fake)
	await online.start()
	await online.start_run(1)
	fake.refuse_commits = 1
	await online.submit_record(1, 4)
	check(
		not online.has_pending_record(),
		"a refusal by the rules drops the record (no endless retry)"
	)
	check(
		LevelCatalog.save_endless(1, 4), "the local record is a separate thing and stays saveable"
	)


func _test_offline_run() -> void:
	_clean()
	var fake := Fakes.FakeFirebase.new()
	var online: Node = _online(fake)
	await online.start()
	fake.offline = true
	check(not await online.start_run(1), "run start lost")
	LevelCatalog.save_endless(1, 6)
	await online.submit_record(1, 6)
	fake.offline = false
	check(not online.has_pending_record(), "no run on the server: nothing is queued")
	await _wait(0.1)
	check(not fake.docs.has("leaderboards/level_1/scores/uid1"), "no back-dated board entry")
	check(LevelCatalog.endless_record(1) == 6, "the local record is kept")


func _test_new_run_drops_old() -> void:
	_clean()
	var fake := Fakes.FakeFirebase.new()
	var online: Node = _online(fake)
	await online.start()
	await online.start_run(1)
	fake.offline = true
	await online.submit_record(1, 5)
	fake.offline = false
	await online.start_run(2)
	check(not online.has_pending_record(), "a new run start drops the old queued record")
	await _wait(0.2)
	check(not fake.docs.has("leaderboards/level_1/scores/uid1"), "old record never sent")

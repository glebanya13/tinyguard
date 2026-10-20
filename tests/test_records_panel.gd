extends SceneTree
## The records window never leaves "Loading..." on the screen: a table, "nobody yet", a refusal
## (403), no internet, a request that hangs (the deadline), no Firebase at all, an error reply.
## Failures offer Retry; the cloud buttons show their result and are free again afterwards.
## Fake server, no network.
## godot --headless --fixed-fps 60 --path . --script res://tests/test_records_panel.gd

const Fakes := preload("res://tests/fakes.gd")
const SAVE := "user://test_records_panel.cfg"
const SESSION := "user://test_records_panel_session.cfg"
const LEVEL := 1

var fails := 0
var _online: Node = null
var _fake: Fakes.FakeFirebase = null
var _transport: Fakes.FakeTransport = null


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = SAVE
	SessionStore.path = SESSION
	GameSettings.config_path = "user://test_records_panel_settings.cfg"
	GameSettings.set_language("ru")
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _setup(configured: bool = true) -> void:
	LevelCatalog.erase_all()
	SessionStore.clear()
	_online = root.get_node("Online")
	_fake = Fakes.FakeFirebase.new()
	_transport = Fakes.FakeTransport.new()
	_transport.handler = _fake.handle
	_online.setup(
		"test-key" if configured else "", "test-project" if configured else "", _transport
	)
	_online.auth.backoff_scale = 0.0
	_online.firestore.backoff_scale = 0.0
	_online._ctx.records.fetch_timeout = 0.4


func _panel() -> RecordsPanel:
	var panel := RecordsPanel.new()
	panel.online = _online
	root.add_child(panel)
	return panel


## Waits (at most 3 s of frames) until the panel left the loading state.
func _settle(panel: RecordsPanel) -> void:
	for i in 180:
		if panel.state != RecordsPanel.STATE_LOADING:
			break
		await process_frame
	await _frames(2)


func _run() -> void:
	# 1. A table: rows, no error, no retry, the spinner is gone.
	_setup()
	for i in 3:
		_fake.docs["leaderboards/level_1/scores/u%d" % i] = {"name": "Рыцарь%d" % i, "wave": 10 + i}
	var panel := _panel()
	panel.open(LEVEL, "Зелёная долина")
	check(panel.state == RecordsPanel.STATE_LOADING, "the request is under way: loading")
	check(panel.status_text() == tr("MAP_LOADING"), "loading text shown")
	check(panel._spinner.visible and panel._spin_tween != null, "an animated spinner is shown")
	await _settle(panel)
	check(panel.rows() == 3, "table: 3 rows (%d)" % panel.rows())
	check(panel.status_text() == "" and not panel._spinner.visible, "table: no status, no spinner")
	check(not panel.is_retry_visible(), "table: no Retry")
	check(panel._spin_tween == null, "table: the spinner animation is stopped")
	panel.queue_free()
	await _frames(2)

	# 2. Nobody yet.
	_setup()
	panel = _panel()
	panel.open(LEVEL, "Зелёная долина")
	await _settle(panel)
	check(panel.status_text() == tr("MAP_NO_RECORDS"), "empty table: 'be the first'")
	check(panel.rows() == 0 and not panel.is_retry_visible(), "empty table: no rows, no Retry")
	panel.queue_free()
	await _frames(2)

	# 3. The rules refuse the list (403 PERMISSION_DENIED).
	_setup()
	_fake.forced_raw["leaderboards/level_1"] = [
		403, {"error": {"code": 403, "status": "PERMISSION_DENIED"}}
	]
	panel = _panel()
	panel.open(LEVEL, "Зелёная долина")
	await _settle(panel)
	check(panel.status_text() == tr("MAP_REC_DENIED"), "403: a clear message")
	check(panel.is_retry_visible(), "403: Retry offered")
	check(not panel._spinner.visible, "403: no spinner")
	# Retry after the server got better.
	_fake.forced_raw.clear()
	_fake.docs["leaderboards/level_1/scores/u9"] = {"name": "Аня", "wave": 7}
	panel._retry.pressed.emit()
	check(
		panel.state == RecordsPanel.STATE_LOADING and not panel.is_retry_visible(),
		"Retry loads again"
	)
	await _settle(panel)
	check(panel.rows() == 1 and not panel.is_retry_visible(), "Retry: the table appears")
	panel.queue_free()
	await _frames(2)

	# 4. Offline.
	_setup()
	_fake.offline = true
	panel = _panel()
	panel.open(LEVEL, "Зелёная долина")
	await _settle(panel)
	check(panel.status_text() == tr("MAP_REC_OFFLINE"), "offline: 'internet needed'")
	check(panel.is_retry_visible(), "offline: Retry offered")
	panel.queue_free()
	await _frames(2)

	# 5. A request that never answers: the deadline ends the wait.
	_setup()
	_transport.hang_fragment = "runQuery"
	panel = _panel()
	var started: int = Time.get_ticks_msec()
	panel.open(LEVEL, "Зелёная долина")
	await _settle(panel)
	var waited: float = (Time.get_ticks_msec() - started) / 1000.0
	check(waited < 3.0, "a hanging request ends by the deadline (%.1f s)" % waited)
	check(panel.status_text() == tr("MAP_REC_FAILED"), "timeout: 'could not load'")
	check(panel.is_retry_visible(), "timeout: Retry offered")
	check(
		OnlineRecords.new(OnlineContext.new()).fetch_timeout >= 8.0, "the real deadline is 8-10 s"
	)
	_transport.hang_fragment = ""
	panel._retry.pressed.emit()
	await _settle(panel)
	check(
		panel.state == RecordsPanel.STATE_DONE and not panel.is_retry_visible(),
		"Retry after a hang works"
	)
	panel.queue_free()
	await _frames(2)

	# 6. Server error (500 on every attempt).
	_setup()
	_fake.forced_raw["leaderboards/level_1"] = [500, {"error": {"code": 500}}]
	panel = _panel()
	panel.open(LEVEL, "Зелёная долина")
	await _settle(panel)
	check(
		panel.status_text() == tr("MAP_REC_FAILED") and panel.is_retry_visible(),
		"500: message and Retry"
	)
	panel.queue_free()
	await _frames(2)

	# 7. No firebase.cfg (not configured): answers at once, no request, no Retry.
	_setup(false)
	panel = _panel()
	panel.open(LEVEL, "Зелёная долина")
	await _settle(panel)
	check(panel.status_text() == tr("MAP_REC_DISABLED"), "no Firebase: says so")
	check(
		not panel.is_retry_visible() and _transport.calls.is_empty(),
		"no Firebase: no Retry, no request"
	)
	panel.queue_free()
	await _frames(2)

	# 8. English texts exist and differ.
	GameSettings.set_language("en")
	check(tr("MAP_REC_OFFLINE") == "Internet needed", "English: offline text")
	check(
		tr("MAP_RETRY") == "Retry" and tr("MAP_NO_RECORDS").begins_with("No records"),
		"English texts"
	)
	GameSettings.set_language("ru")

	# 9. The cloud buttons: a result line, free again; they never block the panel.
	_setup()
	panel = _panel()
	panel.open(LEVEL, "Зелёная долина")
	await _settle(panel)
	panel._to_cloud.pressed.emit()
	check(
		panel._to_cloud.disabled and panel.note_text() == tr("SYNC_SYNCING"), "to cloud: busy line"
	)
	check(
		panel.visible and not panel._frame.dim.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"the panel stays usable"
	)
	for i in 240:
		if not panel._to_cloud.disabled:
			break
		await process_frame
	check(
		not panel._to_cloud.disabled and not panel._from_cloud.disabled,
		"to cloud: buttons free again"
	)
	check(
		panel.note_text() != "" and panel.note_text() != tr("SYNC_SYNCING"),
		"to cloud: a result is shown ('%s')" % panel.note_text()
	)
	_fake.offline = true
	panel._from_cloud.pressed.emit()
	for i in 240:
		if not panel._from_cloud.disabled:
			break
		await process_frame
	check(not panel._from_cloud.disabled, "from cloud offline: buttons free again")
	check(
		panel.note_text() != "" and panel.note_text() != tr("SYNC_SYNCING"),
		"from cloud offline: an error is shown ('%s')" % panel.note_text()
	)
	panel.queue_free()
	await _frames(2)

	LevelCatalog.erase_all()
	SessionStore.clear()
	_online.setup("", "", HttpTransport.new())
	GameSettings.set_language("auto")
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)

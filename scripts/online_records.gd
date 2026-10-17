class_name OnlineRecords
extends RefCounted
## Endless records of Online: the run start (runs/{uid}), the queued record with
## retries, level leaderboards and the parsing of Firestore replies into plain data.
## The queue lives in the local save so a record survives a closed app.

const LEADERBOARD_SIZE := 10
const NAME_MAX := 16
## Leaderboard name of players without a reserved nickname (firestore.rules).
const ANONYMOUS_NAME := "Рыцарь"  # i18n:keep (server-side name)
## Local save section of the endless record queue (run start + unsent record).
const RECORD_SECTION := "record_queue"
const RETRY_MAX := 300.0
const MAX_RETRIES := 8

var _ctx: OnlineContext
var _retry_delay: float = 5.0
var _retries: int = 0
var _record_busy: bool = false


func _init(context: OnlineContext) -> void:
	_ctx = context


## Firestore runQuery reply -> [{name, wave}], best first.
static func parse_leaderboard(json: Variant) -> Array:
	var out: Array = []
	if not json is Array:
		return out
	for row: Variant in json:
		if not row is Dictionary or not (row as Dictionary).has("document"):
			continue
		var document: Variant = row["document"]
		if not document is Dictionary:
			continue
		var fields: Dictionary = FirestoreClient.decode_fields(
			(document as Dictionary).get("fields", {})
		)
		var name: String = clean_name(str(fields.get("name", "")))
		var wave: Variant = fields.get("wave", 0)
		out.append({"name": name if name != "" else "?", "wave": int(wave) if wave is int else 0})
	return out


## Legacy cloud save document (saves/{uid}) -> progress text ("" if missing).
static func parse_save(json: Variant) -> String:
	if not json is Dictionary:
		return ""
	var fields: Dictionary = FirestoreClient.decode_fields((json as Dictionary).get("fields", {}))
	return str(fields.get("progress", ""))


## Legacy free-form name cleanup (control characters dropped, cut to NAME_MAX).
## New names go through NicknameRules.
static func clean_name(value: String) -> String:
	var out := ""
	for ch in value.strip_edges():
		var code: int = ch.unicode_at(0)
		# Controls, zero-width and bidi override characters from a server reply.
		var invisible: bool = (
			code < 32
			or (code >= 0x7F and code <= 0x9F)
			or (code >= 0x200B and code <= 0x200F)
			or (code >= 0x2028 and code <= 0x202E)
			or (code >= 0x2060 and code <= 0x206F)
			or code == 0xFEFF
		)
		if not invisible:
			out += ch
	return out.substr(0, NAME_MAX)


## Marks the start of an endless run on the server (runs/{uid}, server time). The
## rules accept a record of wave N only (N-1)*15 s after this moment, so call it
## when the run begins. Fire and forget; without a connection the run simply
## has no online record. Returns true if the start was stored.
## A run that did not start online can never reach the table later: the rules
## accept only startedAt == request.time, so it cannot be written back-dated. Its
## record stays a local record (LevelCatalog.save_endless) and is not queued.
func start_run(level_id: int) -> bool:
	if not _ctx.is_configured():
		return false
	var signed: Dictionary = await _ctx.auth.ensure_token(true)
	if not signed["ok"]:
		return false
	var data := {"level": "level_%d" % level_id}
	var write: Dictionary = _ctx.firestore.write_set("runs/" + _ctx.auth.uid, data, ["startedAt"])
	var reply: Dictionary = await _ctx.firestore.commit([write])
	if reply["ok"]:
		# The new startedAt replaces the old one on the server, so a still queued
		# record of the previous run would be judged against it: drop it.
		var cfg: ConfigFile = LevelCatalog.data()
		if cfg.has_section(RECORD_SECTION):
			cfg.erase_section(RECORD_SECTION)
		cfg.set_value(RECORD_SECTION, "run_level", level_id)
		cfg.set_value(RECORD_SECTION, "run_uid", _ctx.auth.uid)
		LevelCatalog.commit()
		_retry_delay = _ctx.retry_base
	return reply["ok"]


## Sends the endless record of a level (the rules keep only higher records, stamp
## the time with the server clock and check it against start_run()).
## The name is the reserved nickname, else ANONYMOUS_NAME.
## The record is queued in the local save when the run did start online, and sent
## with retries (exponential delay) if the network fails meanwhile.
func submit_record(level_id: int, wave: int) -> void:
	if not _ctx.is_configured() or wave <= 0:
		return
	var cfg: ConfigFile = LevelCatalog.data()
	var run_ok: bool = (
		int(cfg.get_value(RECORD_SECTION, "run_level", -1)) == level_id
		and str(cfg.get_value(RECORD_SECTION, "run_uid", "")) == _ctx.auth.uid
		and _ctx.auth.uid != ""
	)
	if not run_ok:
		return  # no server-side run start: the rules would refuse it (see start_run)
	if wave > int(cfg.get_value(RECORD_SECTION, "wave", 0)):
		cfg.set_value(RECORD_SECTION, "wave", wave)
		LevelCatalog.commit()
	await flush_records()


## True while a record waits for the network.
func has_pending_record() -> bool:
	return int(LevelCatalog.data().get_value(RECORD_SECTION, "wave", 0)) > 0


## Sends the queued record once. Network/server failures keep it and schedule a
## retry (delay doubles up to RETRY_MAX, at most MAX_RETRIES in a row); a refusal by
## the rules (4xx) drops it. Never sends twice at the same time.
func flush_records() -> void:
	if _record_busy or not _ctx.is_configured() or not has_pending_record():
		return
	_record_busy = true
	var cfg: ConfigFile = LevelCatalog.data()
	var level_id: int = int(cfg.get_value(RECORD_SECTION, "run_level", -1))
	var wave: int = int(cfg.get_value(RECORD_SECTION, "wave", 0))
	var owner_uid: String = str(cfg.get_value(RECORD_SECTION, "run_uid", ""))
	var path := "leaderboards/level_%d/scores/%s"
	var result: String = await send_score(path, level_id, wave, owner_uid)
	_record_busy = false
	match result:
		"sent":
			cfg.set_value(RECORD_SECTION, "wave", null)
			LevelCatalog.commit()
			_retry_delay = _ctx.retry_base
			_retries = 0
			_ctx.status_changed.emit(_ctx.host.tr("ONLINE_RECORD_SENT"))
		"refused":
			cfg.set_value(RECORD_SECTION, "wave", null)
			LevelCatalog.commit()
			_ctx.status_changed.emit(_ctx.host.tr("ONLINE_RECORD_FAILED"))
		_:
			_schedule_retry()


## Writes {name, wave} to a score document of the signed-in player (the leaderboard
## and the daily board share this). "sent", "retry" (network, 5xx, 429, no login) or
## "refused" (the rules said no, or another account is signed in now).
## `path_format` has two placeholders: the board key and the uid.
func send_score(path_format: String, board: Variant, wave: int, owner_uid: String) -> String:
	var signed: Dictionary = await _ctx.auth.ensure_token(true)
	if not signed["ok"]:
		return "retry"
	if _ctx.auth.uid != owner_uid:
		return "refused"  # another account is signed in now
	var p: Dictionary = PlayerProfile.local()
	var nick: String = str(p["nickname"]) if bool(p["nicknameVerified"]) else ANONYMOUS_NAME
	var path: String = path_format % [board, _ctx.auth.uid]
	var write: Dictionary = _ctx.firestore.write_set(
		path, {"name": nick, "wave": wave}, ["updated"]
	)
	var reply: Dictionary = await _ctx.firestore.commit([write])
	if reply["ok"]:
		return "sent"
	var code: int = int(reply.get("code", 0))
	if reply.get("network", false) or code >= 500 or code == 429:
		return "retry"
	return "refused"


func fetch_leaderboard(level_id: int) -> void:
	if not _ctx.is_configured():
		_ctx.leaderboard_loaded.emit(level_id, [])
		return
	var reply: Dictionary = await _ctx.firestore.run_query(
		"leaderboards/level_%d" % level_id, top_query(), false
	)
	_ctx.leaderboard_loaded.emit(level_id, parse_leaderboard(reply["json"]) if reply["ok"] else [])


## Firestore structured query: the best LEADERBOARD_SIZE scores.
static func top_query() -> Dictionary:
	return {
		"from": [{"collectionId": "scores"}],
		"orderBy": [{"field": {"fieldPath": "wave"}, "direction": "DESCENDING"}],
		"limit": LEADERBOARD_SIZE,
	}


func _schedule_retry() -> void:
	if _retries >= MAX_RETRIES or not _ctx.host.is_inside_tree():
		_retries = 0
		return  # the next start() tries again
	_retries += 1
	var delay: float = _retry_delay
	_retry_delay = minf(_retry_delay * 2.0, RETRY_MAX)
	_ctx.host.get_tree().create_timer(delay).timeout.connect(flush_records)

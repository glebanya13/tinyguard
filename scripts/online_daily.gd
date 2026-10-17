class_name OnlineDaily
extends RefCounted
## Daily challenge board of Online: the queued result of the day and the top of a
## day's table. The queue lives in the local save; sending goes through
## OnlineRecords.send_score() (same rules for both boards).

## Local save section of the unsent daily result (day + wave + account).
const DAILY_SECTION := "daily_queue"

var _ctx: OnlineContext
var _daily_busy: bool = false


func _init(context: OnlineContext) -> void:
	_ctx = context


## Queues the daily challenge result of `day` (UTC date) and sends it. The rules accept
## it only on that very day (server clock, one hour of grace after midnight) and only
## above the earlier result; a result that misses the day is dropped, not retried
## forever. One attempt per call: the queue is tried again at the next launch and the
## next result (no timers, so the record queue's retries are not touched).
func submit_daily(day: String, wave: int) -> void:
	if not _ctx.is_configured() or wave <= 0 or not Daily.is_valid_key(day):
		return
	if _ctx.auth.uid == "":
		return
	var cfg: ConfigFile = LevelCatalog.data()
	var same_day: bool = str(cfg.get_value(DAILY_SECTION, "day", "")) == day
	if not same_day or wave > int(cfg.get_value(DAILY_SECTION, "wave", 0)):
		cfg.set_value(DAILY_SECTION, "day", day)
		cfg.set_value(DAILY_SECTION, "wave", wave)
		cfg.set_value(DAILY_SECTION, "uid", _ctx.auth.uid)
		LevelCatalog.commit()
	await flush_daily()


func has_pending_daily() -> bool:
	return int(LevelCatalog.data().get_value(DAILY_SECTION, "wave", 0)) > 0


## Sends the queued daily result once. Kept on network / server failures, dropped when
## the rules refuse it (wrong day, not higher) or another account is signed in.
func flush_daily() -> void:
	if _daily_busy or not _ctx.is_configured() or not has_pending_daily():
		return
	_daily_busy = true
	var cfg: ConfigFile = LevelCatalog.data()
	var day: String = str(cfg.get_value(DAILY_SECTION, "day", ""))
	var wave: int = int(cfg.get_value(DAILY_SECTION, "wave", 0))
	var owner_uid: String = str(cfg.get_value(DAILY_SECTION, "uid", ""))
	var result: String = await _ctx.records.send_score("daily/%s/scores/%s", day, wave, owner_uid)
	_daily_busy = false
	if result == "retry":
		return
	if cfg.has_section(DAILY_SECTION):
		cfg.erase_section(DAILY_SECTION)
	LevelCatalog.commit()
	if result == "sent":
		_ctx.status_changed.emit(_ctx.host.tr("ONLINE_DAILY_SENT"))


## Top of the board of `day` (daily_loaded).
func fetch_daily(day: String) -> void:
	if not _ctx.is_configured() or not Daily.is_valid_key(day):
		_ctx.daily_loaded.emit(day, [])
		return
	var reply: Dictionary = await _ctx.firestore.run_query(
		"daily/" + day, OnlineRecords.top_query(), false
	)
	_ctx.daily_loaded.emit(
		day, OnlineRecords.parse_leaderboard(reply["json"]) if reply["ok"] else []
	)

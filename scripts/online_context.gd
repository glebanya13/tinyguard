class_name OnlineContext
extends RefCounted
## State and signals shared by the services behind the `Online` autoload (the facade
## in scripts/online.gd). The services never reach each other's internals: they talk
## through this context (flags, signals, the service handles) and through each other's
## public methods. Signals go "up": the facade forwards them under its old names.

signal leaderboard_loaded(level_id: int, entries: Array)
## The table could not be loaded: reason "disabled", "offline", "denied", "error" or "timeout".
signal leaderboard_failed(level_id: int, reason: String)
signal daily_failed(day: String, reason: String)
signal status_changed(text: String)
signal daily_loaded(day: String, entries: Array)
signal cloud_loaded(ok: bool)
signal sync_state_changed(state: String)
signal account_changed
signal sync_finished(result: Dictionary)
signal session_expired

var api_key: String = ""
var project_id: String = ""
## Realtime Database URL for co-op (firebase.cfg "database_url"); "" = co-op off.
var database_url: String = ""
var auth := AuthService.new()
var firestore := FirestoreClient.new()
## Transport of the co-op layer (CoopLobby / CoopSession); null without database_url.
var rtdb: RtdbClient = null
## The Node that owns the transports and timers (the autoload).
var host: Node = null

## start() ran (idempotent boot).
var started: bool = false
## The first start() finished (signed in and synced, or failed offline).
var startup_done: bool = false
## A sync is running (one at a time).
var sync_busy: bool = false
## A link / sign-in / sign-out request is running (one at a time).
var email_busy: bool = false
## The account is being switched: no sync may run on a half-switched session.
var switching: bool = false
## Error of the last sync ("" after a success).
var last_error: String = ""
var expired_announced: bool = false

## First retry delay of an unsent record, seconds (tests shorten it).
var retry_base: float = 5.0
## Syncs the profile by itself a few seconds after local progress changed (tests of
## other features keep it off; the autoload's _ready switches it on).
var auto_sync: bool = false
var sync_debounce: float = OnlineSync.SYNC_DEBOUNCE
var sync_min_gap: float = OnlineSync.SYNC_MIN_GAP

var session: OnlineSession = null
var sync: OnlineSync = null
var nicknames: OnlineNicknames = null
var accounts: OnlineAccounts = null
var records: OnlineRecords = null
var daily: OnlineDaily = null
var coop: OnlineCoop = null


## Failed reply -> error key of the sync: offline, denied or server.
static func reply_error(reply: Dictionary) -> String:
	if reply.get("network", false):
		return "offline"
	var code: int = int(reply.get("code", 0))
	if code == 401 or code == 403:
		return "denied"
	return "server"


func is_configured() -> bool:
	return api_key != "" and project_id != ""

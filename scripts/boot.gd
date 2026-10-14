extends Control
## Entry scene: starts the online services in the background (guest sign-in,
## profile sync — offline is fine), then routes by the local profile:
## nickname screen, the tutorial, or straight to the world map.

## A new player waits at most this long for the guest sign-in (seconds);
## returning players never wait.
const AUTH_WAIT := 3.0

var _routed: bool = false


func _ready() -> void:
	$Center/Box/Title.text = GameInfo.TITLE
	LevelCatalog.apply_sound()
	LevelCatalog.tutorial = false
	Onboarding.rename_mode = false
	_run.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()


func _run() -> void:
	Online.start()  # not awaited: it may take long or never answer offline
	if Onboarding.route(PlayerProfile.local()) != Onboarding.Route.MAP:
		var deadline: int = Time.get_ticks_msec() + int(AUTH_WAIT * 1000.0)
		while not Online.startup_done and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
	if _routed:
		return
	_routed = true
	Onboarding.go(get_tree(), Onboarding.route(PlayerProfile.local()))

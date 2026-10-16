extends Control
## Entry scene: starts the online services in the background (restores the saved
## login, syncs the profile — offline is fine), then routes by the local profile:
## welcome screen (clean first launch), nickname screen, the tutorial, or straight
## to the world map.

## A new player waits at most this long for the guest sign-in (seconds);
## returning players never wait.
const AUTH_WAIT := 3.0

var _routed: bool = false


func _ready() -> void:
	GameSettings.apply_language()
	$Center/Box/Title.text = GameInfo.TITLE
	LevelCatalog.apply_sound()
	LevelCatalog.tutorial = false
	Onboarding.rename_mode = false
	_run.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()


func _run() -> void:
	# Not awaited: it may take long or never answer offline. A clean first launch does
	# not create any account here: the welcome screen asks first.
	Online.start(false)
	if _route() != Onboarding.Route.MAP and _route() != Onboarding.Route.WELCOME:
		var deadline: int = Time.get_ticks_msec() + int(AUTH_WAIT * 1000.0)
		while not Online.startup_done and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
	if _routed:
		return
	_routed = true
	Onboarding.go(get_tree(), _route())


## Welcome screen on a clean first launch; otherwise by the local profile only (a
## returning player never waits for the network and sees the cached progress at once).
func _route() -> Onboarding.Route:
	return Onboarding.route(PlayerProfile.local(), Online.needs_welcome())

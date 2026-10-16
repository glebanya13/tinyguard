class_name Onboarding
extends RefCounted
## First-launch flow: boot -> nickname -> tutorial (level 1) -> world map.
## The step is derived from the saved profile, so the flow resumes wherever
## the app was killed and running it twice changes nothing.

enum Route { NICKNAME, TUTORIAL, MAP, WELCOME }

## Bump when the tutorial changes enough that everyone should see it again.
const TUTORIAL_VERSION := 1
const TUTORIAL_LEVEL := 1
const BOOT_SCENE := "res://scenes/boot.tscn"
const WELCOME_SCENE := "res://scenes/welcome.tscn"
## The soft "create an account" reminder comes back after this many seconds.
const REMIND_EVERY := 3 * 86400
const NICKNAME_SCENE := "res://scenes/nickname.tscn"
const MAP_SCENE := "res://scenes/level_select.tscn"
const GAME_SCENE := "res://scenes/main.tscn"

## The nickname screen was opened from the map (rename): back returns there.
static var rename_mode: bool = false


## `welcome`: a clean first launch with Firebase (Online.needs_welcome()) goes to the
## welcome screen before anything else.
static func route(profile: Dictionary, welcome: bool = false) -> Route:
	if welcome:
		return Route.WELCOME
	if str(profile["nickname"]) == "" or bool(profile["nicknameConflict"]):
		return Route.NICKNAME
	if int(profile["tutorialVersionCompleted"]) < TUTORIAL_VERSION:
		return Route.TUTORIAL
	return Route.MAP


## Changes to the scene of `next` (the tutorial runs on level 1 in tutorial mode).
static func go(tree: SceneTree, next: Route) -> void:
	match next:
		Route.WELCOME:
			tree.change_scene_to_file(WELCOME_SCENE)
		Route.NICKNAME:
			tree.change_scene_to_file(NICKNAME_SCENE)
		Route.TUTORIAL:
			start_tutorial(tree)
		Route.MAP:
			tree.change_scene_to_file(MAP_SCENE)


static func start_tutorial(tree: SceneTree) -> void:
	LevelCatalog.selected_id = TUTORIAL_LEVEL
	LevelCatalog.endless = false
	LevelCatalog.tutorial = true
	tree.change_scene_to_file(GAME_SCENE)


## Stores a nickname on this device. `verified`: the server reserved it.
static func set_local_nickname(nickname: String, normalized: String, verified: bool) -> void:
	var p: Dictionary = PlayerProfile.local()
	p["nickname"] = nickname
	p["nicknameNormalized"] = normalized
	p["nicknameVerified"] = verified
	p["nicknameConflict"] = false
	PlayerProfile.save_local(p)


## The server refused a name reserved offline: ask the player for another one.
static func flag_nickname_conflict() -> void:
	var p: Dictionary = PlayerProfile.local()
	p["nicknameConflict"] = true
	p["nicknameVerified"] = false
	PlayerProfile.save_local(p)


## Finished or skipped: both count as seen for this tutorial version.
static func complete_tutorial() -> void:
	var p: Dictionary = PlayerProfile.local()
	p["tutorialVersionCompleted"] = maxi(int(p["tutorialVersionCompleted"]), TUTORIAL_VERSION)
	p["onboardingCompleted"] = true
	PlayerProfile.save_local(p)
	LevelCatalog.tutorial = false


## The player has seen the welcome screen and chose how to play (an account, a sign-in
## or "play without an account"). Local only; erased with the save.
static func welcome_done() -> bool:
	var cfg: ConfigFile = LevelCatalog.data()
	return bool(cfg.get_value(PlayerProfile.SECTION, "welcome_done", false))


static func mark_welcome_done() -> void:
	var cfg: ConfigFile = LevelCatalog.data()
	if not welcome_done():
		cfg.set_value(PlayerProfile.SECTION, "welcome_done", true)
		LevelCatalog.commit()


## True when a guest with at least one won level has not been reminded recently.
static func reminder_due(profile: Dictionary) -> bool:
	if (profile["progression"]["stars"] as Dictionary).is_empty():
		return false
	var cfg: ConfigFile = LevelCatalog.data()
	var last: int = int(cfg.get_value(PlayerProfile.SECTION, "reminder_at", 0))
	return last == 0 or int(Time.get_unix_time_from_system()) - last >= REMIND_EVERY


## "Later" on the reminder: asks again in REMIND_EVERY seconds.
static func dismiss_reminder() -> void:
	var cfg: ConfigFile = LevelCatalog.data()
	cfg.set_value(PlayerProfile.SECTION, "reminder_at", int(Time.get_unix_time_from_system()))
	LevelCatalog.commit()

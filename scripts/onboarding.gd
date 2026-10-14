class_name Onboarding
extends RefCounted
## First-launch flow: boot -> nickname -> tutorial (level 1) -> world map.
## The step is derived from the saved profile, so the flow resumes wherever
## the app was killed and running it twice changes nothing.

enum Route { NICKNAME, TUTORIAL, MAP }

## Bump when the tutorial changes enough that everyone should see it again.
const TUTORIAL_VERSION := 1
const TUTORIAL_LEVEL := 1
const BOOT_SCENE := "res://scenes/boot.tscn"
const NICKNAME_SCENE := "res://scenes/nickname.tscn"
const MAP_SCENE := "res://scenes/level_select.tscn"
const GAME_SCENE := "res://scenes/main.tscn"

## The nickname screen was opened from the map (rename): back returns there.
static var rename_mode: bool = false


static func route(profile: Dictionary) -> Route:
	if str(profile["nickname"]) == "" or bool(profile["nicknameConflict"]):
		return Route.NICKNAME
	if int(profile["tutorialVersionCompleted"]) < TUTORIAL_VERSION:
		return Route.TUTORIAL
	return Route.MAP


## Changes to the scene of `next` (the tutorial runs on level 1 in tutorial mode).
static func go(tree: SceneTree, next: Route) -> void:
	match next:
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

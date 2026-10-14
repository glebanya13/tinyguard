extends SceneTree
## Screenshots of the onboarding screens (nickname states, tutorial steps, the
## account panel) for docs/screenshots. Needs a display (xvfb-run); the online
## states use a fake HTTP layer, nothing reaches the network.
## SHOT_DIR=/tmp/shots xvfb-run -a -s "-screen 0 1280x720x24" godot --path . \
##   --resolution 1280x720 --rendering-driver opengl3 --script res://tools/shot_onboarding.gd

const SAVE := "user://shot_progress.cfg"
const SESSION := "user://shot_session.dat"


## Replies like a Firebase project where "бобр" is taken, or like no network.
class FakeTransport:
	extends HttpTransport
	var offline: bool = false

	func send(_method: int, url: String, _headers: PackedStringArray, _body: String) -> Dictionary:
		await get_tree().create_timer(0.2).timeout
		if offline:
			return {"ok": false, "code": 0, "json": null, "network": true}
		if "signUp" in url or "securetoken" in url:
			var auth := {
				"idToken": "I", "refreshToken": "R", "localId": "u", "expiresIn": "3600",
				"id_token": "I", "refresh_token": "R", "user_id": "u", "expires_in": "3600",
			}
			return {"ok": true, "code": 200, "json": auth, "network": false}
		if url.ends_with("/reserveNickname"):
			var error := {"status": "ALREADY_EXISTS", "details": {"reason": "taken"}}
			return {"ok": false, "code": 409, "json": {"error": error}, "network": false}
		return {"ok": false, "code": 404, "json": null, "network": false}


var _dir: String = ""
var _suffix: String = ""


func _initialize() -> void:
	LevelCatalog.save_path = SAVE
	SessionStore.path = SESSION
	LevelCatalog.erase_all()
	SessionStore.clear()
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = ProjectSettings.globalize_path("user://")
	_run.call_deferred()


func _run() -> void:
	var size: Vector2i = DisplayServer.window_get_size()
	_suffix = "" if size.x == 1280 else "_%dx%d" % [size.x, size.y]
	var online: Node = root.get_node("Online")
	var fake := FakeTransport.new()
	fake.name = "FakeTransport"
	online.setup("fake-key", "fake-project", "europe-west1", fake)

	change_scene_to_file(Onboarding.NICKNAME_SCENE)
	await _frames(20)
	var screen: Node = current_scene
	screen.set_text("Сэр Ёжик")
	await _shot("nickname_valid")
	screen.set_text("Ёжик!!")
	await _shot("nickname_invalid")
	screen.set_text("Бобр")
	screen.submit()
	await _wait_idle(screen)
	await _shot("nickname_taken")
	fake.offline = true
	screen.set_text("Сова")
	screen.submit()
	await _wait_idle(screen)
	await _shot("nickname_offline")

	online.setup("", "", "europe-west1", HttpTransport.new())
	LevelCatalog.erase_all()
	SessionStore.clear()
	Onboarding.set_local_nickname("Сова", "сова", false)
	Onboarding.start_tutorial(self)
	await _frames(40)
	await _shot("tutorial_welcome")
	var tutorial: Tutorial = current_scene.get_node("Tutorial")
	await create_timer(0.6).timeout
	tutorial.press_primary()
	await _frames(30)
	await _shot("tutorial_chop")
	var hero: Hero = current_scene.get_node("Level/Hero")
	var build: BuildManager = current_scene.get_node("BuildManager")
	hero.wood_gathered.emit(12, hero.global_position)
	current_scene.get_node("WaveManager").enemy_killed.emit(15)
	await _frames(20)
	await _shot("tutorial_select")
	for node in get_nodes_in_group(TowerSlot.GROUP):
		if (node as TowerSlot).is_free():
			build.select_slot(node)
			break
	await _frames(30)
	await _shot("tutorial_build")

	LevelCatalog.tutorial = false
	paused = false
	Onboarding.complete_tutorial()
	change_scene_to_file(Onboarding.MAP_SCENE)
	await _frames(40)
	current_scene.get("_account").open()
	await _frames(10)
	await _shot("account_local")
	# A guest account whose name and progress are waiting for the network.
	var offline_net := FakeTransport.new()
	offline_net.offline = true
	online.setup("fake-key", "fake-project", "europe-west1", offline_net)
	SessionStore.save_session({"uid": "Xk3pQ9mZ2vR7tL1wN8yA4bC6dE5f", "refresh_token": "R"})
	change_scene_to_file(Onboarding.MAP_SCENE)
	await create_timer(3.0).timeout
	current_scene.get("_account").open()
	await _frames(10)
	await _shot("account_guest")
	LevelCatalog.erase_all()
	SessionStore.clear()
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _wait_idle(screen: Node) -> void:
	await _frames(2)
	for i in 300:
		if not screen.get("_busy"):
			break
		await process_frame
	await _frames(5)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = _dir.path_join("onboarding_%s%s.png" % [name, _suffix])
	root.get_texture().get_image().save_png(path)
	print("saved ", path)

extends SceneTree
## Screenshots of the welcome screen, the registration and sign-in forms (also with
## the on-screen keyboard height faked), the profile of an email account and the map's
## reminder card. Needs a display; a fake Firebase answers, nothing reaches the network.
## SHOT_DIR=/tmp/shots godot --path . --resolution 1280x720 --script res://tools/shot_welcome.gd

const SAVE := "user://shot_welcome.cfg"
const SESSION := "user://shot_welcome_session.dat"
const Fakes := preload("res://tests/fakes.gd")

# Loaded at run time: these scripts name the Online autoload, which a --script file cannot
# resolve while it compiles itself.
var _dialog_script: GDScript = null
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
	_dialog_script = load("res://scripts/email_auth_dialog.gd")
	var size: Vector2i = DisplayServer.window_get_size()
	_suffix = "" if size.x == 1280 else "_%dx%d" % [size.x, size.y]
	var online: Node = root.get_node("Online")
	var fake := Fakes.FakeFirebase.new()
	var transport := Fakes.FakeTransport.new()
	transport.handler = fake.handle
	online.setup("fake-key", "fake-project", transport)
	online.start(false)

	change_scene_to_file(Onboarding.WELCOME_SCENE)
	await _frames(30)
	await _shot("welcome")
	var form: Control = current_scene.open_form(_dialog_script.Mode["REGISTER"])
	form.set_fields("ana@example.com", "hunter22", "Сова")
	await _frames(10)
	await _shot("register")
	form._password.secret = false
	form._set_status(EmailRules.message("credential_in_use"), _dialog_script.ERROR_COLOR)
	await _frames(5)
	await _shot("register_error")
	form.close()
	form = current_scene.open_form(_dialog_script.Mode["SIGN_IN"])
	form.set_fields("ana@example.com", "")
	await _frames(10)
	await _shot("signin")
	form.close()

	# An email account on the map: profile with the unconfirmed email, the reminder card.
	LevelCatalog.erase_all()
	SessionStore.clear()
	fake = Fakes.FakeFirebase.new()
	transport = Fakes.FakeTransport.new()
	transport.handler = fake.handle
	online.setup("fake-key", "fake-project", transport)
	await online.start(false)
	await online.choose_guest()
	await online.reserve_nickname("Сова")
	LevelCatalog.complete(1, 3)
	Onboarding.complete_tutorial()
	change_scene_to_file(Onboarding.MAP_SCENE)
	await create_timer(1.0).timeout
	await _shot("map_reminder")
	await online.register_email("ana@example.com", "hunter22")
	current_scene.get("_account").open()
	await _frames(20)
	await _shot("profile_email")
	LevelCatalog.erase_all()
	SessionStore.clear()
	online.setup("", "", HttpTransport.new())
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = _dir.path_join("welcome_%s%s.png" % [name, _suffix])
	root.get_texture().get_image().save_png(path)
	print("saved ", path)

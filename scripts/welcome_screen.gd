extends Control
## Welcome screen of a clean first launch (only with Firebase): two big buttons,
## "Create account" and "Sign in" (email and password), and a small "Play without
## an account" link. Playing as a guest stays a full option: nothing is blocked
## and the app review needs no credentials. Everything works offline except the
## account buttons, which then say so and point to the guest option.

var _dialog: EmailAuthDialog = null

@onready var _safe: MarginContainer = $Safe
@onready var _create: Button = $Safe/Center/Row/Panel/Content/CreateButton
@onready var _sign_in: Button = $Safe/Center/Row/Panel/Content/SignInButton
@onready var _guest: Button = $Safe/Center/Row/Panel/Content/GuestButton


func _ready() -> void:
	GameSettings.apply_language()
	$Safe/Center/Row/Art/GameTitle.text = GameInfo.TITLE
	LevelCatalog.apply_sound()
	_apply_safe_area()
	_dialog = EmailAuthDialog.new()
	_dialog.offer_guest = true
	add_child(_dialog)
	_dialog.succeeded.connect(_on_account_ready.unbind(2))
	_create.pressed.connect(func() -> void: _dialog.open(EmailAuthDialog.Mode.REGISTER))
	_sign_in.pressed.connect(func() -> void: _dialog.open(EmailAuthDialog.Mode.SIGN_IN))
	_guest.pressed.connect(_on_guest_pressed)
	# A soft notice under the buttons: crash reports are on by default and can be turned off.
	var notice := UiKit.caption(tr("WELCOME_CRASH_NOTE"))
	notice.name = "CrashNotice"
	_guest.get_parent().add_child(notice)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _dialog != null and _dialog.visible:
			_dialog.close()
		else:
			get_tree().quit()


## Opens the registration or sign-in form (tests and screenshots).
func open_form(mode: EmailAuthDialog.Mode) -> EmailAuthDialog:
	_dialog.open(mode)
	return _dialog


func choose_guest() -> void:
	_on_guest_pressed()


func _on_guest_pressed() -> void:
	Online.choose_guest()  # the guest account appears in the background (or later, offline)
	_continue()


func _on_account_ready() -> void:
	_continue()


func _continue() -> void:
	Onboarding.go(get_tree(), Onboarding.route(PlayerProfile.local()))


func _apply_safe_area() -> void:
	var margins: Vector4 = ScreenUtil.safe_margins(get_viewport())
	_safe.add_theme_constant_override("margin_left", int(margins.x) + 16)
	_safe.add_theme_constant_override("margin_top", int(margins.y) + 8)
	_safe.add_theme_constant_override("margin_right", int(margins.z) + 16)
	_safe.add_theme_constant_override("margin_bottom", int(margins.w) + 8)

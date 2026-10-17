class_name ScreenUtil
extends RefCounted
## Safe area (display cutouts) and on-screen keyboard size in canvas units, for
## the full-screen onboarding UI. Desktop builds report no insets.


## Screenshot tools and tests set this to fake a display cutout (canvas units).
static var fake_margins: Vector4 = Vector4.ZERO


## Insets (left, top, right, bottom) the UI must keep clear of.
static func safe_margins(viewport: Viewport) -> Vector4:
	if fake_margins != Vector4.ZERO:
		return fake_margins
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var window: Vector2i = DisplayServer.window_get_size()
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	if window.x <= 0 or safe.size.x <= 0:
		return Vector4.ZERO
	var scale: float = viewport.get_visible_rect().size.x / float(window.x)
	return (
		Vector4(
			maxi(safe.position.x, 0),
			maxi(safe.position.y, 0),
			maxi(window.x - safe.end.x, 0),
			maxi(window.y - safe.end.y, 0)
		)
		* scale
	)


## Height of the virtual keyboard (0 when hidden or on desktop).
static func keyboard_height(viewport: Viewport) -> float:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return 0.0
	var window: Vector2i = DisplayServer.window_get_size()
	if window.y <= 0:
		return 0.0
	var scale: float = viewport.get_visible_rect().size.y / float(window.y)
	return DisplayServer.virtual_keyboard_get_height() * scale

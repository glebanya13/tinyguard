class_name UiKit
extends RefCounted
## Small builders for the code-made screens, so every title, caption and chip uses the
## same theme types (ui/theme.tres, drawn by tools/make_ui_atlas.py). Grid: 8 px.

const GOLD := Color(1.0, 0.88, 0.45)
const CREAM := Color(1.0, 0.97, 0.88)
const MUTED := Color(0.78, 0.84, 0.97)
const WARN := Color(1.0, 0.62, 0.55)


## Title plaque (ribbon): `variation` is RibbonLabel, ...Green, ...Red or ...Gold.
static func ribbon(text: String, variation: StringName = &"RibbonLabel") -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Outlined display text for a panel heading.
static func heading(text: String, size: int = 0) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"HeadingLabel"
	label.text = text
	if size > 0:
		label.add_theme_font_size_override("font_size", size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Quiet small text (no outline: it costs no extra draw calls).
static func caption(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"CaptionLabel"
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Button of the given theme type with the standard touch size (84 px high).
static func button(
	text: String, variation: StringName = &"", min_width: float = 0.0, icon: Texture2D = null
) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(min_width, 84)
	if icon != null:
		b.icon = icon
	return b


## Gives a code-made label the display look by its size: 30+ is a title (outlined, with
## shadow), 22-29 in gold is a heading. Color and size overrides of the caller still apply.
static func style_label(label: Label, size: int, color: Color = CREAM) -> void:
	if size >= 30:
		label.theme_type_variation = &"TitleLabel"
	elif size >= 22 and color.r > 0.9 and color.b < 0.6:
		label.theme_type_variation = &"HeadingLabel"

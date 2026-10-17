class_name Toast
extends PanelContainer
## A short pill at the top of the screen ("Achievement!" + the name) that slides in,
## stays and fades out. Several at once stack downwards. Does not take touches.

const GROUP := &"toasts"
const GOLD := Color(0.98, 0.8, 0.4)
const TOP := 176.0
const STEP := 84.0
const WIDTH := 460.0
const HOLD_SECONDS := 2.6


## Shows a toast on `parent` (a full-screen Control or the HUD root).
static func show_on(parent: Control, title: String, text: String) -> Toast:
	var toast := Toast.new()
	toast.name = "Toast"
	toast.theme_type_variation = &"ToastPanel"
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.process_mode = Node.PROCESS_MODE_ALWAYS
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_child(box)
	var head := Label.new()
	head.text = title
	head.name = "Title"
	head.theme_type_variation = &"HeadingLabel"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var body := Label.new()
	body.text = text
	body.name = "Text"
	body.add_theme_font_size_override("font_size", 22)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(WIDTH - 40.0, 0.0)
	box.add_child(body)
	toast.custom_minimum_size = Vector2(WIDTH, 0.0)
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	var slot: int = parent.get_tree().get_nodes_in_group(GROUP).size()
	toast.add_to_group(GROUP)
	parent.add_child(toast)
	toast.position = Vector2(parent.size.x / 2.0 - WIDTH / 2.0, TOP + slot * STEP - 40.0)
	toast.modulate.a = 0.0
	var tween: Tween = toast.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(toast, "modulate:a", 1.0, 0.25)
	tween.parallel().tween_property(toast, "position:y", TOP + slot * STEP, 0.3)
	tween.tween_interval(HOLD_SECONDS)
	tween.tween_property(toast, "modulate:a", 0.0, 0.5)
	tween.tween_callback(toast.queue_free)
	return toast


func _exit_tree() -> void:
	remove_from_group(GROUP)

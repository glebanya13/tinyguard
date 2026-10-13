extends Node3D
## Start screen: a 3D island map with one button per level. Locked levels
## show a lock; finished ones a star. Picking a level and pressing "Play"
## loads the game scene with LevelCatalog.selected_id set.

const GAME_SCENE := "res://scenes/main.tscn"
const LOCK_ICON: Texture2D = preload("res://ui/icons/lock.png")
const STAR_ICON: Texture2D = preload("res://ui/icons/star.png")
const CASTLE_ICON: Texture2D = preload("res://ui/icons/flag.png")
## Seconds for one full slow turn of the camera around the island.
const ORBIT_PERIOD := 90.0
const ORBIT_SWAY := 0.12

var _site_buttons: Array[Button] = []
var _sites: Array[Node3D] = []
var _selected: int = 0
var _time: float = 0.0
var _camera_base: Transform3D

@onready var _map: Node3D = $Map
@onready var _camera: Camera3D = $Camera
@onready var _site_layer: Control = $UI/Root/Sites
@onready var _name_label: Label = $UI/Root/Info/Content/Name
@onready var _subtitle_label: Label = $UI/Root/Info/Content/Subtitle
@onready var _play_button: Button = $UI/Root/Info/Content/PlayButton


func _ready() -> void:
	_camera_base = _camera.transform
	var unlocked: int = LevelCatalog.unlocked()
	for level: Dictionary in LevelCatalog.levels():
		var id: int = int(level["id"])
		var site := _map.find_child("Site%d" % id) as Node3D
		if site == null:
			continue
		var button := Button.new()
		button.custom_minimum_size = Vector2(76, 76)
		button.focus_mode = Control.FOCUS_NONE
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.text = ""
		if id > unlocked:
			button.icon = LOCK_ICON
			button.disabled = true
			button.tooltip_text = "Пройдите предыдущий уровень"
		else:
			button.icon = STAR_ICON if LevelCatalog.is_completed(id) else CASTLE_ICON
			button.pressed.connect(_select.bind(id))
		_site_layer.add_child(button)
		var number := Label.new()
		number.text = str(id)
		number.add_theme_font_size_override("font_size", 22)
		number.position = Vector2(4, -6)
		number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(number)
		_site_buttons.append(button)
		_sites.append(site)
	_play_button.pressed.connect(_on_play_pressed)
	_select(clampi(LevelCatalog.selected_id, 1, unlocked))


func _process(delta: float) -> void:
	_time += delta
	# Gentle sway so the map feels alive.
	var angle: float = sin(_time * TAU / ORBIT_PERIOD) * ORBIT_SWAY
	_camera.transform = Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO) * _camera_base
	for i in _site_buttons.size():
		var button: Button = _site_buttons[i]
		var bob: float = sin(_time * 2.4 + i) * 4.0 if i + 1 == _selected else 0.0
		var screen: Vector2 = _camera.unproject_position(_sites[i].global_position)
		button.position = screen - button.size / 2.0 + Vector2(0.0, bob)


func _select(id: int) -> void:
	_selected = id
	var level: Dictionary = LevelCatalog.get_level(id)
	_name_label.text = "%d. %s" % [id, level["name"]]
	_subtitle_label.text = level["subtitle"]
	for i in _site_buttons.size():
		_site_buttons[i].modulate = Color(1.15, 1.1, 0.9) if i + 1 == id else Color.WHITE


func _on_play_pressed() -> void:
	LevelCatalog.selected_id = _selected
	_play_button.disabled = true
	get_tree().change_scene_to_file(GAME_SCENE)

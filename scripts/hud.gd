class_name Hud
extends CanvasLayer
## Wave, gold and lives readouts, the "start wave" button, the build menu
## and the end screen with the restart button.

signal start_wave_pressed
signal build_pressed
signal build_cancelled
signal restart_pressed

var _gold: int = 0
var _build_cost: int = 0

@onready var _wave_label: Label = $TopBar/WaveLabel
@onready var _gold_label: Label = $TopBar/GoldLabel
@onready var _lives_label: Label = $TopBar/LivesLabel
@onready var _start_button: Button = $StartWaveButton
@onready var _message_label: Label = $MessageLabel
@onready var _restart_button: Button = $RestartButton
@onready var _build_menu: Control = $BuildMenu
@onready var _tower_name_label: Label = $BuildMenu/Content/TowerNameLabel
@onready var _cost_label: Label = $BuildMenu/Content/CostLabel
@onready var _hint_label: Label = $BuildMenu/Content/HintLabel
@onready var _build_button: Button = $BuildMenu/Content/Buttons/BuildButton
@onready var _cancel_button: Button = $BuildMenu/Content/Buttons/CancelButton


func _ready() -> void:
	_start_button.pressed.connect(start_wave_pressed.emit)
	_build_button.pressed.connect(build_pressed.emit)
	_cancel_button.pressed.connect(build_cancelled.emit)
	_restart_button.pressed.connect(_on_restart_button_pressed)
	_message_label.hide()
	_restart_button.hide()
	_build_menu.hide()


func set_wave(wave: int, total: int) -> void:
	_wave_label.text = "Волна %d/%d" % [wave, total]


func set_gold(gold: int) -> void:
	_gold = gold
	_gold_label.text = "Золото %d" % gold
	_refresh_build_button()


func set_lives(lives: int) -> void:
	_lives_label.text = "Жизни %d" % lives


func set_start_enabled(enabled: bool) -> void:
	_start_button.disabled = not enabled


## Victory/defeat screen. The restart button works while the tree is paused.
func show_end_screen(text: String) -> void:
	_message_label.text = text
	_message_label.show()
	_restart_button.disabled = false
	_restart_button.show()


func show_build_menu(tower_name: String, cost: int) -> void:
	_build_cost = cost
	_tower_name_label.text = tower_name
	_cost_label.text = "Стоимость: %d золота" % cost
	_refresh_build_button()
	_build_menu.show()


func hide_build_menu() -> void:
	_build_menu.hide()


func _refresh_build_button() -> void:
	# Visual hint only: BuildManager re-checks gold before building.
	var affordable: bool = _gold >= _build_cost
	_build_button.disabled = not affordable
	_hint_label.text = "" if affordable else "Недостаточно золота"


func _on_restart_button_pressed() -> void:
	# The scene reload happens later in the frame; ignore repeated taps.
	_restart_button.disabled = true
	restart_pressed.emit()

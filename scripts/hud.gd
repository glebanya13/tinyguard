class_name Hud
extends CanvasLayer
## Wave, gold and lives readouts plus the "start wave" button.

signal start_wave_pressed

@onready var _wave_label: Label = $TopBar/WaveLabel
@onready var _gold_label: Label = $TopBar/GoldLabel
@onready var _lives_label: Label = $TopBar/LivesLabel
@onready var _start_button: Button = $StartWaveButton
@onready var _message_label: Label = $MessageLabel


func _ready() -> void:
	_start_button.pressed.connect(start_wave_pressed.emit)
	_message_label.hide()


func set_wave(wave: int, total: int) -> void:
	_wave_label.text = "Волна %d/%d" % [wave, total]


func set_gold(gold: int) -> void:
	_gold_label.text = "Золото %d" % gold


func set_lives(lives: int) -> void:
	_lives_label.text = "Жизни %d" % lives


func set_start_enabled(enabled: bool) -> void:
	_start_button.disabled = not enabled


func show_message(text: String) -> void:
	_message_label.text = text
	_message_label.show()

extends Node3D
## Root of the level: wires game systems together through their signals.

@onready var _game_state: GameState = $GameState
@onready var _wave_manager: WaveManager = $WaveManager
@onready var _hud: Hud = $HUD


func _ready() -> void:
	_game_state.gold_changed.connect(_hud.set_gold)
	_game_state.lives_changed.connect(_hud.set_lives)
	_game_state.defeated.connect(_on_defeated)

	_wave_manager.enemy_killed.connect(_game_state.add_gold)
	_wave_manager.enemy_reached_base.connect(_game_state.lose_lives)
	_wave_manager.wave_started.connect(_on_wave_started)
	_wave_manager.wave_cleared.connect(_on_wave_cleared)
	_wave_manager.all_waves_cleared.connect(_on_all_waves_cleared)

	_hud.start_wave_pressed.connect(_wave_manager.start_next_wave)

	# GameState emitted its initial values before these connections existed.
	_hud.set_gold(_game_state.gold)
	_hud.set_lives(_game_state.lives)
	_hud.set_wave(0, _wave_manager.get_total_waves())
	_wave_manager.schedule_next_wave(_wave_manager.config.first_wave_delay)


func _on_wave_started(wave: int, total: int) -> void:
	_hud.set_wave(wave, total)
	_hud.set_start_enabled(false)


func _on_wave_cleared(_wave: int) -> void:
	_hud.set_start_enabled(_wave_manager.has_next_wave())


func _on_all_waves_cleared() -> void:
	if _game_state.is_defeated:
		return
	_hud.show_message("Победа!")
	get_tree().paused = true


func _on_defeated() -> void:
	_wave_manager.stop()
	_hud.set_start_enabled(false)
	_hud.show_message("Поражение")
	get_tree().paused = true

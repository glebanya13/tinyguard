extends Node3D
## Root of the level: wires game systems together through their signals.

@onready var _game_state: GameState = $GameState
@onready var _wave_manager: WaveManager = $WaveManager
@onready var _build_manager: BuildManager = $BuildManager
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

	_build_manager.slot_selected.connect(_on_slot_selected)
	_build_manager.selection_cleared.connect(_hud.hide_build_menu)

	_hud.start_wave_pressed.connect(_wave_manager.start_next_wave)
	_hud.build_pressed.connect(_build_manager.build_selected)
	_hud.build_cancelled.connect(_build_manager.clear_selection)

	# GameState emitted its initial values before these connections existed.
	_hud.set_gold(_game_state.gold)
	_hud.set_lives(_game_state.lives)
	_hud.set_wave(0, _wave_manager.get_total_waves())
	_wave_manager.schedule_next_wave(_wave_manager.config.first_wave_delay)


func _on_slot_selected(_slot: TowerSlot) -> void:
	var tower_data: TowerData = _build_manager.tower_data
	_hud.show_build_menu(tower_data.display_name, tower_data.cost)


func _on_wave_started(wave: int, total: int) -> void:
	_hud.set_wave(wave, total)
	_hud.set_start_enabled(false)


func _on_wave_cleared(_wave: int) -> void:
	_hud.set_start_enabled(_wave_manager.has_next_wave())


func _on_all_waves_cleared() -> void:
	if _game_state.is_defeated:
		return
	_end_game("Победа!")


func _on_defeated() -> void:
	_wave_manager.stop()
	_hud.set_start_enabled(false)
	_end_game("Поражение")


func _end_game(message: String) -> void:
	_build_manager.clear_selection()
	_hud.show_message(message)
	get_tree().paused = true

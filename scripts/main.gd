extends Node3D
## Root of the level: wires game systems together through their signals and
## turns the hero's command card into orders (walk to the slot, then build).

enum Command { BUILD, UPGRADE }

const BUILD_FX := preload("res://scenes/fx/build_fx.tscn")
const UPGRADE_FX := preload("res://scenes/fx/upgrade_fx.tscn")
## The hero builds when this close to a slot centre (metres).
const BUILD_REACH := 1.25
## Walking this close to a slot selects it automatically.
const AUTO_SELECT_REACH := 1.1

## True while the hero walks to carry out a build/upgrade command.
var _command_pending: bool = false

@onready var _game_state: GameState = $GameState
@onready var _wave_manager: WaveManager = $WaveManager
@onready var _build_manager: BuildManager = $BuildManager
@onready var _hud: Hud = $HUD
@onready var _hero: Hero = $Level/Hero
@onready var _wave_horn: AudioStreamPlayer = $Sfx/WaveHorn
@onready var _base_hit: AudioStreamPlayer = $Sfx/BaseHit
@onready var _victory_sound: AudioStreamPlayer = $Sfx/Victory
@onready var _defeat_sound: AudioStreamPlayer = $Sfx/Defeat


func _ready() -> void:
	_game_state.gold_changed.connect(_on_gold_changed)
	_game_state.lives_changed.connect(_hud.set_lives)
	_game_state.defeated.connect(_on_defeated)

	_wave_manager.enemy_killed.connect(_game_state.add_gold)
	_wave_manager.enemy_reached_base.connect(_on_enemy_reached_base)
	_wave_manager.wave_started.connect(_on_wave_started)
	_wave_manager.all_waves_cleared.connect(_on_all_waves_cleared)

	_build_manager.slot_selected.connect(_on_selection_changed.unbind(1))
	_build_manager.selection_cleared.connect(_on_selection_changed)
	_build_manager.tower_built.connect(_on_tower_built)
	_build_manager.tower_upgraded.connect(_on_tower_upgraded)
	_build_manager.ground_tapped.connect(_on_ground_tapped)

	_hud.build_pressed.connect(order.bind(Command.BUILD))
	_hud.upgrade_pressed.connect(order.bind(Command.UPGRADE))
	_hud.cancel_pressed.connect(_on_cancel_pressed)
	_hud.restart_pressed.connect(_on_restart_pressed)
	_hud.joystick_changed.connect(func(v: Vector2) -> void: _hero.joystick_vector = v)
	_hero.order_cancelled.connect(_on_hero_order_ended)
	_hero.order_finished.connect(_on_hero_order_ended)

	# GameState emitted its initial values before these connections existed.
	_hud.set_gold(_game_state.gold)
	_hud.set_lives(_game_state.lives)
	_hud.set_wave(0, _wave_manager.get_total_waves())
	_refresh_card()
	_wave_manager.schedule_next_wave(_wave_manager.config.first_wave_delay)


func _process(_delta: float) -> void:
	_hud.set_next_wave(_wave_manager.current_wave + 1, _wave_manager.time_to_next_wave())
	_auto_select_near_hero()


## Command card action: the hero walks to the selected slot and acts there.
func order(command: Command) -> void:
	var slot: TowerSlot = _build_manager.selected_slot
	if slot == null or not _command_available(command, slot):
		return
	if _hero.is_near(slot.global_position, BUILD_REACH):
		_execute(command, slot)
	else:
		_hero.move_to(slot.global_position, BUILD_REACH, _execute.bind(command, slot))
		_command_pending = true
		_refresh_card()


func _execute(command: Command, slot: TowerSlot) -> void:
	if command == Command.BUILD:
		_build_manager.build_on(slot)
	else:
		_build_manager.upgrade(slot)
	_refresh_card()


func _command_available(command: Command, slot: TowerSlot) -> bool:
	if command == Command.BUILD:
		return _build_manager.can_build(slot)
	return _build_manager.can_upgrade(slot)


func _auto_select_near_hero() -> void:
	# Walking (keys, joystick or a tap on the ground) selects the slot the hero
	# reaches; a pending build/upgrade command keeps its own target.
	if _hero.velocity.length() < 0.1 or _command_pending:
		return
	var nearest: TowerSlot = null
	var best: float = AUTO_SELECT_REACH
	for node: Node in get_tree().get_nodes_in_group(TowerSlot.GROUP):
		var slot := node as TowerSlot
		var offset: Vector3 = slot.global_position - _hero.global_position
		offset.y = 0.0
		if offset.length() < best:
			best = offset.length()
			nearest = slot
	if nearest != null and nearest != _build_manager.selected_slot:
		_build_manager.select_slot(nearest)


func _refresh_card() -> void:
	var slot: TowerSlot = _build_manager.selected_slot
	var data: TowerData = _build_manager.tower_data
	var info := {"has_selection": slot != null, "build_cost": data.cost}
	if slot == null:
		info["title"] = "Рыцарь-страж"
		info["stats"] = "Идти: WASD / стрелки или нажать на землю"
		info["hint"] = "Подойдите к площадке или нажмите на неё"
		info["upgrade_label"] = "—"
	elif slot.is_free():
		info["title"] = "Площадка: %s" % data.display_name
		info["stats"] = _stats_text(data, 0)
		info["upgrade_label"] = "—"
		info["show_build"] = true
		info["can_build"] = _build_manager.can_build(slot)
		info["hint"] = "" if info["can_build"] else "Недостаточно золота"
	else:
		var level: int = slot.tower.level
		info["title"] = "%s · ур. %d/%d" % [data.display_name, level + 1, data.max_level() + 1]
		info["stats"] = _stats_text(data, level)
		info["show_upgrade"] = true
		info["upgrade_cost"] = data.upgrade_cost(level)
		info["can_upgrade"] = _build_manager.can_upgrade(slot)
		if data.upgrade_cost(level) < 0:
			info["hint"] = "Максимальный уровень"
		elif not info["can_upgrade"]:
			info["hint"] = "Недостаточно золота"
		else:
			info["hint"] = "Дальше: " + _stats_text(data, level + 1)
	if _command_pending:
		info["hint"] = "Рыцарь идёт к площадке…"
	_hud.update_card(info)


func _stats_text(data: TowerData, level: int) -> String:
	return (
		"Урон %d · радиус %.1f · %.2f с"
		% [data.damage_levels[level], data.range_levels[level], data.interval_levels[level]]
	)


func _spawn_fx(scene: PackedScene, at: Vector3) -> void:
	var fx := scene.instantiate() as Node3D
	add_child(fx)
	fx.global_position = at


func _on_gold_changed(gold: int) -> void:
	_hud.set_gold(gold)
	_refresh_card()


func _on_selection_changed() -> void:
	_refresh_card()


func _on_tower_built(slot: TowerSlot, tower: Tower) -> void:
	_spawn_fx(BUILD_FX, slot.global_position)
	# Rise out of the dust.
	tower.scale = Vector3(1.0, 0.2, 1.0)
	create_tween().tween_property(tower, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK)
	_refresh_card()


func _on_tower_upgraded(slot: TowerSlot, _tower: Tower) -> void:
	_spawn_fx(UPGRADE_FX, slot.global_position)
	_refresh_card()


func _on_hero_order_ended() -> void:
	_command_pending = false
	_refresh_card()


func _on_ground_tapped(point: Vector3) -> void:
	_hero.move_to(point, 0.15)


func _on_cancel_pressed() -> void:
	_hero.cancel_order()
	_build_manager.clear_selection()
	_refresh_card()


func _on_enemy_reached_base(damage: int) -> void:
	_base_hit.play()
	_game_state.lose_lives(damage)


func _on_wave_started(wave: int, total: int) -> void:
	_hud.set_wave(wave, total)
	_wave_horn.play()


func _on_all_waves_cleared() -> void:
	if _game_state.is_defeated:
		return
	_victory_sound.play()
	_end_game("Победа!", true)


func _on_defeated() -> void:
	_wave_manager.stop()
	_defeat_sound.play()
	_end_game("Поражение", false)


func _end_game(message: String, victory: bool) -> void:
	_hero.cancel_order()
	_build_manager.clear_selection()
	_hud.show_end_screen(message, victory)
	get_tree().paused = true


## All level state lives in this scene's nodes, so reloading it restores the
## starting gold, lives and wave and frees old enemies, projectiles and towers.
## SceneTree.paused is the only state that survives a reload: clear it first.
func _on_restart_pressed() -> void:
	get_tree().paused = false
	var error: Error = get_tree().reload_current_scene()
	if error != OK:
		push_error("Restart failed: %s" % error_string(error))
		get_tree().paused = true

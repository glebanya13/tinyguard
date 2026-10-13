extends Node3D
## Root of a level: builds the selected level from resources/levels.json
## (terrain, castle, portal, path, slots, trees, hero spot), wires the game
## systems together through their signals and turns the hero's command card
## into orders (walk to the slot, then build).

const LEVEL_SELECT_SCENE := "res://scenes/level_select.tscn"
const SLOT_SCENE: PackedScene = preload("res://scenes/tower_slot.tscn")
const TREE_SCENE: PackedScene = preload("res://scenes/wood_tree.tscn")
const CASTLE_SCENE: PackedScene = preload("res://assets/models/castle.glb")
const PORTAL_SCENE: PackedScene = preload("res://assets/models/spawn_portal.glb")
const NO_SHADOW := preload("res://scripts/no_shadow.gd")
const BUILD_FX := preload("res://scenes/fx/build_fx.tscn")
const UPGRADE_FX := preload("res://scenes/fx/upgrade_fx.tscn")
const WOOD_ICON: Texture2D = preload("res://ui/icons/wood.png")
const COIN_ICON: Texture2D = preload("res://ui/icons/coin.png")
const UPGRADE_ICON: Texture2D = preload("res://ui/icons/upgrade.png")
const SWORD_ICON: Texture2D = preload("res://ui/icons/sword.png")
const HEART_ICON: Texture2D = preload("res://ui/icons/heart.png")
const CANCEL_ICON: Texture2D = preload("res://ui/icons/cancel.png")
const RING_TREE_COLOR := Color(0.62, 0.95, 0.42, 0.85)
const RING_ENEMY_COLOR := Color(1.0, 0.38, 0.32, 0.85)
## A tap this close to a tree sends the hero to chop it.
const TREE_TAP_REACH := 1.0
## Hints are shown until this many towers stand on the map.
const HINT_TOWERS := 2
const GOLD_COLOR := Color(1.0, 0.85, 0.35)
const WOOD_COLOR := Color(0.85, 0.65, 0.42)
## The hero builds when this close to a slot centre (metres).
const BUILD_REACH := 1.25
## Walking this close to a slot selects it automatically.
const AUTO_SELECT_REACH := 1.1
## Height of the path curve above the ground.
const PATH_HEIGHT := 0.05
## Camera look-at area is the level bounds shrunk by this margin.
const CAMERA_MARGIN := 4.0
## Physics layers that block walking: level colliders (1) and trees (3).
const WALK_OBSTACLE_MASK := 1 | 4
## Radius a built tower blocks on the walk grid.
const TOWER_BLOCK_RADIUS := 0.6
## Gold for each second left on the countdown when a wave is called early.
const EARLY_CALL_GOLD_PER_SECOND := 0.3

var level: Dictionary = {}
var walk_grid := WalkGrid.new()

var _focused_tree: WoodTree = null
var _paused: bool = false
var _forge_open: bool = false
var _castle: Node3D = null
var _ended: bool = false

## Command to run when the hero reaches the selected slot, or &"".
var _pending_command: StringName = &""

@onready var _level_root: Node3D = $Level
@onready var _enemy_path: Path3D = $Level/EnemyPath
@onready var _camera: Camera3D = $Camera
@onready var _game_state: GameState = $GameState
@onready var _wave_manager: WaveManager = $WaveManager
@onready var _build_manager: BuildManager = $BuildManager
@onready var _hud: Hud = $HUD
@onready var _hero: Hero = $Level/Hero
@onready var _target_ring: MeshInstance3D = $TargetRing
@onready var _range_ring: MeshInstance3D = $RangeRing
@onready var _ring_material: StandardMaterial3D = _target_ring.mesh.surface_get_material(0)
@onready var _wave_horn: AudioStreamPlayer = $Sfx/WaveHorn
@onready var _boss_roar: AudioStreamPlayer = $Sfx/BossRoar
@onready var _base_hit: AudioStreamPlayer = $Sfx/BaseHit
@onready var _victory_sound: AudioStreamPlayer = $Sfx/Victory
@onready var _defeat_sound: AudioStreamPlayer = $Sfx/Defeat


func _ready() -> void:
	level = LevelCatalog.get_level(LevelCatalog.selected_id)
	_build_level()
	_game_state.configure(level["start"])
	_game_state.reset()
	_wave_manager.plan = WavePlan.new(level["waves"])

	_game_state.gold_changed.connect(_on_resources_changed.unbind(1))
	_game_state.wood_changed.connect(_on_resources_changed.unbind(1))
	_game_state.lives_changed.connect(_hud.set_lives)
	_game_state.defeated.connect(_on_defeated)

	_wave_manager.enemy_killed.connect(_game_state.add_gold)
	_wave_manager.enemy_reached_base.connect(_on_enemy_reached_base)
	_wave_manager.wave_started.connect(_on_wave_started)
	_wave_manager.all_waves_cleared.connect(_on_all_waves_cleared)

	_build_manager.slot_selected.connect(_refresh_card.unbind(1))
	_build_manager.selection_cleared.connect(_refresh_card)
	_build_manager.tower_built.connect(_on_tower_built)
	_build_manager.tower_upgraded.connect(_on_tower_upgraded)
	_build_manager.ground_tapped.connect(_on_ground_tapped)

	_hud.command_pressed.connect(_on_command_pressed)
	_hud.attack_pressed.connect(_hero.try_attack)
	_hud.next_wave_pressed.connect(_on_next_wave_pressed)
	_hud.restart_pressed.connect(_on_restart_pressed)
	_hud.map_pressed.connect(_on_map_pressed)
	_hud.pause_pressed.connect(_toggle_pause)
	_hud.continue_pressed.connect(_toggle_pause)
	_hud.speed_pressed.connect(_toggle_speed)
	_hud.forge_pressed.connect(_toggle_forge)
	_build_manager.tower_sold.connect(_on_tower_sold)
	_game_state.lives_changed.connect(_refresh_card.unbind(1))
	_hud.joystick_changed.connect(func(v: Vector2) -> void: _hero.joystick_vector = v)
	_hero.order_cancelled.connect(_on_hero_order_ended)
	_hero.order_finished.connect(_on_hero_order_ended)
	_hero.wood_gathered.connect(_on_wood_gathered)

	_hud.set_gold(_game_state.gold)
	_hud.set_wood(_game_state.wood)
	_hud.set_lives(_game_state.lives)
	_hud.set_wave(0, _wave_manager.get_total_waves())
	_refresh_card()
	_wave_manager.schedule_next_wave(_wave_manager.plan.first_delay)
	_build_walk_grid.call_deferred()


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			# Android back button: pause menu (and back out of it).
			_toggle_pause()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			# Phone call, home button: never let waves run unattended.
			if OS.has_feature("mobile") and not _paused and not _ended:
				_toggle_pause()


func _toggle_pause() -> void:
	if _ended:
		return
	_paused = not _paused
	get_tree().paused = _paused
	if _paused:
		_hero.cancel_order()
		_hud.show_pause_menu()
	else:
		_hud.hide_pause_menu()


func _toggle_speed() -> void:
	Engine.time_scale = 1.0 if Engine.time_scale > 1.0 else 2.0
	_hud.set_speed(roundi(Engine.time_scale))


func _process(_delta: float) -> void:
	var next: int = _wave_manager.current_wave + 1
	_hud.set_next_wave(next, _wave_manager.time_to_next_wave(), _wave_manager.plan.is_boss_wave(next))
	_auto_select_near_hero()
	_update_target_ring()


## Ring under whatever the next swing hits; the attack button shows an axe
## for trees and a sword for enemies.
func _update_target_ring() -> void:
	var target: Node3D = _hero.get_focus_target()
	if target != _focused_tree:
		if is_instance_valid(_focused_tree):
			_focused_tree.set_highlighted(false)
		_focused_tree = target as WoodTree
		if _focused_tree:
			_focused_tree.set_highlighted(true)
	_target_ring.visible = target != null
	var is_tree: bool = target is WoodTree
	_hud.set_attack_mode(is_tree)
	if target == null:
		return
	_target_ring.global_position = Vector3(target.global_position.x, 0.08, target.global_position.z)
	var radius: float = 0.8
	if target is Enemy:
		radius = 1.1 if (target as Enemy).is_boss() else 0.5
	var pulse: float = 1.0 + 0.08 * sin(Time.get_ticks_msec() * 0.008)
	_target_ring.scale = Vector3(radius * pulse, 0.5, radius * pulse)
	_ring_material.albedo_color = RING_TREE_COLOR if is_tree else RING_ENEMY_COLOR


func _build_level() -> void:
	var id: int = int(level["id"])
	for part in ["terrain", "decor", "forest"]:
		var scene: PackedScene = load("res://assets/models/level_%d_%s.glb" % [id, part])
		var node: Node3D = scene.instantiate()
		# Ground, small props and the far forest cast no shadows (half the triangles
		# of the frame otherwise go to the shadow pass); trees and towers still do.
		node.set_script(NO_SHADOW)
		_level_root.add_child(node)
		if part == "decor":
			_plant_trees(node)

	var path: Array = level["path"]
	var curve := Curve3D.new()
	for point: Array in path:
		curve.add_point(_ground(point, PATH_HEIGHT))
	_enemy_path.curve = curve

	var first_dir: Vector3 = (_ground(path[1]) - _ground(path[0])).normalized()
	var portal: Node3D = PORTAL_SCENE.instantiate()
	portal.position = _ground(path[0])
	portal.rotation.y = atan2(first_dir.x, first_dir.z)
	_level_root.add_child(portal)

	var last_dir: Vector3 = (_ground(path[-1]) - _ground(path[-2])).normalized()
	var castle: Node3D = CASTLE_SCENE.instantiate()
	_castle = castle
	castle.position = _ground(level["castle"])
	castle.rotation.y = atan2(-last_dir.x, -last_dir.z)
	_level_root.add_child(castle)

	for point: Array in level["slots"]:
		var slot: Node3D = SLOT_SCENE.instantiate()
		slot.position = _ground(point, PATH_HEIGHT)
		_level_root.add_child(slot)

	_hero.position = _ground(level["hero"])
	var b: Array = level["bounds"]
	_camera.bounds = Rect2(b[0], b[1], b[2], b[3]).grow(-CAMERA_MARGIN)
	_camera.snap()


## Replaces the Chop_<kind>_<i> markers of the decor model with choppable trees.
## Standing trees are drawn by one Grove (MultiMesh) to save draw calls.
func _plant_trees(decor: Node3D) -> void:
	var grove := Grove.new()
	grove.name = "Grove"
	_level_root.add_child(grove)
	var trees: Array[WoodTree] = []
	for marker: Node in decor.find_children("Chop_*", "Node3D", true, false):
		var spot := marker as Node3D
		var tree := TREE_SCENE.instantiate() as WoodTree
		tree.variant = StringName(String(spot.name).get_slice("_", 1))
		tree.model_scale = spot.scale.x
		tree.grove = grove
		tree.position = spot.global_position
		_level_root.add_child(tree)
		trees.append(tree)
		spot.queue_free()
	grove.build(trees)


## Needs the level's bodies in the physics space: runs after a physics frame.
func _build_walk_grid() -> void:
	await get_tree().physics_frame
	var b: Array = level["bounds"]
	walk_grid.build(get_world_3d().direct_space_state, Rect2(b[0], b[1], b[2], b[3]), WALK_OBSTACLE_MASK)
	_hero.walk_grid = walk_grid


func _ground(point: Array, height: float = 0.0) -> Vector3:
	return Vector3(float(point[0]), height, float(point[1]))


func _tower_types() -> Array[TowerData]:
	return _build_manager.tower_types


## Command card action: the hero walks to the selected slot and acts there.
func _on_command_pressed(id: StringName) -> void:
	if id == &"cancel":
		_forge_open = false
		_hero.cancel_order()
		_build_manager.clear_selection()
		_refresh_card()
		return
	if id == &"sword":
		if _game_state.spend(_hero.sword_upgrade_cost()):
			_hero.upgrade_sword()
			_spawn_fx(UPGRADE_FX, _hero.global_position)
		_refresh_card()
		return
	if id == &"repair":
		if _game_state.repair():
			_spawn_fx(BUILD_FX, _castle.global_position)
		_refresh_card()
		return
	if id == &"sell":
		_build_manager.sell(_build_manager.selected_slot)
		_refresh_card()
		return
	var slot: TowerSlot = _build_manager.selected_slot
	if slot == null or not _command_available(id, slot):
		return
	if _hero.is_near(slot.global_position, BUILD_REACH):
		_execute(id, slot)
	else:
		_hero.move_to(slot.global_position, BUILD_REACH, _execute.bind(id, slot))
		_pending_command = id
		_refresh_card()


func _execute(id: StringName, slot: TowerSlot) -> void:
	if id == &"upgrade":
		_build_manager.upgrade(slot)
	else:
		_build_manager.build_on(slot, _tower_for(id))
	_refresh_card()


func _tower_for(id: StringName) -> TowerData:
	var index: int = int(String(id).trim_prefix("build_"))
	return _tower_types()[index]


func _command_available(id: StringName, slot: TowerSlot) -> bool:
	if id == &"upgrade":
		return _build_manager.can_upgrade(slot)
	return _build_manager.can_build(slot, _tower_for(id))


func _auto_select_near_hero() -> void:
	# Walking (keys, joystick or a tap on the ground) selects the slot the hero
	# reaches; a pending build/upgrade command keeps its own target.
	if _hero.velocity.length() < 0.1 or _pending_command != &"":
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
	var info := {}
	var buttons: Array[Dictionary] = []
	if slot == null:
		_range_ring.hide()
	if slot == null and _forge_open:
		_hud.show_hint("")
		_hud.update_card(_forge_card())
		return
	if slot == null:
		_hud.show_hint(_hint_text())
		_hud.update_card({})
		return
	_forge_open = false
	_hud.show_hint("")
	if slot.is_free():
		info["title"] = "Площадка для башни"
		info["stats"] = "Выберите башню"
		var short := true
		for i in _tower_types().size():
			var data: TowerData = _tower_types()[i]
			var ok: bool = _build_manager.can_build(slot, data)
			short = short and not ok
			buttons.append({
				"id": StringName("build_%d" % i), "icon": data.icon, "gold": data.cost_gold,
				"wood": data.cost_wood, "enabled": ok,
				"tooltip": "%s (%d): %s" % [data.display_name, i + 1, _stats_text(data, 0)],
			})
		info["hint"] = "Не хватает золота или дерева" if short else ""
	else:
		var data: TowerData = slot.tower.data
		var level_index: int = slot.tower.level
		var cost: Vector2i = data.upgrade_cost(level_index)
		info["title"] = "%s · ур. %d/%d" % [data.display_name, level_index + 1, data.max_level() + 1]
		info["stats"] = _stats_text(data, level_index)
		var upgrade := {"id": &"upgrade", "icon": UPGRADE_ICON, "enabled": _build_manager.can_upgrade(slot),
				"tooltip": "Улучшить (U)"}
		if cost.x < 0:
			upgrade["label"] = "макс."
			info["hint"] = "Максимальный уровень"
		else:
			upgrade["gold"] = cost.x
			upgrade["wood"] = cost.y
			info["hint"] = "Дальше: " + _stats_text(data, level_index + 1)
			if not upgrade["enabled"]:
				info["hint"] = "Не хватает золота или дерева"
		buttons.append(upgrade)
		var refund: Vector2i = data.sell_value(level_index)
		buttons.append({"id": &"sell", "icon": COIN_ICON, "gold": refund.x, "wood": refund.y, "gain": true,
				"enabled": true, "tooltip": "Продать за 70%% вложенного (X)"})
	if slot != null:
		buttons.append({"id": &"cancel", "icon": CANCEL_ICON, "label": "Esc", "enabled": true,
				"tooltip": "Снять выбор (Esc)"})
	if _pending_command != &"":
		info["hint"] = "Рыцарь идёт к площадке…"
	_show_range(slot)
	info["buttons"] = buttons
	_hud.update_card(info)


## Attack radius of the tower on `slot` (hidden for a free slot).
func _show_range(slot: TowerSlot) -> void:
	_range_ring.visible = slot != null and slot.tower != null
	if _range_ring.visible:
		var r: float = slot.tower.range_m
		_range_ring.global_position = Vector3(slot.global_position.x, 0.07, slot.global_position.z)
		_range_ring.scale = Vector3(r, 1.0, r)


## Forge card: sword upgrade and castle repair.
func _forge_card() -> Dictionary:
	var info := {"title": "Кузница"}
	var sword: Vector2i = _hero.sword_upgrade_cost()
	var next_damage: String = ""
	if sword.x >= 0:
		next_damage = " → %d" % _hero.sword_damage_levels[_hero.sword_level + 1]
	info["stats"] = "Меч: урон %d%s · замок: %d/%d жизней" % [
		_hero.attack_damage, next_damage, _game_state.lives, _game_state.starting_lives]
	var upgrade := {"id": &"sword", "icon": SWORD_ICON, "enabled": _game_state.can_afford(sword),
			"tooltip": "Закалить меч (U)"}
	if sword.x < 0:
		upgrade["label"] = "макс."
	else:
		upgrade["gold"] = sword.x
		upgrade["wood"] = sword.y
	var repair := {"id": &"repair", "icon": HEART_ICON, "wood": _game_state.repair_wood,
			"enabled": _game_state.can_repair(), "tooltip": "Починить стены: +%d жизни" % _game_state.repair_lives}
	info["hint"] = "Ремонт стен: +%d жизни за %d дерева" % [_game_state.repair_lives, _game_state.repair_wood]
	info["buttons"] = [upgrade, repair, {"id": &"cancel", "icon": CANCEL_ICON, "label": "Esc", "enabled": true,
			"tooltip": "Закрыть (Esc)"}]
	return info


func _toggle_forge() -> void:
	_forge_open = not _forge_open
	if _forge_open:
		_build_manager.clear_selection()
	_refresh_card()


## Step-by-step hint for new players while nothing is selected.
func _hint_text() -> String:
	var towers: int = 0
	for node: Node in get_tree().get_nodes_in_group(TowerSlot.GROUP):
		if not (node as TowerSlot).is_free():
			towers += 1
	if towers >= HINT_TOWERS:
		return ""
	var cheapest: TowerData = _tower_types()[0]
	if _game_state.wood < cheapest.cost_wood:
		return "Подойдите к дереву или нажмите на него — рыцарь сам нарубит дров"
	if _game_state.gold < cheapest.cost_gold:
		return "Бейте слизней у тропы — за них дают золото"
	return "Нажмите на каменную площадку и постройте башню"


func _stats_text(data: TowerData, index: int) -> String:
	var text := "Урон %d · радиус %.1f · %.2f с" % [
		data.damage_levels[index], data.range_levels[index], data.interval_levels[index]]
	if data.splash_levels[index] > 0.0:
		text += " · по площади %.1f м" % data.splash_levels[index]
	if data.slow_levels[index] < 1.0:
		text += " · замедление %d%%" % roundi((1.0 - data.slow_levels[index]) * 100.0)
	return text


func _spawn_fx(scene: PackedScene, at: Vector3) -> void:
	var fx := scene.instantiate() as Node3D
	add_child(fx)
	fx.global_position = at


func _popup(text: String, at: Vector3, color: Color, icon: Texture2D = null) -> void:
	if not _camera.is_position_behind(at):
		_hud.popup(text, _camera.unproject_position(at), color, icon)


func _on_resources_changed() -> void:
	_hud.set_gold(_game_state.gold)
	_hud.set_wood(_game_state.wood)
	_refresh_card()


func _on_wood_gathered(amount: int, at: Vector3) -> void:
	_game_state.add_wood(amount)
	_popup("+%d" % amount, at + Vector3.UP * 1.6, WOOD_COLOR, WOOD_ICON)


func _on_tower_built(slot: TowerSlot, tower: Tower) -> void:
	walk_grid.block(slot.global_position, TOWER_BLOCK_RADIUS)
	_spawn_fx(BUILD_FX, slot.global_position)
	# Rise out of the dust.
	tower.scale = Vector3(1.0, 0.2, 1.0)
	create_tween().tween_property(tower, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK)
	_refresh_card()


func _on_tower_sold(slot: TowerSlot, refund: Vector2i) -> void:
	walk_grid.unblock(slot.global_position)
	_spawn_fx(BUILD_FX, slot.global_position)
	_popup("+%d" % refund.x, slot.global_position + Vector3.UP * 1.2, GOLD_COLOR, COIN_ICON)
	_refresh_card()


func _on_tower_upgraded(slot: TowerSlot, _tower: Tower) -> void:
	_spawn_fx(UPGRADE_FX, slot.global_position)
	_refresh_card()


func _on_hero_order_ended() -> void:
	_pending_command = &""
	_refresh_card()


func _on_ground_tapped(point: Vector3) -> void:
	# A tap on (or right next to) a tree: walk up to it, the hero chops by himself.
	var best: WoodTree = null
	var best_distance: float = TREE_TAP_REACH
	for node: Node in get_tree().get_nodes_in_group(WoodTree.GROUP):
		var tree := node as WoodTree
		var offset: Vector3 = tree.global_position - point
		offset.y = 0.0
		if tree.is_choppable() and offset.length() < best_distance:
			best_distance = offset.length()
			best = tree
	if best != null:
		_hero.move_to(best.global_position, _hero.chop_range * 0.8)
	else:
		_hero.move_to(point, 0.15)


func _on_next_wave_pressed() -> void:
	var left: float = _wave_manager.time_to_next_wave()
	if left > 0.0 and _wave_manager.start_next_wave():
		var bonus: int = floori(left * EARLY_CALL_GOLD_PER_SECOND)
		if bonus > 0:
			_game_state.add_gold(bonus)
			_popup("+%d" % bonus, _hero.global_position + Vector3.UP * 2.0, GOLD_COLOR, COIN_ICON)


func _on_enemy_reached_base(damage: int) -> void:
	_base_hit.play()
	_game_state.lose_lives(damage)


func _on_wave_started(wave: int, total: int, boss: bool) -> void:
	_hud.set_wave(wave, total)
	_wave_horn.play()
	if boss:
		_boss_roar.play()
		_hud.show_boss_banner()


func _on_all_waves_cleared() -> void:
	if _game_state.is_defeated:
		return
	var stars: int = LevelCatalog.stars_for(_game_state.lives, _game_state.starting_lives)
	LevelCatalog.complete(int(level["id"]), stars)
	_victory_sound.play()
	_end_game("Победа!", true, stars)


func _on_defeated() -> void:
	_wave_manager.stop()
	_defeat_sound.play()
	_end_game("Поражение", false)


func _end_game(message: String, victory: bool, stars: int = 0) -> void:
	_ended = true
	Engine.time_scale = 1.0
	_hero.cancel_order()
	_build_manager.clear_selection()
	_hud.show_end_screen(message, victory, stars)
	get_tree().paused = true


## All level state lives in this scene's nodes, so reloading it restores the
## starting resources, lives and wave and frees old enemies and towers.
## SceneTree.paused is the only state that survives a reload: clear it first.
func _on_restart_pressed() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	var error: Error = get_tree().reload_current_scene()
	if error != OK:
		push_error("Restart failed: %s" % error_string(error))
		get_tree().paused = true


func _on_map_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(LEVEL_SELECT_SCENE)

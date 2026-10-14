extends Node3D
## Root of a level: builds the selected level from resources/levels.json
## (terrain, castle, portals and paths, slots, trees, hero spot), wires the game
## systems together through their signals and turns the hero's command card
## into orders (walk to the slot, then build).

enum GuideStep { NONE, CHOP, GOLD, BUILD }

const DEFEAT_TIPS: Array[String] = [
	"Мороз перед Пушкой: замедленные враги дольше под обстрелом",
	"улучшайте меч в кузнице и встречайте босса «Вихрем»",
	"звёзды покупают постоянные улучшения в Казне на карте",
	"рубите деревья между волнами — дерево нужно для улучшений",
	"ставьте башни там, где тропа делает петлю: враги проходят их дважды",
]

## Perks recorded in the journal header and applied by a replay.
const PERK_KEYS: Array[StringName] = [
	&"sword", &"axe", &"towers", &"gold_start", &"wood_start", &"walls"
]
const LEVEL_SELECT_SCENE := "res://scenes/level_select.tscn"
const TUTORIAL_SCENE := preload("res://scenes/tutorial.tscn")
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
const SELL_ICON: Texture2D = preload("res://ui/icons/sell.png")
const SWORD_ICON: Texture2D = preload("res://ui/icons/sword.png")
const HEART_ICON: Texture2D = preload("res://ui/icons/heart.png")
const CANCEL_ICON: Texture2D = preload("res://ui/icons/cancel.png")
const VILLAGER_ICON: Texture2D = preload("res://ui/icons/villager.png")
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
## The guide arrow looks for a new target this often (it scans groups).
const GUIDE_REFRESH_FRAMES := 12
## Physics layers that block walking: level colliders (1) and trees (3).
const WALK_OBSTACLE_MASK := 1 | 4
## Radius a built tower blocks on the walk grid.
const TOWER_BLOCK_RADIUS := 0.6
## A tap this close to a villager sends the hero to trade with it.
const VILLAGER_TAP_REACH := 1.0
## The trade card stays open until the hero is this much further than the trade reach.
const TRADE_KEEP_SLACK := 0.6

var level: Dictionary = {}
var walk_grid := WalkGrid.new()
var villagers := Villagers.new()

## Battle simulation (fixed-step clock, entity registry) and the single entry
## for player actions (journal of the battle).
var _sim: Sim = null
var _commands: GameCommands = null

var _focused_tree: WoodTree = null
## What the hero's next swing hits, computed once per frame.
var _focus: Node3D = null
var _guide_target: Node3D = null
var _pending_slot: TowerSlot = null
var _guide_wait: int = 0
var _guide_done: bool = false
var _paused: bool = false
var _endless: bool = false
var _waves_cleared: int = 0
## Battle summary for the end screen.
var _stats := {"kills": 0, "gold": 0, "wood": 0, "towers": 0, "time": 0.0}
var _forge_open: bool = false
var _castle: Node3D = null
var _ended: bool = false
## Onboarding tutorial overlay (only on its level in tutorial mode).
var _tutorial: Tutorial = null

## Command to run when the hero reaches the selected slot, or &"".
var _pending_command: StringName = &""
## Villager whose trade card is open, one the player closed it for (until the
## hero walks away), and whether the hero walks to it after a tap.
var _trade_with: Villager = null
var _trade_dismissed: Villager = null
var _trade_walking: bool = false

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
@onready var _guide_arrow: MeshInstance3D = $GuideArrow
@onready var _ring_material: StandardMaterial3D = _target_ring.mesh.surface_get_material(0)
@onready var _wave_boom: AudioStreamPlayer = $Sfx/WaveBoom
@onready var _boss_roar: AudioStreamPlayer = $Sfx/BossRoar
@onready var _base_hit: AudioStreamPlayer = $Sfx/BaseHit
@onready var _victory_sound: AudioStreamPlayer = $Sfx/Victory
@onready var _defeat_sound: AudioStreamPlayer = $Sfx/Defeat


func _ready() -> void:
	_sim = Sim.new()
	_sim.name = "Sim"
	add_child(_sim)
	_sim.set_seed(randi())  # a replay overrides it (Sim.begin_replay)
	_commands = GameCommands.new()
	_commands.name = "GameCommands"
	_commands.sim = _sim
	add_child(_commands)
	level = LevelCatalog.get_level(LevelCatalog.selected_id)
	_build_level()
	_endless = LevelCatalog.endless
	_apply_perks(_current_perks())
	_wave_manager.plan = WavePlan.new(level["waves"], _endless)
	_wave_manager.sim = _sim
	_build_manager.sim = _sim
	_hero.sim = _sim
	_hero.commands = _commands
	_commands.game_state = _game_state
	_commands.build_manager = _build_manager
	_commands.hero = _hero
	_commands.villagers = villagers
	_sim.commands = _commands
	_sim.game_state = _game_state
	_sim.wave_manager = _wave_manager
	_sim.hero = _hero
	_sim.villagers = villagers
	_commands.journal.header = _journal_header()
	_commands.set_hero_limits(_hero.global_position, _map_rect())
	_wave_manager.wave_cleared.connect(
		func(wave: int) -> void: _waves_cleared = maxi(_waves_cleared, wave)
	)

	_game_state.gold_changed.connect(_on_resources_changed.unbind(1))
	_game_state.wood_changed.connect(_on_resources_changed.unbind(1))
	_game_state.lives_changed.connect(_hud.set_lives)
	_game_state.defeated.connect(_on_defeated)

	_wave_manager.enemy_killed.connect(_game_state.add_gold)
	_wave_manager.enemy_killed.connect(_count_kill)
	_wave_manager.enemy_reached_base.connect(_on_enemy_reached_base)
	_wave_manager.wave_started.connect(_on_wave_started)
	# Deferred: the last enemy may leak in the same emission chain (it still has to
	# take its lives), so the stars are counted after the lives are final.
	_wave_manager.all_waves_cleared.connect(_on_all_waves_cleared, CONNECT_DEFERRED)

	_build_manager.slot_selected.connect(_on_slot_selected)
	_build_manager.selection_cleared.connect(_refresh_card)
	_build_manager.tower_built.connect(_on_tower_built)
	_build_manager.tower_upgraded.connect(_on_tower_upgraded)
	_build_manager.ground_tapped.connect(_on_ground_tapped)
	_commands.applied.connect(_on_command_applied)
	_sim.pause_changed.connect(_on_pause_changed)
	_sim.speed_changed.connect(_on_speed_changed)
	_sim.replay_begun.connect(_on_replay_begun)

	_hud.command_pressed.connect(_on_command_pressed)
	_hud.attack_pressed.connect(_hero.try_attack)
	_hud.spin_pressed.connect(_hero.try_spin)
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
	villagers.name = "Villagers"
	villagers.game_state = _game_state
	villagers.seed_value = _sim.seed_value
	villagers.wood_sold.connect(_on_wood_sold)
	_level_root.add_child(villagers)

	_hud.set_gold(_game_state.gold)
	_hud.set_wood(_game_state.wood)
	_hud.set_lives(_game_state.lives)
	_hud.set_wave(0, 0 if _endless else _wave_manager.get_total_waves())
	_refresh_card()
	_wave_manager.schedule_next_wave(_wave_manager.plan.first_delay)
	if _endless:
		Online.start_run(int(level["id"]))  # server-side start time for the record check
	_hud.show_banner("Первая волна через " + _seconds_text(_wave_manager.plan.first_delay))
	_build_walk_grid.call_deferred()
	_start_tutorial()


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
	_commands.submit(GameCommand.set_pause(not _paused))


## The pause command was applied: stop / resume the whole tree.
func _on_pause_changed(on: bool) -> void:
	if _ended:
		return
	_paused = on
	get_tree().paused = _paused
	_hero.joystick_vector = Vector2.ZERO
	_camera.reset_touches()
	if _paused:
		_hero.cancel_order()
		_hud.show_pause_menu()
	else:
		_hud.hide_pause_menu()


func _toggle_speed() -> void:
	_commands.submit(GameCommand.set_speed(1 if Engine.time_scale > 1.0 else 2))


## The speed command was applied: x2 only means twice as many frames of real
## time per second, so the simulation still sees the same steps.
func _on_speed_changed(speed: int) -> void:
	Engine.time_scale = float(speed)
	_hud.set_speed(speed)


## What a replay needs to know about the battle it reproduces.
func _journal_header() -> Dictionary:
	return {
		"sim_version": Sim.VERSION,
		"tick_rate": Sim.TICK_RATE,
		"level": int(level["id"]),
		"endless": _endless,
		"seed": _sim.seed_value,
		"perks": _current_perks(),
	}


## The player's permanent perks by name.
func _current_perks() -> Dictionary:
	var out := {}
	for key: StringName in PERK_KEYS:
		out[String(key)] = Perks.value(key)
	return out


## Starting resources, lives and damage bonuses from `perks`. A replay applies
## the perks of its journal header (not the local save), so every client plays
## the same battle; call it before the battle clock starts.
func _apply_perks(perks: Dictionary) -> void:
	var start: Dictionary = level["start"].duplicate()
	start["gold"] = int(start["gold"]) + int(perks.get("gold_start", 0))
	start["wood"] = int(start["wood"]) + int(perks.get("wood_start", 0))
	start["lives"] = int(start["lives"]) + int(perks.get("walls", 0))
	_game_state.configure(start)
	_game_state.reset()
	_hero.damage_multiplier = 1.0 + float(perks.get("sword", 0.0))
	_hero.wood_bonus = int(perks.get("axe", 0))
	_build_manager.damage_multiplier = 1.0 + float(perks.get("towers", 0.0))


func _on_replay_begun(header: Dictionary) -> void:
	_apply_perks(header.get("perks", {}))


## Playable area of the map (metres), for validating hero commands.
func _map_rect() -> Rect2:
	var b: Array = level["bounds"]
	return Rect2(b[0], b[1], b[2], b[3])


## UI reaction to an executed command: effects of the forge, a fresh card.
func _on_command_applied(cmd: GameCommand, ok: bool) -> void:
	if not ok:
		return
	match cmd.type:
		GameCommand.Type.SWORD:
			_spawn_fx(UPGRADE_FX, _hero.global_position)
			_refresh_card()
		GameCommand.Type.REPAIR:
			_spawn_fx(BUILD_FX, _castle.global_position)
			_refresh_card()


func _count_kill(reward: int) -> void:
	_stats["kills"] += 1
	_stats["gold"] += reward


func _stats_summary() -> String:
	var t: int = int(_stats["time"])
	var line_1 := "Врагов побеждено: %d · золота добыто: %d" % [_stats["kills"], _stats["gold"]]
	var line_2 := (
		"Дерева нарублено: %d · башен: %d · время %d:%02d"
		% [_stats["wood"], _stats["towers"], floori(t / 60.0), t % 60]
	)
	return line_1 + "\n" + line_2


func _process(delta: float) -> void:
	_stats["time"] += delta / Engine.time_scale  # real seconds, also at x2
	_auto_select_near_hero()
	_update_trade()
	_focus = _hero.get_focus_target()
	_update_target_ring()
	_hud.set_spin_cooldown(_hero.spin_cooldown_left())
	_update_guide_arrow()


## Ring under whatever the next swing hits; the attack button shows an axe
## for trees and a sword for enemies.
func _update_target_ring() -> void:
	var target: Node3D = _focus
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

	# One Path3D per entry: the scene's EnemyPath for the first, siblings for the rest.
	var paths: Array[Path3D] = []
	for route: PackedVector2Array in LevelCatalog.routes(level):
		var path3d: Path3D = _enemy_path
		if not paths.is_empty():
			path3d = Path3D.new()
			path3d.name = "EnemyPath%d" % (paths.size() + 1)
			_level_root.add_child(path3d)
		var curve := Curve3D.new()
		for point: Vector2 in route:
			curve.add_point(Vector3(point.x, PATH_HEIGHT, point.y))
		path3d.curve = curve
		paths.append(path3d)

		var first_dir: Vector3 = Vector3(route[1].x - route[0].x, 0.0, route[1].y - route[0].y)
		var portal: Node3D = PORTAL_SCENE.instantiate()
		portal.position = Vector3(route[0].x, 0.0, route[0].y)
		portal.rotation.y = atan2(first_dir.x, first_dir.z)
		_level_root.add_child(portal)
	_wave_manager.enemy_paths = paths

	var path: Array = level["paths"][0]
	var last_dir: Vector3 = (_ground(path[-1]) - _ground(path[-2])).normalized()
	var castle: Node3D = CASTLE_SCENE.instantiate()
	_castle = castle
	castle.position = _ground(level["castle"])
	castle.rotation.y = atan2(-last_dir.x, -last_dir.z)
	_level_root.add_child(castle)

	for point: Array in level["slots"]:
		var slot := SLOT_SCENE.instantiate() as TowerSlot
		slot.slot_id = _commands.slots.size()
		_commands.slots.append(slot)
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
		var kind: String = String(spot.name).get_slice("_", 1)
		var biome: String = level.get("biome", "meadow")
		tree.variant = StringName(kind if biome == "meadow" else "%s_%s" % [kind, biome])
		tree.model_scale = spot.scale.x
		tree.grove = grove
		tree.sim = _sim
		tree.position = spot.global_position
		_level_root.add_child(tree)
		trees.append(tree)
		spot.queue_free()
	grove.build(trees)


## Needs the level's bodies in the physics space: runs after a physics frame.
func _build_walk_grid() -> void:
	await get_tree().physics_frame
	var b: Array = level["bounds"]
	walk_grid.build(
		get_world_3d().direct_space_state, Rect2(b[0], b[1], b[2], b[3]), WALK_OBSTACLE_MASK
	)
	_hero.walk_grid = walk_grid
	var slots := PackedVector3Array()
	for point: Array in level["slots"]:
		slots.append(_ground(point))
	villagers.spawn(
		walk_grid,
		_wave_manager.get_paths(),
		_ground(level["castle"]),
		_ground(level["hero"]),
		slots
	)
	_sim.start()  # the level is complete: the battle clock may run


func _ground(point: Array, height: float = 0.0) -> Vector3:
	return Vector3(float(point[0]), height, float(point[1]))


func _tower_types() -> Array[TowerData]:
	return _build_manager.tower_types


## Command card action: the hero walks to the selected slot and acts there.
func _on_command_pressed(id: StringName) -> void:
	if id == &"trade_lot" or id == &"trade_all":
		var lots: int = 1 if id == &"trade_lot" else villagers.lots_affordable()
		if lots > 0:
			_commands.submit(GameCommand.trade(lots))
		_refresh_card()
		return
	if id == &"cancel":
		_trade_dismissed = _trade_with
		_set_trade(null)
		_forge_open = false
		_hero.cancel_order()
		_build_manager.clear_selection()
		_refresh_card()
		return
	if id == &"sword":
		_commands.submit(GameCommand.sword())
		return
	if id == &"repair":
		_commands.submit(GameCommand.repair())
		return
	if id == &"sell":
		if _build_manager.selected_slot != null:
			_commands.submit(GameCommand.sell(_build_manager.selected_slot.slot_id))
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
		_pending_slot = slot
		_refresh_card()


func _execute(id: StringName, slot: TowerSlot) -> void:
	if id == &"upgrade":
		_commands.submit(GameCommand.upgrade(slot.slot_id))
	else:
		_commands.submit(GameCommand.build(slot.slot_id, _tower_index(id)))
	_refresh_card()


func _tower_index(id: StringName) -> int:
	return int(String(id).trim_prefix("build_"))


func _tower_for(id: StringName) -> TowerData:
	return _tower_types()[_tower_index(id)]


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
	for slot in _commands.slots:
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
		_hud.update_card(CommandCards.forge(_hero, _game_state))
		return
	if slot == null and _trade_with != null:
		_hud.show_hint("")
		_hud.update_card(CommandCards.trade(villagers, _game_state))
		return
	if slot == null:
		_hud.show_hint(_hint_text())
		_hud.update_card({})
		return
	_forge_open = false
	_hud.show_hint("")
	if slot.is_free():
		info["title"] = "Площадка"
		var names: PackedStringArray = []
		for data: TowerData in _tower_types():
			names.append(data.display_name)
		info["stats"] = " · ".join(names)
		var short := true
		for i in _tower_types().size():
			var data: TowerData = _tower_types()[i]
			var ok: bool = _build_manager.can_build(slot, data)
			short = short and not ok
			(
				buttons
				. append(
					{
						"id": StringName("build_%d" % i),
						"icon": data.icon,
						"gold": data.cost_gold,
						"wood": data.cost_wood,
						"enabled": ok,
						"tooltip":
						(
							"%s (%d) — %s\n%s"
							% [data.display_name, i + 1, data.role, _stats_text(data, 0)]
						),
					}
				)
			)
		info["hint"] = "Не хватает золота или дерева" if short else ""
	else:
		var data: TowerData = slot.tower.data
		var level_index: int = slot.tower.level
		var cost: Vector2i = data.upgrade_cost(level_index)
		info["title"] = (
			"%s · ур. %d/%d" % [data.display_name, level_index + 1, data.max_level() + 1]
		)
		info["stats"] = _stats_text(data, level_index)
		var upgrade := {
			"id": &"upgrade",
			"icon": UPGRADE_ICON,
			"enabled": _build_manager.can_upgrade(slot),
			"tooltip": "Улучшить (U)"
		}
		if cost.x < 0:
			upgrade["label"] = "макс."
		else:
			upgrade["gold"] = cost.x
			upgrade["wood"] = cost.y
			upgrade["tooltip"] = "Улучшить (U) → " + _stats_text(data, level_index + 1)
			if not upgrade["enabled"]:
				info["hint"] = "Не хватает золота или дерева"
		buttons.append(upgrade)
		var refund: Vector2i = data.sell_value(level_index)
		buttons.append(
			{
				"id": &"sell",
				"icon": COIN_ICON,
				"gold": refund.x,
				"wood": refund.y,
				"gain": true,
				"enabled": true,
				"tooltip": "Продать за %d%% вложенного (X)" % roundi(TowerData.SELL_REFUND * 100.0)
			}
		)
	if slot != null:
		buttons.append(
			{
				"id": &"cancel",
				"icon": CANCEL_ICON,
				"label": "Esc",
				"enabled": true,
				"tooltip": "Снять выбор (Esc)"
			}
		)
	if _pending_command != &"":
		info["hint"] = "Рыцарь идёт к площадке…"
	_show_range(slot)
	info["buttons"] = buttons
	_hud.update_card(info)


## Attack radius of the tower on `slot` (for a free slot: what a new tower reaches).
func _show_range(slot: TowerSlot) -> void:
	_range_ring.visible = slot != null
	if _range_ring.visible:
		# A free slot previews the reach of the first tower type at level 1.
		var r: float = slot.tower.range_m if slot.tower else _tower_types()[0].range_levels[0]
		_range_ring.global_position = Vector3(slot.global_position.x, 0.07, slot.global_position.z)
		_range_ring.scale = Vector3(r, 1.0, r)


## Opens the trade card when the hero comes up to a villager and closes it
## when he walks away (unless he is still on his way after a tap).
func _update_trade() -> void:
	var near: Villager = villagers.nearest(_hero.global_position, villagers.trade_reach)
	if near != _trade_dismissed:
		_trade_dismissed = null
	if (
		_trade_with != null
		and (
			_trade_walking
			or _hero.is_near(_trade_with.global_position, villagers.trade_reach + TRADE_KEEP_SLACK)
		)
	):
		return
	_set_trade(null if near == _trade_dismissed else near)


func _set_trade(villager: Villager) -> void:
	if villager == _trade_with:
		return
	if _trade_with != null:
		_trade_with.talk_to(null)
	_trade_with = villager
	if villager != null:
		villager.talk_to(_hero)
	_refresh_card()


func _toggle_forge() -> void:
	_forge_open = not _forge_open
	if _forge_open:
		_build_manager.clear_selection()
	_refresh_card()


## Tutorial mode: the Tutorial node (its own overlay) replaces the built-in
## hints and guide arrow; it only observes the systems passed to it.
func _start_tutorial() -> void:
	if not LevelCatalog.tutorial or _endless or int(level["id"]) != Onboarding.TUTORIAL_LEVEL:
		return
	_tutorial = TUTORIAL_SCENE.instantiate()
	add_child(_tutorial)
	_tutorial.setup(_game_state, _wave_manager, _build_manager, _hero, _camera, _hud)
	_guide_done = true
	_refresh_card()


## Step-by-step hint for new players while nothing is selected.
func _hint_text() -> String:
	if _tutorial != null:
		return ""
	match _guide_step():
		GuideStep.CHOP:
			return "Нажмите на дерево — рыцарь нарубит дров"
		GuideStep.GOLD:
			return "Бейте слизней у тропы — за них золото"
		GuideStep.BUILD:
			return "Нажмите на площадку и постройте башню"
	return ""


## What a new player should do next (until HINT_TOWERS towers stand).
func _guide_step() -> GuideStep:
	var towers: int = 0
	for node: Node in get_tree().get_nodes_in_group(TowerSlot.GROUP):
		if not (node as TowerSlot).is_free():
			towers += 1
	if towers >= HINT_TOWERS:
		return GuideStep.NONE
	var cheapest: TowerData = _tower_types()[0]
	if _game_state.wood < cheapest.cost_wood:
		return GuideStep.CHOP
	if _game_state.gold < cheapest.cost_gold:
		return GuideStep.GOLD
	return GuideStep.BUILD


## Bouncing arrow over the next thing to do: a tree, a slime, a free slot.
func _update_guide_arrow() -> void:
	var target: Node3D = null
	_guide_wait -= 1
	if _guide_done or _guide_wait > 0:
		if _guide_done:
			_guide_arrow.hide()
		elif _guide_target and is_instance_valid(_guide_target):
			_place_guide_arrow(_guide_target)
		else:
			_guide_arrow.hide()
		return
	_guide_wait = GUIDE_REFRESH_FRAMES
	if _guide_step() == GuideStep.NONE:
		_guide_done = true  # hints end for good once the first towers stand
	if _build_manager.selected_slot == null and not _forge_open:
		match _guide_step():
			GuideStep.CHOP:
				target = _nearest_in_group(
					WoodTree.GROUP, func(n: Node) -> bool: return (n as WoodTree).is_choppable()
				)
			GuideStep.GOLD:
				target = _nearest_in_group(
					Enemy.GROUP, func(n: Node) -> bool: return (n as Enemy).is_alive()
				)
			GuideStep.BUILD:
				target = _nearest_in_group(
					TowerSlot.GROUP, func(n: Node) -> bool: return (n as TowerSlot).is_free()
				)
	_guide_target = target
	_place_guide_arrow(target)


func _place_guide_arrow(target: Node3D) -> void:
	_guide_arrow.visible = target != null and target != _focus
	if _guide_arrow.visible:
		var bob: float = 0.18 * sin(Time.get_ticks_msec() * 0.006)
		var height: float = 2.6 if target is WoodTree else 1.0
		_guide_arrow.global_position = target.global_position + Vector3(0.0, height + bob, 0.0)
		_guide_arrow.rotation.y = Time.get_ticks_msec() * 0.002


func _nearest_in_group(group: StringName, accept: Callable) -> Node3D:
	var best: Node3D = null
	var best_distance: float = INF
	for node: Node in get_tree().get_nodes_in_group(group):
		var d: float = (node as Node3D).global_position.distance_squared_to(_hero.global_position)
		if d < best_distance and accept.call(node):
			best_distance = d
			best = node as Node3D
	return best


func _stats_text(data: TowerData, index: int) -> String:
	var text := (
		"Урон %d · радиус %.1f · %.2f с"
		% [data.damage_levels[index], data.range_levels[index], data.interval_levels[index]]
	)
	if data.splash_levels[index] > 0.0:
		text += " · взрыв %.1f м" % data.splash_levels[index]
	if data.slow_levels[index] < 1.0:
		text += " · замедл. %d%%" % roundi((1.0 - data.slow_levels[index]) * 100.0)
	return text


func _spawn_fx(scene: PackedScene, at: Vector3) -> void:
	var fx := scene.instantiate() as Node3D
	add_child(fx)
	fx.global_position = at


func _popup(text: String, at: Vector3, color: Color, icon: Texture2D = null) -> void:
	if not _camera.is_position_behind(at):
		_hud.popup(text, _camera.unproject_position(at), color, icon)


func _on_slot_selected(slot: TowerSlot) -> void:
	# Picking another slot drops a build/upgrade the hero was walking to do.
	if _pending_command != &"" and slot != _pending_slot:
		_hero.cancel_order()
	_refresh_card()


func _on_resources_changed() -> void:
	_hud.set_gold(_game_state.gold)
	_hud.set_wood(_game_state.wood)
	_refresh_card()


func _on_wood_gathered(amount: int, at: Vector3) -> void:
	_game_state.add_wood(amount)
	_stats["wood"] += amount
	_popup("+%d" % amount, at + Vector3.UP * 1.6, WOOD_COLOR, WOOD_ICON)


func _on_wood_sold(_wood: int, gold: int) -> void:
	var at: Vector3 = _trade_with.global_position if _trade_with else _hero.global_position
	_popup("+%d" % gold, at + Vector3.UP * 1.4, GOLD_COLOR, COIN_ICON)
	if _trade_with != null:
		_trade_with.cheer()


func _on_tower_built(slot: TowerSlot, tower: Tower) -> void:
	_stats["towers"] += 1
	walk_grid.block(slot.global_position, TOWER_BLOCK_RADIUS)
	_spawn_fx(BUILD_FX, slot.global_position)
	# Rise out of the dust.
	tower.scale = Vector3(1.0, 0.2, 1.0)
	tower.create_tween().tween_property(tower, "scale", Vector3.ONE, 0.45).set_trans(
		Tween.TRANS_BACK
	)
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
	_trade_walking = false
	_refresh_card()


func _on_ground_tapped(point: Vector3) -> void:
	# A tap on a villager: open the trade card, the hero walks up to it.
	var villager: Villager = villagers.nearest(point, VILLAGER_TAP_REACH)
	if villager != null:
		_trade_dismissed = null
		_hero.move_to(villager.global_position, villagers.trade_reach * 0.7)
		_trade_walking = true
		_set_trade(villager)
		return
	# A tap on (or right next to) a tree: walk up to it, the hero chops by himself.
	var best: WoodTree = null
	var best_distance: float = TREE_TAP_REACH
	for tree in _sim.trees:
		var offset: Vector3 = tree.global_position - point
		offset.y = 0.0
		if tree.is_choppable() and offset.length() < best_distance:
			best_distance = offset.length()
			best = tree
	if best != null:
		_hero.move_to(best.global_position, _hero.chop_range * 0.8)
	else:
		_hero.move_to(point, 0.15)


func _on_enemy_reached_base(damage: int) -> void:
	_base_hit.play()
	_game_state.lose_lives(damage)


func _on_wave_started(wave: int, total: int, boss: bool) -> void:
	_hud.set_wave(wave, 0 if _endless else total)
	_wave_boom.play()
	if boss:
		_boss_roar.play()
	# One banner per wave (a boss wave gets the king icon, not a second banner).
	var last: bool = not _endless and wave >= total
	var title: String = "Последняя волна!" if last else "Волна %d!" % wave
	var next: String = ""
	if not last:
		next = "Следующая через " + _seconds_text(_wave_manager.plan.wave_duration)
	_hud.show_banner(title, next, boss)


## "30 секунд", "21 секунду", "2 секунды".
func _seconds_text(seconds: float) -> String:
	var n: int = roundi(seconds)
	var word: String = "секунд"
	if n % 10 == 1 and n % 100 != 11:
		word = "секунду"
	elif n % 10 in [2, 3, 4] and not (n % 100 in [12, 13, 14]):
		word = "секунды"
	return "%d %s" % [n, word]


func _on_all_waves_cleared() -> void:
	if _game_state.is_defeated or _ended:
		return
	var stars: int = LevelCatalog.stars_for(_game_state.lives, _game_state.starting_lives)
	var before: int = Perks.earned_stars()
	LevelCatalog.complete(int(level["id"]), stars)
	var gained: int = Perks.earned_stars() - before
	_victory_sound.play()
	var line: String = "Звёзд всего: %d из %d" % [Perks.earned_stars(), Perks.max_stars()]
	if gained > 0:
		line = "Новые звёзды: +%d! %s\nПотратьте их в Казне на карте" % [gained, line]
	elif stars < 3:
		line += "\n3 звезды — пройти, не потеряв ни одной жизни"
	_end_game("Победа!", true, stars, line + "\n")


func _on_defeated() -> void:
	if _ended:
		return
	_wave_manager.stop()
	_defeat_sound.play()
	if _endless:
		var id: int = int(level["id"])
		var old_record: int = LevelCatalog.endless_record(id)
		var record: bool = LevelCatalog.save_endless(id, _waves_cleared)
		if record:
			Online.submit_record(id, _waves_cleared)
		var title := "Новый рекорд: %d волн!" % _waves_cleared if record else "Осада окончена"
		var line := (
			"Пройдено волн: %d · рекорд: %d · звёзд за осаду: %d из %d"
			% [
				_waves_cleared,
				maxi(old_record, _waves_cleared),
				Perks.endless_stars(id),
				Perks.ENDLESS_MAX_STARS
			]
		)
		_end_game(title, record, 0, line + "\n")
		return
	var tips: Array[String] = DEFEAT_TIPS.duplicate()
	tips.append(
		(
			"ремонт стен в кузнице: +%d жизни за %d дерева"
			% [_game_state.repair_lives, _game_state.repair_wood]
		)
	)
	_end_game("Поражение", false, 0, "Совет: " + tips.pick_random() + "\n")


func _end_game(message: String, victory: bool, stars: int = 0, prefix: String = "") -> void:
	_ended = true
	Engine.time_scale = 1.0
	_hero.cancel_order()
	_build_manager.clear_selection()
	_hud.show_end_screen(message, victory, stars, prefix + _stats_summary())
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

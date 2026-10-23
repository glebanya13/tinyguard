extends Node3D
## Root of a level: wires the game systems together through their signals. The work
## is split by responsibility: LevelBuilder (terrain, paths, slots, trees),
## CardController (the hero's command card, trade, taps), GuideHints (hints, arrow,
## tutorial hook), BattleEnd (statistics, victory / defeat) and CoopHooks (co-op match).

const LEVEL_SELECT_SCENE := "res://scenes/level_select.tscn"
## A breadcrumb and a key for the crash report every this many waves.
const CRASH_LOG_WAVE_STEP := 5
## Perks recorded in the journal header and applied by a replay.
const PERK_KEYS: Array[StringName] = [
	&"sword", &"axe", &"towers", &"gold_start", &"wood_start", &"walls", &"swift"
]
const BUILD_FX := preload("res://scenes/fx/build_fx.tscn")
const UPGRADE_FX := preload("res://scenes/fx/upgrade_fx.tscn")
const GATE_HIT_FX := preload("res://scenes/fx/gate_hit_fx.tscn")
const WOOD_ICON: Texture2D = preload("res://ui/icons/wood.png")
const COIN_ICON: Texture2D = preload("res://ui/icons/coin.png")
const RING_TREE_COLOR := Color(0.62, 0.95, 0.42, 0.85)
const RING_ENEMY_COLOR := Color(1.0, 0.38, 0.32, 0.85)
const GOLD_COLOR := Color(1.0, 0.85, 0.35)
const WOOD_COLOR := Color(0.85, 0.65, 0.42)
## Physics layers that block walking: level colliders (1) and trees (3).
const WALK_OBSTACLE_MASK := 1 | 4
## Radius a built tower blocks on the walk grid.
const TOWER_BLOCK_RADIUS := 0.6
## Resuming an old checkpoint that has no saved wave clock: the next wave after this long.
const RESUME_FALLBACK_DELAY := 5.0

## Radius of the ring under the hero's target (tree, enemy, boss), metres.
@export var ring_radius_tree: float = 0.8
@export var ring_radius_enemy: float = 0.5
@export var ring_radius_boss: float = 1.1

var level: Dictionary = {}
## Co-op match (docs/MULTIPLAYER.md): empty in single player. Set before the node
## enters the tree (tests), else taken from CoopRun. `coop_transport` null = Online.rtdb.
var coop_config: Dictionary = {}
var coop_transport: CoopTransport = null
var coop_lobby: CoopLobby = null
var coop: CoopBattle = null
var walk_grid := WalkGrid.new()
var villagers := Villagers.new()
## Responsibilities split out of this scene (see the header).
var builder := LevelBuilder.new()
var cards := CardController.new()
var guide := GuideHints.new()
var battle_end := BattleEnd.new()

## Battle simulation (fixed-step clock, entity registry) and the single entry
## for player actions (journal of the battle).
var _sim: Sim = null
var _commands: GameCommands = null

var _focused_tree: WoodTree = null
## What the hero's next swing hits, computed once per frame.
var _focus: Node3D = null
var _paused: bool = false
var _endless: bool = false
## Record Run: the endless mode of a normal level (not the daily challenge, not co-op).
var _record: bool = false
## Campaign difficulty of this battle: 0 Normal, 1 Hard, 2 Nightmare (rows of "difficulty" in
## resources/balance.json). Journal header "difficulty"; co-op: the host's choice.
var _difficulty: int = 0
## Date of the daily challenge being played ("" = a normal battle).
var _daily_key: String = ""
var _tracker: AchievementTracker = null
var _coop_menu_open: bool = false
var _coop_hooks := CoopHooks.new()
var _lane_hint: LaneHint = null
var _fx: Fx = null
## The battle is being left (map / restart): the scene change is queued, ignore more taps.
var _leaving: bool = false
## "С севера!" for the wave that is starting.
var _wave_direction: String = ""
## Map inspection before the battle (docs/GAME_DESIGN.md): the battle clock stands, the knight
## waits, the camera is panned freely until "To battle!".
var _inspecting: bool = false

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
@onready var _upgrade_range_ring: MeshInstance3D = get_node_or_null("UpgradeRangeRing") as MeshInstance3D
@onready var _guide_arrow: MeshInstance3D = $GuideArrow
@onready var _ring_material: StandardMaterial3D = _target_ring.mesh.surface_get_material(0)
@onready var _wave_boom: AudioStreamPlayer = $Sfx/WaveBoom
@onready var _boss_roar: AudioStreamPlayer = $Sfx/BossRoar
@onready var _base_hit: AudioStreamPlayer = $Sfx/BaseHit
@onready var _victory_sound: AudioStreamPlayer = $Sfx/Victory
@onready var _defeat_sound: AudioStreamPlayer = $Sfx/Defeat


func _ready() -> void:
	Cosmetics.refresh()  # worn skins (colours only; not part of the simulation)
	_sim = Sim.new()
	_sim.name = "Sim"
	add_child(_sim)
	if coop_config.is_empty() and CoopRun.is_pending():
		coop_config = CoopRun.take()
		coop_lobby = CoopRun.lobby
	_sim.set_seed(randi())  # a replay overrides it (Sim.begin_replay)
	if _coop_on():
		_sim.set_seed(int(coop_config["seed"]))  # both players: the same battle
	_commands = GameCommands.new()
	_commands.name = "GameCommands"
	_commands.sim = _sim
	add_child(_commands)
	level = LevelCatalog.get_level(LevelCatalog.selected_id)
	builder.build(level, _level_root, _enemy_path, _wave_manager, _commands, _sim, _hero, _camera)
	_daily_key = LevelCatalog.daily_key if not _coop_on() else ""
	_endless = (LevelCatalog.endless or _daily_key != "") and not _coop_on()
	_record = _endless and _daily_key == ""
	_difficulty = _chosen_difficulty()
	_apply_perks(_current_perks())
	_wave_manager.plan = WavePlan.new(level["waves"], _endless, _record)
	_apply_difficulty()
	_wave_manager.sim = _sim
	_build_manager.sim = _sim
	_build_manager.villagers = villagers
	_build_manager.commands = _commands
	_build_manager.bounds = LevelBuilder.map_rect(level)
	_build_manager.lumberjack_camp = builder.lumberjack_camp
	_build_manager.mercenary_camp = builder.mercenary_camp
	if _daily_key != "":
		_sim.set_seed(DailyRun.seed_of(_daily_key))
		DailyRun.apply(_daily_key, _wave_manager.plan, _wave_manager, _build_manager)
	_hero.sim = _sim
	_hero.commands = _commands
	if builder != null and builder.castle != null:
		_hero.respawn_position = builder.castle.position + Vector3(0.0, 0.0, 2.5)
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
	_commands.set_hero_limits(_hero.global_position, LevelBuilder.map_rect(level))
	battle_end.setup(
		get_tree(),
		level,
		_endless,
		_commands,
		_wave_manager,
		_hud,
		_victory_sound,
		_defeat_sound,
		_daily_key
	)
	battle_end.difficulty = _difficulty
	battle_end.record_run = _record
	if _coop_on():
		coop = _coop_hooks.attach(
			self,
			coop_config,
			coop_transport if coop_transport != null else CoopRun.transport(),
			coop_lobby,
			_sim,
			_commands,
			_hero,
			_level_root,
			_hud,
			battle_end
		)

	_game_state.gold_changed.connect(_on_resources_changed.unbind(1))
	_game_state.wood_changed.connect(_on_resources_changed.unbind(1))
	_game_state.lives_changed.connect(_hud.set_lives)

	_wave_manager.enemy_killed.connect(_game_state.add_gold)
	_wave_manager.enemy_reached_base.connect(_on_enemy_reached_base)
	_wave_manager.wave_lanes.connect(_on_wave_lanes)
	_wave_manager.wave_started.connect(_on_wave_started)
	_wave_manager.wave_cleared.connect(_on_wave_cleared)
	battle_end.finished.connect(_on_battle_finished.unbind(2))

	_build_manager.tower_built.connect(_on_tower_built)
	_build_manager.tower_upgraded.connect(_on_tower_upgraded)
	_build_manager.tower_sold.connect(_on_tower_sold)
	_commands.applied.connect(_on_command_applied)
	_sim.pause_changed.connect(_on_pause_changed)
	_sim.speed_changed.connect(_on_speed_changed)
	_sim.replay_begun.connect(_on_replay_begun)

	guide.setup(_guide_arrow, _game_state, _build_manager, _commands, _sim, _hero)
	cards.setup(
		_hero,
		_hud,
		_build_manager,
		_commands,
		villagers,
		_game_state,
		_sim,
		_range_ring,
		guide.hint_text,
		_upgrade_range_ring
	)
	_hud.command_pressed.connect(cards.on_command_pressed)
	_hud.attack_pressed.connect(_hero.try_attack)
	_hud.spin_pressed.connect(_hero.try_spin)
	_hud.restart_pressed.connect(_on_restart_pressed)
	_hud.map_pressed.connect(_on_map_pressed)
	_hud.records_pressed.connect(_on_records_pressed)
	_hud.next_level_pressed.connect(_on_next_level_pressed)
	_hud.call_wave_pressed.connect(_on_call_wave_pressed)
	_hud.start_battle_pressed.connect(_begin_battle)
	_hero.knocked_out.connect(func() -> void:
		_hud.show_banner(tr("HERO_KNOCKED_OUT"), tr("HERO_REVIVING_SUBTITLE"), false)
		_hud.set_hero_knocked_out(true)
	)
	_hero.revived.connect(func() -> void:
		_hud.set_hero_knocked_out(false)
	)
	_hud.pause_pressed.connect(_toggle_pause)
	_hud.continue_pressed.connect(_toggle_pause)
	_hud.speed_pressed.connect(_toggle_speed)
	_hud.forge_pressed.connect(_on_forge_pressed)
	_hud.workbench_pressed.connect(_on_workbench_pressed)
	_hud.strategic_view_pressed.connect(_on_strategic_view_toggle)
	_hud.joystick_changed.connect(
		func(v: Vector2) -> void: _hero.joystick_vector = v
	)
	_hero.wood_gathered.connect(_on_wood_gathered)
	if coop != null:
		coop.ghost.wood_gathered.connect(_on_wood_gathered)
	villagers.name = "Villagers"
	villagers.game_state = _game_state
	villagers.seed_value = _sim.seed_value
	# Buying wood and lumberjacks: off only in the Record Run (one all-time table); the daily
	# challenge has them (one seed and the same rules for everyone that day).
	villagers.wood_economy = not _record
	villagers.wood_sold.connect(_on_wood_sold)
	villagers.wood_bought.connect(_on_wood_bought)
	villagers.lumberjack_chopped.connect(_on_lumberjack_chopped)
	_level_root.add_child(villagers)

	_hud.set_gold(_game_state.gold)
	_hud.set_wood(_game_state.wood)
	_hud.set_lives(_game_state.lives)
	if _record:
		_hud.record_mode = true
		_hud.record_best = LevelCatalog.endless_record(int(level["id"]))
	_hud.set_wave(0, 0 if _endless else _wave_manager.get_total_waves())
	_lane_hint = LaneHint.new()
	_lane_hint.camera = _camera
	_lane_hint.level = level
	_lane_hint.sim = _sim
	_lane_hint.strategic_view_requested.connect(_on_strategic_view_toggle)
	var hud_root: Control = _hud.get_node("Root")
	hud_root.add_child(_lane_hint)
	hud_root.move_child(_lane_hint, 0)  # under the banner, the hint and the buttons
	_hud.layout_changed.connect(_lane_hint.apply_settings)
	cards.refresh()
	_start_fx()
	_start_diagnostics()
	_start_tracker()
	if _endless and _daily_key == "":
		Online.start_run(int(level["id"]))  # server-side start time for the record check
	_inspecting = LevelCatalog.inspect_map and not LevelCatalog.tutorial and not _coop_on()
	LevelCatalog.inspect_map = false
	if not _resuming():
		# The wave clock is set now but runs with the battle clock (after the inspection).
		_wave_manager.schedule_next_wave(_wave_manager.plan.first_delay)
	if _inspecting:
		_enter_inspection()
	elif not _resuming():
		_show_wave_clock_banner()
	_build_walk_grid.call_deferred()
	_start_tutorial()


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	if coop != null:
		coop.leave()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			# Android back button: pause menu (and back out of it); on the end screen
			# it works like "To the map".
			if battle_end.ended:
				_on_map_pressed()
			else:
				_toggle_pause()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			battle_end.flush_progress()  # the process may be killed while in the background
			_save_checkpoint()
			# Phone call, home button: never let waves run unattended.
			if OS.has_feature("mobile") and not _paused and not battle_end.ended and not _coop_on():
				_toggle_pause()


func _process(delta: float) -> void:
	if not _inspecting:
		battle_end.add_time(delta)  # the battle time starts with "To battle!"
	cards.update()
	_focus = _hero.get_focus_target()
	_update_target_ring()
	_hud.set_spin_cooldown(_hero.spin_cooldown_left())
	guide.update_arrow(_focus, _build_manager.selected_slot == null and not cards.forge_open)
	_update_threat_detection()
	if _inspecting or LevelCatalog.tutorial or not _wave_manager.has_next_wave():
		_hud.set_call_wave_info(-1.0, 0)
	else:
		var time_left: float = _wave_manager.time_to_next_wave()
		_hud.set_call_wave_info(time_left, _call_wave_bonus(time_left), _can_call_wave())


func _update_threat_detection() -> void:
	if builder != null and builder.castle != null and _sim != null:
		var castle_pos := builder.castle.global_position
		var min_dist: float = 999.0
		for enemy in _sim.enemies:
			if enemy != null and is_instance_valid(enemy) and enemy.is_alive():
				var d: float = enemy.global_position.distance_to(castle_pos)
				if d < min_dist:
					min_dist = d
		if min_dist < 4.5:
			var danger: float = clampf(1.0 - (min_dist / 4.5), 0.0, 1.0)
			_hud.set_threat_danger(danger)
		else:
			_hud.set_threat_danger(0.0)


func _toggle_pause() -> void:
	if battle_end.ended:
		return
	if _coop_on():
		# The battle is shared: nobody can stop it. The menu only covers the screen.
		_coop_menu_open = not _coop_menu_open
		if _coop_menu_open:
			_hud.show_pause_menu()
		else:
			_hud.hide_pause_menu()
		return
	_commands.submit(GameCommand.set_pause(not _paused))


func _on_forge_pressed() -> void:
	if _paused:
		_toggle_pause()
	elif _coop_on() and _coop_menu_open:
		_coop_menu_open = false
	_hud.hide_pause_menu()
	cards.toggle_forge()


func _on_workbench_pressed() -> void:
	if _inspecting:
		return  # towers are placed once the battle has begun
	if _paused:
		_toggle_pause()
	elif _coop_on() and _coop_menu_open:
		_coop_menu_open = false
	_hud.hide_pause_menu()
	cards.toggle_workbench()


## The pause command was applied: stop / resume the whole tree.
func _on_pause_changed(on: bool) -> void:
	if battle_end.ended:
		return
	_paused = on
	get_tree().paused = _paused
	_hero.joystick_vector = Vector2.ZERO
	_camera.reset_touches()
	if _paused:
		_hero.cancel_order()
		_hud.show_pause_menu()
		_save_checkpoint()
	else:
		_hud.hide_pause_menu()
		if _inspecting:
			_hud.show_start_battle_button()


func _toggle_speed() -> void:
	if _coop_on():
		return
	_commands.submit(GameCommand.set_speed(1 if Engine.time_scale > 1.0 else 2))


## The speed command was applied: x2 only means twice as many frames of real
## time per second, so the simulation still sees the same steps.
func _on_speed_changed(speed: int) -> void:
	Engine.time_scale = float(speed)
	_hud.set_speed(speed)


## What a replay needs to know about the battle it reproduces.
func _journal_header() -> Dictionary:
	return BattleSetup.journal_header(
		level,
		_endless,
		_sim.seed_value,
		_current_perks(),
		_difficulty,
		_record,
		_daily_key,
		coop_config
	)


## Difficulty of this battle (see BattleSetup.chosen_difficulty).
func _chosen_difficulty() -> int:
	return BattleSetup.chosen_difficulty(coop_config, _endless, LevelCatalog.difficulty)


## Health, enemy count and kill gold of the difficulty (the lives are in _apply_perks).
func _apply_difficulty() -> void:
	var plan: WavePlan = _wave_manager.plan
	plan.set_difficulty(_difficulty)
	_wave_manager.reward_scale = plan.reward_scale(_difficulty)


## The player's permanent perks by name.
func _current_perks() -> Dictionary:
	return BattleSetup.current_perks(PERK_KEYS, _coop_on())


## Starting resources, lives and damage bonuses from `perks`. A replay applies
## the perks of its journal header (not the local save), so every client plays
## the same battle; call it before the battle clock starts.
func _apply_perks(perks: Dictionary) -> void:
	var start: Dictionary = BattleSetup.start_resources(level, _difficulty, perks)
	_game_state.configure(start)
	_game_state.reset()
	_hero.damage_multiplier = 1.0 + float(perks.get("sword", 0.0))
	_hero.wood_bonus = int(perks.get("axe", 0))
	_hero.speed_bonus = float(perks.get("swift", 0.0))
	_build_manager.damage_multiplier = 1.0 + float(perks.get("towers", 0.0))


func _on_replay_begun(header: Dictionary) -> void:
	_difficulty = clampi(int(header.get("difficulty", 0)), 0, Balance.difficulty_count() - 1)
	_apply_perks(header.get("perks", {}))
	_apply_difficulty()
	villagers.wood_economy = not bool(header.get("endless", false)) or header.has("daily")
	if int(header.get("sim_version", 0)) < 3:
		villagers.restock_enabled = false
		# Legacy sim_version < 3 journals were recorded with original 90 gold / 60 wood for level 1 and 2.
		if LevelCatalog.selected_id in [1, 2]:
			_game_state.gold = 90
			_game_state.wood = 60
			_game_state.gold_changed.emit(_game_state.gold)
			_game_state.wood_changed.emit(_game_state.wood)
	if header.has("daily"):
		DailyRun.apply(str(header["daily"]), _wave_manager.plan, _wave_manager, _build_manager)


## UI reaction to an executed command: effects of the forge, a fresh card.
func _on_command_applied(cmd: GameCommand, ok: bool) -> void:
	if not ok:
		return
	match cmd.type:
		GameCommand.Type.SWORD:
			_spawn_fx(UPGRADE_FX, _knight_of(cmd.player).global_position)
			cards.refresh()
		GameCommand.Type.REPAIR:
			_spawn_fx(BUILD_FX, builder.castle.global_position)
			cards.refresh()
		GameCommand.Type.UPGRADE_CASTLE:
			_spawn_fx(UPGRADE_FX, builder.castle.global_position)
			_popup(
				tr("POPUP_CASTLE") % _game_state.castle_level,
				builder.castle.global_position + Vector3.UP * 2.4,
				GOLD_COLOR
			)
			cards.refresh()
		GameCommand.Type.HIRE:
			var hired: Villager = villagers.get_villagers()[cmd.args[0]]
			_popup(tr("POPUP_LUMBERJACK"), hired.global_position + Vector3.UP * 1.7, WOOD_COLOR)
			hired.cheer()
			cards.refresh()


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
	var radius: float = ring_radius_tree
	if target is Enemy:
		radius = ring_radius_boss if (target as Enemy).is_boss() else ring_radius_enemy
	var pulse: float = 1.0 + 0.08 * sin(Time.get_ticks_msec() * 0.008)
	_target_ring.scale = Vector3(radius * pulse, 0.5, radius * pulse)
	_ring_material.albedo_color = RING_TREE_COLOR if is_tree else RING_ENEMY_COLOR


## Needs the level's bodies in the physics space: runs after a physics frame.
func _build_walk_grid() -> void:
	await get_tree().physics_frame
	if _leaving or not is_inside_tree():
		return  # the player left in the very first frame
	walk_grid.build(
		get_world_3d().direct_space_state, LevelBuilder.map_rect(level), WALK_OBSTACLE_MASK
	)
	_hero.walk_grid = walk_grid
	var slots := PackedVector3Array()
	for point: Array in level["slots"]:
		slots.append(LevelBuilder.ground(point))
	villagers.spawn(
		walk_grid,
		_wave_manager.get_paths(),
		LevelBuilder.ground(level["castle"]),
		LevelBuilder.ground(level["hero"]),
		slots
	)
	if _resuming():
		restore_from_checkpoint(BattleCheckpoint.load_checkpoint())
	LevelCatalog.resume_checkpoint = false
	if not _inspecting:
		_sim.start()  # the level is complete: the battle clock may run


## Tutorial mode: only on its level, never in co-op or the siege.
func _start_tutorial() -> void:
	if (
		_coop_on()
		or not LevelCatalog.tutorial
		or _endless
		or int(level["id"]) != Onboarding.TUTORIAL_LEVEL
	):
		return
	guide.start_tutorial(self, _wave_manager, _camera, _hud)
	guide.tutorial.leave_requested.connect(_on_map_pressed)
	cards.refresh()


## Achievement counters and the "Achievement!" toast (not in co-op).
func _start_tracker() -> void:
	if _coop_on() or LevelCatalog.tutorial:
		return
	_tracker = AchievementTracker.new()
	_tracker.name = "AchievementTracker"
	add_child(_tracker)
	_tracker.attach(_wave_manager, _build_manager, _game_state, _hero)
	_tracker.unlocked.connect(
		func(def: Dictionary) -> void:
			_hud.show_toast(
				tr("ACH_TOAST"),
				tr(str(def["key"])) + "  " + tr("GEMS_PLUS") % Economy.achievement_reward(def)
			)
	)
	var quests := QuestTracker.new()
	quests.name = "QuestTracker"
	add_child(quests)
	quests.attach(_wave_manager, _build_manager, _game_state)
	quests.quest_done.connect(
		func(def: Dictionary, gems: int) -> void:
			_hud.show_toast(tr("QUEST_TOAST"), Quests.text(def) + "  " + tr("GEMS_PLUS") % gems)
	)


## Game-feel layer (scripts/fx/fx.gd): listens to the signals above, changes nothing.
func _start_fx() -> void:
	var heroes: Array[Hero] = [_hero]
	if coop != null:
		heroes.append(coop.ghost)
	var fx := Fx.new()
	_fx = fx
	fx.name = "Fx"
	add_child(fx)
	fx.setup(_camera, _wave_manager, _build_manager, _game_state, heroes, builder.castle, _hud)
	cards.castle_position = builder.castle.global_position
	_game_state.castle_upgraded.connect(_on_castle_upgraded)


## Quality guard (lowers visual settings on a weak phone) and the hidden diagnostics overlay.
func _start_diagnostics() -> void:
	var guard := QualityGuard.new()
	guard.name = "QualityGuard"
	add_child(guard)
	guard.setup($Sun, get_viewport())
	var diag := DiagOverlay.new()
	add_child(diag)
	diag.setup(_sim, _wave_manager, int(level["id"]), guard)
	guard.level_lowered.connect(_on_quality_lowered)
	_report_battle_start()
	if CrashTrace.take_notice():
		# The last run died in a battle: the guard already starts lower, tell the player once.
		_hud.show_toast(tr("CRASH_NOTICE_TITLE"), tr("CRASH_NOTICE_BODY"))


## Breadcrumbs for the crash report (no personal data): what kind of battle this is.
func _report_battle_start() -> void:
	var mode: String = "campaign"
	if _coop_on():
		mode = "coop"
	elif _daily_key != "":
		mode = "daily"
	elif _endless:
		mode = "endless"
	var preset: String = ""
	if _daily_key != "":
		preset = str(Daily.preset_for(_daily_key).get("id", ""))
	CrashReporter.battle_started(int(level["id"]), mode, _difficulty, preset)


func _on_quality_lowered(notch: int) -> void:
	CrashReporter.set_key("quality_notch", notch)
	CrashReporter.log_line("quality notch lowered to %d" % notch)


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
	cards.refresh()


func _on_wood_gathered(amount: int, at: Vector3) -> void:
	_game_state.add_wood(amount)
	battle_end.count_wood(amount)
	_popup("+%d" % amount, at + Vector3.UP * 1.6, WOOD_COLOR, WOOD_ICON)


func _on_wood_sold(_wood: int, gold: int) -> void:
	var talking: Villager = cards.trade_with
	var at: Vector3 = talking.global_position if talking else _hero.global_position
	_popup("+%d" % gold, at + Vector3.UP * 1.4, GOLD_COLOR, COIN_ICON)
	if talking != null:
		talking.cheer()


func _on_wood_bought(wood: int, _gold: int) -> void:
	var talking: Villager = cards.trade_with
	var at: Vector3 = talking.global_position if talking else _hero.global_position
	_popup("+%d" % wood, at + Vector3.UP * 1.4, WOOD_COLOR, WOOD_ICON)
	if talking != null:
		talking.cheer()


## A hired lumberjack brings a piece of wood (a small sign over him).
func _on_lumberjack_chopped(index: int) -> void:
	_popup("+1", villagers.get_villagers()[index].global_position + Vector3.UP * 1.9, WOOD_COLOR)


func _on_tower_built(slot: TowerSlot, tower: Tower) -> void:
	battle_end.count_tower()
	walk_grid.block_slot(slot, TOWER_BLOCK_RADIUS)
	_spawn_fx(BUILD_FX, slot.global_position)
	# Rise out of the dust.
	tower.scale = Vector3(1.0, 0.2, 1.0)
	tower.create_tween().tween_property(tower, "scale", Vector3.ONE, 0.45).set_trans(
		Tween.TRANS_BACK
	)
	cards.refresh()


func _on_tower_sold(slot: TowerSlot, refund: Vector2i) -> void:
	walk_grid.unblock_slot(slot)
	_spawn_fx(BUILD_FX, slot.global_position)
	_popup("+%d" % refund.x, slot.global_position + Vector3.UP * 1.2, GOLD_COLOR, COIN_ICON)
	cards.refresh()


## The castle looks like its level: the body mesh with the baked decorations.
func _on_castle_upgraded(level: int) -> void:
	CastleModel.show_level(builder.castle, level)


func _on_tower_upgraded(slot: TowerSlot, _tower: Tower) -> void:
	_spawn_fx(UPGRADE_FX, slot.global_position)
	cards.refresh()


func _on_enemy_reached_base(damage: int) -> void:
	_base_hit.play()
	_game_state.take_leak(damage)
	if builder != null and builder.castle != null:
		_spawn_fx(GATE_HIT_FX, builder.castle.global_position + Vector3(0.0, 0.4, 0.0))
	if _hud != null:
		_hud.flash_leak()


## The paths of the starting wave: remember the "С севера!" text for the banner,
## mark the portals on screen (rings / edge arrows) and make them pulse.
func _on_wave_lanes(_wave: int, lanes: Array) -> void:
	_wave_direction = LevelCatalog.direction_text(level, lanes)
	_lane_hint.announce(builder.portals, lanes)


## The arrows of the wave go out when no wave has enemies left.
func _on_wave_cleared(_wave: int) -> void:
	if villagers != null and villagers.restock_enabled:
		villagers.restock(1)
	if not _wave_manager.is_wave_active():
		_lane_hint.finish()
	if not battle_end.ended:
		_save_checkpoint()


func _on_battle_finished() -> void:
	_lane_hint.stop()
	BattleCheckpoint.clear_checkpoint()


func _on_strategic_view_toggle() -> void:
	if _camera != null and _camera.has_method("toggle_strategic_view"):
		_camera.toggle_strategic_view()


func _on_wave_started(wave: int, total: int, boss: bool) -> void:
	if wave % CRASH_LOG_WAVE_STEP == 0:
		CrashReporter.set_key("wave", wave)
		CrashReporter.log_line("wave %d" % wave)
	_hud.set_wave(wave, 0 if _endless else total)
	_wave_boom.play()
	if boss:
		_boss_roar.play()
	# One banner per wave (a boss wave gets the king icon, not a second banner).
	var last: bool = not _endless and wave >= total
	var title: String = tr("WAVE_LAST") if last else tr("WAVE_N") % wave
	var next: String = ""
	if not last:
		next = tr("WAVE_NEXT_IN") % LevelCatalog.seconds_text(_wave_manager.plan.wave_duration)
	if _record and not _wave_manager.plan.surprise_key(wave).is_empty():
		next = tr(_wave_manager.plan.surprise_key(wave))  # "Swarm!", "Armoured!" ...
	var threat_tag: String = ""
	if boss:
		threat_tag = tr("WAVE_TAG_BOSS")
	elif _wave_manager != null and _wave_manager.plan != null:
		var has_flying := false
		var has_armor := false
		var has_healer := false
		var fast_count := 0
		var spawns: Array[Dictionary] = _wave_manager.plan.spawns(wave)
		for s in spawns:
			var d: EnemyData = s.get("data") as EnemyData
			if d != null:
				if d.flying:
					has_flying = true
				if d.armor > 0.0:
					has_armor = true
				if d.heal_fraction > 0.0:
					has_healer = true
				if d.speed >= 1.8:
					fast_count += 1
		if has_flying:
			threat_tag = tr("WAVE_TAG_AIR")
		elif has_armor:
			threat_tag = tr("WAVE_TAG_ARMORED")
		elif has_healer:
			threat_tag = tr("WAVE_TAG_HEALER")
		elif fast_count >= 5:
			threat_tag = tr("WAVE_TAG_SWARM")
	if threat_tag != "":
		next = threat_tag + ("\n" + next if next != "" else "")
	if _wave_direction != "":
		next = _wave_direction + ("\n" + next if next != "" else "")  # "From the north!"
	_hud.show_banner(title, next, boss)


## Early call of the next wave for a gold bonus. Only while the field is clear (no enemy of
## any wave alive or still to come), so the waves cannot be skipped through one after another.
func _on_call_wave_pressed() -> void:
	if not _can_call_wave():
		return
	var time_left: float = _wave_manager.time_to_next_wave()
	var bonus: int = _call_wave_bonus(time_left)
	_game_state.add_gold(bonus)
	_hud.popup("+%d" % bonus, _hud.get_call_wave_pos(), GOLD_COLOR, COIN_ICON)
	_wave_manager.start_next_wave()


func _can_call_wave() -> bool:
	return (
		not _inspecting
		and not LevelCatalog.tutorial
		and not _coop_on()
		and not battle_end.ended
		and _wave_manager.has_next_wave()
		and _wave_manager.time_to_next_wave() > 0.0
		and not _wave_manager.is_wave_active()
	)


func _call_wave_bonus(time_left: float) -> int:
	return maxi(5, int(time_left * 0.3) + 5)


## True when this battle continues a saved checkpoint (campaign / Record Run only).
func _resuming() -> bool:
	return (
		LevelCatalog.resume_checkpoint
		and _daily_key == ""
		and not _coop_on()
		and not LevelCatalog.tutorial
		and BattleCheckpoint.has_checkpoint(level["id"])
	)


## Map inspection: the camera is the player's, the knight and the battle clock wait.
func _enter_inspection() -> void:
	_hero.controls_locked = true
	_build_manager.set_process_unhandled_input(false)  # no taps on slots / ground
	_hud.set_inspection(true)
	_camera.set_free_look(true)
	var title: String = tr("HUD_INSPECT_MAP_TITLE")
	if _resuming():
		title = tr("CHECKPOINT_CONTINUE") % int(BattleCheckpoint.load_checkpoint().get("wave", 0))
	_hud.show_banner(title, tr("HUD_INSPECT_MAP_SUB"), false)
	_hud.show_start_battle_button()


func _end_inspection() -> void:
	_inspecting = false
	_hero.controls_locked = false
	_build_manager.set_process_unhandled_input(true)
	_hud.set_inspection(false)
	_hud.hide_start_battle_button()
	_camera.set_free_look(false)


## "To battle!": ends the inspection and starts the battle clock, once. The wave clock was set
## up before (the first wave after first_delay, or the clock of the resumed checkpoint) and
## stood still, so the time on the banner and the timer is the real one.
func _begin_battle() -> void:
	if not _inspecting or battle_end.ended:
		return
	_end_inspection()
	_show_wave_clock_banner()
	_sim.start()


## Banner with the real time to the next wave ("First wave in 30 s" / "Continue (wave 3)").
func _show_wave_clock_banner() -> void:
	var time_left: float = _wave_manager.time_to_next_wave()
	if time_left <= 0.0:
		return  # the wave starts at once: its own banner follows
	var wait: String = LevelCatalog.seconds_text(time_left)
	if _wave_manager.current_wave == 0:
		_hud.show_banner(tr("WAVE_FIRST_IN") % wait)
	else:
		_hud.show_banner(
			tr("CHECKPOINT_CONTINUE") % _wave_manager.current_wave, tr("WAVE_NEXT_IN") % wait
		)


## All level state lives in this scene's nodes, so reloading it restores the
## starting resources, lives and wave and frees old enemies and towers.
## SceneTree.paused is the only state that survives a reload: clear it first.
func _on_restart_pressed() -> void:
	if _coop_on():
		return  # one player cannot restart a shared battle
	BattleCheckpoint.clear_checkpoint()
	LevelCatalog.inspect_map = true
	_leave_to("")


## Record Run end screen: the map opens with the records table of this level.
func _on_records_pressed() -> void:
	LevelCatalog.open_records = true
	_on_map_pressed()


func _on_map_pressed() -> void:
	if _coop_on():
		coop.leave()
	_leave_to(LEVEL_SELECT_SCENE)


func _on_next_level_pressed() -> void:
	if _coop_on():
		coop.leave()
	BattleCheckpoint.clear_checkpoint()
	LevelCatalog.selected_id = mini(LevelCatalog.selected_id + 1, LevelCatalog.MAX_LEVEL)
	LevelCatalog.inspect_map = not _coop_on()
	_leave_to("")


## Leaves the battle for `scene_path` ("" = start this level again). The change is queued
## for the idle time of the frame: it must not run inside the tap's own input event, nor
## in the middle of a sim step or a _process of this scene (the scene is freed whole).
## Everything that touches the scene from outside (the effects layer, the sim clock,
## the models asked for in advance) is shut down first.
func _leave_to(scene_path: String) -> void:
	if _leaving:
		return
	_leaving = true
	CrashReporter.log_line("leaving the battle: %s" % scene_path.get_file())
	set_process(false)
	_sim.running = false
	if _fx != null and is_instance_valid(_fx):
		_fx.shutdown()
	_change_scene.call_deferred(scene_path)


func _change_scene(scene_path: String) -> void:
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	# SceneTree.paused is the only state that survives a scene change: clear it first.
	tree.paused = false
	Engine.time_scale = 1.0
	var error: Error = (
		tree.change_scene_to_file(scene_path) if scene_path != "" else tree.reload_current_scene()
	)
	if error != OK:
		push_error("Leaving the battle failed: %s" % error_string(error))
		_leaving = false
		set_process(true)
		_sim.running = true
		tree.paused = battle_end.ended or _paused


func _coop_on() -> bool:
	return not coop_config.is_empty()


## The knight of a player slot (the local one in single player).
func _knight_of(player: int) -> Hero:
	return _commands.heroes[player] if _commands.heroes.size() > player else _hero


func _save_checkpoint() -> void:
	if _coop_on() or LevelCatalog.tutorial or _daily_key != "":
		return
	if battle_end.ended or _leaving:
		return
	if _game_state.is_defeated or _game_state.lives <= 0:
		return
	var tower_list: Array = []
	for slot in _commands.slots:
		if slot != null and slot.tower != null and slot.tower.data != null:
			tower_list.append({
				"slot_id": slot.slot_id,
				"type": slot.tower.data.resource_path.get_file().get_basename(),
				"level": slot.tower.level,
				"priority": slot.tower.priority,
				"is_dynamic": slot.is_dynamic,
				"pos": [slot.global_position.x, slot.global_position.y, slot.global_position.z]
			})
	var v_data := {
		"lots_sold": villagers.lots_sold if villagers != null else 0,
		"lots_bought": villagers.lots_bought if villagers != null else 0,
		"hired": villagers._hired if villagers != null else []
	}
	var s_data := {
		"kills": battle_end.stats.get("kills", 0),
		"wood": battle_end.stats.get("wood", 0),
		"towers": battle_end.stats.get("towers", 0),
		"time": battle_end.stats.get("time", 0.0)
	}
	# A wave still running is not kept (its enemies are not saved): the checkpoint resumes
	# after the last cleared wave and plays the running one again at once.
	var cleared: int = _wave_manager.cleared_through()
	var next_wave_in: float = _wave_manager.time_to_next_wave()
	if cleared < _wave_manager.current_wave:
		next_wave_in = 0.0
	var data := {
		"level_id": int(level["id"]),
		"wave": cleared,
		"next_wave_in": next_wave_in,
		"hero_pos": [_hero.global_position.x, _hero.global_position.z],
		"gold": _game_state.gold,
		"wood": _game_state.wood,
		"castle_lives": _game_state.lives,
		"castle_level": _game_state.castle_level,
		"sword_level": _hero.sword_level,
		"difficulty": _difficulty,
		"endless": _endless,
		"towers": tower_list,
		"villagers": v_data,
		"stats": s_data
	}
	BattleCheckpoint.save_checkpoint(data)


func restore_from_checkpoint(data: Dictionary) -> void:
	if data.is_empty():
		return
	if data.has("difficulty"):
		_difficulty = int(data["difficulty"])
		_apply_difficulty()
	if data.has("gold"):
		_game_state.gold = int(data["gold"])
		_game_state.gold_changed.emit(_game_state.gold)
	if data.has("wood"):
		_game_state.wood = int(data["wood"])
		_game_state.wood_changed.emit(_game_state.wood)
	if data.has("castle_lives"):
		_game_state.lives = int(data["castle_lives"])
		_game_state.lives_changed.emit(_game_state.lives)
	if data.has("castle_level"):
		_game_state.castle_level = int(data["castle_level"])
		CastleModel.show_level(builder.castle, _game_state.castle_level)
	if data.has("sword_level"):
		var sword_lvl: int = int(data["sword_level"])
		_hero.sword_level = clampi(sword_lvl, 0, _hero.sword_damage_levels.size() - 1)
		_hero.attack_damage = _hero.sword_damage_levels[_hero.sword_level]

	# Restore towers
	for t in data.get("towers", []):
		var type_name: String = str(t.get("type", ""))
		var target_data: TowerData = null
		if _build_manager != null:
			for d in _build_manager.tower_types:
				if d != null and d.resource_path.get_file().get_basename() == type_name:
					target_data = d
					break
		if target_data == null:
			continue

		var slot: TowerSlot = null
		var is_dyn: bool = bool(t.get("is_dynamic", false))
		if is_dyn:
			if _build_manager != null:
				var pos_arr: Array = t.get("pos", [])
				if pos_arr.size() >= 3:
					var slot_pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
					slot = _build_manager.create_dynamic_slot(slot_pos)
		else:
			var slot_id: int = int(t.get("slot_id", -1))
			if slot_id >= 0 and _commands != null and slot_id < _commands.slots.size():
				slot = _commands.slots[slot_id]

		if slot == null or not slot.is_free():
			continue

		var tower: Tower = slot.place_tower(target_data.scene)
		if tower != null:
			if _sim != null:
				tower.attach(_sim)
			var tower_level: int = int(t.get("level", 0))
			tower.apply_level(target_data, tower_level)
			if _build_manager != null:
				tower.damage *= _build_manager.damage_multiplier
			if t.has("priority"):
				tower.priority = int(t["priority"])
			if walk_grid != null:
				walk_grid.block(slot.global_position, TOWER_BLOCK_RADIUS)
		elif is_dyn and _build_manager != null:
			_build_manager.remove_dynamic_slot(slot)

	# Restore villagers
	var v_data: Dictionary = data.get("villagers", {})
	if villagers != null and not v_data.is_empty():
		villagers.lots_sold = int(v_data.get("lots_sold", 0))
		villagers.lots_bought = int(v_data.get("lots_bought", 0))
		var hired_list: Array = v_data.get("hired", [])
		for i in mini(hired_list.size(), villagers.get_villagers().size()):
			if bool(hired_list[i]):
				villagers._hired[i] = true
				villagers._chop_progress[i] = 0
				villagers.get_villagers()[i].set_lumberjack(true)

	# Restore battle end stats
	var s_data: Dictionary = data.get("stats", {})
	if not s_data.is_empty():
		battle_end.stats["kills"] = int(s_data.get("kills", 0))
		battle_end.stats["wood"] = int(s_data.get("wood", 0))
		battle_end.stats["towers"] = int(s_data.get("towers", 0))
		battle_end.stats["time"] = float(s_data.get("time", 0.0))

	# Restore wave progress
	var wave: int = int(data.get("wave", 0))
	if not _endless and _wave_manager.plan != null and wave >= _wave_manager.plan.wave_count:
		BattleCheckpoint.clear_checkpoint()
		_wave_manager.schedule_next_wave(_wave_manager.plan.first_delay)
		return
	_wave_manager.current_wave = wave
	battle_end.waves_cleared = wave
	_hud.set_wave(wave, 0 if _endless else _wave_manager.get_total_waves())
	_restore_hero_position(data.get("hero_pos", []))
	if _wave_manager.has_next_wave():
		# The wave clock as it was (it stands until "To battle!" when the map is inspected).
		var delay: float = float(data.get("next_wave_in", RESUME_FALLBACK_DELAY))
		_wave_manager.schedule_next_wave(maxf(delay, 0.0))
		if not _inspecting:
			_show_wave_clock_banner()
	else:
		BattleCheckpoint.clear_checkpoint()
	cards.refresh()


## The knight stands where he stood when the checkpoint was saved (if that is on the map).
func _restore_hero_position(saved: Array) -> void:
	if saved.size() < 2:
		return
	var at := Vector3(float(saved[0]), 0.0, float(saved[1]))
	var map: Rect2 = LevelBuilder.map_rect(level)
	if not map.has_point(Vector2(at.x, at.z)):
		return
	_hero.global_position = at
	_commands.set_hero_limits(at, map)  # his next swing is checked from here
	_camera.snap()


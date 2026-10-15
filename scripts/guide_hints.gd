class_name GuideHints
extends RefCounted
## Hints for a new player: the text under the card ("chop a tree", "kill a slime",
## "build a tower"), the bouncing arrow over the next thing to do, and the hook that
## starts the onboarding Tutorial (which then replaces both).

enum GuideStep { NONE, CHOP, GOLD, BUILD }

const TUTORIAL_SCENE := preload("res://scenes/tutorial.tscn")
## Hints are shown until this many towers stand on the map.
const HINT_TOWERS := 2
## The guide arrow looks for a new target this often.
const GUIDE_REFRESH_FRAMES := 12

var tutorial: Tutorial = null

var _arrow: MeshInstance3D = null
var _target: Node3D = null
var _wait: int = 0
var _done: bool = false
var _game_state: GameState = null
var _build_manager: BuildManager = null
var _commands: GameCommands = null
var _sim: Sim = null
var _hero: Hero = null


func setup(
	arrow: MeshInstance3D,
	game_state: GameState,
	build_manager: BuildManager,
	commands: GameCommands,
	sim: Sim,
	hero: Hero
) -> void:
	_arrow = arrow
	_game_state = game_state
	_build_manager = build_manager
	_commands = commands
	_sim = sim
	_hero = hero


## Tutorial mode: the Tutorial node (its own overlay) replaces the built-in hints and
## guide arrow; it only observes the systems passed to it.
func start_tutorial(host: Node, wave_manager: WaveManager, camera: Camera3D, hud: Hud) -> void:
	tutorial = TUTORIAL_SCENE.instantiate()
	host.add_child(tutorial)
	tutorial.setup(_game_state, wave_manager, _build_manager, _hero, camera, hud)
	_done = true


## Step-by-step hint for new players while nothing is selected.
func hint_text() -> String:
	if tutorial != null:
		return ""
	match _step():
		GuideStep.CHOP:
			return TranslationServer.translate("GUIDE_CHOP")
		GuideStep.GOLD:
			return TranslationServer.translate("GUIDE_GOLD")
		GuideStep.BUILD:
			return TranslationServer.translate("GUIDE_BUILD")
	return ""


## Bouncing arrow over the next thing to do: a tree, a slime, a free slot.
## `allowed` is false while a slot or the forge is open; `focus` is what the hero hits.
func update_arrow(focus: Node3D, allowed: bool) -> void:
	var target: Node3D = null
	_wait -= 1
	if _done or _wait > 0:
		if _done:
			_arrow.hide()
		elif _target and is_instance_valid(_target) and _target.is_inside_tree():
			_place_arrow(_target, focus)
		else:
			_arrow.hide()
		return
	_wait = GUIDE_REFRESH_FRAMES
	var step: GuideStep = _step()
	if step == GuideStep.NONE:
		_done = true  # hints end for good once the first towers stand
	if allowed:
		match step:
			GuideStep.CHOP:
				target = _nearest_tree()
			GuideStep.GOLD:
				target = _nearest_enemy()
			GuideStep.BUILD:
				target = _nearest_free_slot()
	_target = target
	_place_arrow(target, focus)


## What a new player should do next (until HINT_TOWERS towers stand).
func _step() -> GuideStep:
	var towers: int = 0
	for slot in _commands.slots:
		if not slot.is_free():
			towers += 1
	if towers >= HINT_TOWERS:
		return GuideStep.NONE
	var cheapest: TowerData = _build_manager.tower_types[0]
	if _game_state.wood < cheapest.cost_wood:
		return GuideStep.CHOP
	if _game_state.gold < cheapest.cost_gold:
		return GuideStep.GOLD
	return GuideStep.BUILD


func _place_arrow(target: Node3D, focus: Node3D) -> void:
	_arrow.visible = target != null and target != focus
	if _arrow.visible:
		var bob: float = 0.18 * sin(Time.get_ticks_msec() * 0.006)
		var height: float = 2.6 if target is WoodTree else 1.0
		_arrow.global_position = target.global_position + Vector3(0.0, height + bob, 0.0)
		_arrow.rotation.y = Time.get_ticks_msec() * 0.002


func _nearest_tree() -> Node3D:
	var best: Node3D = null
	var best_distance: float = INF
	for tree in _sim.trees:
		var d: float = tree.global_position.distance_squared_to(_hero.global_position)
		if d < best_distance and tree.is_choppable():
			best_distance = d
			best = tree
	return best


func _nearest_enemy() -> Node3D:
	var best: Node3D = null
	var best_distance: float = INF
	for enemy in _sim.enemies:
		var d: float = enemy.global_position.distance_squared_to(_hero.global_position)
		if d < best_distance and enemy.is_alive():
			best_distance = d
			best = enemy
	return best


func _nearest_free_slot() -> Node3D:
	var best: Node3D = null
	var best_distance: float = INF
	for slot in _commands.slots:
		var d: float = slot.global_position.distance_squared_to(_hero.global_position)
		if d < best_distance and slot.is_free():
			best_distance = d
			best = slot
	return best

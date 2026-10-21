class_name CardController
extends RefCounted
## The hero's command card in play: what the HUD card shows (build / upgrade / forge /
## trade), what its buttons do (the hero walks to the slot, then the command is
## submitted), the trade card next to a villager and taps on the ground.
## Free Warcraft-style placement is delegated to TowerPlacementController.

## Walking this close to a slot selects it automatically (a little more than BUILD_REACH:
## stopping where the knight can build must pick that slot).
const AUTO_SELECT_REACH := 1.6
## An automatically picked slot is let go when the knight is this far from it.
const AUTO_RELEASE_REACH := 2.6
## The hero builds when this close to a slot centre (metres).
const BUILD_REACH := 1.25
## A tap this close to an enemy sends the hero to chase it.
const ENEMY_TAP_REACH := 1.8
## A tap this close to a tree sends the hero to chop it.
const TREE_TAP_REACH := 1.0
## A tap this close to a villager sends the hero to trade with it.
const VILLAGER_TAP_REACH := 1.0
## A tap this close to the castle opens the forge card (castle upgrades live there).
const CASTLE_TAP_REACH := 2.4
## The trade card stays open until the hero is this much further than the trade reach.
const TRADE_KEEP_SLACK := 0.6

const TowerPlacementController := preload("res://scripts/tower_placement_controller.gd")

var forge_open: bool = false
var workbench_open: bool = false

## Dedicated controller for Warcraft-style free placement
var placement := TowerPlacementController.new()

## Backwards-compatibility property accessors
var placement_mode: bool:
	get: return placement.placement_mode if placement != null else false
	set(v):
		if placement != null:
			placement.placement_mode = v

var placement_tower_index: int:
	get: return placement.placement_tower_index if placement != null else -1
	set(v):
		if placement != null:
			placement.placement_tower_index = v

var placement_position: Vector3:
	get: return placement.placement_position if placement != null else Vector3.ZERO
	set(v):
		if placement != null:
			placement.placement_position = v

var placement_valid: bool:
	get: return placement.placement_valid if placement != null else false
	set(v):
		if placement != null:
			placement.placement_valid = v

var _placement_validation_message: String:
	get: return placement.validation_message if placement != null else ""
	set(v):
		if placement != null:
			placement.validation_message = v

var _placement_ghost: Node3D:
	get: return placement.ghost if placement != null else null
	set(v):
		if placement != null:
			placement.ghost = v

var _active_dynamic_slot: TowerSlot:
	get: return placement.active_dynamic_slot if placement != null else null
	set(v):
		if placement != null:
			placement.active_dynamic_slot = v

var _placement_ring: MeshInstance3D:
	get: return placement.placement_ring if placement != null else null
	set(v):
		if placement != null:
			placement.placement_ring = v

## Where the castle stands (set by main once the level is built).
var castle_position: Vector3 = Vector3(INF, INF, INF):
	set(v):
		castle_position = v
		if placement != null:
			placement.castle_position = v

## Villager whose trade card is open.
var trade_with: Villager = null
## Command to run when the hero reaches the selected slot, or &"".
var pending_command: StringName = &""

var _pending_slot: TowerSlot = null
## The selected slot was picked by walking up to it (not by a tap): walking away drops it.
var _auto_selected: bool = false
var _auto_selecting: bool = false
var _selected_near: bool = false
## The villager the player closed the card for (until the hero walks away), and
## whether the hero walks to the villager after a tap.
var _trade_dismissed: Villager = null
var _trade_walking: bool = false
var _hint_text: Callable
var _hero: Hero = null
var _hud: Hud = null
var _build_manager: BuildManager = null
var _commands: GameCommands = null
var _villagers: Villagers = null
var _game_state: GameState = null
var _sim: Sim = null
var _range_ring: MeshInstance3D = null
var _upgrade_range_ring: MeshInstance3D = null


## `hint_text` returns the guide line shown while nothing is selected.
func setup(
	hero: Hero,
	hud: Hud,
	build_manager: BuildManager,
	commands: GameCommands,
	villagers: Villagers,
	game_state: GameState,
	sim: Sim,
	range_ring: MeshInstance3D,
	hint_text: Callable,
	upgrade_range_ring: MeshInstance3D = null
) -> void:
	_hero = hero
	_hud = hud
	_build_manager = build_manager
	_commands = commands
	_villagers = villagers
	_game_state = game_state
	_sim = sim
	_range_ring = range_ring
	_hint_text = hint_text
	_upgrade_range_ring = upgrade_range_ring
	if _upgrade_range_ring == null and _range_ring != null:
		_upgrade_range_ring = _create_default_upgrade_ring()

	placement.setup(hero, build_manager, commands, game_state, sim, range_ring)
	placement.castle_position = castle_position

	hero.order_cancelled.connect(on_hero_order_ended)
	hero.order_finished.connect(on_hero_order_ended)
	game_state.lives_changed.connect(refresh.unbind(1))
	build_manager.slot_selected.connect(on_slot_selected)
	build_manager.camp_selected.connect(on_camp_selected)
	build_manager.selection_cleared.connect(refresh)
	build_manager.ground_tapped.connect(on_ground_tapped)
	build_manager.placement_moved.connect(on_placement_moved)


## Per frame: select the slot the walking hero reaches, open / close the trade card.
func update() -> void:
	_auto_select_near_hero()
	_update_trade()


## Command card action: the hero walks to the selected slot and acts there.
func on_command_pressed(id: StringName) -> void:
	if id == &"hire_mercenary":
		var merc_camp: CampStructures.MercenaryCamp = null
		if _build_manager != null:
			merc_camp = _build_manager.selected_camp as CampStructures.MercenaryCamp
			if merc_camp == null:
				merc_camp = _build_manager.mercenary_camp
		if merc_camp != null:
			merc_camp.hire_mercenary(_game_state, _sim)
			refresh()
		return
	if id == &"talk_villager":
		var near: Villager = _near_villager()
		if near != null:
			_cleanup_unbuilt_dynamic_slot()
			_build_manager.clear_selection()
			_trade_dismissed = null
			_set_trade(near)
		return
	if _press_trade(id):
		_cleanup_unbuilt_dynamic_slot()
		refresh()
		return
	if id == &"cancel":
		if placement.placement_mode:
			cancel_placement()
			return
		if workbench_open:
			workbench_open = false
			refresh()
			return
		_trade_dismissed = trade_with
		_set_trade(null)
		forge_open = false
		_hero.cancel_order()
		_cleanup_unbuilt_dynamic_slot()
		_build_manager.clear_selection()
		refresh()
		return
	if id == &"confirm_build":
		_confirm_placement()
		return
	if workbench_open and id.begins_with("build_"):
		var tower_idx: int = _tower_index(id)
		start_placement_mode(tower_idx)
		return
	if _press_forge(id):
		_cleanup_unbuilt_dynamic_slot()
		return
	if id == &"sell" or id == &"priority":
		var chosen: TowerSlot = _build_manager.selected_slot
		if chosen != null and id == &"sell":
			_commands.submit(GameCommand.sell(chosen.slot_id))
		elif chosen != null and chosen.tower != null:
			var next: int = (chosen.tower.priority + 1) % TowerData.Priority.size()
			_commands.submit(GameCommand.set_priority(chosen.slot_id, next))
		refresh()
		return
	var slot: TowerSlot = _build_manager.selected_slot
	if slot == null or not _command_available(id, slot):
		return
	if _hero.is_near(slot.global_position, BUILD_REACH):
		_execute(id, slot)
	else:
		_hero.move_to(slot.global_position, BUILD_REACH, _execute.bind(id, slot))
		pending_command = id
		_pending_slot = slot
		refresh()


## The forge's buttons: sword, repair, castle upgrade. False if `id` is none of them.
func _press_forge(id: StringName) -> bool:
	if id == &"sword":
		_commands.submit(GameCommand.sword())
	elif id == &"repair":
		_commands.submit(GameCommand.repair())
	elif id == &"castle":
		_commands.submit(GameCommand.upgrade_castle())
		refresh()
	else:
		return false
	return true


## The villager's buttons: sell, buy, hire. False if `id` is none of them.
func _press_trade(id: StringName) -> bool:
	if id == &"trade_lot" or id == &"trade_all":
		var lots: int = 1 if id == &"trade_lot" else _villagers.lots_affordable()
		if lots > 0:
			_commands.submit(GameCommand.trade(lots))
	elif id == &"buy_lot" or id == &"buy_all":
		var wanted: int = 1 if id == &"buy_lot" else _villagers.buy_lots_affordable()
		if wanted > 0:
			_commands.submit(GameCommand.trade_buy(wanted))
	elif id == &"hire":
		var index: int = _villagers.index_of(trade_with) if trade_with != null else _villagers.first_unhired_index()
		if index >= 0:
			_commands.submit(GameCommand.hire(index))
	else:
		return false
	return true


func toggle_workbench() -> void:
	if placement.placement_mode:
		cancel_placement()
		return
	workbench_open = not workbench_open
	if workbench_open:
		forge_open = false
		_set_trade(null)
		_build_manager.clear_selection()
		_cleanup_unbuilt_dynamic_slot()
	refresh()


func toggle_forge() -> void:
	if placement.placement_mode:
		cancel_placement(false)
	workbench_open = false
	forge_open = not forge_open
	if forge_open:
		_build_manager.clear_selection()
	refresh()


func refresh() -> void:
	if placement.placement_mode:
		_range_ring.hide()
		if _upgrade_range_ring:
			_upgrade_range_ring.hide()
		_hide_placement_ring()
		var data: TowerData = _build_manager.tower_types[placement.placement_tower_index]
		var can_afford: bool = _game_state != null and _game_state.can_afford(Vector2i(data.cost_gold, data.cost_wood))
		_hud.show_hint("")
		_hud.update_card(CommandCards.placement_mode(data, placement.placement_valid, can_afford, placement.validation_message))
		return
	if workbench_open:
		_range_ring.hide()
		if _upgrade_range_ring:
			_upgrade_range_ring.hide()
		_hide_placement_ring()
		_hud.show_hint("")
		_hud.update_card(CommandCards.build_menu(_build_manager, _game_state))
		return
	var slot: TowerSlot = _build_manager.selected_slot
	if slot == null:
		_range_ring.hide()
		if _upgrade_range_ring:
			_upgrade_range_ring.hide()
		_hide_placement_ring()
		if pending_command == &"" and placement.active_dynamic_slot != null and placement.active_dynamic_slot.is_free():
			_cleanup_unbuilt_dynamic_slot()
	if forge_open:
		_range_ring.hide()
		if _upgrade_range_ring:
			_upgrade_range_ring.hide()
		_hide_placement_ring()
		_hud.show_hint("")
		_hud.update_card(CommandCards.forge(_hero, _game_state))
		return
	if trade_with != null:
		_range_ring.hide()
		if _upgrade_range_ring:
			_upgrade_range_ring.hide()
		_hide_placement_ring()
		_hud.show_hint("")
		_hud.update_card(CommandCards.trade(_villagers, _game_state, trade_with))
		return
	var camp: Node3D = _build_manager.selected_camp if _build_manager != null else null
	if camp != null:
		_range_ring.hide()
		if _upgrade_range_ring:
			_upgrade_range_ring.hide()
		_hide_placement_ring()
		_hud.show_hint("")
		if camp is CampStructures.LumberjackCamp:
			_hud.update_card(CommandCards.lumberjack_camp(_villagers, _game_state))
		elif camp is CampStructures.MercenaryCamp:
			_hud.update_card(CommandCards.mercenary_camp(camp as CampStructures.MercenaryCamp, _game_state))
		return
	if slot == null:
		_hud.show_hint(_hint_text.call())
		_hud.update_card({})
		return
	forge_open = false
	_hud.show_hint("")
	_show_range(slot)
	if slot.is_dynamic and slot.is_free():
		show_placement_preview(slot.global_position, true)
	else:
		_hide_placement_ring()
	_hud.update_card(
		CommandCards.for_slot(slot, _build_manager, pending_command != &"", _near_villager())
	)


func on_slot_selected(slot: TowerSlot) -> void:
	if not _auto_selecting:
		_auto_selected = false  # a tap
	_selected_near = slot != null and _flat_distance(slot) <= AUTO_RELEASE_REACH
	if placement.placement_mode:
		cancel_placement(false)
	workbench_open = false
	# Picking another slot drops a build/upgrade the hero was walking to do.
	if pending_command != &"" and slot != _pending_slot:
		_hero.cancel_order()
	if placement.active_dynamic_slot != null and placement.active_dynamic_slot != slot and placement.active_dynamic_slot.is_free():
		_cleanup_unbuilt_dynamic_slot()
	refresh()


func on_camp_selected(_camp: Node3D) -> void:
	forge_open = false
	workbench_open = false
	if placement.placement_mode:
		cancel_placement(false)
	_set_trade(null)
	_cleanup_unbuilt_dynamic_slot()
	if pending_command != &"" and _hero != null:
		_hero.cancel_order()
	refresh()


func on_hero_order_ended() -> void:
	pending_command = &""
	_trade_walking = false
	refresh()


func on_placement_moved(ground_pos: Vector3) -> void:
	if placement.placement_mode:
		update_placement_position(ground_pos)
		return
	placement.handle_placement_moved(ground_pos)


func on_ground_tapped(point: Vector3) -> void:
	if placement.placement_mode:
		update_placement_position(point)
		return
	# A tap on a villager: open the trade card, the hero walks up to it.
	var villager: Villager = _villagers.nearest(point, VILLAGER_TAP_REACH)
	if villager != null:
		_cleanup_unbuilt_dynamic_slot()
		_build_manager.clear_selection()
		_trade_dismissed = null
		_hero.move_to(villager.global_position, _villagers.trade_reach * 0.7)
		_trade_walking = true
		_set_trade(villager)
		return
	# A tap on the castle: its card (the forge with the castle upgrade), the knight stays.
	var to_castle: Vector3 = castle_position - point
	to_castle.y = 0.0
	if castle_position.is_finite() and to_castle.length() < CASTLE_TAP_REACH:
		_cleanup_unbuilt_dynamic_slot()
		if not forge_open:
			toggle_forge()
		return
	# A tap on or near camp structures:
	if _build_manager != null:
		var camp_lj: Node3D = _build_manager.lumberjack_camp
		if camp_lj != null:
			var to_lj: Vector3 = camp_lj.global_position - point
			to_lj.y = 0.0
			if to_lj.length() <= 2.4:
				_cleanup_unbuilt_dynamic_slot()
				_build_manager.select_camp(camp_lj)
				return
		var camp_mc: Node3D = _build_manager.mercenary_camp
		if camp_mc != null:
			var to_mc: Vector3 = camp_mc.global_position - point
			to_mc.y = 0.0
			if to_mc.length() <= 2.6:
				_cleanup_unbuilt_dynamic_slot()
				_build_manager.select_camp(camp_mc)
				return
	# A tap on an enemy: chase it and attack.
	var nearest_enemy: Enemy = null
	var best_enemy_dist: float = ENEMY_TAP_REACH
	if _sim != null:
		for enemy in _sim.enemies:
			if enemy.is_alive():
				var offset: Vector3 = enemy.global_position - point
				offset.y = 0.0
				if offset.length() < best_enemy_dist:
					best_enemy_dist = offset.length()
					nearest_enemy = enemy
	if nearest_enemy != null:
		_cleanup_unbuilt_dynamic_slot()
		_hero.chase_enemy(nearest_enemy)
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
		_cleanup_unbuilt_dynamic_slot()
		_hero.move_to(best.global_position, _hero.chop_range * 0.8)
		return

	# Empty ground tap: Warcraft-style free placement!
	var handled: bool = placement.handle_ground_tap(point)
	if not handled and GameSettings.is_tap_to_move():
		_hero.move_to(point, 0.15)


func _execute(id: StringName, slot: TowerSlot) -> void:
	if id == &"upgrade":
		_commands.submit(GameCommand.upgrade(slot.slot_id))
	else:
		_commands.submit(GameCommand.build(slot.slot_id, _tower_index(id)))
		if slot == placement.active_dynamic_slot:
			placement.active_dynamic_slot = null
			_hide_placement_ring()
	refresh()


func _tower_index(id: StringName) -> int:
	return int(String(id).trim_prefix("build_"))


func _command_available(id: StringName, slot: TowerSlot) -> bool:
	if id == &"upgrade":
		return _build_manager.can_upgrade(slot)
	return _build_manager.can_build(slot, _build_manager.tower_types[_tower_index(id)])


func _auto_select_near_hero() -> void:
	if pending_command != &"" or forge_open or workbench_open or placement.placement_mode or trade_with != null or (_build_manager != null and _build_manager.selected_camp != null):
		return
	var moving: bool = _hero.velocity.length() >= 0.1
	var current: TowerSlot = _build_manager.selected_slot
	var nearest: TowerSlot = null
	var best: float = AUTO_SELECT_REACH
	for slot in _commands.slots:
		var distance: float = _flat_distance(slot)
		if distance < best:
			best = distance
			nearest = slot
	if current != null:
		if _flat_distance(current) <= AUTO_RELEASE_REACH:
			_selected_near = true
		elif (_auto_selected or _selected_near) and _flat_distance(current) > AUTO_RELEASE_REACH:
			_auto_selected = false
			_selected_near = false
			_build_manager.clear_selection()
			return
	if current != null and _auto_selected and not moving:
		# Standing still: only a clearly nearer slot replaces it (no flicker between two).
		if nearest != null and nearest != current and best + 0.15 < _flat_distance(current):
			_auto_select(nearest)
		return
	if not moving:
		return
	if nearest != null and nearest != current:
		_auto_select(nearest)
	elif nearest == null and current != null:
		if (_auto_selected or _selected_near) and _flat_distance(current) > AUTO_RELEASE_REACH:
			_auto_selected = false
			_selected_near = false
			_build_manager.clear_selection()


func _auto_select(slot: TowerSlot) -> void:
	_auto_selecting = true
	_build_manager.select_slot(slot)
	_auto_selecting = false
	_auto_selected = true
	_selected_near = true


func _flat_distance(node: Node3D) -> float:
	var offset: Vector3 = node.global_position - _hero.global_position
	offset.y = 0.0
	return offset.length()


## Attack radius of the tower on `slot` (for a free slot: what a new tower reaches).
func _show_range(slot: TowerSlot) -> void:
	_range_ring.visible = slot != null
	if _range_ring.visible:
		# A free slot previews the reach of the first tower type at level 1.
		var r: float = (
			slot.tower.range_m if slot.tower else _build_manager.tower_types[0].range_levels[0]
		)
		_range_ring.global_position = Vector3(slot.global_position.x, 0.07, slot.global_position.z)
		_range_ring.scale = Vector3(r, 1.0, r)

	if _upgrade_range_ring:
		var show_upgrade: bool = false
		if slot != null and slot.tower != null and slot.tower.data != null:
			var t: Tower = slot.tower
			var next_lvl: int = t.level + 1
			if next_lvl <= t.data.max_level() and next_lvl < t.data.range_levels.size():
				var up_r: float = t.data.range_levels[next_lvl]
				_upgrade_range_ring.global_position = Vector3(
					slot.global_position.x, 0.071, slot.global_position.z
				)
				_upgrade_range_ring.scale = Vector3(up_r, 1.0, up_r)
				show_upgrade = true
		_upgrade_range_ring.visible = show_upgrade


func _create_default_upgrade_ring() -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	ring.name = "UpgradeRangeRing"
	ring.mesh = _range_ring.mesh
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.2, 0.85, 0.9, 0.55)
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	if _range_ring.get_parent():
		_range_ring.get_parent().add_child(ring)
	return ring


## Opens the trade card when the hero comes up to a villager and closes it
## when he walks away (unless he is still on his way after a tap).
func _update_trade() -> void:
	var near: Villager = _villagers.nearest(_hero.global_position, _villagers.trade_reach)
	if near != _trade_dismissed:
		_trade_dismissed = null
	if (
		trade_with != null
		and (
			_trade_walking
			or _hero.is_near(trade_with.global_position, _villagers.trade_reach + TRADE_KEEP_SLACK)
		)
	):
		return
	_set_trade(null if near == _trade_dismissed else near)


func _set_trade(villager: Villager) -> void:
	if villager == trade_with:
		return
	if trade_with != null:
		trade_with.talk_to(null)
	trade_with = villager
	if villager != null:
		villager.talk_to(_hero)
	refresh()


func _near_villager() -> Villager:
	return (
		_villagers.nearest(_hero.global_position, _villagers.trade_reach)
		if _villagers != null and _hero != null
		else null
	)


func _cleanup_unbuilt_dynamic_slot() -> void:
	placement.cleanup_unbuilt_dynamic_slot()


func show_placement_preview(pos: Vector3, valid: bool) -> void:
	placement.show_placement_preview(pos, valid)


func _hide_placement_ring() -> void:
	placement.hide_placement_ring()


func start_placement_mode(tower_index: int) -> void:
	workbench_open = false
	forge_open = false
	_set_trade(null)
	placement.start_placement_mode(tower_index)
	refresh()


func update_placement_position(pos: Vector3) -> void:
	placement.update_placement_position(pos)
	refresh()


func _confirm_placement() -> void:
	var result: Dictionary = placement.confirm_placement()
	if not result.get("success", false):
		return
	var slot: TowerSlot = result["slot"] as TowerSlot
	var cmd_id: StringName = result["cmd_id"] as StringName
	if slot == null:
		return
	_build_manager.select_slot(slot)
	if _hero.is_near(slot.global_position, BUILD_REACH):
		_execute(cmd_id, slot)
	else:
		_hero.move_to(slot.global_position, BUILD_REACH, _execute.bind(cmd_id, slot))
		pending_command = cmd_id
		_pending_slot = slot
	refresh()


func cancel_placement(do_refresh: bool = true) -> void:
	placement.cancel_placement()
	if do_refresh:
		refresh()

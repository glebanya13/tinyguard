class_name CardController
extends RefCounted
## The hero's command card in play: what the HUD card shows (build / upgrade / forge /
## trade), what its buttons do (the hero walks to the slot, then the command is
## submitted), the trade card next to a villager and taps on the ground.

## Walking this close to a slot selects it automatically.
const AUTO_SELECT_REACH := 1.1
## The hero builds when this close to a slot centre (metres).
const BUILD_REACH := 1.25
## A tap this close to a tree sends the hero to chop it.
const TREE_TAP_REACH := 1.0
## A tap this close to a villager sends the hero to trade with it.
const VILLAGER_TAP_REACH := 1.0
## The trade card stays open until the hero is this much further than the trade reach.
const TRADE_KEEP_SLACK := 0.6

var forge_open: bool = false
## Villager whose trade card is open.
var trade_with: Villager = null
## Command to run when the hero reaches the selected slot, or &"".
var pending_command: StringName = &""

var _pending_slot: TowerSlot = null
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
	hint_text: Callable
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
	hero.order_cancelled.connect(on_hero_order_ended)
	hero.order_finished.connect(on_hero_order_ended)
	game_state.lives_changed.connect(refresh.unbind(1))
	build_manager.slot_selected.connect(on_slot_selected)
	build_manager.selection_cleared.connect(refresh)
	build_manager.ground_tapped.connect(on_ground_tapped)


## Per frame: select the slot the walking hero reaches, open / close the trade card.
func update() -> void:
	_auto_select_near_hero()
	_update_trade()


## Command card action: the hero walks to the selected slot and acts there.
func on_command_pressed(id: StringName) -> void:
	if id == &"trade_lot" or id == &"trade_all":
		var lots: int = 1 if id == &"trade_lot" else _villagers.lots_affordable()
		if lots > 0:
			_commands.submit(GameCommand.trade(lots))
		refresh()
		return
	if id == &"cancel":
		_trade_dismissed = trade_with
		_set_trade(null)
		forge_open = false
		_hero.cancel_order()
		_build_manager.clear_selection()
		refresh()
		return
	if id == &"sword":
		_commands.submit(GameCommand.sword())
		return
	if id == &"repair":
		_commands.submit(GameCommand.repair())
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


func toggle_forge() -> void:
	forge_open = not forge_open
	if forge_open:
		_build_manager.clear_selection()
	refresh()


func refresh() -> void:
	var slot: TowerSlot = _build_manager.selected_slot
	if slot == null:
		_range_ring.hide()
	if slot == null and forge_open:
		_hud.show_hint("")
		_hud.update_card(CommandCards.forge(_hero, _game_state))
		return
	if slot == null and trade_with != null:
		_hud.show_hint("")
		_hud.update_card(CommandCards.trade(_villagers, _game_state))
		return
	if slot == null:
		_hud.show_hint(_hint_text.call())
		_hud.update_card({})
		return
	forge_open = false
	_hud.show_hint("")
	_show_range(slot)
	_hud.update_card(CommandCards.for_slot(slot, _build_manager, pending_command != &""))


func on_slot_selected(slot: TowerSlot) -> void:
	# Picking another slot drops a build/upgrade the hero was walking to do.
	if pending_command != &"" and slot != _pending_slot:
		_hero.cancel_order()
	refresh()


func on_hero_order_ended() -> void:
	pending_command = &""
	_trade_walking = false
	refresh()


func on_ground_tapped(point: Vector3) -> void:
	# A tap on a villager: open the trade card, the hero walks up to it.
	var villager: Villager = _villagers.nearest(point, VILLAGER_TAP_REACH)
	if villager != null:
		_trade_dismissed = null
		_hero.move_to(villager.global_position, _villagers.trade_reach * 0.7)
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


func _execute(id: StringName, slot: TowerSlot) -> void:
	if id == &"upgrade":
		_commands.submit(GameCommand.upgrade(slot.slot_id))
	else:
		_commands.submit(GameCommand.build(slot.slot_id, _tower_index(id)))
	refresh()


func _tower_index(id: StringName) -> int:
	return int(String(id).trim_prefix("build_"))


func _command_available(id: StringName, slot: TowerSlot) -> bool:
	if id == &"upgrade":
		return _build_manager.can_upgrade(slot)
	return _build_manager.can_build(slot, _build_manager.tower_types[_tower_index(id)])


func _auto_select_near_hero() -> void:
	# Walking (keys, joystick or a tap on the ground) selects the slot the hero
	# reaches; a pending build/upgrade command keeps its own target.
	if _hero.velocity.length() < 0.1 or pending_command != &"":
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

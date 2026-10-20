class_name Outpost
extends Node3D
## Chupacabra outpost at the start of an enemy route.
## Surrounded by thicket grove trees; chopping them down weakens the enemy
## flow from this outpost (lane weight multiplier in WavePlan) down to a floor of 40%.
## Trees slowly regrow over time via sim.schedule_in.

signal flow_changed(lane: int, flow_pct: int)
signal tree_chopped(tree: WoodTree, felled_now: int, flow_pct: int)
signal tree_regrown(tree: WoodTree, felled_now: int, flow_pct: int)

const DEFAULT_TREES := 24
const SHIELD_PCT := 60
const FLOOR_PCT := 40
const THICKET_REGROW_TIME := 150.0

@export var lane: int = 0
@export var total_trees: int = 24

var sim: Sim = null
var thicket_trees: Array[WoodTree] = []


func add_thicket_tree(tree: WoodTree) -> void:
	tree.is_thicket = true
	tree.outpost = self
	tree.outpost_id = lane
	tree.wood_per_hit = 0
	tree.regrow_time = THICKET_REGROW_TIME
	thicket_trees.append(tree)
	total_trees = thicket_trees.size()


func felled_count() -> int:
	var count: int = 0
	for tree in thicket_trees:
		if not tree.is_choppable():
			count += 1
	return count


func tree_count() -> int:
	return thicket_trees.size()


## Enemy flow from this outpost in whole percent (40..100).
## Formula from docs/CONTENT_V06.md §3: max(40, 100 - (60 * felled) / N)
func flow_pct() -> int:
	if total_trees <= 0:
		return 100
	var felled: int = felled_count()
	var reduced: int = 100 - (SHIELD_PCT * felled) / total_trees
	return maxi(FLOOR_PCT, reduced)


## Lane weight multiplier for WavePlan (0.4 .. 1.0).
func multiplier() -> float:
	return float(flow_pct()) / 100.0


func on_tree_felled(tree: WoodTree) -> void:
	var f: int = felled_count()
	var pct: int = flow_pct()
	tree_chopped.emit(tree, f, pct)
	flow_changed.emit(lane, pct)


func on_tree_regrown(tree: WoodTree) -> void:
	var f: int = felled_count()
	var pct: int = flow_pct()
	tree_regrown.emit(tree, f, pct)
	flow_changed.emit(lane, pct)


func state_ints() -> Array[int]:
	return [lane, felled_count(), flow_pct()]

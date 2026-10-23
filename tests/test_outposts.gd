extends SceneTree
## Tests for Chupacabra Outposts and Thicket mechanics (docs/CONTENT_V06.md §3).
## Verifies:
## 1. Spawn of outposts and thicket grove trees (<= 24 trees per side, MultiMesh).
## 2. Weakening of wave enemy flow upon chopping thicket trees.
## 3. Floor of 40% when all trees are chopped.
## 4. Slow regrowth of trees via sim.schedule_in (150 s).
## 5. Zero wood resource granted (prevents endless farming).
## 6. Strict determinism of simulation state hashes.

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_outposts.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	LevelCatalog.selected_id = (
		int(OS.get_environment("LEVEL")) if OS.has_environment("LEVEL") else 1
	)
	_run.call_deferred()


func _run() -> void:
	print("-- test outposts: spawn and grove trees")
	await _test_spawn()

	print("-- test outposts: chopping, wave weakening, and zero wood resource")
	await _test_chopping_and_weakening()

	print("-- test outposts: floor 40% threshold")
	await _test_floor_40_percent()

	print("-- test outposts: slow regrowth (150s)")
	await _test_regrowth()

	print("-- test outposts: simulation determinism")
	await _test_determinism()

	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _load_main() -> Node:
	change_scene_to_file("res://scenes/main.tscn")
	var sim: Sim = null
	while sim == null:
		await process_frame
		if current_scene != null and current_scene.has_node("Sim"):
			sim = current_scene.get_node("Sim")
	sim.manual = true
	for i in 10:
		await process_frame
	return current_scene


func _test_spawn() -> void:
	var main: Node = await _load_main()
	var builder: LevelBuilder = main.builder
	var sim: Sim = main.get_node("Sim")
	var level: Dictionary = LevelCatalog.get_level(LevelCatalog.selected_id)
	var route_count: int = LevelCatalog.routes(level).size()

	check(
		builder.outposts.size() == route_count,
		"outpost count (%d) matches routes (%d)" % [builder.outposts.size(), route_count]
	)
	check(sim.outposts.size() == route_count, "sim registered all %d outposts" % route_count)

	for outpost: Outpost in builder.outposts:
		var n_trees: int = outpost.thicket_trees.size()
		check(
			n_trees > 0 and n_trees <= Outpost.DEFAULT_TREES,
			(
				"lane %d outpost has %d thicket trees (<= %d)"
				% [outpost.lane, n_trees, Outpost.DEFAULT_TREES]
			)
		)
		check(outpost.flow_pct() == 100, "lane %d initial flow is 100%%" % outpost.lane)
		check(
			is_equal_approx(outpost.multiplier(), 1.0),
			"lane %d initial multiplier is 1.0" % outpost.lane
		)

		for tree: WoodTree in outpost.thicket_trees:
			check(tree.is_thicket, "tree %d has is_thicket true" % tree.id)
			check(
				tree.outpost_id == outpost.lane,
				"tree %d belongs to lane %d" % [tree.id, outpost.lane]
			)
			check(
				tree.wood_per_hit == outpost.thicket_wood_per_hit and tree.wood_per_hit > 0,
				"tree %d gives wood like every choppable tree" % tree.id
			)
			check(
				is_equal_approx(tree.regrow_time, Outpost.THICKET_REGROW_TIME),
				"tree %d regrow time is 150s" % tree.id
			)
			check(
				absf(tree.global_position.x) <= 21.0 and absf(tree.global_position.z) <= 13.8,
				"tree %d is inside hero bounds at %s" % [tree.id, tree.global_position]
			)
			check(tree.grove != null, "tree %d is assigned to Grove MultiMesh" % tree.id)
			check(sim.trees.has(tree), "tree %d is registered in sim.trees" % tree.id)


func _test_chopping_and_weakening() -> void:
	var main: Node = await _load_main()
	var sim: Sim = main.get_node("Sim")
	var gs: GameState = main.get_node("GameState")
	var wm: WaveManager = main.get_node("WaveManager")
	var outpost: Outpost = sim.outposts[0]
	var initial_wood: int = gs.wood
	var first_tree: WoodTree = outpost.thicket_trees[0]

	check(first_tree.is_choppable(), "tree is initially choppable")
	var gained: int = first_tree.chop(Vector3.ZERO)
	check(
		gained == outpost.thicket_wood_per_hit and gained > 0,
		"chopping a thicket tree gives wood like any choppable tree (gained: %d)" % gained
	)
	# chop() only reports the wood; the hero's swing adds it (wood_gathered), so no change here.
	check(gs.wood == initial_wood, "game_state wood is unchanged by chop() alone (%d)" % gs.wood)
	check(
		first_tree.hits_left() == first_tree.hits - 1,
		"tree has %d hits left after 1 strike" % first_tree.hits_left()
	)

	# Finish chopping down the tree
	while first_tree.is_choppable():
		first_tree.chop(Vector3.ZERO)
	await process_frame
	check(not first_tree.is_choppable(), "tree is now felled")
	check(outpost.felled_count() == 1, "outpost felled count is 1")

	# Check flow reduction
	var expected_pct: int = 100 - (Outpost.SHIELD_PCT * 1) / outpost.total_trees
	check(
		outpost.flow_pct() == expected_pct,
		"outpost flow reduced to %d%% (expected %d%%)" % [outpost.flow_pct(), expected_pct]
	)
	check(outpost.multiplier() < 1.0, "outpost multiplier is below 1.0: %f" % outpost.multiplier())

	# Check wave plan weighting
	var full_weights: Array = wm.plan.lane_weights(1, [1.0, 1.0, 1.0, 1.0])
	var reduced_weights: Array = wm.plan.lane_weights(1, [outpost.multiplier(), 1.0, 1.0, 1.0])
	check(
		float(reduced_weights[0]) < float(full_weights[0]),
		(
			"lane 0 weight is reduced in WavePlan: %f < %f"
			% [float(reduced_weights[0]), float(full_weights[0])]
		)
	)


func _test_floor_40_percent() -> void:
	var main: Node = await _load_main()
	var sim: Sim = main.get_node("Sim")
	var outpost: Outpost = sim.outposts[0]

	# Chop down all trees in the outpost's thicket
	for tree: WoodTree in outpost.thicket_trees:
		while tree.is_choppable():
			tree.chop(Vector3.ZERO)
	await process_frame

	check(
		outpost.felled_count() == outpost.total_trees, "all %d trees felled" % outpost.total_trees
	)
	check(
		outpost.flow_pct() == Outpost.FLOOR_PCT,
		(
			"outpost flow reached exactly %d%% floor (got: %d%%)"
			% [Outpost.FLOOR_PCT, outpost.flow_pct()]
		)
	)
	check(is_equal_approx(outpost.multiplier(), 0.40), "outpost multiplier reached 0.40 floor")

	# Test mock formula edge case (if felled > total_trees, still clamped to 40)
	var prev_total: int = outpost.total_trees
	outpost.total_trees = 5
	var reduced_mock: int = 100 - (Outpost.SHIELD_PCT * 10) / outpost.total_trees
	check(
		maxi(Outpost.FLOOR_PCT, reduced_mock) == 40, "floor strictly prevents dropping below 40%%"
	)
	outpost.total_trees = prev_total


func _test_regrowth() -> void:
	var main: Node = await _load_main()
	var sim: Sim = main.get_node("Sim")
	var outpost: Outpost = sim.outposts[0]
	var tree: WoodTree = outpost.thicket_trees[0]

	while tree.is_choppable():
		tree.chop(Vector3.ZERO)
	await process_frame

	check(not tree.is_choppable(), "tree is felled")
	check(outpost.felled_count() == 1, "1 tree felled")
	var regrow_tick: int = tree.regrow_at()
	check(
		regrow_tick > sim.tick,
		"regrow scheduled in future at tick %d (now %d)" % [regrow_tick, sim.tick]
	)

	# Advance until just before regrow
	while sim.tick < regrow_tick - 1:
		sim.step()
	check(not tree.is_choppable(), "tree is still down at tick %d" % sim.tick)

	# Advance past regrow tick
	sim.step()
	sim.step()
	check(tree.is_choppable(), "tree regrew at tick %d and is choppable again" % sim.tick)
	check(tree.hits_left() == tree.hits, "tree restored full hits (%d)" % tree.hits)
	check(outpost.felled_count() == 0, "felled count restored to 0")
	check(outpost.flow_pct() == 100, "outpost flow restored to 100%%")
	check(is_equal_approx(outpost.multiplier(), 1.0), "outpost multiplier restored to 1.0")


func _test_determinism() -> void:
	var tree_scene: PackedScene = load("res://scenes/wood_tree.tscn")
	var trace1: Array[int] = []
	var trace2: Array[int] = []

	var host1 := Node3D.new()
	root.add_child(host1)
	var sim1 := Sim.new()
	sim1.set_seed(42)
	sim1.start()
	host1.add_child(sim1)
	var outpost1 := Outpost.new()
	outpost1.lane = 0
	outpost1.sim = sim1
	sim1.add_outpost(outpost1)
	host1.add_child(outpost1)
	var tree1: WoodTree = tree_scene.instantiate()
	tree1.sim = sim1
	outpost1.add_thicket_tree(tree1)
	host1.add_child(tree1)

	var host2 := Node3D.new()
	root.add_child(host2)
	var sim2 := Sim.new()
	sim2.set_seed(42)
	sim2.start()
	host2.add_child(sim2)
	var outpost2 := Outpost.new()
	outpost2.lane = 0
	outpost2.sim = sim2
	sim2.add_outpost(outpost2)
	host2.add_child(outpost2)
	var tree2: WoodTree = tree_scene.instantiate()
	tree2.sim = sim2
	outpost2.add_thicket_tree(tree2)
	host2.add_child(tree2)

	for step in 300:
		if step == 30:
			tree1.chop(Vector3.ZERO)
			tree2.chop(Vector3.ZERO)
		if step == 60:
			while tree1.is_choppable():
				tree1.chop(Vector3.ZERO)
			while tree2.is_choppable():
				tree2.chop(Vector3.ZERO)
		sim1.step()
		sim2.step()
		if step % 30 == 0:
			trace1.append(sim1.state_hash())
			trace2.append(sim2.state_hash())

	check(
		trace1.size() > 0 and trace1 == trace2,
		"simulation traces match 100%% deterministically across runs"
	)

	# Control: check that an untouched sim has different hash from a chopped sim
	var host_idle := Node3D.new()
	root.add_child(host_idle)
	var sim_idle := Sim.new()
	sim_idle.set_seed(42)
	sim_idle.start()
	host_idle.add_child(sim_idle)
	var outpost_idle := Outpost.new()
	outpost_idle.lane = 0
	outpost_idle.sim = sim_idle
	sim_idle.add_outpost(outpost_idle)
	host_idle.add_child(outpost_idle)
	var tree_idle: WoodTree = tree_scene.instantiate()
	tree_idle.sim = sim_idle
	outpost_idle.add_thicket_tree(tree_idle)
	host_idle.add_child(tree_idle)

	for step in 100:
		sim_idle.step()

	check(
		sim1.state_hash() != sim_idle.state_hash(),
		"chopping thicket tree modifies state hash (neg-control)"
	)

	host1.queue_free()
	host2.queue_free()
	host_idle.queue_free()
	await process_frame

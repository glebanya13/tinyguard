extends SceneTree
## A journal written before the castle upgrade existed (hand-made: builds, upgrades, a hire,
## wood bought, the sword, a sale, with the header of sim_version 2) must replay on the
## current code with the very same state hashes: the castle adds nothing to the hash until
## its first upgrade. The golden hashes below were taken on the commit before UPGRADE_CASTLE.
## LEVEL=<id> godot --headless --fixed-fps 60 --path . --script res://tests/test_old_journal.gd

const TOTAL_TICKS := 3000
const HASH_EVERY := 300
## level id -> state hash at every HASH_EVERY-th step of the journal below.
const GOLDEN: Dictionary = {
	1: [
		7551071772688321947, -1173122881631746942, -41596820854702723, -5573837748390884276,
		-163970875267333930, 4718415681934135167, -9192331749649923436, 6885218292519304434,
		3152690927412392964, 3298410142640502617,
	],
	3: [
		3412921427815170619, 8991223988479817856, 5231913296378219673, 3566291903827656843,
		-8240670637439776257, 297925843446351500, 3764851205796294502, -2462479802279913129,
		6731073523859696038, 2327833304187123321,
	],
}

var fails := 0
var _trace: Array[int] = []


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_old_journal.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	node_added.connect(
		func(node: Node) -> void:
			if node is Hero:
				(node as Hero).auto_action = false
	)
	_run.call_deferred()


func _journal(level_id: int) -> CommandLog:
	var log := CommandLog.new()
	log.header = {
		"sim_version": 2, "tick_rate": 30, "level": level_id, "endless": false, "seed": 4242,
		"perks": {},
	}
	var rows: Array = [
		[5, 0, 11, 1],
		[8, 0, 12, 0],
		[12, 0, 0, 0, 0],
		[60, 0, 0, 1, 1],
		[110, 0, 0, 2, 2],
		[200, 0, 0, 3, 3],
		[300, 0, 0, 4, 0],
		[420, 0, 1, 0],
		[700, 0, 1, 1],
		[800, 0, 3],
		[900, 0, 10, 0, 2],
		[1100, 0, 1, 2],
		[1300, 0, 3],
		[1500, 0, 2, 4],
		[1700, 0, 4],
		[1900, 0, 1, 3],
		[2100, 0, 5, 1],
		[2400, 0, 1, 0],
	]
	for row: Array in rows:
		log.add(GameCommand.from_array(row))
	return log


func _run() -> void:
	var level_id: int = int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1
	LevelCatalog.selected_id = level_id
	paused = false
	var old_scene: Node = current_scene
	change_scene_to_file("res://scenes/main.tscn")
	var sim: Sim = null
	while sim == null:
		await process_frame
		if current_scene != null and current_scene != old_scene and current_scene.has_node("Sim"):
			sim = current_scene.get_node("Sim")
	sim.manual = true
	for i in 200:
		if sim.running:
			break
		await process_frame
	sim.ticked.connect(
		func(t: int) -> void:
			if t % HASH_EVERY == 0:
				_trace.append(sim.state_hash())
	)
	sim.begin_replay(_journal(level_id))
	while sim.tick < TOTAL_TICKS:
		sim.advance(0.1)
		await process_frame
	print("GOLDEN level %d: %s" % [level_id, _trace])
	var gold: Array = GOLDEN.get(level_id, [])
	if not gold.is_empty():
		check(str(_trace) == str(gold), "level %d: old journal keeps its hashes" % level_id)
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)

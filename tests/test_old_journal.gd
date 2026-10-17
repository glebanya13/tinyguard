extends SceneTree
## A journal written before the castle upgrade existed (hand-made: builds, upgrades, a hire,
## wood bought, the sword, a sale, with the header of sim_version 2) must replay on the
## current code with the very same state hashes: the castle adds nothing to the hash until
## its first upgrade. The golden hashes of c1 and c3 were taken on the commit before
## UPGRADE_CASTLE; the others (the other levels, the record run, the daily challenge) on the
## commit that added it, with no castle command in the journal: c1 and c3 prove that the
## hash only changes after an upgrade.
## LEVEL=<id> godot --headless --fixed-fps 60 --path . --script res://tests/test_old_journal.gd

const TOTAL_TICKS := 3000
const HASH_EVERY := 300
## case ('c<level>' campaign, 'r<level>' record run, 'd' daily challenge) -> state hash at every HASH_EVERY-th step of the journal below.
const GOLDEN: Dictionary = {
	"c1": [
		7551071772688321947, -1173122881631746942, -41596820854702723, -5573837748390884276,
		-163970875267333930, 4718415681934135167, -9192331749649923436, 6885218292519304434,
		3152690927412392964, 3298410142640502617,
	],
	"c2": [
		6952952273017873854, 6024915522218639285, 7805469926763322812, -5066074232681010581,
		-8031318103329998009, -489417183453187414, 8811643065913737680, -5678980959798390171,
		5605124167351129647, 92291798644917040,
	],
	"c3": [
		3412921427815170619, 8991223988479817856, 5231913296378219673, 3566291903827656843,
		-8240670637439776257, 297925843446351500, 3764851205796294502, -2462479802279913129,
		6731073523859696038, 2327833304187123321,
	],
	"c4": [
		-8857023506699469214, -6005522188577988465, -7979038756482711920, -3085406235252578058,
		2401324519557867347, -2809503295699264239, -6031214672470188599, 3665204154151349275,
		8337870750421539237, 1637312406279236389,
	],
	"c5": [
		-3974506745807109667, 2041189718589709538, 8008664393530663719, 4392401372462279899,
		986123714935690512, 541053313172832146, -4804961254777012074, -7345195080014201551,
		7881209913315393449, 2812354974030537735,
	],
	"c6": [
		-7311030496001093361, -9075817394910664856, -6519720532988291611, 6226060941432085640,
		8493318381555069279, 3490518524348542884, 352150339036657626, 309926386863715370,
		5578056531412865626, -3462661739801565712,
	],
	"r1": [
		5268845084965223506, -6504440833468075778, 5020456821367776810, 6362725490192885946,
		-87163837897229267, -1071265406220188217, 6419242887063098981, 3577882170342181177,
		1021106363648170822, -1267330359089447743,
	],
	"r2": [
		-843228626799020701, -1826699515300113160, -6287955324059897484, -1083957054544744700,
		-2292940609016569757, 1842082511795799844, 5540109679675451489, -4684213650356861179,
		-4242955740299265956, 6058562711550924354,
	],
	"r3": [
		-7346015082878959524, 6837562837092193737, -1456138389391230115, 9075021529779278805,
		-7100005456837642930, 1458851893575174412, -1881868831300976177, -7542805680705917687,
		-7885542903556165093, -6327041367632370758,
	],
	"r4": [
		1103141833403826263, 6819420330732800429, 1831658979802777177, 4180067292354037381,
		-7829607557935719805, 8381014002967319904, -5545241459633086407, 7044207592975133084,
		6571884954251016380, -77194377842614379,
	],
	"r5": [
		8430673695647460454, 7613957021659573499, -6985347806315944209, 9155098791992835622,
		1434380304204486859, -5396671360359890091, 4740073344176768281, -5327963897471969191,
		6353493885958032762, 2089463750948128018,
	],
	"r6": [
		-7841127286918139540, 2791636518313706833, 2357335397593566141, 5077408405143419523,
		9033911909664677370, -1266914904367793401, -3555032402015128288, 4222268397431205885,
		-1539946953417336589, -1345778404493502358,
	],
	"d": [
		7377947009630537043, 2761842380670991776, 6414596209418234636, -5000958402391682710,
		967004606833889893, 6842491453945015518, 6702644645045986895, 772764742908260288,
		-6395261413520723986, -2978487975376719747,
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
	await _case("c%d" % level_id, level_id, false, "")
	await _case("r%d" % level_id, level_id, true, "")
	if level_id == 1:
		await _case("d", 1, true, _daily_day())
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _daily_day() -> String:
	var base: int = Daily.day_index("2026-10-15")
	for i in 30:
		var key: String = Daily.key_of_day(base + i)
		if str(Daily.preset_for(key)["id"]) == "archers_frost":
			return key
	return Daily.key_of_day(base)


## Replays the old journal in one mode and compares the hashes with the golden ones.
func _case(key: String, level_id: int, endless: bool, daily: String) -> void:
	_trace.clear()
	LevelCatalog.daily_key = ""
	LevelCatalog.endless = endless
	LevelCatalog.selected_id = level_id
	if daily != "":
		DailyRun.select(daily)
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
	var journal: CommandLog = _journal(level_id)
	if endless:
		journal.header["endless"] = true
		journal.header["record"] = 1
	if daily != "":
		journal.header.erase("record")
		journal.header["daily"] = daily
		journal.header["seed"] = DailyRun.seed_of(daily)
	sim.begin_replay(journal)
	while sim.tick < TOTAL_TICKS:
		sim.advance(0.1)
		await process_frame
	print("GOLDEN %s: %s" % [key, _trace])
	var gold: Array = GOLDEN.get(key, [])
	check(not gold.is_empty(), "case %s has golden hashes" % key)
	check(str(_trace) == str(gold), "case %s: old journal keeps its hashes" % key)
	await process_frame
	await process_frame

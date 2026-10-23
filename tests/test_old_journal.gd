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
## case ('c<level>' campaign, 'r<level>' record run, 'd' daily challenge) -> state hash
## at every HASH_EVERY-th step of the journal below.
const GOLDEN: Dictionary = {
	"c1":
	[
		-3276586674870159117,
		2885948362049952364,
		478237695416826538,
		6512947371650528080,
		-4495736033380963321,
		-1974300242392254699,
		-3124397878961308883,
		2028040879509085667,
		-9181841184010559758,
		-2708906440730865365,
	],
	"c2":
	[
		-2565498617144122111,
		16200532590369091,
		-7874608742384973779,
		-4372979958670493249,
		1124241328757701132,
		2555252571981211511,
		3623832932209933573,
		1896855409012778674,
		-900195570967897540,
		902236596018941243,
	],
	"c3":
	[
		-6406622347433696427,
		6515864332281183115,
		4174581193879965889,
		1943049687672714888,
		-4197079973404908481,
		7219690596388828004,
		2722363041583262068,
		-1545147389720511573,
		4590112813866514761,
		-690360144078875867,
	],
	"c4":
	[
		472739660768156112,
		6122845271310301181,
		4392756468960908167,
		-7222814602157067742,
		-2144223407298175074,
		-1054602759967400883,
		-6407299545127883484,
		-4440483425335604666,
		4931423233749203037,
		-4065784352139251147,
	],
	"c5":
	[
		7313137763623108688,
		8249591862082991548,
		5518030849355111850,
		-4810000005530152121,
		-3551562272412729629,
		-5750752266813924245,
		-3355399258431882655,
		-8303796040153812245,
		9163026203333557179,
		7616230319644155269,
	],
	"c6":
	[
		-7052260301934150766,
		2168793047863469454,
		-2697492803401103584,
		-3315678689186391188,
		-5885851677539635468,
		-1340222486460408435,
		5194528641967839101,
		5980290984973638754,
		2023046753254986664,
		-8730944553712082134,
	],
	"r1":
	[
		-634544287587476624,
		5179049431515868492,
		-5948722395044075784,
		-1951882782080078308,
		-7659387349634071657,
		5887444380030728601,
		4009676635554925495,
		-5541096416166261453,
		7773075697225403792,
		-6113051844509516469,
	],
	"r2":
	[
		-270348745582527382,
		-2027971413406349658,
		-7295030789680491550,
		-7563728742517078206,
		-1256875685636893191,
		-9031202758536020779,
		-8091995544654278274,
		-3710006083205431372,
		3848009718687105165,
		-1420095152492025249,
	],
	"r3":
	[
		-5356232387131903241,
		-3416388795826185659,
		561525228160293241,
		7362021266155087396,
		2840275290784350965,
		3749539481547232168,
		7049583952713991380,
		8094017686275434653,
		-5050006093700938285,
		2759358361980595661,
	],
	"r4":
	[
		5212475547870966679,
		-5403837867765364477,
		6094997723635181775,
		-208212301058606361,
		-1721684837431879079,
		1304521687684720246,
		690409493328030946,
		-8484158882238455838,
		-1948000330247692056,
		5629784487447276352,
	],
	"r5":
	[
		7597032674516047473,
		20030547171944421,
		-5747643913011987255,
		774383692628311972,
		5829761747040000165,
		-1203573933400313054,
		-1771088321278630623,
		-7386690027411830003,
		-3875745117625451341,
		7855148648671334734,
	],
	"r6":
	[
		4643450548938523499,
		-4397475362755577081,
		6482639743752676675,
		-5916002565942725159,
		4300328243935181788,
		-8344521209889482040,
		2468736754322437633,
		-5863998993432648964,
		8180713739269725427,
		8960554571994098684,
	],
	"d":
	[
		-2659340483585689704,
		-6892689164399990126,
		-6657769619720548716,
		6308381680536661621,
		3601229602049529558,
		8509270566304151717,
		661633406447449031,
		6102736935889659332,
		3204595264294438448,
		-9175164608254678410,
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
		"sim_version": 2,
		"tick_rate": 30,
		"level": level_id,
		"endless": false,
		"seed": 4242,
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

extends SceneTree
## A journal written before the castle upgrade existed (hand-made: builds, upgrades, a hire,
## wood bought, the sword, a sale, with the header of sim_version 2) must replay on the
## current code with the very same state hashes: the castle adds nothing to the hash until
## its first upgrade. The golden hashes of c1 and c3 were taken on the commit before
## UPGRADE_CASTLE; the others (the other levels, the record run, the daily challenge) on the
## commit that added it, with no castle command in the journal: c1 and c3 prove that the
## hash only changes after an upgrade. All of them were taken again on 2026-10-24 (one tree per
## swing, groves of trees, cheaper tower upgrades: the battle itself changed).
## LEVEL=<id> godot --headless --fixed-fps 60 --path . --script res://tests/test_old_journal.gd

const TOTAL_TICKS := 3000
const HASH_EVERY := 300
## case ('c<level>' campaign, 'r<level>' record run, 'd' daily challenge) -> state hash
## at every HASH_EVERY-th step of the journal below.
const GOLDEN: Dictionary = {
	"c1":
	[
		-7773269104033447381,
		-534260398996171831,
		-7982274077953303825,
		1351735264812303809,
		-653359048343757880,
		-5316094520268368792,
		3280943152272175391,
		-2563201533172358628,
		-740512545283464903,
		-7626442653157021917,
	],
	"c2":
	[
		429681422200659246,
		2185566261159532286,
		-237436793582298320,
		6151938247297893098,
		3889104929263540249,
		3778818988148528970,
		-2211234290511777246,
		-2418194418063805525,
		-7746593872427090997,
		-1745998280583260908,
	],
	"c3":
	[
		4161163969411156116,
		3365758094891272018,
		-7144598191481432976,
		-3482822828526836989,
		-144602072838946716,
		-8118855966072351847,
		8288130423842858385,
		-5538529364858545636,
		8195218997884118328,
		2197301186527167476,
	],
	"c4":
	[
		-930956193452138240,
		2079983313150731309,
		3329574188518818039,
		-2654013555979574718,
		-8398273737067518018,
		2755555540446455469,
		1128003878208758628,
		591346747131359078,
		1634468644454456829,
		6664893693328860645,
	],
	"c5":
	[
		1422143807465156308,
		7988418971821830881,
		-8247059586265824429,
		-7423595291177690992,
		3342977700898338887,
		-6015041291952860415,
		-6335932458155014524,
		1894965035810843662,
		-1454749103991688577,
		2784950884718114900,
	],
	"c6":
	[
		-6704806900036394830,
		-1542725560254499674,
		3477672509470402336,
		7808790736318380188,
		-4661045430407292692,
		1537372507218633813,
		-7088175140410833643,
		176725369613337402,
		2726059414763312072,
		-8187889921894517974,
	],
	"r1":
	[
		4506550108678294014,
		-1965046673669233918,
		-7469006599778979802,
		1719133831079448750,
		3112491828439857315,
		-3911247073913967894,
		1797321391803744676,
		3329613105141747034,
		7235137774114540703,
		4399254383458531527,
	],
	"r2":
	[
		4363317660687960145,
		4548517607416303141,
		1273709658556594313,
		5870509733347878049,
		-4802178972054805722,
		-5299796810827652380,
		3240359080419176139,
		-8334604327904352489,
		364317529389716866,
		-7137955073652163288,
	],
	"r3":
	[
		-7894934089247368352,
		-2044571054761034928,
		7604775517516029220,
		-580437594592990409,
		3461517491543515522,
		1470121811161710023,
		6873889003609939309,
		-6106325716848049140,
		8711675984500791126,
		-6995769729802843362,
	],
	"r4":
	[
		2895550523393730391,
		4859272993118675299,
		-8900514385159618417,
		-617340846564972329,
		-3382609766968653367,
		2555972480975940790,
		-1077975308776815438,
		-2837631782692825774,
		3108546475516423528,
		617935185500227472,
	],
	"r5":
	[
		3157653059467611855,
		-1450165803792957141,
		3612803395567152519,
		2655574582537059852,
		8780944238197000420,
		-2570611192195577085,
		-8241488148332061474,
		-5315238265745693315,
		474294934892860757,
		5165818687543654398,
	],
	"r6":
	[
		1201642487429284827,
		-268349028110382585,
		-7523208434736816765,
		4302405347577457297,
		-6541991129277101956,
		9195402017241790896,
		2087244344809122113,
		135445762155120204,
		-6174089541251114061,
		4451736195314272508,
	],
	"d":
	[
		-2824816755501979779,
		-8347777081408879009,
		8069163425767610393,
		8036511004786887358,
		2400340742355554837,
		-9142060494381560956,
		-5585927621399255018,
		-2786647268263248881,
		-5811974284510569587,
		-6538042364718779973,
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

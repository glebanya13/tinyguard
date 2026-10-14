class_name CoopBattle
extends Node
## The co-op side of a battle scene (docs/MULTIPLAYER.md, "Co-op in the game"):
## the CoopSession of the match, the partner's ghost knight with his name tag,
## the lockstep driver plugged into the battle clock, and leaving the room.
## main.gd creates it only for a co-op match; single player never sees it.

## The match ended for another reason than the battle's own victory or defeat:
## "partner_left", "lost", "desync", "protocol", "denied".
signal match_over(reason: String)
## The partner has been silent (true) or is back (false).
signal partner_waiting(waiting: bool)

const HERO_SCENE: PackedScene = preload("res://scenes/hero.tscn")
## The guest's knight stands this far (metres) from the host's start spot.
const GUEST_OFFSET := 0.8
## After the battle's end the room is kept this long (seconds), so a partner a few
## steps behind still reaches the same victory or defeat before the farewell.
const END_GRACE := 4.0
const END_TEXTS := {
	"partner_left": ["COOP_END_LEFT", "COOP_END_LEFT_TEXT"],
	"lost": ["COOP_END_LOST", "COOP_END_LOST_TEXT"],
	"desync": ["COOP_END_DESYNC", "COOP_END_DESYNC_TEXT"],
	"protocol": ["COOP_END_PROTOCOL", "COOP_END_PROTOCOL_TEXT"],
	"denied": ["COOP_END_DENIED", "COOP_END_DENIED_TEXT"],
}

var session: CoopSession = null
var ghost: Hero = null
var lobby: CoopLobby = null
var slot: int = 0
var config: Dictionary = {}

var _left: bool = false


## Titles for a reason ("lost" for an unknown one): [title key, text key].
static func end_texts(reason: String) -> Array:
	return END_TEXTS.get(reason, END_TEXTS["lost"])


## Wires the match into the battle: `hero` is the local knight (slot 0 = host).
func setup(
	match_config: Dictionary,
	transport: CoopTransport,
	room: CoopLobby,
	sim: Sim,
	commands: GameCommands,
	hero: Hero,
	level_root: Node3D
) -> void:
	config = match_config
	lobby = room
	slot = 0 if str(config["role"]) == "host" else 1
	session = CoopSession.new(
		transport, str(config["code"]), str(config["role"]), int(config["delay"])
	)
	var start: Vector3 = hero.global_position
	var second: Vector3 = start + Vector3(GUEST_OFFSET, 0.0, 0.0)
	ghost = HERO_SCENE.instantiate() as Hero
	ghost.name = "PartnerHero"
	ghost.is_ghost = true
	ghost.sim = sim
	ghost.commands = commands
	ghost.collision_layer = 0
	ghost.collision_mask = 0
	level_root.add_child(ghost)
	ghost.position = start if slot == 1 else second
	ghost.ghost_goto(ghost.position)
	if slot == 1:
		hero.position = second
	ghost.add_child(_name_tag(str(config.get("partner", ""))))
	var knights: Array[Hero] = []
	knights.append(hero if slot == 0 else ghost)
	knights.append(ghost if slot == 0 else hero)
	commands.heroes = knights
	sim.heroes = knights
	commands.local_player = slot
	commands.validate_hero = true
	commands.coop = session
	sim.coop = CoopDriver.new(session, sim, commands)
	session.partner_state_changed.connect(_on_partner_state)
	session.ended.connect(_on_ended)
	session.start()


## Leaves the match and the room (once): the farewell, then the room is cleaned.
func leave() -> void:
	if _left or session == null:
		return
	_left = true
	# A static coroutine: it goes on when this node is freed by a scene change.
	await CoopRun.leave_match(session, lobby)


## After the battle's own end: wait a moment, then leave.
func leave_later() -> void:
	if END_GRACE <= 0.0 or not is_inside_tree():
		leave()
		return
	await get_tree().create_timer(END_GRACE, true, false, true).timeout
	leave()


func has_left() -> bool:
	return _left


func _name_tag(text: String) -> Label3D:
	var tag := Label3D.new()
	tag.text = text
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.fixed_size = true
	tag.pixel_size = 0.0007
	tag.font_size = 28
	tag.outline_size = 8
	tag.position = Vector3(0.0, 2.2, 0.0)
	return tag


func _on_partner_state(state: String) -> void:
	partner_waiting.emit(state != "ok")


func _on_ended(reason: String) -> void:
	if reason != "left":
		match_over.emit(reason)

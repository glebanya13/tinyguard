class_name Puppet
extends Node
## Procedural animation of a little person (the knight, a villager): the model
## has separate parts (Body, Head, ArmL/R, LegL/R, optional Cape, Sword) with
## their pivots at the joints, and this node moves them every frame.
##   * walking and running follow the REAL speed of the model (measured from
##     its position), so legs, arms, bob and lean match what the feet do;
##   * the body rocks, bounces on every step (squash and stretch) and leans
##     into the run and into turns;
##   * standing still it breathes, shifts its weight and looks around;
##   * one-shot clips (PuppetClips: sword swing, whirlwind, wave, hop...) blend over
##     the walk.
## Drawing only: nothing here reaches the simulation or its hash.

## Body parts a clip or the walk can move. ROOT is the whole model (hops).
enum Part { BODY, HEAD, ARM_L, ARM_R, LEG_L, LEG_R, CAPE, SWORD, ROOT }

const PART_NAMES: Array[StringName] = [
	&"Body", &"Head", &"ArmL", &"ArmR", &"LegL", &"LegR", &"Cape", &"Sword"
]
const FADE_IN := 0.06
const FADE_OUT := 0.12

## The glb instance with the parts (set in the scene).
@export var model: Node3D

@export_group("Walk")
## Speed (m/s) at which the walk reaches full strength.
@export var run_speed: float = 3.2
## Metres per full cycle (two steps): shorter strides step faster.
@export var stride: float = 1.3
## Degrees.
@export var leg_swing: float = 44.0
@export var arm_swing: float = 38.0
@export var lean: float = 12.0
@export var body_roll: float = 7.0
@export var body_twist: float = 8.0
## Metres the body rises between the steps, and the squash and stretch share.
@export var bounce: float = 0.07
@export var squash: float = 0.07
@export var leg_lift: float = 0.05
## Degrees of banking per radian/s of turning.
@export var bank: float = 1.2

@export_group("Idle")
@export var breath: float = 0.025
## Degrees the head turns when it looks around.
@export var look_around: float = 24.0
## Seconds between hops on the spot (0 = never); villagers only.
@export var fidget_min: float = 0.0
@export var fidget_max: float = 0.0
@export var fidget_clips: Array[StringName] = [&"hop"]

var _parts: Array[Node3D] = []
var _rest_basis: Array[Basis] = []
var _rest_pos: Array[Vector3] = []
var _rest_scale: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()
var _last_pos: Vector3 = Vector3.ZERO
var _last_yaw: float = 0.0
var _have_last: bool = false
var _speed: float = 0.0
var _yaw_rate: float = 0.0
var _phase: float = 0.0
var _time: float = 0.0
var _offset: float = 0.0
var _clip: Dictionary = {}
var _clip_time: float = 0.0
var _clip_scale: float = 1.0
var _fidget_left: float = 0.0
# Scratch pose of this frame, indexed by Part.
var _q: Array[Quaternion] = []
var _loc: Array[Vector3] = []
var _scl: Array[Vector3] = []


func _ready() -> void:
	_rng.seed = get_instance_id()
	_offset = _rng.randf() * TAU
	_time = _rng.randf() * 10.0
	_phase = _rng.randf() * TAU
	_fidget_left = _rng.randf_range(fidget_min, maxf(fidget_max, fidget_min))
	if model == null:
		set_process(false)
		return
	for name_idx in PART_NAMES.size():
		_parts.append(model.find_child(PART_NAMES[name_idx], true, false) as Node3D)
	_parts.append(model)
	for part in _parts:
		_rest_basis.append(part.basis if part else Basis.IDENTITY)
		_rest_pos.append(part.position if part else Vector3.ZERO)
		_rest_scale.append(Vector3.ONE)
		_q.append(Quaternion.IDENTITY)
		_loc.append(Vector3.ZERO)
		_scl.append(Vector3.ONE)
	# Other nodes of the model (the glb's AnimationPlayer) must not fight us.
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player:
		player.stop()
		player.process_mode = Node.PROCESS_MODE_DISABLED


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	_time += delta
	_measure(delta)
	_reset()
	_walk_pose()
	if _clip.is_empty():
		_idle_fidget(delta)
	else:
		_clip_time += delta * _clip_scale
		if _clip_time >= float(_clip.length):
			_clip = {}
		else:
			_blend_clip()
	_apply()


## Starts a one-shot clip. `duration` > 0 stretches it to last that many seconds.
func play_action(clip_name: StringName, duration: float = 0.0) -> void:
	var clip: Dictionary = PuppetClips.get_clip(clip_name)
	if clip.is_empty():
		return
	_clip = clip
	_clip_time = 0.0
	_clip_scale = float(clip.length) / duration if duration > 0.0 else 1.0


## Length in seconds of the clip (0 if there is none).
func action_length(clip_name: StringName) -> float:
	return float(PuppetClips.get_clip(clip_name).get("length", 0.0))


func is_acting() -> bool:
	return not _clip.is_empty()


## Smoothed ground speed of the model (m/s), for tests and listeners.
func current_speed() -> float:
	return _speed


func _measure(delta: float) -> void:
	var pos: Vector3 = model.global_position
	var yaw: float = model.rotation.y
	if _have_last:
		var step := Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z)
		var fast: float = step.length() / delta
		# A teleport (spawn, ghost snapping to a new place) is not running.
		if fast > run_speed * 3.0:
			fast = 0.0
		_speed = lerpf(_speed, fast, clampf(delta / 0.1, 0.0, 1.0))
		var turn: float = wrapf(yaw - _last_yaw, -PI, PI) / delta
		_yaw_rate = lerpf(_yaw_rate, clampf(turn, -12.0, 12.0), clampf(delta / 0.12, 0.0, 1.0))
	_last_pos = pos
	_last_yaw = yaw
	_have_last = true
	if _speed > 0.05:
		_phase += TAU * _speed / stride * delta


func _reset() -> void:
	for i in _parts.size():
		_q[i] = Quaternion.IDENTITY
		_loc[i] = Vector3.ZERO
		_scl[i] = Vector3.ONE


## Idle plus walk, mixed by how fast the model really moves.
func _walk_pose() -> void:
	var run: float = clampf(_speed / run_speed, 0.0, 1.3)
	var calm: float = clampf(1.0 - run * 1.6, 0.0, 1.0)
	var s: float = sin(_phase)
	var c2: float = cos(2.0 * _phase)
	var o: float = _offset
	var t: float = _time
	# Breathing, weight shift and glances while standing.
	var br: float = sin(t * 2.4 + o)
	var glance: float = sin(t * 0.55 + o) * sin(t * 0.19 + o * 2.0)
	var body_e := Vector3(0.0, 0.0, sin(t * 0.37 + o) * 1.6 * calm)
	var body_s := Vector3(1.0, 1.0, 1.0)
	body_s.z += breath * br * calm
	body_s.x -= breath * 0.5 * br * calm
	body_s.y = body_s.x
	var head_e := Vector3(sin(t * 0.9 + o) * 2.5 * calm, glance * look_around * calm, 0.0)
	var arm_idle: float = br * 3.0 * calm
	# Walking: lean, rock, bounce.
	var bank_z: float = clampf(-_yaw_rate * bank, -10.0, 10.0) * run
	body_e.x += lean * run + 2.0 * br * calm
	body_e.y += body_twist * s * run
	body_e.z += body_roll * s * run + bank_z
	body_s.z += squash * c2 * run
	body_s.x -= squash * 0.5 * c2 * run
	body_s.y = body_s.x
	head_e.x += -lean * 0.6 * run - 3.0 * c2 * run
	head_e.y -= body_twist * 0.8 * s * run
	head_e.z += -body_roll * 0.6 * s * run - bank_z * 0.5
	var lift: float = (1.0 - absf(s)) * bounce * run
	_loc[Part.ROOT].y += lift
	_pose(Part.BODY, body_e, Vector3.ZERO, body_s)
	_pose(Part.HEAD, head_e)
	_pose(Part.LEG_L, Vector3(leg_swing * s * run, 0.0, 0.0), Vector3(0, leg_lift * maxf(-cos(_phase), 0.0) * run, 0))
	_pose(Part.LEG_R, Vector3(-leg_swing * s * run, 0.0, 0.0), Vector3(0, leg_lift * maxf(cos(_phase), 0.0) * run, 0))
	_pose(Part.ARM_L, Vector3(-arm_swing * s * run + arm_idle - 14.0 * run, 0.0, 4.0 * calm))
	_pose(Part.ARM_R, Vector3(arm_swing * 0.75 * s * run - arm_idle - 10.0 * run, 0.0, -2.0 * calm))
	# The cape streams back with speed and flutters.
	var flutter: float = sin(t * 7.0 + o) * 4.0 * run + sin(t * 1.7 + o) * 3.0 * calm
	_pose(
		Part.CAPE,
		Vector3(3.0 + 38.0 * run + 5.0 * br * calm + 6.0 * c2 * run, 0.0, flutter + bank_z * 0.6)
	)


func _pose(part: int, euler_deg: Vector3, loc: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> void:
	if _parts[part] == null:
		return
	_q[part] = (
		Quaternion(Vector3.UP, deg_to_rad(euler_deg.y))
		* Quaternion(Vector3.BACK, deg_to_rad(euler_deg.z))
		* Quaternion(Vector3.RIGHT, deg_to_rad(euler_deg.x))
	)
	_loc[part] += loc
	_scl[part] = scl


func _idle_fidget(delta: float) -> void:
	if fidget_max <= 0.0 or _speed > 0.1:
		return
	_fidget_left -= delta
	if _fidget_left <= 0.0 and not fidget_clips.is_empty():
		_fidget_left = _rng.randf_range(fidget_min, fidget_max)
		play_action(fidget_clips[_rng.randi() % fidget_clips.size()])


func _blend_clip() -> void:
	var length: float = _clip.length
	var weight: float = minf(_clip_time / FADE_IN, 1.0)
	weight = minf(weight, (length - _clip_time) / FADE_OUT)
	weight = clampf(weight, 0.0, 1.0)
	var tracks: Dictionary = _clip.tracks
	for part: int in tracks:
		if _parts[part] == null:
			continue
		var keys: Array = tracks[part]
		var k: int = 0
		while k < keys.size() - 2 and _clip_time > float(keys[k + 1][0]):
			k += 1
		var a: Array = keys[k]
		var b: Array = keys[mini(k + 1, keys.size() - 1)]
		var span: float = float(b[0]) - float(a[0])
		var u: float = clampf((_clip_time - float(a[0])) / span, 0.0, 1.0) if span > 0.0 else 1.0
		u = u * u * (3.0 - 2.0 * u)
		var q: Quaternion = (a[1] as Quaternion).slerp(b[1] as Quaternion, u)
		var loc: Vector3 = (a[2] as Vector3).lerp(b[2] as Vector3, u)
		var scl: Vector3 = (a[3] as Vector3).lerp(b[3] as Vector3, u)
		_q[part] = _q[part].slerp(q, weight)
		_loc[part] = _loc[part].lerp(loc, weight)
		_scl[part] = _scl[part].lerp(scl, weight)


func _apply() -> void:
	for i in _parts.size():
		var part: Node3D = _parts[i]
		if part == null:
			continue
		# The model's own turning (yaw) belongs to its owner.
		if i != Part.ROOT:
			part.basis = _rest_basis[i] * Basis(_q[i]) * Basis.from_scale(_scl[i])
		part.position = _rest_pos[i] + _loc[i]

class_name PuppetClips
extends RefCounted
## One-shot clips of the little people (sword swing, whirlwind, wave, hop...).
## A clip is {length: seconds, tracks: {Puppet.Part: [[t, Quaternion, loc, scale], ...]}}.
## Keys are written like the Blender build scripts: rotations as Blender euler
## degrees (X, Y, Z), relative to the rest pose; loc is metres in the part's parent
## space, scale multiplies the rest scale. Between two keys the pose eases in/out.
## Drawing only: clips never touch the simulation.

const P := Puppet.Part

static var _clips: Dictionary = {}


## The clip called `clip_name`, or an empty Dictionary.
static func get_clip(clip_name: StringName) -> Dictionary:
	if _clips.is_empty():
		_build()
	return _clips.get(clip_name, {})


## Blender euler degrees (X, Y, Z; Blender Z up, -Y forward) as a Godot rotation.
static func blender_rot(deg: Vector3) -> Quaternion:
	# Blender X stays X, Blender Y becomes -Z, Blender Z becomes Y (glTF axes).
	return (
		Quaternion(Vector3.UP, deg_to_rad(deg.z))
		* Quaternion(Vector3.BACK, deg_to_rad(-deg.y))
		* Quaternion(Vector3.RIGHT, deg_to_rad(deg.x))
	)


static func _k(t: float, rot := Vector3.ZERO, loc := Vector3.ZERO, scl := Vector3.ONE) -> Array:
	return [t, blender_rot(rot), loc, scl]


static func _build() -> void:
	_clips[&"attack"] = _attack()
	_clips[&"spin"] = _spin()
	_clips[&"wave"] = _wave()
	_clips[&"hop"] = _hop(1)
	_clips[&"cheer"] = _hop(2)
	_clips[&"skip"] = _skip()
	_clips[&"chop"] = _chop()


## Sword slash: wind-up, strike at ~0.21 s (the Sim hits at 0.2 s), recover.
static func _attack() -> Dictionary:
	var squash := Vector3(1.06, 1.06, 0.92)
	return {
		length = 0.5,
		tracks =
		{
			P.ARM_R:
			[
				_k(0.0),
				_k(0.125, Vector3(-165, 0, -15)),
				_k(0.208, Vector3(-40, 0, 18)),
				_k(0.333, Vector3(-25, 0, 10)),
				_k(0.5),
			],
			P.ARM_L:
			[
				_k(0.0),
				_k(0.125, Vector3(20, 0, 10)),
				_k(0.208, Vector3(-15, 0, -5)),
				_k(0.5),
			],
			P.BODY:
			[
				_k(0.0),
				_k(0.125, Vector3(-6, 0, 22), Vector3(0, 0, 0.0), squash),
				_k(0.208, Vector3(14, 0, -30), Vector3(0, 0, 0.07), Vector3(0.96, 0.96, 1.06)),
				_k(0.333, Vector3(8, 0, -18), Vector3(0, 0, 0.03)),
				_k(0.5),
			],
			P.HEAD:
			[
				_k(0.0),
				_k(0.125, Vector3(4, 0, -8)),
				_k(0.208, Vector3(-6, 0, 10)),
				_k(0.5),
			],
			P.CAPE:
			[_k(0.0, Vector3(2, 0, 0)), _k(0.208, Vector3(34, 0, 8)), _k(0.5, Vector3(2, 0, 0))],
			P.LEG_R: [_k(0.0), _k(0.208, Vector3(-24, 0, 0)), _k(0.5)],
			P.LEG_L: [_k(0.0), _k(0.208, Vector3(22, 0, 0)), _k(0.5)],
			P.SWORD:
			[
				_k(0.0),
				_k(0.083, Vector3(150, 0, 0)),
				_k(0.208, Vector3(170, 0, 0)),
				_k(0.375, Vector3(160, 0, 0)),
				_k(0.5),
			],
			P.ROOT:
			[
				_k(0.0),
				_k(0.125, Vector3.ZERO, Vector3(0, -0.04, 0)),
				_k(0.208, Vector3.ZERO, Vector3(0, 0.03, 0)),
				_k(0.5),
			],
		}
	}


## Whirlwind: the sword arm out in front, crouch, spring and spin (the owner
## turns the model; the clip only shapes the body). Stretched to the spin time.
static func _spin() -> Dictionary:
	return {
		length = 0.45,
		tracks =
		{
			P.ARM_R:
			[
				_k(0.0),
				_k(0.08, Vector3(-95, 0, -25)),
				_k(0.35, Vector3(-95, 0, -25)),
				_k(0.45),
			],
			P.SWORD:
			[_k(0.0), _k(0.08, Vector3(170, 0, 0)), _k(0.35, Vector3(170, 0, 0)), _k(0.45)],
			P.ARM_L:
			[_k(0.0), _k(0.08, Vector3(0, -70, 0)), _k(0.35, Vector3(0, -70, 0)), _k(0.45)],
			P.BODY:
			[
				_k(0.0),
				_k(0.08, Vector3(10, 0, 0), Vector3.ZERO, Vector3(1.08, 1.08, 0.9)),
				_k(0.18, Vector3(16, 0, 0), Vector3.ZERO, Vector3(0.94, 0.94, 1.1)),
				_k(0.35, Vector3(12, 0, 0)),
				_k(0.45, Vector3(0, 0, 0), Vector3.ZERO, Vector3(1.05, 1.05, 0.93)),
			],
			P.LEG_L:
			[_k(0.0), _k(0.08, Vector3(-18, 0, 12)), _k(0.35, Vector3(-18, 0, 12)), _k(0.45)],
			P.LEG_R:
			[_k(0.0), _k(0.08, Vector3(18, 0, -12)), _k(0.35, Vector3(18, 0, -12)), _k(0.45)],
			P.CAPE: [_k(0.0), _k(0.2, Vector3(55, 0, 0)), _k(0.45)],
			P.ROOT:
			[
				_k(0.0),
				_k(0.08, Vector3.ZERO, Vector3(0, -0.06, 0)),
				_k(0.2, Vector3.ZERO, Vector3(0, 0.28, 0)),
				_k(0.38, Vector3.ZERO, Vector3(0, 0.1, 0)),
				_k(0.45),
			],
		}
	}


## Greeting: the right hand goes up and waves twice.
static func _wave() -> Dictionary:
	return {
		length = 1.2,
		tracks =
		{
			P.ARM_R:
			[
				_k(0.0),
				_k(0.2, Vector3(0, 150, 0)),
				_k(0.37, Vector3(0, 118, 0)),
				_k(0.54, Vector3(0, 155, 0)),
				_k(0.71, Vector3(0, 118, 0)),
				_k(0.88, Vector3(0, 155, 0)),
				_k(1.2),
			],
			P.HEAD: [_k(0.0), _k(0.25, Vector3(-4, 0, -9)), _k(0.9, Vector3(-4, 0, -9)), _k(1.2)],
			P.BODY:
			[
				_k(0.0),
				_k(0.25, Vector3(0, 0, 6), Vector3(0, 0, 0.0), Vector3(0.97, 0.97, 1.04)),
				_k(0.9, Vector3(0, 0, 6)),
				_k(1.2),
			],
			P.ARM_L: [_k(0.0), _k(0.5, Vector3(6, 0, 4)), _k(1.2)],
			P.ROOT:
			[
				_k(0.0),
				_k(0.1, Vector3.ZERO, Vector3(0, 0.07, 0)),
				_k(0.2),
				_k(0.37, Vector3.ZERO, Vector3(0, 0.05, 0)),
				_k(0.54),
				_k(0.71, Vector3.ZERO, Vector3(0, 0.05, 0)),
				_k(0.88),
				_k(1.2),
			],
		}
	}


## A jump on the spot (squash, stretch, land) with both arms up; `jumps` in a row.
static func _hop(jumps: int) -> Dictionary:
	var hop_len: float = 0.55
	var root: Array = [_k(0.0)]
	var body: Array = [_k(0.0)]
	var arm_l: Array = [_k(0.0)]
	var arm_r: Array = [_k(0.0)]
	var head: Array = [_k(0.0)]
	for j in jumps:
		var t0: float = j * hop_len
		root.append(_k(t0 + 0.10, Vector3.ZERO, Vector3(0, -0.05, 0)))
		root.append(_k(t0 + 0.28, Vector3.ZERO, Vector3(0, 0.32, 0)))
		root.append(_k(t0 + 0.46, Vector3.ZERO, Vector3(0, 0.0, 0)))
		root.append(_k(t0 + 0.50, Vector3.ZERO, Vector3(0, -0.03, 0)))
		body.append(_k(t0 + 0.10, Vector3(8, 0, 0), Vector3.ZERO, Vector3(1.1, 1.1, 0.86)))
		body.append(_k(t0 + 0.28, Vector3(-4, 0, 0), Vector3.ZERO, Vector3(0.9, 0.9, 1.14)))
		body.append(_k(t0 + 0.46, Vector3.ZERO, Vector3.ZERO, Vector3(1.06, 1.06, 0.92)))
		arm_r.append(_k(t0 + 0.10, Vector3(0, 40, 0)))
		arm_r.append(_k(t0 + 0.28, Vector3(0, 160, 0)))
		arm_r.append(_k(t0 + 0.46, Vector3(0, 70, 0)))
		arm_l.append(_k(t0 + 0.10, Vector3(0, -40, 0)))
		arm_l.append(_k(t0 + 0.28, Vector3(0, -160, 0)))
		arm_l.append(_k(t0 + 0.46, Vector3(0, -70, 0)))
		head.append(_k(t0 + 0.28, Vector3(-8, 0, 0)))
	var end: float = jumps * hop_len + 0.15
	root.append(_k(end))
	body.append(_k(end))
	arm_r.append(_k(end))
	arm_l.append(_k(end))
	head.append(_k(end))
	return {
		length = end,
		tracks = {P.ROOT: root, P.BODY: body, P.ARM_R: arm_r, P.ARM_L: arm_l, P.HEAD: head}
	}


## A happy little skip: two quick bounces with the arms swinging.
static func _skip() -> Dictionary:
	return {
		length = 0.6,
		tracks =
		{
			P.ROOT:
			[
				_k(0.0),
				_k(0.1, Vector3.ZERO, Vector3(0, 0.12, 0)),
				_k(0.2),
				_k(0.4, Vector3.ZERO, Vector3(0, 0.12, 0)),
				_k(0.5),
				_k(0.6),
			],
			P.BODY: [_k(0.0), _k(0.15, Vector3(0, 0, 8)), _k(0.45, Vector3(0, 0, -8)), _k(0.6)],
			P.ARM_L: [_k(0.0), _k(0.15, Vector3(0, -60, 0)), _k(0.45, Vector3(0, -20, 0)), _k(0.6)],
			P.ARM_R: [_k(0.0), _k(0.15, Vector3(0, 20, 0)), _k(0.45, Vector3(0, 60, 0)), _k(0.6)],
		}
	}


## Woodcutting on the spot: both arms raise the axe and swing it down twice, the body
## bows into each blow.
static func _chop() -> Dictionary:
	var up := Vector3(-150, 0, 0)
	var down := Vector3(-25, 0, 0)
	return {
		length = 1.0,
		tracks =
		{
			P.ARM_R: [_k(0.0), _k(0.14, up), _k(0.28, down), _k(0.5, up), _k(0.64, down), _k(1.0)],
			P.ARM_L: [_k(0.0), _k(0.14, up), _k(0.28, down), _k(0.5, up), _k(0.64, down), _k(1.0)],
			P.BODY:
			[
				_k(0.0),
				_k(0.14, Vector3(-6, 0, 0)),
				_k(0.28, Vector3(16, 0, 0), Vector3.ZERO, Vector3(1.04, 1.04, 0.94)),
				_k(0.5, Vector3(-6, 0, 0)),
				_k(0.64, Vector3(16, 0, 0), Vector3.ZERO, Vector3(1.04, 1.04, 0.94)),
				_k(1.0),
			],
			P.HEAD: [_k(0.0), _k(0.28, Vector3(10, 0, 0)), _k(0.64, Vector3(10, 0, 0)), _k(1.0)],
		}
	}

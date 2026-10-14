class_name SimRng
extends RefCounted
## Deterministic random numbers for the battle simulation: PCG32 on plain
## integers, so the sequence does not depend on the engine version or platform
## (RandomNumberGenerator makes no such promise). Gameplay randomness must come
## from here (Sim.rng); visual randomness (animation phases, tree yaw, villager
## strolls) uses the global randf() and never touches the simulation.

const MULTIPLIER: int = 6364136223846793005
const INCREMENT: int = 1442695040888963407
const FORK_MIX: int = 0x1E3779B97F4A7C15
const MASK_32: int = 0xFFFFFFFF
## 46 low bits: what a logical (not arithmetic) shift right by 18 leaves.
const MASK_46: int = 0x3FFFFFFFFFFF

var _state: int = 0


func _init(seed_value: int = 0) -> void:
	reseed(seed_value)


func reseed(seed_value: int) -> void:
	_state = 0
	next_u32()
	_state += seed_value
	next_u32()


## State for hashing / saving.
func state() -> int:
	return _state


## Uniform integer in 0..2^32-1.
func next_u32() -> int:
	var old: int = _state
	_state = old * MULTIPLIER + INCREMENT
	var xorshifted: int = ((((old >> 18) & MASK_46) ^ old) >> 27) & MASK_32
	var rot: int = (old >> 59) & 31
	return ((xorshifted >> rot) | (xorshifted << ((-rot) & 31))) & MASK_32


## Float in [0, 1).
func next_float() -> float:
	return float(next_u32()) / 4294967296.0


## Integer in from..to (inclusive).
func range_int(from: int, to: int) -> int:
	return from + next_u32() % (to - from + 1)


## Independent generator for one consumer, so adding a consumer later does not
## shift the numbers the others get.
func fork(stream: int) -> SimRng:
	return SimRng.new(_state ^ (stream * FORK_MIX))

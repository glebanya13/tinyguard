class_name CoopDriver
extends RefCounted
## Plugs a co-op match (CoopSession) into the battle clock (Sim): the clock may
## take a step only when the partner's commands for it have arrived; before the
## step the commands of both players run in the agreed order, and the state hash
## is reported every CoopProtocol.HASH_INTERVAL ticks. Lockstep tick and Sim
## tick are the same number (both start at 0 and count whole steps).
## See docs/MULTIPLAYER.md, "Co-op in the game".

## The wire carries numbers as JSON: 48 bits survive a trip through a double exactly
## (the full 64-bit state hash would not).
const HASH_MASK: int = 0xFFFFFFFFFFFF

var session: CoopSession = null
var sim: Sim = null
var commands: GameCommands = null
## Commands of both players executed so far (for the HUD / tests).
var executed: int = 0
## Per slot: commands that were refused by the simulation (same on both sides).
var refused: Array[int] = [0, 0]


func _init(match_session: CoopSession, battle: Sim, battle_commands: GameCommands) -> void:
	session = match_session
	sim = battle
	commands = battle_commands


## Every frame, from Sim.advance(): sends / receives, watches the silence.
func process(delta: float) -> void:
	session.process(delta)


## True when the next tick has all its commands (and the match is still on).
func can_step() -> bool:
	return not session.finished and session.lockstep.can_simulate()


## Start of a step: the hash for the checkpoint, then the commands of this tick.
func before_step() -> void:
	var lockstep: CoopLockstep = session.lockstep
	if lockstep.wants_hash():
		lockstep.report_hash(sim.state_hash() & HASH_MASK)
		if lockstep.desynced:
			return  # the match ends; the step still runs once, harmlessly
	for cmd: Dictionary in lockstep.take_commands():
		var slot: int = int(cmd["player"])
		if not commands.apply_coop(str(cmd["type"]), cmd["args"], slot):
			refused[clampi(slot, 0, 1)] += 1
		executed += 1


func after_step() -> void:
	session.lockstep.advance()

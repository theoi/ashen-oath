class_name SimState
extends SimRecord
## The whole simulation state. Copy it (Sim.snapshot) to save, copy back (Sim.restore) to
## roll back; Sim.checksum hashes it.

enum Phase {
	## Round intro: fighters placed, inputs ignored.
	INTRO,
	FIGHT,
	## A round was decided; the scene plays out, inputs ignored.
	ROUND_END,
	## The match is over (winner_team set, -1 for a draw).
	MATCH_END,
}

var tick: int = 0
## xorshift32 state; only Sim.rand_* advances it.
var rng: int = 1
var phase: Phase = Phase.INTRO
var phase_tick: int = 0
var round_number: int = 1
## Ticks since FIGHT began this round (hazard schedules count from here).
var round_tick: int = 0
## Ticks left on the round clock (-1 = no timer).
var round_timer: int = 0
## Round wins per team id (index = team).
var team_wins: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
## Team that won the last round (-1 = draw / none yet) and the match (-1 = undecided/draw).
var round_winner: int = -1
var winner_team: int = -1
## Super flash: everything but the timer freezes while > 0.
var freeze: int = 0
var freeze_owner: int = -1
var fighters: Array[FighterState] = []
var effects: Array[EffectState] = []
var next_effect_id: int = 1
## Per arena hazard: bitmask of slots hit during its current activation.
var hazard_hits: PackedInt32Array = PackedInt32Array()

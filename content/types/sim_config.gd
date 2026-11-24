class_name SimConfig
extends Resource
## Everything needed to start a deterministic match: same config + same inputs = same fight.

@export var arena: ArenaData
@export var rules: CombatRules
## 1-8 slots (with waves, the slots left up to Sim.MAX_SLOTS hold wave combatants).
@export var slots: Array[SlotConfig] = []
@export var seed: int = 1
## 0 = rules.rounds_to_win.
@export var rounds_to_win: int = 0
## Round length in seconds. 0 = rules.round_seconds, -1 = no timer.
@export var round_seconds: int = 0

@export_group("Waves")
## Story waves (empty = a plain match). Wave combatants use extra slots after `slots`.
@export var waves: Array[WaveData] = []
## Wave to start from (a checkpoint retry).
@export var start_wave: int = 0
## Extra slots for wave combatants and Sim.spawn_fighter (-1 = up to Sim.MAX_SLOTS when
## there are waves, else 0).
@export var wave_slots: int = -1

@export_group("Tuning overrides")
## Scales every hitstop (percent).
@export var hitstop_percent: int = 100
## Skill/animation speed: every move frame number is scaled by 100 / this at match start
## (rounded, at least 1 frame), and move speeds by this. sim.fighter_data holds the copies.
@export var move_speed_percent: int = 100
## Dash distance in meters for every skill-kit fighter (-1 = fighter data).
@export var dash_distance: float = -1.0
## Dash charges for every skill-kit fighter (-1 = fighter data).
@export var dash_charges: int = -1
## Frames per dash charge recharge for every skill-kit fighter (-1 = fighter data).
@export var dash_recharge_frames: int = -1


## Config slots plus wave slots: Sim.slot_count() and the replay frame width.
func total_slots() -> int:
	var extra := wave_slots if wave_slots >= 0 else (8 - slots.size() if not waves.is_empty() else 0)
	return slots.size() + maxi(0, extra)


func effective_rounds_to_win() -> int:
	return rounds_to_win if rounds_to_win > 0 else rules.rounds_to_win


func effective_round_frames() -> int:
	if round_seconds < 0:
		return -1
	return (round_seconds if round_seconds > 0 else rules.round_seconds) * 60

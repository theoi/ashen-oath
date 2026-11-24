class_name SimConfig
extends Resource
## Everything needed to start a deterministic match: same config + same inputs = same fight.

@export var arena: ArenaData
@export var rules: CombatRules
## 1-4 slots.
@export var slots: Array[SlotConfig] = []
@export var seed: int = 1
## 0 = rules.rounds_to_win.
@export var rounds_to_win: int = 0
## Round length in seconds. 0 = rules.round_seconds, -1 = no timer.
@export var round_seconds: int = 0

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


func effective_rounds_to_win() -> int:
	return rounds_to_win if rounds_to_win > 0 else rules.rounds_to_win


func effective_round_frames() -> int:
	if round_seconds < 0:
		return -1
	return (round_seconds if round_seconds > 0 else rules.round_seconds) * 60

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


func effective_rounds_to_win() -> int:
	return rounds_to_win if rounds_to_win > 0 else rules.rounds_to_win


func effective_round_frames() -> int:
	if round_seconds < 0:
		return -1
	return (round_seconds if round_seconds > 0 else rules.round_seconds) * 60

class_name HudState
extends RefCounted
## Everything the in-fight HUD shows, for one frame. A MatchRunner fills it from the sim state.

class Fighter:
	var slot := 0
	var name := ""
	var team := 0
	var is_player := false
	var health := 1000.0
	var max_health := 1000.0
	## 0..100. Burst costs 50, the super 100.
	var soul := 0.0
	var guard := 100.0
	var max_guard := 100.0
	var guard_broken := false
	var knocked_out := false
	## Seconds until each ability slot is ready (0 = ready).
	var cooldown_left: Array[float] = [0.0, 0.0, 0.0]
	## Full cooldown per slot, in seconds.
	var cooldown_total: Array[float] = [1.0, 1.0, 1.0]
	var ability_names: PackedStringArray = []


var fighters: Array[Fighter] = []
var round_number := 1
var rounds_to_win := 2
## Rounds won so far, per team.
var round_wins: Array[int] = [0, 0]
## Negative means no timer.
var seconds_left := 99.0

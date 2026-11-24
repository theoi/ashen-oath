class_name HudState
extends RefCounted
## Everything the in-fight HUD shows, for one frame. A MatchRunner fills it from the sim state.

## One skill slot on the player's skill bar.
class Skill:
	enum Type { TAP, HOLD, CHARGE, COMBO, CHAIN, DASH_STRIKE, STANCE }

	var name := ""
	## Input action that casts it (for the button prompt).
	var action: StringName
	var type := Type.TAP
	## A ⚡Counter skill (interrupts counter windows).
	var counter := false
	var icon: Texture2D
	## Seconds until ready (0 = ready) and the full cooldown.
	var cooldown_left := 0.0
	var cooldown_total := 1.0
	## False greys the slot out (knocked out, in hitstun, mid uncancellable move).
	var usable := true
	## A combo part or chain follow-up waiting in the slot: its name and the seconds left of
	## its window (0 = none).
	var follow_name := ""
	var follow_left := 0.0
	var follow_total := 0.0
	## Charge skills while charging: 0..1 of the full charge, level marks and the perfect zone.
	var charging := false
	var charge := 0.0
	var charge_levels: PackedFloat32Array = []
	var perfect_from := 0.0
	var perfect_to := 0.0

	func ready() -> bool:
		return cooldown_left <= 0.0 or follow_left > 0.0


class Fighter:
	var slot := 0
	var name := ""
	var team := 0
	var is_player := false
	var health := 1000.0
	var max_health := 1000.0
	## 0..100. Burst costs 50, the super / awakening 100.
	var soul := 0.0
	var guard := 100.0
	var max_guard := 100.0
	var guard_broken := false
	var knocked_out := false
	## In hitstun, air hitstun or a wall splat: Soul Burst is possible (with 50 Soul).
	var burst_window := false
	## The skill bar, in slot order.
	var skills: Array[Skill] = []
	## Super / awakening: name and the action that casts it.
	var awakening_name := ""
	var awakening_action: StringName
	## Dash charges (dash_max 0 = no dash pips) and progress of the recharging one, 0..1.
	var dash_charges := 0
	var dash_max := 0
	var dash_recharge := 0.0
	var dash_action: StringName
	## Soul Burst is cast with the dash button (true) or the awakening button (false).
	var burst_on_dash := false


var fighters: Array[Fighter] = []
var round_number := 1
var rounds_to_win := 2
## Rounds won so far, per team.
var round_wins: Array[int] = [0, 0]
## Negative means no timer.
var seconds_left := 99.0

class_name FighterPose
extends RefCounted
## What a fighter model should look like this render frame: one clip at a time, plus
## procedural root offsets that fill the reactions KayKit has no clips for (launch tumble,
## wall splat, guard-break wobble...). Built by FighterPoser from sim state.

## Clip in the shared KayKit library and the time into it (seconds).
var clip: StringName = &"Idle"
var time: float = 0.0
## Identifies the pose source; a change starts a crossfade of `fade` seconds.
var key: String = ""
var fade: float = 0.12
## Root rotation around the hips (radians): pitch > 0 leans forward, roll > 0 leans right,
## yaw spins around the vertical axis.
var pitch: float = 0.0
var roll: float = 0.0
var yaw: float = 0.0
## Root offsets in meters: lift up, forward along facing.
var lift: float = 0.0
var forward: float = 0.0
## Positional jitter amount (charge tremble, stagger), 0..1.
var shake: float = 0.0
## Weapon trail on (attack active frames and their follow-through).
var trail: bool = false


func set_clip(new_clip: StringName, new_time: float, new_key: String, new_fade: float) -> void:
	clip = new_clip
	time = new_time
	key = new_key
	fade = new_fade

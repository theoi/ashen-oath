class_name SimInput
extends RefCounted
## Per-tick input frame for one fighter slot, packed into one int:
## bits 0-15 buttons held this tick, bits 16-23 stick x, bits 24-31 stick z (signed bytes,
## -127..127, world space). 0 is "nothing held, stick neutral". Frames hold button *state*;
## the sim derives presses by comparing with the previous tick, so replays store only frames.

const LIGHT := 1 << 0
const HEAVY := 1 << 1
const JUMP := 1 << 2
const DODGE := 1 << 3
const GUARD := 1 << 4
const GRAB := 1 << 5
const ABILITY_1 := 1 << 6
const ABILITY_2 := 1 << 7
const ABILITY_3 := 1 << 8
const SUPER := 1 << 9
## Toggle hard lock / cycle to the next target, then unlock after the last one.
const LOCK := 1 << 10
## Cycle to the next target without unlocking (right-stick flick).
const TARGET_NEXT := 1 << 11

const BUTTON_MASK := 0xFFFF
const STICK_MAX := 127
const ABILITIES: Array[int] = [ABILITY_1, ABILITY_2, ABILITY_3]

## Bit names for debugging and replay dumps.
const NAMES: Dictionary[int, String] = {
	LIGHT: "L", HEAVY: "H", JUMP: "J", DODGE: "D", GUARD: "G", GRAB: "T",
	ABILITY_1: "A1", ABILITY_2: "A2", ABILITY_3: "A3", SUPER: "S", LOCK: "LK", TARGET_NEXT: "TN",
}


static func make(buttons: int, stick_x: int = 0, stick_z: int = 0) -> int:
	var x := clampi(stick_x, -STICK_MAX, STICK_MAX) & 0xFF
	var z := clampi(stick_z, -STICK_MAX, STICK_MAX) & 0xFF
	return (buttons & BUTTON_MASK) | (x << 16) | (z << 24)


## Quantizes a world-space x-z direction (length 0..1) into a frame.
static func from_vector(buttons: int, world_dir: Vector2) -> int:
	var v := world_dir.limit_length(1.0)
	return make(buttons, roundi(v.x * STICK_MAX), roundi(v.y * STICK_MAX))


## Stick pointing along a sim facing angle (Fx.TURN steps), full deflection.
static func toward_angle(buttons: int, angle: int) -> int:
	return make(buttons, Fx.sin_q(angle) * STICK_MAX / Fx.TRIG_ONE, Fx.cos_q(angle) * STICK_MAX / Fx.TRIG_ONE)


static func buttons_of(frame: int) -> int:
	return frame & BUTTON_MASK


static func stick_x(frame: int) -> int:
	var v := (frame >> 16) & 0xFF
	return v - 256 if v >= 128 else v


static func stick_z(frame: int) -> int:
	var v := (frame >> 24) & 0xFF
	return v - 256 if v >= 128 else v


## World-space stick as floats (x, z), for presentation and AI.
static func stick_vector(frame: int) -> Vector2:
	return Vector2(stick_x(frame), stick_z(frame)) / STICK_MAX


static func describe(frame: int) -> String:
	var parts := PackedStringArray()
	for bit: int in NAMES:
		if frame & bit:
			parts.append(NAMES[bit])
	var x := stick_x(frame)
	var z := stick_z(frame)
	if x != 0 or z != 0:
		parts.append("(%d,%d)" % [x, z])
	return " ".join(parts) if not parts.is_empty() else "-"

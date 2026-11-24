class_name SimInput
extends RefCounted
## Per-tick input frame for one fighter slot, packed into one 64-bit int (never negative):
##
## | bits  | field                                                                    |
## |-------|--------------------------------------------------------------------------|
## | 0-15  | buttons held this tick                                                   |
## | 16-23 | stick x, 24-31 stick z (signed bytes, -127..127, world space)            |
## | 32-43 | aim x, 44-55 aim z (signed 12 bits, -2047..2047, world space)            |
## | 56    | AIM_POINT: aim is an exact ground point (offset from the fighter in cm); |
## |       | otherwise aim is a direction scaled by stick deflection (2047 = full)    |
##
## 0 is "nothing held, stick neutral, no aim". Frames hold button *state*; the sim derives
## presses by comparing with the previous tick, so replays store only frames. The low 32 bits
## keep the original layout, so frames stored in a PackedInt32Array (no aim) still work.

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
const SKILL_4 := 1 << 12
const SKILL_5 := 1 << 13
const SKILL_6 := 1 << 14

## Skill-kit names for the same bits: the basic attack is LIGHT, the dash is DODGE (a dodge
## roll for fighters without FighterData.dash), the awakening is SUPER.
const BASIC := LIGHT
const DASH := DODGE
const AWAKEN := SUPER
const SKILL_1 := ABILITY_1
const SKILL_2 := ABILITY_2
const SKILL_3 := ABILITY_3

const BUTTON_MASK := 0xFFFF
const STICK_MAX := 127
const AIM_MAX := 2047
## Sim units (Fx) per aim step in AIM_POINT frames: 1 cm.
const AIM_UNIT := 100
const AIM_POINT := 1 << 56
## Skill slot buttons, slot 0..5. FighterData.abilities[i] is bound to SKILLS[i].
const SKILLS: Array[int] = [SKILL_1, SKILL_2, SKILL_3, SKILL_4, SKILL_5, SKILL_6]
const ABILITIES: Array[int] = SKILLS

## Bit names for debugging and replay dumps.
const NAMES: Dictionary[int, String] = {
	LIGHT: "L", HEAVY: "H", JUMP: "J", DODGE: "D", GUARD: "G", GRAB: "T",
	ABILITY_1: "S1", ABILITY_2: "S2", ABILITY_3: "S3", SKILL_4: "S4", SKILL_5: "S5", SKILL_6: "S6",
	SUPER: "S", LOCK: "LK", TARGET_NEXT: "TN",
}

const _AIM_MASK := 0xFFF
const _AIM_X_SHIFT := 32
const _AIM_Z_SHIFT := 44
const _AIM_BITS := (0xFFFFFF << 32) | AIM_POINT


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


## `frame` with an aim ground point `offset_m` meters (world x, z) from the fighter
## (mouse cursor on the floor). Offsets beyond ±20.47 m per axis are scaled down.
static func with_aim_point(frame: int, offset_m: Vector2) -> int:
	var cm := offset_m * 100.0
	var biggest := maxf(absf(cm.x), absf(cm.y))
	if biggest > AIM_MAX:
		cm *= AIM_MAX / biggest
	return _with_aim(frame, roundi(cm.x), roundi(cm.y)) | AIM_POINT


## `frame` with an aim direction (world x, z; length 0..1 = stick deflection), e.g. the
## right stick. A zero vector means "no aim".
static func with_aim_direction(frame: int, world_dir: Vector2) -> int:
	var v := world_dir.limit_length(1.0)
	return _with_aim(frame, roundi(v.x * AIM_MAX), roundi(v.y * AIM_MAX))


## `frame` aimed along a sim facing angle at full deflection.
static func with_aim_angle(frame: int, angle: int) -> int:
	return _with_aim(frame, Fx.sin_q(angle) * AIM_MAX / Fx.TRIG_ONE, Fx.cos_q(angle) * AIM_MAX / Fx.TRIG_ONE)


static func _with_aim(frame: int, x: int, z: int) -> int:
	var ax := clampi(x, -AIM_MAX, AIM_MAX) & _AIM_MASK
	var az := clampi(z, -AIM_MAX, AIM_MAX) & _AIM_MASK
	return (frame & ~_AIM_BITS) | (ax << _AIM_X_SHIFT) | (az << _AIM_Z_SHIFT)


## A frame read from a PackedInt32Array comes back sign-extended; this restores it.
static func normalized(frame: int) -> int:
	return frame & 0xFFFFFFFF if frame < 0 else frame


static func buttons_of(frame: int) -> int:
	return frame & BUTTON_MASK


static func stick_x(frame: int) -> int:
	var v := (frame >> 16) & 0xFF
	return v - 256 if v >= 128 else v


static func stick_z(frame: int) -> int:
	var v := (frame >> 24) & 0xFF
	return v - 256 if v >= 128 else v


## Raw aim x (cm for AIM_POINT frames, direction × 2047 otherwise).
static func aim_x(frame: int) -> int:
	var v := (frame >> _AIM_X_SHIFT) & _AIM_MASK
	return v - 4096 if v >= 2048 else v


static func aim_z(frame: int) -> int:
	var v := (frame >> _AIM_Z_SHIFT) & _AIM_MASK
	return v - 4096 if v >= 2048 else v


static func aim_is_point(frame: int) -> bool:
	return frame & AIM_POINT != 0


static func has_aim(frame: int) -> bool:
	return frame & _AIM_BITS != 0


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
	if has_aim(frame):
		parts.append("%s%d,%d" % ["@" if aim_is_point(frame) else ">", aim_x(frame), aim_z(frame)])
	return " ".join(parts) if not parts.is_empty() else "-"

class_name FighterPoser
extends RefCounted
## Maps one fighter's sim state to a FighterPose. Pure: reads the sim, never writes it, and
## keeps no history except the presentation `clock` passed in (for looping clips), so the
## pose for a given tick is always the same (replays, rollback).

const Action := FighterState.Action
## Fastest a clip's wind-up is played to fit a move's startup.
const MAX_WINDUP_SPEED := 2.6
## Follow-through speed range after the impact.
const MIN_FOLLOW_SPEED := 0.7
const MAX_FOLLOW_SPEED := 2.2
const RUN_CLIP_SPEED := 5.5
const KNOCKDOWN_FALL := 0.42
## Wave spawns rise from the floor with this clip.
const SPAWN_CLIP := &"Skeletons_Awaken_Floor"

## Clip overrides by role, for fighters whose idle/run differ (two-handed, casters, dead).
var idle_clip: StringName = &"Idle"
var run_clip: StringName = &"Running_A"
var guard_clip: StringName = &"Blocking"
var hit_clips: Array[StringName] = [&"Hit_A", &"Hit_B"]
## Optional per-fighter hook for move-specific procedural poses: a FighterModel.
var model: FighterModel


## Fills `pose` for fighter `f`. `sub` is the fraction of the current tick (0 while frozen)
## and `clock` a free-running presentation time in seconds (looping clips only).
## `hit_variant` alternates hit reactions.
func evaluate(sim: Sim, f: FighterState, pose: FighterPose, sub: float, clock: float, hit_variant: int = 0) -> void:
	var data := sim.fighter_data[f.slot]
	pose.pitch = 0.0
	pose.roll = 0.0
	pose.yaw = 0.0
	pose.lift = 0.0
	pose.forward = 0.0
	pose.shake = 0.0
	pose.trail = false
	var ticks := float(f.action_tick - 1) + sub
	var secs := ticks / 60.0
	match f.action:
		Action.IDLE, Action.RECOVER:
			_locomotion(f, data, pose, clock)
		Action.JUMP_SQUAT:
			var squat := maxf(1.0, float(data.jump_squat))
			pose.set_clip(&"Jump_Start", lerpf(0.15, 0.45, clampf(ticks / squat, 0.0, 1.0)), "squat", 0.05)
		Action.AIR:
			var rising := f.vel.y > 0
			pose.set_clip(&"Jump_Idle", fposmod(clock, FighterClips.length(&"Jump_Idle")), "air", 0.12)
			pose.pitch = deg_to_rad(8.0 if rising else -4.0)
		Action.LAND:
			var land_len := maxf(1.0, float(f.action_len))
			pose.set_clip(&"Jump_Land", clampf(ticks / land_len, 0.0, 1.0) * 0.45, "land", 0.05)
		Action.DODGE:
			_dodge(f, data, pose, ticks, false)
		Action.AIR_DODGE:
			_dodge(f, data, pose, ticks, true)
		Action.GUARD:
			if ticks < 6.0:
				pose.set_clip(&"Block", 0.1 + ticks / 60.0 * 2.0, "guard", 0.05)
			else:
				pose.set_clip(guard_clip, fposmod(clock, FighterClips.length(guard_clip)), "guard_hold", 0.1)
		Action.BLOCKSTUN:
			var total := maxf(1.0, ticks + float(f.stun))
			pose.set_clip(&"Block_Hit", 0.05 + clampf(ticks / total, 0.0, 1.0) * 0.5, "blockstun%d" % hit_variant, 0.03)
			pose.forward = -0.05 * (1.0 - clampf(ticks / total, 0.0, 1.0))
		Action.ATTACK:
			_attack(sim, f, pose, sub)
		Action.HITSTUN:
			_hitstun(f, pose, ticks, hit_variant)
		Action.AIR_HITSTUN:
			_tumble(f, pose, ticks, hit_variant)
		Action.KNOCKDOWN:
			_knockdown(f, pose, ticks)
		Action.GETUP:
			var getup_len := maxf(1.0, float(f.action_len))
			var p := clampf(ticks / getup_len, 0.0, 1.0)
			pose.set_clip(&"Lie_StandUp", lerpf(0.75, 2.25, p), "getup", 0.1)
			if f.action_variant == 1:
				pose.yaw = TAU * clampf(p * 1.3, 0.0, 1.0) * 0.25
				pose.lift = -0.15 * sin(p * PI)
		Action.BURST:
			var burst_p := clampf(ticks / maxf(1.0, float(f.action_len)), 0.0, 1.0)
			pose.set_clip(&"Spellcast_Raise", lerpf(0.5, 1.1, burst_p), "burst", 0.04)
			pose.lift = 0.15 * sin(burst_p * PI)
			pose.shake = 0.4 * (1.0 - burst_p)
		Action.TECH:
			_tech(f, pose, ticks)
		Action.WALL_SPLAT:
			var splat_len := maxf(1.0, float(f.action_len if f.action_len > 0 else 30))
			var q := clampf(ticks / splat_len, 0.0, 1.0)
			pose.set_clip(hit_clips[1], 0.12, "splat", 0.03)
			pose.pitch = deg_to_rad(-18.0)
			pose.lift = -0.35 * q * q
			pose.shake = 0.6 * (1.0 - q)
		Action.GUARD_BREAK:
			var clip := hit_clips[0]
			var len := FighterClips.length(clip)
			var wobble := pingpong(secs * 0.6, len * 0.6)
			pose.set_clip(clip, 0.15 + wobble, "guard_break", 0.04)
			pose.pitch = deg_to_rad(14.0 + 4.0 * sin(secs * 9.0))
			pose.roll = deg_to_rad(9.0 * sin(secs * 5.5))
			pose.lift = -0.08
		Action.GRABBED:
			pose.set_clip(hit_clips[0], 0.18, "grabbed", 0.05)
			pose.pitch = deg_to_rad(-12.0)
			pose.lift = 0.12
			pose.shake = 0.25
		Action.KO:
			_ko(f, pose, ticks)
		Action.SPAWN:
			# Rises out of the floor: the awaken clip over the spawn frames, starting sunk in.
			var rise := clampf(ticks / maxf(1.0, float(f.action_len)), 0.0, 1.0)
			pose.set_clip(SPAWN_CLIP, rise * FighterClips.length(SPAWN_CLIP), "spawn", 0.0)
			pose.lift = -0.5 * (1.0 - smoothstep(0.0, 0.35, rise))
		_:
			_locomotion(f, data, pose, clock)
	if model != null:
		model.adjust_pose(sim, f, pose, sub)


func _locomotion(f: FighterState, data: FighterData, pose: FighterPose, clock: float) -> void:
	var vx := Fx.to_m(f.vel.x) * 60.0
	var vz := Fx.to_m(f.vel.z) * 60.0
	var speed := sqrt(vx * vx + vz * vz)
	if speed < 0.5:
		pose.set_clip(idle_clip, fposmod(clock, FighterClips.length(idle_clip)), "idle", 0.18)
		return
	var face := Fx.angle_to_rad(f.facing)
	var fwd := Vector2(sin(face), cos(face))
	var dir := Vector2(vx, vz) / speed
	var along := fwd.dot(dir)
	var side := fwd.x * dir.y - fwd.y * dir.x
	var rate := speed / RUN_CLIP_SPEED
	var clip := run_clip
	var key := "run"
	if along < -0.5:
		clip = &"Walking_Backwards"
		key = "back"
		rate *= 1.6
	elif absf(side) > 0.7 and along < 0.5:
		clip = &"Running_Strafe_Left" if side < 0.0 else &"Running_Strafe_Right"
		key = "strafe%d" % signi(int(side * 10.0))
	var len := FighterClips.length(clip)
	pose.set_clip(clip, fposmod(clock * rate, len), key, 0.15)
	pose.pitch = deg_to_rad(6.0) * clampf(speed / maxf(1.0, data.run_speed), 0.0, 1.0) if key == "run" else 0.0


## Which way a roll goes relative to facing: 0 forward, 1 right, 2 back, 3 left.
static func relative_quadrant(facing: int, direction: int) -> int:
	var diff := Fx.angle_diff(facing, direction)
	var quarter := Fx.TURN / 4
	var q := int(roundf(float(diff) / float(quarter)))
	return posmod(q, 4)


func _dodge(f: FighterState, data: FighterData, pose: FighterPose, ticks: float, air: bool) -> void:
	var clips: Array[StringName] = [&"Dodge_Forward", &"Dodge_Left", &"Dodge_Backward", &"Dodge_Right"]
	var quadrant := relative_quadrant(f.facing, f.move_dir)
	var frames := float(maxi(1, data.air_dodge_frames if air else data.dodge_move_frames))
	var p := clampf(ticks / frames, 0.0, 1.0)
	pose.set_clip(clips[quadrant], p * FighterClips.length(clips[quadrant]), "dodge%d%s" % [quadrant, "a" if air else ""], 0.04)
	# A tucked roll: dip and lean into the roll direction while invincible.
	var tuck := sin(p * PI)
	var lean := deg_to_rad(28.0) * tuck
	match quadrant:
		0:
			pose.pitch = lean
		2:
			pose.pitch = -lean
		1:
			pose.roll = -lean
		3:
			pose.roll = lean
	pose.lift = -0.22 * tuck
	if air:
		pose.yaw = TAU * p


func _attack(sim: Sim, f: FighterState, pose: FighterPose, sub: float) -> void:
	var move := sim.current_move(f)
	var clip := attack_clip(move)
	var frame := float(f.move_frame - 1)
	if not f.charging:
		frame += sub
	pose.set_clip(clip, attack_time(move, clip, frame), "atk%d" % f.move_index, 0.05 if f.move_frame > 1 or sub > 0.0 else 0.05)
	if f.charging:
		pose.shake = 0.35 + 0.4 * clampf(float(f.charge) / maxf(1.0, float(move.charge_max)), 0.0, 1.0)
	pose.trail = frame >= float(move.startup - 2) and frame <= float(move.last_active_frame() + 4)


## The clip a move plays (its `animation`, else a default by kind).
static func attack_clip(move: MoveData) -> StringName:
	if move.animation != &"" and FighterClips.has(move.animation):
		return move.animation
	match move.kind:
		MoveData.Kind.HEAVY:
			return &"1H_Melee_Attack_Chop"
		MoveData.Kind.AIR_LIGHT:
			return &"1H_Melee_Attack_Slice_Horizontal"
		MoveData.Kind.AIR_HEAVY:
			return &"1H_Melee_Attack_Jump_Chop"
		MoveData.Kind.GRAB:
			return &"Unarmed_Melee_Attack_Punch_A"
		MoveData.Kind.THROW:
			return &"Throw"
		MoveData.Kind.SUPER:
			return &"Spellcast_Summon"
		MoveData.Kind.ABILITY:
			return &"1H_Melee_Attack_Stab"
	return &"1H_Melee_Attack_Slice_Diagonal"


## Clip time for move frame `frame` (0-based, fractional): the wind-up is fitted to the
## startup so the clip's impact lands on the first active frame, then the follow-through
## plays over active + recovery at a clamped speed.
static func attack_time(move: MoveData, clip: StringName, frame: float) -> float:
	var length := FighterClips.length(clip)
	var impact := minf(FighterClips.impact(clip), length)
	var windup_frames := float(maxi(0, move.startup - 1))
	var start := maxf(0.0, impact - windup_frames / 60.0 * MAX_WINDUP_SPEED)
	if frame < windup_frames:
		return lerpf(start, impact, frame / windup_frames)
	var after := frame - windup_frames
	var rest_frames := float(maxi(1, move.active + move.recovery))
	var speed := clampf((length - impact) / (rest_frames / 60.0), MIN_FOLLOW_SPEED, MAX_FOLLOW_SPEED)
	return minf(length, impact + after / 60.0 * speed)


func _hitstun(f: FighterState, pose: FighterPose, ticks: float, variant: int) -> void:
	var clip := hit_clips[variant % hit_clips.size()]
	var total := maxf(1.0, ticks + float(f.stun))
	var p := clampf(ticks / total, 0.0, 1.0)
	pose.set_clip(clip, p * FighterClips.length(clip) * 0.9, "hit%d" % variant, 0.03)
	var recoil := (1.0 - p) * (1.0 - p)
	pose.pitch = deg_to_rad(-14.0) * recoil
	pose.forward = -0.08 * recoil


## Launch / air hitstun: an arched body that rotates with its vertical speed, so rising is
## head-up and falling tips toward lying on the back.
func _tumble(f: FighterState, pose: FighterPose, ticks: float, variant: int) -> void:
	pose.set_clip(hit_clips[1], 0.22, "tumble", 0.05)
	var vy := Fx.to_m(f.vel.y) * 60.0
	var t := clampf(0.5 - vy / 16.0, 0.0, 1.0)
	pose.pitch = deg_to_rad(lerpf(-25.0, -100.0, t))
	pose.roll = deg_to_rad(8.0 * sin(ticks * 0.15 + float(variant)))
	pose.lift = 0.35 * sin(t * PI)


func _knockdown(f: FighterState, pose: FighterPose, ticks: float) -> void:
	var fall := clampf(ticks / 18.0, 0.0, 1.0)
	pose.set_clip(&"Death_A", lerpf(KNOCKDOWN_FALL, FighterClips.length(&"Death_A") - 0.01, fall), "down", 0.1)
	if fall < 1.0:
		pose.lift = 0.08 * sin(fall * PI)


func _tech(f: FighterState, pose: FighterPose, ticks: float) -> void:
	var len := maxf(1.0, float(f.action_len if f.action_len > 0 else 20))
	var p := clampf(ticks / len, 0.0, 1.0)
	if f.action_variant == 1 or (f.action_variant == 0 and f.grounded):
		var clips: Array[StringName] = [&"Dodge_Forward", &"Dodge_Left", &"Dodge_Backward", &"Dodge_Right"]
		var q := relative_quadrant(f.facing, f.move_dir)
		pose.set_clip(clips[q], p * 0.4, "tech%d" % q, 0.04)
		pose.lift = -0.2 * sin(p * PI)
	else:
		pose.set_clip(&"Jump_Idle", 0.3, "airtech", 0.04)
		# Air tech flips backwards; the juggle-limit flip-out turns forwards.
		pose.pitch = (TAU if f.action_variant == 3 else -TAU) * clampf(p * 1.4, 0.0, 1.0)


func _ko(f: FighterState, pose: FighterPose, ticks: float) -> void:
	var clip := &"Death_A"
	pose.set_clip(clip, minf(ticks / 60.0 * 0.8, FighterClips.length(clip) - 0.01), "ko", 0.06)
	if not f.grounded:
		pose.pitch = deg_to_rad(-60.0)

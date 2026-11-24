class_name FighterClips
extends RefCounted
## The shared KayKit animation set and timing facts about its clips.
##
## Every KayKit Adventurers / Skeletons model uses the same 41-bone rig ("Rig/Skeleton3D"),
## so one AnimationLibrary (taken from Skeleton_Warrior.glb, the only model imported with
## animations: it has all 95 clips) drives every fighter.

const SOURCE := "res://assets/kaykit-skeletons/Skeleton_Warrior.glb"

## Seconds into the clip where the swing connects (peak weapon-hand speed, measured from
## the clips at 60 Hz). Moves map their first active frame onto this moment.
const IMPACT: Dictionary[StringName, float] = {
	&"1H_Melee_Attack_Chop": 0.58,
	&"1H_Melee_Attack_Jump_Chop": 0.73,
	&"1H_Melee_Attack_Slice_Diagonal": 0.38,
	&"1H_Melee_Attack_Slice_Horizontal": 0.25,
	&"1H_Melee_Attack_Stab": 0.38,
	&"2H_Melee_Attack_Chop": 0.82,
	&"2H_Melee_Attack_Slice": 0.38,
	&"2H_Melee_Attack_Spin": 1.17,
	&"2H_Melee_Attack_Spinning": 0.27,
	&"2H_Melee_Attack_Stab": 0.38,
	&"Dualwield_Melee_Attack_Chop": 0.55,
	&"Dualwield_Melee_Attack_Slice": 0.55,
	&"Dualwield_Melee_Attack_Stab": 0.38,
	&"Block_Attack": 0.35,
	&"Unarmed_Melee_Attack_Kick": 0.33,
	&"Unarmed_Melee_Attack_Punch_A": 0.43,
	&"Unarmed_Melee_Attack_Punch_B": 0.48,
	&"Throw": 0.72,
	&"Spellcast_Shoot": 0.3,
	&"Spellcast_Raise": 0.75,
	&"Spellcast_Long": 1.2,
	&"Spellcast_Summon": 2.9,
	&"1H_Ranged_Shoot": 0.12,
	&"2H_Ranged_Shoot": 0.12,
	&"Interact": 0.35,
	&"PickUp": 0.55,
	&"Taunt": 0.65,
	&"Cheer": 0.4,
	&"Jump_Start": 0.45,
	&"Hit_A": 0.1,
	&"Hit_B": 0.1,
}

const LOOPED: Array[StringName] = [
	&"Idle", &"Idle_B", &"Idle_Combat", &"2H_Melee_Idle", &"Unarmed_Idle",
	&"Running_A", &"Running_B", &"Running_C", &"Running_Strafe_Left", &"Running_Strafe_Right",
	&"Walking_A", &"Walking_B", &"Walking_C", &"Walking_Backwards", &"Walking_D_Skeletons",
	&"Blocking", &"Jump_Idle", &"Lie_Idle", &"Spellcasting", &"2H_Melee_Attack_Spinning",
	&"1H_Ranged_Aiming", &"2H_Ranged_Aiming", &"Sit_Floor_Idle", &"Sit_Chair_Idle",
]

## Clips whose hips travel sideways; the sim moves the fighter, so this travel is removed.
const IN_PLACE: Array[StringName] = [
	&"Dodge_Backward", &"Dodge_Forward", &"Dodge_Left", &"Dodge_Right",
	&"Running_C", &"Lie_StandUp", &"Sit_Floor_StandUp", &"Skeletons_Awaken_Standing",
]

## The shared library (loaded once, loop modes and in-place fixes applied).
static func library() -> AnimationLibrary:
	return TreeCache.get_or_make(&"fighter_clips_library", _load_library)


static func _load_library() -> AnimationLibrary:
	var scene: PackedScene = load(SOURCE)
	var instance := scene.instantiate()
	var player: AnimationPlayer = instance.find_child("AnimationPlayer", true, false)
	var lib := player.get_animation_library(&"")
	instance.free()
	for clip in LOOPED:
		if lib.has_animation(clip):
			lib.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	for clip in IN_PLACE:
		if lib.has_animation(clip):
			_pin_hips(lib.get_animation(clip))
	return lib


static func length(clip: StringName) -> float:
	var lib := library()
	return lib.get_animation(clip).length if lib.has_animation(clip) else 1.0


static func has(clip: StringName) -> bool:
	return library().has_animation(clip)


## Seconds into `clip` where its hit lands (or 40% of the clip when not measured).
static func impact(clip: StringName) -> float:
	if IMPACT.has(clip):
		return IMPACT[clip]
	return length(clip) * 0.4


static func is_looped(clip: StringName) -> bool:
	return clip in LOOPED


## Keeps the hips over the root on x/z (drops the clip's travel, keeps its bob).
static func _pin_hips(anim: Animation) -> void:
	var track := anim.find_track(NodePath("Rig/Skeleton3D:hips"), Animation.TYPE_POSITION_3D)
	if track < 0 or anim.track_get_key_count(track) == 0:
		return
	var first: Vector3 = anim.track_get_key_value(track, 0)
	for k in anim.track_get_key_count(track):
		var v: Vector3 = anim.track_get_key_value(track, k)
		anim.track_set_key_value(track, k, Vector3(first.x, v.y, first.z))

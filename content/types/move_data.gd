class_name MoveData
extends Resource
## One move: frame data, hitboxes, motion, spawned effects, cancels, armor and invincibility.
##
## Frames count from 1 = the tick the move starts. Frame `startup` is the first active frame
## (fighting-game convention: "startup 5" hits on frame 5). Active frames are
## startup .. startup + active - 1, then `recovery` frames. Total = startup - 1 + active + recovery.

enum Kind { LIGHT, HEAVY, AIR_LIGHT, AIR_HEAVY, GRAB, THROW, ABILITY, SUPER, GETUP_ATTACK, BURST }

enum SkillType { TAP, HOLD, CHARGE, COMBO, CHAIN, DASH_STRIKE, STANCE }

## How the move picks its direction (see Sim.aim_point for how the aim is resolved).
enum Aim {
	## Face the lock-on / soft-lock target, else the stick; track the target during startup.
	AUTO,
	## Snap to face the aim on frame 1, then track the current aim during startup at
	## `tracking` degrees per frame.
	DIRECTION,
	## Face the aim point (clamped to `max_range`) on frame 1 and keep it in move_point for
	## TARGET-anchored effects, AIM_POINT teleports and aim_travel motions (leaps). No tracking.
	GROUND_TARGET,
	## Centered on the caster; snaps to face the aim like DIRECTION.
	SELF,
	## Like GROUND_TARGET, for moves that travel to the point (MotionData.aim_travel STOP_AT).
	DASH_TO,
}

@export var id: StringName = &""
@export var kind: Kind = Kind.LIGHT
@export var startup: int = 6
@export var active: int = 3
@export var recovery: int = 12
@export var hitboxes: Array[HitboxData] = []
@export var motions: Array[MotionData] = []
@export var effects: Array[EffectData] = []
@export var teleport: TeleportData
## Degrees per frame the fighter turns toward its target during startup. -1 = by kind.
@export var tracking: float = -1.0
## Maximum targets one hitbox group can hit per frame (0 = any number).
@export var max_targets: int = 0

@export_group("Aim")
@export var aim: Aim = Aim.AUTO
## GROUND_TARGET / DASH_TO: farthest aim point from the caster, meters.
@export var max_range: float = 8.0

@export_group("Skill")
## What kind of skill this is, for the HUD and AI; behavior comes from the other fields.
@export var skill_type: SkillType = SkillType.TAP
## Combo: re-pressing the same slot within `follow_up_window` frames of this part's first
## hit casts this move (part 2, 3...). Parts ignore the cooldown; the slot's cooldown (the
## first part's) starts when the last part is cast or the window runs out.
@export var follow_up: StringName = &""
@export var follow_up_window: int = 30
## Chain: after this skill hits (hitboxes or its effects), the slot casts `chain_move` for
## `chain_frames`; cooldown as for combos.
@export var chain_move: StringName = &""
@export var chain_frames: int = 180
## Hits every enemy carrying this fighter's mark (HitData.mark), at any distance, on
## `mark_frame` (-1 = startup), and clears those marks.
@export var mark_hit: HitData
@export var mark_frame: int = -1

@export_group("Hold")
## Channel frames: the move advances through them while the slot's button is held;
## releasing at or after `hold_start` jumps to `hold_end + 1` (the tail). 0 = not a hold.
@export var hold_start: int = 0
@export var hold_end: int = 0
## Stick steering while channeling, percent of run speed (0 = rooted).
@export var hold_steer_percent: int = 0

@export_group("Stance")
## The first hit from within `stance_arc` degrees of facing during the window is absorbed
## (melee, projectiles, grabs) and `counter_move` starts at once.
@export var stance_start: int = 0
@export var stance_end: int = 0
@export var stance_arc: float = 180.0
## Freeze on both fighters when the stance absorbs a hit (-1 = CombatRules.stance_hitstop).
@export var stance_hitstop: int = -1
@export var counter_move: StringName = &""

@export_group("Strings and cancels")
## Move id started by pressing light/heavy from the end of the active frames on.
@export var next_light: StringName = &""
@export var next_heavy: StringName = &""
## Extra cancel windows. Lights and heavies get an ability cancel on contact by default;
## abilities get a super cancel on hit (CombatRules).
@export var cancels: Array[CancelData] = []
## First frame another skill or the awakening can cancel this move. -1 = default (basics 1,
## awakening / throws / burst never, others the frame after the last active frame); 0 = never.
@export var skill_cancel_from: int = -1
## First frame a dash can cancel this move (skill-kit fighters). -1 = default (1; awakening,
## throws and burst never); 0 = never.
@export var dash_cancel_from: int = -1
@export var no_dash_cancel: bool = false

@export_group("Defense")
## Fully invincible frames (inclusive, 0 = none).
@export var invuln_start: int = 0
@export var invuln_end: int = 0
## Hits absorbed on armor frames; the fighter keeps acting and takes armor_damage_percent.
@export var armor_start: int = 0
@export var armor_end: int = 0
@export var armor_hits: int = 0
@export var armor_damage_percent: int = 100
## Super armor windows with no hit cap and full damage. Flinch immune ignores STAGGER
## reactions; push immune ignores every reaction, push, pull, carry, grab and wall splat.
## ⚡Counters and boss stagger breaks go through both.
@export var flinch_immune_start: int = 0
@export var flinch_immune_end: int = 0
@export var push_immune_start: int = 0
@export var push_immune_end: int = 0
## Frames in which a ⚡Counter hit interrupts this move (the blue flash).
@export var counter_window_start: int = 0
@export var counter_window_end: int = 0
## Invincible to projectiles only on these frames.
@export var projectile_invuln_start: int = 0
@export var projectile_invuln_end: int = 0

@export_group("Air")
## Starts in the air; ends on landing with `landing_recovery`.
@export var aerial: bool = false
## Landing recovery when landing during the move (0 = CombatRules.landing_frames, or the
## whiff landing when no hit connected).
@export var landing_recovery: int = 0
## May be used while airborne (abilities like blinks).
@export var air_ok: bool = false
## Stays usable on the ground too when air_ok is set.
@export var ground_ok: bool = true
## Gravity scale in percent while airborne during the move (0 = hover).
@export var gravity_percent: int = 100

@export_group("Charge")
## Holding the button at `charge_frame` pauses the move for up to `charge_max` frames.
@export var chargeable: bool = false
@export var charge_frame: int = 8
@export var charge_max: int = 40
## Damage bonus at full charge, in percent (linear in charge time).
@export var charge_damage_percent: int = 50
## At full charge the hit breaks guard.
@export var full_charge_guard_break: bool = true
## Charge levels: charge frames at which L1, L2... start. Empty = the linear bonus above.
## Reaching `charge_max` while held auto-releases at the top normal level.
@export var charge_levels: PackedInt32Array = PackedInt32Array()
## Damage percent per level from L1 (missing = 100).
@export var charge_level_damage_percent: PackedInt32Array = PackedInt32Array()
## Releasing by hand with charge in [perfect_start, perfect_end] is a perfect release.
@export var perfect_start: int = 0
@export var perfect_end: int = 0
@export var perfect_damage_percent: int = 100
## Weight and stagger of this move's hits after a perfect release (AUTO / -1 = unchanged).
@export var perfect_weight: HitData.Weight = HitData.Weight.AUTO
@export var perfect_stagger: int = -1
## Cast instead when released before L1 (a weaker version).
@export var early_release_move: StringName = &""

@export_group("Resources")
## Ability cooldown in frames (abilities only).
@export var cooldown: int = 0
## Soul cost in whole points (supers 100, burst 50).
@export var soul_cost: int = 0
## Super flash freeze frames before the move runs (supers).
@export var flash_frames: int = 0

@export_group("Throws")
## For grabs: the THROW move played on the held victim after a successful grab.
@export var throw_move: StringName = &""
## The victim can tech by pressing grab within CombatRules.grab_tech_window.
@export var techable: bool = true
## Distance in meters the victim is held in front of the thrower.
@export var hold_distance: float = 0.9

@export_group("Effects on self")
## Buff applied to the user on this frame (0 = never).
@export var buff_frame: int = 0
@export var buff: BuffData

@export_group("Presentation")
@export var animation: StringName = &""
@export var cue: StringName = &""


func total_frames() -> int:
	return startup - 1 + active + recovery


func last_active_frame() -> int:
	return startup + active - 1


func is_ability() -> bool:
	return kind == Kind.ABILITY


func in_window(frame: int, start: int, end: int) -> bool:
	return end > 0 and frame >= start and frame <= end


func is_aimed() -> bool:
	return aim != Aim.AUTO


## The aim point is fixed on frame 1 (ground targets and dash-to moves).
func aims_at_point() -> bool:
	return aim == Aim.GROUND_TARGET or aim == Aim.DASH_TO


func is_basic() -> bool:
	return kind == Kind.LIGHT or kind == Kind.HEAVY or kind == Kind.AIR_LIGHT \
			or kind == Kind.AIR_HEAVY or kind == Kind.GETUP_ATTACK

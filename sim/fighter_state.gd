class_name FighterState
extends SimRecord
## One fighter's simulation state. Plain integers (see SimRecord and Fx for units).
## Presentation and AI read these fields; only the Sim writes them.

enum Action {
	## Grounded and actionable: standing or running.
	IDLE,
	JUMP_SQUAT,
	## Airborne and actionable (after a jump or air tech).
	AIR,
	## Landing recovery.
	LAND,
	DODGE,
	AIR_DODGE,
	## Holding guard (guard is up after CombatRules.guard_startup frames).
	GUARD,
	BLOCKSTUN,
	## Executing a move (see move_index / move_frame).
	ATTACK,
	## Grounded hitstun or stagger (parried attackers too).
	HITSTUN,
	## Launched or hit in the air: juggleable until landing or air tech.
	AIR_HITSTUN,
	## On the ground after a fall: only OTG moves hit.
	KNOCKDOWN,
	## Standing up or get-up roll (invincible early).
	GETUP,
	## Air tech or ground tech roll (invincible early).
	TECH,
	WALL_SPLAT,
	GUARD_BREAK,
	## Held by a throw; see grab_partner.
	GRABBED,
	## Neutral recovery with no combo (after a grab tech).
	RECOVER,
	KO,
	## Soul Burst: invincible, pushes enemies away, ends the combo.
	BURST,
	## Skill-kit dash (FighterData.dash).
	DASH,
	## Interrupted by a ⚡Counter during a counter window.
	COUNTER_STUN,
	## Boss stagger bar broken: kneeling, hittable, does not react, takes extra damage.
	STAGGERED,
}

var slot: int = 0
var team: int = 0
var pos: Vector3i = Vector3i.ZERO
## Own velocity in units per tick (x, z from running or moves; y vertical).
var vel: Vector3i = Vector3i.ZERO
## External horizontal push (knockback, pushback) applied while knock_ticks > 0.
var knock: Vector3i = Vector3i.ZERO
var knock_ticks: int = 0
var facing: int = 0
var grounded: bool = true

var action: Action = Action.IDLE
## Ticks spent in the current action; 1 on the tick it starts.
var action_tick: int = 0
## Planned length of timed actions (dodge, stun, landing, get-up), 0 if open-ended.
var action_len: int = 0
## Direction (Fx angle) of rolls, techs and dashes.
var move_dir: int = 0
## Sub-kind of the action: GETUP 0 stand / 1 roll; TECH 1 ground roll / 2 air tech /
## 3 juggle-limit flip.
var action_variant: int = 0

## Current move (index into FighterData.moves), -1 when not attacking.
var move_index: int = -1
## Frame of the current move, 1 on the tick it starts.
var move_frame: int = 0
## SimInput bit that started the move (held to charge).
var move_button: int = 0
## 0 = no contact yet, 1 = blocked/armored/parried, 2 = hit.
var move_contact: int = 0
## Counts every move started; the current move's cast id (buff uses are spent per cast).
var move_cast: int = 0
## World point (y = 0) an aimed move targets (MoveData.aim other than AUTO), set on frame 1.
var move_point: Vector3i = Vector3i.ZERO
## Per hitbox group (0-7): bitmask of slots already hit by this move.
var move_hit_masks: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
## Frames the move has been held at its charge frame.
var charge: int = 0
var charging: bool = false
var armor_left: int = 0
## Landing recovery queued when an aerial lands.
var landing_recovery: int = 0

## Both fighters freeze while > 0 (counts down).
var hitstop: int = 0
## Remaining hitstun / blockstun / stagger frames.
var stun: int = 0
## Generic invincibility frames left (techs, get-ups, bursts).
var invuln: int = 0

var hp: int = 1000
var max_hp: int = 1000
## Soul in hundredths of a point (0..10000).
var soul: int = 0
## Guard gauge in hundredths (0..10000).
var guard: int = 10000
## Ticks since the last blocked hit (guard regenerates after CombatRules.guard_regen_delay).
var guard_idle: int = 0
## After a guard break, the next hit is a counter hit.
var guard_broken: bool = false
## Frames left in the current parry window.
var parry_timer: int = 0
var parry_lockout: int = 0
## Skill cooldowns in frames left, one per skill slot, and their length when they started.
var cooldowns: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])
var cooldown_totals: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])
## Charges left per skill slot for charged skills (MoveData.charges ≥ 2), else 0.
var skill_charges: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])
## Skill slot (0-5) that started the current move, -1 for other moves.
var move_slot: int = -1
## Per skill slot: the move index the slot casts now (combo/chain part, -1 = its skill),
## frames left in the slot's sequence (follow-up window, or waiting for the hit), the
## cooldown waiting for the sequence to end, and the move index of the last part cast.
var skill_next: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1, -1, -1])
var skill_window: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])
var skill_pending: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])
var skill_part: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1, -1, -1])
## Charge level reached on release (0 = below L1) and whether it was a perfect release.
var charge_level: int = 0
var charge_perfect: bool = false
## Per slot: frames left on the mark (brand) that slot's fighter put on this one.
var marks: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
## Skill-kit dash charges and frames until the next charge comes back (0 = full).
var dash_charges: int = 0
var dash_recharge: int = 0
## Boss stagger bar (0 max = none).
var stagger: int = 0
var stagger_max: int = 0

## Input frame bits held this tick, bits newly pressed this tick, and the stick.
var buttons: int = 0
var pressed: int = 0
var stick_x: int = 0
var stick_z: int = 0
## Aim from the input frame (SimInput.aim_x/aim_z; aim_point set for cursor points).
var aim_x: int = 0
var aim_z: int = 0
var aim_point: bool = false
## Buffered button (one SimInput bit) and its age in frames.
var buffer: int = 0
var buffer_age: int = 0
## Frames since dodge was last pressed (tech roll timing).
var dodge_age: int = 999

var hard_lock: bool = false
## Current target slot (hard lock, else nearest enemy), -1 if none.
var target: int = -1
var jumps_used: int = 0
var air_dodge_used: bool = false
var dodge_lockout: int = 0
var perfect_dodge_used: bool = false

## Combo state as a victim (per victim, so scaling is per victim in 1v2).
var combo_hits: int = 0
var combo_damage: int = 0
## Combo clock (CombatRules.combo_decay_frames / combo_max_frames): stun ticks outside
## hitstop plus short free gaps; reset after combo_reset_frames free ticks in a row.
var combo_ticks: int = 0
var combo_free_ticks: int = 0
var juggle_used: int = 0
var wall_splat_used: bool = false
var last_attacker: int = -1
## Set by a wall_splat hit while its knockback (or carry) lasts; a wall contact splats.
var splat_armed: bool = false
var splat_bonus: int = 0
## Pending ground bounce height (units) applied on landing after a spike.
var bounce_pending: int = 0

## Throw partner slot (victim for the thrower, thrower for the victim), -1 if none.
var grab_partner: int = -1
## Frames the grabbed fighter has left to tech the grab (0 = not techable / expired).
var grab_tech_left: int = 0
## Frames left being carried by a dash (victim side).
var carried_ticks: int = 0
var carried_by: int = -1

## Frames left rooted (HitData.root_frames).
var rooted: int = 0
## Channel-break gauge points left and its size (MoveData.channel_gauge; 0 = none showing).
var channel: int = 0
var channel_max: int = 0
## Frames until counter windows show again (SlotConfig.counter_window_cooldown), and
## whether the current move's counter window is suppressed.
var counter_cooldown: int = 0
var counter_blocked: bool = false

var ko: bool = false
## Storage for the fighter's FighterTrait script (stored charges and similar).
var vars: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
var buffs: Array[BuffState] = []


func is_airborne() -> bool:
	return not grounded


func soul_points() -> int:
	return soul / 100


func guard_points() -> int:
	return guard / 100


func is_attacking() -> bool:
	return action == Action.ATTACK


## True in states that can be juggled / comboed (hitstun of any kind).
func in_hitstun() -> bool:
	return action == Action.HITSTUN or action == Action.AIR_HITSTUN or action == Action.WALL_SPLAT \
			or action == Action.GUARD_BREAK or action == Action.COUNTER_STUN or action == Action.STAGGERED

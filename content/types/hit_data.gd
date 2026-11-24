class_name HitData
extends Resource
## What a hit does to its victim. Shared by move hitboxes, effects (projectiles, eruptions)
## and arena hazards. Distances are meters, durations are 60 Hz frames. A value of -1 means
## "use the CombatRules default for this move kind".

enum Reaction {
	## Grounded hitstun; airborne victims stay airborne (juggle).
	STAGGER,
	## Victim falls to the ground (KNOCKDOWN), e.g. sweeps and running lights.
	KNOCKDOWN,
	## Vertical launch; the victim becomes juggleable.
	LAUNCH,
	## Airborne victims are spiked into a ground bounce (relaunch); grounded victims knock down.
	GROUND_BOUNCE,
	## Pulls the victim to `pull_distance` in front of the attacker (chain hook).
	PULL,
}

## Impact class: default hitstop (CombatRules.weight_hitstop) and boss stagger
## (weight_stagger); presentation scales shake, rumble and numbers by it. AUTO = the old
## per-kind hitstop. TICK (hold and multi-hit ticks) comes last so saved values keep their meaning.
enum Weight { AUTO, BASIC, LIGHT, MEDIUM, HEAVY, MASSIVE, TICK }

@export var damage: int = 40
@export var weight: Weight = Weight.AUTO
## Boss stagger gauge drain (-1 = by weight).
@export var stagger: int = -1
## A ⚡Counter: inside the victim's counter window it beats armor and counter-stuns.
@export var counter: bool = false
## Brands the victim for `mark_frames` (MoveData.mark_hit detonates brands).
@export var mark: bool = false
@export var mark_frames: int = 180
## Percent of damage dealt through guard. -1 = by move kind (basic 0, ability 12, super 20).
@export var chip_percent: int = -1
## Frames of hitstun after hitstop. Counter hits add CombatRules.counter_hitstun_percent.
@export var hitstun: int = 16
## Frames of blockstun after hitstop.
@export var blockstun: int = 10
## Frames both fighters freeze on contact. -1 = by move kind.
@export var hitstop: int = -1
## Guard gauge drained on block. -1 = by move kind.
@export var guard_damage: int = -1
@export var reaction: Reaction = Reaction.STAGGER
## Horizontal push away from the attacker, in meters, on hit.
@export var knockback: float = 0.4
## Horizontal push on block, in meters.
@export var block_pushback: float = 0.3
## Launch apex in meters (LAUNCH, GROUND_BOUNCE, or any hit on an airborne victim). Scaled
## by the victim's weight. 0 keeps airborne victims on their current arc with a small pop.
@export var launch_height: float = 0.0
## Juggle points this hit costs when the victim is airborne.
@export var juggle_cost: int = 1
## Can hit knocked-down victims.
@export var otg: bool = false
## Ignores guard (still parryable unless `throw`).
@export var unblockable: bool = false
## Breaks guard instantly when blocked.
@export var guard_break: bool = false
## Strong knockback into a wall splats the victim (once per combo).
@export var wall_splat: bool = false
## Extra damage when this hit causes a wall splat.
@export var wall_splat_bonus: int = 0
## PULL: final distance in front of the attacker, in meters.
@export var pull_distance: float = 1.2
## Frames the victim is carried in front of the attacker (dashes that drag the target).
## Hitting a wall while carried causes a wall splat if `wall_splat` is set.
@export var carry_frames: int = 0
## A grab: unblockable, only hits grounded victims, starts the move's throw sequence.
@export var throw: bool = false
## Throws normally lose to fighters in attack startup/active frames. Set for command grabs
## that only jumps and dodges beat.
@export var throw_beats_attacks: bool = false
## Roots a grounded victim for this many frames: no running, walking, dashing, rolling or
## jumping (skills still work). Launches and knockdowns clear it; armor ignores it.
@export var root_frames: int = 0
## Applied to the victim on hit and on armored hits (debuffs such as Chill use a negative
## speed_bonus_percent). One buff per BuffData.id: a second hit refreshes it.
@export var victim_buff: BuffData
## Can be parried (projectiles and melee). Throws are never parried.
@export var parryable: bool = true
## Presentation cue name for sparks/sound (events carry it).
@export var cue: StringName = &""

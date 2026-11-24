class_name EffectData
extends Resource
## Something a move spawns that lives on its own: projectiles, delayed ground eruptions,
## shockwaves, flame pillars. Its hit shape is a vertical capsule (radius, height) whose base
## sits at the effect position. Distances are meters, speeds m/s, durations frames.

enum Anchor {
	## Spawns at `offset` relative to the owner (rotated by the owner's facing).
	OWNER,
	## Spawns under the owner's current target (clamped to `max_range` from the owner).
	TARGET,
	## Spawns at `offset` from where the owner's last teleport started (Grave Echo).
	TELEPORT_ORIGIN,
}

@export var id: StringName = &""
## Move frame on which the effect spawns.
@export var spawn_frame: int = 1
@export var anchor: Anchor = Anchor.OWNER
@export var offset: Vector3 = Vector3(0.0, 1.0, 1.0)
@export var max_range: float = 12.0
## Forward speed in m/s along the spawn direction (0 = stationary).
@export var speed: float = 0.0
## Spawn several copies fanned out over `spread_degrees` (e.g. 3 souls in a spread).
@export var count: int = 1
@export var spread_degrees: float = 0.0
@export var radius: float = 0.3
@export var height: float = 0.0
## Radius growth in m/s (expanding shockwaves).
@export var grow_speed: float = 0.0
## Telegraph frames before it can hit (rune on the floor, glowing grate).
@export var delay: int = 0
## Frames it can hit after the delay.
@export var lifetime: int = 60
## Maximum travel in meters (0 = limited by lifetime only).
@export var travel: float = 0.0
@export var hit: HitData
## Beams: the hit shape is a horizontal capsule `radius` thick running `length` meters
## from the effect position along its facing (0 = the vertical capsule above).
@export var length: float = 0.0
## Stays on its owner: every tick it moves to the owner's position + `offset` (rotated by
## the effect's facing) and ends when the cast that spawned it ends. `speed` is ignored.
@export var attach_to_owner: bool = false
## Attached effects turn toward the owner's aim at this many degrees per frame (0 = follow
## the owner's facing).
@export var aim_turn_rate: float = 0.0
## Moving effects turn toward the owner's target (else the nearest enemy) at this many
## degrees per frame (awakening lances). 0 = straight.
@export var homing_turn_rate: float = 0.0
## Spawns only after a perfect charge release.
@export var requires_perfect: bool = false
## Hits per target; each target is hit at most this many times, `hit_interval` frames apart.
@export var hits_per_target: int = 1
@export var hit_interval: int = 10
## Removed after its first hit or block.
@export var destroy_on_contact: bool = true
## Destroyed by enemy attack hitboxes (and by parries/blocks with destroys_projectiles).
@export var destroyable: bool = true
## Stopped by arena walls and obstacles that block projectiles.
@export var blocked_by_walls: bool = true
## Hits are treated as a projectile for guard and parry (blockable from the front only).
@export var projectile: bool = true
## Presentation hints (sim ignores them).
@export var scene: String = ""
@export var cue: StringName = &""

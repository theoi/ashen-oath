class_name SimEvent
extends RefCounted
## One thing that happened during a tick, for presentation (sparks, sound, camera, HUD).
## Events are output only: they are not sim state and are rebuilt when ticks are re-run.

enum Type {
	MOVE_START,
	HIT,
	BLOCK,
	PARRY,
	GUARD_BREAK,
	ARMOR,
	WHIFF_PARRY,
	GRAB,
	GRAB_TECH,
	THROW_RELEASE,
	LAUNCH,
	WALL_SPLAT,
	KNOCKDOWN,
	AIR_TECH,
	TECH_ROLL,
	GET_UP,
	JUGGLE_LIMIT,
	JUMP,
	LAND,
	DODGE,
	PERFECT_DODGE,
	TELEPORT,
	SUPER_FLASH,
	BURST,
	BUFF,
	EFFECT_SPAWN,
	EFFECT_ACTIVE,
	EFFECT_END,
	EFFECT_DESTROYED,
	HAZARD_WARN,
	HAZARD_ACTIVE,
	COOLDOWN_READY,
	SOUL_FULL,
	LOCK_ON,
	KO,
	ROUND_START,
	FIGHT,
	TIME_UP,
	ROUND_END,
	MATCH_END,
}

const FLAG_COUNTER := 1
const FLAG_LAUNCH := 2
const FLAG_CHIP := 4
const FLAG_PROJECTILE := 8
const FLAG_SUPER := 16
const FLAG_HAZARD := 32
const FLAG_FULL_CHARGE := 64
const FLAG_THROW := 128

var type: Type
var tick: int = 0
## Acting slot (attacker, user), or -1 (hazards, round events).
var source: int = -1
## Affected slot, or -1.
var target: int = -1
## Move id or effect/hazard id involved.
var id: StringName = &""
## Where it happened (Fx units); use Fx.to_vec3.
var position: Vector3i = Vector3i.ZERO
## Damage, Soul, hitstop frames... depends on type (see sim-api.md).
var amount: int = 0
var flags: int = 0
## Hitstop frames applied (hits, blocks, parries), for presentation shake/freeze.
var hitstop: int = 0
## Presentation cue from HitData/EffectData/MoveData, if any.
var cue: StringName = &""


func _to_string() -> String:
	return "%d %s src=%d tgt=%d %s amt=%d flags=%d" % [tick, Type.keys()[type], source, target, id, amount, flags]

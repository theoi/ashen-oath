class_name EffectState
extends SimRecord
## A live effect (projectile, eruption, shockwave) spawned by a move.

var id: int = 0
var owner: int = 0
var team: int = 0
## Owner's move index and the index into that move's `effects`.
var move_index: int = 0
var effect_index: int = 0
var pos: Vector3i = Vector3i.ZERO
var vel: Vector3i = Vector3i.ZERO
var facing: int = 0
## Ticks since spawn, 1 on the spawn tick. The effect can hit once age > delay.
var age: int = 0
var radius: int = 0
var traveled: int = 0
## Per slot: hits dealt to that slot, and the tick of the last hit.
var hit_counts: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var last_hit_tick: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var dead: bool = false
## Skill slot whose cast spawned it (-1 = none), for chain skills armed by effect hits.
var skill_slot: int = -1
## The owner's FighterState.move_cast when it spawned.
var cast: int = 0

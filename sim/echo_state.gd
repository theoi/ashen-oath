class_name EchoState
extends SimRecord
## A shadow afterimage re-casting its owner's move (MoveData.echo_frames): the move's
## hitboxes, effects and motion replay from the cast position and aim, at damage_percent.

var owner: int = 0
var team: int = 0
var move_index: int = 0
## The owner's FighterState.move_cast of the original cast (buff uses).
var cast: int = 0
## Ticks still to wait before the re-cast plays move frame 1 (counted from the tick
## after the cast), then its move frame (0 while waiting).
var delay_left: int = 0
var frame: int = 0
var pos: Vector3i = Vector3i.ZERO
var facing: int = 0
## The original cast's aim point (FighterState.move_point).
var move_point: Vector3i = Vector3i.ZERO
var damage_percent: int = 50
var charge_perfect: bool = false
## Per hitbox group (0-7): bitmask of slots already hit by this echo.
var hit_masks: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])

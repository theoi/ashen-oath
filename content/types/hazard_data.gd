class_name HazardData
extends Resource
## An arena hazard volume on a fixed tick schedule (e.g. a Drowned Crypt grave vent).
## Cycle: every `period` frames starting at `offset` (counted from round start), it warns
## for `warn` frames, then is active for `active` frames. Its shape is a vertical cylinder.

@export var id: StringName = &""
@export var center: Vector2 = Vector2.ZERO
@export var radius: float = 1.0
@export var height: float = 2.0
@export var period: int = 720
@export var offset: int = 0
@export var warn: int = 60
@export var active: int = 45
## Each fighter is hit at most once per activation.
@export var hit: HitData
@export var cue: StringName = &""

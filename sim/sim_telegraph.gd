class_name SimTelegraph
extends RefCounted
## Where an in-progress attack will hit, for presentation decals (red telegraphs, aim
## lines). Built by Sim.telegraphs() from the current state; not part of the sim state.
## Positions are world Fx units at floor or hitbox height.

enum Shape {
	## A disc of `radius` around `from`.
	CIRCLE,
	## A swept sphere from `from` to `to` with `radius`.
	CAPSULE,
	## A projectile path from `from` to `to`, `radius` wide on each side.
	LINE,
}

var owner: int = -1
var team: int = 0
var move_id: StringName = &""
var shape: Shape = Shape.CIRCLE
var from: Vector3i = Vector3i.ZERO
var to: Vector3i = Vector3i.ZERO
var radius: int = 0
## Ticks until it can hit (0 = live now).
var frames_to_active: int = 0
## Ticks it stays live once active.
var frames_active_left: int = 0
## The move's wind-up: startup plus charge held so far (design: decals for >= 12 f).
var wind_up: int = 0
## True for effects (projectiles, eruptions), false for move hitboxes.
var effect: bool = false
## True for hitboxes and effects of a move echo (MoveData.echo_frames).
var echo: bool = false

class_name GroundDecals
extends Node3D
## Floor decals for readability (design-lost-ark §1.9, §1.10):
## - red telegraphs on enemy attacks (areas and effects always; melee hitboxes and aimed
##   projectiles only when the wind-up is 12 f or more), filling from edge to centre as the
##   hit approaches, from Sim.telegraphs();
## - the blue counter ring under a fighter whose move is in its counter window;
## - target circles for the local player's ground-targeted skills: the range ring and the
##   impact circle flash on cast and stay up while a charge/hold skill is held.
## Presentation only.

const SHADER := preload("res://presentation/fight/shaders/ground_decal.gdshader")
const POOL := 24
const RED := Color(1.0, 0.14, 0.08, 0.8)
const BLUE := Color(0.3, 0.6, 1.0, 0.9)
const AIM := Color(1.0, 0.75, 0.35, 0.75)
const SLOW_WIND_UP := 12
const FLOOR_Y := 0.035

var runner: MatchRunner
var local_slot: int = 0

var _pool: Array[MeshInstance3D] = []
var _used := 0
var _target_flash := 0.0
var _target_move: MoveData
var _target_point := Vector3.ZERO


func setup(match_runner: MatchRunner, slot: int) -> void:
	runner = match_runner
	local_slot = slot
	for i in POOL:
		_pool.append(_make_decal())
	runner.event_emitted.connect(_on_event)


func _process(delta: float) -> void:
	if runner == null or runner.sim == null:
		return
	_used = 0
	_draw_telegraphs()
	_draw_counter_rings()
	_draw_target(delta)
	for i in range(_used, POOL):
		_pool[i].visible = false


func _on_event(e: SimEvent) -> void:
	if e.type != SimEvent.Type.MOVE_START or e.source != local_slot:
		return
	var data := runner.sim.fighter_data[local_slot]
	if e.amount < 0 or e.amount >= data.moves.size():
		return
	var move := data.moves[e.amount]
	if move.aim == MoveData.Aim.GROUND_TARGET:
		_target_move = move
		_target_flash = 0.45


func _draw_telegraphs() -> void:
	var sim := runner.sim
	var team := sim.fighter(local_slot).team
	for t in sim.telegraphs():
		if t.team == team:
			continue
		# Fast melee and fast projectiles stay undecorated so duels stay quick.
		if (not t.effect or t.shape == SimTelegraph.Shape.LINE) and t.wind_up < SLOW_WIND_UP:
			continue
		var fill := 1.0
		if t.frames_to_active > 0:
			fill = clampf(1.0 - float(t.frames_to_active) / maxf(1.0, float(t.wind_up)), 0.0, 1.0)
		var from := Fx.to_vec3(t.from)
		var to := Fx.to_vec3(t.to)
		var radius := Fx.to_m(t.radius)
		if t.shape == SimTelegraph.Shape.CIRCLE:
			to = from
		elif t.shape == SimTelegraph.Shape.LINE:
			radius = maxf(radius, 0.15)
		_place(from, to, radius, RED, fill, false, 0.0)


func _draw_counter_rings() -> void:
	var sim := runner.sim
	for slot in sim.slot_count():
		var f := sim.fighter(slot)
		if f.ko or not sim.in_counter_window(f):
			continue
		var p := runner.fighter_position(slot)
		_place(p, p, 1.1, BLUE, 1.0, true, 1.0)


func _draw_target(delta: float) -> void:
	var sim := runner.sim
	var f := sim.fighter(local_slot)
	var move := sim.current_move(f)
	var holding := move != null and move == _target_move \
			and (f.charging or (move.hold_start > 0 and f.move_frame <= move.hold_end))
	_target_flash = maxf(0.0, _target_flash - delta)
	if _target_move == null or (_target_flash <= 0.0 and not holding):
		return
	var me := runner.fighter_position(local_slot)
	var point := Fx.to_vec3(f.move_point) if move == _target_move else _target_point
	_target_point = point
	var alpha := 1.0 if holding else clampf(_target_flash / 0.45, 0.0, 1.0)
	var ring := Color(AIM, AIM.a * 0.6 * alpha)
	_place(me, me, _target_move.max_range, ring, 0.0, true, 0.0)
	_place(point, point, _impact_radius(_target_move), Color(AIM, AIM.a * alpha), 0.0, false, 0.0)


## Largest hitbox or effect radius of a move (the impact circle).
static func _impact_radius(move: MoveData) -> float:
	var r := 0.5
	for box in move.hitboxes:
		r = maxf(r, box.radius)
	for effect in move.effects:
		r = maxf(r, effect.radius)
	return r


func _place(from: Vector3, to: Vector3, radius: float, color: Color, fill: float, ring: bool, pulse: float) -> void:
	if _used >= POOL:
		return
	var decal := _pool[_used]
	_used += 1
	var seg := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var half_length := seg.length() * 0.5
	var mid := (from + to) * 0.5
	var half := Vector2(half_length + radius, radius)
	decal.visible = true
	decal.global_position = Vector3(mid.x, FLOOR_Y, mid.z)
	decal.rotation = Vector3(0.0, atan2(-seg.z, seg.x) if half_length > 0.001 else 0.0, 0.0)
	decal.scale = Vector3(half.x * 2.0, 1.0, half.y * 2.0)
	var m := decal.material_override as ShaderMaterial
	m.set_shader_parameter(&"color", color)
	m.set_shader_parameter(&"half_size", half)
	m.set_shader_parameter(&"half_length", half_length)
	m.set_shader_parameter(&"radius", radius)
	m.set_shader_parameter(&"fill", fill)
	m.set_shader_parameter(&"ring_only", 1.0 if ring else 0.0)
	m.set_shader_parameter(&"rim_width", 0.06 if ring else 0.1)
	m.set_shader_parameter(&"pulse", pulse)


func _make_decal() -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	var decal := MeshInstance3D.new()
	decal.mesh = plane
	decal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = SHADER
	decal.material_override = material
	decal.top_level = true
	decal.visible = false
	add_child(decal)
	return decal

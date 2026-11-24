extends FighterModel
## Gorrath: a hulking chain-bound brute. Rusted chains glow ember-hot in their pits: one
## slung across his chest, one swinging from his left fist, and the Chain Hook / Execution
## Chain that he hurls and drags opponents back on. Red eyes, leans for his charges.

const HOOK_MOVES: Array[StringName] = [&"chain_hook"]
const DRAG_MOVES: Array[StringName] = [&"execution_chain", &"execution_chain_slams"]
const HOOK_REACH := 9.0
const ROPE_POINTS := 9
const ROPE_SEGMENT := 0.1
## The chest-chain loop, in the chest bone's space (rig units before model_scale).
const SLING: Array[Vector3] = [
	Vector3(0.32, 0.42, 0.05), Vector3(0.25, 0.32, 0.36), Vector3(-0.05, 0.02, 0.44),
	Vector3(-0.34, -0.3, 0.38), Vector3(-0.46, -0.36, 0.0), Vector3(-0.34, -0.3, -0.36),
	Vector3(-0.05, 0.02, -0.4), Vector3(0.25, 0.32, -0.32), Vector3(0.32, 0.42, 0.05),
]

var _sling: ChainVisual
var _rope: ChainVisual
var _hook: ChainVisual
var _rope_pos := PackedVector3Array()
var _rope_prev := PackedVector3Array()
var _hook_len := 0.0
var _heat := 0.0
var _chest := -1
var _hand_l := -1
var _hand_r := -1


func _build_extras() -> void:
	_chest = skeleton.find_bone(&"chest")
	_hand_l = skeleton.find_bone(&"hand.l")
	_hand_r = skeleton.find_bone(&"hand.r")
	_sling = ChainVisual.new(40)
	_rope = ChainVisual.new(24)
	_hook = ChainVisual.new(130, 1.15)
	for chain: ChainVisual in [_sling, _rope, _hook]:
		add_child(chain)
	_rope_pos.resize(ROPE_POINTS)
	_rope_prev.resize(ROPE_POINTS)
	var anchor := _bone(_hand_l)
	for i in ROPE_POINTS:
		_rope_pos[i] = anchor + Vector3.DOWN * ROPE_SEGMENT * i
		_rope_prev[i] = _rope_pos[i]


func update_extras(sim: Sim, f: FighterState, delta: float) -> void:
	_update_sling()
	_update_rope(delta)
	var move := sim.current_move(f)
	var hot := move != null and (move.id in HOOK_MOVES or move.id in DRAG_MOVES)
	_heat = move_toward(_heat, 1.0 if hot else 0.0, delta * (8.0 if hot else 1.5))
	var flicker := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.006)
	_sling.heat = (0.3 + 0.7 * _heat) * flicker
	_rope.heat = (0.3 + 0.7 * _heat) * flicker
	_hook.heat = 1.0
	_update_hook(sim, f, move)


func adjust_pose(sim: Sim, f: FighterState, pose: FighterPose, sub: float) -> void:
	var move := sim.current_move(f)
	if move == null or f.action != FighterState.Action.ATTACK:
		return
	var frame := float(f.move_frame - 1) + sub
	match move.id:
		&"bull_rush":
			var charge := clampf((frame - 3.0) / 4.0, 0.0, 1.0) * clampf((36.0 - frame) / 5.0, 0.0, 1.0)
			pose.pitch += deg_to_rad(24.0) * charge
			pose.lift -= 0.1 * charge
		&"earthsplitter":
			var rise := clampf(frame / 14.0, 0.0, 1.0) * clampf((24.0 - frame) / 4.0, 0.0, 1.0)
			pose.lift += 0.35 * rise
			pose.pitch -= deg_to_rad(8.0) * rise


func _bone(index: int) -> Vector3:
	if index < 0:
		return global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(index).origin


func _update_sling() -> void:
	if _chest < 0:
		return
	var xf := skeleton.global_transform * skeleton.get_bone_global_pose(_chest)
	var points := PackedVector3Array()
	for p in SLING:
		points.append(xf * p)
	_sling.set_points(points)


## Verlet rope hanging from the left fist.
func _update_rope(delta: float) -> void:
	var dt := clampf(delta, 0.0, 1.0 / 30.0)
	_rope_pos[0] = _bone(_hand_l)
	_rope_prev[0] = _rope_pos[0]
	var gravity := Vector3.DOWN * 9.8 * dt * dt
	for i in range(1, ROPE_POINTS):
		var p := _rope_pos[i]
		var v := (p - _rope_prev[i]) * 0.96
		_rope_prev[i] = p
		_rope_pos[i] = p + v + gravity
	for _k in 4:
		for i in range(1, ROPE_POINTS):
			var a := _rope_pos[i - 1]
			var b := _rope_pos[i]
			var d := b - a
			var length := d.length()
			if length > 0.0001:
				var fix := d * (1.0 - ROPE_SEGMENT / length)
				if i == 1:
					_rope_pos[i] = b - fix
				else:
					_rope_pos[i - 1] = a + fix * 0.5
					_rope_pos[i] = b - fix * 0.5
			_rope_pos[i].y = maxf(_rope_pos[i].y, 0.03)
	_rope.set_points(_rope_pos)


## The thrown chain: flies out with Chain Hook (and back, dragging a hooked target), and
## binds the victim during Execution Chain.
func _update_hook(sim: Sim, f: FighterState, move: MoveData) -> void:
	var hand := _bone(_hand_r)
	if move == null or f.action != FighterState.Action.ATTACK or not (move.id in HOOK_MOVES or move.id in DRAG_MOVES):
		_hook_len = 0.0
		_hook.set_points(PackedVector3Array())
		return
	var end := hand
	if move.id in DRAG_MOVES:
		if f.grab_partner < 0:
			_hook.set_points(PackedVector3Array())
			return
		end = _chest_of(sim, f.grab_partner)
	else:
		var frame := float(f.move_frame)
		var out_end := float(move.startup + move.active)
		var reach := HOOK_REACH
		if f.target >= 0:
			reach = minf(reach, _flat(hand, _chest_of(sim, f.target)) + 0.3)
		if f.move_contact == 2 and f.target >= 0:
			end = _chest_of(sim, f.target)
		else:
			var t := clampf((frame - 8.0) / maxf(1.0, out_end - 8.0), 0.0, 1.0)
			if frame > out_end:
				t = clampf(1.0 - (frame - out_end) / 10.0, 0.0, 1.0)
			_hook_len = reach * t
			var dir := global_transform.basis.z
			dir = Vector3(dir.x, 0.0, dir.z).normalized()
			end = hand + dir * _hook_len
			if _hook_len < 0.05:
				_hook.set_points(PackedVector3Array())
				return
	# A slight sag so the chain reads as heavy iron, not a laser.
	var mid := (hand + end) * 0.5 + Vector3.DOWN * minf(0.35, hand.distance_to(end) * 0.04)
	_hook.set_points(PackedVector3Array([hand, mid, end]))


func _chest_of(sim: Sim, slot: int) -> Vector3:
	return Fx.to_vec3(sim.fighter(slot).pos) + Vector3.UP * 1.0


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

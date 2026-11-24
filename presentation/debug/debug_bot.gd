class_name DebugBot
extends InputSource
## A simple scripted opponent for the debug scene and clips: runs at its target and plays
## random routines (strings, launch combos, grabs, abilities, guard, dodges, super, burst).
## Uses its own seeded RNG, never the sim's. The real CPU opponent lives elsewhere.

const L := SimInput.LIGHT
const H := SimInput.HEAVY

var _rng := RandomNumberGenerator.new()
var _plan: Array[int] = []


func _init(seed_value: int = 1) -> void:
	_rng.seed = seed_value


func next_frame(sim: Sim, slot: int) -> int:
	var me := sim.fighter(slot)
	if me.ko or sim.state.phase != SimState.Phase.FIGHT:
		_plan.clear()
		return 0
	if me.in_hitstun() and me.soul_points() >= 50 and _rng.randf() < 0.02:
		_plan.clear()
		return SimInput.SUPER
	if not _plan.is_empty():
		return _plan.pop_front()
	if me.target < 0:
		return 0
	var target := sim.fighter(me.target)
	var to := target.pos - me.pos
	var toward := Vector2(to.x, to.z).normalized()
	var dist := Fx.to_m(Fx.length_xz(to))
	if me.action != FighterState.Action.IDLE and me.action != FighterState.Action.GUARD:
		return 0
	if dist > 6.0 and _rng.randf() < 0.02:
		_queue([SimInput.ABILITY_3])
		return _plan.pop_front()
	if dist > 1.4:
		return SimInput.from_vector(0, toward)
	match _rng.randi() % 12:
		0, 1:
			_queue([L, 0, 0, 0, 0, 0, L, 0, 0, 0, 0, 0, L])
		2:
			_queue([L, 0, 0, 0, 0, 0, L, 0, 0, 0, 0, 0, H] + _wait(20) + [SimInput.JUMP] + _wait(6) + [L, 0, 0, 0, 0, 0, L])
		3:
			_queue([L, 0, 0, 0, 0, 0, H])
		4:
			_queue(_hold(H, 30))
		5:
			_queue([SimInput.GRAB])
		6:
			_queue([SimInput.ABILITY_2] + _wait(14) + [SimInput.JUMP] + _wait(8) + [L, 0, 0, 0, 0, 0, L] + _wait(10) + [H])
		7:
			_queue([SimInput.ABILITY_1])
		8:
			_queue(_hold(SimInput.GUARD, 30 + _rng.randi() % 30))
		9:
			var side := Vector2(-toward.y, toward.x) * (1.0 if _rng.randf() < 0.5 else -1.0)
			_queue([SimInput.from_vector(SimInput.DODGE, side)])
		10:
			_queue([SimInput.SUPER if me.soul_points() >= 100 else L])
		_:
			_queue(_wait(10 + _rng.randi() % 20))
	return _plan.pop_front()


func _queue(frames: Array) -> void:
	for frame: int in frames:
		_plan.append(frame)


func _wait(count: int) -> Array:
	var frames: Array = []
	frames.resize(count)
	frames.fill(0)
	return frames


func _hold(frame: int, count: int) -> Array:
	var frames: Array = []
	frames.resize(count)
	frames.fill(frame)
	return frames

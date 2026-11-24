class_name ShowcaseInputSource
extends InputSource
## Plays a fighter's kit on a loop for clips and the pilot check-in: for each step it walks
## to the step's range of the nearest enemy, then presses the step's button (aimed at the
## enemy) for `hold` ticks and waits `wait` ticks. Dev and capture use only.

## Each step: {"range": metres, "press": SimInput bits, "hold": ticks, "wait": ticks}.
var steps: Array[Dictionary] = []

var _step := 0
var _phase := 0
var _left := 0
var _approach := 0


func _init(showcase_steps: Array[Dictionary] = []) -> void:
	steps = showcase_steps


## Aldric's §4 kit in order: basics, Lunge, Brand Rise + Slam, Flame Rend + Ignition,
## Cinder Wheel, perfect Verdict, Bulwark, then the awakening when Soul allows.
static func aldric() -> ShowcaseInputSource:
	var s := SimInput.SKILLS
	var out: Array[Dictionary] = [
		{"range": 1.8, "press": SimInput.BASIC, "hold": 40, "wait": 30},
		{"range": 5.5, "press": s[0], "hold": 1, "wait": 50},
		{"range": 1.8, "press": s[1], "hold": 1, "wait": 14},
		{"range": 99.0, "press": s[1], "hold": 1, "wait": 60},
		{"range": 7.0, "press": s[2], "hold": 1, "wait": 40},
		{"range": 99.0, "press": s[2], "hold": 1, "wait": 60},
		{"range": 1.8, "press": s[4], "hold": 60, "wait": 40},
		{"range": 5.0, "press": s[5], "hold": 40, "wait": 70},
		{"range": 2.5, "press": s[3], "hold": 34, "wait": 50},
		{"range": 6.0, "press": SimInput.AWAKEN, "hold": 1, "wait": 260},
	]
	return ShowcaseInputSource.new(out)


func next_frame(sim: Sim, slot: int) -> int:
	if steps.is_empty():
		return 0
	var me := sim.fighter(slot)
	var foe := _nearest_enemy(sim, slot)
	if me.ko or foe == null:
		return 0
	var offset := Vector2(Fx.to_m(foe.pos.x - me.pos.x), Fx.to_m(foe.pos.z - me.pos.z))
	var step := steps[_step]
	match _phase:
		0:
			if int(step["press"]) == SimInput.AWAKEN and me.soul < 100 * 100:
				_advance()
				return 0
			_approach += 1
			if offset.length() > float(step["range"]) and _approach < 180:
				return SimInput.from_vector(0, offset.normalized())
			_phase = 1
			_left = int(step["hold"])
			return next_frame(sim, slot)
		1:
			_left -= 1
			if _left <= 0:
				_phase = 2
				_left = int(step["wait"])
			return SimInput.with_aim_point(int(step["press"]), offset)
		_:
			_left -= 1
			if _left <= 0:
				_advance()
			return 0


func _advance() -> void:
	_step = (_step + 1) % steps.size()
	_phase = 0
	_approach = 0


static func _nearest_enemy(sim: Sim, slot: int) -> FighterState:
	var me := sim.fighter(slot)
	var best: FighterState = null
	var best_d := INF
	for other in sim.state.fighters:
		if other.team == me.team or other.ko:
			continue
		var d := Vector2(Fx.to_m(other.pos.x - me.pos.x), Fx.to_m(other.pos.z - me.pos.z)).length()
		if d < best_d:
			best_d = d
			best = other
	return best

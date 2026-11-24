class_name MatchRunner
extends Node
## Runs a Sim at a fixed 60 Hz (physics ticks) from one InputSource per slot, records a
## Replay and re-broadcasts the sim's events. Presentation nodes read `sim.state` and use
## fighter_position()/alpha() to interpolate between ticks; they never write sim state.

## Emitted after every tick with that tick's events.
signal stepped(events: Array[SimEvent])
## Emitted for each event, in order.
signal event_emitted(event: SimEvent)
## Emitted once when the match ends.
signal match_ended(winner_team: int)

var sim: Sim
var sources: Array[InputSource] = []
var replay: Replay
## Stops stepping (pause menu). Rendering keeps going; ends any slow motion.
var paused: bool = false:
	set(value):
		paused = value
		if paused and _slow_ticks > 0:
			_end_slow_motion()
## Record a checksum per tick in the replay (desync checks; costs ~0.05 ms/tick).
var record_checksums: bool = false

var _prev_positions: Array[Vector3i] = []
var _ended: bool = false
## Presentation-only slow motion: ticks left to run slowed (see slow_motion()).
var _slow_ticks := 0


## Starts a match. `input_sources[slot]` drives that slot (null = neutral).
func start(config: SimConfig, input_sources: Array[InputSource]) -> void:
	sim = Sim.new(config)
	sources = input_sources
	replay = Replay.create(config)
	_ended = false
	_snapshot_positions()


func _physics_process(_delta: float) -> void:
	if sim != null and not paused:
		step_once()


## Runs the next `ticks` sim ticks at `factor` of real time (0.4 = 40% speed) by slowing
## the engine clock: the sim steps exactly the same ticks with the same inputs, so results
## do not change. Presentation only (awakening finales, perfect dashes).
func slow_motion(factor: float, ticks: int) -> void:
	if factor >= 1.0 or ticks <= 0:
		return
	_slow_ticks = maxi(_slow_ticks, ticks)
	Engine.time_scale = clampf(factor, 0.05, 1.0)


func is_slowed() -> bool:
	return _slow_ticks > 0


func _end_slow_motion() -> void:
	_slow_ticks = 0
	Engine.time_scale = 1.0


func _exit_tree() -> void:
	if _slow_ticks > 0:
		_end_slow_motion()


## Gathers inputs, steps the sim once and emits its events.
func step_once() -> void:
	var inputs := PackedInt64Array()
	inputs.resize(sim.slot_count())
	for slot in sim.slot_count():
		var source: InputSource = sources[slot] if slot < sources.size() else null
		inputs[slot] = source.next_frame(sim, slot) if source != null else 0
	_snapshot_positions()
	var events := sim.step(inputs)
	if _slow_ticks > 0:
		_slow_ticks -= 1
		if _slow_ticks == 0:
			_end_slow_motion()
	replay.record(inputs, sim.checksum() if record_checksums else 0, record_checksums)
	for event in events:
		event_emitted.emit(event)
	stepped.emit(events)
	if sim.is_over() and not _ended:
		_ended = true
		match_ended.emit(sim.state.winner_team)


## Fraction (0..1) of the way from the previous tick to the current one, for interpolation.
func alpha() -> float:
	return Engine.get_physics_interpolation_fraction()


## Interpolated world position of a fighter, in meters.
func fighter_position(slot: int) -> Vector3:
	var current := Fx.to_vec3(sim.state.fighters[slot].pos)
	if slot >= _prev_positions.size():
		return current
	var previous := Fx.to_vec3(_prev_positions[slot])
	if previous.distance_squared_to(current) > 4.0:
		return current
	return previous.lerp(current, alpha())


func _snapshot_positions() -> void:
	_prev_positions.resize(sim.slot_count())
	for slot in sim.slot_count():
		_prev_positions[slot] = sim.state.fighters[slot].pos

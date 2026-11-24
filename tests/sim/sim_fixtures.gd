class_name SimFixtures
extends RefCounted
## Builders for sim tests: plain fighters, arenas and configs, plus input helpers.

const L := SimInput.LIGHT
const H := SimInput.HEAVY
const J := SimInput.JUMP
const D := SimInput.DODGE
const G := SimInput.GUARD
const T := SimInput.GRAB


static func fighter() -> FighterData:
	var data := FighterData.new()
	data.id = &"fixture"
	data.display_name = "Fixture"
	return data


static func arena(half_x: float = 12.0, half_z: float = 10.0) -> ArenaData:
	var data := ArenaData.new()
	data.id = &"fixture_arena"
	data.floor_polygon = PackedVector2Array([Vector2(-half_x, -half_z), Vector2(half_x, -half_z),
			Vector2(half_x, half_z), Vector2(-half_x, half_z)])
	data.spawn_points = PackedVector2Array([Vector2(0.0, -1.5), Vector2(0.0, 1.5),
			Vector2(-3.0, 3.0), Vector2(3.0, 3.0)])
	return data


## A config with `count` fighters (slot 0 on team 0, the rest on team 1). Round timer off.
static func config(count: int = 2, data: FighterData = null, arena_data: ArenaData = null) -> SimConfig:
	var cfg := SimConfig.new()
	cfg.rules = CombatRules.new()
	cfg.arena = arena_data if arena_data != null else arena()
	cfg.seed = 7
	cfg.round_seconds = -1
	for i in count:
		var slot := SlotConfig.new()
		slot.fighter = data if data != null else fighter()
		slot.team = 0 if i == 0 else 1
		cfg.slots.append(slot)
	return cfg


## A sim already past the round intro (first FIGHT tick is next).
static func fighting_sim(cfg: SimConfig) -> Sim:
	var sim := Sim.new(cfg)
	skip_intro(sim)
	return sim


static func skip_intro(sim: Sim) -> void:
	var neutral := PackedInt32Array()
	neutral.resize(sim.slot_count())
	while sim.state.phase != SimState.Phase.FIGHT:
		sim.step(neutral)


## Steps once with `frame` for slot 0 and neutral for the others.
static func step(sim: Sim, frame: int = 0, other: int = 0) -> Array[SimEvent]:
	var inputs := PackedInt64Array()
	inputs.resize(sim.slot_count())
	inputs[0] = frame
	for i in range(1, sim.slot_count()):
		inputs[i] = other
	return sim.step(inputs)


## Steps `count` times holding the same frames.
static func hold(sim: Sim, count: int, frame: int = 0, other: int = 0) -> Array[SimEvent]:
	var all: Array[SimEvent] = []
	for _i in count:
		all.append_array(step(sim, frame, other))
	return all


static func has_event(events: Array[SimEvent], type: SimEvent.Type) -> bool:
	for e in events:
		if e.type == type:
			return true
	return false


## Deterministic pseudo-random input frames for `ticks` x `slots` (for determinism tests).
static func random_frames(ticks: int, slots: int, seed_value: int) -> Array[PackedInt32Array]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var result: Array[PackedInt32Array] = []
	var held := PackedInt32Array()
	held.resize(slots)
	for _t in ticks:
		var inputs := PackedInt32Array()
		inputs.resize(slots)
		for s in slots:
			if rng.randi() % 6 == 0:
				var buttons := 0
				var roll := rng.randi() % 13
				if roll < 11:
					buttons = 1 << roll
				elif roll == 11:
					buttons = SimInput.GUARD
				held[s] = SimInput.make(buttons, rng.randi_range(-127, 127), rng.randi_range(-127, 127))
			inputs[s] = held[s]
		result.append(inputs)
	return result


# --- Combat helpers ------------------------------------------------------------------------

static func test_fighter() -> FighterData:
	return load("res://content/test_fighter/test_fighter.tres") as FighterData


## A fighting sim with test fighters: slot 0 at the origin facing +Z, slot 1 `distance`
## meters in front facing it, further slots (team 1) behind slot 1.
static func duel(distance: float = 1.2, count: int = 2, data: FighterData = null) -> Sim:
	var sim := fighting_sim(config(count, data if data != null else test_fighter()))
	place(sim, 0, 0.0, 0.0, 0)
	place(sim, 1, 0.0, distance, Fx.HALF_TURN)
	for slot in range(2, count):
		place(sim, slot, 1.0 * slot, distance + 2.0, Fx.HALF_TURN)
	return sim


static func place(sim: Sim, slot: int, x: float, z: float, facing: int) -> void:
	var f := sim.fighter(slot)
	f.pos = Vector3i(Fx.m(x), 0, Fx.m(z))
	f.vel = Vector3i.ZERO
	f.facing = facing
	f.grounded = true


## Steps through per-tick frames for slots 0 and 1 (missing entries are neutral) and returns
## the events of each tick (index 0 = first step).
static func play(sim: Sim, frames0: Array, frames1: Array = [], ticks: int = -1) -> Array[Array]:
	var count := ticks if ticks >= 0 else maxi(frames0.size(), frames1.size())
	var result: Array[Array] = []
	for t in count:
		var a: int = frames0[t] if t < frames0.size() else 0
		var b: int = frames1[t] if t < frames1.size() else 0
		result.append(step(sim, a, b))
	return result


## Frames: `frame` for `count` ticks.
static func held(frame: int, count: int) -> Array:
	var out: Array = []
	for _i in count:
		out.append(frame)
	return out


## 1-based tick of the first event of `type` in `per_tick` (from play), or -1.
static func tick_of(per_tick: Array[Array], type: SimEvent.Type) -> int:
	for t in per_tick.size():
		for e: SimEvent in per_tick[t]:
			if e.type == type:
				return t + 1
	return -1


static func first(per_tick: Array[Array], type: SimEvent.Type) -> SimEvent:
	for events in per_tick:
		for e: SimEvent in events:
			if e.type == type:
				return e
	return null


static func count_of(per_tick: Array[Array], type: SimEvent.Type) -> int:
	var n := 0
	for events in per_tick:
		for e: SimEvent in events:
			if e.type == type:
				n += 1
	return n


## Steps neutral until `f` is in `action` (max ticks); returns ticks stepped or -1.
static func until_action(sim: Sim, f: FighterState, action: FighterState.Action, max_ticks: int = 300) -> int:
	for t in max_ticks:
		if f.action == action:
			return t
		step(sim)
	return -1

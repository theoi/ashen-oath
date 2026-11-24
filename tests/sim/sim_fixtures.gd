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
	var inputs := PackedInt32Array()
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
				var roll := rng.randi() % 12
				if roll < 10:
					buttons = 1 << roll
				held[s] = SimInput.make(buttons, rng.randi_range(-127, 127), rng.randi_range(-127, 127))
			inputs[s] = held[s]
		result.append(inputs)
	return result

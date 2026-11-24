class_name Sim
extends RefCounted
## The deterministic combat simulation: state(t+1) = step(state(t), inputs(t)) at 60 Hz.
##
## Create one per match from a SimConfig, then call step() once per tick with one input
## frame (SimInput) per slot. Everything the sim knows lives in `state` (a SimState of plain
## integers); content Resources are read-only. snapshot()/restore() copy the state,
## checksum() hashes it. step() returns the tick's events for presentation.
##
## Rules: no Node/scene access, no wall-clock time, no global RNG, no floats in state.
## Iterate fighters in slot order and effects in spawn order.

const MAX_SLOTS := 4
## Stick magnitude (of SimInput.STICK_MAX) below which the stick counts as neutral.
const STICK_DEADZONE := 24
## Buttons that are buffered, in priority order when pressed on the same tick.
const BUFFER_PRIORITY: Array[int] = [
	SimInput.SUPER, SimInput.SKILL_1, SimInput.SKILL_2, SimInput.SKILL_3, SimInput.SKILL_4,
	SimInput.SKILL_5, SimInput.SKILL_6, SimInput.GRAB, SimInput.HEAVY, SimInput.LIGHT,
	SimInput.DODGE, SimInput.JUMP,
]
const Action := FighterState.Action
const Phase := SimState.Phase
const EventType := SimEvent.Type

var config: SimConfig
var rules: CombatRules
var arena: ArenaCollision
var state: SimState
## Per slot: the fighter's data and optional trait hook (null when none).
var fighter_data: Array[FighterData] = []
var traits: Array[FighterTrait] = []

var _events: Array[SimEvent] = []
## Mark detonations queued during fighter updates, applied with this tick's contacts.
var _mark_contacts: Array[Contact] = []
var _jump_speed: PackedInt32Array = PackedInt32Array()
var _gravity: PackedInt32Array = PackedInt32Array()
var _juggle_gravity: int = 0
## Per slot body radius and height in units.
var _radius: PackedInt32Array = PackedInt32Array()
var _height: PackedInt32Array = PackedInt32Array()


func _init(sim_config: SimConfig) -> void:
	config = sim_config
	rules = config.rules if config.rules != null else CombatRules.new()
	arena = ArenaCollision.new(config.arena if config.arena != null else ArenaData.new())
	assert(config.slots.size() >= 1 and config.slots.size() <= MAX_SLOTS, "1-4 slots")
	state = SimState.new()
	state.rng = (config.seed ^ 0x2545F491) & 0xFFFFFFFF
	if state.rng == 0:
		state.rng = 1
	var scaled: Dictionary[FighterData, FighterData] = {}
	for i in config.slots.size():
		var slot_config := config.slots[i]
		var data := slot_config.fighter
		if config.move_speed_percent > 0 and config.move_speed_percent != 100:
			if not scaled.has(data):
				scaled[data] = MoveSpeed.scaled_fighter(data, config.move_speed_percent)
			data = scaled[data]
		fighter_data.append(data)
		var hook: FighterTrait = null
		if data.trait_script != null:
			hook = data.trait_script.new()
		traits.append(hook)
		var apex := Fx.m(data.jump_height)
		var airtime := maxi(2, data.jump_airtime)
		_jump_speed.append(4 * apex / airtime)
		_gravity.append(maxi(1, 8 * apex / (airtime * airtime)))
		_radius.append(Fx.m(data.radius))
		_height.append(Fx.m(data.height))
		var f := FighterState.new()
		f.slot = i
		f.team = slot_config.team
		f.max_hp = maxi(1, data.max_hp * slot_config.hp_percent / 100)
		f.soul = clampi(slot_config.start_soul, 0, rules.soul_max) * 100
		state.fighters.append(f)
	_juggle_gravity = Fx.mps2(rules.juggle_gravity)
	state.hazard_hits.resize(arena.hazards.size())
	_start_round()


# --- Public API -------------------------------------------------------------------------

## Advances one tick. `inputs[slot]` is that slot's SimInput frame (missing = neutral):
## a PackedInt64Array, or a PackedInt32Array for frames without aim.
## Returns the events of this tick (also valid until the next step).
func step(inputs: Variant) -> Array[SimEvent]:
	_events = []
	state.tick += 1
	state.phase_tick += 1
	_advance_phase()
	var accept := state.phase == Phase.FIGHT
	var count: int = inputs.size()
	for f in state.fighters:
		var frame: int = inputs[f.slot] if f.slot < count else 0
		_read_input(f, SimInput.normalized(frame), accept)
	if state.freeze > 0:
		state.freeze -= 1
		return _events
	_update_targets()
	for f in state.fighters:
		_update_fighter(f)
	_update_holds()
	_push_bodies()
	_update_effects()
	_resolve_combat()
	_update_hazards()
	for f in state.fighters:
		_post_tick(f)
	_check_round_end()
	return _events


## The events of the last step.
func events() -> Array[SimEvent]:
	return _events


## A deep copy of the current state.
func snapshot() -> SimState:
	return state.clone() as SimState


## Makes the current state equal to `snap` (in place: FighterState objects are reused).
func restore(snap: SimState) -> void:
	state.copy_from(snap)


## 64-bit hash of the whole state. Equal states give equal checksums on every platform.
func checksum() -> int:
	return checksum_of(state)


static func checksum_of(sim_state: SimState) -> int:
	var ints := PackedInt64Array()
	sim_state.write_ints(ints)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(ints.to_byte_array())
	return ctx.finish().decode_s64(0)


func fighter(slot: int) -> FighterState:
	return state.fighters[slot]


func slot_count() -> int:
	return state.fighters.size()


## The move a fighter is executing, or null.
func current_move(f: FighterState) -> MoveData:
	if f.move_index < 0:
		return null
	return fighter_data[f.slot].moves[f.move_index]


## Data of the effect `e` (EffectData), looked up through its owner's move.
func effect_data(e: EffectState) -> EffectData:
	return fighter_data[e.owner].moves[e.move_index].effects[e.effect_index]


func is_enemy(a: FighterState, b: FighterState) -> bool:
	return a.team != b.team


## Living enemies of `f` in slot order.
func enemies_of(f: FighterState) -> Array[FighterState]:
	var result: Array[FighterState] = []
	for other in state.fighters:
		if other.team != f.team and not other.ko:
			result.append(other)
	return result


func is_over() -> bool:
	return state.phase == Phase.MATCH_END


## Whether `f` is invincible to everything on this tick.
func is_invulnerable(f: FighterState) -> bool:
	if f.invuln > 0 or f.ko:
		return true
	var data := fighter_data[f.slot]
	match f.action:
		Action.DODGE:
			return f.action_tick >= data.dodge_invuln_start and f.action_tick <= data.dodge_invuln_end
		Action.AIR_DODGE:
			return f.action_tick >= data.air_dodge_invuln_start and f.action_tick <= data.air_dodge_invuln_end
		Action.DASH:
			return f.action_tick >= data.dash.invuln_start and f.action_tick <= data.dash.invuln_end
		Action.ATTACK:
			var move := current_move(f)
			return move.invuln_end > 0 and f.move_frame >= move.invuln_start and f.move_frame <= move.invuln_end
	return false


## Whether `f` is in a counter window of its current move (the blue flash).
func in_counter_window(f: FighterState) -> bool:
	if f.action != Action.ATTACK:
		return false
	var move := current_move(f)
	return move.in_window(f.move_frame, move.counter_window_start, move.counter_window_end)


## Dash charges `f` starts each round with (0 for fighters without FighterData.dash).
func dash_max_charges(f: FighterState) -> int:
	var dash := fighter_data[f.slot].dash
	if dash == null:
		return 0
	return config.dash_charges if config.dash_charges >= 0 else dash.charges


## Dash distance in units for `f` (SimConfig.dash_distance overrides the fighter's).
func dash_distance(f: FighterState) -> int:
	var dash := fighter_data[f.slot].dash
	if dash == null:
		return 0
	return Fx.m(config.dash_distance if config.dash_distance >= 0.0 else dash.distance)


## Frames one dash charge takes to come back for `f` (SimConfig.dash_recharge_frames
## overrides the fighter's; 0 for fighters without FighterData.dash).
func dash_recharge_frames(f: FighterState) -> int:
	var dash := fighter_data[f.slot].dash
	if dash == null:
		return 0
	return config.dash_recharge_frames if config.dash_recharge_frames >= 0 else dash.recharge_frames


## First frame of `move` from which a skill or the awakening may cancel it (0 = never).
static func skill_cancel_frame(move: MoveData) -> int:
	if move.skill_cancel_from >= 0:
		return move.skill_cancel_from
	match move.kind:
		MoveData.Kind.SUPER, MoveData.Kind.THROW, MoveData.Kind.BURST:
			return 0
	if move.is_basic():
		return 1
	return move.last_active_frame() + 1


## First frame of `move` from which a skill-kit dash may cancel it (0 = never).
static func dash_cancel_frame(move: MoveData) -> int:
	if move.no_dash_cancel:
		return 0
	if move.dash_cancel_from >= 0:
		return move.dash_cancel_from
	match move.kind:
		MoveData.Kind.SUPER, MoveData.Kind.THROW, MoveData.Kind.BURST:
			return 0
	return 1


## Where every in-progress attack will hit: move hitboxes that are not over yet, effects
## the current move will still spawn, and live effects (still in their delay or active).
## Rebuilt on each call from the current state; presentation filters by team and wind-up.
func telegraphs() -> Array[SimTelegraph]:
	var out: Array[SimTelegraph] = []
	for f in state.fighters:
		if f.action != Action.ATTACK or f.ko:
			continue
		var move := current_move(f)
		var frame := f.move_frame
		var wind_up := move.startup + f.charge
		for hb in move.hitboxes:
			if hb.hit == null:
				continue
			var first := hb.start_frame if hb.start_frame >= 0 else move.startup
			var last := hb.end_frame if hb.end_frame >= 0 else move.last_active_frame()
			if frame > last:
				continue
			var base := _telegraph_base(f, move, first)
			var t := _telegraph(f, move, wind_up, first - frame, last - maxi(frame, first) + 1)
			t.from = base + Fx.rotate(Fx.v3(hb.offset), f.facing)
			t.radius = Fx.m(hb.radius)
			if hb.capsule:
				t.shape = SimTelegraph.Shape.CAPSULE
				t.to = base + Fx.rotate(Fx.v3(hb.offset_end), f.facing)
			out.append(t)
		for i in move.effects.size():
			var ed := move.effects[i]
			if ed.hit == null or ed.spawn_frame <= frame:
				continue
			var t := _telegraph(f, move, wind_up, ed.spawn_frame - frame + ed.delay, ed.lifetime)
			t.effect = true
			t.from = _effect_spawn_point(f, move, ed)
			_effect_shape(t, ed, f.facing)
			out.append(t)
	for e in state.effects:
		var ed := effect_data(e)
		if e.dead or ed.hit == null:
			continue
		var owner := state.fighters[e.owner]
		var t := _telegraph(owner, fighter_data[e.owner].moves[e.move_index], 0,
				maxi(0, ed.delay - e.age + 1), ed.delay + ed.lifetime - maxi(e.age, ed.delay))
		t.effect = true
		t.from = e.pos
		_effect_shape(t, ed, e.facing)
		t.radius = e.radius
		out.append(t)
	return out


func _telegraph(f: FighterState, move: MoveData, wind_up: int, to_active: int, active_left: int) -> SimTelegraph:
	var t := SimTelegraph.new()
	t.owner = f.slot
	t.team = f.team
	t.move_id = move.id
	t.wind_up = wind_up
	t.frames_to_active = maxi(0, to_active)
	t.frames_active_left = maxi(0, active_left)
	return t


## Where the fighter will stand when a hitbox starting on `first` comes out: the aim point
## for moves that travel there first (leaps, dash-to), else where it stands now.
func _telegraph_base(f: FighterState, move: MoveData, first: int) -> Vector3i:
	if move.aims_at_point():
		for motion in move.motions:
			if motion.aim_travel != MotionData.AimTravel.NONE and motion.start_frame <= first:
				return Vector3i(f.move_point.x, f.pos.y, f.move_point.z)
	return f.pos


func _effect_spawn_point(f: FighterState, move: MoveData, ed: EffectData) -> Vector3i:
	if ed.anchor != EffectData.Anchor.TARGET:
		return f.pos + Fx.rotate(Fx.v3(ed.offset), f.facing)
	var origin := Vector3i(f.pos.x, 0, f.pos.z)
	var reach := Fx.m(ed.max_range)
	if move.aims_at_point():
		return _clamp_point(origin, f.move_point, reach)
	if move.is_aimed():
		return aim_point(f, reach, true)
	var target := _target_of(f)
	if target != null:
		return _clamp_point(origin, target.pos, reach)
	return origin + Fx.dir(f.facing, reach)


func _effect_shape(t: SimTelegraph, ed: EffectData, angle: int) -> void:
	t.radius = Fx.m(ed.radius)
	if ed.speed <= 0.0:
		t.shape = SimTelegraph.Shape.CIRCLE
		return
	t.shape = SimTelegraph.Shape.LINE
	var reach := Fx.m(ed.travel) if ed.travel > 0.0 else Fx.mps(ed.speed) * ed.lifetime
	t.to = t.from + Fx.dir(angle, reach)


## Hazard `index` phase this tick: 0 idle, 1 warning, 2 active.
func hazard_phase(index: int) -> int:
	if state.phase != Phase.FIGHT and state.phase != Phase.ROUND_END:
		return 0
	var h := arena.hazards[index]
	var t := state.round_tick - h.offset
	if t < 0:
		return 0
	var c := t % h.period
	if c < h.warn:
		return 1
	if c < h.warn + h.active:
		return 2
	return 0


## Remaining round time in whole seconds (rounded up) for the HUD, -1 without a timer.
func seconds_left() -> int:
	if state.round_timer < 0:
		return -1
	return (state.round_timer + 59) / 60


## Deterministic random 32-bit value from the state RNG (xorshift32).
func rand_u32() -> int:
	var x := state.rng
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	state.rng = x
	return x


## Deterministic random integer in [0, n).
func rand_int(n: int) -> int:
	return rand_u32() % n if n > 0 else 0


## Spawns effect `effect_index` of `owner`'s move `move_index` at `pos` heading `angle`.
func spawn_effect(owner: FighterState, move_index: int, effect_index: int, pos: Vector3i,
		angle: int) -> EffectState:
	var ed: EffectData = fighter_data[owner.slot].moves[move_index].effects[effect_index]
	var e := EffectState.new()
	e.id = state.next_effect_id
	state.next_effect_id += 1
	e.owner = owner.slot
	e.team = owner.team
	e.move_index = move_index
	e.effect_index = effect_index
	e.pos = pos
	e.facing = Fx.wrap_angle(angle)
	e.vel = Fx.dir(e.facing, Fx.mps(ed.speed))
	e.radius = Fx.m(ed.radius)
	e.age = 0
	if owner.move_index == move_index:
		e.skill_slot = owner.move_slot
	e.cast = owner.move_cast
	state.effects.append(e)
	_emit(EventType.EFFECT_SPAWN, owner.slot, -1, ed.id, pos, e.id).cue = ed.cue
	return e


# --- Rounds ------------------------------------------------------------------------------

func _start_round() -> void:
	state.phase = Phase.INTRO
	state.phase_tick = 0
	state.round_tick = 0
	state.round_timer = config.effective_round_frames()
	state.round_winner = -1
	state.freeze = 0
	state.freeze_owner = -1
	state.effects.clear()
	for i in state.hazard_hits.size():
		state.hazard_hits[i] = 0
	var spawns := arena.data.spawn_points
	for f in state.fighters:
		var spawn_index := config.slots[f.slot].spawn
		if spawn_index < 0:
			spawn_index = f.slot
		var spawn := spawns[spawn_index % spawns.size()] if spawns.size() > 0 else Vector2.ZERO
		var soul := f.soul
		var team := f.team
		var max_hp := f.max_hp
		var hard_lock := f.hard_lock
		f.copy_from(FighterState.new())
		f.slot = state.fighters.find(f)
		f.team = team
		f.max_hp = max_hp
		f.hp = max_hp
		f.soul = soul
		f.hard_lock = hard_lock
		f.guard = rules.guard_gauge * 100
		var skills := maxi(SimInput.SKILLS.size(), fighter_data[f.slot].abilities.size())
		f.cooldowns.resize(skills)
		f.cooldown_totals.resize(skills)
		f.dash_charges = dash_max_charges(f)
		f.stagger_max = config.slots[f.slot].stagger_max
		f.stagger = f.stagger_max
		f.pos = Vector3i(Fx.m(spawn.x), 0, Fx.m(spawn.y))
	for f in state.fighters:
		f.facing = _spawn_facing(f)
		var hook := traits[f.slot]
		if hook != null:
			hook.on_round_start(self, f)
	_emit(EventType.ROUND_START, -1, -1, &"", Vector3i.ZERO, state.round_number)


func _spawn_facing(f: FighterState) -> int:
	var sum := Vector3i.ZERO
	var count := 0
	for other in state.fighters:
		if other.team != f.team:
			sum += other.pos
			count += 1
	if count == 0:
		return 0
	var center := Vector3i(sum.x / count, 0, sum.z / count)
	return Fx.angle_of(center.x - f.pos.x, center.z - f.pos.z)


func _advance_phase() -> void:
	match state.phase:
		Phase.INTRO:
			if state.phase_tick > rules.round_intro_frames:
				state.phase = Phase.FIGHT
				state.phase_tick = 1
				_emit(EventType.FIGHT, -1, -1, &"", Vector3i.ZERO, state.round_number)
		Phase.ROUND_END:
			if state.phase_tick > rules.round_end_frames:
				if state.winner_team >= 0:
					state.phase = Phase.MATCH_END
					state.phase_tick = 1
					_emit(EventType.MATCH_END, -1, -1, &"", Vector3i.ZERO, state.winner_team)
				else:
					state.round_number += 1
					_start_round()
					state.phase_tick = 1
	if state.phase == Phase.FIGHT and state.freeze == 0:
		state.round_tick += 1
		if state.round_timer > 0:
			state.round_timer -= 1


func _check_round_end() -> void:
	if state.phase != Phase.FIGHT:
		return
	var alive_teams := PackedInt32Array()
	for f in state.fighters:
		if not f.ko and not f.team in alive_teams:
			alive_teams.append(f.team)
	var decided := false
	var winner := -1
	if alive_teams.size() <= 1:
		decided = true
		winner = alive_teams[0] if alive_teams.size() == 1 else -1
	elif state.round_timer == 0:
		decided = true
		_emit(EventType.TIME_UP, -1, -1, &"", Vector3i.ZERO, 0)
		winner = _best_hp_team(alive_teams)
	if not decided:
		return
	state.phase = Phase.ROUND_END
	state.phase_tick = 0
	state.round_winner = winner
	if winner >= 0:
		if state.team_wins.size() <= winner:
			state.team_wins.resize(winner + 1)
		state.team_wins[winner] += 1
		if state.team_wins[winner] >= config.effective_rounds_to_win():
			state.winner_team = winner
	_emit(EventType.ROUND_END, -1, -1, &"", Vector3i.ZERO, winner)


## Team with the highest HP percentage (summed over its fighters), -1 on a tie.
func _best_hp_team(teams: PackedInt32Array) -> int:
	var best := -1
	var best_hp := 0
	var best_max := 1
	var tie := false
	for team in teams:
		var hp := 0
		var max_hp := 0
		for f in state.fighters:
			if f.team == team:
				hp += maxi(0, f.hp)
				max_hp += f.max_hp
		if best < 0 or hp * best_max > best_hp * max_hp:
			best = team
			best_hp = hp
			best_max = max_hp
			tie = false
		elif hp * best_max == best_hp * max_hp:
			tie = true
	return -1 if tie else best


# --- Input and targeting ----------------------------------------------------------------

func _read_input(f: FighterState, frame: int, accept: bool) -> void:
	var held := SimInput.buttons_of(frame)
	f.pressed = (held & ~f.buttons) if accept else 0
	f.buttons = held
	f.stick_x = SimInput.stick_x(frame) if accept else 0
	f.stick_z = SimInput.stick_z(frame) if accept else 0
	f.aim_x = SimInput.aim_x(frame) if accept else 0
	f.aim_z = SimInput.aim_z(frame) if accept else 0
	f.aim_point = accept and SimInput.aim_is_point(frame)
	if not accept:
		f.buffer = 0
		return
	var frozen := f.hitstop > 0 or state.freeze > 0
	var newest := 0
	for bit in BUFFER_PRIORITY:
		if f.pressed & bit:
			newest = bit
			break
	if newest != 0:
		f.buffer = newest
		f.buffer_age = 0
	elif f.buffer != 0 and not frozen:
		f.buffer_age += 1
		if f.buffer_age > rules.buffer_frames:
			f.buffer = 0
	if f.pressed & SimInput.DODGE:
		f.dodge_age = 0
	elif f.dodge_age < 999 and not frozen:
		f.dodge_age += 1
	if f.pressed & SimInput.LOCK:
		_cycle_lock(f, true)
	elif f.pressed & SimInput.TARGET_NEXT:
		_cycle_lock(f, false)


func _cycle_lock(f: FighterState, can_unlock: bool) -> void:
	var enemies := enemies_of(f)
	if enemies.is_empty():
		f.hard_lock = false
		return
	if not f.hard_lock:
		f.hard_lock = true
		f.target = _nearest(f, enemies).slot
	else:
		var next := -1
		for enemy in enemies:
			if enemy.slot > f.target:
				next = enemy.slot
				break
		if next < 0:
			if can_unlock:
				f.hard_lock = false
				return
			next = enemies[0].slot
		f.target = next
	_emit(EventType.LOCK_ON, f.slot, f.target if f.hard_lock else -1, &"", f.pos, 0)


func _update_targets() -> void:
	for f in state.fighters:
		var enemies := enemies_of(f)
		if enemies.is_empty():
			f.target = -1
			f.hard_lock = false
			continue
		if f.hard_lock:
			if f.target >= 0 and not state.fighters[f.target].ko and state.fighters[f.target].team != f.team:
				continue
			f.target = _nearest(f, enemies).slot
		else:
			f.target = _nearest(f, enemies).slot


func _nearest(f: FighterState, candidates: Array[FighterState]) -> FighterState:
	var best: FighterState = null
	var best_d := 0
	for other in candidates:
		var d := Fx.dist2_xz(f.pos, other.pos)
		if best == null or d < best_d:
			best = other
			best_d = d
	return best


## The target an attack starting now should face: the hard-lock target, else the nearest
## enemy within soft_lock_cone of the stick, else the nearest within soft_lock_range.
func attack_target(f: FighterState) -> FighterState:
	if f.hard_lock and f.target >= 0:
		return state.fighters[f.target]
	var enemies := enemies_of(f)
	if enemies.is_empty():
		return null
	var range2 := Fx.m(rules.soft_lock_range)
	range2 *= range2
	if _stick_active(f):
		var stick_angle := Fx.angle_of(f.stick_x, f.stick_z)
		var cone := Fx.deg(rules.soft_lock_cone)
		var in_cone: Array[FighterState] = []
		for enemy in enemies:
			var to := Fx.angle_of(enemy.pos.x - f.pos.x, enemy.pos.z - f.pos.z)
			if absi(Fx.angle_diff(stick_angle, to)) <= cone and Fx.dist2_xz(f.pos, enemy.pos) <= range2:
				in_cone.append(enemy)
		if not in_cone.is_empty():
			return _nearest(f, in_cone)
	var nearest := _nearest(f, enemies)
	if Fx.dist2_xz(f.pos, nearest.pos) <= range2:
		return nearest
	return null


## The world point (y = 0) `f` aims at, at most `reach` units away (0 = aim_assist_range):
## 1. hard lock: the locked target;
## 2. a cursor point (SimInput.AIM_POINT): that point;
## 3. a stick direction: the nearest enemy within aim_assist_degrees of it and within reach,
##    else along it (`ground`: reach × deflection, at least aim_min_ground_range; else reach);
## 4. no aim: the soft-lock target (attack_target), else along facing.
## Points beyond reach are pulled in to reach.
func aim_point(f: FighterState, reach: int = 0, ground: bool = false) -> Vector3i:
	var origin := Vector3i(f.pos.x, 0, f.pos.z)
	if reach <= 0:
		reach = Fx.m(rules.aim_assist_range)
	var min_ground := mini(reach, Fx.m(rules.aim_min_ground_range))
	if f.hard_lock and f.target >= 0:
		return _clamp_point(origin, state.fighters[f.target].pos, reach)
	if f.aim_point:
		return _clamp_point(origin, origin + Vector3i(f.aim_x * SimInput.AIM_UNIT, 0, f.aim_z * SimInput.AIM_UNIT), reach)
	if f.aim_x != 0 or f.aim_z != 0:
		var angle := Fx.angle_of(f.aim_x, f.aim_z)
		var assisted := _assist_target(f, angle, mini(reach, Fx.m(rules.aim_assist_range)))
		if assisted != null:
			return _clamp_point(origin, assisted.pos, reach)
		var dist := reach
		if ground:
			var deflection := mini(Fx.isqrt(f.aim_x * f.aim_x + f.aim_z * f.aim_z), SimInput.AIM_MAX)
			dist = maxi(min_ground, reach * deflection / SimInput.AIM_MAX)
		return origin + Fx.dir(angle, dist)
	var target := attack_target(f)
	if target != null:
		return _clamp_point(origin, target.pos, reach)
	return origin + Fx.dir(f.facing, min_ground if ground else reach)


## Facing angle toward aim_point(f) (current facing when the point is under the fighter).
func aim_angle(f: FighterState) -> int:
	var point := aim_point(f)
	if point.x == f.pos.x and point.z == f.pos.z:
		return f.facing
	return Fx.angle_of(point.x - f.pos.x, point.z - f.pos.z)


func _clamp_point(origin: Vector3i, point: Vector3i, reach: int) -> Vector3i:
	var flat := Vector3i(point.x, 0, point.z)
	if Fx.dist_xz(origin, flat) <= reach:
		return flat
	return origin + Fx.with_length_xz(flat - origin, reach)


func _assist_target(f: FighterState, angle: int, reach: int) -> FighterState:
	var cone := Fx.deg(rules.aim_assist_degrees)
	var in_cone: Array[FighterState] = []
	for enemy in enemies_of(f):
		if Fx.dist2_xz(f.pos, enemy.pos) > reach * reach:
			continue
		if absi(Fx.angle_diff(angle, _angle_to(f, enemy))) <= cone:
			in_cone.append(enemy)
	return _nearest(f, in_cone) if not in_cone.is_empty() else null


## The nearest enemy within `dist` units in front of `f` (within 60° of facing), or null.
func _enemy_ahead(f: FighterState, dist: int) -> FighterState:
	var ahead: Array[FighterState] = []
	for enemy in enemies_of(f):
		if Fx.dist2_xz(f.pos, enemy.pos) <= dist * dist \
				and absi(Fx.angle_diff(f.facing, _angle_to(f, enemy))) <= Fx.TURN / 6:
			ahead.append(enemy)
	return _nearest(f, ahead) if not ahead.is_empty() else null


func _stick_active(f: FighterState) -> bool:
	return f.stick_x * f.stick_x + f.stick_z * f.stick_z > STICK_DEADZONE * STICK_DEADZONE


func _stick_angle(f: FighterState) -> int:
	return Fx.angle_of(f.stick_x, f.stick_z)


func _target_of(f: FighterState) -> FighterState:
	return state.fighters[f.target] if f.target >= 0 else null


func _angle_to(f: FighterState, other: FighterState) -> int:
	return Fx.angle_of(other.pos.x - f.pos.x, other.pos.z - f.pos.z)


# --- Fighter update ---------------------------------------------------------------------

func _update_fighter(f: FighterState) -> void:
	if f.hitstop > 0:
		f.hitstop -= 1
		return
	f.action_tick += 1
	if f.ko:
		_physics(f)
		return
	match f.action:
		Action.IDLE:
			_idle(f)
		Action.JUMP_SQUAT:
			if f.action_tick > fighter_data[f.slot].jump_squat:
				_takeoff(f)
		Action.AIR:
			_air(f)
		Action.LAND:
			if f.action_tick > f.action_len:
				_to_idle(f)
		Action.DODGE:
			_dodge(f)
		Action.AIR_DODGE:
			_air_dodge(f)
		Action.DASH:
			_dashing(f)
		Action.GUARD:
			_guarding(f)
		Action.ATTACK:
			_attack(f)
		_:
			_reaction(f)
	_physics(f)
	var hook := traits[f.slot]
	if hook != null:
		hook.on_tick(self, f)


func _set_action(f: FighterState, action: Action, length: int = 0) -> void:
	f.action = action
	f.action_tick = 1
	f.action_len = length
	f.action_variant = 0
	if action != Action.ATTACK:
		f.move_index = -1
		f.move_frame = 0
		f.move_slot = -1
		f.charging = false


## Ends the current action into IDLE (or AIR) and lets it act on the same tick.
func _to_idle(f: FighterState) -> void:
	if f.grounded:
		_set_action(f, Action.IDLE)
		_idle(f)
	else:
		_set_action(f, Action.AIR)
		_air(f)


func _idle(f: FighterState) -> void:
	if f.buffer == 0 and f.buttons & SimInput.BASIC and fighter_data[f.slot].is_skill_kit():
		f.buffer = SimInput.BASIC
		f.buffer_age = 0
	if _try_action(f, false):
		return
	if f.buttons & SimInput.GUARD:
		_start_guard(f)
		return
	_run(f, 100)


func _start_guard(f: FighterState) -> void:
	_set_action(f, Action.GUARD)
	if f.pressed & SimInput.GUARD and f.parry_lockout == 0:
		f.parry_timer = fighter_data[f.slot].parry_window
	_guard_move(f)


func _guarding(f: FighterState) -> void:
	if not (f.buttons & SimInput.GUARD):
		_to_idle(f)
		return
	if _try_action(f, false):
		return
	_guard_move(f)


## Guarding moves slowly without turning (hard lock still faces the target), so hits
## from behind stay possible.
func _guard_move(f: FighterState) -> void:
	var facing := f.facing
	_run(f, rules.guard_speed_percent)
	if not f.hard_lock:
		f.facing = facing


## Whether guard blocks hits now (guard up and not in startup).
func guard_up(f: FighterState) -> bool:
	return (f.action == Action.GUARD and f.action_tick > rules.guard_startup) or f.action == Action.BLOCKSTUN


## Starts the buffered action if possible. Returns true when something started.
func _try_action(f: FighterState, airborne: bool) -> bool:
	if f.buffer == 0:
		return false
	var data := fighter_data[f.slot]
	var bit := f.buffer
	var skill := SimInput.SKILLS.find(bit)
	if skill >= 0:
		if skill >= data.abilities.size():
			return false
		if f.skill_next[skill] >= 0:
			return _try_move(f, f.skill_next[skill], bit)
		if f.cooldowns[skill] == 0 and f.skill_window[skill] == 0:
			return _try_move(f, data.find_move(data.abilities[skill]), bit)
		return false
	match bit:
		SimInput.SUPER:
			return _try_move(f, data.find_move(data.super_move), bit)
		SimInput.GRAB:
			return not airborne and _try_move(f, data.find_move(data.grab), bit)
		SimInput.HEAVY:
			return _try_move(f, data.find_move(data.air_heavy if airborne else data.heavy), bit)
		SimInput.LIGHT:
			if airborne:
				return _try_move(f, data.find_move(data.air_light), bit)
			if data.run_light != &"" and _is_running(f):
				return _try_move(f, data.find_move(data.run_light), bit)
			return _try_move(f, data.find_move(data.light), bit)
		SimInput.DODGE:
			if data.dash != null:
				if airborne or f.dash_charges <= 0:
					return false
				_start_dash(f)
				return true
			if airborne:
				if f.air_dodge_used:
					return false
				_start_air_dodge(f)
				return true
			if f.dodge_lockout > 0:
				return false
			_start_dodge(f)
			return true
		SimInput.JUMP:
			if airborne:
				if f.jumps_used >= data.jumps:
					return false
				f.buffer = 0
				_takeoff(f)
				return true
			f.buffer = 0
			_set_action(f, Action.JUMP_SQUAT)
			return true
	return false


func _is_running(f: FighterState) -> bool:
	var speed := Fx.length_xz(f.vel)
	return _stick_active(f) and speed * 10 >= Fx.mps(fighter_data[f.slot].run_speed) * 8


func _try_move(f: FighterState, move_index: int, bit: int) -> bool:
	if move_index < 0:
		return false
	var move := fighter_data[f.slot].moves[move_index]
	if f.grounded and not move.ground_ok:
		return false
	if not f.grounded and not (move.aerial or move.air_ok):
		return false
	if move.soul_cost > 0 and f.soul < move.soul_cost * 100:
		return false
	var hook := traits[f.slot]
	if hook != null and not hook.can_start_move(self, f, move):
		return false
	start_move(f, move_index, bit)
	return true


## Starts move `move_index` on `f` this tick (frame 1). Public for traits and tests.
func start_move(f: FighterState, move_index: int, bit: int = 0) -> void:
	var data := fighter_data[f.slot]
	var move := data.moves[move_index]
	_set_action(f, Action.ATTACK)
	f.move_index = move_index
	f.move_frame = 1
	f.move_button = bit
	f.move_contact = 0
	f.move_cast += 1
	f.move_hit_masks.fill(0)
	f.charge = 0
	f.charging = false
	f.armor_left = move.armor_hits
	f.landing_recovery = 0
	f.buffer = 0
	f.charge_level = 0
	f.charge_perfect = false
	f.move_slot = SimInput.SKILLS.find(bit) if bit != 0 else -1
	if f.move_slot < 0 and move.kind == MoveData.Kind.ABILITY:
		f.move_slot = data.abilities.find(move.id)
	if f.move_slot >= 0:
		_skill_cast(f, f.move_slot, move_index, move)
	if move.soul_cost > 0:
		f.soul -= move.soul_cost * 100
	var target := attack_target(f)
	if move.is_aimed():
		_aim_move(f, move)
	elif target != null:
		f.facing = _angle_to(f, target)
	elif _stick_active(f):
		f.facing = _stick_angle(f)
	if move.flash_frames > 0:
		state.freeze = move.flash_frames
		state.freeze_owner = f.slot
		_emit(EventType.SUPER_FLASH, f.slot, -1, move.id, f.pos, move.flash_frames)
	_emit(EventType.MOVE_START, f.slot, target.slot if target != null else -1, move.id, f.pos, move_index).cue = move.cue
	var hook := traits[f.slot]
	if hook != null:
		hook.on_move_start(self, f, move)
	_move_frame_effects(f, move)


## Cooldown and combo/chain bookkeeping when slot `s` casts `move`.
func _skill_cast(f: FighterState, s: int, move_index: int, move: MoveData) -> void:
	var follow := f.skill_next[s] == move_index
	f.skill_next[s] = -1
	f.skill_window[s] = 0
	var sequence := move.follow_up != &"" or move.chain_move != &""
	if not follow and not sequence:
		if move.cooldown > 0:
			_start_cooldown(f, s, move.cooldown)
		return
	if not follow:
		f.skill_pending[s] = move.cooldown
	if sequence:
		f.skill_part[s] = move_index
		f.skill_window[s] = _arming_frames(move)
	else:
		_end_skill_sequence(f, s)


func _start_cooldown(f: FighterState, s: int, frames: int) -> void:
	f.cooldowns[s] = frames
	f.cooldown_totals[s] = frames


## Frames a sequence part waits for its hit: the move plus its effects' lifetimes.
static func _arming_frames(move: MoveData) -> int:
	var last := move.total_frames()
	for ed in move.effects:
		last = maxi(last, ed.spawn_frame + ed.delay + ed.lifetime)
	return last + 1


func _end_skill_sequence(f: FighterState, s: int) -> void:
	f.skill_next[s] = -1
	f.skill_window[s] = 0
	f.skill_part[s] = -1
	if f.skill_pending[s] > 0:
		_start_cooldown(f, s, f.skill_pending[s])
	f.skill_pending[s] = 0


## A sequence part connected: its slot now casts the follow-up / chain move.
func _arm_follow_up(a: FighterState, s: int, move: MoveData) -> void:
	if s < 0 or a.skill_next[s] >= 0 or a.skill_window[s] == 0:
		return
	var data := fighter_data[a.slot]
	if a.skill_part[s] < 0 or data.moves[a.skill_part[s]] != move:
		return
	var next_id := move.follow_up if move.follow_up != &"" else move.chain_move
	var next := data.find_move(next_id)
	if next < 0:
		return
	a.skill_next[s] = next
	a.skill_window[s] = move.follow_up_window if move.follow_up != &"" else move.chain_frames
	_emit(EventType.CHAIN_READY, a.slot, -1, next_id, a.pos, s)


## The move skill slot `s` casts now (combo/chain part or its skill), or null.
func skill_move(f: FighterState, s: int) -> MoveData:
	var data := fighter_data[f.slot]
	if f.skill_next[s] >= 0:
		return data.moves[f.skill_next[s]]
	return data.move_by_id(data.abilities[s]) if s < data.abilities.size() else null


## Whether skill slot `s` can be cast as far as cooldowns and sequences go.
func skill_ready(f: FighterState, s: int) -> bool:
	if s >= fighter_data[f.slot].abilities.size():
		return false
	return f.skill_next[s] >= 0 or (f.cooldowns[s] == 0 and f.skill_window[s] == 0)


## Snaps an aimed move toward the aim and stores its aim point.
func _aim_move(f: FighterState, move: MoveData) -> void:
	if move.aims_at_point():
		f.move_point = aim_point(f, Fx.m(move.max_range), true)
	else:
		f.move_point = aim_point(f)
	if f.move_point.x != f.pos.x or f.move_point.z != f.pos.z:
		f.facing = Fx.angle_of(f.move_point.x - f.pos.x, f.move_point.z - f.pos.z)


func _attack(f: FighterState) -> void:
	var move := current_move(f)
	var advanced := true
	if f.charging:
		if (f.buttons & f.move_button) and f.charge < move.charge_max:
			f.charge += 1
			advanced = false
			_charge_events(f, move)
		else:
			f.charging = false
			if _release_charge(f, move, (f.buttons & f.move_button) != 0):
				return
	if advanced:
		f.move_frame += 1
		if move.hold_end > 0 and f.move_frame > move.hold_start and f.move_frame <= move.hold_end \
				and not (f.buttons & f.move_button):
			f.move_frame = move.hold_end + 1
		if move.chargeable and f.move_frame == move.charge_frame:
			if f.buttons & f.move_button:
				f.charging = true
			elif not move.charge_levels.is_empty() and _release_charge(f, move, false):
				return
	if f.move_frame > move.total_frames():
		if move.next_light != &"" and f.buttons & SimInput.BASIC and move.is_basic() \
				and fighter_data[f.slot].is_skill_kit() \
				and _try_move(f, fighter_data[f.slot].find_move(move.next_light), SimInput.BASIC):
			return
		_to_idle(f)
		return
	if _try_chain_or_cancel(f, move):
		return
	if advanced:
		_move_frame_effects(f, move)
	else:
		_move_motion(f, move)


func _charge_events(f: FighterState, move: MoveData) -> void:
	var level := move.charge_levels.find(f.charge) + 1
	if level > 0:
		_emit(EventType.CHARGE_LEVEL, f.slot, -1, move.id, f.pos, level)
	if move.perfect_end > 0 and f.charge == move.perfect_start:
		var reached := 0
		for threshold in move.charge_levels:
			if f.charge >= threshold:
				reached += 1
		_emit(EventType.CHARGE_LEVEL, f.slot, -1, move.id, f.pos, reached).flags = SimEvent.FLAG_PERFECT


## Settles the charge level when the charge ends. Returns true if it started another move
## (early release).
func _release_charge(f: FighterState, move: MoveData, auto: bool) -> bool:
	f.charge_level = 0
	for threshold in move.charge_levels:
		if f.charge >= threshold:
			f.charge_level += 1
	f.charge_perfect = not auto and move.perfect_end > 0 and f.charge >= move.perfect_start \
			and f.charge <= move.perfect_end
	if f.charge_level == 0 and not move.charge_levels.is_empty() and move.early_release_move != &"":
		var early := fighter_data[f.slot].find_move(move.early_release_move)
		if early >= 0:
			var slot := f.move_slot
			start_move(f, early, f.move_button)
			f.move_slot = slot
			return true
	if move.aims_at_point():
		_aim_move(f, move)
	return false


## Chains (next_light / next_heavy from the end of active frames) and cancel windows.
func _try_chain_or_cancel(f: FighterState, move: MoveData) -> bool:
	if f.buffer == 0:
		return false
	var data := fighter_data[f.slot]
	var frame := f.move_frame
	if frame > move.last_active_frame():
		if f.buffer == SimInput.LIGHT and move.next_light != &"":
			return _try_move(f, data.find_move(move.next_light), SimInput.LIGHT)
		if f.buffer == SimInput.HEAVY and move.next_heavy != &"":
			return _try_move(f, data.find_move(move.next_heavy), SimInput.HEAVY)
	if _default_cancel_allows(f, move, f.buffer):
		return _try_action(f, not f.grounded)
	var allowed := _cancel_mask(f, move)
	if allowed == 0:
		return false
	var want := CancelData.INTO_ABILITY if SimInput.SKILLS.has(f.buffer) else 0
	match f.buffer:
		SimInput.SUPER:
			want = CancelData.INTO_SUPER
		SimInput.JUMP:
			want = CancelData.INTO_JUMP
		SimInput.DODGE:
			want = CancelData.INTO_DODGE
		SimInput.LIGHT:
			want = CancelData.INTO_LIGHT
		SimInput.HEAVY:
			want = CancelData.INTO_HEAVY
	if not (allowed & want):
		return false
	return _try_action(f, not f.grounded)


## The universal cancels: skills and the awakening from skill_cancel_frame (never into the
## same slot), skill-kit dashes from dash_cancel_frame.
func _default_cancel_allows(f: FighterState, move: MoveData, bit: int) -> bool:
	var skill := SimInput.SKILLS.find(bit)
	if skill >= 0 or bit == SimInput.SUPER:
		if skill >= 0 and skill == f.move_slot and f.skill_next[skill] < 0:
			return false
		var from := skill_cancel_frame(move)
		return from > 0 and f.move_frame >= from
	if bit == SimInput.DODGE and fighter_data[f.slot].is_skill_kit():
		var from := dash_cancel_frame(move)
		return from > 0 and f.move_frame >= from
	return false


## Extra cancel targets (MoveData.cancels) allowed on the current frame of `move`.
func _cancel_mask(f: FighterState, move: MoveData) -> int:
	var frame := f.move_frame
	var mask := 0
	for cancel in move.cancels:
		if frame < cancel.start_frame or frame > cancel.end_frame:
			continue
		match cancel.condition:
			CancelData.Condition.ON_CONTACT:
				if f.move_contact < 1:
					continue
			CancelData.Condition.ON_HIT:
				if f.move_contact < 2:
					continue
		mask |= cancel.into
	return mask


## Everything a move does on a newly reached frame: motion, tracking, teleport, effects, buff.
func _move_frame_effects(f: FighterState, move: MoveData) -> void:
	_move_motion(f, move)
	var frame := f.move_frame
	if move.counter_window_end > 0 and frame == move.counter_window_start:
		_emit(EventType.COUNTER_WINDOW, f.slot, -1, move.id, f.pos, move.counter_window_end - frame + 1)
	if move.teleport != null and frame == move.teleport.frame:
		_teleport(f, move.teleport)
	for hb in move.hitboxes:
		if hb.rehit_frames > 0:
			var first := hb.start_frame if hb.start_frame >= 0 else move.startup
			if frame > first and (frame - first) % hb.rehit_frames == 0:
				f.move_hit_masks[clampi(hb.group, 0, 7)] = 0
	for i in move.effects.size():
		var ed := move.effects[i]
		if ed.spawn_frame == frame and (f.charge_perfect or not ed.requires_perfect):
			_spawn_move_effect(f, move, i)
	if move.mark_hit != null and frame == (move.mark_frame if move.mark_frame > 0 else move.startup):
		_detonate_marks(f, move)
	if move.buff != null and frame == move.buff_frame:
		apply_buff(f, move.buff, f.move_index)


func _move_motion(f: FighterState, move: MoveData) -> void:
	var frame := f.move_frame
	var target := _target_of(f)
	var tracking := _tracking_of(move)
	var aimed := move.is_aimed()
	var follows_aim := aimed and not move.aims_at_point()
	if frame < move.startup and tracking > 0:
		if follows_aim:
			f.facing = Fx.turn_toward(f.facing, aim_angle(f), tracking)
		elif not aimed and target != null:
			f.facing = Fx.turn_toward(f.facing, _angle_to(f, target), tracking)
	var moved := false
	var travel_done := false
	for motion in move.motions:
		if frame > motion.end_frame and motion.aim_travel != MotionData.AimTravel.NONE:
			travel_done = true
		if frame < motion.start_frame or frame > motion.end_frame:
			continue
		if motion.homing and tracking > 0:
			if follows_aim:
				f.facing = Fx.turn_toward(f.facing, aim_angle(f), tracking)
			elif not aimed and target != null:
				f.facing = Fx.turn_toward(f.facing, _angle_to(f, target), tracking)
		var forward := Fx.mps(motion.forward_speed)
		if motion.stop_at_distance > 0.0:
			var stop := Fx.m(motion.stop_at_distance)
			if aimed:
				if _enemy_ahead(f, stop) != null:
					forward = 0
			elif target != null and Fx.dist_xz(f.pos, target.pos) <= stop:
				forward = 0
		var v := Fx.rotate(Vector3i(Fx.mps(motion.side_speed), 0, forward), f.facing)
		if motion.aim_travel != MotionData.AimTravel.NONE:
			var to_point := Vector3i(f.move_point.x - f.pos.x, 0, f.move_point.z - f.pos.z)
			var remaining := Fx.length_xz(to_point)
			var speed := mini(forward, remaining)
			if motion.aim_travel == MotionData.AimTravel.ARRIVE:
				speed = remaining / maxi(1, motion.end_frame - frame + 1)
			v = Fx.with_length_xz(to_point, speed)
		f.vel.x = v.x
		f.vel.z = v.z
		if frame == motion.start_frame and motion.up_speed > 0.0:
			f.vel.y = Fx.mps(motion.up_speed)
			f.grounded = false
		moved = true
	if move.hold_steer_percent > 0 and frame >= move.hold_start and frame <= move.hold_end:
		var facing := f.facing
		_run(f, move.hold_steer_percent)
		f.facing = facing
		moved = true
	if not moved and travel_done:
		f.vel.x = 0
		f.vel.z = 0
	elif not moved and f.grounded:
		_brake(f)


func _tracking_of(move: MoveData) -> int:
	if move.tracking >= 0.0:
		return Fx.deg(move.tracking)
	match move.kind:
		MoveData.Kind.LIGHT, MoveData.Kind.AIR_LIGHT, MoveData.Kind.GRAB:
			return Fx.deg(rules.light_tracking)
		MoveData.Kind.HEAVY, MoveData.Kind.AIR_HEAVY, MoveData.Kind.GETUP_ATTACK:
			return Fx.deg(rules.heavy_tracking)
	return Fx.deg(rules.ability_tracking)


func _teleport(f: FighterState, tp: TeleportData) -> void:
	var from := f.pos
	match tp.mode:
		TeleportData.Mode.STICK:
			var angle := _stick_angle(f) if _stick_active(f) else f.facing
			f.pos += Fx.dir(angle, Fx.m(tp.distance))
		TeleportData.Mode.FORWARD:
			f.pos += Fx.dir(f.facing, Fx.m(tp.distance))
		TeleportData.Mode.AIM_POINT:
			var move := current_move(f)
			var reach := Fx.m(tp.max_range)
			var origin := Vector3i(f.pos.x, 0, f.pos.z)
			var point := _clamp_point(origin, f.move_point, reach) if move != null and move.aims_at_point() \
					else aim_point(f, reach, true)
			f.pos = Vector3i(point.x, f.pos.y, point.z)
		TeleportData.Mode.BEHIND_TARGET:
			var target := _target_of(f)
			if target == null or Fx.dist_xz(f.pos, target.pos) > Fx.m(tp.max_range):
				return
			var away := Fx.angle_of(target.pos.x - f.pos.x, target.pos.z - f.pos.z)
			f.pos = Vector3i(target.pos.x, f.pos.y, target.pos.z) + Fx.dir(away, Fx.m(tp.distance))
			f.facing = Fx.wrap_angle(away + Fx.HALF_TURN)
	f.pos = arena.push_circle(f.pos, _radius[f.slot])
	_emit(EventType.TELEPORT, f.slot, -1, &"", from, 0)


func _spawn_move_effect(f: FighterState, move: MoveData, effect_index: int) -> void:
	var ed := move.effects[effect_index]
	var base := f.pos
	var offset := Fx.rotate(Fx.v3(ed.offset), f.facing)
	if ed.anchor == EffectData.Anchor.TARGET:
		var target := _target_of(f)
		var max_range := Fx.m(ed.max_range)
		var origin := Vector3i(f.pos.x, 0, f.pos.z)
		var spot: Vector3i
		if move.aims_at_point():
			spot = _clamp_point(origin, f.move_point, max_range)
		elif move.is_aimed():
			spot = aim_point(f, max_range, true)
		elif target != null:
			spot = Vector3i(target.pos.x, 0, target.pos.z)
			if Fx.dist_xz(f.pos, spot) > max_range:
				spot = Vector3i(f.pos.x, 0, f.pos.z) + Fx.with_length_xz(spot - Vector3i(f.pos.x, 0, f.pos.z), max_range)
		else:
			spot = Vector3i(f.pos.x, 0, f.pos.z) + Fx.dir(f.facing, max_range)
		base = spot
		offset = Vector3i(0, Fx.m(ed.offset.y), 0)
	var spawned: Array[EffectState] = []
	var count := maxi(1, ed.count)
	var spread := Fx.deg(ed.spread_degrees)
	for k in count:
		var angle := f.facing
		if count > 1:
			angle += -spread / 2 + spread * k / (count - 1)
		spawned.append(spawn_effect(f, f.move_index, effect_index, base + offset, angle))
	var hook := traits[f.slot]
	if hook != null:
		hook.on_effects_spawned(self, f, move, effect_index, spawned)


## Adds a buff from `data` (source: owner move index, -1 parry buff, -2 trait).
func apply_buff(f: FighterState, data: BuffData, source: int) -> void:
	for existing in f.buffs:
		if existing.source == source:
			f.buffs.erase(existing)
			break
	var buff := BuffState.new()
	buff.source = source
	buff.ticks_left = data.duration
	buff.uses_left = data.uses
	buff.after_cast = f.move_cast
	buff.damage_bonus_percent = data.damage_bonus_percent
	buff.speed_bonus_percent = data.speed_bonus_percent
	f.buffs.append(buff)
	_emit(EventType.BUFF, f.slot, -1, data.id, f.pos, data.duration).cue = data.cue


func _run(f: FighterState, speed_percent: int) -> void:
	var data := fighter_data[f.slot]
	var full := Fx.mps(data.run_speed)
	var top := full * speed_percent / 100 * (100 + _buff_speed(f)) / 100
	var desired := Vector3i.ZERO
	var active := _stick_active(f)
	if active:
		var mag := Fx.isqrt(f.stick_x * f.stick_x + f.stick_z * f.stick_z)
		var den := maxi(mag, SimInput.STICK_MAX)
		desired = Vector3i(f.stick_x * top / den, 0, f.stick_z * top / den)
	var frames := maxi(1, data.accel_frames if active else data.stop_frames)
	var rate := (full + frames - 1) / frames
	var dx := desired.x - f.vel.x
	var dz := desired.z - f.vel.z
	var dist := Fx.isqrt(dx * dx + dz * dz)
	if dist <= rate:
		f.vel.x = desired.x
		f.vel.z = desired.z
	else:
		f.vel.x += dx * rate / dist
		f.vel.z += dz * rate / dist
	var target := _target_of(f)
	var turn := Fx.deg(data.turn_degrees)
	if f.hard_lock and target != null:
		f.facing = Fx.turn_toward(f.facing, _angle_to(f, target), turn)
	elif active:
		f.facing = Fx.turn_toward(f.facing, _stick_angle(f), turn)


func _buff_speed(f: FighterState) -> int:
	var total := 0
	for buff in f.buffs:
		total += buff.speed_bonus_percent
	return total


## Decelerates horizontal velocity at the fighter's stopping rate.
func _brake(f: FighterState) -> void:
	var data := fighter_data[f.slot]
	var frames := maxi(1, data.stop_frames)
	var rate := (Fx.mps(data.run_speed) + frames - 1) / frames
	var speed := Fx.length_xz(f.vel)
	if speed <= rate:
		f.vel.x = 0
		f.vel.z = 0
	else:
		f.vel.x -= f.vel.x * rate / speed
		f.vel.z -= f.vel.z * rate / speed


func _takeoff(f: FighterState) -> void:
	f.jumps_used += 1
	f.grounded = false
	f.vel.y = _jump_speed[f.slot]
	_set_action(f, Action.AIR)
	_emit(EventType.JUMP, f.slot, -1, &"", f.pos, f.jumps_used)


func _air(f: FighterState) -> void:
	if _try_action(f, true):
		return
	var data := fighter_data[f.slot]
	var full := Fx.mps(data.run_speed)
	if _stick_active(f):
		var mag := maxi(Fx.isqrt(f.stick_x * f.stick_x + f.stick_z * f.stick_z), SimInput.STICK_MAX)
		var desired := Vector3i(f.stick_x * full / mag, 0, f.stick_z * full / mag)
		var rate := roundi(full / maxi(1, data.accel_frames) * data.air_control)
		var dx := desired.x - f.vel.x
		var dz := desired.z - f.vel.z
		var dist := Fx.isqrt(dx * dx + dz * dz)
		if dist <= rate:
			f.vel.x = desired.x
			f.vel.z = desired.z
		elif dist > 0:
			f.vel.x += dx * rate / dist
			f.vel.z += dz * rate / dist
	var target := _target_of(f)
	if f.hard_lock and target != null:
		f.facing = Fx.turn_toward(f.facing, _angle_to(f, target), Fx.deg(data.turn_degrees))


func _start_dodge(f: FighterState) -> void:
	f.buffer = 0
	_set_action(f, Action.DODGE, fighter_data[f.slot].dodge_frames)
	f.move_dir = _stick_angle(f) if _stick_active(f) else Fx.wrap_angle(f.facing + Fx.HALF_TURN)
	f.perfect_dodge_used = false
	_emit(EventType.DODGE, f.slot, -1, &"", f.pos, f.move_dir)
	_dodge_motion(f)


func _dodge(f: FighterState) -> void:
	var data := fighter_data[f.slot]
	if f.action_tick > data.dodge_frames:
		f.dodge_lockout = data.dodge_cooldown
		_to_idle(f)
		return
	_dodge_motion(f)


func _dodge_motion(f: FighterState) -> void:
	var data := fighter_data[f.slot]
	if f.action_tick <= data.dodge_move_frames:
		var v := Fx.dir(f.move_dir, Fx.m(data.dodge_distance) / maxi(1, data.dodge_move_frames))
		f.vel.x = v.x
		f.vel.z = v.z
	else:
		f.vel.x = 0
		f.vel.z = 0


func _start_air_dodge(f: FighterState) -> void:
	var data := fighter_data[f.slot]
	f.buffer = 0
	f.air_dodge_used = true
	f.perfect_dodge_used = false
	_set_action(f, Action.AIR_DODGE, data.air_dodge_frames)
	f.move_dir = _stick_angle(f) if _stick_active(f) else Fx.wrap_angle(f.facing + Fx.HALF_TURN)
	var v := Fx.dir(f.move_dir, Fx.m(data.air_dodge_distance) / maxi(1, data.air_dodge_frames))
	f.vel = Vector3i(v.x, maxi(0, f.vel.y), v.z)
	_emit(EventType.DODGE, f.slot, -1, &"", f.pos, f.move_dir)


func _air_dodge(f: FighterState) -> void:
	if f.action_tick > f.action_len:
		_set_action(f, Action.AIR)
		_air(f)


func _start_dash(f: FighterState) -> void:
	var dash := fighter_data[f.slot].dash
	f.buffer = 0
	_spend_dash_charge(f)
	_set_action(f, Action.DASH, dash.frames)
	if _stick_active(f):
		f.move_dir = _stick_angle(f)
	elif f.aim_point or f.aim_x != 0 or f.aim_z != 0:
		f.move_dir = aim_angle(f)
	else:
		f.move_dir = f.facing
	f.facing = f.move_dir
	f.perfect_dodge_used = false
	_emit(EventType.DASH, f.slot, -1, &"", f.pos, f.move_dir)
	_dash_motion(f, dash)


func _dashing(f: FighterState) -> void:
	var dash := fighter_data[f.slot].dash
	if f.action_tick > dash.frames:
		_to_idle(f)
		return
	if f.action_tick >= dash.skill_cancel_frame and _try_action(f, false):
		return
	_dash_motion(f, dash)


## Front-loaded travel whose total is exactly the dash distance.
func _dash_motion(f: FighterState, dash: DashData) -> void:
	var t := f.action_tick
	var frames := maxi(1, dash.travel_frames)
	if t > frames:
		f.vel.x = 0
		f.vel.z = 0
		return
	var dist := dash_distance(f)
	var v := Fx.dir(f.move_dir, _dash_travelled(dash, dist, t) - _dash_travelled(dash, dist, t - 1))
	f.vel.x = v.x
	f.vel.z = v.z


## Distance covered after `t` dash frames: burst_percent by burst_frames, all by travel_frames.
func _dash_travelled(dash: DashData, dist: int, t: int) -> int:
	var frames := maxi(1, dash.travel_frames)
	if t <= 0:
		return 0
	if t >= frames:
		return dist
	var burst := dash.burst_frames
	if burst <= 0 or burst >= frames:
		return dist * t / frames
	var burst_dist := dist * clampi(dash.burst_percent, 0, 100) / 100
	if t <= burst:
		return burst_dist * t / burst
	return burst_dist + (dist - burst_dist) * (t - burst) / (frames - burst)


func _spend_dash_charge(f: FighterState) -> void:
	f.dash_charges -= 1
	if f.dash_recharge == 0:
		f.dash_recharge = dash_recharge_frames(f)


func _quick_rise(f: FighterState, dash: DashData) -> void:
	f.buffer = 0
	_spend_dash_charge(f)
	_set_action(f, Action.GETUP, dash.rise_frames)
	f.action_variant = 2
	f.invuln = dash.rise_invuln
	f.move_dir = _stick_angle(f) if _stick_active(f) else -1
	if f.move_dir >= 0:
		f.facing = f.move_dir
	_emit(EventType.GET_UP, f.slot, -1, &"", f.pos, 3)


## Hit reactions and other non-player-controlled actions.
func _reaction(f: FighterState) -> void:
	match f.action:
		Action.HITSTUN, Action.BLOCKSTUN, Action.GUARD_BREAK, Action.RECOVER, Action.COUNTER_STUN, \
				Action.STAGGERED:
			if (f.action == Action.HITSTUN or f.action == Action.COUNTER_STUN) and _try_burst(f):
				return
			if f.stun > 0:
				f.stun -= 1
				if f.grounded:
					_brake(f)
				return
			if f.action == Action.BLOCKSTUN and (f.buttons & SimInput.GUARD) and f.grounded:
				_set_action(f, Action.GUARD)
				f.action_tick = rules.guard_startup + 1
				_guarding(f)
				return
			_to_idle(f)
		Action.AIR_HITSTUN:
			if _try_burst(f):
				return
			if f.stun > 0:
				f.stun -= 1
			elif f.buffer == SimInput.DODGE:
				_air_tech(f)
		Action.WALL_SPLAT:
			if _try_burst(f):
				return
			if f.stun > 0:
				f.stun -= 1
				return
			if f.grounded:
				_knockdown(f)
			else:
				_set_action(f, Action.AIR_HITSTUN)
				f.stun = 999
		Action.KNOCKDOWN:
			var dash := fighter_data[f.slot].dash
			if dash != null and f.buffer == SimInput.DASH and f.action_tick > dash.rise_after and f.dash_charges > 0:
				_quick_rise(f, dash)
			elif f.action_tick > rules.knockdown_frames:
				_get_up(f)
		Action.GETUP:
			if f.action_tick > f.action_len:
				_to_idle(f)
			elif f.action_variant == 1:
				var v := Fx.dir(f.move_dir, Fx.m(rules.getup_roll_distance) / maxi(1, rules.getup_roll_frames - 6))
				f.vel = Vector3i(v.x, 0, v.z) if f.action_tick <= rules.getup_roll_frames - 6 else Vector3i.ZERO
			elif f.action_variant == 2 and f.move_dir >= 0:
				var rise := fighter_data[f.slot].dash
				var travel := maxi(1, rise.rise_frames - 6)
				var v := Fx.dir(f.move_dir, Fx.m(rise.rise_distance) / travel)
				f.vel = Vector3i(v.x, 0, v.z) if f.action_tick <= travel else Vector3i.ZERO
		Action.TECH:
			match f.action_variant:
				1:
					if f.action_tick > f.action_len:
						_to_idle(f)
					else:
						var v := Fx.dir(f.move_dir, Fx.m(rules.tech_roll_distance) / maxi(1, rules.tech_roll_frames))
						f.vel = Vector3i(v.x, 0, v.z)
				2:
					if f.action_tick > f.action_len:
						_set_action(f, Action.AIR)
						_air(f)
		Action.GRABBED:
			var thrower := state.fighters[f.grab_partner] if f.grab_partner >= 0 else null
			if thrower == null or thrower.grab_partner != f.slot:
				f.grab_partner = -1
				_to_idle(f)
			elif fighter_data[f.slot].is_skill_kit() and _try_burst(f):
				return
			elif f.grab_tech_left > 0:
				if f.pressed & SimInput.GRAB:
					_grab_tech(f, thrower)
				else:
					f.grab_tech_left -= 1
		Action.BURST:
			if f.action_tick > f.action_len:
				_to_idle(f)
			elif f.grounded:
				_brake(f)
		Action.KO:
			pass
		_:
			if f.action_len > 0 and f.action_tick > f.action_len:
				_to_idle(f)


func _air_tech(f: FighterState) -> void:
	f.buffer = 0
	_set_action(f, Action.TECH, rules.air_tech_frames)
	f.action_variant = 2
	f.invuln = rules.air_tech_invuln
	f.vel = Vector3i(0, maxi(f.vel.y, 0), 0)
	f.knock_ticks = 0
	f.bounce_pending = 0
	_emit(EventType.AIR_TECH, f.slot, -1, &"", f.pos, 0)


func _knockdown(f: FighterState) -> void:
	_set_action(f, Action.KNOCKDOWN)
	f.vel = Vector3i.ZERO
	f.knock_ticks = 0
	_emit(EventType.KNOCKDOWN, f.last_attacker, f.slot, &"", f.pos, 0)


func _get_up(f: FighterState) -> void:
	var data := fighter_data[f.slot]
	var wants_attack := f.buffer == SimInput.LIGHT or (f.buttons & SimInput.LIGHT) != 0
	var wants_roll := f.buffer == SimInput.DODGE or (f.buttons & SimInput.DODGE) != 0
	if wants_attack and data.find_move(data.getup_attack) >= 0:
		start_move(f, data.find_move(data.getup_attack), SimInput.LIGHT)
		_emit(EventType.GET_UP, f.slot, -1, data.getup_attack, f.pos, 2)
		return
	f.buffer = 0
	if wants_roll:
		_set_action(f, Action.GETUP, rules.getup_roll_frames)
		f.action_variant = 1
		f.invuln = rules.getup_roll_invuln
		f.move_dir = _stick_angle(f) if _stick_active(f) else Fx.wrap_angle(f.facing + Fx.HALF_TURN)
	else:
		_set_action(f, Action.GETUP, rules.getup_stand_frames)
		f.action_variant = 0
		f.invuln = rules.getup_stand_invuln
	_emit(EventType.GET_UP, f.slot, -1, &"", f.pos, f.action_variant)


## Soul Burst out of hitstun, juggles and wall splats (skill-kit fighters: also throws).
## Skill-kit fighters burst with DASH, others with SUPER.
func _try_burst(f: FighterState) -> bool:
	var button := SimInput.DASH if fighter_data[f.slot].is_skill_kit() else SimInput.SUPER
	if f.buffer != button or f.soul < rules.burst_cost * 100:
		return false
	if f.grab_partner >= 0:
		_release_grab(f)
	f.buffer = 0
	f.soul -= rules.burst_cost * 100
	_set_action(f, Action.BURST, rules.burst_frames)
	f.invuln = rules.burst_invuln
	f.stun = 0
	f.knock_ticks = 0
	f.carried_ticks = 0
	f.bounce_pending = 0
	f.splat_armed = false
	f.vel = Vector3i(0, mini(f.vel.y, 0), 0)
	var reach := Fx.m(rules.burst_radius)
	var push := Fx.m(rules.burst_knockback) / KNOCK_TICKS
	for enemy in enemies_of(f):
		if Fx.dist2_xz(f.pos, enemy.pos) > reach * reach:
			continue
		if enemy.grab_partner >= 0:
			_release_grab(enemy)
		_set_action(enemy, Action.RECOVER)
		enemy.stun = rules.burst_push_stun
		enemy.hitstop = 0
		enemy.knock = Fx.dir(_angle_to(f, enemy), push)
		enemy.knock_ticks = KNOCK_TICKS
		enemy.vel = Vector3i(0, enemy.vel.y, 0)
	_emit(EventType.BURST, f.slot, -1, &"", f.pos, rules.burst_cost)
	return true


func _grab_tech(victim: FighterState, thrower: FighterState) -> void:
	var push := Fx.m(rules.grab_tech_push) / KNOCK_TICKS
	var away := _angle_to(thrower, victim)
	for f: FighterState in [victim, thrower]:
		_set_action(f, Action.RECOVER)
		f.stun = rules.grab_tech_stun
		f.grab_partner = -1
		f.grab_tech_left = 0
		f.vel = Vector3i.ZERO
		f.knock_ticks = KNOCK_TICKS
	victim.knock = Fx.dir(away, push)
	thrower.knock = Fx.dir(away + Fx.HALF_TURN, push)
	_emit(EventType.GRAB_TECH, victim.slot, thrower.slot, &"", victim.pos, 0)


## Lets go of whoever `f` holds or is held by.
func _release_grab(f: FighterState) -> void:
	if f.grab_partner < 0:
		return
	var other := state.fighters[f.grab_partner]
	f.grab_partner = -1
	if other.grab_partner == f.slot:
		other.grab_partner = -1
		if other.action == Action.GRABBED:
			_set_action(other, Action.IDLE)
	if f.action == Action.GRABBED:
		_set_action(f, Action.IDLE)


## Keeps thrown fighters in the thrower's hands and carried fighters in front of dashes.
func _update_holds() -> void:
	for f in state.fighters:
		if f.grab_partner >= 0 and f.action != Action.GRABBED:
			var victim := state.fighters[f.grab_partner]
			var move := current_move(f)
			if f.action == Action.ATTACK and move.kind == MoveData.Kind.THROW \
					and victim.action == Action.GRABBED and victim.grab_partner == f.slot:
				var held := f.pos + Fx.dir(f.facing, Fx.m(move.hold_distance))
				victim.pos = Vector3i(held.x, f.pos.y, held.z)
				victim.facing = Fx.wrap_angle(f.facing + Fx.HALF_TURN)
				victim.grounded = f.grounded
				victim.vel = Vector3i.ZERO
			else:
				if victim.grab_partner == f.slot:
					victim.grab_partner = -1
					if victim.action == Action.GRABBED:
						_set_action(victim, Action.IDLE)
						_emit(EventType.THROW_RELEASE, f.slot, victim.slot, &"", victim.pos, 0)
				f.grab_partner = -1
		if f.carried_ticks > 0:
			var carrier := state.fighters[f.carried_by]
			if carrier.action != Action.ATTACK or carrier.ko:
				f.carried_ticks = 0
				continue
			if f.hitstop > 0:
				continue
			f.carried_ticks -= 1
			var reach := _radius[carrier.slot] + _radius[f.slot] + Fx.m(0.1)
			var spot := carrier.pos + Fx.dir(carrier.facing, reach)
			f.pos = arena.push_circle(Vector3i(spot.x, f.pos.y, spot.z), _radius[f.slot])
			if arena.contact and arena.contact_splat and f.splat_armed:
				_wall_splat(f)


# --- Physics ----------------------------------------------------------------------------

func _gravity_of(f: FighterState) -> int:
	match f.action:
		Action.AIR_HITSTUN, Action.KO, Action.TECH, Action.BURST:
			return _juggle_gravity
		Action.WALL_SPLAT:
			return 0
		Action.AIR_DODGE:
			return _gravity[f.slot] / 2
		Action.ATTACK:
			return _gravity[f.slot] * current_move(f).gravity_percent / 100
	return _gravity[f.slot]


func _physics(f: FighterState) -> void:
	if f.action == Action.GRABBED or f.carried_ticks > 0:
		return
	var delta := Vector3i(f.vel.x, 0, f.vel.z)
	if not f.grounded:
		# Average of this tick's start and end velocity: exact parabolas (apex v²/2g).
		var g := _gravity_of(f)
		delta.y = f.vel.y - g / 2
		f.vel.y -= g
	var knocked := f.knock_ticks > 0
	if knocked:
		delta += f.knock
		f.knock_ticks -= 1
	f.pos += delta
	if not f.grounded and f.pos.y <= 0 and f.vel.y <= 0:
		f.pos.y = 0
		f.vel.y = 0
		f.grounded = true
		_on_land(f)
	elif f.grounded:
		f.pos.y = 0
	f.pos = arena.push_circle(f.pos, _radius[f.slot])
	if arena.contact and knocked and f.splat_armed and arena.contact_splat:
		_wall_splat(f)


func _on_land(f: FighterState) -> void:
	f.jumps_used = 0
	f.air_dodge_used = false
	match f.action:
		Action.AIR, Action.AIR_DODGE, Action.JUMP_SQUAT:
			_set_action(f, Action.LAND, rules.landing_frames)
			f.vel.x = 0
			f.vel.z = 0
			_emit(EventType.LAND, f.slot, -1, &"", f.pos, 0)
		Action.ATTACK:
			var move := current_move(f)
			if move.aerial:
				var lag := move.landing_recovery
				if lag <= 0:
					lag = rules.landing_frames if f.move_contact > 0 else rules.whiff_landing_frames
				_set_action(f, Action.LAND, lag)
				f.vel.x = 0
				f.vel.z = 0
				_emit(EventType.LAND, f.slot, -1, move.id, f.pos, lag)
		Action.AIR_HITSTUN:
			if f.bounce_pending > 0:
				var height := f.bounce_pending
				f.bounce_pending = 0
				_launch(f, height, maxi(f.stun, 20))
				_emit(EventType.LAUNCH, f.last_attacker, f.slot, &"ground_bounce", f.pos, height)
			elif f.dodge_age <= rules.tech_roll_window:
				_set_action(f, Action.TECH, rules.tech_roll_frames)
				f.action_variant = 1
				f.invuln = rules.tech_roll_frames - 4
				f.move_dir = _stick_angle(f) if _stick_active(f) else Fx.wrap_angle(f.facing + Fx.HALF_TURN)
				f.knock_ticks = 0
				_emit(EventType.TECH_ROLL, f.slot, -1, &"", f.pos, f.move_dir)
			else:
				_knockdown(f)
		Action.TECH:
			if f.action_variant == 3:
				f.invuln = 0
			_set_action(f, Action.LAND, rules.landing_frames)
			f.vel = Vector3i.ZERO
			_emit(EventType.LAND, f.slot, -1, &"", f.pos, 0)
		Action.KO:
			f.vel = Vector3i.ZERO


func _wall_splat(f: FighterState) -> void:
	f.splat_armed = false
	f.wall_splat_used = true
	f.carried_ticks = 0
	_set_action(f, Action.WALL_SPLAT)
	f.stun = rules.wall_splat_frames
	f.knock_ticks = 0
	f.vel = Vector3i.ZERO
	var bonus := f.splat_bonus
	f.splat_bonus = 0
	if bonus > 0:
		f.hp -= bonus
		f.combo_damage += bonus
	_emit(EventType.WALL_SPLAT, f.last_attacker, f.slot, &"", f.pos, bonus)
	if f.hp <= 0:
		_ko(f)


func _push_bodies() -> void:
	var fighters := state.fighters
	for i in fighters.size():
		var a := fighters[i]
		if a.ko or a.action == Action.GRABBED:
			continue
		for j in range(i + 1, fighters.size()):
			var b := fighters[j]
			if b.ko or b.action == Action.GRABBED:
				continue
			var ra := _radius[a.slot]
			var rb := _radius[b.slot]
			if absi(a.pos.y - b.pos.y) >= _height[a.slot]:
				continue
			var reach := ra + rb
			var d2 := Fx.dist2_xz(a.pos, b.pos)
			if d2 >= reach * reach:
				continue
			var d := Fx.isqrt(d2)
			var nx := Fx.TRIG_ONE
			var nz := 0
			if d > 0:
				nx = (b.pos.x - a.pos.x) * Fx.TRIG_ONE / d
				nz = (b.pos.z - a.pos.z) * Fx.TRIG_ONE / d
			var half := (reach - d) * rules.body_push_percent / 100
			var push := Vector3i(nx * half / Fx.TRIG_ONE, 0, nz * half / Fx.TRIG_ONE)
			a.pos -= push
			b.pos += push
			a.pos = arena.push_circle(a.pos, ra)
			b.pos = arena.push_circle(b.pos, rb)


# --- Effects and hazards ----------------------------------------------------------------

func _update_effects() -> void:
	for e in state.effects:
		e.age += 1
		var ed := effect_data(e)
		if ed.delay > 0 and e.age == ed.delay + 1:
			_emit(EventType.EFFECT_ACTIVE, e.owner, -1, ed.id, e.pos, e.id)
		if e.age <= ed.delay:
			continue
		e.pos += e.vel
		e.traveled += Fx.length_xz(e.vel)
		if ed.grow_speed != 0.0:
			e.radius = maxi(0, e.radius + Fx.mps(ed.grow_speed))
		if ed.blocked_by_walls and arena.blocks_projectile(e.pos, e.radius):
			_kill_effect(e, true)
		elif (ed.travel > 0.0 and e.traveled >= Fx.m(ed.travel)) or e.age > ed.delay + ed.lifetime:
			_kill_effect(e, false)
	_remove_dead_effects()


func _kill_effect(e: EffectState, destroyed: bool) -> void:
	if e.dead:
		return
	e.dead = true
	var ed := effect_data(e)
	_emit(EventType.EFFECT_DESTROYED if destroyed else EventType.EFFECT_END, e.owner, -1, ed.id, e.pos, e.id)


func _remove_dead_effects() -> void:
	var i := 0
	while i < state.effects.size():
		if state.effects[i].dead:
			state.effects.remove_at(i)
		else:
			i += 1


func _update_hazards() -> void:
	if state.phase != Phase.FIGHT:
		return
	for i in arena.hazards.size():
		var h := arena.hazards[i]
		var t := state.round_tick - h.offset
		if t < 0:
			continue
		var c := t % h.period
		if c == 0:
			state.hazard_hits[i] = 0
			_emit(EventType.HAZARD_WARN, -1, -1, h.id, arena.hazard_centers[i], i).cue = h.cue
		elif c == h.warn:
			_emit(EventType.HAZARD_ACTIVE, -1, -1, h.id, arena.hazard_centers[i], i).cue = h.cue


# --- Combat -----------------------------------------------------------------------------

## Ticks over which knockback distance is applied.
const KNOCK_TICKS := 10
const PULL_TICKS := 8
## Pop height for grounded knockdowns (units).
const KNOCKDOWN_POP := 3500
## Bounce height after a spike when the hit has no launch height (units).
const DEFAULT_BOUNCE := 10000
## Hurtbox height of a knocked-down fighter (units).
const DOWN_HEIGHT := 6000
## Stun value meaning "until landing".
const UNTIL_LANDING := 999


## One overlap found this tick, applied after all are collected so trades are symmetric.
class Contact:
	var attacker: FighterState
	var victim: FighterState
	## The attacker's move for hitboxes and throws; the spawning move for effects.
	var move: MoveData
	var hit: HitData
	var effect: EffectState
	var hazard: int = -1
	## A throw move hitting its held partner.
	var held: bool = false
	var counter: bool = false
	var point: Vector3i
	## Where the hit comes from (guard arc) and the knockback direction.
	var source: Vector3i
	var direction: int = 0
	var charge: int = 0
	## A ⚡Counter landing inside the victim's counter window.
	var counter_attack: bool = false


func _resolve_combat() -> void:
	var contacts: Array[Contact] = _mark_contacts
	_mark_contacts = []
	_collect_hitbox_contacts(contacts)
	_destroy_effects_by_hitboxes()
	_collect_effect_contacts(contacts)
	_collect_hazard_contacts(contacts)
	_collect_throw_contacts(contacts)
	for c in contacts:
		_apply_contact(c)
	_remove_dead_effects()


## Queues MoveData.mark_hit on every enemy carrying `f`'s mark and clears those marks.
func _detonate_marks(f: FighterState, move: MoveData) -> void:
	for v in enemies_of(f):
		if v.marks[f.slot] <= 0:
			continue
		v.marks[f.slot] = 0
		if is_invulnerable(v) or v.action == Action.GRABBED:
			continue
		var c := Contact.new()
		c.attacker = f
		c.victim = v
		c.move = move
		c.hit = move.mark_hit
		c.point = v.pos + Vector3i(0, _height[v.slot] / 2, 0)
		c.source = v.pos
		c.direction = _angle_to(f, v) if Fx.dist2_xz(f.pos, v.pos) > 0 else f.facing
		_mark_contacts.append(c)


func _collect_hitbox_contacts(contacts: Array[Contact]) -> void:
	for a in state.fighters:
		if a.action != Action.ATTACK or a.hitstop > 0 or a.ko:
			continue
		var move := current_move(a)
		if move.kind == MoveData.Kind.THROW:
			continue
		var group_counts := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
		for hb in move.hitboxes:
			if hb.hit == null or not hitbox_active(move, hb, a.move_frame):
				continue
			var group := clampi(hb.group, 0, 7)
			for v in state.fighters:
				if v.team == a.team or v.ko or v.action == Action.GRABBED:
					continue
				if a.move_hit_masks[group] & (1 << v.slot):
					continue
				if move.max_targets > 0 and group_counts[group] >= move.max_targets:
					break
				if not _hitbox_overlaps(a, hb, v):
					continue
				if not _can_be_hit(v, hb.hit, false, a.slot):
					continue
				a.move_hit_masks[group] |= 1 << v.slot
				group_counts[group] += 1
				var c := Contact.new()
				c.attacker = a
				c.victim = v
				c.move = move
				c.hit = hb.hit
				c.counter = _is_counter(v)
				c.point = a.pos + Fx.rotate(Fx.v3(hb.offset), a.facing)
				c.source = a.pos
				c.direction = _angle_to(a, v) if Fx.dist2_xz(a.pos, v.pos) > 0 else a.facing
				c.charge = a.charge
				contacts.append(c)


static func hitbox_active(move: MoveData, hb: HitboxData, frame: int) -> bool:
	var first := hb.start_frame if hb.start_frame >= 0 else move.startup
	var last := hb.end_frame if hb.end_frame >= 0 else move.last_active_frame()
	return frame >= first and frame <= last


func _hitbox_overlaps(a: FighterState, hb: HitboxData, v: FighterState) -> bool:
	var r := Fx.m(hb.radius)
	var p1 := a.pos + Fx.rotate(Fx.v3(hb.offset), a.facing)
	if not hb.capsule:
		return _sphere_hits_body(p1, r, v)
	var p2 := a.pos + Fx.rotate(Fx.v3(hb.offset_end), a.facing)
	var d := p2 - p1
	var length := Fx.isqrt(d.x * d.x + d.y * d.y + d.z * d.z)
	var steps := maxi(1, length / maxi(1, r))
	for i in steps + 1:
		var p := Vector3i(p1.x + d.x * i / steps, p1.y + d.y * i / steps, p1.z + d.z * i / steps)
		if _sphere_hits_body(p, r, v):
			return true
	return false


func _sphere_hits_body(c: Vector3i, r: int, v: FighterState) -> bool:
	var rv := _radius[v.slot]
	var height := DOWN_HEIGHT if v.action == Action.KNOCKDOWN else _height[v.slot]
	var y0 := v.pos.y + rv
	var y1 := v.pos.y + maxi(height - rv, rv)
	var cy := clampi(c.y, y0, y1)
	var dx := c.x - v.pos.x
	var dy := c.y - cy
	var dz := c.z - v.pos.z
	var reach := r + rv
	return dx * dx + dy * dy + dz * dz <= reach * reach


## Vertical capsule (base at `pos`) against a fighter body.
func _cylinder_hits_body(pos: Vector3i, r: int, h: int, v: FighterState) -> bool:
	var rv := _radius[v.slot]
	var height := DOWN_HEIGHT if v.action == Action.KNOCKDOWN else _height[v.slot]
	if pos.y - r > v.pos.y + height or pos.y + h + r < v.pos.y:
		return false
	var reach := r + rv
	return Fx.dist2_xz(pos, v.pos) <= reach * reach


## Whether `v` can take `hit` right now; also grants perfect-dodge Soul on dodged hits.
func _can_be_hit(v: FighterState, hit: HitData, projectile: bool, attacker: int) -> bool:
	if is_invulnerable(v):
		_check_perfect_dodge(v, attacker)
		return false
	if projectile and v.action == Action.ATTACK:
		var move := current_move(v)
		if move.projectile_invuln_end > 0 and v.move_frame >= move.projectile_invuln_start \
				and v.move_frame <= move.projectile_invuln_end:
			return false
	if v.action == Action.KNOCKDOWN and not hit.otg:
		return false
	if hit.throw:
		if not v.grounded or v.action == Action.KNOCKDOWN or v.action == Action.GRABBED:
			return false
		if not hit.throw_beats_attacks and v.action == Action.ATTACK \
				and v.move_frame <= current_move(v).last_active_frame():
			return false
	return true


func _check_perfect_dodge(v: FighterState, attacker: int) -> void:
	if v.perfect_dodge_used or v.ko:
		return
	var data := fighter_data[v.slot]
	var first := 0
	var window := rules.perfect_dodge_frames
	if v.action == Action.DODGE:
		first = data.dodge_invuln_start
	elif v.action == Action.AIR_DODGE:
		first = data.air_dodge_invuln_start
	elif v.action == Action.DASH:
		first = data.dash.invuln_start
		window = data.dash.perfect_frames
	else:
		return
	if v.action_tick < first or v.action_tick >= first + window:
		return
	v.perfect_dodge_used = true
	_gain_soul(v, rules.perfect_dodge_soul * 100)
	_emit(EventType.PERFECT_DODGE, attacker, v.slot, &"", v.pos, rules.perfect_dodge_soul)


## Counter hit: the victim is in an attack's startup, or was guard broken.
func _is_counter(v: FighterState) -> bool:
	if v.guard_broken:
		return true
	return v.action == Action.ATTACK and v.move_frame < current_move(v).startup


func _destroy_effects_by_hitboxes() -> void:
	if state.effects.is_empty():
		return
	for a in state.fighters:
		if a.action != Action.ATTACK or a.ko:
			continue
		var move := current_move(a)
		for hb in move.hitboxes:
			if not hb.destroys_projectiles or not hitbox_active(move, hb, a.move_frame):
				continue
			var p := a.pos + Fx.rotate(Fx.v3(hb.offset), a.facing)
			var r := Fx.m(hb.radius)
			for e in state.effects:
				if e.dead or e.team == a.team:
					continue
				var ed := effect_data(e)
				if not ed.destroyable or e.age <= ed.delay:
					continue
				var reach := r + e.radius
				if Fx.dist2_xz(p, e.pos) <= reach * reach and absi(p.y - e.pos.y) <= reach + Fx.m(ed.height):
					_kill_effect(e, true)


func _collect_effect_contacts(contacts: Array[Contact]) -> void:
	for e in state.effects:
		if e.dead:
			continue
		var ed := effect_data(e)
		if ed.hit == null or e.age <= ed.delay:
			continue
		var owner := state.fighters[e.owner]
		var height := Fx.m(ed.height)
		for v in state.fighters:
			if v.team == e.team or v.ko or v.action == Action.GRABBED:
				continue
			if e.hit_counts[v.slot] >= ed.hits_per_target:
				continue
			if e.hit_counts[v.slot] > 0 and state.tick - e.last_hit_tick[v.slot] < ed.hit_interval:
				continue
			if not _cylinder_hits_body(e.pos, e.radius, height, v):
				continue
			if not _can_be_hit(v, ed.hit, ed.projectile, e.owner):
				continue
			e.hit_counts[v.slot] += 1
			e.last_hit_tick[v.slot] = state.tick
			var c := Contact.new()
			c.attacker = owner
			c.victim = v
			c.move = fighter_data[e.owner].moves[e.move_index]
			c.hit = ed.hit
			c.effect = e
			c.counter = _is_counter(v)
			c.point = e.pos
			c.source = e.pos
			c.direction = Fx.angle_of(e.vel.x, e.vel.z) if (e.vel.x != 0 or e.vel.z != 0) \
					else Fx.angle_of(v.pos.x - e.pos.x, v.pos.z - e.pos.z)
			contacts.append(c)
			if ed.destroy_on_contact:
				break


func _collect_hazard_contacts(contacts: Array[Contact]) -> void:
	for i in arena.hazards.size():
		var h := arena.hazards[i]
		if h.hit == null or hazard_phase(i) != 2:
			continue
		var center := arena.hazard_centers[i]
		for v in state.fighters:
			if v.ko or state.hazard_hits[i] & (1 << v.slot):
				continue
			if not _cylinder_hits_body(center, Fx.m(h.radius), Fx.m(h.height), v):
				continue
			if not _can_be_hit(v, h.hit, false, -1):
				continue
			state.hazard_hits[i] |= 1 << v.slot
			var c := Contact.new()
			c.victim = v
			c.hit = h.hit
			c.hazard = i
			c.point = Vector3i(v.pos.x, v.pos.y, v.pos.z)
			c.source = center
			c.direction = Fx.angle_of(v.pos.x - center.x, v.pos.z - center.z)
			contacts.append(c)


func _collect_throw_contacts(contacts: Array[Contact]) -> void:
	for a in state.fighters:
		if a.action != Action.ATTACK or a.grab_partner < 0 or a.hitstop > 0:
			continue
		var move := current_move(a)
		if move.kind != MoveData.Kind.THROW:
			continue
		var v := state.fighters[a.grab_partner]
		if v.action != Action.GRABBED or v.grab_partner != a.slot or v.grab_tech_left > 0:
			continue
		for hb in move.hitboxes:
			var group := clampi(hb.group, 0, 7)
			if hb.hit == null or not hitbox_active(move, hb, a.move_frame) or a.move_hit_masks[group] & (1 << v.slot):
				continue
			a.move_hit_masks[group] |= 1 << v.slot
			var c := Contact.new()
			c.attacker = a
			c.victim = v
			c.move = move
			c.hit = hb.hit
			c.held = true
			c.point = v.pos + Vector3i(0, _height[v.slot] / 2, 0)
			c.source = a.pos
			c.direction = a.facing
			contacts.append(c)


func _apply_contact(c: Contact) -> void:
	var v := c.victim
	if v.ko or (c.effect != null and c.effect.dead and effect_data(c.effect).destroy_on_contact):
		return
	if not c.held and is_invulnerable(v):
		return
	if not c.held and _try_stance(c):
		_after_contact(c)
		return
	if c.hit.throw:
		_connect_grab(c)
		return
	if not c.held:
		if _try_parry(c) or _try_block(c):
			_after_contact(c)
			return
		c.counter_attack = c.hit.counter and c.attacker != null and in_counter_window(v)
		if not c.counter_attack and (_try_super_armor(c) or _try_armor(c)):
			_after_contact(c)
			return
	_land_hit(c)
	_after_contact(c)


func _after_contact(c: Contact) -> void:
	if c.effect != null and effect_data(c.effect).destroy_on_contact:
		_kill_effect(c.effect, false)


func _kind_of(c: Contact) -> MoveData.Kind:
	return c.move.kind if c.move != null else MoveData.Kind.ABILITY


func _hitstop_of(c: Contact) -> int:
	return _scaled_hitstop(_base_hitstop(c))


## Applies SimConfig.hitstop_percent (a non-zero hitstop stays at least 1 frame).
func _scaled_hitstop(frames: int) -> int:
	if frames <= 0 or config.hitstop_percent == 100:
		return frames
	return maxi(1, frames * config.hitstop_percent / 100)


## Whether a contact comes from a move whose charge was released perfectly.
func _perfect_of(c: Contact) -> bool:
	var a := c.attacker
	if a == null or c.move == null or c.move.perfect_end <= 0:
		return false
	return a.charge_perfect and a.move_index >= 0 and current_move(a) == c.move


## Damage percent from charge levels for a levelled charge move's contact.
func _charge_percent(c: Contact) -> int:
	if _perfect_of(c):
		return c.move.perfect_damage_percent
	var a := c.attacker
	if a == null or current_move(a) != c.move or a.charge_level <= 0:
		return 100
	var percents := c.move.charge_level_damage_percent
	return percents[a.charge_level - 1] if a.charge_level - 1 < percents.size() else 100


## HitData.Weight of a contact, with AUTO resolved: BASIC for basic moves, LIGHT otherwise.
func _weight_of(c: Contact) -> int:
	if c.move != null and c.move.perfect_weight != HitData.Weight.AUTO and _perfect_of(c):
		return c.move.perfect_weight
	if c.hit.weight != HitData.Weight.AUTO:
		return c.hit.weight
	return HitData.Weight.BASIC if c.move != null and c.move.is_basic() else HitData.Weight.LIGHT


func _stagger_of(c: Contact) -> int:
	if c.move != null and c.move.perfect_stagger >= 0 and _perfect_of(c):
		return c.move.perfect_stagger
	if c.hit.stagger >= 0:
		return c.hit.stagger
	var index := _weight_of(c) - 1
	return rules.weight_stagger[index] if index < rules.weight_stagger.size() else 0


func _base_hitstop(c: Contact) -> int:
	if c.hit.hitstop >= 0:
		return c.hit.hitstop
	var weight := c.hit.weight
	if c.move != null and c.move.perfect_weight != HitData.Weight.AUTO and _perfect_of(c):
		weight = c.move.perfect_weight
	if weight == HitData.Weight.MASSIVE and _kind_of(c) == MoveData.Kind.SUPER:
		return rules.hitstop_super_final
	if weight != HitData.Weight.AUTO and weight - 1 < rules.weight_hitstop.size():
		return rules.weight_hitstop[weight - 1]
	match _kind_of(c):
		MoveData.Kind.LIGHT, MoveData.Kind.AIR_LIGHT, MoveData.Kind.GETUP_ATTACK:
			return rules.hitstop_light
		MoveData.Kind.HEAVY, MoveData.Kind.AIR_HEAVY, MoveData.Kind.GRAB, MoveData.Kind.THROW:
			return rules.hitstop_heavy
		MoveData.Kind.SUPER:
			return rules.hitstop_super
		MoveData.Kind.BURST:
			return 0
	return rules.hitstop_ability


func _guard_damage_of(c: Contact) -> int:
	if c.hit.guard_damage >= 0:
		return c.hit.guard_damage
	match _kind_of(c):
		MoveData.Kind.LIGHT, MoveData.Kind.AIR_LIGHT, MoveData.Kind.GETUP_ATTACK:
			return rules.guard_damage_light
		MoveData.Kind.HEAVY, MoveData.Kind.AIR_HEAVY:
			return rules.guard_damage_heavy
		MoveData.Kind.SUPER:
			return rules.guard_damage_super
	return rules.guard_damage_ability


func _chip_percent_of(c: Contact) -> int:
	if c.hit.chip_percent >= 0:
		return c.hit.chip_percent
	match _kind_of(c):
		MoveData.Kind.ABILITY:
			return rules.chip_ability_percent
		MoveData.Kind.SUPER:
			return rules.chip_super_percent
	return 0


## Whether `v` faces `source` within the guard arc.
func _facing_source(v: FighterState, source: Vector3i) -> bool:
	if Fx.dist2_xz(v.pos, source) == 0:
		return true
	var to := Fx.angle_of(source.x - v.pos.x, source.z - v.pos.z)
	return absi(Fx.angle_diff(v.facing, to)) * 2 <= Fx.deg(rules.guard_arc)


## Freezes both fighters (melee) or just the victim (effects, hazards).
func _apply_hitstop(c: Contact, frames: int) -> void:
	c.victim.hitstop = frames
	if c.attacker != null and c.effect == null:
		c.attacker.hitstop = frames


func _try_parry(c: Contact) -> bool:
	var v := c.victim
	if v.parry_timer <= 0 or not c.hit.parryable:
		return false
	if v.action != Action.GUARD and v.action != Action.BLOCKSTUN:
		return false
	if not _facing_source(v, c.source):
		return false
	v.parry_timer = 0
	var hitstop := _scaled_hitstop(rules.hitstop_heavy)
	v.hitstop = hitstop
	var guard_max := rules.guard_gauge * 100
	v.guard = mini(guard_max, v.guard + rules.parry_guard_refill * 100)
	_gain_soul(v, rules.parry_soul * 100)
	var a := c.attacker
	if a != null and c.effect == null:
		a.move_contact = maxi(a.move_contact, 1)
		if a.grab_partner >= 0:
			_release_grab(a)
		_set_action(a, Action.HITSTUN)
		a.stun = rules.parry_stagger
		a.hitstop = hitstop
		a.vel = Vector3i(0, a.vel.y, 0)
	var data := fighter_data[v.slot]
	if data.parry_buff != null:
		apply_buff(v, data.parry_buff, -1)
	var e := _emit(EventType.PARRY, v.slot, a.slot if a != null else -1, c.move.id if c.move != null else &"",
			c.point, rules.parry_soul)
	e.hitstop = hitstop
	if c.effect != null:
		e.flags |= SimEvent.FLAG_PROJECTILE
		_kill_effect(c.effect, true)
	var hook := traits[v.slot]
	if hook != null:
		hook.on_parry(self, v, a.slot if a != null else -1)
	return true


func _try_block(c: Contact) -> bool:
	var v := c.victim
	if c.hit.unblockable or not guard_up(v) or not _facing_source(v, c.source):
		return false
	var a := c.attacker
	var hitstop := _hitstop_of(c)
	var chip := c.hit.damage * _chip_percent_of(c) / 100
	if chip > 0 and _kind_of(c) != MoveData.Kind.SUPER:
		chip = mini(chip, v.hp - 1)
	chip = maxi(chip, 0)
	v.hp -= chip
	v.guard -= _guard_damage_of(c) * 100
	v.guard_idle = 0
	if a != null:
		_gain_soul(a, chip * rules.soul_per_100_dealt)
		if c.effect == null:
			a.move_contact = maxi(a.move_contact, 1)
	var full_charge := c.move != null and c.move.chargeable and c.move.full_charge_guard_break \
			and c.effect == null and c.charge >= c.move.charge_max
	var flags := SimEvent.FLAG_CHIP if chip > 0 else 0
	if c.effect != null:
		flags |= SimEvent.FLAG_PROJECTILE
	if c.hit.guard_break or full_charge or v.guard <= 0:
		_set_action(v, Action.GUARD_BREAK)
		v.stun = rules.guard_break_frames
		v.guard = rules.guard_gauge * 100
		v.guard_broken = true
		v.parry_timer = 0
		v.vel = Vector3i.ZERO
		_apply_hitstop(c, hitstop)
		var e := _emit(EventType.GUARD_BREAK, a.slot if a != null else -1, v.slot,
				c.move.id if c.move != null else &"", c.point, chip)
		e.hitstop = hitstop
		e.flags = flags | (SimEvent.FLAG_FULL_CHARGE if full_charge else 0)
		e.cue = c.hit.cue
	else:
		_set_action(v, Action.BLOCKSTUN)
		v.stun = c.hit.blockstun
		v.vel = Vector3i.ZERO
		var push := Fx.m(c.hit.block_pushback)
		if push > 0:
			v.knock = Fx.dir(c.direction, push / KNOCK_TICKS)
			v.knock_ticks = KNOCK_TICKS
		_apply_hitstop(c, hitstop)
		var e := _emit(EventType.BLOCK, a.slot if a != null else -1, v.slot,
				c.move.id if c.move != null else &"", c.point, chip)
		e.hitstop = hitstop
		e.flags = flags
		e.cue = c.hit.cue
	if a != null:
		var hook := traits[a.slot]
		if hook != null:
			hook.on_hit_dealt(self, a, v, c.move, c.hit, true)
	if v.hp <= 0:
		_ko(v)
	return true


## A stance window absorbs the first hit from inside its arc and starts the counter move.
func _try_stance(c: Contact) -> bool:
	var v := c.victim
	if v.action != Action.ATTACK:
		return false
	var move := current_move(v)
	if not move.in_window(v.move_frame, move.stance_start, move.stance_end):
		return false
	if Fx.dist2_xz(v.pos, c.source) > 0:
		var to := Fx.angle_of(c.source.x - v.pos.x, c.source.z - v.pos.z)
		if absi(Fx.angle_diff(v.facing, to)) * 2 > Fx.deg(move.stance_arc):
			return false
	var a := c.attacker
	var hitstop := _scaled_hitstop(move.stance_hitstop if move.stance_hitstop >= 0 else rules.stance_hitstop)
	var e := _emit(EventType.STANCE_TRIGGER, v.slot, a.slot if a != null else -1, move.id, c.point, 0)
	e.hitstop = hitstop
	if c.effect != null:
		e.flags |= SimEvent.FLAG_PROJECTILE
		_kill_effect(c.effect, true)
	elif a != null:
		a.hitstop = hitstop
		a.move_contact = maxi(a.move_contact, 1)
	_gain_soul(v, rules.counter_soul * 100)
	var data := fighter_data[v.slot]
	var counter := data.find_move(move.counter_move)
	if counter >= 0:
		var slot := v.move_slot
		start_move(v, counter, v.move_button)
		v.move_slot = slot
	if data.parry_buff != null:
		apply_buff(v, data.parry_buff, -1)
	v.hitstop = hitstop
	return true


## Flinch-immune and push-immune windows: no hit cap, full damage, half hitstop, no reaction.
func _try_super_armor(c: Contact) -> bool:
	var v := c.victim
	if v.action != Action.ATTACK:
		return false
	var move := current_move(v)
	var push := move.in_window(v.move_frame, move.push_immune_start, move.push_immune_end)
	var flinch := move.in_window(v.move_frame, move.flinch_immune_start, move.flinch_immune_end) \
			and c.hit.reaction == HitData.Reaction.STAGGER and v.grounded
	if not push and not flinch:
		return false
	var damage := _hit_damage(c)
	v.hp -= damage
	_deal_soul(c, damage)
	_gain_soul(v, damage * rules.soul_per_100_taken)
	if c.attacker != null and c.effect == null:
		c.attacker.move_contact = maxi(c.attacker.move_contact, 1)
	var hitstop := _hitstop_of(c)
	if hitstop > 0:
		hitstop = maxi(1, hitstop / 2)
	_apply_hitstop(c, hitstop)
	var e := _emit(EventType.ARMOR, c.attacker.slot if c.attacker != null else -1, v.slot,
			c.move.id if c.move != null else &"", c.point, damage)
	e.hitstop = hitstop
	e.cue = c.hit.cue
	e.weight = _weight_of(c)
	if c.effect != null:
		e.flags |= SimEvent.FLAG_PROJECTILE
	_drain_stagger(v, c.attacker, _stagger_of(c))
	_on_connect(c)
	if v.hp <= 0:
		_ko(v)
	return true


## A hit or armored hit landed: brand the victim and arm the attacker's combo/chain.
func _on_connect(c: Contact) -> void:
	var a := c.attacker
	if a == null or c.move == null:
		return
	if c.hit.mark:
		c.victim.marks[a.slot] = c.hit.mark_frames
	if c.effect != null:
		_arm_follow_up(a, c.effect.skill_slot, c.move)
	elif current_move(a) == c.move:
		_arm_follow_up(a, a.move_slot, c.move)


## Outgoing damage of a contact before per-victim combo scaling: base, charge, counter hit,
## buffs, trait, and the staggered bonus.
func _hit_damage(c: Contact) -> int:
	var v := c.victim
	var a := c.attacker
	var damage := c.hit.damage
	if c.move != null and c.move.chargeable and not c.move.charge_levels.is_empty():
		damage = damage * _charge_percent(c) / 100
	elif c.move != null and c.move.chargeable and c.effect == null and c.move.charge_max > 0:
		damage += damage * c.move.charge_damage_percent * c.charge / (100 * c.move.charge_max)
	if c.counter:
		damage = damage * rules.counter_damage_percent / 100
	if a != null:
		damage = damage * (100 + _use_damage_buffs(a, c.effect.cast if c.effect != null else a.move_cast)) / 100
		var hook := traits[a.slot]
		if hook != null:
			damage = damage * hook.damage_percent(self, a, v, c.move, c.hit) / 100
	if v.action == Action.STAGGERED:
		damage = damage * rules.stagger_damage_percent / 100
	return damage


## Soul for the attacker of a contact (basics earn basic_soul_percent).
func _deal_soul(c: Contact, damage: int) -> void:
	if c.attacker == null:
		return
	var rate := rules.soul_per_100_dealt
	if c.move != null and c.move.is_basic():
		rate = rate * rules.basic_soul_percent / 100
	_gain_soul(c.attacker, damage * rate)


## Drains a boss stagger bar; at 0 the fighter is STAGGERED and the bar refills, bigger.
func _drain_stagger(v: FighterState, attacker: FighterState, amount: int) -> void:
	if v.stagger_max <= 0 or v.ko or v.action == Action.STAGGERED or amount <= 0:
		return
	v.stagger -= amount
	if v.stagger > 0:
		return
	v.stagger_max = v.stagger_max * rules.stagger_growth_percent / 100
	v.stagger = v.stagger_max
	_release_grab(v)
	_set_action(v, Action.STAGGERED)
	v.stun = rules.stagger_frames
	v.vel = Vector3i(0, v.vel.y, 0)
	v.knock_ticks = 0
	v.carried_ticks = 0
	v.bounce_pending = 0
	v.splat_armed = false
	if attacker != null:
		_gain_soul(attacker, rules.stagger_soul * 100)
	_emit(EventType.STAGGER_BREAK, attacker.slot if attacker != null else -1, v.slot, &"", v.pos, v.stagger_max)


func _try_armor(c: Contact) -> bool:
	var v := c.victim
	if v.action != Action.ATTACK or v.armor_left <= 0:
		return false
	var move := current_move(v)
	if v.move_frame < move.armor_start or v.move_frame > move.armor_end:
		return false
	v.armor_left -= 1
	var damage := c.hit.damage * move.armor_damage_percent / 100
	v.hp -= damage
	if c.attacker != null:
		_gain_soul(c.attacker, damage * rules.soul_per_100_dealt)
		if c.effect == null:
			c.attacker.move_contact = maxi(c.attacker.move_contact, 1)
	_gain_soul(v, damage * rules.soul_per_100_taken)
	var hitstop := _hitstop_of(c)
	_apply_hitstop(c, hitstop)
	var e := _emit(EventType.ARMOR, c.attacker.slot if c.attacker != null else -1, v.slot,
			c.move.id if c.move != null else &"", c.point, damage)
	e.hitstop = hitstop
	e.cue = c.hit.cue
	if v.hp <= 0:
		_ko(v)
	return true


func _land_hit(c: Contact) -> void:
	var v := c.victim
	var a := c.attacker
	var hit := c.hit
	var kind := _kind_of(c)
	var was_airborne := not v.grounded
	var staggered := v.action == Action.STAGGERED
	var damage := _hit_damage(c)
	var scale := 100
	if v.combo_hits >= rules.scaling_free_hits:
		var floor_percent := rules.super_scaling_floor_percent if kind == MoveData.Kind.SUPER \
				else rules.scaling_floor_percent
		scale = maxi(floor_percent, 100 - rules.scaling_step_percent * (v.combo_hits - rules.scaling_free_hits + 1))
	if damage > 0:
		damage = maxi(1, damage * scale / 100)
	v.hp -= damage
	v.combo_hits += 1
	v.combo_damage += damage
	v.last_attacker = a.slot if a != null else -1
	v.guard_broken = false
	v.parry_timer = 0
	_deal_soul(c, damage)
	if a != null and c.effect == null:
		a.move_contact = 2
	_gain_soul(v, damage * rules.soul_per_100_taken)
	if v.grab_partner >= 0 and not c.held:
		_release_grab(v)
	var hitstun := hit.hitstun
	if c.counter:
		hitstun = hitstun * rules.counter_hitstun_percent / 100
	if v.combo_ticks >= rules.combo_decay_frames:
		hitstun = hitstun * rules.combo_decay_hitstun_percent / 100
	var hitstop := _hitstop_of(c)
	_apply_hitstop(c, hitstop)
	var flags := 0
	if c.counter:
		flags |= SimEvent.FLAG_COUNTER
	if c.effect != null:
		flags |= SimEvent.FLAG_PROJECTILE
	if kind == MoveData.Kind.SUPER:
		flags |= SimEvent.FLAG_SUPER
	if c.hazard >= 0:
		flags |= SimEvent.FLAG_HAZARD
	if c.held:
		flags |= SimEvent.FLAG_THROW
	if c.move != null and c.move.chargeable and c.effect == null and c.charge >= c.move.charge_max:
		flags |= SimEvent.FLAG_FULL_CHARGE
	if _perfect_of(c):
		flags |= SimEvent.FLAG_PERFECT
	var launched := false
	if c.counter_attack:
		flags |= SimEvent.FLAG_COUNTER_ATTACK
		_counter_stun(c)
	elif staggered:
		flags |= SimEvent.FLAG_STAGGERED
	else:
		launched = _react(c, hitstun, was_airborne)
	if launched:
		flags |= SimEvent.FLAG_LAUNCH
	var id := c.move.id if c.move != null else (arena.hazards[c.hazard].id if c.hazard >= 0 else &"")
	var e := _emit(EventType.HIT, a.slot if a != null else -1, v.slot, id, c.point, damage)
	e.flags = flags
	e.hitstop = hitstop
	e.cue = hit.cue
	e.weight = _weight_of(c)
	if launched:
		_emit(EventType.LAUNCH, a.slot if a != null else -1, v.slot, id, v.pos, v.vel.y)
	if c.counter_attack:
		_emit(EventType.COUNTER_STUN, a.slot, v.slot, id, v.pos, v.stun)
	_drain_stagger(v, a, _stagger_of(c) + (rules.counter_stagger if c.counter_attack else 0))
	_on_connect(c)
	if a != null:
		var hook := traits[a.slot]
		if hook != null:
			hook.on_hit_dealt(self, a, v, c.move, hit, false)
	if v.hp <= 0:
		_ko(v)


## A ⚡Counter: the victim's move is interrupted into COUNTER_STUN; the attacker gains Soul
## and its parry buff (Aldric's Oathkeeper).
func _counter_stun(c: Contact) -> void:
	var v := c.victim
	var a := c.attacker
	_set_action(v, Action.COUNTER_STUN)
	v.stun = rules.counter_stun_boss_frames if v.stagger_max > 0 else rules.counter_stun_frames
	v.vel = Vector3i(0, v.vel.y, 0)
	v.bounce_pending = 0
	var knock := Fx.m(c.hit.knockback)
	v.knock = Fx.dir(c.direction, knock / KNOCK_TICKS)
	v.knock_ticks = KNOCK_TICKS if knock > 0 else 0
	_gain_soul(a, rules.counter_soul * 100)
	var buff := fighter_data[a.slot].parry_buff
	if buff != null:
		apply_buff(a, buff, -1)


## Applies the hit reaction. Returns true if the victim was launched.
func _react(c: Contact, hitstun: int, was_airborne: bool) -> bool:
	var v := c.victim
	var a := c.attacker
	var hit := c.hit
	var reaction := hit.reaction
	if v.action == Action.KNOCKDOWN and (reaction == HitData.Reaction.STAGGER or reaction == HitData.Reaction.PULL):
		reaction = HitData.Reaction.KNOCKDOWN
	v.vel = Vector3i(0, v.vel.y, 0)
	v.bounce_pending = 0
	var knock := Fx.m(hit.knockback)
	v.knock = Fx.dir(c.direction, knock / KNOCK_TICKS)
	v.knock_ticks = KNOCK_TICKS if knock > 0 else 0
	v.splat_armed = hit.wall_splat and not v.wall_splat_used \
			and knock * Fx.TICKS_PER_SECOND / KNOCK_TICKS >= Fx.m(rules.wall_splat_min_speed)
	v.splat_bonus = hit.wall_splat_bonus if v.splat_armed else 0
	if hit.carry_frames > 0 and a != null and c.effect == null:
		v.carried_by = a.slot
		v.carried_ticks = hit.carry_frames
		v.knock_ticks = 0
		v.splat_armed = hit.wall_splat and not v.wall_splat_used
		v.splat_bonus = hit.wall_splat_bonus if v.splat_armed else 0
	if reaction == HitData.Reaction.PULL and a != null:
		var spot := a.pos + Fx.dir(a.facing, Fx.m(hit.pull_distance))
		var delta := Vector3i(spot.x - v.pos.x, 0, spot.z - v.pos.z)
		v.knock = Vector3i(delta.x / PULL_TICKS, 0, delta.z / PULL_TICKS)
		v.knock_ticks = PULL_TICKS
		v.splat_armed = false
	if c.held and reaction == HitData.Reaction.STAGGER:
		v.knock_ticks = 0
		return false
	if c.held:
		v.grab_partner = -1
		if a != null:
			a.grab_partner = -1
	var height := roundi(Fx.m(hit.launch_height) * fighter_data[v.slot].weight)
	if was_airborne:
		v.juggle_used += hit.juggle_cost
		if reaction == HitData.Reaction.GROUND_BOUNCE:
			_set_action(v, Action.AIR_HITSTUN)
			v.stun = maxi(hitstun, 1)
			v.vel.y = -_jump_speed[v.slot] * 2
			v.bounce_pending = height if height > 0 else DEFAULT_BOUNCE
		else:
			var pop := maxi(height, roundi(Fx.m(rules.juggle_pop) * fighter_data[v.slot].weight))
			var stun := UNTIL_LANDING if reaction == HitData.Reaction.KNOCKDOWN else hitstun
			_launch(v, pop, stun)
		if v.juggle_used >= rules.juggle_points:
			_set_action(v, Action.TECH)
			v.action_variant = 3
			v.invuln = UNTIL_LANDING
			v.knock_ticks = 0
			v.bounce_pending = 0
			_emit(EventType.JUGGLE_LIMIT, a.slot if a != null else -1, v.slot, &"", v.pos, v.juggle_used)
			return false
		return height > 0 and reaction == HitData.Reaction.LAUNCH
	match reaction:
		HitData.Reaction.LAUNCH:
			_launch(v, maxi(height, KNOCKDOWN_POP), hitstun)
			return true
		HitData.Reaction.GROUND_BOUNCE:
			if height > 0:
				_launch(v, height, hitstun)
				return true
			_launch(v, KNOCKDOWN_POP, UNTIL_LANDING)
		HitData.Reaction.KNOCKDOWN:
			_launch(v, KNOCKDOWN_POP, UNTIL_LANDING)
		_:
			_set_action(v, Action.HITSTUN)
			v.stun = hitstun
	return false


## Sends `f` up so its apex is `height` units above the current position.
func _launch(f: FighterState, height: int, stun: int) -> void:
	_set_action(f, Action.AIR_HITSTUN)
	f.stun = stun
	f.grounded = false
	f.vel.y = Fx.isqrt(2 * _juggle_gravity * maxi(height, 0))


func _connect_grab(c: Contact) -> void:
	var a := c.attacker
	var v := c.victim
	if a.action != Action.ATTACK or current_move(a) != c.move or a.hitstop > 0:
		return
	if v.in_hitstun() or not v.grounded or v.action == Action.GRABBED:
		return
	if v.action == Action.ATTACK:
		var guarded := current_move(v)
		if guarded.in_window(v.move_frame, guarded.push_immune_start, guarded.push_immune_end):
			return
	var data := fighter_data[a.slot]
	var throw_index := data.find_move(c.move.throw_move)
	a.move_contact = 2
	if throw_index < 0:
		return
	var techable := c.move.techable
	start_move(a, throw_index, a.move_button)
	a.facing = _angle_to(a, v)
	a.grab_partner = v.slot
	if v.grab_partner >= 0:
		_release_grab(v)
	_set_action(v, Action.GRABBED)
	v.grab_partner = a.slot
	v.grab_tech_left = rules.grab_tech_window if techable else 0
	v.stun = 0
	v.knock_ticks = 0
	v.carried_ticks = 0
	v.vel = Vector3i.ZERO
	v.parry_timer = 0
	_emit(EventType.GRAB, a.slot, v.slot, c.move.id, v.pos, 0).cue = c.hit.cue
	_update_holds()


func _ko(f: FighterState) -> void:
	if f.ko:
		return
	f.hp = 0
	f.ko = true
	_release_grab(f)
	_set_action(f, Action.KO)
	f.stun = 0
	f.carried_ticks = 0
	f.splat_armed = false
	if f.grounded:
		f.grounded = false
		f.vel.y = Fx.isqrt(2 * _juggle_gravity * KNOCKDOWN_POP)
	_emit(EventType.KO, f.last_attacker, f.slot, &"", f.pos, 0)


## Sums the damage buffs that apply to a hit of `cast`; the first hit of each cast spends a use.
func _use_damage_buffs(f: FighterState, cast: int) -> int:
	var total := 0
	for buff in f.buffs:
		if buff.damage_bonus_percent == 0:
			continue
		var limited := buff.uses_left > 0 or buff.spent
		if limited and cast <= buff.after_cast:
			continue
		if limited and cast != buff.last_cast:
			if buff.spent:
				continue
			buff.last_cast = cast
			buff.uses_left -= 1
			buff.spent = buff.uses_left == 0
		total += buff.damage_bonus_percent
	return total


## Whether `f`'s move `cast` is still running or has live effects.
func _cast_live(f: FighterState, cast: int) -> bool:
	if f.action == Action.ATTACK and f.move_cast == cast:
		return true
	for e in state.effects:
		if e.owner == f.slot and e.cast == cast and not e.dead:
			return true
	return false


## Adds Soul in hundredths, capped, with a SOUL_FULL event when it fills.
func _gain_soul(f: FighterState, hundredths: int) -> void:
	if hundredths <= 0 or f.ko:
		return
	var cap := rules.soul_max * 100
	var before := f.soul
	f.soul = mini(cap, f.soul + hundredths)
	if before < cap and f.soul == cap:
		_emit(EventType.SOUL_FULL, f.slot, -1, &"", f.pos, rules.soul_max)


# --- Bookkeeping ------------------------------------------------------------------------

func _post_tick(f: FighterState) -> void:
	for s in f.skill_window.size():
		if f.skill_window[s] > 0:
			f.skill_window[s] -= 1
			if f.skill_window[s] == 0:
				_end_skill_sequence(f, s)
	for s in f.marks.size():
		if f.marks[s] > 0:
			f.marks[s] -= 1
	if f.dash_recharge > 0:
		f.dash_recharge -= 1
		if f.dash_recharge == 0:
			f.dash_charges += 1
			if f.dash_charges < dash_max_charges(f):
				f.dash_recharge = dash_recharge_frames(f)
	for i in f.cooldowns.size():
		if f.cooldowns[i] > 0:
			f.cooldowns[i] -= 1
			if f.cooldowns[i] == 0:
				_emit(EventType.COOLDOWN_READY, f.slot, -1, &"", f.pos, i)
	if f.parry_timer > 0:
		f.parry_timer -= 1
		if f.parry_timer == 0:
			f.parry_lockout = rules.parry_lockout
			_emit(EventType.WHIFF_PARRY, f.slot, -1, &"", f.pos, rules.parry_lockout)
	elif f.parry_lockout > 0:
		f.parry_lockout -= 1
	if f.dodge_lockout > 0 and f.action != Action.DODGE:
		f.dodge_lockout -= 1
	if f.invuln > 0 and f.hitstop == 0 and f.invuln < UNTIL_LANDING:
		f.invuln -= 1
	f.guard_idle += 1
	var guard_max := rules.guard_gauge * 100
	if f.guard_idle > rules.guard_regen_delay and f.guard < guard_max:
		f.guard = mini(guard_max, f.guard + rules.guard_regen_per_second * 100 / 60)
	match f.action:
		Action.HITSTUN, Action.AIR_HITSTUN, Action.WALL_SPLAT, Action.COUNTER_STUN, Action.STAGGERED:
			if f.hitstop == 0:
				f.combo_ticks += 1
		Action.KNOCKDOWN, Action.GUARD_BREAK, Action.GRABBED, Action.KO:
			pass
		_:
			f.combo_hits = 0
			f.combo_damage = 0
			f.combo_ticks = 0
			f.juggle_used = 0
			f.wall_splat_used = false
	if f.knock_ticks == 0 and f.carried_ticks == 0:
		f.splat_armed = false
	var i := 0
	while i < f.buffs.size():
		var buff := f.buffs[i]
		buff.ticks_left -= 1
		if buff.ticks_left <= 0 or (buff.spent and not _cast_live(f, buff.last_cast)):
			f.buffs.remove_at(i)
		else:
			i += 1


func _emit(type: EventType, source: int, target: int, id: StringName, position: Vector3i,
		amount: int) -> SimEvent:
	var e := SimEvent.new()
	e.type = type
	e.tick = state.tick
	e.source = source
	e.target = target
	e.id = id
	e.position = position
	e.amount = amount
	_events.append(e)
	return e

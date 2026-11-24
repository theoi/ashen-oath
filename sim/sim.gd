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
	SimInput.SUPER, SimInput.ABILITY_1, SimInput.ABILITY_2, SimInput.ABILITY_3, SimInput.GRAB,
	SimInput.HEAVY, SimInput.LIGHT, SimInput.DODGE, SimInput.JUMP,
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
	for i in config.slots.size():
		var slot_config := config.slots[i]
		var data := slot_config.fighter
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

## Advances one tick. `inputs[slot]` is that slot's SimInput frame (missing = neutral).
## Returns the events of this tick (also valid until the next step).
func step(inputs: PackedInt32Array) -> Array[SimEvent]:
	_events = []
	state.tick += 1
	state.phase_tick += 1
	_advance_phase()
	var accept := state.phase == Phase.FIGHT
	for f in state.fighters:
		_read_input(f, inputs[f.slot] if f.slot < inputs.size() else 0, accept)
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
		Action.ATTACK:
			var move := current_move(f)
			return move.invuln_end > 0 and f.move_frame >= move.invuln_start and f.move_frame <= move.invuln_end
	return false


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
		f.cooldowns.resize(maxi(3, fighter_data[f.slot].abilities.size()))
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
	match bit:
		SimInput.SUPER:
			return _try_move(f, data.find_move(data.super_move), bit)
		SimInput.ABILITY_1, SimInput.ABILITY_2, SimInput.ABILITY_3:
			var ability := SimInput.ABILITIES.find(bit)
			if ability < data.abilities.size() and f.cooldowns[ability] == 0:
				return _try_move(f, data.find_move(data.abilities[ability]), bit)
			return false
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
	f.move_hit_masks.fill(0)
	f.charge = 0
	f.charging = false
	f.armor_left = move.armor_hits
	f.landing_recovery = 0
	f.buffer = 0
	if move.kind == MoveData.Kind.ABILITY:
		var ability := data.abilities.find(move.id)
		if ability >= 0 and move.cooldown > 0:
			f.cooldowns[ability] = move.cooldown
	if move.soul_cost > 0:
		f.soul -= move.soul_cost * 100
	var target := attack_target(f)
	if target != null:
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


func _attack(f: FighterState) -> void:
	var move := current_move(f)
	var advanced := true
	if f.charging:
		if (f.buttons & f.move_button) and f.charge < move.charge_max:
			f.charge += 1
			advanced = false
		else:
			f.charging = false
	if advanced:
		f.move_frame += 1
		if move.chargeable and f.move_frame == move.charge_frame and (f.buttons & f.move_button):
			f.charging = true
	if f.move_frame > move.total_frames():
		_to_idle(f)
		return
	if _try_chain_or_cancel(f, move):
		return
	if advanced:
		_move_frame_effects(f, move)
	else:
		_move_motion(f, move)


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
	var allowed := _cancel_mask(f, move)
	if allowed == 0:
		return false
	var want := 0
	match f.buffer:
		SimInput.ABILITY_1, SimInput.ABILITY_2, SimInput.ABILITY_3:
			want = CancelData.INTO_ABILITY
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


## Cancel targets allowed on the current frame of `move`.
func _cancel_mask(f: FighterState, move: MoveData) -> int:
	var frame := f.move_frame
	var mask := 0
	var window_end := move.last_active_frame() + rules.cancel_window_frames
	if frame >= move.startup and frame <= window_end:
		if move.is_basic() and f.move_contact >= 1:
			mask |= CancelData.INTO_ABILITY
		if move.kind == MoveData.Kind.ABILITY and f.move_contact >= 2:
			mask |= CancelData.INTO_SUPER
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
	if move.teleport != null and frame == move.teleport.frame:
		_teleport(f, move.teleport)
	for i in move.effects.size():
		if move.effects[i].spawn_frame == frame:
			_spawn_move_effect(f, move, i)
	if move.buff != null and frame == move.buff_frame:
		apply_buff(f, move.buff, f.move_index)


func _move_motion(f: FighterState, move: MoveData) -> void:
	var frame := f.move_frame
	var target := _target_of(f)
	var tracking := _tracking_of(move)
	if target != null and frame < move.startup and tracking > 0:
		f.facing = Fx.turn_toward(f.facing, _angle_to(f, target), tracking)
	var moved := false
	for motion in move.motions:
		if frame < motion.start_frame or frame > motion.end_frame:
			continue
		if motion.homing and target != null and tracking > 0:
			f.facing = Fx.turn_toward(f.facing, _angle_to(f, target), tracking)
		var forward := Fx.mps(motion.forward_speed)
		if motion.stop_at_distance > 0.0 and target != null \
				and Fx.dist_xz(f.pos, target.pos) <= Fx.m(motion.stop_at_distance):
			forward = 0
		var v := Fx.rotate(Vector3i(Fx.mps(motion.side_speed), 0, forward), f.facing)
		f.vel.x = v.x
		f.vel.z = v.z
		if frame == motion.start_frame and motion.up_speed > 0.0:
			f.vel.y = Fx.mps(motion.up_speed)
			f.grounded = false
		moved = true
	if not moved and f.grounded:
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
		var spot: Vector3i
		if target != null:
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


## Hit reactions and other non-player-controlled actions.
func _reaction(f: FighterState) -> void:
	match f.action:
		Action.HITSTUN, Action.BLOCKSTUN, Action.GUARD_BREAK, Action.RECOVER:
			if f.action == Action.HITSTUN and _try_burst(f):
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
			if f.action_tick > rules.knockdown_frames:
				_get_up(f)
		Action.GETUP:
			if f.action_tick > f.action_len:
				_to_idle(f)
			elif f.action_variant == 1:
				var v := Fx.dir(f.move_dir, Fx.m(rules.getup_roll_distance) / maxi(1, rules.getup_roll_frames - 6))
				f.vel = Vector3i(v.x, 0, v.z) if f.action_tick <= rules.getup_roll_frames - 6 else Vector3i.ZERO
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


## Soul Burst out of hitstun, juggles and wall splats (not guard break or throws).
func _try_burst(f: FighterState) -> bool:
	if f.buffer != SimInput.SUPER or f.soul < rules.burst_cost * 100:
		return false
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


func _resolve_combat() -> void:
	var contacts: Array[Contact] = []
	_collect_hitbox_contacts(contacts)
	_destroy_effects_by_hitboxes()
	_collect_effect_contacts(contacts)
	_collect_hazard_contacts(contacts)
	_collect_throw_contacts(contacts)
	for c in contacts:
		_apply_contact(c)
	_remove_dead_effects()


func _collect_hitbox_contacts(contacts: Array[Contact]) -> void:
	for a in state.fighters:
		if a.action != Action.ATTACK or a.hitstop > 0 or a.ko:
			continue
		var move := current_move(a)
		if move.kind == MoveData.Kind.THROW:
			continue
		var group_counts := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
		for hb in move.hitboxes:
			if hb.hit == null or not _hitbox_active(move, hb, a.move_frame):
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


func _hitbox_active(move: MoveData, hb: HitboxData, frame: int) -> bool:
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
	if v.action == Action.DODGE:
		first = data.dodge_invuln_start
	elif v.action == Action.AIR_DODGE:
		first = data.air_dodge_invuln_start
	else:
		return
	if v.action_tick < first or v.action_tick >= first + rules.perfect_dodge_frames:
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
			if not hb.destroys_projectiles or not _hitbox_active(move, hb, a.move_frame):
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
			if hb.hit == null or not _hitbox_active(move, hb, a.move_frame) or a.move_hit_masks[group] & (1 << v.slot):
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
	if c.hit.throw:
		_connect_grab(c)
		return
	if not c.held:
		if _try_parry(c) or _try_block(c) or _try_armor(c):
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
	if c.hit.hitstop >= 0:
		return c.hit.hitstop
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
	var hitstop := rules.hitstop_heavy
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
	var damage := hit.damage
	if c.move != null and c.move.chargeable and c.effect == null and c.move.charge_max > 0:
		damage += damage * c.move.charge_damage_percent * c.charge / (100 * c.move.charge_max)
	if c.counter:
		damage = damage * rules.counter_damage_percent / 100
	if a != null:
		damage = damage * (100 + _use_damage_buffs(a)) / 100
		var hook := traits[a.slot]
		if hook != null:
			damage = damage * hook.damage_percent(self, a, v, c.move, hit) / 100
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
	if a != null:
		_gain_soul(a, damage * rules.soul_per_100_dealt)
		if c.effect == null:
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
	var launched := _react(c, hitstun, was_airborne)
	if launched:
		flags |= SimEvent.FLAG_LAUNCH
	var id := c.move.id if c.move != null else (arena.hazards[c.hazard].id if c.hazard >= 0 else &"")
	var e := _emit(EventType.HIT, a.slot if a != null else -1, v.slot, id, c.point, damage)
	e.flags = flags
	e.hitstop = hitstop
	e.cue = hit.cue
	if launched:
		_emit(EventType.LAUNCH, a.slot if a != null else -1, v.slot, id, v.pos, v.vel.y)
	if a != null:
		var hook := traits[a.slot]
		if hook != null:
			hook.on_hit_dealt(self, a, v, c.move, hit, false)
	if v.hp <= 0:
		_ko(v)


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


## Sums active damage buffs and spends their uses.
func _use_damage_buffs(f: FighterState) -> int:
	var total := 0
	var i := 0
	while i < f.buffs.size():
		var buff := f.buffs[i]
		if buff.damage_bonus_percent != 0:
			total += buff.damage_bonus_percent
			if buff.uses_left > 0:
				buff.uses_left -= 1
				if buff.uses_left == 0:
					f.buffs.remove_at(i)
					continue
		i += 1
	return total


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
		Action.HITSTUN, Action.AIR_HITSTUN, Action.WALL_SPLAT:
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
		if buff.ticks_left <= 0:
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

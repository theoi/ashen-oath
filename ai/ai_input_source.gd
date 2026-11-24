class_name AiInputSource
extends InputSource
## The CPU opponent (design §6): an InputSource that reads what a player could see (positions,
## actions and move frames, cooldowns, meter, effects; never another fighter's buttons or
## buffer) and returns the same per-tick SimInput frames a pad would.
##
## Three layers:
## - Strategy, every `AiDifficulty.strategy_period` frames: utility scores pick an intent
##   (approach, pressure, zone, bait, defend, retreat, circle) from distance, health, meter,
##   cooldowns, the opponent's state and walls, weighted by the fighter's AiProfile.
## - Tactics, every frame: picks moves by reach, startup and on-block safety from the
##   fighter's own MoveData (AiMoveBook), runs strings, cancels, juggles and punishes.
## - Reaction: answers attacks, projectiles, eruptions and grabs after the difficulty's
##   reaction delay, with its probability: block, parry, dodge, jump, tech or Burst.
##
## Deterministic: decisions use an AiRng seeded from the match seed and the slot, so the same
## config and difficulties replay the same match; the recorded Replay reproduces it exactly.
## In 1v2, CPU teammates share AiAttackTokens so only 1 (2 on Nightmare) attacks at a time.

enum Intent { IDLE, APPROACH, PRESSURE, ZONE, BAIT, DEFEND, RETREAT, CIRCLE, PUNISH }
enum Response { NONE, BLOCK, PARRY, DODGE, JUMP, COUNTER, ESCAPE }
enum ThreatKind { MELEE, GRAB, PROJECTILE, ERUPTION }

const INTENT_NAMES: PackedStringArray = ["idle", "approach", "pressure", "zone", "bait", "defend",
		"retreat", "circle", "punish"]
const Action := FighterState.Action
const Entry := AiMoveBook.Entry
const WALL_MARGIN := 14000
const THREAT_TTL := 120


class Threat:
	extends RefCounted
	var kind: ThreatKind = ThreatKind.MELEE
	var slot: int = -1
	var move_index: int = -1
	var effect_id: int = -1
	var respond_tick: int = 0
	var response: Response = Response.NONE
	var expires: int = 0


var difficulty: AiDifficulty
var profile: AiProfile
## Shared by the CPU fighters of one team (null = no sharing, e.g. 1v1).
var tokens: AiAttackTokens
## Current intent, for debugging and the soak report.
var intent: Intent = Intent.IDLE
## Decision counters for the soak report (threats seen, responses, punishes...).
var counters: Dictionary[String, int] = {}

var rng: AiRng = AiRng.new()
var _seeded: bool = false
var _sim: Sim
var _me: FighterState
var _target: FighterState
var _book: AiMoveBook
var _tbook: AiMoveBook
var _tick: int = 0
var _round: int = -1

var _hold: int = 0
var _pulse: int = 0
var _deferred: int = 0
var _last_buttons: int = 0
var _stick_angle: int = 0
var _stick_mag: int = 0

var _next_strategy: int = 0
var _hesitate_until: int = 0
var _aim_noise: int = 0
var _anticipate: bool = false
var _jump_in_ok: bool = false
var _whiff_ok: bool = false
var _super_ok: bool = false
var _circle_dir: int = 1
var _target_switch_tick: int = -999

var _threats: Array[Threat] = []
var _seen_move: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1])
var _seen_frame: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var _seen_effect_id: int = 0
var _guard_until: int = 0
var _escape_until: int = 0
var _escape_angle: int = 0

var _next_attack_tick: int = 0
## Keeps the attack token until the move just pressed has started.
var _token_keep_until: int = 0
var _punish_key: int = -1
var _punish_ok: bool = false
var _punish_counted: int = -1
var _armor_key: int = -1
## Action entries whose chain / cancel decision was already made (one roll per move).
var _chain_key: int = -1
var _cancel_key: int = -1
var _books: Array[AiMoveBook] = []
## Tick the target entered its current action, for one punish decision per opening.
var _target_entry: int = 0
var _target_prev_slot: int = -1
var _target_prev_action: int = -1
var _target_prev_tick: int = 0
var _charge_until: int = 0
var _reaction_key: int = -1
var _reaction_ok: bool = false
var _block_key: int = -1
var _keep_guard: bool = false
var _burst_ok: bool = false
var _getup_attack: bool = false

## Tick the fighter entered its current action (stable through hitstop, unlike action_tick).
var _action_entry: int = 0
var _prev_action: int = -1
var _prev_action_tick: int = 0
var _burst_rolled: bool = false

var _stuck_pos: Vector3i = Vector3i.ZERO
var _stuck_tick: int = 0
var _unstick_until: int = 0
var _unstick_angle: int = 0


func _init(level: AiDifficulty = null, fighter_profile: AiProfile = null, team_tokens: AiAttackTokens = null) -> void:
	difficulty = level if level != null else AiDifficulty.preset(AiDifficulty.Level.NORMAL)
	profile = fighter_profile
	tokens = team_tokens


## CPU sources for `cpu_slots` of a match: one per slot (null for other slots), with attack
## tokens shared per team. `cap` limits the level (story fight 1: AiDifficulty.Level.EASY).
## `profiles` optionally overrides the profile per slot (e.g. the Oath-Shade).
static func for_match(config: SimConfig, cpu_slots: PackedInt32Array, level: int, cap: int = -1,
		profiles: Dictionary = {}) -> Array[InputSource]:
	var preset := AiDifficulty.preset(level, cap)
	var team_tokens := shared_tokens(config, cpu_slots, preset.attack_tokens)
	var sources: Array[InputSource] = []
	for slot in config.slots.size():
		if not slot in cpu_slots:
			sources.append(null)
			continue
		var fighter_profile: AiProfile = profiles.get(slot, null)
		sources.append(AiInputSource.new(preset, fighter_profile, team_tokens.get(config.slots[slot].team)))
	return sources


## Attack tokens for each team with two or more CPU fighters (a lone CPU needs none).
static func shared_tokens(config: SimConfig, cpu_slots: PackedInt32Array, count: int) -> Dictionary[int, AiAttackTokens]:
	var per_team: Dictionary[int, int] = {}
	for slot in cpu_slots:
		if slot >= 0 and slot < config.slots.size():
			var team := config.slots[slot].team
			per_team[team] = per_team.get(team, 0) + 1
	var result: Dictionary[int, AiAttackTokens] = {}
	for team: int in per_team:
		if per_team[team] >= 2:
			result[team] = AiAttackTokens.new(count)
	return result


func next_frame(sim: Sim, slot: int) -> int:
	_sim = sim
	_me = sim.fighter(slot)
	_tick = sim.state.tick
	_hold = 0
	_pulse = 0
	_stick_mag = 0
	if not _seeded:
		_setup(slot)
	if sim.state.round_number != _round:
		_reset_round()
	if sim.state.phase != SimState.Phase.FIGHT or _me.ko:
		_give_back_token()
		return _finish()
	_target = _choose_target()
	if _target == null:
		_give_back_token()
		return _finish()
	_tbook = _books[_target.slot]
	if _me.action != _prev_action or _me.action_tick < _prev_action_tick:
		_action_entry = _tick
	_prev_action = _me.action
	_prev_action_tick = _me.action_tick
	if _target.slot != _target_prev_slot or _target.action != _target_prev_action \
			or _target.action_tick < _target_prev_tick:
		_target_entry = _tick
	_target_prev_slot = _target.slot
	_target_prev_action = _target.action
	_target_prev_tick = _target.action_tick
	_observe()
	_manage_lock()
	if _tick >= _next_strategy:
		_strategy()
		_next_strategy = _tick + maxi(1, difficulty.strategy_period)
	_act()
	_update_token()
	return _finish()


func intent_name() -> String:
	return INTENT_NAMES[intent]


func _count(key: String) -> void:
	counters[key] = counters.get(key, 0) + 1


# --- Setup ---------------------------------------------------------------------------------

func _setup(slot: int) -> void:
	_seeded = true
	rng.reseed(_sim.config.seed * 7919 + slot * 104729 + difficulty.level * 31 + 17)
	for data in _sim.fighter_data:
		_books.append(AiMoveBook.new(data))
	_book = _books[slot]
	if profile == null:
		profile = AiProfile.for_fighter(_sim.fighter_data[slot])
	_circle_dir = 1 if rng.chance(50) else -1


func _reset_round() -> void:
	_round = _sim.state.round_number
	_threats.clear()
	_seen_move.fill(-1)
	_seen_frame.fill(0)
	_guard_until = 0
	_escape_until = 0
	_next_strategy = 0
	_next_attack_tick = 0
	_hesitate_until = 0
	_unstick_until = 0
	_charge_until = 0
	intent = Intent.IDLE
	if tokens != null:
		tokens.release(_me.slot, _tick)


# --- Output --------------------------------------------------------------------------------

func _finish() -> int:
	var pulse := _pulse | _deferred
	# A press needs the button up on the previous frame: re-press next frame instead.
	var blocked := pulse & _last_buttons
	_deferred = blocked & ~_hold if _me != null and not _me.ko else 0
	var buttons := (_hold | pulse) & ~blocked
	_last_buttons = buttons
	if _stick_mag <= 0:
		return SimInput.make(buttons)
	var x := Fx.sin_q(_stick_angle) * _stick_mag / Fx.TRIG_ONE
	var z := Fx.cos_q(_stick_angle) * _stick_mag / Fx.TRIG_ONE
	return SimInput.make(buttons, x, z)


func _press(bit: int) -> void:
	_pulse |= bit


func _stick(angle: int, magnitude: int = SimInput.STICK_MAX) -> void:
	_stick_angle = Fx.wrap_angle(angle)
	_stick_mag = magnitude


func _run_toward(angle: int, magnitude: int = SimInput.STICK_MAX) -> void:
	if _tick < _unstick_until:
		_stick(_unstick_angle, magnitude)
		return
	_stick(_steer(angle + _aim_noise), magnitude)
	_check_stuck(angle)


# --- Perception ----------------------------------------------------------------------------

func _choose_target() -> FighterState:
	var enemies := _sim.enemies_of(_me)
	if enemies.is_empty():
		return null
	var current: FighterState = null
	if _me.target >= 0:
		var t := _sim.fighter(_me.target)
		if not t.ko and t.team != _me.team:
			current = t
	var best: FighterState = null
	var best_score := 0
	for e in enemies:
		var score := Fx.dist_xz(_me.pos, e.pos)
		if e.action == Action.ATTACK and absi(Fx.angle_diff(e.facing, _angle_from(e, _me))) < Fx.deg(45.0):
			score -= Fx.m(2.0)
		if e.in_hitstun():
			score -= Fx.m(1.5)
		if best == null or score < best_score:
			best = e
			best_score = score
	if current != null and best != current and _tick - _target_switch_tick < 60:
		return current
	if current != null and best != current:
		var current_score := Fx.dist_xz(_me.pos, current.pos)
		if current_score - best_score < Fx.m(1.5):
			return current
	return best


func _manage_lock() -> void:
	if _tick % 4 != 0:
		return
	if not _me.hard_lock:
		_press(SimInput.LOCK)
	elif _me.target != _target.slot:
		_press(SimInput.TARGET_NEXT)
		_target_switch_tick = _tick


func _observe() -> void:
	for e in _sim.state.fighters:
		if e.team == _me.team:
			continue
		if e.action != Action.ATTACK or e.ko:
			_seen_move[e.slot] = -1
			continue
		if e.move_index != _seen_move[e.slot] or e.move_frame < _seen_frame[e.slot]:
			_on_enemy_move(e)
		_seen_move[e.slot] = e.move_index
		_seen_frame[e.slot] = e.move_frame
	for e in _sim.state.effects:
		if e.id <= _seen_effect_id:
			continue
		_seen_effect_id = e.id
		if e.team != _me.team and not e.dead:
			_on_effect(e)
	var i := 0
	while i < _threats.size():
		if _threats[i].expires < _tick:
			_threats.remove_at(i)
		else:
			i += 1


func _delay() -> int:
	return difficulty.reaction_delay + rng.below(difficulty.reaction_jitter + 1)


func _on_enemy_move(e: FighterState) -> void:
	var entry := _books[e.slot].entry(e.move_index)
	if entry == null or not entry.melee:
		return
	_count("threats")
	if not rng.chance(difficulty.defend_chance):
		return
	var t := Threat.new()
	t.slot = e.slot
	t.move_index = e.move_index
	t.respond_tick = _tick + _delay()
	t.expires = _tick + THREAT_TTL
	if entry.has(AiMoveBook.TAG_THROW):
		t.kind = ThreatKind.GRAB
		var roll := rng.below(100)
		t.response = Response.JUMP if roll < 40 else (Response.DODGE if roll < 80 else Response.COUNTER)
	else:
		t.kind = ThreatKind.MELEE
		t.response = _pick_defense(entry.has(AiMoveBook.TAG_UNBLOCKABLE))
	_threats.append(t)


func _on_effect(e: EffectState) -> void:
	var ed := _sim.effect_data(e)
	if ed.hit == null:
		return
	_count("threats")
	if not rng.chance(difficulty.defend_chance):
		return
	var t := Threat.new()
	t.slot = e.owner
	t.effect_id = e.id
	t.respond_tick = _tick + _delay()
	t.expires = _tick + THREAT_TTL + ed.delay
	if ed.anchor == EffectData.Anchor.TARGET or (ed.speed <= 0.0 and ed.delay > 0):
		t.kind = ThreatKind.ERUPTION
		t.response = Response.ESCAPE
	else:
		t.kind = ThreatKind.PROJECTILE
		t.response = _pick_defense(ed.hit.unblockable or not ed.projectile)
	_threats.append(t)


func _pick_defense(unblockable: bool) -> Response:
	if rng.chance(difficulty.parry_percent) and not unblockable:
		return Response.PARRY
	if unblockable or rng.chance(difficulty.dodge_percent):
		return Response.DODGE
	return Response.BLOCK


# --- Acting --------------------------------------------------------------------------------

func _act() -> void:
	match _me.action:
		Action.GRABBED:
			_grabbed()
		Action.HITSTUN, Action.AIR_HITSTUN, Action.WALL_SPLAT:
			_in_hitstun()
		Action.KNOCKDOWN:
			_knocked_down()
		Action.ATTACK:
			_attacking()
		Action.BLOCKSTUN:
			_blocking()
		Action.AIR:
			_airborne()
		Action.IDLE, Action.GUARD:
			_neutral()
		Action.LAND, Action.DODGE, Action.JUMP_SQUAT:
			# Buffered presses (8 frames) come out as soon as the fighter can act.
			if _me.action_len > 0 and _me.action_len - _me.action_tick <= 4:
				_try_punish()


func _neutral() -> void:
	if _respond_to_threats():
		return
	if _tick < _escape_until:
		_run_toward(_escape_angle)
		return
	if _tick < _guard_until:
		_hold |= SimInput.GUARD
		return
	if _try_juggle():
		return
	if _try_armor_answer():
		return
	if _try_punish():
		return
	if intent != Intent.RETREAT and _check_approach(Fx.dist_xz(_me.pos, _target.pos), _angle_to_target()):
		return
	if _anticipate and _should_guard_preemptively():
		_hold |= SimInput.GUARD
		_strafe_slowly()
		return
	match intent:
		Intent.IDLE:
			pass
		Intent.APPROACH:
			_approach()
		Intent.PRESSURE, Intent.PUNISH:
			_pressure()
		Intent.ZONE:
			_zone()
		Intent.BAIT:
			_bait()
		Intent.DEFEND:
			_defend()
		Intent.RETREAT:
			_retreat()
		Intent.CIRCLE:
			_circle()


func _respond_to_threats() -> bool:
	for t in _threats:
		if t.respond_tick > _tick or t.response == Response.NONE:
			continue
		var response := t.response
		var result := _respond(t)
		if result >= 0:
			if result == 1:
				_count("react_" + Response.keys()[t.response if t.response != Response.NONE else response].to_lower())
				t.response = Response.NONE
			return true
	return false


## Executes a threat response. Returns 1 when done, 0 when it acted and keeps waiting
## (e.g. holding guard until the dodge timing), -1 when the threat no longer applies.
func _respond(t: Threat) -> int:
	var frames_to_hit := 0
	var hit_end := 0
	var source := Vector3i.ZERO
	var reach := 0
	if t.kind == ThreatKind.MELEE or t.kind == ThreatKind.GRAB:
		var e := _sim.fighter(t.slot)
		var entry := _books[t.slot].entry(t.move_index)
		if e.action != Action.ATTACK or e.move_index != t.move_index or e.move_frame > entry.last_hit_frame:
			t.response = Response.NONE
			return -1
		var d := Fx.dist_xz(e.pos, _me.pos)
		if d > entry.reach + _radius(_me) + Fx.m(0.8):
			return -1
		if d > Fx.m(1.6) and absi(Fx.angle_diff(e.facing, _angle_from(e, _me))) > Fx.deg(50.0):
			return -1
		frames_to_hit = entry.hit_frame - e.move_frame
		hit_end = entry.last_hit_frame - e.move_frame
		source = e.pos
	else:
		var effect := _effect_by_id(t.effect_id)
		if effect == null:
			t.response = Response.NONE
			return -1
		var ed := _sim.effect_data(effect)
		source = effect.pos
		var d := Fx.dist_xz(effect.pos, _me.pos)
		if t.kind == ThreatKind.ERUPTION:
			if d > effect.radius + _radius(_me) + Fx.m(0.3):
				t.response = Response.NONE
				return -1
			frames_to_hit = ed.delay - effect.age + 1
			hit_end = frames_to_hit + ed.lifetime
		else:
			var speed := maxi(1, Fx.length_xz(effect.vel))
			var heading := Fx.angle_of(effect.vel.x, effect.vel.z)
			if absi(Fx.angle_diff(heading, Fx.angle_of(_me.pos.x - effect.pos.x, _me.pos.z - effect.pos.z))) > Fx.deg(25.0):
				return -1
			# Delayed projectiles neither move nor hit until their delay is over.
			frames_to_hit = maxi(0, ed.delay + 1 - effect.age) + maxi(0, (d - effect.radius - _radius(_me)) / speed)
			hit_end = frames_to_hit + 3
	var data := _sim.fighter_data[_me.slot]
	var away := Fx.angle_of(_me.pos.x - source.x, _me.pos.z - source.z)
	match t.response:
		Response.BLOCK:
			_hold |= SimInput.GUARD
			_guard_until = _tick + maxi(0, hit_end) + 6
			return 1
		Response.PARRY:
			if _me.parry_lockout > 0 or frames_to_hit < 2:
				t.response = Response.BLOCK
				return _respond(t)
			if frames_to_hit - 1 > data.parry_window - 2:
				return -1
			if _me.buttons & SimInput.GUARD:
				return 0
			_press(SimInput.GUARD)
			_guard_until = _tick + maxi(0, hit_end) + 6
			return 1
		Response.DODGE:
			if _me.dodge_lockout > 0 or frames_to_hit < data.dodge_invuln_start:
				t.response = Response.BLOCK if t.kind != ThreatKind.GRAB else Response.COUNTER
				return _respond(t)
			if frames_to_hit > data.dodge_invuln_end - 2:
				if t.kind != ThreatKind.GRAB:
					_hold |= SimInput.GUARD
				return 0
			_press(SimInput.DODGE)
			_stick(_dodge_angle(away))
			return 1
		Response.JUMP:
			_press(SimInput.JUMP)
			_stick(away)
			return 1
		Response.COUNTER:
			if _book.light != null:
				_press(SimInput.LIGHT)
				_stick_mag = 0
			return 1
		Response.ESCAPE:
			if frames_to_hit <= 0:
				return -1
			if frames_to_hit >= data.dodge_invuln_start and frames_to_hit <= data.dodge_invuln_end - 2 \
					and _me.dodge_lockout == 0:
				_press(SimInput.DODGE)
				_stick(_dodge_angle(away))
				return 1
			_escape_until = _tick + frames_to_hit
			_escape_angle = _steer(away)
			_run_toward(away)
			return 1
	return -1


func _dodge_angle(away: int) -> int:
	# Sidestep (beats slow-tracking heavies), toward the side with more room.
	var left := Fx.wrap_angle(away + Fx.QUARTER_TURN)
	var right := Fx.wrap_angle(away - Fx.QUARTER_TURN)
	return left if _room_toward(left) >= _room_toward(right) else right


func _grabbed() -> void:
	if _me.grab_tech_left <= 0:
		return
	if _action_entry != _reaction_key:
		_reaction_key = _action_entry
		_reaction_ok = rng.chance(difficulty.tech_chance)
	# The tech window is short (CombatRules.grab_tech_window), so trained fighters tech early.
	var delay := mini(maxi(3, difficulty.reaction_delay / 2), _sim.rules.grab_tech_window - 2)
	if _reaction_ok and _tick - _action_entry >= delay:
		_press(SimInput.GRAB)


func _in_hitstun() -> void:
	# Nightmare keeps a full meter for its super unless the combo is threatening its life.
	var saving := difficulty.super_use >= 3 and _book.super_entry != null \
			and _me.soul >= _sim.rules.super_cost * 100 and _me.hp * 100 > _me.max_hp * 35
	if _me.soul >= _sim.rules.burst_cost * 100 and difficulty.burst_chance > 0 and not saving:
		var threshold := maxi(1, 3 - profile.burst_bias - (1 if _me.hp * 100 < _me.max_hp * 40 else 0))
		if _me.combo_hits < threshold:
			_burst_rolled = false
		elif not _burst_rolled:
			# One decision per combo, made when it reaches the threshold.
			_burst_rolled = true
			_burst_ok = rng.chance(difficulty.burst_chance)
		if _me.combo_hits >= threshold and _burst_ok:
			_press(SimInput.SUPER)
			return
	if _me.action == Action.AIR_HITSTUN:
		if _action_entry != _reaction_key:
			_reaction_key = _action_entry
			_reaction_ok = rng.chance(difficulty.tech_chance)
		if _reaction_ok:
			var falling_low := _me.vel.y < 0 and _me.pos.y <= -_me.vel.y * 5
			if _me.stun <= 3 or falling_low:
				_press(SimInput.DODGE)
				_stick(_steer(_angle_from(_target, _me)))


func _knocked_down() -> void:
	if _action_entry != _reaction_key:
		_reaction_key = _action_entry
		# Untrained fighters just stand up; trained ones mix rolls and get-up attacks.
		_reaction_ok = rng.chance(difficulty.tech_chance)
		_getup_attack = rng.chance(30)
	if _me.action_tick < _sim.rules.knockdown_frames - 6:
		return
	if not _reaction_ok:
		return
	if _getup_attack and _book.getup != null and Fx.dist_xz(_me.pos, _target.pos) < Fx.m(2.5):
		_hold |= SimInput.LIGHT
	else:
		_hold |= SimInput.DODGE
		_stick(_steer(_angle_from(_target, _me) + Fx.QUARTER_TURN * _circle_dir))


func _blocking() -> void:
	if _action_entry != _block_key:
		_block_key = _action_entry
		_keep_guard = rng.chance(difficulty.hold_guard_percent)
	if _keep_guard or _tick < _guard_until:
		_hold |= SimInput.GUARD
	if _me.stun <= 3:
		_try_punish()


func _attacking() -> void:
	var entry := _book.entry(_me.move_index)
	if entry == null:
		return
	if entry.move.chargeable and _tick < _charge_until:
		_hold |= _me.move_button
	if _me.move_contact == 0:
		return
	var level := difficulty.combo_level
	var dist := Fx.dist_xz(_me.pos, _target.pos)
	var reach_pad := _radius(_target)
	var hit := _me.move_contact >= 2
	var frame := _me.move_frame
	# A press on the last frames would be buffered into a fresh neutral move instead.
	if frame >= entry.total - 1:
		return
	var follow: Entry = null
	if entry.move.is_basic() and frame >= entry.move.last_active_frame() - 2 and _chain_key != _action_entry:
		_chain_key = _action_entry
		var nl := _book.next_light(entry)
		var nh := _book.next_heavy(entry)
		if hit:
			# Hard and up only chain into follow-ups that are still a true combo.
			if level >= 2:
				if nl != null and not _combos_into(entry, nl):
					nl = null
				if nh != null and not _combos_into(entry, nh):
					nh = null
			if level == 1:
				follow = nl
			elif level == 2:
				follow = nl if nl != null else (nh if rng.chance(50) else null)
			elif level >= 3:
				if nh != null and nh.has(AiMoveBook.TAG_LAUNCH) and _target.grounded:
					follow = nh
				else:
					follow = nl if nl != null else nh
		elif level >= 1:
			# Blocked: Normal keeps mashing sometimes; Hard and up only continue when safe.
			var next := nl if nl != null else nh
			if next != null and (next.on_block >= -4 if level >= 2 else rng.chance(40)):
				follow = next
		if follow != null and follow.reach + reach_pad + Fx.m(0.4) >= dist:
			_cancel_key = _action_entry
			_press(SimInput.LIGHT if follow == nl else SimInput.HEAVY)
			_stick_mag = 0
			return
	if not hit or _cancel_key == _action_entry:
		return
	if level >= 3 and entry.has(AiMoveBook.TAG_JUMP_CANCEL) and _target.action == Action.AIR_HITSTUN \
			and frame > entry.last_hit_frame:
		_cancel_key = _action_entry
		_press(SimInput.JUMP)
		_stick(_angle_to_target(), SimInput.STICK_MAX / 2)
		return
	# Ability and super cancels exist only within the sim's cancel window after the hit.
	if frame <= entry.move.last_active_frame() \
			or frame >= entry.move.last_active_frame() + _sim.rules.cancel_window_frames:
		return
	if level >= 2 and entry.move.is_basic():
		var ability := _best_ability_followup(dist)
		if ability != null:
			_cancel_key = _action_entry
			_press(ability.button)
			_stick_mag = 0
			return
	if entry.move.kind == MoveData.Kind.ABILITY and level >= 2 and difficulty.super_use >= 2:
		var sup := _book.super_entry
		if sup != null and _usable(sup) and sup.reach + reach_pad >= dist:
			_cancel_key = _action_entry
			_press(SimInput.SUPER)


## Whether chaining from `from` (on hit) into `next` hits before the victim's hitstun ends.
## A chain starts on the frame after the last active frame.
func _combos_into(from: Entry, next: Entry) -> bool:
	var stun_left := from.hitstun - (from.move.last_active_frame() - from.hit_frame)
	return next.hit_frame <= stun_left


func _best_ability_followup(dist: int) -> Entry:
	var best: Entry = null
	var best_score := 0
	for e in _book.abilities:
		if e == null or not _usable(e) or e.melee == false:
			continue
		if e.reach + _radius(_target) < dist or e.hit_frame > 16:
			continue
		var score := e.damage * profile.ability_weight(e.ability_slot) / 100
		if e.has(AiMoveBook.TAG_LAUNCH) and difficulty.combo_level >= 3:
			score += 60
		if best == null or score > best_score:
			best = e
			best_score = score
	return best


func _airborne() -> void:
	if _target == null:
		return
	var dist := Fx.dist_xz(_me.pos, _target.pos)
	_stick(_angle_to_target(), SimInput.STICK_MAX if dist > Fx.m(1.0) else 0)
	if not _can_hit_target(null):
		return
	var juggling := _target.action == Action.AIR_HITSTUN
	for e: Entry in [_book.air_light, _book.air_heavy]:
		if e == null:
			continue
		if dist > e.reach + _radius(_target):
			continue
		var my_low := _me.pos.y + e.low
		var my_high := _me.pos.y + e.high
		var t_low := _target.pos.y
		var t_high := _target.pos.y + _height(_target)
		if my_high < t_low or my_low > t_high:
			continue
		if e == _book.air_heavy and juggling and _target.juggle_used + 2 < _sim.rules.juggle_points:
			continue
		if not juggling and not _may_attack():
			return
		_press(e.button)
		_committed(e)
		return


# --- Neutral tactics -----------------------------------------------------------------------

func _approach() -> void:
	var dist := Fx.dist_xz(_me.pos, _target.pos)
	if dist <= _close_range():
		_pressure()
		return
	var angle := _angle_to_target()
	if _may_attack() and _can_hit_target(null):
		var running := _is_running()
		var best := _pick_attack(dist, Intent.APPROACH, running)
		if best != null:
			_use(best, angle)
			return
		if _jump_in_ok and dist > Fx.m(2.2) and dist < Fx.m(4.0) and _book.air_heavy != null:
			_jump_in_ok = false
			_press(SimInput.JUMP)
			_stick(angle)
			return
	_run_toward(angle)


func _pressure() -> void:
	var dist := Fx.dist_xz(_me.pos, _target.pos)
	var angle := _angle_to_target()
	if dist > _close_range() + Fx.m(1.0):
		_run_toward(angle)
		return
	if not _can_hit_target(null):
		# Wait out invincible get-ups and knockdowns just outside their reach.
		if _anticipate:
			_hold |= SimInput.GUARD
		if dist < Fx.m(1.4):
			_run_toward(angle + Fx.HALF_TURN, SimInput.STICK_MAX / 2)
		return
	if not _may_attack():
		if dist > _close_range():
			_run_toward(angle, SimInput.STICK_MAX * 2 / 3)
		elif _anticipate:
			_hold |= SimInput.GUARD
		return
	var guarding := _target.action == Action.GUARD or _target.action == Action.BLOCKSTUN
	if guarding and _book.grab != null and dist <= _book.grab.reach + _radius(_target) \
			and rng.chance(profile.grab):
		_use(_book.grab, angle)
		return
	if guarding and _book.heavy != null and _book.heavy.move.chargeable and _target.action_tick > 30 \
			and rng.chance(profile.charge):
		_charge_until = _tick + _book.heavy.move.charge_frame + _book.heavy.move.charge_max + 2
		_use(_book.heavy, angle)
		return
	var best := _pick_attack(dist, Intent.PRESSURE, false)
	if best != null:
		_use(best, angle)
	elif dist > _close_range() * 2 / 3:
		_run_toward(angle, SimInput.STICK_MAX * 2 / 3)


func _zone() -> void:
	var dist := Fx.dist_xz(_me.pos, _target.pos)
	var angle := _angle_to_target()
	var lo := Fx.m(profile.preferred_min)
	var hi := Fx.m(profile.preferred_max)
	if dist <= _close_range() and _may_attack() and _can_hit_target(null):
		var close := _pick_attack(dist, Intent.PRESSURE, false)
		if close != null:
			_use(close, angle)
			return
	if _may_attack() and _can_hit_target(null):
		var ranged := _pick_attack(dist, Intent.ZONE, false)
		if ranged != null and (ranged.has(AiMoveBook.TAG_PROJECTILE) or ranged.has(AiMoveBook.TAG_ERUPTION)):
			_use(ranged, angle)
			return
	if dist < lo:
		if _cornered() and dist < Fx.m(3.0):
			_escape_corner()
		elif dist < Fx.m(3.0) and _blink(angle + Fx.HALF_TURN + _circle_dir * Fx.deg(40.0)):
			return
		else:
			_run_toward(angle + Fx.HALF_TURN)
	elif dist > hi:
		_run_toward(angle + _circle_dir * Fx.deg(25.0))
	else:
		_strafe(angle, SimInput.STICK_MAX * 3 / 4)


func _bait() -> void:
	var dist := Fx.dist_xz(_me.pos, _target.pos)
	var angle := _angle_to_target()
	var edge := _tbook.quick_reach + _radius(_me) + Fx.m(0.6)
	if dist < edge - Fx.m(0.3):
		_run_toward(angle + Fx.HALF_TURN, SimInput.STICK_MAX * 3 / 4)
	elif dist > edge + Fx.m(0.6):
		_run_toward(angle, SimInput.STICK_MAX * 3 / 4)
	else:
		# Dance on the edge of their reach.
		var phase := (_tick / 18) % 3
		if phase == 0:
			_run_toward(angle, SimInput.STICK_MAX / 2)
		elif phase == 1:
			_run_toward(angle + Fx.HALF_TURN, SimInput.STICK_MAX / 2)
		else:
			_strafe(angle, SimInput.STICK_MAX / 2)


func _defend() -> void:
	var dist := Fx.dist_xz(_me.pos, _target.pos)
	if dist < _threat_range() + Fx.m(0.8):
		_hold |= SimInput.GUARD
		_strafe_slowly()
	else:
		_strafe(_angle_to_target(), SimInput.STICK_MAX / 2)


func _retreat() -> void:
	var dist := Fx.dist_xz(_me.pos, _target.pos)
	var angle := _angle_to_target()
	if _cornered() and dist < Fx.m(3.0):
		_escape_corner()
		return
	# Zoners keep shooting while they back off.
	if dist >= Fx.m(3.5) and _fire_ranged(dist, angle):
		return
	if dist < Fx.m(3.0) and _blink(angle + Fx.HALF_TURN):
		return
	_run_toward(angle + Fx.HALF_TURN + _circle_dir * Fx.deg(30.0))


func _fire_ranged(dist: int, angle: int) -> bool:
	if not _may_attack() or not _can_hit_target(null):
		return false
	var ranged := _pick_attack(dist, Intent.ZONE, false)
	if ranged == null or not (ranged.has(AiMoveBook.TAG_PROJECTILE) or ranged.has(AiMoveBook.TAG_ERUPTION)):
		return false
	_use(ranged, angle)
	return true


## Blinks (a ready teleport ability with no hitbox) toward the angle, steered off walls.
func _blink(angle: int) -> bool:
	for e in _book.abilities:
		if e != null and e.has(AiMoveBook.TAG_TELEPORT) and not e.melee and _usable(e):
			_press(e.button)
			_stick(_steer(angle))
			return true
	return false


## Whether backing off actually opens space: faster than the opponent, or a blink ready.
func _can_outpace() -> bool:
	if _sim.fighter_data[_me.slot].run_speed > _sim.fighter_data[_target.slot].run_speed:
		return true
	for e in _book.abilities:
		if e != null and e.has(AiMoveBook.TAG_TELEPORT) and not e.melee and _usable(e):
			return true
	return false


func _circle() -> void:
	var dist := Fx.dist_xz(_me.pos, _target.pos)
	var angle := _angle_to_target()
	if _tick % 90 == 0 and rng.chance(35):
		_circle_dir = -_circle_dir
	if dist < Fx.m(3.5):
		_run_toward(angle + Fx.HALF_TURN - _circle_dir * Fx.deg(50.0))
	elif dist > Fx.m(5.5):
		_run_toward(angle + _circle_dir * Fx.deg(40.0))
	else:
		_strafe(angle, SimInput.STICK_MAX * 2 / 3)


func _strafe(angle_to_target: int, magnitude: int) -> void:
	var dir := angle_to_target + _circle_dir * Fx.QUARTER_TURN
	if _room_toward(Fx.wrap_angle(dir)) < Fx.m(1.5):
		_circle_dir = -_circle_dir
		dir = angle_to_target + _circle_dir * Fx.QUARTER_TURN
	_run_toward(dir, magnitude)


func _strafe_slowly() -> void:
	if _tick % 40 < 20:
		_strafe(_angle_to_target(), SimInput.STICK_MAX / 2)


func _escape_corner() -> void:
	var angle := _angle_to_target()
	var side := Fx.wrap_angle(angle + _circle_dir * Fx.QUARTER_TURN)
	if _room_toward(side) < Fx.m(2.0):
		_circle_dir = -_circle_dir
		side = Fx.wrap_angle(angle + _circle_dir * Fx.QUARTER_TURN)
	for e in _book.abilities:
		if e != null and e.has(AiMoveBook.TAG_TELEPORT) and not e.melee and _usable(e):
			_press(e.button)
			_stick(side)
			return
	if _me.dodge_lockout == 0 and rng.chance(30):
		_press(SimInput.DODGE)
		_stick(side)
		return
	_run_toward(side)


func _should_guard_preemptively() -> bool:
	if intent == Intent.APPROACH or intent == Intent.PUNISH:
		return false
	var dist := Fx.dist_xz(_me.pos, _target.pos)
	if dist > _threat_range() + Fx.m(0.5):
		return false
	match _target.action:
		Action.IDLE, Action.GUARD, Action.AIR, Action.ATTACK, Action.JUMP_SQUAT:
			return intent != Intent.PRESSURE or _tick < _next_attack_tick
	return false


# --- Offense helpers -----------------------------------------------------------------------

## Punishes recovery, landing lag, guard breaks and parried staggers when a move gets there in
## time. Returns true when it pressed a button or ran in for the punish.
func _try_punish() -> bool:
	var frames_left := _vulnerable_frames(_target)
	if frames_left < 2:
		return false
	if _target_entry != _punish_key:
		_punish_key = _target_entry
		_punish_ok = rng.chance(difficulty.punish_chance * profile.punish / 100)
	if not _punish_ok or not _may_attack(true):
		return false
	var dist := Fx.dist_xz(_me.pos, _target.pos)
	var lag := 1
	if _me.action == Action.BLOCKSTUN:
		lag += _me.stun
	elif _me.action == Action.LAND or _me.action == Action.DODGE or _me.action == Action.JUMP_SQUAT:
		lag += maxi(0, _me.action_len - _me.action_tick)
	var best: Entry = null
	var best_score := 0
	for e in _candidates(false):
		if e.has(AiMoveBook.TAG_PROJECTILE) and dist < Fx.m(3.0):
			continue
		if e.hit_frame + lag > frames_left or e.reach + _radius(_target) < dist or dist < e.min_reach:
			continue
		if e.use == AiMoveBook.Use.GRAB and not _target.grounded:
			continue
		var score := e.damage * 100 / maxi(4, e.hit_frame)
		if e.use == AiMoveBook.Use.SUPER:
			score = score * 2 if difficulty.super_use >= 2 else 0
		if e.has(AiMoveBook.TAG_LAUNCH) and difficulty.combo_level >= 2:
			score += 300
		if e.use == AiMoveBook.Use.LIGHT and difficulty.combo_level >= 1:
			score += 200
		if e.ability_slot >= 0:
			score = score * profile.ability_weight(e.ability_slot) / 100
		if best == null or score > best_score:
			best = e
			best_score = score
	if best != null:
		if _punish_counted != _punish_key:
			_punish_counted = _punish_key
			_count("punishes")
		_use(best, _angle_to_target())
		return true
	# Too far for a standing punish: run in if the gap closes in time.
	if _me.action != Action.IDLE and _me.action != Action.GUARD:
		return false
	var quick := _book.light if _book.light != null else _book.heavy
	if quick == null:
		return false
	var gap := dist - quick.reach - _radius(_target)
	var run := Fx.mps(_sim.fighter_data[_me.slot].run_speed)
	if gap > 0 and gap / maxi(1, run) + quick.hit_frame + 6 <= frames_left:
		intent = Intent.PUNISH
		_run_toward(_angle_to_target())
		return true
	return false


## Answers a known incoming attack with an armored move whose armor covers the hit, or an
## invincible super, that reaches the attacker. One decision per enemy move.
func _try_armor_answer() -> bool:
	if difficulty.combo_level < 1 or profile.armor_answer <= 0:
		return false
	for e in _sim.state.fighters:
		if e.team == _me.team or e.ko or e.action != Action.ATTACK or e.move_frame <= difficulty.reaction_delay:
			continue
		var threat := _books[e.slot].entry(e.move_index)
		if threat == null or not threat.melee or e.move_frame >= threat.hit_frame:
			continue
		var dist := Fx.dist_xz(e.pos, _me.pos)
		if dist > threat.reach + _radius(_me) + Fx.m(0.3):
			continue
		var key := e.slot * 1000003 + _tick - e.move_frame
		if key == _armor_key:
			return false
		_armor_key = key
		if not rng.chance(profile.armor_answer):
			return false
		# The enemy hit lands on our move frame (frames_to_hit), counting our first frame as 1.
		var lands := threat.hit_frame - e.move_frame
		for mine in _candidates(false):
			var m := mine.move
			var armored := m.armor_hits > 0 and lands >= m.armor_start and lands <= m.armor_end
			# Invincible supers work as reversals.
			var reversal := mine.use == AiMoveBook.Use.SUPER and difficulty.super_use >= 2 \
					and lands >= m.invuln_start and lands <= m.invuln_end
			if not armored and not reversal:
				continue
			if mine.reach + _radius(e) < dist or not _may_attack(true):
				continue
			_count("armor_answers")
			_use(mine, Fx.angle_of(e.pos.x - _me.pos.x, e.pos.z - _me.pos.z))
			return true
	return false


## Meets an opponent running in with an armored move that reaches it (armored fighters bait
## approaches this way). Uses the armor_answer habit; ignores the attack gap.
func _check_approach(dist: int, angle: int) -> bool:
	if profile.armor_answer <= 0 or _target.action != Action.IDLE or not _target.grounded:
		return false
	var closing := -((_target.vel.x * (_target.pos.x - _me.pos.x) + _target.vel.z * (_target.pos.z - _me.pos.z)) / maxi(1, dist))
	if closing < Fx.mps(3.0):
		return false
	for e in _candidates(false):
		# Only quick armored moves: slow armored heavies get parried or stepped around.
		if e.move.armor_hits <= 0 or e.move.armor_start > 8 or e.hit_frame > 14 or e.has(AiMoveBook.TAG_THROW):
			continue
		# Where the opponent will be when the move lands.
		var then := dist - closing * e.hit_frame
		if then > e.reach + _radius(_target) or then < 0:
			continue
		var key := _target_entry
		if key == _armor_key:
			return false
		_armor_key = key
		if rng.chance(profile.armor_answer) and _may_attack(true):
			_count("armor_checks")
			_use(e, angle)
			return true
		return false
	return false

## Frames the opponent cannot act or defend in a punishable state, -1 if none.
func _vulnerable_frames(e: FighterState) -> int:
	if e.ko or _sim.is_invulnerable(e):
		return -1
	match e.action:
		Action.ATTACK:
			var entry := _tbook.entry(e.move_index)
			if entry == null or e.move_frame <= entry.last_hit_frame:
				return -1
			return entry.total - e.move_frame
		Action.LAND:
			return e.action_len - e.action_tick if e.action_len > 6 else -1
		Action.GUARD_BREAK:
			return e.stun
		Action.HITSTUN:
			return e.stun if e.combo_hits == 0 else -1
	return -1


func _try_juggle() -> bool:
	if difficulty.combo_level < 2 or _target.action != Action.AIR_HITSTUN:
		return false
	if _target.juggle_used >= _sim.rules.juggle_points - 1 or _sim.is_invulnerable(_target):
		return false
	if _target.last_attacker != _me.slot and tokens != null and not tokens.holds(_me.slot):
		return false
	var dist := Fx.dist_xz(_me.pos, _target.pos)
	var g := Fx.mps2(_sim.rules.juggle_gravity)
	var best: Entry = null
	for e in _candidates(false):
		if e.use == AiMoveBook.Use.GRAB or e.use == AiMoveBook.Use.SUPER or not e.melee:
			continue
		if e.reach + _radius(_target) < dist:
			continue
		var n := e.hit_frame
		var y := maxi(0, _target.pos.y + _target.vel.y * n - g * n * n / 2)
		if e.high < y or e.low > y + _height(_target):
			continue
		if best == null or e.damage > best.damage:
			best = e
	if best != null and (difficulty.combo_level >= 3 or rng.chance(30)) and _may_attack(true):
		_use(best, _angle_to_target())
		return true
	if difficulty.combo_level >= 3 and dist > Fx.m(1.2) and dist < Fx.m(4.0):
		_run_toward(_angle_to_target())
		return true
	return false


## Moves startable from the current state (ready, affordable, right ground/air).
func _candidates(running: bool) -> Array[Entry]:
	var list: Array[Entry] = []
	var airborne := not _me.grounded
	if airborne:
		for e: Entry in [_book.air_light, _book.air_heavy]:
			if e != null:
				list.append(e)
	else:
		var light := _book.run_light if running and _book.run_light != null else _book.light
		for e: Entry in [light, _book.heavy, _book.grab]:
			if e != null:
				list.append(e)
	for e in _book.abilities:
		if e != null and _usable(e) and e.hits_anything():
			list.append(e)
	var sup := _book.super_entry
	if sup != null and _usable(sup) and difficulty.super_use > 0:
		list.append(sup)
	return list


func _usable(e: Entry) -> bool:
	if e.ability_slot >= 0 and (e.ability_slot >= _me.cooldowns.size() or _me.cooldowns[e.ability_slot] > 0):
		return false
	if e.soul_cost > 0 and _me.soul < e.soul_cost * 100:
		return false
	if _me.grounded and not e.move.ground_ok:
		return false
	if not _me.grounded and not (e.move.aerial or e.move.air_ok):
		return false
	return true


## The best move for `purpose` that reaches `dist` now (null if none fits).
func _pick_attack(dist: int, purpose: Intent, running: bool) -> Entry:
	var best: Entry = null
	var best_score := 0
	var pad := _radius(_target)
	var guarding := _target.action == Action.GUARD or _target.action == Action.BLOCKSTUN
	for e in _candidates(running):
		var reach := e.reach + pad
		if _whiff_ok:
			reach += Fx.m(0.8)
		if reach < dist or dist < e.min_reach:
			continue
		if e.use == AiMoveBook.Use.GRAB and (not _target.grounded or not guarding):
			continue
		if e.use == AiMoveBook.Use.SUPER and not _super_allowed(dist):
			continue
		var score := e.damage * 100 / maxi(4, e.hit_frame + 2)
		if e.on_block < -6 and not e.has(AiMoveBook.TAG_UNBLOCKABLE):
			score += e.on_block * (12 if guarding else 4)
		match purpose:
			Intent.APPROACH:
				if e.has(AiMoveBook.TAG_GAP_CLOSER) or e.has(AiMoveBook.TAG_PULL):
					score += 250
				elif e.use == AiMoveBook.Use.RUN_LIGHT:
					score += 150
				elif dist > Fx.m(2.5) and not e.has(AiMoveBook.TAG_TELEPORT):
					score -= 300
			Intent.PRESSURE:
				if e.has(AiMoveBook.TAG_PROJECTILE) or e.has(AiMoveBook.TAG_ERUPTION):
					score -= 400
				if e.use == AiMoveBook.Use.LIGHT:
					score += 150 if difficulty.combo_level >= 1 else 60
				if e.has(AiMoveBook.TAG_GUARD_BREAK) and guarding:
					score += 200
			Intent.ZONE:
				if e.has(AiMoveBook.TAG_PROJECTILE) or e.has(AiMoveBook.TAG_ERUPTION):
					score += 400
		if e.ability_slot >= 0:
			score = score * profile.ability_weight(e.ability_slot) / 100
		score += rng.below(maxi(1, absi(score) / 3 + 20))
		if score <= 0:
			continue
		if best == null or score > best_score:
			best = e
			best_score = score
	return best


func _super_allowed(dist: int) -> bool:
	match difficulty.super_use:
		1:
			return _super_ok
		2, 3:
			return _target.action != Action.GUARD and _target.action != Action.DODGE and _target.grounded
	return false


func _use(e: Entry, angle: int) -> void:
	_press(e.button)
	if e.use == AiMoveBook.Use.RUN_LIGHT:
		_stick(angle)
	elif e.has(AiMoveBook.TAG_TELEPORT):
		_stick(angle)
	else:
		_stick_mag = 0
	_committed(e)


func _committed(e: Entry) -> void:
	_token_keep_until = _tick + 3
	var gap := difficulty.attack_gap * rng.range_i(60, 140) / 100
	_next_attack_tick = _tick + e.total + gap
	_whiff_ok = false


## Whether the CPU may start an attack now (gap elapsed, no known incoming attack, and an
## attack token).
func _may_attack(ignore_gap: bool = false) -> bool:
	if not ignore_gap and (_tick < _next_attack_tick or _known_threat()):
		return false
	if tokens == null:
		return true
	return tokens.acquire(_me.slot, _tick)


## An enemy attack that started at least a reaction delay ago and can still reach: starting
## a move into it would just get counter-hit.
func _known_threat() -> bool:
	for e in _sim.state.fighters:
		if e.team == _me.team or e.action != Action.ATTACK or e.move_frame <= difficulty.reaction_delay:
			continue
		var entry := _books[e.slot].entry(e.move_index)
		if entry == null or not entry.melee or e.move_frame > entry.last_hit_frame:
			continue
		if Fx.dist_xz(e.pos, _me.pos) <= entry.reach + _radius(_me) + Fx.m(0.5):
			return true
	return false


func _can_hit_target(e: Entry) -> bool:
	if _target.ko or _sim.is_invulnerable(_target):
		return false
	if _target.action == Action.KNOCKDOWN:
		return e != null and e.has(AiMoveBook.TAG_OTG)
	return true


func _is_running() -> bool:
	var speed := Fx.length_xz(_me.vel)
	return speed * 10 >= Fx.mps(_sim.fighter_data[_me.slot].run_speed) * 8


# --- Strategy ------------------------------------------------------------------------------

func _strategy() -> void:
	_anticipate = rng.chance(difficulty.anticipate_guard_percent)
	_jump_in_ok = rng.chance(profile.jump_in)
	_whiff_ok = rng.chance(difficulty.whiff_percent)
	_super_ok = rng.chance(30)
	var noise := difficulty.aim_noise_degrees
	_aim_noise = Fx.deg(float(rng.range_i(-noise, noise))) if noise > 0 else 0
	if _tick < _hesitate_until:
		return
	if rng.chance(difficulty.hesitation_percent):
		intent = Intent.IDLE
		_hesitate_until = _tick + rng.range_i(difficulty.hesitation_ticks / 2, difficulty.hesitation_ticks * 3 / 2)
		return
	var dist := Fx.dist_xz(_me.pos, _target.pos) / 100
	var pref_min := roundi(profile.preferred_min * 100.0)
	var pref_max := roundi(profile.preferred_max * 100.0)
	var close := _close_range() / 100
	var threat := _threat_range() / 100
	var lead := _me.hp * 100 / maxi(1, _me.max_hp) - _target.hp * 100 / maxi(1, _target.max_hp)
	var seconds := _sim.seconds_left()
	var ranged := _has_ranged_ready()
	var target_guarding := _target.action == Action.GUARD or _target.action == Action.BLOCKSTUN
	var target_busy := _vulnerable_frames(_target) > 0 or _target.in_hitstun()

	var scores := PackedInt32Array()
	scores.resize(Intent.size())
	scores[Intent.APPROACH] = (40 + mini(40, (dist - pref_max) / 10)) if dist > pref_max else 5
	var pressure := 0
	if dist <= pref_max + 60 or dist <= close + 60:
		pressure = 35
		if target_guarding:
			pressure += 10
		if _wall_distance(_target.pos) < Fx.m(2.5):
			pressure += 15
		if target_busy:
			pressure += 30
	scores[Intent.PRESSURE] = pressure
	if ranged:
		var zone := 30
		if dist >= pref_min and dist <= pref_max + 300:
			zone += 35
		elif dist >= 350:
			# Ranged tools still work at mid range, short of the preferred band.
			zone += 20
		scores[Intent.ZONE] = zone
	scores[Intent.BAIT] = 30 if dist >= threat and dist <= threat + 250 else 10
	var defend := 15
	if dist < threat + 80 and not target_busy:
		defend += 15
	if lead > 20:
		defend += 10
	if _target.soul >= _sim.rules.super_cost * 100:
		defend += 10
	scores[Intent.DEFEND] = defend
	var retreat := 0
	if dist < pref_min:
		retreat = mini(60, 25 + (pref_min - dist) / 10)
		if dist < 400 and not _can_outpace():
			retreat /= 2
	if lead > 25 and seconds >= 0 and seconds < 20:
		retreat += 30
	scores[Intent.RETREAT] = retreat

	var aggression := difficulty.aggression * profile.aggression / 100
	scores[Intent.APPROACH] = scores[Intent.APPROACH] * aggression * profile.approach / 10000
	scores[Intent.PRESSURE] = scores[Intent.PRESSURE] * aggression * profile.pressure / 10000
	scores[Intent.ZONE] = scores[Intent.ZONE] * aggression * profile.zone / 10000
	scores[Intent.BAIT] = scores[Intent.BAIT] * profile.bait / 100
	scores[Intent.DEFEND] = scores[Intent.DEFEND] * profile.defend / 100
	scores[Intent.RETREAT] = scores[Intent.RETREAT] * profile.retreat / 100

	var amp := 10 + difficulty.hesitation_percent
	var best: int = Intent.CIRCLE
	var best_score := -1
	for i in range(Intent.APPROACH, Intent.CIRCLE):
		var s := scores[i] + rng.below(amp)
		if i == intent:
			s += 8
		if s > best_score:
			best = i
			best_score = s
	var chosen := best as Intent
	if _is_offensive(chosen) and tokens != null and not tokens.acquire(_me.slot, _tick):
		chosen = Intent.ZONE if chosen == Intent.ZONE else Intent.CIRCLE
	intent = chosen


func _is_offensive(value: Intent) -> bool:
	return value == Intent.APPROACH or value == Intent.PRESSURE or value == Intent.ZONE \
			or value == Intent.PUNISH


func _has_ranged_ready() -> bool:
	for e in _book.abilities:
		if e != null and (e.has(AiMoveBook.TAG_PROJECTILE) or e.has(AiMoveBook.TAG_ERUPTION)) and _usable(e):
			return true
	return false


func _update_token() -> void:
	if tokens == null or not tokens.holds(_me.slot):
		return
	if _me.action == Action.ATTACK or _tick < _token_keep_until or _target.in_hitstun() \
			or _target.action == Action.GRABBED:
		return
	if not _is_offensive(intent) or tokens.held_for(_me.slot, _tick) > tokens.max_hold:
		tokens.release(_me.slot, _tick)
		if _is_offensive(intent):
			intent = Intent.CIRCLE


func _give_back_token() -> void:
	if tokens != null and _me != null:
		tokens.release(_me.slot, _tick)


# --- Geometry ------------------------------------------------------------------------------

func _radius(f: FighterState) -> int:
	return Fx.m(_sim.fighter_data[f.slot].radius)


func _height(f: FighterState) -> int:
	return Fx.m(_sim.fighter_data[f.slot].height)


func _angle_to_target() -> int:
	return Fx.angle_of(_target.pos.x - _me.pos.x, _target.pos.z - _me.pos.z)


func _angle_from(a: FighterState, b: FighterState) -> int:
	return Fx.angle_of(b.pos.x - a.pos.x, b.pos.z - a.pos.z)


## Reach at which the CPU starts its close-range game.
func _close_range() -> int:
	return _book.quick_reach + _radius(_target) + Fx.m(0.2)


## How close the opponent must be to threaten with its quick moves.
func _threat_range() -> int:
	return _tbook.quick_reach + _radius(_me)


func _effect_by_id(id: int) -> EffectState:
	for e in _sim.state.effects:
		if e.id == id and not e.dead:
			return e
	return null


func _wall_distance(pos: Vector3i) -> int:
	var arena := _sim.arena
	var best := Fx.m(100.0)
	for i in arena.edge_points.size():
		best = mini(best, arena.edge_distance(i, pos))
	return best


func _cornered() -> bool:
	var away := Fx.wrap_angle(_angle_to_target() + Fx.HALF_TURN)
	return _room_toward(away) < Fx.m(2.0)


## Free distance (units, capped at 6 m) from the fighter along `angle` before a wall or obstacle.
func _room_toward(angle: int) -> int:
	var step := Fx.m(0.5)
	var radius := _radius(_me)
	var arena := _sim.arena
	for k in range(1, 13):
		var p := _me.pos + Fx.dir(angle, step * k)
		for i in arena.edge_points.size():
			if arena.edge_distance(i, p) < radius:
				return step * (k - 1)
		for i in arena.obstacle_a.size():
			var c := ArenaCollision.closest_on_segment(arena.obstacle_a[i], arena.obstacle_b[i], p)
			var reach := arena.obstacle_radius[i] + radius
			if Fx.dist2_xz(c, p) < reach * reach:
				return step * (k - 1)
	return step * 12


## Bends a run direction so it slides along nearby walls and around obstacles.
func _steer(angle: int) -> int:
	var dx := Fx.sin_q(angle)
	var dz := Fx.cos_q(angle)
	var arena := _sim.arena
	var pos := _me.pos
	for i in arena.edge_points.size():
		if arena.edge_distance(i, pos) > WALL_MARGIN:
			continue
		var n := arena.edge_normals[i]
		var dot := (dx * n.x + dz * n.z) / Fx.TRIG_ONE
		if dot < 0:
			dx -= n.x * dot / Fx.TRIG_ONE
			dz -= n.z * dot / Fx.TRIG_ONE
	var radius := _radius(_me)
	for i in arena.obstacle_a.size():
		var c := ArenaCollision.closest_on_segment(arena.obstacle_a[i], arena.obstacle_b[i], pos)
		var gap := Fx.dist_xz(c, pos) - arena.obstacle_radius[i] - radius
		if gap > Fx.m(0.8):
			continue
		var ox := pos.x - c.x
		var oz := pos.z - c.z
		var length := maxi(1, Fx.isqrt(ox * ox + oz * oz))
		var nx := ox * Fx.TRIG_ONE / length
		var nz := oz * Fx.TRIG_ONE / length
		var dot := (dx * nx + dz * nz) / Fx.TRIG_ONE
		if dot < 0:
			# Slide around it: drop the inward part and keep tangential motion.
			dx -= nx * dot / Fx.TRIG_ONE
			dz -= nz * dot / Fx.TRIG_ONE
	if absi(dx) < 800 and absi(dz) < 800:
		return Fx.wrap_angle(angle + _circle_dir * Fx.QUARTER_TURN)
	return Fx.angle_of(dx, dz)


func _check_stuck(angle: int) -> void:
	if _tick - _stuck_tick < 30:
		return
	if _tick - _stuck_tick > 40:
		# Not running recently: start a fresh measurement.
		_stuck_tick = _tick
		_stuck_pos = _me.pos
		return
	var moved := Fx.dist_xz(_stuck_pos, _me.pos)
	if _stuck_tick > 0 and moved < Fx.m(0.4) and _me.action == Action.IDLE:
		_unstick_until = _tick + 30
		_circle_dir = -_circle_dir
		_unstick_angle = Fx.wrap_angle(angle + _circle_dir * Fx.QUARTER_TURN)
	_stuck_tick = _tick
	_stuck_pos = _me.pos

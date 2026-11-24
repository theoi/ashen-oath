class_name SparringInputSource
extends InputSource
## A simple scripted sparring partner for the fight sandbox and the look-and-feel check-in:
## walks in, throws strings, abilities and supers, guards, parries and dodges sometimes.
## It reads sim state like a player would and uses its own seeded RNG (never the sim's).
## The real CPU opponent (difficulty levels, tokens) is a separate InputSource.

## Chance per decision to guard / dodge a visible attack, and to tap-parry instead.
var guard_chance: float = 0.45
var dodge_chance: float = 0.15
var parry_chance: float = 0.15
## How eagerly it uses abilities and supers (0..1).
var aggression: float = 0.6

var _rng := RandomNumberGenerator.new()
var _plan: Array[PackedInt32Array] = []
var _plan_tick := 0
var _hold := 0
var _defending := 0
var _defense_buttons := 0
var _idle := 0
var _strafe := 1


func _init(seed_value: int = 1) -> void:
	_rng.seed = seed_value


func next_frame(sim: Sim, slot: int) -> int:
	var me := sim.fighter(slot)
	var enemies := sim.enemies_of(me)
	if enemies.is_empty() or me.ko or sim.state.phase != SimState.Phase.FIGHT:
		_plan.clear()
		return 0
	var foe := enemies[0]
	for e in enemies:
		if Fx.dist2_xz(me.pos, e.pos) < Fx.dist2_xz(me.pos, foe.pos):
			foe = e
	var to := Vector2(Fx.to_m(foe.pos.x - me.pos.x), Fx.to_m(foe.pos.z - me.pos.z))
	var dist := to.length()
	var toward := to.normalized() if dist > 0.01 else Vector2.ZERO
	var data := sim.fighter_data[slot]
	if me.in_hitstun():
		_plan.clear()
		if me.soul_points() >= 50 and _rng.randf() < 0.01 * aggression and me.combo_hits >= 3:
			return SimInput.from_vector(SimInput.SUPER, Vector2.ZERO)
		return 0
	if _defending > 0:
		_defending -= 1
		return SimInput.from_vector(_defense_buttons, Vector2.ZERO if _defense_buttons & SimInput.GUARD else Vector2(-toward.y, toward.x) * float(_strafe))
	if _plan.is_empty() and _threatened(sim, foe, dist):
		var roll := _rng.randf()
		if roll < parry_chance:
			_defending = 3
			_defense_buttons = SimInput.GUARD
			return SimInput.from_vector(SimInput.GUARD, Vector2.ZERO)
		if roll < parry_chance + dodge_chance:
			_defending = 2
			_strafe = -_strafe
			_defense_buttons = SimInput.DODGE
			return SimInput.from_vector(SimInput.DODGE, Vector2(-toward.y, toward.x) * float(_strafe))
		if roll < parry_chance + dodge_chance + guard_chance:
			_defending = 14
			_defense_buttons = SimInput.GUARD
			return SimInput.from_vector(SimInput.GUARD, Vector2.ZERO)
	if not _plan.is_empty():
		return _run_plan(toward)
	if _idle > 0:
		_idle -= 1
		return SimInput.from_vector(0, Vector2(-toward.y, toward.x) * 0.5 * float(_strafe) if dist < 4.0 else toward)
	if me.action != FighterState.Action.IDLE:
		return SimInput.from_vector(0, toward)
	_choose_plan(me, data, dist)
	if _plan.is_empty():
		return SimInput.from_vector(0, toward if dist > 1.8 else Vector2.ZERO)
	return _run_plan(toward)


func _threatened(sim: Sim, foe: FighterState, dist: float) -> bool:
	if foe.action != FighterState.Action.ATTACK or dist > 4.5:
		return false
	var move := sim.current_move(foe)
	return move != null and foe.move_frame <= 2 and _rng.randf() < 0.9


func _choose_plan(me: FighterState, data: FighterData, dist: float) -> void:
	var a := aggression
	if me.soul_points() >= 100 and data.super_move != &"" and dist < 4.5 and _rng.randf() < 0.5 * a:
		_plan_buttons([SimInput.SUPER], 1)
		return
	if dist > 6.5:
		if data.abilities.size() > 0 and me.cooldowns[0] == 0 and dist < 8.0 and _rng.randf() < 0.25 * a:
			_plan_buttons([SimInput.ABILITY_1], 1)
		return
	if dist > 2.3:
		var r := _rng.randf()
		if data.abilities.size() > 0 and me.cooldowns[0] == 0 and dist < 6.5 and r < 0.2 * a:
			_plan_buttons([SimInput.ABILITY_1], 1)
		elif r < 0.35 and data.run_light != &"" and dist < 4.0:
			_plan_buttons([SimInput.LIGHT], 1)
		return
	var roll := _rng.randf()
	if roll < 0.08:
		_idle = 20 + _rng.randi_range(0, 30)
		_strafe = -_strafe
	elif roll < 0.3:
		_plan_buttons([SimInput.LIGHT, SimInput.LIGHT, SimInput.LIGHT], 10)
	elif roll < 0.45:
		if data.abilities.size() > 1 and me.cooldowns[1] == 0:
			_plan_buttons([SimInput.LIGHT, SimInput.LIGHT, SimInput.ABILITY_2, SimInput.JUMP, SimInput.LIGHT, SimInput.LIGHT], 9)
		else:
			_plan_buttons([SimInput.LIGHT, SimInput.LIGHT, SimInput.HEAVY], 10)
	elif roll < 0.58:
		_plan_buttons([SimInput.LIGHT, SimInput.HEAVY], 11)
	elif roll < 0.7:
		_plan_buttons([SimInput.HEAVY, SimInput.HEAVY], 22)
	elif roll < 0.8:
		_plan_buttons([SimInput.GRAB], 1)
	elif roll < 0.9 and data.abilities.size() > 2 and me.cooldowns[2] == 0:
		_plan_buttons([SimInput.ABILITY_3], 1)
	else:
		_plan_buttons([SimInput.LIGHT, SimInput.LIGHT, SimInput.LIGHT], 10)


## Presses each button for 2 ticks, `gap` ticks apart (the sim buffers the rest).
func _plan_buttons(buttons: Array[int], gap: int) -> void:
	_plan.clear()
	var t := 0
	for b in buttons:
		_plan.append(PackedInt32Array([t, b]))
		t += gap
	_plan_tick = 0


func _run_plan(toward: Vector2) -> int:
	var buttons := 0
	var i := 0
	while i < _plan.size():
		var step := _plan[i]
		if _plan_tick >= step[0] and _plan_tick < step[0] + 2:
			buttons |= step[1]
		i += 1
	_plan_tick += 1
	if _plan_tick > _plan[_plan.size() - 1][0] + 3:
		_plan.clear()
	return SimInput.from_vector(buttons, toward)

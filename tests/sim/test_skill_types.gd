extends TestCase
## Skill types: combo, chain with marks, charge levels and perfect release, hold, stance;
## move speed scaling and telegraphs.

const F := preload("res://tests/sim/sim_fixtures.gd")
const K := preload("res://tests/sim/test_skill_kit.gd")
const Action := FighterState.Action
const T := SimEvent.Type
const RISE := SimInput.SKILL_1
const REND := SimInput.SKILL_2
const BULWARK := SimInput.SKILL_3
const WHEEL := SimInput.SKILL_4
const VERDICT := SimInput.SKILL_5
const LEAP := SimInput.SKILL_6

var sim: Sim
var me: FighterState
var foe: FighterState


static func _fighter() -> FighterData:
	var data := F.fighter()
	data.id = &"types"
	data.dash = DashData.new()
	var jab := K._move(&"jab", MoveData.Kind.LIGHT, 4, 2, 12, K._hit(25, HitData.Weight.BASIC))
	var rise1 := K._move(&"rise1", MoveData.Kind.ABILITY, 4, 4, 16, K._hit(70, HitData.Weight.LIGHT))
	rise1.skill_type = MoveData.SkillType.COMBO
	rise1.follow_up = &"rise2"
	rise1.cooldown = 360
	var rise2 := K._move(&"rise2", MoveData.Kind.ABILITY, 7, 4, 16, K._hit(90, HitData.Weight.HEAVY))
	var rend := K._move(&"rend", MoveData.Kind.ABILITY, 6, 1, 14, null)
	rend.hitboxes = []
	rend.skill_type = MoveData.SkillType.CHAIN
	rend.chain_move = &"ignite"
	rend.cooldown = 480
	var wave := EffectData.new()
	wave.id = &"wave"
	wave.spawn_frame = 6
	wave.speed = 30.0
	wave.travel = 9.0
	wave.radius = 0.8
	wave.height = 1.0
	wave.lifetime = 40
	wave.hit = K._hit(70, HitData.Weight.MEDIUM)
	wave.hit.mark = true
	rend.effects = [wave]
	var ignite := K._move(&"ignite", MoveData.Kind.ABILITY, 3, 4, 12, null)
	ignite.hitboxes = []
	ignite.mark_hit = K._hit(60, HitData.Weight.MEDIUM, HitData.Reaction.LAUNCH)
	ignite.mark_hit.launch_height = 1.5
	var bulwark := K._move(&"bulwark", MoveData.Kind.ABILITY, 3, 4, 16, K._hit(40, HitData.Weight.LIGHT))
	bulwark.skill_type = MoveData.SkillType.STANCE
	bulwark.hitboxes[0].start_frame = 35
	bulwark.hitboxes[0].end_frame = 38
	bulwark.recovery = 16 + 35 - 3
	bulwark.stance_start = 3
	bulwark.stance_end = 34
	bulwark.counter_move = &"retribution"
	var retribution := K._move(&"retribution", MoveData.Kind.ABILITY, 4, 4, 16, K._hit(110, HitData.Weight.HEAVY))
	retribution.invuln_start = 1
	retribution.invuln_end = 10
	retribution.no_dash_cancel = true
	var wheel := K._move(&"wheel", MoveData.Kind.ABILITY, 5, 72, 14, K._hit(20, HitData.Weight.BASIC))
	wheel.skill_type = MoveData.SkillType.HOLD
	wheel.hitboxes[0].rehit_frames = 10
	wheel.hitboxes[0].offset = Vector3(0.0, 1.0, 0.0)
	wheel.hitboxes[0].radius = 2.0
	wheel.hold_start = 5
	wheel.hold_end = 76
	wheel.hold_steer_percent = 50
	var verdict := K._move(&"verdict", MoveData.Kind.ABILITY, 10, 4, 18, K._hit(120, HitData.Weight.HEAVY))
	verdict.skill_type = MoveData.SkillType.CHARGE
	verdict.aim = MoveData.Aim.GROUND_TARGET
	verdict.max_range = 7.0
	verdict.chargeable = true
	verdict.charge_frame = 2
	verdict.charge_max = 46
	verdict.charge_levels = PackedInt32Array([15, 35])
	verdict.charge_level_damage_percent = PackedInt32Array([100, 125])
	verdict.perfect_start = 35
	verdict.perfect_end = 45
	verdict.perfect_damage_percent = 158
	verdict.perfect_weight = HitData.Weight.MASSIVE
	verdict.perfect_stagger = 80
	verdict.early_release_move = &"smash"
	var pillar := EffectData.new()
	pillar.id = &"pillar"
	pillar.spawn_frame = 10
	pillar.anchor = EffectData.Anchor.TARGET
	pillar.offset = Vector3.ZERO
	pillar.radius = 1.0
	pillar.lifetime = 4
	pillar.hit = K._hit(20, HitData.Weight.LIGHT)
	pillar.requires_perfect = true
	verdict.effects = [pillar]
	var smash := K._move(&"smash", MoveData.Kind.ABILITY, 5, 3, 12, K._hit(70, HitData.Weight.MEDIUM))
	var leap := K._move(&"leap", MoveData.Kind.ABILITY, 10, 3, 12, K._hit(80, HitData.Weight.HEAVY))
	leap.aim = MoveData.Aim.GROUND_TARGET
	leap.max_range = 7.0
	leap.hitboxes[0].offset = Vector3.ZERO
	leap.hitboxes[0].radius = 2.0
	var arc := MotionData.new()
	arc.start_frame = 2
	arc.end_frame = 9
	arc.aim_travel = MotionData.AimTravel.ARRIVE
	leap.motions = [arc]
	data.moves = [jab, rise1, rise2, rend, ignite, bulwark, retribution, wheel, verdict, smash, leap]
	data.light = &"jab"
	data.abilities = [&"rise1", &"rend", &"bulwark", &"wheel", &"verdict", &"leap"]
	var oath := BuffData.new()
	oath.id = &"oathkeeper"
	oath.damage_bonus_percent = 25
	oath.uses = 2
	data.parry_buff = oath
	return data


func before_each() -> void:
	_duel(1.2)


func _duel(distance: float, cfg: SimConfig = null) -> void:
	sim = F.fighting_sim(cfg if cfg != null else F.config(2, _fighter()))
	F.place(sim, 0, 0.0, 0.0, 0)
	F.place(sim, 1, 0.0, distance, Fx.HALF_TURN)
	me = sim.fighter(0)
	foe = sim.fighter(1)


func _index(id: StringName) -> int:
	return sim.fighter_data[0].find_move(id)


func test_combo_part_two_on_re_press_and_cooldown_after_the_last_part() -> void:
	var ticks := F.play(sim, [RISE], [], 6)
	var ready := F.first(ticks, T.CHAIN_READY)
	assert_not_null(ready)
	assert_eq(ready.amount, 0)
	assert_eq(ready.id, &"rise2")
	assert_eq(me.skill_next[0], _index(&"rise2"))
	assert_eq(sim.skill_move(me, 0).id, &"rise2")
	assert_true(sim.skill_ready(me, 0))
	assert_eq(me.cooldowns[0], 0, "no cooldown during the sequence")
	ticks = F.play(sim, [RISE], [], 20)
	var started := false
	for events in ticks:
		for e: SimEvent in events:
			if e.type == T.MOVE_START and e.id == &"rise2":
				started = true
	assert_true(started, "part 2 cancels part 1 after its last active frame")
	assert_eq(me.cooldown_totals[0], 360)
	assert_true(me.cooldowns[0] > 300, "cooldown starts with the last part")
	assert_eq(me.skill_next[0], -1)
	assert_false(sim.skill_ready(me, 0))


func test_combo_window_expiry_and_whiff_start_the_cooldown() -> void:
	F.play(sim, [RISE], [], 6)
	assert_eq(me.skill_window[0], 30 - 3, "the window counts from the hit (tick 4 of 6)")
	F.hold(sim, 60)
	assert_eq(me.skill_next[0], -1)
	assert_true(me.cooldowns[0] > 0 and me.cooldowns[0] < 360)
	_duel(8.0)
	F.step(sim, RISE)
	assert_false(sim.skill_ready(me, 0), "waiting for the hit")
	F.step(sim, RISE)
	assert_eq(me.move_frame, 2, "the root cannot be recast while waiting")
	F.hold(sim, 30)
	assert_eq(me.cooldown_totals[0], 360)
	assert_true(me.cooldowns[0] > 0, "whiffed: the cooldown starts when the part is over")


func test_chain_after_an_effect_hit_detonates_marks_at_any_distance() -> void:
	_duel(3.0)
	var ticks := F.play(sim, [REND], [], 20)
	assert_ne(F.tick_of(ticks, T.HIT), -1)
	assert_true(foe.marks[0] > 0)
	assert_eq(sim.skill_move(me, 1).id, &"ignite")
	F.until_action(sim, foe, Action.IDLE)
	F.until_action(sim, me, Action.IDLE)
	F.place(sim, 1, 9.0, 8.0, Fx.HALF_TURN)
	ticks = F.play(sim, [REND], [], 6)
	var hit := F.first(ticks, T.HIT)
	assert_not_null(hit, "Ignition hits the marked foe 12 m away")
	assert_eq(hit.id, &"ignite")
	assert_eq(F.tick_of(ticks, T.HIT), 3)
	assert_eq(foe.action, Action.AIR_HITSTUN)
	assert_eq(foe.marks[0], 0)
	assert_eq(me.cooldown_totals[1], 480)
	ticks = F.play(sim, [], [], 3)
	assert_eq(F.count_of(ticks, T.HIT), 0)


func _verdict(held: int) -> Array[Array]:
	return F.play(sim, F.held(VERDICT, held), [], held + 30)


func test_charge_tap_fires_the_early_version() -> void:
	var ticks := _verdict(1)
	assert_eq(F.first(ticks, T.HIT).id, &"smash")
	assert_eq(me.cooldown_totals[4], 0, "the early version does not reset anything")


func test_charge_levels_and_auto_release() -> void:
	var ticks := _verdict(20)
	var hit := F.first(ticks, T.HIT)
	assert_eq(hit.id, &"verdict")
	assert_eq(hit.amount, 120, "L1")
	assert_eq(me.charge_level, 1)
	assert_eq(F.count_of(ticks, T.CHARGE_LEVEL), 1)
	_duel(1.2)
	ticks = _verdict(80)
	hit = F.first(ticks, T.HIT)
	assert_eq(hit.amount, 150, "held past the maximum: auto-release at L2, not perfect")
	assert_false(me.charge_perfect)
	assert_eq(hit.flags & SimEvent.FLAG_PERFECT, 0)


func test_perfect_release() -> void:
	var ticks := _verdict(40)
	assert_true(me.charge_perfect)
	assert_eq(me.charge_level, 2)
	var perfect_zone := false
	for events in ticks:
		for e: SimEvent in events:
			if e.type == T.CHARGE_LEVEL and e.flags & SimEvent.FLAG_PERFECT:
				perfect_zone = true
	assert_true(perfect_zone)
	var hit: SimEvent = null
	for events in ticks:
		for e: SimEvent in events:
			if e.type == T.HIT and e.id == &"verdict" and hit == null:
				hit = e
	assert_eq(hit.amount, 120 * 158 / 100)
	assert_eq(hit.weight, HitData.Weight.MASSIVE)
	assert_eq(hit.hitstop, 10)
	assert_true(hit.flags & SimEvent.FLAG_PERFECT != 0)
	var pillar := false
	for events in ticks:
		for e: SimEvent in events:
			if e.type == T.EFFECT_SPAWN and e.id == &"pillar":
				pillar = true
	assert_true(pillar, "perfect-only effect spawns")


func test_charge_reaims_ground_target_on_release() -> void:
	_duel(8.0)
	F.play(sim, [SimInput.with_aim_point(VERDICT, Vector2(0.0, 3.0))] + F.held(VERDICT, 18), [], 19)
	F.step(sim, SimInput.with_aim_point(0, Vector2(4.0, 0.0)))
	assert_eq(me.move_point, Vector3i(40000, 0, 0))
	assert_eq(me.facing, 1024)


func test_hold_channels_rehits_and_releases_into_the_tail() -> void:
	var ticks := F.play(sim, F.held(WHEEL, 50), [], 50)
	assert_eq(F.count_of(ticks, T.HIT), 4, "frames 5, 15, 25, 35 (3 f hitstop each)")
	F.step(sim)
	assert_eq(me.move_frame, 77, "released: straight to the tail")
	_duel(8.0)
	F.play(sim, F.held(WHEEL, 200), [], 200)
	assert_eq(me.action, Action.IDLE, "held to the maximum, then the tail")
	_duel(8.0)
	F.play(sim, F.held(SimInput.make(WHEEL, 127, 0), 30), [], 30)
	assert_true(me.pos.x > 0, "steerable")
	assert_eq(me.action, Action.ATTACK)


func test_stance_absorbs_a_frontal_hit_and_counters() -> void:
	var ticks := F.play(sim, [BULWARK], [0, F.L], 8)
	var trigger := F.first(ticks, T.STANCE_TRIGGER)
	assert_not_null(trigger)
	assert_eq(trigger.target, 1)
	assert_eq(me.hp, me.max_hp)
	assert_eq(sim.current_move(me).id, &"retribution")
	assert_eq(me.soul, 1000)
	assert_eq(me.buffs.size(), 1, "Oathkeeper")
	assert_eq(F.count_of(ticks, T.HIT), 0)
	ticks = F.play(sim, [], [], 10)
	assert_eq(F.first(ticks, T.HIT).source, 0, "Retribution lands")


func test_stance_destroys_projectiles_but_not_hits_from_behind() -> void:
	_duel(4.0)
	var ticks := F.play(sim, [BULWARK], [REND], 30)
	assert_not_null(F.first(ticks, T.STANCE_TRIGGER))
	assert_ne(F.tick_of(ticks, T.EFFECT_DESTROYED), -1)
	_duel(1.2)
	F.place(sim, 1, 0.0, -1.2, 0)
	ticks = F.play(sim, [SimInput.with_aim_point(BULWARK, Vector2(0.0, 3.0))], [0, F.L], 8)
	assert_eq(F.first(ticks, T.STANCE_TRIGGER), null)
	assert_ne(F.tick_of(ticks, T.HIT), -1)


func test_move_speed_percent_scales_frames() -> void:
	for percent: int in [200, 50]:
		var cfg := F.config(2, _fighter())
		cfg.move_speed_percent = percent
		_duel(1.2, cfg)
		var startup := sim.fighter_data[0].move_by_id(&"rise1").startup
		assert_eq(startup, MoveSpeed.at(4, percent))
		var ticks := F.play(sim, [RISE], [], 12)
		assert_eq(F.tick_of(ticks, T.HIT), startup, "%d%%" % percent)
	assert_eq(cfg_fighter_startup(), 4, "the content itself is not modified")
	assert_eq(MoveSpeed.at(4, 200), 3)
	assert_eq(MoveSpeed.at(4, 50), 7)


func cfg_fighter_startup() -> int:
	var data := _fighter()
	var cfg := F.config(2, data)
	cfg.move_speed_percent = 150
	Sim.new(cfg)
	return data.move_by_id(&"rise1").startup


func test_telegraphs_cover_hitboxes_effects_and_leaps() -> void:
	_duel(8.0)
	F.step(sim, RISE)
	var list := sim.telegraphs()
	assert_eq(list.size(), 1)
	var t := list[0]
	assert_eq(t.owner, 0)
	assert_eq(t.move_id, &"rise1")
	assert_eq(t.shape, SimTelegraph.Shape.CIRCLE)
	assert_eq(t.frames_to_active, 3)
	assert_eq(t.frames_active_left, 4)
	assert_eq(t.wind_up, 4)
	assert_false(t.effect)
	_duel(8.0)
	F.step(sim, REND)
	list = sim.telegraphs()
	assert_eq(list.size(), 1)
	assert_eq(list[0].shape, SimTelegraph.Shape.LINE)
	assert_eq(list[0].frames_to_active, 5)
	assert_eq(Fx.dist_xz(list[0].from, list[0].to), 90000)
	F.hold(sim, 6)
	list = sim.telegraphs()
	assert_eq(list.size(), 1)
	assert_true(list[0].effect)
	assert_eq(list[0].frames_to_active, 0, "live projectile")
	_duel(8.0)
	F.step(sim, SimInput.with_aim_point(LEAP, Vector2(0.0, 5.0)))
	list = sim.telegraphs()
	assert_eq(list[0].from, Vector3i(0, 0, 50000), "the landing spot, not where the leap starts")


func test_skill_kit_fights_are_deterministic_through_rollback() -> void:
	var cfg := F.config(3, _fighter())
	cfg.slots[2].stagger_max = 200
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var buttons: Array[int] = [SimInput.BASIC, SimInput.DASH, SimInput.AWAKEN]
	buttons.append_array(SimInput.SKILLS)
	var frames: Array[PackedInt64Array] = []
	var held := PackedInt64Array([0, 0, 0])
	for _t in 900:
		for s in 3:
			if rng.randi() % 5 == 0:
				var frame := SimInput.make(buttons[rng.randi() % buttons.size()] if rng.randi() % 3 > 0 else 0,
						rng.randi_range(-127, 127), rng.randi_range(-127, 127))
				held[s] = SimInput.with_aim_point(frame, Vector2(rng.randf_range(-8.0, 8.0), rng.randf_range(-8.0, 8.0)))
		frames.append(held.duplicate())
	var a := Sim.new(cfg)
	var sums := PackedInt64Array()
	for t in 900:
		a.step(frames[t])
		sums.append(a.checksum())
	var b := Sim.new(cfg)
	for t in 450:
		b.step(frames[t])
	var snap := b.snapshot()
	for t in range(450, 600):
		b.step(frames[t])
	b.restore(snap)
	for t in range(450, 900):
		b.step(frames[t])
		assert_eq(b.checksum(), sums[t], "tick %d" % t)
		if b.checksum() != sums[t]:
			return
	var moves := 0
	for s in 3:
		moves += a.fighter(s).max_hp - a.fighter(s).hp
	assert_true(moves > 0, "the fight did something")

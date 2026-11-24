extends TestCase
## Aldric's skill kit (design-lost-ark §4) in the sim, from his real data: basics, the six
## skills, Oathkeeper and the awakening.

const F := preload("res://tests/sim/sim_fixtures.gd")
const Action := FighterState.Action
const T := SimEvent.Type
const ALDRIC := "res://content/fighters/aldric/aldric.tres"
const HOLLOWED := "res://content/fighters/hollowed/hollowed.tres"
const B := SimInput.BASIC
const LUNGE := SimInput.SKILL_1
const RISE := SimInput.SKILL_2
const REND := SimInput.SKILL_3
const BULWARK := SimInput.SKILL_4
const WHEEL := SimInput.SKILL_5
const VERDICT := SimInput.SKILL_6

var sim: Sim
var me: FighterState
var foe: FighterState


func _duel(distance: float, theirs: String = ALDRIC) -> void:
	var cfg := F.config(2, load(ALDRIC))
	cfg.slots[1].fighter = load(theirs)
	sim = F.fighting_sim(cfg)
	F.place(sim, 0, 0.0, 0.0, 0)
	F.place(sim, 1, 0.0, distance, Fx.HALF_TURN)
	me = sim.fighter(0)
	foe = sim.fighter(1)


func _hits_by(ticks: Array[Array], move_id: StringName, source: int = 0) -> Array[SimEvent]:
	var found: Array[SimEvent] = []
	for events in ticks:
		for e: SimEvent in events:
			if e.type == T.HIT and e.id == move_id and e.source == source:
				found.append(e)
	return found


func _started(ticks: Array[Array], move_id: StringName) -> bool:
	for events in ticks:
		for e: SimEvent in events:
			if e.type == T.MOVE_START and e.id == move_id and e.source == 0:
				return true
	return false


func test_stats_and_slots() -> void:
	var data: FighterData = load(ALDRIC)
	assert_eq(data.max_hp, 1500)
	assert_eq(data.jumps, 0)
	assert_not_null(data.dash, "skill-kit fighter")
	assert_eq(data.abilities.size(), 6)
	for move in data.moves:
		assert_ne(move.aim, MoveData.Aim.AUTO, "%s is aimed" % move.id)


func test_basics_chain_three_hits_while_held() -> void:
	_duel(1.4, HOLLOWED)
	var ticks := F.play(sim, F.held(B, 70), [], 70)
	assert_eq(_hits_by(ticks, &"aldric_b1").size() >= 1, true)
	assert_eq(_hits_by(ticks, &"aldric_b2").size() >= 1, true)
	assert_eq(_hits_by(ticks, &"aldric_b3").size() >= 1, true)
	assert_eq(_hits_by(ticks, &"aldric_b1")[0].weight, HitData.Weight.BASIC)


func test_a_skill_cancels_a_basic_on_its_startup() -> void:
	_duel(1.4, HOLLOWED)
	var ticks := F.play(sim, [B, RISE], [], 12)
	assert_true(_started(ticks, &"brand_rise"), "Brand Rise cancels the basic on frame 2")
	assert_eq(_hits_by(ticks, &"aldric_b1").size(), 0)


func test_lunge_dashes_to_the_aim_and_is_flinch_immune() -> void:
	_duel(5.5, HOLLOWED)
	var aim := SimInput.with_aim_point(LUNGE, Vector2(0.0, 5.5))
	# The Hollowed's fast light lands during the lunge's flinch-immune frames.
	F.place(sim, 1, 0.0, 2.2, Fx.HALF_TURN)
	var ticks := F.play(sim, [aim], [0, F.L], 30)
	var hit := _hits_by(ticks, &"aldric_b1", 1)
	assert_eq(_hits_by(ticks, &"oathfire_lunge").size(), 1, "the lunge connects")
	assert_eq(hit.size(), 0)
	assert_eq(me.action == Action.ATTACK or me.action == Action.IDLE, true, "not interrupted")


func test_lunge_counters_a_cinder_wheel_wind_up() -> void:
	_duel(3.0)
	var ticks := F.play(sim, F.held(0, 2) + [LUNGE], F.held(WHEEL, 20), 20)
	assert_not_null(F.first(ticks, T.COUNTER_STUN), "⚡Counter inside Cinder Wheel's window")
	assert_eq(foe.action, Action.COUNTER_STUN)
	assert_false(me.buffs.is_empty(), "the counter ignites Oathkeeper")


func test_brand_rise_launches_and_the_slam_follows() -> void:
	_duel(1.5)
	var ticks := F.play(sim, [RISE] + F.held(0, 8) + [RISE], [], 40)
	assert_eq(_hits_by(ticks, &"brand_rise").size(), 1)
	assert_not_null(F.first(ticks, T.LAUNCH))
	var slam := _hits_by(ticks, &"brand_rise_slam")
	assert_eq(slam.size(), 1, "part 2 hits the launched foe")
	assert_eq(slam[0].weight, HitData.Weight.HEAVY)
	assert_true(me.cooldowns[1] > 0, "cooldown after the last part")


func test_flame_rend_brands_and_ignition_launches_from_anywhere() -> void:
	_duel(6.0)
	var ticks := F.play(sim, [REND], [], 20)
	assert_eq(_hits_by(ticks, &"flame_rend").size(), 1, "the wave reaches 6 m")
	assert_true(foe.marks[0] > 0, "branded")
	assert_eq(sim.skill_move(me, 2).id, &"rend_ignition")
	F.until_action(sim, me, Action.IDLE)
	ticks = F.play(sim, [REND], [], 8)
	assert_eq(_hits_by(ticks, &"rend_ignition").size(), 1)
	assert_eq(foe.action, Action.AIR_HITSTUN)


func test_bulwark_absorbs_a_frontal_hit_into_retribution_and_ignites() -> void:
	_duel(1.4)
	var ticks := F.play(sim, [BULWARK], F.held(0, 3) + [B], 30)
	var trigger := F.first(ticks, T.STANCE_TRIGGER)
	assert_not_null(trigger)
	if trigger != null:
		assert_eq(trigger.hitstop, 6, "two frames over the stance default")
	assert_eq(me.hp, me.max_hp)
	assert_eq(_hits_by(ticks, &"retribution").size(), 1)
	assert_eq(foe.action == Action.KNOCKDOWN or foe.action == Action.HITSTUN or foe.action == Action.AIR_HITSTUN, true)
	assert_eq(me.buffs.size(), 1, "Oathkeeper ignites the blade")
	assert_eq(me.buffs[0].uses_left, 2, "Retribution does not spend the ignite")


func test_ignited_blade_adds_a_quarter_to_two_skills() -> void:
	_duel(1.4, HOLLOWED)
	var data: FighterData = load(ALDRIC)
	sim.apply_buff(me, data.parry_buff, -1)
	var ticks := F.play(sim, [RISE], [], 20)
	assert_eq(_hits_by(ticks, &"brand_rise")[0].amount, 70 * 125 / 100)
	assert_eq(me.buffs.size(), 1, "one use left")


func test_bulwark_whiff_cannot_be_skill_cancelled() -> void:
	_duel(6.0)
	var ticks := F.play(sim, [BULWARK] + F.held(0, 38) + [LUNGE], [], 45)
	assert_false(_started(ticks, &"oathfire_lunge"))


func test_cinder_wheel_ticks_while_held_and_ends_on_release() -> void:
	_duel(1.6, HOLLOWED)
	var ticks := F.play(sim, F.held(WHEEL, 40), [], 40)
	assert_true(_hits_by(ticks, &"cinder_wheel").size() >= 3)
	for i in 6:
		F.step(sim)
	assert_true(me.move_frame > 76, "released into the tail (after any hitstop)")


func test_verdict_perfect_release_is_massive() -> void:
	_duel(5.0, HOLLOWED)
	var aim := SimInput.with_aim_point(VERDICT, Vector2(0.0, 5.0))
	var ticks := F.play(sim, F.held(aim, 40), [], 80)
	var hit := _hits_by(ticks, &"verdict")
	assert_eq(hit.size(), 4, "leaps to the aim point and lands, then three eruptions")
	assert_true(me.charge_perfect)
	assert_eq(hit[0].weight, HitData.Weight.MASSIVE)
	assert_eq(hit[0].amount, 120 * 158 / 100)
	assert_true(hit[1].flags & SimEvent.FLAG_PROJECTILE != 0, "the eruptions are the perfect-only effect")


func test_verdict_tap_is_the_small_smash() -> void:
	_duel(1.4, HOLLOWED)
	var ticks := F.play(sim, [VERDICT], [], 30)
	assert_eq(_hits_by(ticks, &"verdict_smash").size(), 1)


func test_awakening_deals_its_damage_to_one_target() -> void:
	_duel(4.0, HOLLOWED)
	me.soul = 10000
	var aim := SimInput.with_aim_point(SimInput.AWAKEN, Vector2(0.0, 4.0))
	var ticks := F.play(sim, [aim], [], 220)
	assert_not_null(F.first(ticks, T.SUPER_FLASH))
	var total := 0
	var massive := false
	for events in ticks:
		for e: SimEvent in events:
			if e.type == T.HIT and e.source == 0 and e.id == &"pyre_of_the_forsworn":
				total += e.amount
				massive = massive or e.weight == HitData.Weight.MASSIVE
	assert_true(total >= 240, "pillar, wave and sword land (%d)" % total)
	assert_true(massive, "the falling sword is MASSIVE")


func test_dash_has_two_charges() -> void:
	_duel(8.0)
	var ticks := F.play(sim, [SimInput.DASH] + F.held(0, 19) + [SimInput.DASH] + F.held(0, 19) + [SimInput.DASH], [], 42)
	assert_eq(F.count_of(ticks, T.DASH), 2)

## While Aldric holds (or mashes) BASIC at a foe that never acts: the most damage the foe
## takes without a free frame, and the fewest free frames between the shield thrust (b3)
## landing and the next hit.
func _basic_pressure(foe_z: float, mash: bool, victim: String) -> Vector2i:
	var cfg := F.config(2, load(ALDRIC))
	cfg.slots[1].fighter = load(victim)
	sim = F.fighting_sim(cfg)
	F.place(sim, 0, 0.0, foe_z - 1.3, 0)
	F.place(sim, 1, 0.0, foe_z, Fx.HALF_TURN)
	me = sim.fighter(0)
	foe = sim.fighter(1)
	var worst := 0
	var combo := 0
	var after_b3 := -1
	var shortest := 999
	var hp := foe.hp
	for t in 400:
		var events := F.step(sim, (B if t % 4 < 2 else 0) if mash else B)
		if foe.ko:
			break
		for e: SimEvent in events:
			if e.type == T.HIT and e.source == 0:
				if after_b3 >= 0:
					shortest = mini(shortest, after_b3)
				after_b3 = 0 if e.id == &"aldric_b3" else -1
		var stunned := foe.action in [Action.HITSTUN, Action.AIR_HITSTUN, Action.COUNTER_STUN, Action.KNOCKDOWN]
		combo += hp - foe.hp
		hp = foe.hp
		worst = maxi(worst, combo)
		if not stunned:
			combo = 0
			if after_b3 >= 0:
				after_b3 += 1
	return Vector2i(worst, shortest)


func test_held_or_mashed_basics_are_not_an_infinite() -> void:
	var one_chain := 25 + 25 + 40
	for victim: String in [HOLLOWED, ALDRIC]:
		for foe_z: float in [0.0, 9.4]:
			for mash: bool in [false, true]:
				var result := _basic_pressure(foe_z, mash, victim)
				var label := "%s at z %.1f, %s" % [victim.get_file().get_basename(), foe_z, "mashed" if mash else "held"]
				assert_true(result.x <= one_chain, "%s: at most one chain without a free frame (%d)" % [label, result.x])
				assert_true(result.y >= 8, "%s: free for 8+ frames after the shield thrust (%d)" % [label, result.y])

extends TestCase
## Per-skill charges (MoveData.charges / recharge_frames).

const F := preload("res://tests/sim/sim_fixtures.gd")
const K := preload("res://tests/sim/test_skill_kit.gd")
const Action := FighterState.Action
const T := SimEvent.Type
const QUICK := SimInput.SKILL_3
const SLOT := 2

var sim: Sim
var me: FighterState


func before_each() -> void:
	var data := K.kit()
	data.moves[5].charges = 2
	data.moves[5].recharge_frames = 100
	sim = F.duel(8.0, 2, data)
	me = sim.fighter(0)


func _cast() -> bool:
	F.step(sim, QUICK)
	var started := me.action == Action.ATTACK
	F.until_action(sim, me, Action.IDLE)
	return started


func test_two_casts_back_to_back_then_one_charge_at_a_time() -> void:
	assert_eq(sim.skill_max_charges(me, SLOT), 2)
	assert_eq(me.skill_charges[SLOT], 2)
	assert_true(_cast())
	assert_eq(me.skill_charges[SLOT], 1)
	assert_true(sim.skill_ready(me, SLOT), "a charge is left while the first recharges")
	var elapsed := 100 - me.cooldowns[SLOT]
	assert_true(_cast(), "second charge")
	assert_eq(me.skill_charges[SLOT], 0)
	assert_eq(100 - me.cooldowns[SLOT] > elapsed, true, "the running recharge was not restarted")
	assert_false(sim.skill_ready(me, SLOT))
	assert_false(_cast(), "no charges left")
	var ticks := F.play(sim, [], [], me.cooldowns[SLOT])
	assert_eq(F.tick_of(ticks, T.COOLDOWN_READY), ticks.size(), "on the last tick")
	assert_eq(me.skill_charges[SLOT], 1)
	assert_eq(me.cooldowns[SLOT], 100, "the next charge starts recharging")
	assert_eq(me.cooldown_totals[SLOT], 100)
	F.hold(sim, 100)
	assert_eq(me.skill_charges[SLOT], 2)
	assert_eq(me.cooldowns[SLOT], 0, "full: no recharge running")


func test_skills_without_charges_keep_the_plain_cooldown() -> void:
	assert_eq(sim.skill_max_charges(me, 0), 0)
	assert_eq(me.skill_charges[0], 0)
	F.step(sim, SimInput.SKILL_1)
	assert_eq(me.cooldowns[0], 300 - 1)
	assert_false(sim.skill_ready(me, 0))

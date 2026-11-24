extends TestCase
## Gorrath's kit in the sim: Unbroken heavy armour, Chain Hook's pull advantage,
## Earthsplitter, Bull Rush, and Execution Chain as an unblockable, untechable command grab
## that beats attacks.

const F := preload("res://tests/sim/sim_fixtures.gd")
const Action := FighterState.Action
const T := SimEvent.Type
const GORRATH := "res://content/fighters/gorrath/gorrath.tres"

var sim: Sim
var me: FighterState
var foe: FighterState


func _duel(distance: float) -> void:
	var gorrath: FighterData = load(GORRATH)
	sim = F.fighting_sim(F.config(2, gorrath))
	F.place(sim, 0, 0.0, 0.0, 0)
	F.place(sim, 1, 0.0, distance, Fx.HALF_TURN)
	me = sim.fighter(0)
	foe = sim.fighter(1)


func _hits_by(ticks: Array[Array], move_id: StringName) -> Array[SimEvent]:
	var found: Array[SimEvent] = []
	for events in ticks:
		for e: SimEvent in events:
			if e.type == T.HIT and e.id == move_id:
				found.append(e)
	return found


func test_unbroken_heavy_absorbs_a_light_and_still_hits() -> void:
	_duel(1.6)
	var ticks := F.play(sim, [F.H], F.held(0, 2) + [F.L], 40)
	var armor := F.first(ticks, T.ARMOR)
	assert_not_null(armor, "the light lands on Unbroken armour")
	assert_eq(armor.target, 0)
	assert_eq(me.max_hp - me.hp, 45 * 50 / 100, "armour halves the damage")
	assert_eq(_hits_by(ticks, &"gorrath_h1").size(), 1, "the heavy goes through")


func test_unbroken_absorbs_only_one_hit() -> void:
	_duel(1.6)
	var ticks := F.play(sim, [F.H], F.held(0, 1) + [F.L] + F.held(0, 8) + [F.L], 40)
	assert_eq(F.count_of(ticks, T.ARMOR), 1)
	assert_eq(_hits_by(ticks, &"gorrath_h1").size(), 0, "the second light interrupts the heavy")


func test_chain_hook_pulls_the_target_in_at_plus_fourteen() -> void:
	_duel(7.0)
	var ticks := F.play(sim, [SimInput.ABILITY_1], [], 20)
	assert_eq(_hits_by(ticks, &"chain_hook").size(), 1, "the chain reaches 7 m")
	var me_free := -1
	var foe_free := -1
	for t in 80:
		if me_free < 0 and me.action == Action.IDLE:
			me_free = t
		if foe_free < 0 and foe.action == Action.IDLE:
			foe_free = t
		if me_free >= 0 and foe_free >= 0:
			break
		F.step(sim)
	assert_eq(foe_free - me_free, 14, "Gorrath recovers 14 frames before the target")
	assert_true(Fx.dist_xz(me.pos, foe.pos) < Fx.m(2.0), "the target was pulled point-blank")


func test_earthsplitter_wave_bounces_a_foe_four_meters_away() -> void:
	_duel(4.0)
	var ticks := F.play(sim, [SimInput.ABILITY_2], [], 50)
	assert_eq(_hits_by(ticks, &"earthsplitter").size(), 1)
	assert_true(not foe.grounded or foe.action != Action.IDLE)


func test_bull_rush_armors_two_hits_and_carries() -> void:
	_duel(3.0)
	var ticks := F.play(sim, [SimInput.ABILITY_3], [], 50)
	assert_eq(_hits_by(ticks, &"bull_rush").size(), 1)
	var moved := Fx.to_vec3(foe.pos).z
	assert_true(moved > 4.0, "the foe was carried (z = %.2f)" % moved)


func test_execution_chain_ignores_guard() -> void:
	_duel(1.5)
	me.soul = 10000
	var ticks := F.play(sim, F.held(0, 3) + [SimInput.SUPER], F.held(F.G, 140), 140)
	assert_not_null(F.first(ticks, T.GRAB), "the guard does not stop it")
	assert_eq(F.count_of(ticks, T.BLOCK), 0)
	assert_eq(_hits_by(ticks, &"execution_chain_slams").size(), 3, "three slams")
	assert_true(foe.hp < foe.max_hp - 250)


func test_execution_chain_beats_an_attack_in_startup() -> void:
	_duel(1.5)
	me.soul = 10000
	var ticks := F.play(sim, F.held(0, 3) + [SimInput.SUPER], [F.H], 40)
	var grab := F.first(ticks, T.GRAB)
	assert_not_null(grab, "grabs the foe out of their heavy")
	assert_eq(grab.id, &"execution_chain")


func test_a_normal_grab_loses_to_the_same_attack() -> void:
	_duel(1.5)
	var ticks := F.play(sim, F.held(0, 3) + [F.T], [F.H], 40)
	assert_null(F.first(ticks, T.GRAB))


func test_execution_chain_cannot_be_teched() -> void:
	_duel(1.5)
	me.soul = 10000
	var mash: Array = []
	for i in 120:
		mash.append(F.T if i % 2 == 0 else 0)
	var ticks := F.play(sim, F.held(0, 3) + [SimInput.SUPER], mash, 120)
	assert_not_null(F.first(ticks, T.GRAB))
	assert_null(F.first(ticks, T.GRAB_TECH))

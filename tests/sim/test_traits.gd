extends TestCase
## FighterTrait hooks: stored charges in FighterState.vars change later moves, and survive
## snapshot/restore.

const F := preload("res://tests/sim/sim_fixtures.gd")
const T := SimEvent.Type


func test_stored_souls_turn_the_next_bolt_into_a_spread() -> void:
	var data := F.test_fighter().duplicate()
	data.trait_script = load("res://tests/sim/fixtures/stored_souls_trait.gd")
	var sim := F.duel(1.2, 2, data)
	var me := sim.fighter(0)
	F.play(sim, [SimInput.ABILITY_2], [], 8)
	assert_eq(me.vars[0], 1, "ability hit stored a soul")
	var snap := sim.snapshot()
	F.until_action(sim, me, FighterState.Action.IDLE, 120)
	var ticks := F.play(sim, [SimInput.ABILITY_3], [], 20)
	assert_eq(F.count_of(ticks, T.EFFECT_SPAWN), 2, "bolt plus one stored soul")
	assert_eq(me.vars[0], 0, "souls spent")
	sim.restore(snap)
	assert_eq(me.vars[0], 1, "trait storage is part of the snapshot")

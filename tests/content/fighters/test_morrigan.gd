extends TestCase
## Morrigan's kit in the sim: Soul Lance at range, Grave Grasp's rune locked where the
## target stood, Lantern of Souls storing ability hits and firing them as shards,
## Wraithstep, Requiem of the Drowned.

const F := preload("res://tests/sim/sim_fixtures.gd")
const Action := FighterState.Action
const T := SimEvent.Type
const MORRIGAN := "res://content/fighters/morrigan/morrigan.tres"
const SOULS := 0

var sim: Sim
var me: FighterState
var foe: FighterState


func _duel(distance: float) -> void:
	var morrigan: FighterData = load(MORRIGAN)
	sim = F.fighting_sim(F.config(2, morrigan))
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


func _spawns_of(ticks: Array[Array], effect_id: StringName) -> int:
	var n := 0
	for events in ticks:
		for e: SimEvent in events:
			if e.type == T.EFFECT_SPAWN and e.id == effect_id:
				n += 1
	return n


func test_soul_lance_hits_across_the_arena() -> void:
	_duel(9.0)
	var ticks := F.play(sim, [SimInput.ABILITY_1], [], 60)
	assert_eq(_spawns_of(ticks, &"soul_lance_bolt"), 1)
	assert_eq(_hits_by(ticks, &"soul_lance").size(), 1, "the bolt reaches 9 m")
	assert_eq(foe.max_hp - foe.hp, 60)


func test_grave_grasp_erupts_under_a_standing_target_and_launches() -> void:
	_duel(6.0)
	var ticks := F.play(sim, [SimInput.ABILITY_2], [], 60)
	assert_eq(_hits_by(ticks, &"grave_grasp").size(), 1)
	var launch := F.first(ticks, T.LAUNCH)
	assert_not_null(launch)
	assert_eq(launch.target, 1)


func test_grave_grasp_stays_where_the_target_stood() -> void:
	_duel(6.0)
	# The rune is placed on cast (tick 15); the foe then walks sideways out of it before
	# it erupts 30 frames later.
	var walk := SimInput.make(0, 127, 0)
	var ticks := F.play(sim, [SimInput.ABILITY_2], F.held(0, 15) + F.held(walk, 45), 60)
	assert_eq(_spawns_of(ticks, &"grave_grasp_hands"), 1, "the rune was placed")
	assert_true(absf(Fx.to_vec3(foe.pos).x) > 2.0, "the foe walked away")
	assert_eq(_hits_by(ticks, &"grave_grasp").size(), 0, "the rune did not follow")
	assert_eq(foe.hp, foe.max_hp)


func test_lantern_stores_a_soul_per_ability_hit() -> void:
	_duel(6.0)
	F.play(sim, [SimInput.ABILITY_2], [], 60)
	assert_eq(me.vars[SOULS], 1, "Grave Grasp stored a soul")


func test_lantern_ignores_blocked_and_normal_hits() -> void:
	_duel(6.0)
	F.play(sim, [SimInput.ABILITY_1], F.held(F.G, 60), 60)
	assert_eq(me.vars[SOULS], 0, "a blocked Soul Lance stores nothing")
	_duel(1.4)
	F.play(sim, [F.L], [], 30)
	assert_true(foe.hp < foe.max_hp)
	assert_eq(me.vars[SOULS], 0, "a staff hit stores nothing")


func test_lantern_holds_at_most_three_souls() -> void:
	_duel(6.0)
	me.vars[SOULS] = 3
	F.play(sim, [SimInput.ABILITY_2], [], 60)
	assert_eq(me.vars[SOULS], 3)


func test_soul_lance_fires_stored_souls_as_shards() -> void:
	_duel(9.0)
	me.vars[SOULS] = 3
	var ticks := F.play(sim, [SimInput.ABILITY_1], [], 60)
	assert_eq(_spawns_of(ticks, &"soul_lance_bolt"), 1)
	assert_eq(_spawns_of(ticks, &"soul_lance_shard"), 3, "one shard per stored soul")
	assert_eq(me.vars[SOULS], 1, "the lantern emptied; the bolt's hit stored one soul")


func test_shard_hits_do_not_refill_the_lantern() -> void:
	_duel(2.5)
	me.vars[SOULS] = 1
	var ticks := F.play(sim, [SimInput.ABILITY_1], [], 40)
	var lance_hits := _hits_by(ticks, &"soul_lance").size()
	assert_eq(lance_hits, 2, "bolt and shard both connect point-blank")
	assert_eq(me.vars[SOULS], 1, "only the bolt stored a soul")


func test_lantern_is_empty_each_round() -> void:
	_duel(6.0)
	me.vars[SOULS] = 2
	sim.traits[0].on_round_start(sim, me)
	assert_eq(me.vars[SOULS], 0)


func test_wraithstep_blinks_five_meters_along_the_stick() -> void:
	_duel(6.0)
	var right := SimInput.make(0, 127, 0)
	var ticks := F.play(sim, [SimInput.make(SimInput.ABILITY_3, 127, 0)] + F.held(right, 3), [], 4)
	assert_ne(F.tick_of(ticks, T.TELEPORT), -1)
	var p := Fx.to_vec3(me.pos)
	assert_true(absf(absf(p.x) - 5.0) < 0.3 and absf(p.z) < 0.3, "moved 5 m sideways (%s)" % p)


func test_wraithstep_is_invincible() -> void:
	_duel(1.4)
	var ticks := F.play(sim, F.held(0, 4) + [SimInput.make(SimInput.ABILITY_3, 127, 0)], [F.L], 20)
	assert_eq(me.hp, me.max_hp, "the light passes through the blink")
	assert_null(F.first(ticks, T.HIT))


func test_requiem_launches_everyone_around_her() -> void:
	_duel(5.0)
	me.soul = 10000
	var ticks := F.play(sim, [SimInput.SUPER], [], 70)
	assert_eq(_hits_by(ticks, &"requiem_of_the_drowned").size(), 1)
	assert_not_null(F.first(ticks, T.LAUNCH))
	assert_true(me.soul_points() < 50, "the super spent 100 Soul")

extends TestCase
## Abilities and resources: cooldowns, cancels, armor, charge, grabs and techs, projectiles,
## eruptions, blinks, pulls, command grabs, buffs, Soul, supers, perfect dodge.

const F := preload("res://tests/sim/sim_fixtures.gd")
const Action := FighterState.Action
const T := SimEvent.Type
const A1 := SimInput.ABILITY_1
const A2 := SimInput.ABILITY_2
const A3 := SimInput.ABILITY_3

var sim: Sim
var me: FighterState
var foe: FighterState


func before_each() -> void:
	_duel(1.2)


func _duel(distance: float, data: FighterData = null) -> void:
	sim = F.duel(distance, 2, data)
	me = sim.fighter(0)
	foe = sim.fighter(1)


func _start(slot: int, move_id: StringName) -> void:
	sim.start_move(sim.fighter(slot), sim.fighter_data[slot].find_move(move_id))


func test_ability_cooldown_blocks_reuse_until_ready() -> void:
	_duel(5.0)
	F.play(sim, [A3])
	assert_eq(me.cooldowns[2], 150 - 1)
	F.until_action(sim, me, Action.IDLE)
	var ticks := F.play(sim, [A3], [], 1)
	assert_eq(F.count_of(ticks, T.MOVE_START), 0, "on cooldown")
	ticks = F.play(sim, [], [], 150)
	var ready := F.first(ticks, T.COOLDOWN_READY)
	assert_not_null(ready)
	assert_eq(ready.amount, 2)
	ticks = F.play(sim, [A3], [], 1)
	assert_eq(F.count_of(ticks, T.MOVE_START), 1)


func test_soul_gain_from_damage_dealt_and_taken() -> void:
	F.play(sim, [F.L], [], 6)
	assert_eq(me.soul, 35 * 8 * 3 / 2, "basics earn 1.5x Soul")
	assert_eq(foe.soul, 35 * 6)


func test_ability_cancels_a_light_on_hit() -> void:
	var ticks := F.play(sim, [F.L, 0, 0, 0, 0, 0, 0, A2], [], 12)
	var starts := 0
	for events in ticks:
		for e: SimEvent in events:
			if e.type == T.MOVE_START and e.id == &"rising_slash":
				starts += 1
	assert_eq(starts, 1, "rising slash cancels the light after contact")


func test_skill_cancels_a_whiffed_light_on_any_frame() -> void:
	_duel(4.0)
	var ticks := F.play(sim, [F.L, A2], [], 12)
	assert_eq(F.count_of(ticks, T.MOVE_START), 2)
	assert_eq(F.first(ticks.slice(1), T.MOVE_START).id, &"rising_slash", "cancels the light's startup")


func test_jump_cancel_on_hit() -> void:
	F.play(sim, [A2], [], 8)
	F.hold(sim, 8)
	F.step(sim, F.J)
	assert_true(me.action == Action.JUMP_SQUAT or me.action == Action.AIR, "jump cancels rising slash on hit")


func test_super_cancels_an_ability_on_hit() -> void:
	me.soul = 10000
	var ticks := F.play(sim, [A2] + F.held(0, 8) + [SimInput.SUPER], [], 25)
	assert_ne(F.tick_of(ticks, T.SUPER_FLASH), -1)


func test_armor_absorbs_one_hit_and_keeps_attacking() -> void:
	_duel(3.0)
	var ticks := F.play(sim, [A1], [F.L], 30)
	var armor := F.first(ticks, T.ARMOR)
	assert_not_null(armor, "dash armored the light")
	assert_eq(me.hp, me.max_hp - 35)
	var hit := F.first(ticks, T.HIT)
	assert_not_null(hit)
	assert_eq(hit.source, 0, "dash still hits")


func test_charged_heavy_full_charge_deals_150_percent_and_breaks_guard() -> void:
	var ticks := F.play(sim, F.held(F.H, 60), [], 70)
	var hit := F.first(ticks, T.HIT)
	assert_eq(hit.amount, 150)
	assert_true(hit.flags & SimEvent.FLAG_FULL_CHARGE)
	assert_eq(F.tick_of(ticks, T.HIT), 18 + 40)
	_duel(1.2)
	F.play(sim, [], F.held(F.G, 8))
	ticks = F.play(sim, F.held(F.H, 60), F.held(F.G, 70), 70)
	assert_ne(F.tick_of(ticks, T.GUARD_BREAK), -1)


func test_grab_beats_guard_and_throws_after_the_tech_window() -> void:
	F.play(sim, [], F.held(F.G, 8))
	var ticks := F.play(sim, [F.T], F.held(F.G, 40))
	assert_eq(F.tick_of(ticks, T.GRAB), 6)
	assert_eq(F.tick_of(ticks, T.HIT), 6 + 13, "throw hits on throw frame 14")
	assert_eq(foe.hp, foe.max_hp - 90)


func test_grab_tech_within_10_frames() -> void:
	var foe_frames: Array = F.held(0, 15)
	foe_frames[14] = F.T
	var ticks := F.play(sim, [F.T], foe_frames, 30)
	assert_eq(F.tick_of(ticks, T.GRAB_TECH), 15)
	assert_eq(foe.hp, foe.max_hp)
	assert_eq(me.action, Action.RECOVER)
	assert_eq(foe.action, Action.RECOVER)
	_duel(1.2)
	foe_frames = F.held(0, 17)
	foe_frames[16] = F.T
	ticks = F.play(sim, [F.T], foe_frames, 30)
	assert_eq(F.tick_of(ticks, T.GRAB_TECH), -1, "too late")


func test_grab_loses_to_attacks_and_jumps() -> void:
	var ticks := F.play(sim, [F.T], [F.L], 8)
	assert_eq(F.tick_of(ticks, T.GRAB), -1)
	assert_eq(F.first(ticks, T.HIT).source, 1)
	_duel(1.2)
	ticks = F.play(sim, [0, 0, F.T], [F.J], 12)
	assert_eq(F.tick_of(ticks, T.GRAB), -1)


func test_projectile_travels_hits_and_is_blockable_with_chip() -> void:
	_duel(6.0)
	var ticks := F.play(sim, [A3], [], 60)
	var hit := F.first(ticks, T.HIT)
	assert_not_null(hit)
	assert_true(hit.flags & SimEvent.FLAG_PROJECTILE)
	assert_eq(hit.amount, 60)
	assert_eq(F.tick_of(ticks, T.HIT), 30, "spawns on frame 16, flies 0.3 m per frame")
	assert_eq(sim.state.effects.size(), 0, "removed on contact")
	_duel(6.0)
	F.play(sim, [], F.held(F.G, 8))
	ticks = F.play(sim, [A3], F.held(F.G, 60))
	assert_eq(F.first(ticks, T.BLOCK).amount, 60 * 12 / 100)


func test_attack_hitboxes_destroy_projectiles() -> void:
	_duel(3.0)
	var foe_frames: Array = F.held(0, 12)
	foe_frames[11] = F.L
	var ticks := F.play(sim, [A3], foe_frames, 40)
	assert_ne(F.tick_of(ticks, T.EFFECT_DESTROYED), -1)
	assert_eq(F.tick_of(ticks, T.HIT), -1)
	assert_eq(foe.hp, foe.max_hp)


func test_parry_works_against_projectiles() -> void:
	_duel(6.0)
	var foe_frames: Array = F.held(0, 26)
	foe_frames[25] = F.G
	var ticks := F.play(sim, [A3], foe_frames + F.held(F.G, 20), 40)
	assert_eq(F.tick_of(ticks, T.PARRY), 30)
	assert_ne(me.action, Action.HITSTUN, "the shooter is not staggered")
	assert_eq(sim.state.effects.size(), 0)


func test_walls_and_pillars_block_projectiles() -> void:
	var arena := F.arena()
	var pillar := ArenaObstacle.new()
	pillar.a = Vector2(0.0, 3.0)
	pillar.b = pillar.a
	pillar.radius = 0.5
	arena.obstacles.append(pillar)
	sim = F.fighting_sim(F.config(2, F.test_fighter(), arena))
	F.place(sim, 0, 0.0, 0.0, 0)
	F.place(sim, 1, 0.0, 6.0, Fx.HALF_TURN)
	var ticks := F.play(sim, [A3], [], 60)
	assert_ne(F.tick_of(ticks, T.EFFECT_DESTROYED), -1)
	assert_eq(F.tick_of(ticks, T.HIT), -1)


func test_delayed_eruption_spawns_under_the_target_and_can_be_dodged() -> void:
	_duel(6.0)
	F.place(sim, 1, 2.0, 6.0, Fx.HALF_TURN)
	_start(0, &"eruption")
	var ticks := F.play(sim, [], [], 50)
	var spawn := F.first(ticks, T.EFFECT_SPAWN)
	assert_eq(Fx.to_vec3(spawn.position).distance_to(Vector3(2.0, 0.0, 6.0)) < 0.01, true)
	assert_eq(F.tick_of(ticks, T.EFFECT_SPAWN), 13)
	assert_eq(F.tick_of(ticks, T.HIT), 13 + 30)
	assert_eq(foe.action, Action.AIR_HITSTUN, "launches")
	_duel(6.0)
	_start(0, &"eruption")
	ticks = F.play(sim, [], F.held(0, 14) + F.held(SimInput.make(0, 127, 0), 30), 50)
	assert_eq(F.tick_of(ticks, T.HIT), -1, "ran out of the rune")


func test_blink_teleports_in_the_stick_direction_with_invincibility() -> void:
	_duel(6.0)
	var start := me.pos
	_start(0, &"blink")
	assert_true(sim.is_invulnerable(me))
	var ticks := F.play(sim, [SimInput.make(0, 127, 0)], [], 1)
	assert_eq(F.tick_of(ticks, T.TELEPORT), 1)
	assert_almost_eq(Fx.to_m(me.pos.x - start.x), 5.0, 0.15)


func test_chain_hook_pulls_the_target_in_front() -> void:
	_duel(7.0)
	_start(0, &"chain_hook")
	var ticks := F.play(sim, [], [], 30)
	assert_eq(F.tick_of(ticks, T.HIT), 13)
	assert_almost_eq(Fx.to_m(Fx.dist_xz(me.pos, foe.pos)), 1.2, 0.15)
	assert_eq(foe.action, Action.HITSTUN)


func test_command_grab_super_beats_attacks_and_cannot_be_teched() -> void:
	var data := F.test_fighter().duplicate()
	data.super_move = &"command_grab"
	_duel(1.2, data)
	me.soul = 10000
	var foe_frames: Array = F.held(0, 30)
	foe_frames[0] = F.H
	for i in range(21, 30):
		foe_frames[i] = F.T if i % 2 == 0 else 0
	var ticks := F.play(sim, [SimInput.SUPER], foe_frames, 1)
	assert_eq(F.tick_of(ticks, T.SUPER_FLASH), 1)
	assert_eq(me.soul, 0)
	ticks = F.play(sim, [], foe_frames.slice(1), 110)
	assert_ne(F.tick_of(ticks, T.GRAB), -1)
	assert_eq(F.tick_of(ticks, T.GRAB_TECH), -1)
	assert_eq(F.count_of(ticks, T.HIT), 3)
	assert_eq(foe.hp, foe.max_hp - (100 + 100 + 150), "hits 1-3 are unscaled")


func test_super_flash_freezes_everyone() -> void:
	me.soul = 10000
	var foe_pos := foe.pos
	# The flash starts on the tick after the super starts, for everyone at once.
	var ticks := F.play(sim, [SimInput.SUPER], [SimInput.make(0, 127, 0)], 1)
	assert_eq(F.tick_of(ticks, T.SUPER_FLASH), 1)
	foe_pos = foe.pos
	ticks = F.play(sim, [], F.held(SimInput.make(0, 127, 0), 20), 20)
	assert_eq(foe.pos, foe_pos, "nobody moves during the flash")
	assert_eq(me.move_frame, 1)
	ticks = F.play(sim, [], [], 10)
	assert_eq(F.tick_of(ticks, T.HIT), 7, "hits on super frame 8 after the flash")
	assert_true(F.first(ticks, T.HIT).flags & SimEvent.FLAG_SUPER)


func test_super_needs_full_soul() -> void:
	me.soul = 9900
	var ticks := F.play(sim, [SimInput.SUPER], [], 3)
	assert_eq(F.count_of(ticks, T.MOVE_START), 0)


func test_damage_buff_applies_to_the_next_hit() -> void:
	_duel(4.0)
	_start(0, &"war_cry")
	F.until_action(sim, me, Action.IDLE)
	assert_eq(me.buffs.size(), 1)
	F.place(sim, 1, 0.0, 1.2, Fx.HALF_TURN)
	var ticks := F.play(sim, [F.L], [], 6)
	assert_eq(F.first(ticks, T.HIT).amount, 45)
	F.until_action(sim, me, Action.IDLE)
	assert_eq(me.buffs.size(), 0, "spent once the buffed move is over")


func test_perfect_dodge_grants_soul() -> void:
	# Light hits on tick 6, the sidestep roll started on tick 2 is on its 5th frame.
	var ticks := F.play(sim, [F.L], [0, SimInput.make(F.D, 127, 0)], 12)
	assert_eq(F.tick_of(ticks, T.PERFECT_DODGE), 6)
	assert_eq(F.tick_of(ticks, T.HIT), -1)
	assert_eq(foe.soul_points(), 5)

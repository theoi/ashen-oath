extends TestCase
## Frame-accurate hit interactions: hit, whiff, block, parry, guard break, counter hits,
## hitstop, frame advantage, strings, tracking, chip, scaling, multi-target.

const F := preload("res://tests/sim/sim_fixtures.gd")
const Action := FighterState.Action
const T := SimEvent.Type

var sim: Sim
var me: FighterState
var foe: FighterState


func before_each() -> void:
	sim = F.duel()
	me = sim.fighter(0)
	foe = sim.fighter(1)


func test_light_hits_on_its_startup_frame_with_hitstop_and_hitstun() -> void:
	var ticks := F.play(sim, [F.L], [], 6)
	assert_eq(F.tick_of(ticks, T.HIT), 6, "startup 6 hits on the 6th tick")
	var hit := F.first(ticks, T.HIT)
	assert_eq(hit.amount, 35)
	assert_eq(hit.hitstop, 5)
	assert_eq(foe.hp, foe.max_hp - 35)
	assert_eq(foe.action, Action.HITSTUN)
	assert_eq(foe.stun, 16)
	assert_eq(me.hitstop, 5)
	var frame := me.move_frame
	var foe_pos := foe.pos
	F.hold(sim, 5)
	assert_eq(me.move_frame, frame, "attacker frozen during hitstop")
	assert_eq(foe.pos, foe_pos, "victim frozen during hitstop")
	F.step(sim)
	assert_eq(me.move_frame, frame + 1)


func test_light_is_plus_3_on_hit_and_minus_2_on_block() -> void:
	assert_eq(_advantage(false), 3)
	sim = F.duel()
	me = sim.fighter(0)
	foe = sim.fighter(1)
	assert_eq(_advantage(true), -2)


func _advantage(block: bool) -> int:
	if block:
		_raise_guard()
	F.play(sim, [F.L], F.held(F.G, 6) if block else [], 6)
	var stun_action := Action.BLOCKSTUN if block else Action.HITSTUN
	assert_eq(foe.action, stun_action)
	var mine := -1
	var theirs := -1
	for t in 60:
		F.step(sim, 0, F.G if block else 0)
		if mine < 0 and me.action == Action.IDLE:
			mine = t
		if theirs < 0 and foe.action != stun_action:
			theirs = t
	return theirs - mine


func test_out_of_range_light_whiffs() -> void:
	sim = F.duel(3.0)
	var ticks := F.play(sim, [F.L], [], 25)
	assert_eq(F.tick_of(ticks, T.HIT), -1)
	assert_eq(sim.fighter(1).hp, sim.fighter(1).max_hp)


## Holds guard long enough that the parry window has passed.
func _raise_guard() -> void:
	F.play(sim, [], F.held(F.G, 8))


func test_block_takes_no_damage_from_basics_and_drains_guard() -> void:
	_raise_guard()
	var ticks := F.play(sim, [F.L], F.held(F.G, 10))
	assert_eq(F.tick_of(ticks, T.BLOCK), 6)
	assert_eq(foe.hp, foe.max_hp)
	assert_eq(foe.guard_points(), 100 - 8)
	assert_eq(foe.action, Action.BLOCKSTUN)


func test_guard_regenerates_after_45_frames_at_30_per_second() -> void:
	_raise_guard()
	F.play(sim, [F.L], F.held(F.G, 6))
	F.hold(sim, 44, 0, F.G)
	assert_eq(foe.guard, 9200, "no regen in the first 45 frames")
	F.hold(sim, 60, 0, F.G)
	assert_eq(foe.guard_points(), 100, "refills at 30/s")


func test_hits_from_behind_go_through_guard() -> void:
	_raise_guard()
	foe.facing = 0
	var ticks := F.play(sim, [F.L], F.held(F.G, 10))
	assert_eq(F.tick_of(ticks, T.HIT), 6)
	assert_eq(foe.hp, foe.max_hp - 35)


func test_parry_window_is_6_frames() -> void:
	# Guard pressed on tick 1, hit lands on tick 6: 6th frame of the window.
	var ticks := F.play(sim, [F.L], F.held(F.G, 6))
	assert_eq(F.tick_of(ticks, T.PARRY), 6)
	assert_eq(foe.hp, foe.max_hp)
	assert_eq(foe.soul_points(), 10)
	assert_eq(me.action, Action.HITSTUN, "attacker staggered")
	assert_eq(me.stun, 24)
	# Guard pressed one tick earlier: the hit lands on the 7th frame and is just blocked.
	sim = F.duel()
	ticks = F.play(sim, [0, F.L], F.held(F.G, 7))
	assert_eq(F.tick_of(ticks, T.PARRY), -1)
	assert_eq(F.tick_of(ticks, T.BLOCK), 7)


func test_parry_buff_from_fighter_data() -> void:
	var data := F.test_fighter().duplicate()
	data.parry_window = 8
	var buff := BuffData.new()
	buff.id = &"ignite"
	buff.damage_bonus_percent = 30
	buff.uses = 1
	data.parry_buff = buff
	sim = F.duel(1.2, 2, data)
	var ticks := F.play(sim, [0, 0, F.L], F.held(F.G, 8))
	assert_eq(F.tick_of(ticks, T.PARRY), 8, "8-frame parry window")
	assert_eq(sim.fighter(1).buffs.size(), 1)
	# The buffed next hit deals +30% once.
	F.hold(sim, 30)
	F.place(sim, 0, 0.0, 0.0, 0)
	F.place(sim, 1, 0.0, 1.2, Fx.HALF_TURN)
	ticks = F.play(sim, [], [F.L], 6)
	assert_eq(F.first(ticks, T.HIT).amount, 45)
	assert_eq(sim.fighter(1).buffs.size(), 0, "single use")


func test_missed_parry_locks_out_parry_for_20_frames() -> void:
	F.play(sim, [], [F.G, 0, 0, 0, 0, 0, 0])
	assert_eq(foe.parry_lockout, 19)
	var ticks := F.play(sim, [F.L], [F.G] + F.held(F.G, 6))
	assert_eq(F.tick_of(ticks, T.PARRY), -1, "tapping again during lockout only guards")
	assert_eq(F.tick_of(ticks, T.BLOCK), 6)


func test_guard_break_on_empty_gauge_then_counter_hit() -> void:
	_raise_guard()
	foe.guard = 2000
	foe.guard_idle = 0
	var ticks := F.play(sim, [F.H], F.held(F.G, 20))
	assert_eq(F.tick_of(ticks, T.GUARD_BREAK), 18)
	assert_eq(foe.action, Action.GUARD_BREAK)
	assert_eq(foe.stun, 60)
	assert_eq(foe.guard_points(), 100, "gauge refills after the break")
	F.until_action(sim, me, Action.IDLE)
	ticks = F.play(sim, [F.L], [], 6)
	var hit := F.first(ticks, T.HIT)
	assert_not_null(hit)
	assert_true(hit.flags & SimEvent.FLAG_COUNTER, "next hit after a guard break is a counter hit")


func test_counter_hit_during_startup() -> void:
	# Foe starts a heavy (startup 18); our light lands during its startup.
	var ticks := F.play(sim, [0, F.L], [F.H], 8)
	var hit := F.first(ticks, T.HIT)
	assert_not_null(hit)
	assert_eq(hit.source, 0)
	assert_true(hit.flags & SimEvent.FLAG_COUNTER)
	assert_eq(hit.amount, 35 * 115 / 100)
	assert_eq(foe.stun, 24, "hitstun +50%")


func test_trade_when_both_hit_on_the_same_tick() -> void:
	var ticks := F.play(sim, [F.L], [F.L], 6)
	assert_eq(F.count_of(ticks, T.HIT), 2)
	assert_eq(me.hp, me.max_hp - 35)
	assert_eq(foe.hp, foe.max_hp - 35)


func test_light_string_chains_when_active_frames_end() -> void:
	var events: Array[SimEvent] = []
	var starts: Array[int] = []
	for t in 60:
		var frame := F.L if t == 0 or t == 4 or t == 25 else 0
		var tick_events := F.step(sim, frame)
		for e in tick_events:
			if e.type == T.MOVE_START and e.source == 0:
				starts.append(t + 1)
			if e.type == T.HIT and e.source == 0:
				events.append(e)
	assert_eq(events.size(), 3, "L L L all connect")
	assert_eq(starts[1], 6 + 2 + 5, "2nd light starts the frame after active ends (+hitstop)")
	assert_eq(events[0].amount, 35)
	assert_eq(events[1].amount, 35)
	assert_eq(events[2].amount, 45, "3rd hit scaled to 90%")


func test_buffer_expires_after_8_frames_in_a_string() -> void:
	# Second press 9+ frames before the chain point is dropped.
	F.play(sim, [F.L])
	var ticks := F.play(sim, [0, 0, 0, 0, 0, 0], [], 40)
	assert_eq(F.count_of(ticks, T.MOVE_START), 0)


func test_damage_scaling_floor_and_long_combo_decay() -> void:
	foe.action = Action.HITSTUN
	foe.stun = 100
	foe.combo_hits = 20
	var ticks := F.play(sim, [F.L], [], 6)
	assert_eq(F.first(ticks, T.HIT).amount, 35 * 40 / 100, "40% floor")
	sim = F.duel()
	foe = sim.fighter(1)
	foe.action = Action.HITSTUN
	foe.stun = 100
	foe.combo_ticks = 240
	F.play(sim, [F.L], [], 6)
	assert_eq(foe.stun, 8, "hitstun halved after 240 frames of combo")


func test_lights_track_8_degrees_heavies_3_per_frame() -> void:
	# Target 90 degrees to the side; soft lock snaps at the start, so turn the attacker away
	# after the start and measure how fast startup tracking turns it back.
	F.step(sim, F.L)
	me.facing = Fx.wrap_angle(me.facing + Fx.QUARTER_TURN)
	var before := me.facing
	F.step(sim)
	assert_eq(absi(Fx.angle_diff(before, me.facing)), Fx.deg(8.0))
	sim = F.duel()
	me = sim.fighter(0)
	F.step(sim, F.H)
	me.facing = Fx.wrap_angle(me.facing + Fx.QUARTER_TURN)
	before = me.facing
	F.step(sim)
	assert_eq(absi(Fx.angle_diff(before, me.facing)), Fx.deg(3.0))


func test_sidestep_beats_a_heavy() -> void:
	sim = F.duel(1.6)
	foe = sim.fighter(1)
	var side := SimInput.make(0, 127, 0)
	var ticks := F.play(sim, [F.H], F.held(side, 20))
	assert_eq(F.tick_of(ticks, T.HIT), -1, "a heavy cannot track a sidestep")


func test_chip_from_abilities_cannot_ko_but_super_chip_can() -> void:
	sim = F.duel(1.2)
	foe = sim.fighter(1)
	_raise_guard()
	var ticks := F.play(sim, [SimInput.ABILITY_2], F.held(F.G, 12))
	var block := F.first(ticks, T.BLOCK)
	assert_eq(block.amount, 70 * 12 / 100)
	assert_eq(foe.hp, foe.max_hp - 8)
	sim = F.duel(1.2)
	foe = sim.fighter(1)
	foe.hp = 1
	_raise_guard()
	F.play(sim, [SimInput.ABILITY_2], F.held(F.G, 12))
	assert_eq(foe.hp, 1, "ability chip leaves 1 HP")
	sim = F.duel(1.2)
	foe = sim.fighter(1)
	sim.fighter(0).soul = 10000
	foe.hp = 5
	_raise_guard()
	F.play(sim, [SimInput.SUPER], F.held(F.G, 40))
	assert_true(foe.ko, "super chip can KO")


func test_one_swing_hits_every_overlapping_enemy_with_separate_scaling() -> void:
	sim = F.duel(1.2, 3)
	F.place(sim, 2, 0.5, 1.2, Fx.HALF_TURN)
	sim.fighter(1).action = Action.HITSTUN
	sim.fighter(1).stun = 100
	sim.fighter(1).combo_hits = 5
	var ticks := F.play(sim, [F.L], [], 6)
	assert_eq(F.count_of(ticks, T.HIT), 2)
	assert_eq(sim.fighter(1).hp, sim.fighter(1).max_hp - 35 * 60 / 100)
	assert_eq(sim.fighter(2).hp, sim.fighter(2).max_hp - 35)

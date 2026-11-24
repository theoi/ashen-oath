extends TestCase
## Boss rules: channel-break gauge, ⚡Counters only from the boss's front, and the limit on
## counterable wind-ups.

const F := preload("res://tests/sim/sim_fixtures.gd")
const K := preload("res://tests/sim/test_skill_kit.gd")
const Action := FighterState.Action
const T := SimEvent.Type
const LUNGE := SimInput.SKILL_1
const ARMORED := SimInput.SKILL_2
const QUICK := SimInput.SKILL_3
const MAELSTROM := SimInput.SKILL_5

var sim: Sim
var me: FighterState
var boss: FighterState


## The kit plus a boss special: 120 f channel (push immune) with a 100-point gauge, then a
## 6 m slam. Quick drains 60 stagger and has no cooldown.
static func _kit(armored_channel: bool = true) -> FighterData:
	var data := K.kit()
	data.moves[5].cooldown = 0
	data.moves[5].hitboxes[0].hit.stagger = 60
	var slam := K._move(&"maelstrom", MoveData.Kind.ABILITY, 121, 3, 20, K._hit(250, HitData.Weight.MASSIVE))
	slam.hitboxes[0].radius = 6.0
	slam.channel_gauge = 100
	slam.channel_start = 1
	slam.channel_end = 120
	if armored_channel:
		slam.push_immune_start = 1
		slam.push_immune_end = 120
	data.moves.append(slam)
	data.abilities.append(&"maelstrom")
	return data


func _duel(data: FighterData, counter_cooldown: int = 0) -> void:
	var cfg := F.config(2, data)
	cfg.slots[1].stagger_max = 600
	cfg.slots[1].counter_window_cooldown = counter_cooldown
	sim = F.fighting_sim(cfg)
	F.place(sim, 0, 0.0, 0.0, 0)
	F.place(sim, 1, 0.0, 1.2, Fx.HALF_TURN)
	me = sim.fighter(0)
	boss = sim.fighter(1)


func test_channel_gauge_breaks_into_stagger() -> void:
	_duel(_kit())
	var ticks := F.play(sim, [], [MAELSTROM], 1)
	var start := F.first(ticks, T.CHANNEL_START)
	assert_not_null(start)
	assert_eq(start.amount, 100)
	assert_eq(boss.channel, 100)
	ticks = F.play(sim, [QUICK], [], 10)
	assert_not_null(F.first(ticks, T.ARMOR), "the channel is armored")
	assert_eq(boss.channel, 40)
	var soul := me.soul
	F.until_action(sim, me, Action.IDLE)
	ticks = F.play(sim, [QUICK], [], 10)
	var brk := F.first(ticks, T.CHANNEL_BREAK)
	assert_not_null(brk)
	assert_eq(brk.source, 0)
	assert_eq(brk.target, 1)
	assert_eq(brk.id, &"maelstrom")
	assert_eq(boss.action, Action.STAGGERED)
	assert_eq(boss.channel, 0)
	assert_eq(boss.stagger, 600, "the gauge took the drain, not the stagger bar")
	assert_true(me.soul - soul >= sim.rules.stagger_soul * 100, "+20 Soul for the break")
	assert_eq(F.tick_of(ticks, T.CHANNEL_END), -1)


func test_unbroken_channel_fires_the_special() -> void:
	_duel(_kit())
	var ticks := F.play(sim, [], [MAELSTROM], 125)
	var end := F.first(ticks, T.CHANNEL_END)
	assert_not_null(end)
	assert_eq(end.amount, 1, "completed")
	assert_eq(F.tick_of(ticks, T.CHANNEL_END), 121)
	var hit := F.first(ticks, T.HIT)
	assert_not_null(hit)
	assert_eq(hit.source, 1)
	assert_eq(hit.id, &"maelstrom")


func test_interrupted_channel_ends_without_firing() -> void:
	_duel(_kit(false))
	F.play(sim, [], [MAELSTROM], 2)
	var ticks := F.play(sim, [QUICK], [], 10)
	assert_eq(boss.action, Action.HITSTUN)
	var end := F.first(ticks, T.CHANNEL_END)
	assert_not_null(end)
	assert_eq(end.amount, 0, "interrupted")
	assert_eq(boss.channel, 0)


func test_boss_counters_only_land_from_the_front() -> void:
	_duel(K.kit())
	var ticks := F.play(sim, [0, LUNGE], [ARMORED], 7)
	assert_not_null(F.first(ticks, T.COUNTER_STUN), "from the front")
	_duel(K.kit())
	F.play(sim, [], [ARMORED], 1)
	boss.facing = 0
	ticks = F.play(sim, [LUNGE], [], 7)
	assert_eq(F.tick_of(ticks, T.COUNTER_STUN), -1, "from behind: armor holds")
	assert_not_null(F.first(ticks, T.ARMOR))


func test_counter_window_cooldown_suppresses_the_next_windows() -> void:
	_duel(K.kit(), 600)
	var ticks := F.play(sim, [], [ARMORED], 1)
	assert_eq(F.tick_of(ticks, T.COUNTER_WINDOW), 1)
	F.until_action(sim, boss, Action.IDLE)
	while boss.cooldowns[1] > 0:
		F.step(sim)
	ticks = F.play(sim, [], [ARMORED], 1)
	assert_eq(boss.action, Action.ATTACK)
	assert_eq(F.tick_of(ticks, T.COUNTER_WINDOW), -1, "within 600 f of the last window")
	assert_false(sim.in_counter_window(boss))
	ticks = F.play(sim, [LUNGE], [], 7)
	assert_eq(F.tick_of(ticks, T.COUNTER_STUN), -1)
	F.until_action(sim, boss, Action.IDLE)
	F.hold(sim, 600)
	ticks = F.play(sim, [], [ARMORED], 1)
	assert_eq(F.tick_of(ticks, T.COUNTER_WINDOW), 1, "shows again after the cooldown")

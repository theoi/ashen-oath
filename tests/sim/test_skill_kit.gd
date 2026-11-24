extends TestCase
## Skill-kit rules: dash, cancels, armor categories, ⚡Counters, weight hitstop, stagger.

const F := preload("res://tests/sim/sim_fixtures.gd")
const Action := FighterState.Action
const T := SimEvent.Type
const B := SimInput.BASIC
const DASH := SimInput.DASH
const LUNGE := SimInput.SKILL_1
const ARMORED := SimInput.SKILL_2
const QUICK := SimInput.SKILL_3
const SWEEP := SimInput.SKILL_4

var sim: Sim
var me: FighterState
var foe: FighterState


static func _hit(damage: int, weight: HitData.Weight, reaction: HitData.Reaction = HitData.Reaction.STAGGER) -> HitData:
	var hit := HitData.new()
	hit.damage = damage
	hit.weight = weight
	hit.reaction = reaction
	hit.hitstun = 20
	hit.knockback = 0.0
	return hit


static func _move(id: StringName, kind: MoveData.Kind, startup: int, active: int, recovery: int,
		hit: HitData) -> MoveData:
	var move := MoveData.new()
	move.id = id
	move.kind = kind
	move.startup = startup
	move.active = active
	move.recovery = recovery
	move.aim = MoveData.Aim.DIRECTION
	var box := HitboxData.new()
	box.offset = Vector3(0.0, 1.0, 0.9)
	box.radius = 0.7
	box.hit = hit
	move.hitboxes = [box]
	return move


## Basics 4/2/12, 4/2/12, 6/2/12; skills: lunge (⚡, flinch immune 1-12), armored (push
## immune 1-20, counter window 1-15), quick (3/2/14), sweep (knockdown); awakening.
static func kit() -> FighterData:
	var data := F.fighter()
	data.id = &"kit"
	data.dash = DashData.new()
	var b1 := _move(&"basic1", MoveData.Kind.LIGHT, 4, 2, 12, _hit(25, HitData.Weight.BASIC))
	b1.next_light = &"basic2"
	var b2 := _move(&"basic2", MoveData.Kind.LIGHT, 4, 2, 12, _hit(25, HitData.Weight.BASIC))
	b2.next_light = &"basic3"
	var b3 := _move(&"basic3", MoveData.Kind.LIGHT, 6, 2, 12, _hit(40, HitData.Weight.BASIC))
	var lunge := _move(&"lunge", MoveData.Kind.ABILITY, 5, 8, 16, _hit(90, HitData.Weight.MEDIUM))
	lunge.hitboxes[0].hit.counter = true
	lunge.flinch_immune_start = 1
	lunge.flinch_immune_end = 12
	lunge.cooldown = 300
	var armored := _move(&"armored", MoveData.Kind.ABILITY, 20, 2, 10, _hit(100, HitData.Weight.HEAVY))
	armored.push_immune_start = 1
	armored.push_immune_end = 20
	armored.counter_window_start = 1
	armored.counter_window_end = 15
	armored.cooldown = 60
	var quick := _move(&"quick", MoveData.Kind.ABILITY, 3, 2, 14, _hit(50, HitData.Weight.LIGHT))
	quick.cooldown = 60
	var sweep := _move(&"sweep", MoveData.Kind.ABILITY, 4, 2, 14,
			_hit(30, HitData.Weight.MEDIUM, HitData.Reaction.KNOCKDOWN))
	var awaken := _move(&"awaken", MoveData.Kind.SUPER, 10, 4, 20, _hit(300, HitData.Weight.MASSIVE))
	awaken.soul_cost = 100
	data.moves = [b1, b2, b3, lunge, armored, quick, sweep, awaken]
	data.light = &"basic1"
	data.abilities = [&"lunge", &"armored", &"quick", &"sweep"]
	data.super_move = &"awaken"
	return data


func before_each() -> void:
	_duel(1.2)


func _duel(distance: float, cfg: SimConfig = null) -> void:
	sim = F.fighting_sim(cfg if cfg != null else F.config(2, kit()))
	F.place(sim, 0, 0.0, 0.0, 0)
	F.place(sim, 1, 0.0, distance, Fx.HALF_TURN)
	me = sim.fighter(0)
	foe = sim.fighter(1)


func _starts(ticks: Array[Array], slot: int = 0) -> Array[String]:
	var out: Array[String] = []
	for t in ticks.size():
		for e: SimEvent in ticks[t]:
			if e.type == T.MOVE_START and e.source == slot:
				out.append("%d:%s" % [t + 1, e.id])
	return out


func test_dash_travels_its_distance_with_charges_and_recharge() -> void:
	_duel(8.0)
	var right := SimInput.make(DASH, 127, 0)
	F.step(sim, right)
	assert_eq(me.action, Action.DASH)
	assert_eq(me.dash_charges, 1)
	assert_eq(me.dash_recharge, 299, "counts down from the dash tick")
	F.hold(sim, 5)
	assert_eq(me.pos.x, 31500, "front-loaded: 70% (3.15 m) by frame 6")
	F.hold(sim, 6)
	assert_eq(me.pos.x, 45000, "4.5 m in 12 frames")
	F.hold(sim, 7)
	assert_eq(me.action, Action.IDLE, "18 frames in total")
	F.step(sim, right)
	F.hold(sim, 20)
	assert_eq(me.dash_charges, 0)
	F.step(sim, right)
	assert_ne(me.action, Action.DASH, "no charges left")
	F.hold(sim, 300 - 41)
	assert_eq(me.dash_charges, 1, "one charge back after 300 frames")
	assert_eq(me.dash_recharge, 300, "the next charge starts recharging")


func test_dash_is_invincible_on_frames_1_to_10_and_perfect_early() -> void:
	var ticks := F.play(sim, [0, DASH], [F.L], 4)
	assert_eq(F.tick_of(ticks, T.PERFECT_DODGE), 4, "hit during dash frame 3")
	assert_eq(me.soul, 500)
	assert_eq(F.tick_of(ticks, T.HIT), -1)
	_duel(1.2)
	F.step(sim, DASH)
	for tick in range(1, 19):
		assert_eq(sim.is_invulnerable(me), tick <= 10, "dash frame %d" % tick)
		F.step(sim)


func test_dash_goes_toward_the_aim_without_stick_and_not_in_the_air() -> void:
	F.step(sim, SimInput.with_aim_point(DASH, Vector2(-3.0, 0.0)))
	assert_eq(me.move_dir, 3072)
	_duel(1.2)
	me.grounded = false
	me.pos.y = 20000
	me.action = Action.AIR
	F.step(sim, DASH)
	assert_ne(me.action, Action.DASH)


func test_tuning_overrides_dash_distance_charges_and_recharge() -> void:
	var cfg := F.config(2, kit())
	cfg.dash_distance = 3.0
	cfg.dash_charges = 3
	cfg.dash_recharge_frames = 120
	_duel(8.0, cfg)
	assert_eq(me.dash_charges, 3)
	assert_eq(sim.dash_recharge_frames(me), 120)
	F.step(sim, SimInput.make(DASH, 127, 0))
	assert_eq(me.dash_recharge, 119)
	F.hold(sim, 15)
	assert_eq(me.pos.x, 30000)
	F.hold(sim, 104)
	assert_eq(me.dash_charges, 3, "charge back after 120 frames")


func test_dash_cancels_skill_startup_and_the_cooldown_stays_spent() -> void:
	_duel(8.0)
	F.step(sim, QUICK)
	F.step(sim, DASH)
	assert_eq(me.action, Action.DASH)
	assert_eq(me.cooldowns[2], 60 - 2)


func test_awakening_cannot_be_cancelled() -> void:
	_duel(8.0)
	me.soul = 10000
	F.step(sim, SimInput.AWAKEN)
	var ticks := F.play(sim, [DASH, 0, QUICK, 0, B], [], 30)
	assert_eq(_starts(ticks), [] as Array[String])
	assert_eq(me.dash_charges, 2)


func test_skill_cancels_another_after_its_last_active_frame_from_the_buffer() -> void:
	_duel(8.0)
	var ticks := F.play(sim, [LUNGE, 0, QUICK], [], 20)
	assert_eq(_starts(ticks), ["1:lunge", "13:quick"], "buffered, fires on lunge frame 13")


func test_basic_can_be_cancelled_by_skill_and_dash_on_any_frame() -> void:
	_duel(8.0)
	var ticks := F.play(sim, [B, QUICK], [], 4)
	assert_eq(_starts(ticks), ["1:basic1", "2:quick"])
	_duel(8.0)
	F.play(sim, [B, DASH], [], 2)
	assert_eq(me.action, Action.DASH)


func test_skill_from_dash_frame_8() -> void:
	_duel(8.0)
	var ticks := F.play(sim, [DASH, 0, QUICK], [], 10)
	assert_eq(_starts(ticks), ["8:quick"])


func test_holding_basic_repeats_the_chain() -> void:
	_duel(8.0)
	var ticks := F.play(sim, F.held(B, 60), [], 60)
	assert_eq(_starts(ticks), ["1:basic1", "18:basic2", "35:basic3", "54:basic1"])


func test_flinch_immune_absorbs_stagger_with_half_hitstop_but_not_knockdown() -> void:
	var ticks := F.play(sim, [0, LUNGE], [F.L], 6)
	var armor := F.first(ticks, T.ARMOR)
	assert_not_null(armor)
	assert_eq(armor.amount, 25 * 115 / 100, "full damage (a counter hit: the lunge is in startup)")
	assert_eq(armor.hitstop, 1, "BASIC 3 f halved")
	assert_eq(me.action, Action.ATTACK)
	assert_eq(me.hp, me.max_hp - armor.amount)
	_duel(1.2)
	F.play(sim, [0, LUNGE], [SWEEP], 6)
	assert_ne(me.action, Action.ATTACK, "knockdowns go through flinch immunity")


func test_push_immune_absorbs_knockdowns() -> void:
	var ticks := F.play(sim, [ARMORED], [0, SWEEP], 8)
	assert_eq(F.count_of(ticks, T.ARMOR), 1)
	assert_eq(me.action, Action.ATTACK)


func test_counter_beats_armor_in_the_window_only() -> void:
	var ticks := F.play(sim, [0, LUNGE], [ARMORED], 7)
	assert_eq(F.tick_of(ticks, T.COUNTER_WINDOW), 1)
	assert_true(sim.in_counter_window(foe) or foe.action == Action.COUNTER_STUN)
	var stun := F.first(ticks, T.COUNTER_STUN)
	assert_not_null(stun)
	assert_eq(foe.action, Action.COUNTER_STUN)
	assert_eq(stun.amount, 60)
	var hit := F.first(ticks, T.HIT)
	assert_true(hit.flags & SimEvent.FLAG_COUNTER_ATTACK != 0)
	assert_eq(hit.amount, 90 * 115 / 100, "also a counter hit on startup")
	assert_eq(me.soul, hit.amount * 8 + 1000, "damage Soul + 10 counter Soul")
	_duel(1.2)
	ticks = F.play(sim, F.held(0, 12) + [LUNGE], [ARMORED], 20)
	assert_eq(F.tick_of(ticks, T.COUNTER_STUN), -1, "window over (frame 17): armor holds")
	assert_eq(F.count_of(ticks, T.ARMOR), 1)


func test_weight_sets_hitstop_and_hitstop_percent_scales_it() -> void:
	var ticks := F.play(sim, [LUNGE], [], 6)
	assert_eq(F.first(ticks, T.HIT).hitstop, 5)
	assert_eq(F.first(ticks, T.HIT).weight, HitData.Weight.MEDIUM)
	var cfg := F.config(2, kit())
	cfg.hitstop_percent = 50
	_duel(1.2, cfg)
	ticks = F.play(sim, [LUNGE], [], 6)
	assert_eq(F.first(ticks, T.HIT).hitstop, 2)


func test_weight_hitstop_table_and_tick_class() -> void:
	var rules := CombatRules.new()
	var expected := {HitData.Weight.TICK: 1, HitData.Weight.BASIC: 3, HitData.Weight.LIGHT: 4,
			HitData.Weight.MEDIUM: 5, HitData.Weight.HEAVY: 8, HitData.Weight.MASSIVE: 10}
	for w: int in expected:
		assert_eq(rules.weight_hitstop[w - 1], expected[w], "weight %d" % w)
	assert_eq(rules.weight_stagger.size(), rules.weight_hitstop.size())
	var data := kit()
	data.moves[5].hitboxes[0].hit.weight = HitData.Weight.TICK
	_duel(1.2, F.config(2, data))
	var ticks := F.play(sim, [QUICK], [], 6)
	var hit := F.first(ticks, T.HIT)
	assert_eq(hit.weight, HitData.Weight.TICK)
	assert_eq(hit.hitstop, 1)
	assert_eq(me.hitstop + foe.hitstop, 0, "1 frame, already over")


func test_awakening_massive_hit_uses_the_final_hit_hitstop() -> void:
	_duel(1.2)
	me.soul = 10000
	var ticks := F.play(sim, [SimInput.AWAKEN], [], 80)
	var hit := F.first(ticks, T.HIT)
	assert_not_null(hit)
	assert_eq(hit.weight, HitData.Weight.MASSIVE)
	assert_eq(hit.hitstop, 12)


func test_stagger_bar_breaks_refills_bigger_and_counter_stun_is_longer_for_bosses() -> void:
	var cfg := F.config(2, kit())
	cfg.slots[1].stagger_max = 100
	_duel(1.2, cfg)
	assert_eq(foe.stagger, 100)
	foe.stagger = 20
	var ticks := F.play(sim, [LUNGE], [], 6)
	var brk := F.first(ticks, T.STAGGER_BREAK)
	assert_not_null(brk, "MEDIUM drains 30")
	assert_eq(foe.action, Action.STAGGERED)
	assert_eq(foe.stun, 150)
	assert_eq(foe.stagger_max, 120)
	assert_eq(foe.stagger, 120)
	assert_eq(me.soul, 90 * 8 + 2000)
	F.hold(sim, 20)
	ticks = F.play(sim, [QUICK], [], 6)
	var hit := F.first(ticks, T.HIT)
	assert_eq(hit.amount, 50 * 125 / 100, "staggered: +25% damage")
	assert_true(hit.flags & SimEvent.FLAG_STAGGERED != 0)
	assert_eq(foe.action, Action.STAGGERED, "no reaction while staggered")
	_duel(1.2, cfg)
	ticks = F.play(sim, [0, LUNGE], [ARMORED], 7)
	assert_eq(F.first(ticks, T.COUNTER_STUN).amount, 90)


func test_quick_rise_from_knockdown_uses_a_charge() -> void:
	F.play(sim, [SWEEP], [], 8)
	assert_ne(F.until_action(sim, foe, Action.KNOCKDOWN), -1)
	F.step(sim, 0, DASH)
	assert_eq(foe.action, Action.KNOCKDOWN, "too early")
	F.hold(sim, 12)
	assert_eq(foe.action, Action.GETUP)
	assert_eq(foe.action_variant, 2)
	assert_eq(foe.dash_charges, 1)
	assert_true(sim.is_invulnerable(foe))


func test_dash_button_bursts_in_hitstun() -> void:
	foe.soul = 5000
	F.play(sim, [QUICK], [], 4)
	assert_eq(foe.action, Action.HITSTUN)
	F.hold(sim, 8, 0, DASH)
	assert_eq(foe.action, Action.BURST)
	assert_eq(foe.soul, 50 * 6, "50 Soul spent; 3 gained from the hit")
	assert_eq(foe.dash_charges, 2, "no dash charge used")

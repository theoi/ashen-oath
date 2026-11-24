extends TestCase
## Statuses from hits: root, victim buffs (debuffs), and the hit-taken trait hook.

const F := preload("res://tests/sim/sim_fixtures.gd")
const K := preload("res://tests/sim/test_skill_kit.gd")
const Action := FighterState.Action
const T := SimEvent.Type
const ARMORED := SimInput.SKILL_2
const QUICK := SimInput.SKILL_3
const SWEEP := SimInput.SKILL_4
const RIGHT := 127

var sim: Sim
var me: FighterState
var foe: FighterState


func _duel(data: FighterData) -> void:
	sim = F.duel(1.2, 2, data)
	me = sim.fighter(0)
	foe = sim.fighter(1)


static func _chill(speed: int) -> BuffData:
	var chill := BuffData.new()
	chill.id = &"chill"
	chill.duration = 90
	chill.speed_bonus_percent = speed
	return chill


func test_root_stops_movement_and_dash_but_not_skills() -> void:
	var data := K.kit()
	data.moves[5].hitboxes[0].hit.root_frames = 60
	_duel(data)
	var ticks := F.play(sim, [QUICK], [], 4)
	var root := F.first(ticks, T.ROOT)
	assert_not_null(root)
	assert_eq(root.target, 1)
	assert_eq(root.amount, 60)
	F.until_action(sim, foe, Action.IDLE)
	assert_true(foe.rooted > 0)
	var pos := foe.pos
	F.hold(sim, 5, 0, SimInput.make(0, RIGHT, 0))
	assert_eq(foe.pos, pos, "no walking while rooted")
	F.step(sim, 0, SimInput.DASH)
	assert_ne(foe.action, Action.DASH, "no dash while rooted")
	F.step(sim, 0, QUICK)
	assert_eq(foe.action, Action.ATTACK, "skills still work")
	F.until_action(sim, foe, Action.IDLE)
	while foe.rooted > 0:
		F.step(sim)
	F.hold(sim, 5, 0, SimInput.make(0, RIGHT, 0))
	assert_true(foe.pos.x > pos.x, "moves again once the root ends")


func test_root_is_cleared_by_knockdown_and_ignored_by_armor() -> void:
	var data := K.kit()
	data.moves[5].hitboxes[0].hit.root_frames = 60
	data.moves[6].hitboxes[0].hit.root_frames = 60
	_duel(data)
	var ticks := F.play(sim, [SWEEP], [], 6)
	assert_eq(F.tick_of(ticks, T.ROOT), -1, "knockdown hits do not root")
	_duel(data)
	foe.rooted = 50
	F.play(sim, [SWEEP], [], 6)
	assert_eq(foe.action, Action.AIR_HITSTUN, "knockdown hits pop the victim first")
	assert_eq(foe.rooted, 0, "knockdowns clear the root")
	_duel(data)
	ticks = F.play(sim, [0, QUICK], [ARMORED], 6)
	assert_not_null(F.first(ticks, T.ARMOR))
	assert_eq(foe.rooted, 0, "armored hits do not root")


func test_victim_debuff_slows_and_refreshes_by_id() -> void:
	var data := K.kit()
	data.moves[0].hitboxes[0].hit.victim_buff = _chill(-30)
	_duel(data)
	F.play(sim, [SimInput.BASIC], [], 6)
	assert_eq(foe.buffs.size(), 1)
	assert_eq(foe.buffs[0].speed_bonus_percent, -30)
	F.until_action(sim, me, Action.IDLE)
	F.play(sim, [SimInput.BASIC], [], 6)
	assert_eq(foe.buffs.size(), 1, "a second Chill refreshes instead of stacking")
	assert_eq(me.buffs.size(), 0)
	F.until_action(sim, foe, Action.IDLE)
	F.hold(sim, 20, 0, SimInput.make(0, RIGHT, 0))
	assert_eq(Fx.length_xz(foe.vel), Fx.mps(data.run_speed) * 70 / 100, "run speed −30%")


func test_slows_past_minus_100_stop_without_reversing() -> void:
	var data := K.kit()
	data.moves[0].hitboxes[0].hit.victim_buff = _chill(-150)
	_duel(data)
	F.play(sim, [SimInput.BASIC], [], 6)
	F.until_action(sim, foe, Action.IDLE)
	var pos := foe.pos
	F.hold(sim, 10, 0, SimInput.make(0, RIGHT, 0))
	assert_eq(foe.pos, pos)


func test_on_hit_taken_sees_hits_and_armored_hits() -> void:
	var data := K.kit()
	data.trait_script = load("res://tests/sim/fixtures/hit_taken_trait.gd")
	_duel(data)
	var ticks := F.play(sim, [QUICK], [], 4)
	assert_eq(foe.vars[0], F.first(ticks, T.HIT).amount)
	assert_eq(foe.vars[1], 0)
	assert_eq(foe.vars[2], 1, "attacker slot 0")
	_duel(data)
	ticks = F.play(sim, [0, QUICK], [ARMORED], 6)
	assert_eq(foe.vars[0], F.first(ticks, T.ARMOR).amount)
	assert_eq(foe.vars[1], 1)


static func _iron_hide(armor: BuffData.Armor, taken: int = 0) -> BuffData:
	var hide := BuffData.new()
	hide.id = &"iron_hide"
	hide.duration = 300
	hide.armor = armor
	hide.damage_taken_percent = taken
	return hide


func test_push_immune_buff_armors_every_hit_in_any_action() -> void:
	_duel(K.kit())
	sim.apply_buff(foe, _iron_hide(BuffData.Armor.PUSH_IMMUNE, -30), -2)
	var ticks := F.play(sim, [QUICK], [], 6)
	var armor := F.first(ticks, T.ARMOR)
	assert_not_null(armor, "idle, still armored")
	assert_eq(armor.amount, 50 * 70 / 100, "takes 30% less")
	assert_eq(F.tick_of(ticks, T.HIT), -1)
	assert_eq(foe.action, Action.IDLE)
	F.until_action(sim, me, Action.IDLE)
	ticks = F.play(sim, [SWEEP], [], 8)
	assert_not_null(F.first(ticks, T.ARMOR), "knockdowns too")
	assert_eq(foe.action, Action.IDLE)


func test_flinch_immune_buff_still_falls_to_knockdowns() -> void:
	_duel(K.kit())
	sim.apply_buff(foe, _iron_hide(BuffData.Armor.FLINCH_IMMUNE), -2)
	var ticks := F.play(sim, [QUICK], [], 6)
	assert_not_null(F.first(ticks, T.ARMOR))
	assert_eq(F.first(ticks, T.ARMOR).amount, 50)
	F.until_action(sim, me, Action.IDLE)
	ticks = F.play(sim, [SWEEP], [], 8)
	assert_not_null(F.first(ticks, T.HIT))
	assert_ne(foe.action, Action.IDLE)

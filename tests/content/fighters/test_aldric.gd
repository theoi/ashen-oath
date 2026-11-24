extends TestCase
## Aldric's kit in the sim: strings, Oathfire Lunge armour, Brand Rise launch + jump
## cancel, Oathkeeper's wider parry and ignited blade, Pyre of the Forsworn.

const F := preload("res://tests/sim/sim_fixtures.gd")
const Action := FighterState.Action
const T := SimEvent.Type
const ALDRIC := "res://content/fighters/aldric/aldric.tres"

var sim: Sim
var me: FighterState
var foe: FighterState


func _duel(distance: float, mine: FighterData = null, theirs: FighterData = null) -> void:
	var aldric: FighterData = load(ALDRIC)
	var cfg := F.config(2, aldric)
	cfg.slots[0].fighter = mine if mine != null else aldric
	cfg.slots[1].fighter = theirs if theirs != null else aldric
	sim = F.fighting_sim(cfg)
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


func test_light_string_chains_three_hits() -> void:
	_duel(1.3)
	var frames: Array = []
	for i in 40:
		frames.append(F.L if i % 6 < 2 else 0)
	var ticks := F.play(sim, frames, [], 60)
	assert_eq(_hits_by(ticks, &"aldric_l1").size(), 1)
	assert_eq(_hits_by(ticks, &"aldric_l2").size(), 1)
	assert_eq(_hits_by(ticks, &"aldric_l3").size(), 1)


func test_light_light_heavy_launches() -> void:
	_duel(1.3)
	var frames: Array = [F.L, 0, 0, 0, 0, 0, 0, 0, 0, F.L, 0, 0, 0, 0, 0, 0, 0, 0, F.H]
	var ticks := F.play(sim, frames, [], 50)
	assert_eq(_hits_by(ticks, &"aldric_llh").size(), 1, "launcher connects")
	var launch := F.first(ticks, T.LAUNCH)
	assert_not_null(launch)
	assert_eq(launch.target, 1)


func test_light_heavy_sweeps_into_knockdown() -> void:
	_duel(1.3)
	var ticks := F.play(sim, [F.L, 0, 0, 0, 0, 0, 0, 0, 0, F.H], [], 90)
	assert_eq(_hits_by(ticks, &"aldric_lh").size(), 1)
	assert_ne(F.tick_of(ticks, T.KNOCKDOWN), -1, "sweep knocks down")


func test_oathfire_lunge_armors_a_light_and_still_hits() -> void:
	_duel(3.5)
	var ticks := F.play(sim, [SimInput.ABILITY_1], [0, 0, F.L], 40)
	var armor := F.first(ticks, T.ARMOR)
	assert_not_null(armor, "the foe's light lands on the lunge's armour")
	assert_eq(armor.target, 0)
	assert_eq(me.action == Action.ATTACK or me.action == Action.IDLE, true, "Aldric was not interrupted")
	assert_eq(_hits_by(ticks, &"oathfire_lunge").size(), 1, "the lunge connects")


func test_oathfire_lunge_crosses_six_meters() -> void:
	_duel(6.0)
	var ticks := F.play(sim, [SimInput.ABILITY_1], [], 40)
	assert_eq(_hits_by(ticks, &"oathfire_lunge").size(), 1, "reaches a foe 6 m away")


func test_brand_rise_launches_and_jump_cancels_into_air_follow_up() -> void:
	_duel(1.3)
	var frames: Array = [SimInput.ABILITY_2] + F.held(0, 9) + [F.J] + F.held(0, 7) + [F.L]
	var ticks := F.play(sim, frames, [], 45)
	assert_eq(_hits_by(ticks, &"brand_rise").size(), 1)
	assert_not_null(F.first(ticks, T.LAUNCH))
	assert_ne(F.tick_of(ticks, T.JUMP), -1, "jump cancels Brand Rise on hit")
	assert_eq(_hits_by(ticks, &"aldric_air_l1").size(), 1, "air light follows the launch")


func test_brand_rise_cannot_jump_cancel_on_whiff() -> void:
	_duel(5.0)
	var ticks := F.play(sim, [SimInput.ABILITY_2] + F.held(0, 9) + [F.J], [], 16)
	assert_eq(F.tick_of(ticks, T.JUMP), -1)


## The foe's light hits on tick 13 (pressed on tick 8, startup 6). Aldric presses guard
## 7 ticks earlier: inside his 8-frame parry window, outside the default 6.
func _late_parry_ticks() -> Array[Array]:
	var mine: Array = F.held(0, 5) + F.held(F.G, 12)
	var theirs: Array = F.held(0, 7) + [F.L]
	return F.play(sim, mine, theirs, 20)


func test_oathkeeper_parry_window_is_eight_frames() -> void:
	_duel(1.3)
	var ticks := _late_parry_ticks()
	var parry := F.first(ticks, T.PARRY)
	assert_not_null(parry, "Aldric parries a hit 7 frames after the press")
	assert_eq(me.hp, me.max_hp)


func test_default_parry_window_misses_the_same_timing() -> void:
	var plain: FighterData = (load(ALDRIC) as FighterData).duplicate()
	plain.parry_window = 6
	plain.parry_buff = null
	_duel(1.3, plain)
	var ticks := _late_parry_ticks()
	assert_null(F.first(ticks, T.PARRY))


func test_oathkeeper_parry_ignites_the_next_hit() -> void:
	_duel(1.3)
	var ticks := _late_parry_ticks()
	assert_not_null(F.first(ticks, T.BUFF), "parry ignites the blade")
	F.until_action(sim, me, Action.IDLE)
	var hp_before := foe.hp
	var after := F.play(sim, [F.L], [], 10)
	var hit := _hits_by(after, &"aldric_l1")
	assert_eq(hit.size(), 1)
	assert_eq(hp_before - foe.hp, 35 * 130 / 100, "+30% on the next hit")
	assert_true(me.buffs.is_empty(), "the ignite is spent after one hit")


func test_pyre_is_invincible_through_startup_and_launches() -> void:
	_duel(1.4)
	me.soul = 10000
	var mine: Array = [SimInput.SUPER]
	var theirs: Array = F.held(0, 22) + [F.L]
	var ticks := F.play(sim, mine, theirs, 80)
	assert_eq(me.hp, me.max_hp, "the foe's light passes through the startup")
	var pillar_hit := false
	for events in ticks:
		for e: SimEvent in events:
			if e.type == T.HIT and e.source == 0 and e.target == 1 and (e.flags & SimEvent.FLAG_SUPER) != 0:
				pillar_hit = true
	assert_true(pillar_hit, "the flame pillar hits")
	assert_not_null(F.first(ticks, T.LAUNCH))
	assert_true(me.soul_points() < 50, "the super spent 100 Soul")


func test_bulwark_charge_staggers_on_hit() -> void:
	_duel(2.5)
	var ticks := F.play(sim, [SimInput.ABILITY_3], [], 22)
	assert_eq(_hits_by(ticks, &"bulwark_charge").size(), 1)
	assert_eq(foe.action, Action.HITSTUN)

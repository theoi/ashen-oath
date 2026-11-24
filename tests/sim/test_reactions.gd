extends TestCase
## Hit reactions: launches, juggle limit, air tech, knockdown, tech roll, get-up, OTG,
## ground bounce, wall splat, KO, Soul Burst, hazards.

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


func _start(slot: int, move_id: StringName) -> void:
	var data := sim.fighter_data[slot]
	sim.start_move(sim.fighter(slot), data.find_move(move_id))


func test_launcher_juggles_then_knockdown_without_tech() -> void:
	var ticks := F.play(sim, [SimInput.ABILITY_2], [], 8)
	assert_eq(F.tick_of(ticks, T.LAUNCH), 8)
	assert_eq(foe.action, Action.AIR_HITSTUN)
	var airtime := F.until_action(sim, foe, Action.KNOCKDOWN, 120)
	assert_true(airtime >= 8 + 50 and airtime <= 8 + 62, "launch airtime %d (incl. 8 hitstop)" % airtime)
	assert_eq(foe.action, Action.KNOCKDOWN)


func test_air_tech_after_hitstun_ends() -> void:
	F.play(sim, [SimInput.ABILITY_2], [], 8)
	F.hold(sim, 8 + 45)
	assert_eq(foe.stun, 0)
	assert_false(foe.grounded)
	var ticks := F.play(sim, [], [F.D], 1)
	assert_eq(F.tick_of(ticks, T.AIR_TECH), 1)
	assert_true(sim.is_invulnerable(foe))
	assert_eq(F.until_action(sim, foe, Action.LAND, 60) >= 0, true, "lands on its feet")


func test_no_air_tech_while_hitstun_lasts() -> void:
	F.play(sim, [SimInput.ABILITY_2], [], 8)
	var ticks := F.play(sim, [], [0, F.D, 0, F.D, 0, F.D], 20)
	assert_eq(F.tick_of(ticks, T.AIR_TECH), -1)


func _airborne_victim(juggle_used: int) -> void:
	foe.action = Action.AIR_HITSTUN
	foe.grounded = false
	foe.pos.y = Fx.m(1.0)
	foe.vel = Vector3i.ZERO
	foe.stun = 40
	foe.juggle_used = juggle_used
	foe.combo_hits = 3


func test_airborne_hits_cost_juggle_points_and_the_limit_flips_out() -> void:
	_airborne_victim(0)
	F.play(sim, [F.L], [], 6)
	assert_eq(foe.juggle_used, 1)
	assert_eq(foe.action, Action.AIR_HITSTUN, "juggled")
	sim = F.duel()
	me = sim.fighter(0)
	foe = sim.fighter(1)
	_airborne_victim(5)
	var ticks := F.play(sim, [F.L], [], 6)
	assert_eq(F.tick_of(ticks, T.HIT), 6)
	assert_eq(F.tick_of(ticks, T.JUGGLE_LIMIT), 6)
	assert_eq(foe.action, Action.TECH)
	assert_true(sim.is_invulnerable(foe), "flips out invincible")
	assert_true(F.until_action(sim, foe, Action.LAND, 90) >= 0, "lands on its feet")
	assert_false(sim.is_invulnerable(foe))


func test_knockdown_tech_roll_when_dodge_pressed_just_before_landing() -> void:
	_start(0, &"sweep")
	var alternate: Array = []
	for i in 60:
		alternate.append(F.D if i > 15 and i % 2 == 0 else 0)
	var ticks := F.play(sim, [], alternate)
	assert_ne(F.tick_of(ticks, T.TECH_ROLL), -1)
	assert_eq(F.tick_of(ticks, T.KNOCKDOWN), -1)


func test_knockdown_40_frames_then_stand_with_invincibility() -> void:
	_start(0, &"sweep")
	assert_true(F.until_action(sim, foe, Action.KNOCKDOWN, 80) > 0)
	var down := F.until_action(sim, foe, Action.GETUP, 80)
	assert_eq(down, 40)
	assert_eq(foe.action_variant, 0, "stands in place")
	var invulnerable := 0
	for _i in 20:
		if sim.is_invulnerable(foe):
			invulnerable += 1
		F.step(sim)
	assert_eq(invulnerable, 11, "frames 2-12 (frame 1 already ran)")
	F.step(sim)
	assert_eq(foe.action, Action.IDLE)


func test_get_up_roll_and_get_up_attack() -> void:
	_start(0, &"sweep")
	F.until_action(sim, foe, Action.KNOCKDOWN, 80)
	var ticks := F.play(sim, [], F.held(F.D, 41))
	assert_eq(foe.action, Action.GETUP)
	assert_eq(foe.action_variant, 1, "roll")
	assert_ne(F.tick_of(ticks, T.GET_UP), -1)
	sim = F.duel()
	me = sim.fighter(0)
	foe = sim.fighter(1)
	_start(0, &"sweep")
	F.until_action(sim, foe, Action.KNOCKDOWN, 80)
	F.play(sim, [], F.held(F.L, 41))
	assert_eq(foe.action, Action.ATTACK)
	assert_eq(sim.current_move(foe).id, &"getup_attack")
	assert_true(sim.is_invulnerable(foe))


func test_only_otg_moves_hit_downed_fighters() -> void:
	_start(0, &"sweep")
	F.until_action(sim, foe, Action.KNOCKDOWN, 80)
	F.until_action(sim, me, Action.IDLE, 80)
	F.place(sim, 0, 0.0, Fx.to_m(foe.pos.z) - 1.0, 0)
	var ticks := F.play(sim, [F.L], [], 8)
	assert_eq(F.tick_of(ticks, T.HIT), -1, "plain light whiffs on a downed fighter")
	var data := F.test_fighter().duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as FighterData
	data.move_by_id(&"light_1").hitboxes[0].hit.otg = true
	data.move_by_id(&"light_1").hitboxes[0].offset.y = 0.3
	sim = F.duel(1.2, 2, data)
	me = sim.fighter(0)
	foe = sim.fighter(1)
	_start(0, &"sweep")
	F.until_action(sim, foe, Action.KNOCKDOWN, 80)
	F.until_action(sim, me, Action.IDLE, 80)
	F.place(sim, 0, 0.0, Fx.to_m(foe.pos.z) - 1.0, 0)
	ticks = F.play(sim, [F.L], [], 8)
	assert_eq(F.tick_of(ticks, T.HIT), 6, "OTG light hits")
	assert_true(F.until_action(sim, foe, Action.KNOCKDOWN, 60) >= 0, "an OTG hit keeps the victim down")


func test_air_heavy_spikes_into_a_ground_bounce() -> void:
	_airborne_victim(0)
	foe.pos.y = Fx.m(0.6)
	me.grounded = false
	me.pos.y = Fx.m(0.9)
	me.action = Action.AIR
	me.vel = Vector3i.ZERO
	var ticks := F.play(sim, [F.H], [], 40)
	assert_eq(F.tick_of(ticks, T.HIT), 12)
	var bounce := F.first(ticks, T.LAUNCH)
	assert_not_null(bounce)
	assert_eq(bounce.id, &"ground_bounce")


func test_heavy_knockback_into_a_wall_splats_once_per_combo() -> void:
	F.place(sim, 0, 0.0, 7.0, 0)
	F.place(sim, 1, 0.0, 8.3, Fx.HALF_TURN)
	_start(0, &"heavy_2")
	var ticks := F.play(sim, [], [], 50)
	assert_ne(F.tick_of(ticks, T.WALL_SPLAT), -1)
	var splat_tick := F.tick_of(ticks, T.WALL_SPLAT)
	assert_true(foe.wall_splat_used)
	assert_almost_eq(Fx.to_m(foe.pos.z), 10.0 - 0.45, 0.01)
	# A second wall_splat hit in the same combo only knocks back.
	assert_true(foe.in_hitstun() or foe.action == Action.KNOCKDOWN, "still in the combo (tick %d)" % splat_tick)
	F.place(sim, 0, 0.0, Fx.to_m(foe.pos.z) - 1.3, 0)
	foe.action = Action.HITSTUN
	foe.stun = 60
	_start(0, &"heavy_2")
	ticks = F.play(sim, [], [], 40)
	assert_eq(F.tick_of(ticks, T.WALL_SPLAT), -1)


func test_ko_ends_the_round() -> void:
	foe.hp = 20
	var ticks := F.play(sim, [F.L], [], 6)
	assert_eq(F.tick_of(ticks, T.KO), 6)
	assert_eq(F.tick_of(ticks, T.ROUND_END), 6)
	assert_true(foe.ko)
	assert_eq(sim.state.round_winner, 0)


func test_soul_burst_breaks_a_combo_and_pushes_enemies_away() -> void:
	foe.soul = 5000
	F.play(sim, [F.L], [], 6)
	assert_eq(foe.action, Action.HITSTUN)
	var ticks := F.play(sim, [], [0, 0, 0, 0, 0, SimInput.SUPER], 7)
	assert_eq(F.tick_of(ticks, T.BURST), 6, "after hitstop")
	assert_eq(foe.action, Action.BURST)
	assert_eq(foe.soul, 35 * 6, "50 spent, damage taken still counted")
	assert_true(sim.is_invulnerable(foe))
	assert_eq(me.action, Action.RECOVER)
	var gap := Fx.dist_xz(me.pos, foe.pos)
	F.hold(sim, 12)
	assert_true(Fx.dist_xz(me.pos, foe.pos) > gap + Fx.m(3.0), "pushed about 4 m")
	assert_eq(foe.combo_hits, 0)


func test_soul_burst_needs_50_soul_and_not_in_guard_break() -> void:
	foe.soul = 4700
	F.play(sim, [F.L], [], 6)
	var ticks := F.play(sim, [], [0, 0, 0, 0, 0, SimInput.SUPER], 7)
	assert_eq(F.tick_of(ticks, T.BURST), -1)
	sim = F.duel()
	foe = sim.fighter(1)
	foe.soul = 10000
	foe.action = Action.GUARD_BREAK
	foe.stun = 60
	ticks = F.play(sim, [], [SimInput.SUPER], 3)
	assert_eq(F.tick_of(ticks, T.BURST), -1)


func test_hazard_hits_once_per_activation_on_its_schedule() -> void:
	var arena := F.arena()
	var vent := HazardData.new()
	vent.id = &"vent"
	vent.center = Vector2(0.0, 3.0)
	vent.radius = 1.0
	vent.period = 200
	vent.offset = 1
	vent.warn = 60
	vent.active = 45
	var hit := HitData.new()
	hit.damage = 60
	hit.reaction = HitData.Reaction.LAUNCH
	hit.launch_height = 0.8
	hit.unblockable = true
	vent.hit = hit
	arena.hazards.append(vent)
	var cfg := F.config(2, F.test_fighter(), arena)
	sim = F.fighting_sim(cfg)
	F.place(sim, 1, 0.0, 3.0, 0)
	var ticks := F.play(sim, [], [], 150)
	assert_eq(F.count_of(ticks, T.HAZARD_ACTIVE), 1)
	assert_eq(F.count_of(ticks, T.HIT), 1)
	var hazard_hit := F.first(ticks, T.HIT)
	assert_true(hazard_hit.flags & SimEvent.FLAG_HAZARD)
	assert_eq(hazard_hit.source, -1)
	assert_eq(sim.state.round_tick - 149 + F.tick_of(ticks, T.HIT) - 1, 61, "hits on the first active frame")
	assert_eq(sim.fighter(1).hp, sim.fighter(1).max_hp - 60)

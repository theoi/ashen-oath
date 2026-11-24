extends TestCase
## Round flow: intro, timer, time-up decisions, match end.

const F := preload("res://tests/sim/sim_fixtures.gd")
const Phase := SimState.Phase


func test_intro_then_fight_with_inputs_ignored_during_intro() -> void:
	var sim := Sim.new(F.config(2))
	var events: Array[SimEvent] = []
	for _i in 90:
		events.append_array(F.step(sim, SimInput.make(0, 127, 0)))
	assert_eq(sim.state.phase, Phase.INTRO)
	assert_eq(sim.fighter(0).vel.x, 0, "no movement during the intro")
	var fight := F.step(sim, SimInput.make(0, 127, 0))
	assert_eq(sim.state.phase, Phase.FIGHT)
	assert_true(F.has_event(fight, SimEvent.Type.FIGHT))
	assert_true(sim.fighter(0).vel.x > 0, "moves on the first fight tick")


func test_time_up_awards_the_round_by_hp_percent_and_match_ends() -> void:
	var cfg := F.config(2)
	cfg.round_seconds = 2
	var sim := F.fighting_sim(cfg)
	assert_eq(sim.seconds_left(), 2)
	sim.fighter(1).hp -= 100
	# fighting_sim already ran the first fight tick.
	var events := F.hold(sim, 118)
	assert_eq(sim.state.phase, Phase.FIGHT)
	events = F.step(sim)
	assert_true(F.has_event(events, SimEvent.Type.TIME_UP))
	assert_eq(sim.state.phase, Phase.ROUND_END)
	assert_eq(sim.state.round_winner, 0)
	assert_eq(sim.state.team_wins[0], 1)
	F.hold(sim, 151)
	assert_eq(sim.state.round_number, 2)
	assert_eq(sim.fighter(1).hp, sim.fighter(1).max_hp, "HP resets each round")
	F.skip_intro(sim)
	sim.fighter(1).hp -= 1
	F.hold(sim, 120)
	assert_eq(sim.state.winner_team, 0)
	F.hold(sim, 151)
	assert_true(sim.is_over())


func test_equal_hp_at_time_up_is_a_draw() -> void:
	var cfg := F.config(2)
	cfg.round_seconds = 1
	var sim := F.fighting_sim(cfg)
	F.hold(sim, 60)
	assert_eq(sim.state.phase, Phase.ROUND_END)
	assert_eq(sim.state.round_winner, -1)
	assert_eq(sim.state.team_wins[0] + sim.state.team_wins[1], 0)


func test_soul_carries_over_between_rounds() -> void:
	var cfg := F.config(2)
	cfg.round_seconds = 1
	cfg.slots[1].start_soul = 50
	var sim := F.fighting_sim(cfg)
	assert_eq(sim.fighter(1).soul_points(), 50)
	F.hold(sim, 60 + 151)
	assert_eq(sim.state.round_number, 2)
	assert_eq(sim.fighter(1).soul_points(), 50)

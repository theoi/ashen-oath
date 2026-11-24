extends TestCase
## SimHud on a real sim with a skill-kit fighter: dash pips, follow-ups, cooldown totals,
## Burst on the dash button.

const F := preload("res://tests/sim/sim_fixtures.gd")


func _skill_kit() -> FighterData:
	var data: FighterData = (load(MatchSetup.FALLBACK_FIGHTER) as FighterData).duplicate()
	data.dash = DashData.new()
	return data


func test_dash_charges_and_recharge_come_from_the_sim() -> void:
	var sim := F.fighting_sim(F.config(2, _skill_kit()))
	var hud := SimHud.fill(sim, HudState.new())
	var player := hud.fighters[0]
	assert_true(player.burst_on_dash)
	assert_eq(player.dash_max, 2)
	assert_eq(player.dash_charges, 2)
	var f := sim.fighter(0)
	f.dash_charges = 1
	f.dash_recharge = 150
	SimHud.fill(sim, hud)
	assert_eq(player.dash_charges, 1)
	assert_almost_eq(player.dash_recharge, 0.5, 0.001, "half of the 300-frame recharge is done")


func test_tuned_dash_charges_set_the_pip_count() -> void:
	var cfg := F.config(2, _skill_kit())
	cfg.dash_charges = 3
	var hud := SimHud.fill(F.fighting_sim(cfg), HudState.new())
	assert_eq(hud.fighters[0].dash_max, 3)


func test_follow_up_and_scaled_cooldowns() -> void:
	var data := _skill_kit()
	var sim := F.fighting_sim(F.config(2, data))
	var f := sim.fighter(0)
	var follow_index := -1
	for i in sim.fighter_data[0].moves.size():
		if sim.fighter_data[0].moves[i].id == data.abilities[1]:
			follow_index = i
	f.skill_next[0] = follow_index
	f.skill_window[0] = 90
	f.cooldowns[2] = 120
	f.cooldown_totals[2] = 240
	var hud := SimHud.fill(sim, HudState.new())
	var skills := hud.fighters[0].skills
	assert_eq(skills[0].follow_name, String(data.abilities[1]).capitalize(), "the slot shows what it casts now")
	assert_almost_eq(skills[0].follow_left, 1.5, 0.001)
	assert_true(skills[0].ready(), "a waiting follow-up is ready")
	assert_almost_eq(skills[2].cooldown_left, 2.0, 0.001)
	assert_almost_eq(skills[2].cooldown_total, 4.0, 0.001, "the total the sim started (move speed applied)")
	assert_eq(hud.fighters[1].skills[0].follow_name, "", "only the player's bar tracks follow-ups")


func test_burst_window_includes_grabs_for_skill_kit_fighters() -> void:
	var sim := F.fighting_sim(F.config(2, _skill_kit()))
	sim.fighter(0).action = FighterState.Action.GRABBED
	var hud := SimHud.fill(sim, HudState.new())
	assert_true(hud.fighters[0].burst_window, "the dash bursts out of grabs")
	assert_false(hud.fighters[0].skills[0].usable)

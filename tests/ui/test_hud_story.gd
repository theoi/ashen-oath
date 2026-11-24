extends TestCase
## Story and boss HUD: wave counter, free wave slots hidden, slots that change fighters,
## compact bars for up to seven wave enemies, the boss bar with stagger and channel-break
## gauges, and skill charge pips.

const F := preload("res://tests/sim/sim_fixtures.gd")
const K := preload("res://tests/sim/test_skill_kit.gd")
const W := preload("res://tests/sim/test_waves.gd")

var hud: Hud


func before_each() -> void:
	hud = add_child_autofree(Hud.new())


## Two grunts, then a brute that has to reuse a grunt's slot (two wave slots).
func _wave_sim(grunt: FighterData, brute: FighterData) -> Sim:
	var cfg := F.config(1, K.kit())
	var waves: Array[WaveData] = [W._wave([W._entry(grunt, 2)], 0), W._wave([W._entry(brute, 1)])]
	cfg.waves = waves
	cfg.wave_slots = 2
	return F.fighting_sim(cfg)


func _named(id: StringName, display: String) -> FighterData:
	var data := F.fighter()
	data.id = id
	data.display_name = display
	return data


func test_waves_fill_slots_and_the_counter_from_the_sim() -> void:
	var sim := _wave_sim(_named(&"grunt", "Hollowed"), _named(&"brute", "Hollowed Brute"))
	var state := SimHud.fill(sim, HudState.new())
	assert_eq(state.fighters.size(), 3)
	assert_eq(state.wave_count, 2)
	assert_eq(state.wave, 1)
	assert_false(state.fighters[0].wave_member)
	assert_true(state.fighters[1].wave_member)
	assert_true(state.fighters[2].active)
	assert_eq(state.fighters[1].name, "Hollowed")

	sim._ko(sim.fighter(1))
	sim._ko(sim.fighter(2))
	W._until(sim, SimEvent.Type.SPAWN)
	SimHud.fill(sim, state)
	assert_eq(state.wave, 2, "second wave started")
	assert_true(state.fighters[1].active)
	assert_eq(state.fighters[1].name, "Hollowed Brute", "a reused slot shows the fighter it runs now")
	assert_false(state.fighters[2].active, "the freed slot nobody took is hidden")


func test_wave_start_and_breaks_translate_to_match_events() -> void:
	var sim := _wave_sim(F.fighter(), F.fighter())
	var event := SimEvent.new()
	event.type = SimEvent.Type.WAVE_START
	event.amount = 1
	assert_eq(SimHud.translate(sim, event), {"type": MatchEvents.WAVE, "wave": 2, "waves": 2})
	event.type = SimEvent.Type.CHANNEL_BREAK
	event.source = 0
	event.target = 3
	assert_eq(SimHud.translate(sim, event)["slot"], 3)
	event.type = SimEvent.Type.STAGGER_BREAK
	assert_eq(SimHud.translate(sim, event), {"type": MatchEvents.STAGGER_BREAK, "slot": 3})


func test_skill_charges_and_boss_gauges_come_from_the_sim() -> void:
	var data := K.kit()
	data.moves[5].charges = 2
	data.moves[5].recharge_frames = 100
	var sim := F.duel(8.0, 2, data)
	var boss := sim.fighter(1)
	boss.stagger_max = 600
	boss.stagger = 450
	boss.channel = 30
	boss.channel_max = 120
	sim.fighter(0).skill_charges[2] = 1
	sim.fighter(0).cooldowns[2] = 50
	var state := SimHud.fill(sim, HudState.new())
	var skill := state.fighters[0].skills[2]
	assert_eq(skill.max_charges, 2)
	assert_eq(skill.charges, 1)
	assert_true(skill.ready(), "a charge is left while the other refills")
	assert_eq(state.fighters[0].skills[0].max_charges, 0, "plain skills have no pips")
	assert_true(state.fighters[1].is_boss())
	assert_almost_eq(state.fighters[1].stagger, 450.0, 0.001)
	assert_almost_eq(state.fighters[1].channel_max, 120.0, 0.001)


func test_seven_wave_enemies_get_compact_bars_and_free_slots_hide() -> void:
	var state := _story_state(7)
	state.fighters[5].active = false
	hud.apply(state)
	assert_null(hud.boss_bar())
	var right := hud.plate_for(0).get_parent() != hud.mob_for(1).get_parent()
	assert_true(right, "enemies on the other side")
	for slot in range(1, 8):
		assert_not_null(hud.mob_for(slot))
		assert_eq(hud.mob_for(slot).visible, slot != 5)
	assert_true(hud.mob_for(1).get_combined_minimum_size().y < hud.plate_for(0).get_combined_minimum_size().y * 0.5)
	var column := hud.mob_for(1).get_parent() as Control
	await wait_frames(1)
	assert_true(column.get_combined_minimum_size().y < 300.0, "seven bars fit under the timer")
	assert_eq(hud.wave_text(), "Wave 2 / 3")
	state.fighters[2].health = 25.0
	hud.apply(state)
	assert_almost_eq(hud.mob_for(2).health_shown(), 0.25, 0.001)


func test_boss_gets_the_big_bar_with_stagger_and_channel_gauge() -> void:
	var state := _story_state(4)
	var boss := state.fighters[4]
	boss.name = "Gorrath"
	boss.stagger_max = 600.0
	boss.stagger = 150.0
	hud.apply(state)
	var bar := hud.boss_bar()
	assert_not_null(bar)
	assert_eq(bar.slot, 4)
	assert_false(hud.mob_for(4).visible, "the boss is not listed twice")
	assert_almost_eq(bar.stagger_shown(), 0.25, 0.001)
	assert_eq(bar.channel_shown(), 0.0, "no gauge until a channel starts")
	boss.channel_max = 200.0
	boss.channel = 50.0
	hud.apply(state)
	assert_almost_eq(bar.channel_shown(), 0.25, 0.001)
	boss.staggered = true
	hud.apply(state)
	assert_eq(bar.stagger_shown(), 0.0)


func test_wave_announcements_and_quiet_mob_kos() -> void:
	var state := _story_state(3)
	state.fighters[3].stagger_max = 300.0
	state.fighters[3].name = "Oath-Shade"
	hud.apply(state)
	hud.on_event({"type": MatchEvents.WAVE, "wave": 3, "waves": 3})
	hud.on_event({"type": MatchEvents.KO, "slot": 1})
	hud.on_event({"type": MatchEvents.KO, "slot": 3})
	assert_eq(hud.announced, PackedStringArray(["Wave 3", "KO"]), "mob KOs are not announced; the boss's is")


func test_charged_skill_with_a_charge_left_stays_lit() -> void:
	var state := _story_state(1)
	var skill := state.fighters[0].skills[0]
	skill.max_charges = 2
	skill.charges = 1
	skill.cooldown_left = 3.0
	skill.cooldown_total = 5.0
	hud.apply(state)
	assert_true(hud.skill_bar().slot(0).is_lit())
	skill.charges = 0
	hud.apply(state)
	assert_false(hud.skill_bar().slot(0).is_lit())


## The player in slot 0 and `mobs` wave enemies after them, wave 2 of 3.
func _story_state(mobs: int) -> HudState:
	var state := HudState.new()
	state.wave = 2
	state.wave_count = 3
	state.seconds_left = -1.0
	for slot in mobs + 1:
		var fighter := HudState.Fighter.new()
		fighter.slot = slot
		fighter.name = "Aldric Vane" if slot == 0 else "Hollowed"
		fighter.team = 0 if slot == 0 else 1
		fighter.is_player = slot == 0
		fighter.wave_member = slot > 0
		fighter.max_health = 100.0
		fighter.health = 100.0
		if slot == 0:
			var skill := HudState.Skill.new()
			skill.name = "Oathfire Lunge"
			skill.action = DefaultBindings.ability_action(0)
			fighter.skills.append(skill)
		state.fighters.append(fighter)
	return state

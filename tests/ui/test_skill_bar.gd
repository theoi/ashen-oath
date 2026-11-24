extends TestCase
## The skill bar: chain / combo follow-ups, charge perfect zone, dash charges, Burst on dash.

var bar: SkillBar


func before_each() -> void:
	bar = add_child_autofree(SkillBar.new())


func test_follow_up_swaps_the_slot_and_lights_it_during_the_cooldown() -> void:
	var fighter := _fighter(["Flame Rend"])
	var skill := fighter.skills[0]
	skill.cooldown_left = 8.0
	skill.cooldown_total = 8.0
	bar.apply(fighter)
	assert_false(bar.slot_ready(0))
	assert_eq(bar.slot(0).shown_name(), "Flame Rend")
	skill.follow_name = "Rend Ignition"
	skill.follow_left = 2.0
	skill.follow_total = 3.0
	bar.apply(fighter)
	assert_true(bar.slot_ready(0), "the chain follow-up is ready while the root skill is not")
	assert_eq(bar.slot(0).shown_name(), "Rend Ignition", "the slot shows the follow-up")


func test_ready_transition_signals_once() -> void:
	var fighter := _fighter(["Oathfire Lunge"])
	fighter.skills[0].cooldown_left = 0.5
	bar.apply(fighter)
	var seen := [0]
	bar.slot(0).became_ready.connect(func() -> void: seen[0] += 1)
	fighter.skills[0].cooldown_left = 0.0
	bar.apply(fighter)
	bar.apply(fighter)
	assert_eq(seen[0], 1)


func test_unusable_slots_are_not_lit() -> void:
	var fighter := _fighter(["Oathfire Lunge"])
	fighter.skills[0].usable = false
	bar.apply(fighter)
	assert_false(bar.slot_ready(0))


func test_dash_pips_show_and_burst_moves_to_the_dash_button() -> void:
	var fighter := _fighter(["A", "B", "C", "D", "E", "F"])
	fighter.dash_max = 2
	fighter.dash_charges = 1
	fighter.dash_recharge = 0.4
	fighter.dash_action = DefaultBindings.DODGE
	fighter.burst_on_dash = true
	fighter.soul = 60.0
	bar.apply(fighter)
	assert_eq(bar.slot_count(), 6)
	assert_eq(bar.prompts().size(), 8, "six skills, dash and awakening")
	assert_eq(bar.dash_text(), "DASH")
	assert_false(bar.burst_ready())
	fighter.burst_window = true
	bar.apply(fighter)
	assert_eq(bar.dash_text(), "BURST", "in hitstun the dash button bursts")
	assert_true(bar.burst_ready())
	assert_ne(bar.awakening_text(), "BURST", "the awakening button does not burst for skill-kit fighters")
	assert_false(bar.awakening_ready())


func test_charge_bar_shows_only_while_charging() -> void:
	var fighter := _fighter(["Verdict"])
	var skill := fighter.skills[0]
	skill.type = HudState.Skill.Type.CHARGE
	skill.charge_levels = PackedFloat32Array([0.3, 0.7])
	skill.perfect_from = 0.7
	skill.perfect_to = 0.9
	bar.apply(fighter)
	assert_eq(bar.slot(0)._charge_bar.modulate.a, 0.0)
	skill.charging = true
	skill.charge = 0.8
	bar.apply(fighter)
	assert_eq(bar.slot(0)._charge_bar.modulate.a, 1.0)


func _fighter(names: Array) -> HudState.Fighter:
	var fighter := HudState.Fighter.new()
	fighter.is_player = true
	fighter.awakening_action = DefaultBindings.SUPER
	for i in names.size():
		var skill := HudState.Skill.new()
		skill.name = names[i]
		skill.action = DefaultBindings.ability_action(i)
		fighter.skills.append(skill)
	return fighter

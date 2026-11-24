extends TestCase
## The move list is generated from each fighter's data.

const FIGHTERS: PackedStringArray = ["aldric", "morrigan", "gorrath", "hollowed", "oath_shade"]


func test_move_list_generates_for_every_fighter() -> void:
	var rules: CombatRules = load(MatchSetup.RULES)
	for id in FIGHTERS:
		var data: FighterData = load("res://content/fighters/%s/%s.tres" % [id, id])
		var entries := MoveList.build(data, rules)
		var names := PackedStringArray()
		for entry in entries:
			names.append(entry.name)
			assert_has(MoveList.sections(), entry.section)
			for action in entry.inputs:
				assert_false(InputGlyphs.parts(action, ActiveDevice.Scheme.GAMEPAD, 0).is_empty(), "%s: %s input" % [id, entry.name])
		for universal: String in ["Basic attack", "Soul Burst", "Move", "Aim", "Lock-on"]:
			assert_has(names, universal, "%s lists %s" % [id, universal])
		assert_true("Dash" in names or "Dodge roll" in names, "%s lists its dash or roll" % id)
		for entry in entries:
			for action in entry.inputs:
				if action != InputGlyphs.MOVE and action != InputGlyphs.AIM:
					assert_true(InputMap.has_action(action), "%s: %s uses a bound action (%s)" % [id, entry.name, action])
		var abilities := entries.filter(func(e: MoveList.Entry) -> bool: return e.section == MoveList.ABILITIES)
		assert_eq(abilities.size(), data.abilities.size(), "%s: one entry per ability" % id)


func test_entries_come_from_the_data() -> void:
	var data: FighterData = load("res://content/fighters/aldric/aldric.tres")
	var entries := MoveList.build(data, load(MatchSetup.RULES) as CombatRules)
	var by_name := {}
	for entry in entries:
		if not by_name.has(entry.name):
			by_name[entry.name] = entry
	var basic: MoveList.Entry = by_name.get("Basic attack")
	var chain := 0
	var step := data.move_by_id(data.light)
	var seen: Array[StringName] = []
	while step != null and chain < MoveList.MAX_CHAIN and not seen.has(step.id):
		seen.append(step.id)
		chain += 1
		step = data.move_by_id(step.next_light) if not step.next_light.is_empty() else null
	if chain > 1:
		assert_true(basic.detail.contains("%d-hit chain" % chain), basic.detail)
	var lunge: MoveList.Entry = by_name.get("Oathfire Lunge")
	assert_not_null(lunge)
	if lunge != null:
		var move := data.move_by_id(data.abilities[0])
		assert_true(lunge.detail.contains("%s s cooldown" % String.num(move.cooldown / 60.0, 1).trim_suffix(".0")), lunge.detail)
		assert_eq(lunge.inputs, [DefaultBindings.SKILL_1] as Array[StringName])
		assert_has(MoveList.SKILL_TYPES, lunge.context, "every skill shows its type")


func test_skill_types_come_from_the_move_data() -> void:
	var move := MoveData.new()
	assert_eq(MoveList.skill_type(move), "Tap")
	move.chargeable = true
	assert_eq(MoveList.skill_type(move), "Charge")
	move.chargeable = false
	move.aim = MoveData.Aim.DASH_TO
	assert_eq(MoveList.skill_type(move), "Dash-strike")
	if &"skill_type" in move:
		move.set(&"skill_type", MoveList.SKILL_TYPES.find("Stance"))
		assert_eq(MoveList.skill_type(move), "Stance", "the declared type wins")


func test_any_number_of_ability_slots_is_listed() -> void:
	var data: FighterData = (load("res://content/fighters/aldric/aldric.tres") as FighterData).duplicate()
	var abilities := data.abilities.slice(0, 3)
	abilities.append_array(data.abilities.slice(0, 3))
	data.abilities = abilities
	var entries := MoveList.build(data, load(MatchSetup.RULES) as CombatRules)
	var inputs: Array[StringName] = []
	for entry in entries:
		if entry.section == MoveList.ABILITIES:
			inputs.append_array(entry.inputs)
	assert_eq(inputs.size(), 6)
	for i in inputs.size():
		assert_eq(inputs[i], DefaultBindings.ability_action(i))


func test_screen_focuses_a_row_for_gamepad_scrolling() -> void:
	var stack: ScreenStack = add_child_autofree(ScreenStack.new())
	GameFlow.move_list_fighter = &"morrigan"
	stack.set_screens([&"move_list"])
	await wait_frames(1)
	var focus := host.get_viewport().gui_get_focus_owner()
	assert_not_null(focus, "a row has focus so a pad can scroll")
	assert_true(stack.current_screen().is_ancestor_of(focus))

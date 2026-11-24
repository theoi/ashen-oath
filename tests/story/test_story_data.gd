extends TestCase
## Act 1 content: the five fights of design §5 with their rules, and scenes that the player
## can actually show (known arenas, speakers, shots, props; 3–8 lines each).

const STORY_FIGHTERS: Array[StringName] = [&"hollowed", &"oath_shade"]

var story: StoryData


func before_each() -> void:
	story = StoryDirector.load_story()


func test_act_order_is_scene_first_and_last_with_five_fights() -> void:
	var ids: Array[StringName] = []
	for s in story.steps:
		ids.append(s.id)
	assert_eq(ids, [&"prologue", &"fight_squire", &"the_dead_stir", &"fight_two_hollowed", &"the_grave_witch",
			&"fight_morrigan", &"the_road_below", &"the_chainbound", &"fight_gorrath", &"what_the_fire_left",
			&"fight_oath_shade", &"epilogue"] as Array[StringName])
	assert_eq(story.fights().size(), 5)
	var unique := {}
	for s in story.steps:
		assert_false(s.title.is_empty(), "%s has a chapter title" % s.id)
		unique[s.id] = true
	assert_eq(unique.size(), story.steps.size(), "step ids are unique")
	for s in story.steps:
		assert_eq(s.resource_path, "res://content/story/act1/%s.tres" % s.id, "%s lives in its own file" % s.id)


func test_fights_match_the_design() -> void:
	var f := story.fights()
	# [opponents, arena, rounds_to_win, ai_cap, opponent soul]
	var expected: Array[Array] = [
		[[&"hollowed"], &"ashen_chapel", 1, MatchConfig.Difficulty.EASY, []],
		[[&"hollowed", &"hollowed"], &"ashen_chapel", 1, -1, []],
		[[&"morrigan"], &"ashen_chapel_night", 2, -1, []],
		[[&"gorrath"], &"drowned_crypt", 2, -1, []],
		[[&"oath_shade"], &"drowned_crypt_depths", 2, -1, [50]],
	]
	for i in expected.size():
		var e: Array = expected[i]
		assert_eq(f[i].player, &"aldric", "Aldric is the story protagonist")
		assert_eq(Array(f[i].opponents), e[0], "fight %d opponents" % (i + 1))
		assert_eq(f[i].arena, e[1], "fight %d arena" % (i + 1))
		assert_eq(f[i].rounds_to_win, e[2], "fight %d format" % (i + 1))
		assert_eq(f[i].ai_cap, e[3], "fight %d AI cap" % (i + 1))
		assert_eq(Array(f[i].opponent_soul), e[4], "fight %d starting Soul" % (i + 1))
		assert_false(f[i].opponent_name.is_empty())
	assert_eq(Array(f[4].opponent_ai_profiles), [&"oath_shade"], "the Shade plays the aggressive profile")
	assert_not_null(AiProfile.by_id(&"oath_shade"))
	assert_eq(AiProfile.by_id(&"oath_shade").resource_path, AiProfile.PROFILE_DIR + "oath_shade.tres")
	assert_eq(Array(f[2].unlocks), [&"morrigan"], "Morrigan unlocks after fight 3")
	assert_eq(Array(f[3].unlocks), [&"gorrath"], "Gorrath unlocks after fight 4")
	for i: int in [0, 1, 4]:
		assert_true(f[i].unlocks.is_empty())


func test_fight_one_teaches_the_basics_and_fight_two_the_kit() -> void:
	var fights := story.fights()
	var expected: Array[Array] = [
		[StoryPrompt.Goal.MOVE, StoryPrompt.Goal.LIGHT_STRING, StoryPrompt.Goal.GUARD, StoryPrompt.Goal.PARRY,
				StoryPrompt.Goal.DODGE, StoryPrompt.Goal.GRAB, StoryPrompt.Goal.LOCK_ON, StoryPrompt.Goal.NONE],
		[StoryPrompt.Goal.TARGET, StoryPrompt.Goal.ABILITY, StoryPrompt.Goal.ABILITY, StoryPrompt.Goal.ABILITY,
				StoryPrompt.Goal.SUPER, StoryPrompt.Goal.BURST],
	]
	for f in 2:
		var goals: Array = []
		for prompt in fights[f].prompts:
			goals.append(prompt.goal)
			assert_false(prompt.title.is_empty())
			assert_true(prompt.text.length() <= 70, "%s is short (%d chars)" % [prompt.title, prompt.text.length()])
			assert_true(prompt.goal == StoryPrompt.Goal.NONE or not FightPrompts.hint_for(prompt).is_empty(), "%s shows its buttons" % prompt.title)
			for action in prompt.actions:
				assert_true(action == &"move" or InputMap.has_action(action), "%s is an input action" % action)
		assert_eq(goals, expected[f], "fight %d tips" % (f + 1))
	var kit := fights[1].prompts
	assert_eq([kit[1].ability_slot, kit[2].ability_slot, kit[3].ability_slot], [0, 1, 2], "each ability with its own button")
	assert_eq(Array(kit[1].actions), [DefaultBindings.ABILITY_1])
	assert_eq(kit[4].trigger, StoryPrompt.Trigger.SOUL_FULL, "the super tip waits for full Soul")
	assert_eq(kit[5].trigger, StoryPrompt.Trigger.IN_COMBO, "the burst tip waits for a combo")
	for i in 4:
		assert_eq(kit[i].trigger, StoryPrompt.Trigger.IN_ORDER)
	for i in range(3):
		assert_eq(kit[i + 1].title, Roster.ability_names(&"aldric")[i], "ability tips use Aldric's ability names")


func test_scenes_are_playable() -> void:
	var arena_ids: Array[StringName] = []
	for entry in Roster.ARENAS:
		arena_ids.append(entry["id"])
	for s in story.steps:
		var scene := s as StoryScene
		if scene == null:
			continue
		assert_true(scene.lines.size() >= 3 and scene.lines.size() <= 8, "%s has 3-8 lines (%d)" % [scene.id, scene.lines.size()])
		assert_has(arena_ids, scene.arena, "%s arena" % scene.id)
		assert_false(scene.shots.is_empty(), "%s has a camera" % scene.id)
		for line in scene.lines:
			assert_false(line.text.is_empty(), "%s: empty line" % scene.id)
			assert_true(line.shot < scene.shots.size(), "%s: shot %d exists" % [scene.id, line.shot])
			if not line.speaker.is_empty():
				assert_true(line.speaker in Roster.fighter_ids() or line.speaker in STORY_FIGHTERS, "%s: speaker %s" % [scene.id, line.speaker])
				assert_false(StoryPlayer.speaker_name(line).is_empty())
			if not line.cue.is_empty():
				assert_true(Sound.has_cue(line.cue), "%s: cue %s" % [scene.id, line.cue])
		for actor in scene.actors:
			assert_true(actor.fighter in Roster.fighter_ids() or actor.fighter in STORY_FIGHTERS, "%s: actor %s" % [scene.id, actor.fighter])
			assert_true(actor.enter_line < scene.lines.size(), "%s: %s enters" % [scene.id, actor.fighter])
		for prop in scene.props:
			var path := (ArenaView.HALLOWEEN if prop.kit == StoryProp.Kit.HALLOWEEN else ArenaView.DUNGEON) % prop.model
			assert_true(ResourceLoader.exists(path), "%s: prop %s" % [scene.id, path])


func test_act_ends_on_the_end_of_act_card() -> void:
	var ending := story.steps.back() as StoryScene
	var last: StoryLine = ending.lines.back()
	assert_eq(last.kind, StoryLine.Kind.CARD)
	assert_eq(last.title, "End of Act 1")
	var intro := story.steps[0] as StoryScene
	assert_eq(intro.lines[0].kind, StoryLine.Kind.CARD, "the intro opens on title cards")

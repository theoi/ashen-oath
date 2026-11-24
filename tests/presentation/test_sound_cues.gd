extends TestCase
## Sound cues: every cue the match plays exists, and every file in the cue table loads.


func test_every_cue_file_loads() -> void:
	for id: StringName in SoundCues.TABLE:
		var row: Array = SoundCues.TABLE[id]
		assert_true(row.size() == 5, "%s row shape" % id)
		for path: String in row[0]:
			assert_true(ResourceLoader.exists(path) and load(path) is AudioStream, "%s: %s loads" % [id, path])
		assert_has([SoundCues.UI, SoundCues.SFX, SoundCues.MUSIC], row[1], "%s bus" % id)


func test_match_events_map_to_existing_cues() -> void:
	for type: StringName in MatchSounds.BY_TYPE:
		assert_true(Sound.has_cue(MatchSounds.BY_TYPE[type]), "cue for %s" % type)
	assert_eq(MatchSounds.cue_for({"type": MatchEvents.HIT, "heavy": true}), &"hit_heavy")
	assert_eq(MatchSounds.cue_for({"type": MatchEvents.HIT, "counter": true}), &"hit_counter")
	assert_eq(MatchSounds.cue_for({"type": MatchEvents.HIT}), &"hit_light")
	assert_eq(MatchSounds.cue_for({"type": MatchEvents.BLOCK, "cue": &"parry"}), &"parry", "an event's own cue wins")
	assert_eq(MatchSounds.cue_for({"type": MatchEvents.BLOCK, "cue": &"no_such_cue"}), &"block", "unknown own cue falls back")
	assert_eq(MatchSounds.cue_for({"type": MatchEvents.WAVE, "wave": 2, "waves": 3}), &"wave_start")
	assert_eq(MatchSounds.cue_for({"type": MatchEvents.STAGGER_BREAK, "slot": 1}), &"stagger_break")
	assert_eq(MatchSounds.cue_for({"type": MatchEvents.CHANNEL_BREAK, "slot": 1}), &"channel_break")


func test_story_and_boss_cues_exist() -> void:
	# FightFx plays these by name and falls back to generic cues when they are missing.
	for id: StringName in [&"spawn_rise", &"root", &"channel_start", &"channel_break", &"mob_death", &"stagger_break", &"wave_start"]:
		assert_true(Sound.has_cue(id), "cue %s" % id)


func test_sim_events_reach_the_cue_player() -> void:
	var sim := Sim.new(SimFixtures.config(2))
	var played: Array[StringName] = []
	for event in sim.events():
		var translated := SimHud.translate(sim, event)
		if not translated.is_empty():
			played.append(MatchSounds.cue_for(translated))
	assert_has(played, &"bell_toll", "round start tolls the bell")

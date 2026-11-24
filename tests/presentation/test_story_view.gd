extends TestCase
## Story waves and boss statuses on screen (sim-api "Story and boss support"): free slots are
## hidden, spawns rise from the floor and rebuild the view when a slot changes fighter, the
## channel-break gauge drains and shatters, root and debuffs show, and the camera keeps the
## player framed among up to 8 combatants.

const F := preload("res://tests/sim/sim_fixtures.gd")
const ALDRIC := "res://content/fighters/aldric/aldric.tres"
const HOLLOWED := "res://content/fighters/hollowed/hollowed.tres"
const GORRATH := "res://content/fighters/gorrath/gorrath.tres"
const T := SimEvent.Type


static func _entry(path: String, count: int) -> WaveEntry:
	var entry := WaveEntry.new()
	entry.fighter = load(path)
	entry.count = count
	return entry


static func _wave(entries: Array[WaveEntry], advance_alive: int) -> WaveData:
	var wave := WaveData.new()
	wave.entries = entries
	wave.advance_alive = advance_alive
	wave.advance_frames = 0
	return wave


func _fight(waves: Array[WaveData], wave_slots: int) -> FightView:
	var config := SimConfig.new()
	config.rules = load("res://content/rules/default_rules.tres")
	config.arena = load("res://content/arenas/ashen_chapel.tres")
	config.seed = 3
	var slot := SlotConfig.new()
	slot.fighter = load(ALDRIC)
	slot.team = 0
	config.slots.append(slot)
	config.waves = waves
	config.wave_slots = wave_slots
	var sources: Array[InputSource] = []
	for i in config.total_slots():
		sources.append(ScriptedInputSource.new())
	var fight := FightView.new()
	add_child_autofree(fight)
	fight.start(config, sources)
	fight.runner.paused = true
	return fight


## Steps the runner (events reach FightFx and the views) until `type` fires.
func _until(fight: FightView, type: SimEvent.Type, limit: int = 600) -> SimEvent:
	for i in limit:
		# Lambdas capture locals by value, so collect into an array.
		var found: Array[SimEvent] = []
		var on_event := func(e: SimEvent) -> void:
			if e.type == type:
				found.append(e)
		fight.runner.event_emitted.connect(on_event)
		fight.runner.step_once()
		fight.runner.event_emitted.disconnect(on_event)
		for view in fight.views:
			view._update(1.0 / 60.0)
		if not found.is_empty():
			return found[0]
	return null


func after_each() -> void:
	Engine.time_scale = 1.0


func test_free_slots_hide_and_spawns_rise_then_rebuild_for_a_new_fighter() -> void:
	var waves: Array[WaveData] = [_wave([_entry(HOLLOWED, 2)], 0), _wave([_entry(GORRATH, 1)], 0)]
	var fight := _fight(waves, 2)
	for view in fight.views:
		view._update(0.0)
	assert_false(fight.views[1].visible, "a free wave slot is hidden")
	var spawn := _until(fight, T.SPAWN)
	assert_not_null(spawn)
	var view := fight.views[spawn.source]
	assert_true(view.visible, "shown on SPAWN")
	assert_eq(view._pose.clip, FighterPoser.SPAWN_CLIP, "rises from the floor")
	assert_true(view.scene_path.contains("hollowed"))
	var sim := fight.runner.sim
	for _i in sim.rules.spawn_rise_frames + 2:
		fight.runner.step_once()
	sim._ko(sim.fighter(1))
	sim._ko(sim.fighter(2))
	# Both corpses free their slots on the same tick; the next wave's Gorrath takes the first.
	var again := _until(fight, T.SPAWN)
	assert_not_null(again)
	assert_eq(again.id, &"gorrath")
	assert_false(fight.views[3 - again.source].visible, "the other freed slot is hidden")
	var reused := fight.views[again.source]
	assert_true(reused.scene_path.contains("gorrath"), "the view rebuilt for the slot's new fighter")
	assert_true(reused.model.is_inside_tree())
	assert_eq(reused._body.get_child_count(), 1, "the old model is gone")


func test_channel_gauge_drains_and_shatters_on_break() -> void:
	var waves: Array[WaveData] = [_wave([_entry(GORRATH, 1)], 0)]
	var fight := _fight(waves, 1)
	var spawn := _until(fight, T.SPAWN)
	var view := fight.views[spawn.source]
	var boss := fight.runner.sim.fighter(spawn.source)
	boss.channel_max = 200
	boss.channel = 80
	view._update(1.0 / 60.0)
	assert_true(view.gauge_shown())
	assert_almost_eq(view.gauge_fill(), 0.4, 0.001)
	boss.channel = 0
	boss.channel_max = 0
	var e := SimEvent.new()
	e.type = T.CHANNEL_BREAK
	e.source = 0
	e.target = spawn.source
	fight.runner.event_emitted.emit(e)
	assert_true(fight.runner.is_slowed(), "the break gets a slow-motion beat")
	view._update(1.0 / 60.0)
	assert_true(view.gauge_shown(), "shatters after the break")
	for _i in 40:
		view._update(1.0 / 60.0)
	assert_false(view.gauge_shown(), "then goes away")


func test_root_chains_and_chill_tint() -> void:
	var waves: Array[WaveData] = [_wave([_entry(HOLLOWED, 1)], 0)]
	var fight := _fight(waves, 1)
	var view := fight.views[0]
	var me := fight.runner.sim.fighter(0)
	me.rooted = 30
	var chill := BuffState.new()
	chill.source = Sim.VICTIM_BUFF
	chill.speed_bonus_percent = -30
	chill.ticks_left = 120
	me.buffs.append(chill)
	for _i in 20:
		view._update(1.0 / 60.0)
	var ring := view.get_node(^"RootChains") as MeshInstance3D
	assert_true(ring.visible, "chains of ash at the feet")
	var amount := float(view.model.body_material.get_shader_parameter(&"status_amount"))
	assert_true(amount > 0.4, "chill tint (%.2f)" % amount)
	me.rooted = 0
	me.buffs.clear()
	for _i in 30:
		view._update(1.0 / 60.0)
	assert_false(ring.visible)
	assert_true(float(view.model.body_material.get_shader_parameter(&"status_amount")) < 0.05)


func test_camera_keeps_the_player_framed_among_eight() -> void:
	var waves: Array[WaveData] = [_wave([_entry(HOLLOWED, 7)], 0)]
	var fight := _fight(waves, -1)
	var sim := fight.runner.sim
	assert_eq(sim.slot_count(), 8)
	_until(fight, T.SPAWN)
	for _i in sim.rules.spawn_rise_frames + 4:
		fight.runner.step_once()
	F.place(sim, 0, -7.0, -5.0, 0)
	var spots: Array[Vector2] = [Vector2(4, 6), Vector2(6, 2), Vector2(-2, 7), Vector2(8, 7), Vector2(0, 3), Vector2(5, -3), Vector2(-6, 4)]
	for i in spots.size():
		F.place(sim, i + 1, spots[i].x, spots[i].y, 0)
	var camera := fight.camera
	for _i in 240:
		camera._process(1.0 / 60.0)
	assert_true(camera._distance <= Feel.camera_distance_max() + 0.01, "within the max distance (%.1f)" % camera._distance)
	assert_true(camera._distance > Feel.camera_distance() + 0.5, "pulled back for the spread (%.1f)" % camera._distance)
	var size := fight.get_viewport().get_visible_rect().size
	var at := camera.unproject_position(fight.runner.fighter_position(0) + Vector3.UP * 0.9)
	var rel := (at - size * 0.5) / (size * 0.5)
	assert_true(absf(rel.x) <= 0.62 and absf(rel.y) <= 0.62, "the player stays in the middle 60%% (%.2f, %.2f)" % [rel.x, rel.y])

extends TestCase
## Echoes, beams, armor buffs and mob deaths on screen (sim-api "Echoes", "Effect
## upgrades", "Armor buffs").

const ALDRIC := "res://content/fighters/aldric/aldric.tres"
const HOLLOWED := "res://content/fighters/hollowed/hollowed.tres"
const T := SimEvent.Type


## Aldric vs Hollowed, with Flame Rend echoing 30 f after its cast.
func _fight() -> FightView:
	var aldric := (load(ALDRIC) as FighterData).duplicate(true) as FighterData
	aldric.move_by_id(&"flame_rend").echo_frames = 30
	var config := SimConfig.new()
	config.rules = load("res://content/rules/default_rules.tres")
	config.arena = load("res://content/arenas/ashen_chapel.tres")
	config.seed = 3
	for data: FighterData in [aldric, load(HOLLOWED) as FighterData]:
		var slot := SlotConfig.new()
		slot.fighter = data
		slot.team = config.slots.size()
		config.slots.append(slot)
	var sources: Array[InputSource] = [ScriptedInputSource.new(), ScriptedInputSource.new()]
	var fight := FightView.new()
	add_child_autofree(fight)
	fight.start(config, sources)
	fight.runner.paused = true
	SimFixtures.skip_intro(fight.runner.sim)
	SimFixtures.place(fight.runner.sim, 0, 0.0, -4.0, 0)
	SimFixtures.place(fight.runner.sim, 1, 0.0, 4.0, Fx.HALF_TURN)
	return fight


func _step(fight: FightView, frame: int) -> void:
	var inputs := PackedInt64Array([frame, 0])
	for e in fight.runner.sim.step(inputs):
		fight.runner.event_emitted.emit(e)
	fight.fx.echoes._process(1.0 / 60.0)
	fight.fx.decals._process(1.0 / 60.0)


func after_each() -> void:
	Engine.time_scale = 1.0


func test_an_echo_ghost_waits_recasts_and_burns_away_with_a_ghostly_warning() -> void:
	var fight := _fight()
	var echoes := fight.fx.echoes
	# Watch from the Hollowed's side: echo warnings are for enemy echoes.
	fight.fx.decals.local_slot = 1
	_step(fight, SimInput.with_aim_point(SimInput.SKILL_3, Vector2(0.0, 6.0)))
	assert_eq(fight.runner.sim.state.echoes.size(), 1, "the cast records an echo")
	assert_eq(echoes.ghost_count(), 1, "a ghost stands at the cast position")
	var ghost := echoes.ghost_for(0, fight.runner.sim.state.echoes[0].cast)
	assert_not_null(ghost)
	var ghostly := false
	for _i in 10:
		_step(fight, 0)
		for decal in fight.fx.decals.get_children():
			var m := (decal as MeshInstance3D).material_override as ShaderMaterial
			if (decal as MeshInstance3D).visible and m.get_shader_parameter(&"color") == GroundDecals.ECHO_RED:
				ghostly = true
	assert_true(ghostly, "the pending echo shows a ghostly red warning")
	var cast := false
	for _i in 200:
		_step(fight, 0)
		if fight.runner.sim.state.echoes.is_empty():
			break
		cast = cast or fight.runner.sim.state.echoes[0].frame > 0
	assert_true(cast, "the echo re-cast")
	assert_true(fight.runner.sim.state.echoes.is_empty())
	for _i in 30:
		echoes._process(1.0 / 60.0)
	assert_eq(echoes.ghost_count(), 0, "burned away once the echo ended")


func test_beams_run_along_their_length() -> void:
	var data := EffectData.new()
	data.length = 6.0
	data.radius = 0.5
	data.attach_to_owner = true
	var visual: Node3D = add_child_autofree(preload("res://presentation/fight/effect_visual.gd").new())
	visual.call(&"setup", data, Color.ORANGE)
	assert_eq(visual.get(&"kind"), 4, "BEAM")
	var core := visual.get(&"_core") as MeshInstance3D
	assert_almost_eq((core.mesh as CylinderMesh).height, 6.0, 0.001)
	visual.call(&"_process", 0.2)
	assert_almost_eq(core.position.z, 3.0, 0.01, "centred halfway along the facing")


func test_armor_buff_sheen() -> void:
	var fight := _fight()
	var view := fight.views[1]
	var iron := BuffState.new()
	iron.armor = 1
	iron.ticks_left = 300
	fight.runner.sim.fighter(1).buffs.append(iron)
	for _i in 20:
		view._update(1.0 / 60.0)
	assert_true(float(view.model.body_material.get_shader_parameter(&"sheen_amount")) > 0.5)
	fight.runner.sim.fighter(1).buffs.clear()
	for _i in 20:
		view._update(1.0 / 60.0)
	assert_almost_eq(float(view.model.body_material.get_shader_parameter(&"sheen_amount")), 0.0, 0.01)


func test_wave_mob_ko_is_light_and_a_duel_ko_stays_big() -> void:
	var config := SimConfig.new()
	config.rules = load("res://content/rules/default_rules.tres")
	config.arena = load("res://content/arenas/ashen_chapel.tres")
	var slot := SlotConfig.new()
	slot.fighter = load(ALDRIC)
	config.slots.append(slot)
	var wave := WaveData.new()
	var entry := WaveEntry.new()
	entry.fighter = load(HOLLOWED)
	wave.entries = [entry]
	config.waves = [wave]
	config.wave_slots = 1
	var fight := FightView.new()
	add_child_autofree(fight)
	fight.start(config, [ScriptedInputSource.new(), ScriptedInputSource.new()] as Array[InputSource])
	fight.runner.paused = true
	var ko := SimEvent.new()
	ko.type = T.KO
	ko.source = 0
	ko.target = 1
	fight.fx._on_event(ko)
	assert_almost_eq(fight.fx._overlay_flash, 0.0, 0.001, "no full-screen pulse for a mob")
	assert_true(fight.camera.shake_amplitude() <= 0.03, "a light shake (%.3f)" % fight.camera.shake_amplitude())
	ko.target = 0
	ko.source = 1
	fight.fx._on_event(ko)
	assert_true(fight.fx._overlay_flash > 0.2, "the player's KO keeps its pulse")
	assert_true(fight.camera.shake_amplitude() >= 0.1)

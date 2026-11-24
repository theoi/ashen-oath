extends TestCase
## Fighter-specific presentation extras: Morrigan's lantern follows her stored souls,
## Gorrath's thrown chain only shows while Chain Hook is out, and every body mesh carries
## rest positions for the grime and crack shader.

const F := preload("res://tests/sim/sim_fixtures.gd")


func _model(id: String) -> FighterModel:
	var data: FighterData = load("res://content/fighters/%s/%s.tres" % [id, id])
	var model := (load(data.scene) as PackedScene).instantiate() as FighterModel
	add_child_autofree(model)
	model.build()
	return model


func _sim(id: String) -> Sim:
	var data: FighterData = load("res://content/fighters/%s/%s.tres" % [id, id])
	var sim := F.fighting_sim(F.config(2, data))
	F.place(sim, 0, 0.0, 0.0, 0)
	F.place(sim, 1, 0.0, 6.0, Fx.HALF_TURN)
	return sim


func test_lantern_burns_brighter_with_stored_souls() -> void:
	var model := _model("morrigan")
	var sim := _sim("morrigan")
	var me := sim.fighter(0)
	for _i in 120:
		model.update_extras(sim, me, 1.0 / 60.0)
	var dim: float = model._light.light_energy
	me.vars[0] = 3
	for _i in 120:
		model.update_extras(sim, me, 1.0 / 60.0)
	assert_true(model._light.light_energy > dim * 1.5, "3 souls: %.2f vs %.2f" % [model._light.light_energy, dim])


func test_chain_hook_shows_the_thrown_chain_only_while_out() -> void:
	var model := _model("gorrath")
	var sim := _sim("gorrath")
	var me := sim.fighter(0)
	model.update_extras(sim, me, 1.0 / 60.0)
	assert_eq(model._hook.multimesh.visible_instance_count, 0, "no chain at rest")
	var longest := 0
	for t in 40:
		F.step(sim, SimInput.ABILITY_1 if t == 0 else 0)
		model.update_extras(sim, me, 1.0 / 60.0)
		longest = maxi(longest, model._hook.multimesh.visible_instance_count)
	assert_true(longest > 30, "the chain flew out (%d links)" % longest)
	F.until_action(sim, me, FighterState.Action.IDLE)
	model.update_extras(sim, me, 1.0 / 60.0)
	assert_eq(model._hook.multimesh.visible_instance_count, 0, "chain gone after the move")


func test_body_meshes_carry_rest_positions() -> void:
	for id: String in ["aldric", "morrigan", "gorrath", "hollowed", "oath_shade"]:
		var model := _model(id)
		var found := 0
		for node in model.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.material_override != model.body_material or mi.mesh == null:
				continue
			found += 1
			var format: int = (mi.mesh as ArrayMesh).surface_get_format(0)
			assert_true((format & Mesh.ARRAY_FORMAT_CUSTOM0) != 0, "%s/%s has CUSTOM0" % [id, mi.name])
		assert_true(found > 0, "%s has body meshes" % id)

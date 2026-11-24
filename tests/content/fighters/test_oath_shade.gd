extends TestCase
## The Oath-Shade: Aldric's full kit and Oathkeeper trait under a shadow look.

const ALDRIC := "res://content/fighters/aldric/aldric.tres"
const SHADE := "res://content/fighters/oath_shade/oath_shade.tres"


func test_shade_runs_aldrics_kit() -> void:
	var aldric: FighterData = load(ALDRIC)
	var shade: FighterData = load(SHADE)
	assert_eq(shade.moves.size(), aldric.moves.size())
	for i in aldric.moves.size():
		assert_eq(shade.moves[i], aldric.moves[i], "shares %s" % aldric.moves[i].id)
	assert_eq(shade.abilities, aldric.abilities)
	assert_eq(shade.super_move, aldric.super_move)
	assert_eq(shade.parry_window, 8)
	assert_not_null(shade.parry_buff)


func test_shade_wears_the_shadow_material() -> void:
	var shade: FighterData = load(SHADE)
	var model := (load(shade.scene) as PackedScene).instantiate() as FighterModel
	add_child_autofree(model)
	model.build()
	assert_eq(model.shade, 1.0)
	assert_not_null(model.skeleton)

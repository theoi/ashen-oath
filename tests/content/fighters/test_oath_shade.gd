extends TestCase
## The Oath-Shade: Aldric's classic kit and Oathkeeper trait under a shadow look; the
## Hollowed share its move files.

const SHADE := "res://content/fighters/oath_shade/oath_shade.tres"
const HOLLOWED := "res://content/fighters/hollowed/hollowed.tres"


func test_shade_runs_the_classic_kit() -> void:
	var shade: FighterData = load(SHADE)
	assert_eq(shade.abilities, [&"oathfire_lunge", &"brand_rise", &"bulwark_charge"] as Array[StringName])
	assert_eq(shade.super_move, &"pyre_of_the_forsworn")
	assert_eq(shade.parry_window, 8)
	assert_not_null(shade.parry_buff)
	assert_null(shade.dash, "keeps the roll until design-lost-ark §5")


func test_hollowed_share_the_shade_moves() -> void:
	var shade: FighterData = load(SHADE)
	var hollowed: FighterData = load(HOLLOWED)
	for move in hollowed.moves:
		assert_true(move in shade.moves, "%s is shared" % move.id)


func test_shade_wears_the_shadow_material() -> void:
	var shade: FighterData = load(SHADE)
	var model := (load(shade.scene) as PackedScene).instantiate() as FighterModel
	add_child_autofree(model)
	model.build()
	assert_eq(model.shade, 1.0)
	assert_not_null(model.skeleton)

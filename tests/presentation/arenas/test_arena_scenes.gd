extends TestCase
## Every arena scene builds without errors (a misspelled model name only fails at runtime),
## and its dressing stays within the Compatibility-renderer budget for the web build.

const ARENAS: PackedStringArray = [
	"res://content/arenas/ashen_chapel.tres",
	"res://content/arenas/ashen_chapel_night.tres",
	"res://content/arenas/drowned_crypt.tres",
	"res://content/arenas/drowned_crypt_depths.tres",
]
## Each light adds a draw pass per object it touches in the Compatibility renderer. Vent
## lights only switch on while a vent glows or burns.
const MAX_OMNI_LIGHTS := 16
const MAX_PARTICLES := 700


func test_arenas_build_within_budget() -> void:
	for path in ARENAS:
		var data: ArenaData = load(path)
		var scene: PackedScene = load(data.scene)
		var arena: ArenaView = scene.instantiate()
		add_child_autofree(arena)
		await wait_frames(2)
		var props := arena.get_node("Props")
		assert_true(props.get_child_count() > 50, "%s has props" % path)
		var omni := arena.find_children("*", "OmniLight3D", true, false).size()
		assert_true(omni <= MAX_OMNI_LIGHTS, "%s uses %d omni lights" % [path, omni])
		var particles := 0
		for node in arena.find_children("*", "CPUParticles3D", true, false):
			particles += (node as CPUParticles3D).amount
		assert_true(particles <= MAX_PARTICLES, "%s spawns %d particles" % [path, particles])
		assert_not_null(arena.get_node_or_null("Flames"), "%s has candle flames" % path)
		# Shadowed lights are the costliest in the Compatibility renderer: only the key light.
		var shadowed := 0
		for light: Light3D in arena.find_children("*", "Light3D", true, false):
			if light.shadow_enabled:
				shadowed += 1
		assert_true(shadowed <= 1, "%s has %d shadowed lights" % [path, shadowed])
		# Fighter-only lights must skip arena geometry (layer 2).
		var fill := arena.get_node_or_null("FighterFill") as Light3D
		if fill != null:
			assert_eq(fill.light_cull_mask & ArenaView.ARENA_LAYER, 0, "%s fill skips the arena" % path)

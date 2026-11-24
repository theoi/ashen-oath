extends TestCase
## Every arena scene builds without errors (a misspelled model name only fails at runtime),
## and its dressing stays within the Compatibility-renderer budget for the web build.

const ARENAS: PackedStringArray = [
	"res://presentation/arenas/ashen_chapel/ashen_chapel.tscn",
	"res://presentation/arenas/ashen_chapel/ashen_chapel_night.tscn",
]
## Each light adds a draw pass per object it touches in the Compatibility renderer.
const MAX_OMNI_LIGHTS := 14
const MAX_PARTICLES := 700


func test_arenas_build_within_budget() -> void:
	for path in ARENAS:
		var scene: PackedScene = load(path)
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

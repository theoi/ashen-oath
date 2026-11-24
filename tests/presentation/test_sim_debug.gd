extends TestCase
## The debug view runs a match with bots without errors.


func test_debug_view_runs_a_match() -> void:
	var view: Node3D = (load("res://presentation/debug/sim_debug.tscn") as PackedScene).instantiate()
	add_child_autofree(view)
	await wait_physics_frames(100)
	await wait_frames(2)
	var runner: MatchRunner = view.get("runner")
	assert_not_null(runner)
	assert_true(runner.sim.state.tick >= 95)
	assert_eq(runner.sim.state.phase, SimState.Phase.FIGHT)

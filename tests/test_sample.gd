extends TestCase
## Example tests that show the runner's API. Copy this file to start a new test file.


func test_assertions() -> void:
	assert_eq(2 + 2, 4)
	assert_eq(3, 3.0, "int and float compare by value")
	assert_almost_eq(0.1 + 0.2, 0.3, 0.000001)
	assert_has([1, 2, 3], 2)
	assert_ne("light", "heavy")


func test_can_await_frames_with_nodes_in_the_tree() -> void:
	var node := add_child_autofree(Node3D.new())
	await wait_physics_frames(2)
	assert_true(node.is_inside_tree())

class_name TestCase
extends RefCounted
## Base class for tests run by res://tests/runner.tscn.
##
## Put tests in files named `test_*.gd` anywhere under res://tests/ (outside framework/).
## Each file holds one class extending TestCase. Every method named `test_*` runs on a fresh
## instance, between before_each() and after_each(). Test methods may `await`.
## Any engine or script error logged while a test runs also fails that test.

## The runner node. Use it to reach the SceneTree, or call add_child_autofree().
var host: Node

var _failures: PackedStringArray = []
var _autofree: Array[Node] = []


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func fail(message: String) -> void:
	_failures.append("%s  [%s]" % [message, _caller_location()])


func assert_true(condition: bool, message: String = "") -> void:
	if not condition:
		fail(_describe("expected true", message))


func assert_false(condition: bool, message: String = "") -> void:
	if condition:
		fail(_describe("expected false", message))


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if not _values_equal(actual, expected):
		fail(_describe("expected %s, got %s" % [var_to_str(expected), var_to_str(actual)], message))


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	if _values_equal(actual, unexpected):
		fail(_describe("expected anything but %s" % var_to_str(unexpected), message))


func assert_almost_eq(actual: float, expected: float, tolerance: float = 0.00001, message: String = "") -> void:
	if absf(actual - expected) > tolerance:
		fail(_describe("expected %s ± %s, got %s" % [expected, tolerance, actual], message))


func assert_null(value: Variant, message: String = "") -> void:
	if value != null:
		fail(_describe("expected null, got %s" % var_to_str(value), message))


func assert_not_null(value: Variant, message: String = "") -> void:
	if value == null:
		fail(_describe("expected a value, got null", message))


## Passes when `value in container` (Array, Dictionary keys, String, packed arrays).
func assert_has(container: Variant, value: Variant, message: String = "") -> void:
	if not value in container:
		fail(_describe("expected %s to contain %s" % [var_to_str(container), var_to_str(value)], message))


## Adds `node` under the runner and frees it after the test.
func add_child_autofree(node: Node) -> Node:
	host.add_child(node)
	_autofree.append(node)
	return node


func wait_frames(count: int) -> void:
	for _i in count:
		await host.get_tree().process_frame


func wait_physics_frames(count: int) -> void:
	for _i in count:
		await host.get_tree().physics_frame


func _cleanup() -> void:
	for node in _autofree:
		if is_instance_valid(node):
			node.free()
	_autofree.clear()


func _describe(problem: String, message: String) -> String:
	return problem if message.is_empty() else "%s: %s" % [message, problem]


## int and float compare by value; any other type mismatch is unequal instead of an error.
func _values_equal(a: Variant, b: Variant) -> bool:
	var a_numeric := typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT
	var b_numeric := typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT
	if a_numeric and b_numeric:
		return a == b
	if typeof(a) != typeof(b):
		return false
	return a == b


func _caller_location() -> String:
	for backtrace in Engine.capture_script_backtraces():
		for i in backtrace.get_frame_count():
			var file := backtrace.get_frame_file(i)
			if not file.ends_with("framework/test_case.gd"):
				return "%s:%d" % [file, backtrace.get_frame_line(i)]
	return "unknown location"

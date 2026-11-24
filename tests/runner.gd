extends Node
## Headless test runner.
##
##   godot --headless --path . res://tests/runner.tscn [-- --filter=<text>]
##
## Runs every `test_*` method of every res://tests/**/test_*.gd (see framework/test_case.gd)
## and quits with exit code 0 when all pass, 1 otherwise. --filter keeps only tests whose
## id ("path/test_file.gd::test_method") contains <text>.

const TESTS_ROOT := "res://tests"
const SKIP_DIRS: PackedStringArray = ["framework"]


## Collects engine and script errors so a test that triggers one fails even without asserts.
class ErrorCollector extends Logger:
	var _mutex := Mutex.new()
	var _errors: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		var detail := rationale if not rationale.is_empty() else code
		_mutex.lock()
		_errors.append("error: %s (%s:%d, %s)" % [detail, file, line, function])
		_mutex.unlock()

	func take() -> PackedStringArray:
		_mutex.lock()
		var errors := _errors
		_errors = PackedStringArray()
		_mutex.unlock()
		return errors


var _collector := ErrorCollector.new()
var _filter := ""
var _passed := 0
var _failed: PackedStringArray = []


func _ready() -> void:
	OS.add_logger(_collector)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			_filter = arg.trim_prefix("--filter=")
	_run.call_deferred()


func _run() -> void:
	var started := Time.get_ticks_msec()
	for path in _find_test_files(TESTS_ROOT):
		await _run_file(path)
	OS.remove_logger(_collector)

	var total := _passed + _failed.size()
	print("")
	if total == 0:
		print("No tests ran%s." % (" (filter: %s)" % _filter if not _filter.is_empty() else ""))
		get_tree().quit(1)
		return
	for id in _failed:
		print("FAILED  %s" % id)
	print("%d passed, %d failed, %d total in %.2f s" % [_passed, _failed.size(), total,
			(Time.get_ticks_msec() - started) / 1000.0])
	get_tree().quit(0 if _failed.is_empty() else 1)


func _run_file(path: String) -> void:
	var relative := path.trim_prefix(TESTS_ROOT + "/")
	_collector.take()
	var script := load(path) as GDScript
	var problems := _collector.take()
	if script == null or not script.can_instantiate():
		problems.insert(0, "could not load the script")
	elif not script.new() is TestCase:
		problems.append("the script does not extend TestCase")
	if not problems.is_empty():
		_report("%s::<load>" % relative, problems, 0)
		return

	var methods: PackedStringArray = []
	for method in script.get_script_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_") and not method_name in methods:
			methods.append(method_name)
	for method_name in methods:
		var id := "%s::%s" % [relative, method_name]
		if _filter.is_empty() or id.contains(_filter):
			await _run_test(script, id, method_name)


func _run_test(script: GDScript, id: String, method_name: String) -> void:
	var test: TestCase = script.new()
	test.host = self
	_collector.take()
	var started := Time.get_ticks_usec()
	await test.before_each()
	if test._failures.is_empty():
		await test.call(method_name)
	await test.after_each()
	test._cleanup()
	var problems := test._failures + _collector.take()
	_report(id, problems, Time.get_ticks_usec() - started)


func _report(id: String, problems: PackedStringArray, elapsed_usec: int) -> void:
	if problems.is_empty():
		_passed += 1
		print("  ok    %s  (%.1f ms)" % [id, elapsed_usec / 1000.0])
		return
	_failed.append(id)
	print("  FAIL  %s" % id)
	for problem in problems:
		print("          %s" % problem)


func _find_test_files(dir_path: String) -> PackedStringArray:
	var found: PackedStringArray = []
	var files := DirAccess.get_files_at(dir_path)
	files.sort()
	for file in files:
		if file.begins_with("test_") and file.ends_with(".gd"):
			found.append(dir_path.path_join(file))
	var dirs := DirAccess.get_directories_at(dir_path)
	dirs.sort()
	for dir in dirs:
		if not dir in SKIP_DIRS:
			found.append_array(_find_test_files(dir_path.path_join(dir)))
	return found

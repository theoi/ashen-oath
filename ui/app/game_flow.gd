extends Node
## Autoload `GameFlow`: moves between menu screens and matches.
##
## Menu screens live in ScreenStacks: the menus (ui/app/menu_app.tscn, the main scene) and,
## during a match, the pause/results overlay. Screens call open_screen() / back(), which act
## on the most recent stack. start_match() switches to the match scene; return_to_menu()
## comes back with a given screen stack so "back" from the landing screen still makes sense.

## A match finished (any mode). Story mode listens to this, or sets MatchConfig.on_finished.
signal match_finished(result: MatchResult)

const MENU_SCENE := "res://ui/app/menu_app.tscn"
const MATCH_SCENE := "res://ui/match/match_screen.tscn"

## Screen id -> scene. "story" is the entry point the story mode replaces.
const SCREENS: Dictionary[StringName, String] = {
	&"title": "res://ui/menus/title_screen.tscn",
	&"mode_select": "res://ui/menus/mode_select.tscn",
	&"story": "res://ui/story/story_entry.tscn",
	&"story_chapters": "res://ui/story/story_chapters.tscn",
	&"versus": "res://ui/versus/versus_select.tscn",
	&"controls": "res://ui/menus/controls_screen.tscn",
	&"settings": "res://ui/menus/settings_screen.tscn",
	&"pause": "res://ui/match/pause_screen.tscn",
	&"results": "res://ui/match/results_screen.tscn",
}

## The match being played or last played (rematch uses it).
var current_match: MatchConfig
## How the last match ended (the results screen shows it).
var last_result: MatchResult
## The story run in progress (a StoryDirector), kept here across scene changes. A static
## var would outlive the engine's resource teardown at quit.
var story_director: RefCounted

var _hosts: Array[ScreenStack] = []
var _pending_menu: Array[StringName] = [&"title"]


func _ready() -> void:
	# Dev and capture runs can start deeper in the menus (-- --menu=mode_select,settings)
	# or straight in a versus match (-- --match).
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--menu="):
			var stack: Array[StringName] = []
			for id in arg.trim_prefix("--menu=").split(",", false):
				if SCREENS.has(StringName(id)):
					stack.append(StringName(id))
			if not stack.is_empty():
				_pending_menu = stack
		elif arg.begins_with("--match"):
			start_match.call_deferred(_dev_match(arg.trim_prefix("--match").trim_prefix("=")))


## Dev / capture matches: "" (Aldric vs Morrigan), "1v2" (vs Morrigan and Gorrath) or
## "hollowed" (vs a Hollowed). An "-attract" suffix ("attract", "1v2-attract",
## "hollowed-attract") makes every slot a CPU.
func _dev_match(kind: String) -> MatchConfig:
	var config := MatchConfig.versus(&"aldric", &"morrigan", &"ashen_chapel", Settings.default_difficulty)
	match kind:
		"1v2", "1v2-attract":
			config.fighters = [&"aldric", &"morrigan", &"gorrath"]
			config.teams = [0, 1, 1]
			config.starting_soul = [100, 0, 50]
		"hollowed", "hollowed-attract":
			config.fighters = [&"aldric", &"hollowed"]
			config.starting_soul = [60, 0]
	config.attract = kind.ends_with("attract")
	return config


func attach_host(host: ScreenStack) -> void:
	_hosts.erase(host)
	_hosts.append(host)


func detach_host(host: ScreenStack) -> void:
	_hosts.erase(host)


## The menu stack to show when the menus load; resets to the title afterwards.
func take_pending_menu() -> Array[StringName]:
	var stack := _pending_menu
	_pending_menu = [&"title"]
	return stack


func open_screen(id: StringName) -> void:
	if not SCREENS.has(id):
		push_error("unknown screen %s" % id)
		return
	if _hosts.is_empty():
		return_to_menu([id])
	else:
		_hosts.back().push_screen(id)


func back() -> void:
	if not _hosts.is_empty():
		_hosts.back().pop_screen()


func rematch() -> void:
	if current_match != null:
		start_match(current_match.duplicate_config())


## Leaves the match for the menus it was started from.
func leave_match() -> void:
	return_to_menu(current_match.menu_stack if current_match != null else [&"mode_select"] as Array[StringName])


func start_match(config: MatchConfig) -> void:
	current_match = config
	get_tree().paused = false
	get_tree().change_scene_to_file(MATCH_SCENE)


## Called by the match scene when the last round ends.
func finish_match(result: MatchResult) -> void:
	last_result = result
	match_finished.emit(result)
	if current_match != null and current_match.on_finished.is_valid():
		current_match.on_finished.call(result)


## Loads the menus showing `stack` (bottom first). Unpauses the tree.
func return_to_menu(stack: Array[StringName] = [&"mode_select"]) -> void:
	_pending_menu = stack
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


## Desktop builds can quit; the web build has nowhere to quit to.
func can_quit() -> bool:
	return not OS.has_feature("web")


func quit_game() -> void:
	get_tree().quit()

class_name StoryDirector
extends RefCounted
## Runs a StoryRun through the game: scenes in the story player, fights through GameFlow,
## then the results card or the "You Hollowed" screen, and back to the menus at the end.
##
## The current director is kept by GameFlow so it survives scene changes (the match's
## on_finished callback points at it). Navigation goes through Callables that tests replace.

enum View { SCENE, RESULTS, HOLLOWED }

const STORY := "res://content/story/act1/act1.tres"
const PLAYER_SCENE := "res://ui/story/story_player.tscn"
## Seconds of the KO before the results card.
const RESULTS_DELAY := 2.4
const STORY_MENU: Array[StringName] = [&"mode_select", &"story"]
const CHAPTER_MENU: Array[StringName] = [&"mode_select", &"story", &"story_chapters"]

var run: StoryRun
var view := View.SCENE

## Opens the story player for `view` (default: change to PLAYER_SCENE).
var show_player: Callable
## Starts a fight: (MatchConfig) -> void (default: GameFlow.start_match).
var start_match: Callable
## Leaves for the menus: (Array[StringName] stack) -> void (default: GameFlow.return_to_menu).
var to_menu: Callable
## Calls back after a delay: (seconds: float, callback: Callable) -> void.
var after: Callable


func _init(story_run: StoryRun = null) -> void:
	run = story_run
	show_player = _change_to_player
	start_match = func(config: MatchConfig) -> void: GameFlow.start_match(config)
	to_menu = func(stack: Array[StringName]) -> void: GameFlow.return_to_menu(stack)
	after = _after


static func load_story() -> StoryData:
	return load(STORY) as StoryData


## The director of the story run in progress, or null.
static func current() -> StoryDirector:
	return GameFlow.story_director as StoryDirector


static func set_current(director: StoryDirector) -> void:
	GameFlow.story_director = director


## Makes `director` current and shows its run's current step.
static func begin(director: StoryDirector) -> void:
	set_current(director)
	director.show_current()


func show_current() -> void:
	var step := run.step()
	if step == null:
		_finish()
	elif step is StoryScene:
		view = View.SCENE
		show_player.call()
	elif step is StoryFight:
		start_match.call(match_config())


## The match for the current fight, wired back to this director.
func match_config() -> MatchConfig:
	var config := run.match_config(run.current_fight())
	config.on_finished = _on_match_finished
	config.on_started = _on_match_started
	config.menu_stack = STORY_MENU.duplicate()
	return config


func scene_finished() -> void:
	run.advance()
	show_current()


func continue_after_results() -> void:
	run.advance()
	show_current()


func retry() -> void:
	show_current()


func retry_on_lower_difficulty() -> void:
	run.lower_difficulty()
	show_current()


func quit() -> void:
	to_menu.call(CHAPTER_MENU.duplicate() if run.chapter_only else STORY_MENU.duplicate())


func _finish() -> void:
	to_menu.call(CHAPTER_MENU.duplicate())


func _on_match_finished(result: MatchResult) -> void:
	view = View.RESULTS if run.record(result) else View.HOLLOWED
	after.call(RESULTS_DELAY, show_player)


func _on_match_started(screen: MatchScreen) -> void:
	var fight := run.current_fight()
	if fight != null and not fight.prompts.is_empty():
		var overlay := FightPrompts.new()
		overlay.setup(fight.prompts, screen.runner, 0)
		screen.add_overlay(overlay)


func _change_to_player() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	tree.paused = false
	tree.change_scene_to_file(PLAYER_SCENE)


func _after(seconds: float, callback: Callable) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	tree.create_timer(seconds, true).timeout.connect(callback)

extends TestCase
## Fight 1 tutorial prompts on a real story match: the match screen adds them, and each one
## is ticked off by the player's fighter doing it in the sim.

const MATCH_SCENE := preload("res://ui/match/match_screen.tscn")
const SAVE_PATH := "user://test_fight_prompts.cfg"


## Feeds queued frames to a slot, then neutral.
class QueueSource:
	extends InputSource
	var queue: Array[int] = []

	func next_frame(_sim: Sim, _slot: int) -> int:
		return queue.pop_front() if not queue.is_empty() else 0

	func hold(frame: int, ticks: int) -> void:
		for i in ticks:
			queue.append(frame)

	func tap(frame: int, gap: int) -> void:
		queue.append(frame)
		hold(0, gap)


var screen: MatchScreen
var director: StoryDirector


func before_each() -> void:
	StorySave.default_path = SAVE_PATH
	Engine.time_scale = 1.0


func after_each() -> void:
	host.get_tree().paused = false
	if is_instance_valid(screen):
		screen.free()
	GameFlow.current_match = null
	GameFlow.story_director = null
	director = null
	StorySave.default_path = StorySave.DEFAULT_PATH
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func test_tutorial_prompts_follow_the_players_actions() -> void:
	var story := StoryDirector.load_story()
	var save := StorySave.load_from()
	save.started = true
	save.next_step = story.step_index(&"fight_squire")
	var run := StoryRun.resume(story, save)
	director = StoryDirector.new(run)
	GameFlow.current_match = director.match_config()
	screen = MATCH_SCENE.instantiate()
	host.add_child(screen)
	await wait_frames(1)
	var prompts := screen.find_children("*", "FightPrompts", true, false)
	assert_eq(prompts.size(), 1, "story fight 1 shows the tutorial prompts")
	if prompts.is_empty():
		return
	var overlay := prompts[0] as FightPrompts
	assert_eq(overlay.current().goal, StoryPrompt.Goal.MOVE)

	var source := QueueSource.new()
	screen.runner.paused = true
	screen.runner.sources[0] = source
	screen.runner.sources[1] = null
	for i in 600:
		if screen.runner.sim.state.phase == SimState.Phase.FIGHT:
			break
		screen.runner.step_once()

	source.hold(SimInput.make(0, 0, -127), 150)
	_run_until(overlay, 1, source)
	assert_eq(overlay.index, 1, "moving 4 m completes Move")

	for n in 3:
		source.tap(SimInput.LIGHT, 7)
	source.hold(0, 60)
	_run_until(overlay, 2, source)
	assert_eq(overlay.index, 2, "three chained lights complete the string")

	source.hold(SimInput.GUARD, 80)
	_run_until(overlay, 3, source)
	assert_eq(overlay.index, 3, "holding guard completes Guard")

	source.tap(SimInput.DODGE, 60)
	_run_until(overlay, 4, source)
	assert_eq(overlay.index, 4, "a roll completes Dodge")

	source.tap(SimInput.GRAB, 80)
	_run_until(overlay, 5, source)
	assert_eq(overlay.index, 5, "a grab completes Grab")
	assert_eq(overlay.completed, ["Move", "Light string", "Guard", "Dodge", "Grab"] as Array[String])

	for i in 400:
		screen.runner.step_once()
	assert_true(overlay.is_done(), "the last prompt times out")


func test_versus_matches_have_no_prompts() -> void:
	GameFlow.current_match = MatchConfig.versus(&"aldric", &"morrigan", &"ashen_chapel", MatchConfig.Difficulty.NORMAL)
	screen = MATCH_SCENE.instantiate()
	host.add_child(screen)
	await wait_frames(1)
	assert_eq(screen.find_children("*", "FightPrompts", true, false).size(), 0)


## Steps until the overlay reaches prompt `target` (or the queued input runs out).
func _run_until(overlay: FightPrompts, target: int, source: QueueSource) -> void:
	for i in 1200:
		if overlay.index >= target:
			return
		screen.runner.step_once()
		if source.queue.is_empty() and i > 300:
			return

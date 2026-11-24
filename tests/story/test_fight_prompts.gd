extends TestCase
## Story tips on a real story match: the match screen adds them, each one is ticked off by
## the player's fighter doing it in the sim, contextual tips cut in at their moment, tips
## can be skipped, and a retry does not repeat what was already learned.

const MATCH_SCENE := preload("res://ui/match/match_screen.tscn")
const SAVE_PATH := "user://test_fight_prompts.cfg"
const Goal := StoryPrompt.Goal


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
var source: QueueSource
var overlay: FightPrompts


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


func test_fight_one_tutorial_follows_the_players_actions() -> void:
	await _open_fight(&"fight_squire")
	assert_eq(overlay.current().goal, Goal.MOVE)

	source.hold(SimInput.make(0, 0, -127), 150)
	_run_until(Goal.LIGHT_STRING)
	for n in 3:
		source.tap(SimInput.LIGHT, 7)
	source.hold(0, 60)
	_run_until(Goal.GUARD)
	source.hold(SimInput.GUARD, 80)
	_run_until(Goal.PARRY)
	assert_eq(overlay.current().goal, Goal.PARRY, "parry comes after guard")
	_press_skip_key()
	assert_eq(overlay.current().goal, Goal.DODGE, "F1 skips the tip")
	source.tap(SimInput.DODGE, 60)
	_run_until(Goal.GRAB)
	source.tap(SimInput.GRAB, 80)
	_run_until(Goal.LOCK_ON)
	source.tap(SimInput.LOCK, 60)
	_run_until(Goal.NONE)
	assert_eq(overlay.completed, ["Move", "Light string", "Guard", "Dodge", "Grab", "Lock on"] as Array[String])
	_step(400)
	assert_true(overlay.is_done(), "the last tip times out")


func test_a_retry_skips_tips_already_learned() -> void:
	await _open_fight(&"fight_squire")
	source.hold(SimInput.make(0, 0, -127), 150)
	_run_until(Goal.LIGHT_STRING)
	screen.free()
	await _open_fight(&"fight_squire", false)
	_step(1)
	assert_eq(overlay.current().goal, Goal.LIGHT_STRING, "the retry starts at the first tip not yet done")


func test_fight_two_teaches_abilities_and_cuts_in_for_super_and_burst() -> void:
	await _open_fight(&"fight_two_hollowed")
	_step(1)
	assert_eq(overlay.current().goal, Goal.TARGET)
	source.tap(SimInput.LOCK, 20)
	source.tap(SimInput.TARGET_NEXT, 20)
	_run_until(Goal.ABILITY)
	assert_eq(overlay.current().ability_slot, 0, "ability 1 first")
	assert_has(FightPrompts.hint_for(overlay.current()), "1", "shows the ability 1 key")

	var player := screen.runner.sim.fighter(0)
	player.soul = 100 * 100
	_step(2)
	assert_eq(overlay.current().goal, Goal.SUPER, "full Soul brings up the super tip")
	assert_eq(overlay._counter.text, "Tip")
	source.tap(SimInput.SUPER, 120)
	_step(130)
	assert_has(overlay.completed, "Soul full")

	player = screen.runner.sim.fighter(0)
	player.soul = 60 * 100
	player.action = FighterState.Action.HITSTUN
	player.action_tick = 1
	player.stun = 40
	_step(2)
	assert_eq(overlay.current().goal, Goal.BURST, "caught in a combo with 50 Soul brings up Soul Burst")
	source.tap(SimInput.SUPER, 30)
	_step(40)
	assert_has(overlay.completed, "Caught")


func _open_fight(step_id: StringName, new_run: bool = true) -> void:
	if new_run:
		var story := StoryDirector.load_story()
		var save := StorySave.load_from()
		save.started = true
		save.next_step = story.step_index(step_id)
		director = StoryDirector.new(StoryRun.resume(story, save))
	GameFlow.current_match = director.match_config()
	screen = MATCH_SCENE.instantiate()
	host.add_child(screen)
	await wait_frames(1)
	var found := screen.find_children("*", "FightPrompts", true, false)
	assert_eq(found.size(), 1, "the story fight shows tips")
	overlay = found[0] as FightPrompts if not found.is_empty() else null
	source = QueueSource.new()
	screen.runner.paused = true
	screen.runner.sources[0] = source
	for slot in range(1, screen.runner.sources.size()):
		screen.runner.sources[slot] = null
	for i in 600:
		if screen.runner.sim.state.phase == SimState.Phase.FIGHT:
			break
		screen.runner.step_once()


func _step(ticks: int) -> void:
	for i in ticks:
		screen.runner.step_once()


## Steps until the tip shown has `goal` (or the queued input runs out).
func _run_until(goal: StoryPrompt.Goal) -> void:
	for i in 1500:
		if overlay.current() != null and overlay.current().goal == goal:
			return
		screen.runner.step_once()
	fail("never reached tip %s (at %s)" % [goal, overlay.current().title if overlay.current() != null else "none"])


func _press_skip_key() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F1
	key.pressed = true
	overlay._input(key)

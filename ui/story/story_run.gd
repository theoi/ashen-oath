class_name StoryRun
extends RefCounted
## One playthrough of a story act, or a single chapter replayed from chapter select: which
## step is current, the difficulty, losses on the current fight, and the save. Pure logic
## (no scenes), so a whole act can be scripted in tests.

var data: StoryData
var save: StorySave
var index := 0
var difficulty := MatchConfig.Difficulty.NORMAL
## Losses on the current fight since it was last won or entered.
var losses := 0
## Replaying one step from chapter select: progress is not saved.
var chapter_only := false
## Fighters newly unlocked by the last won fight.
var new_unlocks: Array[StringName] = []
## How the last fight ended.
var last_result: MatchResult

var _end := 0


## Starts the act from the beginning and saves that (keeps the "completed" mark).
static func new_story(story: StoryData, story_save: StorySave, level: MatchConfig.Difficulty) -> StoryRun:
	var run := StoryRun._make(story, story_save, 0, story.steps.size())
	run.difficulty = level
	story_save.act = story.id
	story_save.started = true
	story_save.next_step = 0
	story_save.difficulty = level
	story_save.write()
	return run


## Continues from the saved step.
static func resume(story: StoryData, story_save: StorySave) -> StoryRun:
	var run := StoryRun._make(story, story_save, clampi(story_save.next_step, 0, story.steps.size()), story.steps.size())
	run.difficulty = story_save.difficulty
	return run


## Plays only step `step_index` (chapter select), then ends.
static func chapter(story: StoryData, story_save: StorySave, step_index: int, level: MatchConfig.Difficulty) -> StoryRun:
	var run := StoryRun._make(story, story_save, step_index, step_index + 1)
	run.difficulty = level
	run.chapter_only = true
	return run


static func _make(story: StoryData, story_save: StorySave, start: int, end: int) -> StoryRun:
	var run := StoryRun.new()
	run.data = story
	run.save = story_save
	run.index = start
	run._end = end
	return run


## The current step, or null once the run is over.
func step() -> StoryStep:
	return null if is_finished() else data.step(index)


func is_finished() -> bool:
	return index >= _end or index >= data.steps.size()


func current_fight() -> StoryFight:
	return step() as StoryFight


## Difficulty the CPU plays `fight` at: the chosen one, capped by the fight.
func fight_difficulty(fight: StoryFight) -> MatchConfig.Difficulty:
	if fight != null and fight.ai_cap >= 0:
		return mini(int(difficulty), fight.ai_cap) as MatchConfig.Difficulty
	return difficulty


## The match for `fight`. Callbacks and menus are added by the caller.
func match_config(fight: StoryFight) -> MatchConfig:
	var config := MatchConfig.new()
	config.mode = MatchConfig.Mode.STORY
	config.fighters = [fight.player]
	config.teams = [0]
	config.starting_soul = [0]
	config.hp_percent = [100]
	for i in fight.opponents.size():
		config.fighters.append(fight.opponents[i])
		config.teams.append(1)
		config.starting_soul.append(fight.opponent_soul[i] if i < fight.opponent_soul.size() else 0)
		config.hp_percent.append(fight.opponent_hp_percent[i] if i < fight.opponent_hp_percent.size() else 100)
		if i < fight.opponent_ai_profiles.size() and not fight.opponent_ai_profiles[i].is_empty():
			config.ai_profiles[i + 1] = fight.opponent_ai_profiles[i]
	config.arena = fight.arena
	config.difficulty = fight_difficulty(fight)
	config.ai_cap = fight.ai_cap
	config.rounds_to_win = fight.rounds_to_win
	config.round_seconds = fight.round_seconds
	config.seed = fight.seed
	return config


## Records how the current fight ended. A win unlocks the fight's fighters and saves
## progress (unless replaying a chapter). Returns true for a win; a draw counts as a loss.
func record(result: MatchResult) -> bool:
	last_result = result
	new_unlocks.clear()
	var fight := current_fight()
	if fight == null:
		return false
	if not result.player_won():
		losses += 1
		return false
	losses = 0
	for id in fight.unlocks:
		if Profile.unlock_fighter(id):
			new_unlocks.append(id)
	if not chapter_only:
		save.next_step = index + 1
		save.difficulty = difficulty
		save.write()
	return true


## Moves to the next step. Finishing the act marks it completed and saves.
func advance() -> void:
	index += 1
	losses = 0
	if is_finished() and not chapter_only:
		save.completed = true
		save.next_step = data.steps.size()
		save.write()


## "Retry on lower difficulty" is offered after two losses, while there is a lower level.
func can_lower_difficulty() -> bool:
	return losses >= 2 and fight_difficulty(current_fight()) > MatchConfig.Difficulty.EASY


func lower_difficulty() -> void:
	set_difficulty(maxi(0, int(fight_difficulty(current_fight())) - 1) as MatchConfig.Difficulty)


func set_difficulty(level: MatchConfig.Difficulty) -> void:
	difficulty = level
	if not chapter_only:
		save.difficulty = level
		save.write()

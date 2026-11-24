class_name StorySave
extends RefCounted
## Story progress, persisted to user://story.cfg: where to continue, the chosen difficulty,
## and whether the act has been completed (chapter select). Saved automatically after each
## won fight and when the act ends. Load never logs errors: a missing or unreadable file
## means a fresh save.

const DEFAULT_PATH := "user://story.cfg"

## Where saves are read and written by default. Tests and the playthrough tool point this
## elsewhere so they never touch the player's save.
static var default_path := DEFAULT_PATH

var path := DEFAULT_PATH
var act: StringName = &"act1"
## Index in StoryData.steps to continue from.
var next_step := 0
## A story has been started (Continue is offered while next_step is inside the act).
var started := false
## The act has been finished once: chapter select is open.
var completed := false
var difficulty := MatchConfig.Difficulty.NORMAL


static func load_from(file_path: String = default_path) -> StorySave:
	var save := StorySave.new()
	save.path = file_path
	save.difficulty = Settings.default_difficulty
	if not FileAccess.file_exists(file_path):
		return save
	var config := ConfigFile.new()
	if config.parse(FileAccess.get_file_as_string(file_path)) != OK:
		return save
	var act_id: Variant = config.get_value("story", "act", "act1")
	if act_id is String or act_id is StringName:
		save.act = StringName(act_id)
	var step: Variant = config.get_value("story", "next_step", 0)
	if step is int and step >= 0:
		save.next_step = step
	var started_value: Variant = config.get_value("story", "started", false)
	if started_value is bool:
		save.started = started_value
	var completed_value: Variant = config.get_value("story", "completed", false)
	if completed_value is bool:
		save.completed = completed_value
	var level: Variant = config.get_value("story", "difficulty", int(save.difficulty))
	if level is int and level >= 0 and level < MatchConfig.Difficulty.size():
		save.difficulty = level as MatchConfig.Difficulty
	return save


## True when there is a story to continue in an act with `step_count` steps.
func can_continue(step_count: int) -> bool:
	return started and next_step < step_count


func write() -> Error:
	var config := ConfigFile.new()
	config.set_value("story", "act", String(act))
	config.set_value("story", "next_step", next_step)
	config.set_value("story", "started", started)
	config.set_value("story", "completed", completed)
	config.set_value("story", "difficulty", int(difficulty))
	return config.save(path)

class_name MatchConfig
extends RefCounted
## What the menus (or story mode) hand to a match: who fights where, and how.
##
## Slot 0 is the local player. Fighters on the same team are allies; the slice uses 1v1 and
## 1v2 (teams [0, 1, 1]).

enum Difficulty { EASY, NORMAL, HARD, NIGHTMARE }
enum Mode { VERSUS, STORY }

const DIFFICULTY_NAMES: PackedStringArray = ["Easy", "Normal", "Hard", "Nightmare"]

var mode := Mode.VERSUS
## Fighter id per slot (content ids, e.g. &"aldric").
var fighters: Array[StringName] = []
## Team per slot.
var teams: Array[int] = []
## Which slots a local player controls; the rest are CPU.
var human_slots: Array[int] = [0]
## Demo / capture: every slot is a CPU (MatchSetup.cpu_source; the HUD still follows slot 0).
var attract := false
var arena: StringName = &"ashen_chapel"
var difficulty := Difficulty.NORMAL
## Rounds a team needs to win the match (2 = best of 3).
var rounds_to_win := 2
var round_seconds := 99
## Simulation RNG seed.
var seed := 1
## Starting Soul per slot (story: the Oath-Shade starts with 50). Missing entries mean 0.
var starting_soul: Array[int] = []
## Max HP percent per slot (handicaps, story grunts). Missing entries mean 100.
var hp_percent: Array[int] = []
## Called with the MatchResult when the match ends, instead of the versus results screen.
var on_finished: Callable
## Called with the MatchScreen once it is set up (story mode adds its in-fight prompts).
var on_started: Callable
## Menu screens to return to when leaving the match (bottom first).
var menu_stack: Array[StringName] = [&"mode_select", &"versus"]


static func difficulty_name(value: Difficulty) -> String:
	return DIFFICULTY_NAMES[value]


static func versus(player: StringName, opponent: StringName, arena_id: StringName, level: Difficulty) -> MatchConfig:
	var config := MatchConfig.new()
	config.fighters = [player, opponent]
	config.teams = [0, 1]
	config.arena = arena_id
	config.difficulty = level
	return config


func slot_count() -> int:
	return fighters.size()


func is_human(slot: int) -> bool:
	return slot in human_slots


func duplicate_config() -> MatchConfig:
	var copy := MatchConfig.new()
	copy.mode = mode
	copy.fighters = fighters.duplicate()
	copy.teams = teams.duplicate()
	copy.human_slots = human_slots.duplicate()
	copy.attract = attract
	copy.arena = arena
	copy.difficulty = difficulty
	copy.rounds_to_win = rounds_to_win
	copy.round_seconds = round_seconds
	copy.seed = seed
	copy.starting_soul = starting_soul.duplicate()
	copy.hp_percent = hp_percent.duplicate()
	copy.on_finished = on_finished
	copy.on_started = on_started
	copy.menu_stack = menu_stack.duplicate()
	return copy

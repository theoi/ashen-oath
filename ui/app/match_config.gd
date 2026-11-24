class_name MatchConfig
extends RefCounted
## What the menus hand to a match: who fights where, and how.

enum Difficulty { EASY, NORMAL, HARD, NIGHTMARE }

const DIFFICULTY_NAMES: PackedStringArray = ["Easy", "Normal", "Hard", "Nightmare"]


static func difficulty_name(value: Difficulty) -> String:
	return DIFFICULTY_NAMES[value]

class_name StoryFight
extends StoryStep
## A story fight: who Aldric faces, where, and under what rules.

## The player's fighter.
@export var player: StringName = &"aldric"
## One fighter id per opponent (two for a 1v2). All opponents share a team.
@export var opponents: Array[StringName] = []
## Name used on the results card and in chapter select ("Hollowed Squire").
@export var opponent_name: String = ""
@export var arena: StringName = &"ashen_chapel"
## Rounds a side needs to win (1 = single round, 2 = best of 3).
@export var rounds_to_win: int = 2
## Round timer in seconds (-1 = no timer).
@export var round_seconds: int = 99
## Highest CPU difficulty for this fight (MatchConfig.Difficulty; -1 = no cap).
@export var ai_cap: int = -1
## Max HP percent per opponent (missing = 100).
@export var opponent_hp_percent: Array[int] = []
## Starting Soul per opponent (missing = 0).
@export var opponent_soul: Array[int] = []
## Sim seed for the fight.
@export var seed: int = 1
## Fighters unlocked for versus when this fight is won.
@export var unlocks: Array[StringName] = []
## Prompts shown in order during the fight (the tutorial in fight 1).
@export var prompts: Array[StoryPrompt] = []

class_name SlotConfig
extends Resource
## One fighter slot in a match.

@export var fighter: FighterData
## Fighters on the same team never hit each other.
@export var team: int = 0
## Soul at match start, whole points (the Oath-Shade starts with 50).
@export var start_soul: int = 0
## Max HP as percent of the fighter's (handicaps, story grunts).
@export var hp_percent: int = 100
## Absolute max HP (boss HP); replaces hp_percent when > 0.
@export var hp_override: int = 0
## Spawn point index in ArenaData.spawn_points (-1 = slot index).
@export var spawn: int = -1
## Boss stagger bar size (0 = none).
@export var stagger_max: int = 0
## Frames after a counter window opens during which this fighter's next counter windows
## are suppressed (no blue flash, not counterable). Bosses: one per 15-20 s. 0 = no limit.
@export var counter_window_cooldown: int = 0

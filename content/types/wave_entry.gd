class_name WaveEntry
extends Resource
## One group of a wave: `count` copies of `fighter`, spawned into free combatant slots.

@export var fighter: FighterData
@export var count: int = 1
@export var team: int = 1
## ArenaData.spawn_points index (-1 = the next point in rotation).
@export var spawn: int = -1
## Frames after the wave starts before the first one spawns, and between the others.
@export var delay: int = 0
@export var interval: int = 0
## Max HP as percent of the fighter's, or an absolute value when hp_override > 0 (bosses).
@export var hp_percent: int = 100
@export var hp_override: int = 0
@export var start_soul: int = 0
## Boss stagger bar size (0 = none) and counter-window limit (SlotConfig).
@export var stagger_max: int = 0
@export var counter_window_cooldown: int = 0

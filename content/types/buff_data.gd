class_name BuffData
extends Resource
## A timed modifier on a fighter (e.g. Aldric's ignited blade after a parry).

@export var id: StringName = &""
## Duration in frames.
@export var duration: int = 180
## Extra outgoing damage in percent (30 = +30%).
@export var damage_bonus_percent: int = 0
## Run speed change in percent.
@export var speed_bonus_percent: int = 0
## Removed after this many hits land (0 = lasts the full duration).
@export var uses: int = 0
@export var cue: StringName = &""

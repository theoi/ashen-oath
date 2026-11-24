class_name BuffData
extends Resource
## A timed modifier on a fighter (e.g. Aldric's ignited blade after a parry).

@export var id: StringName = &""
## Duration in frames.
@export var duration: int = 180
## Extra outgoing damage in percent (30 = +30%).
@export var damage_bonus_percent: int = 0
## Run speed change in percent; negative slows (the total is floored at -100).
@export var speed_bonus_percent: int = 0
## Lasts for this many casts that deal damage (0 = the full duration). A cast is one move
## started after the buff, with every hit of it and of its effects; the move running when
## the buff is applied does not use it.
@export var uses: int = 0
## Armor while active, in any action (Iron Hide): flinch immune or push immune, as the
## MoveData windows (no reaction, full damage, half hitstop, ARMOR event).
enum Armor { NONE, FLINCH_IMMUNE, PUSH_IMMUNE }
@export var armor: Armor = Armor.NONE
## Damage taken change in percent (-30 = takes 30% less); the total is floored at -100.
@export var damage_taken_percent: int = 0
@export var cue: StringName = &""

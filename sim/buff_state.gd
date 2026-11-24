class_name BuffState
extends SimRecord
## An active buff on a fighter. Values are copied from BuffData when applied.

## Where it came from: a move index of the owner, or -1 for FighterData.parry_buff,
## -2 for a FighterTrait.
var source: int = -1
## Hash of BuffData.id for victim buffs (they replace by id), else 0.
var key: int = 0
var ticks_left: int = 0
var uses_left: int = 0
## Buffs with uses apply to casts with a FighterState.move_cast above this (not the one
## running when they were applied).
var after_cast: int = 0
## The last cast that spent a use; its later hits keep the bonus.
var last_cast: int = -1
## All uses are spent; the buff ends once last_cast is over.
var spent: bool = false
var damage_bonus_percent: int = 0
var speed_bonus_percent: int = 0
## BuffData.Armor and damage_taken_percent.
var armor: int = 0
var damage_taken_percent: int = 0

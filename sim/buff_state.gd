class_name BuffState
extends SimRecord
## An active buff on a fighter. Values are copied from BuffData when applied.

## Where it came from: a move index of the owner, or -1 for FighterData.parry_buff,
## -2 for a FighterTrait.
var source: int = -1
var ticks_left: int = 0
var uses_left: int = 0
var damage_bonus_percent: int = 0
var speed_bonus_percent: int = 0

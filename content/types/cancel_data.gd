class_name CancelData
extends Resource
## A window of move frames in which another action may interrupt this move.

enum Condition { ALWAYS, ON_CONTACT, ON_HIT }

## Bit flags for `into`.
const INTO_ABILITY := 1
const INTO_SUPER := 2
const INTO_JUMP := 4
const INTO_DODGE := 8
const INTO_LIGHT := 16
const INTO_HEAVY := 32

@export var start_frame: int = 1
@export var end_frame: int = 99
@export var condition: Condition = Condition.ON_CONTACT
@export_flags("Ability", "Super", "Jump", "Dodge", "Light", "Heavy") var into: int = INTO_ABILITY

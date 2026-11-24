class_name StoryPrompt
extends Resource
## An in-fight tip: what to try, the buttons for it, when it appears and what counts as done.

enum Goal {
	## Shown for `timeout_seconds`, then the next prompt.
	NONE,
	## Run `amount` meters.
	MOVE,
	## `amount` light attacks in one string.
	LIGHT_STRING,
	## Block an attack, or hold guard for `amount` frames.
	GUARD,
	## Dodge roll or air dodge `amount` times.
	DODGE,
	## Start a grab.
	GRAB,
	## Use an ability (`ability_slot`, or any when -1).
	ABILITY,
	## Lock onto targets `amount` times (2 = lock on, then switch).
	TARGET,
	## Use a Soul Burst.
	BURST,
	## Parry an attack.
	PARRY,
	## Turn hard lock-on on.
	LOCK_ON,
	## Start the super.
	SUPER,
}

enum Trigger {
	## Shown in list order, one after another.
	IN_ORDER,
	## Shown whenever the player's Soul is full (and the super is not yet used).
	SOUL_FULL,
	## Shown while the player is caught in a combo with enough Soul to burst.
	IN_COMBO,
}

@export var goal: Goal = Goal.NONE
@export var trigger: Trigger = Trigger.IN_ORDER
@export var amount: int = 1
## Ability slot 0-2 for ABILITY goals (-1 = any ability).
@export var ability_slot: int = -1
## Empty for an ability tip = the fighter's name for that ability.
@export var title: String = ""
@export_multiline var text: String = ""
## Actions whose buttons are shown (DefaultBindings names; &"move" for the move stick/keys).
## Empty = the input of the goal: the ability slot's action, or super for SUPER / BURST.
@export var actions: Array[StringName] = []
## > 0: move on after this many seconds even if the goal was not met.
@export var timeout_seconds: float = 0.0

class_name StoryPrompt
extends Resource
## An in-fight prompt: what to try, the buttons for it, and what counts as done.

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
	## Use any ability.
	ABILITY,
	## Switch or lock onto a target.
	TARGET,
	## Use a Soul Burst.
	BURST,
}

@export var goal: Goal = Goal.NONE
@export var amount: int = 1
@export var title: String = ""
@export_multiline var text: String = ""
## Actions whose default bindings are shown (DefaultBindings names).
@export var actions: Array[StringName] = []
## Replaces the binding line (e.g. "Left stick  ·  W A S D").
@export var hint: String = ""
## > 0: move on after this many seconds even if the goal was not met.
@export var timeout_seconds: float = 0.0

class_name StoryLine
extends Resource
## One beat of a scene: a dialogue line (portrait, name, typewriter text) or a full-screen
## title card.

enum Kind { DIALOGUE, CARD }

@export var kind: Kind = Kind.DIALOGUE
## Fighter id of the speaker (portrait from their model); empty = narration, no portrait.
@export var speaker: StringName = &""
## Name shown in the dialogue box; empty = the fighter's roster name.
@export var speaker_name: String = ""
## Card heading (cards only).
@export var title: String = ""
@export_multiline var text: String = ""
## Switches the camera to StoryScene.shots[shot] when this line starts (-1 = keep).
@export var shot: int = -1
## Sound cue played when the line starts (e.g. &"bell_toll").
@export var cue: StringName = &""

class_name StoryStep
extends Resource
## One entry in a story's sequence: a scene (StoryScene) or a fight (StoryFight).
## Chapter select lists steps by `title`.

@export var id: StringName = &""
## Shown in chapter select.
@export var title: String = ""

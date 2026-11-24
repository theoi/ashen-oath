class_name StoryScene
extends StoryStep
## A story scene: in-engine stills of a dressed arena with posed characters, read as a
## sequence of dialogue lines and full-screen title cards.

## Arena id (Roster / content/arenas) dressed for the stills; empty = darkness (cards only).
@export var arena: StringName = &""
## Camera setups; a line switches to one with StoryLine.shot. The scene opens on shots[0].
@export var shots: Array[StoryShot] = []
@export var actors: Array[StoryActor] = []
## Extra set dressing on top of the arena (fallen coffins, bones).
@export var props: Array[StoryProp] = []
@export var lines: Array[StoryLine] = []

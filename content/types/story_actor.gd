class_name StoryActor
extends Resource
## A character held in a pose for a scene: the fighter's in-game model, posed with one clip
## of the shared KayKit animation set.

## Fighter id (Roster / content/fighters); its FighterData.scene is the model.
@export var fighter: StringName = &""
## Floor position in arena world space (y is usually 0).
@export var position: Vector3 = Vector3.ZERO
## Yaw in degrees; 0 faces +Z (toward the default camera side).
@export var facing_degrees: float = 0.0
## Clip of the shared animation set: Idle, Idle_Combat, Lie_Idle, Sit_Floor_Idle, Cheer,
## Taunt, Death_A, Blocking, Spellcasting... Unknown clips fall back to Idle.
@export var pose: StringName = &"Idle"
## Seconds into the clip to hold; negative = loop the clip from the start (breathing idles).
@export var pose_time: float = -1.0
## The actor is shown from this line index (0 = from the start)...
@export var enter_line: int = 0
## ...until this line index, exclusive (-1 = to the end).
@export var exit_line: int = -1
## Uniform scale on top of the model's own (silhouettes, distant figures).
@export var scale: float = 1.0


## Visible while line `index` is shown.
func is_present(index: int) -> bool:
	return index >= enter_line and (exit_line < 0 or index < exit_line)

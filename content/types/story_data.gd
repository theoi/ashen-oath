class_name StoryData
extends Resource
## A story act: its scenes and fights in play order. Adding a fight or a scene is a data
## change: insert StoryFight / StoryScene resources into `steps`.

@export var id: StringName = &""
@export var title: String = ""
@export var subtitle: String = ""
@export_multiline var blurb: String = ""
@export var steps: Array[StoryStep] = []


func step(index: int) -> StoryStep:
	return steps[index] if index >= 0 and index < steps.size() else null


func step_index(step_id: StringName) -> int:
	for i in steps.size():
		if steps[i].id == step_id:
			return i
	return -1


## The fights in order.
func fights() -> Array[StoryFight]:
	var result: Array[StoryFight] = []
	for s in steps:
		if s is StoryFight:
			result.append(s)
	return result


## 1-based position of the fight among the fights (0 if not a fight of this story).
func fight_number(fight: StoryFight) -> int:
	return fights().find(fight) + 1

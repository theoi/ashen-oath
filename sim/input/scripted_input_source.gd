class_name ScriptedInputSource
extends InputSource
## Frames from a per-tick list (index = sim tick before the step), neutral past the end.
## Handy for tests, demos and tutorials.

var frames: PackedInt32Array = PackedInt32Array()
## Repeat from the start instead of going neutral at the end.
var loop: bool = false


func _init(source_frames: PackedInt32Array = PackedInt32Array(), looping: bool = false) -> void:
	frames = source_frames
	loop = looping


func next_frame(sim: Sim, _slot: int) -> int:
	if frames.is_empty():
		return 0
	var index := sim.state.tick
	if loop:
		index %= frames.size()
	return frames[index] if index < frames.size() else 0

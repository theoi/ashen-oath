class_name ReplayInputSource
extends InputSource
## Plays one slot's recorded frames. Indexed by sim tick, so it also works after a restore.

var replay: Replay
var slot: int = 0


func _init(source_replay: Replay, source_slot: int) -> void:
	replay = source_replay
	slot = source_slot


func next_frame(sim: Sim, _slot: int) -> int:
	return replay.frame(sim.state.tick, slot)

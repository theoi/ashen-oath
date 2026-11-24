class_name InputSource
extends RefCounted
## Produces the SimInput frame for one slot each tick. Local devices, the CPU opponent,
## replays and (later) the network all implement this, so the sim cannot tell them apart.
## Sources may read the sim (as a player sees the screen) but never write it.


## Frame for `slot` for the next step (the sim is at tick sim.state.tick).
func next_frame(_sim: Sim, _slot: int) -> int:
	return 0

class_name Replay
extends Resource
## A recorded match: its config plus one SimInput frame per slot per tick. Stepping a fresh
## Sim built from `config` with these frames reproduces the match exactly. Optional
## per-tick checksums detect desyncs (e.g. after a code change: golden replays).
##
## Save with ResourceSaver (.res or .tres); the config references content by path.

## 2: 64-bit frames with aim (SimInput).
const FORMAT_VERSION := 2

@export var format_version: int = FORMAT_VERSION
@export var config: SimConfig
@export var slot_count: int = 2
## Tick-major: frames[tick * slot_count + slot].
@export var frames: PackedInt64Array = PackedInt64Array()
## Checksum after each recorded tick (empty when not recorded).
@export var checksums: PackedInt64Array = PackedInt64Array()


static func create(sim_config: SimConfig) -> Replay:
	var replay := Replay.new()
	replay.config = sim_config
	replay.slot_count = sim_config.total_slots()
	return replay


func tick_count() -> int:
	return frames.size() / maxi(1, slot_count)


## Appends one tick of inputs (PackedInt64Array or PackedInt32Array, as for Sim.step) and
## optionally the checksum after stepping it.
func record(inputs: Variant, checksum: int = 0, with_checksum: bool = false) -> void:
	var count: int = inputs.size()
	for slot in slot_count:
		var frame: int = inputs[slot] if slot < count else 0
		frames.append(SimInput.normalized(frame))
	if with_checksum:
		checksums.append(checksum)


## Inputs of tick `index` (0-based: the inputs passed to the index-th step).
func inputs_at(index: int) -> PackedInt64Array:
	var start := index * slot_count
	return frames.slice(start, start + slot_count)


func frame(index: int, slot: int) -> int:
	var i := index * slot_count + slot
	return frames[i] if i < frames.size() else 0


## Replays into a fresh Sim. Returns the first tick index whose checksum differs from the
## recorded one, or -1 if all match (or none were recorded).
func verify() -> int:
	var sim := Sim.new(config)
	for i in tick_count():
		sim.step(inputs_at(i))
		if i < checksums.size() and checksums[i] != sim.checksum():
			return i
	return -1

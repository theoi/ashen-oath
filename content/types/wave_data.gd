class_name WaveData
extends Resource
## One wave of a story fight (SimConfig.waves). The next wave starts once every entry has
## spawned and either at most `advance_alive` of this wave's fighters are still alive or
## `advance_frames` have passed since the wave started.

@export var entries: Array[WaveEntry] = []
@export var advance_alive: int = 1
## 0 = no timer.
@export var advance_frames: int = 1500

class_name AiRng
extends RefCounted
## Small deterministic RNG for the CPU opponent (xorshift32 on an int). The CPU never touches
## the sim's RNG (input sources must not write the sim); its own stream is derived from the
## match seed and the slot, so the same match config plays out the same way every time.

var state: int = 1


func _init(seed_value: int = 1) -> void:
	reseed(seed_value)


func reseed(seed_value: int) -> void:
	state = (seed_value ^ 0x6C8E9CF5) & 0xFFFFFFFF
	if state == 0:
		state = 1
	for _i in 4:
		next_u32()


func next_u32() -> int:
	var x := state
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	state = x
	return x


## Integer in [0, n).
func below(n: int) -> int:
	return next_u32() % n if n > 0 else 0


## Integer in [lo, hi].
func range_i(lo: int, hi: int) -> int:
	return lo + below(hi - lo + 1) if hi > lo else lo


## True with `percent` % probability.
func chance(percent: int) -> bool:
	if percent <= 0:
		return false
	if percent >= 100:
		return true
	return below(100) < percent

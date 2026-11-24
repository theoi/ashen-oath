class_name AiAttackTokens
extends RefCounted
## Attack tokens shared by the CPU fighters of one team (design §6, 1v2 fairness): only
## `capacity` of them may commit to an attack at a time; the others circle or reposition.
## Sources ask in slot order every tick, so grants are deterministic.

var capacity: int = 1
## Frames a fighter may keep a token while not attacking before it must pass it on.
var max_hold: int = 150
## Frames a fighter waits after giving a token back before asking again (lets others act).
var rest: int = 40

var _holder_since: Dictionary[int, int] = {}
var _rest_until: Dictionary[int, int] = {}


func _init(token_count: int = 1) -> void:
	capacity = maxi(1, token_count)


func holds(slot: int) -> bool:
	return _holder_since.has(slot)


func holder_count() -> int:
	return _holder_since.size()


## Takes a token for `slot` if one is free. Returns whether `slot` holds one now.
func acquire(slot: int, tick: int) -> bool:
	if _holder_since.has(slot):
		return true
	if tick < _rest_until.get(slot, -1) or _holder_since.size() >= capacity:
		return false
	_holder_since[slot] = tick
	return true


func release(slot: int, tick: int) -> void:
	if _holder_since.erase(slot):
		_rest_until[slot] = tick + rest


## Frames `slot` has held its token (0 if none).
func held_for(slot: int, tick: int) -> int:
	return tick - _holder_since[slot] if _holder_since.has(slot) else 0


func reset() -> void:
	_holder_since.clear()
	_rest_until.clear()

class_name FighterData
extends Resource
## A fighter's stats and move list. Universal actions (run, jump, dodge, guard, burst) use
## these stats; attacks reference moves in `moves` by id.

@export var id: StringName = &""
@export var display_name: String = ""
@export var max_hp: int = 1000

@export_group("Body")
## Hurt/collision capsule.
@export var radius: float = 0.45
@export var height: float = 1.8
## Launch height multiplier (heavier fighters fly less).
@export var weight: float = 1.0

@export_group("Movement")
@export var run_speed: float = 6.5
@export var accel_frames: int = 5
@export var stop_frames: int = 4
@export var turn_degrees: float = 30.0
@export var jump_squat: int = 3
@export var jump_height: float = 1.6
@export var jump_airtime: int = 42
## Fraction of ground acceleration available in the air.
@export var air_control: float = 0.5
@export var jumps: int = 1

@export_group("Dodge")
@export var dodge_frames: int = 24
@export var dodge_invuln_start: int = 3
@export var dodge_invuln_end: int = 14
@export var dodge_distance: float = 3.5
## Frames during which the roll moves (the rest is recovery).
@export var dodge_move_frames: int = 18
## Frames after a roll before the next one.
@export var dodge_cooldown: int = 6
@export var air_dodge_frames: int = 18
@export var air_dodge_invuln_start: int = 2
@export var air_dodge_invuln_end: int = 12
@export var air_dodge_distance: float = 2.0

@export_group("Defense")
## Frames after a guard press in which a hit is parried (CombatRules default is 6).
@export var parry_window: int = 6
## Buff gained on a successful parry (Aldric's Oathkeeper), optional.
@export var parry_buff: BuffData

@export_group("Moves")
@export var moves: Array[MoveData] = []
@export var light: StringName = &""
@export var heavy: StringName = &""
@export var run_light: StringName = &""
@export var air_light: StringName = &""
@export var air_heavy: StringName = &""
@export var grab: StringName = &""
@export var getup_attack: StringName = &""
## Ability slots 1-3 (approach, launch/control, utility).
@export var abilities: Array[StringName] = []
@export var super_move: StringName = &""
## Optional FighterTrait script for unusual traits (stored charges, custom reactions).
@export var trait_script: Script

@export_group("Presentation")
## Presentation scene path (models, animation); the sim ignores it.
@export var scene: String = ""
@export var portrait: String = ""
## AI profile resource for the CPU opponent; the sim ignores it.
@export var ai_profile: Resource

var _index: Dictionary[StringName, int] = {}


## Index of the move with `move_id` in `moves`, or -1.
func find_move(move_id: StringName) -> int:
	if move_id == &"":
		return -1
	if _index.size() != moves.size():
		_index.clear()
		for i in moves.size():
			_index[moves[i].id] = i
	return _index.get(move_id, -1)


func move_by_id(move_id: StringName) -> MoveData:
	var index := find_move(move_id)
	return moves[index] if index >= 0 else null

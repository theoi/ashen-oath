class_name AiProfile
extends Resource
## How one fighter likes to play (design §6): preferred range and intent weights. The CPU
## picks moves from the fighter's own MoveData, so a profile only biases the choices.
##
## Lookup: FighterData.ai_profile if set, else content/ai/profiles/<fighter id>.tres, else
## the default profile. Story fights can pass a profile explicitly (the Oath-Shade).

const PROFILE_DIR := "res://content/ai/profiles/"
const DEFAULT_PATH := "res://content/ai/profiles/default.tres"

@export var id: StringName = &"default"

@export_group("Range")
## Distance band (meters) the fighter tries to fight from.
@export var preferred_min: float = 1.2
@export var preferred_max: float = 3.0

@export_group("Intent weights (percent)")
@export var approach: int = 100
@export var pressure: int = 100
@export var zone: int = 100
@export var bait: int = 100
@export var defend: int = 100
@export var retreat: int = 100
@export var punish: int = 100

@export_group("Habits (percent)")
## Overall offensive bias added to the difficulty's aggression.
@export var aggression: int = 100
## Chance to pick a jump-in when approaching from mid range.
@export var jump_in: int = 8
## Chance to grab a guarding opponent at close range.
@export var grab: int = 30
## Chance to charge a heavy against a turtling opponent.
@export var charge: int = 20
## Skill-kit fighters: chance per strategy decision to dash in from mid range.
@export var dash_in: int = 30
## Chance to meet a seen attack with an armored move that absorbs it (Normal and up).
@export var armor_answer: int = 30
## Weight of each ability slot when choosing moves (percent, slots 1-3).
@export var ability_bias: PackedInt32Array = PackedInt32Array([100, 100, 100])
## Burst a little earlier (positive) or later (negative), in combo hits.
@export var burst_bias: int = 0


static func for_fighter(data: FighterData) -> AiProfile:
	if data != null and data.ai_profile is AiProfile:
		return data.ai_profile as AiProfile
	if data != null and data.id != &"":
		var path := PROFILE_DIR + String(data.id) + ".tres"
		if ResourceLoader.exists(path):
			return load(path) as AiProfile
	return load(DEFAULT_PATH) as AiProfile


static func by_id(profile_id: StringName) -> AiProfile:
	var path := PROFILE_DIR + String(profile_id) + ".tres"
	if ResourceLoader.exists(path):
		return load(path) as AiProfile
	return load(DEFAULT_PATH) as AiProfile


func ability_weight(slot: int) -> int:
	return ability_bias[slot] if slot >= 0 and slot < ability_bias.size() else 100

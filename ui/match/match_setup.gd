class_name MatchSetup
extends RefCounted
## Turns a menu-level MatchConfig into the sim's SimConfig and input sources.
##
## Content lookup: fighters and arenas are found through Roster ("data" paths). While a
## fighter or arena has no content yet, a stand-in is used so the match still runs: the test
## fighter (or a bare FighterData) and the training arena.

const RULES := "res://content/rules/default_rules.tres"
const FALLBACK_ARENA := "res://content/arenas/training_arena.tres"
const FALLBACK_FIGHTER := "res://content/fighters/test/test_fighter.tres"


static func sim_config(config: MatchConfig) -> SimConfig:
	var cfg := SimConfig.new()
	cfg.rules = load(RULES)
	cfg.arena = arena_data(config.arena)
	cfg.seed = config.seed
	cfg.rounds_to_win = config.rounds_to_win
	cfg.round_seconds = config.round_seconds
	for slot in config.slot_count():
		var slot_config := SlotConfig.new()
		slot_config.fighter = fighter_data(config.fighters[slot])
		slot_config.team = config.teams[slot]
		slot_config.start_soul = config.starting_soul[slot] if slot < config.starting_soul.size() else 0
		slot_config.hp_percent = config.hp_percent[slot] if slot < config.hp_percent.size() else 100
		cfg.slots.append(slot_config)
	return cfg


## One input source per slot: the local device for human slots, the CPU for the rest.
static func input_sources(config: MatchConfig, camera: Camera3D) -> Array[InputSource]:
	var sources: Array[InputSource] = []
	for slot in config.slot_count():
		sources.append(DeviceInputSource.new(camera) if config.is_human(slot) else cpu_source(config, slot))
	return sources


## The CPU opponent for `slot`. Until the AI lands this is null (the fighter stands still).
static func cpu_source(_config: MatchConfig, _slot: int) -> InputSource:
	return null


static func fighter_data(id: StringName) -> FighterData:
	var path: String = Roster.fighter(id).get("data", "")
	for candidate: String in [path, FALLBACK_FIGHTER]:
		if not candidate.is_empty() and ResourceLoader.exists(candidate):
			var data := load(candidate) as FighterData
			if data != null:
				return data
	var stand_in := FighterData.new()
	stand_in.id = id
	stand_in.display_name = Roster.fighter_name(id)
	return stand_in


static func arena_data(id: StringName) -> ArenaData:
	var path: String = Roster.arena(id).get("data", "")
	if not path.is_empty() and ResourceLoader.exists(path):
		return load(path)
	return load(FALLBACK_ARENA)


## The arena's presentation scene, or null when it has none yet.
static func arena_scene(id: StringName, data: ArenaData) -> PackedScene:
	var path: String = Roster.arena(id).get("scene", "")
	if data != null and not data.scene.is_empty():
		path = data.scene
	if not path.is_empty() and ResourceLoader.exists(path):
		return load(path)
	return null

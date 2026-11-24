class_name MatchSetup
extends RefCounted
## Turns a menu-level MatchConfig into the sim's SimConfig and input sources.
##
## Content lookup: fighters and arenas are found through Roster ("data" paths). While a
## fighter or arena has no content yet, a stand-in is used so the match still runs: the test
## fighter (or a bare FighterData) and the training arena.

const RULES := "res://content/rules/default_rules.tres"
const FALLBACK_ARENA := "res://content/arenas/training_arena.tres"
const FALLBACK_FIGHTER := "res://content/test_fighter/test_fighter.tres"


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


## One input source per slot: the local device for human slots, the CPU for the rest (every
## slot in attract mode).
static func input_sources(config: MatchConfig, camera: Camera3D) -> Array[InputSource]:
	var sources: Array[InputSource] = []
	# CPU fighters on one team share attack tokens (1v2: one attacker at a time).
	var per_team: Dictionary[int, int] = {}
	for slot in config.slot_count():
		if config.attract or not config.is_human(slot):
			per_team[config.teams[slot]] = per_team.get(config.teams[slot], 0) + 1
	var team_tokens: Dictionary[int, AiAttackTokens] = {}
	for team: int in per_team:
		if per_team[team] >= 2:
			team_tokens[team] = AiAttackTokens.new(cpu_difficulty(config).attack_tokens)
	for slot in config.slot_count():
		if config.attract or not config.is_human(slot):
			sources.append(cpu_source(config, slot, team_tokens.get(config.teams[slot])))
		else:
			sources.append(DeviceInputSource.new(camera))
	return sources


## The CPU opponent for `slot` at the match difficulty (capped by `ai_cap`), with the
## fighter's AI profile unless `ai_profiles` overrides it. Pass the team's shared tokens
## when several CPU fighters fight on one team.
static func cpu_source(config: MatchConfig, slot: int, tokens: AiAttackTokens = null) -> InputSource:
	var profile: AiProfile = null
	if config.ai_profiles.has(slot):
		profile = AiProfile.by_id(config.ai_profiles[slot])
	return AiInputSource.new(cpu_difficulty(config), profile, tokens)


static func cpu_difficulty(config: MatchConfig) -> AiDifficulty:
	return AiDifficulty.preset(config.difficulty, config.ai_cap)

static func fighter_data(id: StringName) -> FighterData:
	var path: String = Roster.fighter(id).get("data", "")
	if not path.is_empty() and ResourceLoader.exists(path):
		return load(path) as FighterData
	if ResourceLoader.exists(FALLBACK_FIGHTER):
		# Stand-in moves under the roster fighter's name until their data lands.
		var fallback := (load(FALLBACK_FIGHTER) as FighterData).duplicate() as FighterData
		fallback.display_name = Roster.fighter_name(id)
		return fallback
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
	var path := data.scene if data != null else ""
	if not path.is_empty() and ResourceLoader.exists(path):
		return load(path)
	return null

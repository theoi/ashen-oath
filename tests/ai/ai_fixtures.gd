class_name AiFixtures
extends RefCounted
## Builders for CPU opponent tests: AI-vs-AI configs and bouts on the test fighter.

const F := preload("res://tests/sim/sim_fixtures.gd")


## A config with one test fighter per entry of `teams`, on the training arena by default.
static func config(teams: Array[int], seed_value: int, round_seconds: int = 45, rounds_to_win: int = 1,
		arena_path: String = "res://content/arenas/training_arena.tres") -> SimConfig:
	var cfg := SimConfig.new()
	cfg.rules = load("res://content/rules/default_rules.tres")
	cfg.arena = load(arena_path)
	cfg.seed = seed_value
	cfg.round_seconds = round_seconds
	cfg.rounds_to_win = rounds_to_win
	for team in teams:
		var slot := SlotConfig.new()
		slot.fighter = F.test_fighter()
		slot.team = team
		cfg.slots.append(slot)
	return cfg


## CPU sources for every slot (level -1 = no source, the fighter stands still), with attack
## tokens shared by CPU teammates like AiInputSource.for_match.
static func sources(cfg: SimConfig, levels: Array[int]) -> Array[InputSource]:
	var cpu_slots := PackedInt32Array()
	var token_count := 1
	for slot in cfg.slots.size():
		if levels[slot] >= 0:
			cpu_slots.append(slot)
			token_count = maxi(token_count, AiDifficulty.preset(levels[slot]).attack_tokens)
	var team_tokens := AiInputSource.shared_tokens(cfg, cpu_slots, token_count)
	var result: Array[InputSource] = []
	for slot in cfg.slots.size():
		if levels[slot] < 0:
			result.append(null)
			continue
		result.append(AiInputSource.new(AiDifficulty.preset(levels[slot]), null,
				team_tokens.get(cfg.slots[slot].team)))
	return result


static func bout(cfg: SimConfig, levels: Array[int]) -> AiBout:
	return AiBout.new(cfg, sources(cfg, levels)).run()

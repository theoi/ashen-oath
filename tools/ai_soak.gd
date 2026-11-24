extends SceneTree
## AI-vs-AI soak and difficulty harness (headless, no rendering). Runs N seeded matches with
## the chosen fighters, arena and difficulties, then reports win rates, round lengths,
## timeouts, stuck states, engine errors and sim cost. Exit code 1 on errors (and on stuck
## states with --fail-on-stuck, on long combos with --fail-on-infinite), so CI or the final validation can use it as a soak test.
##
##   tools/ai_soak.sh --matches=40 --levels=nightmare,easy
##   tools/ai_soak.sh --fighters=aldric,hollowed,hollowed --levels=easy,hard,hard --arena=ashen_chapel
##
## See ai/README.md for every option.

const LEVELS: PackedStringArray = ["easy", "normal", "hard", "nightmare"]


class ErrorCollector extends Logger:
	var _mutex := Mutex.new()
	var errors: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		errors.append("%s (%s:%d, %s)" % [rationale if not rationale.is_empty() else code, file, line, function])
		_mutex.unlock()


var _collector := ErrorCollector.new()
var _opts: Dictionary[String, String] = {}


func _init() -> void:
	OS.add_logger(_collector)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var parts := arg.trim_prefix("--").split("=", true, 1)
			_opts[parts[0]] = parts[1] if parts.size() > 1 else "1"
	if _opts.has("help"):
		print(_usage())
		quit(0)
		return
	var code := _run()
	OS.remove_logger(_collector)
	quit(code)


func _usage() -> String:
	return "usage: tools/ai_soak.sh [--matches=20] [--seed=1] [--fighters=test_fighter,test_fighter]\n" \
		+ "  [--levels=normal,normal] [--teams=0,1] [--arena=training_arena] [--rounds=N] [--round-seconds=S]\n" \
		+ "  [--profiles=1:oath_shade] [--start-soul=1:50] [--cap=easy] [--no-swap] [--stuck-seconds=20]\n" \
		+ "  [--stuck-action-seconds=10] [--verify] [--json=path] [--replays=dir] [--save-all] [--quiet]\n" \
		+ "  [--fail-on-stuck] [--infinite-hits=20] [--infinite-seconds=8] [--fail-on-infinite]"


func _run() -> int:
	var fighter_ids := _list("fighters", "test_fighter,test_fighter")
	var slot_count := fighter_ids.size()
	var level_names := _list("levels", ",".join(_repeat("normal", slot_count)))
	var teams := _list("teams", "")
	var arena_path := _resolve_arena(_opts.get("arena", "training_arena"))
	var matches := int(_opts.get("matches", "20"))
	var base_seed := int(_opts.get("seed", "1"))
	var quiet := _opts.has("quiet")
	var swap := not _opts.has("no-swap") and slot_count == 2
	var cap := LEVELS.find(_opts.get("cap", "")) if _opts.has("cap") else -1
	if slot_count < 1 or slot_count > 4 or level_names.size() != slot_count:
		push_error("need 1-4 fighters and one level per fighter (got %d fighters, %d levels)" % [slot_count, level_names.size()])
		return 1
	var fighters: Array[FighterData] = []
	for id in fighter_ids:
		var data := _resolve_fighter(id)
		if data == null:
			push_error("unknown fighter '%s'" % id)
			return 1
		fighters.append(data)
	var arena := load(arena_path) as ArenaData
	if arena == null:
		push_error("unknown arena '%s'" % arena_path)
		return 1
	var profile_overrides := _slot_map("profiles")
	var start_soul := _slot_map("start-soul")
	var labels := PackedStringArray()
	var team_of := PackedInt32Array()
	for slot in slot_count:
		var team := int(teams[slot]) if slot < teams.size() else (0 if slot == 0 else 1)
		team_of.append(team)
		labels.append("%s %s" % [level_names[slot], fighters[slot].id])

	print("AI soak: %d matches, %s, arena %s, seed %d%s" % [matches, " vs ".join(labels),
			arena.id, base_seed, ", sides swapped every other match" if swap else ""])
	var team_names: Dictionary[int, String] = {}
	for slot in slot_count:
		var name: String = team_names.get(team_of[slot], "")
		team_names[team_of[slot]] = labels[slot] if name.is_empty() else name + " + " + labels[slot]
	var wins: Dictionary[int, int] = {}
	var draws := 0
	var unfinished := 0
	var round_ticks := 0
	var round_count := 0
	var timeouts := 0
	var stuck_reports: PackedStringArray = []
	var combo_reports: PackedStringArray = []
	var longest_hits := 0
	var longest_ticks := 0
	var verify_failures := 0
	var total_ticks := 0
	var sim_usec := 0
	var input_usec := 0
	var totals: Array[Dictionary] = []
	for slot in slot_count:
		var counters: Dictionary = {}
		for key in AiBout.SUM_KEYS:
			counters[key] = 0
		totals.append(counters)
	var match_reports: Array[Dictionary] = []
	var ai_counters: Array[Dictionary] = []
	for _slot in slot_count:
		ai_counters.append({})
	var replay_dir: String = _opts.get("replays", "")
	if not replay_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(replay_dir)

	for m in matches:
		var cfg := SimConfig.new()
		cfg.rules = load("res://content/rules/default_rules.tres")
		cfg.arena = arena
		cfg.seed = base_seed + m
		if _opts.has("rounds"):
			cfg.rounds_to_win = int(_opts["rounds"])
		if _opts.has("round-seconds"):
			cfg.round_seconds = int(_opts["round-seconds"])
		var swapped := swap and m % 2 == 1
		for slot in slot_count:
			var sc := SlotConfig.new()
			sc.fighter = fighters[slot]
			sc.team = team_of[slot]
			sc.start_soul = int(start_soul.get(slot, "0"))
			if swapped:
				sc.spawn = 1 - slot
			cfg.slots.append(sc)
		var sources := _sources(cfg, level_names, profile_overrides, cap)
		var bout := AiBout.new(cfg, sources)
		bout.record_checksums = _opts.has("verify")
		bout.stuck_no_damage_ticks = roundi(float(_opts.get("stuck-seconds", "20")) * 60.0)
		bout.stuck_action_ticks = roundi(float(_opts.get("stuck-action-seconds", "10")) * 60.0)
		bout.long_combo_hits = int(_opts.get("infinite-hits", "20"))
		bout.long_combo_ticks = roundi(float(_opts.get("infinite-seconds", "8")) * 60.0)
		bout.run()
		total_ticks += bout.ticks
		sim_usec += bout.sim_usec
		input_usec += bout.input_usec
		if not bout.finished:
			unfinished += 1
		elif bout.winner_team < 0:
			draws += 1
		else:
			wins[bout.winner_team] = wins.get(bout.winner_team, 0) + 1
		for r in bout.rounds:
			round_ticks += int(r["ticks"])
			round_count += 1
			if r["timeout"]:
				timeouts += 1
		for line in bout.stuck:
			stuck_reports.append("match %d (seed %d): %s" % [m + 1, cfg.seed, line])
		for line in bout.long_combos:
			combo_reports.append("match %d (seed %d): %s" % [m + 1, cfg.seed, line])
		longest_hits = maxi(longest_hits, bout.longest_combo_hits)
		longest_ticks = maxi(longest_ticks, bout.longest_combo_ticks)
		for slot in slot_count:
			for key in AiBout.SUM_KEYS:
				totals[slot][key] = int(totals[slot][key]) + int(bout.stats[slot][key])
			var ai := sources[slot] as AiInputSource
			if ai != null:
				for key: String in ai.counters:
					ai_counters[slot][key] = int(ai_counters[slot].get(key, 0)) + ai.counters[key]
		var verified := true
		if _opts.has("verify"):
			verified = bout.replay.verify() == -1
			if not verified:
				verify_failures += 1
		var report := {
			"match": m + 1, "seed": cfg.seed, "swapped": swapped, "winner_team": bout.winner_team,
			"finished": bout.finished, "ticks": bout.ticks, "rounds": bout.rounds, "stuck": bout.stuck,
			"replay_verified": verified, "checksum": bout.final_checksum, "stats": bout.stats,
		}
		match_reports.append(report)
		if not replay_dir.is_empty() and (_opts.has("save-all") or not bout.stuck.is_empty() or not verified):
			var path := replay_dir.path_join("match_%03d_seed_%d.res" % [m + 1, cfg.seed])
			ResourceSaver.save(bout.replay, path)
		if not quiet:
			var lengths := PackedStringArray()
			for r in bout.rounds:
				lengths.append("%.0fs%s" % [int(r["ticks"]) / 60.0, "(T)" if r["timeout"] else ""])
			var winner: String = "draw" if bout.winner_team < 0 else team_names.get(bout.winner_team, "team %d" % bout.winner_team)
			print("  #%-3d seed %-5d %-28s rounds %s%s%s" % [m + 1, cfg.seed, winner, " ".join(lengths),
					"  STUCK x%d" % bout.stuck.size() if not bout.stuck.is_empty() else "",
					"" if verified else "  REPLAY MISMATCH"])

	var ms_per_tick := (sim_usec + input_usec) / 1000.0 / maxi(1, total_ticks)
	print("")
	print("Results (%d matches):" % matches)
	for team: int in team_names:
		var w: int = wins.get(team, 0)
		print("  %-40s %3d wins  %5.1f%%" % [team_names[team], w, 100.0 * w / maxi(1, matches)])
	print("  draws %d, unfinished %d" % [draws, unfinished])
	print("  rounds %d, average %.1f s, timeouts %d" % [round_count, round_ticks / 60.0 / maxi(1, round_count), timeouts])
	print("  per slot (hits / blocks / parries / dodges / abilities / supers / bursts / grabs / techs):")
	for slot in slot_count:
		var t := totals[slot]
		print("    %d %-28s %d / %d / %d / %d / %d / %d / %d / %d / %d" % [slot, labels[slot], t["hits"], t["blocks"],
				t["parries"], t["dodges"], t["abilities"], t["supers"], t["bursts"], t["grabs"], t["techs"]])
	print("  CPU decisions per slot:")
	for slot in slot_count:
		var keys: Array = ai_counters[slot].keys()
		keys.sort()
		var parts := PackedStringArray()
		for key: String in keys:
			parts.append("%s %d" % [key, ai_counters[slot][key]])
		print("    %d %s" % [slot, ", ".join(parts)])
	print("  stuck states: %d" % stuck_reports.size())
	for line in stuck_reports.slice(0, 20):
		print("    " + line)
	print("  long combos (>= %s hits or >= %s s of hitstun): %d, longest %d hits / %.1f s" % [
			_opts.get("infinite-hits", "20"), _opts.get("infinite-seconds", "8"), combo_reports.size(),
			longest_hits, longest_ticks / 60.0])
	for line in combo_reports.slice(0, 10):
		print("    " + line)
	if _opts.has("verify"):
		print("  replay verification failures: %d" % verify_failures)
	print("  errors: %d" % _collector.errors.size())
	for line in _collector.errors.slice(0, 10):
		print("    " + line)
	print("  cost: %.3f ms per tick (sim %.3f, AI %.3f), %d ticks" % [ms_per_tick,
			sim_usec / 1000.0 / maxi(1, total_ticks), input_usec / 1000.0 / maxi(1, total_ticks), total_ticks])

	if _opts.has("json"):
		var summary := {
			"matches": matches, "seed": base_seed, "arena": String(arena.id), "slots": labels,
			"teams": team_of, "wins": wins, "draws": draws, "unfinished": unfinished,
			"rounds": round_count, "average_round_seconds": round_ticks / 60.0 / maxi(1, round_count),
			"timeouts": timeouts, "stuck": stuck_reports, "long_combos": combo_reports,
			"longest_combo_hits": longest_hits, "longest_combo_seconds": longest_ticks / 60.0, "errors": _collector.errors,
			"verify_failures": verify_failures, "ms_per_tick": ms_per_tick, "totals": totals,
			"cpu_decisions": ai_counters,
			"match_reports": match_reports,
		}
		var file := FileAccess.open(_opts["json"], FileAccess.WRITE)
		file.store_string(JSON.stringify(summary, "  "))
		file.close()
	var failed := not _collector.errors.is_empty() or verify_failures > 0
	if _opts.has("fail-on-stuck") and (not stuck_reports.is_empty() or unfinished > 0):
		failed = true
	if _opts.has("fail-on-infinite") and not combo_reports.is_empty():
		failed = true
	return 1 if failed else 0


func _sources(cfg: SimConfig, level_names: PackedStringArray, profile_overrides: Dictionary,
		cap: int) -> Array[InputSource]:
	var cpu_slots := PackedInt32Array()
	var levels := PackedInt32Array()
	for slot in cfg.slots.size():
		var name := level_names[slot].to_lower()
		var level := LEVELS.find(name)
		if level < 0:
			level = -1 if name == "none" or name == "dummy" else clampi(int(name), 0, 3)
		levels.append(level)
		if level >= 0:
			cpu_slots.append(slot)
	# Token count comes from the strongest CPU (only Nightmare has 2).
	var token_count := 1
	for level in levels:
		if level >= 0:
			token_count = maxi(token_count, AiDifficulty.preset(level, cap).attack_tokens)
	var team_tokens := AiInputSource.shared_tokens(cfg, cpu_slots, token_count)
	var sources: Array[InputSource] = []
	for slot in cfg.slots.size():
		if levels[slot] < 0:
			sources.append(null)
			continue
		var profile: AiProfile = null
		if profile_overrides.has(slot):
			profile = AiProfile.by_id(StringName(profile_overrides[slot]))
		sources.append(AiInputSource.new(AiDifficulty.preset(levels[slot], cap), profile,
				team_tokens.get(cfg.slots[slot].team)))
	return sources


func _resolve_fighter(id: String) -> FighterData:
	var candidates: PackedStringArray = [id] if id.begins_with("res://") else [
		"res://content/fighters/%s/%s.tres" % [id, id],
		"res://content/fighters/%s.tres" % id,
		"res://content/test_fighter/%s.tres" % id,
	]
	for path in candidates:
		if ResourceLoader.exists(path):
			return load(path) as FighterData
	return null


func _resolve_arena(id: String) -> String:
	return id if id.begins_with("res://") else "res://content/arenas/%s.tres" % id


func _list(key: String, fallback: String) -> PackedStringArray:
	var value: String = _opts.get(key, fallback)
	return value.split(",", false) if not value.is_empty() else PackedStringArray()


## "--key=1:value,2:value" -> {1: "value", 2: "value"}
func _slot_map(key: String) -> Dictionary:
	var result: Dictionary = {}
	for item in _list(key, ""):
		var parts := item.split(":", true, 1)
		if parts.size() == 2:
			result[int(parts[0])] = parts[1]
	return result


func _repeat(value: String, count: int) -> PackedStringArray:
	var out := PackedStringArray()
	for _i in count:
		out.append(value)
	return out

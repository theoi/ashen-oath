class_name AiBout
extends RefCounted
## Runs one match headless (no nodes, no rendering) from per-slot InputSources, as fast as
## the CPU allows, and records what soak tests and the AI harness report: winner, round
## lengths, timeouts, stuck states, per-slot stats and the replay.
##
##   var bout := AiBout.new(config, sources)
##   bout.run()
##   print(bout.winner_team, bout.stuck)
##
## Stuck detection: no fighter's HP changes for `stuck_no_damage_ticks` of fight time in a
## round, a fighter stays in one non-neutral action for `stuck_action_ticks`, or the match
## runs past `max_ticks`.
##
## Infinite detection: a combo (FighterState.combo_hits / combo_ticks, one victim) that
## reaches `long_combo_hits` hits or `long_combo_ticks` of hitstun is reported in `long_combos`.

const Action := FighterState.Action
const SUM_KEYS: PackedStringArray = ["hits", "damage", "blocks", "parries", "dodges",
		"perfect_dodges", "abilities", "supers", "bursts", "grabs", "grab_techs", "techs",
		"launches", "wall_splats", "guard_breaks"]

var config: SimConfig
var sources: Array[InputSource] = []
## 0 = derived from the rules (every round to the timer, plus margin).
var max_ticks: int = 0
var stuck_no_damage_ticks: int = 1200
var stuck_action_ticks: int = 600
var record_replay: bool = true
var record_checksums: bool = false
var long_combo_hits: int = 20
var long_combo_ticks: int = 480

var sim: Sim
var replay: Replay
## Winning team, -1 for a draw or an unfinished match.
var winner_team: int = -1
var finished: bool = false
var ticks: int = 0
## One entry per decided round: {"round", "ticks" (fight ticks), "winner", "timeout"}.
var rounds: Array[Dictionary] = []
## Human-readable stuck reports ("round 2 tick 4410: no damage for 20.0 s").
var stuck: PackedStringArray = []
## Human-readable long-combo reports ("round 1 tick 900: slot 1 took 21 hits over 6.2 s").
var long_combos: PackedStringArray = []
## Longest combo seen on any fighter: hits, and hitstun ticks.
var longest_combo_hits: int = 0
var longest_combo_ticks: int = 0
## Per slot: counters named in SUM_KEYS.
var stats: Array[Dictionary] = []
var final_checksum: int = 0
var sim_usec: int = 0
var input_usec: int = 0

var _last_hp_total: int = -1
var _quiet_ticks: int = 0
var _quiet_reported: bool = false
var _action_reported: PackedInt32Array = PackedInt32Array()
var _timeout_round: bool = false
var _combo_reported: PackedInt32Array = PackedInt32Array()


func _init(sim_config: SimConfig, input_sources: Array[InputSource]) -> void:
	config = sim_config
	sources = input_sources


func run() -> AiBout:
	sim = Sim.new(config)
	replay = Replay.create(config)
	stats.clear()
	for _slot in sim.slot_count():
		var counters: Dictionary = {}
		for key in SUM_KEYS:
			counters[key] = 0
		stats.append(counters)
	_action_reported.resize(sim.slot_count())
	_action_reported.fill(0)
	_combo_reported.resize(sim.slot_count())
	_combo_reported.fill(0)
	var limit := max_ticks if max_ticks > 0 else _default_limit()
	var inputs := PackedInt64Array()
	inputs.resize(sim.slot_count())
	while not sim.is_over() and sim.state.tick < limit:
		var t0 := Time.get_ticks_usec()
		for slot in sim.slot_count():
			var source: InputSource = sources[slot] if slot < sources.size() else null
			inputs[slot] = source.next_frame(sim, slot) if source != null else 0
		var t1 := Time.get_ticks_usec()
		var events := sim.step(inputs)
		input_usec += t1 - t0
		sim_usec += Time.get_ticks_usec() - t1
		if record_replay:
			replay.record(inputs, sim.checksum() if record_checksums else 0, record_checksums)
		_track(events)
	ticks = sim.state.tick
	finished = sim.is_over()
	winner_team = sim.state.winner_team if finished else -1
	if not finished:
		stuck.append("match did not end within %d ticks" % limit)
	final_checksum = sim.checksum()
	return self


## Average fight length of decided rounds, in seconds.
func average_round_seconds() -> float:
	if rounds.is_empty():
		return 0.0
	var total := 0
	for r in rounds:
		total += int(r["ticks"])
	return total / 60.0 / rounds.size()


func timeouts() -> int:
	var count := 0
	for r in rounds:
		if r["timeout"]:
			count += 1
	return count


func team_stat(team: int, key: String) -> int:
	var total := 0
	for slot in stats.size():
		if config.slots[slot].team == team:
			total += int(stats[slot][key])
	return total


func _default_limit() -> int:
	var rules := config.rules if config.rules != null else CombatRules.new()
	var round_frames := config.effective_round_frames()
	if round_frames < 0:
		round_frames = 99 * 60
	var max_rounds := config.effective_rounds_to_win() * 2 + 1
	return max_rounds * (round_frames + rules.round_intro_frames + rules.round_end_frames + 120)


func _track(events: Array[SimEvent]) -> void:
	var st := sim.state
	for e in events:
		match e.type:
			SimEvent.Type.HIT:
				if e.source >= 0:
					_add(e.source, "hits", 1)
					_add(e.source, "damage", e.amount)
				if e.flags & SimEvent.FLAG_LAUNCH and e.source >= 0:
					_add(e.source, "launches", 1)
			SimEvent.Type.BLOCK:
				_add(e.target, "blocks", 1)
			SimEvent.Type.PARRY:
				_add(e.source, "parries", 1)
			SimEvent.Type.DODGE:
				_add(e.source, "dodges", 1)
			SimEvent.Type.PERFECT_DODGE:
				_add(e.target, "perfect_dodges", 1)
			SimEvent.Type.MOVE_START:
				var move := sim.fighter_data[e.source].moves[e.amount]
				if move.kind == MoveData.Kind.ABILITY:
					_add(e.source, "abilities", 1)
				elif move.kind == MoveData.Kind.SUPER:
					_add(e.source, "supers", 1)
			SimEvent.Type.BURST:
				_add(e.source, "bursts", 1)
			SimEvent.Type.GRAB:
				_add(e.source, "grabs", 1)
			SimEvent.Type.GRAB_TECH:
				_add(e.source, "grab_techs", 1)
			SimEvent.Type.AIR_TECH, SimEvent.Type.TECH_ROLL:
				_add(e.source, "techs", 1)
			SimEvent.Type.WALL_SPLAT:
				_add(e.source, "wall_splats", 1)
			SimEvent.Type.GUARD_BREAK:
				_add(e.source, "guard_breaks", 1)
			SimEvent.Type.TIME_UP:
				_timeout_round = true
			SimEvent.Type.ROUND_END:
				rounds.append({"round": st.round_number, "ticks": st.round_tick, "winner": e.amount,
						"timeout": _timeout_round})
				_timeout_round = false
			SimEvent.Type.ROUND_START:
				_last_hp_total = -1
				_quiet_ticks = 0
				_quiet_reported = false
				_action_reported.fill(0)
	if st.phase != SimState.Phase.FIGHT:
		return
	var hp_total := 0
	for f in st.fighters:
		hp_total += f.hp
	if hp_total != _last_hp_total:
		_last_hp_total = hp_total
		_quiet_ticks = 0
	elif st.freeze == 0:
		_quiet_ticks += 1
		if _quiet_ticks >= stuck_no_damage_ticks and not _quiet_reported:
			_quiet_reported = true
			stuck.append("round %d tick %d: no damage for %.1f s (%s)" % [st.round_number, st.tick,
					_quiet_ticks / 60.0, _describe_fighters()])
	for f in st.fighters:
		longest_combo_hits = maxi(longest_combo_hits, f.combo_hits)
		longest_combo_ticks = maxi(longest_combo_ticks, f.combo_ticks)
		if f.combo_hits == 0:
			_combo_reported[f.slot] = 0
		elif _combo_reported[f.slot] == 0 and (f.combo_hits >= long_combo_hits or f.combo_ticks >= long_combo_ticks):
			_combo_reported[f.slot] = 1
			long_combos.append("round %d tick %d: slot %d took %d hits over %.1f s of hitstun" % [st.round_number,
					st.tick, f.slot, f.combo_hits, f.combo_ticks / 60.0])
	for f in st.fighters:
		if f.ko or f.action == Action.IDLE or f.action == Action.GUARD:
			continue
		if f.action_tick >= stuck_action_ticks and _action_reported[f.slot] == 0:
			_action_reported[f.slot] = 1
			stuck.append("round %d tick %d: slot %d stuck in %s for %d ticks" % [st.round_number,
					st.tick, f.slot, Action.keys()[f.action], f.action_tick])


func _add(slot: int, key: String, amount: int) -> void:
	if slot >= 0 and slot < stats.size():
		stats[slot][key] = int(stats[slot][key]) + amount


func _describe_fighters() -> String:
	var parts := PackedStringArray()
	for f in sim.state.fighters:
		parts.append("slot %d %s at (%.1f, %.1f) hp %d" % [f.slot, Action.keys()[f.action],
				Fx.to_m(f.pos.x), Fx.to_m(f.pos.z), f.hp])
	return "; ".join(parts)

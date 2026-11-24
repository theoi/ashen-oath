class_name SimHud
extends RefCounted
## Reads the sim for the HUD and translates sim events into MatchEvents (HUD and sounds).
## Presentation only: never writes the sim.

const _T := SimEvent.Type


## Fills `hud` from the sim state. Creates fighter entries on first use. `human_slots` get
## the ability bar.
static func fill(sim: Sim, hud: HudState, human_slots: Array[int] = [0]) -> HudState:
	var state := sim.state
	hud.round_number = state.round_number
	hud.rounds_to_win = sim.config.effective_rounds_to_win()
	hud.round_wins.resize(_team_count(sim))
	for team in hud.round_wins.size():
		hud.round_wins[team] = state.team_wins[team] if team < state.team_wins.size() else 0
	hud.seconds_left = float(sim.seconds_left())
	while hud.fighters.size() < sim.slot_count():
		var entry := HudState.Fighter.new()
		var slot := hud.fighters.size()
		var data := sim.fighter_data[slot]
		entry.slot = slot
		entry.is_player = slot in human_slots
		entry.name = data.display_name if not data.display_name.is_empty() else Roster.fighter_name(data.id)
		entry.ability_names = _ability_names(data)
		entry.cooldown_total = _cooldown_totals(data)
		hud.fighters.append(entry)
	for slot in sim.slot_count():
		var f := sim.fighter(slot)
		var entry := hud.fighters[slot]
		entry.team = f.team
		entry.health = f.hp
		entry.max_health = f.max_hp
		entry.soul = f.soul_points()
		entry.guard = f.guard_points()
		entry.max_guard = 100.0
		entry.guard_broken = f.guard_broken
		entry.knocked_out = f.ko
		entry.cooldown_left.resize(f.cooldowns.size())
		for i in f.cooldowns.size():
			entry.cooldown_left[i] = f.cooldowns[i] / 60.0
	return hud


## The MatchEvents dictionary for a sim event, or an empty one when the HUD and sounds
## have nothing to do with it.
static func translate(sim: Sim, event: SimEvent) -> Dictionary:
	var acting := event.source
	var affected := event.target if event.target >= 0 else event.source
	var out := {}
	match event.type:
		_T.ROUND_START:
			out = {"type": MatchEvents.ROUND_INTRO, "round": event.amount}
		_T.FIGHT:
			out = {"type": MatchEvents.FIGHT}
		_T.KO:
			out = {"type": MatchEvents.KO, "slot": affected}
		_T.TIME_UP:
			out = {"type": MatchEvents.TIME_UP}
		_T.ROUND_END:
			out = {"type": MatchEvents.ROUND_WON, "team": event.amount}
		_T.MATCH_END:
			out = {"type": MatchEvents.MATCH_WON, "team": event.amount}
		_T.HIT:
			out = {"type": MatchEvents.HIT, "attacker": acting, "victim": event.target,
					"heavy": event.hitstop >= 8 or event.amount >= 80,
					"counter": event.flags & SimEvent.FLAG_COUNTER != 0}
		_T.BLOCK:
			out = {"type": MatchEvents.BLOCK, "attacker": acting, "victim": event.target}
		_T.PARRY:
			out = {"type": MatchEvents.PARRY, "slot": affected}
		_T.GUARD_BREAK:
			out = {"type": MatchEvents.GUARD_BREAK, "slot": affected}
		_T.PERFECT_DODGE:
			out = {"type": MatchEvents.PERFECT_DODGE, "slot": acting}
		_T.DODGE:
			out = {"type": MatchEvents.DODGE, "slot": acting}
		_T.SUPER_FLASH:
			out = {"type": MatchEvents.SUPER, "slot": acting}
		_T.BURST:
			out = {"type": MatchEvents.SOUL_BURST, "slot": acting}
		_T.WALL_SPLAT:
			out = {"type": MatchEvents.WALL_SPLAT, "slot": affected}
		_T.HAZARD_ACTIVE:
			out = {"type": MatchEvents.HAZARD}
		_T.MOVE_START:
			var f := sim.fighter(acting)
			var data := sim.fighter_data[acting]
			var index := data.abilities.find(event.id)
			if index >= 0 and sim.current_move(f) != null and sim.current_move(f).kind == MoveData.Kind.ABILITY:
				out = {"type": MatchEvents.ABILITY, "slot": acting, "ability": index}
	if not out.is_empty() and not event.cue.is_empty():
		out["cue"] = event.cue
	return out


static func result(sim: Sim, config: MatchConfig) -> MatchResult:
	var result := MatchResult.new()
	result.config = config
	result.winner_team = sim.state.winner_team
	result.rounds_played = sim.state.round_number
	for team in _team_count(sim):
		result.round_wins.append(sim.state.team_wins[team])
	return result


static func _team_count(sim: Sim) -> int:
	var count := 0
	for slot in sim.slot_count():
		count = maxi(count, sim.fighter(slot).team + 1)
	return count


static func _ability_names(data: FighterData) -> PackedStringArray:
	var names := Roster.ability_names(data.id)
	if names.size() >= 3:
		return names
	names = PackedStringArray()
	for id in data.abilities:
		names.append(String(id).capitalize())
	return names


static func _cooldown_totals(data: FighterData) -> Array[float]:
	var totals: Array[float] = [1.0, 1.0, 1.0]
	for i in mini(3, data.abilities.size()):
		var move := data.move_by_id(data.abilities[i])
		if move != null and move.cooldown > 0:
			totals[i] = move.cooldown / 60.0
	return totals

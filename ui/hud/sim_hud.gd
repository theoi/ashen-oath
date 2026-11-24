class_name SimHud
extends RefCounted
## Reads the sim for the HUD and translates sim events into MatchEvents (HUD and sounds).
## Presentation only: never writes the sim.

const _T := SimEvent.Type
## Actions in which the sim accepts Soul Burst (Sim._reaction).
const BURST_ACTIONS: Array[FighterState.Action] = [FighterState.Action.HITSTUN, FighterState.Action.AIR_HITSTUN, FighterState.Action.WALL_SPLAT]


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
	hud.wave_count = sim.config.waves.size()
	# wave_index equals waves.size() once the last wave has spawned.
	hud.wave = clampi(state.wave_index + 1, 1, hud.wave_count) if hud.wave_count > 0 else 0
	while hud.fighters.size() < sim.slot_count():
		var entry := HudState.Fighter.new()
		entry.slot = hud.fighters.size()
		entry.is_player = entry.slot in human_slots
		entry.wave_member = entry.slot >= sim.config.slots.size()
		hud.fighters.append(entry)
	for slot in sim.slot_count():
		var f := sim.fighter(slot)
		var entry := hud.fighters[slot]
		if entry.roster != f.roster:
			_bind(sim, entry)
			entry.roster = f.roster
		entry.active = f.active
		entry.stagger = f.stagger
		entry.stagger_max = f.stagger_max
		entry.staggered = f.action == FighterState.Action.STAGGERED
		entry.channel = f.channel
		entry.channel_max = f.channel_max if f.channel > 0 else 0
		entry.team = f.team
		entry.health = f.hp
		entry.max_health = f.max_hp
		entry.soul = f.soul_points()
		entry.guard = f.guard_points()
		entry.max_guard = 100.0
		entry.guard_broken = f.guard_broken
		entry.knocked_out = f.ko
		var grabbed := f.action == FighterState.Action.GRABBED
		entry.burst_window = not f.ko and (f.action in BURST_ACTIONS or (grabbed and entry.burst_on_dash))
		if entry.dash_max > 0:
			_fill_dash(sim, f, entry)
		var stunned := entry.burst_window or grabbed
		for i in entry.skills.size():
			var skill := entry.skills[i]
			skill.cooldown_left = f.cooldowns[i] / 60.0 if i < f.cooldowns.size() else 0.0
			if i < f.cooldown_totals.size() and f.cooldown_totals[i] > 0:
				skill.cooldown_total = f.cooldown_totals[i] / 60.0
			# A combo/chain sequence still running holds the slot until its cooldown starts.
			skill.usable = not f.ko and not stunned and (sim.skill_ready(f, i) or skill.cooldown_left > 0.0)
			skill.max_charges = sim.skill_max_charges(f, i)
			skill.charges = f.skill_charges[i] if i < f.skill_charges.size() else 0
			if entry.is_player:
				_fill_follow_up(sim, f, i, skill)
				_fill_charge(sim, f, i, skill)
	return hud


## Name, skills, awakening and dash of the fighter the slot runs now.
static func _bind(sim: Sim, entry: HudState.Fighter) -> void:
	var data := sim.fighter_data[entry.slot]
	if data == null:
		entry.skills = []
		return
	entry.name = data.display_name if not data.display_name.is_empty() else Roster.fighter_name(data.id)
	entry.skills = _skills(data)
	entry.awakening_name = Roster.fighter(data.id).get("super", "Super")
	entry.awakening_action = DefaultBindings.AWAKEN
	entry.dash_action = DefaultBindings.DASH
	entry.burst_on_dash = data.dash != null
	entry.dash_max = 0
	if data.dash != null:
		entry.dash_max = sim.config.dash_charges if sim.config.dash_charges >= 0 else data.dash.charges


static func _fill_dash(sim: Sim, f: FighterState, entry: HudState.Fighter) -> void:
	entry.dash_charges = f.dash_charges
	entry.dash_recharge = 0.0
	var total := sim.dash_recharge_frames(f)
	if f.dash_charges < entry.dash_max and total > 0:
		entry.dash_recharge = clampf(1.0 - float(f.dash_recharge) / total, 0.0, 1.0)


## A combo part or chain follow-up waiting in the slot (FighterState.skill_next / skill_window).
static func _fill_follow_up(sim: Sim, f: FighterState, slot: int, skill: HudState.Skill) -> void:
	skill.follow_name = ""
	skill.follow_left = 0.0
	if slot >= f.skill_next.size() or f.skill_next[slot] < 0 or f.skill_window[slot] <= 0:
		return
	var follow := sim.skill_move(f, slot)
	var data := sim.fighter_data[f.slot]
	var root := data.move_by_id(data.abilities[slot])
	var left := f.skill_window[slot]
	skill.follow_name = String(follow.id).capitalize()
	skill.follow_left = left / 60.0
	var total := 0
	if root != null:
		total = root.chain_frames if not root.chain_move.is_empty() else root.follow_up_window
	skill.follow_total = maxi(total, left) / 60.0


## Charge progress while the slot's chargeable skill is held.
static func _fill_charge(sim: Sim, f: FighterState, slot: int, skill: HudState.Skill) -> void:
	skill.charging = false
	var move := sim.current_move(f)
	var data := sim.fighter_data[f.slot]
	if move == null or not move.chargeable or not f.charging or slot >= data.abilities.size():
		return
	if f.move_slot != slot and (f.move_slot >= 0 or move.id != data.abilities[slot]):
		return
	var top := float(maxi(move.charge_max, 1))
	skill.charging = true
	skill.charge = clampf(f.charge / top, 0.0, 1.0)
	skill.charge_levels = PackedFloat32Array()
	for level in move.charge_levels:
		skill.charge_levels.append(level / top)
	skill.perfect_from = move.perfect_start / top
	skill.perfect_to = move.perfect_end / top


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
		_T.WAVE_START:
			out = {"type": MatchEvents.WAVE, "wave": event.amount + 1, "waves": sim.config.waves.size()}
		_T.STAGGER_BREAK:
			out = {"type": MatchEvents.STAGGER_BREAK, "slot": affected}
		_T.CHANNEL_BREAK:
			out = {"type": MatchEvents.CHANNEL_BREAK, "slot": event.target, "breaker": event.source}
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


## The fighter's skill slots: names from Roster (else the move id), buttons, full cooldowns.
static func _skills(data: FighterData) -> Array[HudState.Skill]:
	var known := Roster.ability_names(data.id)
	var skills: Array[HudState.Skill] = []
	for i in data.abilities.size():
		var skill := HudState.Skill.new()
		skill.name = known[i] if i < known.size() else String(data.abilities[i]).capitalize()
		skill.action = DefaultBindings.ability_action(i)
		var move := data.move_by_id(data.abilities[i])
		if move != null:
			if move.cooldown > 0:
				skill.cooldown_total = move.cooldown / 60.0
			skill.type = MoveList.SKILL_TYPES.find(MoveList.skill_type(move)) as HudState.Skill.Type
			skill.counter = MoveList.is_counter(move)
		skills.append(skill)
	return skills

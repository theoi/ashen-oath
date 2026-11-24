class_name MoveList
extends RefCounted
## Builds a fighter's move list from its FighterData and MoveData, so it stays correct as
## content changes. Names and one-line descriptions of skills, trait and awakening come from
## Roster; everything else (skill type, follow-ups, charge, armor, cooldowns...) from the data.
## Only moves the player can input with the default bindings (design-lost-ark §2) are listed.
##
## Inputs are Arrays of DefaultBindings actions (drawn as glyphs) and context Strings.

const B := preload("res://ui/input/default_bindings.gd")

const BASICS := "Basic attack"
const ABILITIES := "Skills"
const SOUL := "Awakening and Soul"
const DEFENSE := "Movement and defense"

## MoveData.skill_type names, in enum order (TAP, HOLD, CHARGE, COMBO, CHAIN, DASH_STRIKE, STANCE).
const SKILL_TYPES: PackedStringArray = ["Tap", "Hold", "Charge", "Combo", "Chain", "Dash-strike", "Stance"]
## How far a basic chain is followed.
const MAX_CHAIN := 6


class Entry:
	var section := ""
	var name := ""
	## Shown before the inputs, e.g. "Charge", "Knocked down", "In hitstun".
	var context := ""
	## DefaultBindings actions (and InputGlyphs.MOVE / AIM) in press order.
	var inputs: Array[StringName] = []
	var detail := ""
	## A ⚡Counter move: interrupts an enemy's counter window (blue flash).
	var counter := false

	func _init(p_section: String, p_name: String, p_inputs: Array[StringName], p_detail: String, p_context: String = "") -> void:
		section = p_section
		name = p_name
		inputs = p_inputs
		detail = p_detail
		context = p_context


static func build(data: FighterData, rules: CombatRules = null) -> Array[Entry]:
	if rules == null:
		rules = CombatRules.new()
	var entries: Array[Entry] = []
	var info := Roster.fighter(data.id)
	var skill_kit := data.dash != null

	_basic_chain(data, entries)
	_single(data, data.run_light, "Running attack", [B.BASIC], "Running", entries)
	_single(data, data.getup_attack, "Get-up attack", [B.BASIC], "Knocked down", entries)

	var names: Array = info.get("abilities", [])
	var details: Array = info.get("ability_details", [])
	for i in data.abilities.size():
		var move := data.move_by_id(data.abilities[i])
		if move == null:
			continue
		var name: String = names[i] if i < names.size() else _title(move.id)
		var line: String = details[i] if i < details.size() else ""
		var extra := tags(move)
		var follow := _follow_text(data, move)
		if not follow.is_empty():
			extra.insert(0, follow)
		var entry := Entry.new(ABILITIES, name, [B.ability_action(i)], _sentence(line, extra), skill_type(move))
		entry.counter = is_counter(move)
		entries.append(entry)

	var awakening := data.move_by_id(data.super_move)
	if awakening != null:
		var cost := awakening.soul_cost if awakening.soul_cost > 0 else rules.super_cost
		var awakening_name: String = info.get("super", "")
		entries.append(Entry.new(SOUL, awakening_name if not awakening_name.is_empty() else "Awakening", [B.AWAKEN],
				_sentence(info.get("super_detail", ""), tags(awakening)), "%d Soul" % cost))
	var trait_text: String = info.get("trait", "")
	if not trait_text.is_empty():
		var colon := trait_text.find(":")
		var trait_detail := trait_text.substr(colon + 1).strip_edges() if colon > 0 else trait_text
		entries.append(Entry.new(SOUL, trait_text.substr(0, colon) if colon > 0 else "Trait", [],
				trait_detail.left(1).to_upper() + trait_detail.substr(1), "Trait"))
	entries.append(Entry.new(SOUL, "Soul Burst", [B.DASH if skill_kit else B.AWAKEN],
			"Breaks a combo and pushes everyone near you away. Costs %d Soul." % rules.burst_cost,
			"In hitstun"))
	entries.append(Entry.new(SOUL, "Gaining Soul", [],
			"Deal and take damage, perfect dashes (+%d) and ⚡Counters. Soul carries over between rounds." % rules.perfect_dodge_soul))

	entries.append(Entry.new(DEFENSE, "Move", [InputGlyphs.MOVE], ""))
	entries.append(Entry.new(DEFENSE, "Aim", [InputGlyphs.AIM],
			"Skills and basics snap to the aim on their first frame. Without aim they go toward the nearest enemy."))
	if data.dash != null:
		entries.append(Entry.new(DEFENSE, "Dash", [B.DASH], _dash_text(data.dash)))
		entries.append(Entry.new(DEFENSE, "Quick rise", [B.DASH], "Roll to your feet, invincible. Uses a dash charge.", "Knocked down"))
	else:
		entries.append(Entry.new(DEFENSE, "Dodge roll", [B.DASH],
				"Rolls toward the stick (backward if neutral), invincible frames %d-%d." % [data.dodge_invuln_start, data.dodge_invuln_end]))
		entries.append(Entry.new(DEFENSE, "Tech", [B.DASH], "Just before landing from a knockdown: roll to your feet.", "Knocked down"))
	entries.append(Entry.new(DEFENSE, "Lock-on", [B.LOCK_ON],
			"Aim at one enemy; press again for the next, and after the last it unlocks."))
	if B.find(B.TARGET_NEXT) != null:
		entries.append(Entry.new(DEFENSE, "Next target", [B.TARGET_NEXT], "Switch target and stay locked."))
	return entries


## The skill type label: MoveData.skill_type when set, else read from the move (TAP is the
## default, so older kits get a type from their charge, follow-ups, stance, hold or aim).
static func skill_type(move: MoveData) -> String:
	if move.skill_type != MoveData.SkillType.TAP:
		return SKILL_TYPES[move.skill_type]
	if move.chargeable:
		return SKILL_TYPES[MoveData.SkillType.CHARGE]
	if not move.follow_up.is_empty():
		return SKILL_TYPES[MoveData.SkillType.COMBO]
	if not move.chain_move.is_empty():
		return SKILL_TYPES[MoveData.SkillType.CHAIN]
	if move.stance_end > 0:
		return SKILL_TYPES[MoveData.SkillType.STANCE]
	if move.hold_end > 0:
		return SKILL_TYPES[MoveData.SkillType.HOLD]
	if move.aim == MoveData.Aim.DASH_TO:
		return SKILL_TYPES[MoveData.SkillType.DASH_STRIKE]
	return SKILL_TYPES[MoveData.SkillType.TAP]


## True when any hit of the move is a ⚡Counter hit.
static func is_counter(move: MoveData) -> bool:
	for hit in _hits(move):
		if hit.counter:
			return true
	return false


## Short traits of a move from its data: charge, reactions, armor, invincibility, cooldown.
static func tags(move: MoveData) -> PackedStringArray:
	var out := PackedStringArray()
	if is_counter(move):
		out.append("⚡counter")
	if move.chargeable:
		if move.perfect_end > 0:
			out.append("hold to charge, release in the perfect zone for a bonus")
		else:
			out.append("hold to charge" + (", breaks guard at full charge" if move.full_charge_guard_break else ""))
	if move.hold_end > 0:
		out.append("hold to keep going")
	var projectile := false
	for effect in move.effects:
		if effect.projectile and effect.speed > 0.0:
			projectile = true
	var seen := PackedStringArray()
	for hit in _hits(move):
		var words := PackedStringArray()
		match hit.reaction:
			HitData.Reaction.LAUNCH:
				words.append("launches")
			HitData.Reaction.KNOCKDOWN:
				words.append("knocks down")
			HitData.Reaction.GROUND_BOUNCE:
				words.append("ground bounce")
			HitData.Reaction.PULL:
				words.append("pulls in")
		if hit.wall_splat:
			words.append("wall splat")
		if hit.unblockable:
			words.append("unblockable")
		if hit.otg:
			words.append("hits downed foes")
		for word in words:
			if not word in seen:
				seen.append(word)
	out.append_array(seen)
	if projectile:
		out.append("projectile")
	if move.teleport != null:
		out.append("teleport")
	if move.push_immune_end > 0:
		out.append("unstoppable (push immune)")
	elif move.flinch_immune_end > 0:
		out.append("flinch immune")
	if move.armor_hits > 0:
		out.append("armor (%d hit%s)" % [move.armor_hits, "" if move.armor_hits == 1 else "s"])
	if move.invuln_end > 0:
		out.append("invincible frames %d-%d" % [move.invuln_start, move.invuln_end])
	if move.cooldown > 0:
		out.append("%s s cooldown" % String.num(move.cooldown / 60.0, 1).trim_suffix(".0"))
	return out


static func sections() -> PackedStringArray:
	return [BASICS, ABILITIES, SOUL, DEFENSE]


## The basic attack chain (following next_light): one entry with its hit count and traits.
static func _basic_chain(data: FighterData, out: Array[Entry]) -> void:
	var move := data.move_by_id(data.light)
	if move == null:
		return
	var seen: Array[StringName] = []
	var extra := PackedStringArray()
	while move != null and not move.id in seen and seen.size() < MAX_CHAIN:
		seen.append(move.id)
		for tag in tags(move):
			if not tag in extra:
				extra.append(tag)
		move = data.move_by_id(move.next_light) if not move.next_light.is_empty() else null
	var line := "A %d-hit chain; hold to repeat. Skills and the dash cancel it at any time." % seen.size() \
			if seen.size() > 1 else "Fastest attack. Skills and the dash cancel it at any time."
	out.append(Entry.new(BASICS, "Basic attack", [B.BASIC], _sentence(line, extra)))


static func _single(data: FighterData, move_id: StringName, name: String, inputs: Array[StringName], context: String,
		out: Array[Entry], line: String = "") -> void:
	var move := data.move_by_id(move_id)
	if move != null:
		out.append(Entry.new(BASICS, name, inputs, _sentence(line, tags(move)), context))


## "Press again: Brand Rise II" (combo) or "Then within 3 s: Rend Ignition" (chain), or "".
static func _follow_text(data: FighterData, move: MoveData) -> String:
	if not move.follow_up.is_empty():
		return "press again for %s" % _title(move.follow_up)
	if not move.chain_move.is_empty():
		return "on hit, press again within %s s for %s" % [String.num(move.chain_frames / 60.0, 1).trim_suffix(".0"), _title(move.chain_move)]
	return ""


static func _dash_text(dash: DashData) -> String:
	return "%s m, invincible frames %d-%d. %d charges, each back after %s s. Cancels basics and most skills." % [
		String.num(dash.distance, 1).trim_suffix(".0"), dash.invuln_start, dash.invuln_end,
		dash.charges, String.num(dash.recharge_frames / 60.0, 1).trim_suffix(".0")]


static func _hits(move: MoveData) -> Array[HitData]:
	var hits: Array[HitData] = []
	for box in move.hitboxes:
		if box.hit != null:
			hits.append(box.hit)
	for effect in move.effects:
		if effect.hit != null:
			hits.append(effect.hit)
	return hits


static func _title(id: StringName) -> String:
	return String(id).capitalize()


## A description line plus the data tags: "Rising slash. Launches, 4 s cooldown."
static func _sentence(line: String, extra: PackedStringArray) -> String:
	var tail := ", ".join(extra)
	if not tail.is_empty():
		tail = tail.left(1).to_upper() + tail.substr(1) + "."
	if line.is_empty():
		return tail
	return line if tail.is_empty() else "%s %s" % [line, tail]

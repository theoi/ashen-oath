class_name MoveList
extends RefCounted
## Builds a fighter's move list from its FighterData and MoveData, so it stays correct as
## content changes. Names and one-line descriptions of abilities, trait and super come from
## Roster; everything else (strings, charge, launches, armor, cooldowns...) from the data.
##
## Inputs are Arrays of DefaultBindings actions (drawn as glyphs) and context Strings.

const B := preload("res://ui/input/default_bindings.gd")

const BASICS := "Attacks"
const ABILITIES := "Abilities"
const SOUL := "Trait, super and Soul"
const DEFENSE := "Movement and defense"

## How deep string chains are followed (L L L H would be 4).
const MAX_STRING := 4


class Entry:
	var section := ""
	var name := ""
	## Shown before the inputs, e.g. "Running", "Hold", "In hitstun".
	var context := ""
	## DefaultBindings actions (and InputGlyphs.MOVE / CAMERA) in press order.
	var inputs: Array[StringName] = []
	var detail := ""

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
	_strings(data, data.light, [B.LIGHT], entries, [])
	_strings(data, data.heavy, [B.HEAVY], entries, [])
	_single(data, data.run_light, "Running attack", [B.LIGHT], "Running", entries)
	_strings(data, data.air_light, [B.LIGHT], entries, [], "In the air")
	_single(data, data.air_heavy, "Air heavy", [B.HEAVY], "In the air", entries)
	_single(data, data.grab, "Grab", [B.GRAB], "", entries, "Throw that beats guard; loses to attacks, jumps and dodges.")
	_single(data, data.getup_attack, "Get-up attack", [B.LIGHT], "Getting up", entries)

	var info := Roster.fighter(data.id)
	var names: Array = info.get("abilities", [])
	var details: Array = info.get("ability_details", [])
	for i in data.abilities.size():
		var move := data.move_by_id(data.abilities[i])
		if move == null:
			continue
		var name: String = names[i] if i < names.size() else String(move.id).capitalize()
		var line: String = details[i] if i < details.size() else ""
		entries.append(Entry.new(ABILITIES, name, [B.ability_action(i)], _sentence(line, tags(move))))

	var trait_text: String = info.get("trait", "")
	if not trait_text.is_empty():
		var colon := trait_text.find(":")
		var trait_detail := trait_text.substr(colon + 1).strip_edges() if colon > 0 else trait_text
		entries.append(Entry.new(SOUL, trait_text.substr(0, colon) if colon > 0 else "Trait", [],
				trait_detail.left(1).to_upper() + trait_detail.substr(1), "Trait"))
	var super_move := data.move_by_id(data.super_move)
	if super_move != null:
		var cost := super_move.soul_cost if super_move.soul_cost > 0 else rules.super_cost
		var super_name: String = info.get("super", "")
		entries.append(Entry.new(SOUL, super_name if not super_name.is_empty() else "Super", [B.SUPER],
				_sentence(info.get("super_detail", ""), tags(super_move)), "%d Soul" % cost))
	entries.append(Entry.new(SOUL, "Soul Burst", [B.SUPER],
			"Breaks a combo and pushes everyone near you away. Costs %d Soul; not while guard-broken or thrown." % rules.burst_cost,
			"In hitstun"))
	entries.append(Entry.new(SOUL, "Gaining Soul", [],
			"Deal and take damage, parry (+%d) and perfect dodge (+%d). Soul carries over between rounds." % [rules.parry_soul, rules.perfect_dodge_soul]))

	entries.append(Entry.new(DEFENSE, "Move", [InputGlyphs.MOVE], "Relative to the camera. Attacks track the enemy your stick points at."))
	entries.append(Entry.new(DEFENSE, "Jump", [B.JUMP], ""))
	entries.append(Entry.new(DEFENSE, "Guard", [B.GUARD],
			"Blocks hits from the front. Blocking drains the guard gauge; when it empties your guard breaks.", "Hold"))
	entries.append(Entry.new(DEFENSE, "Parry", [B.GUARD],
			"Tap just before a hit lands (%d-frame window): no damage, the attacker staggers, +%d Soul. Works on projectiles." % [data.parry_window, rules.parry_soul],
			"Tap"))
	entries.append(Entry.new(DEFENSE, "Dodge roll", [B.DODGE],
			"Rolls toward the stick (backward if neutral), invincible frames %d-%d." % [data.dodge_invuln_start, data.dodge_invuln_end]))
	entries.append(Entry.new(DEFENSE, "Air dodge", [B.DODGE], "Once per jump, briefly invincible.", "In the air"))
	entries.append(Entry.new(DEFENSE, "Tech", [B.DODGE],
			"Just before landing from a knockdown: roll to your feet. In air hitstun: recover in the air.", "Knocked down"))
	entries.append(Entry.new(DEFENSE, "Grab tech", [B.GRAB], "Press right as you are grabbed to break free.", "Grabbed"))
	entries.append(Entry.new(DEFENSE, "Lock-on", [B.LOCK_ON],
			"Hard lock: face and circle your target. Press again to switch target in 1v2; after the last it unlocks."))
	entries.append(Entry.new(DEFENSE, "Camera", [InputGlyphs.CAMERA], ""))
	return entries


## Short traits of a move from its data: charge, reactions, armor, invincibility, cooldown.
static func tags(move: MoveData) -> PackedStringArray:
	var out := PackedStringArray()
	if move.chargeable:
		out.append("hold to charge" + (", breaks guard at full charge" if move.full_charge_guard_break else ""))
	var hits: Array[HitData] = []
	for box in move.hitboxes:
		if box.hit != null:
			hits.append(box.hit)
	var projectile := false
	for effect in move.effects:
		if effect.hit != null:
			hits.append(effect.hit)
		if effect.projectile and effect.speed > 0.0:
			projectile = true
	var seen := PackedStringArray()
	for hit in hits:
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
		if hit.guard_break:
			words.append("breaks guard")
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
	if move.armor_hits > 0:
		out.append("armor (%d hit%s)" % [move.armor_hits, "" if move.armor_hits == 1 else "s"])
	if move.invuln_end > 0:
		out.append("invincible frames %d-%d" % [move.invuln_start, move.invuln_end])
	if move.air_ok:
		out.append("usable in the air")
	if move.cooldown > 0:
		out.append("%s s cooldown" % String.num(move.cooldown / 60.0, 1).trim_suffix(".0"))
	return out


static func sections() -> PackedStringArray:
	return [BASICS, ABILITIES, SOUL, DEFENSE]


static func _strings(data: FighterData, move_id: StringName, path: Array[StringName], out: Array[Entry],
		visited: Array[StringName], context: String = "") -> void:
	var move := data.move_by_id(move_id)
	if move == null or move_id in visited or path.size() > MAX_STRING:
		return
	var seen: Array[StringName] = visited.duplicate()
	seen.append(move_id)
	var detail := _sentence("", tags(move))
	var continues := not move.next_light.is_empty() or not move.next_heavy.is_empty()
	if path.size() == 1 and detail.is_empty() and context.is_empty():
		detail = "Fastest attack; starts your strings." if path[0] == B.LIGHT else ""
	# Middle steps of a string with nothing special about them would only repeat the full string.
	if path.size() == 1 or not detail.is_empty() or not continues:
		out.append(Entry.new(BASICS, _string_name(path), path, detail, context))
	if not move.next_light.is_empty():
		var next: Array[StringName] = path.duplicate()
		next.append(B.LIGHT)
		_strings(data, move.next_light, next, out, seen, context)
	if not move.next_heavy.is_empty():
		var next: Array[StringName] = path.duplicate()
		next.append(B.HEAVY)
		_strings(data, move.next_heavy, next, out, seen, context)


static func _single(data: FighterData, move_id: StringName, name: String, inputs: Array[StringName], context: String,
		out: Array[Entry], line: String = "") -> void:
	var move := data.move_by_id(move_id)
	if move != null:
		out.append(Entry.new(BASICS, name, inputs, _sentence(line, tags(move)), context))


## "Light", "Heavy", or a string like "Light, light, heavy".
static func _string_name(path: Array[StringName]) -> String:
	var words := PackedStringArray()
	for action in path:
		words.append("light" if action == B.LIGHT else "heavy")
	var name := ", ".join(words)
	return name.left(1).to_upper() + name.substr(1)


## A description line plus the data tags: "Rising slash. Launches, 4 s cooldown."
static func _sentence(line: String, extra: PackedStringArray) -> String:
	var tail := ", ".join(extra)
	if not tail.is_empty():
		tail = tail.left(1).to_upper() + tail.substr(1) + "."
	if line.is_empty():
		return tail
	return line if tail.is_empty() else "%s %s" % [line, tail]

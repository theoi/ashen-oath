class_name Hud
extends Control
## In-fight HUD: fighter plates (team 0 on the left, others on the right; extra fighters on a
## side are shown smaller, so 1v2 fits), round timer and pips, the player's ability bar and
## center-screen announcements. Fed by apply(HudState) every frame and on_event() per event.

const ANNOUNCE_SECONDS := 1.3

## Every announcement title so far, oldest first.
var announced: PackedStringArray = []

var _plates: Array[FighterPlate] = []
var _left: VBoxContainer
var _right: VBoxContainer
var _timer: Label
var _round: Label
var _skills: SkillBar
var _announce_title: Label
var _announce_sub: Label
var _queue: Array[Array] = []
var _announce_left := 0.0
var _built_for := -1
var _last_state: HudState


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_left = _column(Control.PRESET_TOP_LEFT, 36.0)
	_right = _column(Control.PRESET_TOP_RIGHT, -36.0)
	_right.alignment = BoxContainer.ALIGNMENT_BEGIN

	var center := VBoxContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	center.offset_top = 18.0
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.add_theme_constant_override("separation", -6)
	add_child(center)
	_timer = Label.new()
	_timer.theme_type_variation = &"HudNumberLabel"
	_timer.add_theme_font_size_override("font_size", 50)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_timer)
	_round = Label.new()
	_round.theme_type_variation = &"SubtleLabel"
	_round.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_round)

	_skills = SkillBar.new()
	_skills.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_skills.offset_bottom = -18.0
	_skills.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_skills.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_skills)

	var announcer := VBoxContainer.new()
	announcer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	announcer.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	announcer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	announcer.grow_vertical = Control.GROW_DIRECTION_BOTH
	announcer.offset_top = -120.0
	add_child(announcer)
	_announce_title = Label.new()
	_announce_title.theme_type_variation = &"TitleLabel"
	_announce_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announcer.add_child(_announce_title)
	_announce_sub = Label.new()
	_announce_sub.theme_type_variation = &"SubheaderLabel"
	_announce_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announcer.add_child(_announce_sub)
	announcer.modulate.a = 0.0


func apply(state: HudState) -> void:
	_last_state = state
	if _built_for != state.fighters.size():
		_build(state)
	for plate in _plates:
		var fighter := state.fighters[plate.slot]
		var wins := state.round_wins[fighter.team] if fighter.team < state.round_wins.size() else 0
		plate.apply(fighter, wins)
	_timer.text = "--" if state.seconds_left < 0.0 else "%d" % ceili(state.seconds_left)
	_timer.add_theme_color_override("font_color", Palette.EMBER if 0.0 <= state.seconds_left and state.seconds_left <= 10.0 else Palette.BONE)
	_round.text = "Round %d" % state.round_number
	var player := _player(state)
	_skills.visible = player != null
	if player != null:
		_skills.apply(player)


func on_event(event: Dictionary) -> void:
	match event.get("type", &""):
		MatchEvents.ROUND_INTRO:
			var round_number: int = event.get("round", 1)
			announce("Round %d" % round_number, "Final round" if _is_final_round() else "")
		MatchEvents.FIGHT:
			announce("Fight", "", 0.8)
		MatchEvents.KO:
			announce("KO", "%s falls" % _name_of(event.get("slot", -1)), 1.1)
		MatchEvents.TIME_UP:
			announce("Time", "", 1.0)
		MatchEvents.ROUND_WON:
			var team: int = event.get("team", -1)
			announce("Draw" if team < 0 else "%s wins the round" % _team_name(team), "", 1.6)
		MatchEvents.PARRY:
			_callout(event.get("slot", -1), "Parry", Palette.GUARD)
		MatchEvents.GUARD_BREAK:
			_callout(event.get("slot", -1), "Guard break", Palette.GUARD_LOW)
		MatchEvents.PERFECT_DODGE:
			_callout(event.get("slot", -1), "Perfect dodge", Palette.SOUL)
		MatchEvents.SOUL_BURST:
			_callout(event.get("slot", -1), "Soul Burst", Palette.SOUL_FULL)
		MatchEvents.SUPER:
			_callout(event.get("slot", -1), "Super", Palette.SOUL_FULL)
		MatchEvents.HIT:
			if event.get("counter", false):
				_callout(event.get("attacker", -1), "Counter", Palette.EMBER_BRIGHT)


## Queues a center-screen announcement.
func announce(title: String, subtitle: String = "", seconds: float = ANNOUNCE_SECONDS) -> void:
	announced.append(title)
	_queue.append([title, subtitle, seconds])
	if _announce_left <= 0.0:
		_next_announcement()


func announcement_text() -> String:
	return _announce_title.text if _announce_left > 0.0 else ""


func plate_for(slot: int) -> FighterPlate:
	for plate in _plates:
		if plate.slot == slot:
			return plate
	return null


func skill_bar() -> SkillBar:
	return _skills


func _process(delta: float) -> void:
	if _announce_left > 0.0:
		_announce_left -= delta
		if _announce_left <= 0.0:
			_next_announcement()


func _next_announcement() -> void:
	var box := _announce_title.get_parent() as Control
	if _queue.is_empty():
		_announce_left = 0.0
		create_tween().tween_property(box, "modulate:a", 0.0, 0.2)
		return
	var item: Array = _queue.pop_front()
	_announce_title.text = item[0]
	var long := (item[0] as String).length() > 10
	_announce_title.add_theme_font_size_override("font_size", 60 if long else 104)
	_announce_sub.text = item[1]
	_announce_left = item[2]
	box.modulate.a = 0.0
	box.pivot_offset = box.size * 0.5
	box.scale = Vector2(1.25, 1.25)
	var tween := create_tween().set_parallel()
	tween.tween_property(box, "modulate:a", 1.0, 0.12)
	tween.tween_property(box, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build(state: HudState) -> void:
	for plate in _plates:
		plate.queue_free()
	_plates.clear()
	_built_for = state.fighters.size()
	var first_on_side := {}
	for fighter in state.fighters:
		var left_side := fighter.team == 0
		var side_key := 0 if left_side else 1
		var compact := first_on_side.has(side_key)
		var team_first := not state.fighters.slice(0, fighter.slot).any(func(f: HudState.Fighter) -> bool: return f.team == fighter.team)
		first_on_side[side_key] = true
		var plate := FighterPlate.new()
		(_left if left_side else _right).add_child(plate)
		plate.setup(fighter, not left_side, compact, team_first, state.rounds_to_win)
		_plates.append(plate)


func _column(preset: LayoutPreset, x: float) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_and_offsets_preset(preset)
	column.offset_left = x if x > 0.0 else -480.0 + x
	column.offset_right = 480.0 + x if x > 0.0 else x
	column.offset_top = 22.0
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	return column


func _player(state: HudState) -> HudState.Fighter:
	for fighter in state.fighters:
		if fighter.is_player:
			return fighter
	return null


func _callout(slot: int, text: String, color: Color) -> void:
	var plate := plate_for(slot)
	if plate != null:
		plate.callout(text, color)


func _name_of(slot: int) -> String:
	if _last_state == null or slot < 0 or slot >= _last_state.fighters.size():
		return "A fighter"
	return _last_state.fighters[slot].name


func _team_name(team: int) -> String:
	if _last_state == null:
		return "Team %d" % (team + 1)
	var members := _last_state.fighters.filter(func(f: HudState.Fighter) -> bool: return f.team == team)
	if members.is_empty():
		return "Team %d" % (team + 1)
	var first: HudState.Fighter = members[0]
	return first.name if members.size() == 1 else "%s's side" % first.name


func _is_final_round() -> bool:
	if _last_state == null:
		return false
	for wins in _last_state.round_wins:
		if wins < _last_state.rounds_to_win - 1:
			return false
	return true

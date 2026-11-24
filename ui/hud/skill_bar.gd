class_name SkillBar
extends HBoxContainer
## The player's skill bar (design-lost-ark §1.11), bottom center: dash charges on the left,
## one SkillSlotView per skill, and the awakening (super) with its Soul ring on the right.
## Soul Burst lights on the dash pips or the awakening, whichever button casts it.

const AWAKENING_SIZE := 76.0
const PIP := 14.0

var _slots: Array[SkillSlotView] = []
var _slot_row: HBoxContainer
var _dash: VBoxContainer
var _dash_pips: Control
var _dash_label: Label
var _dash_prompt: InputPrompt
var _awakening: Control
var _awakening_label: Label
var _awakening_name: Label
var _awakening_prompt: InputPrompt
var _fighter: HudState.Fighter = HudState.Fighter.new()
var _awakening_lit := false
var _burst_lit := false
var _was_full := false
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 14)

	_dash = VBoxContainer.new()
	_dash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dash.alignment = BoxContainer.ALIGNMENT_END
	_dash.add_theme_constant_override("separation", 3)
	add_child(_dash)
	_dash_label = _label(&"StrongLabel", 14)
	_dash.add_child(_dash_label)
	_dash_pips = Control.new()
	_dash_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dash_pips.draw.connect(_draw_dash)
	_dash.add_child(_dash_pips)
	_dash_prompt = InputPrompt.new(&"", 22.0, true)
	_dash.add_child(_dash_prompt)

	_slot_row = HBoxContainer.new()
	_slot_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot_row.add_theme_constant_override("separation", 6)
	add_child(_slot_row)

	var awakening := VBoxContainer.new()
	awakening.mouse_filter = Control.MOUSE_FILTER_IGNORE
	awakening.alignment = BoxContainer.ALIGNMENT_END
	awakening.add_theme_constant_override("separation", 2)
	add_child(awakening)
	_awakening = Control.new()
	_awakening.custom_minimum_size = Vector2(AWAKENING_SIZE, AWAKENING_SIZE)
	_awakening.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_awakening.draw.connect(_draw_awakening)
	awakening.add_child(_awakening)
	_awakening_label = _label(&"StrongLabel", 17)
	_awakening_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_awakening.add_child(_awakening_label)
	_awakening_prompt = InputPrompt.new(&"", 22.0, true)
	awakening.add_child(_awakening_prompt)
	_awakening_name = _label(&"SubtleLabel", 13)
	_awakening_name.custom_minimum_size.x = AWAKENING_SIZE + 30.0
	_awakening_name.clip_text = true
	awakening.add_child(_awakening_name)


func apply(fighter: HudState.Fighter) -> void:
	_fighter = fighter
	_ensure_slots(fighter.skills.size())
	for i in _slots.size():
		_slots[i].apply(fighter.skills[i])

	var soul := clampf(fighter.soul, 0.0, 100.0)
	var alive := not fighter.knocked_out
	var bursting := fighter.burst_window and alive
	_burst_lit = bursting and soul >= 50.0
	var burst_here := bursting and not fighter.burst_on_dash
	_awakening_lit = alive and (soul >= 50.0 if burst_here else soul >= 100.0 and not bursting)
	_awakening_label.text = "BURST" if burst_here else ("" if soul < 100.0 else "READY")
	_awakening_label.add_theme_color_override("font_color", Palette.SOUL_FULL)
	_awakening_name.text = fighter.awakening_name
	_awakening_prompt.modulate.a = 1.0 if _awakening_lit else 0.45
	if _awakening_prompt.action != fighter.awakening_action:
		_awakening_prompt.action = fighter.awakening_action
	var full := soul >= 100.0
	if full and not _was_full and is_inside_tree():
		Sound.play(&"awakening_ready")
	_was_full = full

	_dash.visible = fighter.dash_max > 0
	_dash_pips.custom_minimum_size = Vector2(maxf(fighter.dash_max, 1) * (PIP + 5.0), PIP + 2.0)
	var burst_on_dash := bursting and fighter.burst_on_dash
	_dash_label.text = "BURST" if burst_on_dash else "DASH"
	_dash_label.add_theme_color_override("font_color", Palette.SOUL_FULL if burst_on_dash and _burst_lit else Palette.ASH_TEXT)
	_dash_prompt.modulate.a = 1.0 if (fighter.dash_charges > 0 or (burst_on_dash and _burst_lit)) and alive else 0.45
	if _dash_prompt.action != fighter.dash_action:
		_dash_prompt.action = fighter.dash_action
	_dash_pips.queue_redraw()
	_awakening.queue_redraw()


func slot_count() -> int:
	return _slots.size()


func slot(index: int) -> SkillSlotView:
	return _slots[index]


## Whether skill slot `index` is lit as ready.
func slot_ready(index: int) -> bool:
	return _slots[index].is_lit()


func awakening_ready() -> bool:
	return _awakening_lit


## Soul Burst is available right now (on whichever button casts it).
func burst_ready() -> bool:
	return _burst_lit


func awakening_text() -> String:
	return _awakening_label.text


func dash_text() -> String:
	return _dash_label.text


## Button prompts: skills in order, then dash (when shown) and awakening.
func prompts() -> Array[InputPrompt]:
	var all: Array[InputPrompt] = []
	for view in _slots:
		all.append(view.prompt())
	if _dash.visible:
		all.append(_dash_prompt)
	all.append(_awakening_prompt)
	return all


func _process(delta: float) -> void:
	_time += delta
	if _fighter.soul >= 100.0:
		_awakening.queue_redraw()


func _ensure_slots(count: int) -> void:
	if count == _slots.size():
		return
	for view in _slots:
		_slot_row.remove_child(view)
		view.queue_free()
	_slots.clear()
	for i in count:
		var view := SkillSlotView.new()
		view.became_ready.connect(_on_slot_ready)
		_slots.append(view)
		_slot_row.add_child(view)


func _on_slot_ready() -> void:
	if is_inside_tree():
		Sound.play(&"skill_ready")


func _draw_dash() -> void:
	for i in _fighter.dash_max:
		var center := Vector2(PIP * 0.5 + 1.0 + i * (PIP + 5.0), PIP * 0.5 + 1.0)
		var radius := PIP * 0.5
		_dash_pips.draw_circle(center, radius, Color(0.0, 0.0, 0.0, 0.7))
		if i < _fighter.dash_charges:
			_dash_pips.draw_circle(center, radius - 1.5, Palette.EMBER_BRIGHT)
		elif i == _fighter.dash_charges and _fighter.dash_recharge > 0.0:
			_dash_pips.draw_arc(center, radius - 2.0, -PI / 2.0, -PI / 2.0 + TAU * _fighter.dash_recharge, 24, Palette.EMBER, 3.0)
		_dash_pips.draw_arc(center, radius, 0.0, TAU, 24, Palette.ASH_EDGE, 1.0)


func _draw_awakening() -> void:
	var center := _awakening.size * 0.5
	var radius := AWAKENING_SIZE * 0.5 - 4.0
	var soul := clampf(_fighter.soul, 0.0, 100.0) / 100.0
	_awakening.draw_circle(center, radius, Color(0.12, 0.2, 0.18, 0.9) if _awakening_lit else Color(0.04, 0.035, 0.04, 0.88))
	_awakening.draw_arc(center, radius, 0.0, TAU, 48, Palette.ASH_EDGE, 2.0)
	if soul > 0.0:
		_awakening.draw_arc(center, radius, -PI / 2.0, -PI / 2.0 + TAU * soul, 64, Palette.SOUL, 5.0)
	# Burst threshold mark at 50 Soul.
	_awakening.draw_line(center + Vector2(0.0, radius - 5.0), center + Vector2(0.0, radius + 4.0), Palette.BONE, 2.0)
	if soul >= 1.0:
		var pulse := 0.5 + 0.5 * sin(_time * 6.0)
		_awakening.draw_arc(center, radius + 2.0 + 2.0 * pulse, 0.0, TAU, 64, Color(Palette.SOUL_FULL, 0.4 + 0.5 * pulse), 2.0)


static func _label(variation: StringName, size: int) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.add_theme_font_size_override("font_size", size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

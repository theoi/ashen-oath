class_name AbilityBar
extends HBoxContainer
## The local player's ability slots (as many as the fighter has) and super / Soul Burst, each
## with the button for the active device. A slot lights up (ember frame, bright button) when
## it can be used: an ability once its cooldown is over, the super at 100 Soul, Soul Burst at
## 50 Soul while the player is in hitstun.

const SLOT_SIZE := Vector2(104.0, 64.0)
## Slots narrow past this many abilities so a long bar stays inside the bottom-left corner.
const ROOMY_SLOTS := 4
const PROMPT_SIZE := 26.0
const _NUMERALS: PackedStringArray = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]

var _columns: Array[VBoxContainer] = []
var _fills: Array[ProgressBar] = []
var _counts: Array[Label] = []
var _frames: Array[Panel] = []
var _names: Array[Label] = []
var _numerals: Array[Label] = []
var _prompts: Array[InputPrompt] = []
var _lit: Array[bool] = []
var _super_lit := false
var _super_frame: Panel
var _super_fill: ProgressBar
var _super_label: Label
var _super_prompt: InputPrompt


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 12)
	add_child(_super_slot())


func apply(fighter: HudState.Fighter) -> void:
	_ensure_slots(fighter.ability_names.size())
	for i in _frames.size():
		var left := fighter.cooldown_left[i] if i < fighter.cooldown_left.size() else 0.0
		var total := fighter.cooldown_total[i] if i < fighter.cooldown_total.size() else 1.0
		var ready := left <= 0.0 and not fighter.knocked_out
		_fills[i].value = 1.0 if left <= 0.0 else 1.0 - left / maxf(total, 0.001)
		_counts[i].text = "" if left <= 0.0 else ("%.1f" % left if left < 1.0 else "%d" % ceili(left))
		_numerals[i].visible = left <= 0.0
		_names[i].text = fighter.ability_names[i]
		_lit[i] = _light(ready, _lit[i], _frames[i], _prompts[i], Palette.EMBER_BRIGHT)
	var burst := fighter.burst_window
	var soul := clampf(fighter.soul, 0.0, 100.0)
	var lit := not fighter.knocked_out and (soul >= 50.0 if burst else soul >= 100.0)
	_super_fill.value = soul / 100.0
	_super_label.text = "BURST" if burst else "SUPER"
	_super_label.add_theme_color_override("font_color", Palette.SOUL_FULL if lit else Palette.ASH_TEXT)
	_super_lit = _light(lit, _super_lit, _super_frame, _super_prompt, Palette.SOUL_FULL)


func slot_count() -> int:
	return _frames.size()


## Whether ability slot `index` (0-based) is lit as ready.
func slot_ready(index: int) -> bool:
	return _lit[index]


func super_ready() -> bool:
	return _super_lit


func super_text() -> String:
	return _super_label.text


## The button prompts: ability slots in order, then super.
func prompts() -> Array[InputPrompt]:
	var all := _prompts.duplicate()
	all.append(_super_prompt)
	return all


func _ensure_slots(count: int) -> void:
	if count == _frames.size():
		return
	for column in _columns:
		remove_child(column)
		column.queue_free()
	for list: Array in [_columns, _fills, _counts, _frames, _names, _numerals, _prompts, _lit]:
		list.clear()
	var width := SLOT_SIZE.x if count <= ROOMY_SLOTS else SLOT_SIZE.x * 0.75
	for i in count:
		var column := _slot(i, Vector2(width, SLOT_SIZE.y))
		_columns.append(column)
		_lit.append(false)
		add_child(column)
		move_child(column, i)


## Applies the lit or dim look and returns `lit`.
func _light(lit: bool, was: bool, frame: Panel, prompt: InputPrompt, color: Color) -> bool:
	frame.add_theme_stylebox_override("panel", _frame_style(lit, color))
	prompt.modulate = Color(1, 1, 1, 1.0) if lit else Color(1, 1, 1, 0.35)
	if lit and not was and is_inside_tree():
		# A short flare when a slot comes off cooldown, so readiness is noticed mid-fight.
		frame.pivot_offset = frame.size * 0.5
		frame.scale = Vector2(1.12, 1.12)
		frame.modulate = Color(1.6, 1.4, 1.2)
		var tween := create_tween().set_parallel()
		tween.tween_property(frame, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(frame, "modulate", Color.WHITE, 0.35)
	return lit


func _slot(index: int, size: Vector2) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name := Label.new()
	name.theme_type_variation = &"SubtleLabel"
	name.add_theme_font_size_override("font_size", 15)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.custom_minimum_size.x = size.x
	name.clip_text = true
	_names.append(name)
	column.add_child(name)

	var frame := Panel.new()
	frame.custom_minimum_size = size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(frame)
	var fill := _bar(Color(Palette.EMBER.r, Palette.EMBER.g, Palette.EMBER.b, 0.35))
	frame.add_child(fill)
	var count := Label.new()
	count.theme_type_variation = &"HudNumberLabel"
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var roman := Label.new()
	roman.theme_type_variation = &"SubheaderLabel"
	roman.text = _NUMERALS[index] if index < _NUMERALS.size() else str(index + 1)
	roman.modulate.a = 0.35
	roman.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	roman.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	roman.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_child(roman)
	frame.add_child(count)
	_numerals.append(roman)
	_fills.append(fill)
	_counts.append(count)
	_frames.append(frame)

	var prompt := InputPrompt.new(DefaultBindings.ability_action(index), PROMPT_SIZE)
	_prompts.append(prompt)
	column.add_child(prompt)
	return column


func _super_slot() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var spacer := Label.new()
	spacer.theme_type_variation = &"SubtleLabel"
	spacer.add_theme_font_size_override("font_size", 15)
	column.add_child(spacer)
	_super_frame = Panel.new()
	_super_frame.custom_minimum_size = SLOT_SIZE
	_super_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_super_frame)
	_super_fill = _bar(Color(Palette.SOUL.r, Palette.SOUL.g, Palette.SOUL.b, 0.3))
	_super_frame.add_child(_super_fill)
	_super_label = Label.new()
	_super_label.theme_type_variation = &"StrongLabel"
	_super_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_super_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_super_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_super_frame.add_child(_super_label)
	_super_prompt = InputPrompt.new(DefaultBindings.SUPER, PROMPT_SIZE)
	column.add_child(_super_prompt)
	return column


static func _bar(color: Color) -> ProgressBar:
	var fill := ProgressBar.new()
	fill.min_value = 0.0
	fill.max_value = 1.0
	fill.step = 0.0
	fill.show_percentage = false
	fill.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 3)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	fill.add_theme_stylebox_override("fill", style)
	fill.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	return fill


static func _frame_style(lit: bool, color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(color.r * 0.25, color.g * 0.18, color.b * 0.12, 0.85) if lit else Color(0.03, 0.025, 0.03, 0.82)
	box.border_color = color if lit else Palette.ASH_EDGE
	box.set_border_width_all(2 if lit else 1)
	if lit:
		box.shadow_color = Color(color.r, color.g, color.b, 0.45)
		box.shadow_size = 6
	return box

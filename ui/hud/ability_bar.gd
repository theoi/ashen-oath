class_name AbilityBar
extends HBoxContainer
## The local player's ability cooldowns (slots 1-3) and super / Soul Burst readiness.

const SLOT_SIZE := Vector2(104.0, 64.0)
const KEY_HINTS: PackedStringArray = ["1 · LT+X", "2 · LT+Y", "3 · LT+B"]

var _fills: Array[ProgressBar] = []
var _counts: Array[Label] = []
var _frames: Array[Panel] = []
var _names: Array[Label] = []
var _numerals: Array[Label] = []
var _super_frame: Panel
var _super_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 12)
	for i in 3:
		add_child(_slot(i))
	add_child(_super_slot())


func apply(fighter: HudState.Fighter) -> void:
	for i in _fills.size():
		var left := fighter.cooldown_left[i] if i < fighter.cooldown_left.size() else 0.0
		var total := fighter.cooldown_total[i] if i < fighter.cooldown_total.size() else 1.0
		var ready := left <= 0.0
		_fills[i].value = 1.0 if ready else 1.0 - left / maxf(total, 0.001)
		_counts[i].text = "" if ready else ("%.1f" % left if left < 1.0 else "%d" % ceili(left))
		_numerals[i].visible = ready
		_frames[i].add_theme_stylebox_override("panel", _frame_style(ready, Palette.EMBER_BRIGHT))
		if i < fighter.ability_names.size():
			_names[i].text = fighter.ability_names[i]
	var super_ready := fighter.soul >= 100.0
	var burst_ready := fighter.soul >= 50.0
	_super_frame.add_theme_stylebox_override("panel", _frame_style(super_ready, Palette.SOUL_FULL))
	_super_label.text = "SUPER" if super_ready else ("BURST" if burst_ready else "")
	_super_label.add_theme_color_override("font_color", Palette.SOUL_FULL if super_ready else Palette.SOUL)


func slot_ready(index: int) -> bool:
	return _counts[index].text.is_empty()


func _slot(index: int) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name := Label.new()
	name.theme_type_variation = &"SubtleLabel"
	name.add_theme_font_size_override("font_size", 15)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.custom_minimum_size.x = SLOT_SIZE.x
	name.clip_text = true
	_names.append(name)
	column.add_child(name)

	var frame := Panel.new()
	frame.custom_minimum_size = SLOT_SIZE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(frame)
	var fill := ProgressBar.new()
	fill.min_value = 0.0
	fill.max_value = 1.0
	fill.step = 0.0
	fill.show_percentage = false
	fill.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 3)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Palette.EMBER.r, Palette.EMBER.g, Palette.EMBER.b, 0.35)
	fill.add_theme_stylebox_override("fill", style)
	fill.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	frame.add_child(fill)
	var count := Label.new()
	count.theme_type_variation = &"HudNumberLabel"
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_child(count)
	var roman := Label.new()
	roman.theme_type_variation = &"SubheaderLabel"
	roman.text = ["I", "II", "III"][index]
	roman.modulate.a = 0.35
	roman.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	roman.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	roman.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_child(roman)
	_numerals.append(roman)
	frame.move_child(count, -1)
	_fills.append(fill)
	_counts.append(count)
	_frames.append(frame)

	var key := Label.new()
	key.theme_type_variation = &"SubtleLabel"
	key.add_theme_font_size_override("font_size", 15)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.text = KEY_HINTS[index]
	column.add_child(key)
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
	_super_frame.custom_minimum_size = Vector2(SLOT_SIZE.x, SLOT_SIZE.y)
	column.add_child(_super_frame)
	_super_label = Label.new()
	_super_label.theme_type_variation = &"StrongLabel"
	_super_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_super_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_super_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_super_frame.add_child(_super_label)
	var key := Label.new()
	key.theme_type_variation = &"SubtleLabel"
	key.add_theme_font_size_override("font_size", 15)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.text = "R · RT"
	column.add_child(key)
	return column


static func _frame_style(lit: bool, color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.03, 0.025, 0.03, 0.82)
	box.border_color = color if lit else Palette.ASH_EDGE
	box.set_border_width_all(2 if lit else 1)
	return box

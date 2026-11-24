class_name FighterPlate
extends VBoxContainer
## One fighter's HUD block: name, round pips, health (with a trailing loss bar), guard and Soul.
## Mirrored plates (right side of the screen) drain toward the center.

const TRAIL_DELAY := 0.45
const TRAIL_SPEED := 0.9
const CALLOUT_SECONDS := 0.9

var slot := -1

var _mirrored := false
var _name: Label
var _pips: HBoxContainer
var _health: ProgressBar
var _trail: ProgressBar
var _guard: ProgressBar
var _guard_fill: StyleBoxFlat
var _soul: ProgressBar
var _soul_fill: StyleBoxFlat
var _soul_label: Label
var _callout: Label
var _trail_hold := 0.0
var _last_health := -1.0


func setup(fighter: HudState.Fighter, mirrored: bool, compact: bool, show_pips: bool, rounds_to_win: int) -> void:
	slot = fighter.slot
	_mirrored = mirrored
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 3)
	var width := 300.0 if compact else 450.0

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	header.alignment = BoxContainer.ALIGNMENT_END if mirrored else BoxContainer.ALIGNMENT_BEGIN
	add_child(header)
	_name = Label.new()
	_name.theme_type_variation = &"SubheaderLabel" if not compact else &"StrongLabel"
	_name.text = fighter.name
	_name.add_theme_color_override("font_color", Palette.TEAMS[fighter.team % Palette.TEAMS.size()].lerp(Palette.BONE, 0.45))
	_pips = HBoxContainer.new()
	_pips.add_theme_constant_override("separation", 5)
	_pips.alignment = BoxContainer.ALIGNMENT_CENTER
	if show_pips:
		for i in rounds_to_win:
			var pip := Panel.new()
			pip.custom_minimum_size = Vector2(14.0, 14.0)
			pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_pips.add_child(pip)
	_callout = Label.new()
	_callout.theme_type_variation = &"StrongLabel"
	_callout.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
	_callout.modulate.a = 0.0
	for child: Control in ([_callout, _pips, _name] if mirrored else [_name, _pips, _callout]):
		header.add_child(child)

	var health_stack := Control.new()
	health_stack.custom_minimum_size = Vector2(width, 12.0 if compact else 22.0)
	health_stack.size_flags_horizontal = Control.SIZE_SHRINK_END if mirrored else Control.SIZE_SHRINK_BEGIN
	add_child(health_stack)
	_trail = _bar(Palette.HEALTH_LOSS, true)
	_health = _bar(Palette.HEALTH, false)
	for bar: ProgressBar in [_trail, _health]:
		bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		health_stack.add_child(bar)

	_guard = _bar(Palette.GUARD, true)
	_guard_fill = _guard.get_theme_stylebox("fill") as StyleBoxFlat
	_guard.custom_minimum_size = Vector2(width * 0.62, 5.0 if compact else 7.0)
	_guard.size_flags_horizontal = Control.SIZE_SHRINK_END if mirrored else Control.SIZE_SHRINK_BEGIN
	add_child(_guard)

	var soul_row := HBoxContainer.new()
	soul_row.alignment = BoxContainer.ALIGNMENT_END if mirrored else BoxContainer.ALIGNMENT_BEGIN
	soul_row.add_theme_constant_override("separation", 8)
	add_child(soul_row)
	var soul_stack := Control.new()
	soul_stack.custom_minimum_size = Vector2(width * 0.5, 8.0 if compact else 11.0)
	soul_stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_soul = _bar(Palette.SOUL, true)
	_soul_fill = _soul.get_theme_stylebox("fill") as StyleBoxFlat
	_soul.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	soul_stack.add_child(_soul)
	var burst_tick := ColorRect.new()
	burst_tick.color = Palette.BONE
	burst_tick.custom_minimum_size = Vector2(2.0, 0.0)
	burst_tick.anchor_left = 0.5
	burst_tick.anchor_right = 0.5
	burst_tick.anchor_bottom = 1.0
	burst_tick.offset_left = -1.0
	burst_tick.offset_right = 1.0
	soul_stack.add_child(burst_tick)
	_soul_label = Label.new()
	_soul_label.theme_type_variation = &"SubtleLabel"
	for child: Control in ([_soul_label, soul_stack] if mirrored else [soul_stack, _soul_label]):
		soul_row.add_child(child)
	if compact:
		_soul_label.visible = false
	apply(fighter, 0)


func apply(fighter: HudState.Fighter, team_wins: int) -> void:
	var health := clampf(fighter.health / maxf(fighter.max_health, 1.0), 0.0, 1.0)
	if _last_health >= 0.0 and health < _last_health:
		_trail_hold = TRAIL_DELAY
	if health > _trail.value or _last_health < 0.0:
		_trail.value = health
	_last_health = health
	_health.value = health
	_guard.value = clampf(fighter.guard / maxf(fighter.max_guard, 1.0), 0.0, 1.0)
	_guard_fill.bg_color = Palette.GUARD_LOW if fighter.guard_broken or _guard.value < 0.3 else Palette.GUARD
	_soul.value = clampf(fighter.soul / 100.0, 0.0, 1.0)
	_soul_fill.bg_color = Palette.SOUL_FULL if fighter.soul >= 100.0 else Palette.SOUL
	_soul_label.text = "Soul %d" % floori(fighter.soul)
	modulate = Color(1, 1, 1, 0.45) if fighter.knocked_out else Color.WHITE
	for i in _pips.get_child_count():
		var pip := _pips.get_child(i) as Panel
		var won := (i < team_wins) if not _mirrored else (_pips.get_child_count() - 1 - i < team_wins)
		pip.add_theme_stylebox_override("panel", _pip_style(won))


## A short word over the plate, e.g. "Parry" or "Counter".
func callout(text: String, color: Color = Palette.EMBER_BRIGHT) -> void:
	_callout.text = text
	_callout.add_theme_color_override("font_color", color)
	_callout.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(CALLOUT_SECONDS * 0.6)
	tween.tween_property(_callout, "modulate:a", 0.0, CALLOUT_SECONDS * 0.4)


func health_shown() -> float:
	return _health.value


func soul_shown() -> float:
	return _soul.value


func guard_shown() -> float:
	return _guard.value


func _process(delta: float) -> void:
	if _trail_hold > 0.0:
		_trail_hold -= delta
	elif _trail.value > _health.value:
		_trail.value = maxf(_health.value, _trail.value - TRAIL_SPEED * delta)


func _bar(color: Color, with_background: bool) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.0
	bar.value = 1.0
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.fill_mode = ProgressBar.FILL_END_TO_BEGIN if _mirrored else ProgressBar.FILL_BEGIN_TO_END
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	if not with_background:
		bar.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	return bar


static func _pip_style(won: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.EMBER if won else Color(0.04, 0.03, 0.035, 0.9)
	box.border_color = Palette.EMBER_BRIGHT if won else Palette.ASH_EDGE
	box.set_border_width_all(1)
	return box

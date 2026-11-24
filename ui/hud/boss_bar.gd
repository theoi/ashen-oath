class_name BossBar
extends VBoxContainer
## The boss's bar at the top of the screen: name, a wide health bar with a trailing loss bar,
## the stagger bar under it, and the orange channel-break gauge while a channelled special
## can still be broken (design-lost-ark §5.8).

const WIDTH := 560.0
const TRAIL_DELAY := 0.45
const TRAIL_SPEED := 0.6
const CALLOUT_SECONDS := 1.1
const STAGGER := Color(0.96, 0.84, 0.5)
const CHANNEL := Color(1.0, 0.52, 0.08)

## The slot shown (-1 = none).
var slot := -1

var _name: Label
var _callout: Label
var _health: ProgressBar
var _trail: ProgressBar
var _stagger: ProgressBar
var _stagger_fill: StyleBoxFlat
var _stagger_label: Label
var _channel_row: Control
var _channel: ProgressBar
var _trail_hold := 0.0
var _last_health := -1.0
var _pulse := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 3)
	custom_minimum_size.x = WIDTH

	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 14)
	add_child(header)
	_name = Label.new()
	_name.theme_type_variation = &"SubheaderLabel"
	_name.add_theme_color_override("font_color", Palette.BONE)
	header.add_child(_name)
	_callout = Label.new()
	_callout.theme_type_variation = &"StrongLabel"
	_callout.modulate.a = 0.0
	header.add_child(_callout)

	var health_stack := Control.new()
	health_stack.custom_minimum_size = Vector2(WIDTH, 18.0)
	add_child(health_stack)
	_trail = FighterPlate.make_bar(Palette.HEALTH_LOSS, true, false)
	_health = FighterPlate.make_bar(Palette.HEALTH, false, false)
	for bar: ProgressBar in [_trail, _health]:
		bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		health_stack.add_child(bar)

	var stagger_row := HBoxContainer.new()
	stagger_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stagger_row.add_theme_constant_override("separation", 8)
	add_child(stagger_row)
	_stagger = FighterPlate.make_bar(STAGGER, true, false)
	_stagger_fill = _stagger.get_theme_stylebox("fill") as StyleBoxFlat
	_stagger.custom_minimum_size = Vector2(WIDTH * 0.7, 7.0)
	_stagger.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stagger_row.add_child(_stagger)
	_stagger_label = Label.new()
	_stagger_label.theme_type_variation = &"SubtleLabel"
	_stagger_label.add_theme_font_size_override("font_size", 13)
	_stagger_label.custom_minimum_size.x = 70.0
	stagger_row.add_child(_stagger_label)

	var channel_row := HBoxContainer.new()
	channel_row.alignment = BoxContainer.ALIGNMENT_CENTER
	channel_row.add_theme_constant_override("separation", 8)
	add_child(channel_row)
	_channel_row = channel_row
	var channel_label := Label.new()
	channel_label.theme_type_variation = &"StrongLabel"
	channel_label.add_theme_color_override("font_color", CHANNEL)
	channel_label.text = "Break it"
	channel_row.add_child(channel_label)
	_channel = FighterPlate.make_bar(CHANNEL, true, false)
	_channel.custom_minimum_size = Vector2(WIDTH * 0.55, 13.0)
	_channel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.1, 0.04, 0.0, 0.85)
	frame.border_color = CHANNEL
	frame.set_border_width_all(1)
	_channel.add_theme_stylebox_override("background", frame)
	channel_row.add_child(_channel)


func apply(fighter: HudState.Fighter) -> void:
	if fighter.slot != slot:
		slot = fighter.slot
		_last_health = -1.0
	_name.text = fighter.name
	var health := clampf(fighter.health / maxf(fighter.max_health, 1.0), 0.0, 1.0)
	if _last_health >= 0.0 and health < _last_health:
		_trail_hold = TRAIL_DELAY
	if health > _trail.value or _last_health < 0.0:
		_trail.value = health
	_last_health = health
	_health.value = health
	_stagger.value = 0.0 if fighter.staggered else clampf(fighter.stagger / maxf(fighter.stagger_max, 1.0), 0.0, 1.0)
	_stagger.get_parent().visible = fighter.stagger_max > 0.0
	_stagger_label.text = "Staggered" if fighter.staggered else "Stagger"
	_stagger_label.add_theme_color_override("font_color", STAGGER if fighter.staggered else Palette.ASH_TEXT)
	_channel_row.modulate.a = 1.0 if fighter.channel_max > 0.0 else 0.0
	_channel.value = clampf(fighter.channel / maxf(fighter.channel_max, 1.0), 0.0, 1.0)
	modulate = Color(1, 1, 1, 0.5) if fighter.knocked_out else Color.WHITE


func callout(text: String, color: Color) -> void:
	_callout.text = text
	_callout.add_theme_color_override("font_color", color)
	_callout.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(CALLOUT_SECONDS * 0.6)
	tween.tween_property(_callout, "modulate:a", 0.0, CALLOUT_SECONDS * 0.4)


func health_shown() -> float:
	return _health.value


func stagger_shown() -> float:
	return _stagger.value


func channel_shown() -> float:
	return _channel.value if _channel_row.modulate.a > 0.0 else 0.0


func _process(delta: float) -> void:
	if _trail_hold > 0.0:
		_trail_hold -= delta
	elif _trail.value > _health.value:
		_trail.value = maxf(_health.value, _trail.value - TRAIL_SPEED * delta)
	if _channel_row.modulate.a > 0.0:
		_pulse = fmod(_pulse + delta * 3.0, TAU)
		_channel.self_modulate = Color.WHITE.lerp(Color(1.4, 1.2, 1.0), 0.5 + 0.5 * sin(_pulse))

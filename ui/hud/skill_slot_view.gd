class_name SkillSlotView
extends VBoxContainer
## One skill on the skill bar: initials (or icon), radial cooldown sweep with seconds left,
## the button for the active device, a ⚡ mark on counter skills, charge pips on skills with
## several charges, a draining border while a combo or chain follow-up waits in the slot,
## and a charge bar with the perfect zone.

const BOX := 60.0
const CHARGE_HEIGHT := 7.0

## Emitted when the slot comes off cooldown (for the ready chime).
signal became_ready

var skill: HudState.Skill = HudState.Skill.new()

var _box: Control
var _charge_bar: Control
var _initials: Label
var _count: Label
var _name: Label
var _prompt: InputPrompt
var _was_ready := true
var _flash := 0.0


func _init(action: StringName = &"") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 3)
	_charge_bar = Control.new()
	_charge_bar.custom_minimum_size = Vector2(BOX, CHARGE_HEIGHT)
	_charge_bar.draw.connect(_draw_charge)
	_charge_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_charge_bar)

	_box = Control.new()
	_box.custom_minimum_size = Vector2(BOX, BOX)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.draw.connect(_draw_box)
	add_child(_box)
	_initials = _label(&"SubheaderLabel", 24)
	_initials.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_box.add_child(_initials)
	_count = _label(&"HudNumberLabel", 26)
	_count.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_box.add_child(_count)
	_prompt = InputPrompt.new(action, 22.0, true)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 2)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_box.add_child(_prompt)

	_name = _label(&"SubtleLabel", 12)
	_name.custom_minimum_size.x = BOX + 8.0
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_name)


func apply(value: HudState.Skill) -> void:
	skill = value
	if _prompt.action != skill.action:
		_prompt.action = skill.action
	var following := skill.follow_left > 0.0
	var shown_name := skill.follow_name if following else skill.name
	_name.text = shown_name
	_initials.text = initials(shown_name)
	_initials.visible = skill.icon == null
	var left := 0.0 if following else skill.cooldown_left
	# With a charge left, the slot reads as ready; the pips and a faint sweep show the refill.
	if skill.max_charges > 0 and skill.charges > 0:
		left = 0.0
	_count.text = "" if left <= 0.0 else ("%.1f" % left if left < 1.0 else "%d" % ceili(left))
	_initials.modulate.a = 1.0 if left <= 0.0 else 0.15
	var is_ready := skill.ready()
	if is_ready and not _was_ready:
		_flash = 1.0
		became_ready.emit()
	_was_ready = is_ready
	_box.modulate = Color.WHITE if skill.usable else Color(0.55, 0.55, 0.55, 0.8)
	_prompt.modulate.a = 1.0 if is_ready and skill.usable else 0.45
	_charge_bar.modulate.a = 1.0 if skill.charging else 0.0
	_box.queue_redraw()
	_charge_bar.queue_redraw()


func is_lit() -> bool:
	return skill.ready() and skill.usable


func prompt() -> InputPrompt:
	return _prompt


func shown_name() -> String:
	return _name.text


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 2.5, 0.0)
		_box.queue_redraw()


## "Oathfire Lunge" -> "OL", "Bulwark" -> "BU".
static func initials(text: String) -> String:
	var words := text.split(" ", false)
	if words.is_empty():
		return ""
	if words.size() == 1:
		return words[0].left(2).to_upper()
	return (words[0].left(1) + words[1].left(1)).to_upper()


func _draw_box() -> void:
	var rect := Rect2(Vector2.ZERO, _box.size)
	var lit := is_lit()
	_box.draw_rect(rect, Color(0.17, 0.08, 0.04, 0.92) if lit else Color(0.04, 0.035, 0.04, 0.88))
	if skill.icon != null:
		_box.draw_texture_rect(skill.icon, rect.grow(-3.0), false)
	if skill.cooldown_left > 0.0 and skill.follow_left <= 0.0:
		var fraction := clampf(skill.cooldown_left / maxf(skill.cooldown_total, 0.001), 0.0, 1.0)
		var charge_left := skill.max_charges > 0 and skill.charges > 0
		_draw_sweep(rect, fraction, Color(0.0, 0.0, 0.0, 0.3 if charge_left else 0.6))
	var border := Palette.EMBER_BRIGHT if lit else Palette.ASH_EDGE
	_box.draw_rect(rect, border, false, 2.0 if lit else 1.0)
	if skill.follow_left > 0.0:
		_draw_perimeter(rect.grow(-1.5), skill.follow_left / maxf(skill.follow_total, 0.001), Palette.SOUL_FULL, 3.0)
	if skill.counter:
		_draw_bolt(Vector2(4.0, 3.0))
	_draw_charge_pips(rect)
	if _flash > 0.0:
		_box.draw_rect(rect, Color(1.0, 0.85, 0.6, 0.5 * _flash))
		_box.draw_rect(rect.grow(2.0 * _flash), Color(1.0, 0.8, 0.5, _flash), false, 2.0)


## One diamond per charge along the top-right edge, lit while the charge is available.
func _draw_charge_pips(rect: Rect2) -> void:
	if skill.max_charges < 2:
		return
	for i in skill.max_charges:
		var center := Vector2(rect.end.x - 7.0 - i * 10.0, rect.position.y + 7.0)
		var points := PackedVector2Array([center + Vector2(0.0, -4.0), center + Vector2(4.0, 0.0),
				center + Vector2(0.0, 4.0), center + Vector2(-4.0, 0.0)])
		var lit := skill.max_charges - 1 - i < skill.charges
		_box.draw_colored_polygon(points, Palette.EMBER_BRIGHT if lit else Color(0.0, 0.0, 0.0, 0.7))
		points.append(points[0])
		_box.draw_polyline(points, Palette.EMBER_DIM if lit else Palette.ASH_EDGE, 1.0)


## The counter mark, drawn because the UI fonts have no ⚡ glyph.
func _draw_bolt(at: Vector2) -> void:
	var points := PackedVector2Array([Vector2(8.0, 0.0), Vector2(1.0, 9.0), Vector2(5.5, 9.0),
			Vector2(3.5, 16.0), Vector2(11.0, 6.5), Vector2(6.5, 6.5), Vector2(9.5, 0.0)])
	for i in points.size():
		points[i] += at
	_box.draw_colored_polygon(points, Color(0.55, 0.8, 1.0))
	points.append(points[0])
	_box.draw_polyline(points, Color(0.0, 0.0, 0.0, 0.8), 1.0)


## Dark pie over the part of the cooldown still to run, clockwise from 12 o'clock.
func _draw_sweep(rect: Rect2, fraction: float, color: Color) -> void:
	if fraction <= 0.0:
		return
	var center := rect.get_center()
	var half := rect.size * 0.5
	var points := PackedVector2Array([center])
	var steps := maxi(2, ceili(96.0 * fraction))
	var start := -PI / 2.0 + TAU * (1.0 - fraction)
	for i in steps + 1:
		var direction := Vector2.from_angle(start + TAU * fraction * float(i) / float(steps))
		# Where the ray from the center leaves the square.
		var reach := minf(half.x / maxf(absf(direction.x), 0.0001), half.y / maxf(absf(direction.y), 0.0001))
		points.append(center + direction * reach)
	_box.draw_colored_polygon(points, color)


## A border along `fraction` of the perimeter, clockwise from the top-left corner.
func _draw_perimeter(rect: Rect2, fraction: float, color: Color, width: float) -> void:
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y), rect.position]
	var length := clampf(fraction, 0.0, 1.0) * (rect.size.x + rect.size.y) * 2.0
	var points := PackedVector2Array([corners[0]])
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[i + 1]
		var side := a.distance_to(b)
		if length >= side:
			points.append(b)
			length -= side
		else:
			points.append(a.lerp(b, length / side))
			break
	if points.size() >= 2:
		_box.draw_polyline(points, color, width)


func _draw_charge() -> void:
	if not skill.charging:
		return
	var rect := Rect2(Vector2.ZERO, _charge_bar.size)
	_charge_bar.draw_rect(rect, Color(0.0, 0.0, 0.0, 0.7))
	var perfect := Rect2(rect.position.x + rect.size.x * skill.perfect_from, 0.0,
			rect.size.x * (skill.perfect_to - skill.perfect_from), rect.size.y)
	var in_perfect := skill.perfect_to > skill.perfect_from and skill.charge >= skill.perfect_from and skill.charge <= skill.perfect_to
	if perfect.size.x > 0.0:
		_charge_bar.draw_rect(perfect, Color(1.0, 1.0, 1.0, 0.9 if in_perfect else 0.35))
	var fill := Rect2(rect.position, Vector2(rect.size.x * clampf(skill.charge, 0.0, 1.0), rect.size.y))
	_charge_bar.draw_rect(fill, Color(1.0, 0.95, 0.85) if in_perfect else Palette.EMBER)
	for level in skill.charge_levels:
		var x := rect.size.x * level
		_charge_bar.draw_line(Vector2(x, -1.0), Vector2(x, rect.size.y + 1.0), Palette.BONE, 1.0)
	_charge_bar.draw_rect(rect, Palette.ASH_EDGE, false, 1.0)


static func _label(variation: StringName, size: int) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.add_theme_font_size_override("font_size", size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

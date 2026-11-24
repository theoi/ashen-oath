class_name DamageNumbers
extends Node3D
## Floating damage numbers (design-lost-ark §1.12): rise from the hit point and fade. White
## for hits, gold and larger for counters, red for damage the local player takes, grey for
## armoured hits; size grows with the hit's weight. Consecutive hits of one move on one
## target also show a running total. Presentation only; off when Feel.damage_numbers is off.

const POOL := 24
const DAMAGE_FONT := preload("res://assets/cinzel-font/Cinzel.ttf")
const LIFE := 0.8
const TOTAL_GAP := 0.6
const WHITE := Color(1.0, 0.97, 0.92)
const GOLD := Color(1.0, 0.78, 0.25)
const RED := Color(1.0, 0.32, 0.25)
const GREY := Color(0.62, 0.64, 0.68)

var local_slot: int = 0

var _labels: Array[Label3D] = []
var _ages: PackedFloat32Array = PackedFloat32Array()
var _velocities: Array[Vector3] = []
var _next := 0
var _total_label: Label3D
var _total_key := ""
var _total := 0
var _total_age := 99.0


func _ready() -> void:
	for i in POOL:
		_labels.append(_make_label())
	_ages.resize(POOL)
	_ages.fill(99.0)
	_velocities.resize(POOL)
	_total_label = _make_label()


## Shows `amount` at `at`. `weight` 0..5 (SimEvent weight; 0 = unknown), `counter` gold,
## `taken` red (the local player was hit), `armored` grey with a shield mark.
func show_hit(at: Vector3, amount: int, weight: int, counter: bool, taken: bool, armored: bool, key: String) -> void:
	if not Feel.damage_numbers() or amount <= 0:
		return
	var i := _next
	_next = (_next + 1) % POOL
	var label := _labels[i]
	label.text = str(amount)
	var color := GREY if armored else (RED if taken else (GOLD if counter else WHITE))
	label.modulate = color
	label.outline_modulate = Color(0.05, 0.02, 0.02, 0.9)
	var size := 44 + 10 * clampi(weight - 1, 0, 4) + (18 if counter else 0)
	label.font_size = size
	label.outline_size = maxi(8, size / 5)
	label.global_position = at + Vector3(randf_range(-0.25, 0.25), 0.4, randf_range(-0.25, 0.25))
	label.visible = true
	_ages[i] = 0.0
	_velocities[i] = Vector3(randf_range(-0.4, 0.4), 2.2, 0.0)
	if armored or taken:
		return
	if key == _total_key and _total_age < TOTAL_GAP:
		_total += amount
		_total_label.text = "%d" % _total
		_total_label.modulate = GOLD if counter else WHITE
		_total_label.font_size = 58
		_total_label.outline_size = 12
		_total_label.global_position = at + Vector3.UP * 1.3
		_total_label.visible = true
	else:
		_total = amount
		_total_label.visible = false
	_total_key = key
	_total_age = 0.0


func _process(delta: float) -> void:
	for i in POOL:
		if _ages[i] > LIFE:
			_labels[i].visible = false
			continue
		_ages[i] += delta
		var t := _ages[i] / LIFE
		_labels[i].global_position += _velocities[i] * delta
		_velocities[i].y = maxf(0.3, _velocities[i].y - 5.0 * delta)
		# Pop in large, settle, then fade.
		_labels[i].scale = Vector3.ONE * (1.0 + 0.6 * maxf(0.0, 1.0 - t * 6.0))
		_labels[i].modulate.a = clampf((1.0 - t) * 2.0, 0.0, 1.0)
	_total_age += delta
	if _total_age > TOTAL_GAP + 0.4:
		_total_label.visible = false
	elif _total_age > TOTAL_GAP:
		_total_label.modulate.a = clampf(1.0 - (_total_age - TOTAL_GAP) / 0.4, 0.0, 1.0)


func _make_label() -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0006
	label.shaded = false
	label.double_sided = true
	label.render_priority = 10
	label.outline_render_priority = 9
	label.visible = false
	label.top_level = true
	label.font = DAMAGE_FONT
	add_child(label)
	return label

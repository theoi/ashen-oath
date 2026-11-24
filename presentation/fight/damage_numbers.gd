class_name DamageNumbers
extends Node3D
## Floating damage numbers (design-lost-ark §1.12): white for hits, gold and larger for
## counters, red for damage the local player takes, grey for armoured hits; size grows with
## the hit's weight. Each number pops from 1.4× to 1× over 6 f, rises 0.6 m over 0.7 s and
## fades over its last 0.2 s. The ticks of one hold or multi-hit skill on one target merge
## into one rolling number, and other consecutive hits of one move show a running total.
## Presentation only; off when Feel.damage_numbers is off.

const POOL := 24
const DAMAGE_FONT := preload("res://assets/cinzel-font/Cinzel.ttf")
const LIFE := 0.7
const POP := 0.1
const RISE := 0.6
const FADE := 0.2
## A tick within this many seconds of the last one adds to the rolling number.
const ROLL_GAP := 0.5
const TOTAL_GAP := 0.6
const WHITE := Color(1.0, 0.97, 0.92)
const GOLD := Color(1.0, 0.78, 0.25)
const RED := Color(1.0, 0.32, 0.25)
const GREY := Color(0.62, 0.64, 0.68)

var local_slot: int = 0

var _labels: Array[Label3D] = []
var _ages: PackedFloat32Array = PackedFloat32Array()
var _origins: Array[Vector3] = []
var _next := 0
var _roll_index := -1
var _roll_key := ""
var _roll_total := 0
var _total_label: Label3D
var _total_key := ""
var _total := 0
var _total_age := 99.0


func _ready() -> void:
	for i in POOL:
		_labels.append(_make_label())
	_ages.resize(POOL)
	_ages.fill(99.0)
	_origins.resize(POOL)
	_total_label = _make_label()


## Shows `amount` at `at`. `weight` 0..5 (0 tick, 1 basic .. 5 massive), `counter` gold,
## `taken` red (the local player was hit), `armored` grey with a shield mark.
func show_hit(at: Vector3, amount: int, weight: int, counter: bool, taken: bool, armored: bool, key: String) -> void:
	if not Feel.damage_numbers() or amount <= 0:
		return
	var tick := weight == 0 and not armored
	if tick and key != "" and key == _roll_key and _roll_index >= 0 and _ages[_roll_index] < ROLL_GAP:
		_roll_total += amount
		var rolling := _labels[_roll_index]
		rolling.text = str(_roll_total)
		# Restart the life with a small bump, keeping the number where it is.
		_ages[_roll_index] = POP * 0.5
		_origins[_roll_index] = rolling.global_position - Vector3.UP * RISE * _rise(POP * 0.5)
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
	_origins[i] = at + Vector3(randf_range(-0.25, 0.25), 0.4, randf_range(-0.25, 0.25))
	label.global_position = _origins[i]
	label.scale = Vector3.ONE * 1.4
	label.visible = true
	_ages[i] = 0.0
	if tick:
		_roll_index = i
		_roll_key = key
		_roll_total = amount
		return
	if i == _roll_index:
		_roll_index = -1
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


## The rolling tick number's label and total, or null while none is showing.
func rolling_label() -> Label3D:
	return _labels[_roll_index] if _roll_index >= 0 and _labels[_roll_index].visible else null


func _process(delta: float) -> void:
	for i in POOL:
		if _ages[i] > LIFE:
			_labels[i].visible = false
			continue
		_ages[i] += delta
		var age := minf(_ages[i], LIFE)
		_labels[i].global_position = _origins[i] + Vector3.UP * RISE * _rise(age)
		_labels[i].scale = Vector3.ONE * lerpf(1.4, 1.0, clampf(age / POP, 0.0, 1.0))
		_labels[i].modulate.a = clampf((LIFE - age) / FADE, 0.0, 1.0)
	_total_age += delta
	if _total_age > TOTAL_GAP + 0.4:
		_total_label.visible = false
	elif _total_age > TOTAL_GAP:
		_total_label.modulate.a = clampf(1.0 - (_total_age - TOTAL_GAP) / 0.4, 0.0, 1.0)


## Share of the rise reached at `age` seconds (eases out).
static func _rise(age: float) -> float:
	return 1.0 - pow(1.0 - clampf(age / LIFE, 0.0, 1.0), 2.0)


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

class_name TitleCard
extends Control
## A full-screen title card: black, a heading and a short passage, faded in.

const FADE_SECONDS := 0.7

var _title: Label
var _text: Label
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var black := ColorRect.new()
	black.color = Color(0.008, 0.006, 0.01, 1.0)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 22)
	add_child(column)
	_title = Label.new()
	_title.theme_type_variation = &"HeaderLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
	column.add_child(_title)
	var rule := ColorRect.new()
	rule.color = Palette.EMBER_DIM
	rule.custom_minimum_size = Vector2(220.0, 2.0)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(rule)
	_text = Label.new()
	_text.theme_type_variation = &"BodyLabel"
	_text.add_theme_font_size_override("font_size", 26)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = 780.0
	column.add_child(_text)
	visible = false


func show_card(title: String, text: String) -> void:
	_title.text = title
	_title.visible = not title.is_empty()
	_text.text = text
	visible = true
	modulate.a = 0.0
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, FADE_SECONDS)


func title() -> String:
	return _title.text


func is_typing() -> bool:
	return visible and _tween != null and _tween.is_running()


func complete() -> void:
	if _tween != null:
		_tween.kill()
	modulate.a = 1.0


func hide_card() -> void:
	complete()
	visible = false

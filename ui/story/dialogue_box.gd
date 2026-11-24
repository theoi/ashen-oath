class_name DialogueBox
extends Control
## The bottom dialogue box of story scenes: portrait, speaker name and typewriter text.
## Narration has no name or portrait.

const CHARS_PER_SECOND := 50.0
const PORTRAIT_SIZE := 150.0

var _portrait_frame: PanelContainer
var _portrait: TextureRect
var _name: Label
var _text: Label
var _more: Label
var _shown := 0.0
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left = 90.0
	offset_right = -90.0
	offset_top = -214.0
	offset_bottom = -40.0
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 22)
	panel.add_child(row)

	_portrait_frame = PanelContainer.new()
	_portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_frame.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_portrait_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.03, 0.025, 0.03, 0.95)
	frame_style.border_color = Palette.EMBER_DIM
	frame_style.set_border_width_all(2)
	_portrait_frame.add_theme_stylebox_override("panel", frame_style)
	row.add_child(_portrait_frame)
	_portrait = TextureRect.new()
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_frame.add_child(_portrait)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	row.add_child(column)
	_name = Label.new()
	_name.theme_type_variation = &"SubheaderLabel"
	_name.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
	column.add_child(_name)
	_text = Label.new()
	_text.theme_type_variation = &"BodyLabel"
	_text.add_theme_font_size_override("font_size", 25)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.custom_minimum_size.x = 400.0
	column.add_child(_text)
	_more = Label.new()
	_more.theme_type_variation = &"SubtleLabel"
	_more.text = "▼"
	_more.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_more.add_theme_color_override("font_color", Palette.EMBER)
	column.add_child(_more)


## Starts typing a line. `portrait` null = no portrait (narration).
func show_line(speaker: String, text: String, portrait: Texture2D) -> void:
	_name.text = speaker
	_name.visible = not speaker.is_empty()
	_text.text = text
	_text.add_theme_color_override("font_color", Palette.BONE if not speaker.is_empty() else Palette.ASH_TEXT.lightened(0.25))
	_text.visible_characters = 0
	_shown = 0.0
	_portrait.texture = portrait
	_portrait_frame.visible = portrait != null


func speaker() -> String:
	return _name.text


func text() -> String:
	return _text.text


func is_typing() -> bool:
	return _text.visible_characters >= 0 and _text.visible_characters < _text.get_total_character_count()


## Shows the whole line at once.
func complete() -> void:
	_text.visible_characters = -1


func _process(delta: float) -> void:
	_time += delta
	if is_typing():
		_shown += delta * CHARS_PER_SECOND
		_text.visible_characters = int(_shown)
		if _text.visible_characters >= _text.get_total_character_count():
			complete()
	_more.modulate.a = 0.0 if is_typing() else 0.55 + 0.45 * sin(_time * 4.0)

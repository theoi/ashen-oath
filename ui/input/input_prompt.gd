class_name InputPrompt
extends HBoxContainer
## Shows the button(s) for an action in the active control scheme, as glyphs, and follows
## ActiveDevice when the player switches device. Set `action` (a DefaultBindings action, or
## InputGlyphs.MOVE / CAMERA).

@export var action: StringName = &"":
	set(value):
		action = value
		if is_inside_tree():
			_rebuild()

## Glyph height in pixels.
@export var glyph_size := 30.0


func _init(p_action: StringName = &"", p_size: float = 30.0) -> void:
	action = p_action
	glyph_size = p_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 2)


func _ready() -> void:
	ActiveDevice.changed.connect(_rebuild)
	_rebuild()


## The prompt as text (for tests and screen readers), e.g. "LT + X".
func describe() -> String:
	return InputGlyphs.text(action, ActiveDevice.scheme, ActiveDevice.pad_family)


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if action.is_empty():
		return
	for part: Variant in InputGlyphs.parts(action, ActiveDevice.scheme, ActiveDevice.pad_family):
		if part is Texture2D:
			var glyph := TextureRect.new()
			glyph.texture = part
			glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			glyph.custom_minimum_size = Vector2(glyph_size, glyph_size)
			glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(glyph)
		else:
			var label := Label.new()
			label.text = String(part)
			label.theme_type_variation = &"StrongLabel"
			label.add_theme_font_size_override("font_size", int(glyph_size * 0.6))
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(label)
	tooltip_text = describe()

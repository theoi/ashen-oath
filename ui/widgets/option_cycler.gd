class_name OptionCycler
extends Button
## A "‹  value  ›" selector for gamepad-friendly menus: left/right (or click) cycles.
##
## Options can be marked locked: they are still shown (dimmed, with a lock note), and
## is_selected_locked() lets the screen refuse to confirm them.

signal selection_changed(index: int)

var options: PackedStringArray = []
var locked: Array[bool] = []
var selected := 0
var locked_suffix := "  (locked)"


func _ready() -> void:
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	pressed.connect(func() -> void: step(1))
	mouse_entered.connect(grab_focus)
	_refresh()


func set_options(values: PackedStringArray, index: int = 0) -> void:
	options = values
	locked.resize(values.size())
	locked.fill(false)
	selected = clampi(index, 0, maxi(values.size() - 1, 0))
	_refresh()


func set_locked(index: int, value: bool) -> void:
	if index >= 0 and index < locked.size():
		locked[index] = value
		_refresh()


func is_selected_locked() -> bool:
	return selected < locked.size() and locked[selected]


func select(index: int) -> void:
	if options.is_empty():
		return
	selected = wrapi(index, 0, options.size())
	_refresh()
	selection_changed.emit(selected)


func step(direction: int) -> void:
	if options.size() < 2:
		return
	Sound.play(&"ui_cycle")
	select(selected + direction)


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_left", true):
		accept_event()
		step(-1)
	elif event.is_action_pressed(&"ui_right", true):
		accept_event()
		step(1)


func _refresh() -> void:
	if options.is_empty():
		text = ""
		return
	var value := options[selected] + (locked_suffix if is_selected_locked() else "")
	text = "‹   %s   ›" % value
	var dim := is_selected_locked()
	for color_name: String in ["font_color", "font_focus_color", "font_hover_color"]:
		if dim:
			add_theme_color_override(color_name, Palette.LOCKED.lightened(0.25))
		else:
			remove_theme_color_override(color_name)

class_name MenuScreen
extends Control
## Base for full-screen menus shown by MenuApp.
##
## Every screen must be usable with a gamepad or keyboard alone: return the control to focus
## from default_focus(). ui_cancel goes back unless can_go_back() says no. Build buttons with
## make_button() so they play sounds and take focus on mouse hover.

## Set by MenuApp: the GameFlow.SCREENS key this screen was opened as.
var screen_id: StringName

var _last_focus: Control


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## The control that gets focus when the screen opens.
func default_focus() -> Control:
	return null


func can_go_back() -> bool:
	return true


## Called each time the screen becomes the top screen.
func on_shown() -> void:
	pass


func focus_default() -> void:
	var target := _last_focus
	if not is_instance_valid(target) or not target.is_visible_in_tree() or target.focus_mode == Control.FOCUS_NONE:
		target = default_focus()
	if target != null:
		target.grab_focus()


func remember_focus() -> void:
	var owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if owner != null and is_ancestor_of(owner):
		_last_focus = owner


func go_back() -> void:
	if can_go_back():
		Sound.play(&"ui_back")
		GameFlow.back()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		go_back()
	elif _is_navigation(event) and get_viewport().gui_get_focus_owner() == null:
		# Focus was lost (e.g. a mouse click on empty space): a d-pad or arrow press recovers it.
		get_viewport().set_input_as_handled()
		focus_default()


## A button that plays the confirm sound, then calls `on_press`. Hovering focuses it.
func make_button(text: String, on_press: Callable, variation: StringName = &"") -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = variation
	button.pressed.connect(func() -> void:
		Sound.play(&"ui_confirm")
		on_press.call())
	button.mouse_entered.connect(func() -> void:
		if button.focus_mode != Control.FOCUS_NONE:
			button.grab_focus())
	return button


func make_label(text: String, variation: StringName = &"BodyLabel") -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## A page layout: a header at the top left, a content column, and an optional hint line.
func make_page(title: String) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 90)
	margin.add_theme_constant_override("margin_top", 56)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	column.add_child(make_label(title, &"HeaderLabel"))
	return column


static func _is_navigation(event: InputEvent) -> bool:
	for action: StringName in [&"ui_up", &"ui_down", &"ui_left", &"ui_right"]:
		if event.is_action_pressed(action):
			return true
	return false

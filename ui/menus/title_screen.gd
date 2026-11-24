extends MenuScreen
## Title screen: the game's name over the backdrop. Any key, button or click continues.

var _prompt: Label
var _time := 0.0


func _ready() -> void:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	column.offset_left = 96.0
	column.offset_right = 900.0
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 6)
	add_child(column)

	column.add_child(make_label("ASHEN OATH", &"TitleLabel"))
	column.add_child(make_label("Act 1  ·  The Bell Wakes", &"HeaderLabel"))
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 90.0
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	_prompt = make_label("Press any button", &"SubheaderLabel")
	column.add_child(_prompt)

	var footer := make_label("%s  ·  Godot %s" % [BuildInfo.label(), Engine.get_version_info()["string"]], &"SubtleLabel")
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	footer.offset_left = 96.0
	footer.offset_top = -46.0
	footer.offset_bottom = -18.0
	add_child(footer)


func can_go_back() -> bool:
	return false


func _process(delta: float) -> void:
	_time += delta
	_prompt.modulate.a = 0.55 + 0.45 * sin(_time * 2.4)


func _unhandled_input(event: InputEvent) -> void:
	if _is_press(event):
		get_viewport().set_input_as_handled()
		start()


func start() -> void:
	Sound.play(&"bell_toll")
	GameFlow.open_screen(&"mode_select")


static func _is_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.is_pressed() and not event.is_echo()
	if event is InputEventJoypadButton or event is InputEventMouseButton:
		return event.is_pressed()
	return event is InputEventAction and event.is_pressed()

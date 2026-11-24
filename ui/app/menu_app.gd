class_name MenuApp
extends Node
## The main scene: a 3D backdrop with a stack of menu screens on top.
##
## GameFlow decides which screens to show; this node only builds, hides and restores them.
## Screens below the top stay alive (hidden and disabled) so they keep their focused button.

const BACKDROP := preload("res://presentation/menu_backdrop/menu_backdrop.tscn")
const FADE_SECONDS := 0.14

static var _announced := false

var _stack: Array[MenuScreen] = []
var _host: Control
var _frames_drawn := 0


func _ready() -> void:
	add_child(BACKDROP.instantiate())
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(_make_shade())
	_host = Control.new()
	_host.name = "Screens"
	_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_host)

	var ids := GameFlow.attach_menu(self)
	for i in ids.size():
		_push(ids[i], i == ids.size() - 1)
	set_process(not _announced)


func _exit_tree() -> void:
	GameFlow.detach_menu(self)


func current_screen() -> MenuScreen:
	return null if _stack.is_empty() else _stack.back()


func screen_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for screen in _stack:
		ids.append(screen.screen_id)
	return ids


func push_screen(id: StringName) -> void:
	_push(id, true)


## Returns to the previous screen. The bottom screen stays.
func pop_screen() -> void:
	if _stack.size() <= 1:
		return
	var top: MenuScreen = _stack.pop_back()
	_host.remove_child(top)
	top.queue_free()
	_show(_stack.back())


func _push(id: StringName, visible: bool) -> void:
	if not _stack.is_empty():
		_hide(_stack.back())
	var scene: PackedScene = load(GameFlow.SCREENS[id])
	var screen := scene.instantiate() as MenuScreen
	screen.screen_id = id
	_host.add_child(screen)
	_stack.append(screen)
	if visible:
		_show(screen)
	else:
		_hide(screen)


func _show(screen: MenuScreen) -> void:
	screen.visible = true
	screen.process_mode = Node.PROCESS_MODE_INHERIT
	screen.on_shown()
	Sound.quiet_focus_sound()
	screen.focus_default()
	screen.modulate.a = 0.0
	create_tween().tween_property(screen, "modulate:a", 1.0, FADE_SECONDS)


func _hide(screen: MenuScreen) -> void:
	screen.remember_focus()
	screen.visible = false
	screen.process_mode = Node.PROCESS_MODE_DISABLED


## Darkens the left side of the backdrop so menu text stays readable.
func _make_shade() -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.01, 0.008, 0.012, 0.92))
	gradient.set_color(1, Color(0.01, 0.008, 0.012, 0.15))
	gradient.add_point(0.45, Color(0.01, 0.008, 0.012, 0.72))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 4
	var shade := TextureRect.new()
	shade.texture = texture
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return shade


## Prints the ready marker once per run, after the first screen has had two frames to draw.
func _process(_delta: float) -> void:
	_frames_drawn += 1
	if _frames_drawn >= 2:
		set_process(false)
		if not _announced:
			_announced = true
			print("%s %s" % [BuildInfo.READY_MARKER, BuildInfo.label()])

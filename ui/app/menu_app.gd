class_name MenuApp
extends Node
## The main scene: a 3D backdrop with the menu ScreenStack on top.
## GameFlow decides which screens to show.

const BACKDROP := preload("res://presentation/menu_backdrop/menu_backdrop.tscn")

static var _announced := false

var _screens: ScreenStack
var _frames_drawn := 0


func _ready() -> void:
	add_child(BACKDROP.instantiate())
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(_make_shade())
	_screens = ScreenStack.new()
	_screens.name = "Screens"
	layer.add_child(_screens)
	_screens.set_screens(GameFlow.take_pending_menu())
	set_process(not _announced)


func current_screen() -> MenuScreen:
	return _screens.current_screen()


func screen_ids() -> Array[StringName]:
	return _screens.screen_ids()


## Prints the ready marker once per run, after the first screen has had two frames to draw.
func _process(_delta: float) -> void:
	_frames_drawn += 1
	if _frames_drawn >= 2:
		set_process(false)
		if not _announced:
			_announced = true
			print("%s %s" % [BuildInfo.READY_MARKER, BuildInfo.label()])


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

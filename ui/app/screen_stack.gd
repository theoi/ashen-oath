class_name ScreenStack
extends Control
## A stack of MenuScreens. Only the top one is visible and takes input; the ones below stay
## alive (hidden and disabled) so they keep their focused control.
##
## While in the tree it registers with GameFlow, so GameFlow.open_screen() / back() act on the
## most recently added stack (the pause overlay over a match, otherwise the menus).

## back() was requested on the bottom screen.
signal back_from_root

const FADE_SECONDS := 0.14

var _stack: Array[MenuScreen] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _enter_tree() -> void:
	GameFlow.attach_host(self)


func _exit_tree() -> void:
	GameFlow.detach_host(self)


func current_screen() -> MenuScreen:
	return null if _stack.is_empty() else _stack.back()


func screen_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for screen in _stack:
		ids.append(screen.screen_id)
	return ids


func is_empty() -> bool:
	return _stack.is_empty()


func push_screen(id: StringName) -> MenuScreen:
	return _push(id, true)


## Builds the stack bottom first; only the last screen is shown.
func set_screens(ids: Array[StringName]) -> void:
	clear()
	for i in ids.size():
		_push(ids[i], i == ids.size() - 1)


func pop_screen() -> void:
	if _stack.size() <= 1:
		back_from_root.emit()
		return
	var top: MenuScreen = _stack.pop_back()
	remove_child(top)
	top.queue_free()
	_show(_stack.back())


func clear() -> void:
	for screen in _stack:
		remove_child(screen)
		screen.queue_free()
	_stack.clear()


func _push(id: StringName, visible: bool) -> MenuScreen:
	if not _stack.is_empty():
		_hide(_stack.back())
	var scene: PackedScene = load(GameFlow.SCREENS[id])
	var screen := scene.instantiate() as MenuScreen
	screen.screen_id = id
	add_child(screen)
	_stack.append(screen)
	if visible:
		_show(screen)
	else:
		_hide(screen)
	return screen


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

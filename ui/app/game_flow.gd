extends Node
## Autoload `GameFlow`: moves between menu screens and matches.
##
## Menu screens live in a stack inside the menu app (ui/app/menu_app.tscn, the main scene).
## Screens call open_screen() / back(); leaving a match calls return_to_menu() with the stack
## to rebuild, so "back" from the screen you land on still makes sense.

const MENU_SCENE := "res://ui/app/menu_app.tscn"

## Screen id -> scene. "story" is the entry point the story mode replaces.
const SCREENS: Dictionary[StringName, String] = {
	&"title": "res://ui/menus/title_screen.tscn",
	&"mode_select": "res://ui/menus/mode_select.tscn",
	&"story": "res://ui/story/story_entry.tscn",
	&"controls": "res://ui/menus/controls_screen.tscn",
	&"settings": "res://ui/menus/settings_screen.tscn",
}

var _menu: MenuApp
var _pending_stack: Array[StringName] = [&"title"]


func _ready() -> void:
	# Dev and capture runs can start deeper in the menus: -- --menu=mode_select,settings
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--menu="):
			var stack: Array[StringName] = []
			for id in arg.trim_prefix("--menu=").split(",", false):
				if SCREENS.has(StringName(id)):
					stack.append(StringName(id))
			if not stack.is_empty():
				_pending_stack = stack


## Called by the menu app when it starts; returns the screen stack to show.
func attach_menu(menu: MenuApp) -> Array[StringName]:
	_menu = menu
	var stack := _pending_stack
	_pending_stack = [&"title"]
	return stack


func detach_menu(menu: MenuApp) -> void:
	if _menu == menu:
		_menu = null


func open_screen(id: StringName) -> void:
	if not SCREENS.has(id):
		push_error("unknown screen %s" % id)
		return
	if _menu != null:
		_menu.push_screen(id)
	else:
		return_to_menu([id])


func back() -> void:
	if _menu != null:
		_menu.pop_screen()


## Loads the menu app showing `stack` (bottom first). Unpauses the tree.
func return_to_menu(stack: Array[StringName] = [&"mode_select"]) -> void:
	_pending_stack = stack
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


## Desktop builds can quit; the web build has nowhere to quit to.
func can_quit() -> bool:
	return not OS.has_feature("web")


func quit_game() -> void:
	get_tree().quit()

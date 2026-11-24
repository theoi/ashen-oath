extends MenuScreen
## Story mode entry point (GameFlow screen "story").
##
## Placeholder until story mode lands: the story task replaces this screen (or points
## GameFlow.SCREENS["story"] at its own scene).

var _back: Button


func _ready() -> void:
	var page := make_page("Act 1 · The Bell Wakes")
	var text := make_label("The bell has not yet tolled for Sir Aldric. Story mode is still being forged.", &"BodyLabel")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 640.0
	text.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	page.add_child(text)
	_back = make_button("Back", go_back)
	_back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	page.add_child(_back)


func default_focus() -> Control:
	return _back

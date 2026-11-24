extends MenuScreen
## Chapter select: replay any scene or fight of the act once it is complete. Replays do not
## change the saved progress.

var story: StoryData
var save: StorySave

var _list: VBoxContainer
var _difficulty: OptionCycler
var _back: Button


func _ready() -> void:
	story = StoryDirector.load_story()
	save = StorySave.load_from()
	var page := make_page("Chapter select")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	page.add_child(row)
	var label := make_label("Difficulty", &"SubtleLabel")
	label.custom_minimum_size.x = 120.0
	row.add_child(label)
	_difficulty = OptionCycler.new()
	_difficulty.name = "Difficulty"
	_difficulty.set_options(MatchConfig.DIFFICULTY_NAMES, save.difficulty)
	_difficulty.custom_minimum_size.x = 340.0
	row.add_child(_difficulty)

	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var open := story.steps.size() if save.completed else mini(save.next_step, story.steps.size())
	for i in open:
		_add_chapter(i)
	if open == 0:
		_list.add_child(make_label("Finish Act 1 to replay its scenes and fights here.", &"SubtleLabel"))

	_back = make_button("Back", go_back)
	_back.name = "Back"
	_back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	page.add_child(_back)


func default_focus() -> Control:
	for child in _list.get_children():
		if child is Button:
			return child
	return _back


func chapter_count() -> int:
	return _list.get_children().filter(func(c: Node) -> bool: return c is Button).size()


func play_chapter(index: int) -> void:
	var run := StoryRun.chapter(story, save, index, _difficulty.selected as MatchConfig.Difficulty)
	StoryDirector.begin(StoryDirector.new(run))


func _add_chapter(index: int) -> void:
	var step := story.steps[index]
	var kind := "Scene"
	if step is StoryFight:
		var fight := step as StoryFight
		kind = "Fight  ·  %s" % ("best of 3" if fight.rounds_to_win == 2 else "1 round" if fight.rounds_to_win == 1 else "first to %d" % fight.rounds_to_win)
		if fight.opponents.size() > 1:
			kind += "  ·  1 v %d" % fight.opponents.size()
	var button := make_button("%s      %s" % [step.title, kind], func() -> void: play_chapter(index), &"MenuEntryButton")
	button.name = String(step.id)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_list.add_child(button)

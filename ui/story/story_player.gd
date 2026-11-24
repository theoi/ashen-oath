class_name StoryPlayer
extends Node
## The story player scene: plays a StoryScene as in-engine stills with dialogue and title
## cards, or shows a fight's results card / "You Hollowed" screen over a still of the arena.
## What to show comes from StoryDirector.current().
##
## Scenes: Accept / Light / click advances (the first press finishes the line being typed);
## holding Back (Esc / B) skips the scene.
##
## Run on its own for previews and screenshots (user args after `--`):
##   --step=ID           story step to show (default: the first)
##   --view=results|hollowed   for a fight step: the card instead of a scene
##   --line=N            jump to line N of the scene
##   --shot=PATH         save a PNG after --frames rendered frames, then quit (default 30)

const SKIP_SECONDS := 1.0
const PREVIEW_SAVE := "user://story_preview.cfg"
## Camera and placement for the results / loss stills.
const AFTERMATH_SHOT := [Vector3(-0.9, 1.55, 4.4), Vector3(0.5, 0.85, 0.0), 42.0]

var director: StoryDirector
var stage: StoryStage
var scene: StoryScene
## Line being shown (-1 before the first).
var line_index := -1
var dialogue: DialogueBox
var card: TitleCard
## The results or loss screen when one is shown.
var panel: MenuScreen

var _layer: CanvasLayer
var _skip_box: Control
var _skip_bar: ProgressBar
var _skip_held := 0.0
var _finished := false
var _portraits: Dictionary[StringName, StoryPortrait] = {}
var _shot_path := ""
var _shot_frames := 30
var _frames := 0


func _ready() -> void:
	director = StoryDirector.current()
	var args := _parse_args()
	if director == null:
		director = _preview_director(args)
	stage = StoryStage.new()
	add_child(stage)
	_layer = CanvasLayer.new()
	_layer.layer = 5
	add_child(_layer)
	dialogue = DialogueBox.new()
	dialogue.visible = false
	_layer.add_child(dialogue)
	card = TitleCard.new()
	_layer.add_child(card)
	_build_skip_hint()
	_shot_path = args.get("shot", "")
	_shot_frames = int(args.get("frames", "30"))

	match director.view:
		StoryDirector.View.SCENE:
			play(director.run.step() as StoryScene)
			for i in int(args.get("line", "0")):
				advance()
				advance()
		StoryDirector.View.RESULTS:
			_show_aftermath(true)
		StoryDirector.View.HOLLOWED:
			_show_aftermath(false)


func play(story_scene: StoryScene) -> void:
	scene = story_scene
	stage.build(scene.arena, scene.actors, scene.props)
	if not scene.shots.is_empty():
		stage.set_shot(scene.shots[0])
	_skip_box.visible = true
	advance()


## Next beat: finishes a line still typing, else shows the next line or ends the scene.
func advance() -> void:
	if scene == null or _finished:
		return
	if dialogue.visible and dialogue.is_typing():
		dialogue.complete()
		return
	if card.is_typing():
		card.complete()
		return
	line_index += 1
	if line_index >= scene.lines.size():
		_finish_scene()
		return
	var line := scene.lines[line_index]
	if line.shot >= 0 and line.shot < scene.shots.size():
		stage.set_shot(scene.shots[line.shot])
	stage.show_line(line_index)
	if not line.cue.is_empty():
		Sound.play(line.cue)
	if line.kind == StoryLine.Kind.CARD:
		dialogue.visible = false
		card.show_card(line.title, line.text)
	else:
		card.hide_card()
		dialogue.visible = true
		dialogue.show_line(speaker_name(line), line.text, _portrait(line.speaker))


func skip() -> void:
	_finish_scene()


func is_finished() -> bool:
	return _finished


func current_line() -> StoryLine:
	return scene.lines[line_index] if scene != null and line_index >= 0 and line_index < scene.lines.size() else null


static func speaker_name(line: StoryLine) -> String:
	if not line.speaker_name.is_empty():
		return line.speaker_name
	return "" if line.speaker.is_empty() else Roster.fighter_name(line.speaker)


func _finish_scene() -> void:
	if _finished:
		return
	_finished = true
	_skip_box.visible = false
	director.scene_finished()


func _unhandled_input(event: InputEvent) -> void:
	if scene == null or _finished:
		return
	if event.is_action_pressed(&"ui_accept") or event.is_action_pressed(DefaultBindings.LIGHT):
		get_viewport().set_input_as_handled()
		advance()


func _process(delta: float) -> void:
	if scene != null and not _finished:
		var held := Input.is_action_pressed(&"ui_cancel") or Input.is_action_pressed(DefaultBindings.PAUSE)
		_skip_held = _skip_held + delta if held else 0.0
		_skip_bar.value = clampf(_skip_held / SKIP_SECONDS, 0.0, 1.0)
		if _skip_held >= SKIP_SECONDS:
			skip()
	_frames += 1
	if not _shot_path.is_empty() and _frames == _shot_frames:
		get_viewport().get_texture().get_image().save_png(_shot_path)
		print("saved %s" % _shot_path)
		get_tree().quit()


func _portrait(id: StringName) -> Texture2D:
	if id.is_empty():
		return null
	if not _portraits.has(id):
		var portrait := StoryPortrait.new()
		add_child(portrait)
		portrait.setup(id)
		_portraits[id] = portrait
	for key in _portraits:
		_portraits[key].render_target_update_mode = SubViewport.UPDATE_ALWAYS if key == id else SubViewport.UPDATE_DISABLED
	return _portraits[id].get_texture()


# --- Results and loss -------------------------------------------------------------------

## A still of the fight's arena after the last blow, with the results or loss screen.
func _show_aftermath(won: bool) -> void:
	var fight := director.run.current_fight()
	var actors: Array[StoryActor] = []
	var player := StoryActor.new()
	player.fighter = fight.player if fight != null else &"aldric"
	player.position = Vector3(-0.6, 0.0, 0.7)
	player.facing_degrees = 35.0 if won else 80.0
	player.pose = &"Idle" if won else &"Death_B"
	player.pose_time = -1.0 if won else 99.0
	actors.append(player)
	var opponents: Array[StringName] = fight.opponents if fight != null else []
	for i in opponents.size():
		var foe := StoryActor.new()
		foe.fighter = opponents[i]
		foe.position = Vector3(1.4 + 1.2 * float(i), 0.0, -0.5 - 0.9 * float(i))
		foe.facing_degrees = -110.0 if won else -60.0
		foe.pose = &"Death_A" if won else &"Idle_Combat"
		foe.pose_time = 99.0 if won else -1.0
		actors.append(foe)
	stage.build(fight.arena if fight != null else &"", actors)
	var shot := StoryShot.new()
	shot.position = AFTERMATH_SHOT[0]
	shot.target = AFTERMATH_SHOT[1]
	shot.fov = AFTERMATH_SHOT[2]
	stage.set_shot(shot)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.008, 0.012, 0.55 if won else 0.7)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(shade)
	var screen: MenuScreen = StoryResultsScreen.new() if won else StoryHollowedScreen.new()
	screen.set("director", director)
	panel = screen
	_layer.add_child(screen)
	screen.on_shown()
	screen.focus_default()
	Sound.play(&"ui_start" if won else &"bell_toll")


# --- Skip hint and previews ---------------------------------------------------------------

func _build_skip_hint() -> void:
	_skip_box = VBoxContainer.new()
	_skip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skip_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_skip_box.offset_left = -300.0
	_skip_box.offset_right = -36.0
	_skip_box.offset_top = 26.0
	_skip_box.visible = false
	_layer.add_child(_skip_box)
	var hint := Label.new()
	hint.theme_type_variation = &"SubtleLabel"
	hint.text = "Hold Esc / B to skip"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_box.add_child(hint)
	_skip_bar = ProgressBar.new()
	_skip_bar.show_percentage = false
	_skip_bar.max_value = 1.0
	_skip_bar.custom_minimum_size = Vector2(0.0, 4.0)
	_skip_box.add_child(_skip_bar)


## A director for running this scene alone: one chapter, nothing saved, quits at the end.
func _preview_director(args: Dictionary) -> StoryDirector:
	var story := StoryDirector.load_story()
	var index := maxi(0, story.step_index(StringName(args.get("step", ""))))
	var save := StorySave.load_from(PREVIEW_SAVE)
	var run := StoryRun.chapter(story, save, index, MatchConfig.Difficulty.NORMAL)
	var preview := StoryDirector.new(run)
	var view: String = args.get("view", "")
	preview.view = StoryDirector.View.RESULTS if view == "results" else StoryDirector.View.HOLLOWED if view == "hollowed" else StoryDirector.View.SCENE
	if preview.view != StoryDirector.View.SCENE:
		var result := MatchResult.new()
		result.config = run.match_config(run.current_fight())
		result.winner_team = 0 if preview.view == StoryDirector.View.RESULTS else 1
		result.round_wins.assign([2, 1] if result.winner_team == 0 else [1, 2])
		run.last_result = result
		run.losses = 2 if preview.view == StoryDirector.View.HOLLOWED else 0
		if preview.view == StoryDirector.View.RESULTS:
			run.new_unlocks = run.current_fight().unlocks.duplicate()
	preview.show_player = func() -> void: get_tree().quit()
	preview.start_match = func(_config: MatchConfig) -> void: get_tree().quit()
	preview.to_menu = func(_stack: Array[StringName]) -> void: get_tree().quit()
	StoryDirector.set_current(preview)
	return preview


static func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var trimmed := arg.trim_prefix("--")
		var eq := trimmed.find("=")
		if eq < 0:
			parsed[trimmed] = "1"
		else:
			parsed[trimmed.substr(0, eq)] = trimmed.substr(eq + 1)
	return parsed

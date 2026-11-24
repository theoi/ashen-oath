extends Node
## Plays story mode end to end through the real game: the menus, every scene, every fight
## on the real sim with the CPU opponents, the results and loss screens, auto-save, and
## chapter select. Menus and scenes are driven with the same input actions a player uses;
## the player's fighter is driven by an input source (the CPU AI at Nightmare when it
## exists, else the debug bot). Prints STORY_AUTOPLAY lines and exits 0 when chapter
## select opens after the act, 1 on a timeout. tools/story_playthrough.sh wraps it.
##
## User args (after `--`):
##   --difficulty=easy|normal|hard|nightmare   story difficulty (default normal)
##   --player=cpu|bot|idle   who plays Aldric (default cpu)
##   --force-after=SECONDS   end each round in Aldric's favor after this many fight seconds
##                            (round decided on time with the foes at 1 HP; 0 = off)
##   --lose=FIGHT_ID:N       lose the first N attempts of a fight (forced the same way);
##                            the second loss retries on lower difficulty
##   --resume-after=FIGHT_ID quit to the menu after winning that fight, then Continue
##   --skip-scenes           hold Back to skip scenes instead of reading them
##   --line-seconds=S        reading time per line (default 0.5)
##   --fast=N                Engine.time_scale (default 1)
##   --shots=DIR             save screenshots of each new screen (needs a renderer: Xvfb)
##   --quit-after-step=ID    stop (exit 0) when this step starts (short clips)
##   --timeout=SECONDS       real-time budget (default 1800)

const SAVE_PATH := "user://autoplay_story.cfg"
const PROFILE_PATH := "user://autoplay_profile.cfg"
const ACT_EVERY := 0.25

var _args: Dictionary = {}
var _cooldown := 0.0
var _line_timer := 0.0
var _started_msec := 0
var _seen: Dictionary = {}
var _match: MatchScreen
## Round already forced in the current match.
var _last_round := -1
var _attempts: Dictionary = {}
var _losses_left: Dictionary = {}
var _resumed := false
var _resume_pending := false
var _fights_won := 0
var _losses := 0
var _scenes := 0
var _forced := 0
var _shot_index := 0
var _last_step: StringName = &""
var _done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_args = StoryPlayer._parse_args()
	_started_msec = Time.get_ticks_msec()
	StorySave.default_path = SAVE_PATH
	for path: String in [SAVE_PATH, PROFILE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Profile.path = PROFILE_PATH
	Profile.load_profile()
	var level := MatchConfig.DIFFICULTY_NAMES.find(String(_args.get("difficulty", "normal")).capitalize())
	Settings.default_difficulty = maxi(level, 0) as MatchConfig.Difficulty
	Engine.time_scale = maxf(1.0, float(_args.get("fast", "1")))
	var lose: String = _args.get("lose", "")
	if lose.contains(":"):
		_losses_left[StringName(lose.get_slice(":", 0))] = int(lose.get_slice(":", 1))
	_resume_pending = _args.has("resume-after")
	if _args.has("shots"):
		DirAccess.make_dir_recursive_absolute(_args["shots"])
	_log("start difficulty=%s player=%s" % [MatchConfig.difficulty_name(Settings.default_difficulty), _args.get("player", "cpu")])
	# Persist across scene changes, then start from the title like a player.
	_reparent_to_root.call_deferred()


func _reparent_to_root() -> void:
	var tree := get_tree()
	get_parent().remove_child(self)
	tree.root.add_child(self)
	GameFlow.return_to_menu([&"title"])


func _process(delta: float) -> void:
	if _done:
		return
	if Time.get_ticks_msec() - _started_msec > int(float(_args.get("timeout", "1800")) * 1000.0):
		_finish(1, "timeout")
		return
	var scene := get_tree().current_scene
	if scene is MatchScreen:
		_drive_match(scene as MatchScreen)
	else:
		_match = null
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	_cooldown = ACT_EVERY
	if scene is MenuApp:
		_drive_menu(scene as MenuApp)
	elif scene is StoryPlayer:
		_drive_player(scene as StoryPlayer, delta)


# --- Menus --------------------------------------------------------------------------------

func _drive_menu(app: MenuApp) -> void:
	var screen := app.current_screen()
	if screen == null:
		return
	match screen.screen_id:
		&"title":
			_press(&"ui_accept")
		&"mode_select":
			_choose(screen, "Story")
		&"story":
			_shot_once("story_entry_%d" % int(_resumed))
			if StorySave.load_from().completed:
				_choose(screen, "Chapters")
			elif screen.find_child("Continue", true, false) != null:
				_resumed = true
				_log("menu continue")
				_choose(screen, "Continue")
			else:
				_set_difficulty(screen)
				_choose(screen, "New")
		&"story_chapters":
			_shot_once("chapter_select")
			_log("chapter select open with %d chapters" % int(screen.call("chapter_count")))
			_finish(0, "act complete")


func _set_difficulty(screen: MenuScreen) -> void:
	var cycler := screen.find_child("Difficulty", true, false) as OptionCycler
	if cycler != null and cycler.selected != Settings.default_difficulty:
		cycler.select(Settings.default_difficulty)


# --- Story player -------------------------------------------------------------------------

func _drive_player(player: StoryPlayer, _delta: float) -> void:
	var run := player.director.run
	var step_id := run.step().id if run.step() != null else &""
	match player.director.view:
		StoryDirector.View.SCENE:
			if step_id != _last_step:
				_last_step = step_id
				_scenes += 1
				_log("scene %s (%d lines)" % [step_id, player.scene.lines.size() if player.scene != null else 0])
				if String(_args.get("quit-after-step", "")) == String(step_id):
					_finish(0, "reached %s" % step_id)
					return
			if player.is_finished():
				return
			if _args.has("skip-scenes"):
				Input.action_press(&"ui_cancel")
				return
			_shot_once("scene_%s_%d" % [step_id, player.line_index])
			_line_timer += ACT_EVERY
			if _line_timer >= float(_args.get("line-seconds", "0.5")):
				_line_timer = 0.0
				_press(&"ui_accept")
		StoryDirector.View.RESULTS:
			Input.action_release(&"ui_cancel")
			_shot_once("results_%s" % step_id)
			if _resume_pending and String(_args.get("resume-after", "")) == String(step_id):
				_resume_pending = false
				_log("quit to menu after %s (save next_step=%d)" % [step_id, StorySave.load_from().next_step])
				_choose(player.panel, "Quit")
			else:
				_choose(player.panel, "Continue")
		StoryDirector.View.HOLLOWED:
			_shot_once("hollowed_%s_%d" % [step_id, run.losses])
			var lower := player.panel.find_child("RetryLower", true, false)
			if lower != null:
				_log("retry %s on lower difficulty" % step_id)
				_choose(player.panel, "RetryLower")
			else:
				_log("retry %s" % step_id)
				_choose(player.panel, "Retry")


# --- Matches ------------------------------------------------------------------------------

func _drive_match(screen: MatchScreen) -> void:
	Input.action_release(&"ui_cancel")
	var config := screen.config
	if _match != screen:
		_match = screen
		_last_round = -1
		var step_id := _story_step()
		_last_step = step_id
		_attempts[step_id] = int(_attempts.get(step_id, 0)) + 1
		screen.runner.sources[0] = _player_source(config)
		screen.runner.match_ended.connect(_on_match_ended.bind(step_id), CONNECT_ONE_SHOT)
		_log("fight %s attempt %d: %s on %s, %s, CPU %s" % [step_id, _attempts[step_id], " vs ".join(config.fighters),
				config.arena, "best of %d" % (config.rounds_to_win * 2 - 1), MatchConfig.difficulty_name(config.difficulty)])
		if String(_args.get("quit-after-step", "")) == String(step_id):
			_finish(0, "reached %s" % step_id)
			return
	var sim := screen.runner.sim
	if sim.state.phase != SimState.Phase.FIGHT or screen.is_paused():
		return
	if sim.state.round_tick >= 90:
		_shot_once("fight_%s" % _story_step())
	var losing := int(_losses_left.get(_story_step(), 0)) > 0
	var force_ticks := 180 if losing else int(float(_args.get("force-after", "0")) * 60.0)
	if force_ticks > 0 and sim.state.round_tick >= force_ticks and _last_round != sim.state.round_number:
		_last_round = sim.state.round_number
		_force_round(sim, 1 if losing else 0)


## Decides the round on time with `winner_team` ahead: the other side drops to 1 HP and
## the timer runs out on the next tick.
func _force_round(sim: Sim, winner_team: int) -> void:
	for f in sim.state.fighters:
		if f.ko:
			continue
		f.hp = f.max_hp if f.team == winner_team else 1
	sim.state.round_timer = 1
	_forced += 1


func _on_match_ended(winner_team: int, step_id: StringName) -> void:
	if winner_team == 0:
		_fights_won += 1
		_log("won %s" % step_id)
	else:
		_losses += 1
		_log("lost %s" % step_id)
		if _losses_left.has(step_id):
			_losses_left[step_id] = int(_losses_left[step_id]) - 1


func _player_source(config: MatchConfig) -> InputSource:
	match String(_args.get("player", "cpu")):
		"idle":
			return null
		"bot":
			return DebugBot.new(config.seed)
	var strong := config.duplicate_config()
	strong.difficulty = MatchConfig.Difficulty.NIGHTMARE
	var source := MatchSetup.cpu_source(strong, 0)
	return source if source != null else DebugBot.new(config.seed)


func _story_step() -> StringName:
	var director := StoryDirector.current()
	if director == null or director.run.step() == null:
		return &""
	return director.run.step().id


# --- Helpers ------------------------------------------------------------------------------

func _choose(screen: Control, button_name: String) -> void:
	var button := screen.find_child(button_name, true, false) as Control
	if button == null or not button.is_visible_in_tree():
		return
	button.grab_focus()
	_press(&"ui_accept")


func _press(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)


## Saves a screenshot the second time a key is seen, so the new screen has settled.
func _shot_once(key: String) -> void:
	if not _args.has("shots") or _seen.get(key, false):
		return
	if not _seen.has(key):
		_seen[key] = false
		return
	_seen[key] = true
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		return
	_shot_index += 1
	var path := "%s/%02d_%s.png" % [_args["shots"], _shot_index, key]
	image.save_png(path)


func _log(text: String) -> void:
	print("STORY_AUTOPLAY %s" % text)


func _finish(code: int, why: String) -> void:
	_done = true
	Input.action_release(&"ui_cancel")
	var save := StorySave.load_from()
	_log("unlocked=%s save_next_step=%d completed=%s" % [Profile.unlocked_fighters(), save.next_step, save.completed])
	print("STORY_AUTOPLAY_DONE %s: %s fights_won=%d losses=%d scenes=%d forced_rounds=%d resumed=%s seconds=%.1f" % [
			"ok" if code == 0 else "FAILED", why, _fights_won, _losses, _scenes, _forced, _resumed,
			float(Time.get_ticks_msec() - _started_msec) / 1000.0])
	GameFlow.story_director = null
	Engine.time_scale = 1.0
	get_tree().quit(code)

class_name MatchScreen
extends Node
## A match: the view, the sim MatchRunner, the HUD, and the pause / results overlay.
## GameFlow.start_match() opens this scene with GameFlow.current_match.
##
## Pause (Esc / Start) stops the runner and freezes the pausable tree; the overlay and this
## node keep running. Leaving goes back to MatchConfig.menu_stack.

const RESULTS_DELAY := 2.2
const ROUND_FLOW_SOUNDS: Array[StringName] = [MatchEvents.ROUND_INTRO, MatchEvents.FIGHT, MatchEvents.TIME_UP]

var config: MatchConfig
var runner: MatchRunner
var view: FightView
var hud: Hud

var _hud_state := HudState.new()
var _overlay: CanvasLayer
var _dim: ColorRect
var _screens: ScreenStack
var _paused := false
var _finished := false
var _results_in := -1.0
var _mouse_mode_before_pause := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	config = GameFlow.current_match
	if config == null:
		config = MatchConfig.versus(&"aldric", &"morrigan", &"ashen_chapel", Settings.default_difficulty)
		GameFlow.current_match = config

	var sim_config := MatchSetup.sim_config(config)
	runner = MatchRunner.new()
	runner.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(runner)
	view = FightView.new()
	view.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(view)
	runner.start(sim_config, [])
	var focus_slot := config.human_slots[0] if not config.human_slots.is_empty() else 0
	view.show_match(runner, focus_slot, Roster.arena(config.arena).get("scene", ""))
	view.camera.player_control = not config.attract
	runner.sources = MatchSetup.input_sources(config, view.camera)
	runner.stepped.connect(_on_stepped)

	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 5
	hud_layer.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(hud_layer)
	hud = Hud.new()
	hud_layer.add_child(hud)

	_overlay = CanvasLayer.new()
	_overlay.layer = 10
	add_child(_overlay)
	_dim = ColorRect.new()
	_dim.color = Color(0.01, 0.008, 0.012, 0.78)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	_overlay.add_child(_dim)
	_screens = ScreenStack.new()
	_screens.back_from_root.connect(_on_back_from_root)
	_overlay.add_child(_screens)
	hud.apply(SimHud.fill(runner.sim, _hud_state, config.human_slots))
	# The first round starts inside Sim.new(), before any step: replay those events.
	_on_stepped(runner.sim.events())
	_apply_capture_args()


func is_paused() -> bool:
	return _paused


func is_finished() -> bool:
	return _finished


func result() -> MatchResult:
	return SimHud.result(runner.sim, config)


func pause() -> void:
	if _paused or _finished:
		return
	_paused = true
	runner.paused = true
	_mouse_mode_before_pause = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	_dim.visible = true
	_screens.set_screens([&"pause"])
	Sound.play(&"ui_confirm")


func resume() -> void:
	if not _paused:
		return
	_paused = false
	_screens.clear()
	_dim.visible = false
	get_tree().paused = false
	runner.paused = false
	Input.mouse_mode = _mouse_mode_before_pause
	Sound.play(&"ui_back")


func _process(delta: float) -> void:
	hud.apply(SimHud.fill(runner.sim, _hud_state, config.human_slots))
	if _results_in > 0.0:
		_results_in -= delta
		if _results_in <= 0.0:
			_show_results()


func _on_stepped(events: Array[SimEvent]) -> void:
	for sim_event in events:
		var event := SimHud.translate(runner.sim, sim_event)
		if event.is_empty():
			continue
		hud.on_event(event)
		# FightView's FightFx voices combat events (hits, blocks, abilities...) with
		# per-move cues; the match screen voices only the round flow.
		if event["type"] in ROUND_FLOW_SOUNDS:
			MatchSounds.play_for(event)
		if event["type"] == MatchEvents.MATCH_WON:
			_on_match_won()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(DefaultBindings.PAUSE) and not _finished:
		get_viewport().set_input_as_handled()
		if _paused:
			resume()
		else:
			pause()


func _notification(what: int) -> void:
	# Losing window focus (alt-tab, browser tab switch) pauses the fight.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_inside_tree() and not _finished:
		pause()


func _on_back_from_root() -> void:
	if _paused:
		resume()


func _on_match_won() -> void:
	if _finished:
		return
	_finished = true
	GameFlow.finish_match(result())
	if not config.on_finished.is_valid():
		_results_in = RESULTS_DELAY


func _show_results() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_dim.visible = true
	_screens.set_screens([&"results"])


## For screenshots and clips: --fast=N runs the match N times faster, --pause-after=SECONDS
## opens the pause menu.
func _apply_capture_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fast="):
			Engine.time_scale = maxf(1.0, arg.trim_prefix("--fast=").to_float())
		elif arg.begins_with("--pause-after="):
			get_tree().create_timer(arg.trim_prefix("--pause-after=").to_float(), true, false, true).timeout.connect(pause)

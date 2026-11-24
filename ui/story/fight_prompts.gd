class_name FightPrompts
extends Control
## In-fight prompts (the fight 1 tutorial): one StoryPrompt at a time, with the buttons for
## it, ticked off when the player's fighter does it in the sim. Reads the runner's events
## and state only. Time counts in sim ticks, so prompts wait while the match is paused.

const Goal := StoryPrompt.Goal
const Type := SimEvent.Type
## Lights started within this many ticks of each other count as one string.
const STRING_GAP := 45
## Ticks a ticked-off prompt stays up before the next one.
const DONE_TICKS := 50

var prompts: Array[StoryPrompt] = []
var runner: MatchRunner
var slot := 0
## Index of the prompt shown (prompts.size() once all are done).
var index := 0
## Titles of prompts completed, in order (timeouts excluded).
var completed: Array[String] = []

var _progress := 0
var _ticks := 0
var _done_ticks := -1
var _last_light := -1000
var _last_pos := Vector3i.ZERO
var _moved := 0.0
var _panel: PanelContainer
var _counter: Label
var _title: Label
var _text: Label
var _hint: Label


func setup(prompt_list: Array[StoryPrompt], match_runner: MatchRunner, player_slot: int) -> void:
	prompts = prompt_list
	runner = match_runner
	slot = player_slot
	runner.stepped.connect(_on_stepped)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_panel.offset_left = 36.0
	_panel.offset_right = 476.0
	_panel.offset_top = -110.0
	_panel.offset_bottom = 70.0
	add_child(_panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	_panel.add_child(column)
	_counter = _label(&"SubtleLabel", column)
	_title = _label(&"SubheaderLabel", column)
	_title.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
	_text = _label(&"BodyLabel", column)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint = _label(&"StrongLabel", column)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override("font_color", Palette.BONE)
	_show()


func current() -> StoryPrompt:
	return prompts[index] if index < prompts.size() else null


func is_done() -> bool:
	return index >= prompts.size()


## The binding line for a prompt: gamepad, then keyboard + mouse.
static func hint_for(prompt: StoryPrompt) -> String:
	if not prompt.hint.is_empty():
		return prompt.hint
	if prompt.actions.is_empty():
		return ""
	var bindings := {}
	for binding in DefaultBindings.gameplay():
		bindings[binding.action] = binding
	var pad := PackedStringArray()
	var keys := PackedStringArray()
	for action in prompt.actions:
		if not bindings.has(action):
			continue
		var binding: DefaultBindings.Binding = bindings[action]
		var pad_text := DefaultBindings.gamepad_hint(action)
		if pad_text.is_empty():
			pad_text = _join_events(binding.gamepad)
		pad.append(pad_text)
		keys.append(_join_events(binding.keyboard_mouse))
	return "%s   ·   %s" % [" , ".join(pad), " , ".join(keys)]


static func _join_events(events: Array[InputEvent]) -> String:
	var names := PackedStringArray()
	for event in events:
		var text := DefaultBindings.describe(event)
		if not text in names:
			names.append(text)
	return " / ".join(names)


func _on_stepped(events: Array[SimEvent]) -> void:
	if is_done() or runner.sim.state.phase != SimState.Phase.FIGHT:
		return
	_ticks += 1
	if _done_ticks >= 0:
		_done_ticks += 1
		if _done_ticks >= DONE_TICKS:
			_next()
		return
	var prompt := current()
	var f := runner.sim.fighter(slot)
	match prompt.goal:
		Goal.MOVE:
			var step := Vector2(f.pos.x - _last_pos.x, f.pos.z - _last_pos.z).length()
			if _ticks > 1 and step < Fx.ONE:
				_moved += step / float(Fx.ONE)
			_last_pos = f.pos
			if _moved >= float(prompt.amount):
				_complete()
				return
		Goal.GUARD:
			if f.action == FighterState.Action.GUARD:
				_progress += 1
				if _progress >= prompt.amount:
					_complete()
					return
	for event in events:
		if _matches(prompt, event):
			_complete()
			return
	if prompt.timeout_seconds > 0.0 and _ticks >= int(prompt.timeout_seconds * 60.0):
		_next()


func _matches(prompt: StoryPrompt, event: SimEvent) -> bool:
	match prompt.goal:
		Goal.LIGHT_STRING:
			if event.type == Type.MOVE_START and event.source == slot and _move_kind(event) == MoveData.Kind.LIGHT:
				_progress = _progress + 1 if event.tick - _last_light <= STRING_GAP else 1
				_last_light = event.tick
				return _progress >= prompt.amount
		Goal.GUARD:
			return (event.type == Type.BLOCK and event.target == slot) or (event.type == Type.PARRY and event.source == slot)
		Goal.DODGE:
			if event.type == Type.DODGE and event.source == slot:
				_progress += 1
				return _progress >= prompt.amount
		Goal.GRAB:
			return (event.type == Type.MOVE_START and event.source == slot and _move_kind(event) == MoveData.Kind.GRAB) \
					or (event.type == Type.GRAB and event.source == slot)
		Goal.ABILITY:
			return event.type == Type.MOVE_START and event.source == slot and _move_kind(event) == MoveData.Kind.ABILITY
		Goal.TARGET:
			return event.type == Type.LOCK_ON and event.source == slot
		Goal.BURST:
			return event.type == Type.BURST and event.source == slot
	return false


func _move_kind(event: SimEvent) -> int:
	var data := runner.sim.fighter_data[event.source]
	if event.amount < 0 or event.amount >= data.moves.size():
		return -1
	return data.moves[event.amount].kind


func _complete() -> void:
	completed.append(current().title)
	_done_ticks = 0
	Sound.play(&"ui_confirm")
	_title.text = "✓  %s" % current().title
	_title.add_theme_color_override("font_color", Palette.SOUL)
	_text.modulate.a = 0.5
	_hint.modulate.a = 0.5


func _next() -> void:
	index += 1
	_progress = 0
	_ticks = 0
	_done_ticks = -1
	_moved = 0.0
	_last_light = -1000
	_show()


func _show() -> void:
	if _panel == null:
		return
	var prompt := current()
	if prompt == null:
		create_tween().tween_property(_panel, "modulate:a", 0.0, 0.4)
		return
	# Only prompts that wait for the player are numbered (the tutorial's steps).
	var counted := prompts.filter(func(p: StoryPrompt) -> bool: return p.goal != Goal.NONE and p.timeout_seconds <= 0.0)
	var position := counted.find(prompt)
	_counter.text = "Training  %d / %d" % [position + 1, counted.size()] if position >= 0 else ""
	_counter.visible = not _counter.text.is_empty()
	_title.text = prompt.title
	_title.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
	_text.text = prompt.text
	_text.modulate.a = 1.0
	_hint.text = hint_for(prompt)
	_hint.modulate.a = 1.0
	_hint.visible = not _hint.text.is_empty()
	_panel.modulate.a = 0.0
	create_tween().tween_property(_panel, "modulate:a", 1.0, 0.25)


func _label(variation: StringName, parent: Container) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

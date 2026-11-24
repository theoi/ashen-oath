class_name FightPrompts
extends Control
## In-fight tips (the story tutorial): one StoryPrompt at a time with the buttons for it,
## ticked off when the player's fighter does it in the sim. In-order tips follow the list;
## contextual tips (Soul full, caught in a combo) cut in while their moment lasts. Doing
## something before its tip comes up counts too. The player can skip the tip shown (View /
## Back on a gamepad, F1 on a keyboard). Reads the runner's events and state only; time
## counts in sim ticks, so tips wait while the match is paused.

const Goal := StoryPrompt.Goal
const Trigger := StoryPrompt.Trigger
const Type := SimEvent.Type
const Action := FighterState.Action
## Lights started within this many ticks of each other count as one string.
const STRING_GAP := 45
## Ticks a ticked-off tip stays up before the next one.
const DONE_TICKS := 50
## Ticks a contextual tip stays after its moment passes.
const LINGER_TICKS := 120
const SKIP_KEY := KEY_F1
const SKIP_BUTTON := JOY_BUTTON_BACK
const SKIP_HINT := "Skip tip: View / F1"

var prompts: Array[StoryPrompt] = []
var runner: MatchRunner
var slot := 0
## Prompt index -> true once done or skipped. Shared with the story run, so a retry does
## not repeat tips already seen.
var done: Dictionary = {}
## Titles completed by doing them, in order (skips and timeouts excluded).
var completed: Array[String] = []
## Index of the tip shown (-1 = none).
var active := -1

var _progress := 0
var _ticks := 0
var _done_ticks := -1
var _linger := 0
var _last_light := -1000
var _last_pos := Vector3i.ZERO
var _moved := 0.0
var _panel: PanelContainer
var _counter: Label
var _title: Label
var _text: Label
var _buttons: HBoxContainer
var _skip: Label


func setup(prompt_list: Array[StoryPrompt], match_runner: MatchRunner, player_slot: int, done_state: Dictionary = {}) -> void:
	prompts = prompt_list
	runner = match_runner
	slot = player_slot
	done = done_state
	runner.stepped.connect(_on_stepped)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_panel.offset_left = 36.0
	_panel.offset_right = 436.0
	_panel.offset_top = -100.0
	_panel.grow_vertical = Control.GROW_DIRECTION_END
	add_child(_panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	_panel.add_child(column)
	_counter = _label(&"SubtleLabel", column)
	_title = _label(&"SubheaderLabel", column)
	_text = _label(&"BodyLabel", column)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_buttons = HBoxContainer.new()
	_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buttons.add_theme_constant_override("separation", 10)
	column.add_child(_buttons)
	_skip = _label(&"SubtleLabel", column)
	_skip.text = SKIP_HINT
	_skip.add_theme_font_size_override("font_size", 14)
	_panel.visible = false
	var device := _active_device()
	if device != null and device.has_signal(&"changed"):
		device.connect(&"changed", func() -> void:
			if current() != null:
				_fill_buttons(current()))


func current() -> StoryPrompt:
	return prompts[active] if active >= 0 else null


func is_done() -> bool:
	return prompts.size() == done.size() and _done_ticks < 0


## Skips the tip shown.
func skip() -> void:
	if active < 0 or _done_ticks >= 0:
		return
	done[active] = true
	Sound.play(&"ui_back")
	_switch(_pick(runner.sim.fighter(slot)))


## The buttons for `action` as text: the active device's (ActiveDevice + InputGlyphs, when
## the project has them), else the gamepad and keyboard + mouse bindings.
static func binding_text(action: StringName) -> String:
	var device := _active_device()
	var glyphs := _glyphs()
	if device != null and glyphs != null:
		var text: String = glyphs.call("text", action, device.get("scheme"), device.get("pad_family"))
		if not text.is_empty():
			return text
	if action == &"move":
		return "Left stick  ·  W A S D"
	var binding: DefaultBindings.Binding = null
	for b in DefaultBindings.gameplay():
		if b.action == action:
			binding = b
	if binding == null:
		return ""
	var pad := DefaultBindings.gamepad_hint(action)
	if pad.is_empty():
		pad = _join_events(binding.gamepad)
	return "%s  ·  %s" % [pad, _join_events(binding.keyboard_mouse)]


## The tip's title: its own, or for an ability tip without one, the fighter's ability name.
static func title_for(prompt: StoryPrompt, fighter: StringName) -> String:
	if not prompt.title.is_empty():
		return prompt.title
	if prompt.goal == Goal.ABILITY and prompt.ability_slot >= 0:
		var names := Roster.ability_names(fighter)
		if prompt.ability_slot < names.size():
			return names[prompt.ability_slot]
		return "Ability %d" % (prompt.ability_slot + 1)
	return ""


## The actions whose buttons a tip shows: its own, or the input for its ability slot,
## awakening or Soul Burst. Skill-kit fighters (FighterData.dash set) burst with the dash.
static func actions_for(prompt: StoryPrompt, fighter: FighterData = null) -> Array[StringName]:
	if not prompt.actions.is_empty():
		return prompt.actions
	match prompt.goal:
		Goal.ABILITY:
			if prompt.ability_slot >= 0 and prompt.ability_slot < DefaultBindings.ability_actions().size():
				return [DefaultBindings.ability_action(prompt.ability_slot)]
		Goal.SUPER:
			return [DefaultBindings.AWAKEN]
		Goal.BURST:
			return [DefaultBindings.DASH if fighter != null and fighter.dash != null else DefaultBindings.AWAKEN]
	return []


## One line with the buttons of every action of `prompt`.
static func hint_for(prompt: StoryPrompt, fighter: FighterData = null) -> String:
	var parts := PackedStringArray()
	for action in actions_for(prompt, fighter):
		var text := binding_text(action)
		if not text.is_empty():
			parts.append(text)
	return "   |   ".join(parts)


## Looked up at runtime: device-aware prompts are optional for this overlay.
static func _active_device() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(^"ActiveDevice") if tree != null else null


static func _glyphs() -> Script:
	for entry in ProjectSettings.get_global_class_list():
		if entry["class"] == &"InputGlyphs":
			return load(entry["path"]) as Script
	return null


static func _join_events(events: Array[InputEvent]) -> String:
	var names := PackedStringArray()
	for event in events:
		var text := DefaultBindings.describe(event)
		if not text in names:
			names.append(text)
	return " / ".join(names)


func _input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventKey:
		pressed = event.is_pressed() and not event.is_echo() and (event as InputEventKey).physical_keycode == SKIP_KEY
	elif event is InputEventJoypadButton:
		pressed = event.is_pressed() and (event as InputEventJoypadButton).button_index == SKIP_BUTTON
	if pressed and active >= 0:
		get_viewport().set_input_as_handled()
		skip()


func _on_stepped(events: Array[SimEvent]) -> void:
	if runner.sim.state.phase != SimState.Phase.FIGHT:
		return
	var f := runner.sim.fighter(slot)
	# Things done before their tip comes up count as learned.
	for i in prompts.size():
		if not done.has(i) and i != active and _event_goal_met(prompts[i], events):
			done[i] = true
	if _done_ticks >= 0:
		_done_ticks += 1
		if _done_ticks >= DONE_TICKS:
			_done_ticks = -1
			_switch(-1)
		return
	var wanted := _pick(f)
	if wanted != active:
		_switch(wanted)
	if active < 0:
		return
	_ticks += 1
	var prompt := current()
	if _goal_progress(prompt, f, events):
		_complete()
	elif prompt.timeout_seconds > 0.0 and _ticks >= int(prompt.timeout_seconds * 60.0):
		done[active] = true
		_switch(-1)


## The tip that should be shown now.
func _pick(f: FighterState) -> int:
	for i in prompts.size():
		if not done.has(i) and prompts[i].trigger != Trigger.IN_ORDER and _moment(prompts[i], f):
			_linger = LINGER_TICKS
			return i
	if active >= 0 and prompts[active].trigger != Trigger.IN_ORDER and not done.has(active) and _linger > 0:
		_linger -= 1
		return active
	for i in prompts.size():
		if not done.has(i) and prompts[i].trigger == Trigger.IN_ORDER:
			return i
	return -1


## Whether a contextual tip's moment is now.
func _moment(prompt: StoryPrompt, f: FighterState) -> bool:
	var rules := runner.sim.rules
	match prompt.trigger:
		Trigger.SOUL_FULL:
			return f.soul_points() >= rules.super_cost
		Trigger.IN_COMBO:
			var caught := f.action in [Action.HITSTUN, Action.AIR_HITSTUN, Action.WALL_SPLAT]
			return caught and f.soul_points() >= rules.burst_cost
	return false


## Progress of the shown tip this tick; true when it is met.
func _goal_progress(prompt: StoryPrompt, f: FighterState, events: Array[SimEvent]) -> bool:
	match prompt.goal:
		Goal.MOVE:
			var step := Vector2(f.pos.x - _last_pos.x, f.pos.z - _last_pos.z).length()
			if _ticks > 1 and step < Fx.ONE:
				_moved += step / float(Fx.ONE)
			_last_pos = f.pos
			return _moved >= float(prompt.amount)
		Goal.GUARD:
			if f.action == Action.GUARD:
				_progress += 1
		Goal.LIGHT_STRING:
			for event in events:
				if event.type == Type.MOVE_START and event.source == slot and _move_kind(event) == MoveData.Kind.LIGHT:
					_progress = _progress + 1 if event.tick - _last_light <= STRING_GAP else 1
					_last_light = event.tick
			return _progress >= prompt.amount
		Goal.DODGE, Goal.TARGET:
			for event in events:
				if _event_matches(prompt, event):
					_progress += 1
			return _progress >= prompt.amount
	if prompt.goal == Goal.GUARD and _progress >= prompt.amount:
		return true
	return _event_goal_met(prompt, events)


## One-event goals (and GUARD's block), checkable for any pending tip.
func _event_goal_met(prompt: StoryPrompt, events: Array[SimEvent]) -> bool:
	if prompt.goal in [Goal.NONE, Goal.MOVE, Goal.LIGHT_STRING] or prompt.amount > 1 and prompt.goal in [Goal.DODGE, Goal.TARGET]:
		return false
	for event in events:
		if _event_matches(prompt, event):
			return true
	return false


func _event_matches(prompt: StoryPrompt, event: SimEvent) -> bool:
	match prompt.goal:
		Goal.GUARD:
			return event.type == Type.BLOCK and event.target == slot
		Goal.PARRY:
			return event.type == Type.PARRY and event.source == slot
		Goal.DODGE:
			return (event.type == Type.DODGE or event.type == Type.DASH) and event.source == slot
		Goal.GRAB:
			return (event.type == Type.MOVE_START and event.source == slot and _move_kind(event) == MoveData.Kind.GRAB) \
					or (event.type == Type.GRAB and event.source == slot)
		Goal.ABILITY:
			if event.type != Type.MOVE_START or event.source != slot or _move_kind(event) != MoveData.Kind.ABILITY:
				return false
			var abilities := runner.sim.fighter_data[slot].abilities
			return prompt.ability_slot < 0 or (prompt.ability_slot < abilities.size() and event.id == abilities[prompt.ability_slot])
		Goal.SUPER:
			return event.type == Type.MOVE_START and event.source == slot and _move_kind(event) == MoveData.Kind.SUPER
		Goal.TARGET, Goal.LOCK_ON:
			return event.type == Type.LOCK_ON and event.source == slot and event.target >= 0
		Goal.BURST:
			return event.type == Type.BURST and event.source == slot
	return false


func _move_kind(event: SimEvent) -> int:
	var data := runner.sim.fighter_data[event.source]
	if event.amount < 0 or event.amount >= data.moves.size():
		return -1
	return data.moves[event.amount].kind


func _complete() -> void:
	completed.append(_title_of(current()))
	done[active] = true
	_done_ticks = 0
	Sound.play(&"ui_confirm")
	_title.text = "✓  %s" % _title_of(current())
	_title.add_theme_color_override("font_color", Palette.SOUL)
	_text.modulate.a = 0.5
	_buttons.modulate.a = 0.5
	_skip.visible = false


func _switch(index: int) -> void:
	active = index
	_progress = 0
	_ticks = 0
	_moved = 0.0
	_last_light = -1000
	_last_pos = runner.sim.fighter(slot).pos
	_show()


func _show() -> void:
	if _panel == null:
		return
	var prompt := current()
	if prompt == null:
		if _panel.visible:
			var tween := create_tween()
			tween.tween_property(_panel, "modulate:a", 0.0, 0.3)
			tween.tween_callback(func() -> void: _panel.visible = false)
		return
	var ordered := prompts.filter(func(p: StoryPrompt) -> bool: return p.trigger == Trigger.IN_ORDER and p.goal != Goal.NONE)
	var position := ordered.find(prompt)
	_counter.text = "Training  %d / %d" % [position + 1, ordered.size()] if position >= 0 else "Tip"
	_title.text = _title_of(prompt)
	_title.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
	_text.text = prompt.text
	_text.modulate.a = 1.0
	_fill_buttons(prompt)
	_buttons.modulate.a = 1.0
	_skip.visible = prompt.goal != Goal.NONE
	_panel.visible = true
	_panel.modulate.a = 0.0
	create_tween().tween_property(_panel, "modulate:a", 1.0, 0.2)


func _fill_buttons(prompt: StoryPrompt) -> void:
	for child in _buttons.get_children():
		_buttons.remove_child(child)
		child.queue_free()
	var actions := actions_for(prompt, runner.sim.fighter_data[slot] if runner != null and runner.sim != null else null)
	for action in actions:
		var label := _label(&"StrongLabel", _buttons)
		label.text = binding_text(action)
		label.add_theme_color_override("font_color", Palette.BONE)
	_buttons.visible = not actions.is_empty()


func _title_of(prompt: StoryPrompt) -> String:
	return title_for(prompt, runner.sim.fighter_data[slot].id if runner != null else &"")


func _label(variation: StringName, parent: Container) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

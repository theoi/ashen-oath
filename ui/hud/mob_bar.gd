class_name MobBar
extends HBoxContainer
## A story-wave enemy in the HUD: a small name and a thin health bar, plus a thin orange
## channel-break gauge while it channels. Up to seven stack under the main plates.

const BAR_WIDTH := 170.0

var slot := -1

var _name: Label
var _health: ProgressBar
var _channel: ProgressBar


func setup(fighter: HudState.Fighter, mirrored: bool) -> void:
	slot = fighter.slot
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END if mirrored else BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", 8)
	size_flags_horizontal = Control.SIZE_SHRINK_END if mirrored else Control.SIZE_SHRINK_BEGIN
	_name = Label.new()
	_name.theme_type_variation = &"SubtleLabel"
	_name.add_theme_font_size_override("font_size", 13)
	var bars := VBoxContainer.new()
	bars.add_theme_constant_override("separation", 2)
	bars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_health = FighterPlate.make_bar(Palette.HEALTH, true, mirrored)
	_health.custom_minimum_size = Vector2(BAR_WIDTH, 8.0)
	bars.add_child(_health)
	_channel = FighterPlate.make_bar(BossBar.CHANNEL, true, mirrored)
	_channel.custom_minimum_size = Vector2(BAR_WIDTH, 4.0)
	bars.add_child(_channel)
	for child: Control in ([_name, bars] if mirrored else [bars, _name]):
		add_child(child)
	apply(fighter)


func apply(fighter: HudState.Fighter) -> void:
	_name.text = fighter.name
	# Wave slots are free (team -1) until something spawns in them.
	if fighter.team >= 0:
		_name.add_theme_color_override("font_color", Palette.TEAMS[fighter.team % Palette.TEAMS.size()].lerp(Palette.BONE, 0.55))
	_health.value = clampf(fighter.health / maxf(fighter.max_health, 1.0), 0.0, 1.0)
	_channel.value = clampf(fighter.channel / maxf(fighter.channel_max, 1.0), 0.0, 1.0)
	_channel.modulate.a = 1.0 if fighter.channel_max > 0.0 else 0.0
	modulate = Color(1, 1, 1, 0.4) if fighter.knocked_out else Color.WHITE


func health_shown() -> float:
	return _health.value

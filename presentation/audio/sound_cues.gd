class_name SoundCues
extends RefCounted
## Sound cue table: cue id -> files, bus, loudness and pitch variation.
##
## Gameplay and presentation code refer to cues by id (`Sound.play(&"ui_confirm")`, or a cue
## id stored in content data). Add a row here to add a cue; several files mean one is picked
## at random per play.

const UI := &"UI"
const SFX := &"SFX"
const MUSIC := &"Music"

const _IFACE := "res://assets/kenney-interface-sounds/"
const _IMPACT := "res://assets/kenney-impact-sounds/"
const _RPG := "res://assets/kenney-rpg-audio/"

## id: [files, bus, volume_db, pitch_scale, pitch_jitter (+/- fraction)]
const TABLE: Dictionary[StringName, Array] = {
	&"ui_move": [[_IFACE + "tick_002.ogg"], UI, -4.0, 0.9, 0.04],
	&"ui_confirm": [[_IFACE + "select_004.ogg"], UI, -3.0, 0.8, 0.0],
	&"ui_back": [[_IFACE + "back_002.ogg"], UI, -3.0, 0.8, 0.0],
	&"ui_cycle": [[_IFACE + "tick_004.ogg"], UI, -3.0, 0.85, 0.03],
	&"ui_denied": [[_IFACE + "error_004.ogg"], UI, -6.0, 0.75, 0.0],
	&"ui_start": [[_IFACE + "confirmation_002.ogg"], UI, -6.0, 0.7, 0.0],
	&"bell_toll": [[_IMPACT + "impactBell_heavy_000.ogg"], SFX, -2.0, 0.55, 0.0],

	# Generic combat cues (MatchSounds maps match events to these).
	&"fight_call": [[_RPG + "drawKnife1.ogg"], SFX, 0.0, 0.75, 0.0],
	&"hit_light": [[_IMPACT + "impactPunch_medium_000.ogg", _IMPACT + "impactPunch_medium_001.ogg", _IMPACT + "impactPunch_medium_002.ogg"], SFX, -3.0, 0.9, 0.08],
	&"hit_heavy": [[_IMPACT + "impactPunch_heavy_000.ogg", _IMPACT + "impactPunch_heavy_001.ogg", _IMPACT + "impactPunch_heavy_002.ogg"], SFX, 0.0, 0.75, 0.06],
	&"hit_counter": [[_IMPACT + "impactPlate_heavy_000.ogg", _IMPACT + "impactPlate_heavy_001.ogg"], SFX, 0.0, 0.85, 0.05],
	&"block": [[_IMPACT + "impactMetal_medium_000.ogg", _IMPACT + "impactMetal_medium_001.ogg", _IMPACT + "impactMetal_medium_002.ogg"], SFX, -4.0, 0.8, 0.06],
	&"parry": [[_IMPACT + "impactMetal_light_000.ogg", _IMPACT + "impactMetal_light_001.ogg"], SFX, 0.0, 1.25, 0.04],
	&"guard_break": [[_IMPACT + "impactGlass_heavy_000.ogg"], SFX, -1.0, 0.6, 0.0],
	&"ko": [[_IMPACT + "impactBell_heavy_001.ogg"], SFX, 0.0, 0.42, 0.0],
	&"dodge": [[_RPG + "cloth1.ogg", _RPG + "cloth2.ogg", _RPG + "cloth3.ogg"], SFX, -8.0, 0.9, 0.1],
	&"perfect_dodge": [[_RPG + "knifeSlice.ogg"], SFX, -3.0, 0.6, 0.0],
	&"ability": [[_RPG + "knifeSlice.ogg"], SFX, -5.0, 0.8, 0.08],
	&"super_flash": [[_IMPACT + "impactBell_heavy_002.ogg"], SFX, 0.0, 0.8, 0.0],
	&"soul_burst": [[_IMPACT + "impactSoft_heavy_000.ogg"], SFX, 2.0, 0.55, 0.0],
	&"wall_splat": [[_IMPACT + "impactWood_heavy_000.ogg"], SFX, 0.0, 0.7, 0.05],
}

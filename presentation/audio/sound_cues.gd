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

## id: [files, bus, volume_db, pitch_scale, pitch_jitter (+/- fraction)]
const TABLE: Dictionary[StringName, Array] = {
	&"ui_move": [[_IFACE + "tick_002.ogg"], UI, -4.0, 0.9, 0.04],
	&"ui_confirm": [[_IFACE + "select_004.ogg"], UI, -3.0, 0.8, 0.0],
	&"ui_back": [[_IFACE + "back_002.ogg"], UI, -3.0, 0.8, 0.0],
	&"ui_cycle": [[_IFACE + "tick_004.ogg"], UI, -3.0, 0.85, 0.03],
	&"ui_denied": [[_IFACE + "error_004.ogg"], UI, -6.0, 0.75, 0.0],
	&"ui_start": [[_IFACE + "confirmation_002.ogg"], UI, -6.0, 0.7, 0.0],
	&"bell_toll": [[_IMPACT + "impactBell_heavy_000.ogg"], SFX, -2.0, 0.55, 0.0],
}

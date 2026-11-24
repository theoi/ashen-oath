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
const _SCIFI := "res://assets/kenney-sci-fi-sounds/"
const _SWISH := "res://assets/oga-swishes/"

## id: [files, bus, volume_db, pitch_scale, pitch_jitter (+/- fraction)]
const TABLE: Dictionary[StringName, Array] = {
	&"ui_move": [[_IFACE + "tick_002.ogg"], UI, -4.0, 0.9, 0.04],
	&"ui_confirm": [[_IFACE + "select_004.ogg"], UI, -3.0, 0.8, 0.0],
	&"ui_back": [[_IFACE + "back_002.ogg"], UI, -3.0, 0.8, 0.0],
	&"ui_cycle": [[_IFACE + "tick_004.ogg"], UI, -3.0, 0.85, 0.03],
	&"ui_denied": [[_IFACE + "error_004.ogg"], UI, -6.0, 0.75, 0.0],
	&"ui_start": [[_IFACE + "confirmation_002.ogg"], UI, -6.0, 0.7, 0.0],
	&"bell_toll": [[_IMPACT + "impactBell_heavy_000.ogg"], SFX, -2.0, 0.55, 0.0],
	&"skill_ready": [[_IFACE + "tick_004.ogg"], UI, -10.0, 1.6, 0.0],
	&"awakening_ready": [[_IMPACT + "impactBell_heavy_000.ogg"], SFX, -9.0, 1.3, 0.0],

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
	&"grave_vent": [[_IMPACT + "impactSoft_heavy_000.ogg"], SFX, 1.0, 0.38, 0.05],
	&"wall_splat": [[_IMPACT + "impactWood_heavy_000.ogg"], SFX, 0.0, 0.7, 0.05],

	# Fight presentation (FightFx routes sim events here; HitData/MoveData/EffectData cues
	# name rows).
	&"swing_light": [[_SWISH + "swish-1.ogg", _SWISH + "swish-2.ogg", _SWISH + "swish-3.ogg", _SWISH + "swish-4.ogg"], SFX, -6.0, 1.05, 0.06],
	&"swing_heavy": [[_SWISH + "swish-9.ogg", _SWISH + "swish-10.ogg", _SWISH + "swish-11.ogg"], SFX, -3.0, 0.75, 0.05],
	&"hit_flesh": [[_RPG + "chop.ogg"], SFX, -4.0, 0.7, 0.08],
	&"hit_blade": [[_IMPACT + "impactPlate_medium_000.ogg", _IMPACT + "impactPlate_medium_001.ogg", _IMPACT + "impactPlate_medium_002.ogg"], SFX, -3.0, 0.85, 0.06],
	&"hit_heavy_blade": [[_IMPACT + "impactPlate_heavy_000.ogg", _IMPACT + "impactPlate_heavy_001.ogg", _IMPACT + "impactPlate_heavy_002.ogg"], SFX, -1.0, 0.75, 0.05],
	&"hit_shield": [[_IMPACT + "impactMetal_heavy_000.ogg", _IMPACT + "impactMetal_heavy_001.ogg"], SFX, -1.0, 0.65, 0.04],
	&"hit_fire": [[_SCIFI + "explosionCrunch_000.ogg", _SCIFI + "explosionCrunch_001.ogg", _SCIFI + "explosionCrunch_002.ogg"], SFX, -3.0, 0.8, 0.06],
	&"armor": [[_IMPACT + "impactMetal_light_000.ogg", _IMPACT + "impactMetal_light_001.ogg", _IMPACT + "impactMetal_light_002.ogg"], SFX, -3.0, 0.6, 0.04],
	&"launch": [[_SWISH + "swish-12.ogg", _SWISH + "swish-13.ogg"], SFX, -4.0, 0.6, 0.05],
	&"body_fall": [[_IMPACT + "impactSoft_heavy_000.ogg", _IMPACT + "impactSoft_heavy_001.ogg", _IMPACT + "impactSoft_heavy_002.ogg"], SFX, -2.0, 0.75, 0.06],
	&"jump": [[_RPG + "cloth2.ogg"], SFX, -8.0, 0.9, 0.08],
	&"land": [[_IMPACT + "footstep_concrete_000.ogg", _IMPACT + "footstep_concrete_001.ogg", _IMPACT + "footstep_concrete_002.ogg"], SFX, -6.0, 0.8, 0.08],
	&"grab": [[_RPG + "beltHandle1.ogg", _RPG + "beltHandle2.ogg"], SFX, -2.0, 0.8, 0.05],
	# Aldric
	&"oathfire_lunge": [[_SCIFI + "thrusterFire_000.ogg", _SCIFI + "thrusterFire_001.ogg"], SFX, -2.0, 0.9, 0.05],
	&"brand_rise": [[_SCIFI + "thrusterFire_002.ogg"], SFX, -2.0, 1.2, 0.05],
	&"bulwark_charge": [[_RPG + "metalLatch.ogg"], SFX, -2.0, 0.7, 0.04],
	&"oathfire_ignite": [[_SCIFI + "thrusterFire_003.ogg"], SFX, -1.0, 1.4, 0.0],
	&"pyre_plant": [[_IMPACT + "impactPlate_heavy_000.ogg"], SFX, 0.0, 0.5, 0.0],
	&"pyre_pillar": [[_SCIFI + "lowFrequency_explosion_001.ogg"], SFX, 0.0, 0.8, 0.0],
	&"pyre_wave": [[_SCIFI + "thrusterFire_000.ogg", _SCIFI + "thrusterFire_001.ogg"], SFX, 0.0, 0.6, 0.03],
	# Morrigan
	&"hit_staff": [[_IMPACT + "impactWood_heavy_000.ogg", _IMPACT + "impactPunch_heavy_000.ogg", _IMPACT + "impactPunch_heavy_001.ogg"], SFX, -3.0, 0.9, 0.06],
	&"hit_soul": [[_SCIFI + "forceField_000.ogg", _SCIFI + "forceField_001.ogg", _SCIFI + "forceField_002.ogg"], SFX, -2.0, 0.7, 0.06],
	&"soul_lance_cast": [[_SCIFI + "laserLarge_000.ogg"], SFX, -4.0, 0.55, 0.04],
	&"soul_lance": [[_SCIFI + "laserLarge_001.ogg"], SFX, -4.0, 0.7, 0.05],
	&"soul_shard": [[_SCIFI + "laserLarge_000.ogg", _SCIFI + "laserLarge_001.ogg"], SFX, -8.0, 1.1, 0.08],
	&"grave_grasp_cast": [[_RPG + "cloth3.ogg"], SFX, -3.0, 0.6, 0.05],
	&"grave_grasp": [[_SCIFI + "slime_000.ogg"], SFX, -2.0, 0.5, 0.05],
	&"wraithstep": [[_SCIFI + "forceField_002.ogg"], SFX, -4.0, 1.3, 0.06],
	&"requiem_rise": [[_IMPACT + "impactBell_heavy_001.ogg"], SFX, 0.0, 0.5, 0.0],
	&"requiem_hands": [[_SCIFI + "lowFrequency_explosion_000.ogg"], SFX, 1.0, 0.6, 0.0],
	# Gorrath
	&"chain_throw": [[_RPG + "drawKnife1.ogg", _RPG + "drawKnife2.ogg"], SFX, -2.0, 0.6, 0.05],
	&"hit_chain": [[_IMPACT + "impactMetal_medium_000.ogg", _IMPACT + "impactMetal_medium_001.ogg", _IMPACT + "impactMetal_medium_002.ogg"], SFX, -1.0, 0.7, 0.05],
	&"earthsplitter": [[_IMPACT + "impactMining_000.ogg", _IMPACT + "impactMining_001.ogg"], SFX, 0.0, 0.55, 0.04],
	&"earthsplitter_wave": [[_SCIFI + "lowFrequency_explosion_000.ogg"], SFX, -1.0, 0.9, 0.05],
	&"bull_rush": [[_IMPACT + "footstep_concrete_000.ogg"], SFX, -1.0, 0.5, 0.05],
	&"execution_chain": [[_RPG + "metalLatch.ogg", _RPG + "metalClick.ogg"], SFX, 0.0, 0.5, 0.0],
}

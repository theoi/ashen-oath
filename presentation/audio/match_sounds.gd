class_name MatchSounds
extends RefCounted
## Maps match events (MatchEvents) to sound cues. Presentation only.
##
## Events may carry their own "cue" (e.g. from move data); otherwise the generic cue for the
## event type plays. Ability cues fall back from "<fighter>_ability_<n>" to "ability".

const BY_TYPE: Dictionary[StringName, StringName] = {
	MatchEvents.ROUND_INTRO: &"bell_toll",
	MatchEvents.FIGHT: &"fight_call",
	MatchEvents.KO: &"ko",
	MatchEvents.TIME_UP: &"bell_toll",
	MatchEvents.BLOCK: &"block",
	MatchEvents.PARRY: &"parry",
	MatchEvents.GUARD_BREAK: &"guard_break",
	MatchEvents.PERFECT_DODGE: &"perfect_dodge",
	MatchEvents.DODGE: &"dodge",
	MatchEvents.ABILITY: &"ability",
	MatchEvents.SUPER: &"super_flash",
	MatchEvents.SOUL_BURST: &"soul_burst",
	MatchEvents.WALL_SPLAT: &"wall_splat",
}


## The cue an event should play, or &"" for none.
static func cue_for(event: Dictionary) -> StringName:
	var own: StringName = event.get("cue", &"")
	if not own.is_empty() and Sound.has_cue(own):
		return own
	var type: StringName = event.get("type", &"")
	if type == MatchEvents.HIT:
		if event.get("counter", false):
			return &"hit_counter"
		return &"hit_heavy" if event.get("heavy", false) else &"hit_light"
	return BY_TYPE.get(type, &"")


static func play_for(event: Dictionary) -> void:
	var cue := cue_for(event)
	if not cue.is_empty():
		Sound.play(cue)

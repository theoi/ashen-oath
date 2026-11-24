class_name MatchEvents
extends RefCounted
## Event types a MatchRunner reports to the HUD and the sound cue player.
##
## Events are Dictionaries: {"type": <one of these>, ...fields}. The runner translates the
## sim's event stream into these, so presentation code does not depend on sim internals.

## {round}
const ROUND_INTRO := &"round_intro"
const FIGHT := &"fight"
## {slot}
const KO := &"ko"
const TIME_UP := &"time_up"
## {team}; team -1 is a draw.
const ROUND_WON := &"round_won"
## {team}
const MATCH_WON := &"match_won"

## {attacker, victim, heavy: bool, counter: bool}
const HIT := &"hit"
## {attacker, victim}
const BLOCK := &"block"
## {slot}
const PARRY := &"parry"
## {slot}
const GUARD_BREAK := &"guard_break"
## {slot}
const PERFECT_DODGE := &"perfect_dodge"
## {slot}
const DODGE := &"dodge"
## {slot, ability: 0..5, cue: StringName (optional, from move data)}
const ABILITY := &"ability"
## {slot}
const SUPER := &"super"
## {slot}
const SOUL_BURST := &"soul_burst"
## {slot}
const WALL_SPLAT := &"wall_splat"
## {cue: StringName}
const HAZARD := &"hazard"
## {wave: 1-based, waves: total}
const WAVE := &"wave"
## {slot}: a boss's stagger bar broke.
const STAGGER_BREAK := &"stagger_break"
## {slot, breaker}: a boss's channelled special was broken.
const CHANNEL_BREAK := &"channel_break"

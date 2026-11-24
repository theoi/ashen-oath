# presentation/fight/

A fight on screen. `FightView` puts together the arena scene, one `FighterView` per slot,
`FightCamera` and `FightFx`, around a `MatchRunner`. The match screen
(`ui/match/match_screen.gd`) uses `FightView.show_match(runner, focus_slot, arena_scene)`;
dev scenes can call `start(config, sources)`.

- `fight_camera.gd` (`FightCamera`): third person over the player's shoulder, frames the
  target, orbits with mouse / right stick, turns to the target under hard lock, pulls in and
  rises instead of entering walls or pillars. Hooks: `add_trauma(amount)` (shake) and
  `cinematic(at, look, seconds)` (super shots). `spectator` gives a side-on view.
- `fight_fx.gd` (`FightFx`): sim events -> hit sparks, flashes, rings, screen pulses, camera
  shake and sounds. Sound: the event's `cue` (HitData/MoveData/EffectData) if it names a row
  in `presentation/audio/sound_cues.gd`, else a generic cue for the event type. It also shows
  sim effects (`EffectData.scene`, or `effect_visual.gd`: bolt, rune, ring, flame column).
- `sparring_input_source.gd` (`SparringInputSource`): scripted sparring partner (strings,
  abilities, guards, parries, dodges) used until the CPU AI lands and for clips.
- `fight_sandbox.tscn`: dev scene. `-- --p1=aldric --p2=hollowed --cpu1 --soul=100`,
  `--spectator`, `--side`, `--shot=PATH --frames=N`, `--shot=DIR --every=N`.

Clip of a real exchange:

```sh
tools/capture_clip.sh res://presentation/fight/fight_sandbox.tscn /tmp/fight.mp4 1800 -- --cpu1 --soul=60
```

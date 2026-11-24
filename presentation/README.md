# presentation/

Everything that shows the simulation: character models, animation, VFX, camera, audio and
arena scenes. It reads sim state and the sim event stream and interpolates between ticks.
It never writes sim state.

- `menu_backdrop/`: the 3D scene behind the menus.
- `audio/`: the `Sound` autoload and its cue table (`sound_cues.gd`). Play a cue with
  `Sound.play(&"cue_id")`; add cues by adding rows to the table. Audio buses: Master, Music, SFX, UI
  (`res://default_bus_layout.tres`); the Settings autoload sets their volumes.

`debug/sim_debug.tscn` is the combat core's minimal debug view: capsule fighters, active
hitbox gizmos, effects, hazards and arena collision with a text readout. It plays the test
fighter (keyboard/gamepad on slot 0, `DebugBot` opponents). User args after `--`:
`--arena=<ArenaData path>`, `--fighters=1..4`, `--p2=bot|idle|guard`, `--demo` (bots on every
slot), `--replay=<path>`, `--save-replay=<path>`. It is a development tool, not the game's
fight scene.

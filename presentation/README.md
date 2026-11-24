# presentation/

Everything that shows the simulation: character models, animation, VFX, camera, audio and
arena scenes. It reads sim state and the sim event stream and interpolates between ticks.
It never writes sim state.

- `menu_backdrop/`: the 3D scene behind the menus.
- `audio/`: the `Sound` autoload and its cue table (`sound_cues.gd`). Play a cue with
  `Sound.play(&"cue_id")`; add cues by adding rows to the table. Audio buses: Master, Music, SFX, UI
  (`res://default_bus_layout.tres`); the Settings autoload sets their volumes.

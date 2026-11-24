# presentation/arenas/

Arena scenes: what an arena looks like. Collision, spawns, camera bounds and hazards are
sim data in the arena's `ArenaData` under `content/arenas/`; scenes here only show it.

- `arena_view.gd` (`ArenaView`): base class. Builds the environment, key/rim lights, the
  recolored KayKit props, candle flames (one MultiMesh), light shafts and particles from an
  `ArenaLook`, then calls `_build_layout()`. Match presentation calls `set_sim_tick(tick)`
  every sim tick so hazard visuals follow the sim (hitstop, replays) rather than wall time.
- `arena_look.gd` (`ArenaLook`): the mood of one variant (fog, lights, palette, VFX
  amounts). A variant is the same layout script with another look `.tres` and flags.
- `shaders/grim_prop.gdshader`: the "stylized grim" recolor of the KayKit atlases
  (desaturate, cold tint, world-space grime, glowing flame/lantern atlas cells).
- `arena_preview.tscn`: dev viewer with stand-in fighters and preset cameras.

Web budget (Compatibility renderer): a handful of short-range omni lights without shadows
(each one adds a draw pass per lit object), shadows only from the key light and large
props, CPU particles, about 300 draw calls. `tests/presentation/arenas/` checks the
light and particle counts.

Screenshots under Xvfb (software OpenGL):

```sh
tools/arena_shot.sh /tmp/chapel.png --arena=res://presentation/arenas/ashen_chapel/ashen_chapel.tscn --view=fight
tools/capture_clip.sh res://presentation/arenas/arena_preview.tscn /tmp/chapel.mp4 240 -- --orbit
```

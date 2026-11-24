# presentation/arenas/

Arena scenes: what an arena looks like. Collision, spawns, camera bounds and hazards are
sim data in `content/arenas/<arena>.tres` (`ArenaData`, whose `scene` points here).

| Arena | ArenaData | Scene | Notes |
|---|---|---|---|
| Ashen Chapel | `ashen_chapel.tres` | `ashen_chapel/ashen_chapel.tscn` | No hazards. NW corner cut around the fallen roof. |
| Ashen Chapel (Night) | `ashen_chapel_night.tres` | `ashen_chapel/ashen_chapel_night.tscn` | Story fight 3. Same collision, burning dressing. |
| Drowned Crypt | `drowned_crypt.tres` | `drowned_crypt/drowned_crypt.tscn` | 4 grave vents: diagonal pairs at round ticks 240 and 600, every 720. |
| Drowned Crypt (Depths) | `drowned_crypt_depths.tres` | `drowned_crypt/drowned_crypt_depths.tscn` | Story fight 5. Same collision and vents, deeper water and soul-light. |

All four: floor about 24 × 20 m with chamfered corners, 4 pillars, 4 spawn points (slot 0
at x = -4, slot 1 at x = +4, slot 2 further east as the second 1v2 opponent, slot 3 west
with slot 0) and
`camera_bounds` of 22 × 18 m.

## Using an arena in a match

```gdscript
var data: ArenaData = load("res://content/arenas/drowned_crypt.tres")
config.arena = data
var arena: ArenaView = (load(data.scene) as PackedScene).instantiate()
add_child(arena)
arena.attach(runner)   # or call arena.show_sim(runner.sim) after each step
```

Hazard visuals read `sim.hazard_phase(i)` and `round_tick`, so they hold still in hitstop
and replay exactly. HAZARD_WARN / HAZARD_ACTIVE events (cue `grave_vent`) are for sound
and camera shake.

## Pieces

- `arena_view.gd` (`ArenaView`): base class. Builds the environment, key/rim lights, the
  recolored KayKit props, candle flames (one MultiMesh), light shafts, water and particles
  from an `ArenaLook`, then calls `_build_layout()`.
- `arena_look.gd` (`ArenaLook`): the mood of one variant (fog, lights, palette, VFX
  amounts). A variant is the same layout script with another look `.tres` and flags.
- `shaders/`: `grim_prop` (the "stylized grim" recolor of the KayKit atlases: desaturate,
  cold tint, world-space grime, glowing flame/lantern cells), `water`, `flame`,
  `light_shaft`, `vent_glow`, `spirit_fire`.
- `arena_preview.tscn`: dev viewer. Runs a real `Sim` on an `ArenaData` with idle stand-in
  fighters on the spawns; `--debug` draws walls, pillars, vents, spawns and camera bounds
  (`arena_debug_draw.gd`).

Layout scripts declare `PILLARS` (and `VENTS`); `tests/content/arenas/` checks they match
the ArenaData, so moving a pillar means changing both.

Web budget (Compatibility renderer): at most 16 short-range omni lights without shadows
(each one adds a draw pass per lit object; vent lights are off between eruptions), shadows
only from the key light and large props, CPU particles under 700, about 300 draw calls.
`tests/presentation/arenas/` checks the light and particle counts.

## Screenshots and clips (Xvfb, software OpenGL)

```sh
tools/arena_shot.sh /tmp/crypt.png --arena=res://content/arenas/drowned_crypt.tres --view=fight
tools/arena_shot.sh /tmp/top.png --arena=res://content/arenas/drowned_crypt.tres --view=top --debug --fighters=4
tools/arena_shot.sh /tmp/vents.png --arena=res://content/arenas/drowned_crypt.tres --tick=318 --hold   # vents erupting
tools/capture_clip.sh res://presentation/arenas/arena_preview.tscn /tmp/crypt.mp4 900 -- --arena=res://content/arenas/drowned_crypt.tres --orbit
```

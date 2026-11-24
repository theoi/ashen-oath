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

## Gameplay camera

The fight camera is a fixed-yaw high three-quarter view (`design-lost-ark.md` §3). Each
`ArenaData` has `camera_yaw` (degrees, the direction the camera looks on the floor:
(sin, cos) in (x, z), the `FightCamera` convention). All four slice arenas use 0: the camera
sits on the north (−z) side looking along +z, the long nave runs across the screen and the
Chapel altar is on the left. `attach(runner)` calls `apply_gameplay_camera(data)`, which:

- cuts the walls whose outward normal faces the camera down to ragged ~1.1 m stubs (in
  `grim_prop.gdshader`; back faces draw as a dark cap) and hides props on those walls,
- hides roofs, beams, the crypt vault and upper pillar drums (`overhead()`); hidden pieces
  keep casting shadows so the lighting does not change,
- turns the rim light so it backlights fighters as seen from the camera, with the
  fighter-only fill from the camera side,
- dithers props within ~1.5 m (on screen) of each fighter down to 25 % when they are
  between the camera and the fighter.

Story stills don't call it and keep the full set. `ArenaCutaway` (the generic cutaway in
`presentation/fight/`) skips `ArenaView` scenes, which cut themselves. To preview:
`tools/arena_shot.sh /tmp/a.png --arena=res://content/arenas/drowned_crypt.tres --game`
(capsules) or `--real=aldric,gorrath` (real fighters sparring through `FightView`).

## Grim look and readability

`ArenaLook` drives the mood. Surface decay (`breakup`, `damp_*`, `soot_*`, `streak_amount`,
`stain_*`) dirties every prop; blood-dark stains and banners are kept sparse. Readability
comes from the fight light pool, not from brighter walls: props darken away from
`pool_center` (`pool_darken`), a soft `PoolLight` spot lights the middle of the floor, and
two lights on render layer 1 only (fighters; arena geometry is on layer 2) keep fighters
separated from the dark: the rim light from behind and `FighterFill` from the camera side.
Grave vents keep a faint border while dormant and a bright border plus fill while warning.
Murky water: `water_opacity`, `water_murk` (drifting scum and silt).

Floors, walls and pillars should still read at a glance from the gameplay camera: keep
`grime_amount` and `breakup` moderate and `grime_color` off pure black, and lift the floor
with `prop_brightness` rather than `ambient_energy` (ambient barely shows on the grim
material).

The player Brightness setting (`Settings.brightness`) multiplies each arena's tonemap
exposure, so `look.exposure` is the base at brightness 1. Tune the looks at 1; preview
other values with `arena_preview --brightness=1.4`.

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
(each one adds a draw pass per lit object; vent lights are off between eruptions), one
unshadowed pool spot and two fighter-only directionals, shadows only from the key light and
large props, CPU particles under 700, about 300 draw calls.
`tests/presentation/arenas/` checks the light and particle counts.

## Screenshots and clips (Xvfb, software OpenGL)

```sh
tools/arena_shot.sh /tmp/crypt.png --arena=res://content/arenas/drowned_crypt.tres --view=fight
tools/arena_shot.sh /tmp/top.png --arena=res://content/arenas/drowned_crypt.tres --view=top --debug --fighters=4
tools/arena_shot.sh /tmp/vents.png --arena=res://content/arenas/drowned_crypt.tres --tick=318 --hold   # vents erupting
tools/capture_clip.sh res://presentation/arenas/arena_preview.tscn /tmp/crypt.mp4 900 -- --arena=res://content/arenas/drowned_crypt.tres --orbit
```

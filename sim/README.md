# sim/

The deterministic combat simulation. See "Architecture rules" in the top-level README.

- Pure GDScript on plain data (`RefCounted`/`Resource`, arrays, dictionaries). No `Node`,
  scene tree, engine physics, rendering, camera or audio.
- Steps at a fixed 60 Hz from per-tick input frames: `state(t+1) = step(state(t), inputs(t))`.
- Never reads wall-clock time, `delta`, the camera, or unseeded/global RNG. Randomness comes
  from an RNG whose state lives in the sim state.
- State can be snapshotted, restored and checksummed.
- Emits events (hit, block, parry, KO, hazard...) for presentation to consume.

| File | What |
|---|---|
| `sim.gd` | `Sim`: create from a `SimConfig`, `step(inputs)`, snapshot/restore/checksum, queries |
| `fx.gd` | `Fx`: fixed-point units (1 m = 10000), angles (4096 per turn), integer trig |
| `sim_input.gd` | `SimInput`: the per-tick input frame (buttons + world-space stick) |
| `sim_state.gd`, `fighter_state.gd`, `effect_state.gd`, `buff_state.gd` | State records (integers only) |
| `sim_record.gd` | `SimRecord`: generic copy and checksum of state records |
| `sim_event.gd` | `SimEvent`: the sim → presentation event stream |
| `arena_collision.gd` | `ArenaCollision`: floor polygon walls, capsule obstacles, hazards |
| `fighter_trait.gd` | `FighterTrait`: per-fighter script hook for unusual traits |
| `replay.gd` | `Replay`: config + input log (+ checksums) |
| `input/` | `InputSource` and the replay/scripted sources (device capture lives in `presentation/input/`) |

State fields are integers so fights are bit-identical across platforms; content is
authored in floats and converted with `Fx` on read. The full API is described in the
workstream's sim API note and in the doc comments here.

Tests go in `tests/sim/` (`sim_fixtures.gd` has builders and input helpers).

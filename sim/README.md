# sim/

The deterministic combat simulation. See "Architecture rules" in the top-level README.

- Pure GDScript on plain data (`RefCounted`/`Resource`, arrays, dictionaries). No `Node`,
  scene tree, engine physics, rendering, camera or audio.
- Steps at a fixed 60 Hz from per-tick input frames: `state(t+1) = step(state(t), inputs(t))`.
- Never reads wall-clock time, `delta`, the camera, or unseeded/global RNG. Randomness comes
  from an RNG whose state lives in the sim state.
- State can be snapshotted, restored and checksummed.
- Emits events (hit, block, parry, KO, hazard...) for presentation to consume.

Tests go in `tests/sim/`.

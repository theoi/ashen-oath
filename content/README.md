# content/

Game data as Godot `Resource`s (`.tres`): moves, fighters, arenas, story. The simulation and
presentation read these; changing numbers here should not need code changes.

- `types/`: the Resource scripts. Combat: `CombatRules`, `FighterData`, `MoveData`,
  `HitboxData`, `HitData`, `MotionData`, `TeleportData`, `EffectData`, `CancelData`,
  `BuffData`. Arenas: `ArenaData`, `ArenaObstacle`, `HazardData`. Matches: `SimConfig`,
  `SlotConfig`.
- `rules/default_rules.tres`: universal combat numbers (design §2).
- `arenas/`: arena collision data. `ashen_chapel`, `ashen_chapel_night`, `drowned_crypt` and
  `drowned_crypt_depths` are the slice arenas (see `presentation/arenas/README.md`);
  `training_arena.tres` is a plain 24 × 20 m test arena.

Units: frames are 60 Hz ticks, distances meters, speeds m/s, angles degrees. Move frames
count from 1; `startup` is the first active frame. Fighter-local offsets use Godot
node-local axes of a model facing +Z (+Z forward, +Y up).

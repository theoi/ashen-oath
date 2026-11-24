# Ashen Oath

A dark fantasy realtime 3D arena brawler, built in Godot 4.

Cursed knights and grave-witches fight in the ruins of the dead kingdom of Vael. Free 3D
movement, a third-person camera, heavy hits, earned dodges, and fighters that each play
like their own game. The first milestone is the **Act 1 slice**: story mode ("The Bell
Wakes") plus versus against the computer, with Aldric, Morrigan and Gorrath in the
Ashen Chapel and the Drowned Crypt.

**Play in the browser:** https://theoi.github.io/ashen-oath/ (built from `main`).

Status: early development. The game boots to the title screen and menus; fights are on the way.

## Requirements

- [Godot 4.7.2 stable](https://godotengine.org/download/archive/4.7.2-stable/) (standard build, not .NET).
- For web exports: the 4.7.2 export templates (Editor → Manage Export Templates, or extract
  `templates/web_nothreads_*.zip` and `templates/version.txt` from the official `.tpz` into
  `~/.local/share/godot/export_templates/4.7.2.stable/`).
- Optional, for the browser smoke test: Node 18+ and Google Chrome.

The `tools/*.sh` scripts find Godot through `$GODOT`, then `godot` on `PATH`, then
`~/tools/godot/Godot_v4.7.2-stable_linux.x86_64`.

## Run, test and export

```sh
# Play: open the project in the Godot editor and press F5, or
godot --path .

# Headless tests (imports the project first; exit code 0 = all passed)
tools/run_tests.sh
tools/run_tests.sh --filter=sim/        # only tests whose "file::method" id contains "sim/"

# Web export (single-threaded, Compatibility renderer) into build/web
tools/export_web.sh
python3 -m http.server -d build/web 8060   # then open http://localhost:8060

# Browser smoke test: loads a build (directory or URL) in headless Chrome and screenshots it
(cd tools/web_smoke && npm install)
node tools/web_smoke/smoke.mjs build/web /tmp/shot.png
node tools/web_smoke/smoke.mjs https://theoi.github.io/ashen-oath/ /tmp/pages.png

# Record a scene to mp4 with Movie Maker (needs xvfb-run and ffmpeg)
tools/capture_clip.sh res://ui/app/menu_app.tscn /tmp/clip.mp4 180

# Play story mode Act 1 end to end through the real game (args: tests/story/story_autoplay.gd)
tools/story_playthrough.sh --fast=8 --skip-scenes

# Screenshot after N frames; --menu= opens a menu screen stack directly (ids in ui/app/game_flow.gd)
tools/capture_screenshot.sh /tmp/settings.png 30 -- --menu=mode_select,settings
```

After a fresh clone, or after adding assets or `class_name` scripts outside the editor, run
an import (`tools/run_tests.sh` and `tools/export_web.sh` do this for you):
`godot --headless --path . --import`.

### Writing tests

Tests live under `tests/` in files named `test_*.gd`. Each file extends `TestCase`
(`tests/framework/test_case.gd`), and every method named `test_*` runs on a fresh instance.
Mirror the source layout, e.g. `tests/sim/test_hitstop.gd`.

```gdscript
extends TestCase

func test_light_string_hits_on_frame_6() -> void:
	assert_eq(2 + 2, 4)
	assert_almost_eq(0.1 + 0.2, 0.3, 0.000001)
	var node := add_child_autofree(Node3D.new())   # freed after the test
	await wait_physics_frames(2)                     # tests may await
```

Available: `assert_true/false`, `assert_eq/ne`, `assert_almost_eq`, `assert_null/not_null`,
`assert_has`, `fail`, `before_each/after_each`, `add_child_autofree`, `wait_frames`,
`wait_physics_frames`, and `host` (the runner node). Any engine or script error logged
during a test (including `push_error` and runtime errors) fails that test. A built-in test
loads every `.gd`, `.tscn` and `.tres` in the project, so parse errors and broken references
fail CI even without a dedicated test.

## Repository layout

| Path | What goes there |
|---|---|
| `sim/` | The deterministic combat simulation: `state(t+1) = step(state(t), inputs(t))` at 60 Hz. Plain data and pure logic, no scene tree, nodes, engine physics or rendering, so it runs and tests headless. |
| `content/` | Data-driven content as Godot `Resource`s: moves, fighters, arenas, story. Adding a fighter or arena should be mostly data plus art. |
| `presentation/` | Everything that *reads* simulation state and events: models, animation, VFX, camera, audio, arena scenes. Never writes simulation state. |
| `ui/` | Menus, HUD, settings, controls screen, input bindings, theme, story scene player. See [ui/README.md](ui/README.md). |
| `assets/` | Third-party CC0 assets, one folder per pack with its license file. Credit each in `CREDITS.md`. |
| `tests/` | Headless tests (`test_*.gd`) and the runner (`runner.tscn`, `framework/`). Not exported. |
| `tools/` | Scripts for headless runs, exports, smoke tests and clip capture. Ignored by Godot (`.gdignore`) and not exported. |
| `.github/` | CI workflow and the cached Godot setup action. |

## Architecture rules

- **The simulation is separate from presentation.** `sim/` steps at a fixed 60 Hz from
  per-tick input frames only. Presentation reads state and the event stream and
  interpolates between ticks; frame rate never changes outcomes.
- **Determinism.** The same inputs and seed must produce the same fight. The sim **never**
  reads the camera, wall-clock time (`Time`, `OS`, `delta`), or unseeded/global RNG
  (`randi()`, `randf()`, `randomize()`). Randomness comes from an RNG whose state lives in
  the sim state. Iterate in a stable order (no reliance on dictionary order from hashing
  objects, no physics callbacks).
- **Inputs are world-space.** Camera-relative movement is converted to world space when
  input is captured, before it reaches the sim.
- **No engine physics in combat.** Hit/hurtboxes are shapes in move data, not bones.
- **Snapshot-able state.** Sim state is plain data that can be copied, restored and
  checksummed (replays, rollback later).

## Contributing

**Flow:** branch from `main` (`feature/<topic>`, `fix/<topic>`), commit, push, open a pull
request into `main`. CI must be green before merging. Keep PRs focused on one piece of work.
`main` deploys to GitHub Pages automatically, so it must always build and run.

**GDScript style:**
- Follow the [official GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html):
  tabs, `snake_case` files, functions and variables, `PascalCase` classes and nodes,
  `CONSTANT_CASE` constants, `_leading_underscore` for private members.
- **Typed GDScript everywhere.** Every variable, parameter and return value has a static
  type (`:=` inference counts). The project treats untyped declarations as errors
  (`debug/gdscript/warnings/untyped_declaration`), so an untyped script fails to load and
  fails CI.
- `class_name` only for types other code refers to. Prefer `Resource` subclasses for data.
- Doc comments (`##`) on public classes and non-obvious functions; comments explain why.

**Content and assets:** only CC0 (or equally permissive) third-party assets. Put each pack
in `assets/<pack-name>/` with its license file and add it to `CREDITS.md` in the same PR.
Nothing secret goes into this public repository.

**Commits:** short imperative subject line ("Add hitstop to light attacks"), with a body
when the reason isn't obvious.

## CI and deployment

`.github/workflows/ci.yml` runs on every pull request and every push to `main`:

1. **Headless tests:** installs Godot 4.7.2 (cached, checksum-verified), imports the project
   and runs `tools/run_tests.sh`.
2. **Web export:** installs the single-threaded web templates (cached) and runs
   `tools/export_web.sh`, so export breakage shows up on the PR.
3. **Deploy (main only):** publishes `build/web` to GitHub Pages.

The web build uses the Compatibility renderer without threads, so it needs no
cross-origin isolation headers and runs on plain GitHub Pages.

## Credits

See [CREDITS.md](CREDITS.md).

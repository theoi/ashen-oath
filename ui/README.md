# ui/

Menus, HUD, settings, the controls screen and the story scene player.

## Input

`input/default_bindings.gd` (`DefaultBindings`) holds the default bindings from design §7 for
gamepad, keyboard + mouse and keyboard only, and the action names as constants. All three
schemes are active at once. The table is written into `project.godot` by:

```sh
godot --headless --path . -s "$PWD/tools/gen_input_map.gd"
```

`tests/ui/test_input_map.gd` fails if `project.godot` and the table drift apart.

Gameplay actions: `move_left/right/forward/back`, `camera_left/right/up/down`, `attack_light`,
`attack_heavy`, `jump`, `dodge`, `guard`, `grab`, `ability_1/2/3`, `ability_modifier`,
`super`, `lock_on`, `pause`. Menus use Godot's `ui_*` actions, extended with gamepad A
(accept), B (back) and the shoulder buttons (next/previous tab).

Things input capture handles itself, because they are not plain actions:
- **Mouse camera:** `InputEventMouseMotion` while the mouse is captured.
- **Gamepad abilities** are chords: LT + X / Y / B. Use `DefaultBindings.held_ability_chord()`
  and skip light / heavy / dodge when `DefaultBindings.is_chord_consumed(action)` is true.
- **Right-stick flick** to switch target: watch the `camera_*` axis strength.

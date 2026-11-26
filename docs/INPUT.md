# Controls and input

Gameplay code never reads keys. It reads **actions** (`move_up`, `end_turn`, …) from Godot's
InputMap, which `InputBindings` (`game/scripts/input/input_bindings.gd`) fills at startup.
So keyboard, controller and remapped controls all work the same way.

## Actions and default bindings

Defaults live in `game/data/input/bindings.json`.

| Action | Keyboard | Controller |
|---|---|---|
| `move_up` / `move_down` / `move_left` / `move_right` | W A S D, arrow keys | D-pad, left stick |
| `end_turn` | Space | A |
| `switch_hero` | Tab | X |
| `talk` (open the text box to the GM) | Enter | Y |
| `cancel` (leave the text box) | Escape | B |
| `restart` (new delve after a loss) | R | Start |

Letters are bound by **physical position**, so WASD stays where it is on AZERTY or Dvorak keyboards.

## Remapping

Add an `[input]` section to `settings.cfg` (macOS: `~/Library/Application Support/Godot/app_userdata/Emberdeep/`,
Linux: `~/.local/share/godot/app_userdata/Emberdeep/`). Each line replaces all bindings of one action:

```ini
[input]
end_turn="key:Enter, joy_button:start"
move_up="key:I, key:Up, joy_button:dpad_up, joy_axis:left_y-"
```

| Format | Examples |
|---|---|
| `key:<name>` | `key:W`, `key:Space`, `key:Enter`, `key:Kp Enter`, `key:F5` (Godot key names) |
| `joy_button:<name or number>` | `a b x y back start left_shoulder right_shoulder left_stick right_stick dpad_up dpad_down dpad_left dpad_right`, or `0`–`20` |
| `joy_axis:<axis><+ or ->` | `left_x+`, `left_y-`, `right_x-` |

A binding that can't be read is skipped with a warning; the action's other bindings still work.

## Movement feel

- A move happens **on the key press itself**, not on the next frame.
- Holding a direction repeats on the game's clock, not the operating system's key repeat, so it
  feels the same everywhere and works on controllers. A frame hitch never fires a burst of moves.
- Tune it in `settings.cfg`:

```ini
[controls]
move_repeat_delay=0.22      ; seconds before a held move repeats
move_repeat_interval=0.11   ; seconds between repeats
```

## Text and HUD size

```ini
[ui]
scale=1.25    ; 0.75 to 2.0: text size and HUD width (e.g. 1.25 on a Steam Deck)
```

## Adding an action

1. Add it to `data/input/bindings.json` with a label and default bindings (keyboard and controller).
2. Handle it in `main.gd` with `event.is_action_pressed("<action>")`, never with a keycode.
3. Add it to the list in `_test_input_bindings()`.

# Scroll bug — "I am not able to scroll while selecting the map" (v3.1, real phone)

Status: Phase 1 — root cause PROVEN by experiment (see §3). NOT fixed yet;
this file is the fix plan for the implementation worker.

## 1. The report

User on a real phone, v3.1 lobby (host): the map-selection list does not
scroll — maps below the fold (Neon City, Ancient Temple, Airship Fleet
and the lower rows) cannot be reached. 13 maps exist
(`GameData.MAP_NAMES`, `game_data.gd:53`); only the first ~2 rows are
visible in the lobby's scroll area.

## 2. Root cause (proven)

**When a touch drag starts on an enabled map `Button`, the `Button`
captures the touch and the `ScrollContainer` never sees the drag, so it
never scrolls.**

Mechanics (Godot 4.7.2, verified by the probe in §3):
- The lobby DOES have a working `ScrollContainer` around the map grid
  (`main.gd._build_lobby`, ~line 951: `ScrollContainer.new()`,
  `SIZE_EXPAND_FILL`, horizontal scroll disabled; inner `VBoxContainer`
  holds the player list, the 2-column map `GridContainer` (13 buttons,
  72 px rows), map vote, mode, kill-limit and match-time rows).
- The container itself scrolls fine: programmatic `scroll_vertical = 150`
  works, and a touch drag starting on a non-button control scrolls fully.
- But a `Button` (`BaseButton`) handles the `InputEventScreenTouch`
  press in its own `_gui_input` and accepts the event. The viewport then
  makes that button the mouse-focus control for the touch, and every
  following `InputEventScreenDrag` for that touch is delivered to the
  button — which ignores drags — instead of propagating up to the
  `ScrollContainer`. The `ScrollContainer`'s drag handling never runs.
- The map grid fills the full width of the scroll area (2 columns ×
  ~592 px buttons, 8 px gaps), so **virtually every drag start lands on
  a button**. The only places a drag can start are the 8 px gaps and the
  section labels — effectively unscrollable. That is exactly what the
  user reported.
- It bites the host specifically: for a non-host client the map buttons
  are `disabled` (`_refresh_lobby_buttons`, `mb.disabled = not _is_host`),
  disabled buttons don't accept the press, and drag-scroll works. The
  reporter is the host picking the map — buttons enabled, scroll dead.

Why the v2.3/v3.x headless checks missed it: the flow checks verified
"reachable by scrolling" with **programmatic scrolling / mouse wheel**,
never with a touch drag starting on a button. The project's headless
harness drives `_unhandled_input` directly and never exercises the
viewport's GUI drag path. There was never a touch-drag test on the lobby.

### What it is NOT
- The `ScrollContainer` is NOT missing or misconfigured — it exists, has
  the right size (1200×344 at 1280×720), `max = 1228`, `page = 344`.
- It is NOT a phone aspect-ratio overflow: at 1280×720 (and on phones,
  stretch `canvas_items`/`expand` keeps the logical height at 720) the
  layout is correct — lobby panel (1248, 696), labels full-width,
  `ScrollContainer` 344 px tall with 1228 px of overflow to scroll.
- No `_input`/`_unhandled_input` handler in `main.gd` eats the drag
  (`main.gd` has no input handling at all; the `_unhandled_input` in
  `game.gd` belongs to the game scene, not the menu).
- The same latent issue affects the OTHER two `ScrollContainer`s in
  `main.gd` (customization ~line 624, multiplayer ~line 888) — both hold
  buttons that fill the scroll area. Fix all three the same way.

## 3. Proof (empirical, Godot 4.7.2, real 1280×720 window under Xvfb)

Probe: throwaway copy of the v3.1 project with a probe appended to
`main.gd` (throwaway only — the real project is untouched), run as the
real main scene with `-- --probe-lobby`, synthetic events fed through
`Input.parse_input_event` (the real viewport GUI path), results read a
half-second later (events only dispatch on the next input flush — reading
them synchronously always shows 0; that was a probe bug in the first
attempt, fixed by making the probe two-phase).

Results (lobby, host, all map buttons enabled):
| Test | Gesture | `scroll_vertical` after |
|---|---|---|
| C (sanity) | programmatic `scroll_vertical = 150` | **150** — container can scroll |
| G (sanity) | tap map button [1] | `map_id` 0 → **1** — harness delivers GUI presses |
| **A** | **touch drag starting ON visible map button [0], −200 px** | **0 — BUG** |
| B | touch drag starting on the "Map:" section label, −200 px | **200 — works** |
| D | mouse drag starting on the label | 0 (mouse drag is not the phone path; ignore) |
| E+F | mouse drag on button + mouse wheel | 43 combined (mouse path is partial; phone path is touch) |

A vs B with identical drag parameters is the proof: the ONLY difference
is which control the drag starts on. Touch-drag scroll works; touch-drag
starting on a button does not.

The probe code is not in the real project. To re-run it: copy the project
to a throwaway dir, append the probe from the Phase-1 notes (probe
functions `_probe_lobby_layout` / `_probe_drag` / `_probe_mouse_drag` /
`_probe_read_results*`, hooked in `_ready` behind `--probe-lobby`), run
under `xvfb-run` at 1280×720, and check that test A reads 200 after the
fix (and that test G still selects the map).

### Harness artifact to NOT chase
Instantiating `main.tscn` manually from a `SceneTree -s` script
(`_initialize`, before the window exists) produces a DIFFERENT,
bogus layout: lobby panel (1248, **6427**), `ScrollContainer` height 0,
labels 1 px wide / ~2000 px tall. That is the v2.2 autowrap-at-width-0
min-size explosion (`_build_lobby`'s autowrap labels wrapping at zero
width while the viewport is still 64×64, inflating the panel, which
never shrinks back). It does NOT reproduce in the genuine startup path
(main scene auto-loaded, viewport 1280×720 from frame 0 — panel is
(1248, 696) and everything lays out correctly). On Android the window
exists before the scene loads, so the genuine path applies. If you see a
giant panel in a test harness, it is the harness, not the game — but
note the underlying fragility: the lobby's autowrap labels can inflate
the panel if they are ever measured at ~zero width. The fix in §4 keeps
the labels at full width from the first frame (see "also fix").

## 4. Fix plan (implementation worker — do NOT ship without the test in §5)

### Primary fix — forward button drags to the ScrollContainer (minimal, keeps `Button`s)
For every button that lives inside a scrolled area (map grid, vote,
mode, limit, time buttons in the lobby; colour/helmet buttons in
customization; room buttons in multiplayer), connect its `gui_input`
signal to a forwarder that hands drags to the enclosing `ScrollContainer`:

```gdscript
# in _build_lobby (and the same for _build_customize / _build_multiplayer):
scroll_container_ref = scroll  # keep a reference
map_button.gui_input.connect(_on_scrolled_button_gui_input.bind(scroll))
# ...
func _on_scrolled_button_gui_input(event: InputEvent, scroll: ScrollContainer) -> void:
    if event is InputEventScreenDrag:
        scroll.scroll_vertical -= event.relative.y
    elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
        scroll.scroll_vertical -= event.relative.y
```

Why this works: the drag IS delivered to the button (it is mouse-focus);
`gui_input` receives it, and the forwarder scrolls the container by the
same delta the container would have used. A tap (press + release with no
drag) still goes through the button's normal `pressed` path untouched.
A drag that ends over a different button must NOT select anything:
`BaseButton` only emits `pressed` when the release lands inside the same
button, so a 200 px drag-release cannot fire a selection — but verify
this explicitly in the test (§5, case 4).

Details to get right:
- Apply the forwarder to ALL buttons inside the three scrolled panels,
  not just the map grid (vote/mode/limit/time rows are inside the same
  `ScrollContainer`; the customize and multiplayer panels have the same
  pattern).
- Do NOT set the buttons' `mouse_filter` to `IGNORE`/`PASS` as part of
  this fix — that changes press behaviour and is not needed.
- Keep the grid geometry (2 cols, 72 px rows, 8 px gaps). Do not "fix"
  scrolling by shrinking rows so everything fits — the vote/mode/limit/
  time rows below the map grid still overflow 344 px and still need the
  scroll.
- The `ScrollContainer` needs a visible scrollbar (theme provides it) and
  a "Scroll for more maps ↓" hint under the grid while content overflows
  (see `THEME_SPEC.md` §8). The hint is a label OUTSIDE the scroll area
  or the first row inside it — a label is a valid drag start (test B
  proves it), so the hint doubles as a drag handle.

### Fallback fix (only if the forwarder proves flaky in testing)
Set the scrolled buttons' `mouse_filter = MOUSE_FILTER_IGNORE` and
implement tap detection manually on the row/panel (`gui_input` on the
parent: press + release within ~10 px and ~0.3 s = tap → select the map
whose row contains the point). This guarantees drag-scroll (nothing
captures the press) but loses `Button`'s built-in visuals/hover/pressed
states, which must then be re-implemented per row. More code, more risk —
use only if the primary fix fails its test.

### Also fix (same change, cheap, prevents the §3 artifact from ever biting)
Give the lobby's four autowrap labels (`_host_ip_label`,
`_room_info_label`, `controls_hint`, `join_hint`) an explicit
`size_flags_horizontal = SIZE_EXPAND_FILL` AND a sane
`custom_minimum_size.y` (single-line height), so their minimum size can
never explode to thousands of pixels even if measured at zero width.
(Their `autowrap_mode` stays; with a real width they wrap to 1–2 lines.)

### Files / nodes involved
- `main.gd`: `_build_lobby()` (~lines 912–1080: `scroll`,
  `map_grid`, `_map_buttons`, `_vote_buttons`, `_mode_buttons`,
  `_limit_buttons`, `_time_buttons`); `_build_customize()` (~line 624
  `scroll`); `_build_multiplayer()` (~line 888 `scroll`,
  `_host_buttons`); `_refresh_lobby_buttons()` (disabled-state logic —
  unchanged); the four autowrap labels in `_build_lobby()`.
- `main.tscn`: no change (the whole lobby is built in code).
- No change to `game.gd`, `joystick.gd`, physics, networking or maps.

## 5. Test plan (must pass before delivery)

Re-run the §3 probe (throwaway copy, real 1280×720 window, host lobby)
and require:
1. Test A (touch drag starting on a map button, −200 px):
   `scroll_vertical` goes 0 → ~200. **This is the regression test.**
2. Test B (touch drag on a label) still scrolls (~200) — no regression.
3. Test C (programmatic scroll) still works.
4. Test G (tap a map button) still selects that map (`map_id` changes,
   `✓` moves) — taps are not broken by the fix.
5. Drag 200 px starting on map [0] and release over map [5]: NO map is
   selected by the release (selection changes only on a clean tap).
6. Repeat 1–5 on a tall phone resolution (e.g. 2400×1080 landscape,
   logical 1600×720) and on a short one (1280×720) — scrolling must work
   at both; all 13 maps reachable (scroll to max, last row visible and
   tappable).
7. Same drag test on the customize and multiplayer scrolled lists.
8. Full flow suite green afterwards (menu → create room → lobby → scroll
   → select each map → start match → play → pause → scoreboard → back),
   0 script errors.

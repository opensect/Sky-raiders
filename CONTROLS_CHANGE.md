# Controls change (v3.2) — REMOVE the FIRE button, fire from the right stick

Status: Phase 1 — design + implementation notes only. NO game code changed
yet. The implementation worker applies this in Phase 2.

User instruction (2026-11-19): remove the dedicated FIRE button entirely
and move firing to the right joystick, exactly like Mini Militia. This
SUPERSEDES the v2.4 dedicated-FIRE-button design.

## 1. The new scheme

- **Left stick:** move. Push up = jump / fly (jetpack). Unchanged.
- **Right stick:** aim AND fire. Pushing it in a direction aims the weapon
  that way and fires while held. Releasing it (stick back to centre)
  stops firing immediately.
- **Kept as-is:** RELOAD button, ammo display, GRENADE button, WEAPON
  (switch) button, PAUSE and SCORE buttons. Only the FIRE button goes.
- **New hint text** (lobby `controls_hint` in `main.gd`, and the in-game
  hint label in `game.gd` ~line 1657):
  `Left stick: move • Push up: jump / fly • Right stick: aim and shoot`
  (replaces `… Right stick: aim • FIRE button: hold to shoot`).

## 2. Firing rule (exact, for the implementation worker)

- **CORRECTION to the brief:** the brief said "fire only while the right
  stick is deflected beyond its dead zone (keep the existing ~0.35
  threshold)". The actual dead zone in the code is **0.20, not 0.35**
  (`joystick.gd:24`: `@export var dead_zone: float = 0.20`, "GAP-09: THE
  single dead zone"). The `0.35` figures in `game.gd` (lines 4762, 4920,
  4977, 5040) are the semi-auto **press-to-press spacing** (0.10 s hold +
  0.25 s gap), not a stick threshold. **Use 0.20.**
- The aim stick already provides exactly the signal needed
  (`joystick.gd`): `get_vector()` returns `Vector2.ZERO` unless a finger
  is actively holding the stick (`_touch_id != -1`), and returns zero
  below the dead zone (magnitude rescaled above it). So:
  `touch_firing = aim_stick.get_vector() != Vector2.ZERO`
  (replacing `game.gd:2434`: `touch_firing = fire_button != null and
  fire_button.is_held()`). The aim direction is the same vector.
- **Auto weapons:** fire continuously at their weapon-table rate while
  the vector is non-zero (existing rate/ammo/validation path unchanged).
- **Semi-auto weapons (pistol, sniper):** fire **once per fresh
  deflection** — on the ZERO → non-zero transition of the aim vector.
  A quick flick must fire exactly 1 shot even if the finger is already
  gone by the time the shooting step runs (**QA-027 tap-loss fix must
  carry over**): implement a pending-shot flag set on the transition and
  consumed by the shooting step, so a flick is never silently lost.
  Holding a semi-auto weapon deflected must NOT auto-repeat.
- **Stale-aim rule (QA-016, already in `joystick.gd` — keep it):** the
  aim vector is zero unless a finger is actively holding the stick; the
  stick resets itself on window focus loss and app pause
  (`_notification`, `NOTIFICATION_WM_WINDOW_FOCUS_OUT` /
  `NOTIFICATION_APPLICATION_PAUSED`). The firing path must ALSO reset on
  death, pause, and match end (see §4) — the stick must never fire from
  a stale position.
- **Zero-shot rule:** moving the left stick, or tapping
  GRENADE / WEAPON / RELOAD / PAUSE / SCORE, must fire **0 shots**.
  These are separate touch IDs routed in `game.gd._unhandled_input`
  (~lines 2291–2350); the firing decision must read ONLY the aim stick's
  vector, never any other control's state.
- **Geometry / touch behaviour of the sticks must stay as tested**
  (QA-029 camera-transform fix in `joystick.gd._update_from_point`).
  Do not move, resize or re-route the sticks except for §3's layout
  change (aim stick back to bottom-right).

## 3. What to delete / change (implementation worker)

### Delete
- The FIRE button from the HUD: creation + layout in `game.gd`
  (~lines 2099–2106: `fire_button = FIRE_BUTTON_SCRIPT.new()`, anchors,
  position, size, `hud.add_child(fire_button)`), and the left-handed
  layout branch that swaps it with the aim stick (`game.gd:2074`,
  `var lefty := GameData.fire_button_left`, and the `lefty` layout at
  ~2071–2084).
- `game.gd:24` `FIRE_BUTTON_SCRIPT` preload; `game.gd:524`
  `var fire_button`; `game.gd:548` `_fire_touch_id`; `game.gd:610`
  `_smoke_fire_idx` (or repurpose — see §5); the FIRE routing in
  `_unhandled_input` (`:2298–2299` press, `:2332–2336` drag,
  `:2346–2349` release) and its reset entries (`:2241`, `:2263`,
  `:2268–2269`, `:2285` lists).
- `res://fire_button.gd` (+ its `.uid`) — it only served the button.
  Delete the file once nothing references it.
- The "FIRE button side" setting: `GameData.fire_button_left`
  (`game_data.gd:24, 82, 101`) and its settings UI row in `main.gd`
  (~lines 763, 772–773). The settings save file tolerates the missing
  key (loads use defaults), so removing the field is safe. With no FIRE
  button there is nothing left/right to choose.
- The v2.4 comment at `game.gd:539` ("firing comes ONLY from the FIRE
  button") — replace with the new rule (§2).

### Change
- **Aim stick position:** back to bottom-right (it was moved left in
  v2.4 to make room for the FIRE button — `game.gd` ~line 2082 comment).
  Move stick stays bottom-left. This also removes the need for the
  `fire_button_left` layout swap.
- **Hint texts:** lobby (`main.gd` `controls_hint`) and in-game
  (`game.gd:1655–1657`) → the §1 text.
- **HUD layout (no FIRE button):** aim stick bottom-right; RELOAD,
  GRENADE, WEAPON buttons keep their places; ammo display stays next to
  RELOAD. The freed bottom-right corner is the aim stick's — do not put
  another button there.

### Keep (only the INPUT source changes)
- Data-driven weapon table (`weapons.gd`), bullet pool, muzzle flash /
  trails / recoil / screen shake, host-validated shooting sync
  (`shooting_sync`, host-side fire-rate/ammo validation), hit regions,
  kill-credit lock (QA-031), physics, networking, maps, audio.
- `joystick.gd` untouched except the visual cue below (no behaviour
  change): draw a **cyan ring + small crosshair mark in the aim stick's
  base while idle**, brightening while firing, so the player can see the
  right stick is also the fire control. Geometry, radii, dead zone,
  touch routing and the QA-029 transform stay exactly as tested.
  (Visual-only change to `_draw()`; the cue must never affect input.)

## 4. Safety invariants (must hold after the change)

1. `aim_stick.get_vector() == Vector2.ZERO` whenever no finger holds
   the aim stick (already guaranteed by `joystick.gd`; add a test).
2. Firing stops within one frame of: aim-stick release, aim vector
   returning to zero, player death, pause opening, match end,
   focus loss / app pause.
3. No firing while dead, paused, or after match end — gate
   `touch_firing` on the same conditions the old path used (the old
   `fire_button.is_held()` was already gated by those states; the new
   vector read must be gated identically — do not just OR it in).
4. A tap on GRENADE / WEAPON / RELOAD / PAUSE / SCORE, or left-stick
   movement alone, fires 0 shots (multi-touch: those touches must not
   leak into the aim stick's touch ID — the existing per-stick
   `_touch_id` ownership in `joystick.gd` already prevents this; keep it).
5. Simultaneous move + aim-fire works (two fingers, two touch IDs) —
   the existing routing already supports this; verify, don't assume.

## 5. Test plan (REPLACES the old fire-button test suite)

Delete/retire the old fire-button tests in `game.gd` (the `_jt_press_fire`
/ `_jt_release_fire` / `_st_press(fire_button)` helpers at ~lines
3444–3450, 3672–3684, 3844–3915, 4163, 4244–4250, 4846, 4935–4953 —
repurpose the harness helpers to drive the AIM stick instead) and add a
right-stick-fire suite. Required cases:
1. Aim stick untouched → **0 shots**.
2. Deflect aim stick beyond dead zone → fires; aim direction matches
   the stick vector.
3. Release aim stick → firing stops immediately (0 shots in the next
   tick window).
4. Move stick alone / GRENADE alone / WEAPON alone / RELOAD alone /
   PAUSE alone / SCORE alone → **0 shots each**.
5. Move + aim-fire simultaneously (two touch IDs) → moves AND fires.
6. Semi-auto (pistol/sniper): quick flick → **exactly 1 shot** (QA-027
   carry-over); hold deflected → still exactly 1 shot, no auto-repeat.
7. Hold auto weapon deflected → fires continuously at its table rate
   (count shots over 1 s ≈ rate, ammo decreases, host validation holds).
8. No firing while dead / paused / after match end (drive each state,
   deflect the stick, assert 0 shots).
9. Focus-out / app-pause with the stick held → vector resets to zero,
   no stuck firing on return (QA-016 behaviour, re-verified on the new
   path).
10. Full flow + regression suite green afterwards (QA-029 joystick
    transform, QA-030 solid collision, QA-031 kill-credit lock), 0 script
    errors.

## 6. Version / logging

- Version stays **v3.2 / versionCode 10**.
- When the implementation lands, log it as a new QA entry in `BUGS.md`
  (not in this phase): FIRE-button removal + right-stick fire, the §5
  suite results, and any leftovers.
- `fire_button.gd` deletion and the `fire_button_left` setting removal
  must be called out in the delivery notes (save-file compatibility:
  old saves carry a harmless stale key; the loader defaults cover it).

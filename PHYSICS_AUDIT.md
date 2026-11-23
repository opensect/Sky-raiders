# Physics Audit — LAN Arena Shooter vs PHYSICS_SPEC.md

**Audited:** 2026-11-19 ~01:25 IST. Read-only audit; no game file was edited.
**Spec:** `PHYSICS_SPEC.md` (user's reference physics breakdown, 2026-11-19).
**Code audited:** `player.gd`, `bullet.gd`, `grenade.gd`, `game.gd`, `joystick.gd`,
`fire_button.gd`, `weapons.gd`, `shooting_sync.gd`, `bullet_pool.gd`,
`game_data.gd`, `project.godot`, plus `player.tscn` / `bullet.tscn` /
`grenade.tscn` for collision layers.

## 0. Snapshot — file state at audit time (v2.5 builder is live)

A v2.5 builder is currently editing `game.gd` / `joystick.gd` /
`fire_button.gd`. Line numbers below are from this snapshot; **re-verify
after the v2.5 edit lands**, especially anything in `game.gd`.

| File | Modified (UTC) | Modified (IST) | Notes |
|---|---|---|---|
| `game.gd` | 2026-11-18 19:50:57 | 2026-11-19 01:20:57 | Most recent — v2.5 in progress |
| `joystick.gd` | 2026-11-18 19:32:16 | 2026-11-19 01:02:16 | QA-029 canvas-space fix present |
| `fire_button.gd` | 2026-11-18 19:32:21 | 2026-11-19 01:02:21 | QA-023 touch ownership present |
| `player.gd` | 2026-11-18 19:04:26 | 2026-11-19 00:34:26 | |
| `bullet.gd` | 2026-11-18 19:06:50 | 2026-11-19 00:36:50 | |
| `grenade.gd` | 2026-11-18 15:13:18 | 2026-11-18 20:43:18 | Oldest physics file — untouched by v2.4/v2.5 |
| `weapons.gd` | 2026-11-18 18:41:28 | 2026-11-19 00:11:28 | |
| `shooting_sync.gd` | 2026-11-18 18:41:39 | 2026-11-19 00:11:39 | |
| `bullet_pool.gd` | 2026-11-18 18:41:39 | 2026-11-19 00:11:39 | |
| `project.godot` | 2026-11-18 14:19:50 | 2026-11-18 19:49:50 | |

**Verdict summary:** 7 spec areas conform (or mostly), 4 partially conform,
**18 gaps** (GAP-01…GAP-18). The three biggest: no variable jump height,
no ground/air movement split and no air drag at all, and multiplayer
movement is peer-authoritative with lerp-only smoothing (no host authority
over positions, no prediction/reconciliation).

---

## 1. Fixed timestep — ✅ CONFORMS

- `project.godot:60` — `physics_ticks_per_second=60`. Fixed step is on.
- All movement, gravity, jetpack, bullets and grenades integrate in
  `_physics_process(delta)` (`player.gd:306`, `bullet.gd:104`,
  `grenade.gd:43`) with `delta`-scaled terms. No `_process`-driven motion.
- Minor (GAP-14, see §12): touch state is sampled in `game.gd:_process`
  (`game.gd:1723` `_update_touch_state`) and read one frame later in
  physics; acceptable, but keyboard `Input.is_action_just_pressed`
  (`player.gd:399`) is polled inside `_physics_process`, where a press
  landing between physics ticks can be missed.

## 2. Horizontal movement — ⚠️ PARTIAL (GAP-01/02/03)

What the code does (`player.gd:14-16`, `415-429`):

```gdscript
const SPEED := 330.0
const ACCEL := 2600.0
const DECEL := 3400.0
# _apply_movement:
var target_vx := _move_axis * SPEED
if _move_axis != 0.0:
    velocity.x = move_toward(velocity.x, target_vx, ACCEL * delta)
else:
    velocity.x = move_toward(velocity.x, 0.0, DECEL * delta)
```

- Analog magnitude is honoured (`target_vx = _move_axis * SPEED`), and
  direction reversal is smooth in the limited sense that `move_toward`
  passes through 0 instead of snapping — reversal itself is not broken.
- **GAP-02 — no ground/air split (spec §2E).** One `ACCEL`, one `DECEL`,
  one `SPEED` for ground and air. Spec requires: stronger accel + higher
  friction + faster reversal + its own max speed on ground; moderate
  accel + lower friction + slower reversal + its own max speed in air.
  **Fix:** in `player.gd`, add
  `ACCEL_GROUND := 2600.0`, `ACCEL_AIR := 1500.0`,
  `DECEL_GROUND := 3400.0`, `DECEL_AIR := 900.0`,
  `SPEED_GROUND := 330.0`, `SPEED_AIR := 360.0` (air slightly faster,
  reference feel), and branch on `is_on_floor()` in `_apply_movement`.
- **GAP-03 — no exponential damping / air drag (spec §2C, §6).**
  Deceleration is linear `move_toward` only. There is no
  `velocity *= exp(-k*delta)` anywhere, and no drag constant exists.
  **Fix:** add `DRAG_GROUND := 8.0`, `DRAG_AIR := 1.2`; when no move
  input, apply `velocity.x *= exp(-drag * delta)` (ground) and apply the
  air drag every frame while airborne (even with input held, so top
  speed in air is drag-limited, not just clamped). Keep `move_toward`
  for the powered-acceleration case only.
- **GAP-01 — reversal uses the same rate both ways.** With the
  ground/air split above, add a reversal bonus: when
  `sign(_move_axis) != sign(velocity.x)` and `velocity.x != 0`, use
  `ACCEL * 1.6` (ground) / `ACCEL * 1.2` (air) so a flick reverses
  crisply on ground and lazily in air. Spec §2D is otherwise satisfied
  by `move_toward` (no snap), so this is tuning, not a rebuild.

## 3. Gravity, falling, landing — ✅ MOSTLY CONFORMS

- `player.gd:20-21`: `GRAVITY := 1400.0`, `MAX_FALL := 950.0`;
  `player.gd:448-455` applies gravity after jump/jetpack and clamps
  `velocity.y` to `MAX_FALL` (+350 while fast-falling).
  Terminal velocity exists and is enforced every physics frame. ✅
- Landing is via `move_and_slide()` (`player.gd:458`) with a capsule
  (`player.gd:170-176`, radius 17, height 52, `floor_snap_length = 4.0`).
  Hard-landing FX fires when `_fall_speed > 550` (`player.gd:460-466`). ✅
- Player tunnelling is not possible in practice: max fall step is
  `1300 px/s / 60 = ~22 px` per tick vs 48 px platform thickness
  (`game.gd:71-110`, all platforms `Rect2(..., 48)`). ✅
- Extra, not in spec but fine: stick-down fast-fall
  (`FAST_FALL_EXTRA := 1600.0`, `player.gd:32,450-453`).
- Note for the builder: gravity is added on the same frame the jump is
  applied (`player.gd:433` sets `vy = -660`, then `player.gd:448` adds
  `+1400*delta` ≈ +23), so the effective jump impulse is −637, not −660.
  Apex ≈ 155 px. Harmless, but jump tuning must be measured from the
  real apex, not the constant.

## 4. Jumping — ❌ GAP (GAP-04: no variable jump height)

- Jump itself is good: stick-up rising edge only, re-arm on release
  (`player.gd:362-369`), coyote time 0.10 s + jump buffer 0.12 s
  (`player.gd:25-26,424-435`), `JUMP_VELOCITY := -660.0`. ✅
- **GAP-04 — variable jump height is missing (spec §4).** There is no
  jump-release cut anywhere: releasing the stick up while `velocity.y < 0`
  does nothing, so a tap and a hold reach the same apex.
  **Fix:** in `_apply_movement`, after the jetpack branch, add:
  ```gdscript
  # Variable jump height: releasing stick-up while still rising cuts vy.
  if not _jump_held and velocity.y < 0.0 and _jump_cut_armed:
      velocity.y *= 0.45
      _jump_cut_armed = false
  ```
  Set `_jump_cut_armed = true` when the jump is applied
  (`player.gd:433`), clear it on landing / when jetpack starts. Suggested
  cut factor `0.45` (spec: `vy *= c, c < 1`). This interacts with the
  jetpack: the cut must NOT fire while `_jetpacking` is true, and holding
  stick-up must keep `_jump_held` true so the cut never triggers during
  a jetpack climb.

## 5. Jetpack — ⚠️ PARTIAL (GAP-05/06/07)

What the code does (`player.gd:18-19,22-24,436-447`):

```gdscript
const JET_ACCEL := 1900.0
const MAX_JET_RISE := 430.0
const FUEL_MAX := 100.0
const FUEL_DRAIN := 45.0   # ~2.2 s of thrust
const FUEL_REFILL := 70.0  # ~1.4 s to refill
# elif _jump_held and not is_on_floor() and fuel > 0.0:
#     velocity.y -= JET_ACCEL * delta; clamp to -MAX_JET_RISE
#     fuel -= FUEL_DRAIN * delta; _jetpacking = true
# if is_on_floor(): fuel += FUEL_REFILL * delta
```

- Thrust/fuel/momentum core is correct: thrust 1900 vs gravity 1400 gives
  net −500 px/s² rise, capped at −430 px/s; releasing the stick keeps
  upward velocity (nothing zeroes `vy` on release — momentum preserved ✅);
  jetpack sound starts/stops with thrust (`player.gd:443-445`); the
  `jetpack` animation plays while thrusting (`player.gd:509-511`). ✅
- **GAP-05 — fuel regen model is wrong vs spec §5.** Fuel refills only
  while `is_on_floor()` (`player.gd:446-447`), instantly, with no
  recharge delay. Spec: regen when thrust is released (not only on the
  ground) + a recharge delay + distinct empty-fuel behaviour.
  **Fix:** add `FUEL_REGEN_DELAY := 0.6` (s) and `_fuel_delay_timer`;
  reset the timer whenever thrusting; regen (`FUEL_REFILL`) only after
  the timer expires, whether grounded or airborne; keep the on-ground
  rate higher if desired (`FUEL_REFILL_GROUND := 70.0`,
  `FUEL_REFILL_AIR := 35.0`). At `fuel == 0`, thrust must stay off until
  fuel > 0 (already true) — and the flame/sound must stop (sound does;
  flame does not exist, see GAP-06).
- **GAP-06 — no jetpack flame at all (spec §5).** Grep over
  `player.gd` / `game.gd` / `audio.gd` finds no flame sprite, particle,
  or scale-by-thrust effect — only the `jetpack` animation and the
  looping sound. Spec requires flame tied to actual thrust state:
  off = none, thrusting = visible, strong thrust = longer flame,
  low fuel = warning, empty = flame gone, descending = none.
  **Fix:** add a `Sprite2D`/`GPUParticles2D` flame child at the
  backpack (position ≈ `(0, 18)` behind the sprite), driven in
  `_update_visuals`: `visible = _jetpacking and fuel > 0`;
  `scale.y = 0.6 + 0.6 * (thrust fraction)`; tint orange-red and blink
  when `fuel < 25`; hide whenever `not _jetpacking` (covers descending).
  Do not tie it to the animation name — tie it to `_jetpacking`.
- Tuning note (not a gap): net rise accel is only 500 px/s², so the
  jetpack feels sluggish for the first ~0.5 s; if playtesting says
  "floaty", raise `JET_ACCEL` to 2200 (net −800) rather than touching
  `MAX_JET_RISE`. Do not raise `MAX_JET_RISE` above ~500 or the
  170 px platform gaps become trivial.

## 6. Air resistance / momentum — ❌ GAP (GAP-03, see §2)

- No drag constant, no `exp(-k*delta)` damping, no separate ground/air
  deceleration anywhere in `player.gd` or `game.gd`. Releasing the stick
  on the ground and in the air currently stops the player in the same
  way (linear `DECEL := 3400`, ~0.1 s from max speed). Spec §6 requires
  ground = responsive stop, air = long smooth slide. **Fix is GAP-03
  above.** After the fix, air slide from 330 px/s at `DRAG_AIR 1.2`
  should take ~1 s to fall below 60 px/s; ground stop should take
  ~0.15 s. Verify with test T-06.

## 7. Rotation & aiming — ⚠️ PARTIAL (GAP-08/09)

- Dual-stick independence is correct: left stick moves, right stick
  aims, FIRE button fires; aim angle is `atan2` via `_aim_dir.angle()`
  (`player.gd:471`), facing flips from `cos(aim_angle)`
  (`player.gd:472-473`), gun sprite rotates to the exact aim angle and
  flips upright when aiming left (`player.gd:896-899`). Moving right
  while shooting left works. ✅
- **GAP-08 — aim does not hold when the stick is released (spec §7:
  "|D| < D_min => keep previous aim").** `player.gd:474-477`:
  ```gdscript
  elif _move_axis != 0.0:
      facing = ...; aim_angle = 0.0 if facing > 0 else PI
  ```
  Releasing the aim stick while moving snaps the gun to horizontal
  facing. **Fix:** delete the `aim_angle = 0.0 / PI` assignment; only
  update `facing` from movement when not aiming, and leave `aim_angle`
  untouched. (When standing still and not aiming, `aim_angle` already
  persists — keep that behaviour everywhere.)
- **GAP-09 — dead zone is applied three times with three values
  (spec §7 wants one D_min).** `joystick.gd:24,141` dead zone 0.12 with
  rescale; `game.gd:1737` `touch_aim_active = aim_vec.length() > 0.25`;
  `player.gd:23,376` `AIM_DEAD_ZONE := 0.25`. Net effect: the aim stick
  is dead below ~0.25 and the 0.12 rescale is pointless.
  **Fix:** single source of truth — keep the rescaling dead zone in
  `joystick.gd` only, set it to `0.20`, delete the `0.25` thresholds in
  `game.gd:1737` (`touch_aim_active = aim_vec.length() > 0.0`) and
  `player.gd:376` (`_aiming = _aim_dir.length() > 0.0`), and keep
  `AIM_DEAD_ZONE` only as the documented constant that `joystick.gd`
  reads. Do the same audit for the move stick: its 0.12 dead zone is
  the only move dead zone — fine, just document it.
- Minor: `_aim_dir` is multiplied by `GameData.sensitivity`
  (`player.gd:373`) before the dead-zone test, so a sensitivity > 1
  shrinks the effective dead zone. After GAP-09, apply sensitivity
  after the dead zone (or clamp it to the 0.5–2.0 range in settings).

## 8. Weapon recoil — ✅ CONFORMS

- Data-driven per-weapon table (`weapons.gd:19-26`): recoil 15–260 px/s,
  shake 0.05–0.50, auto/semi-auto flags. Pistol 20 / SMG 15 / rifle 30 /
  shotgun 220 / sniper 180 / rocket 260 — sensible ordering. ✅
- Applied as a velocity impulse opposite the shot plus gun kick plus
  trauma-squared camera shake (`player.gd:586-592, 640-646, 907-914`):
  `velocity -= dir * recoil`, `_gun_kick = 1.0`, `add_shake(shake)`. ✅
- Two tuning notes for the builder, not gaps: (a) the horizontal recoil
  impulse is eaten by `DECEL := 3400` within ~1–2 physics frames, so
  the *movement* effect is nearly invisible — the feel comes from the
  gun kick + shake, which is fine; do not "fix" this by lowering DECEL.
  (b) Recoil is applied on the owning peer before the `spawn_bullet`
  RPC is validated by the host (`player.gd:567-592` vs
  `shooting_sync.gd:29`); a rejected shot still kicks locally. Cosmetic
  only — leave it, or gate `_fire()`'s kick on host acceptance later.

## 9. Bullets — ✅ CONFORMS (one trajectory gap: GAP-10)

- Swept collision is real: `bullet.gd:104-122` raycasts
  `from → to` every physics step with mask 3 (world layer 1 + players
  layer 2), so the fastest bullet (sniper 1600 px/s = 26.7 px/step)
  cannot tunnel a 48 px platform. Impact / player-hit / owner-overlap
  handling is correct. Pooling (`bullet_pool.gd`, 96 preallocated) does
  not affect physics. ✅
- Per-weapon speed / spread / pellets / life-as-range all come from
  `weapons.gd` (`player.gd:567-585`). ✅
- **GAP-10 — rocket has no gravity/drop (spec §9: "gravity-affected
  grenades/rockets").** The rocket is a straight-line bullet
  (`kind == 4`, `explosive == true`, speed 700, `bullet.gd` has no
  gravity term at all). **Fix (optional, gameplay decision):** if the
  v3 design wants arcing rockets, add `gravity: float` to the weapon
  table (`weapons.gd`, default 0, rocket 500) and in `bullet.gd`
  `_physics_process` apply `direction = (direction*speed +
  Vector2(0, gravity*delta)).normalized()` — or leave straight and
  note it as a deliberate deviation from the spec. Grenades already arc
  (see §10).

## 10. Grenades & explosions — ⚠️ PARTIAL (GAP-11/12)

- Grenade arc: `grenade.gd:44` gravity 1400 (matches player gravity ✅),
  initial velocity `throw_dir * 620 + (0, -260)` (`grenade.gd:31`),
  fuse 2.0 s, blast radius 170, damage 55 (`grenade.gd:20-22`). ✅
- **GAP-11 — grenade bounce is broken.** `grenade.gd:46-49`:
  ```gdscript
  if is_on_floor():
      velocity.y = -velocity.y * 0.45
      velocity.x *= 0.7
  ```
  `move_and_slide()` zeroes `velocity.y` on floor contact *before*
  this runs, so the bounce reads `vy ≈ 0` and the grenade never bounces;
  worse, `velocity.x *= 0.7` runs **every physics frame** while resting,
  so a rolling grenade stops in ~0.1 s. **Fix:** capture
  `vy_before := velocity.y` before `move_and_slide()`, then:
  ```gdscript
  if is_on_floor() and vy_before > 120.0:
      velocity.y = -vy_before * 0.45
      velocity.x *= 0.8
  elif is_on_floor():
      velocity.x *= exp(-4.0 * delta)   # rolling friction, frame-rate independent
  ```
  Wall bounce (`grenade.gd:50-51`, `vx *= -0.5`) has the same
  pre/post-slide problem — apply it only when `is_on_wall()` and the
  pre-slide `vx` was toward the wall. Also add a grenade terminal
  velocity (`MAX_FALL := 950`, same as the player) — currently uncapped.
- Explosions: host-only damage with distance falloff
  `amount = damage * (0.4 + 0.6 * falloff)` (`player.gd:758-763`,
  `game.gd:2137-2164`), knockback `dir * 550 * falloff + (0, -220 *
  falloff)` (`player.gd:765`). Radius/damage consistent between host
  and victim (computed twice from the same formula). ✅
- **GAP-12 — explosions ignore walls/cover (spec §9).** `game.gd`
  `request_explosion` damages everyone within `radius` with no
  line-of-sight test, so a grenade behind a solid crate still hurts.
  **Fix:** in `request_explosion`, before applying damage to each
  player, raycast `pos → child.global_position` on mask 1; if a
  `StaticBody2D` is hit first, skip damage (or halve it) for that
  player. Knockback should be skipped too. Cheap (one ray per player
  per explosion) and makes crates real cover.

## 11. Solid collision (platforms / decor / walls) — ✅ MOSTLY (GAP-13/14)

- Arena: all platforms + left/right walls + ceiling are `StaticBody2D`
  shapes on layer 1 (`game.gd:627-652`); player mask is 1, so players
  collide; bullets raycast mask 3, so bullets stop. ✅
- Solid decor is real (QA-030, `game.gd:618-624, 663-677`):
  `crate, barrels, sandbags, rock, column, jpillar, jstatue, jtower,
  jcrate, jrock` get a collision rect on layer 1; players cannot walk
  through them and bullets stop at them. ✅
- Players do **not** collide with each other: `player.tscn` sets
  `collision_layer = 2, collision_mask = 1` — correct for the reference game
  (players pass through each other). ✅
- **GAP-13 — visible bridges/arches have no collision.** `game.gd:655-661`
  draws every decor sprite, but only `SOLID_DECOR_KINDS` get shapes.
  `bridge` and `jarch`/`jbridge` are drawn as solid-looking walkable
  structures and the player falls straight through them — the most
  visible collision lie left in the game.
  **Fix:** either add `"bridge", "jbridge", "jarch"` to
  `SOLID_DECOR_KINDS` (with a thinner rect — top plank only, e.g.
  height = 24 px at the sprite's top edge, not the full texture), or
  remove/replace those sprites with clearly non-solid dressing (vines,
  background arches). Do not leave a walkable-looking bridge
  pass-through.
- **GAP-14 — decor collision rect = full texture size.**
  `game.gd:670-677` uses `Vector2(tex.get_width(), tex.get_height())`
  centred on the sprite, including transparent padding, so the solid
  box is bigger than the visible crate/barrel (invisible edges block
  movement and bullets). **Fix:** add a per-kind inset table, e.g.
  `DECOR_INSETS := {"crate": 6, "barrels": 8, "column": 10, ...}` (px
  trimmed per side), and shrink the rect by the inset. Verify against
  the actual sprite bounds in the v3 asset pass.
- Non-gaps: no one-way platforms exist (all solid) — spec does not
  require them; lava is a separate hazard system, out of scope here.

## 12. Multiplayer physics sync — ⚠️ PARTIAL (GAP-15/16/17)

What the code does:

- **Shooting / health / deaths / kills / pickups: host-authoritative ✅.**
  `spawn_bullet` RPC is validated on the host for fire-rate (0.75×
  weapon rate) and ammo mirror (`shooting_sync.gd:29-56`); only the
  host's simulation deals damage (`bullet.gd:160-196`); `take_damage` /
  `take_explosion_damage` / `add_kill` / `give_pickup` reject any sender
  that is not the host (`player.gd:705-714, 749-757, 770-777, 780-788`).
  Kill credit is decided by the host (`bullet.gd:187-196`,
  `game.gd:2150-2163`). ✅
- **GAP-15 — player positions are peer-authoritative, not
  host-authoritative (spec §9).** Each peer simulates its own player
  (`player.gd:324-340`: local input → `_apply_movement` on the owning
  peer only) and replicates `sync_position` / `sync_velocity` via
  `MultiplayerSynchronizer` at 0.05 s (`player.gd:296-302`). The host
  never validates or corrects a position; a modified client can
  teleport and the host will accept it. **Fix (v3, needs a design
  decision, not a one-line patch):** either (a) accept peer-authoritative
  movement as the LAN design (document it as a deliberate deviation —
  defensible on a trusted LAN, and the current anti-cheat already
  covers shooting/ammo), or (b) implement host reconciliation: clients
  send inputs, host simulates and sends back authoritative positions,
  clients reconcile. Do not half-do (b) — a naive host snap will feel
  worse than the current lerp. Recommendation: document (a) for v3.0,
  revisit only if cheating is reported.
- **GAP-16 — no client prediction / reconciliation; interpolation is
  lerp-only.** Remote players are rendered as
  `position.lerp(sync_position, clampf(delta * 14.0, 0, 1))`
  (`player.gd:338-340`) — a smoothing filter, not interpolation: no
  timestamp, no snapshot buffer, no extrapolation, so remote movement
  lags ~50–100 ms and stutters when packets bunch. There is no
  prediction of the local player on remote peers and no reconciliation
  step anywhere. **Fix:** if staying peer-authoritative, add a
  2-snapshot interpolation buffer: store `(timestamp, position,
  velocity)` on receipt, render at `now - 100 ms` by interpolating
  between the two bracketing snapshots; extrapolate one step past the
  newest snapshot using `sync_velocity` when no newer snapshot has
  arrived. This is a contained change in `player.gd` remote branch.
- **GAP-17 — knockback is applied on the victim's peer, not the host.**
  `take_explosion_damage` adds the knockback impulse to `velocity` on
  the victim's own node (`player.gd:765`) via RPC from the host. That is
  correct in direction, but the host never sees the resulting position
  change until the next sync tick, and nothing reconciles it — combined
  with GAP-15, a knockbacked player can desync briefly. Minor; fix by
  folding knockback into the same sync path as GAP-16 (velocity is
  already replicated, so the lerp will absorb it — verify in test T-21).

## 13. Input path (joystick / FIRE button) — ✅ MOSTLY (GAP-18)

- Joystick: touch-owned, dead zone 0.12 with rescale, knob clamped to
  radius, vector zero unless a finger is held, reset on focus loss /
  pause (`joystick.gd:24, 113-160`); QA-029 canvas-space conversion is
  in place (`joystick.gd:124-128`). FIRE button: owns one touch, hold =
  auto fire, press edge for semi-auto, slide-off cancels
  (`fire_button.gd`). Touch routing by screen half / button rect
  (`game.gd:1626-1673`). ✅
- **GAP-18 — input is sampled in `_process`, consumed in
  `_physics_process`.** `game.gd:1723-1738` updates `touch_move_vec` /
  `touch_aim` / `touch_firing` in `_process` (render rate, variable),
  while `player.gd:306-340` reads them in `_physics_process` (fixed
  60 Hz). A tap shorter than one physics tick can be read late or, for
  the semi-auto press edge, only via the `has_press_edge()` peek
  (`fire_button.gd`, `player.gd:385-390`) — which works, but the
  one-frame lag is real. **Fix:** low priority; if input latency is
  ever measured above ~2 frames, move `_update_touch_state()` into
  `_physics_process` in `game.gd` (it only reads stick/button state)
  and keep `_process` for HUD only. Do not change this speculatively —
  measure first (test T-24).

## 14. Gap index (for the builder)

| # | Gap | Spec § | Severity | Where to fix |
|---|---|---|---|---|
| GAP-01 | Reversal rate same both ways (no reversal bonus) | §2D | Low (tuning) | `player.gd` `_apply_movement` |
| GAP-02 | No ground/air accel/decel/max-speed split | §2E | **High** | `player.gd` constants + `_apply_movement` |
| GAP-03 | No exponential damping / air drag at all | §2C, §6 | **High** | `player.gd` `_apply_movement` |
| GAP-04 | No variable jump height (tap = hold apex) | §4 | **High** | `player.gd` `_apply_movement` |
| GAP-05 | Fuel regen only on floor, instant, no delay | §5 | Medium | `player.gd` `_apply_movement` |
| GAP-06 | No jetpack flame tied to thrust state | §5 | Medium | `player.gd` `_update_visuals` + new flame node |
| GAP-07 | (folded into GAP-05/06 tuning) net jetpack accel 500 px/s² feels weak — raise `JET_ACCEL` to ~2200 if playtest says floaty | §5 | Low (tuning) | `player.gd:18` |
| GAP-08 | Aim snaps to facing when aim stick released while moving | §7 | Medium | `player.gd:474-477` |
| GAP-09 | Dead zone applied 3× (0.12 + 0.25 + 0.25) | §7 | Medium | `joystick.gd`, `game.gd:1737`, `player.gd:376` |
| GAP-10 | Rocket has no gravity/drop | §9 | Low (design decision) | `weapons.gd` + `bullet.gd` |
| GAP-11 | Grenade bounce broken (vy zeroed before bounce; vx *= 0.7 every frame) | §9 | Medium | `grenade.gd:43-51` |
| GAP-12 | Explosions damage through walls (no line-of-sight) | §9 | Medium | `game.gd:2137` `request_explosion` |
| GAP-13 | Bridges/arches look walkable, no collision | §9 | Medium | `game.gd:623` `SOLID_DECOR_KINDS` or remove sprites |
| GAP-14 | Decor collision rect = full texture incl. transparent padding | §9 | Low | `game.gd:670-677` |
| GAP-15 | Positions peer-authoritative, not host-authoritative | §9 | **High** (design decision) | Document (a) or rebuild (b) — see §12 |
| GAP-16 | No prediction/reconciliation; lerp-only remote smoothing | §9 | Medium | `player.gd:336-340` |
| GAP-17 | Knockback applied on victim peer, host never reconciles it | §9 | Low | Covered by GAP-16 fix; verify T-21 |
| GAP-18 | Input sampled in `_process`, consumed in `_physics_process` | §1 | Low | `game.gd:1723` — measure first (T-24) |

Conforming, no action: fixed 60 Hz timestep; gravity + terminal velocity
(1400 / 950); coyote 0.10 s + jump buffer 0.12 s; jetpack thrust/fuel/
momentum core; swept bullet raycast; per-weapon recoil table + gun kick +
shake; host-authoritative shooting/health/deaths/kills/pickups; solid
platforms/walls/ceiling + solid decor; players pass through each other;
dual-stick independent aim; touch ownership (QA-016/023/029).

---

## 15. PHYSICS TESTS — builder must run after the rebuild

Run headless where the harness supports it (`--joy-test`,
`--collision-test`, `--flow-test` in `game.gd`); the rest need a real
phone or the desktop keyboard/mouse fallback. Record pass/fail per test
in `BUGS.md` (new QA entries, don't overwrite existing ones).

### A. Movement & friction

- **T-01 Direction reversal.** Run right at max speed (hold move stick
  fully right ~1 s), then flick fully left. Pass: `velocity.x` decreases
  smoothly through 0 (log it — no single-frame sign flip), and the
  reversal completes noticeably faster on the ground than in the air.
- **T-02 Ground vs air accel.** From standstill, hold full right on the
  ground; time to 330 px/s. Repeat mid-air (jump, then hold right).
  Pass: ground reaches max speed clearly faster than air (target:
  ground ≤ 0.15 s, air ≥ 0.25 s after the GAP-02 fix).
- **T-03 Analog magnitude.** Hold the move stick at ~50% deflection.
  Pass: steady speed ≈ 165 px/s (±20), not full 330.
- **T-04 Stop distance, ground.** Run at max speed, release the stick.
  Pass: player stops within ~60 px (responsive ground friction).
- **T-05 Stop distance, air (same as T-04 but airborne).** Jump,
  build max horizontal speed, release the stick mid-air. Pass: player
  keeps sliding — travels at least 2× the ground stop distance before
  `|vx| < 60`.
- **T-06 Air vs ground decel (T-04 vs T-05 numbers).** Pass: air slide
  distance ≥ 2× ground stop distance; air decel is visibly smooth, not
  a linear ramp to zero.

### B. Gravity, jumping, landing

- **T-07 Terminal velocity.** Drop from the top of the map (no input).
  Pass: `velocity.y` caps at 950 px/s (1300 while fast-falling with
  stick down); never exceeds the cap by more than 5%.
- **T-08 Tap vs hold jump.** Tap stick-up (flick up and release in
  < 0.15 s) vs hold stick-up for the full rise; measure apex height in
  px from the take-off point. Pass: hold apex is clearly higher than
  tap apex (target: hold ≈ 155 px, tap ≈ 70–90 px after the GAP-04 fix).
- **T-09 Coyote + buffer.** Run off a platform edge, press jump within
  ~0.1 s after leaving the edge; and press jump ~0.1 s before landing.
  Pass: both jumps fire (no "I pressed jump and nothing happened").
- **T-10 Landing.** Fall from max height onto a platform. Pass: player
  lands exactly on the platform top (feet on the surface, no sinking,
  no bounce), `velocity.y` reads 0 on the landing frame, hard-landing
  dust FX appears only for falls with `vy > 550` at impact.

### C. Jetpack

- **T-11 Jetpack rise + cap.** From the ground, jump then hold
  stick-up. Pass: player rises smoothly, `velocity.y` never goes below
  −430 px/s, climb feels steady (not accelerating forever).
- **T-12 Fuel drain + empty.** Hold stick-up from full fuel until it
  stops rising. Pass: fuel drains to 0 in ~2.2 s, flame stops, thrust
  stops, player falls; no thrust is possible at 0 fuel.
- **T-13 Fuel regen + delay.** Land with empty fuel, wait without
  thrusting. Pass: no regen for the first ~0.6 s (recharge delay), then
  fuel refills at ~70/s on the ground; regen also happens in the air
  after the delay when not thrusting (slower is acceptable).
- **T-14 Jetpack momentum.** Thrust upward, release stick-up mid-climb.
  Pass: player keeps rising on momentum, apexes, then falls — velocity
  is NOT zeroed on release.
- **T-15 Flame follows thrust.** Thrust, release, thrust again, run
  out of fuel, descend without thrusting. Pass: flame visible only
  while actually thrusting; longer/brighter under full thrust; blinks
  or changes colour at fuel < 25; gone when fuel is 0 and while
  descending.
- **T-16 Air control while flying.** Jetpack up while holding the move
  stick left/right. Pass: horizontal speed builds in the air (slower
  than on the ground) and the player can steer while climbing.

### D. Aiming

- **T-17 Independent aim.** Move right while aiming/shooting left;
  fly up while shooting diagonally; fall while shooting horizontally.
  Pass: bullets go where the aim stick points in all three cases,
  regardless of movement direction.
- **T-18 Aim hold.** Aim up-right, release the aim stick, keep moving
  right. Pass: `aim_angle` stays up-right (gun does not snap to
  horizontal facing) until the aim stick is touched again.
- **T-19 Dead zone.** Wiggle the aim stick slightly (small deflections
  < ~20% of radius). Pass: aim angle does not jitter or drift; the gun
  holds still.

### E. Weapons, bullets, recoil, explosions

- **T-20 No tunnelling.** Fire the sniper (fastest, 1600 px/s) at a
  thin 48 px platform from point blank, and at a solid crate.
  Pass: bullet stops at the platform/crate surface every time (impact
  FX at the surface, no bullet visible on the far side) across 20 shots.
- **T-21 Recoil.** Fire the sniper and the rocket; then fire the
  pistol. Pass: sniper/rocket give a visible backward impulse +
  camera shake + gun kick; pistol gives almost none. Numbers: sniper
  recoil 180, rocket 260, pistol 20 (from `weapons.gd`).
- **T-22 Explosion knockback.** Stand next to a grenade blast (own
  grenade, close range, not lethal). Pass: player is pushed away from
  the blast centre and upward (`dir * 550 * falloff + (0, -220 *
  falloff)`), and the push is visible even through the movement code.
- **T-23 Explosion vs cover.** Stand behind a solid crate; have a
  grenade explode on the far side of the crate within blast radius.
  Pass: no (or halved, if the builder chooses halved) damage through
  the crate after the GAP-12 fix.
- **T-24 Grenade bounce.** Throw a grenade at a platform at a shallow
  angle. Pass: it bounces at least once with a visibly reduced height
  (~45% of impact speed), rolls/slides and slows gradually — it does
  not stop dead on first contact and does not pass through the floor.
- **T-25 Rocket trajectory.** Fire the rocket across the map. Pass:
  straight-line flight (current design) OR a visible arc if the builder
  implements GAP-10 — either is a pass, but the choice must be written
  in `BUGS.md` so it is a decision, not an accident.

### F. Collision

- **T-26 Solid decor.** Walk into a crate, a barrel stack and a
  column; shoot at each. Pass: player cannot pass through; bullets stop
  at the visible surface (not at invisible padding — check the impact
  point against the sprite edge).
- **T-27 Bridge/arch.** Walk over / under every bridge and arch decor
  piece. Pass: either the player can stand on the bridge (collision
  added, GAP-13 fixed) or the piece is visibly non-solid — never a
  walkable-looking bridge the player falls through.
- **T-28 Player vs player.** Two players run into each other. Pass:
  they pass through each other (no pushing, no getting stuck).
- **T-29 Fall-through check.** Fast-fall from the top of the map onto
  each platform height. Pass: no fall-through on any platform, 10/10
  drops.

### G. Multiplayer (code-path verification, not live LAN — sandbox blocks UDP)

- **T-30 Host-authoritative hits.** Read `bullet.gd:160-196` +
  `shooting_sync.gd:29-56` after the rebuild. Pass: only the host's
  simulation deals damage; a client-side `take_damage` from a non-host
  sender is rejected; fire-rate/ammo validation still runs.
- **T-31 Remote smoothing.** Two-phone test (user): host and client run
  and strafe. Pass: remote player motion looks smooth (no visible
  teleporting or rubber-banding beyond one interpolation step); if the
  GAP-16 buffer is implemented, motion stays smooth during a 100 ms
  packet gap.
- **T-32 Knockback sync.** Host throws a grenade next to the client.
  Pass: the client's knockback is visible on the host's screen within
  ~0.2 s and the client does not snap back afterward.
- **T-33 Input latency (GAP-18).** Tap FIRE quickly 10 times with the
  pistol (semi-auto). Pass: 10 shots, none lost, none doubled. If any
  tap is lost, move `_update_touch_state()` into `_physics_process`
  before delivery.

### H. Regression (must still pass after the rebuild)

- **T-34** Joystick acceptance suite 21/21 (existing `--joy-test` in
  `game.gd`), **T-35** smoke test 19 phases (`--smoke-test`),
  **T-36** fire-button suite 25/25, **T-37** full flow 10/10
  (menu → host → lobby → match → pause → scoreboard → back),
  **T-38** 0 script errors on a clean run, **T-39** all 10 maps load
  with platforms + spawns + pickups intact.

**Test count: 39** (T-01…T-39). Minimum green bar for delivery: all of
§A–§F on a real phone, §G by code path + the user's two-phone check,
§H suites at their previous pass counts.

---

# EXTENSION — spec points 9–21 (audit #2, 2026-11-19 ~01:35 IST)

**Scope:** `PHYSICS_SPEC.md` points 9–17 (user-provided 2026-11-19), point 17
in its **full** form (legs 0.75, arms 0.85, §§17.1–17.8), point 18 in its
**full Godot 4** form (environmental zones, §§18.A–18.E), point 19 (camera),
point 20 (firing while moving), point 21 (multiplayer sync). **Correction:**
the earlier draft flagged the legs multiplier as "unknown — message cut
off". That flag is **withdrawn**: the full point 17 gives head 1.5 /
torso 1.0 / legs 0.75 / arms 0.85. The partial-18 audit in the follow-up
handoff is **superseded** by the full-18 audit below (zones-based, not
player-controller-based). **Points 22–28 have NOT arrived** — the user's
message cut off at the start of point 22.

**Read-only audit; no game file was edited.** Gaps continue GAP-19+,
tests continue T-40+, same format as §§1–15.

## 0b. Snapshot — file state at audit #2 (v2.5 builder STILL live)

`game.gd` changed **during** this audit (19:50:57 → 19:59:56 UTC), so
**all `game.gd` line numbers below are stale-risk — re-verify after v2.5
lands**. All other files unchanged since audit #1.

| File | Modified (UTC) | Modified (IST) |
|---|---|---|
| `game.gd` | 2026-11-18 19:59:56 | 2026-11-19 01:29:56 | ⚠️ changed mid-audit |
| `joystick.gd` | 2026-11-18 19:32:16 | 2026-11-19 01:02:16 | |
| `fire_button.gd` | 2026-11-18 19:32:21 | 2026-11-19 01:02:21 | |
| `player.gd` | 2026-11-18 19:04:26 | 2026-11-19 00:34:26 | |
| `bullet.gd` | 2026-11-18 19:06:50 | 2026-11-19 00:36:50 | |
| `grenade.gd` | 2026-11-18 15:13:18 | 2026-11-18 20:43:18 | |
| `weapons.gd` | 2026-11-18 18:41:28 | 2026-11-19 00:11:28 | |
| `pickup.gd` | 2026-11-18 15:07:55 | 2026-11-18 20:37:55 | |
| `shooting_sync.gd` | 2026-11-18 18:41:39 | 2026-11-19 00:11:39 | |
| `bullet_pool.gd` | 2026-11-18 18:41:39 | 2026-11-19 00:11:39 | |

**Verdict summary (extension):** 7 spec areas conform (or mostly),
6 partially conform, **44 new gaps** (GAP-19…GAP-62). The three biggest:
no damage multipliers / hit regions at all (single flat-damage capsule),
respawn teleports blind with zero validation, and no velocity inheritance
or burst/reserve-ammo systems in the firing model.

---

## 16. Bullet / projectile physics (§9) — ⚠️ PARTIAL (GAP-19/20/21)

What the code does (`bullet.gd`, `player.gd:567-594`, `weapons.gd`):

- Per-projectile state exists **in part**: `bullet.gd:14-22` carries
  `direction, speed, damage, kind, owner_id, explosive, blast_radius,
  life` (+ `position` from the node). Muzzle start is real:
  `player.gd:576` `muzzle = global_position + (8*facing, 5) + dir * 52`
  (`GUN_LENGTH 46 + 6`). Straight-line flight, `position = from +
  direction * speed * delta` (`bullet.gd:104-109`). Swept collision is
  real: raycast `from → to` every physics step, mask 3
  (`bullet.gd:110-122`) — fastest bullet (sniper 1600 px/s = 26.7 px/step)
  cannot tunnel a 48 px platform. Pooling is **verified used, not just
  present**: `game.gd:533` creates `BulletPool.new(..., 96)`,
  `game.gd:553-565` `obtain_bullet()` / `return_bullet()`,
  `player.gd:672-695` `spawn_bullet` pulls from the pool, `bullet.gd`
  `_despawn()` returns to it. ✅
- **GAP-19 — no per-projectile radius / gravity / drag / range /
  weapon-id fields (spec §9).** `bullet.gd` has no `radius` (collision is
  a zero-thickness ray, not a circle), no `gravity`, no `drag`, no
  `range` (`life` doubles as range: range = speed × life), no `mask`
  (ray mask `3` is hardcoded at `bullet.gd:113`), and `kind` doubles as
  the weapon id. **Fix:** extend `bullet.gd:setup()` with
  `p_radius: float, p_gravity: float, p_drag: float, p_range: float`,
  store them, and in `_physics_process` apply
  `velocity.y += gravity * delta`, `velocity *= exp(-drag * delta)`,
  expire when travelled distance ≥ range; read `gravity/drag/range`
  from `weapons.gd` (defaults 0 / 0 / speed×life). Rocket gravity is
  the same fix as GAP-10 — do them together.
- **GAP-20 — shotgun is 6 pellets with random spread, not 7 with
  fixed offsets (spec §9).** `weapons.gd:22`: `pellets: 6`,
  `spread: 0.16` rad (±9.2°); `player.gd:578-583` fires each pellet as
  its own RPC bullet (independent state ✅) but with
  `d.rotated(randf_range(-spread, spread))` — uniform-random, not the
  spec's deterministic `[-15,-10,-5,0,5,10,15]°`. Note the spec
  contradicts itself: §20 says shotgun 6 pellets (see §24). **Fix:**
  `pellets: 7` in `weapons.gd`, and replace the random rotation with
  `d.rotated(deg_to_rad([-15,-10,-5,0,5,10,15][i]))`. Recommend 7 (the
  §9 detail) over §20's 6 — or ask the user to pick.
- **GAP-21 — bullet Area2D layer/mask disagrees with itself (Low,
  trap).** `bullet.tscn` says `collision_layer = 8, collision_mask = 3`,
  but `bullet.gd:34-36` `_ready()` sets `layer = 8, mask = 0`,
  `monitoring = false`. Harmless today (collision is raycast-based, the
  Area2D never detects anything) but a trap for the next edit.
  **Fix:** delete the layer/mask lines from `_ready()` (let the scene
  own them) or set them to match the scene; add a comment that the
  raycast at `bullet.gd:113` is the real collision.

## 17. Explosion physics (§10) — ⚠️ PARTIAL (GAP-22/23/24; GAP-12 stands)

- Falloff exists but is the wrong curve: `game.gd:2137-2164`
  `request_explosion` and `player.gd:758-763` both compute
  `amount = damage * (0.4 + 0.6 * (1 - d/R))` — the host's lethal check
  and the victim's actual damage use the same formula ✅ (consistent),
  but it is neither spec curve. **GAP-22 — 40% damage floor at the
  blast edge.** Spec wants linear `D = Dmax·(1-d/R)` (0 at edge) or
  smooth `D = Dmax·(1-u²)²`. **Fix:** adopt the smooth curve
  `amount = int(round(damage * pow(1.0 - u*u, 2.0)))` with `u = d/R`
  in **both** places (`game.gd:2150`, `player.gd:758-763`) — keep them
  in sync or the host's lethal check and the victim's damage disagree.
- **GAP-23 — knockback has no mass, no (1-u)² shaping, no vertical
  multiplier (spec §10).** `player.gd:765`:
  `velocity += dir * 550.0 * falloff + Vector2(0, -220.0 * falloff)` —
  a fixed velocity add, linear in falloff, same for every weapon and
  every player. No `ΔV = J/m`, no `J = K·(1-u)²·N`, no `Ky`.
  **Fix:** add `const MASS := 1.0` (player.gd) and in
  `take_explosion_damage` compute `u = dist/radius`,
  `J = 550.0 * pow(1.0 - u, 2.0)`, `velocity += dir * (J / MASS) +
  Vector2(0, -J * 0.4)` (0.4 ≈ Ky, tune so an explosion below a player
  launches them clearly upward).
- Visuals are layered and separate from damage ✅ in structure
  (`game.gd:2165-2186` `_spawn_explosion_fx`: fireball scale tween +
  smoke rise + explosion sound; FX runs on every peer, damage host-only;
  one-shot RPC, so no repeated damage per frame ✅). **GAP-24 — FX is
  missing the flash, shockwave ring and debris (spec §10, Low,
  cosmetic).** **Fix:** add a 0.08 s white flash sprite + an expanding
  ring (Line2D/arc tweened to `radius`) + 6–10 debris particles in
  `_spawn_explosion_fx`; all visual-only, no damage code.
- Wall obstruction is GAP-12 (audit #1) — unchanged, still open.

## 18. Collision detection (§11) — ⚠️ PARTIAL (GAP-25/26/27)

- Layer/mask taxonomy exists but is incomplete. Actual map:
  world/platforms/decor = layer 1 (`game.gd:630`); player body = layer 2,
  mask 1 (`player.tscn`); bullet = layer 8, raycast mask 3
  (`bullet.gd:113`); pickup trigger = layer 16, mask 2
  (`pickup.gd:26-27`); grenade = layer 0, mask 1 (`grenade.gd:20-21`).
  AABB + circle tests are engine-provided: player capsule
  (`player.gd:169-176`, radius 17, height 52) vs world via
  `move_and_slide()` (`player.gd:458`), which does minimum-separation
  resolution and preserves tangential movement (slide along a vertical
  wall while falling ✅). Bullet CCD is the swept raycast ✅. Pickup
  circle radius 22 (`pickup.gd:30`) ✅. **Conforms where the engine
  does the work.**
- **GAP-25 — one capsule is body, hitbox and damage region (spec §11).**
  The same capsule (`player.gd:169-176`) handles movement collision
  AND bullet hits; `bullet.gd:124-136` `_hit_player` applies flat
  `damage` wherever the ray strikes — no head/torso/legs/arms regions.
  **Fix:** either (a) add two child `Area2D` hit regions (head circle
  at y≈-20, torso/body = the capsule) and pass the region into
  `take_damage`, or (b) compute the region from the hit height in
  `_hit_player`: `rel_y = hit_pos.y - p.global_position.y`
  (head if `rel_y < -14`, legs if `rel_y > 12`, else torso; arms folded
  into torso unless (a) is built). See also GAP-42 — do these together,
  or record single-body 1.0× as a deliberate deviation per spec §17.3
  ("do not over-complicate if single body hitbox").
- **GAP-26 — no explosion / hazard / sensor layers (spec §11, Low).**
  Explosions are RPC + distance math (`game.gd:2137`), lava is a
  positional `Rect2.has_point` check (`game.gd:786-830`) — neither is a
  physics category. **Fix (documentation-first):** name the layers in
  `project.godot` (`1 world, 2 player body, 4 explosion [reserved],
  8 projectile, 16 pickup, 32 hazard [reserved]`) and record that
  explosion/lava stay positional by design; only build real
  `Area2D` hazard zones if a second hazard type is added.
- **GAP-27 — grenade has no CCD and no terminal velocity (Low).**
  `grenade.gd:43-45` is discrete `move_and_slide()` only, `velocity.y`
  uncapped. Not exploitable today (worst fall step ≈ 33 px/tick vs
  48 px platforms) but unprotected. **Fix:** cap `velocity.y` at
  `MAX_FALL := 950` (same as the player) in `grenade.gd:44`; add a
  swept segment check only if thinner platforms are ever added.

## 19. Walls / ceilings / platforms (§12) — ❌ GAPS (GAP-28/29/30/31)

- Solid walls + ceiling ✅: `game.gd:645-653` builds left/right walls
  and a ceiling as layer-1 rects; `move_and_slide()` zeroes upward
  velocity on ceiling contact and preserves horizontal velocity ✅
  (engine behaviour — matches the spec's ceiling rule without extra
  code). No bottom wall exists, but falling out is caught:
  `player.gd:464` respawns when `position.y > map_size.y + 200` ✅.
- **GAP-28 — no one-way platforms (spec §12).** All platforms are
  solid `Rect2` (`game.gd:627-641`); the four one-way conditions
  (falling + previous bottom above + new bottom crosses top +
  horizontal overlap) exist nowhere. **Feasibility: OUT OF SCOPE for
  v3.0.** Every map is designed around solid platforms; adding
  one-way needs a platform flag + drop-through input (stick-down +
  jump) + `floor_snap` exceptions. Only build if a map design needs
  jump-through platforms.
- **GAP-29 — no moving platforms (spec §12).** No `AnimatableBody2D`,
  no `PathFollow2D`, no platform velocity anywhere; grep finds no
  moving-platform code. **Feasibility: OUT OF SCOPE for v3.0.** Needs
  platform displacement inheritance (carry grounded players by the
  platform's delta, not by adding velocity — the spec's own warning),
  plus host sync of platform phase. Only if a new map needs them.
- **GAP-30 — no destructible terrain (spec §12).** No per-shape HP,
  no disable-collision-on-destroy, no debris-on-destroy, no map-state
  sync. **Feasibility: OUT OF SCOPE for v3.0** (needs server-
  authoritative destruction + replicated map state). Explosive barrels
  (§18.E) are the cheaper version of this — see GAP-51.
- **GAP-31 — no terrain-material friction (spec §12, optional).**
  All platforms share the engine default; the player's single
  `DECEL := 3400` (`player.gd:12`) applies everywhere. **Feasibility:
  small OPTIONAL touch.** Add a per-platform `friction` value in the
  `MAPS` platform data (default 1.0) and scale `DECEL` by it while
  grounded; the concrete case is ice — see GAP-52 (§18.A).

## 20. Grenade physics (§13) — ⚠️ PARTIAL (GAP-32/33; GAP-11 stands)

- Conforms: gravity 1400 (`grenade.gd:44`, matches player gravity ✅);
  initial velocity `throw_dir * 620 + (0, -260)` (`grenade.gd:31`);
  fuse 2.0 s decremented in `_physics_process` independent of movement
  (`grenade.gd:53-55`) ✅ — a bouncing/rolling grenade still explodes
  on time. Bounce itself is GAP-11 (audit #1, still open).
- **GAP-32 — no air drag (spec §13: `Fd = -k·v`).**
  `grenade.gd:43-44` applies gravity only; no drag constant exists.
  **Fix:** add `const DRAG := 0.15` and
  `velocity *= exp(-DRAG * delta)` after the gravity line — small
  enough that the arc still reads, large enough that long throws fall
  short of a drag-free throw (verify in T-45).
- **GAP-33 — no resting state (spec §13).** The grenade never formally
  rests: `velocity.x *= 0.7` runs every frame on the floor
  (`grenade.gd:46-49`, part of GAP-11) and there is no `_resting`
  flag. **Fix:** with the GAP-11 fix, add
  `if is_on_floor() and velocity.length() < 40.0: _resting = true;
  velocity = Vector2.ZERO` and skip bounce/roll while `_resting`
  (fuse keeps counting — `grenade.gd:53-55` is outside the bounce
  branch, so this is safe).

## 21. Player-to-player collision (§14) — ✅ CONFORMS BY DEFAULT (GAP-34)

- Current behaviour **is the spec's recommended default**:
  `player.tscn` sets `collision_layer = 2, collision_mask = 1`, so
  players pass through each other; bullets still hit
  (`bullet.gd:124-136`), explosions still damage
  (`game.gd:2137-2164`), knockback still applies (`player.gd:765`).
  No separation/impulse code exists anywhere — correctly, since
  blocking is off. ✅
- **GAP-34 — the choice is hardcoded, not configurable (Low).**
  Spec recommends `PLAYER_COLLISION_ENABLED = False`,
  `PLAYER_DAMAGE_COLLISION = True`, `PLAYER_EXPLOSION_COLLISION =
  True` and testing both modes before choosing. **Fix:** add the
  three constants in `player.gd` (or `game_data.gd`) with those
  defaults; gate the existing pass-through on them. Only implement
  the circle-separation + impulse branch (`O = r1+r2-d`,
  `J = -(1+e)(Vr·N)/(1/m1+1/m2)`) if the blocking mode is ever
  enabled — test both first (T-52).

## 22. Weapon pickups (§15) — ⚠️ PARTIAL (GAP-35/36/37)

- Conforms: trigger (not solid) via `Area2D` layer 16 / mask 2,
  circle radius 22 (`pickup.gd:26-30`); host-only collection
  (`pickup.gd:60-68`, `player.gd:780-788` `give_pickup` rejects
  non-host senders) ✅; bob animation
  `position.y = _base_y + sin(_bob_t * 3.0) * 6.0` (`pickup.gd:47-49`)
  — amplitude 6, ω 3.0 rad/s (spec's 8 / 2.0 are examples, not
  requirements) ✅, and the `Area2D` itself bobs so the collection
  area follows the visual ✅.
- **GAP-35 — no rotation (Low, cosmetic).** `pickup.gd` has bob only;
  no `θ(t) = θ0 + ωt`. **Fix:** in `pickup.gd:_process`, add
  `rotation = 0.12 * sin(_bob_t * 1.5)` (gentle sway, not full spin —
  full spin would make the label unreadable).
- **GAP-36 — no weapon drop (spec §15).** Switching weapon
  (`player.gd:631-640`) and dying/respawning (`player.gd:815-849`,
  `_owned_extra.clear()`) never drop anything; no `V_drop =
  V_player + V_throw`, no gravity, no settle. **Feasibility: OUT OF
  SCOPE unless the design wants it.** If added: spawn a `pickup`
  with initial velocity, gravity + floor settle, then re-enable its
  trigger; decide whether the rifle/pistol (starting loadout) are
  droppable — recommend they are not.
- **GAP-37 — respawn is a global timer, not per-pickup (Medium).**
  `game.gd:1885-1898` `_update_pickup_spawn`: host-only, one global
  `_pickup_timer`, spawns one random pickup every 14 s if fewer than
  3 exist, at a random spot from `MAPS[map_id]["pickups"]`, random
  kind. Three concrete problems: (a) **no pickups at match start** —
  the timer starts at 0, so the map is empty for the first 14 s
  (`spawn_pickup_remote` is called from nowhere else); (b) pickups
  self-despawn after 20 s (`pickup.gd:50-55`, `_life`) with no
  per-spot timer restarting; (c) no runtime validity re-check of the
  spot (spots are static map data — currently covered only by the
  map-load test T-39). **Fix:** spawn 3 pickups at match start from
  distinct spots; replace the global timer with a per-spot timer
  (14 s per collected/despawned spot); keep the 20 s lifetime only
  if the per-spot timer restarts on despawn.

## 23. Firing rate & ammunition (§16) — ⚠️ PARTIAL (GAP-38/39/40/41)

- Conforms: time-based, never per-frame. `_fire_cooldown -= delta`
  in `_physics_process` (`player.gd:477`), fire only when
  `_want_fire and _fire_cooldown <= 0.0` (`player.gd:489`), cooldown
  set to `w["rate"]` per shot (`player.gd:572`). `rate` is seconds
  between shots, so RPM = 60/rate (rifle 0.13 → 7.7/s, SMG 0.07 →
  14.3/s, pistol 0.22 → 4.5/s). Host-side validation enforces 0.75×
  rate + ammo mirror (`shooting_sync.gd:29-56`) ✅. Semi-auto edge
  via `fire_button.gd` press edge + peek/consume (`player.gd:385-391,
  489-504`) ✅. Auto reload on empty mag (`player.gd:569-571,
  591-592`), manual reload (`start_reload`, `player.gd:599-605`,
  full-mag guard), reload progress for HUD
  (`reload_progress`, `player.gd:608-612`) ✅.
- **GAP-38 — no burst mode (spec §16).** No `burst` field in
  `weapons.gd`, no burst counter/timer in `player.gd`. **Fix (only if
  a burst weapon is added):** add `"burst": 3, "burst_interval": 0.08,
  "burst_delay": 0.3` to the weapon table and `_burst_left /
  _burst_timer` state in `_apply_aim_and_fire`. Otherwise mark out of
  scope — no current weapon uses burst.
- **GAP-39 — no reserve ammo (Medium, design decision).** Only
  `mag_ammo` exists (`player.gd:72`); reload always refills to full
  (`player.gd:483`, `mag_ammo = WEAPONS[weapon]["mag"]`), and
  switching weapon also grants a full mag (`player.gd:638`).
  Effective reserve is infinite. **Fix (if the design wants scarcity):**
  add `reserve_ammo: Dictionary` per owned weapon, reload transfers
  `min(mag_size - mag_ammo, reserve)`, HUD shows `mag/reserve`,
  pickups refill reserve. **Or** document infinite reserve as the
  deliberate arcade choice — either way, write it down; right now it
  is accidental.
- **GAP-40 — no recoil accumulation (spec §16: `R_n = R_0 + n·K`).**
  Each shot applies a single impulse `velocity -= dir * recoil`
  (`player.gd:588`) and resets `_gun_kick = 1.0` (`player.gd:590`,
  decays 7.0/s, `player.gd:310`). `_shake_trauma` does accumulate
  (capped 1.0, decays 1.8/s, `player.gd:596,309`) but aim/velocity
  recoil does not grow with consecutive shots. **Fix:** add
  `_recoil_accum: float`, `+= K` per shot (K per weapon, e.g. rifle
  0.06, shotgun 0.20), decays `exp(-3.0 * delta)` when not firing;
  apply as extra spread in `_fire` (`spread + _recoil_accum`) and
  extra gun kick. Tune so 5 rapid rifle shots visibly widen the
  group, then it settles (T-53).
- **GAP-41 — no explicit FIRING state (Low, code clarity).** The
  reload machine is a `reloading: bool` + `_reload_timer`
  (`player.gd:76,82,479-483,625-628`); READY → RELOADING → READY
  exists, but FIRING is implicit (`_fire()` is instantaneous).
  **Fix:** add `enum WeaponState { READY, FIRING, RELOADING }`,
  set FIRING for one physics frame inside `_fire()`, keep `reloading`
  as a derived property until the HUD stops reading it.
- Tuning note (not a gap): `weapons.gd:24` rocket is `"auto": true`
  — hold-to-fire rocket at 1.2 s rate. Probably should be semi-auto
  like the sniper; decide in the §20 prototype comparison (§26).

## 24. Damage / health / knockback (§17 FULL) — ❌ GAPS (GAP-42/43/44/45/46)

**Correction:** legs 0.75 / arms 0.85 are now known (spec §17.3);
the "legs unknown" flag from the first handoff is withdrawn.

- Conforms: health 100 / max 100 (`player.gd:68`), clamp at 0
  (`player.gd:724-728`, `health = 0` on death, never negative ✅);
  `is_alive` = `alive` (`player.gd:75`); invulnerability exists with
  a defined duration — spawn protection 2.0 s
  (`SPAWN_PROTECTION`, `player.gd:31`, checked in `take_damage`
  `player.gd:720-721` and `take_explosion_damage` `player.gd:755-757`)
  ✅; server-authoritative health ✅ (`take_damage` /
  `take_explosion_damage` / `add_kill` / `give_pickup` all reject
  non-host senders, `player.gd:712-788`); death once per life ✅
  (`take_damage` returns early `if not alive`, `player.gd:718-719`);
  respawn is atomic in one function ✅ (`_respawn`,
  `player.gd:815-849`: health, fuel, weapon, mag, collision, anim,
  position, velocity all reset together); visuals never apply damage
  ✅ (`spawn_impact_fx`, `_spawn_explosion_fx` are visual-only);
  single-hit projectiles ✅ (`bullet.gd:23,104-105` `_dead` flag —
  a bullet applies damage once then despawns); continuous-hazard
  interval ✅ (lava ticks at 1.0 s, not per frame — see §25).
- **GAP-42 — no damage multipliers at all (High).** `D_final =
  D_base`, always. No `M_distance` (bullet damage is flat at any
  range), no `M_weapon`, no `M_armor`, no `damage_multiplier` field
  (`player.gd:68-75` has no such var), no armor, no regen (both
  optional per §17.1, but the multiplier plumbing is not optional).
  Hit regions are absent (GAP-25), so head 1.5 / torso 1.0 /
  legs 0.75 / arms 0.85 cannot apply. **Fix:** add
  `calculate_damage(base: int, region: String, distance: float,
  weapon: int) -> int` (in `player.gd` or `weapons.gd`) implementing
  `D_final = D_base × M_region × M_distance × M_weapon × M_armor`
  with `M_region = {"head": 1.5, "torso": 1.0, "legs": 0.75,
  "arms": 0.85}`; `M_distance` = 1.0 inside 400 px falling to 0.7 at
  max range (tuning proposal — confirm values in playtest, do not
  treat as final); `M_weapon` per-weapon scalar default 1.0;
  `M_armor` = 1.0 until armor exists. **But note spec §17.3 itself:**
  "for a cartoon shooter, headshots can be optional — do not
  over-complicate collision if the game uses a single body hitbox."
  If GAP-25 is not built, the honest alternative is a deliberate,
  documented deviation: single body hitbox, all regions 1.0×. Do not
  half-build regions.
- **GAP-43 — no unique damage event IDs (spec §17.8, Medium).**
  `take_damage(amount, from_id)` / `take_explosion_damage(pos,
  radius, damage, from_id)` carry no event id; nothing dedupes a
  re-sent or double-routed damage RPC. **Fix:** host keeps
  `_damage_event_seq: int`; every damage RPC carries `event_id`;
  victim keeps `_seen_damage_ids` (last 64) and ignores repeats.
  Cheap, and it closes the "killed twice by one bullet" class
  entirely (the simultaneous-lethal-hits edge already documented in
  `BUGS.md` is adjacent to this).
- **GAP-44 — no death FSM (spec §17.6, Medium).** Death is an
  `alive: bool` + `_respawn_timer: float` (`player.gd:75,83`);
  `take_damage` (`player.gd:724-748`) inlines: health 0 → `alive =
  false`, `deaths += 1`, `_respawn_timer = 3.0`, collision disabled
  (deferred), `die` anim, sounds. What exists: controls disabled
  (early return in `_physics_process`, `player.gd:320-329`), firing
  stopped (fire path only runs when alive), pickup collection stopped
  (`pickup.gd:64` checks `p.alive`). What is missing: no DYING /
  DEAD / RESPAWNING states, no death impulse, no explicit
  state-transition guard. **Fix:** add
  `enum LifeState { ALIVE, DYING, DEAD, RESPAWNING }` + `life_state`;
  DYING = 0.4 s (death anim window, input already locked) → DEAD
  until the timer → RESPAWNING during validation + teleport →
  ALIVE; guard `take_damage` on `life_state == ALIVE` (makes
  "death once per life" structural, not just the `alive` check).
- **GAP-45 — respawn is never validated (High, spec §17.7).**
  `get_spawn_point` (`game.gd:568-571`) returns
  `MAPS[map_id]["spawns"][(player_index-1) % n]` with **no check
  at all** — not for wall/ground/obstacle, not for a nearby enemy,
  not for map bounds. `_respawn` (`player.gd:815-849`) teleports
  blindly; the fall-out respawn (`player.gd:464`) does the same.
  Today this works only because the 10 maps' spawn points were
  hand-checked by the map-load test (T-39) — a spawn camped by an
  enemy or a future map edit breaks it silently. **Fix:** in
  `_respawn`, iterate the spawn list: for each candidate, run an
  overlap test (capsule shape at the point, mask 1, via
  `direct_space_state.intersect_shape`) + enemy proximity check
  (> 150 px from any live enemy) + bounds check; take the first
  valid; if none is valid, defer respawn 0.5 s and retry instead of
  spawning inside a wall.
- **GAP-46 — no per-weapon knockback on the victim (spec §17.5,
  Medium).** The shooter's recoil table exists (`weapons.gd`
  recoil 15–260) but `take_damage` (`player.gd:712-748`) changes
  **no velocity at all** — a sniper hit and a pistol hit push the
  victim identically (zero). Explosion knockback is uniform 550
  regardless of weapon (GAP-23). **Fix:** add `"knockback"` to the
  `weapons.gd` table (proposal, tune in playtest: pistol 40 very
  low, rifle 60 low, SMG 40, shotgun 180 medium, sniper 220
  medium/high, rocket 400 high, grenade 400 high); pass the shot
  direction into `take_damage` (it currently takes only
  `amount, from_id`) and apply
  `velocity += dir * knockback` there. Explosion knockback then
  uses the same path with the rocket/grenade value.
- §17.8 note: knockback never bypassing collision — for the **local**
  player this holds (knockback is a velocity add, resolved by
  `move_and_slide` next frame ✅). For **remote** players it does not
  quite hold: `player.gd:338` sets `position` by lerp directly,
  bypassing collision — cosmetic (rendering only, the owning peer
  simulates correctly), but it is the same root as GAP-16.

## 25. Environmental physics — separate zones (§18 FULL) — ⚠️ PARTIAL (GAP-47/48/49/50/51)

**Supersedes the partial-18 audit from the follow-up handoff.** The full
spec requires environmental physics as **separate configurable zones,
NOT inside the player controller**. Current state: there are no zones at
all — no `Area2D` region, no per-region multiplier, no
`is_on_ice`/`in_water` flag anywhere in `player.gd` / `game.gd`
(grep for water/ice/mud/conveyor/wind finds only `WINDOW_FOCUS_OUT`
false positives). The only environmental system is lava (positional
`Rect2` check, §25 below). Note: the partial-18 draft mentioned
conveyor belts; the full-18 spec **drops conveyors** (replaced by
damage zones §18.E) — no conveyor gap is filed.

- **GAP-47 — no water / buoyancy (§18.A–B, 18.2).** No water region
  in any of the 10 maps; no gravity/drag/speed multipliers, no
  swimming, no splash particles, no per-weapon underwater bullet
  behaviour. **Feasibility: OUT OF SCOPE for v3.0** — no map needs
  water. If a water map is ever added: implement `WaterZone`
  (`Area2D`, layer 6 per §24.D) holding `gravity_mult 0.5,
  accel_mult 0.7, drag 3.0, max_speed_mult 0.65`; when the player
  overlaps it, apply the multipliers in `_apply_movement` and add a
  simplified buoyancy force (upward accel ≈ 700 px/s² while fully
  submerged, scaled by submersion depth — the spec's `F_b = ρ·V·g`
  reduced to a constant, no fluid simulation). Keep the zone out of
  `player.gd` — the zone sets flags the player reads.
- **GAP-48 — no mud (§18.C).** No mud region in any map; no speed /
  accel / jump penalties, no mud particles. **Feasibility: OUT OF
  SCOPE, optional.** Same zone pattern as GAP-47 with lower
  multipliers; only if a map wants a slow patch. Do not change player
  mass (the spec's own warning).
- **GAP-49 — no wind (§18.D).** No wind force, no wind particles, no
  effect on players or bullets/grenades. **Feasibility: OUT OF SCOPE
  for v3.0** — only if a new map needs it. If added: a `WindZone`
  with a constant horizontal accel vector applied in
  `_apply_movement` (players, stronger while airborne) and in
  `grenade.gd` / `bullet.gd` (bullets: small, e.g. 30 px/s² lateral),
  plus drifting particle streaks so the direction is visible.
- **GAP-50 — damage zones: only lava exists (§18.E).** Each zone type
  needs collision + damage interval + knockback + visual warning +
  sound. Present: **lava only** (see §25 lava audit — mostly
  conforms). Absent: electric fields, explosive barrels, poison gas,
  falling rocks. **Fix:** implement **explosive barrels first**
  (GAP-64, §27 — the cheap win, art already exists); electric field
  and poison gas are the same `Area2D` + interval-damage pattern as
  lava and are cheap **if** a map wants them; falling rocks need a
  spawner + gravity + impact — out of scope unless a map needs them.
- **GAP-51 — no ice (§18.A, prototype values given).** Frozen
  Fortress (`game.gd:174`, 2800×1500) has no low-friction area at
  all. **Feasibility: THE OBVIOUS SMALL TOUCH — recommend for v3.0.**
  Implement as a zone (not player-controller code, per the spec):
  `IceZone` (`Area2D`) with the spec's prototype values — ground
  friction 1200, ice friction 100, ice acceleration 500, max speed
  350, air control 0.65. While the player overlaps it, `_apply_movement`
  uses ice friction/accel: releasing the stick slides far, direction
  changes take longer, jumping preserves horizontal momentum (already
  true — no velocity zeroing on jump, `player.gd:415-458`). Verify
  with T-58. This is the same work as GAP-31 (terrain materials) —
  do them together: per-platform/zone friction, ice first.

### Lava audit vs §18.E (Volcanic Cavern already has lava)

`game.gd:786-830` `_update_lava`: server-only, feet point
(`position + (0,20)`) tested against `MAPS[map_id]["lava"]` rects,
20 HP per 1.0 s tick, routed to the victim's owning peer (v2.4 fix),
no kill credit, spawn protection covers fresh spawns, pools are
shallow/flanked by safe platforms so a player can jetpack out ✅.
Deviations from §18.E: (a) damage interval is **1.0 s, not the
spec's 0.5 s example** — same 20 HP/s either way; suggest 0.5 s ×
10 HP for smoother feedback (one-line change, `_lava_cd = 0.5`,
`take_damage(10, 0)`); (b) **no knockback** on lava contact
(spec wants a knockback force per zone — lava should arguably push
the player up/out, currently it only hurts); (c) **no visual
warning / sound beyond the pool art** — the pools are bright orange
and visible, but there is no "you are burning" feedback other than
the hit flash. All three are small; (a) + a burn tick sound are the
cheap fixes. Lava otherwise conforms to §18.E and to §17.4
(interval, not per-frame).

## 26. Camera follow & physics (§19) — ⚠️ PARTIAL (GAP-52/53/54)

What exists (v2.1 camera, `player.gd:142-160, 843-844, 859-863`):

- Smooth follow ✅: `Camera2D` child of the local player,
  `position_smoothing_enabled = true`,
  `position_smoothing_speed = 7.0` (spec suggests ~8.0 — 7.0 is
  close; bump to 8.0 as a one-line tune, not a gap). Engine smoothing
  is frame-rate independent ✅.
- **Hard limits ✅: `cam.limit_left = 0, limit_top = 0,
  limit_right = map_size.x, limit_bottom = map_size.y`** — the
  camera can never show out-of-map area. `reset_smoothing()` on
  respawn (`player.gd:843-844`) so no cross-map swoop ✅.
- Shake exists and is trauma-squared (`_shake_trauma` decays 1.8/s,
  offset = trauma² × 16, `player.gd:309,859-863`), applied on firing
  via `add_shake()` (`player.gd:588-596`) — small and brief ✅ for
  the shooter.
- **GAP-52 — no camera dead zone (spec §19).** The camera is a
  **child of the player**, so it follows every pixel of movement
  (smoothed only). There is no central region the player can move
  in without the camera following. **Fix:** decouple the camera
  from the player node: make it a sibling that follows
  `global_position.lerp(target, 1 - exp(-8.0 * delta))` (the spec's
  exact formula) and only moves the target when the player leaves a
  dead-zone rect (~120×80 px around screen centre). Medium work —
  the camera currently inherits the player's transform for free.
- **GAP-53 — no look-ahead (spec §19).** No offset by movement
  direction or facing; the player is always dead-centre, so a
  sprinting player cannot see what's ahead. **Fix:** with the GAP-52
  decoupling, add `target += Vector2(sign(velocity.x), 0) * 80`
  (or `facing * 80`) lerped in over ~0.3 s; clamp inside the limits.
- **GAP-54 — shake is firing-only; no shake on explosions / damage
  for the victim (spec §19, Low).** `take_damage`
  (`player.gd:712-748`) and `take_explosion_damage`
  (`player.gd:749-767`) never call `add_shake()`; only the shooter
  gets shake from `_fire()`. A rocket exploding next to you is
  silent on the camera. **Fix:** `add_shake(0.25)` in
  `take_damage`, `add_shake(0.5)` in `take_explosion_damage`.
  Keep trauma capped at 1.0 (already is, `player.gd:596`).

## 27. Firing while moving (§20) — ⚠️ PARTIAL (GAP-55/56/57)

- Conforms: separate inputs ✅ (left stick move, right stick aim,
  FIRE button — audit #1 §7); aim independent of movement direction
  ✅ (modulo GAP-08, aim snap on release); muzzle start ✅
  (`player.gd:576`, 52 px from centre vs capsule radius 17 — the
  bullet never spawns inside the player); no immediate self-collision
  ✅ (`bullet.gd:127-131` skips the owner when the ray starts
  inside/behind them); fire rate via cooldown, never per-frame ✅
  (`player.gd:477,489`); projectiles expire ✅ (`life`, `bullet.gd`
  `141-143`); projectile count is bounded in practice (pool 96 +
  one-off allocation on exhaustion, each one-off freed on despawn —
  max alive ≈ fire-rate × lifetime, not unbounded ✅, but see
  GAP-67 for the budget shortfall); recoil as
  `velocity -= dir * force` ✅ (`player.gd:588`, the spec's exact
  `apply_recoil` formula) + muzzle flash (`player.gd:615-621`) +
  sound + per-weapon shake ✅. Bullet direction from aim angle
  (`player.gd:575-576`) is equivalent to the spec's
  `(aim_position - muzzle).normalized()` for a direction-based aim
  system (there is no aim *point* — the aim stick gives a direction,
  not a screen position).
- **GAP-55 — no velocity inheritance (spec §20.C, Medium).**
  Bullet velocity is exactly `direction * bullet_speed`
  (`bullet.gd:104-109`); the player's velocity contributes nothing.
  Spec wants `bullet.velocity = direction * bullet_speed +
  player.velocity * 0.15`. **Fix:** `bullet.gd` must store a
  `velocity: Vector2` instead of scalar `speed` + `direction`
  (step = `velocity * delta`, rotation from `velocity.angle()`),
  and `player.gd:583` passes `dir * speed + velocity * 0.15` into
  `spawn_bullet`. Effect is subtle at 0.15 (a 330 px/s sprint adds
  ~50 px/s) but it makes leading shots and jump-shots feel right;
  verify with T-60. Note the host validation in `shooting_sync.gd`
  is rate/ammo only, so inheritance needs no server change.
- **GAP-56 — prototype values differ from `weapons.gd` (comparison
  table — do NOT blindly adopt).** Spec §20.C values are "starting
  values for balancing"; §24.C gives a second, slightly different
  set (see §29). Current table (`weapons.gd:19-26`) vs §20 prototype:

  | Weapon | Current | §20 prototype | Verdict |
  |---|---|---|---|
  | Bullet speed (generic) | rifle 1100, SMG 1000, pistol 950, shotgun 900, sniper 1600, rocket 700 | 900 | **Keep current.** Per-weapon speeds are the point; flattening to 900 would make the sniper feel wrong. |
  | Rifle rate | 0.13 s → 7.7/s | 8/s (0.125 s) | **Adopt** — one-line change, 0.13 → 0.125. Indistinguishable in play; aligns the table. |
  | Pistol rate | 0.22 s → 4.5/s | 3/s (0.333 s) | **Decide.** Current pistol is a fast sidearm; 3/s makes it deliberate. Recommend keeping 0.22 unless the pistol feels spammy in playtest. |
  | Shotgun pellets | 6 | 6 (§20) — **but §9 says 7** | **Spec conflict.** §9's 7 with fixed offsets is the detailed spec; §20's 6 matches the current code. Recommend 7 (GAP-20). Flag for the user to confirm. |
  | Rocket speed | 700 | 450 | **Decide.** 450 makes rockets dodgeable/heavy; 700 is current. Recommend 450 **only if** rocket gravity (GAP-10) is also added — slow + arcing reads as "heavy". Slow + straight reads as broken. |
  | Inheritance | 0 (absent) | 0.15 | **Adopt** (GAP-55). |

- **GAP-57 — no flamethrower (spec §20.E, out of scope).** The
  spec's weapon list includes a flamethrower (short-range
  particle/projectile stream). No such weapon exists; no stream /
  cone-damage system exists. **Feasibility: OUT OF SCOPE for v3.0**
  — a new weapon type with a different damage model (cone + DoT
  ticks). Only if a post-v3 weapon pass happens.
- Six common shooting bugs (§20.F) — checked individually: (1)
  spawn inside player ✅ no (muzzle 52 px out); (2) immediate
  self-collision ✅ no (owner skip); (3) aim tied to movement
  ⚠️ GAP-08 (audit #1, still open); (4) per-frame fire rate ✅ no
  (cooldown); (5) unlimited projectiles ✅ no (pool + lifetime);
  (6) bullets never expiring ✅ no (life expiry). No new gap — see
  T-62.

## 28. Multiplayer physics sync (§21) — ⚠️ PARTIAL (GAP-58/59/60/61; GAP-15/16 reconciled)

**Reconciliation with audit #1 GAP-15 (peer-authoritative positions)
and GAP-16 (lerp-only smoothing):** the spec's full model is
server-authoritative positions + client prediction + server
reconciliation with input replay + 100 ms interpolation buffer +
lag compensation + host migration. What is realistic for LAN v3.0:

- **Already conforms:** server-authoritative health / damage /
  bullets / kills / pickups / score / timer / result ✅ (audit #1
  §12); physics 60 ticks/s ✅ (`project.godot:60`); UDP transport ✅
  (ENet, `discovery.gd`); reliable messages for match events ✅
  (RPCs are reliable by default; discovery packets are versioned,
  `discovery.gd:16,190`); LAN flow host → discovery/IP → lobby →
  start ✅; join timeout 8 s ✅ (`game.gd:11-12`); disconnect
  handling ✅ (`_on_peer_disconnected`, reconnect IP saved,
  `game.gd:959-980`); 2–8 players ✅ (room max 8, cap 12,
  `game.gd:30,412`); NEVER trust clients for damage/kills/score/
  inventory ✅ (host validation, `shooting_sync.gd`, `player.gd`
  sender checks).
- **Add for v3.0:** the interpolation buffer (GAP-16 — 100 ms,
  2-snapshot buffer, the spec's §21.D/F target). It is contained
  work in `player.gd:336-340` and is the highest-value sync item.
- **Document as the LAN design decision (do NOT rebuild):**
  peer-authoritative movement (GAP-15). Full input-replay
  reconciliation would require the host to simulate all players,
  clients to log + replay inputs, and a rewind path — a multi-day
  rebuild for a trusted-LAN game where the anti-cheat already covers
  shooting/ammo. The local peer *does* simulate its own input
  immediately at 60 Hz (`player.gd:324-334`), which is de-facto
  client-side prediction; what is missing is the server correction
  step, and on a LAN (< 5 ms) the correction would almost always
  be ~0. Record the decision in `BUGS.md`/README so it is a
  decision, not an accident.
- **GAP-58 — no lag compensation (spec §21.E, out of scope).** No
  position history, no firing-time estimation, no rewind validation;
  the host validates hits against its *current* positions
  (`bullet.gd:160-196`). **Feasibility: OUT OF SCOPE for LAN v3.0**
  — LAN latency is ~1–5 ms, so the rewind window would buy
  almost nothing; the host's current-position check is the
  correct simplification. Revisit only if WAN play is ever added.
- **GAP-59 — no host migration (spec §21.G).** If the host leaves,
  the match ends; there is no ownership transfer, no new-host
  election. **Feasibility: OUT OF SCOPE for v3.0.** ENet
  peer-hosted migration is a large feature (state transfer +
  re-election + re-sync). Mitigation in place: reconnect IP is
  saved and the menu offers reconnect (`main.gd:136`,
  `game.gd:980`). Document "host leaves = match ends" in the
  lobby so players are not surprised.
- **GAP-60 — snapshot rate is at the low end and there is no input
  stream (spec §21.F, Low).** `replication_interval = 0.05`
  (`player.gd:302`) = 20 snapshots/s — the bottom of the spec's
  20–30/s target. Input updates are 60/s *locally* but no input
  messages are ever sent to the server (peer-authoritative design).
  **Fix:** raise the synchronizer to `0.033` (30/s) — free on LAN;
  leave the input stream absent by design (see GAP-15 decision).
- **GAP-61 — no version check on the game connection itself
  (spec §21.G, Low).** Discovery packets are versioned
  (`discovery.gd:172,190`, old builds ignored ✅), but the ENet
  join itself has no version handshake — a mismatched client can
  join and desync silently (different weapon tables, different
  maps). **Fix:** add a `BUILD_VERSION` const in `game_data.gd`,
  send it in the join RPC, and have the host reject (with a
  readable message) on mismatch. Small, do it for v3.0.

## 29. Advanced interactions (§22) — ❌ MOSTLY ABSENT (GAP-62/63/64/65/66/67)

Feasibility per item is the point of this section: moving platforms,
destructibles, ropes and bounce pads **do not exist** in the current
game (grep for moving/destructible/rope/grapple/bounce/spring/
barrel-behaviour finds only the "barrels" decor *texture*,
`game.gd:46`, which is a solid crate by another name).

- **GAP-62 — no moving platforms (§22.A).** No horizontal / vertical
  / rotating / falling / timed / elevator platform; no standing
  detection, no carry, no platform sync. **Feasibility: OUT OF SCOPE
  for v3.0.** This is the same work as GAP-29, now with the full
  type list: the carry rule (add the platform's *displacement* to
  the grounded player, never its velocity — the spec's "prevent
  slipping through" + "no runaway acceleration" warning) plus host
  sync of platform phase is a multi-hour feature with real
  desync risk. Only if a new map is designed around one.
- **GAP-63 — no destructible environment (§22.B).** No object has
  an ID / health / material / resistance / destruction animation /
  sound / debris / respawn config; nothing in the game can be
  damaged except players. **Feasibility: OUT OF SCOPE for v3.0
  except barrels (GAP-64).** Full destructibles need per-shape HP,
  server-authorised destruction and replicated map state (same as
  GAP-30). Wood/glass/stone/metal/weak-wall tiers are a post-v3
  system, not a one-night add.
- **GAP-64 — no explosive barrels (§22.C) — ⭐ CHEAP WIN, recommend
  for v3.0.** The art already exists: `"barrels"` decor is on every
  map (`game.gd:92,118,171,...`) and is already solid cover
  (`SOLID_DECOR_KINDS`, `game.gd:623`). What is missing is only the
  behaviour: HP + `take_damage` on bullet hit + explosion sequence
  on death. **Fix:** add a `Barrel` node (or a flag on solid decor)
  with `max_health 100`, damageable by the bullet raycast
  (raycast mask already hits layer 1 — the barrel must be
  distinguishable from a wall, e.g. metadata on the shape), on
  destroy call the existing `request_explosion`
  (`game.gd:2137`) with `D = Dmax × max(0, 1 - d/R)` — note this is
  the **linear** curve, not the smooth curve recommended in GAP-22;
  pick one curve for all explosions and use it in both places —
  plus the LOS check from GAP-12 (a wall must block a barrel blast
  too), radial knockback (GAP-23), particles + audio (reuse
  `_spawn_explosion_fx`, `game.gd:2165`), and host-authorised
  replication (host decides the destruction, clients see the FX).
  Estimated: the smallest new system in this audit — one node type
  + one damage path + reuse of three existing systems.
- **GAP-65 — no rope / grappling (§22.D).** No attachment points,
  no max length, no tension, no detachment, no rope collision, no
  sync. **Feasibility: OUT OF SCOPE.** A rope is a constraint
  solver (Verlet or distance-joint chain) plus a new movement mode
  plus sync — the largest item in §22 and the least like the reference game.
  Do not attempt in v3.0.
- **GAP-66 — no bounce pads / springs (§22.E) — ⭐ CHEAP WIN,
  recommend for v3.0.** Nothing applies upward velocity on touch.
  **Fix:** add a `BouncePad` (`Area2D`, layer 8 trigger per §24.D):
  on `body_entered`, if the body is a player, set
  `player.velocity.y = -750` (the spec's value), play bounce
  animation + particles + sound, and set a per-player
  `_bounce_cooldown` (0.3 s) so the same contact cannot retrigger
  every physics frame while the player is still overlapping the pad.
  One node type, no sync beyond the player's own replicated
  velocity (which already syncs). Place 1–2 per map where vertical
  flow needs help.
- **GAP-67 — projectile budget is below the spec's (§22.G + §24.E).**
  Pool is 96 shared bullets (`game.gd:533`,
  `bullet_pool.gd:14`); at 8 players that is **12 per player**, below
  the spec's 16–32 projectiles/player budget. Worst case: 8 players
  full-auto SMG (14.3 shots/s × 1.0 s life ≈ 14 alive each) = ~114
  alive > 96 → overflow allocates one-offs (`bullet_pool.gd:41-46`,
  freed on despawn, so not a leak — but it defeats the pool under
  exactly the heavy-fire conditions the pool exists for). The rest
  of §22.G conforms: static collision shapes for map geometry ✅
  (`game.gd:627-677`), simplified shapes ✅ (rects/capsule/circles),
  server-controlled destruction events ✅ (host-authoritative
  damage; no destruction events exist to control yet). **Fix:**
  raise the pool to 160 (`BulletPool.new(..., 160)`) — memory cost
  is trivial (64 more tiny nodes) — and log `active_count()` in
  the smoke test so overflow is visible. Distance-based simulation
  management (spec §22.G) is not implemented and not needed at
  this scale — record as not-applicable, not a gap.
- Death physics (§22.F) — mostly conforms, no new gap: input +
  firing disabled on death ✅ (`player.gd:320-329, 724-748`), death
  animation + sound ✅, respawn timer ✅ (3.0 s), state restored on
  respawn ✅ (`_respawn`). Missing: death impulse (already filed
  as part of GAP-44), ragdoll (optional per spec — **out of scope**,
  the `die` animation is the cartoon equivalent), body
  removal/recycling (the dead player's node persists with collision
  disabled and gun/ring/HP hidden — acceptable; a body that
  lingers as a visible corpse is a design choice, not a bug).

## 30. Architecture & module design (§23) — ⚠️ PARTIAL (GAP-68/69)

Verdict per sub-item — the honest picture is that the code works but
is organised as a prototype that grew, not as the spec's system split.

- **§23.A — separate systems: ❌ NOT DONE.** One `game.gd` (~4,400
  lines, 159 KB) holds match management + arena building + networking
  + HUD + input routing + all four headless test harnesses; one
  `player.gd` (902 lines) holds movement + health + weapons +
  camera + animation + sync. There is no Physics System, no
  Environment System, no Camera System as files. Partial credit:
  the *data* is already separated (`weapons.gd` table,
  `shooting_sync.gd` validation, `bullet_pool.gd`,
  `game_data.gd` settings, `audio.gd`) — the split started at the
  edges, not the core.
- **§23.B — folder structure: ⚠️ HALF.** `assets/` exists with
  sensible subfolders (characters, weapons, maps/effects, tiles,
  backgrounds, headgear, items, jungle, thumbs) ✅. But everything
  else is flat in the project root: all 14 `.gd` files and all
  `.tscn` files sit together; there are **no** `scenes/`,
  `scripts/`, `resources/` or `tests/` folders.
- **§23.C — player scene structure: ⚠️ HALF.** The player
  (`player.tscn` + `player.gd:169-302`) builds its
  `CollisionShape2D` (capsule), `AnimatedSprite2D`, `Camera2D`,
  gun + muzzle sprites in code, not as a composed scene — but there
  is no `WeaponHolder`/`Muzzle` `Marker2D` (muzzle is computed
  arithmetically, `player.gd:576`), and no `HealthComponent` /
  `MovementComponent` / `AimComponent` / `AnimationController` /
  `AudioComponent` nodes: health, movement, aim, animation and
  audio are all methods/vars on the one player script, and the
  weapon system reaches into the movement script's state directly
  (e.g. `_fire` writes `velocity`, `player.gd:588`) instead of
  requesting the aim direction through an interface.
- **§23.D — physics update order: ⚠️ MOSTLY, wrong in one place.**
  The local tick (`player.gd:306-340`) runs read input →
  movement/accel/friction/gravity (`_apply_movement`) →
  weapons/projectiles (`_apply_aim_and_fire`) in the spec's order
  ✅. But damage/interaction events are **not** processed in the
  tick — they arrive as RPCs at arbitrary times (`take_damage`,
  `take_explosion_damage`, `give_pickup`) — and authoritative
  multiplayer state is replicated by the synchronizer on its own
  0.05 s clock, not at the end of the tick. For a LAN game this is
  acceptable, but it is not the spec's order.
- **GAP-68 — no systems split; `game.gd` is a 4,400-line monolith
  (High for maintainability, Low for v3.0 delivery).** **Feasibility:
  a full component split is OUT OF SCOPE for one night** — moving
  `game.gd`'s arena/HUD/network/test code into systems while the
  v2.5 builder is editing the same file is how regressions happen.
  **Realistic for v3.0:** (1) extract a `physics_config.gd`
  (constants resource — the §24 values + ice/wind zone data) so
  tuning stops meaning edits to `player.gd`; (2) move the four
  test harnesses out of `game.gd` into `tests/` (they are ~1,500
  lines of the shipped file); (3) create the `scenes/` +
  `scripts/` folders and move new systems there (zones, barrels,
  bounce pads) so new code follows the layout even if old code
  does not move yet. Full `HealthComponent`/`MovementComponent`
  split is a post-v3 refactor.
- **GAP-69 — physics and rendering are mixed (spec §23.E, Medium).**
  `player.gd` has **no `_process` at all**: `_update_visuals`
  (sprite scale, gun rotation/kick, camera offset/shake, hit flash,
  HP bar) is called from `_physics_process`
  (`player.gd:307, 847-930`), so visuals run at the physics tick,
  not the render frame. Conversely `game.gd:_process`
  (`game.gd:1675`) samples touch state (GAP-18) and drives HUD.
  `pickup.gd:52` bobbing is correctly in `_process` ✅. **Fix:**
  move `_update_visuals(delta)` into a new `player.gd:_process`
  (visual-only: sprite/gun/camera offset/HP bar), keep
  `_physics_process` for simulation only, and never write
  `position`/`velocity` from `_process` (nothing currently does —
  keep it that way). Also note the spec's interpolation point:
  remote players are rendered from lerped `sync_position`
  (`player.gd:338`) — once the GAP-16 buffer lands, that lerp
  becomes real interpolation and this gap's rendering half is
  closed. Fixed 60 Hz physics ✅ (`project.godot:60`) is already
  met.

## 31. Configuration & starting values (§24) — ⚠️ PARTIAL (GAP-70/71)

The spec's values are "prototype defaults — tune to feel", so each
row below gives current code value → spec value → adopt-or-not.

### §24.A Player movement — current (`player.gd:10-28`) vs spec

| Value | Current | Spec §24.A | Verdict |
|---|---|---|---|
| Max horizontal speed | `SPEED 330` | 350 | **Adopt.** 330 → 350, trivial, matches the air-speed target too. |
| Ground accel | `ACCEL 2600` | 1800 | **Do NOT adopt blindly.** 2600 is already tuned with GAP-02's ground/air split pending; 1800 would feel sluggish after 2600. Keep 2600 ground / add 900–1500 air (GAP-02). |
| Air accel | (none — same 2600) | 900 | **Adopt via GAP-02** (new constant, ~900–1500). |
| Ground friction | `DECEL 3400` (linear) | 1200 (friction) | **Different model, not a number swap.** Spec friction is a decel rate; current DECEL 3400 is already stronger. Keep, and add the exponential drag from GAP-03. |
| Gravity | `GRAVITY 1400` | 1400 | ✅ **Identical — conforms.** |
| Jump velocity | `JUMP_VELOCITY -660` | -550 | **Do NOT adopt.** -660 gives apex ≈ 155 px (measured, audit #1 §3); -550 gives ≈ 108 px and would break the 170 px platform gaps. Keep -660. |
| Max fall speed | `MAX_FALL 950` | 1000 | **Adopt** (950 → 1000, trivial). Fast-fall cap 1300 stays. |
| Air control mult | (none) | 0.65 | **Adopt via GAP-02** (air accel ≈ 0.65 × ground is one way to express it; 2600 × 0.65 ≈ 1690 — use ~1500, tune in playtest). |

### §24.B Jetpack — current (`player.gd:14-24`) vs spec

| Value | Current | Spec §24.B | Verdict |
|---|---|---|---|
| Upward force | `JET_ACCEL 1900` | 1800 | **Keep 1900** (net −500 vs gravity; spec net is −400 — current is already the livelier one; audit #1 suggested 2200 if floaty). |
| Max up speed | `MAX_JET_RISE 430` | 450 | **Adopt** (430 → 450, trivial). |
| Fuel capacity | `FUEL_MAX 100` | 100 | ✅ **Identical.** |
| Fuel consumption | `FUEL_DRAIN 45/s` | 25/s | **Decide.** 45/s = 2.2 s of thrust; 25/s = 4 s. Current is the reference-like short burst; spec is a longer hover. Recommend keeping 45/s — doubling flight time changes every map's vertical balance. |
| Fuel recovery | `FUEL_REFILL 70/s` | 15/s | **Do NOT adopt as-is.** 15/s = 6.7 s to refill; current 70/s = 1.4 s. But GAP-05 (regen delay + air regen) must be fixed first; after that, retune recovery to ~35–70/s, not 15/s. |
| Activation delay | (none — instant) | 0.1 s | **Adopt if jetpack feels twitchy** (GAP-05 fix is the place: start the 0.6 s regen delay timer and a 0.1 s thrust delay together). Low priority. |

### §24.C Weapons — current (`weapons.gd:19-26`) vs spec (also §20.C)

| Weapon | Current (speed / rate / life) | Spec §24.C | Verdict |
|---|---|---|---|
| Pistol | 950 / 0.22 s (4.5/s) / 0.9 s | 800 / 3/s / 2 s | Speed: keep 950 (fast sidearm). Rate: keep 0.22 (see GAP-56). **Life: adopt 2 s? No — life IS range** (950 × 0.9 = 855 px; 800 × 2 = 1600 px). Doubling pistol life doubles its effective range; that is a balance change, not a bug fix. Keep 0.9 s unless the pistol feels stubby. |
| Rifle | 1100 / 0.13 s (7.7/s) / 1.2 s | 950 / 8/s / 2 s | Rate: adopt 0.125 s (GAP-56). Speed: keep 1100. Life: 1100 × 1.2 = 1320 px already; 2 s would be 2200 px (cross-map). Keep. |
| Rocket | 700 / 1.2 s (0.83/s) / 1.4 s | 450 / 1/s / 4 s | Rate: adopt ~1.0 s. Speed: 450 only with gravity (GAP-56). Life: 700 × 1.4 = 980 px; 450 × 4 = 1800 px — the spec's rocket flies far and slow. If speed drops to 450, life must rise (~2.5–3 s) or rockets will fizzle mid-map. Change speed + life together or neither. |

- **GAP-70 — config drift: no single source of truth for tuning
  values (Medium).** Movement constants live in `player.gd:10-32`,
  weapon values in `weapons.gd`, fuel in `player.gd`, spawn/match
  values in `game.gd`/`game_data.gd` — there is no config file to
  diff against §24. **Fix:** create `physics_config.gd`
  (or a `physics.tres` resource) holding the §24 table with the
  "adopt / keep / decide" verdicts above recorded as comments, and
  have `player.gd` / `weapons.gd` read from it. This is GAP-68's
  step (1) — the cheap half of the architecture work.
- **GAP-71 — collision layer scheme does not match §24.D (Medium).**
  Spec: 1 world, 2 player, 3 enemy, 4 projectiles, 5 destructible,
  6 hazards, 7 pickups, 8 triggers. Actual: 1 world, 2 player,
  **8 projectile** (bullet layer 8, `bullet.gd:34`), **16 pickup**
  (`pickup.gd:26`), no enemy layer (no enemies — correct, it is
  PvP), no destructible/hazard/trigger layers. The bullet raycast
  mask 3 (world + players) is *numerically* consistent with the
  current layers but would be **wrong** under the spec scheme
  (mask 3 = world + player only if projectiles are layer 4, not 8).
  **Fix (do it with GAP-64/66, not alone):** renumber to the spec
  scheme — projectile layer 8 → 4, pickup layer 16 → 7, new:
  destructible 5, hazard 6, trigger 8 (bounce pads, zones);
  update the raycast mask in `bullet.gd:113` (world 1 + player 2 =
  mask 3 — unchanged numerically, but re-derive it from named
  constants so the next renumber does not silently break it),
  `player.tscn` (layer 2, mask 1 — unchanged), `pickup.gd:26-27`
  (layer 7, mask 2), and name all layers in `project.godot`
  (`layer_names/2d_physics/layer_1="world"` …). Do **not** renumber
  without also moving the barrel/bounce-pad code — a lone renumber
  is pure risk.
- §24.E performance targets: 60 ticks/s ✅, 60 FPS (untested on
  device — target, not a measurement), 2–8 players ✅ (room max 8),
  16–32 projectiles/player ⚠️ **below budget** (GAP-67: 96 pool =
  12/player at 8 players). Benchmark note: no FPS measurement
  exists in the repo — the smoke test logs no frame time. Add a
  10-second FPS sample to the smoke test before claiming 60 FPS.

## 32. Common physics bugs — prevention check (§25)

One row per spec bug: prevented already (with refs) or a gap.

| Spec bug | Status | Evidence |
|---|---|---|
| Falling through platforms | ✅ **Prevented.** | Player is `CharacterBody2D` with a capsule (`player.gd:169-176`), `floor_snap_length = 4.0`; max fall step ≈ 22 px/tick < 48 px platforms (audit #1 §3); bullets use the swept raycast (`bullet.gd:104-122`). Grenade is the exception — GAP-27 (no CCD, uncapped fall). |
| Stuck inside walls | ⚠️ **Half prevented.** | Map geometry IS validated statically: `--collision-test` (`game.gd:3009-3031`) checks every spawn/pickup against every solid rect and every platform's reachability, and `MAP_AUDIT.md` records the map-level review (47/47 map loads PASS, audit #1 T-39). But there is **no runtime recovery**: a player who does get stuck (bad spawn, knockback into a seam) has no unstuck path except dying. **GAP-72 — no stuck-player recovery (Low).** **Fix:** in `player.gd:_physics_process`, if the player has not moved > 2 px in 3 s while holding a move input and is not on a floor edge, teleport to the nearest valid spawn (reuse the GAP-45 validator) and log it. Cheap insurance; verify with T-72. |
| Bullets passing through players | ✅ **Prevented.** | Swept raycast (`bullet.gd:104-122`) + host-side hit validation (`bullet.gd:160-196`, `shooting_sync.gd:29-56`). The owner-overlap skip (`bullet.gd:127-131`) is the deliberate exception. |
| Multiplayer jitter | ⚠️ **Partial — GAP-16.** | Fixed 60 Hz updates ✅ + de-facto local prediction ✅ (audit #1 §12), but lerp-only remote smoothing, no interpolation buffer, no reconciliation. The GAP-16 buffer is the fix; lag compensation is out of scope (GAP-58). |
| Infinite bullet generation | ✅ **Prevented.** | Cooldowns (`player.gd:477,572`) + magazine limits (`player.gd:569-574`) + host ammo mirror (`shooting_sync.gd`) + pooling (`bullet_pool.gd`). Pool budget is the only hole — GAP-67 (96 shared < 16–32/player at 8 players). |
| Optimisation | ✅ **Mostly.** | Simplified collision geometry ✅ (rects / capsule / circles only); static shapes for map geometry ✅ (`game.gd:627-677`); resource cleanup ✅ (pooled bullets return to the pool, FX sprites `queue_free` after their tween, one-off bullets freed). Spatial partitioning: **not applicable** — Godot's physics server does broadphase internally; no manual partitioning is needed at this object count. No FPS/memory measurement exists — GAP-73 (§33). |

## 33. QA & testing — compliance checklist (§26)

Automated tests that exist today (all headless harnesses inside
`game.gd`, run with `xvfb-run -a godot --path . --auto-host --<flag>`):

| Harness | Flag | What it covers | Last known result |
|---|---|---|---|
| Smoke test | `--smoke-test` | 19 phases: movement, jump, jetpack, aim, shooting, grenade, pickup, damage, respawn | 19/19 PASS (v2.3) |
| Joystick acceptance | `--joy-test` | 21 checks incl. canvas-space fix QA-029 | 21/21 PASS (v2.2) |
| Fire-button | `--fire-test` | 25 checks incl. touch ownership QA-023 | 25/25 PASS (v2.4) |
| Multiplayer/net | `--net-test` | 11 checks + menu-network 6/6 + full flow 10/10 | 11/11, 6/6, 10/10 PASS (v2.4) |
| Scale/coordinate | `--scale-test` | Stick math at 1280×720 / 1920×1080 | PASS (QA-029) |
| Collision / map-load | `--collision-test` | 47 checks: all 10 maps, platforms, spawns, pickups vs solid rects | 47/47 PASS (v2.3) |

Spec §26 coverage vs reality:

- Movement / jumping / jetpack / collisions / weapons / ammo /
  explosions: ✅ covered (harnesses above + tests T-01…T-64 in
  this audit).
- Multiplayer sync / LAN connections / disconnections: ⚠️
  **half** — `--net-test` covers code paths headless (sandbox
  blocks UDP); the real two-phone check is the user's job with
  the README two-device guide. No automated disconnect/reconnect
  test exists (T-74 adds a manual procedure).
- Performance / memory / crash stability: ❌ **missing.
  GAP-73 — no performance, memory or crash-stability tests
  (Medium).** No FPS sample, no memory measurement, no soak test
  anywhere in the repo; §24.E's 60 FPS target is currently
  unmeasured. **Fix:** add a `--perf-test` harness: 10-minute
  headless soak (8 simulated players, full-auto fire, grenades,
  explosions), sampling FPS + `OS.get_static_memory_usage()` every
  10 s and failing on any script error or FPS < 55 sustained.
  Run it before every delivery; record in `BUGS.md`.
- Consistent bug-report format: ✅ exists — `BUGS.md` with
  numbered QA-xxx entries (cause, fix, verification). Keep using
  it; new entries for this audit's gaps go there, not in a new file.
- **Delivery gate (spec: "never release with critical crashes or
  game-breaking multiplayer defects"):** all of §H regression
  (T-34…T-39) at previous pass counts + all new tests T-40…T-75
  green or explicitly waived with a reason + 0 script errors on a
  clean run + the user's two-phone LAN check (host + join on real
  Wi-Fi) + `--perf-test` green. See the final checklist in §35.

## 34. Technology & architecture — compliance (§27)

| Spec item | Status |
|---|---|
| Godot 4 | ✅ Godot 4.3 in use (v3.0 brief: upgrade to latest 4.7 — separate task, not this audit). |
| GDScript | ✅ All game code is GDScript. |
| Godot Physics 2D | ✅ Default physics engine; `CharacterBody2D` players, `move_and_slide`, raycasts. |
| ENet / Godot Multiplayer API | ✅ ENet via `SceneMultiplayer`; `MultiplayerSynchronizer` for state, RPCs for events. |
| TileMapLayer | ❌ **Not used — GAP-74 (Low, deliberate deviation).** Maps are built in code: `Rect2` platform lists in `MAPS` (`game.gd:71-334`) + `_draw_tiles` (`game.gd:831+`). **Verdict: does not matter for v3.0.** TileMapLayer helps when maps are tile-authored in the editor; these maps are data-driven rects with hand-placed decor, and the `--collision-test` validates them statically. Do not convert 10 maps to TileMapLayer for the sake of the checklist — record the deviation. |
| AnimatedSprite2D | ✅ Player sprite (`player.gd:179-243`, `_make_sprite_frames`). |
| Git | ❌ **Not in use — GAP-75 (Medium).** No `.git` folder exists in `~/workspace/sky-raiders/` (checked 2026-11-19 ~01:37 IST). The project has no version history, no rollback, and the v2.5 builder is editing live files alongside this audit with only file mtimes as protection. **Fix (do first, before any v3.0 edit):** `git init`, add a `.gitignore` (`.godot/`, `*.apk`, `*.import` churn as decided), commit the v2.4-delivered tree as the baseline, then commit per feature. This is the cheapest risk reduction in the whole audit. |
| Automated tests | ✅ Six headless harnesses (§33). |
| Separate systems (player / physics / weapon / networking / environment / camera / audio / UI) | ⚠️ **Partial — GAP-68.** Data is separated (`weapons.gd`, `shooting_sync.gd`, `bullet_pool.gd`, `audio.gd`) but the core is not: `game.gd` (~4,400 lines) + `player.gd` (902 lines) hold most systems. Environment and Camera have no files at all. Realistic v3.0 step: `physics_config.gd` + `tests/` + new systems in `scripts/` (GAP-68). |
| CharacterBody2D players | ✅ (`player.tscn`, `grenade.gd` also CharacterBody2D). |
| StaticBody2D fixed geometry | ✅ Arena + decor (`game.gd:627-677`). |
| RigidBody2D physical objects | N/A — **no physical objects exist.** Nothing in the game needs rigid-body simulation (grenades are kinematic by design; barrels, if added per GAP-64, are static + scripted). Do not add RigidBody2D for the checklist's sake. |
| Area2D triggers | ✅ Pickups (`pickup.gd`); bullets are Area2D (raycast-based, monitoring off). Bounce pads / zones (§18/§22) would extend this pattern. |

## 35. Complete production requirements — final delivery checklist (§28)

Spec is **COMPLETE**: points 1–28 all received (2026-11-19 ~01:35 IST).
Nothing more is coming. One line per §28 requirement, with status.

| # | Requirement | Status |
|---|---|---|
| 1 | Responsive gameplay | ⚠️ Partial — joystick/fire fixes done (QA-016/023/029); GAP-02/03/04/08/09 (movement feel) still open. |
| 2 | Independent aiming | ⚠️ Partial — dual-stick independent ✅; GAP-08 (aim snap) open. |
| 3 | Weapons | ✅ 6 weapons + grenades, data-driven table; GAP-38/39/40/57 open (burst/reserve/recoil-accum/flamethrower). |
| 4 | Jetpack | ⚠️ Partial — thrust/fuel/momentum ✅; GAP-05/06 (regen/flame) open. |
| 5 | Health | ✅ 100 HP, clamp, spawn protection; GAP-42/43 (multipliers/event IDs) open. |
| 6 | Damage | ⚠️ Partial — host-authoritative ✅; flat damage only (GAP-42), no victim knockback (GAP-46). |
| 7 | Respawning | ❌ Blind teleport — GAP-45 (no validation) + GAP-44 (no death FSM). |
| 8 | LAN multiplayer | ⚠️ Partial — host/join/rooms/modes work; two-phone join **unverified on real phones**; GAP-59/60/61 open. |
| 9 | Authoritative game logic | ⚠️ Partial — combat/health/kills/pickups host-authoritative ✅; positions peer-authoritative by documented decision (GAP-15). |
| 10 | Original maps | ✅ 10 unique maps (user requirement: no duplicates — verify in MAP_AUDIT.md). |
| 11 | Visual effects | ⚠️ Partial — muzzle/impact/fireball/smoke ✅; GAP-24 (flash/ring/debris) open. |
| 12 | Menus | ✅ Menu/lobby/scoreboard/pause (flow 10/10, v2.4). |
| 13 | HUD | ✅ Health/ammo/grenades/scoreboard; reload progress ✅. |
| 14 | Security | ⚠️ Partial — host validation for shooting/ammo/damage ✅; no version handshake (GAP-61), no Git (GAP-75). |
| 15 | Performance optimisation | ⚠️ Partial — pooling + static shapes ✅; pool budget short (GAP-67), no FPS measurement (GAP-73). |
| 16 | Crash prevention | ⚠️ Partial — no crash-stability test (GAP-73); disconnect handling exists ✅. |
| 17 | Release testing | ⚠️ Partial — 6 harnesses ✅; new tests T-40…T-75 must go green; two-phone check owed by the user. |

**Delivery gate for v3.0:** (1) `git init` + baseline commit (GAP-75)
first; (2) all §H regression suites at previous pass counts; (3) tests
T-40…T-75 green or waived-with-reason in `BUGS.md`; (4) 0 script errors
on a clean run; (5) `--perf-test` green (GAP-73); (6) user's two-phone
LAN check on real Wi-Fi. Do not ship on fewer.

---

## 36. Gap index — extension (GAP-19…GAP-75)

**Correction to §0b:** the extension scope grew while it was being
written (points 9–21 → 9–28 as the user kept sending spec). The
correct counts are **57 new gaps (GAP-19…GAP-75)** and **36 new tests
(T-40…T-75)** — not the 44 gaps / points 9–21 stated in §0b.

| # | Gap | Spec § | Severity | Where to fix |
|---|---|---|---|---|
| GAP-19 | No per-projectile radius / gravity / drag / range / weapon-id | §9 | Medium | `bullet.gd` `setup()` + `weapons.gd` |
| GAP-20 | Shotgun 6 pellets, random spread — not 7 with fixed [-15..15]° offsets | §9 | Medium | `weapons.gd:22`, `player.gd:578-583` |
| GAP-21 | Bullet Area2D layer/mask disagrees with itself (tscn 8/3 vs `_ready` 8/0) | §9 | Low | `bullet.gd:34-36` |
| GAP-22 | Explosion falloff has 40% floor at edge — neither linear nor smooth curve | §10 | Medium | `game.gd:2150`, `player.gd:758-763` |
| GAP-23 | Knockback has no mass, no (1-u)², no vertical multiplier | §10 | Medium | `player.gd:749-767` |
| GAP-24 | Explosion FX missing flash / shockwave ring / debris | §10 | Low | `game.gd:2165-2186` |
| GAP-25 | One capsule is body + hitbox + damage region (no head/torso/legs/arms) | §11 | High | `bullet.gd:124-136`, `player.gd:169-176` |
| GAP-26 | No explosion / hazard / sensor layers | §11 | Low | `project.godot` layer names (doc first) |
| GAP-27 | Grenade has no CCD, no terminal velocity | §11/§13 | Low | `grenade.gd:43-45` |
| GAP-28 | No one-way platforms | §12 | Out of scope | — |
| GAP-29 | No moving platforms | §12/§22.A | Out of scope | — |
| GAP-30 | No destructible terrain | §12/§22.B | Out of scope | — |
| GAP-31 | No terrain-material friction | §12 | Low (optional) | `MAPS` platform data + `player.gd` |
| GAP-32 | Grenade has no air drag | §13 | Low | `grenade.gd:44` |
| GAP-33 | Grenade has no resting state | §13 | Medium | `grenade.gd:43-55` (with GAP-11) |
| GAP-34 | Player collision choice is hardcoded, not configurable | §14 | Low | `player.gd` / `game_data.gd` constants |
| GAP-35 | Pickups have no rotation | §15 | Low | `pickup.gd:52-55` |
| GAP-36 | No weapon drop | §15 | Out of scope | — |
| GAP-37 | Pickup respawn is a global 14 s timer; no pickups at match start; 20 s self-despawn | §15 | Medium | `game.gd:1885-1898`, `pickup.gd:50-55` |
| GAP-38 | No burst mode | §16 | Out of scope unless a burst weapon is added | `weapons.gd`, `player.gd` |
| GAP-39 | No reserve ammo (infinite reserve, accidental) | §16 | Medium (design decision) | `player.gd:72,483,638` |
| GAP-40 | No recoil accumulation (R_n = R_0 + n·K) | §16 | Medium | `player.gd:588-596` |
| GAP-41 | No explicit FIRING state (bool + timer only) | §16 | Low | `player.gd:76,82,479-483` |
| GAP-42 | No damage multipliers at all (distance/weapon/armor/regions) | §17.1–17.3 | **High** | New `calculate_damage()` + GAP-25 |
| GAP-43 | No unique damage event IDs | §17.8 | Medium | `player.gd:712-767` damage RPCs |
| GAP-44 | No death FSM (bool + timer only; no DYING/DEAD/RESPAWNING) | §17.6 | Medium | `player.gd:75,83,724-748` |
| GAP-45 | Respawn never validated (wall/ground/enemy/bounds) | §17.7 | **High** | `game.gd:568-571`, `player.gd:815-849` |
| GAP-46 | No per-weapon knockback on the victim | §17.5 | Medium | `weapons.gd` table + `player.gd:712` |
| GAP-47 | No water / buoyancy zones | §18.A–B | Out of scope | — |
| GAP-48 | No mud zones | §18.C | Out of scope (optional) | — |
| GAP-49 | No wind zones | §18.D | Out of scope | — |
| GAP-50 | Damage zones: only lava exists (no electric/barrels/gas/rocks) | §18.E | Medium | New zone nodes; barrels = GAP-64 |
| GAP-51 | No ice zone on Frozen Fortress (prototype values given) | §18.A | Low — **recommend for v3.0** | New `IceZone` + `player.gd` `_apply_movement` |
| GAP-52 | No camera dead zone | §19 | Medium | `player.gd:142-160` (decouple camera) |
| GAP-53 | No camera look-ahead | §19 | Medium | Same as GAP-52 |
| GAP-54 | No shake on explosion/damage for the victim | §19 | Low | `player.gd:712-767` |
| GAP-55 | No bullet velocity inheritance (0.15) | §20.C | Medium | `bullet.gd:104-109`, `player.gd:583` |
| GAP-56 | Prototype values differ from `weapons.gd` (rifle/pistol/shotgun/rocket — see §27 table) | §20.C/§24.C | Low (per-value decisions) | `weapons.gd:19-26` |
| GAP-57 | No flamethrower weapon | §20.E | Out of scope | — |
| GAP-58 | No lag compensation | §21.E | Out of scope (LAN) | — |
| GAP-59 | No host migration (host leaves = match ends) | §21.G | Out of scope | Document in lobby |
| GAP-60 | Snapshot rate 20/s (low end); no input stream to server | §21.F | Low | `player.gd:302` → 0.033 |
| GAP-61 | No version handshake on game join (discovery only) | §21.G | Low | `game_data.gd` `BUILD_VERSION` + join RPC |
| GAP-62 | No moving platforms (full type list) | §22.A | Out of scope | — |
| GAP-63 | No destructible environment (full material system) | §22.B | Out of scope except barrels | — |
| GAP-64 | No explosive barrels | §22.C | Medium — **⭐ cheap win, recommend for v3.0** | New `Barrel` + `game.gd:2137` |
| GAP-65 | No rope / grappling | §22.D | Out of scope | — |
| GAP-66 | No bounce pads / springs | §22.E | Low — **⭐ cheap win, recommend for v3.0** | New `BouncePad` Area2D |
| GAP-67 | Bullet pool 96 shared = 12/player at 8 players, below 16–32 budget | §22.G/§24.E | Medium | `game.gd:533` → 160 |
| GAP-68 | No systems split; `game.gd` is a ~4,400-line monolith; flat folder layout | §23.A–C | High (maintainability) / Low (delivery) | `physics_config.gd` + `tests/` first |
| GAP-69 | Physics and rendering mixed (`_update_visuals` runs in `_physics_process`) | §23.E | Medium | `player.gd:307` → new `_process` |
| GAP-70 | Config drift: no single source of truth for tuning values | §24 | Medium | New `physics_config.gd` |
| GAP-71 | Collision layer scheme ≠ §24.D (projectile 8 not 4, pickup 16 not 7) | §24.D | Medium | Renumber with GAP-64/66 |
| GAP-72 | No stuck-player recovery at runtime | §25 | Low | `player.gd:_physics_process` |
| GAP-73 | No performance / memory / crash-stability tests | §26/§24.E | Medium | New `--perf-test` harness |
| GAP-74 | No TileMapLayer (maps built in code) — deliberate deviation, record it | §27 | Low (doc) | README / `MAP_AUDIT.md` note |
| GAP-75 | **No Git — no version history at all** | §27 | **High (process)** | `git init` + baseline commit first |

## 37. EXTENSION TESTS — T-40…T-75

Same rules as §15: headless where the harness supports it, real phone
otherwise; record pass/fail per test in `BUGS.md` (new QA entries).

### I. Projectiles & explosions

- **T-40 Shotgun spread (7 pellets, independent hits).** Fire the
  shotgun at a flat wall 600 px away. Pass: exactly 7 impact marks,
  angular spread ≈ ±15° with the centre pellet on the aim line, and
  each pellet is a separate bullet (fire at two players standing
  100 px apart in the spread — each takes only the pellets that hit
  them, not all 7).
- **T-41 Swept bullet vs thin platform.** Fire the sniper at a 24 px
  platform (thinner than the current 48 px) from point blank, 20
  shots. Pass: bullet stops at the surface every time (T-20 already
  covers 48 px — this is the thinner case that only swept collision
  catches).
- **T-42 Explosion falloff, centre vs edge.** Detonate a grenade
  (damage 55, radius 170) with a player at d ≈ 0, d ≈ 85, d ≈ 165.
  Pass: centre damage ≈ 55, mid ≈ 55 × (1−0.25)² ≈ 31 (smooth
  curve, GAP-22), edge ≈ 0–5 — and the host's lethal check agrees
  with the victim's damage in all three cases.
- **T-43 Explosion behind a wall.** Grenade explodes on the far side
  of a solid crate; player stands behind the crate within blast
  radius. Pass: no (or halved, if the builder chooses halved)
  damage through the crate after the GAP-12 fix (T-23 is the same
  check — run once, record under both numbers).
- **T-44 Grenade bounce + rest.** Throw a grenade at a platform at a
  shallow angle. Pass: it bounces at least once at ~45% of impact
  speed, rolls/slides and slows gradually, then visibly stops
  (resting state, GAP-33) without jitter — it does not stop dead on
  first contact and does not bounce forever.
- **T-45 Grenade fuse timing.** Throw a grenade that bounces and
  rolls; time from throw to explosion. Pass: 2.0 s ± 0.1 s regardless
  of bounces, rolling, or resting (fuse independent of movement).
  Repeat with a grenade thrown straight up: same 2.0 s.
- **T-46 Pickup float.** Watch a pickup for 10 s. Pass: bobs
  smoothly (amplitude ≈ 6 px, period ≈ 2.1 s at ω = 3.0) with a
  gentle sway if rotation was added (GAP-35); the collection circle
  follows the visual.

### J. Pickups, fire rate, reload, recoil

- **T-47 Pickup respawn.** Collect a pickup; watch its spot. Pass:
  3 pickups are present at match start (GAP-37 fix — currently 0
  for the first 14 s), the collected spot respawns after its
  per-spot timer, total active never exceeds the cap, and no pickup
  ever spawns inside a solid (map-load test re-run).
- **T-48 Weapon drop.** Only if GAP-36 is implemented. Drop the
  shotgun (switch weapon / die with drop enabled). Pass: it falls
  with gravity, settles on the ground, and can be picked up again.
  If drop stays out of scope, record the decision in `BUGS.md` and
  mark T-48 N/A — do not leave it blank.
- **T-49 RPM timing at different frame rates.** Hold FIRE with the
  SMG (rate 0.07) for 10 s at 30 / 60 / 120 FPS render rates
  (physics stays 60 Hz). Pass: shots per second = 14.3 ± 5% at all
  three rates — fire rate must not depend on the render frame rate.
  Repeat with the rifle (7.7/s) and pistol (semi-auto, one shot per
  tap, 10 taps = 10 shots).
- **T-50 Reload state machine.** Fire to empty, watch the reload;
  try firing mid-reload; tap FIRE during reload; press RELOAD with
  a full mag. Pass: READY → RELOADING → READY; no shot fires during
  reload; the mid-reload tap is discarded (no shot the instant the
  reload finishes); RELOAD on a full mag does nothing; mag refills
  to full (and reserve decreases, if GAP-39 is implemented).
- **T-51 Hit-region multipliers.** Same weapon (rifle, 12 dmg), same
  distance: head hit vs torso hit vs legs vs arms. Pass: damage
  ratio 1.5 : 1.0 : 0.75 : 0.85 (head 18, torso 12, legs 9, arms
  ~10). If single-body hitbox is the documented deviation (GAP-42),
  all four read 12 and the deviation is recorded — either is a pass,
  but the choice must be written down.
- **T-52 Player-to-player, both modes.** Default (non-blocking):
  two players run into each other — pass: they pass through, no
  pushing, no sticking. If the blocking mode is ever enabled
  (GAP-34): pass: they separate along the push direction with no
  overlap and no velocity explosion, and can walk apart freely.
- **T-53 Recoil accumulation.** Fire 5 rapid rifle shots, then stop
  and wait 2 s. Pass: the shot group visibly widens over the 5
  shots (spread grows with `_recoil_accum`) and the gun kick is
  larger on shot 5 than shot 1; after the pause, the next shot is
  back to baseline spread (accumulation decayed).
- **T-54 Burst mode.** Only if a burst weapon is added (GAP-38).
  One trigger pull: pass: exactly 3 shots, ~0.08 s apart, then no
  more until ~0.3 s later. If no burst weapon exists, mark N/A with
  the reason recorded.

### K. Death, damage integrity, hazards, ice

- **T-55 Death FSM + respawn validation.** Kill a player; watch the
  sequence. Pass: controls + firing stop immediately, `die` anim
  plays, no second death is recorded for the same life (kill feed
  shows one death), respawn happens after 3.0 s at a **validated**
  spawn — never inside a wall/ground, never within 150 px of a live
  enemy, never out of bounds. Camp a spawn with an enemy and kill
  the victim 5 times: pass: the victim never spawns inside the
  camper.
- **T-56 Single-hit duplicate prevention.** Fire one bullet through
  a player (host view, frame-step if possible). Pass: exactly one
  damage event lands (health drops by exactly the bullet damage,
  once). Stand in lava 3 s: pass: health drops in 1.0 s ticks
  (3 × 20 = 60), never per-frame. Re-send a damage RPC (or kill the
  victim with two simultaneous lethal hits): pass: one death, one
  kill credit (GAP-43).
- **T-57 Hazard damage intervals.** Stand in a lava pool for 3 s,
  then step out. Pass: 20 HP per 1.0 s tick (or 10 HP per 0.5 s tick
  if the GAP-50 lava change lands), damage stops the tick after
  leaving, no kill credit is awarded for a lava death.
- **T-58 Ice sliding (prototype values).** Only if GAP-51 is
  implemented. On Frozen Fortress ice: run at max speed, release
  the stick. Pass: stop distance on ice ≥ 3× the ground stop
  distance (friction 100 vs 1200); direction changes take clearly
  longer; jumping while sliding preserves horizontal speed (measure
  `vx` before/after the jump — within 10%). Off ice, behaviour is
  unchanged.

### L. Camera, firing-while-moving, sync

- **T-59 Camera dead zone / look-ahead / limits / shake.** Move the
  player in small steps inside the screen centre: pass: the camera
  does not follow every step (dead zone, GAP-52). Sprint right:
  pass: more of the map is visible to the right than the left
  (look-ahead, GAP-53). Run to each map corner: pass: no out-of-map
  area is ever visible (limits). Stand next to a grenade blast and
  take non-lethal damage: pass: a small brief camera shake is
  visible (GAP-54) and aiming is still possible during it.
- **T-60 Velocity inheritance 0.15.** Sprint right at 330 px/s and
  fire the rifle horizontally right; repeat standing still. Pass:
  the sprinting bullet travels ~50 px/s faster (330 × 0.15) than
  the standing bullet — measure by time-to-impact at a fixed
  1000 px wall, or by tracer speed. Fire while sprinting left and
  shooting right: pass: bullet is slower than the standing shot
  (inheritance subtracts).
- **T-61 RPM values vs `weapons.gd`.** For each weapon, hold FIRE
  10 s and count shots. Pass: rifle ≈ 77–80 (0.125 s), pistol
  semi-auto only, shotgun 6 pellets per shot (or 7 if GAP-20
  lands), rocket ≈ 10 (1.0 s). Record the adopted table in
  `BUGS.md` next to the GAP-56 decisions.
- **T-62 The six shooting bugs (§20.F).** One pass/fail each: (1)
  muzzle never inside the player capsule at any aim angle; (2) no
  self-hit on the firing frame (fire 50 shots point-blank at a wall
  — shooter takes 0 damage); (3) aim independent of movement
  (T-17 re-run); (4) no per-frame fire rate (T-49); (5) no
  unbounded projectiles (8 players full-auto SMG 10 s — active
  bullets stay ≤ pool size + small overflow, no growth over time);
  (6) every bullet despawns at end of life (no orphan bullets after
  10 s of firing, `active_count()` returns to 0).
- **T-63 Interpolation buffer behaviour.** Two-phone test (user):
  host and client strafe; introduce a ~100 ms packet gap (or just
  observe during heavy fire). Pass: remote player motion stays
  smooth with no visible teleporting; a remote player who stops
  moving does not slide past their stop point (extrapolation
  capped to one step). If the GAP-16 buffer is not implemented,
  record the lerp-only behaviour and mark T-63 as "known
  limitation", not a pass.
- **T-64 Host-authoritative checks.** Code-path + live attempt: a
  client calls `take_damage` / `add_kill` / `give_pickup` directly
  (or a modified client sends a forged `spawn_bullet` with a
  0.01 s rate). Pass: all rejected (sender check / rate + ammo
  validation); no damage, kill, or pickup results. Also: a client
  on a mismatched build version is refused at join with a readable
  message (GAP-61).

### M. Advanced interactions, config, architecture, delivery

- **T-65 Explosive barrel LOS + falloff.** Shoot a barrel next to a
  wall; player stands behind the wall within blast radius. Pass:
  barrel explodes (FX + sound + host-authorised), damage follows
  `D = Dmax × max(0, 1 - d/R)` (linear — note if GAP-22's smooth
  curve is used instead, the barrel must use the same curve),
  the player behind the wall takes 0 (LOS check, GAP-12). Only if
  GAP-64 is implemented; else N/A with reason recorded.
- **T-66 Bounce pad single-trigger.** Step on a bounce pad and stay
  on it. Pass: exactly one launch (`velocity.y = -750`) per
  contact — the player is not relaunched every physics frame while
  overlapping; after landing back on the pad, it triggers again.
  Only if GAP-66 is implemented; else N/A with reason recorded.
- **T-67 Moving platform carry.** Only if moving platforms are ever
  added (GAP-29/62). Stand on a horizontal platform: pass: the
  player is carried at the platform's speed with no input, can walk
  against it, and does not slip through at max platform speed; the
  carry does not accumulate into permanent velocity after stepping
  off. Else N/A with reason recorded.
- **T-68 Config values applied.** Spot-check the adopted §24 table
  (§31): speed 350, gravity 1400, jump −660 (kept), max fall 1000,
  jetpack rise 450, rifle rate 0.125. Pass: each constant in code
  matches the recorded adopted value (read them out of
  `physics_config.gd` if GAP-70 landed, else out of `player.gd` /
  `weapons.gd`).
- **T-69 Update order respected.** Frame-step or log one physics
  tick with input + movement + firing + a damage event in the same
  tick. Pass: input is read before movement, movement/collision
  resolve before projectiles spawn, damage applies after the
  projectile step, and no visual code writes `position` or
  `velocity` (GAP-69 — check by grep: no `position =` /
  `velocity =` outside `_physics_process` and RPC handlers).
- **T-70 Physics / rendering separation.** Run at an unlocked render
  rate with physics at 60 Hz. Pass: visuals (sprite, gun kick,
  camera offset, HP bar) update in `_process`, simulation only in
  `_physics_process`; remote players render smoothly between
  physics ticks (interpolation, not stepping at 60 Hz).
- **T-71 Layer scheme check.** After any renumber (GAP-71): pass:
  bullet raycast hits world + players only (mask 3 under the new
  scheme), pickups trigger on players only, bounce pads / zones
  trigger on players only, and a bullet never triggers a pickup or
  a bounce pad. Run the `--collision-test` after the renumber.
- **T-72 Stuck-player recovery.** Only if GAP-72 is implemented.
  Force a stuck state (teleport the player into a wall seam in a
  test build). Pass: within 3 s the player is moved to the nearest
  valid spawn with a log line; no manual death/respawn needed.
- **T-73 Performance soak.** `--perf-test` (GAP-73): 10-minute
  headless soak, 8 simulated players, full-auto fire + grenades.
  Pass: sustained FPS ≥ 55, no script errors, memory growth < 50 MB
  over the soak, `active_count()` returns to 0 after firing stops.
- **T-74 Two-phone LAN disconnect / reconnect.** User test: host +
  client on real Wi-Fi; client kills the app mid-match and rejoins
  via the saved IP. Pass: the host's match continues, the
  rejoining client spawns correctly, and the host leaving ends the
  match with a clear message (no silent hang — GAP-59 documented
  behaviour).
- **T-75 Delivery gate.** Run §35's gate end to end before shipping
  v3.0: `git` baseline exists (GAP-75), §H regression at previous
  pass counts, T-40…T-74 green or waived-with-reason in `BUGS.md`,
  0 script errors on a clean run, `--perf-test` green, two-phone
  LAN check done. Pass: every box ticked or explicitly waived by
  name — no silent skips.

**Test count: 75 total** (T-01…T-39 audit #1 + **T-40…T-75** this
extension, 36 new). Minimum green bar for v3.0 delivery: all of
§A–§F on a real phone, §G by code path + the user's two-phone check,
§H suites at their previous pass counts, §§I–M green or waived with
a written reason, and the §35 delivery gate fully ticked.

---

## 38. Extension totals (audit #2, final — spec complete)

- **Spec coverage:** points 1–28 all audited. Audit #1 covered
  §§1–8; this extension covers §§9–28. **No spec items remain
  outstanding.** (Points 22–28 arrived in pieces during this audit;
  the "not received" notes in earlier sections are superseded by
  this one: the spec is complete as of 2026-11-19 ~01:35 IST.)
- **Gaps:** 18 (audit #1) + **57 new (GAP-19…GAP-75)** = **75 gaps
  total**. Of the 57 new: 13 out of scope (one-way/moving
  platforms, destructibles, water, mud, wind, conveyor dropped,
  weapon drop, burst-unless-added, flamethrower, lag compensation,
  host migration, ropes), 6 design decisions to record rather than
  build (infinite reserve, single-body hitbox option, peer-
  authoritative movement, rocket speed/gravity, pistol rate,
  TileMapLayer), 2 cheap wins recommended for v3.0 (explosive
  barrels GAP-64, bounce pads GAP-66) + 1 small touch (ice GAP-51),
  and 1 process fix that must come first (`git init`, GAP-75).
- **Tests:** 39 (audit #1) + **36 new (T-40…T-75)** = **75 tests
  total**.
- **Biggest 3 new gaps:** (1) **GAP-42 — no damage multipliers at
  all** (flat damage, no head 1.5× / torso 1.0× / legs 0.75× /
  arms 0.85×, no distance/weapon/armor terms); (2) **GAP-45 —
  respawn is never validated** (blind teleport to a fixed spawn,
  no wall/enemy/bounds check); (3) **GAP-75 — no Git** (no version
  history while two agents edit the same files live).
- **Conforming, no action (extension):** bullet pooling verified
  used (96 preallocated); swept bullet raycast; host-authoritative
  combat/health/kills/pickups; one-shot explosions (no per-frame
  damage); single-hit bullets (`_dead` flag); lava interval damage
  (1.0 s ticks, server-only, no kill credit); player pass-through
  = spec's recommended default; time-based fire cooldowns;
  camera hard limits from map size; 60 Hz fixed timestep; LAN flow
  + join timeout + disconnect handling + versioned discovery.
- **File-state warning (repeat):** `game.gd` changed during this
  audit (19:50:57 → 19:59:56 UTC). Re-verify every `game.gd` line
  number in this extension after the v2.5 edit lands.

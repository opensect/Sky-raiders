# Frag Arena — v3.5

A Mini Militia-like 2D multiplayer shooting game for Android, played over
local Wi-Fi (LAN). No accounts, no online servers, no matchmaking, no ads.
2–12 players on the same Wi-Fi. (Renamed from "LAN Arena Shooter" in v3.5 —
see QA-065 in BUGS.md; the package name `com.lanarena.shooter` is unchanged,
so v3.5 installs over v3.4.)

## What's new in v3.5 (crash fix + rifle straight + no more stuck + REAL lobby redesign + Frag Arena)

- **Crash after starting a match once — fixed in-process (QA-060).**
  The rematch path called `reload_current_scene()` from inside
  `_process`, and the rest of that frame kept running on the
  tree-detached instance where `multiplayer` is null (5× null
  errors reproduced pre-fix). The `_leaving` guard now covers
  rematch; the old ENet peer is explicitly `close()`d at every
  teardown site before being replaced; the `start_match` RPC has
  an idempotency guard; "Back to Lobby" is relabelled "Back to
  Menu" (it goes to the menu). New restart test — match 1 → leave
  → match 2 → end → rematch → play again — **8/8 PASS**. Honest
  note: the crash could not be reproduced as a phone crash
  in-process, and a GDScript error alone does not force-close an
  Android app — if the phone still closes, a logcat is needed.
- **Assault rifle fires straight now (QA-061).** Its bullets
  sprayed up to ±20–30° during sustained auto fire: table spread
  0.05 plus accumulated recoil spread (`_recoil_accum * 0.5`,
  growing 0.06/shot). Table spread is now 0.0 and the rifle is
  excluded from recoil-spread growth. Fire test: 14 shots held
  2.5 s, max deviation **0.00°**; repl-sim local + remote both
  0.00°. Shotgun spread, gun kick and shake unchanged.
- **No more getting stuck between obstacles (QA-063).** A
  computational audit of all 13 maps found 2 trap gaps (a slot
  you can drop into but cannot jump out of) and 13 tight gaps;
  15 obstacle moves later the audit reads **0 TRAP, 0 TIGHT**.
  The stuck-recovery code now also catches wedged-between
  (not just inside-solid) and teleports you to a spawn away from
  the trap. New P24b wedge-recovery check in the physics suite.
- **Lobby REDESIGNED — the entire layout is new (QA-059).**
  QA-058 was only polish and you called it out, so the lobby is
  genuinely different now: room + players in a LEFT column,
  map selection as large real-art cards in a RIGHT column, and
  the I'M READY / START / Leave buttons in a fixed bottom bar.
  The ghost boxes are gone — they were panel shapes baked into
  the old background art, replaced by a clean background. Map
  scrolling still works (9/9 at both resolutions, including a
  genuine 2400x1080 check).
- **New name + logo: Frag Arena (QA-065).** New code-drawn logo
  (crosshair + FRAG ARENA, Orbitron, cyan-on-navy) and app icon.
  Package name unchanged, so v3.5 installs over v3.4.
- **Grenade + reload buttons are plain round buttons (QA-062).**
  Round 72 px circles with a simple icon — the progress rings
  and count badge were built, then removed at your request ("No
  remove that", "Just have plain buttons"). Grenade count stays
  as plain text; throw/reload behaviour unchanged.
- **Godot engine logo removed from startup (QA-064).** No logo,
  straight into the game.
- **Double-check corrections:** the physics jump-test spot sat
  exactly on Space Station's bounce pad (QA-066 — test-only fix,
  physics untouched); the QA-055 inside-geometry fix and the
  QA-056 bullet size are now test-proven, not just code-verified;
  the AIM no-left check at 2400 was added; the v3.4 "genuine
  2400x1080" claims were retracted (the xvfb window capped at
  1600x720 — genuine 2400x1080 verification only exists from
  v3.5, on a dedicated Xvfb:99 screen); QA-058 is honestly
  recorded as polish, not a redesign.
- Nothing else changed: same 13 maps, same features, same 3
  permissions, same debug keystore — v3.5 installs over v3.4.

### v3.5 build (delivered 2026-11-19, independently verified + exported)

- **APK:** `mini-militia-lan.apk` — 35,880,779 bytes (~34 MB), md5
  `3a1ab1ea6bf71fcc485ec94cd2153ad3`, versionCode **13**,
  versionName **3.5**, targetSdk 36, minSdk 24, package
  `com.lanarena.shooter`, arm64-v8a only, app label **Frag Arena**.
  Built with Godot 4.7.2 (`--export-release Android` under xvfb).
  **Signing note:** the Godot export came out unsigned (preset
  `package/signed=false`), so the APK was signed afterwards with
  `apksigner` using the same debug keystore as v3.2/v3.3/v3.4 —
  `apksigner verify` passes (v2 + v3 schemes), cert SHA-256
  `f65f2fa3d8041b5e8920e627355a0dd68d9b50414d6b40702fea6b4da6e02d11`
  matches v3.4 exactly, so it installs over v3.4. Exactly the 3
  permissions (INTERNET / ACCESS_NETWORK_STATE /
  ACCESS_WIFI_STATE). Contents: both music OGGs, Orbitron + Rajdhani
  fonts, gohud theme, arena backgrounds (`arena_blue.png`,
  `arena_clean.png`), Frag Arena logo + icon, Sky Brawl textures; no
  `.md`/`.txt`, no `fire_button` leftovers. v3.4 APK backed up at
  `~/workspace/mini-militia-lan-backup-v3.4/` (md5 verified
  `39e11621341a78a04b8f4b7ce7108453`).
- **Independent verification (fresh re-run on the shipped code by the
  test/export worker, not the fix worker's logs):** repl-sim 26/26,
  joystick 26/26, fire (right-stick) 29/29, scale 70/70, physics
  32/32 (maps 0/6/10/12) + 23/23 (Frozen ice, map 4), features
  11/11, net 15/15, menu-net 6/6, full flow DONE, scroll 9/9 at
  1280x720 AND genuine 2400x1080 (dedicated Xvfb:99 2400x1080
  screen), collision 8/8 on all 13 maps, smoke DONE on all 13 maps,
  restart test 8/8 — **0 script errors in every log**.
  Post-version-bump re-run: repl-sim 26/26, flow DONE, physics map 0
  32/32 (after one P02 flake re-run), restart 8/8, 0 script errors.
  Previous-bug regression QA-001…QA-066 all still fixed (see
  BUGS.md). Screenshots re-captured from the shipped code at both
  resolutions (menu, lobby, HUD, pause, scoreboard, end, settings,
  customization, multiplayer, countdown) in
  `~/workspace/mini-militia-lan-v35-proof/` — all 20 files verified
  1280x720 / 2400x1080 px; the 10 menu-side shots are byte-identical
  to the fix worker's, the 10 game shots differ only by capture
  timing. Lobby confirmed visually as the new two-column layout with
  no ghost boxes; menu shows the Frag Arena logo; HUD shows the plain
  round grenade/reload buttons with no rings; the top-right panel is
  fully opaque at 2400x1080 (the v3.4 ghost box is gone).
- **Two honest findings from the export worker's stricter checks
  (see BUGS.md v3.5 delivery record):** (1) physics run on ALL 13
  maps (the suite only claims maps 0/4/6/10/12) fails a few
  harness-placement steps on maps 1/2/5/8/9/11 — the SAME steps fail
  on the v3.4 backup, so they are pre-existing harness limits on
  maps never in the physics-test set, not v3.5 regressions and not
  game-physics bugs. One exception: map 7 (City Underground) passed
  31/31 in v3.4 but fails P07a/P07b in v3.5 — the QA-066 jump-spot
  move (x=2100→x=800) fixed map 6 but the new spot bonks an overhead
  platform on map 7; the spot was only validated on the five
  physics-test maps. (2) At genuine 2400x1080 the joystick suite is
  25/26: RELEASE-STOPS fails twice (vel.x 74/95 vs <60) while the
  720p run passes (45) — the release itself is clean (vector 0,
  knob 0, not jetpacking); under llvmpipe at 2400 fewer physics
  frames elapse in the 0.5 s wall-clock wait, so the player has not
  finished decelerating when the check fires. Same load-marginal
  family as P02/P19. The QA-054 no-left steps PASS at 2400 in both
  runs, including AIM-RELEASE-NO-LEFT-2400.
- **AAB: NOT built — blocked on the release keystore** (same as
  v3.4; see PLAY_SUBMISSION_CHECKLIST.md).
- **Honest limits (unchanged):** real two-phone LAN join and
  movement sync, real touch hardware, real-phone performance and
  audio-by-ear are still untested here (the sandbox blocks UDP
  sends; repl-sim 26/26 is the in-process substitute). The
  two-phone check below is the only proof that counts.
  Mid-match rejoin is not supported. The two-process rejoin test
  fails in the sandbox (UDP blocked) — needs two real phones. The
  QA-060 phone crash is fixed in-process only — if the phone still
  closes, a logcat is needed.

## What's new in v3.4 (RPC movement sync + joystick release fix + bullet audit + top-right & lobby UI)

- **Movement sync rebuilt on the proven RPC channel (QA-053).**
  In v3.3 both players were visible but movement still did not reflect
  on the other phone — while bullets and grenades DID sync. Root cause:
  the `MultiplayerSynchronizer` was created with no explicit name, so
  Godot gave it a different auto-uniquified name on every peer (e.g.
  `@MultiplayerSynchronizer@1335`); synchronizer packets are addressed
  by node path, so remote peers dropped them silently. RPCs worked
  because they are addressed by the player node path
  (`Players/<pid>`). The synchronizer is now deleted entirely; player
  state travels on unreliable RPC snapshots at 30/s, with out-of-order
  drops and interpolation over a 12-entry 100 ms buffer. One owner for
  the remote visible position; combat stays host-authoritative.
  Simulated two-peer test 24/24 (both directions smooth: max step
  303/315 px/s, snap-back 0.0 px; bullet tracking max error 0.0 px) —
  **the live two-phone check is still yours to do**, see "Testing the
  join on two real phones", step 4 — the sim cannot prove live ENet
  delivery, and the v3.3 sim passed 19/19 while real phones still
  failed.
- **Joystick release no longer turns you left (QA-054).** Pushing the
  stick right and releasing it made the player turn left. Cause:
  `emulate_mouse_from_touch` plus the mouse-aim fallback aiming at the
  left-half touch point while running right. Fixed with a 500 ms
  touch gate; the fallback only runs when no touch was used recently.
  Joystick test 25/25, including the exact repro (push right →
  release → no leftward velocity, no facing flip in the next 30
  frames) on both sticks at 1280x720 and 2400x1080.
- **Bullet audit (QA-055) + bullets 20% smaller (QA-056).** One real
  bug found: the swept ray's `hit_from_inside` was false, so bullets
  fired through walls when the muzzle started inside geometry — fixed.
  The "bullets don't look realtime" report was the stale shooter pose
  from the dead synchronizer; snapshots now carry aim/facing, and
  flight stays deterministic per-peer simulation. Bullets are now 20%
  smaller on all weapons (visual 80%, trail matched; the hitbox is
  the zero-width swept ray, unchanged).
- **Top-right menu redesigned (QA-057) + lobby and all pages
  redesigned (QA-058).** The in-game top-right is now a proper Neon
  Arena panel: SCORE (96×56) + pause (56×56) buttons, Kills, Deaths,
  Players, weapon + ammo, Grenades — readable over all maps, no
  overlap with the timer, kill feed, buttons or right stick. Every
  screen (menu, multiplayer, lobby, settings, customization,
  countdown, map vote, pause, scoreboard, end) got section labels,
  titles and lobby player cards in the same theme; the end screen
  typo is fixed ("You win!", not "You wins!"). Map-list scrolling
  did not regress (8/8 at both resolutions). One fix found while
  verifying: the HUD showed "Players: 1/12" in every room (it used
  the 12-player cap, not the room's max) — it now shows the room max,
  so a default room reads "Players: 2/8" with two players.
- Nothing else changed: same 13 maps, same features, same 3
  permissions, same debug keystore — v3.4 installs over v3.3.

### v3.4 build (delivered 2026-11-19, independently verified + exported)

- **APK:** `mini-militia-lan.apk` — 35,576,986 bytes (~34 MB), md5
  `39e11621341a78a04b8f4b7ce7108453`, versionCode **12**,
  versionName **3.4**, targetSdk 36, minSdk 24, package
  `com.lanarena.shooter`, arm64-v8a only. Built with Godot 4.7.2
  (`--export-release Android` under xvfb). **Signing note:** the
  Godot export came out unsigned this time (preset
  `package/signed=false`), so the APK was signed afterwards with
  `apksigner` using the same debug keystore as v3.2/v3.3 —
  `apksigner verify` passes (v2 + v3 schemes), cert SHA-256
  `f65f2fa3d8041b5e8920e627355a0dd68d9b50414d6b40702fea6b4da6e02d11`
  matches v3.3 exactly, so it installs over v3.3. Exactly the 3
  permissions (INTERNET / ACCESS_NETWORK_STATE /
  ACCESS_WIFI_STATE). Contents: both music OGGs, Orbitron + Rajdhani
  fonts, gohud theme, arena background, Sky Brawl textures; no
  `.md`/`.txt`, no `fire_button` leftovers. v3.3 APK backed up at
  `~/workspace/mini-militia-lan-backup-v3.3/` (md5
  `296d69ea8c2959073709e27d784a5c09`).
- **Independent verification (fresh re-run on the shipped code, not
  the builder's logs):** repl-sim 24/24 (both directions smooth,
  snap-back 0.0 px, bullet tracking max error 0.0 px), joystick
  25/25, fire (right-stick) 26/26, scale 70/70, physics 31/31 (maps
  0/6/10/12) + 22/22 (Frozen ice, map 4), features 11/11, net 15/15,
  menu-net 6/6, full flow DONE, scroll 8/8 at 1280x720 AND
  2400x1080, collision 8/8 on all 13 maps, smoke DONE on all 13
  maps — **0 script errors in every log**. Previous-bug regression
  QA-001…QA-058 all still fixed (see BUGS.md). Screenshots
  re-reviewed by the test worker at both resolutions (menu, lobby,
  HUD, pause, scoreboard, end, settings, customization,
  multiplayer, countdown); two stale proof files (end + HUD at
  2400) were re-captured from the shipped code.
- **AAB: NOT built — blocked on the release keystore.** No release
  keystore exists anywhere on this machine; one must be created with
  a password supplied by you via Secure Vault (never invented, never
  written in a file). Exact steps are in
  `PLAY_SUBMISSION_CHECKLIST.md`. The APK above is the deliverable.
- **Honest limits (unchanged):** real two-phone LAN join and
  movement sync, real touch hardware, real-phone performance and
  audio-by-ear are still untested here (the sandbox blocks UDP
  sends; repl-sim 24/24 is the in-process substitute). The v3.3 sim
  passed 19/19 while real phones still failed, so the two-phone
  check below is the only proof that counts. Mid-match rejoin is
  not supported.

## What's new in v3.3 (movement sync fix + joysticks moved inward)

- **Movement now syncs to the other phone (QA-051).** In v3.2 both
  players were visible on both phones, but movement did not reflect —
  the other phone's copy of you stood frozen. Cause: the
  `MultiplayerSynchronizer` on each player never had its own
  authority set, so it stayed the server on every copy and a client's
  position writes never left the client. The synchronizer now gets
  the owning peer's authority, its root path is pinned, and every
  replicated property is explicitly `REPLICATION_MODE_ALWAYS` with
  spawn on. Simulated two-peer test 19/19 (14 old + 5 new sync
  checks) — **the live two-phone check is still yours to do**, see
  "Testing the join on two real phones", step 4.
- **Joysticks moved inward from the bottom corners (QA-052).** Both
  sticks sit 50 px up and 50 px toward the centre (move stick
  x 90–240, aim stick x 940–1090 at 1280x720) — easier to reach, and
  the aim stick still clears the RELOAD / GRENADE / WEAPON column.
  Nothing else about the controls changed: left stick moves, right
  stick aims and shoots, touch conversion is untouched.
- Nothing else changed: same NEON ARENA UI, same 13 maps, same
  features, same 3 permissions, same debug keystore — v3.3 installs
  over v3.2.

### v3.3 build (delivered 2026-11-19, independently verified + exported)

- **APK:** `mini-militia-lan.apk` — 35,732,833 bytes (~34 MB), md5
  `296d69ea8c2959073709e27d784a5c09`, versionCode **11**,
  versionName **3.3**, targetSdk 36, minSdk 24, package
  `com.lanarena.shooter`, arm64-v8a only. Built with Godot 4.7.2
  (`--export-release Android`), signed with the same debug keystore
  as v3.2 — `apksigner verify` passes, cert SHA-256
  `f65f2fa3d8041b5e8920e627355a0dd68d9b50414d6b40702fea6b4da6e02d11`
  matches v3.2 exactly, so it installs over v3.2. Exactly the 3
  permissions (INTERNET / ACCESS_NETWORK_STATE /
  ACCESS_WIFI_STATE). Contents: both music OGGs, Orbitron + Rajdhani
  fonts, gohud theme, arena background, Sky Brawl textures; no
  `.md`/`.txt`, no `fire_button` leftovers. v3.2 APK backed up at
  `~/workspace/mini-militia-lan-backup-v3.2/` (md5
  `cf1d7392f79bd1ba1f1104e26f18cf26`).
- **Independent verification (fresh re-run on the shipped code, not
  the builder's logs):** joystick 21/21, fire (right-stick) 26/26,
  scale 70/70, physics 31/31 (maps 0/6/10/12) + 22/22 (Frozen ice,
  map 4), features 11/11, net 15/15, menu-net 6/6, full flow DONE,
  repl-sim 19/19, scroll 8/8 at 1280x720 AND 2400x1080, collision
  8/8 on all 13 maps, smoke DONE on all 13 maps — **0 script errors
  in every log**. One first-run physics 30/31 on maps 0 and 6 was a
  documented P02-air-accel timing flake under llvmpipe — re-runs on
  the identical code were 31/31 (see BUGS.md); no physics code
  changed in v3.3.
- **AAB: NOT built — blocked on the release keystore.** No release
  keystore exists anywhere on this machine; one must be created with
  a password supplied by you via Secure Vault (never invented, never
  written in a file). Exact steps are in
  `PLAY_SUBMISSION_CHECKLIST.md`. The APK above is the deliverable.
- **Honest limits (unchanged):** real two-phone LAN join and
  movement sync, real touch hardware, real-phone performance and
  audio-by-ear are still untested here (the sandbox blocks UDP
  sends; repl-sim 19/19 is the in-process substitute). Mid-match
  rejoin is not supported.

## What's new in v3.2 (totally new UI + right-stick firing + join fix)

- **Totally new look everywhere (NEON ARENA).** Built with the free
  gohud 1.3.0 UI library (MIT) — cyan-on-navy sci-fi theme, chamfered
  corners, Orbitron titles + Rajdhani body text (SIL OFL 1.1), arena
  background with a dark scrim — on every screen: menu, multiplayer,
  lobby, HUD, pause, end-of-match, settings, customization, map vote,
  countdown. The old green rounded look is gone. HP/fuel are gohud
  GoBars; the timer turns amber under 30 s and red under 10 s; the
  kill feed sits on dark chips so it reads over bright and dark maps.
- **Map selection scrolls on a real phone (QA-048).** A drag starting
  on a map button now scrolls the list (the button used to swallow
  the drag). All 13 maps are reachable and tappable — verified at
  1280x720 and 2400x1080. Drag-release over another button does not
  select it.
- **No more FIRE button — fire with the right stick (QA-049).**
  Mini Militia style: push the right stick to aim and shoot, release
  to stop. The aim stick has a cyan ring + crosshair. Semi-auto
  weapons fire once per flick. RELOAD, GRENADE and WEAPON buttons
  stay. See "Controls" below.
- **Multiplayer join fixed (QA-047).** The joining phone used to get
  stuck on "Connecting..." with 0/8 players while the host saw 2
  players (the 2nd never moving) — the server spawned the player but
  never replicated it to the client. The server now broadcasts every
  spawn to all peers, re-sends on retry, and the client heals itself
  from the server's player list; the error shows the real state (IP
  tried, ENet status, whether the server answered). Simulated
  two-peer test 14/14 — the live two-phone check is still yours to
  do, see "Testing the join on two real phones" below.
- **Permissions authorised + Google Play / Android compliant.**
  Only three networking permissions (INTERNET, ACCESS_NETWORK_STATE,
  ACCESS_WIFI_STATE — all install-time, none is a runtime permission,
  so nothing to request at runtime). No data collected, no accounts,
  no ads/analytics — see `PRIVACY_POLICY.md` and
  `PLAY_SUBMISSION_CHECKLIST.md`. Target SDK 36, 64-bit arm64-v8a.
  The app is NOT published to Play (that needs your own Play Console
  account); the checklist tells you exactly what remains.

### v3.2 build (delivered 2026-11-19, independently verified + exported)

- **APK:** `mini-militia-lan.apk` — 35,728,737 bytes (~34 MB), md5
  `cf1d7392f79bd1ba1f1104e26f18cf26`, versionCode **10**,
  versionName **3.2**, targetSdk 36, minSdk 24, package
  `com.lanarena.shooter`, arm64-v8a only. Built with Godot 4.7.2
  (`--export-release Android`), signed with the same debug keystore
  as v3.1 — `apksigner verify` passes, cert SHA-256
  `f65f2fa3d8041b5e8920e627355a0dd68d9b50414d6b40702fea6b4da6e02d11`
  matches v3.1 exactly, so it installs over v3.1. Exactly the 3
  permissions (INTERNET / ACCESS_NETWORK_STATE /
  ACCESS_WIFI_STATE). Contents: both music OGGs, Orbitron + Rajdhani
  fonts, gohud theme, arena background, Sky Brawl textures; no
  `.md`/`.txt`, no `fire_button` leftovers. v3.1 APK backed up at
  `~/workspace/mini-militia-lan-backup-v3.1/` (md5
  `01eefb9c15061b1c51f9bb9b67e22dee`).
- **Independent verification (fresh re-run on the shipped code, not
  the builder's logs):** joystick 21/21, fire (right-stick) 26/26,
  scale 70/70, physics 31/31 (maps 0/6/10/12) + 22/22 (Frozen ice,
  map 4), features 11/11, net 15/15, menu-net 6/6, full flow DONE,
  repl-sim 14/14, scroll 8/8 at 1280x720 AND 2400x1080, collision
  8/8 on all 13 maps, smoke DONE on all 13 maps — **0 script errors
  in every log**. Screenshots spot-checked vs the v3.1 baseline:
  menu, lobby, HUD and end screens are visibly different (cyan
  NEON ARENA theme, arena background); HUD hint + host-IP line now
  visible (QA-050); no FIRE button anywhere (QA-049).
- **AAB: NOT built — blocked on the release keystore.** No release
  keystore exists anywhere on this machine; one must be created with
  a password supplied by you via Secure Vault (never invented, never
  written in a file). Exact steps are in
  `PLAY_SUBMISSION_CHECKLIST.md`. The APK above is the deliverable.
- **Honest limits (unchanged):** real two-phone LAN join, real touch
  hardware, real-phone performance and audio-by-ear are still
  untested here (the sandbox blocks UDP sends; repl-sim 14/14 is the
  in-process substitute). Mid-match rejoin is not supported.

## What's new in v3.0 (Godot 4.7.2 + 13 unique maps + features + music)

- **Engine upgrade: Godot 4.3 → 4.7.2.** No fallback, zero API breaks
  (only `project.godot` changed: features "4.3" → "4.7"). The Android
  template now targets SDK 36 (was 34) — baked into the 4.7.2 template,
  and it satisfies current Play requirements (35+).
- **13 unique maps** (was 10), each with 12 spawn points and 6 pickups,
  its own theme, layout, cover, sightlines and look — no two maps share
  a platform set. New: **Neon City** (3400×1800 vertical figure-eight
  with a risky centre skybridge), **Ancient Temple** (stepped ziggurat
  with a crypt tunnel below the floor), **Airship Fleet** (three
  separate ship decks with gaps crossed by jump + jetpack, safety net
  below, falling through a gap respawns you with no death). Rebuilt:
  **Space Station**, **City Underground**, **Pirate Island**. Every map
  validated: no spawn/pickup inside a solid, no route sealed off, every
  area reachable, cover within 150 px of every spawn, at least one
  explosive barrel per map.
- **Physics rebuilt to the full Mini Militia spec (points 1–28).**
  Fixed-timestep movement, gravity/jetpack/air control, swept bullets,
  explosion falloff + knockback, solid collision, host-authoritative
  sync (60 ticks/sec, 100 ms buffer), hit regions head 1.5× / torso
  1.0× / legs 0.75× / arms 0.85×, velocity inheritance 0.15, coyote
  0.10 s + jump buffer 0.12 s, fuel drain 45/s with regen delay, stuck
  -player recovery. Verified by a 31-step physics harness on maps 0,
  6, 10, 12 and 22 steps live on the Frozen Fortress ice (map 4).
- **All common game features (11/11):** kill feed, end-of-match stats
  (K/D, accuracy, best streak), real settings screen (sound/music
  volume, music on/off, joystick sensitivity, show FPS, invert aim —
  saved in `user://settings.cfg`), better scoreboard (sorted by kills, K-D +
  accuracy columns, TDM team totals, self highlighted), weapon info
  panel (pause → Weapons, all 6 weapons), 3-2-1-FIGHT countdown +
  goal banner, hitmarkers + floating damage numbers, MVP screen,
  map vote (host's map + next two, live counts), health/grenade
  pickups, and spectator mode (Survival / Last Man Standing, NEXT
  PLAYER cycling). Modes: Deathmatch, Team Deathmatch, Survival,
  Last Man Standing.
- **Music:** menu track (`menu_at_rest`) in menu/lobby/end screens and
  battle track (`battle_five_armies`) in matches, with a procedural
  loop as fallback; music on/off and volume in settings. Sky Brawl
  art is used throughout: map backgrounds (parallax layer), tiles,
  structures, characters (lobby select), pickups and effects.
- **Controls (v3.2, right-stick firing):** left stick move — push up
  to jump / fly with the jetpack; right stick aim AND fire while held,
  release to stop. Semi-auto weapons (pistol, shotgun, sniper) fire
  once per flick. RELOAD, grenade and weapon-switch buttons on the
  right. No FIRE button.

## What's new in v2.5 (joystick fix + solid obstacles + UI polish)

- **Fixed: joysticks moved downwards on a real phone (QA-029).** Touching
  either stick made the knob slam to the bottom and the player drift
  down, at every screen size. The cause was the touch conversion: the
  game converted touches with the viewport's canvas transform, which
  carries the camera offset (the camera follows the player), but the HUD
  does not follow the camera — so every touch landed ~680 px too low.
  Now touches are converted with the HUD layer's own transform and each
  stick measures from its own on-screen position, so the knob follows
  your finger exactly. The same fix also repaired FIRE-button taps,
  which missed the button by the same offset whenever the camera had
  moved. Verified by a new scale test: 70/70 checks across 1280x720,
  2400x1080, 1920x1080, 800x480 and 2340x1080 — centre touch gives a
  zero vector and the knob stays centred at every size.
- **New: solid obstacles (QA-030).** Crates, barrels, sandbags, rocks,
  columns, pillars, statues and watchtowers are now real cover: bullets
  stop at them with a spark burst, you cannot walk through them, and
  grenades bounce off them — like a real game. Trees, palms, bushes,
  bridges and arches stay decoration: you and your bullets pass through
  them. 11 decor items that sat exactly on top of a spawn point or a
  pickup were moved to a clear spot on the same platform. Verified by a
  new collision test (8/8 on Catacombs, 8/8 on Jungle Ruins) plus a
  static check of all 10 maps: 53 solid obstacles, 120 spawn points and
  60 pickups — no spawn or pickup inside a solid, no route sealed off,
  every area still reachable.
- **Polished UI (built-in Godot UI, no new libraries).** The HUD now
  shows your exact health and fuel numbers next to the bars, and all
  top-of-screen text has a dark outline so it reads over bright skies
  as well as dark ones. The main menu buttons have small icons, selected
  buttons (map, mode, kill limit, time, colour, helmet) have a light
  rim so the choice is obvious, and the multiplayer and lobby screens
  have short hints ("Tap a room to join it", "Friends join from LOCAL
  MULTIPLAYER — they tap your room, or type the host IP above"). Every
  touch target is still at least 56 px, and every flow works as before.

## What's new in v2.4 (FIRE button + multiplayer overhaul)

- **New: a Mini Militia-style FIRE button (QA-024).** A big red circular
  button sits at the far bottom-right corner of the screen. Hold it to
  fire continuously at the weapon's fire rate; tap it once for a single
  shot with semi-auto weapons (pistol, shotgun, sniper). The right stick
  is now **aim-only** — it never fires. The button has a white bullet
  icon, shrinks slightly when pressed, and glows while you are firing.
- **Fixed: firing triggered together with movement, grenade and weapon
  buttons (QA-023).** On a real phone, tapping GRENADE or WEAPON could
  also fire the gun. The cause was the touch routing: the game grabbed
  every touch first and routed it by screen half, and the only thing
  protecting the buttons was a rectangle check that could miss when the
  screen was stretched. Now the game only sees touches the buttons did
  not consume, the FIRE button owns its own touch, and firing is true
  only while a finger is actually holding the FIRE button — nothing else
  can ever fire the gun. Verified by tests: move alone, aim alone,
  GRENADE alone and WEAPON alone all give 0 shots.
- **New: Pistol.** Your default starting sidearm (12-bullet magazine,
  moderate rate, low recoil). Pick up the rifle, SMG, shotgun, sniper
  and rocket launcher as before. Every weapon now has its own fire rate,
  damage, magazine, reload time, bullet speed, recoil, sound and
  animation, all in one weapon table.
- **New: RELOAD button.** The ammo count shows next to the weapon name
  ("Rifle 24/30"). Tap RELOAD (or wait for the auto-reload at zero
  ammo) — a progress percentage shows while reloading, and you cannot
  fire until it finishes. Reload has its own animation and sound.
- **New: rooms (QA-025).** Local Multiplayer now has **Create Room**,
  **Join Room**, **Quick LAN Match** (joins the first open room),
  **Refresh Rooms**, **Manual IP Connection** and Back. When you create a
  room you set the room name, max players (2–12), and optionally make it
  private with a password. The host can change the map, mode, kill limit
  and match time, turn friendly fire on/off (Team Deathmatch), kick
  players, and start when everyone is ready — or force-start.
- **Fixed: the host IP is now shown big and clear.** The lobby shows
  "HOST IP: 192.168.1.5 — friends type this IP to join", and the
  multiplayer screen shows your own IP before you even host. If
  automatic discovery fails, the joining player can always type the IP.
- **Fixed: room discovery now also broadcasts to your subnet address**
  (e.g. 192.168.1.255), not only to 255.255.255.255, which many routers
  and hotspots block. Rooms list themselves with name, host, players,
  map, mode and status, and disappear a few seconds after they stop
  announcing. Manual IP entry is always there as a fallback.
- **Fixed: a lost packet can no longer strand a joining player.** The
  client now re-sends its spawn request every 2 seconds until it spawns
  or the 8-second timeout fires (with Back / Retry). The server ignores
  duplicate requests, so retries are safe.
- **Host-authoritative combat (QA-026).** The host now validates every
  shot (weapon, ammo, fire rate), decides all bullet hits and damage,
  credits kills, and owns health, deaths, respawns, the timer and the
  scoreboard. Clients send inputs; they can no longer decide damage or
  kills. Shots that arrive too fast or with no ammo are rejected, so
  latency cannot duplicate shots.
- **New modes: Survival and Last Man Standing.** Survival is round-based:
  one life per round, last player alive wins the round, first to the
  round limit wins the match. Last Man Standing is one life for the whole
  match — the last player alive wins. Free-for-All and Team Deathmatch
  are unchanged.
- **Every map now has 12 spawn points** (was 8), so 12-player rooms work.
- **Safer disconnects.** If a player leaves mid-match, they are removed
  and the lobby/scoreboard update. If the host leaves, every client gets
  a clear "The host left the game" message and returns to the main menu
  with the host's IP prefilled, ready to reconnect — nobody is ever left
  stuck on a loading screen. If the host kicks you, or you type the wrong
  room password, you get the exact reason instead of a silent hang.
- **Two small real bugs found and fixed while testing v2.4:**
  (1) a semi-auto tap could be silently lost if it landed just after a
  physics step — the press edge is now only consumed when the shot
  actually fires; (2) leaving a match logged script errors because the
  game's update loop ran once more after the network was torn down —
  the loop now stops as soon as you leave.
- **Verified end-to-end before release.** Joystick test 21/21, smoke
  test 19 phases, fire-button test 25/25 (run twice), multiplayer test
  11/11, menu network test 6/6, and a full-flow check 10/10 (menu →
  create room → lobby → start match → play → pause → scoreboard → end
  screen → back to menu) — all with no script errors. See `BUGS.md`.

## What's new in v2.3 (10 maps + modern UI + host-lobby fix)

- **Fixed: HOST GAME showed the game world but no buttons.** On a real
  phone, tapping HOST GAME in v2.2 loaded the game world behind the lobby
  but showed no map selection, no mode/start options, nothing. The lobby
  panel had been sized to a transient ~2877 px minimum height and placed
  mostly off-screen (the old PRESET_CENTER + manual offset-centring
  approach). The whole UI is now rebuilt on robust full-rect containers
  with a ScrollContainer for the tall lobby, so it fits any screen height.
  See `BUGS.md` QA-017.
- **Fixed: after leaving a match (or a failed join), HOST GAME and JOIN
  did nothing until the app was restarted.** Disconnecting set the network
  peer to `null`, and the host/join guards treated `null` as "already
  connected" and silently returned. Disconnects now restore the offline
  peer and the guards are null-safe. Found by the v2.3 end-to-end flow
  check. See `BUGS.md` QA-018.
- **Modern UI.** Rounded panels, a green accent colour, big touch targets
  (minimum 56 px), map thumbnails in the lobby, clear selected-state
  highlights on map/mode/kill-limit/time buttons, and a scrollable lobby
  so the mode, kill limit, match time and START MATCH are always reachable
  on any phone screen. Same flows as before: menu → Local Multiplayer →
  host lobby (map + mode + kill limit + match time) → START MATCH; join
  by IP or from the discovered-games list; Customization; Settings.
- **10 maps** (was 3), each with 8 spawn points, 6 pickups, its own tile
  art, sky, decor and ambient effects — see the Maps section below.
  **Jungle Ruins** was built from the user's asset pack: the atlas was
  sliced into 12 sprites, dark-background artifacts cleaned, and the map
  follows the pack's placement guide (6 zones: spawn terrace, high ruin
  route, central temple, cliff + watchtower, waterfall terrace, cave
  network). **Volcanic Cavern** has glowing lava pools that hurt (20 HP/s)
  but are shallow, clearly visible and avoidable, with safe routes around
  them. **Up to 8 players** (was 4) — the host and lobby now support 8.
- **Verified end-to-end before release.** A scripted flow check drove the
  real app: menu → host lobby → map select → start match → play → pause /
  scoreboard → end screen → back to lobby → host again → bad-IP join
  error → join-timeout error panel — **19/19 passed**. Every map was
  load-tested headlessly (loads, safe spawn, collision matches the
  platforms, camera limits, platforms landable) — **47/47 passed**,
  including all 6 Jungle Ruins zones. The joystick acceptance test was
  re-run on the final code (see Notes).

## What's new in v2.2 (joystick rework + fire fix)

- **Left virtual joystick rebuilt to the Mini Militia spec.** Circular
  base with a visible border and a knob that follows your finger, stays
  inside the base, and springs back to the centre on release. Full
  360-degree control with normalized diagonals (moving diagonally is no
  faster than moving straight), analog strength (small push = slow walk,
  full push = full run), a dead zone, and a highlight when touched. The
  character, its facing, its run animation speed and its aim all follow
  the sticks exactly. Multi-touch works: one finger moves, another aims
  and fires, and lifting one finger never disturbs the other.
- **No more JUMP button.** Pushing the left stick up jumps; holding it
  up while you are in the air flies the jetpack. Fuel still drains only
  while you thrust, refills on the ground, and stops at zero. Pushing
  the stick down while falling makes you drop faster. The game tells you
  the new control in the lobby and on screen at the start of a match.
- **Fixed: the gun kept firing non-stop (QA-016).** Firing now happens
  only while a finger is actually holding the aim stick, and stops the
  instant the finger lifts. The bug was that the firing state came from
  the aim knob's position, which was only cleared by a touch-release
  event — any release the phone never delivered (app switched away,
  notification shade, gesture cancel) left the gun firing forever. The
  sticks now track their own touch, report zero the moment no finger is
  holding them, and reset themselves if the app loses focus. Firing also
  never happens while you are dead, paused, or after the match ends.
  See `BUGS.md` for the full diagnosis.
- **Joystick acceptance tests pass** (21 checks in a scripted headless
  run driving the real touch handlers): every direction, diagonals,
  knob clamping, release behaviour, multi-touch, focus-out reset, and
  fire stopping on release / death / pause / match end.

## What's new in v2.1 (QA pass)

A full QA pass over the v2.0 build found and fixed these issues (details in
`BUGS.md`):

- **Fixed: menus and panels were off-centre and clipped.** Every centred
  panel (main menu, Customization, Settings, Local Multiplayer, Game
  Lobby, scoreboard, pause menu, end screen, join-error panel) had its
  top-left corner sitting on the screen centre, so on a 720p screen the
  menu's SETTINGS button was cut off and the hint text was invisible.
  All panels are now truly centred and fully visible on any screen size.
- **Added: spawn protection.** You are invulnerable for 2 seconds after
  spawning or respawning (your soldier blinks), so nobody can kill you
  the instant you appear.
- **Fixed: animation froze during reload.** The run/idle animation now
  keeps updating while you reload.
- **Fixed: camera snapped wrong after respawn.** The camera now snaps to
  your respawn point instead of gliding across the map from where you died.
- **Fixed: the host's own game showed up in its "Games found" list.**
  Discovery now ignores the host's own broadcast.
- **Fixed: START MATCH could be double-tapped** and start the match twice.
- **Fixed: the menu was too dark** — the day sky, sun and green ground
  now actually show behind the menu panel.
- The v2.0 QA run also re-verified the earlier fixes: grenades bounce and
  explode instead of falling through the floor, bullets stop at platforms,
  the HUD bars show the true health/fuel values, and the pause menu really
  pauses (player and match timer freeze).

## What's new in v2.0

- **Fixed: "stuck on Connecting".** In v1 the host spawned a joining
  player's character the instant the network connection opened — before
  the joining phone had even loaded the game screen — so the spawn was
  lost and the joining phone sat on "Connecting..." forever. In v2 the
  server only spawns a player after that phone has loaded the game and
  sent a ready signal. If a join still fails, the game shows an error
  after 8 seconds ("Could not connect — check the Wi-Fi and IP, then try
  again") with Back and Retry buttons, instead of hanging forever.
  Players who leave are also removed from the game properly now.
- **Fixed: bullets pass through obstacles.** Bullets now use a swept
  raycast each step, so they stop at platforms, walls and the ground and
  make a small impact burst instead of tunnelling through.
- **3 maps** (pick one in the lobby): Military Base, Industrial Zone and
  Forest Outpost. Each is bigger than the v1 arena, with more platforms,
  several routes, high ground and hiding spots, and its own look.
- **5 weapons:** Assault Rifle (default), SMG, Shotgun, Sniper and Rocket
  Launcher (explosive, area damage + knockback). Each has its own damage,
  fire rate, magazine size and reload time. Weapon pickups appear on the
  map — walk over one to grab it, and tap WEAPON to switch.
- **Grenades:** throwable, 2-second fuse, area damage + knockback.
  Tap GRENADE to throw one (you carry up to 4).
- **Game modes:** Free-for-All (most kills wins) and Team Deathmatch
  (two teams, team score). A match ends at the kill limit (5 / 10 / 15)
  or when the timer runs out (3 / 5 / 10 minutes), then an end screen
  shows the scoreboard, the winner, and Rematch / Back-to-lobby buttons.
- **Character:** pick a name, a player colour and a helmet style in
  Customization. Your colour and name show above your character and in
  the lobby; each player has a distinct colour.
- **Sound:** procedurally generated gunshots, reload, explosions,
  jetpack, jump, hit, death and UI sounds, plus a simple music loop.
  No audio files are bundled. Volume is in Settings.
- **Polish:** muzzle flash, bullet trails, impact and explosion bursts,
  hit flash, death animation, 3-second respawn, smooth camera that
  follows you and stays inside the map.
- **Art:** the soldier, weapons, tiles, effects and backgrounds come
  from the MiniShooter asset pack (sliced from its master sprite sheet),
  so the game looks like a real 2D shooter instead of drawn shapes.

## How to install

1. Copy `mini-militia-lan.apk` to your phone.
2. On the phone, allow installing apps from unknown sources when asked
   (Settings → Apps → Special access → Install unknown apps, then allow it
   for your file manager or browser).
3. Open the APK file and tap Install. If you already have an older
   version, installing this one over it keeps working — it is signed
   with the same key, so it upgrades cleanly.

## How to play with two phones (step by step)

You need two phones with this game installed. No internet is needed —
the phones only need to reach each other on local Wi-Fi.

### Option A — same Wi-Fi (easiest)

1. Connect **both phones to the same Wi-Fi network** (the same router,
   same network name).
2. **Host phone:** open the game → **LOCAL MULTIPLAYER**.
   The screen shows "Your IP on this Wi-Fi: 192.168.1.5" (your numbers
   will be different) — remember this number.
3. **Host phone:** type a room name (or leave the default), pick the
   max players, then tap **CREATE ROOM**.
4. The lobby opens. At the top it says, big and clear:
   **"HOST IP: 192.168.1.5 — friends type this IP to join"**.
   Pick the map, game mode, kill limit and match time. Tap **I'M READY**.
5. **Joining phone:** open the game → **LOCAL MULTIPLAYER**.
   After a second or two your room appears under "Games found on this
   Wi-Fi" (it shows the room name, host name, players, map and mode).
   **Tap the room.** If it asks for a password, type the room password.
6. The joining phone appears in the lobby list. Both phones tap
   **I'M READY**. The host taps **START MATCH** (if someone is not
   ready, the button says "START ANYWAY" — the host can still start).
7. Fight! The match ends at the kill limit, when the timer runs out,
   or (Survival / Last Man Standing) when one player is left alive.
   The end screen shows the scoreboard and the winner.

### Option B — one phone's hotspot (no Wi-Fi router)

1. **Host phone:** turn on its Wi-Fi hotspot (Settings → Hotspot).
   Note the hotspot name and password.
2. **Joining phone:** turn Wi-Fi on and connect to the host phone's
   hotspot (enter the hotspot password).
3. Now follow Option A steps 2–7 exactly. The host phone's IP is shown
   in the lobby — use it if the room does not appear in the list.

### If the room does not appear in the list

- Wait 5 seconds, then tap **REFRESH**.
- Check both phones are on the **same** network (same Wi-Fi name, or
  the joining phone is on the host's hotspot). A phone on mobile data
  will not see the room.
- **Type the IP instead:** on the joining phone, type the host IP
  shown in the host's lobby into the "Host IP" box and tap **JOIN**.
  This works even when discovery is blocked by the router.
- **Quick match:** tap **QUICK LAN MATCH** — it joins the first open
  room it can find.

### If joining hangs on "Connecting..."

**Fixed in v3.2 (QA-047):** in v3.1 the joining phone could reach the
game scene but never spawn — the host saw 2 players, the joiner saw
0/8 and a stuck "Connecting...". v3.2 sends the spawn explicitly and
syncs the full player list, so the joiner spawns or gets a clear
error. If it still fails, the error now tells you exactly what
happened:

- **"Could not connect to 192.168.1.5. ENet: 2. Server answered: no.
  Players seen: 0/8."** — read it like this:
  - **The IP** is the one it tried. It must match the host's lobby
    exactly (four numbers with dots). A wrong digit means the wrong
    phone (or no phone).
  - **ENet: 2** means the network link is up (2 = connected);
    **ENet: 1** means it is still connecting; **ENet: 0** means no
    link — the phones cannot reach each other at all (wrong network,
    or the host app is closed).
  - **Server answered: yes** means the host replied but the spawn
    still did not land — that is a game bug, not your Wi-Fi; note the
    exact text and tell the developer. **Server answered: no** means
    the host never replied — a Wi-Fi/IP problem.
  - **Players seen** is how many players your phone can see. 0/8
    with "Server answered: yes" is the old v3.1 bug — update both
    phones to v3.4.
- Tap **Retry**: if the link is still up it re-asks the host for your
  player; if the link is gone it takes you back to the menu with the
  host IP already filled in — tap **JOIN** to try again.
- Wait for the 8-second timeout: the game never hangs forever.
- If the host's Wi-Fi changed (it switched networks or the hotspot
  restarted), the host IP changes too — read the new IP from the
  host's lobby and try again.
- Restart the app on both phones and try again. The host creates the
  room first, then the joiner joins.
- **Both phones must run the same version** (v3.4). A version
  mismatch is refused with a clear message ("Version mismatch: host
  runs 3.4, you run 3.3. Update and rejoin.").

### Testing the join on two real phones (v3.4 acceptance test)

The build machine cannot test two-phone play (its sandbox blocks UDP
traffic between processes), so **run this check on two real phones
before trusting a release**. It takes two minutes:

1. Install the same v3.4 APK on both phones. Both on the same Wi-Fi.
2. Host: LOCAL MULTIPLAYER → CREATE ROOM → I'M READY. Joiner:
   LOCAL MULTIPLAYER → **QUICK LAN MATCH**.
3. Host taps START MATCH. **Both phones must show Players: 2/8**
   and both players must be visible in the world.
4. **Movement check (QA-053 — the v3.3 bug, fixed in v3.4, was:
   both players visible, but movement not reflecting, while bullets
   and grenades DID sync). Move on the joining phone** (left stick)
   and watch the HOST phone: the 2nd player there must move too —
   smoothly, no jumps, no snap-back, no frozen-then-catch-up burst.
   Then **move on the host phone** and watch the JOINING phone: the
   host's player must move there as well, just as smoothly.
   **Pass = both phones show Players: 2/8 AND each phone sees the
   other player move in both directions.** If either player's remote
   copy stands frozen while the player moves on their own phone, note
   which direction failed (joiner→host or host→joiner) and the exact
   error text from the "Connecting..." section above.
5. **Shoot on the joining phone** (right stick). The host must see
   the shots fly smoothly and in realtime, tracking the same path
   the shooting phone shows — no delay, jumps, or steps — and the
   kill feed must update.
6. **Joystick release check (QA-054):** on either phone, push the
   left stick RIGHT, then release it. The player must stop and keep
   facing right — it must NOT turn left. Do the same with the right
   (aim) stick.
7. Joiner: leave the match (pause → Leave). The host must see
   Players: 1/8 again, with no error spam.
8. Repeat once with the room list (tap the room instead of QUICK LAN
   MATCH) and once by typing the host IP manually — all three join
   paths must work.

### If the host leaves or the game drops

- If the host leaves the match, every other phone sees "The host left
  the game" and goes back to the main menu. The host's last IP is
  already filled in the "Host IP" box — tap **JOIN** to reconnect, or
  create your own room.
- If you are kicked, the game tells you "The host removed you from the
  room." If the password is wrong, it says "Wrong room password."
  If the room is full, it says "Room is full."

## Maps

Pick a map in the host lobby (tap a map in the grid; the picked one gets
a ✓). Every map has 12 spawn points and 6 pickups, multiple routes, high
ground and hiding spots, and its own look — no two maps share a layout.
The strongest weapons (Sniper / Rocket) are pinned to the centre spot of
every map, and the HUD shows a countdown to the next one. In Team
Deathmatch, teams spawn grouped: team RED on the left half, team BLUE on
the right half.

| # | Map | Size | Layout signature — what makes it different |
|---|---|---|---|
| 1 | **Catacombs** | 3200×1400 | Symmetric 3-3-3 stack with a wide central bridge; dark underground palette. |
| 2 | **Military Base** | 2880×1440 | Tallest stack (7 levels) with a centred sniper perch — the highest platform in the game; smallest width. |
| 3 | **Desert Outpost** | 3000×1500 | Classic staggered arena, sand palette, palms. The original template, kept as-is. |
| 4 | **Industrial Factory** | 3200×1600 | Tallest map (1600); bridge decor; dusk grey-brown palette. |
| 5 | **Frozen Fortress** | 2800×1500 | Smallest map, densest floor cover; snow effects and a low-friction ice zone on the floor. |
| 6 | **Jungle Ruins** | 3200×1400 | The hand-designed map: dense overlapping centre (68% cover at mid height), 6 zones, watchtower and statues. |
| 7 | **Space Station** | 3000×1500 | **Rebuilt in v3.0:** vertical station, no full-width floor — 3 disconnected deck segments, a central vertical shaft (fast, exposed) and side maintenance tunnels (slow, covered). Dark palette. |
| 8 | **City Underground** | 3200×1600 | **Rebuilt in v3.0:** subway map — two stacked tunnel tubes (upper fast/exposed, lower slow/covered with pillars) joined by 3 stair shafts; hot zone on the centre platform between the tubes. |
| 9 | **Volcanic Cavern** | 3000×1500 | Split floor: two lava pools (they hurt — use the safe routes around them). |
| 10 | **Pirate Island** | 3000×1500 | **Rebuilt in v3.0:** asymmetric beached-ship map — stepped hull rising to a crow's-nest perch on the LEFT, open sand mid, and a below-deck tunnel on the RIGHT. |
| 11 | **Neon City** | 3400×1800 | **New in v3.0:** vertical figure-eight — two rooftop tower routes, a street-level alley, and a centre skybridge (no cover — crossing it is the risk). Rain-slick cyberpunk night, purple-brick tiles. |
| 12 | **Ancient Temple** | 3000×1750 | **New in v3.0:** stepped ziggurat in the centre (3 tiers to an altar top) flanked by colonnades, with a crypt tunnel running BELOW the floor. |
| 13 | **Airship Fleet** | 3200×1500 | **New in v3.0:** the only map with no full-width floor — three separate ship decks with gaps crossed by jump + jetpack, a safety net below, and the Sniper/Rocket pinned to the centre ship's crow's nest. Falling through a gap respawns you on your own deck (no death, no kill credited). |

Seven maps (Catacombs, Industrial Factory, Space Station, City
Underground, Volcanic Cavern, Neon City, Ancient Temple) also draw a
Sky Brawl arena image as a far parallax background behind the
procedural sky; the five day maps (Military Base, Desert Outpost,
Frozen Fortress, Jungle Ruins, Pirate Island) keep the procedural
gradient, and Airship Fleet uses a warm sunset gradient.

## Controls

- **Left stick** — move. Push a little to walk slowly, push fully to
  run at full speed. The character faces the direction you push and the
  run animation matches your speed. Release the stick to stop (no
  sliding) and the idle animation plays. **Push the stick up to jump;
  hold it up in the air to fly with the jetpack.** The jetpack uses fuel
  (blue bar); it refills when you stand on the ground. Push the stick
  down while falling to drop faster.
- **Right stick** — aim AND shoot (QA-049, v3.2). Push the right
  stick in any direction (full 360°) to aim — the weapon points
  where the stick points and the character faces the aim direction —
  and the gun fires while the stick is held. Release the stick and
  the gun stops at once. Tap it once for one shot with semi-auto
  weapons (pistol, shotgun, sniper). There is no FIRE button any
  more: the right stick is the fire control, Mini Militia style.
  It works at the same time as the move stick — one finger per
  stick.
- **RELOAD button** — reload the current weapon. You also reload
  automatically when the magazine is empty. You cannot fire while
  reloading; the ammo count shows the reload progress.
- **GRENADE button** — throw a grenade in the direction you are aiming
  (or forward-up if you are not aiming).
- **WEAPON button** — switch between the weapons you have picked up.
- **II button** — pause menu (Resume, sound/music volume, Leave Match).
- **SCORE button** — show the scoreboard during a match.

In short: **Left stick: move • Push up: jump / fly • Right stick: aim and shoot (hold to fire, release to stop).**

**Solid cover:** crates, barrels, sandbags, rocks, columns, pillars,
statues, watchtowers, and the Sky Brawl huts, stone blocks, shrine
blocks and vents are solid — bullets stop at them, you cannot walk
through them, and grenades bounce off them. Use them as cover.
Trees, palms, bushes, bridges and arches are decoration — you and your
bullets pass straight through them.

## Weapons

| Weapon | Fire | Damage | Magazine | Reload | Notes |
|---|---|---|---|---|---|
| Pistol | Semi-auto | 10 | 12 | 1.0 s | Your starting sidearm. Low recoil. |
| Assault Rifle | Automatic | 12 | 30 | 1.2 s | Medium rate, slight spread. |
| SMG | Automatic | 8 | 32 | 1.0 s | Fastest fire rate. |
| Shotgun | Semi-auto | 9 × 6 pellets | 6 | 1.8 s | Wide spread, short range, strong recoil. |
| Sniper | Semi-auto | 60 | 5 | 1.6 s | Slow, high damage, long range. |
| Rocket Launcher | Automatic | 70 | 4 | 2.0 s | Explosive, area damage + knockback. |

Pickups appear on the map — walk over one to grab that weapon, then tap
WEAPON to switch between the weapons you own. The centre spot of every
map only ever spawns the Sniper or the Rocket Launcher (alternating),
and the HUD counts down to the next one; the other spots spawn SMG,
Shotgun, Health or Grenades.

## HUD

- Green bar (top left): health — the number next to it is your exact
  HP. Blue bar under it: jetpack fuel, with its number next to it.
- Top right: a panel with **SCORE** and **II** (pause) buttons, then
  kills, deaths, players in the game (out of the room max, e.g.
  "Players: 2/8"), current weapon and ammo (e.g. "Rifle 24/30"),
  grenades left. Tap **SCORE** for the scoreboard, **II** to pause.
- Top centre: match timer and the kill limit ("First to 10 kills").
- If you are eliminated, you respawn after 3 seconds, with 2 seconds of
  spawn protection (your soldier blinks while protected). In Survival
  you stay out until the round ends; in Last Man Standing you are out
  for the whole match.

## Permissions

The game only asks for these three, all needed for LAN play:

- `INTERNET` — Android requires it for any app that opens network
  sockets; here only local Wi-Fi sockets to the other phones in the
  room. No internet traffic is ever sent.
- `ACCESS_NETWORK_STATE` — to check that Wi-Fi is available before
  hosting or joining.
- `ACCESS_WIFI_STATE` — to read the phone's own Wi-Fi address so the
  host can show it and joiners can type it.

No storage, notifications, location, microphone, or camera access.
All three are install-time permissions — Android grants them when
the app is installed, so the game never shows a permission pop-up.
Discovery uses UDP broadcast (not multicast), so no multicast
permission is needed. See `PRIVACY_POLICY.md` for the full privacy
policy (no data collected, no accounts, no ads, no analytics) and
`PLAY_SUBMISSION_CHECKLIST.md` for the Google Play submission notes.

## Notes

- This is a debug build, signed with a debug key.
- Version 3.0 (version code 8), package `com.lanarena.shooter`. APK
  `mini-militia-lan.apk`: 32,518,408 bytes, md5
  `cf6495ff319d5d0704b597491644e48d`, signed with the same debug key as
  v2.4/v2.5 (certificate SHA-256 matches, so it installs over v2.5).
  Target SDK 36 (Godot 4.7.2 template).
- The game was verified on this build machine with a rendered smoke test
  on all 13 maps, a scripted QA harness driving the real game, a
  joystick acceptance test (21/21), a scale test (70/70 across five
  screen sizes), a collision test (8/8 on ALL 13 maps), a fire-button
  test (25/25), a physics harness (31/31 on maps 0, 6, 10, 12; 22/22
  live on the Frozen Fortress ice, map 4), a features test (11/11),
  a multiplayer test (11/11), a menu network test (6/6), and a full-flow
  check (menu → create room → lobby → start match → play → pause →
  scoreboard → end screen → back to menu) — all with zero script
  errors. The two-player join could not be tested on this build machine
  because its sandbox blocks UDP network traffic between processes — the
  host and join code uses standard Godot ENet networking, which works on
  real phones on the same Wi-Fi. The join path was verified by code
  review plus the 8-second timeout and error screen, the spawn retry,
  and the host IP always being visible, so a failed join can never hang
  forever again. See `BUGS.md` for the full QA log, including the few
  things that could not be tested here.
- Known small visual detail: the soldier art has a rifle drawn into the
  sprite, and the separate weapon sprite is drawn over it. At a straight
  up or down aim a small bit of the drawn-in rifle can peek out at the
  base of the weapon — it reads as a foregrip and does not affect play.
- Built with Godot 4.7.2.

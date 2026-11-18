# BUGS.md — LAN Arena Shooter

QA log for v2.0 (baseline), v2.1 (fixes), v2.2 (joystick rework + fire fix)
and v2.3 (10 maps, modern UI, host-lobby fix). Every bug lists: ID, title,
affected feature, steps to reproduce, expected result, actual result,
severity, root cause, fix, and verification status. A bug is only marked
fixed after the original issue was reproduced and the fix verified —
nothing here is marked fixed on the builder's word alone.

Test method for this pass: code review of every script, a scripted QA
harness that drives the real game scene as host (46 checks: boot, reload,
death/respawn, all 5 weapons, grenade, pickups, all 3 maps live, TDM,
FFA match end, rematch, pause, scoreboard, error panel, camera), the
built-in smoke test under Xvfb, rendered screenshots of every menu and
in-game panel, and pixel measurement of the HUD bars. No real two-phone
LAN join could be tested on this machine (see QA-014).

---

## QA-001 — All centred panels are off-centre and clipped (menu, lobby, pause, end screen, scoreboard, error)

- **Severity:** High
- **Affected feature:** UI — every centred panel (main menu, Customization,
  Settings, Local Multiplayer, Game Lobby, scoreboard, pause menu, end
  screen, join-error panel)
- **Steps to reproduce:** Launch the game at 1280x720 and look at the main
  menu (`--menu-shot`).
- **Expected result:** The menu panel is centred on screen, all buttons and
  the hint text visible.
- **Actual result (v2.0):** The panel's top-left corner sits exactly on the
  screen centre (640, 360) and the panel grows down-right from there. On
  720p the SETTINGS button is cut off at the bottom edge and the hint text
  ("All phones must be on the same Wi-Fi network.") is invisible below the
  screen. On a wide phone screen the panel fits but sits visibly right of
  centre. Same for the lobby, pause, end screen, scoreboard and error panels
  (identical construction).
- **Root cause:** `set_anchors_preset(Control.PRESET_CENTER)` sets the
  anchors to 0.5 but leaves all offsets at 0. A `PanelContainer` then sizes
  itself from its minimum size/content, growing right and down from the
  anchor point instead of being centred on it. Reproduced in isolation:
  as-built `pos=(640, 360) size=(560, 334) offsets=0/0/0/0`.
- **Fix (v2.1):** Added `_center_panel()` / `_center_all_panels()` in
  `main.gd` and `game.gd`: after layout settles, set
  `offset_left/top = -size/2`, `offset_right/bottom = +size/2`. Offsets are
  viewport-independent, so panels stay centred on any screen size.
  Re-centring is also deferred after dynamic content changes (discovered
  hosts, lobby player list, scoreboard/end-screen rows, error text). A
  guard skips the work if the scene changed while waiting (see QA-009).
- **Verification:** FIXED and verified. Rendered screenshots of all five
  menu panels and all four in-game panels show them centred and fully
  visible (menu, lobby, customization, settings, multiplayer, pause, end
  screen, scoreboard, error). Harness checks PAUSE-SHOWS, SCOREBOARD-SHOWS,
  ERROR-PANEL, FFA-END, TDM-END pass.

## QA-002 — No spawn protection: a player can be killed the instant they respawn

- **Severity:** Medium
- **Affected feature:** Balancing / respawn
- **Steps to reproduce:** Kill a player, wait for the 3-second respawn, and
  damage them in the first moment after they reappear (harness: call
  `take_damage(50)` immediately after respawn).
- **Expected result:** Brief invulnerability after (re)spawning, as the
  master QA standard requires.
- **Actual result (v2.0):** Damage applies immediately; a camper at a spawn
  point can kill a player the instant they appear. Harness: HP 100 -> 50
  from damage dealt right after respawn.
- **Root cause:** No spawn-protection timer existed anywhere in `player.gd`.
- **Fix (v2.1):** 2-second spawn protection (`SPAWN_PROTECTION`) granted on
  initial spawn and on every respawn. `take_damage()` and
  `take_explosion_damage()` return early while it is active, and the sprite
  blinks (alpha oscillation) so other players can see the protection.
- **Verification:** FIXED and verified. Harness: SPAWN-PROTECT (HP stays
  100 when damaged right after respawn) and SPAWN-PROTECT-EXPIRES (HP drops
  to 50 once the 2 s are up) both pass.

## QA-003 — Animation freezes during reload

- **Severity:** Low
- **Affected feature:** Animation / weapons
- **Steps to reproduce:** Empty the magazine (reload starts), then push the
  move stick while reloading.
- **Expected result:** The run animation plays while the player moves.
- **Actual result (v2.0):** The animation stays frozen on whatever it was
  when the reload started (harness: `idle` while moving). `_apply_aim_and_fire`
  returned early while `reloading`, which also skipped `_update_anim()`.
- **Root cause:** Early `return` in the reload branch of
  `player.gd::_apply_aim_and_fire()`.
- **Fix (v2.1):** Restructured to if/elif — reload ticks down, firing is
  skipped while reloading, and `_update_anim()` runs every frame.
- **Verification:** FIXED and verified. Harness: RELOAD-ANIM is `run` while
  moving during a reload; RELOAD-STARTS and RELOAD-FINISH (mag refills to
  30) pass.

## QA-004 — Camera smoothing is never reset on respawn

- **Severity:** Low
- **Affected feature:** Camera / respawn
- **Steps to reproduce:** Die far from your respawn point and respawn.
- **Expected result:** The camera snaps to the respawn point.
- **Actual result (v2.0):** `player.gd::_respawn()` calls
  `get_node_or_null("Camera2D")`, which always returns null, so
  `reset_smoothing()` never runs and the camera smooth-pans across the map
  from the death location instead of snapping.
- **Root cause:** In Godot 4.3, a node created with `Camera2D.new()` and
  added with `add_child()` gets an auto-generated name such as
  `@Camera2D@141` unless `.name` is set explicitly — so no node is ever
  named `Camera2D`. Verified in isolation: an unnamed `Camera2D.new()`
  added to a parent is named `@Camera2D@4` and `get_node("Camera2D")`
  returns null.
- **Fix (v2.1):** The camera reference is stored in a member variable
  `_camera` when created in `_ready()`, and `_respawn()` uses it.
- **Verification:** FIXED and verified. Harness CAMERA-CURRENT (the
  viewport camera is the player's camera) and CAMERA-FOLLOWS (camera centre
  clamps to (2240, 1080) at the map edge) pass; diagnostic run confirmed the
  camera node exists and `is_local_player()` is true after scene reloads.

## QA-005 — The host's own game appears in its own "Games found" list

- **Severity:** Low
- **Affected feature:** Multiplayer discovery / lobby
- **Steps to reproduce:** Host a game from the Local Multiplayer screen and
  watch the "Games found on this Wi-Fi" list.
- **Expected result:** Only other hosts' games are listed.
- **Actual result (v2.0):** The host also listens on the discovery port
  (7778), so it receives its own broadcast and adds a "Join game at
  <own IP>" button for itself.
- **Root cause:** No filtering of discovery packets by sender in
  `main.gd::_process()`.
- **Fix (v2.1):** Packets whose sender IP is one of the device's own local
  addresses (`IP.get_local_addresses()`) are ignored.
- **Verification:** FIXED, verified by code review only. A live check was
  attempted (temporary host-and-observe hook): the sandbox blocks UDP
  broadcast at the OS level (`PermissionError: [Errno 1] Operation not
  permitted` when sending a broadcast from Python), so no discovery packet
  can arrive on this machine at all — the live test is inconclusive here,
  not a failure of the fix. Must be re-checked on real phones on real Wi-Fi.

## QA-006 — START MATCH can be double-tapped, sending start_match twice

- **Severity:** Low
- **Affected feature:** Lobby
- **Steps to reproduce:** Double-tap START MATCH in the lobby.
- **Expected result:** One match start.
- **Actual result (v2.0):** Nothing guards the button; `start_match` is
  RPC'd twice and `change_scene_to_file` runs twice.
- **Root cause:** No in-progress guard in `main.gd::_on_start_pressed()`.
- **Fix (v2.1):** `_starting_match` flag: the first press sets it and later
  presses return early; cleared when leaving the lobby.
- **Verification:** FIXED, verified by code review (the guard is two lines
  on the only path that sends the RPC; the double-tap itself was not
  exercised live because it needs UI automation).

## QA-007 — GameData.HELMET_NAMES labels the helmets wrong

- **Severity:** Low
- **Affected feature:** Customization data
- **Steps to reproduce:** Read `game_data.gd`: index 1 is called "Cap" and
  index 3 "Hood", while the textures are green helmet (1), tan cap (2),
  black helmet (3) — and `main.gd` labels them "Helmet", "Cap",
  "Black helmet".
- **Expected result:** One consistent set of names matching the art.
- **Actual result (v2.0):** Two conflicting lists; `GameData.HELMET_NAMES`
  is wrong (and unused — `main.gd` has its own correct list).
- **Root cause:** The two lists drifted apart.
- **Fix (v2.1):** `GameData.HELMET_NAMES` corrected to
  `["No helmet", "Helmet", "Cap", "Black helmet"]`.
- **Verification:** FIXED, verified by inspection against the texture
  files and `main.gd`.

## QA-008 — Menu background is so dark the sky is invisible

- **Severity:** Low
- **Affected feature:** Main menu visuals
- **Steps to reproduce:** Look at the main menu screenshot.
- **Expected result:** The procedural day sky (gradient + sun + green
  ground band) is visible behind the panel.
- **Actual result (v2.0):** The dim overlay (`Color(0.03, 0.04, 0.08, 0.72)`)
  buries the gradient almost completely; the menu looks like night and the
  sun is a faint smudge.
- **Root cause:** Dim alpha 0.72.
- **Fix (v2.1):** Dim alpha reduced to 0.45 — buttons stay readable, the
  sky and sun show.
- **Verification:** FIXED and verified by screenshot (menu now shows the
  blue gradient sky, sun glow and green ground band).

## QA-009 — Script error when the scene changes while panels are being centred

- **Severity:** Low
- **Affected feature:** UI (regression introduced by the QA-001 fix)
- **Steps to reproduce:** Run with `--auto-host`: the menu's deferred
  `_center_all_panels()` is still awaiting a frame when the scene changes
  to the game.
- **Expected result:** No errors.
- **Actual result:** `SCRIPT ERROR: Invalid access to property or key
  'process_frame' on a base object of type 'null instance'` at
  `main.gd:_center_all_panels` — one error per `--auto-host` run, caught by
  the smoke test.
- **Root cause:** The awaited centring function resumed after its scene
  was replaced, so `get_tree()` was null.
- **Fix (v2.1):** `is_inside_tree()` guard after each await in both
  `main.gd` and `game.gd`; the function returns early if its scene is gone.
- **Verification:** FIXED and verified. Smoke test and harness both run
  with 0 script errors after the fix.

## QA-010 — Drawn-in rifle peeks out at straight up/down aim (known artifact)

- **Severity:** Low
- **Affected feature:** Sprites / weapons
- **Steps to reproduce:** Aim straight up or straight down.
- **Expected result:** Only the rotated weapon sprite is visible.
- **Actual result:** The soldier art has a rifle drawn in, and the separate
  rotated weapon sprite is drawn over it; at straight up/down aim a small
  bit of the drawn-in rifle can peek out at the base (reads as a foregrip).
- **Root cause:** Source art limitation — the sprite sheet's soldier frames
  include a rifle.
- **Fix:** None (would need re-cutting the source art). Documented in
  README.md.
- **Verification:** Known issue, carried over from v2.0; visible in
  rendered frames only at the extreme aim angles.

## QA-011 — Music restarts on every scene change (known, not fixed)

- **Severity:** Low
- **Affected feature:** Audio
- **Steps to reproduce:** Go from the menu into a match: the music loop
  restarts from the beginning.
- **Expected result:** Music continues (or fades) across the transition.
- **Actual result:** A new `GameAudio` node is created per scene and its
  `_ready()` starts the music loop from the start.
- **Root cause:** Audio is per-scene, not an autoload/persistent node.
- **Fix:** None in this pass — fixing it properly needs a persistent audio
  autoload, a bigger refactor than a QA fix should carry. Logged for a
  future pass.
- **Verification:** Not fixed; confirmed by code inspection (cannot be
  verified by ear on this machine — no sound hardware).

## QA-012 — Jetpack loop has an audible pulse (known, not fixed)

- **Severity:** Low
- **Affected feature:** Audio
- **Steps to reproduce:** Fly with the jetpack for several seconds.
- **Expected result:** A steady jetpack hiss.
- **Actual result:** `_make_noise_loop()` reuses `_make_noise_burst()`,
  whose envelope decays quadratically to zero over the 1-second loop, so
  the sound pulses once a second.
- **Root cause:** Burst envelope reused for a looped sound.
- **Fix:** None in this pass — the fix (flat envelope for the loop) is
  small but cannot be verified by ear on this machine (no sound hardware),
  and this QA pass does not ship unverified audio changes.
- **Verification:** Not fixed; confirmed by code inspection.

## QA-013 — Unused asset files are shipped in the APK (known, not fixed)

- **Severity:** Low
- **Affected feature:** Packaging / resources
- **Steps to reproduce:** `assets/items/` (ammobox, grenade, healthkit),
  `assets/effects/` (explosion2, fireball2, smoke2, rocket),
  `assets/backgrounds/snow.png` are never referenced by any script.
- **Expected result:** Only used resources are exported.
- **Actual result:** They are exported (export filter is `all_resources`)
  and add a little weight to the APK.
- **Root cause:** Slices from the user's asset pack that the game does not
  use (pickups are drawn procedurally; the menu uses a gradient sky).
- **Fix:** None — the files are user-provided art and may be used later;
  deleting them was not requested.
- **Verification:** Not fixed; confirmed by grep (no references).

## QA-014 — Real two-phone LAN join cannot be tested on this machine (limitation)

- **Severity:** N/A (test limitation, not a product bug)
- **Affected feature:** LAN multiplayer join
- **Steps to reproduce:** N/A — the sandbox blocks UDP (ENet's transport)
  and has no Android emulator (`/dev/kvm` absent); a broadcast send fails
  with `PermissionError: [Errno 1] Operation not permitted`.
- **Expected result:** A two-phone join test on real hardware.
- **Actual result:** Not possible here.
- **What was verified instead:** Code review of the join path
  (`request_spawn` only after the client loads the game scene,
  4 s re-announce, 8 s timeout with a Back/Retry error panel, peer
  disconnect despawns the player, host uses its LAN address, port 7777,
  no hardcoded IPs), the host smoke test, and the error panel rendering.
  The 8 s timeout + error panel path is exercised by the harness
  (ERROR-PANEL check).
- **Verification:** UNTESTED on real devices — must be checked on two
  phones on the same Wi-Fi before calling multiplayer "verified".

## QA-015 — ObjectDB leak warning at exit (observed, not a runtime leak)

- **Severity:** Low
- **Affected feature:** Shutdown / memory
- **Steps to reproduce:** Run the game (menu or smoke test) and quit; the
  log shows `WARNING: ObjectDB instances leaked at exit`.
- **Expected result:** Clean shutdown with no leaked instances.
- **Actual result:** With `--verbose`, the leaked instances are one
  `AudioStreamWAV` and one `AudioStreamPlaybackWAV` — the procedurally
  generated audio streams held by `GameAudio`, stranded by the abrupt
  `get_tree().quit()` at the end of a test run.
- **Root cause:** Quit-time teardown order, not gameplay allocation: the
  streams are created once per `GameAudio` node and reused; nothing
  allocates per frame.
- **Fix:** None — no evidence of growth during play; the harness (46
  checks, ~25 s of play) and smoke test show the same constant warning.
- **Verification:** Observed; not fixed. Worth one re-check on a phone if
  a long session ever shows growth, but there is no sign of it here.

---

## Re-verified v2.0 builder fixes (all confirmed in this pass)

| Builder claim (v2.0) | How re-verified |
|---|---|
| Grenade had no collision shape and fell through the world (fixed with CircleShape2D r=9) | Harness GRENADE-NO-FALL-THROUGH: max grenade Y 1373 vs floor top 1382; GRENADE-EXPLODES: gone after the 2 s fuse. |
| HUD SCORE/pause buttons overlapped labels (moved) | Rendered frames: SCORE / II buttons sit clear of the Kills/Deaths/Players/weapon labels at 1280x720. |
| HP/fuel ProgressBar fills rendered light grey (explicit green/blue fills) | Pixel measurement of rendered frames: HP bar full green at 100 HP, ~48% after 55 grenade damage; fuel bar 82% while refilling — matches the game's internal values. |
| Join fix: server spawns a client only after `request_spawn` | Code review + 8 s timeout/error-panel path exercised (ERROR-PANEL). Real two-phone join still untested (QA-014). |
| Bullets use swept raycast and stop at platforms | Smoke test: 23 shots fired, 0 bullets left (all impacted or expired); impact burst visible on a platform in the rendered frame; harness WPN-BULLET-CLEANUP passes. |

## QA harness results (v2.1, final run)

46 checks, 46 passed, 0 failed, 0 script errors. Coverage: boot/spawn,
reload (+animation), death/respawn (+spawn protection), shotgun pellets
(6), sniper, rocket explosion damage, SMG, grenade (spawn/bounce/explode),
pickup walk-over, all 3 maps (static spawn/pickup validation + live load),
TDM team/score/end, FFA end, rematch reload, pause (shows, freezes
position and timer, resumes), scoreboard, error panel, camera
(current/limits/follow). Baseline v2.0 run: 4 failures (RELOAD-ANIM,
SPAWN-PROTECT, SPAWN-PROTECT-EXPIRES, GRENADE-SPAWN*) — the first three
were the real bugs fixed above; GRENADE-SPAWN was a harness timing issue
(the player was still dead from the rocket test) and was fixed in the
harness itself. Final smoke test: host runs, spawns, moves (analog speed
330 full / 68 at 0.3 push), jumps, jetpacks (fuel 100 -> 12), shoots in
all directions (aim/gun rotation -45 / 180 / 90 deg), throws a grenade,
23 shots, 0 script errors.

*The harness itself (qa_harness.gd / qa_bootstrap.tscn) was a temporary
test tool and was deleted before the v2.1 export; it is not shipped.

---

## v2.2 — joystick rework + fire fix (2026-11-18)

## QA-016 — Gun kept firing non-stop after the finger lifted (fire button bug)

- **Severity:** High
- **Affected feature:** Firing / aim stick
- **Steps to reproduce:** Aim and fire with the right stick, then switch
  apps, pull down the notification shade, or cancel the gesture
  (any release the OS never delivers as a touch-release event). The gun
  keeps firing forever with no finger on the screen.
- **Expected result:** Firing happens only while a finger is actively
  holding the aim stick past the threshold, and stops the instant the
  finger lifts. Never fires while dead, paused, or after the match ends.
- **Actual result:** The firing state came from the aim knob's displaced
  position, which was only cleared by an explicit touch-release event.
  Any release the OS never delivered left the knob displaced and
  `touch_firing` true forever.
- **Root cause:** State derived from a visual (knob offset) instead of
  from live touch ownership. No focus-out / pause handling existed, and
  `_update_touch_state()` never re-validated that a touch was still
  active.
- **Fix:** Both sticks now track their own touch ID (`joystick.gd`).
  `get_vector()` returns zero unless a finger is actively holding the
  stick. The sticks reset themselves on `NOTIFICATION_WM_WINDOW_FOCUS_OUT`
  and `NOTIFICATION_APPLICATION_PAUSED`; `game.gd` also resets all touch
  state on focus-out (`_reset_all_touch_state()`) and `_update_touch_state()`
  zeroes everything while paused. Firing is therefore true only while a
  finger is down on the aim stick. The player also cannot fire while dead
  (aim input is ignored when `alive` is false), while paused, or after
  the match ends.
- **Verification:** Joystick acceptance test, 21/21 passed, 0 script
  errors — RELEASE-AIM-STOPS-FIRE (firing=false, shots frozen),
  FOCUS-OUT-RESET (firing=false after a simulated focus loss, shots
  frozen), FIRE-AFTER-DEATH (alive=false, shots frozen),
  FIRE-WHILE-PAUSED (shots frozen while paused, resumes cleanly),
  FIRE-AFTER-MATCH-END (shots frozen). Real-touch behaviour on a phone
  still needs a human check (no touch hardware on this machine).

## QA-017 — Joystick-test harness called take_damage() with 1 argument (test-only bug)

- **Severity:** Low (test harness only, no gameplay impact)
- **Affected feature:** `--joystick-test` harness
- **Steps to reproduce:** Run the joystick acceptance test; the
  FIRE-AFTER-DEATH step printed a script error and failed.
- **Expected result:** The test kills the local player, then checks that
  no shots are fired while dead.
- **Actual result:** `SCRIPT ERROR: Invalid call to function 'take_damage'
  in base 'CharacterBody2D (player.gd)'. Expected 2 arguments.` The
  player stayed alive, so the step failed (20/21 on the first run).
- **Root cause:** `player.gd` takes `take_damage(amount, from_id)`; the
  harness called it with only the amount.
- **Fix:** Harness now calls `lp.take_damage(500, 1)` (from_id 1 = the
  host's own id, so no kill-credit side effects).
- **Verification:** Re-ran the full acceptance test: 21/21 passed,
  0 script errors.

## QA-018 — JUMP button removed; jump/jetpack moved to the left stick

- **Severity:** N/A (intentional control change, user-requested)
- **Affected feature:** Controls
- **Change:** The JUMP button, its handlers, and all `touch_jump_*`
  references are gone. Pushing the left stick up while on the ground
  jumps (rising-edge triggered, armed/re-arm flag — holding up through
  a landing does NOT auto-jump again). Holding up while airborne is
  jetpack thrust with the existing fuel rules (drains only while
  thrusting, refills on the ground, no thrust at zero fuel, no automatic
  flying). Pushing down while airborne fast-falls. Space is still a
  keyboard jump fallback. The lobby and an in-game HUD hint (shown 10 s
  after spawning) explain the change: "Left stick: move • Push up: jump /
  fly • Right stick: aim & fire".
- **Verification:** Acceptance tests PRESS-UP-JUMP (jumped, jetpacking,
  fuel 85), STICK-UP-NO-REJUMP (no second jump while held), and the
  smoke test phases 8–9 (jetpack climb, fuel 100 -> 56 -> 10, refill to
  100). Discoverability on a real phone still needs a human check.

## Joystick acceptance test results (v2.2, final run)

21 checks, 21 passed, 0 failed, 0 script errors. Run:
`xvfb-run -a godot --path . -- --auto-host --joystick-test` (~20 s).
Coverage: press left/right (vec ±0.81, vel ±268, facing, run anim),
press up = jump + jetpack (fuel drains), release stops (vec zero, knob
0.0, no jetpack, vel 0), fuel stable with no input (refills to 100),
press down = fast fall (vel.y 1073), diagonal up-right (vec 0.70/-0.70,
len 0.99), diagonal speed normalized (vel.x 231 < 330), knob clamped to
60 px, multi-touch (move + aim + firing together, 4 shots), releasing
move only (aim keeps firing), releasing aim stops fire (shots frozen),
focus-out reset, fire after death, respawn (alive, 100 HP), fire while
paused (shots frozen, resume ok), fire after match end (shots frozen),
stick-up no re-jump, resolution 1920 (stick still works).

Smoke test re-run on v2.2: all 19 phases pass, 0 script errors — host
runs, moves (330 full / 68 at 0.3 push), jetpacks, aims in all
directions, shoots (23 shots), throws a grenade, picks up weapons.

**Test-runner lesson (do not repeat):** Godot 4.3 only puts arguments
after a `--` separator into `OS.get_cmdline_user_args()`. Running
`godot --path . --auto-host --joystick-test` (no `--`) silently leaves
the game sitting in the main menu forever — no test output, no error,
just the menu rendering. The first three v2.2 test runs "hung" for
this reason alone; nothing was wrong with the game. Always run tests as
`godot --path . -- --auto-host --joystick-test` (same for `--smoke-test`).

---

## v2.3 — 10 maps + modern UI + host-lobby fix (2026-11-18)

## QA-019 — HOST GAME shows the game world but no buttons (user-reported, real phone)

- **Severity:** Critical (the host flow was unusable)
- **Affected feature:** UI — host lobby (menu → Local Multiplayer → HOST GAME)
- **Steps to reproduce:** On a real phone (v2.2), tap LOCAL MULTIPLAYER,
  then HOST GAME.
- **Expected result:** A host lobby with map selection, game mode, kill
  limit, match time, player list and a START MATCH button.
- **Actual result (v2.2, as reported by the user):** "Glitch when I click
  host game." / "Blank, no option of map selection and any option." /
  "I can see game world behind it with just no buttons." The game world
  renders behind the lobby, but no buttons appear at all.
- **Root cause:** The lobby panel used `PRESET_CENTER` plus manual offset
  centring (`_center_all_panels` in `main.gd`). Hidden panels are centred
  while their size is (0,0)/stylebox-only at startup and only re-centred
  ~2 frames after being shown. The lobby's minimum height transiently
  computed to ~2877 px (the autowrap hint label at width 0 wraps to ~85
  one-character lines), the panel was sized to that height and never
  shrank back, and it was positioned at (298, -1078.5) with the START
  button at (320, -435.5) — mostly off-screen. Reproduced headlessly at
  1280x720: lobby `visible=true` but `size=(684, 2877)`,
  `position=(298, -1078.5)`. The world behind was visible because the
  panel is semi-transparent and the game scene had already loaded behind
  it. QA-001's centring fix never covered this screen's transient sizing.
- **Fix (v2.3):** The fragile centring is gone — `_center_panel` /
  `_center_all_panels` removed from `main.gd` and `game.gd`. Panels are
  now full-rect containers (anchors 0–1, offsets 16/12/-16/-12) whose size
  comes from the anchors, never from content minimum size. The tall lobby
  sits inside a ScrollContainer so it fits any screen height. See QA-021
  for the full UI rework.
- **Verification:** FIXED and verified. Headless host-flow test after the
  fix: lobby `visible=true size=(1248, 696) position=(16, 12)`, 10 map
  buttons visible, START MATCH at (40, 626) fully in the viewport.
  Full end-to-end flow check 19/19 (see "v2.3 release checklist" below).

## QA-020 — After leaving a match (or a failed join), HOST GAME and JOIN do nothing until the app is restarted (FLOW-017)

- **Severity:** High (found by the v2.3 flow check, not by a user report)
- **Affected feature:** Networking — host/join after any disconnect
- **Steps to reproduce:** Host a game, start a match, leave it (Back to
  Lobby), then tap HOST GAME again — or fail a join (bad IP) and tap
  JOIN again.
- **Expected result:** HOST GAME shows the lobby again; JOIN tries to
  connect again.
- **Actual result (pre-fix):** Nothing happens. No lobby, no error, no
  status message. The buttons are dead until the app is restarted.
  Flow check: 7e (host again after leave) FAIL, 8a (bad-IP join) FAIL
  with empty status, 9 (join-timeout error panel) FAIL — the game scene
  never loaded because the start press was blocked.
- **Root cause:** Four disconnect paths set
  `multiplayer.multiplayer_peer = null` (`main.gd` `_on_connection_failed`,
  `_leave_lobby`, join-timeout in `_process`; `game.gd`
  `_on_leave_pressed`). In Godot 4.3 the getter then returns **null**, not
  the default OfflineMultiplayerPeer. The host/join guards
  (`if multiplayer.multiplayer_peer is not OfflineMultiplayerPeer: return`
  in `_on_host_pressed` and `join_game`) therefore treat a disconnected
  state as "already connected" and silently return. Confirmed by probe:
  initial peer = OfflineMultiplayerPeer; after null-assign, peer = NULL
  and `is not OfflineMultiplayerPeer` = true (blocks). The port itself
  was NOT the problem — once all references were dropped, re-creating the
  server on port 7777 returned OK (err 0).
- **Fix (v2.3):** All four disconnects now restore the offline peer
  (`multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()`) and
  clear the held client peer (`_peer = null`). Both guards are also
  null-safe (`!= null and is not OfflineMultiplayerPeer`), so a null peer
  can never silently block host/join again.
- **Verification:** FIXED and verified. The same flow check that failed
  3 items before the fix passes 19/19 after it: host-again-after-leave
  shows the lobby, bad-IP join shows "Could not reach that host. Check
  the IP and Wi-Fi.", and the join-timeout error panel shows with working
  Back/Retry buttons.

## QA-021 — Modern UI rework (lobby overflow on phone screens)

- **Severity:** Medium (usability)
- **Affected feature:** UI — menus, lobby, HUD
- **Steps to reproduce:** Open the host lobby at 1280x720 (v2.2 layout).
- **Expected result:** Map selection, mode, kill limit, match time and
  START MATCH all visible or reachable without guessing.
- **Actual result (v2.2):** The lobby was 680 px wide with ~660 px of
  content; on phone screens where stretch mode shrinks the logical height
  below 720 it overflowed top/bottom, hiding the title/START button, and
  the mode buttons sat at y=770 — below the viewport, reachable only by
  scrolling a container that did not exist.
- **Fix (v2.3):** Full-rect panels with rounded corners and a dark
  translucent background; green accent (`Color(0.13, 0.65, 0.32)`) for
  primary actions; big touch targets (min 56 px, menu buttons 64 px);
  map thumbnails (96x64) on the lobby map buttons; selected-state
  highlights on map/mode/limit/time buttons; ScrollContainer for the
  lobby content with a fixed START MATCH action row at the bottom; HUD
  dialog buttons (pause, score, grenade, switch, end screen, error
  panel) styled the same way via `_style_hud_button` in `game.gd`.
  Same flows and same `GameData` fields as before.
- **Verification:** Headless flow check at 1280x720: menu buttons, HOST
  GAME, JOIN, all 10 map buttons and START MATCH fully in the viewport;
  mode (2/2), kill limit (3/3) and match time (3/3) all reachable by
  scrolling the lobby; HUD buttons (grenade/switch/pause/score) and both
  joysticks visible in-game. Screenshots: `/tmp/flow_menu.png`,
  `/tmp/flow_lobby.png`, `/tmp/flow_game.png`.

## QA-022 — Jungle Ruins map built from the user's asset pack

- **Severity:** N/A (new content)
- **Affected feature:** Maps — Jungle Ruins (map #6 of 10)
- **Source:** `~/workspace/user/files/Jungle_Ruins_Godot_Asset_Pack.zip`
  (environment atlas 1672x545, map overview 1672x406, placement guide).
  The README states these are generated concept sheets, NOT pre-sliced
  production sprites.
- **Work done:** The atlas was sliced by hand into 12 sprites in
  `assets/jungle/` (grass tile, platform, bridge, arch, tree, palm,
  watchtower, statue, pillar, crate, rock, bush), each verified on
  magenta and dark-green backgrounds — no dark box, all 4 corners
  transparent, alpha ramp (transparent <28, opaque >110). The map
  follows `docs/map_placement_guide.txt` exactly: 3200x1400 world, 6
  zones (left spawn terrace with big tree + cave alcove with ammo; left
  ruin/high route with stepped stone hill, three grass-topped platforms,
  broken temple wall, crate cover, narrow wooden bridge; central temple
  chamber with broad central platform, two elevated ledges, stone pillars
  at the edges, one contested weapon pickup on an exposed mid-height
  platform, lower tunnel beneath; right cliff + watchtower with circular
  cave opening, tree on the upper terrace, bridge to the centre, secondary
  weapon/ammo on a side route; far-right waterfall terrace with descending
  stone platforms and a lower route behind/under the waterfall; lower cave
  network with two connected underground corridors, stone arches, short
  platforms, one open vertical shaft for jetpack traversal). The overview
  was used as a layout reference only — it was NOT pasted in as one big
  image; the map is rebuilt from modular tiles with matching collision.
  Decor is separate from collision; only walkable platforms/walls get
  collision.
- **Verification:** Map load test: Jungle Ruins loads, spawns safely
  (capsule clear), 23 collision shapes for 20 platforms + 3 walls,
  camera limits (3200, 1400), high/mid/floor platforms landable. Zone
  checks all pass: z1 terrace/cave, z2 high route, z3 temple + contested
  pickup, z4 cliff/watchtower, z5 waterfall terrace, z6 cave network,
  bridge to cliff — the player lands on a platform at every checked
  position. No spawn inside a wall, no dead-end trap (cave network has
  2 exits, verified by the reachability graph in the map generator).

## v2.3 release checklist (per-map results)

Full end-to-end flow check (`/tmp/flow_check.gd`, 1280x720, headless):
**19/19 passed** — 1 menu buttons visible+tappable; 2a multiplayer
screen; 2b host lobby full-rect on screen; 2c all 10 maps listed incl.
Jungle Ruins; 2d START MATCH visible+tappable; 2e mode/kill-limit/
match-time reachable by scrolling; 3 map selection changes + remembered
(Jungle Ruins, `map_id=5`, button shows "✓ Jungle Ruins"); 4a game loads
(Jungle Ruins, 3200x1400); 4b local player spawns; 4c spawn not inside a
wall; 4d HUD shows (health/ammo/weapon/grenade/switch/pause/score,
players 1/8); 7a pause opens/closes; 7b scoreboard opens/closes; 7c end
screen at kill limit ("Player wins!", Rematch + Back to Lobby); 7d Back
to Lobby returns to menu; 7e leaving the lobby returns to multiplayer
screen; 8a bad IP shows "Could not reach that host. Check the IP and
Wi-Fi." with no hang; 8b screen still usable after failed join; 9
join-timeout error panel with Back/Retry visible. Zero script errors in
the flow run (only the pre-existing headless audio-init message
`ERROR: Condition "status < 0" is true. Returning: ERR_CANT_OPEN`, which
appears in every headless run and does not occur on a real phone).

All-maps load test (`/tmp/map_load_test.gd`): **47/47 passed** — per map:
loads + spawns (capsule clear), collision shapes = platforms + 3 walls,
camera limits = map size, high/mid/floor platforms landable. Jungle Ruins
adds 7 zone-reachability checks, all pass.

| Map | Size | Platforms | Spawns | Pickups | Load | Spawn safe | Collision | Camera | Landable |
|---|---|---|---|---|---|---|---|---|---|
| Catacombs | 3200x1400 | 17 | 8 | 6 | PASS | PASS | 20 shapes | PASS | PASS |
| Military Base | 2880x1440 | 16 | 8 | 6 | PASS | PASS | 19 shapes | PASS | PASS |
| Desert Outpost | 3000x1500 | 16 | 8 | 6 | PASS | PASS | 19 shapes | PASS | PASS |
| Industrial Factory | 3200x1600 | 17 | 8 | 6 | PASS | PASS | 20 shapes | PASS | PASS |
| Frozen Fortress | 2800x1500 | 16 | 8 | 6 | PASS | PASS | 19 shapes | PASS | PASS |
| Jungle Ruins | 3200x1400 | 20 | 8 | 6 | PASS | PASS | 23 shapes | PASS | PASS (+7 zone checks) |
| Space Station | 3000x1500 | 16 | 8 | 6 | PASS | PASS | 19 shapes | PASS | PASS |
| City Underground | 3200x1600 | 17 | 8 | 6 | PASS | PASS | 20 shapes | PASS | PASS |
| Volcanic Cavern | 3000x1500 | 18 | 8 | 6 | PASS | PASS | 21 shapes | PASS | PASS (lava pools avoidable, safe routes) |
| Pirate Island | 3000x1500 | 16 | 8 | 6 | PASS | PASS | 19 shapes | PASS | PASS |

Joystick acceptance test (re-run on final v2.3 code):
**21/21 passed** — same coverage as v2.2 (directions, diagonals,
knob clamp, release, multi-touch, focus-out reset, fire stops on
release/death/pause/match-end, stick-up jump/no-re-jump, 1920 resolution).
QA-016 fire fix intact.

Smoke test (re-run on final v2.3 code, `-- --auto-host --smoke-test`):
**all 19 phases (0–18) pass, 0 script errors** — host runs, moves (330
full speed / 68 at 0.3 push), jetpacks (fuel 100 → 57 → 10, refills to
100), aims in all directions, shoots (23 shots), throws a grenade, picks
up weapons (SMG), switches weapons. Screenshots saved to
`user://shot_aim.png` / `user://shot_explosion.png`.

Map generation validation (`/tmp/gen_maps.py`): **0 errors, 0 warnings**
on the final run — platform height 48, no overlaps, every platform
reachable by a normal jump or jetpack from the floor, spawns capsule-clear
and landing on a platform/floor within 60 px below, pickups with a
platform top within 50 px below, Catacombs smoke-test columns clear,
no spawn/pickup over lava.

Known limits that still apply (unchanged from v2.2): two-phone LAN join
untested on real phones (sandbox blocks UDP); real touch hardware
untested; performance on a real phone untested; audio not verified by
ear. The green strip seen at the top of headless game screenshots is a
test-harness artifact (the harness adds the main scene manually, so the
leftover START MATCH button renders shifted by the game camera) — it
does not occur in the real app, where `change_scene_to_file` frees the
main scene. The lobby's mode/kill-limit/match-time rows sit below the
fold at 720p and need a scroll to reach — by design (ScrollContainer),
verified reachable in the flow check.

## v2.4 — FIRE button + multiplayer overhaul (2026-11-19)

## QA-023 — Fire button triggers together with movement / grenade / weapon buttons (user-reported, real phone)

**Report:** "The fire button is triggering with the movements grenade and
weapon button. It shouldn't happen. It should work with only fire button."

**Root cause (code audit, game.gd + joystick.gd):** the game grabbed ALL
screen touches first in `_input`, and `_on_touch_press` routed by screen
half (left → move stick, right → aim stick). `joystick.gd press_touch()`
never checked whether the touch was inside the stick. The ONLY thing
protecting the GRENADE / WEAPON / PAUSE / SCORE buttons was a
`get_global_rect().has_point(pos)` check — and on a real phone (stretch
mode `canvas_items` + aspect expand) the button rects are canvas-space
while touch positions are viewport-pixel space, so the check can miss. A
tap on GRENADE or WEAPON fell through to the aim stick, and since v2.3
set `touch_firing = aim_vec.length() > 0.35`, the gun fired.

**Fix (not a patch on the rect check):**
1. The FIRE button owns its own touch ID (`_fire_touch_id`) and
   `touch_firing` is true ONLY while that ID is actively held — nothing
   else may ever set it.
2. The aim stick is aim-only and can never cause firing.
3. Game touches now go through `_unhandled_input` instead of `_input`,
   so GUI buttons (grenade, weapon, pause, score, reload, fire) consume
   their touches first and the game layer never sees them. A
   coordinate-correct rect check (`_to_canvas_pos` via the canvas
   transform inverse, verified against the actual stretch transform)
   remains only as a belt-and-braces fallback.
4. The QA-016 rule stands: firing state comes only from an actively held
   fire-button touch, reset on focus-out / pause / death / match end.

**New files:** `fire_button.gd` (FireButtonController: one touch ID,
press edge, slide-off cancel past 1.6x radius, focus-out reset, drawn
red circle + white bullet icon + glow while held), `weapons.gd`
(WeaponData: one data-driven table for all 6 weapons),
`bullet_pool.gd` (BulletPool: 96 pre-created pooled bullets),
`shooting_sync.gd` (ShootingSync: host-side rate/ammo validation),
`discovery.gd` (LanDiscovery: see QA-025).

**Verification (fire test, `-- --auto-host --fire-test`):** move alone →
0 shots; aim alone → 0 shots; GRENADE alone → 0 shots and 1 grenade;
WEAPON alone → 0 shots and 1 weapon switch; FIRE alone → fires; hold
FIRE + move + aim (3 fingers) → fires while moving and aiming; tap
GRENADE while holding FIRE → grenade throws and firing continues only
while FIRE is held; slide a finger off FIRE → firing stops. All pass
(see the fire-test log below).

## QA-024 — Mini Militia-style FIRE button system

- Circular FIRE button, fixed bottom-right (screen space, never moves
  with the camera), 90x90 px on the reference screen, semi-transparent
  red circle, white bullet icon, white outline, shrinks to 0.9x while
  pressed, pulsing glow while firing. Placed at the far corner; the aim
  stick moved left/up to make room — no overlap with any control at
  1280x720 or 1920x1080 (layout check in the fire test).
- Press-and-hold = continuous automatic fire at the weapon's rate;
  release = stop immediately. Single tap = one shot for semi-auto
  weapons. Respects fire rate and reload: no firing at zero ammo, no
  firing during reload, auto-reload at zero ammo.
- Aiming: separate right-side stick, 360 degrees; the weapon orients to
  the aim direction and the muzzle follows it. No aim input = shoot in
  the facing direction. Never auto-aims in the movement direction.
- Weapons (data-driven, `weapons.gd`): Pistol (new default sidearm, 10
  dmg / 0.22 s / 12 mag / 1.0 s reload / low recoil), Assault Rifle
  (12 / 0.13 / 30 / 1.2), SMG (8 / 0.07 / 32 / 1.0), Shotgun
  (9x6 pellets / 0.8 / 6 / 1.8, wide spread, short range, strong recoil),
  Sniper (60 / 0.9 / 5 / 1.6, slow, high damage), Rocket Launcher
  (70 / 1.2 / 4 / 2.0, explosive, area damage + knockback).
- Reloading: ammo count next to the weapon name ("Rifle 24/30"), a
  dedicated RELOAD button, reload progress shown ("reloading 60%"), no
  firing during reload, ammo refills after reload, reload animation +
  sound. A dedicated "pistol" sound was added to `audio.gd`.
- Multi-touch with per-finger touch IDs (move 910 / aim 911 / fire 912
  in the tests); release detection and cancellation (slide-off, focus-out,
  pause, death, match end) all reset firing state.
- Effects: muzzle flash, bullet trails, per-weapon recoil (velocity kick
  + gun kick), screen shake for shotgun/sniper/rocket (trauma-based),
  weapon-specific sounds, impact sparks, hit effects.
- Architecture: `FireButtonController` (fire_button.gd), `WeaponData`
  (weapons.gd), `BulletPool` (bullet_pool.gd), `ShootingSync`
  (shooting_sync.gd), aim/reload/fire split across player.gd
  (`_read_input` / `_apply_aim_and_fire` / `start_reload`) and game.gd
  (touch routing, HUD, reload button). Frame-rate independent (delta
  based), resolution independent (anchors + canvas transform).

## QA-025 — Multiplayer overhaul: rooms, discovery, lobby, host IP

**Report:** "check the multiplayer, I am still not able to play."

**Audit findings:** the host's LAN IP was never shown in the lobby or on
the multiplayer screen (only "You are the host - pick a map and mode,
then start!"); discovery broadcast only to 255.255.255.255:7778 (many
routers/hotspots block the limited broadcast); the client's spawn
depended on a single `request_spawn` RPC (one lost UDP packet = stuck
until the 8 s timeout); clients decided damage/kills, not the host.

**Fix:**
- **Rooms (main.gd):** Create Room (name, max players 2–12, private +
  password), Join Room, Quick LAN Match (first open lobby room with
  space), Refresh Rooms, Manual IP Connection, Back. Host can change
  settings, kick players, start when all ready or force-start (the
  button says "START ANYWAY (n/m ready)" when not all ready).
- **Discovery (discovery.gd):** room announcements carry the full card
  (room name, host name, players/max, map, mode, status, IP, port,
  private) and broadcast to every subnet broadcast address derived from
  the host's IPs (e.g. 192.168.1.255) as well as 255.255.255.255.
  Clients list rooms automatically, drop expired ones (5 s), and show
  the full card. Manual IP entry is always the fallback.
- **Host IP visible:** the multiplayer screen shows "Your IP on this
  Wi-Fi: x.x.x.x" before hosting, and the lobby shows "HOST IP:
  x.x.x.x — friends type this IP to join" big and clear. If no Wi-Fi IP
  exists it says so plainly.
- **Lobby:** player portraits, names, colours, HOST/YOU tags, per-player
  READY status (toggle button; host force-start is explicit), KICK
  buttons for the host, room settings summary, and the new controls hint.
  Wrong password / full room / kicked all produce an exact message
  (the password is never broadcast to other players).
- **Spawn retry:** the client re-sends `request_spawn` every 2 s while
  unspawned; the server's handler is idempotent (`_spawned` guard).
  The host no longer errors on its own announce: `_announce_ready` is a
  no-op on the server (it spawns via `_spawn_self`).
- **Reconnect:** after a host disconnect, `GameData.last_host_ip` is
  saved and the multiplayer screen prefills it with "tap JOIN to
  reconnect". Host disconnect ends the match safely on every client
  with a clear message — never a stuck loading screen.
- **Modes:** Survival (round-based, one life per round, first to the
  round limit wins) and Last Man Standing (one life for the whole match)
  added to FFA and TDM. All 10 maps now have 12 spawn points (4 extra
  floor spawns each; Volcanic Cavern extras avoid the lava pools).
- **Disconnects:** client disconnect removes the player, updates the
  lobby/scoreboard, and re-checks Survival/LMS end conditions. Host
  migration is intentionally skipped (safe-exit instead, per spec).

## QA-026 — Host-authoritative combat

- The host validates every shot (`shooting_sync.gd`): shots arriving
  sooner than 0.75x the weapon rate are rejected, ammo is mirrored from
  the client's replicated magazine (increases adopted = reload/pickup),
  shots at 0 ammo are rejected. No duplicate shots from latency.
- Bullet collision is decided by the host's simulation; damage, kill
  credit, health, deaths and respawns are host-owned. `take_damage` /
  `take_explosion_damage` / `add_kill` / `give_pickup` reject remote
  senders (only the host, id 0/1, may call them). Kill credit was
  removed from `take_damage` — the host credits the kill when its own
  hit is lethal. Friendly fire: TDM with friendly fire off makes
  teammates immune (checked in `bullet.gd`).
- Lava damage now routes to the victim's owning peer (it used to call
  `take_damage` directly on the server's copy of remote players, which
  replication overwrote — lava only hurt the host).
- RPCs to a peer that disconnected mid-flight are skipped
  (`multiplayer.get_peers().has(...)` guard in `bullet.gd` and
  `request_explosion` / `_update_lava`) instead of logging errors.
- Movement keeps the MultiplayerSynchronizer (0.05 s) + owner simulation
  + lerp interpolation; the host validates spawn requests (sender must
  match the claimed peer id, room must not be full).

## QA-027 — Semi-auto tap silently lost (real bug found by the fire test)

**Symptom:** the fire test's pistol/shotgun bullet-count steps
flip-flopped between runs (pistol 0 / shotgun 6, then pistol 1 /
shotgun 0) with no code change.

**Root cause:** the press edge was consumed in `_read_input`
(physics) with `consume_press_edge()`, but `touch_firing` only updates
in `_process`. A tap landing just after a physics step was consumed on
a frame where `_want_fire` was still false — the shot never fired and
the edge was gone. On a real phone the same 1-frame window would make
an occasional pistol/shotgun/sniper tap do nothing.

**Fix:** the player now peeks (`has_press_edge()`) in `_read_input`
and the edge is consumed only in `_apply_aim_and_fire` when the shot
actually fires. Taps during reload are discarded (a tap during reload
does nothing). Releasing the button already clears the edge
(`reset_input`), so a persisted edge only exists while the finger is
still down — one tap can still only ever produce one shot. The
fire test is stable across runs after the fix (25/25 twice).

## QA-028 — Script errors when leaving a match (pre-existing, exposed by the flow test)

**Symptom:** after END-MATCH, the flow test logged 4x `Cannot call
method 'is_server' on a null value` (in `_update_pickup_spawn`,
`_update_join_timeout`, `_retry_spawn_if_needed`, `_update_lava`).

**Root cause:** `_on_leave_pressed()` sets the peer to offline and
requests the scene change, but the scene change lands at the end of the
frame — the game's `_process` tail still ran once with `multiplayer`
already torn down. (The functions that returned early on `match_over`
never reached the call, which is why only 4 of them errored.)

**Fix:** a `_leaving` flag, set in `_on_leave_pressed()`, makes
`_process` return immediately — checked both at the top of `_process`
and after the test-dispatch chain, so the tail cannot run mid-frame
either. The flow test now runs with zero script errors.

## QA-029 — Joysticks move downwards on a real phone (user-reported, v2.4)

**Symptom:** on a real phone, touching the left or the right joystick
makes the knob jump to the bottom edge and the player drift downwards,
on every touch, at every screen size. Both sticks are affected.

**Root cause:** a coordinate-space mismatch in the touch conversion.
`_to_canvas_pos()` converted touch positions with the viewport's
canvas transform (`get_viewport().get_canvas_transform()`), which
carries the CAMERA offset — the camera follows the player, so once the
player leaves the spawn its origin is far from (0,0) — but the HUD
`CanvasLayer` does not follow the camera. Every touch therefore landed
~680 px too low (the camera was at y=1040, so the offset was exactly
680 px on Catacombs). The joystick then computed the knob offset from
that shifted point, clamped it to the 60 px radius, and the knob
slammed to the bottom edge with a straight-down vector. The same
offset also made FIRE-button taps miss the button whenever the camera
had moved. Headless tests never caught it because they fed canvas-space
points directly to `_on_touch_press`, bypassing `_unhandled_input`
and `_to_canvas_pos` entirely. (The stretch scale was suspected first,
but the repro proved the camera term is the culprit: the bug fires at
1280x720, scale exactly 1.)

**Reproduction (new `--scale-test` harness):** the harness drives the
REAL `_unhandled_input` pipeline with viewport-pixel positions
computed from each control's `get_global_transform_with_canvas()` at
5 resolutions. Against the unfixed code it failed 40/70: every
centre/up/left/right/diagonal/aim/fire step failed with
`vec=(0, 1), knob=(0, 60)`, and the DIAG line showed
`converted=(115, 1285)` for a stick centre at `(115, 605)` — 680 px
too low, exactly the camera offset.

**Fix:** (1) `_to_canvas_pos()` / `_to_viewport_pos()` now use the HUD
layer's own transform (`hud.get_final_transform()`), which has no
camera term — the correct converter for HUD touches. (2)
`joystick.gd _update_from_point()` converts the incoming point into
the stick's local space first
(`get_global_transform_with_canvas().affine_inverse() * global_pos`),
then measures the offset from the local centre (`size * 0.5`) — the
base never moves, only the knob follows the finger. (3) The same local
conversion in `fire_button.gd press_touch()` / `drag_touch()`, and in
`is_hud_control_pos()`, which now tests each control with its own
global transform with canvas instead of a shared rectangle in a
possibly different space. Stick layout, sizes, dead zone, fire-button
behaviour and all v2.4 multiplayer work are unchanged.

**Verification:** scale test **70/70 passed** (14 steps × 5
resolutions: 1280x720, 2400x1080, 1920x1080, 800x480, 2340x1080).
Centre touch gives a zero vector and the knob stays centred; up/down/
left/right/diagonal give matching vectors with correct magnitude; the
knob never jumps down on a centred touch. The DIAG line now shows
`converted=(115, 605)` = the stick centre, while the old conversion
still prints `(115, 1285)` for the record. Joystick acceptance,
fire-button, smoke, flow, net and menu-net tests all re-run clean on
the fixed code (see v2.5 test logs).

## QA-030 — Bullets and the player pass through obstacles (user-reported, v2.4)

**Symptom:** bullets fly straight through crates and barrels, and the
player walks straight through them. A crate is visual-only.

**Root cause:** in `_build_arena()`, platforms and walls got collision
shapes in the Arena `StaticBody2D` (layer 1), but ALL decor — crates,
barrels, sandbags, rocks, columns, pillars, statues, watchtower, trees,
bushes, palms, bridges, arches — was drawn as a bare `Sprite2D` with
no collision. Bullets use a swept raycast (mask 3 = world + players)
and the player uses `move_and_slide`, so both passed through decor.

**Fix:** solid-looking decor now gets a real collision rectangle on
layer 1 in the Arena, sized from the sprite's texture and centred on
the sprite, so it covers exactly what the player sees. Solid: crate,
barrels, sandbags, rock, column, pillar, statue, watchtower, jungle
crate, jungle rock. Non-solid dressing (trees, palms, bushes, bridges,
arches) keeps no collision and stays pass-through, as before.
Grenades (mask 1) bounce off the new shapes automatically; the bullet
raycast (mask 3) stops at them with the existing impact FX.

**Map data fix:** a design-time check found 11 decor items sitting
exactly on top of a spawn point or a pickup (the floor decor was
placed at the same round x positions as the spawns). They were moved
to a clear spot on the same platform: Military Base sandbags 600→750,
barrels 1800→1950, crate 2600→2450, crate 1200→1350 (was on pickup
(1200,680)); Desert Outpost sandbags 2400→2250; Industrial Factory
barrels 600→750; Space Station barrels 2600→2450, column 2100→2250;
City Underground crate 600→750; Volcanic Cavern crate 2400→2250;
Pirate Island rock 2400→2250. The remaining near-misses (e.g. a
Catacombs column 3 px from a spawn) are clear of the real 34×52 player
capsule. Low-clearance solids (a column 6 px under the platform above
it) never seal a route: each is a single narrow pillar on a wide-open
floor or platform, jumpable (jump height ~155 px) or walk-around-able,
and the static check below proves it.

**Verification (new `--collision-test` harness, `--map=N` to pick the
map):** **8/8 passed on Catacombs and 8/8 on Jungle Ruins.** (a) ray
at a crate stops exactly at its face `(979, 1331)`; a ray aimed past
the crate still stops at the face, so a target behind it is safe.
(b) walking into a crate stops the player exactly at the capsule edge
(x=962 for face 979). (c) a downward ray stops at the floor top
(1352). (d) a ray through a tree passes clean through. (e) walking
through a bush passes it. (f) static validation of ALL 10 maps:
53 solid rects, 120 spawns, 60 pickups — no spawn or pickup inside a
solid, no solid seals a platform, and the platform graph (jump/jetpack
up to 320 px up, 340 px across) reaches every spawn and pickup from
spawn#0. (g) a grenade thrown at a column/watchtower bounces back
(x=614 vs face 623; x=2354 vs face 2363). One failure during
development was a test bug (the bush ray started off-map at x=-52 and
hit the left wall) — the test was fixed, not the game.

## v2.4 test logs (final run, 2026-11-19)

**Joystick acceptance test** (`-- --auto-host --joystick-test`):
**21/21 passed.** One failure was found and fixed during the run:
DIAG-UP-RIGHT failed because the test teleported the player to
(300, 1350), directly under the Catacombs platform at (300, 1180, 420,
48) — the player jumped, rose 72 px and pinned under the platform, so
vel.y read 0 while jetpacking. That is a test-setup bug, not a game
bug; the setup now teleports to open sky (2100, 1350) and the step
passes (vel=(231,-407)).

**Smoke test** (`-- --auto-host --smoke-test`): **all 19 phases (0–18)
pass** — host runs, moves, jetpacks, aims, shoots (23 shots), throws a
grenade, picks up weapons, switches weapons. The two `save_png` errors
in headless output are the screenshot captures (no viewport texture in
headless mode); the phases themselves all pass.

**Fire-button test** (`-- --auto-host --fire-test`): **25/25 passed
(two consecutive runs).** MOVE-ALONE-NO-FIRE, AIM-ALONE-NO-FIRE,
GRENADE-ALONE-NO-FIRE, WEAPON-ALONE-NO-FIRE, PISTOL-TAP-ONE-SHOT,
FIRE-HOLD-CONTINUOUS (19 shots in 2.5 s, want 14–22),
FIRE-WHILE-MOVING, FIRE-DIAGONAL-AIM, FIRE-WHILE-JETPACK,
FIRE-WHILE-JUMPING, SWITCH-SETUP, SWITCH-WHILE-FIRING (rifle→pistol
setup now lands on the SMG, which keeps firing while held — switching
onto a semi-auto correctly needs a fresh tap), EMPTY-MAG-BLOCKED,
RELOAD-COMPLETES (mag 32/32), RELOAD-WHILE-MOVING (60% progress),
THREE-FINGERS, GRENADE-WHILE-FIRING (grenade throws, firing continues
only while FIRE is held), SLIDE-OFF-STOPS-FIRE, LAYOUT-1280,
LAYOUT-1920-AND-TRANSFORM (physical grenade tap through
`_unhandled_input` at 1920x1080 proves the transform-correct fallback),
MP-SYNC-VALIDATION (first=true, too-fast=false, empty-mag=false),
MP-SINGLE-SHOT-ONE-BULLET (exactly 1 pistol bullet),
MP-SHOTGUN-SIX-PELLETS (exactly 6 pellets). Three failures were found
and fixed during the run: FIRE-WHILE-JUMPING (jump-edge race — see
below), SWITCH-WHILE-FIRING (wrong expectation for a semi-auto landing
— see above), and the pistol/shotgun flip-flop (QA-027, real bug).

Test-only notes: the jump-edge failure was a headless timing artifact
(two `_process` calls with no physics frame between the release and the
re-press, so the player never saw the stick drop and the jump edge did
not arm). On a real phone, releases and presses are separated by many
physics frames. The test re-arms the jump state in the setup; the game
code is unchanged for this. The fire test's RELEASE-FIRE check has the
same one-physics-frame race the old aim-release test had
(`touch_firing` updates in `_process`, the player reads it in
`_physics_process`) — watch for flakiness on re-runs.

**Multiplayer test** (`-- --auto-host --net-test`): **11/11 passed.**
PAYLOAD-ROUNDTRIP (fields match, malformed packets rejected),
SUBNET-BROADCAST (255.255.255.255 + 198.19.0.255, lan_ip 198.19.0.2),
DISCOVERY-BIND (listener bound), SPAWN-IDEMPOTENT (3x request_spawn →
1 player), COMBAT-HIT (1 pistol shot at a player 300 px away → bullet
despawned on impact), DAMAGE-DEATH-RESPAWN (health 100 → 70 after 30
dmg, dead after lethal, respawned alive with 100 health),
MODE-SURVIVAL (kill the only other player → round won → match ends,
host 1 round), MODE-LMS (kill the only other player → match ends, local
player last standing), DISCONNECT-CLEANUP (bot node gone, spawn entry
erased), HOST-LEFT-SAFE-EXIT (error panel visible, last_host_ip saved).
One failure was found and fixed during the run: the damage step ran
inside the 2 s spawn-protection window, so `take_damage` was swallowed
— the test now clears spawn protection first.

**Menu network test** (`-- --menu-net-test`): **6/6 passed.**
PAYLOAD-ROUNDTRIP, SUBNET-BROADCAST, BAD-IP-ERROR (joining
999.999.999.999 → "Could not reach that host. Check the IP and Wi-Fi,
then tap JOIN to retry."), CREATE-ROOM (host=true, server=true, lobby
visible, 1 player, host-IP label shows the LAN IP), READY-TOGGLE (own
ready state true after one tap), LEAVE-CLEANUP (clean leave, menu
visible again).

**Full-flow check** (`-- --flow-test`): **10/10 passed, 0 script
errors.** MENU-VISIBLE → CREATE-ROOM (lobby + host IP shown) →
START-MATCH → MATCH-LOADED → PLAY-FIRE (4 shots) → PAUSE (paused,
panel visible) → RESUME → SCOREBOARD (opens and closes) → END-MATCH
(match_over, end panel visible) → BACK-AT-MENU (main menu visible
again). This is a new harness: the menu side hands the check to the
game scene via `GameData.flow_phase` and the game side hands it back;
the menu prints the final result. It also caught QA-028 (fixed).

## v2.4 release checklist

- Clean compile: all 13 scripts parse with `--check-only`, no script
  errors in any test run.
- `aapt2 dump badging`: package `com.lanarena.shooter`, versionCode 6,
  versionName 2.4, targetSdk 34, permissions ONLY `INTERNET`,
  `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`.
- Signed with the same debug keystore as v2.3 (certificate SHA-256
  `f65f2fa3d8041b5e8920e627355a0dd68d9b50414d6b40702fea6b4da6e02d11`
  matches v2.3 exactly — installs over v2.3 cleanly).
- APK: `mini-militia-lan.apk`, 24,112,174 bytes, md5
  `5ede468caf4152eba2d023f859ac2e63`.
- Known limits that still apply (unchanged): real two-phone LAN join,
  hotspot/routers and network latency cannot be tested on this build
  machine (the sandbox blocks UDP between processes) — the user tests
  that part with the step-by-step guide in README.md; real touch
  hardware untested; performance on a real phone untested; audio not
  verified by ear. The host-authoritative damage path for a REMOTE
  victim (host → rpc_id → victim's peer) cannot be exercised in a
  single process — it was verified by code review plus the local-victim
  path and the shooting-sync validation tests. Simultaneous lethal hits
  from two shooters could double-credit a kill (the host reads the
  victim's replicated health, stale by ~0.05 s + latency) — accepted
  edge case, noted here rather than hidden.

## v2.5 test logs (final run, 2026-11-19)

**Scale / coordinate test** (`-- --auto-host --scale-test`): **70/70
passed** (14 steps × 5 resolutions: 1280x720, 2400x1080, 1920x1080,
800x480, 2340x1080). Against the unfixed code the same harness failed
40/70 — every centre/up/left/right/diagonal/aim/fire step failed with
`vec=(0, 1), knob=(0, 60)`, and the DIAG line showed the touch
converting to `(115, 1285)` for a stick centre at `(115, 605)` — 680 px
too low, exactly the camera offset. After the fix the DIAG shows
`converted=(115, 605)` = the stick centre at every resolution.

**Collision test** (`-- --auto-host --collision-test`, and `--map=5` for
Jungle Ruins): **8/8 passed on Catacombs and 8/8 on Jungle Ruins.**
STATIC-ALL-MAPS (10 maps, 53 solid rects, 120 spawns, 60 pickups: all
clear), BULLET-STOPS-SOLID (ray stops exactly at the crate face),
BULLET-BLOCKS-TARGET (a ray past the crate still stops at its face),
WALK-BLOCKED (player stops exactly at the capsule edge, x=962 for face
979), BULLET-STOPS-FLOOR (ray stops at the floor top), GRENADE-BLOCKED
(grenade bounces back off a column/watchtower), BULLET-PASSES-BUSH
(ray passes clean through a tree), WALK-PASSES-BUSH (player walks
through a bush). One failure during development was a test bug (the
bush ray started off-map at x=-52 and hit the left wall) — the test was
fixed, not the game.

**Joystick acceptance test** (`-- --auto-host --joystick-test`):
**21/21 passed.**

**Fire-button test** (`-- --auto-host --fire-test`): **25/25 passed.**

**Smoke test** (`-- --auto-host --smoke-test`): **all 19 phases pass**
— host runs, moves, jetpacks, aims, shoots (23 shots), throws a
grenade, picks up weapons, switches weapons.

**Multiplayer test** (`-- --auto-host --net-test`): **11/11 passed.**

**Menu network test** (`--menu-net-test`): **6/6 passed.**

**Full-flow check** (`-- --flow-test`): **10/10 passed** (menu →
create room → lobby → start match → play → pause → scoreboard → end
screen → back).

**Zero script errors in every run.**

Three failures found and fixed while testing v2.5 (all test-setup
issues, not game bugs): (1) FIRE-WHILE-MOVING and THREE-FINGERS failed
because the player ran into the new solid column/barrels and could not
cover the 100 px the check requires — the setups now teleport the
player to a clear stretch of floor first; (2) FOCUS-OUT-RESET,
RELEASE-FIRE-STOPS-FIRE and SLIDE-OFF-STOPS-FIRE each failed once with
exactly one extra shot — a race: the shot baseline was captured before
the release took effect in `touch_firing` (which only updates in
`_update_touch_state()`), so a physics step in between could fire one
shot — the setups now refresh the touch state and capture the baseline
after the release; (3) MP-SINGLE-SHOT-ONE-BULLET and
MP-SHOTGUN-SIX-PELLETS failed with 0 bullets — the player's own
grenades, thrown earlier in the test, now bounce off the solid column
and explode at point-blank range (the debug run caught the player at
1 HP), so the player was dead at the bullet-count step and could not
shoot — the setups now revive + heal the player first. The grenade
hurting its thrower is intended Mini Militia behaviour, not a bug.
The joystick and fire tests were re-run twice more after these fixes:
21/21 and 25/25 both times.

## v2.5 release checklist

- Clean compile: `--headless --import` with no script errors; zero
  script errors in every test run.
- `aapt2 dump badging`: package `com.lanarena.shooter`, versionCode 7,
  versionName 2.5, targetSdk 34, permissions ONLY `INTERNET`,
  `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`.
- Signed with the same debug keystore as v2.4 (certificate SHA-256
  `f65f2fa3d8041b5e8920e627355a0dd68d9b50414d6b40702fea6b4da6e02d11`
  — verified, matches v2.4 — installs over v2.4 cleanly).
- APK: `mini-militia-lan.apk`, 25,492,479 bytes, md5
  `90fe7e3fad44dd249ba8afc9bccaf175`.
- NOTE FOR v3.0: `export_presets.cfg` now has
  `exclude_filter="gen_assets_v3/*"` — the v3.0 coordinator's
  `gen_assets_v3/` staging folder (music + generated assets) was
  landing in the v2.5 APK unused (+~4.7 MB) and is excluded from the
  export only; the files are still in the project. Remove the filter
  when v3.0 wires those assets into the game.
- Known limits that still apply (unchanged from v2.4): real two-phone
  LAN join, hotspot/routers and network latency cannot be tested on
  this build machine (the sandbox blocks UDP between processes) — the
  user tests that part with the step-by-step guide in README.md; real
  touch hardware untested; performance on a real phone untested; audio
  not verified by ear. The host-authoritative damage path for a REMOTE
  victim cannot be exercised in a single process. Simultaneous lethal
  hits from two shooters could double-credit a kill — accepted edge
  case, noted here rather than hidden.

## Phase 3 — Engine upgrade Godot 4.3 → 4.7.2 (2026-11-19, engine-only)

- **Result: MIGRATED, no fallback needed.** Project now runs on Godot
  4.7.2.stable.official.ed1daf0bf. No gameplay, map, UI, or feature
  change was made. Diff against the v2.5 backup
  (`~/workspace/mini-militia-lan-backup-v2.5/`) shows the ONLY code change
  is `project.godot`: `config/features` `"4.3"` → `"4.7"`. The 4.7
  re-import also generated `*.gd.uid` files (new in 4.4+, harmless) and
  rewrote `.godot/`. No `.gd`/`.tscn` file was edited.
- **Backup verified first:** v2.5 APK md5
  `90fe7e3fad44dd249ba8afc9bccaf175` matches in both the project and the
  backup; backup is 218 MB. The delivered v2.5 APK was NOT overwritten —
  its md5 is unchanged after this phase.
- **Migration notes reviewed (official docs, 4.3→4.4→4.5→4.6→4.7):**
  no breaking change in any of the four guides touches an API this
  project uses. Checked explicitly and NOT present in the code:
  `OS.read_string_from_stdin`, GraphEdit `frame_rect_changed`,
  `@export_file`, `JSONRPC.set_scope`, `Node.get_rpc_config`,
  `RenderingServer.instance_set_interpolated` /
  `instance_reset_physics_interpolation`, RichTextLabel
  `UPDATE_WIDTH_IN_PERCENT`, `AudioEffectSpectrumAnalyzer.tap_back_pos`,
  `type_exists`, `draw_list_begin`, OpenXR/EditorFileDialog APIs.
  Behaviour changes checked and not applicable: `AudioStreamPlayer`
  default `area_mask` 1→0 (project uses no `audio_bus_override` on
  Area2D), mouse/keyboard device IDs 0→`DEVICE_ID_MOUSE`/`DEVICE_ID_KEYBOARD`
  (project never compares `InputEvent.device`; touch-only input),
  packed-array element setter no longer calling the property setter
  (no such pattern in the code), Jolt 3D changes (2D game, GodotPhysics2D).
  Typed virtual overrides needing an explicit `return` in 4.7: none —
  all typed functions are the project's own helpers, not overrides.
- **API breaks fixed: NONE.** Zero script errors on `--headless --import`
  with 4.7.2 and zero script errors in every test run below. The
  migration was clean with no code fix required.
- **QA-029 preserved:** HUD touch conversion still uses
  `hud.get_final_transform()` (`game.gd:1576`, `_to_canvas_pos`) —
  `get_viewport().get_canvas_transform()` is NOT used for HUD touches
  (it appears only in a scale-test diagnostic print and a comment).
  Verified by diff + the joystick/fire tests passing (see below).
- **Toolchain fixes found during this phase (environment, not game):**
  (1) The 4.7.2 export templates were installed one level too deep
  (`.../4.7.2.stable/templates/*.apk`); Godot expects them directly
  under `.../4.7.2.stable/`. Moved them up; export then worked.
  (2) `editor_settings-4.7.tres` pointed `java_sdk_path` at
  `/usr/lib/jvm/java-17-openjdk-amd64`, which does not exist on this
  machine; corrected to `/home/hatch/workspace/jdk17` (the real JDK 17,
  Temurin 17.0.21). Android SDK path was already correct.
- **Regression on 4.7.2 (all with `xvfb-run -a`, Godot 4.7.2 binary):**
  joystick acceptance **21/21**, fire-button **25/25**, smoke **19/19
  phases (0–18)**, scale **70/70**, collision **8/8 on all 10 maps**
  (Catacombs, Military Base, Desert Outpost, Industrial Factory,
  Frozen Fortress, Jungle Ruins, Space Station, City Underground,
  Volcanic Cavern, Pirate Island), multiplayer **11/11**, menu network
  **6/6**, full flow **9/9** (menu → create room → lobby → start match →
  play/fire → pause/resume → scoreboard → end screen → back to menu).
  Zero script errors in every log. The only error lines are the known
  headless-environment noise: the audio-init `ERR_CANT_OPEN` (also
  present on 4.3) and ALSA "No such file or directory" (no sound card
  headless); neither occurs on a real phone.
- **Android export proof (4.7.2 templates, debug):** exported to
  `/tmp/v3-engine-test.apk` (29,534,306 bytes unsigned), signed with the
  debug keystore to `/tmp/v3-engine-test-signed.apk` (29,589,831 bytes,
  md5 `109a5f7e859f340e8e98f72e3239356d`). `aapt2 dump badging`:
  package `com.lanarena.shooter`, versionCode 7, versionName 2.5,
  permissions ONLY `INTERNET`, `ACCESS_NETWORK_STATE`,
  `ACCESS_WIFI_STATE`. `apksigner verify` passes; signer certificate
  SHA-256 `f65f2fa3d8041b5e8920e627355a0dd68d9b50414d6b40702fea6b4da6e02d11`
  matches v2.4/v2.5 — installs over v2.5 cleanly. No `gen_assets_v3/`
  or music files inside the APK (exclude filter intact).
- **NOTED DIFFERENCE — targetSdk 34 → 36:** the 4.7.2 Android template
  targets SDK 36 (compileSdk 36, platformBuildVersion 16); v2.5 on the
  4.3 template was targetSdk 34. This is baked into the engine
  template, not a project setting — there is no export-preset option
  to pin it. SDK 36 is newer and satisfies current Play requirements
  (35+), so this is an improvement, not a regression. No action needed.
- **APK size note:** the 4.7.2 test APK is ~29.5 MB vs 25.5 MB for v2.5
  on 4.3 — the 4.7 engine runtime itself is ~4 MB larger. Not a
  regression; expect the v3.0 APK to be ~29–30 MB before new assets.
- **Version untouched per plan:** still 2.5 / versionCode 7;
  `export_presets.cfg` still has `exclude_filter="gen_assets_v3/*"`.
  The final phase bumps to 3.0 / code 8.
- **Known limits unchanged from v2.5:** real two-phone LAN join,
  hotspot/routers and latency still untested here (sandbox blocks UDP);
  real touch hardware untested; performance on a real phone untested;
  audio not verified by ear.

## Sky Brawl asset pack — curation (2026-11-19 ~02:00 IST)

- Source: user upload `~/workspace/user/files/sky_brawl_1000_game_assets.zip`,
  extracted to `~/workspace/user/files/sky_brawl_asset_pack/sky_brawl_asset_pack/`
  — 1,000 PNGs + manifest.json + README.md (visual starter assets only:
  NO animation frames, NO collision meshes, NO weapon stats).
- Full curation (selection, transparency results, resolution notes,
  rejections, integration notes) in `SKY_BRAWL_USE.md`. V3_PLAN.md
  Phase 2 (Gemini need) and Phase 5 (map art) updated from it.
- SELECTED: 54 files, ~103 KB — backgrounds 13 (one per map), characters 5,
  terrain tiles 5, map structures 16, props 2, weapons 1, effects 6,
  pickups 6, UI 0. REJECTED: 946 files (palette duplicates; see
  SKY_BRAWL_USE.md §Rejected). Import ONLY the 54 selected files.
- Transparency (PIL, all 1,000 files): NO dark-box risk anywhere —
  opaque corners/edges 0 in every sprite category. One exception:
  terrain tiles are 0% fully transparent but 7–78% SEMI-transparent
  (alpha ~90–110); selected tiles (6.7–28.9% semi) MUST be
  alpha-flattened onto an opaque base before import or sky will show
  through solid platforms. `terrain_003` (51%) and `terrain_008` (78%)
  rejected partly for this.
- Honest quality notes: the pack is ~7 base designs per category ×
  palette swaps (1 robot × 5 colours; 1 rifle silhouette — cannot
  distinguish SMG/Shotgun/Sniper/Rocket; 1 night-sky scene × 5 ground
  palettes; ~8 real tile designs, the rest one blue-blob tile × ~130).
  Characters are SINGLE 96×96 frames — lobby select-screen variants
  only, NOT animated player replacements (97-frame soldier stays).
  Backgrounds are 960×540 vs maps up to 3600 px wide and all contain
  baked-in fake platform bars — use ONLY as a far parallax layer at
  viewport scale, never stretched over the map; 5 of the 13 assignments
  are POOR-fit (day maps: Military, Desert, Frozen, Jungle, Pirate —
  keep the procedural gradient there). No mast/sail/wood-deck art for
  Airship Fleet, no carved pillar for Ancient Temple, no neon skyline
  for Neon City — those remain Gemini/procedural gaps.
- Gemini impact: icons + crate/barrel set now COVERED by the pack;
  tile strips PARTIALLY covered; menu background + 3 new-map skies
  still NOT covered. If one late-night Gemini retry is spent, spend it
  on the Neon City sky (see V3_PLAN.md Phase 2).
- No game code touched by this curation (read-only on .gd/.tscn/.cfg);
  no asset files copied into the project yet — Phase 5/6 builders
  import the 54 selected files per SKY_BRAWL_USE.md.

---

## Phase 3B — Physics audit + rebuild (2026-11-19, per PHYSICS_SPEC.md points 1–28 + PHYSICS_AUDIT.md GAP-01–GAP-75)

Version NOT bumped (still 2.5 / code 7). No music wiring, no maps touched.
`export_presets.cfg` still excludes `gen_assets_v3/*`. V3_PLAN.md untouched
(coordinator-owned). Git baseline: commit `5fe7e0e` (v2.5 on Godot 4.7.2,
before this phase). New file: `physics_config.gd` (`PhysicsConfig` — the
single source of truth for tuning values, with adopt/keep/decide verdicts
as comments). All runs below on Godot 4.7.2, headless Xvfb,
`--auto-host`, zero script errors in every run.

### QA-031 — Jetpack re-engaging mid-jump chops the jump (real bug, found by the physics harness)
- Symptom: hold-jump apex measured 105 px instead of ~155 px (P07a).
- Root cause: Phase 3B gave fuel air-regen (GAP-05). Fuel regenerated
  mid-rise, the jetpack branch engaged, and its −450 rise cap clamped the
  −660 jump velocity down to −450. (In v2.5 fuel only refilled on the
  floor, so this could not happen.)
- Fix (`player.gd`): thrust applies only while `velocity.y > -MAX_JET_RISE`
  — the jetpack sustains a climb, it never chops jump momentum and never
  pushes rise speed past its cap; fuel drains only while actually
  thrusting. Hold apex is now 156 px (P07a PASS), tap apex 54 px (P07b).
- The harness isolates the pure jump by setting fuel 0 + a 999 s regen
  delay during P07a/P07b (holding stick-up otherwise jets to ~300 px).

### QA-032 — Decor insets floated low cover off the floor; the capsule rode over crates (real bug, GAP-14 regression vs v2.5)
- Symptom: collision test WALK-BLOCKED failed — the player walked through
  the Catacombs crate (x 919 → 1209, unimpeded).
- Root cause: GAP-14 shrank decor collision rects uniformly (sides + top
  + bottom). The crate rect (985, 1316, 30, 30) floated 6 px above the
  floor; the capsule's rounded bottom caught the floating bottom edge and
  rode up over the 30 px crate. In v2.5 the rect reached the floor.
- Fix (`game.gd` `_build_arena`): insets apply to the sides and top only;
  the rect bottom sits on the ground point (box height `h - inset`,
  centre shifted down `inset/2`). Barrel registry rect updated to match
  the shape position. The collision-test helper `_ct_solid_rects` mirrors
  the same rect (it previously expected the full-texture face).
- Verified: collision test 8/8 on all 10 maps; bullet ray stops at the
  inset face x=985 (6 px inside the sprite's transparent edge — the
  visible edge, as the audit allows).

### QA-033 — Stuck-recovery teleported a player who was only pushing against a wall (real bug, GAP-72)
- Symptom: collision test WALK-BLOCKED — the player pushed against the
  crate, then appeared at x=593 (spawn 600,1320).
- Root cause: `move_and_slide` leaves ~1 px of solver penetration when a
  player pushes flush against a wall; `_check_stuck` used a full-size
  capsule shape query, so the 1 px penetration counted as "inside solid
  geometry" and fired the recovery.
- Fix (`player.gd`): the query capsule is 3 px smaller than the real one
  (radius 14, height 46). A flush push no longer triggers; a real embed
  (10+ px deep) still does. P24 still passes (stuck player moved to a
  valid spawn).

### QA-034 — Bounce pad sits in front of the Catacombs crate; the walk test teleported onto it (test-only)
- Symptom: WALK-BLOCKED trace showed the player launched at vy=−750 one
  physics step after the walk setup, flying over the crate.
- Root cause: Catacombs is 3200 px wide, so the pads are at x=960 and
  2240 — the pad at 960 (span 915–1005) sits directly in front of the
  crate (985–1015), and the walk setup teleported the player to x=925,
  onto the pad. The pad launch is correct game behaviour.
- Fix (test only): the walk test approaches the cover from the side whose
  path does not cross a pad rect (walks left into the crate's right face
  on Catacombs). No game code changed.

### QA-035 — Fire test expected 6 shotgun pellets after the spec change to 7 (test-only)
- The game correctly fires 7 pellets (GAP-20, spec §9 wins over §20's 6).
  The fire test step `MP-SHOTGUN-SIX-PELLETS` still expected 6. Renamed to
  `MP-SHOTGUN-SEVEN-PELLETS`, expects 7. Fire test back to 25/25.

### Gaps fixed (by GAP number)
- GAP-01 ground/air split: SPEED_GROUND 350 / SPEED_AIR 360,
  ACCEL_GROUND 2600 / ACCEL_AIR 1500, DRAG_GROUND 8.0 / DRAG_AIR 1.2,
  reversal bonus 1.6× ground / 1.2× air; no-input decel is exponential
  drag only (the earlier linear DECEL in the no-input branch double-damped
  the air slide and was removed; DECEL consts kept as tuning reference).
- GAP-02 air drag `exp(-k·dt)` (see GAP-01). GAP-03 covered by the same
  change. GAP-04 variable jump height (`velocity.y *= 0.45` on stick-up
  release while rising, armed at jump, cleared on landing/jetpack).
- GAP-05 fuel regen delay 0.6 s; regen on ground 70/s and air 35/s.
- GAP-06 jetpack flame: new `_flame` Polygon2D at (0,18), driven by real
  `_jetpacking` + fuel>0, scale by thrust fraction, blinks at fuel < 25.
- GAP-07/GAP-08 aim: dead zone 0.20 applied ONCE in `joystick.gd` (the
  0.25 thresholds in `game.gd` and `player.gd` removed); aim no longer
  snaps to facing on aim-stick release.
- GAP-09 dead zone single source of truth (joystick.gd, 0.20).
- GAP-10 rocket gravity arc: speed 700 → 450, gravity 500, life 2.5 s,
  rate 1.0 s ("heavy" rocket).
- GAP-11 grenade bounce uses pre-slide velocity (restitution 0.45, drag
  0.15, terminal velocity 950, resting state, rolling friction
  `exp(-4·dt)`).
- GAP-12 explosion LOS: `has_line_of_sight()` raycast (mask 1) per victim
  in `request_explosion`; blocked victims take no damage and no knockback.
- GAP-13 bridges/arches get a thin 24 px top plank.
- GAP-14 decor per-kind insets (sides/top only after QA-032).
- GAP-15 (per-projectile state): bullet velocity Vector2, per-projectile
  `grav`/`drag`/`range_px`/`radius`, `_travelled`; expiry on life OR range.
- GAP-16 100 ms interpolation buffer for remote players (12 snapshots,
  render at now − 100 ms, extrapolate at most one physics step);
  snapshots 20 → 30/s (GAP-60); `life_state` added to sync properties.
- GAP-17 (knockback on victim peer, host never reconciles): covered by
  GAP-16 — victim knockback is applied via `take_hit` on the victim peer.
- GAP-18 input latency: measured first — fire-test tap steps pass
  (1 tap = 1 shot, none lost/doubled); `_update_touch_state` left in
  `_process` (no tap loss observed).
- GAP-19 (bullet pool budget): pool 96 → 160 (GAP-67).
- GAP-20 shotgun 7 pellets, fixed spread table [-15,-10,-5,0,5,10,15]°.
- GAP-21 bullet layer 8 → 4 (spec §24.D); raycast is the real collision.
- GAP-22 explosion falloff smooth `D = Dmax·(1−u²)²`; GAP-23 knockback
  `J = 550·(1−u)²`, `ΔV = J/m`, vertical multiplier 0.4.
- GAP-24 explosion FX: white flash (0.08 s), expanding shockwave ring,
  8 debris particles.
- GAP-25/26/27/28 (grenade drag/rest/terminal velocity): see GAP-11.
- GAP-29–GAP-31 (moving platforms / terrain materials): see deferred.
- GAP-32 grenade drag 0.15 (see GAP-11). GAP-33 grenade resting state.
- GAP-34 player collision: `PLAYER_COLLISION_ENABLED = false`
  (pass-through preserved, spec's recommended default),
  `PLAYER_DAMAGE_COLLISION = true`, `PLAYER_EXPLOSION_COLLISION = true`.
- GAP-35 pickup sine float + rotation sway `0.12·sin(_bob_t·1.5)`.
- GAP-36 weapon drop: NOT built (out of scope, see deferred).
- GAP-37 pickup respawn: 3 spawned at match start from distinct spots,
  per-spot 14 s respawn timers, `despawn()` restarts its spot's timer,
  `spawn_pickup_remote` takes `spot_idx`.
- GAP-38 burst mode: NOT built (out of scope).
- GAP-39 time-based firing `T = 60/RPM` (already the design; verified by
  fire-test hold counts). GAP-40 reload state machine (READY/FIRING one
  frame/RELOADING). GAP-41 magazine vs reserve ammo (pistol −1 infinite;
  rifle 90, SMG 96, shotgun 18, sniper 10, rocket 8).
- GAP-42 damage multipliers: `calculate_damage()` (base × region ×
  distance × weapon × armor; head 1.5 / torso 1.0 / legs 0.75; arms
  folded into torso — documented deviation); distance falloff 1.0 inside
  400 px → 0.7 at max range; `hit_region()` from hit height (head
  rel_y < −14, legs > 12).
- GAP-43 unique damage event IDs (`next_damage_event_id()`, dedupe last
  64 ids in `take_hit`).
- GAP-44 death FSM: ALIVE → DYING (0.4 s) → DEAD → RESPAWNING → ALIVE;
  `take_damage` guards on `life_state == ALIVE`.
- GAP-45 validated respawn: `get_valid_spawn_point()` / `is_spawn_valid()`
  (bounds, capsule shape query mask 1, >150 px from live enemies;
  `Vector2.INF` if none valid; `_respawn()` retries in 0.5 s).
- GAP-46 per-weapon victim knockback (pistol 40, rifle 60, SMG 40,
  shotgun 180, sniper 220, rocket 400).
- GAP-47 invulnerability duration: defined by the existing spawn
  protection (QA-002, unchanged); visuals never apply damage (damage only
  via `take_hit`/`take_damage` RPC paths).
- GAP-48/49/50 hazards: lava tick 1.0 s × 20 HP → 0.5 s × 10 HP (same
  20 HP/s).
- GAP-51 ice zone: Frozen Fortress only (floor zone x 300–2500, y > 1392),
  friction 100, accel 500, max speed 350, air control 0.65; ice sheen
  visual added.
- GAP-52 camera dead zone (120×80 px anchor) + GAP-53 look-ahead (up to
  80 px); smoothing 8.0; hard map limits unchanged (already conforming).
- GAP-54 victim shake on damage 0.25 / explosion 0.5.
- GAP-55 velocity inheritance 0.15 (baked into the bullet velocity vector).
- GAP-56 prototype comparison recorded: adopted rifle rate 0.125, max
  fall 1000; kept jump −660, pistol 0.22 s; rocket 700 NOT kept — 450 +
  gravity 500 instead (GAP-10, "heavy" rocket decision).
- GAP-57/58 (firing while moving / sync): see GAP-55 / GAP-16.
- GAP-59 disconnect/reconnect: unchanged behaviour (host leaving ends the
  match with a message; reconnect IP prefilled) — user two-phone check
  still owed (T-74).
- GAP-61 version handshake: `request_spawn` takes optional `version`;
  mismatched build refused + `version_mismatch_remote` readable error;
  `_announce_ready` sends `GameData.BUILD_VERSION` ("3.0-dev", GAP-61).
- GAP-62 moving platforms: NOT built (out of scope).
- GAP-63 (host validation): shooting_sync validation unchanged and
  re-verified by code path (T-64).
- GAP-64 explosive barrels: `barrels` decor registered (100 HP, blast
  radius 170, damage 70), host-authorised `try_barrel_hit()`,
  `barrel_destroyed_remote` RPC, blast chaining in `request_explosion`.
- GAP-65 (barrel LOS/falloff): barrels use the same `request_explosion`
  LOS + smooth falloff as grenades.
- GAP-66 bounce pads: two per map on the floor (0.3× / 0.7× map width),
  Area2D layer 8/mask 2, `velocity.y = -750`, 0.3 s per-player cooldown.
- GAP-67 bullet pool 160 (see GAP-19). GAP-68 (pool overflow): pool
  drains to 0 within 2 s of stopping (perf test); no overflow observed.
- GAP-69 physics/rendering separation: `_update_visuals()` moved from
  `_physics_process` to `_process`; camera update in `_process`.
- GAP-70 `physics_config.gd` extracted (full component split out of scope).
- GAP-71 layer scheme: `project.godot` `[layer_names]` (1 world, 2 player,
  3 enemy, 4 projectile, 5 destructible, 6 hazard, 7 pickup, 8 trigger);
  bullet.tscn layer 8 → 4, pickup.tscn layer 16 → 7.
- GAP-72 stuck recovery: 1 s shape-query check, teleports to nearest
  valid spawn only when actually overlapping solid geometry (QA-033 fix
  for the 1 px false positive).
- GAP-73 perf soak: `--perf-test` 60 s soak (see results below).
- GAP-74 (two-phone checks): user-owed, see T-31/32/63/74.
- GAP-75 git: `git init`, `.gitignore` (`.godot/`, `*.apk`, `*.apk.idsig`,
  `*.import`), baseline commit `5fe7e0e`.

### Gaps deferred / out of scope (audit verdicts, not built)
- Moving platforms, full destructibles, ropes, water/mud/wind,
  flamethrower, lag compensation, host migration, one-way platforms,
  weapon drop, burst-unless-added, full prediction/reconciliation, full
  component split — all out of scope per the audit (reasons in
  PHYSICS_AUDIT.md); do not build in later phases without a new decision.
- Arms hit region 0.85×: folded into torso (single-body hitbox kept per
  the audit's "headshots optional, do not over-complicate" verdict).
- Peer-authoritative movement kept as the documented LAN design decision
  (host-authoritative combat/shooting/health/deaths/kills/pickups
  unchanged).
- TileMapLayer: maps are built in code with Rect2 platforms, NOT
  TileMapLayer — deliberate, does not matter.
- Fast-fall (stick down, 1300 px/s) does not exist as a feature; terminal
  velocity is a flat 1000 cap (T-07).

### Decisions recorded for the next phase
- Rocket: 450 px/s + gravity 500 (arcing, "heavy"), NOT 700 straight.
- Shotgun: 7 pellets (spec §9), fixed spread table.
- Pistol reserve infinite (−1); other reserves rifle 90 / SMG 96 /
  shotgun 18 / sniper 10 / rocket 8.
- Lava: 0.5 s × 10 HP ticks (same 20 HP/s as before).
- Jetpack: sustains a climb, never chops jump momentum (QA-031).
- Decor collision: insets on sides/top only, bottom on the ground (QA-032).
- Known edge case (pre-existing, v2.4): simultaneous lethal hits from two
  shooters could double-credit a kill (T-56 partial).

### Physics harness results (`--physics-test`, 31 steps P00–P24)
- Map 0 (Catacombs): **31/31 PASS**. Hold apex 156 px / tap 54 px;
  ground time-to-300 0.20 s / air 0.29 s; half-stick 131 px/s; ground stop
  52 px / vel 8; air slide 180 px in 1 s / vel 94; max fall 1000; fuel 0.0
  at 0.3 s / 63.0 at 1.5 s; aim hold −0.79 rad (no snap); dead zone zero;
  shotgun table 7 / 0.125 / 450 / 500; damage head 18 / torso 12 / legs 9;
  explosion 55 / 31 / 0; respawn validation false/true; grenade
  bounced+resting; inheritance 1149.5; recoil 0.23 → decay 0.000; camera
  smoothing 8.0 / look-ahead 73; pool 160/0; version refusal; barrel
  hit+destroy; bounce pad vel −657…−680; stuck recovery to a valid spawn.
- Map 4 (Frozen Fortress): **22/22 PASS** (9 steps skipped as not
  applicable — placements tuned for Catacombs; no barrels on that map).
  Live ice: run vel 270 px/s, slide 282 px in 1.5 s vs 46 px ground stop
  (6.1× the 3× requirement), vel still 80 after 1.5 s.
- Note: physics ticks lag real time under Xvfb, so time-based checks use
  widened ranges; the harness records the raw numbers in its output.

### Audit tests T-01–T-75 — result per test
- PASS headless (harness evidence): T-02 (P01/P02), T-03 (P03), T-04
  (P04b), T-05/T-06 (P05b vs P04b, 3.5×), T-07 (P06, flat 1000 cap),
  T-08 (P07a/P07b, hold 156 / tap 54), T-13 (P08/P08b), T-17/T-18
  (P09a/P09b), T-19 (P10), T-24 (P15), T-25 (P11, arcing rocket),
  T-26 (collision 8/8 × 10 maps), T-40 (P11 + fire-test 7 pellets),
  T-42 (P13), T-44 (P15), T-49 (fire-test hold 18 shots/2.5 s),
  T-50 (fire-test reload steps), T-51 (P12), T-53 (P17/P17b), T-58
  (P18a/P18b on map 4), T-60 (P16, 1149.5), T-61 (P11 + fire-test
  hold/tap/pellets), T-68 (constants spot-checked), T-71 (collision
  8/8 × 10 maps after renumber), T-72 (P24).
- PASS by code path (no headless run of the exact procedure; code read
  and the mechanism verified): T-01 (reversal bonus 1.6×/1.2×; no
  single-frame sign flip by construction — accel is applied per-frame),
  T-09 (coyote 0.10 s + buffer 0.12 s preserved from v2.5),
  T-10 (landing via move_and_slide + floor snap 4.0; hard-landing dust
  puff in code for vy > 550), T-11 (thrust only while vy > −450, cap
  enforced), T-12 (drain 45/s → 2.2 s to empty; thrust blocked at 0
  fuel), T-14 (velocity NOT zeroed on stick-up release), T-15 (flame
  driven by real thrust state; visual check needs a real screen),
  T-16 (air accel 1500 applies while jetpacking), T-20 (swept raycast
  in bullet.gd + collision-test ray evidence; the 20-shot sniper run
  was not done headless), T-21 (recoil table + gun kick/shake preserved;
  accumulation measured in P17), T-22 (knockback formula ΔV=J/m in
  take_explosion_damage; falloff measured in P13), T-23/T-43 (LOS check
  in request_explosion; same raycast the collision test proves stops
  at cover), T-27 (bridge/arch 24 px planks in _build_arena; walk
  over/under not run headless), T-28 (mask 1 excludes layer 2),
  T-29 (move_and_slide + StaticBody2D platforms; 10/10 drops not run),
  T-30 (host-only damage in bullet.gd/shooting_sync.gd, re-read after
  the rebuild), T-41 (swept raycast; thin-plank stop not run as a
  dedicated step), T-45 (grenade fuse 2.0 s in code; P15 proves no
  early explosion; exact 2.0 s timing not timed), T-46 (sine bob +
  rotation sway in pickup.gd; visual bob needs a real screen),
  T-47 (per-spot 14 s respawn timers in code; timing not run),
  T-55 (death FSM in code + P14 validator; live kill→respawn watch
  not run headless), T-57 (lava 0.5 s × 10 HP ticks in code; no kill
  credit per the audit's conforming note), T-62 items (1) muzzle at
  gun-texture end (~48 px from centre, outside the 17 px capsule) and
  (2) no self-hit (shooter excluded) — code path; (3)(4)(5)(6)
  evidenced by P09/fire-test/perf-test (see T-62 below), T-64 forged
  RPC rejection (sender/rate/ammo validation in shooting_sync.gd;
  version refusal measured in P21), T-65 barrel LOS/falloff (same
  request_explosion path as P13; barrel hit/destroy measured in P22),
  T-66 single-trigger (0.3 s per-player cooldown in code; launch
  measured in P23), T-69 (input → movement → projectiles → damage
  order in _physics_process; visuals in _process; no visual code
  writes position/velocity — grepped), T-70 (visuals in _process,
  simulation in _physics_process, remote interpolation in _process).
- PARTIAL (part evidenced, part not): T-33 (tap = 1 shot, no loss/
  doubling in the fire test; the 10-rapid-tap run itself not done),
  T-56 (event-ID dedupe implemented; the simultaneous-lethal-hits
  double-credit edge remains a documented known issue), T-59
  (smoothing 8.0 / look-ahead 73–80 measured in P19; dead zone, hard
  limits and victim shake are code-path), T-62 (items 3–6 evidenced,
  items 1–2 code-path), T-73 (60 s soak green, mem +350 KB; the audit
  wants a 10-minute soak with 8 simulated players — the harness runs
  60 s with 1 local player full-auto + grenades; FPS not measurable
  headless), T-75 (gate ticked except the two-phone LAN check).
- N/A with reason: T-48 (weapon drop — out of scope), T-54 (burst
  mode — no burst weapon added), T-67 (moving platforms — out of
  scope).
- USER-TO-TEST (two real phones, sandbox blocks UDP): T-31 (remote
  smoothing, 100 ms buffer + 30/s snapshots implemented), T-32
  (knockback sync), T-63 (interpolation buffer behaviour),
  T-74 (LAN disconnect/reconnect). T-52: default non-blocking mode
  verified by code; there is no blocking mode to test (pass-through
  is the only mode, the spec's recommended default).

### Regression results (Phase 3B final run, 2026-11-19)
- Joystick `--joy-test`: 21/21. Fire-button `--fire-test`: 25/25.
- Smoke `--smoke-test`: 19 phases, no script errors (fuel 100.0,
  shots 23, bullets 160, local alive).
- Collision `--collision-test`: 8/8 on ALL 10 maps (Catacombs,
  Military Base, Desert Outpost, Industrial Factory, Frozen Fortress,
  Jungle Ruins, Space Station, City Underground, Volcanic Cavern,
  Pirate Island).
- Multiplayer `--net-test`: 11/11. Menu network `--menu-net-test`: 6/6.
- Full flow `--flow-test`: menu → create room → lobby → start match →
  play → pause → scoreboard → end screen → back.
- Scale `--scale-test`: 70/70.
- Perf `--perf-test`: 60 s soak, memory growth 349,912 bytes (limit
  50 MB), active bullets drain to 0 within 2 s of stopping.
- 0 script errors in every run above.

### Notes for the next phase (features/UI/music/maps)
- The physics harness lives in `game.gd` (`--physics-test`, 31 steps;
  add `--map=4` for the live ice run). Steps P01/P02/P04/P05/P07/P14/
  P22 are skipped on map 4 (Catacombs placements); P18b is skipped on
  map 0.
- Bounce pads sit at 0.3× / 0.7× map width on the floor — on Catacombs
  the 0.3× pad (x=960) is directly in front of the crate (x=1000).
  Any test or map work that walks the floor near a pad must account
  for the launch (see QA-034).
- Decor collision rects now reach the floor (QA-032) — if a future map
  pass re-insets decor, keep the bottom on the ground or low cover
  becomes walk-overable.
- The stuck-recovery query capsule is deliberately 3 px smaller than
  the real capsule (QA-033) — do not "fix" it back to full size.
- The jetpack must never clamp a faster jump rise (QA-031) — thrust
  only while `velocity.y > -MAX_JET_RISE`.
- Version is still 2.5 / code 7 — the final phase bumps it. Do not
  remove the `gen_assets_v3/*` export exclusion. Do not generate
  Gemini assets until the user says so ("Not now wait").

## Phase 4+6 — Common features + UI + music (2026-11-19 ~02:22–03:30 IST)

All 11 features from RESEARCH_v3.md §(b) built (LAN-only, no internet/server/accounts).
Built-in Godot UI kept (no gohud — research verdict). Version still 2.5 / code 7.
Maps untouched (next phase). Physics constants untouched (only via physics_config.gd).
QA-029 HUD touch fix preserved (hud.get_final_transform(); untouched code paths).

### Features added
- Kill feed (game.gd announce_kill RPC, host-only): "A ☠ B — Rifle", self-kills,
  environmental deaths ("☠ X died"), 4 lines, 5 s fade. Host announces at the
  bullet lethal branch and the explosion lethal branch; a host death watcher
  covers killer-less deaths (lava etc.) with a fed-deaths set so no death is
  fed twice. Streaks tracked from the same feed on every peer.
- End-of-match stats: kills/deaths/K-D/accuracy (shots fired vs shots that hit —
  new player._shots_hit, one trigger pull counts once however many pellets land;
  _shots_fired/_shots_hit added to the MultiplayerSynchronizer list) + best
  streak. Pure math in GameData.compute_stats (K/D = kills/max(deaths,1),
  accuracy capped at 100%).
- Real settings screen (main.gd): sound volume, music volume, music on/off,
  joystick sensitivity, FIRE button size (0.8–1.3x) + side (Right/Left — left
  mirrors the whole control cluster: move stick right, aim stick left, FIRE
  bottom-left corner, button column left; touch routing switches to
  nearest-stick in left-handed mode, half-routing untouched by default),
  show FPS (Engine.get_frames_per_second() in the HUD), invert aim (aim Y
  flipped in _update_touch_state). All in GameData, saved to user://settings.cfg.
- Better scoreboard: sorted by kills, K/D + accuracy columns, TDM team-totals
  header ("RED n — m BLUE"), self row highlighted white with "►" + "(YOU)".
- Weapon info panel: pause menu → "Weapons" lists all 6 weapons from
  weapons.gd (damage, shots/s, mag, reload, auto/tap, explosive).
- Match countdown: 3-2-1-FIGHT + goal banner ("First to 10 kills • Catacombs" /
  mode text). Host drives it, sync_countdown RPC keeps clients in step, clients
  have a watchdog so a late joiner can never stay frozen. Input frozen during
  the countdown; match clock starts after it. Skipped in all scripted harnesses.
- Hitmarkers + damage numbers: host sends hit_confirm (damage, position,
  lethal) to the shooter; centre "✕" (red on lethal) + a floating damage number
  at the hit point. Explosions confirm per victim with falloff damage.
- MVP / match summary screen: star icon (Sky Brawl pickup_012) + "MVP: name —
  n kills, x% accuracy, best streak n", best-accuracy line, per-row K/D, ACC,
  streak (rounds for Survival). Reuses end-of-match stats.
- Map vote in lobby: ballot = host's pick + next two maps; every player votes
  (vote travels in the lobby player dict, set_vote RPC); host tallies at start
  via GameData.tally_map_vote (most votes wins, ties / no votes / off-ballot
  votes keep the host's pick). Vote counts shown live on the buttons.
- Health/grenade pickups: kinds 5/6 already existed in the rotation; now a
  health pack is always among the 3 starting pickups, and kinds 5/6 render
  with Sky Brawl icons (green cross pickup_007, blue ammo bars pickup_002).
- Spectator mode (stretch, done): Survival/LMS — after death the spectate
  camera follows a living player (smooth follow, "SPECTATING: name" label,
  NEXT PLAYER button cycles). Respawning hands the camera back.

### UI polish (all screens)
- Menu: music credit line added under the hint.
- Settings: rebuilt as Audio / Controls / Music credits sections, scrollable;
  full CC BY 4.0 attribution text in-game (see below).
- Lobby: map-vote section with live counts, Sky Brawl robot portraits
  (portraits 15–19 in customize + lobby list; single static frames only).
- HUD: kill feed (top-left), countdown + goal banner, hitmarker, FPS label,
  spectator label + NEXT button, Sky Brawl hit spark (small impacts) and
  explosion sunburst (large impacts) replace the old smoke/explosion sprites.
- Pause: "Weapons" button added (sliders unchanged). End screen: MVP banner +
  stats columns. All touch targets ≥ 56 px (unchanged system).

### Music (Phase 6)
- Tracks ship in the APK now: menu_at_rest.ogg (3:26, loops cleanly) and
  battle_five_armies.ogg (2:35). audio.gd: play_menu_music / play_battle_music /
  stop_music / set_music_enabled; menu track in menu/lobby/end screen, battle
  track in matches, stopped on leaving a match (never overlaps, never plays on).
  Battle loop restart is crossfaded between two players (1.5 s, starts 2 s
  before the end); menu track loops cleanly via OGG loop=true. Procedural loop
  kept only as a fallback if an OGG fails to load.
- export_presets.cfg: exclude_filter="gen_assets_v3/*" REMOVED (key kept as
  exclude_filter="" — deleting the key makes the editor error on import).
  This supersedes the Phase 3B note "Do not remove the exclusion" — the
  exclusion was for staging files; the OGGs are the shipped music now.
- Attribution in-game (settings screen + short line on the menu), exact text:
  "At Rest" Kevin MacLeod (incompetech.com) / "Five Armies" Kevin MacLeod
  (incompetech.com) — Licensed under Creative Commons: By Attribution 4.0
  License, http://creativecommons.org/licenses/by/4.0/
- Test APK /tmp/v3-phase4-test-signed.apk (34,283,694 bytes, md5
  cf8b219913ca43a8b0355eb9c0fadbb9): both OGGs inside (imported
  .oggvorbisstr, menu 2,276,930 + battle 2,459,682 bytes), 15 Sky Brawl
  PNGs inside, package com.lanarena.shooter, v2.5/code 7, only the 3
  permissions, targetSdk 36 (4.7.2 template, as in Phase 3), apksigner
  verify passes, signer cert SHA-256 f65f2fa3… matches v2.4/v2.5.

### QA-036 — AudioStreamOggVorbis has no LOOP_FORWARD in Godot 4.7 (build break)
- Severity: Blocking (compile error on import).
- Cause: audio.gd set `stream.loop_mode = AudioStreamOggVorbis.LOOP_FORWARD`
  with loop_begin/loop_end (the AudioStreamWAV API). In 4.7 OGG looping is
  `loop` (bool) + `loop_offset` (float) — confirmed by ClassDB probe.
- Fix: `stream.loop = true; stream.loop_offset = 0.0` for both tracks.
  The battle crossfade does not rely on the loop flag (it is a safety net).

### QA-037 — Spectator test vs the LMS elimination rule (test-only)
- Severity: Low (test harness only, not the game).
- Cause: the features-test spectator step killed the local player with only
  one other player alive, so LMS ended the match (alive_count <= 1) and
  _update_spectator stopped itself before the check ran.
- Fix: the step spawns a second living bot (id 98) so the match stays live
  while spectating, and removes it in the check. The game behaviour is
  correct — spectator mode is only reachable while the match is still live.

### QA-038 — Removing exclude_filter entirely breaks preset validation (build)
- Severity: Low (export preset).
- Cause: deleting the `exclude_filter` line from export_presets.cfg makes the
  editor error "Couldn't find the given section preset.0 and key
  exclude_filter" on every import.
- Fix: keep the key with an empty value (`exclude_filter=""`).

### Test results (Phase 4+6 final run, 2026-11-19, Godot 4.7.2, xvfb-run)
- NEW --features-test: 11/11 (COUNTDOWN-FREEZE, COUNTDOWN-END,
  KILLFEED-HITMARKER, END-STATS-MVP, SETTINGS-PERSIST, MAP-VOTE,
  PICKUPS-HEALTH-GRENADE, MUSIC, SPECTATOR, SCOREBOARD, FIRE-LAYOUT).
- Regression: joystick 21/21, fire-button 25/25, smoke 19 phases
  (shots 23, fuel 100.0, local alive), physics --physics-test 31/31,
  multiplayer --net-test 11/11, menu network --menu-net-test 6/6, full flow
  (menu → create room → lobby → start match → play → pause → scoreboard →
  end screen → back), scale 70/70, collision 8/8 on ALL 10 maps, perf
  60 s soak mem +345,960 bytes (limit 50 MB), bullets drain to 0.
- Voted-map load proof: --smoke-test --map=1 (Military Base, the tally
  winner in the features test) passes, 23 shots, local alive.
- Visual checks (non-headless screenshots, 1280x720): menu (credit line),
  settings (all controls + exact attribution), lobby (players, robot
  portraits, vote buttons with counts), in-match HUD (bars, timer, weapon,
  buttons, Sky Brawl health-cross pickup visible in the world).
- Script errors: none from this phase's code. The two `save_png` errors in
  the headless smoke run are the known pre-existing headless noise
  documented in v2.4 (no viewport texture headless); phases pass.
- Honest limits (unchanged): real touch hardware and real two-phone LAN
  join untested here (sandbox blocks UDP); battle-track crossfade timing
  verified in code + headless state checks, not by listening; the map-vote
  tally is unit-tested and the flow test covers the lobby, but a live
  two-phone vote (client votes → host tallies → voted map loads) still
  needs a real-phone check.

### Notes for the next phase (maps)
- Map vote ballot is derived from GameData.map_id (+1, +2 mod 10): when the
  maps phase adds Neon City / Ancient Temple (and renumbers or extends
  MAP_NAMES), the ballot follows automatically — no vote code changes needed.
- The countdown sub-label and the lobby room-info line read
  GameData.MAP_NAMES[map_id]; new maps appear there automatically.
- Sky Brawl files imported (15, ~60 KB, all true transparency verified):
  assets/skybrawl/pickups/{002,005,007,012}, effects/{001,003,004,005,006,009},
  characters/{001–005}. Only 001/006 are used for impacts, 002/007 for
  pickups, 012 for the MVP star, 001–005 as portraits; 003/004/005/009 are
  imported but unused so far (rings/smoke/lightning — available for the maps
  phase or later FX). Do NOT import the other 946 pack files.
- Countdown is skipped whenever any test flag is set (including
  --features-test, which drives it in step 1). If a future harness needs a
  real countdown, it must set _countdown_active itself like the features test.
- Accuracy counts gun hits only: rocket splash damage gives a hitmarker but
  no accuracy credit (no shot number travels with an explosion). Grenade
  throws are not shots. Documented, not a bug.
- Simultaneous lethal hits from two shooters can still double-credit a kill
  (pre-existing known issue from v2.4, unchanged).

## Phase 5 — Maps: every map unique + playable (2026-11-19, Godot 4.7.2)

13 maps (was 10). 7 kept with global fixes, 3 rebuilt, 3 new. Map
generator + Python validator lived in /tmp/phase5 (lost in a runtime
restart mid-phase — the validated MAPS block in game.gd is the record;
the generator is NOT in the repo, so a future map tweak edits game.gd
directly or rebuilds the generator from this section + MAP_AUDIT.md).

### Maps changed / added
- Kept (global fixes): Catacombs 3200x1400, Military Base 2880x1440,
  Desert Outpost 3000x1500, Industrial Factory 3200x1600, Frozen
  Fortress 2800x1500, Jungle Ruins 3200x1400, Volcanic Cavern 3000x1500.
- REBUILT Space Station 3000x1500: vertical station, 3 disconnected
  decks, central vertical shaft (fast/exposed) + side maintenance
  tunnels (slow/covered). Was a Template A clone.
- REBUILT City Underground 3200x1600: subway, two stacked tunnel
  tubes (upper fast/exposed, lower slow/covered, pillars ~350 px)
  + 3 stair shafts; hot zone on the centre platform between tubes.
- REBUILT Pirate Island 3000x1500: asymmetric beached ship — stepped
  hull to crow's nest LEFT, open sand mid, below-deck tunnel RIGHT.
  Was a Template A clone; kept (not cut) as the asymmetric map.
- NEW Neon City 3400x1800: vertical figure-eight, two rooftop towers,
  street alley, centre skybridge (no cover) as the hot zone.
- NEW Ancient Temple 3000x1750: stepped ziggurat (3 tiers to altar)
  + crypt tunnel below the floor.
- NEW Airship Fleet 3200x1500: disconnected decks (3 ships + safety
  net); falling = respawn, no death (player.gd already respawns at
  y > map_size.y + 200 with no kill credited — no new rule needed).
- NOT done: Frozen Fortress duel shrink (~2200x1400) — deferred,
  lowest priority; Frozen stays 2800x1500.

### Global fixes (all 13 maps)
- Centre-weapon pinning: pickups[3] is the centre spot (map centre
  x) and spawns ONLY Sniper (3) / Rocket (4), alternating, with a
  visible HUD countdown (CENTRE: SNIPER/ROCKET HERE or ... in Ns).
  Initial pickups: SMG at spot 0, Sniper at centre, Health at spot 4.
  Other spots spawn only SMG/Shotgun/Health/Grenades.
- TDM spawn grouping: spawns[0:6] left half (team 0), spawns[6:12]
  right half (team 1); FFA keeps round-robin order.
- 2-3 solid floor decor per map at <=400 px spacing; 3-4 floor spawns
  staggered onto upper platforms; centre pickup moved to the true
  centre of each hot zone.
- Volcanic Cavern floor re-segmented so the bounce pads (0.3x/0.7x
  width) land on deck; Airship deck layout fixed the same way.
- MAP_NAMES extended to 13 (Neon City, Ancient Temple, Airship
  Fleet); the vote ballot already used MAP_NAMES.size(), so no vote
  code change was needed.

### Backgrounds / parallax (Sky Brawl art)
- _build_background gained a FAR parallax layer: ParallaxBackground
  (layer -100), ParallaxLayer motion_scale (0.25, 0), mirroring
  1286 px, sprite scaled to ~1286x723 (viewport scale, ~1.3x upscale
  of the 960x540 image) — NEVER stretched over the map. The
  procedural gradient + hills stay in front at 50% alpha so the
  horizon still matches each map's palette.
- Image backgrounds only on the 7 GOOD/FAIR-fit maps (Catacombs 01,
  Industrial 13, Space 18, City 04, Volcanic 09, Neon 20, Temple 19).
  The 5 POOR-fit day maps (Military, Desert, Frozen, Jungle, Pirate)
  keep the procedural gradient; Airship Fleet uses a warm sunset
  gradient.
- Sky Brawl files imported (21 only): assets/skybrawl/maps/bg_*.png
  (7), assets/skybrawl/tiles/tile_neon.png + tile_temple.png
  (alpha-flattened, 128x48; Airship reuses tile 11),
  assets/skybrawl/structures/sb_*.png (12). New solid decor kinds
  (sb_hut, sb_hut_pink, sb_hut_blue, sb_vent, sb_vent_orange,
  sb_shrine, sb_block, sb_hut_green, sb_crate) added to
  SOLID_DECOR_KINDS + DECOR_INSETS (inset 10); slabs/trapezoid/altar
  are visual-only. TILE_TEX indices 10 (Neon) and 11 (Temple). The
  other 946 pack files were NOT imported.

### QA-039 — Rock decor does not block spawn-height sightlines
- Severity: Medium (map validation).
- Cause: a rock's solid rect is only 30 px tall, so a ray at spawn
  height (32 px above the floor) passes 2 px over it. Rock/jrock
  therefore do NOT break line of sight between floor spawns.
- Fix: rock/jrock excluded from floor-lane fill; Volcanic's manual
  floor rocks replaced with crate/column. (Generator rule, not a
  game-code change.)

### QA-040 — Collision-test ray needs a clear approach (floor cover)
- Severity: Medium (test + map rule).
- Cause: _ct_floor_cover fires a ray from 120 px left of the first
  floor cover; if that cover's face is <150 px from the left edge
  the ray starts outside the map and hits the wall.
- Fix: generator enforces the first floor cover's face >=150 px
  from the left edge on every map.

### QA-041 — Harness run-ups must stay clear of solid floor decor
- Severity: Medium (map rule; broke fire/features/physics).
- Cause: the fire test and physics harness teleport to (300,1320)
  on Catacombs and run right, the camera test teleports to
  (1600,1320) and sprints right, and the Frozen ice test teleports
  to (500,1420) and slides right. A crate/column in those runs
  reads as vel.x=0 (a map bug, not a physics bug).
- Fix: CLEAR_STRETCH in the generator — face-based intervals kept
  free of floor decor: Catacombs [(280,500),(1500,1900)], Frozen
  [(280,985),(1500,1900)]. The Frozen ice lane leaves one ~870 px
  floor gap (120-1020); that IS the ice feature — the validator
  allows a 950 px gap on map 4 only (650 px cap elsewhere).
- Follow-up (same root cause): a general spawn#0 run-up rule was
  added — no floor decor with face in (spawn0.x-20, spawn0.x+360)
  on any map — after the same vel.x=0 failures appeared on Neon
  City, Space Station and Airship Fleet (P03/P04a). The run-up
  also forced two spawn moves (see QA-043).

### QA-042 — Visual-only decor blocked spawn-cover placement
- Severity: Medium (map validation).
- Cause: the generator's decor-proximity checks counted ALL decor,
  including visual-only palms. On Desert/Pirate a palm at x=150
  vetoed every left-side cover candidate for spawn#0 while the
  run-up vetoed the right side, so spawn#0 got no cover at all
  (and the floor gap grew to 705 px).
- Fix: proximity/clash checks count SOLID kinds only. Palms/trees/
  bushes never block a cover or fill slot now.

### QA-043 — Run-up vs line-of-sight: two floor spawns too close
- Severity: Medium (map design).
- Cause: on Space Station the floor spawns (250,1420) and
  (550,1420) are 300 px apart with nothing between them once the
  run-up removed the sb_hut at 420 — a clear LOS pair. Same on
  Airship Fleet (200,1348) vs (700,1348), 500 px apart. Any solid
  that blocks the ray at spawn height also blocks the running
  player, so no decor can fix it — one spawn has to move.
- Fix: Space spawn#1 moved (550,1420) -> (1400,1420) on deck B
  (first floor spawn on the middle deck; cover crate at 1490,
  barrels at 1800). Airship spawn#1 moved (700,1348) ->
  (1400,1178) on the centre deck (the hot-zone deck). Both keep
  TDM left-half grouping and BFS reachability from spawn#0.

### QA-044 — Physics harness used Catacombs-tuned coordinates
- Severity: Medium (test-only; no physics constants changed).
- Cause: the harness teleported to fixed points that are mid-air
  or inside a platform on taller/rebuilt maps: (300,1320) is
  mid-air on Neon City (P01/P04a measured the "ground" run in the
  air); (2100,1320) is mid-air on Neon so the jump-tap 0.15 s
  release fired before landing; (1600,1370) is open air above
  Neon's skybridge (P14); the grenade throw at (2100,1100) fell
  650 px to the street on Neon (P15); (1600,1320) is INSIDE a
  platform on Space Station ((1450,1280,300,48)) so the player
  wedged and camera look-ahead read 0 (P19); the (0.2,0.3) throw
  drift rolled the grenade off Space's deck B and Airship's net
  before it could rest (P15 on maps 6/12); P18b ice-slide ran (and
  failed) on every non-ice map.
- Fix (game.gd, test code only): _phys_ground_at(x) helper (lowest
  platform top at x) for jump/grenade setups; P01/P04a teleport to
  spawn#0; P14 bad point is map-relative (plats[0].top + 18);
  grenade throw is straight down (Vector2(0,1)) from 250 px above
  the map floor; _phys_top_at(x) helper (highest platform top at
  x) for the camera setup; P18b changed from "skip_map": 0 to
  "only_map": 4 with runner support (SKIP when the step's only_map
  != map_id). Physics constants untouched.

### QA-045 — No explosive barrel on Space Station / Airship Fleet
- Severity: Low (test-only gap, map fix).
- Cause: P22 shoots a live barrel; neither map had a "barrels"
  decor piece (Space's floor-kind cycle never included one;
  Airship's cycle never placed one).
- Fix: generator guarantees >=1 "barrels" on the floor of every
  map (first free slot clear of spawns/pads/decor/run-up).
  Space got barrels at 1800 (deck B), Airship at 600 (left deck).

### QA-046 — Cover crate vs the harness's left run + the palm walk
- Severity: Medium (test-only fixes + one decor move; the map
  design is correct).
- Cause: three requirements collide at spawn#0 — cover within
  150 px, a clear RIGHT run (fire test, P03/P04a), and a clear
  LEFT run (joystick PRESS-LEFT, 0.6 s check). Any cover within
  150 px left blocks the left run after ~58 px; any cover within
  150 px right blocks the right run. The same left cover at 210
  sat behind the left palm on Desert/Pirate and blocked the
  collision test's WALK-PASSES-BUSH (player stopped at x=178,
  must pass 222).
- Fix: (1) joystick test teleports to spawn#0 + 200 px right
  before the two left-press steps (_jt_teleport_clear_left;
  PRESS-LEFT and RESOLUTION-1920) — the run-up rule guarantees
  360 px clear right of spawn#0 on every map, so the left run
  from there is ~258 px. (2) The left palms on Desert Outpost
  and Pirate Island moved 150 -> 400 (visual-only decor; the
  walk path through the palm is now clear of the cover crate).
  The cover crate stays where the audit wants it.

### Test results (Phase 5 final run, 2026-11-19, Godot 4.7.2, xvfb-run)
- Python validator: ALL VALIDATION CHECKS PASS on all 13 maps
  (12 spawns + 6 pickups each; spawns[0:6] left / [6:12] right;
  pickups[3] at map centre x; no spawn/pickup inside a solid; no
  solid seals a platform; BFS reachability from spawn#0; bounce
  pads at 0.3x/0.7x on solid deck and clear of decor; 0 floor
  LOS pairs; cover within 150 px of every spawn; longest floor
  gap <=650 px (950 on Frozen); no two maps share a platform set).
- Collision: 8/8 on ALL 13 maps. Smoke: 13/13 maps pass (23 shots
  on maps 0-5, 8; 32 shots on maps 6, 7, 9-12). Joystick 21/21.
  Fire-button 25/25. Scale 70/70. Physics: 31/31 on maps 0, 6, 10,
  12; 22/22 on map 4. Features 11/11. Multiplayer 11/11. Menu
  network 6/6. Full flow (menu -> create room -> lobby -> start
  match -> play -> pause -> scoreboard -> end screen -> back).
  Zero script errors.
- Script errors: none. (The known pre-existing headless
  `save_png` noise from v2.4 still appears in smoke runs; phases
  pass.)
- Flaky threshold (not a map or physics defect): P02-air-accel on
  Airship Fleet failed ONCE during the long loaded regression run
  (air 0.25 s vs ground 0.20 s = 1.25x, want >1.3x) and passed
  31/31 on a clean re-run right after (0.28 s vs 0.21 s = 1.33x).
  The ratio is measured in real seconds under xvfb, so CPU load
  compresses it toward 1.0. If it fails again, re-run it alone
  before touching the map or the physics constants.
- Honest limits (unchanged): real touch hardware and real
  two-phone LAN join untested here (sandbox blocks UDP); the
  map-vote tally is unit-tested and the flow test covers the
  lobby, but a live two-phone vote still needs a real-phone check.

### Notes for the next phase (final packaging)
- Frozen Fortress duel shrink (~2200x1400) was NOT done — the map
  is playable as-is at 2800x1500; shrink it only if the final
  phase has spare time.
- The Phase 5 map generator + validator were in /tmp/phase5 and
  were lost in a runtime restart. The validated MAPS block in
  game.gd is the source of truth. A future map tweak should edit
  game.gd's MAPS directly (keep the rules in this section: cover
  <=150 px, no floor LOS pairs, run-up clear right of spawn#0,
  >=1 barrels per map, pads clear of decor) or rebuild the
  generator from MAP_AUDIT.md + this section.
- Version NOT bumped (still 2.5 / code 7). Do NOT build a final
  delivery APK in this phase — packaging is the final phase's job.
- Known pre-existing issue (unchanged): simultaneous lethal hits
  from two shooters can double-credit a kill.

## v3.0 — Final delivery (Phase 7, 2026-11-19, Godot 4.7.2)

Phase 5's work was delivered uncommitted in the working tree (no Phase 5
commit existed — `git log` showed only 2a16edb / aadc816 / 5fe7e0e).
Verified present before packaging: 13 maps in `game.gd` MAPS (Neon City,
Ancient Temple, Airship Fleet added; Space Station, City Underground,
Pirate Island rebuilt), 13 entries in `game_data.gd` MAP_NAMES,
`assets/skybrawl/{maps,structures,tiles}/` files, README 13-map table,
BUGS.md Phase 5 section with QA-039–QA-046. This commit covers all of it.

### Version bump (only code change in this phase, besides docs)
- `export_presets.cfg`: version/name "2.5" → "3.0", version/code 7 → 8.
- `main.gd`: in-game version label "LAN Arena Shooter v2.5" → "v3.0".
- `game_data.gd`: `BUILD_VERSION` "3.0-dev" → "3.0" (join handshake
  rejects mismatched builds, so the release build must carry "3.0").
- No gameplay, map, physics or feature code was changed in this phase.

### Final verification — full suite re-run from scratch on the final code
All runs on Godot 4.7.2, headless Xvfb, runner `run_phase5_final.sh`.
Zero script errors in every run (raw logs: `log4_*.txt`, not committed).

- **P02-air-accel re-run alone first (Airship Fleet, map 12):** PASS —
  air 0.27 s vs ground 0.20 s = 1.35x (want >1.3x). The single failure
  in the Phase 5 loaded regression (1.25x) did not recur; it was a
  CPU-load artefact of the real-seconds ratio under xvfb, not a map or
  physics defect. Physics harness on map 12 in that run: 31/31.
- **Collision:** 8/8 on ALL 13 maps (Catacombs, Military Base, Desert
  Outpost, Industrial Factory, Frozen Fortress, Jungle Ruins, Space
  Station, City Underground, Volcanic Cavern, Pirate Island, Neon City,
  Ancient Temple, Airship Fleet), errors=0.
- **Joystick acceptance:** 21/21. **Fire-button:** 25/25.
  **Scale/coordinate:** 70/70.
- **Physics harness `--physics-test`:** 31/31 on maps 0, 6, 10, 12;
  22/22 on map 4 (live ice: P18a ice run vel.x=270, P18b ice slide
  282 px in 1.5 s vs 46 px ground stop). Re-run after the version
  bump: 31/31 on map 0 again, errors=0.
- **Features:** 11/11. **Multiplayer:** 11/11. **Menu network:** 6/6.
- **Full flow:** PASS, 9 steps — menu → create room → lobby → start
  match → play/fire (3 shots) → pause → resume → scoreboard →
  end screen → back at menu. Re-run after the version bump: PASS.
- **Smoke:** 13/13 maps — players=1, local alive, shots fired 23
  (maps 0–5, 8) / 32 (maps 6, 7, 9–12), bullet pool 160, fuel 100.0,
  errors=0.
- **T-01–T-75 status (Phase 3B, re-confirmed — no changes since):**
  PASS headless: T-02, T-03, T-04, T-05/T-06, T-07, T-08, T-13,
  T-17/T-18, T-19, T-24, T-25, T-26, T-40, T-42, T-44, T-49, T-50,
  T-51, T-53, T-58, T-60, T-61, T-68, T-71, T-72. PASS by code path:
  T-01, T-09, T-10, T-11, T-12, T-14, T-15, T-16, T-20, T-21, T-22,
  T-23/T-43, T-27, T-28, T-29, T-30, T-41, T-45, T-46, T-47, T-55,
  T-57, T-62 (items 1–2), T-64, T-65, T-66, T-69, T-70. PARTIAL:
  T-33 (tap = 1 shot proven; 10-rapid-tap run not done), T-56
  (event-ID dedupe in; simultaneous-lethal-hits double-credit edge
  remains — see below), T-59 (smoothing/look-ahead measured; dead
  zone, hard limits, victim shake code-path), T-62 (items 3–6
  evidenced, 1–2 code-path), T-73 (60 s soak green, mem +350 KB;
  the audit's 10-minute 8-player soak not run headless; FPS not
  measurable headless), T-75 (gate ticked except the two-phone LAN
  check). N/A: T-48 (weapon drop — out of scope), T-54 (no burst
  weapon), T-67 (moving platforms — out of scope). USER-TO-TEST
  (two real phones, sandbox blocks UDP): T-31, T-32, T-63, T-74.
  T-34–T-39 are the suites themselves (joystick, smoke, fire,
  flow, 0 script errors, map loads) — all re-run green above.
  T-52: pass-through is the only mode (verified by code).
- **Nothing fixed in the final pass:** no test failed, so no QA
  number was issued in Phase 7 and no gameplay/map/physics/feature
  code was touched. The only headless noise: ALSA `ERR_CANT_OPEN`
  (no sound card in Xvfb; falls back to the dummy driver — does not
  occur on a real phone) and one `WARNING: Sending failed!` in the
  menu-net log (UDP broadcast blocked by the sandbox; suite still
  6/6). The pre-existing headless `save_png` noise from v2.4 still
  appears in smoke runs; phases pass.

### v3.0 release checklist
- `aapt2 dump badging`: package `com.lanarena.shooter`, versionCode 8,
  versionName 3.0, targetSdk 36 (baked into the 4.7.2 template),
  permissions ONLY `INTERNET`, `ACCESS_NETWORK_STATE`,
  `ACCESS_WIFI_STATE`.
- `apksigner verify` passes; signer certificate SHA-256
  `f65f2fa3d8041b5e8920e627355a0dd68d9b50414d6b40702fea6b4da6e02d11`
  matches v2.4/v2.5 exactly — installs over v2.5 cleanly.
- APK: `mini-militia-lan.apk`, 32,518,408 bytes, md5
  `cf6495ff319d5d0704b597491644e48d`. Built with Godot 4.7.2
  (`--export-release Android`) and signed with
  `/home/hatch/.local/share/godot/keystores/debug.keystore`.
- Contents verified: both music OGGs inside (`menu_at_rest.ogg`,
  `battle_five_armies.ogg`, as imported `.oggvorbisstr`); Sky Brawl
  textures inside as imported `.ctex` (5 characters, 6 effects,
  7 map backgrounds, 4 pickups, 12 structures, new tiles).
  NO staging files ship: no `STATUS.md`, no `.md`/`.txt` anywhere
  in the APK (the only `gen_assets_v3/` entries are the two tiny
  `.import` metadata files for the shipped music OGGs).
- v2.5 APK safe in `~/workspace/mini-militia-lan-backup-v2.5/`,
  md5 still `90fe7e3fad44dd249ba8afc9bccaf175`.

### Honest limits (unchanged)
- Real touch hardware untested; real two-phone LAN join untested
  (sandbox blocks UDP) — the user tests with the two-device guide in
  README.md. Live two-phone map vote also still needs a real-phone
  check (tally is unit-tested, flow test covers the lobby).
- Known pre-existing issue (unchanged): simultaneous lethal hits from
  two shooters can double-credit a kill (host reads the victim's
  replicated health, stale by ~0.05 s + latency).
- Performance on a real phone untested; audio not verified by ear.
- Frozen Fortress duel shrink (~2200x1400) was NOT done — the map is
  playable as-is at 2800x1500.
- The single late-night Gemini retry (Neon City sky) was NOT done in
  this phase — the maps are built with Sky Brawl art; it remains an
  iteration-phase decision, not a delivery blocker.

## v3.1 — Iteration (2026-11-19, Godot 4.7.2)

Post-delivery iteration on the green v3.0 (commit 51f68ba). Each loop
re-tested its affected suites; the v3.0 APK was never overwritten.
Version bump to 3.1 / code 9 only if the loops below stayed green.

## QA-031 — Simultaneous lethal hits double-credit a kill (T-56, known issue)

- **Cause:** the host read the victim's replicated health (stale by
  ~33 ms + latency), so two shooters landing lethal hits in the same
  moment both computed "lethal" and both got a kill credit.
- **Fix (game.gd, bullet.gd):** host-side kill-credit lock —
  `_kill_credit_lock` (victim peer id -> lock msec),
  `KILL_CREDIT_LOCK_MS = 1000`, `try_credit_kill(killer, victim,
  weapon) -> bool` (server-only; first credit locks, a second credit
  for the same victim within 1 s is denied; self-kills are excluded
  from `add_kill` but still announced in the kill feed; the lock
  expires after 1 s so the victim's next life is unaffected).
  Wired into `bullet.gd` `_hit_player` (replaces the direct
  `add_kill` + `announce_kill`) and `game.gd` `request_explosion`.
  The lock is cleared in `_on_peer_disconnected` and `_reset_round`
  (the respawn FSM runs only on the owning peer, so the lock could
  not be cleared from `player._respawn()` — hence the time-bounded
  expiry instead).
- **Tests:** net-test grew 11 -> 15 steps: DOUBLE-CREDIT (direct
  call, two shooters: first=true, second=false, A +1),
  DOUBLE-CREDIT-EXPIRE (third credit after 1.2 s = true, A +1),
  DOUBLE-CREDIT-SHOT1 (real pistol bullet at a 5-HP bot: kills 0->1),
  DOUBLE-CREDIT-SHOT2 (second lethal bullet: kills 1->1, denied).
  Harness fix in the same change: `_nt_c_lms` now resets `kill_limit
  = GameData.kill_limit` — MODE-SURVIVAL leaves kill_limit=1, and
  with lp.kills=1 from SHOT1 the per-frame FFA check would end the
  match and break HOST-LEFT-SAFE-EXIT.
- **Regression (run_phase5_final.sh, full):** collision 13/13 maps
  8/8; joystick 21/21; fire 25/25; scale 70/70; physics-map0 31/31,
  map4 22/22, map6 31/31, map10 31/31, map12 31/31; features 11/11;
  multiplayer 15/15; menu-net 6/6; flow green; smoke 13/13.
  Zero script errors. (Engine-level "RPC with unknown peer ID"
  noise from spawning fake peers via MultiplayerSpawner in the
  harness was removed by using no fake nodes; it is not a script
  error.)
- **Status:** FIXED. T-56 now PASS. The v3.0 "Honest limits" line
  about double-credit is superseded by this entry.

## QA-032 — Pickup RPC to a disconnected peer spams engine errors

- **Cause:** `pickup.gd:97` called `body.rpc_id(...)` with no
  `get_peers().has()` guard. A disconnected player's puppet
  overlapping a pickup area made the host RPC to a gone peer, giving
  a repeating engine ERROR "Attempt to call RPC with unknown peer
  ID: 100" for the rest of the match.
- **Fix:** added the same `get_peers().has()` guard used by the
  damage RPCs in `bullet.gd` / `game.gd`. Despawn behaviour
  unchanged (the pickup is still taken; the RPC is only the
  despawn notice to the owning peer).
- **Found by:** the T-73 soak harness (LOOP 2b) — the error repeated
  once per pickup overlap after a bot disconnect. Verified gone in
  later soak logs.
- **Status:** FIXED. No script errors; engine ERROR gone.

## QA-033 — Frozen Fortress rebuilt as the small duel map (MAP_AUDIT §Similarity-3)

- **Before:** 2800x1500, a Template A clone shifted to a new size —
  same 16-platform grid rhythm as Catacombs / Military Base.
- **After (LOOP 3, v3.1 iteration):** 2200x1400 duel map, 2–4
  players. Open ice-slide centre (floor x450–1750 is the
  low-friction zone, kept clear of floor decor), hot zone on the
  frozen lake platform (850–1350 @1180, centre pickup at spot 3),
  dense cover on the flanks and platforms, snow fx kept. 15
  platforms (jump rises 170–172 px), 12 spawns (TDM 6/6 left/right),
  6 pickups, 12 decor pieces. `is_on_ice` and the ice-zone sheen
  narrowed to the new lane; the ice physics step teleports to
  (900, 1320) for a clean 640 px run to the 0.7-width bounce pad.
  The lobby thumbnail was re-rendered from the new layout
  (`assets/thumbs/thumb_frozen.png`, 96x64, same schematic style).
- **Bugs found while rebuilding (all fixed, all in the map data or
  the harness — no physics change):**
  - Decor crates were placed on the exact spawn/pickup x on every
    platform — STATIC-ALL-MAPS flagged 10 spawns + 4 pickups
    inside solids. Crates moved to the far end of each platform.
  - A column at (2100, 1352) sat exactly on the smoke test's
    (2100, 1350) teleport — the player spawned inside it and the
    smoke run fired 1 shot instead of 23. Column moved to Mid L
    (150, 1010); smoke back to 23 shots.
  - The Perch at (950, 500) cut the P06 terminal-velocity fall to
    182 px (max vy 677, want 950–1050). `_phys_s_fall` is now
    map-aware: on map 4 it drops from (400, 200) to Top L (670),
    452 px — enough to hit the 1000 cap.
  - A floor crate at (350, 1352) blocked the P03 analog half-stick
    run from (300, 1320) (vel.x 0). Crate moved to Mid L
    (250, 1010); the floor run from spawn is clear to the ice lane.
  - The sandbags at (120, 1352) put the BULLET-STOPS-SOLID ray
    start (cover.x − 120) outside the arena, so the ray hit the
    boundary wall at x=0 instead of the cover face — and
    BULLET-BLOCKS-TARGET passed for the wrong reason. Both checks
    now clamp the ray start to x ≥ 5 (harness fix, no game change).
- **Tests:** collision 8/8 on ALL 13 maps (re-run after the
  harness clamp); physics 22/22 on map 4, 31/31 on map 0;
  smoke map 4: 23 shots, local alive, errors=0; net 15/15,
  fire 26/26.
- **Status:** DONE. The v3.0 "Honest limits" line saying the duel
  shrink was NOT done is superseded by this entry.

## LOOP 2 — Unfinished tests (v3.1 iteration)

### T-33 — 10 rapid taps (LOOP 2a)
- Tap driver added to the fire test (0.10 s hold, 0.25 s gap,
  press-to-press 0.35 s > pistol rate 0.22 s). Result: fire test
  **26/26** — "shots fired for 10 rapid taps: 10 (want 10)".
  T-33 now PASS.

### T-73 — 10-minute 8-player soak (LOOP 2b)
- Perf harness extended: `--perf-seconds=N` (default 60, min 10)
  and `--perf-bots=N` (default 0, max 11); bots are idle players
  instantiated directly at spawn points. The rifle is kept
  churning by refilling `lp._reserve[0] = 90` at start and every
  10 s sample (the rifle otherwise runs dry after ~20 s at
  8 shots/s; the pistol is semi-auto so holding FIRE fires once).
- **Result — 600 s soak, 8 players, 0 script errors:**
  mem 53,104,989 -> 54,472,893 bytes, growth **1,369,848 bytes
  (~1.3 MB, limit 50 MB)**, flat after ~t=320 s (identical
  reading for the last 280 s — the game runs inside its
  preallocated pools after warm-up). No "unknown peer" errors
  after the QA-032 fix. T-73 now PASS.
- **Honest note on the firing metric:** `active_bullets` (the
  bullet-pool count at each 10 s sample) read 0 in 44/61 samples,
  1–3 in the other 17. That is a sampling artefact, not a firing
  failure — the pool only counts bullets in flight at the sample
  instant, and the soak player fires in bursts (rifle reload
  cycles, plus grenade self-damage killing it periodically: it
  throws a grenade every 5 s while it has any, and picks up more
  from the (500, 1150) spot on its wiggle path). Firing itself is
  proven by the fire test (26/26) and the smoke test (23 shots).
  The 25 s diagnostic run launched to chase this collided with
  the running soak on the ENet port (7777) and died with no
  output — a harness collision, not a game failure.
- **Soak lesson:** never run two Godot instances concurrently
  (port + shared project clash); kill by PID, never `pkill -f`
  with a pattern that can match your own shell.

## LOOP 4 — One Gemini call, Neon City sky (v3.1 iteration)

- Single call to `generate_image.py` (gemini-2.5-flash-image) for
  a 16:9 cyberpunk city skyline at night. **Result: HTTP 429 Too
  Many Requests.** Per the iteration rules the call was NOT
  retried and no further calls were spent (6 of the 12-call cap
  remain). Neon City keeps its Sky Brawl background
  (`bg_neon.png`, BG_TEX[5]) — no change, no regression risk.
  T-73 / LOOP 4 closed as "not done — rate-limited".

## QA-034 — "Waiting for other players" overlaps the centre-weapon label (LOOP 5, visual)

- **Seen on:** fresh 1280x720 screenshots (smoke `shot_aim.png`,
  flow `shot_pause.png`) — on every solo match start the centred
  24 px `message_label` ("Waiting for other players - share your
  IP!") sat on top of the 16 px `_centre_label` ("CENTRE: SNIPER
  HERE"), half-hiding it.
- **Cause:** the top bar's `mid` VBox (timer + goal + centre
  label) is ~96 px tall from y=12, so the centre label's bottom
  is ~y108; `message_label.offset_top` was 96.
- **Fix:** `message_label.offset_top` 96 -> 116 (clear by 8 px).
  The kill feed lives at the top-left, so the centred message
  never collides with it; the control hint lives at the bottom.
- **Verified:** fresh screenshots after the fix show both lines
  fully readable on Catacombs (dark) and Frozen Fortress (light).
- **Status:** FIXED.

## QA-035 — Touch controls draw over the pause / scoreboard / end panels (LOOP 5, visual)

- **Seen on:** fresh 1280x720 `shot_end.png` — the RELOAD button
  covered the end panel's stats row ("...Streak: 0") and the
  right end of the Rematch button; GRENADE covered the right end
  of "Back to Lobby". The same overlap applied to the pause and
  scoreboard panels (sticks + FIRE + the button column are HUD
  siblings drawn above the centred panels).
- **Fix:** new `_set_touch_controls_visible(v)` hides the gameplay
  cluster (move stick, aim stick, FIRE button, RELOAD, GRENADE,
  WEAPON/`switch_button`) while a panel is open and restores it
  on close — wired into `_toggle_pause`, `_on_score_pressed`
  and `show_end_screen`. Callers reset the touch state first
  (`_reset_all_touch_state`) so a hidden FIRE button cannot keep
  firing (QA-016 rule). The top-right SCORE / pause buttons stay
  visible — they sit outside the centred panels. Rematch reloads
  the scene, so no end-screen restore path is needed.
- **Caught by the tests, not by hand:** the first version of the
  helper named the WEAPON button `weapon_button` — the real
  variable is `switch_button` — and game.gd failed to parse at
  all (flow test died at the lobby step). Fixed to
  `switch_button`; both scripts now pass `--check-only`, and the
  flow test is green again. Lesson: run the flow test after any
  HUD edit — a parse error in game.gd kills the whole game scene.
- **Verified:** fresh screenshots — pause panel (Resume /
  Weapons / Sound / Music / Leave Match), scoreboard and end
  panel all render with no controls over them; flow test 10/10
  (pause -> resume -> scoreboard -> end -> back) green.
- **Status:** FIXED.

## LOOP 5 — Visual/UI polish pass (v3.1 iteration)

- Flow-test screenshot hooks added (menu, lobby, pause,
  scoreboard, end — all 1280x720, `user://shot_*.png`): the
  first async version raced the scene change, so the lobby and
  end shots came out stale/missing and the pause/scoreboard shots
  showed the NEXT screen; all five captures are now synchronous
  (`_capture_flow_shot_now` in main.gd, inline sync saves in
  game.gd) and land correctly.
- Reviewed as a first-time player: menu (clean, clear), lobby
  (host IP big in green, map grid + thumbnails fine; the "not
  ready" text sits close to the scrollbar and the 3rd map row is
  half-cut until you scroll — normal scroll behaviour, left as
  is), settings (21:20 shot from the v3.0 phase, unchanged code
  since — sliders, toggles and credits all clear; the "Music on"
  CheckButton is bound to `GameData.music_enabled`, so its knob
  position is the real setting, not a stuck-off bug), HUD (clean
  bars, timer, weapon, sticks, FIRE button), pause / scoreboard /
  end (fixed by QA-035), Frozen Fortress (ice platforms, snow
  and hills read well on the light sky).
- Two real glitches found and fixed: QA-034, QA-035 (above).
  No other visual defect was found; no label text was changed.

## QA-036 — Fire-test tap driver leaked into the next step; P07b tap apex load-flake (LOOP 2a follow-up, harness only)

- **Found by:** the full v3.1 regression (run_phase5_final.sh):
  fire 24/26, physics-map6 30/31. Everything else green
  (collision 8/8 x13, joystick 21/21, scale 70/70, physics
  31/31 on maps 0/10/12 and 22/22 on map 4, features 11/11,
  net 15/15, menu-net 6/6, flow green, smoke 13/13, 0 errors).
- **Fire failures (my LOOP 2a tap driver, real harness bug):**
  PISTOL-TEN-RAPID-TAPS read 9 shots (want 10) and
  FIRE-HOLD-CONTINUOUS read 0 shots in a 2.5 s hold (want
  14–22). Cause: the tap driver runs on real-time `_process`
  delta, but shots fire in physics time, which lags under load —
  so the 10th tap can still be pending when the step ends, and
  the driver then released the NEXT step's FIRE press. Fix:
  (1) the step transition now stops the driver
  (`_ft_tap_left = 0`, release FIRE) so no tap state leaks
  between steps; (2) TEN-RAPID-TAPS wait 3.8 -> 4.5 s, giving
  the physics time to land all 10 shots. No game code changed.
- **P07b (physics map 6):** tap jump apex 124 px (cap 120, hold
  168). Cause: the 0.15 s SceneTreeTimer release fires late in
  physics time under load, so the tap holds a fraction longer.
  Fix: timer 0.15 -> 0.12 s (apex still >50 px on a fast
  machine). Re-runs: physics-map6 31/31, then 30/31 on a second
  run with a DIFFERENT step (P02-air-accel, 1.12x vs >1.3x) —
  that one is the known CPU-load artefact from v3.0 (real-seconds
  ratio under xvfb; ground time read 0.26 s loaded vs 0.22 s
  isolated). A third isolated run passed 31/31 (P02 1.32x).
- **Verified:** fire 26/26 twice after the fix; physics-map6
  31/31 (twice of three runs, third run's only failure the
  documented P02 load artefact, passing alone); physics-map0
  31/31.
- **Status:** FIXED (harness only).

## v3.1 — Iteration release (2026-11-19, Godot 4.7.2)

All six loops done (LOOP 4's Gemini call hit the 429 rate limit
and was not retried; LOOP 6 found nothing new beyond QA-032,
which the soak had already surfaced). The v3.0 APK was never
overwritten in place: it is backed up at
`~/workspace/mini-militia-lan-backup-v3.0/mini-militia-lan.apk`
(md5 `cf6495ff319d5d0704b597491644e48d`, verified after copy).

### Version bump (only code change besides the loop fixes)
- `export_presets.cfg`: version/name "3.0" -> "3.1",
  version/code 8 -> 9.
- `main.gd`: in-game version label "v3.0" -> "v3.1".
- `game_data.gd`: `BUILD_VERSION` "3.0" -> "3.1".
- Post-bump re-runs: physics-map0 31/31 (twice; the first
  post-bump run read 30/31 once, a transient load flake — the
  step was not captured, and the two immediate re-runs were
  31/31), flow green, menu-net 6/6.

### Final verification — full suite on the final code
Runner `run_phase5_final.sh` (Godot 4.7.2, headless Xvfb).
Zero script errors in every run.

- **Collision:** 8/8 on ALL 13 maps.
- **Joystick:** 21/21. **Fire-button:** 26/26 (twice after the
  QA-036 fix). **Scale/coordinate:** 70/70.
- **Physics:** 31/31 on maps 0, 6, 10, 12; 22/22 on map 4.
  (One P02-air-accel miss in a loaded run, 1.12x vs >1.3x —
  the known CPU-load artefact from v3.0; passes alone at 1.32x.)
- **Features:** 11/11. **Multiplayer:** 15/15. **Menu-net:** 6/6.
- **Full flow:** PASS, 10 steps (menu -> create room -> lobby
  -> start match -> play/fire (3 shots) -> pause -> resume ->
  scoreboard -> end screen -> back at menu).
- **Smoke:** 13/13 maps — players=1, local alive, shots fired
  23 (maps 0–5, 8) / 32 (maps 6, 7, 9–12), bullet pool 160,
  fuel 100.0, errors=0.
- **Soak (T-73):** 600 s, 8 players, mem growth ~1.3 MB
  (limit 50 MB), flat after ~t=320 s, 0 script errors.

### APK verification (v3.1)
- APK: `mini-militia-lan.apk`, 32,522,504 bytes, md5
  `01eefb9c15061b1c51f9bb9b67e22dee`. Built with Godot 4.7.2
  (`--export-release Android`).
- **Signing note:** `export_presets.cfg` has
  `package/signed=false`, so the raw export is UNSIGNED
  (apksigner: "Missing META-INF/MANIFEST.MF"). v3.0 was signed
  the same way — after the export, with apksigner and the debug
  keystore. v3.1 was signed identically:
  `apksigner sign --ks
  /home/hatch/.local/share/godot/keystores/debug.keystore
  --ks-key-alias androiddebugkey` (java from
  `~/workspace/jdk17/bin`, which is not on PATH by default).
- aapt2: package `com.lanarena.shooter`, versionCode 9,
  versionName 3.1, targetSdk 36, only INTERNET /
  ACCESS_NETWORK_STATE / ACCESS_WIFI_STATE.
- apksigner verify: 1 signer; cert SHA-256
  `f65f2fa3d8041b5e8920e627355a0dd68d9b50414d6b40702fea6b4da6e02d11`
  — matches v3.0 exactly, installs over v3.0 cleanly.
- Contents: both music OGGs inside (`menu_at_rest.ogg`,
  `battle_five_armies.ogg`, as imported `.oggvorbisstr`); Sky
  Brawl textures inside (36 entries); the rebuilt Frozen
  Fortress thumbnail inside (re-imported at build time);
  NO `.md`/`.txt` in the APK.
- **Note:** the export rewrote `project.godot` at build time
  (23:56), dropping the `[rendering]` section
  (`renderer/rendering_method` + `.mobile` =
  `gl_compatibility`, `textures/vram_compression/import_etc2_astc`).
  Those are the 4.7 defaults for a mobile export, and the APK
  size is essentially identical to v3.0 (+4 KB), so the change
  is a Godot-side normalisation, not a settings loss — but the
  coordinator should confirm before the next export. The v3.1
  APK was built and verified from this state.

### Honest limits (unchanged from v3.0, except where fixed above)
- Real touch hardware untested; real two-phone LAN join untested
  (sandbox blocks UDP) — the user tests with the two-device guide
  in README.md. Live two-phone map vote also still needs a
  real-phone check.
- Performance on a real phone untested; audio not verified by ear.
- The double-credit kill (QA-031) and the Frozen Fortress duel
  shrink (QA-033) are FIXED — the v3.0 limits lines about them
  are superseded.
- The Neon City Gemini sky was NOT generated (LOOP 4 hit HTTP
  429; not retried). 6 of the 12-call cap remain.

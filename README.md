# LAN Arena Shooter — v2.5

A Mini Militia-like 2D multiplayer shooting game for Android, played over
local Wi-Fi (LAN). No accounts, no online servers, no matchmaking, no ads.
2–12 players on the same Wi-Fi.

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

- Wait for the 8-second timeout: the game shows an error with
  **Back** and **Retry** — it never hangs forever. Tap **Retry**.
- Check the IP you typed: it must match the host's lobby exactly
  (four numbers with dots, e.g. 192.168.1.5). A wrong digit gives
  "Could not reach that host".
- If the host's Wi-Fi changed (it switched networks or the hotspot
  restarted), the host IP changes too — read the new IP from the
  host's lobby and try again.
- Restart the app on both phones and try again. The host creates the
  room first, then the joiner joins.

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
a ✓). Every map is 2400–3600 px wide, has 12 spawn points and 6 pickups,
multiple routes, high ground and hiding spots, and its own look:

1. **Catacombs** — underground tombs, dark stone, torches, blue-grey
   light. Five levels: upper entrance, main combat chamber, underground
   tunnels, lower chamber, and vertical shafts connecting them.
2. **Military Base** — destroyed installation: watchtower, metal bridge,
   central building, underground bunker, sandbags and barriers.
3. **Desert Outpost** — sand and rock: observation towers, a long aerial
   route, a central tent battlefield, and an underground bunker.
4. **Industrial Factory** — steel platforms, pipes, hanging walkways,
   a big factory floor, and a maintenance tunnel below.
5. **Frozen Fortress** — snow platforms, ice blocks, a watchtower and
   bridge, a frozen courtyard, and an ice cave with hidden passages.
6. **Jungle Ruins** — ancient ruins in the jungle: spawn terrace, high
   ruin route, central temple, cliff with a watchtower, waterfall
   terrace, and a cave network with a jetpack shaft. Built from the
   Jungle Ruins asset pack.
7. **Space Station** — metal floors, glass walkways, a control room,
   central command chamber, and maintenance tunnels / engine room.
8. **City Underground** — rooftops and bridges above, an urban street
   with vehicles as cover in the middle, and a metro station with
   railway tunnels below.
9. **Volcanic Cavern** — dark volcanic rock, narrow bridges, elevated
   platforms, and glowing lava pools below (they hurt — use the safe
   routes around them).
10. **Pirate Island Fortress** — fortress towers and bridges, a central
    courtyard with a shipwreck, and treasure chambers with tunnels below.

## Controls

- **Left stick** — move. Push a little to walk slowly, push fully to
  run at full speed. The character faces the direction you push and the
  run animation matches your speed. Release the stick to stop (no
  sliding) and the idle animation plays. **Push the stick up to jump;
  hold it up in the air to fly with the jetpack.** The jetpack uses fuel
  (blue bar); it refills when you stand on the ground. Push the stick
  down while falling to drop faster.
- **Right stick** — aim in any direction (full 360°). The weapon points
  where the stick points and the character faces the aim direction.
  The right stick only aims — it never fires.
- **FIRE button** (big red circle, bottom-right corner) — hold it to
  shoot continuously; tap it once for one shot with semi-auto weapons.
  Let go and the gun stops at once. It works at the same time as the
  move and aim sticks — one finger per control.
- **RELOAD button** — reload the current weapon. You also reload
  automatically when the magazine is empty. You cannot fire while
  reloading; the ammo count shows the reload progress.
- **GRENADE button** — throw a grenade in the direction you are aiming
  (or forward-up if you are not aiming).
- **WEAPON button** — switch between the weapons you have picked up.
- **II button** — pause menu (Resume, sound/music volume, Leave Match).
- **SCORE button** — show the scoreboard during a match.

In short: **Left stick: move • Push up: jump / fly • Right stick: aim •
FIRE button: hold to shoot.**

**Solid cover:** crates, barrels, sandbags, rocks, columns, pillars,
statues and watchtowers are solid — bullets stop at them, you cannot
walk through them, and grenades bounce off them. Use them as cover.
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
WEAPON to switch between the weapons you own.

## HUD

- Green bar (top left): health — the number next to it is your exact
  HP. Blue bar under it: jetpack fuel, with its number next to it.
- Top right: kills, deaths, players in the game, current weapon and
  ammo (e.g. "Rifle 24/30"), grenades left.
- Top centre: match timer and the kill limit ("First to 10 kills").
- If you are eliminated, you respawn after 3 seconds, with 2 seconds of
  spawn protection (your soldier blinks while protected). In Survival
  you stay out until the round ends; in Last Man Standing you are out
  for the whole match.

## Permissions

The game only asks for these three, all needed for LAN play:

- `INTERNET`
- `ACCESS_NETWORK_STATE`
- `ACCESS_WIFI_STATE`

No storage, notifications, location, microphone, or camera access.

## Notes

- This is a debug build, signed with a debug key.
- Version 2.5 (version code 7), package `com.lanarena.shooter`. APK
  `mini-militia-lan.apk`: 25,492,479 bytes, md5
  `90fe7e3fad44dd249ba8afc9bccaf175`, signed with the same debug key as
  v2.4 (certificate SHA-256 matches v2.4, so it installs over v2.4).
- The game was verified on this build machine with a rendered smoke test
  (19 phases), a scripted QA harness driving the real game, a joystick
  acceptance test (21/21), a scale test (70/70 across five screen
  sizes), a collision test (8/8 on Catacombs and 8/8 on Jungle Ruins,
  plus a static check of all 10 maps), a fire-button test (25/25),
  a multiplayer test (11/11), a menu network test (6/6), and a full-flow
  check (10/10: menu → create room → lobby → start match → play →
  pause → scoreboard → end screen → back to menu) — all with no script
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
- Built with Godot 4.3.

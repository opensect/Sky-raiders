# Sky Raiders

A Mini Militia-style 2D multiplayer shooter for Android, played over local
Wi-Fi (LAN). No accounts, no online servers, no matchmaking, no ads.
2–12 players on the same Wi-Fi.

- **6 maps:** Ironfall, Jungle Ruins, Neon City, Volcanic Cavern, Pirate
  Island, and Skyfall (a vertical tower climb).
- **6 weapons:** rifle, SMG, shotgun, sniper, rocket launcher, pistol —
  plus grenades.
- **5 modes:** Free-for-All, Team Deathmatch, Survival, Last Man Standing,
  and Capture the Flag (Skyfall only — vertical CTF, flag at the summit).
- **7 power-ups:** Shield, Speed, Health, Jetpack Boost, Wind Blast,
  Thunder Strike, Invisibility. Pick one up, tap its slot to use it.
- **Jetpack** on every player, host-authoritative combat, kill feed,
  scoreboard, MVP screen, map vote, profiles and room codes (FRAG-XXXX).

Version: **3.11** (versionCode 19). Package: `com.lanarena.shooter`.
Full version history is in [CHANGELOG.md](CHANGELOG.md); the bug/fix log
is in [BUGS.md](BUGS.md).

## Setup — open and run it

1. Install **Godot 4.7.2** (the project targets Godot 4.7).
   Download it from https://godotengine.org/download — the standard
   (non-.NET) build is enough.
2. Clone this repo and open `project.godot` in Godot.
   On first open Godot imports the art and fonts — that takes a minute.
3. Press **F5** (or the Play button) to run the game on your computer.
   The menu, lobby and a local match all work on desktop for testing.
   Real multiplayer needs two Android phones — see "Play on LAN".

No other setup is needed to run it. No accounts, no keys, no servers.

## Play on LAN (two phones)

1. Put both phones on the **same Wi-Fi** (a phone hotspot works too).
2. On phone 1: **Local Multiplayer → Create Room** — pick a map, mode
   and player limit, then **Create**. The lobby shows the room code
   (FRAG-XXXX) and the host IP.
3. On phone 2: **Local Multiplayer → Join Room** — tap the room in the
   list, or type the room code / host IP.
4. Both tap **I'm Ready**, the host taps **Start**.

## Controls

- **Left stick** — move. Push up to jump / fly with the jetpack.
- **Right stick** — aim and fire while held, release to stop firing.
  (No fire button — Mini Militia style.)
- **RELOAD / GRENADE / WEAPON** — plain buttons on the right side.
- **SCOPE** — sniper 2.0x / rifle 1.5x zoom.

## Build the Android APK

1. In Godot: **Project → Install Android Build Template**, then
   **Editor → Manage Export Templates** and install the 4.7.2 templates.
   (Needs a JDK 17 and the Android SDK — Godot's docs cover the setup:
   https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html)
2. **Project → Export → Android → Export Project.** The preset in
   `export_presets.cfg` exports **unsigned** (`package/signed=false`).
3. Sign the APK afterwards with `apksigner` and the debug keystore —
   the keystore is **not** in this repo. The shipped v3.11 APK was
   signed with the project's debug key (cert SHA-256
   `f65f2fa3d8041b5e8920e627355a0dd68d9b50414d6b40702fea6b4da6e02d11`);
   use the same keystore if you want new builds to install over the
   old ones. A release build for Google Play needs a release keystore
   — see [PLAY_SUBMISSION_CHECKLIST.md](PLAY_SUBMISSION_CHECKLIST.md).

The app needs only 3 permissions (all install-time, no runtime prompts):
`INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`. Target SDK 36,
min SDK 24, arm64-v8a only.

## Project layout

| Path | What it is |
|---|---|
| `main.gd` / `main.tscn` | Main menu, settings, profile |
| `game.gd` / `game.tscn` | The match: players, maps, HUD, Skyfall |
| `player.gd` | Player movement, jetpack, combat |
| `weapons.gd` | Weapon table (damage, rate, mag, spread) |
| `bullet.gd`, `grenade.gd` | Projectiles |
| `audio.gd` | Sound effects (synthesized in code) |
| `discovery.gd` | LAN room discovery (UDP 7778) |
| `game_data.gd` | Shared state, version (`BUILD_VERSION`) |
| `assets/` | Art, tiles, fonts, music |
| `addons/gohud/` | gohud 1.3.0 UI library (MIT) |
| `addons/reeboo_fx2d/` | Stylized 2D VFX Lite (MIT) |
| `export_presets.cfg` | Android export preset |

The network code is ENet on port 7777, discovery on 7778. Combat is
host-authoritative; movement syncs by RPC snapshots at 30/s (see
`PHYSICS_SPEC.md` and `SKYFALL.md`).

## Tests

The project has an in-engine test suite (run from the command line,
e.g. `godot --path . -- --auto-host --joystick-test`). Full suite:
collision, joystick, fire, scale, physics (34 checks per map), features,
Skyfall features, multiplayer sim, menu-net, flow, smoke — 0 script
errors. Real two-phone LAN play is the only true test of sync; the
sandbox blocks UDP, so the sim is a substitute, not proof.

## License

Code in this repo is the author's own. Third-party pieces keep their own
licenses — see the files: gohud 1.3.0 (MIT), Stylized 2D VFX Lite and
Sprite Juice Kit Lite (MIT), Orbitron + Rajdhani fonts (SIL OFL 1.1),
menu/battle music by Kevin MacLeod (CC BY 4.0 — attribution is in-game).

# RESEARCH v3 — LAN Arena Shooter (Godot 4.3 → v3.0 planning)

Sources: gamedesign.gg (PvP map design), Soldat2 mapping wiki, Mini Militia map guides,
godotengine.org 4.7 release notes, https://thruthesky.github.io/gohud/ (+ install page).
Current game state checked against README.md + BUGS.md (v2.4).

## (a) How to design a good 2D side-view multiplayer shooter map

References: Mini Militia (Outpost, Catacombs, Hightower), Soldat/Soldat2, Stickman-style arena shooters.

**Flow — the map is the rules, expressed as geometry**
- Build a loop, not a line: a figure-eight / 3-lane layout (centre lane = fast, risky;
  two side lanes = slower, flanking). A player should always rotate without backtracking.
- **Rule: every area reachable by at least 2 routes** (jump/jetpack counts only if it is
  obvious — a visible platform chain, not a hidden pixel jump).
- **Rule: no dead ends.** Every corridor/tunnel has 2 exits, or is short enough to see
  the whole thing from the entrance. (Jungle Ruins caves already do this.)
- One contested centre (the "hot zone") where the best pickup sits; the rest of the map
  feeds into it. Mini Militia's Outpost works because mid is open but flankable.

**Cover & sightlines — tune sightline length against time-to-kill**
- Long lanes are sniper lanes: keep them **few (1–2 per map), avoidable, and never the
  only route** between two areas. Most fights should be medium range (rifle/SMG range).
- **Rule: cover every 300–400 px on any lane longer than ~800 px** — a crate, pillar or
  platform edge to duck behind. A lane with no cover is a death corridor, not a feature.
- Mix cover heights: full cover (blocks sight + bullets) for hiding, half cover (blocks
  body, allows firing over) for duels. All-full-cover = peek stalemate; all-half = attrition.
- **Rule: no position is exposed to 3+ firing angles at once.** A spot shot at from
  three directions is a death trap, not a power position.
- High ground must be strong but not safe: a sniper perch needs 2+ approaches and no
  full cover on top, or one player camps it all match.**Spawns — spawn-killing is the #1 fun-killer**
- **Rule: no spawn within line of sight of another spawn, and no spawn facing a long lane.**
- **Rule: every spawn has cover within ~150 px and 2 escape routes.**
- Existing 2 s spawn protection (QA-002) is the minimum; also pick the respawn point
  **farthest from live enemies** (Soldat2 maps are criticised exactly for random spawns
  landing players on top of enemies). 12 spawns for 12 players is the floor, not the target.
- Team modes: spawns grouped per team, never interleaved.

**Verticality — use the jetpack, don't fight it**
- 3–4 levels (floor / mid platforms / high route / roof or tunnel below). Current maps
  already do 5 levels in places — fine, but each level must connect to the next by
  **jump (≤ ~180 px rise) or an obvious jetpack shaft**, never a single hidden route.
- High routes should be the *fast* way across the map but exposed; low routes slower
  but covered. That trade-off is what makes rotation a decision.

**Pickups — risk must match reward**
- **Rule: the strongest weapon (sniper/rocket) sits exposed in the contested centre,
  never next to a spawn and never in a campable corner.** If a player can grab it and
  hold the same spot, the placement is wrong.
- Spread the other 5 pickups across the map's zones so losing players always have a
  weapon nearby; respawn pickups on a visible timer (~15–20 s).
- Health/grenade pickups (if added) go on side routes to reward flanking.**Map size for 2–8 players**
- Current maps (2400–3600 px wide, 1400–1600 tall) are right for 4–8 players. For
  2-player duels they feel empty — a **small map (~2000 px) for 2–4 players** is worth
  adding; don't stretch one size to all counts.
- Fun vs frustrating, in one line: fun = you always know where you died from and what
  you could have done differently; frustrating = you died from somewhere you couldn't
  see, couldn't reach, or couldn't escape.## (b) Common shooter features — what exists vs what is missing

Already in v2.4: main menu, rooms/lobby (create/join/quick match, passwords, kick,
ready), 4 modes (FFA/TDM/Survival/LMS), 6 weapons + grenades, reload, FIRE button,
dual joysticks, pause menu (resume, volume, leave), in-match + end scoreboard,
customisation (name, colour, helmet), settings (sound/music volume), procedural
sounds + music, HUD (health/fuel/ammo/timer/kill limit), spawn protection, rematch.

| Missing feature | Verdict | Note |
|---|---|---|
| Real settings screen: joystick sensitivity, FIRE button size/position, show FPS, invert aim | FEASIBLE | All local `GameData` values; FPS via `Engine.get_frames_per_second()`; ~2–3 h |
| Kill feed ("A killed B — Rifle") | FEASIBLE | Host already owns kills; one RPC + a 4-line HUD list; ~1 h |
| End-of-match stats: kills/deaths/K-D, accuracy (shots fired vs hits), best streak | FEASIBLE | Host tracks counters already for scoreboard; add shots/hits counters; ~2 h |
| Better scoreboard: sort by kills, K-D column, team totals in TDM, highlight self | FEASIBLE | Re-sort existing rows; ~1 h |
| Weapon info panel (damage/rate/mag per weapon, in lobby or pause) | FEASIBLE | Data already in `weapons.gd`; read-only display; ~1 h |
| Match countdown ("3-2-1-FIGHT") + "first to X" banner at start | FEASIBLE | Timer + label; prevents spawn-rush at 0:00; ~1 h |
| Hitmarker + damage numbers on hit | FEASIBLE | Client-side only, host sends hit confirm; ~2 h |
| MVP / match summary screen (most kills, best accuracy) | FEASIBLE | Reuses end-of-match stats; ~1 h |
| Map vote in lobby (players pick from 2–3 maps) | FEASIBLE | Lobby RPC + vote tally; ~2–3 h |
| Health/grenade pickups on maps | FEASIBLE | Same pickup system as weapons; ~2 h |
| Spectator mode after death (Survival/LMS) | FEASIBLE (stretch) | Camera follows a living player; ~4 h, needs care |
| Voice chat, text chat | NOT FEASIBLE | Needs audio capture/codec + LAN relay work; out of scope |
| Accounts, ranks, cloud saves, leaderboards | NOT FEASIBLE | Needs internet/server — explicitly out of scope |
| Online matchmaking / cross-Wi-Fi play | NOT FEASIBLE | Needs a server — explicitly out of scope |
| Replays / killcam | NOT FEASIBLE | Needs full match recording + playback; heavy |
| Bots / practice mode | NOT FEASIBLE | User already said skip bots (2026-11-18) |

## (c) Godot 4.7 + gohud evaluation

**Godot 4.7 (stable 18 Jun 2026; latest 4.7.2, 18 Aug 2026) — what matters for this game**
- **Built-in `VirtualJoystick` node** (Fixed / Dynamic / Following modes) — the one
  4.7 feature that directly touches this game; could replace hand-rolled `joystick.gd`,
  but the current sticks are battle-tested (QA-016/023) — swap only if the new node
  passes the same 21-check acceptance test.
- **`Control` offset transforms** — move/scale UI without fighting container layout;
  helps button press animations and HUD juice.
- Searchable `PopupMenu`, `Tween.tween_await()`, new Asset Store, stable Android
  build/export tooling (GABE). 3D/HDR/AreaLight3D are irrelevant to this 2D game.
- **Upgrade risk:** 4.3 → 4.7 crosses 4.4/4.5/4.6 — read the official 4.7 migration
  guide first; expect small API breaks. Mitigation: upgrade on a branch, re-run the
  full test suite (joystick 21, fire 25, smoke 19, flow 19) before shipping.**gohud (free, MIT, 14 presets incl. Material 3, mobile-first)**
- **Requires Godot 4.7+** — officially supported floor, recorded in `GoUi.MIN_ENGINE`;
  uses 4.5 APIs (DPITexture, FoldableContainer, accessibility props) and **fails while
  parsing on anything older**. So: engine upgrade first, gohud second.
- What it gives: one-line theme switch for all menus/HUD/lobby (Material 3 is the
  best fit for settings/menus), safe-area + notch handling, 48 dp touch targets,
  dialogs/sheets/toasts, HUD anchors, a skinned joystick. Install = drop
  `res://addons/gohud/` in; works without enabling the plugin.
- What it costs: **a rewrite of the existing UI code** (`main.gd`/`game.gd` build all
  UI in code) to gohud's widget API. The current UI was rebuilt in v2.3 and works —
  theming is the only real gain. APK size: small (scripts + theme data, no big assets),
  but ship without the `examples/` folder. **Biggest risk:** gohud's joystick/touch
  handling would replace the hand-fixed touch routing (QA-016 stuck-fire, QA-023
  fire-on-any-tap, QA-019 off-screen lobby). Those bugs took three versions to kill;
  re-introducing a new touch layer is the most dangerous change in this whole plan.

**Verdict: UPGRADE the engine to 4.7.2, KEEP the built-in Godot UI.**
- Do the 4.7 upgrade for `VirtualJoystick`, offset transforms and GABE — real gains,
  low risk, verified by the existing test suite.
- Do NOT adopt gohud for v3.0. The menus/HUD already look modern (v2.3 rework) and
  work; a full UI rewrite buys a theme switch and risks the touch bugs. Revisit gohud
  later only for *new* screens (e.g. the real settings screen) as a contained trial —
  never for the in-game joysticks, FIRE button or HUD.

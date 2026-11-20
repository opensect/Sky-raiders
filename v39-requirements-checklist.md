# v3.9 Requirements Checklist (2026-11-20) — ALL TICKED

Every v3.9 requirement verified with proof before compiling.
Checked 2026-11-20 ~14:30 IST by the v3.9 coordinator.

## 1. Skyfall as the 6th map (8 levels, vertical, 3600x7200)
- [x] Map 5 "Skyfall" in MAP_NAMES/MAP_CARD_INFO, 6 maps total, all 5 old maps kept
  - Proof: game_data.gd MAP_NAMES (6 entries), FT-SF-MAP (size 3600x7200, 70 platforms, 12 spawns)
- [x] 8 levels (Twin Base Camp, Broken Cliffs, Underground Tunnels, Hanging Bridge,
      Sniper Territory, Mechanical Ascent, The Last Stand, Flag Summit)
  - Proof: FT-SF-MAP + --skyfall-shots 8 level captures (shot_sf_L1..L8.png, both resolutions)
- [x] Vertical-follow + horizontal-tracking camera, team spawns at the bottom
      on opposite sides, team checkpoints, falling drops to a lower platform
      (never a dead end — recovery routes exist)
  - Proof: collision map 5 8/8 + physics map 5 34/34 + smoke map 5 clean (BFS 70/70 reachable)

## 2. CTF back — ONLY for Skyfall
- [x] Mode 4 "Capture the Flag" available only on Skyfall; other 5 maps keep
      exactly FFA/TDM/Survival/LMS
  - Proof: main.gd _ctf_available() + FT-SF-MODE; lobby hides mode 4 elsewhere; start_match falls back 4->0
- [x] Flag at the summit, 1.5 s hold to grab, carrier 15% slower + no jetpack
      boost, flag drops where the carrier dies, returns after 15 s unretrieved,
      score by bringing it to your own base extraction zone
  - Proof: FT-SF-GRAB (carrier=1), FT-SF-CAPTURE (RED 3 pts), player.gd carrier rule (x0.85, no jetpack)
  - BUG FOUND + FIXED: the v3.6 grab timer was keyed by peer only, so the other flag's
    distance check erased the hold every frame — a flag could NEVER be grabbed. Key is now (peer, flag team).

## 3. Seven power-ups, 3 slots per player, rarer than weapons
- [x] 7 power-ups (health +35%, shield 6 s, speed 7 s, ammo refill, grenade +2,
      jetpack boost fuel, radar 5 s) with pack art + 64 px icons
  - Proof: pickup.gd (7 textures), FT-SF-MAP (7 skyfall_pickups)
- [x] Every player has exactly 3 slots, up to 3 different charges, one active
      temporary boost at a time; health/ammo/grenade never take a slot
  - Proof: FT-SF-POWERUP-SLOTS (2 held), FT-SF-POWERUP-ACTIVE (3 held); HUD shows the 3 pack slot images
- [x] Power-ups appear LESS often than weapons (longer cooldown, fewer points)
  - Proof: FT-SF-RARITY (300 s sim: weapons 93, power-ups 41); 35 s vs 14 s, max 2 vs 3, 1 at start vs 3

## 4. Partial scoring — relay stations levels 4 and 7
- [x] Banking the flag at a relay scores +1 pt; full capture +3 pts; first to 9
  - Proof: FT-SF-RELAY-GRAB (carrier=1), FT-SF-RELAY-BANK (RED 4 pts = 3 capture + 1 relay, flag home)

## 5. Respawn checkpoints levels 3, 5, 7
- [x] Holding level 3/5/7 respawns there; losing a level moves respawn back down
  - Proof: FT-SF-CHECKPOINT-UP (3), FT-SF-CHECKPOINT-DOWN (0), FT-SF-DIE-L7 (respawn at L7, y 1681)
  - Fixes: +40 px threshold (spots sit 34 px above the platform, standing centre 31 px above it);
    5 s grace freeze when a team has no living members (a single death must not drop the respawn to the bottom)

## 6. Matches start without full teams
- [x] Host can start with whoever is in the room; minimum 2 players, one per
      team in team modes; no full-team requirement anywhere
  - Proof: main.gd _start_minimum_reason() + MIN-START-SOLO / MIN-START-CASES 10/10 / MIN-START-3V2 (all pass)

## 7. Comeback help for the trailing team
- [x] Team behind by >= 2 pts gets summit elevator + bonus power-up near their
      base; shown in the HUD for both teams; leading team keeps its checkpoint
  - Proof: FT-SF-COMEBACK (trailing=BLUE, elevator timer 5.0 s, label visible, bonus pickup present)

## 8. Random mid-match events
- [x] Random type (supply drop / collapsing level / route shift) at random
      times (45-90 s), announced to both teams; independent of the 90 s storm
  - Proof: FT-SF-EVENT (event fired, timer reset to 45-90 s), FT-SF-COMBO-EVENT-STORM (event + storm together)

## 9. Movement options — grapple / wall-jump / jetpack lines
- [x] Grapple points (6) to pull up, wall-jumps while climbing, marked jetpack
      lines through wind zones (wind shield + half fuel); visible in the map
  - Proof: FT-SF-MAP (grapple 6, lines 2); --movement-test 16/16 twice, bit-for-bit identical:
    grapple pull ~496 px/s, no fuel; wall-jump vel (-306.9, -450.0); on a line fuel drain 9.0 in 0.4 s
    (half of 18.0 off-line), vel.x -4 (shielded) vs -84 off-line; carrier pull 425, stored boost on drop

## 10. Vertical HUD — height bar + pings
- [x] Height bar with live teammate/enemy positions, team pings (world marker
      + bar dot + feed line, 3 s cooldown), route legend
  - Proof: FT-SF-HEIGHTBAR (dot y 128.3 vs want 127.0), FT-SF-PING (pings=1, bar dot visible)
  - Fix: bar re-anchored below the kill feed (feed chips drew over it at 720p); 360 px tall now

## 11. Colour-coded routes
- [x] WEST cyan / CENTRE gold / EAST green — same colours on platforms, height
      bar, and HUD legend
  - Proof: FT-SF-ROUTES (0/1/2, 3 legend rows); visible in the L1/L4/L7 screenshots (gold centre strip, green east strip)

## 12. Statistics and pause redesigns
- [x] Scoreboard + end-of-match stats as aligned columns (rank/name/K/D/K-D/ACC),
      wider panels, readable at 1280x720 and 2400x1080; pause menu with match
      info line, section labels, slider % values, 56 px buttons
  - Proof: --game-shots screenshots (shot_pause.png, shot_scoreboard.png, shot_end.png) at both resolutions — verified clean
  - Fixes: SCOPE/PING buttons hid over the panels (added to _set_touch_controls_visible + gated in
    _update_scope_button); MVP line shortened (streak is a table column); clip_text on a centred label
    collapses it to near-zero width in Godot 4 — never use it there

## 13. Dynamic scenery
- [x] Drifting clouds, flowing waterfall, flying helicopter, rotating gears,
      smoke/steam, distant lightning flashes during storms — scenery only,
      no gameplay effect, no phone perf cost
  - Proof: FT-SF-SCENERY (heli moved, clouds 5, gears 2, puffs 4, streaks 5, flash present) in both features runs;
    visible in the --skyfall-shots screenshots

## 14. Double-test pass
- [x] Every Skyfall feature tested TWICE with the same result; full suite green
      twice in a row
  - Proof: features-skyfall 38/38 run 1 + 38/38 run 2; full suite run 1 + run 2 (see BUGS.md QA-114);
    movement 16/16 run 1 + 16/16 run 2 (identical numbers); physics map 5 34/34 twice

## 15. No coincidence glitches
- [x] Random event + Summit Storm; carrier + grapple/wall-jump/jetpack line/wind;
      checkpoint advance + comeback; banking + random event; power-up pickup +
      active boost; falling + trap door + collapsing level; dying on L7 while
      holding L7
  - Proof: FT-SF-COMBO-EVENT-STORM, FT-SF-COMBO-TRAP, FT-SF-DIE-L7, FT-SF-POWERUP-ACTIVE — all pass

## 16. No opposite-feature glitches
- [x] Carrier slow/no-jetpack wins over speed/jetpack boost; wind vs jetpack
      line (line wins); comeback help vs leading team's checkpoint (both hold);
      shield vs storm (no damage, shield intact); collapsing platform under a
      grappling player; trap door under the carrier; route-shift mid-grapple;
      trailing-team power-up spawn on a level the other team holds (spawns at
      the trailing team's base only)
  - Proof: FT-SF-OPP-CARRIER-CTRL, FT-SF-OPP-CARRIER, FT-SF-OPP-SHIELD-STORM — all pass;
    movement worker measured the carrier/line cases

## 17. 5v5 = 10 players
- [x] 10 players work in a Skyfall room (5v5); fall back to 4v4 only if it breaks
  - Proof: FT-SF-5V5 (10 players, 5 RED / 5 BLUE) passes; net test 15/15 green — 5v5 SHIPS, no fallback needed

## 18. Export (only after all above are ticked)
- [x] versionName 3.9, versionCode 17, package com.lanarena.shooter, same debug
      key (SHA-256 f65f2fa3...), 3 permissions, targetSdk 36, minSdk 24
- [x] APK verified (ls/md5/file, apksigner, zipalign), v3.8 backed up, git commit
- See the completion report for the APK path, size, md5 and test results.

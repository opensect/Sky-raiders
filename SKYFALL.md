# SKYFALL – The Last Ascent — map concept (user-shared, 2026-11-20)

Vertical battlefield: both teams start at the bottom on opposite sides of a
massive abandoned military tower; the flag is at the summit; the whole map is
a dangerous climbing battlefield. Build as ONE map, moving from bottom to top
to capture the flag. Use the assets from the current zip file (the Ironfall
asset pack — already sliced at assets/ironfall_sliced/).

## Match design
- Mode: Vertical Capture the Flag; Teams Red vs Blue; Players 5 vs 5
- Objective: capture the enemy summit flag
- Map structure: 8 climbing levels; Power-up types 7; Power-ups per team 3 active slots
- Match duration 5–8 minutes; Respawning at team-specific lower checkpoints
- Win: reach the summit, grab the enemy flag, bring it to your own team's
  extraction zone at the bottom. Simply touching the flag does not win.

## Eight vertical levels
1. Twin Base Camp — Red and Blue spawn at opposite ends; protective walls,
   small platforms, weapon pickups, two ways to start climbing.
2. Broken Cliffs — narrow platforms, falling rocks, ladders, exposed climbing
   routes; players can knock opponents off platforms.
3. Underground Tunnels — two hidden tunnels connect opposite sides; sneak
   past enemy positions, surprise attacks.
4. Hanging Bridge — narrow moving bridge with gaps; falling drops the player
   to a lower platform (not instant death).
5. Sniper Territory — two elevated sniper platforms with partial cover.
6. Mechanical Ascent — moving elevators, rotating platforms, timed gates.
7. The Last Stand — wide combat arena, multiple entrances, limited cover,
   valuable power-ups; both teams fight for summit control.
8. Flag Summit — enemy flag inside a guarded summit structure; several entry
   points from different directions.

## Seven power-up types (distributed across heights)
1. Health Pack — restores 35% health.
2. Energy Shield — absorbs incoming damage for 6 seconds.
3. Speed Boost — increases movement speed for 7 seconds.
4. Ammo Crate — refills ammunition.
5. Grenade Pack — grants two additional grenades.
6. Jetpack Boost — temporary extra flight fuel.
7. Enemy Radar — reveals enemy positions for 5 seconds.
Rules: max 3 different power-up charges per player; only one active temporary
boost at a time; health/ammo collected separately; power-ups respawn after a
cooldown; collecting an owned power-up refreshes its charge only when appropriate.

## Multiplayer mechanics
Collapsing platforms (break after repeated use), moving elevators, hidden
tunnels, rope bridges, falling rocks, wind zones (change jetpack movement),
trap doors, sniper towers, emergency ladders (recovery after falling),
final summit gate (opens after a timed mechanism).

## Teamwork (5v5 roles, dynamic)
2 Attackers (push to summit, contest flag), 1 Defender (protect lower
routes), 1 Sniper (cover from elevated positions), 1 Support (collect
power-ups, protect advancing teammates).

## Flag capture mechanics
- Reach the summit, break through enemy defences.
- Capture the enemy flag: hold the interaction button for 1.5 seconds.
- Carry the flag down: carrier cannot use jetpack boosts, moves 15% slower.
- Teammates must defend the return route.
- Score at your base to win the round.
- Carrier dies → flag drops at their location; either team can recover it;
  unretrieved for 15 seconds → returns to its original position.

## Dimensions / technical design (initial values, playtest to confirm)
World 3600 px wide × 7200 px tall; camera vertical-follow + horizontal
tracking; 10 players (5 each); 8 main levels; 4 hidden routes; 2 sniper
positions; 7 power-up types; 3 active power-up slots per player.

## Special mechanics
- Summit Storm: every 90 seconds, lightning temporarily disables selected
  exposed platforms — find alternate routes.
- Destructible Routes: certain wooden bridges and barricades can be destroyed,
  changing climbing routes during the match.
- Summit Control Switch: a switch halfway up temporarily activates a team
  elevator — capturing it creates an alternative route to the upper levels.

Design rule: vertically INTERCONNECTED, not vertically linear — a player who
falls must be able to recover through a tunnel, elevator or alternate route.

## Asset pack (user-uploaded 2026-11-20 ~17:46)
`~/workspace/user/files/SKYFALL_assets.zip` (1.8 MB, 77 files, 2.0 MB extracted
to `~/workspace/sky-raiders/assets/skyfall/SKYFALL_assets/`). Organized:
levels/ (8 level images 1800x450, one per level), powerups/ (7 power-ups, full
+ 64px icons + spritesheet), characters/ (8 Red/Blue × Attacker/Defender/
Sniper/Support sprites 128x192 RGBA transparent), flags/ (red/blue flags +
dropped versions + extraction zones 256x256 RGBA), hazards/ (falling rock,
storm lightning, disabled platform), map/ (dusk + storm skies, concept
diagram, full map overview), tiles/ (14: collapsing platform, moving
elevator, rope bridge, sniper tower, control switch, summit gate, trapdoors,
wind zone, wall block, destructible barricade, emergency ladder, solid
platform), ui/ (17: HUD bars, mode card, power-up slots, role icons, team
banners, title logo), README.txt. This is the "current zip file" the user
means — NOT the Ironfall pack.
1. CTF was REMOVED in v3.8 (user's own instruction ~16:45, QA-107). This map
   is built around capturing the flag. Bring CTF back — for this map only, or
   fully? Or build the map without the flag mode?
2. 6th map, or replace one of the 5 (Ironfall, Jungle, Neon City, Volcanic, Pirate)?
3. 5v5 = 10 players, but rooms currently cap at 8 players — raise the cap for
   this map, or play it with fewer players?

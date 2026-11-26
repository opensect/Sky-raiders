# Ironfall (Outpost) Competitive Map Redesign

**Scope.** The project's Mini Militia-style arena is map 0, Ironfall, a 3200×1400 adaptation of the classic Outpost. This review covers that playable map, its active map art, combat geometry, spawn/pickup placements and the existing movement/damage rules. It does not claim to audit every asset in the other four maps. Coordinates below use the game's world space; platform `y` is its top edge.

## 1. Map audit and gameplay problems

The old layout had a long, safe floor, a dense run of mid platforms, and a central fortress plus a separate upper-left perch. The fortress was a strong central visual landmark, but its sprite had no collision, so it looked like cover while bullets and players passed through it. The left perch added an asymmetric second summit. Spawn points were spread across multiple heights, so a player could re-enter directly into a high or mid fight while another had to climb from the floor. This made early combat timing and high-ground ownership depend on which spawn slot was assigned.

The rework keeps the 3200×1400 footprint and the recognizable Ironfall skyline, bunker, comms tower, iron plate and industrial props. It replaces the platform topology with mirrored outer climbs feeding a separated central bridge. There are 20 platform rectangles including the continuous floor, eight overhead rows, two equal high perches and several ground-level routes. The now-solid central bunker adds a small, covered roof perch. Platform rises are at most 132 px (the final summit step is 98 px), below the current 190 px jetpack rise cap; ordinary jumps remain useful for short corrections, while jetpack fuel and landing timing decide the vertical route.

| Topic | Audit | Redesign decision |
|---|---|---|
| Arena size and time to combat | 3200 px width gives flanks room, but the old upper spawns unevenly shortened/lengthened re-entry. | Keep the footprint; place six mirrored spawn points per team at floor level. Nearest opposing spawn pair is 260 px apart (about 0.87 s at 300 px/s before combat); other pairs are progressively farther apart. |
| Routes and circulation | Old levels often had broad gaps between disconnected shelves; reaching some high shelves depended on large jetpack climbs. | Use mirrored 132 px stair steps, with left, inside and right approach options into the centre. The isolated 640 px centre bridge is separated from side shelves by 260 px gaps, breaking the long firing runway. |
| Hotspots and dead areas | The fortress and one-sided summit were the clearest power positions; long floor stretches offered little decision-making. | Three expected fights: lower-lane spawn exits, the middle bridge and paired high perches. The centre bunker is now actual solid cover; short cover and landing shelves make the lower lane playable. |
| Vertical balance | A long central summit could fire into multiple lanes and was hard to contest from below. | Replace it with two 350 px summits, mirrored and exposed. No summit-exclusive pickup; both can be challenged from a lower ledge. |
| Weapons and range | Open floor encourages rifle/sniper aim; connected mid shelves bring shotguns and SMGs into play; a single central nest over-rewards long range. | Shorten high perches and interrupt long sightlines with level changes and cover. Keep the middle bridge contested and open enough for grenades/rockets to matter. |
| Damage and visibility | Platform, bunker and cover colliders are checked by bullet and explosion line-of-sight; explosions use the shared 125 px radius/falloff rules. No active Ironfall damage hazard is defined; decorative spikes and waterfall props could read as dangerous. | Keep the floor safe and predictable. Make the bunker solid, remove the misleading spike/water dressing; add no new damage trap to this competitive map. |

## 2. Movement and verticality

- **Walking and jumping:** the floor is continuous and safe; 132 px tier rises are intentionally not all ordinary-jumpable under the current short reference jump. The jump still helps with low cover and landing corrections.
- **Jetpack and hovering:** the route depends on short, repeatable thrust bursts and landing to refill. A tier is below the 190 px rise cap, but a player must still choose a landing and cannot hold a summit indefinitely without spending fuel.
- **Falling and escape:** gaps between shelves are deliberate drop routes back to the floor or lower tier. There are no deep pits, one-way traps, or ambiguous walkable-looking holes.
- **Wall interaction:** Ironfall has only the enclosing side walls; wall-jump is not enabled on this arena (the current special wall-jump rules are Skyfall-specific). Do not mistake the map boundary for an intended climb route.
- **Landing and camping:** small upper ledges give little lateral room and are exposed from below. The mirrored outside stair routes let players disengage by dropping, or challenge the summit from either side. No unreachable balcony or infinite-fuel perch is introduced.

### Platform placement (world coordinates)

The first row is the continuous safe floor. Every other row is `[x, y, width, 48]`:

| Top y | Platform spans (x to x+width) |
|---:|---|
| 1352 | 0–3200 (safe floor) |
| 1220 | 180–800; 2400–3020 |
| 1088 | 500–1000; 2200–2700 |
| 956 | 900–1420; 1780–2300 |
| 824 | 240–660; 720–1240; 1960–2480; 2540–2960 |
| 692 | 500–1020; 1280–1920 (centre bridge); 2180–2700 |
| 560 | 820–1240; 1960–2380 |
| 428 | 450–970; 2230–2750 |
| 330 | 600–950; 2250–2600 (paired summits) |

The bunker at `(1500,692)` has a 114×143 inset collision footprint from its 134×153 source slice. Its top is an intentional extra, compact landing surface; it is not an extra platform rectangle in the table above.

Spawns are `[220, 470, 720, 970, 1220, 1470]` and `[2980, 2730, 2480, 2230, 1980, 1730]`, all at `y=1318`. Weapon anchors are `(350,1188)`, `(2850,1188)`, `(1120,924)`, `(2080,924)`, `(1350,660)`, `(1850,660)`. Power-ups are `(1100,924)`, `(2100,924)`, `(1600,660)`. These are placed on or just above the intended platform surface, away from the solid centre bunker; no weapon is reserved to either summit.

## 3. Combat, power positions, and weapons

The annotated layout at [ironfall_redesign_layout.svg](assets/ironfall_redesign_layout.svg) shows the tier rhythm, team spawn halves, climb lanes, central contest area and the deliberate absence of active hazards.

| Position | Advantage | Counterplay |
|---|---|---|
| Twin summit perches, y330–428 | Strong view over nearby routes; useful for sniper/rifle taps. | 350 px summit cap, no exclusive pickup, symmetric access, exposed underside and short sightline broken by the lower platform bands. Grenades and rockets punish predictable holds. |
| Bunker roof, about y549 | Compact covered micro-perch on the centre bridge; a small height edge and visual anchor. | Inset solid collider matches the bunker silhouette. The roof is much narrower than either summit and can be challenged from both sides; it has no pickup. |
| Centre bridge, y692 | Fast rotation and the main mid-range rifle/SMG contest. | 640 px wide but bounded by open approaches and split from the side shelves. Both teams can enter from inside or outside routes; explosives have room to deny a landing. |
| Ground-level lane, floor y1352 | Fast re-entry, close-range cover and weapon pickup access. | Cover is sparse and destructible barrels remain readable; no team owns an elevated spawn. Opponents must commit into the lower lane to pressure a spawn. |

Shotguns/SMGs gain use around the floor cover and compact shelves; rifles have staggered medium lanes; snipers can hold a summit briefly but cannot dominate the whole map. Grenades and rockets are effective against platform landings and the central bridge, while safe gaps leave a drop/escape option. No weapon-specific damage or projectile rules were changed here.

## 4. Spawn, pickups, hazards, and edge cases

**Spawns.** Twelve positions remain in the existing contract: indices 0–5 are on the left team half, 6–11 on the right. All are at `y=1318`, with feet aligned to the safe floor at `y=1352`. They are mirrored around the center, at least 250 px apart within each team, and keep team players off the summit. Existing validation rejects overlapping geometry and prefers positions more than 150 px from live enemies, with team-half fallback. The floor itself remains in view; the new center crate and deck cover provide visual breaks but are not full spawn rooms. Spawn protection remains important for the nearest opposing slots.

**Hazards.** Ironfall has no `lava`, `fire_traps`, acid, electric damage or moving hazard entries. The old `if_spikes` image was dressing rather than a damage collider and could promise damage that never happened, so it is removed from this map. The explosive barrel prop is the only environmental damage source; it has visible art, solid cover collision and the game's existing blast behavior. Keep its blast radius and damage consistent with player explosives.

**Exploit and geometry checklist.** Bounds still enclose the map; the floor closes the bottom; no pit/fall-death route exists. Platforms are all within the 3200×1400 arena and have nonzero width. The top ledges are reachable from lower ledges; none is a pixel-sized foothold or an unreachable decorative platform. Avoid adding collision to visual-only buildings without matching the art. No projectile-only invisible wall, hidden hazard, or spawn-overlap surface was added. The supplied platform artwork is 128×48 and repeats; collision remains a rectangle of the same dimensions.

## 5. Active map asset quality review

This is an audit of the assets used by Ironfall, not all 559 files in `assets/`.

| Asset | Current quality / resolution | Gameplay and readability impact | Verdict |
|---|---|---|---|
| `tile_ironfall.png` | Clean, seamless dark iron plate with a warm hazard-marked lip; 128×48 RGB. Repeated at world scale. | High platform edge contrast; small rivets are decorative and do not obscure player silhouettes. 1024×1024 would waste memory for a repeating strip. | Keep |
| `bg_ironfall.png` | Restrained dusk industrial skyline; 960×540. Used as a far parallax layer, not collision. | Quiet lower contrast than the platforms; smoke/structures stay behind combat and do not imitate platform geometry. Current size is adequate at game viewport scale. | Keep |
| `if_bunker.png` | 134×153 transparent slice. Small landmark art. | Central bunker now has a matching inset rectangle collider, so its visible cover stops bullets and players consistently. | Keep |
| `if_comms.png` | 94×175 transparent slice. Small landmark art. | Tall silhouette adds industrial identity; intentionally visual-only. | Keep |
| `if_tower.png` | 61×101 transparent slice. Small landmark art. | Readable as distant set dressing, not intended as a sniper platform. | Keep |
| `if_gantry.png` | 109×87 transparent slice. | Industrial middle-ground shape, visual-only. | Keep |
| `crate.png` | 42×42 transparent prop. | Small floor cover with matching collision. | Keep |
| `barrels.png` | 49×48 transparent cluster. | Readable explosive cover; collision and blast behavior are already present. | Keep |
| `stone_column.png` | 54×118 transparent prop. | Narrow vertical cover; small silhouette. | Keep |
| `if_crate.png` | 42×59 transparent slice. | Solid prop collision matches its small visible footprint. | Keep |
| `if_barrel.png` | 34×48 transparent slice. | Solid/explosive threat is small but recognizable. | Keep |
| `if_sandbags.png` | 55×36 transparent slice. | Low solid cover; does not hide a full character, leaving readable counterplay. | Keep |
| `if_palm.png` | 128×131 transparent slice. | Large visual foliage; no collision, stays at the edge of play. | Keep |
| `if_derrick.png` | 60×101 transparent slice. | Thin landmark, visual-only. | Keep |
| `if_vent.png` | 82×96 transparent slice. | Industrial set dressing, not solid cover; do not use it to imply a safe firing bunker. | Keep |
| `if_door.png` | 54×96 transparent slice. | Small door landmark, visual-only. | Keep |
| `if_cave.png` / `if_cave2.png` | 131×87 / 131×84 transparent slices. | Dark cave shapes can imply a passage; both are decorative and should stay behind the clear play silhouette. | Keep at edge positions |
| `if_lamp.png` | 30×46 transparent slice. | Tiny light landmark, not gameplay-critical. | Keep |
| `if_bridge_metal.png` | 179×35 transparent slice. | Clear bridge motif, but collision is supplied by the platform rectangle below. | Keep |
| `if_bridge.png` | 125×42 transparent slice. | Decorative bridge, supported visually by a platform; the sprite itself is not a walkable surface. | Keep |
| `if_rockledge.png` | 119×45 transparent slice. | Low rock shape sits on a platform; gameplay collision remains the platform rectangle. | Keep |
| `if_rock.png` | 122×38 transparent slice. | Small cluster with matching solid collision. | Keep |
| `if_plank.png` | 179×29 transparent slice. | Visual route cue over the platform underneath. | Keep |
| `if_spikes.png` | Transparent 80×94 prop. | It did not apply damage in this map, creating a misleading hazard cue. | Remove from Ironfall dressing; reserve for a map with actual spike collision/damage |
| `if_fall.png` / `if_water.png` | 56×100 / 167×92 transparent slices. | A waterfall and water block at the former floor centre suggested a pit/hazard although the floor was continuous and safe. | Remove from Ironfall dressing; retain in the shared library for an appropriate map |
| `thumb_ironfall.png` | 96×64 map selector thumbnail. | Correct for a small menu card, not for gameplay. | Keep |

## 6. Resolution and performance guidance

Choose source size by on-screen pixels, not a blanket 1024×1024 rule. Keep the 128×48 seamless platform tile as-is. The 960×540 background already exceeds the 1280×720 viewport only after the parallax scale is considered; retain it unless the camera begins to show visible softness. Existing landmark props are drawn small, so 512×512 source art is only justified if they become large foreground silhouettes. A 2048×2048 hero texture is unnecessary for the present arena and would cost memory and bandwidth. Preserve transparent cutouts and atlas/repeat behavior.

All listed map art stays shared as small PNG textures; platforms repeat one 128×48 texture instead of duplicating a large image per segment. Transparent props are low-pixel-count cutouts and no new particle systems, animated hazards, materials, or per-platform draw calls were added. Keep background parallax behind the procedural sky and platform/character layers. Preserve the existing texture filtering and mipmap choices unless a mobile capture shows shimmer.

## 7. Competitive pacing and design principles

- **Opening:** both teams start at ground level with immediate route choice: take sparse cover and a lower pickup, or begin a 132 px climb. Spawn slots do not grant automatic high ground.
- **Mid game:** mirrored stair routes converge on the broken centre bridge. This produces recurring 2–4 second rotations and multi-angle engagements, instead of one mandatory tunnel or one summit.
- **Late game:** short summits create temporary control; low fuel, exposure, grenades and the drop route make a held position contestable. The map does not add a sudden lethal zone or randomness.

The design applies familiar principles from the named arena/platform shooters without copying their maps: compact routes and weapon-role contrast, readable silhouettes, safe counter-routes, equal access to height, and enough cover to break sightlines without erasing movement skill. It is intended to support repeated rotations rather than a single dominant lane.

## 8. Final redesign change list

1. Keep the Ironfall theme, size, full safe floor, background and tile art.
2. Replace the asymmetric 30-platform arrangement with mirrored stair routes and equal exposed summit perches; keep a split 640 px central bridge.
3. Place all 12 spawns at floor level in mirrored team halves; preserve the existing six-per-team indexing.
4. Re-anchor weapon and power-up spots to the new platform tops, balancing the left/right lanes and centre.
5. Remove the misleading decorative spike prop; retain the readable explosive-barrel gameplay.
6. Leave combat physics, weapon values, spawn validation, and hazard damage code unchanged.

**QA status:** source-level geometry and reference review only. Godot was not available in the command environment, so no in-engine collision, screenshot, multiplayer spawn, or weapon playtest is claimed. Validate the new layout in a running build at 1v1, 3v3 and full 6v6 before shipping; in particular check the nearest centre spawn pair and whether summit sightlines stay interruptible at actual camera zoom.

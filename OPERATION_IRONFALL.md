# Operation Ironfall — map design (user-shared, 2026-11-20)

Original 2D shooter map, Mini Militia-inspired side-scrolling battlefield.
Assets: `~/workspace/mini-militia-lan/assets/ironfall/` (10 PNG sheets from
`~/workspace/user/files/Operation_Ironfall_Map_Assets.zip`, 2.1 MB) + `concept.jpg`
(the full design sheet the user shared). All sheets are RGB with solid dark
backgrounds — NOT transparent production sprites. They must be sliced into
individual sprites and background-removed before import (same technique as the
Jungle Ruins pack: connected-component labelling + alpha ramp, verified on a
contrasting background so no dark box shows).

User specs: USE this asset, HIGH quality, map size NOT too big NOT too small
(medium — comparable to the existing maps, ~3200x1400 play area).

## Five combat zones
- Zone A – Northern Watchtower: elevated sniper positions, observation towers,
  long-range firing lanes.
- Zone B – Broken Bridges: suspended bridges, narrow platforms and gaps,
  attack from above or below.
- Zone C – Underground Tunnels: connected caves, hidden routes, narrow
  passages, concealed weapon pickups.
- Zone D – Ironfall Central Base: central combat area, multiple entrances,
  defensive structures, elevated platforms.
- Zone E – Waterfall Cavern: lower-level combat, water obstacles, hidden cave
  entrances, alternative escape routes.

## Asset sheets
| File | Contents |
| ---- | -------- |
| 00_map_layout_reference.png (1536x520) | Complete map layout reference |
| 01_terrain_tiles.png | Rocky terrain tiles |
| 02_structures_buildings.png | Buildings and fortress structures |
| 03_bridges_platforms.png | Bridges and platforms |
| 04_tunnels_caves.png | Tunnels and caves |
| 05_objects_props.png | Crates, barrels and props |
| 06_nature_decor.png | Trees, plants and vegetation |
| 07_gameplay_markers.png | Gameplay markers and flags |
| 08_special_environment.png | Waterfall, water and special elements |
| 09_extra_structures.png | Watchtowers and extra structures |

## Implementation notes (from the design doc)
- Separate foreground and background layers.
- Modular terrain collision polygons; independent platform collision.
- Tunnel entrances connected through continuous playable paths.
- Sniper positions with sufficient visibility.
- Multiple routes between upper, middle and lower levels.
- Weapon pickup spawn points distributed across the map.
- Jetpack-accessible platforms and hidden shortcuts.
- Map features: multi-tier platforms, underground tunnels, sniper spots,
  hidden routes, strategic cover, balanced gameplay.

## Open decision (asked 2026-11-20 ~12:59)
Add Ironfall as a 6th map, or replace one of the 5 kept maps
(Military, Jungle, Neon City, Volcanic, Pirate)? Awaiting the user's pick.

# Asset Manifest — LAN Arena Shooter (Godot 4.3)

All art is original, made with Python + PIL only. Style: bold clean cartoon
military look, thick dark outline, readable at combat speed, matched to the
existing `tiles/grass_block.png` (200x58) and `tiles/stone_slab.png` (128x48).
No existing file under `assets/` was modified. No code/config files touched.

## v4 supply pickup pack (`assets/generated/v4_supply_pack/`)

Three transparent 128x128 SVG pickup illustrations: `field_medkit.svg`,
`ammo_cache.svg`, and `frag_grenade.svg`. They use the game's dark outline,
navy shadow, and high-contrast green/amber palette, and are wired into
`pickups/pickup.gd` for health, weapon, and grenade pickups.

## Part 1 — Themed platform tiles (`assets/tiles/`, all 128x48 px, RGB, fully opaque)

| File | Size | Description |
|---|---|---|
| `tile_catacombs.png` | 128x48 | Dark blue-grey cracked stone, warm torch-lit top edge |
| `tile_military.png` | 128x48 | Grey concrete, darker edge lines, yellow/black hazard stripe on top |
| `tile_desert.png` | 128x48 | Warm sandstone, sandy top, darker rock body |
| `tile_factory.png` | 128x48 | Dark steel plates with rivets, yellow/black warning edge on top |
| `tile_frozen.png` | 128x48 | White snow top, pale blue cracked ice body |
| `tile_jungle.png` | 128x48 | Bright green grass top, brown dirt body with roots |
| `tile_space.png` | 128x48 | Dark metal floor, glowing cyan edge strip on top, panel lines |
| `tile_city.png` | 128x48 | Dark asphalt top with pale curb edge, brick body below |
| `tile_volcanic.png` | 128x48 | Dark basalt, glowing orange cracks, ember-orange top edge |
| `tile_pirate.png` | 128x48 | Wooden plank top (warm brown), stone wall body below |

Seam check: each tile was pasted 4x side-by-side and viewed — tiling is
continuous left-to-right (patterns wrap; mean left-vs-right edge column
difference 0.0–7.9/255, the residual being the shared dark block outline,
same as the existing `grass_block.png` style). The dark vertical line at each
joint is the tile's own outline, not a seam error.

## Part 2 — Map thumbnails (`assets/thumbs/`, all 96x64 px, RGB, no text)

| File | Size | Description |
|---|---|---|
| `thumb_catacombs.png` | 96x64 | Dark blue sky, torch glow, stone ground + 2 platforms |
| `thumb_military.png` | 96x64 | Grey sky, concrete ground + 2 platforms |
| `thumb_desert.png` | 96x64 | Warm orange sky, sandy ground + 2 platforms |
| `thumb_factory.png` | 96x64 | Grey industrial sky, steel ground + 2 platforms |
| `thumb_frozen.png` | 96x64 | Pale blue sky, snowfall dots, snow ground + 2 platforms |
| `thumb_jungle.png` | 96x64 | Green sky, palm cue, dirt ground + 2 platforms |
| `thumb_space.png` | 96x64 | Dark navy/purple sky, metal ground + 2 platforms |
| `thumb_city.png` | 96x64 | Grey-blue sky, asphalt ground + 2 platforms |
| `thumb_volcanic.png` | 96x64 | Dark red sky, lava glow, basalt ground + 2 platforms |
| `thumb_pirate.png` | 96x64 | Bright blue sky, wooden ground + 2 platforms |

Each thumbnail: gradient sky in theme colours, ground/platform silhouette at
the bottom, one or two small platform shapes, one subtle theme cue.

## Part 3 — Jungle Ruins slices (`assets/jungle/`, PNG with transparency)

Source: `~/workspace/user/files/Jungle_Ruins_Godot_Asset_Pack/assets/environment_asset_atlas.png`
(1672x545, generated concept sheet with a BLACK background, not pre-sliced).

Method: sprites were located by image analysis (connected-component
labelling at brightness threshold 60) plus enlarged visual inspection of
each atlas section, then hand-boxed — auto-labelling alone merges sprites
via the sheet's soft olive/grey glow halo. Black background removed with an
alpha ramp (fully transparent below brightness 28, fully opaque above 110),
0.6px Gaussian feather on the alpha channel, and a 3px transparent disc
cleared at each corner. Every output was verified on magenta and on dark
green backgrounds: no dark box around any sprite. A faint soft glow fringe
remains on a few sprites (the sheet's baked-in halo, now semi-transparent);
it reads as glow on a dark jungle background, not a box.

Transparent % = share of pixels with alpha exactly 0. All 4 corner pixels
are fully transparent (alpha 0) in every jungle file below.

| File | Size (px) | Fully transparent | Corners transparent | Notes |
|---|---|---|---|---|
| `jungle_grass_tile.png` | 66x56 | 0.0% | Yes | Solid square terrain tile (decor/texture, not a platform tile); near-0% is correct — only the rounded corners are transparent |
| `jungle_platform.png` | 142x61 | 19.0% | Yes | Floating grass-topped stone platform |
| `jungle_bridge.png` | 122x56 | 29.7% | Yes | Wooden bridge/platform segment |
| `jungle_arch.png` | 155x90 | 33.3% | Yes | Stone arch |
| `jungle_tree.png` | 124x118 | 17.9% | Yes | Large leafy tree |
| `jungle_palm.png` | 81x130 | 14.3% | Yes | Palm tree (curved trunk, grass tuft at base) |
| `jungle_watchtower.png` | 74x180 | 3.1% | Yes | Tall wooden watchtower with roof; atlas sprite is 74x180, not ~90x220 |
| `jungle_statue.png` | 53x97 | 0.6% | Yes | Stone statue head on a rock base; fills most of its frame |
| `jungle_pillar.png` | 52x84 | 6.5% | Yes | Stone pillar; atlas sprite is 52x84, not ~50x120 |
| `jungle_crate.png` | 49x51 | 0.0% | Yes | Wooden crate; solid square, only rounded corners transparent |
| `jungle_rock.png` | 74x94 | 28.0% | Yes | Grey rock cluster |
| `jungle_bush.png` | 74x39 | 12.5% | Yes | Leafy bush |

Skipped: none. All 12 requested jungle sprites were cleanly separated.
Sizes differ from the rough aims in a few cases because the atlas sprites
themselves are those sizes (watchtower, statue, pillar, rock, bush, palm,
tree) — the crops are the full sprites, not rescaled.

## Part 4 — v3.7 map-independent visuals (QA-082…QA-092)

All drawn with Python + PIL only (`gen_v37_assets.py` in the project
root), 4x supersampled then downscaled, PNG lossless. Style: bold
clean cartoon military, thick dark outline, readable at combat speed.

### Effects (`assets/effects/`, transparent PNG)

| File | Size | Description |
|---|---|---|
| `jetpack_flame.png` | 32x64 | Teardrop flame, orange → yellow → white-hot core, dark outline; points down from its top edge |
| `muzzle_pistol.png` | 48x24 | Small 3-spike starburst, yellow-white core |
| `muzzle_rifle.png` | 64x28 | 4-spike starburst (rifle + SMG share it) |
| `muzzle_shotgun.png` | 80x40 | Wide 6-spike burst |
| `muzzle_sniper.png` | 88x20 | Long narrow horizontal spike |
| `muzzle_rocket.png` | 72x56 | Big 8-spike fireball burst |
| `bullet_trail.png` | 64x8 | Gradient streak, bright at the head (right), fading to the tail |
| `dust.png` | 64x48 | Soft tan dust puffs (no hard outline — dust is soft) |
| `flag_red.png` / `flag_blue.png` | 72x96 | Pole with gold finial + waving cloth + white star emblem |
| `capture_burst.png` | 96x96 | Gold starburst with orbiting sparks |
| `particle_dot.png` | 32x32 | Soft radial dot for the GPUParticles2D blast burst (QA-091) |

### Items (`assets/items/`)

`ammobox.png` (96x56, olive crate, AMMO stencil), `grenade.png`
(56x76, pin + lever + ridges) and `healthkit.png` (64x64, white box,
green cross) were already in the folder but NEVER used — redrawn
bigger/clearer and wired into `pickup.gd` (QA-088). New:
`weapon.png` (72x44 rifle glyph, on the weapon pickups) and
`shield.png` (56x64, blue shield + star — drawn, not wired: no
shield pickup kind exists yet).

### Headgear (`assets/headgear/`)

`bandana_red.png` (48x28, knot + tails), `nvg.png` (48x30,
night-vision goggles, glowing green lenses), `helmet_camo.png`
(49x32, camo-blotch dome). Indices 4–6; 1–3 unchanged (QA-090).

### Menu background (`assets/backgrounds/`)

`menu_arena_dusk.png` (1920x1080, RGB): dusk gradient, stars,
mountain silhouettes, arena wall with floodlight towers at the
edges, dark empty centre so the menu UI stays readable (QA-089).

### Verification done

- Every sprite viewed on a dark-green contact sheet: no dark box,
  all four corners transparent (except `bullet_trail.png`, whose
  bright head end touches the bullet — by design).
- Two fixes during drawing: the muzzle bursts were first drawn at
  1x radii on a 4x canvas (tiny white ovals) — fixed to scaled
  radii; the menu sky gradient banded and the sun glow bled onto
  the ground as flat ovals — fixed with a bicubic ramp and a
  blurred, clipped glow.
- External libraries (QA-092) are NOT in this manifest — see
  BUGS.md QA-092 for the library list (`addons/reeboo_fx2d`,
  `addons/sprite_juice_lite`).

## Part 5 — v3.7 Operation Ironfall (QA-095/QA-096)

Source: the user's `Operation_Ironfall_Map_Assets.zip` (10 PNG
sheets + `concept.jpg`, RGB on solid dark blue-grey backgrounds
~25–41 brightness — NOT transparent sprites). Generator:
`gen_ironfall_assets.py` in the project root.

### Slices (`assets/ironfall_sliced/`, PNG with transparency)

Method: hand-boxed from visual inspection + connected-component
analysis (auto-labelling alone merges sprites via the sheets'
soft glow halo, same as the Jungle pack). Background removed by
flood-fill from the crop border (colour distance < 14 from the
border-median background colour) — NOT the Jungle brightness
ramp, which would eat the sprite stone (nearly as dark as the
background). Pure-black pixels (brightness < 10) restored to
opaque near-black after the fill, so cave mouths stay dark.
0.7 px Gaussian feather on the alpha channel, 3 px transparent
disc cleared at each corner. Every output verified on magenta
and on dark-green backgrounds: no dark box on any sprite.
Two crops were wrong on the first pass (vent/door/lamp read off
a scaled-up view and caught neighbouring sprites) — caught on
the contact sheet, re-boxed from a 50 px grid overlay,
re-verified. Transparent % = share of pixels with alpha exactly
0. All 4 corner pixels are fully transparent (alpha 0) in every
file below.

| File | Size (px) | Fully transparent | Notes |
|---|---|---|---|
| `if_tower.png` | 61x101 | 41.2% | Watchtower with roof (sheet 09) |
| `if_gantry.png` | 109x87 | 35.0% | Steel gantry frame (09) |
| `if_derrick.png` | 60x101 | 59.2% | Oil derrick (09) |
| `if_bridge.png` | 125x42 | 45.0% | Wooden bridge with legs (03) |
| `if_bridge_metal.png` | 179x35 | 34.5% | Long metal bridge (03) |
| `if_plank.png` | 179x29 | 50.2% | Long wooden plank (03) |
| `if_cave.png` | 131x87 | 31.4% | Stone cave arch, dark mouth (04) |
| `if_cave2.png` | 131x84 | 27.1% | Cave arch with lamp (04) |
| `if_cavern.png` | 270x142 | 33.0% | Big two-mouth cave system (04) — sliced, not placed on the map yet |
| `if_rockledge.png` | 119x45 | 32.5% | Rock ledge (04) |
| `if_water.png` | 167x92 | 26.8% | Water block with waves (08) |
| `if_fall.png` | 56x100 | 51.7% | Waterfall column + splash (08) |
| `if_spikes.png` | 80x94 | 36.9% | Spike trap base (08) |
| `if_vent.png` | 82x96 | 35.1% | Fan vent building (08) |
| `if_door.png` | 54x96 | 25.3% | Hazard-striped door (08) |
| `if_crate.png` | 42x59 | 43.4% | Tall wooden crate, SOLID (05) |
| `if_barrel.png` | 34x48 | 36.4% | Red barrel, SOLID (05) |
| `if_sandbags.png` | 55x36 | 39.0% | Sandbag pile, SOLID (05) |
| `if_lamp.png` | 30x46 | 33.4% | Glowing lamp post (05) |
| `if_palm.png` | 128x131 | 51.3% | Two palm trees (06) |
| `if_vines.png` | 138x69 | 42.4% | Hanging vines (06) — sliced, not placed yet |
| `if_rock.png` | 122x38 | 40.7% | Rock cluster (06) |
| `if_tree.png` | 64x67 | 43.6% | Small pine tree (06) — sliced, not placed yet |
| `if_bunker.png` | 134x153 | 34.0% | Two-tier bunker, doorway open (02) |
| `if_arch.png` | 114x165 | 50.4% | Arch building with antenna (02) — sliced, not placed yet |
| `if_comms.png` | 94x175 | 50.5% | Comms tower with dish (02) |

Note: the bunker/arch doorway interiors went transparent in the
flood fill (they connect to the crop border through the open
doorway) — they read as open doorways showing the sky, not as
dark boxes. The cave mouths are enclosed by stone, so they
stayed opaque black.

### Code-drawn (`tile_ironfall`, `bg_ironfall`, thumbs)

| File | Size | Description |
|---|---|---|
| `assets/tiles/tile_ironfall.png` | 128x48 | Iron plate tile: dark gunmetal plates, rivets, rust-orange top edge with hazard ticks; left-vs-right edge column mean difference 4.0/255 (the joint line is the tile's own outline, like the other tiles) |
| `assets/skybrawl/maps/bg_ironfall.png` | 960x540 | Dusk factory skyline: steel-blue gradient, low orange sun glow, factory silhouettes, smokestacks with smoke, crane; far-parallax layer, mirrored at 1286 like the other backgrounds |
| `assets/thumbs/thumb_ironfall.png` | 96x64 | Dark steel sky, watchtower cue, iron ground + 2 platforms, no text |
| `assets/thumbs/thumb_neon.png` | 96x64 | Neon City's missing thumbnail: purple/pink sky, neon dots + strip, dark ground + 2 platforms, no text |

### Verification done

- Every slice viewed on magenta and on dark-green contact
  sheets: no dark box, all four corners transparent.
- Tile pasted 4× side-by-side and viewed: continuous, joint
  is the outline only. Background + both thumbs viewed at 3×.
- No game build/export/test was run by the asset step itself
  (the map work's full suite covers it — see BUGS.md QA-096).

## Verification done

- Viewed `grass_block.png` and `stone_slab.png` first; tiles match their style.
- Tiles: 4x side-by-side seam strips viewed; sizes confirmed 128x48, RGB/opaque.
- Thumbnails: confirmed 96x64, no text.
- Jungle: every sprite viewed on magenta and dark-green backgrounds;
  corner pixels and transparent % measured per file (table above).
- No game build/export/test was run (out of scope for this task).

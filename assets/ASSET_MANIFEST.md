# Asset Manifest — LAN Arena Shooter (Godot 4.3)

All art is original, made with Python + PIL only. Style: bold clean cartoon
military look, thick dark outline, readable at combat speed, matched to the
existing `tiles/grass_block.png` (200x58) and `tiles/stone_slab.png` (128x48).
No existing file under `assets/` was modified. No code/config files touched.

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

## Verification done

- Viewed `grass_block.png` and `stone_slab.png` first; tiles match their style.
- Tiles: 4x side-by-side seam strips viewed; sizes confirmed 128x48, RGB/opaque.
- Thumbnails: confirmed 96x64, no text.
- Jungle: every sprite viewed on magenta and dark-green backgrounds;
  corner pixels and transparent % measured per file (table above).
- No game build/export/test was run (out of scope for this task).

# Sky Brawl asset pack — curation for the LAN Arena Shooter

Curated 2026-11-19 ~02:00 IST. Pack source: user upload
`~/workspace/user/files/sky_brawl_1000_game_assets.zip`, extracted to
`~/workspace/user/files/sky_brawl_asset_pack/sky_brawl_asset_pack/`
(1,000 PNGs + `manifest.json` + `README.md`).

**Pack root in the paths below:** `P = ~/workspace/user/files/sky_brawl_asset_pack/sky_brawl_asset_pack/`
(e.g. `P/maps/arena_map_01.png`).

## Verdict in one paragraph

The pack is usable, small (whole pack 671 KB; the selection below is
**54 files, ~103 KB**), and honest flat-vector placeholder art — but it is
far less varied than "1,000 assets" sounds. Nearly every category is a
handful of base designs × palette swaps: 1 robot character in 5 colours,
1 rifle silhouette, 1 night-sky background scene in 5 ground palettes,
~7 real tile designs (the other ~130 tiles are one blue-blob design),
~7 structure shapes, 8 props, ~10 effects, ~6 pickup icons. The
**pickup icons, effects, structures and characters are the genuinely good
stuff**; the **backgrounds are the weakest part** (all night scenes, all
the same layout, with fake platforms baked in). Import ONLY the 54 files
below — the other 946 files add nothing but APK size.

## Transparency verification (PIL, all 1,000 files)

Method: every file opened with PIL; counted fully-transparent pixels
(alpha = 0), semi-transparent pixels (0 < alpha < 255), and opaque
corners/edges (4×4 corner blocks + edge ring, alpha > 10 = opaque).
**No file in any sprite category has opaque corners or edges — there is
no dark-box risk from this pack** (unlike the first asset pack, whose
explosion/weapon/headgear pieces were nearly fully solid).

| Category | Files | Size | Fully transparent | Semi-transparent | Opaque corners/edges | Verdict |
|---|---|---|---|---|---|---|
| Characters | 120 | 96×96 RGBA | ~65% | ~0% | 0 / 120 | Clean. True transparency. |
| Weapons | 120 | 128×64 RGBA | ~77% | ~0% | 0 / 120 | Clean. |
| Terrain tiles | 160 | 64×64 RGBA | **0%** | **7–78%** | 160 / 160 (corners opaque) | See warning below. |
| Props | 120 | 96×96 RGBA | 49–82% | ~0% | 0 / 120 | Clean. |
| Combat effects | 160 | 96×96 RGBA | 57–88% | ~0% | 0 / 120 | Clean. |
| Pickups | 80 | 64×64 RGBA | 42% (all) | ~0% | 0 / 80 | Clean. |
| UI elements | 40 | 128×64 RGBA | 18–54% | ~0% | 0 / 40 | Clean, but unused (see §Rejected). |
| Arena backgrounds | 20 | 960×540 RGBA | 0% | 0% | 20 / 20 | Fully opaque — correct for a background. |
| Map structures | 180 | 128×128 RGBA | 21–64% | ~0% | 0 / 180 | Clean. |

**Terrain-tile warning (the one real transparency problem in the pack).**
Tiles have ZERO fully-transparent pixels, but 7–78% of each tile is
**semi-transparent (alpha ≈ 90–110)** instead of opaque. Per selected
tile: terrain_005 6.7% semi, terrain_001 18.0%, terrain_002 25.8%,
terrain_006 27.2%, terrain_004 28.9%. The game draws tiles with
`_draw_tiles()` in `game.gd` (one texture repeated along each platform
top, over the gradient sky) — semi-transparent tile regions would let
the sky show through the middle of solid platforms. **Before import,
flatten every selected tile: composite it onto an opaque base of its own
dominant dark colour (or threshold alpha < 255 → 255).** Do NOT import
raw. `terrain_003` (51.2% semi) and `terrain_008` (77.6% semi) are
rejected partly for this reason. `terrain_002` is the exception: its
semi-transparency is fine for its assigned use (cloud layer, visual
only, never a solid platform top).

**Distinct-design counts** (16×16 grayscale shape-hash clustering, then
visually confirmed on contact sheets of one representative per group):
characters 5 groups = **1 robot design × 5 colours**; weapons 28 hash
groups = **1 rifle silhouette** (groups differ only by scope-blob
position/colour); terrain 27 groups = **~8 real designs, then one
blue-blob design repeated ~130×**; props 8 designs; effects 10 designs;
pickups 19 groups = **~6 icon designs**; UI 19 groups = generic shapes;
structures 32 groups = **~7 shapes × palettes**; arena backgrounds =
**1 scene × 5 ground palettes**.

## Resolution notes

- **Arena backgrounds are 960×540; maps are 2800–3600 px wide and
  1400–1800 px tall.** The game currently draws NO image background at
  all: `_build_background()` in `game.gd` draws a procedural vertical
  gradient (`GradientTexture2D`, 4×512, stretched over the whole map),
  a polygon sun/moon, and two polygon hill silhouettes. There is no
  parallax layer to drop an image into — the Phase 5 builder must ADD
  one. Do NOT stretch a 960×540 image over a 3400 px map (3.5× upscale
  = visible blur, and the baked-in platform bars would sit under the
  real platforms).
- **Recommended use:** far parallax layer at **viewport scale, not map
  scale** — draw the image screen-fixed (or with a small parallax
  factor ~0.2–0.3) sized to cover the camera view (~1280×720 on phones),
  i.e. only ~1.3× upscale, behind the existing gradient sky. Flat
  vector shapes survive a 1.3× upscale fine. Keep the procedural
  gradient + hills in front of / blended with it so the horizon still
  matches each map's palette.
- **Baked-in fake platforms:** every arena background contains floating
  cyan platform bars (mid-image, roughly y 180–420 of 540) plus a
  rounded-rect sign top-left, which do NOT match any map's real
  platform layout. As a far parallax layer they read as distant
  scenery and are acceptable; never use the image as a full-screen
  static backdrop, where the fake platforms would confuse players
  (visible platforms with no collision). If a background ever looks
  wrong in-game, first suspect these bars.
- **Tiles are 64×64; the game's existing tiles are 128×48** and
  `_draw_tiles()` repeats the texture horizontally along platform tops.
  A 64×64 tile repeats every 64 px (fine) but is 16 px taller than the
  48 px platform collision box (it will overhang below the platform —
  acceptable, reads as a platform lip — or crop/resize to 128×48 on
  import). Flatten alpha first (see warning above).
- **Characters 96×96, weapons 128×64, props/effects 96×96, pickups
  64×64, structures 128×128** — all fine at native size for their
  assigned uses; no upscaling needed.

## SELECTION — 54 files, ~103 KB

### Arena backgrounds — 13 (one per map)

All 20 are the same night scene (dark navy starry sky, flat triangle
mountains, solid ground band, floating platform bars) in 5 ground
palettes: red-brown `#43272b`, steel blue `#19364e`, forest green
`#2b4333`, purple `#362a4c`, tan brown `#563e2b`, plus slate blue-gray
`#334d5b`. Assignments are **by ground palette only** — no pack
background matches a daytime, desert, snow, jungle, sunset or neon
theme. Fit rating: GOOD = dark map, palette matches; FAIR = dark map,
palette close; POOR = day map, night background clashes — on POOR maps
prefer keeping the procedural gradient and treat the pack image as an
optional dusk/night variant only.

| Map | File | Ground palette | Fit | Note |
|---|---|---|---|---|
| Catacombs | `P/maps/arena_map_01.png` | red-brown | FAIR | Darkest sky in the pack; matches the dark map. |
| Military Base | `P/maps/arena_map_07.png` | forest green | POOR | Day map (bright blue sky in `game.gd`); green ground only echoes its green hills. Keep gradient preferred. |
| Desert Outpost | `P/maps/arena_map_05.png` | tan brown | POOR | Day map; tan ground is the closest palette, warmest sky. Keep gradient preferred. |
| Industrial Factory | `P/maps/arena_map_13.png` | tan brown | FAIR | Dusk gray-brown map; tan ground fits the factory floor tone. |
| Frozen Fortress | `P/maps/arena_map_02.png` | steel blue | POOR | Day/ice map; steel-blue ground only. Keep gradient preferred. |
| Jungle Ruins | `P/maps/arena_map_03.png` | forest green | POOR | Day map; green ground matches the jungle, night sky does not. Keep gradient preferred. |
| Space Station | `P/maps/arena_map_18.png` | steel blue | GOOD | Very dark map; blue mountains read as a space vista. Best fit in the pack. |
| City Underground | `P/maps/arena_map_04.png` | purple | GOOD | Very dark map; purple ground fits the underground neon-less gloom. |
| Volcanic Cavern | `P/maps/arena_map_09.png` | red-brown | GOOD | Dark red map; red-brown ground matches the cavern. |
| Pirate Island | `P/maps/arena_map_14.png` | slate blue-gray | POOR | Day/sea map; slate blue is the closest to sea/steel. Keep gradient preferred. |
| Neon City (new) | `P/maps/arena_map_20.png` | purple | GOOD-ish | Dark blue/purple night map per MAP_AUDIT.md; purple ground is the best palette fit. No neon skyline in the image — a Gemini neon sky is still wanted. |
| Ancient Temple (new) | `P/maps/arena_map_19.png` | forest green | FAIR | Green ground fits "overgrown"; no gold/teal temple sky in the pack. A Gemini temple sky is still wanted. |
| Airship Fleet (new) | `P/maps/arena_map_17.png` | red-brown | POOR | Warm sunset dusk wanted; pack has no sunset sky at all. Red-brown ground is the warmest available. A Gemini dusk sky is still wanted. |

Rejected backgrounds (7): `arena_map_06, 08, 10, 11, 12, 15, 16` —
same scene, duplicate palettes of the selected 13 (e.g. 10/18 are both
steel blue, 08/16 both magenta-purple ground). Nothing visually
distinct in them; do not import.

### Terrain tiles — 5

| File | Design | Semi-transparent | Use |
|---|---|---|---|
| `P/terrain_tiles/terrain_005.png` | tan diagonal cut stone | 6.7% (cleanest) | **Ancient Temple** platform tile (carved-stone look). Also fallback deck tile for Airship Fleet. |
| `P/terrain_tiles/terrain_001.png` | red brick grid | 18.0% | **Ancient Temple** alternate / Catacombs floor-tile refresh. |
| `P/terrain_tiles/terrain_004.png` | purple brick grid | 28.9% | **Neon City** platform tile (purple brick reads as night-city). |
| `P/terrain_tiles/terrain_006.png` | blue diagonal stripes | 27.2% | **Neon City** alternate (neon-lit metal). |
| `P/terrain_tiles/terrain_002.png` | blue with white blobs | 25.8% | **Airship Fleet cloud layer only** (visual-only, below the decks) + Frozen Fortress snow/foam alternate. Never as a solid platform top. |

All 5 must be alpha-flattened before import (except 002 in its cloud
role). Resize/crop to 128×48 to match the existing tile convention, or
keep 64×64 and accept the 16 px overhang. Add as `tile` indices 10/11/12
in `TILE_TEX` for the three new maps; do not renumber the existing 0–9.

### Map structures — 16 (128×128, all visually verified)

Shape families in the pack: horizontal slab, hut/bunker with doorway,
hut with round window, vent/grate, trapezoid platform, ring, X-crate.
Every file below was viewed individually (representative sheets +
single-file verification for 033/036/042/051/057/069/054/023).

**Neon City (7)** — night-city rooftop kit:
- `P/maps/map_structure_014.png` — blue slab = holo-billboard / neon sign board (rooftop half-cover).
- `P/maps/map_structure_012.png` — purple vent/grate = rooftop AC unit (alley cover, MAP_AUDIT.md asks for one every ~350 px).
- `P/maps/map_structure_004.png` — purple trapezoid = rooftop platform.
- `P/maps/map_structure_002.png` — blue hut with doorway = rooftop building block (SOLID cover).
- `P/maps/map_structure_008.png` — pink hut with doorway = neon-lit building block (SOLID cover).
- `P/maps/map_structure_072.png` — pink ring = neon ring sign (visual).
- `P/maps/map_structure_036.png` — purple ring = neon ring sign (visual). (WARNING: 036 looks like a brown hut in the small contact sheet — it is NOT; verified full-size, it is a purple ring. Do not use as a hut.)

**Ancient Temple (5)** — stone kit:
- `P/maps/map_structure_013.png` — tan trapezoid = ziggurat step.
- `P/maps/map_structure_005.png` — tan slab = altar stone.
- `P/maps/map_structure_033.png` — brown hut, orange round window = carved shrine block (SOLID cover, colonnade pillar substitute).
- `P/maps/map_structure_069.png` — brown hut, tan round window = temple block (SOLID cover).
- `P/maps/map_structure_009.png` — orange ring = sun-disc decoration (visual, altar backdrop).

**Airship Fleet (0 new files — shares the Temple set):**
`map_structure_005` (deck plank), `013` (hull wedge), `033` + `069`
(ship cabins, SOLID), `009` (life ring). Sharing 5 files between Temple
and Airship is acceptable — the game already shares crate/barrels/column
across all 10 maps — and the maps stay distinct via layout (disconnected
decks), sky and tiles. The pack contains NO mast, sail, rigging or
wood-plank texture, so those still need procedural shapes or Gemini art.

**Existing-map improvements (4):**
- `P/maps/map_structure_042.png` — dark-blue hut, blue round window = SOLID cover for the **Space Station** rebuild (dark palette match).
- `P/maps/map_structure_051.png` — dark-green hut, green round window = SOLID cover for **Jungle Ruins** (MAP_AUDIT.md spawn-safety patch).
- `P/maps/map_structure_007.png` — green X-crate = SOLID crate variant for **Jungle Ruins** floor cover.
- `P/maps/map_structure_057.png` — orange vent/grate = decor for **Industrial Factory**.

Rejected structures (164): all other files are palette duplicates of
the 7 shapes above (same shape, same or different colour — e.g.
`map_structure_077/149` are byte-identical to `005`). Do not import
duplicates; one file per shape-colour is enough.

### Characters — 5 (select-screen variants ONLY)

- `P/characters/character_001.png` — orange robot trooper
- `P/characters/character_002.png` — cyan robot trooper
- `P/characters/character_003.png` — green robot trooper
- `P/characters/character_004.png` — purple robot trooper
- `P/characters/character_005.png` — tan robot trooper

**Hard limit, do not work around it:** these are FIVE COLOURS OF ONE
STATIC 96×96 FRAME. There are no run, jump, jetpack, aim, shoot or
death frames, no directional sets, and the figure faces the viewer
(front-on robot with backpack), not a side-view soldier. They can ONLY
be used as **character-select portraits / colour variants in the lobby
menu**. They CANNOT replace the animated soldier — the game already has
a 97-frame soldier animation set from the user's first asset pack, and
that stays the in-game player sprite. If a variant is ever shown
in-game, it would need a full animation set drawn to match (not in this
pack) — do not attempt a single-frame player. Rejected: the other 115
character files (same robot, same 5 colours, repeated).

### Weapons — 1 (optional)

- `P/weapons/weapon_001.png` — orange rifle, side view, 128×64.
  OPTIONAL use: world-pickup sprite for the Assault Rifle
  (`weapons.gd` id 0), replacing the coloured text box for that one
  pickup kind. Nothing else in the category is usable: all 120 files
  are the same rifle silhouette with a scope blob in slightly different
  spots/colours — a player could not tell SMG from Shotgun from Sniper
  from Rocket by looking at them. **Weapon STATS must come from
  `weapons.gd` — the pack contains no damage, rate, mag, speed or
  recoil data for any weapon.** Do not invent stats from the art; if a
  new weapon is ever added from this art, give it a full `weapons.gd`
  entry (name, damage, rate, mag, reload, speed, spread, pellets,
  explosive, sound, recoil, shake, auto, life) and a distinct
  silhouette — this pack cannot supply the silhouette. Rejected: the
  other 119 weapon files (indistinguishable duplicates).

### Combat effects — 6

- `P/effects/effect_001.png` — orange sunburst = **explosion** (replaces/augments `assets/effects/explosion1.png`).
- `P/effects/effect_004.png` — gray smoke cloud = **smoke / dust** (replaces/augments `smoke.png`).
- `P/effects/effect_005.png` — yellow lightning bolt = energy-hit / zap effect.
- `P/effects/effect_003.png` — green ring = shockwave ring.
- `P/effects/effect_009.png` — orange ring = shockwave ring (warm variant).
- `P/effects/effect_006.png` — cyan asterisk = hit spark / impact star.

All clean transparency, simple flat shapes that read well at small
sizes and fast motion. They are single frames, not animated sequences —
use as one-shot sprites with scale/fade (the game already animates
explosions that way in `game.gd` `_spawn_explosion`). Rejected: the
other 154 effect files (same 10 designs × palettes — e.g. pink/purple
asterisks and rings that add nothing).

### Pickups — 6

The game (`pickup.gd`) has kinds 1 SMG, 2 Shotgun, 3 Sniper, 4 Rocket,
5 Health (+50), 6 Grenades (+2), currently drawn as a coloured box +
text label. These icons are the cleanest art in the pack (consistent
circular badges, readable at 64×64). Map:

| File | Icon | Use (pickup.gd kind) |
|---|---|---|
| `P/pickups/pickup_007.png` | green cross | kind 5 Health (+50) — primary health icon. |
| `P/pickups/pickup_001.png` | orange cross | kind 5 Health alternate (or high-value health). |
| `P/pickups/pickup_003.png` | green shield | Future armour pickup (not a kind yet — Phase 6 only if armour is added; do not wire to an existing kind). |
| `P/pickups/pickup_002.png` | blue ammo bars | kind 6 Grenades (+2) — closest readable "ammo" glyph; or future ammo pickup. |
| `P/pickups/pickup_005.png` | gold `$` coin | Score/bonus marker (MVP screen / end stats), not a world pickup. |
| `P/pickups/pickup_012.png` | purple star | Rare/special pickup marker (e.g. the pinned centre Sniper/Rocket spot). |

Weapon pickups (kinds 1–4) keep their text labels — the pack has no
distinguishable weapon icons, and a rifle glyph on all four would be
worse than the labels. Rejected: the other 74 pickup files (same 6
icon designs × palettes, plus arrow icons with no in-game meaning).

### UI elements — 0 selected

All 40 rejected. They are generic flat shapes (rounded rects, hexagons,
circles, trapezoids, toggle pills) in random colours, with no text, no
icons and no game-specific elements (no health bar, joystick, weapon
slot, button label). The game already has a consistent built-in UI
(green-accent rounded panels, 56 px touch targets, v2.3) and these
would break that consistency. If Phase 4 wants a panel texture, revisit
— but the current StyleBoxFlat theme is better than any of these.

## REJECTED — summary

| Category | Rejected | Why |
|---|---|---|
| Backgrounds | 7 files | Same scene, duplicate palettes of the selected 13. |
| Characters | 115 files | Same 1 robot × 5 colours, repeated. |
| Weapons | 119 files | Same 1 rifle silhouette; cannot distinguish weapon types. |
| Terrain tiles | 155 files | ~130 are the same blue-blob tile; rest are palette dupes or too semi-transparent (terrain_003 51%, terrain_008 78%). |
| Props | 118 files | Duplicates of the 8 designs; most duplicate existing game decor (crate, barrels, trees) or clash in colour (purple tree, purple torii). |
| Effects | 154 files | Same 10 designs × palettes. |
| Pickups | 74 files | Same 6 icon designs × palettes; arrow icons have no in-game meaning. |
| UI | 40 files | Generic shapes, no text/icons, would break UI consistency. |
| **Total rejected** | **946 files** | |

Rejected props worth naming so nobody re-selects them: `prop_001`
(X-crate — duplicates existing crate), `prop_002` (blue canister —
duplicates barrels), `prop_004` (purple blob tree — wrong colour for
any map), `prop_005` (brown platform — duplicates structure slabs),
`prop_008` (purple-pink torii arch — the only gate shape in the pack,
but purple clashes with the gold/teal Ancient Temple; needs a recolour
or Gemini replacement, do not use as-is), `prop_003` (green lamp —
usable shape, wrong colour for Neon City; left out, `prop_006` covers
the street-lamp role).

## Integration notes for the Phase 5/6 builders

1. **Import ONLY the 54 selected files** (~103 KB). Copy them from
   the pack path above into the project (suggested: `assets/skybrawl/`
   subfolders by category) — do not copy the whole pack (671 KB of
   mostly duplicates is still waste, and the 946 rejected files must
   never reach the APK). Note: `export_presets.cfg` currently excludes
   `gen_assets_v3/*`; keep selected Sky Brawl files OUT of any staging
   folder — put them in their final `assets/` location.
2. **Backgrounds:** add a far parallax layer in `_build_background()`
   (viewport scale, parallax ~0.2–0.3, z_index below the gradient
   hills). One `bg` key per map in `MAPS` pointing at the assigned
   file. On the five POOR-fit day maps, default to the procedural
   gradient (pack image off) unless the map is re-lit. Never stretch
   over the full map. The baked-in platform bars are scenery, not
   platforms — no collision for them, ever.
3. **Tiles:** flatten alpha (composite onto opaque base) and resize to
   128×48 before import; add as `TILE_TEX` indices 10 (Neon City,
   terrain_004), 11 (Ancient Temple, terrain_005), 12 (Airship Fleet,
   terrain_005 fallback — same file is fine, decks differ by layout).
   `terrain_002` is visual-only cloud art, not a `TILE_TEX` entry.
4. **Structures:** new `DECOR_TEX` keys (e.g. `sb_slab_blue`,
   `sb_hut_blue`, `sb_trap_tan`, …). Huts/blocks and the X-crate are
   SOLID — add their keys to `SOLID_DECOR_KINDS` with a collision
   rectangle matching the visible sprite (same pattern as QA-030).
   Slabs, trapezoids, rings and vents are visual dressing unless a map
   design explicitly makes one a platform (then it needs a real
   platform rect in the map's `platforms` list, not just a sprite).
   Structures are 128×128 — scale ×1.0 for cover pieces; do not
   upscale beyond ×1.5 or the flat edges soften.
5. **Hitboxes/collision (general):** the pack ships NO collision data.
   Every solid piece needs a hand-set rectangle: structures = full
   sprite bounds (they are blocky by design); props = trunk/base
   only for the lamp post (`prop_006`: thin pole rect, not the whole
   96×96), cannon (`prop_007`: base rect). Characters/effects/pickups
   need no collision (pickups already have a 22 px circle in
   `pickup.gd`).
6. **Weapon stats:** none in the pack. `weapon_001` (if used) reuses
   the Assault Rifle entry in `weapons.gd` — no new stats needed. Any
   future pack-derived weapon needs a full `weapons.gd` row first.
7. **Characters:** lobby select-screen portraits only (5 colour
   variants). No animation frames exist — do not wire them to the
   player scene.
8. **Effects/pickups:** drop-in sprite swaps in the existing
   explosion/pickup code paths; keep the existing scale/fade/bob
   animation (single frames, no sequences in the pack).
9. **Style mismatch to manage:** pack art is flat vector with thick
   dark outlines and bright candy colours; the game's existing art
   (soldier animation, jungle atlas, procedural tiles) is more
   textured. The selected pieces were chosen where the flat style
   reads as intentional (icons, effects, neon signs, stone blocks).
   On day maps the flat night backgrounds clash hardest — that is why
   five of them are POOR-fit. If a selected piece looks wrong in-game
   after import, prefer dropping it over recolouring the whole map
   around it.
10. **Attribution:** the pack is user-uploaded original generated art
    ("Sky Brawl", 1,000 original PNGs, README states original
    placeholder art). No third-party licence text was included; no
    attribution is required by the pack itself. Keep the pack zip +
    manifest in `~/workspace/user/files/` as the source of truth; the
    project should only ever contain the 54 selected files.

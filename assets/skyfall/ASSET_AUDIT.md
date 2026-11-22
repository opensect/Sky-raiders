# SKYFALL Asset Audit — Sky Raiders (Godot 4.7.2)

- **Pack:** `assets/skyfall/SKYFALL_assets/` (user-shared 2026-11-20, `SKYFALL_assets.zip`)
- **Audited:** 2026-11-20. Method: Python PIL measurements (size, mode, alpha stats,
  corner alpha, opaque bounding box, semi-transparent-pixel brightness) + visual
  inspection of every file on magenta AND dark-green backgrounds (the established
  method from `assets/ASSET_MANIFEST.md` — a dark box or halo shows on one of them).
- **Scope:** read-only audit. No game code touched, no art files modified.
- **Design doc:** `~/workspace/mini-militia-lan/SKYFALL.md` (world 3600×7200 px,
  8 levels × 900 px tall, Vertical CTF, 5v5, 7 power-ups).

## Verdict summary (76 PNGs + 1 README.txt = 77 files)

| Verdict | Count | Meaning |
|---|---|---|
| **USE AS-IS** | **63** | Real transparency, no dark box, no halo. Load and use. |
| **NEEDS SLICING** | **11** | Usable only after cutting (baked text / baked fill level). |
| **SKIP** (reference only) | **2** | Layout/reference posters, not in-game art. |
| **NEEDS BACKGROUND REMOVAL** | **0** | Nothing. Unlike the Jungle/Ironfall packs, no sprite in this pack sits on a solid background that must be removed — every RGBA sprite already has real transparency, and every fully-opaque file is a complete scene/card where the "background" IS the art. |

**No blockers.** Nothing in the pack is unusable, and no file shows a dark box or
dark halo on a contrasting background. The cautions below are design gaps (missing
art for a few mechanics, baked-in labels, wrong-scale skies), not broken files.

### Headline findings

1. **All RGBA sprites have real transparency.** 67 of 76 files are RGBA; all but 8
   of those have transparent corners and 12–88% fully-transparent pixels. The 8
   RGBA files that are 100% opaque are full scenes/cards, not sprites
   (2 skies, concept diagram, mode card, 3 platform slabs, disabled-platform slab).
2. **No dark halo/fringe anywhere.** Semi-transparent pixels are anti-aliasing,
   glow (lightning, extraction-zone rings), or intentional soft shadows (the dark
   ellipse under each character sprite and under each flag). Checked on magenta
   and on dark green — nothing reads as a box.
3. **Roles are NOT visually distinct as characters.** The 8 character sprites are
   the same body/pose; roles differ only by a small chest emblem (arrow / shield /
   crosshair / plus) — pixel diff between roles of the same team is ~1%. Team
   colour (red vs blue) is the only big difference (~45% of pixels). See §6.
4. **Level strips are layout references, not playable art.** All 8 strips have
   baked-in text labels ("LEVEL 1 - Twin Base Camp", "HIDDEN TUNNEL A/B",
   "FALL = LOWER PLATFORM", "ENEMY FLAG", sight lines, "SUMMIT CONTROL ARENA").
   They are exactly half-scale (1800×450 for a 3600×900 level) and show the intended
   platform layout — build the levels from the tile sprites following these strips,
   do not paste the strips in as-is or the labels will show in-game.
5. **HUD bars have baked-in fill levels** (health full green, jetpack ~60% purple,
   flag-carry ~40% yellow). They cannot drive a dynamic HUD as-is — slice out the
   empty frame or draw bars in code like the existing HUD.
6. **Mode card bakes in "5 vs 5"** — conflicts with the current 8-player room cap
   unless the cap is raised for Skyfall (open question in SKYFALL.md).
7. **Missing art for several design elements** — see §9 (no gate-open state, no
   tunnel art, no standalone summit building, no side-view player sprites, no
   96×64 map thumbnail, no rotating-platform art, skies are landscape 1920×1080
   for a 7200-tall vertical world).

---

## 1. Level strips — `levels/` (8 files, all 1800×450, RGB, 100% opaque)

Confirmed half-scale: map is 3600 px wide, each level 900 px tall → strip at
1800×450 is exactly 2× downscale in both axes. All 8 are distinct scenes
(different md5s). All are RGB with baked-in labels — **NEEDS SLICING** (crop the
label bar and annotation text off, or use as layout reference only).

| File | What it shows | Baked-in text / annotations in-game problem |
|---|---|---|
| `level_1_twin_base_camp.png` | Dusk orange sky, pine silhouettes, green ground strip, grey platforms, 2 ladders, crates, red flag left / blue flag right, 2 pickup dots | "LEVEL 1 - Twin Base Camp" + "Starting combat zone" top-left label bar |
| `level_2_broken_cliffs.png` | Pale blue sky, brown cliff spires, small ledges, 2 ladders, falling rocks | "LEVEL 2 - Broken Cliffs" + "Danger zone" label; small red mark near a ledge |
| `level_3_underground_tunnels.png` | Near-black tunnel background, 2 horizontal lamp-lit tunnels joined by a vertical shaft | "LEVEL 3 - Underground Tunnels" + "Flanking routes" label; "HIDDEN TUNNEL A" / "HIDDEN TUNNEL B" bottom corners; red/blue flags at tunnel ends |
| `level_4_hanging_bridge.png` | Blue sky, clouds, long sagging rope bridge with gaps, 2 lower safety platforms | "LEVEL 4 - Hanging Bridge" + "High-risk shortcut" label; "FALL = LOWER PLATFORM" centre text with arrow |
| `level_5_sniper_territory.png` | Dusk pink/blue sky, 2 tall sniper towers (left/right), 3 small platforms, crates | "LEVEL 5 - Sniper Territory" + "Long-range combat" label; "SNIPER A" / "SNIPER B" labels; red/blue sight lines drawn across the scene |
| `level_6_mechanical_ascent.png` | Dark machine room, gears, vertical rails, elevator platforms with up/down arrows, red/yellow dots | "LEVEL 6 - Mechanical Ascent" + "Skill challenge" label; schematic arrows/dots are part of the drawing |
| `level_7_the_last_stand.png` | Dusk arena, wide ground platform, pillars, 3 small platforms, crates, coloured power-up dots | "LEVEL 7 - The Last Stand" + "Main battlefield" label; "SUMMIT CONTROL ARENA" text on the ground platform |
| `level_8_flag_summit.png` | Night purple sky, storm clouds, lightning, central summit building (red roof, 4 lit windows, dark doorway), side platforms | "LEVEL 8 - Flag Summit" + "Final objective" label; "ENEMY FLAG" text on the building |

**Use:** rebuild each level's platforms/colliders from the tile sprites (§4)
following the strip layout; optionally use the strip with the top ~70 px label bar
cropped off as a static parallax backdrop — but the platforms drawn in the strip
would then double with the tile platforms, so reference-only is the safer call.
Do NOT scale a strip 2× and use it as the playable level: the baked text and the
drawn platforms would both show, and collision would have to be hand-matched to
the drawing.

## 2. Tiles — `tiles/` (13 files)

| File | Size | Mode | Transparent | Verdict | Notes |
|---|---|---|---|---|---|
| `platform_solid.png` | 512×96 | RGBA, 100% opaque | 0% | USE AS-IS | Grey brick + green grass top. Solid rectangle — fine as a full-width platform strip; cannot overlap decor (no transparency). Corners are the platform's own edge, not a box. |
| `platform_collapsing.png` | 512×96 | RGBA, 100% opaque | 0% | USE AS-IS | Tan brick with 3 black cracks. Same solid-rectangle note as above. The cracks are the "collapsing" cue. |
| `platform_moving_elevator.png` | 512×96 | RGBA | 16.7% | USE AS-IS | Dark slab, yellow/black hazard stripe on top, 3 bolts, 2 light-blue arrows. Clean transparent corners. |
| `rope_bridge.png` | 512×128 | RGBA | 69.5% | USE AS-IS | Sagging rope with 12 hanging planks + 2 posts. Clean transparency; thin ropes read fine. |
| `trapdoor_closed.png` | 512×96 | RGBA | 22.9% | USE AS-IS | Brown plank trapdoor, yellow top edge, white handle. Clean. |
| `trapdoor_open.png` | 512×96 | RGBA | 23.0% | USE AS-IS (caution) | Near-black slab (only 1.2% pure-black pixels — very dark brown/grey). Reads as an open hole. Place only over dark ground/tunnel: against bright sky it will look like a black rectangle. |
| `wall_block.png` | 128×384 | RGBA, 100% opaque | 0% | USE AS-IS | Tall grey-brick wall. Solid rectangle, fine as a wall. |
| `destructible_barricade.png` | 160×192 | RGBA | 23.0% | USE AS-IS | Wooden planks with diagonal X brace. Clean. Only ONE barricade variant in the pack. |
| `emergency_ladder.png` | 96×384 | RGBA | 51.5% | USE AS-IS | Wooden ladder, 10 rungs, full height. Clean transparency. |
| `sniper_tower.png` | 256×384 | RGBA | 53.9% | USE AS-IS | Watchtower: brown roof, cabin with yellow slit window, X-braced legs. Clean; legs are thin lines, no halo. |
| `summit_gate_closed.png` | 128×384 | RGBA | 34.2% | USE AS-IS | Vertical barred gate, dark frame, red button centre. Gaps between bars ARE transparent (34.2%) — sky shows through correctly. Corners alpha 1–3 (frame fills the corners by design). |
| `summit_control_switch.png` | 256×256 | RGBA | 72.8% | USE AS-IS | Green glowing button on a grey post + dark base. Clean. Single state only (no pressed/lit variant). |
| `wind_zone.png` | 384×384 | RGBA | 0% fully, 100% semi | USE AS-IS | Translucent overlay, mean alpha ~54/255 (~21% opacity), pale with 5 wind arrows. No fully-opaque pixel; the square edge is faintly visible over any background — acceptable as a zone tint, not invisible. |

**Tile scale note:** these are 512×96 platform strips, NOT the 128×48 code-drawn
tiles the other 5 maps use (`assets/tiles/`). They are single-piece platforms
(one strip = one platform), so the map builder places them whole rather than
tiling them. Do not stretch them to other widths without checking — the brick
pattern will distort.

## 3. Power-ups — `powerups/` (15 files)

All 7 types are genuinely distinct art (55–63% of pixels differ between types).
Same circular-badge template, different glyph + colour. Clean on magenta and
green, no box, no halo.

| # | File (256px / 64px) | Glyph | Verdict |
|---|---|---|---|
| 1 | `powerup_1_health_pack(.png / _64.png)` | White cross on green | USE AS-IS |
| 2 | `powerup_2_energy_shield(.png / _64.png)` | White/blue shield on blue | USE AS-IS |
| 3 | `powerup_3_speed_boost(.png / _64.png)` | White lightning bolt on yellow | USE AS-IS |
| 4 | `powerup_4_ammo_crate(.png / _64.png)` | 3 bullets on orange | USE AS-IS |
| 5 | `powerup_5_grenade_pack(.png / _64.png)` | Round grenade/bomb on dark red | USE AS-IS |
| 6 | `powerup_6_jetpack_boost(.png / _64.png)` | Twin nozzles with yellow flames on purple | USE AS-IS (glyph reads a little like binoculars at small size — acceptable placeholder) |
| 7 | `powerup_7_enemy_radar(.png / _64.png)` | Radar rings + sweep on teal | USE AS-IS |

- 256px files: 256×256 RGBA, 31.3% transparent, corners alpha 0, opaque bbox
  9–246 px (badge fills the frame with a small margin). 3.7% semi-transparent
  pixels = anti-aliased badge rim; semi-pixel brightness is low only for the
  grenade icon (98.4% of its semi pixels are dark — that is the dark-red badge
  rim, not a halo; verified visually clean).
- 64px files: 64×64 RGBA, 25.8% transparent, 14.0% semi (normal downscale AA),
  corners alpha 0. **Clean transparent icons, suitable for HUD use as-is** —
  readable at 64 px on magenta, glyphs stay legible.
- `powerups_spritesheet.png` (896×128 RGBA, 7 × 128 px cells, same order as
  power-ups 1–7; cell-vs-icon pixel diff ~8–10/255 = resampling noise only):
  USE AS-IS as an alternative to the 7 individual files. Either the sheet or the
  individual files — do not load both.

## 4. Characters — `characters/` (8 files, all 128×192 RGBA)

| File | Transparent | Verdict |
|---|---|---|
| `player_red_attacker.png`, `player_red_defender.png`, `player_red_sniper.png`, `player_red_support.png` | 41.1% | USE AS-IS (lobby/role-select portraits only — see below) |
| `player_blue_attacker.png`, `player_blue_defender.png`, `player_blue_sniper.png`, `player_blue_support.png` | 41.1% | USE AS-IS (lobby/role-select portraits only — see below) |

- All 8: corners alpha 0, opaque bbox 7–120 × 3–190 px, consistent framing
  (identical bbox on all 8 — same pose, same position in frame).
- Real transparency, no dark box, no halo on magenta or green. The soft dark
  ellipse under the feet is an intentional ground shadow (semi-transparent dark
  pixels), not a fringe.
- **Roles differ only by the chest emblem** (attacker = up arrow, defender =
  shield, sniper = crosshair, support = plus). Pixel diff between roles of the
  same team is 0.4–1.7%; team colour swap (red↔blue) changes 45.3% of pixels.
  In-game, a sniper and an attacker will look identical except for a ~20 px
  emblem — do not rely on these to tell roles apart at combat distance.
- **Front-facing flat figures, single static pose, no animation frames, no
  jetpack, no weapon.** The game is a side-view shooter with its own animated
  player sprites — these cannot be dropped in as player sprites. Use them for
  the lobby / role-select screen and team banners only; the in-game player art
  must stay the existing system (or be drawn new).
- Style mismatch note: these are simple flat vector figures (rounded helmet,
  visor, block body). The existing game characters are drawn in the same bold
  cartoon style, so they sit acceptably in UI, but they are visibly simpler
  than the Ironfall/Jungle art.

## 5. Flags & extraction zones — `flags/` (6 files, all 256×256 RGBA)

| File | Transparent | Verdict | Notes |
|---|---|---|---|
| `flag_red.png` / `flag_blue.png` | 74.7% | USE AS-IS | Pole with gold finial, waving swallow-tail cloth, white star. Clean; shadow ellipse under the pole is intentional. Red/blue differ only in cloth colour (15.6% of pixels). |
| `flag_red_dropped.png` / `flag_blue_dropped.png` | 87.9% | USE AS-IS | Fallen flag lying diagonally, pole on the ground, cloth without star. Clean. |
| `extraction_zone_red.png` / `extraction_zone_blue.png` | 68.8% | USE AS-IS | Concentric ground rings + 3 upward chevrons, team colour. Only 2.0% fully opaque — almost entirely thin lines + soft glow. Visible on both test backgrounds but subtle; in a busy scene it may need a stronger glow or a pulsing scale to read as a zone. Red/blue differ in colour only (31.2% of pixels). |

No "carried flag" art (flag on a player's back) exists in the pack. Reuse the
standing flag scaled down, or the existing v3.7 `assets/effects/flag_red.png` /
`flag_blue.png` (72×96), for the carrier indicator.

## 6. Hazards — `hazards/` (4 files)

| File | Size | Mode | Transparent | Verdict | Notes |
|---|---|---|---|---|---|
| `falling_rock.png` | 192×192 | RGBA | 47.9% | USE AS-IS | Faceted brown boulder, thick dark outline. Clean. |
| `falling_rock_motion.png` | 192×384 | RGBA | 72.3% | USE AS-IS | Smaller boulder at the bottom + 3 pale motion dashes above it (the fall trail). Clean. |
| `summit_storm_lightning.png` | 192×512 | RGBA | 51.5% | USE AS-IS | Yellow lightning bolt, tall. 36.1% semi-transparent pixels = soft pale glow around the bolt — reads as glow on both backgrounds, not a box. |
| `platform_disabled_by_storm.png` | 512×96 | RGBA, 100% opaque | 0% | USE AS-IS | Dark brick slab with light-blue lightning cracks and a pale-blue border. Solid rectangle like the other platform slabs; the pale border is the "disabled" cue, not a background leak. |

## 7. Map & skies — `map/` (4 files)

| File | Size | Mode | Verdict | Notes |
|---|---|---|---|---|
| `bg_sky_dusk.png` | 1920×1080 | RGBA, 100% opaque | USE AS-IS (with scale caveat) | Dusk gradient (dark blue top → orange horizon). Full scene, no transparency needed. **Scale problem:** 1920×1080 landscape for a 3600×7200 vertical world — it cannot cover the map without vertical tiling/stretching. Use as a parallax layer or stretch per-level, or draw a code gradient per level. |
| `bg_sky_storm.png` | 1920×1080 | RGBA, 100% opaque | USE AS-IS (same caveat) | Dark storm gradient (near-black top → purple-grey). Same scale problem as dusk. |
| `skyfall_full_map_overview.png` | 1020×1800 | RGB | SKIP (reference) | Vertical stack of all 8 level strips with L1–L8 side labels and red/blue ascent arrows. White corners (top two corners are white). A poster, not in-game art. Keep as the layout reference for the map builder. |
| `skyfall_concept_diagram.png` | 600×1200 | RGBA, 100% opaque | SKIP (reference) | Tower silhouette with level names 1–8 and red/blue arrows. Reference only. |

## 8. UI — `ui/` (18 files)

| File | Size | Mode | Transparent | Verdict | Notes |
|---|---|---|---|---|---|
| `role_icon_red/blue_attacker/defender/sniper/support.png` (8) | 128×128 | RGBA | 26.9% | USE AS-IS | Team-coloured circle, white ring, white role glyph (same 4 glyphs as the character chest emblems). Roles genuinely differ (18–24% of pixels). Semi-transparent pixels are pure white (the ring's soft edge) — no halo. |
| `powerup_slot_1/2/3.png` | 128×128 | RGBA | 8.9% fully, 91.1% semi | USE AS-IS | Dark rounded square, translucent fill (mean alpha ~173/255 — the game behind shows through slightly), number 1/2/3. Slots differ only by the digit (3.0% of pixels). Usable as HUD slot backgrounds. |
| `team_banner_red.png` / `team_banner_blue.png` | 640×160 | RGBA | 8.2% | USE AS-IS | Ribbon banner with baked-in "RED" / "BLUE" text. Clean transparency. |
| `title_logo.png` | 1280×480 | RGBA | 80.7% | USE AS-IS | "SKYFALL" gold + "THE LAST ASCENT" white subtitle. Clean, transparent background. |
| `mode_card_vertical_ctf.png` | 1024×512 | RGBA, 100% opaque | 0% | USE AS-IS (caution) | Card art: dusk gradient, tower silhouette, "VERTICAL CAPTURE THE FLAG - 5 vs 5" baked in. Opaque is correct for a card. Two cautions: (a) a thin white strip along the bottom edge (the card art's own margin); (b) the baked "5 vs 5" text conflicts with the 8-player room cap unless the cap is raised for Skyfall. |
| `hud_health_bar.png` | 512×64 | RGBA | 4.2% | NEEDS SLICING | Full green fill baked in. Frame + fill are one image — cannot show damage without slicing the fill out or redrawing. |
| `hud_jetpack_fuel_bar.png` | 512×64 | RGBA | 4.2% | NEEDS SLICING | ~60% purple fill baked in. Same problem. |
| `hud_flag_carry_bar.png` | 512×64 | RGBA | 4.2% | NEEDS SLICING | ~40% yellow fill baked in. Same problem. |

For the HUD bars, the established pattern in this game is code-drawn bars (the
existing HUD draws its own). Slicing the empty frame from these three images is
possible (the dark track + rounded frame is identical in all three) but the
simplest correct call is: use them as a visual reference for colours and draw
the bars in code.

---

## 9. Missing art / things that would look wrong in-game

Checked against SKYFALL.md's mechanics list. Art that EXISTS is marked ✓;
missing or partial is marked ✗/◐.

| Design element | Art in pack? | Gap / what to do |
|---|---|---|
| Summit gate | ◐ `summit_gate_closed.png` only | **No open-state art.** The gate "opens after a timed mechanism" — needs a `summit_gate_open` variant (bars raised / doorway clear) or the closed gate must be hidden/swapped in code. |
| Summit control switch | ✓ `summit_control_switch.png` | Single state only (green button). No pressed/activated variant — fine if code tints it or swaps in the same sprite with a glow. |
| Moving elevators | ◐ `platform_moving_elevator.png` only | One static slab. No shaft/rail art, no cabin, no up/down state. Level 6 strip shows rails + arrows schematically — rebuild rails in code or draw them. |
| Emergency ladders | ✓ `emergency_ladder.png` | Covered. |
| Rope bridges | ✓ `rope_bridge.png` | Covered (single 512 px span; longer spans need 2+ placed end-to-end). |
| Collapsing platforms | ✓ `platform_collapsing.png` | Covered (cracks baked in; the "about to break" state must come from code — shake/fade — there is no second, more-cracked frame). |
| Trap doors | ✓ open + closed | Covered, with the `trapdoor_open` sky-contrast caution (§2). |
| Wind zones | ✓ `wind_zone.png` | Covered as a faint overlay; the square edge is faintly visible. |
| Sniper towers | ✓ `sniper_tower.png` | Covered. Level 5 strip also draws its own towers — use the sprite, not the strip. |
| Falling rocks | ✓ `falling_rock.png` + motion variant | Covered. |
| Summit Storm | ✓ lightning + disabled platform | Covered. |
| Hidden tunnels | ✗ | **No tunnel art at all.** Level 3 is two lamp-lit tunnels, but the pack has no tunnel entrance/exit, mouth, or tube sprite. The strip shows the layout only. Needs new art (or reuse the Ironfall cave slices `if_cave.png` / `if_cavern.png`). |
| Summit building | ✗ | **No standalone summit building.** The only summit structure is baked into the level 8 strip (with "ENEMY FLAG" text on it). Needs new art, or rebuild from `wall_block` + `summit_gate_closed` + a drawn roof. |
| Rotating platforms (level 6) | ✗ | Named in the design ("rotating platforms") — no art. Reuse `platform_moving_elevator.png` or draw new. |
| Destructible routes | ◐ one barricade | One `destructible_barricade.png` only; "certain wooden bridges and barricades" (plural) implies more than one destructible prop. Reuse the one, or draw variants. |
| Side-view player sprites | ✗ | Characters are front-facing portraits only (§4). In-game players must use the existing player art. |
| Map thumbnail (96×64) | ✗ | Every other map has `assets/thumbs/thumb_*.png` (96×64, no text). Skyfall has none — the mode card (1024×512) is not a thumbnail. Draw one from the level 1 strip or the title logo. |
| Vertical sky background | ◐ | Both skies are 1920×1080 landscape for a 3600×7200 vertical world (§7). Needs vertical tiling, per-level gradients, or new tall sky art. |
| Carried-flag visual | ✗ | No flag-on-back sprite (§5). Reuse a scaled standing flag or the v3.7 effect flags. |
| HUD bars (dynamic) | ◐ | Baked fill levels (§8) — slice or draw in code. |
| "5 vs 5" on mode card | ⚠ | Baked text conflicts with the 8-player room cap until the cap question is settled. |

### Things that would look wrong if used naively

1. **Pasting any level strip in as a level background** — baked labels and
   drawn platforms would show in-game (see §1). Reference only.
2. **`trapdoor_open.png` floating on sky** — reads as a black rectangle; keep
   it over dark ground/tunnel.
3. **`platform_solid/collapsing/wall_block` stretched** — they are solid
   rectangles; stretching changes the brick scale. Place whole, or slice a
   128×48 repeating tile from them.
4. **Characters as in-game sprites** — front-facing, static, no weapon/jetpack;
   they would look wrong side-on and cannot animate. Lobby only.
5. **HUD bars as dynamic bars** — fill level is baked; health would never appear
   to drop.
6. **Extraction zones at small size** — only 2% fully-opaque pixels (thin rings);
   at 256 px on a busy background they are subtle. Consider a pulsing scale or a
   stronger glow in code.
7. **Wind zone square edge** — faintly visible; acceptable, but do not stack
   several overlapping or the edges will show as a grid.

---

## 10. Preload path list (for the game code)

Base: `res://assets/skyfall/SKYFALL_assets/`. Load only what the map uses —
the pack is placeholder art, so prefer the individual files over the spritesheet
(or the sheet over the individuals, not both).

### Levels (reference — do NOT preload for in-game use; layout reference only)
```
res://assets/skyfall/SKYFALL_assets/levels/level_1_twin_base_camp.png
res://assets/skyfall/SKYFALL_assets/levels/level_2_broken_cliffs.png
res://assets/skyfall/SKYFALL_assets/levels/level_3_underground_tunnels.png
res://assets/skyfall/SKYFALL_assets/levels/level_4_hanging_bridge.png
res://assets/skyfall/SKYFALL_assets/levels/level_5_sniper_territory.png
res://assets/skyfall/SKYFALL_assets/levels/level_6_mechanical_ascent.png
res://assets/skyfall/SKYFALL_assets/levels/level_7_the_last_stand.png
res://assets/skyfall/SKYFALL_assets/levels/level_8_flag_summit.png
```

### Tiles
```
res://assets/skyfall/SKYFALL_assets/tiles/platform_solid.png
res://assets/skyfall/SKYFALL_assets/tiles/platform_collapsing.png
res://assets/skyfall/SKYFALL_assets/tiles/platform_moving_elevator.png
res://assets/skyfall/SKYFALL_assets/tiles/rope_bridge.png
res://assets/skyfall/SKYFALL_assets/tiles/trapdoor_closed.png
res://assets/skyfall/SKYFALL_assets/tiles/trapdoor_open.png
res://assets/skyfall/SKYFALL_assets/tiles/wall_block.png
res://assets/skyfall/SKYFALL_assets/tiles/destructible_barricade.png
res://assets/skyfall/SKYFALL_assets/tiles/emergency_ladder.png
res://assets/skyfall/SKYFALL_assets/tiles/sniper_tower.png
res://assets/skyfall/SKYFALL_assets/tiles/summit_gate_closed.png
res://assets/skyfall/SKYFALL_assets/tiles/summit_control_switch.png
res://assets/skyfall/SKYFALL_assets/tiles/wind_zone.png
```

### Power-ups (individual files; or the spritesheet instead — not both)
```
res://assets/skyfall/SKYFALL_assets/powerups/powerup_1_health_pack.png
res://assets/skyfall/SKYFALL_assets/powerups/powerup_2_energy_shield.png
res://assets/skyfall/SKYFALL_assets/powerups/powerup_3_speed_boost.png
res://assets/skyfall/SKYFALL_assets/powerups/powerup_4_ammo_crate.png
res://assets/skyfall/SKYFALL_assets/powerups/powerup_5_grenade_pack.png
res://assets/skyfall/SKYFALL_assets/powerups/powerup_6_jetpack_boost.png
res://assets/skyfall/SKYFALL_assets/powerups/powerup_7_enemy_radar.png
res://assets/skyfall/SKYFALL_assets/powerups/powerup_1_health_pack_64.png
res://assets/skyfall/SKYFALL_assets/powerups/powerup_2_energy_shield_64.png
res://assets/skyfall/SKYFALL_assets/powerups/powerup_3_speed_boost_64.png
res://assets/skyfall/SKYFALL_assets/powerups/powerup_4_ammo_crate_64.png
res://assets/skyfall/SKYFALL_assets/powerups/powerup_5_grenade_pack_64.png
res://assets/skyfall/SKYFALL_assets/powerups/powerup_6_jetpack_boost_64.png
res://assets/skyfall/SKYFALL_assets/powerups/powerup_7_enemy_radar_64.png
res://assets/skyfall/SKYFALL_assets/powerups/powerups_spritesheet.png
```

### Characters (lobby / role-select only)
```
res://assets/skyfall/SKYFALL_assets/characters/player_red_attacker.png
res://assets/skyfall/SKYFALL_assets/characters/player_red_defender.png
res://assets/skyfall/SKYFALL_assets/characters/player_red_sniper.png
res://assets/skyfall/SKYFALL_assets/characters/player_red_support.png
res://assets/skyfall/SKYFALL_assets/characters/player_blue_attacker.png
res://assets/skyfall/SKYFALL_assets/characters/player_blue_defender.png
res://assets/skyfall/SKYFALL_assets/characters/player_blue_sniper.png
res://assets/skyfall/SKYFALL_assets/characters/player_blue_support.png
```

### Flags & extraction zones
```
res://assets/skyfall/SKYFALL_assets/flags/flag_red.png
res://assets/skyfall/SKYFALL_assets/flags/flag_blue.png
res://assets/skyfall/SKYFALL_assets/flags/flag_red_dropped.png
res://assets/skyfall/SKYFALL_assets/flags/flag_blue_dropped.png
res://assets/skyfall/SKYFALL_assets/flags/extraction_zone_red.png
res://assets/skyfall/SKYFALL_assets/flags/extraction_zone_blue.png
```

### Hazards
```
res://assets/skyfall/SKYFALL_assets/hazards/falling_rock.png
res://assets/skyfall/SKYFALL_assets/hazards/falling_rock_motion.png
res://assets/skyfall/SKYFALL_assets/hazards/summit_storm_lightning.png
res://assets/skyfall/SKYFALL_assets/hazards/platform_disabled_by_storm.png
```

### Map & skies
```
res://assets/skyfall/SKYFALL_assets/map/bg_sky_dusk.png
res://assets/skyfall/SKYFALL_assets/map/bg_sky_storm.png
```
(Reference only — do not preload in-game: `map/skyfall_full_map_overview.png`,
`map/skyfall_concept_diagram.png`.)

### UI
```
res://assets/skyfall/SKYFALL_assets/ui/role_icon_red_attacker.png
res://assets/skyfall/SKYFALL_assets/ui/role_icon_red_defender.png
res://assets/skyfall/SKYFALL_assets/ui/role_icon_red_sniper.png
res://assets/skyfall/SKYFALL_assets/ui/role_icon_red_support.png
res://assets/skyfall/SKYFALL_assets/ui/role_icon_blue_attacker.png
res://assets/skyfall/SKYFALL_assets/ui/role_icon_blue_defender.png
res://assets/skyfall/SKYFALL_assets/ui/role_icon_blue_sniper.png
res://assets/skyfall/SKYFALL_assets/ui/role_icon_blue_support.png
res://assets/skyfall/SKYFALL_assets/ui/powerup_slot_1.png
res://assets/skyfall/SKYFALL_assets/ui/powerup_slot_2.png
res://assets/skyfall/SKYFALL_assets/ui/powerup_slot_3.png
res://assets/skyfall/SKYFALL_assets/ui/team_banner_red.png
res://assets/skyfall/SKYFALL_assets/ui/team_banner_blue.png
res://assets/skyfall/SKYFALL_assets/ui/title_logo.png
res://assets/skyfall/SKYFALL_assets/ui/mode_card_vertical_ctf.png
```
(HUD bars `ui/hud_health_bar.png`, `ui/hud_jetpack_fuel_bar.png`,
`ui/hud_flag_carry_bar.png` — slice or use as colour reference only, §8.)

---

## 11. Per-file verdict table (all 76 PNGs)

| File | Size | Mode | Transparent % | Verdict | One-line reason |
|---|---|---|---|---|---|
| levels/level_1_twin_base_camp.png | 1800×450 | RGB | 0 | NEEDS SLICING | Half-scale layout strip; baked "LEVEL 1" label bar — reference only |
| levels/level_2_broken_cliffs.png | 1800×450 | RGB | 0 | NEEDS SLICING | Half-scale layout strip; baked "LEVEL 2" label — reference only |
| levels/level_3_underground_tunnels.png | 1800×450 | RGB | 0 | NEEDS SLICING | Half-scale layout strip; baked labels + "HIDDEN TUNNEL A/B" — reference only |
| levels/level_4_hanging_bridge.png | 1800×450 | RGB | 0 | NEEDS SLICING | Half-scale layout strip; baked "FALL = LOWER PLATFORM" text — reference only |
| levels/level_5_sniper_territory.png | 1800×450 | RGB | 0 | NEEDS SLICING | Half-scale layout strip; baked "SNIPER A/B" + sight lines — reference only |
| levels/level_6_mechanical_ascent.png | 1800×450 | RGB | 0 | NEEDS SLICING | Half-scale schematic strip; baked label + schematic arrows — reference only |
| levels/level_7_the_last_stand.png | 1800×450 | RGB | 0 | NEEDS SLICING | Half-scale layout strip; baked "SUMMIT CONTROL ARENA" text — reference only |
| levels/level_8_flag_summit.png | 1800×450 | RGB | 0 | NEEDS SLICING | Half-scale layout strip; baked "ENEMY FLAG" text on building — reference only |
| tiles/platform_solid.png | 512×96 | RGBA* | 0 | USE AS-IS | Solid brick+grass platform strip, opaque by design |
| tiles/platform_collapsing.png | 512×96 | RGBA* | 0 | USE AS-IS | Solid cracked-brick platform strip, opaque by design |
| tiles/platform_moving_elevator.png | 512×96 | RGBA | 16.7 | USE AS-IS | Clean transparent corners; hazard stripe + arrows |
| tiles/rope_bridge.png | 512×128 | RGBA | 69.5 | USE AS-IS | Clean transparency; 12 planks + posts |
| tiles/trapdoor_closed.png | 512×96 | RGBA | 22.9 | USE AS-IS | Clean plank trapdoor with handle |
| tiles/trapdoor_open.png | 512×96 | RGBA | 23.0 | USE AS-IS | Near-black "hole" slab — keep over dark ground, not sky |
| tiles/wall_block.png | 128×384 | RGBA* | 0 | USE AS-IS | Solid tall brick wall, opaque by design |
| tiles/destructible_barricade.png | 160×192 | RGBA | 23.0 | USE AS-IS | Clean plank barricade with X brace; only one variant |
| tiles/emergency_ladder.png | 96×384 | RGBA | 51.5 | USE AS-IS | Clean full-height ladder |
| tiles/sniper_tower.png | 256×384 | RGBA | 53.9 | USE AS-IS | Clean watchtower; thin legs, no halo |
| tiles/summit_gate_closed.png | 128×384 | RGBA | 34.2 | USE AS-IS | Bar gaps are transparent; no open-state variant exists |
| tiles/summit_control_switch.png | 256×256 | RGBA | 72.8 | USE AS-IS | Clean green button on post; single state only |
| tiles/wind_zone.png | 384×384 | RGBA | 0 fully / 100 semi | USE AS-IS | Faint translucent overlay (mean alpha ~54); square edge faintly visible |
| powerups/powerup_1_health_pack.png | 256×256 | RGBA | 31.3 | USE AS-IS | Clean green cross badge |
| powerups/powerup_1_health_pack_64.png | 64×64 | RGBA | 25.8 | USE AS-IS | Clean HUD-size icon, glyph legible |
| powerups/powerup_2_energy_shield.png | 256×256 | RGBA | 31.3 | USE AS-IS | Clean blue shield badge |
| powerups/powerup_2_energy_shield_64.png | 64×64 | RGBA | 25.8 | USE AS-IS | Clean HUD-size icon |
| powerups/powerup_3_speed_boost.png | 256×256 | RGBA | 31.3 | USE AS-IS | Clean yellow bolt badge |
| powerups/powerup_3_speed_boost_64.png | 64×64 | RGBA | 25.8 | USE AS-IS | Clean HUD-size icon |
| powerups/powerup_4_ammo_crate.png | 256×256 | RGBA | 31.3 | USE AS-IS | Clean orange bullets badge |
| powerups/powerup_4_ammo_crate_64.png | 64×64 | RGBA | 25.8 | USE AS-IS | Clean HUD-size icon |
| powerups/powerup_5_grenade_pack.png | 256×256 | RGBA | 31.3 | USE AS-IS | Clean dark-red grenade badge |
| powerups/powerup_5_grenade_pack_64.png | 64×64 | RGBA | 25.8 | USE AS-IS | Clean HUD-size icon |
| powerups/powerup_6_jetpack_boost.png | 256×256 | RGBA | 31.3 | USE AS-IS | Clean purple nozzles badge; glyph reads slightly like binoculars |
| powerups/powerup_6_jetpack_boost_64.png | 64×64 | RGBA | 25.8 | USE AS-IS | Clean HUD-size icon |
| powerups/powerup_7_enemy_radar.png | 256×256 | RGBA | 31.3 | USE AS-IS | Clean teal radar badge |
| powerups/powerup_7_enemy_radar_64.png | 64×64 | RGBA | 25.8 | USE AS-IS | Clean HUD-size icon |
| powerups/powerups_spritesheet.png | 896×128 | RGBA | 23.9 | USE AS-IS | 7×128 px cells matching icons 1–7; use instead of individuals, not both |
| characters/player_red_attacker.png | 128×192 | RGBA | 41.1 | USE AS-IS | Clean portrait; lobby only — role = chest arrow emblem only |
| characters/player_red_defender.png | 128×192 | RGBA | 41.1 | USE AS-IS | Clean portrait; lobby only — role = chest shield emblem only |
| characters/player_red_sniper.png | 128×192 | RGBA | 41.1 | USE AS-IS | Clean portrait; lobby only — role = chest crosshair emblem only |
| characters/player_red_support.png | 128×192 | RGBA | 41.1 | USE AS-IS | Clean portrait; lobby only — role = chest plus emblem only |
| characters/player_blue_attacker.png | 128×192 | RGBA | 41.1 | USE AS-IS | Clean portrait; lobby only — role = chest arrow emblem only |
| characters/player_blue_defender.png | 128×192 | RGBA | 41.1 | USE AS-IS | Clean portrait; lobby only — role = chest shield emblem only |
| characters/player_blue_sniper.png | 128×192 | RGBA | 41.1 | USE AS-IS | Clean portrait; lobby only — role = chest crosshair emblem only |
| characters/player_blue_support.png | 128×192 | RGBA | 41.1 | USE AS-IS | Clean portrait; lobby only — role = chest plus emblem only |
| flags/flag_red.png | 256×256 | RGBA | 74.7 | USE AS-IS | Clean pole flag, red cloth + star |
| flags/flag_blue.png | 256×256 | RGBA | 74.7 | USE AS-IS | Clean pole flag, blue cloth + star |
| flags/flag_red_dropped.png | 256×256 | RGBA | 87.9 | USE AS-IS | Clean fallen flag, no star on cloth |
| flags/flag_blue_dropped.png | 256×256 | RGBA | 87.9 | USE AS-IS | Clean fallen flag, no star on cloth |
| flags/extraction_zone_red.png | 256×256 | RGBA | 68.8 | USE AS-IS | Thin red rings + chevrons; subtle — may need pulse/glow in code |
| flags/extraction_zone_blue.png | 256×256 | RGBA | 68.8 | USE AS-IS | Thin blue rings + chevrons; subtle — may need pulse/glow in code |
| hazards/falling_rock.png | 192×192 | RGBA | 47.9 | USE AS-IS | Clean boulder, thick outline |
| hazards/falling_rock_motion.png | 192×384 | RGBA | 72.3 | USE AS-IS | Clean boulder + motion-dash trail |
| hazards/summit_storm_lightning.png | 192×512 | RGBA | 51.5 | USE AS-IS | Clean bolt; soft glow fringe reads as glow, not a box |
| hazards/platform_disabled_by_storm.png | 512×96 | RGBA* | 0 | USE AS-IS | Solid dark slab, light-blue cracks + border = disabled cue |
| map/bg_sky_dusk.png | 1920×1080 | RGBA* | 0 | USE AS-IS | Full dusk gradient; landscape size — needs vertical tiling for 7200 px world |
| map/bg_sky_storm.png | 1920×1080 | RGBA* | 0 | USE AS-IS | Full storm gradient; same vertical-scale caveat |
| map/skyfall_full_map_overview.png | 1020×1800 | RGB | 0 | SKIP | Reference poster (stacked strips + labels); not in-game art |
| map/skyfall_concept_diagram.png | 600×1200 | RGBA* | 0 | SKIP | Reference tower diagram; not in-game art |
| ui/role_icon_red_attacker.png | 128×128 | RGBA | 26.9 | USE AS-IS | Clean red circle, white arrow glyph |
| ui/role_icon_red_defender.png | 128×128 | RGBA | 26.9 | USE AS-IS | Clean red circle, white shield glyph |
| ui/role_icon_red_sniper.png | 128×128 | RGBA | 26.9 | USE AS-IS | Clean red circle, white crosshair glyph |
| ui/role_icon_red_support.png | 128×128 | RGBA | 26.9 | USE AS-IS | Clean red circle, white plus glyph |
| ui/role_icon_blue_attacker.png | 128×128 | RGBA | 26.9 | USE AS-IS | Clean blue circle, white arrow glyph |
| ui/role_icon_blue_defender.png | 128×128 | RGBA | 26.9 | USE AS-IS | Clean blue circle, white shield glyph |
| ui/role_icon_blue_sniper.png | 128×128 | RGBA | 26.9 | USE AS-IS | Clean blue circle, white crosshair glyph |
| ui/role_icon_blue_support.png | 128×128 | RGBA | 26.9 | USE AS-IS | Clean blue circle, white plus glyph |
| ui/powerup_slot_1.png | 128×128 | RGBA | 8.9 | USE AS-IS | Translucent dark slot, number 1 |
| ui/powerup_slot_2.png | 128×128 | RGBA | 8.9 | USE AS-IS | Translucent dark slot, number 2 |
| ui/powerup_slot_3.png | 128×128 | RGBA | 8.9 | USE AS-IS | Translucent dark slot, number 3 |
| ui/team_banner_red.png | 640×160 | RGBA | 8.2 | USE AS-IS | Clean red ribbon, "RED" baked in |
| ui/team_banner_blue.png | 640×160 | RGBA | 8.2 | USE AS-IS | Clean blue ribbon, "BLUE" baked in |
| ui/title_logo.png | 1280×480 | RGBA | 80.7 | USE AS-IS | Clean gold "SKYFALL" + subtitle, transparent bg |
| ui/mode_card_vertical_ctf.png | 1024×512 | RGBA* | 0 | USE AS-IS | Card art; baked "5 vs 5" conflicts with 8-player cap; thin white bottom strip |
| ui/hud_health_bar.png | 512×64 | RGBA | 4.2 | NEEDS SLICING | Full green fill baked in — cannot show damage as-is |
| ui/hud_jetpack_fuel_bar.png | 512×64 | RGBA | 4.2 | NEEDS SLICING | ~60% purple fill baked in — slice frame or draw in code |
| ui/hud_flag_carry_bar.png | 512×64 | RGBA | 4.2 | NEEDS SLICING | ~40% yellow fill baked in — slice frame or draw in code |

\* RGBA mode but alpha 255 on every pixel (fully opaque file).

---

## 12. Bottom line for the map builder

- **Start with:** all 13 tiles, the 7 power-up 64 px icons (HUD) + 256 px (world
  pickups), flags + extraction zones, hazards, role icons / slots / banners /
  title logo, and one sky as a parallax layer.
- **Do not use as-is:** the 8 level strips (labels baked in — rebuild from tiles
  using the strips as the layout plan), the 3 HUD bars (fill baked in), the map
  overview / concept diagram (reference posters).
- **Draw or borrow before the map is complete:** gate-open state, tunnel
  entrance/mouth art (or reuse Ironfall cave slices), standalone summit building,
  96×64 map thumbnail, rotating-platform art, a carried-flag visual, and a tall
  vertical sky (or per-level code gradients). The in-game player keeps the
  existing player art — the 8 character sprites are lobby portraits only.
- **No background-removal work is needed on any file** — the pack's transparency
  is already real, verified on magenta and dark green with no dark box on any
  sprite.

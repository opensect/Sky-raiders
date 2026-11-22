# v3.2 Theme Spec — "NEON ARENA" (totally new look)

Status: Phase 1 (design + investigation). Written 2026-11-19 by Worker 1.
Version: v3.2 / versionCode 10. Previous look: v3.1 (green-accent `#21a652`,
rounded 10–18 px panels, default Godot font, procedural gradient sky).
The new look must be unmistakably different at a glance — and it is:
**cyan-on-navy sci-fi, chamfered (cut) corners, Orbitron/Rajdhani type,
real arena artwork background.** Proof screenshot (demo menu built with
this exact stack): `~/workspace/mini-militia-lan-v32-proof/gohud_demo_scifi_menu.png`
— compare with the v3.1 baseline in the same folder (`v31_menu_baseline.png`).

## 1. External libraries used (user requirement: USE external libraries)

### 1a. gohud — the UI library (REQUIRED, installed, verified working)
- **Name:** gohud — GUI, HUD and UI/UX kit for Godot 4
- **Version:** 1.3.0 (2026-10-06). **Licence:** MIT, Copyright (c) 2026 JaeHo Song.
  Full text: `res://addons/gohud/LICENSE`. Third-party notices:
  `res://addons/gohud/THIRD_PARTY_NOTICES.md`.
- **Source:** https://github.com/thruthesky/gohud.git (cloned 2026-11-19,
  `--depth 1`; full clone kept at `/tmp/gohud` for restore).
  Docs: https://thruthesky.github.io/gohud/ · Asset Store: "Gohud" by WITHCENTER.
- **Requirements:** Godot 4.7+ (game is on 4.7.2 — `GoUi.engine_supported()`
  returns `true`; `GoUi.MIN_ENGINE = [4, 7]`).
- **Installed:** `res://addons/gohud/` — **lean runtime subset, 11 MB, 681 files**
  (full repo is 98 MB). Installed: `plugin.cfg`, `plugin.gd`, `core/`,
  `widgets/`, `services/`, `i18n/`, `themes/` (see exclusions below),
  `icons/default/` + `icons/game/` (+ `gohud_icons.tres`, `gohud_icons_game.tres`),
  `assets/fonts/` (baloo2, cinzel, nunito, roboto), `assets/dark/`,
  `assets/light/`, `assets/scifi_dark/`, `assets/scifi_light/`,
  `LICENSE`, `THIRD_PARTY_NOTICES.md`, `CHANGELOG.md`.
- **Excluded (deliberate, to keep the APK lean):** `www/`, `examples/`,
  `tests/`, `docs/`, `skills/`, `tools/`, `assets/arcade_*`, `assets/comic_*`,
  `assets/kids_*`, `assets/material_*`, `assets/medieval_*`,
  `assets/fonts/noto_sans_cjk/`, `icons/library/` (1000-icon set, 7.9 MB),
  `icons/arcade_light/`, `icons/medieval/`, and the arcade/comic/kids/
  material/medieval preset + theme + skin files. **Consequence: only the
  `scifi_dark`, `scifi_light`, `default_dark`, `default_light` presets work
  in this install.** `GoThemePresets.ids()` returns exactly those four.
  Do NOT call `use_preset()` with any other id — its `.tres` file is absent
  and the theme load will fail. To restore a preset, copy its files back
  from `/tmp/gohud` (or the GitHub repo) — preset `.tres` in
  `themes/presets/`, theme in `themes/gohud_<id>.tres`, skin in
  `themes/skins/`, art in `assets/<id>/`, icons in `icons/<id>/`.
- **Install gotcha found and fixed (record for the next worker):**
  `widgets/go_bar.gd:450` does `GoUi.skin() as GoSkinArcade` — a parse-time
  type reference. Excluding `themes/skins/go_skin_arcade.gd` broke
  compilation of `go_bar.gd` ("Could not find type GoSkinArcade",
  cascading "Failed to compile depended scripts"). The file was restored
  (`themes/skins/go_skin_arcade.gd` + `.uid` only — its arcade PNG assets
  are still excluded; it only `load()`s them at runtime if the arcade skin
  is actually used, which it never is). **Lesson: never delete a skin
  `*.gd` — only theme/preset `.tres` files and asset dirs are safe to trim.**
- **Verified in the real project (2026-11-19, Godot 4.7.2):**
  - `godot --headless --path . --import` — exit 0, **0 script errors**.
  - Smoke run (`/tmp/gohud_smoke.gd`): `GoUi.VERSION = 1.3.0`,
    `engine_supported = true`, `use_preset(SCIFI_DARK)` ok,
    `GoHudButton` / `GoHudCard` / `GoBar` / `GoSurface` / `Button` all
    construct, `main.tscn` instantiates with gohud present, fonts load.
  - One-screen proof: a menu screen built with the preset + fonts +
    background renders correctly (screenshot above); standard `Button`s
    styled by `GoUi.theme()` render as cut-corner cyan-bordered buttons.
  - The editor plugin is **NOT** enabled (not needed: "Drop it in and it
    works… enabling the editor plugin only adds conveniences"). No autoload
    is registered. `GoUi` is pure static — no autoload required.
- **Chosen preset: `GoThemePresets.SCIFI_DARK`** (`scifi_dark`).
  Why: a 2D arena shooter wants a sci-fi HUD, not an app (Material 3) or
  arcade-cabinet look; cyan-on-navy is the furthest possible from v3.1's
  green; it ships cut-corner styleboxes (`GoStyleBoxCut`) so buttons/panels
  look angular instead of rounded; dark baseline keeps HUD readable over
  bright maps. `scifi_light` is the same look on a light baseline — do not
  use it (light panels wash out over bright maps).
- **Config resource (new file, ready to use):** `res://ui/gohud_config.tres`
  (`GoConfig`, `preset = &"scifi_dark"`). Verified it loads
  (`preset=scifi_dark`, accent `#00E5FF`). The implementation worker wires
  it in with `GoUi.config = preload("res://ui/gohud_config.tres")` before
  building UI (or `GoUi.use_preset(GoThemePresets.SCIFI_DARK)` in
  `main.gd._ready()` / `game.gd._ready()` — do it once, early, before any
  screen is built).
- **How to apply (implementation worker):** set the theme on each screen's
  root control (`root.theme = GoUi.theme()`) and **delete the per-button
  manual stylebox overrides** — `main.gd._style_button()` /
  `_style_selected()` / `_btn_style()` / `_panel()` and
  `game.gd._style_hud_button()` currently override `normal/hover/pressed/
  disabled/focus` + font colours on every button, which **masks the gohud
  theme completely** (a bare `use_preset()` call alone changes almost
  nothing on the existing screens — proven by inspection: every menu/HUD
  button carries explicit overrides). Replace them with theme-driven
  styling: keep the 56–64 px minimum touch targets, keep the selected-state
  logic (selected = accent fill + `✓` prefix), but let the colours, corner
  cut, borders and fonts come from the theme. Keep `GoBar` for HP/ammo bars
  and the kill-feed/scoreboard chips; use `GoHudButton` only for HUD corner
  icon buttons (pause etc. — it is an art + key-hint button, it has NO
  `text` property; use `GoHudButton.make(art, size, key)`).
  `GoSurface` is the gohud modal/popup surface — use it for pause,
  scoreboard, end-screen and error dialogs.
- **Icons:** use only names present in `icons/default` (84: play, pause,
  settings, user, home, check, close, warning, volume_*, shield, skull,
  target, trophy, sword…) or `icons/game` (187: helmet, medkit, bomb,
  rocket, radar, drone, armor, crosshair-ish `target`, …) via
  `GoUi.icons().texture(&"name")`. The 1000-icon library is NOT installed.
  The old hand-drawn `_make_icon()` shapes in `main.gd` (play/user/gear)
  should be replaced by gohud icons (`play`, `user`, `settings`).
- **NEVER use gohud for:** the joysticks, the firing input, physics,
  networking, maps, weapons or audio. Those stay on the tested custom code
  (`joystick.gd`, `game.gd`, `weapons.gd`, `discovery.gd`). gohud is
  menus/panels/buttons/HUD styling ONLY. The virtual joystick in gohud
  (`GoHudJoystick`?) is NOT to be used — the game's `joystick.gd` is the
  tested one (QA-029 touch-transform fix must survive).

### 1b. Fonts — Orbitron + Rajdhani (SIL OFL 1.1, free to ship)
- **Orbitron** (headings / titles / big numbers): variable font
  `Orbitron[wght].ttf`, Copyright 2018 The Orbitron Project Authors
  (https://github.com/theleagueof/orbitron), Reserved Font Name "Orbitron".
  Source: https://github.com/google/fonts/tree/main/ofl/orbitron
- **Rajdhani** (body / buttons / HUD text / small numbers): Regular,
  Medium, SemiBold, Bold. Copyright (c) 2014 Indian Type Foundry
  (info@indiantypefoundry.com). Source:
  https://github.com/google/fonts/tree/main/ofl/rajdhani
- **Licence:** SIL Open Font License 1.1 for both. The licence text is
  bundled in the project: `res://assets/fonts/orbitron/OFL.txt` and
  `res://assets/fonts/rajdhani/OFL.txt`. OFL permits bundling in the APK
  and commercial use; it requires the licence text to travel with the
  font (satisfied by the bundled `OFL.txt` files) and forbids selling the
  fonts alone or modifying them under the same Reserved Font Name.
  **Attribution:** add one line to Settings → Credits (implementation
  worker): "Orbitron © 2018 The Orbitron Project Authors, Rajdhani © 2014
  Indian Type Foundry — SIL Open Font License 1.1".
- **Installed:** `res://assets/fonts/orbitron/Orbitron-Variable.ttf`
  (38 KB) + `OFL.txt`; `res://assets/fonts/rajdhani/Rajdhani-{Regular,
  Medium,SemiBold,Bold}.ttf` (~1.5 MB total) + `OFL.txt`. Verified loading
  as `FontFile` in the smoke run. (Variable-font note: Godot reads the
  Orbitron variable font at its default weight; if a heavier title weight
  is wanted, the worker should pin a weight via `FontVariation` — test it,
  do not assume.)
- **Also bundled by gohud (NOT used for game text):** Cinzel, Roboto,
  Nunito, Baloo 2 (all OFL 1.1, see `addons/gohud/THIRD_PARTY_NOTICES.md`).
  Roboto is the Material 3 preset's font — not used; the game uses
  Orbitron/Rajdhani only. Tabler Icons (MIT) supply the game icon set's
  path data — see the notices file.

### 1c. Other libraries — evaluated, NOT added (deliberate)
- No other external library is installed. gohud already bundles themes,
  icons and fonts; the game already has its own music (OGG tracks),
  procedural SFX and a tested HUD. A free audio/music helper or a second
  UI kit would add dependency risk for no visible gain. If a later worker
  finds a free library that genuinely helps, it must be MIT/Apache/OFL
  (or equivalent), verified on Godot 4.7.2, UI/presentation-only, and
  recorded here first. **No paid library or asset pack — user forbids
  purchases without asking first.**

## 2. Colour palette (measured from the live `scifi_dark` theme tokens)

All values below were read from `GoUi.color()` on Godot 4.7.2 after
`use_preset(SCIFI_DARK)` — use these hexes, do not re-derive them.

| Role | Hex | Token / note |
|---|---|---|
| Primary / accent | `#00E5FF` | `GoTheme.ACCENT` — cyan. THE accent. Replaces v3.1 green everywhere. |
| Background (app) | `#05080E` | `GoTheme.BACKGROUND` — near-black navy |
| Panel / surface | `#121D2E` | `GoTheme.SURFACE` |
| Panel soft | `#1A2B42` | `GoTheme.SURFACE_SOFT` (cards, list rows) |
| Panel high | `#213754` | `GoTheme.SURFACE_HIGH` (hovered/emphasised surface) |
| Border | `#3D8FB5` | `GoTheme.BORDER` — steel blue, 1–2 px |
| Text | `#D8F4FF` | `GoTheme.TEXT` — ice blue-white |
| Secondary text | `#7FB4CC` | `GoTheme.SECONDARY` |
| Muted text | `#85A7BD` | `GoTheme.MUTED` |
| On-accent (text on cyan) | `#03121A` | `GoTheme.ON_ACCENT` — near-black, for pressed-button text |
| Success | `#3BFFA5` | `GoTheme.SUCCESS` — mint. Semantic only (ready/victory). NOT the accent. |
| Warning | `#FFC53D` | `GoTheme.WARNING` — amber (low ammo, timers) |
| Danger | `#FF4D6D` | `GoTheme.DANGER` — coral red (damage, leave, errors) |
| Info | `#5B8CFF` | `GoTheme.INFO` — blue (hints) |
| Scrim | `#000914` @ 0.55 | `GoTheme.SCRIM` — dim over backgrounds |
| Bar track | `#04090F` | `GoTheme.TRACK` — HP/ammo bar background |

Rules: **no green as an accent or primary action colour anywhere**
(the old `UI_ACCENT #21A652` is gone). Green appears only as the
`success` token where a semantic "good" is needed (e.g. host IP "ready"
state) — and even there, prefer cyan/`success` mint sparingly. Selected
map/mode = cyan fill + dark text + `✓`. Danger actions (Leave, End,
disconnect) = danger red. The host IP in the lobby stays big, but in
cyan, not green.

## 3. Typography

| Use | Font | Size (px) | Notes |
|---|---|---|---|
| App title (Sky Raiders logo image, `assets/logo/sky_raiders_logo.png`) | — | 460×119 | Crosshair emblem + "SKY RAIDERS" wordmark (Orbitron, cyan `#00E5FF` + ice `#E0F7FF`), centred. QA-145 replaced the v3.5 "FRAG ARENA" logo with the same style, new name. v3.5 replaced the old text title "LAN ARENA SHOOTER" (Orbitron 40) with the logo TextureRect — the text title is gone. |
| Screen titles ("GAME LOBBY", "SETTINGS") | Orbitron | 30 | Text `#D8F4FF` |
| Section labels ("Map:", "Game mode:") | Rajdhani SemiBold | 20 | Muted `#85A7BD`, caps optional |
| Buttons | Rajdhani SemiBold | 22–26 | ALL CAPS text, text `#D8F4FF` (pressed: `#03121A` on cyan) |
| Body / hints / status | Rajdhani Regular | 18–20 | Muted/secondary |
| Numbers (HP, ammo, timer, score, kills) | Rajdhani Bold | 20–28 | Text `#D8F4FF`; timer warning amber < 30 s, danger red < 10 s |
| Kill feed / toasts | Rajdhani Medium | 18 | On dark translucent chips |

The gohud theme's base font size is 16 — **always set explicit sizes**
(above) on every control; do not rely on the theme default. The menu
title is now the Sky Raiders logo image (460×119), not text — it fits
1280 and phone-landscape widths; verify on a narrow (portrait-ish)
width before shipping.

## 4. Buttons (gohud `scifi_dark` theme)

- **Shape:** chamfered/cut corners (`GoStyleBoxCut`), NOT rounded.
  Theme metric `RADIUS = 12`, `BUTTON_HEIGHT = 52` (dp). Keep the game's
  56–64 px minimum touch targets (menu 64, lobby rows 56–72).
- **Normal:** navy fill `#121D2E`, 1 px steel-blue border `#3D8FB5`,
  ice text `#D8F4FF`.
- **Hover:** lighter surface `#213754`, brighter cyan border, text stays ice.
- **Pressed:** cyan fill `#00E5FF`, dark text `#03121A`.
- **Selected (map/mode/limit/time/colour/helmet):** same as pressed +
  `✓ ` prefix on the label. Keep the existing selection logic.
- **Disabled (non-host in lobby):** muted fill, muted text `#85A7BD`,
  no border glow. Must still be visibly different from enabled.
- **Primary actions** (START MATCH, LOCAL MULTIPLAYER, RESUME): cyan fill
  + dark text by default (not just on press).
- **Danger actions** (Leave, End Match, disconnect): danger fill/border
  `#FF4D6D`.
- **Focus:** empty focus stylebox (no Godot focus ring) — keep as in v3.1.
- **No per-button `add_theme_stylebox_override` in game code anymore.**
  If a button needs a one-off look, it is a theme variation, not an inline
  override — inline overrides are how v3.1 ended up ignoring its own theme.

## 5. Panels / cards

- **Panels** (menu, lobby, settings, customize, multiplayer): full-rect
  `PanelContainer`, 16 px side / 12 px top-bottom offsets (keep v2.3's
  full-rect rule — never centre with manual offsets), dark navy fill
  `#121D2E` at ~0.96 alpha, 1 px `#3D8FB5` border, cut corners, content
  margins 24/18 (keep). The panel sits over the arena background + scrim.
- **Cards / rows** (room cards, player rows, map rows, scoreboard rows):
  `#1A2B42` fill, 1 px border, cut corners, 8–10 px separation.
- **Popups** (pause, scoreboard, end screen, errors): `GoSurface`
  (gohud modal surface) with scrim behind; do not hand-roll popup panels.
- **Scrollbar:** gohud theme's scrollbar (thin, cyan thumb on dark track).
  The lobby map list MUST show a visible scrollbar — see `SCROLL_BUG.md`.

## 6. Backgrounds

- **Menu, lobby, settings, customization, multiplayer, end screens:**
  ONE image — Sky Brawl `arena_map_02.png` (blue arena: starfield,
  mountain silhouettes, floating platforms, 960×540, **6 KB**), with a
  `0.55`-alpha dark scrim (`#000914`) over it. The image is flat vector
  art: upscaling 960→1280 (1.33×) stays crisp. Alternate (same set):
  `arena_map_06.png` (pale ice-blue) if the blue reads too dark on a
  given screen — do not use the red/green/pink/purple colourways; they
  clash with the cyan identity.
  Source file: `~/workspace/user/files/sky_brawl_asset_pack/sky_brawl_asset_pack/maps/arena_map_02.png`
  (Sky Brawl pack, user's own assets). **Import exactly this one image**
  into the project (e.g. `res://assets/backgrounds/arena_blue.png`) —
  do NOT import all 20 arena backgrounds (19 × ~6 KB is small, but only
  one is used; keep the APK lean). Alpha channel: min 110 (stars/glows
  are semi-transparent) — flatten over the dark scrim, never over white.
- **What the 20 arena backgrounds are:** all 20 share one composition
  (starfield + mountains + platforms + solid ground band) in 10 colourways
  × 2 layout variants. They are side-view arena backdrops, not menu art —
  the ground band across the bottom third is why the scrim + centred
  panel are required. Do not use them as in-game map backgrounds (the
  game already has per-map skies).
- **HUD (in-game):** no background image. Bars/text over the live game.
- **Old background:** the procedural gradient sky + sun + ground band in
  `main.gd._build_background()` is REPLACED by the arena image + scrim.
  Keep the dim `ColorRect` pattern (it is what makes text readable), just
  with the new image underneath. The old `assets/backgrounds/day.png`
  (79×102) stays unused — it was already too small to stretch.

## 7. HUD readability (bright AND dark maps)

- HP bar: `GoBar`, cyan fill on `#04090F` track, 3 px dark outline,
  numeric HP text beside it (Rajdhani Bold, `#D8F4FF` with a dark outline).
- Ammo: Rajdhani Bold number + "RELOAD" button (cyan border); low ammo =
  amber, empty = danger red + pulsing reload hint.
- Kill feed / timer / score: dark translucent chips (`#05080E` @ 0.8)
  behind every text element that floats over the game world. No bare
  white text on a bright sky.
- Hitmarkers: keep the existing cyan/white hitmarker; it already reads on
  both bright and dark maps.
- Aim stick (see `CONTROLS_CHANGE.md`): cyan ring + crosshair cue so the
  player knows the right stick also fires. Stick geometry/touch behaviour
  unchanged (QA-029).
- Joysticks keep the tested custom drawing (`joystick.gd`); only the
  colours change to the new palette (base dark navy, border ice, knob
  white, active ring cyan). **Do not restyle the sticks with gohud.**

## 8. Lobby map-selection list (new-theme design)

- 2-column grid, rows 72 px, 8 px gaps (keep v3.1 geometry — it fits).
- Each row: map thumbnail left (existing `assets/thumbs/thumb_*.png`,
  96×64 — keep), map name in Rajdhani SemiBold 20, selected row = cyan
  fill + dark text + `✓`.
- **All 13 maps must be reachable by touch-drag scrolling** — this is the
  reported bug; the fix is specified in `SCROLL_BUG.md`. The list lives
  in ONE `ScrollContainer` with a visible scrollbar and a
  "Scroll for more maps ↓" hint under the grid when content overflows.
- Map vote, mode, kill limit, match time rows keep their current layout,
  restyled to the new theme. The fixed bottom action row (I'M READY /
  START MATCH / Leave) stays outside the scroll area.

## 9. Quality rule (user instruction, applies to the whole v3.2 build)

1. **Test every change** — the new UI on every screen, the map-list
   scrolling at phone resolutions, and the right-stick firing — with the
   full test suite, and **re-run the suite after each fix**.
2. **Regressions:** v3.1 fixes must still hold — joystick touch transform
   (QA-029), solid collision (QA-030), kill-credit lock (QA-031) — and the
   old fire-button glitches must not return through the new input path
   (stale aim vector, firing from grenade/weapon/reload/pause taps,
   firing while dead/paused).
3. **Screenshots of every redesigned screen**, reviewed before delivery.
   If anything looks broken, misaligned, unreadable or overlapping, fix it.
4. **If any change cannot be made bug-free, leave that piece out and
   report exactly what was left out and why** — do not ship it broken.
5. **Deliver v3.2 only on a green full pass with 0 script errors.**
6. **Prefer simple, robust, testable design choices over flashy ones.**
   No exotic controls that could swallow touch input; the map list stays
   a plain `ScrollContainer` with standard buttons (plus the
   drag-forwarding fix in `SCROLL_BUG.md`).

### Risky elements — prove with a test or leave out
- `GoStyleBoxCut` chamfered corners on small buttons — verify on a real
  phone screenshot that corners don't clip text at 56 px height.
- `GoBar` readout text (demo showed "1 / 1" for a 0.75 fill) — set the
  readout format explicitly for HP/ammo and verify the number shown.
- Orbitron variable font weight — verify the title weight in a screenshot;
  if too light, pin a weight with `FontVariation`.
- Theme font sizes: gohud base is 16 — every control must carry an
  explicit size (see §3); a missed override = unreadably small text.
- Drag-forwarding scroll fix — must pass the touch-drag probe
  (`SCROLL_BUG.md`) on a real phone resolution; if it proves flaky, fall
  back to the `MOUSE_FILTER_IGNORE` + manual-tap variant documented there.
- `GoSurface` modals (pause/scoreboard/end) — verify each opens, closes,
  and returns focus correctly; a stuck modal is a ship-blocker.

## 10. Implementation checklist (next worker)

- [ ] Wire the theme once, early: `GoUi.config = preload("res://ui/gohud_config.tres")`
      in `main.gd._ready()` (and `game.gd._ready()` for the HUD side).
- [ ] Replace `_build_background()` with arena image + scrim (§6).
- [ ] Rewrite `_style_button` / `_style_selected` / `_btn_style` / `_panel`
      (main.gd) and `_style_hud_button` (game.gd) to use the theme (§4–§5);
      delete the old green colour constants (`UI_ACCENT` etc.).
- [ ] Apply Orbitron/Rajdhani per §3; add the font credit line to Settings.
- [ ] Replace `_make_icon()` shapes with gohud icons (§1a).
- [ ] Restyle every screen: menu, customization, settings, multiplayer,
      lobby (incl. the map list, §8), pause, scoreboard, end, error panels.
- [ ] Apply the scroll fix (`SCROLL_BUG.md`) + the control change
      (`CONTROLS_CHANGE.md` — FIRE button removal, right-stick fire).
- [ ] Screenshots of every screen at 1280×720 AND a phone resolution;
      review and fix before delivery.
- [ ] Full test suite green, 0 script errors, regressions QA-029/030/031
      re-verified (see §9).

## 11. Files touched in Phase 1 (this worker)

- NEW `res://addons/gohud/` (gohud 1.3.0, lean runtime subset, §1a)
- NEW `res://assets/fonts/orbitron/` + `res://assets/fonts/rajdhani/` (§1b)
- NEW `res://ui/gohud_config.tres` (preset `scifi_dark`)
- NEW `THEME_SPEC.md` (this file), `SCROLL_BUG.md`, `CONTROLS_CHANGE.md`
- MODIFIED: none of the game scripts/scenes. (`project.godot` untouched —
  no autoload, no plugin enabled. `.godot/` import state + generated
  `.import` files for the new assets only.)
- Backup of the untouched v3.1 project:
  `~/workspace/mini-militia-lan-backup-v3.1/` (APK md5 verified
  `01eefb9c15061b1c51f9bb9b67e22dee`, git `296fa73`).

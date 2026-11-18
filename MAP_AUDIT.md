# MAP UNIQUENESS AUDIT — LAN Arena Shooter

- **Audited:** `game.gd` `MAPS` array (lines 66–345), 10 maps. Read-only audit; no game code touched.
- **game.gd as read:** last modified **2026-11-18 19:50:57 UTC** (158,201 bytes, 4,378 lines) — a v2.5 builder is actively editing it; the QA-030 solid-decor collision code was already present in this copy. Re-check after v2.5 lands.
- **Rules applied:** `RESEARCH_v3.md` §(a) — loop/3-lane flow, 2 routes per area, no dead ends, cover every 300–400 px on lanes >800 px, no spawn in LOS of another spawn, cover within ~150 px of every spawn, 2 escape routes per spawn, strongest weapon exposed in contested centre, high routes fast but exposed, low routes slow but covered, jump rise ≤ ~180 px.
- **Method:** platform/spawn/pickup/decor coordinates parsed and measured with a script (platform-set identity, level coverage, floor LOS pairs counting only *solid* decor as blocking — palms/trees/bushes/bridges/arches are pass-through per `SOLID_DECOR_KINDS`). "LOS pairs" = pairs of the 8 floor spawns with an unblocked sightline along the floor (36 possible pairs).
- **Headline finding:** only **3 genuinely distinct layouts** exist. 5 of the 10 maps are byte-identical copies of one of two templates, differing only in sky colour / decor skins.

## Per-map table

| Map | Size | Levels / platforms | Layout signature | Cover density (mid levels) | Longest uncovered floor lane | Spawn safety | Centre hot zone + strongest pickup | What makes it DIFFERENT |
|---|---|---|---|---|---|---|---|---|
| Catacombs | 3200×1400 | 6 / 17 | Symmetric 3-3-3 stack + one 900 px-wide central bridge platform at y1010 | 29–52% per level | 1200 px (x1000→2200) | 7/36 floor LOS pairs; 6/12 spawns no solid cover ≤150 px | Pickup (1600,810) is 110 px from map centre — closest to true centre of all maps | Only map with a wide mid bridge; dark underground palette; only map whose centre pickup is actually central |
| Military Base | 2880×1440 | 7 / 16 | Tallest stack; centred top perch (1250,370) — highest platform in the game | 13–42% (thinnest top: 13%) | 1200 px | 8/36 LOS pairs; 6/12 spawns no cover | Centre pickup (1200,680), 243 px off centre | Only 7-level map with a centred sniper perch; smallest width; most vertical |
| Desert Outpost | 3000×1500 | 6 / 16 | Template A (see below) | 21–43% | 1000 px | 7/36 LOS pairs; **9/12 spawns no solid cover — worst in game** (its 2 palms are pass-through, so only 3 solid floor decor) | Centre pickup (1400,910), 189 px off centre | NOTHING in layout — only sand palette + palms. Clone (see §Similarity) |
| Industrial Factory | 3200×1600 | 7 / 17 | Template B (see below) | 10–41% (thinnest top: 10%) | **1450 px** (x750→2200) | 5/36 LOS pairs (best, bridge + column break sightlines) | Centre pickup (1500,1010), 233 px off centre | Tallest map (1600) + bridge decor; otherwise a clone (see §Similarity) |
| Frozen Fortress | 2800×1500 | 6 / 16 | Template A shifted to 2800 width | 23–44% | **800 px — best floor cover** (5 solid floor decor) | 5/36 LOS pairs; only 3/12 spawns no cover — best spawn safety | Centre pickup (1300,910), 189 px off centre | Smallest map; densest floor cover; snow fx. Same skeleton as Template A, but the cover density genuinely changes play |
| Jungle Ruins | 3200×1400 | 6 / 20 | Dense overlapping centre: 68% coverage at y1010, 59% at y1180; hand-built 6-zone layout, 12 decor pieces | 9–68% (only map >50% on any mid level) | **2500 px — worst in game** (only 1 solid floor decor; trees/bushes are pass-through) | **18/36 floor LOS pairs — worst in game**; 8/12 spawns no solid cover | Centre pickup (1450,640), 162 px off centre | The only hand-designed map: breaks the 3-3-3 template, only map with zone structure, only pass-through-heavy cover. Most distinct — and least spawn-safe |
| Space Station | 3000×1500 | 6 / 16 | Template A, exact copy | 21–43% | 1500 px | **10/36 LOS pairs — worst of the Template A trio** | Centre pickup (1400,910), 189 px off centre | NOTHING — dark palette only. **Weakest map in the game** (see verdict) |
| City Underground | 3200×1600 | 7 / 17 | Template B, exact copy | 10–41% | 1450 px | 5/36 LOS pairs | Centre pickup (1500,1010), 233 px off centre | NOTHING in layout — rain fx + dark palette only. Clone |
| Volcanic Cavern | 3000×1500 | 6 / 18 | Template A + split floor: 2 lava pools (300 px each, x700–1000 and x2000–2300); floor coverage 80% instead of 100% | 21–43% | 900 px | 6/36 LOS pairs; spawns shifted off the lava | Centre pickup (1400,910), 189 px off centre | **Only map with a floor hazard; only split floor.** The one Template A variant that earns its slot |
| Pirate Island | 3000×1500 | 6 / 16 | Template A, exact copy | 21–43% | 1000 px | 5/36 LOS pairs | Centre pickup (1400,910), 189 px off centre | NOTHING in layout — palms + bright sky only. Clone |

**Templates (the core problem):**
- **Template A** (6 levels, y = 600/770/940/1110/1280/floor): Desert Outpost, Frozen Fortress (≈, shifted), Space Station, Volcanic Cavern (≈, +lava), Pirate Island. Same staggered 3-low / 4-mid / 2-high rhythm, same spawn pattern (5 floor + 3 upper + 4 floor), same 6 pickup spots.
- **Template B** (7 levels, y = 530/700/870/1040/1210/1380/floor): Industrial Factory, City Underground.
- **Template C** (Catacombs + Jungle Ruins share the y-rhythm 500/670/840/1010/1180/floor, but their platform *layouts* differ enough to count as distinct.)

**What passes everywhere:** jump rise between levels is 170–172 px on all 10 maps (rule ≤180 ✓ — but it is *identical* everywhere, so vertical feel never changes); no dead ends on any map (there are no enclosed corridors at all); every area has 2+ routes via the jump chains; top platforms have no cover on them (perches are exposed ✓).

## Global rule violations (all 10 maps — fix once, fix everywhere)

1. **Strongest weapon is NOT in the contested centre — by design.** `_update_pickup_spawn` (game.gd ~1885) spawns a pickup at a *random* spot from the 6 with a *random* kind every 14 s. Sniper/Rocket can appear next to a spawn or in a corner, and the centre spot is no more likely than any other. Fix: pin Sniper/Rocket spawns to the centre spot (with a visible timer); randomise only SMG/Shotgun/Health/Grenades across the other spots.
2. **Every floor is one 2800–3200 px uncovered lane.** Longest uncovered floor stretch is 800–2500 px on every map vs the rule "cover every 300–400 px on lanes >800 px". Every map fails; Jungle Ruins (2500 px) and Space Station (1500 px) are the worst. Fix: add 2–3 more solid floor decor pieces (crates/barrels/columns) per map, spaced ≤400 px apart — cheapest global fix in this audit.
3. **Floor spawns see each other.** 5–18 of 36 floor-spawn pairs have clear LOS on every map (rule: zero). All 8 floor spawns sit on one straight line. Fix: stagger floor-spawn heights (use the y1180/y1110 platforms for 3–4 spawns instead of all 8 on the floor) and add the floor cover from (2). Also verify respawn picks the point **farthest from live enemies** — if it is still random/round-robin, change it; 2 s spawn protection alone does not fix a spawn in someone's sights.
4. **TDM spawns are not grouped.** All 12 spawns are one interleaved list on every map (rule: spawns grouped per team, never interleaved). Fix: split each map's spawn list into a left-half and right-half group for TDM.
5. **Centre pickups are off-centre on 9/10 maps** (162–243 px from map centre; only Catacombs is ~110 px). Move each map's central pickup spot to the true centre of its hot zone.

## Similarity — pairs that are too similar, and exactly what must change

### MUST FIX (byte-identical geometry — same platforms, same spawns, same pickups; only sky/decor differ)

1. **Desert Outpost = Space Station = Pirate Island** — platform arrays are *identical rect-for-rect* (16 platforms), spawns identical, pickups identical. Three maps that play exactly the same.
   - **Keep one as-is: Desert Outpost** (best spawn-cover story of the three is still bad, but it is the original template).
   - **Space Station — rebuild, do not re-skin.** New layout: low-gravity-feel vertical station — remove the full-width floor, replace with 3 disconnected deck segments with gaps (jetpack crossings), add a central vertical shaft (fast exposed up-route) and side maintenance tunnels (slow covered low route). Keep the dark palette. This also fixes its 10/36 LOS pairs.
   - **Pirate Island — rebuild as a different kind.** New layout: beach + beached ship hull — sloped deck (stepped platforms rising to a crow's-nest perch at one end, not the centre), open sand mid with palm cover, and a below-deck tunnel (short, both ends visible). Asymmetric: high ground on the *left*, hot zone on the *right*. If a rebuild is too big for v3.0, delete Pirate Island and ship 9 maps — a duplicate is worse than one fewer map.
2. **Industrial Factory = City Underground** — platform arrays *identical* (17 platforms), spawns identical, pickups identical.
   - **Keep Industrial Factory as-is.**
   - **City Underground — re-lay-out, keep the theme.** New layout: subway-tunnel map — two stacked tunnel tubes (upper tube = fast exposed lane, lower tube = slow covered lane with pillars every ~350 px), connected by 3 stair shafts; hot zone on the centre platform *between* the tubes where both lanes cross. The tunnel walls naturally break the 3200 px floor sightline that Template B suffers from.

### SHOULD FIX (same skeleton, different numbers — plays the same)

3. **Frozen Fortress vs Desert Outpost / Space Station / Pirate Island** — same Template A y-levels and spawn/pickup pattern, only shifted to 2800 px width. **Keep**, but only because its floor cover (800 px longest gap, 5 solid floor decor) genuinely changes fights. To make it unambiguously distinct: shrink it further into the game's **small duel map (~2200×1400, 2–4 players)** — RESEARCH §(a) already calls for one — and give it an ice-slide centre (low-friction-feel open mid) with the hot zone on a frozen lake platform.
4. **Volcanic Cavern vs the Template A family** — same template, but the lava split-floor + shifted spawns make it play differently. **Keep as-is.** If time allows, deepen the difference: make the lava pools wider (400 px) and put the centre pickup on a narrow bridge *over* the middle lava gap — highest risk/reward spot in the game.
5. **Catacombs vs Jungle Ruins** — same y-level rhythm, different layouts. **Keep both.** No change needed, but do not copy this rhythm into any new map.

### NOT a problem
- **Military Base** vs the family: same design language, but 7 levels + centred top perch + smallest width give it a different vertical game. Keep.
- **Jungle Ruins**: most distinct map; fix its spawn safety (2500 px open floor, 18/36 LOS pairs) rather than its identity — add 2 solid floor decor pieces (statue/pillar) at ~x1000 and ~x1900 and move 2 floor spawns up to the y1180 platforms.

## New maps — 3 large maps, each a different kind from all 10 existing ones

Candidate check from the plan: **Neon City — confirmed. Ancient Temple — confirmed, with a differentiator from Jungle Ruins. Arctic Research Station — REJECTED**: too close to Frozen Fortress (snow + ice + white palette + cold fx). Replaced with **Airship Fleet**, which introduces the game's first disconnected ground.

### 1. Neon City — the vertical map (3400×1800, 5 levels)
- **Theme:** rain-slick cyberpunk downtown at night; neon signs, holo-billboards, rooftop antennas. Dark blue/purple sky, pink/cyan neon, rain fx.
- **Layout signature:** vertical figure-eight. Two tower blocks (left and right) with rooftop high routes, a street-level low route through an alley, and a centre skybridge at mid height connecting the towers. Rotation is up-and-over (fast, exposed rooftops) or through the alley (slow, covered). No full-width floor — the street is broken by a central plaza gap crossed by the skybridge.
- **Levels:** 5 (street 1752 / alley ledges 1580 / skybridge 1400 / mid roofs 1100 / antenna roofs 800). Jump rises 170–180 px; rooftop-to-rooftop gaps need the jetpack and are deliberately exposed.
- **Cover/sightlines:** neon sign boards as solid half-cover on rooftops (fire over them, can't hide behind them fully); alley has a solid dumpster/AC-unit every ~350 px so the long street lane is never a death corridor; the skybridge has *no* cover — crossing it is the risk.
- **Hot zone + strongest pickup:** Sniper/Rocket pinned to the centre of the skybridge (exposed from both rooftops and the street — 3 firing angles, per the rule's limit). Side pickups in the alley and on each rooftop.
- **Spawns:** 12 — 4 street (2 per tower base, grouped per team for TDM), 4 alley ledges, 4 rooftops; no two floor spawns share LOS (tower bases block the street line).
- **Art needed:** neon sign boards (3–4 variants), rooftop AC units/antennas, holo-billboard, rain fx (reuse), dark building silhouettes, plaza tiles. No new mechanics.

### 2. Ancient Temple — the ziggurat map (3000×1600, 6 levels incl. one below floor)
- **Theme:** overgrown stone temple, gold/teal torches, carved pillars. Distinct from Jungle Ruins: this one is *vertical and ceremonial* (stepped pyramid + crypt), Jungle is *horizontal and dense* (canopy + zones).
- **Layout signature:** stepped ziggurat in the centre (3 tiers rising to a flat altar top), flanked by two low colonnades, with a **crypt tunnel below the floor** — the only below-floor level in the game. Flow: colonnade (slow, covered) → ziggurat steps (fast, exposed) → altar; crypt (slowest, fully covered) runs underneath and exits at both ends.
- **Levels:** 6 (crypt 1650 / floor 1552 / colonnade ledges 1380 / ziggurat tier 1 at 1210 / tier 2 at 1040 / altar top 870). Every rise ≤170 px; the altar is reachable from either side, never from one hidden route.
- **Cover/sightlines:** stone pillars as full cover every ~350 px along the colonnades; the ziggurat steps are open (no cover — climbing is the risk); the crypt is a short tunnel with both exits visible from the entrance (no-dead-end rule). The altar has no cover on top — the perch rule.
- **Hot zone + strongest pickup:** Sniper/Rocket pinned to the altar top, centre of the map — exposed to both colonnades and the crypt exits. Side pickups: one in each colonnade, one at each crypt exit.
- **Spawns:** 12 — 4 in the colonnades (2 per side), 4 on ziggurat tier 1 (2 per side), 2 at the crypt exits, 2 on the floor flanks. No spawn faces the long colonnade lane; crypt spawns have 2 exits each.
- **Art needed:** ziggurat step tiles, carved pillar, altar stone, torch (flame fx), crypt wall tiles, gold trim. No new mechanics.

### 3. Airship Fleet — the disconnected-ground map (3200×1500, 5 levels)
- **Theme:** three flying ships at dusk — wooden hulls, sails, rigging, clouds below. Warm sunset sky, distinct from every existing palette.
- **Layout signature:** the only map with **no full-width floor**. Three separate hull decks (left, centre, right) with 250–350 px gaps between them — gaps are crossed by jump + jetpack, never by walking. The centre ship is the biggest and sits highest; the two side ships sit lower. Rotation is a triangle: left → centre → right → (drop to clouds / jetpack back to left). Falling in a gap costs position, not health (respawn on your own deck, or land on a lower safety net platform).
- **Levels:** 5 (safety net 1452 / side decks 1380 / centre deck 1210 / masts 940 / crow's nest 770). Gaps between decks are the map's signature risk; every deck connects to the next by an obvious plank/jetpack hop, never a hidden jump.
- **Cover/sightlines:** masts and sail cloth as full cover on each deck (one per deck, breaking deck sightlines); rigging as half-cover on the centre deck; no cover on the planks between ships. Longest sightline is centre-deck to side-deck (~700 px) — medium range, not a sniper lane.
- **Hot zone + strongest pickup:** Sniper/Rocket pinned to the centre ship's crow's-nest platform — reachable from both side ships, exposed from every deck, no cover on top. Side pickups: one per side deck, one on the safety net.
- **Spawns:** 12 — 4 per ship (grouped per ship, so TDM teams start on opposite side ships with the centre contested). No spawn on the centre ship: nobody spawns on the hot zone.
- **Art needed:** ship hull + deck tiles, mast, sail (full + tattered), rigging ropes, crow's nest, cloud layer below, plank bridges. One small mechanic note: falling through a gap should respawn the player on their own deck, not kill them — decide before building.

## Verdict — weakest map
**Space Station.** Byte-identical geometry to Desert Outpost and Pirate Island, the worst spawn LOS of its clone trio (10/36 pairs), a 1500 px uncovered floor lane, and zero distinguishing feature — not even a hazard (Volcanic has lava) or a cover-density story (Frozen has one). Rebuild it as the vertical station in §Similarity-1 or cut it.

## Fix order (cheapest first)
1. Global: pin Sniper/Rocket to the centre spot; add 2–3 solid floor decor per map (≤400 px spacing); stagger 3–4 floor spawns onto upper platforms; split spawn lists into left/right halves for TDM. (~1–2 h, fixes all 10 maps at once.)
2. Rebuild Space Station layout; re-lay-out City Underground as the subway map. (~2–3 h each.)
3. Rebuild Pirate Island as the asymmetric ship map — or cut it. (~2–3 h, or 0 h to cut.)
4. Shrink Frozen Fortress into the small duel map (~2200×1400). (~1 h.)
5. Build Neon City, Ancient Temple, Airship Fleet from §New maps. (~3–4 h each incl. art.)
6. Jungle Ruins spawn-safety patch: 2 solid floor decor + 2 spawns moved to y1180. (~30 min.)

*Audit method note: LOS/cover numbers count only solid decor (crate/barrels/sandbags/rock/column/jpillar/jstatue/jtower/jcrate/jrock). Palms, trees, bushes, bridges and arches are visual-only and do not block bullets or sightlines. If v2.5 changes which kinds are solid, re-run the numbers.*

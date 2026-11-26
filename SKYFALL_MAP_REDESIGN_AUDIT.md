# Skyfall Competitive Map Redesign

## Scope and audit basis

This review covers the active Skyfall arena in `maps/map_data.gd`, its construction and movement logic, the CTF checkpoint/respawn path, and Skyfall art referenced by the builder. The redesign keeps the 3400 × 10800 vertical ascent, six themed bands, industrial/fantasy dusk identity, summit flags, base extraction, relays, wind, traps, and moving platforms.

The source asset pack's [asset audit](assets/skyfall/ASSET_AUDIT.md) was originally written for a different 3600 × 7200, eight-level proposal. File measurements remain useful, but that layout description is stale. This document describes the active six-level map.

## 1. Map audit report

| Area | Existing behavior | Redesign decision |
|---|---|---|
| Shape and size | Tall, narrow climb; six 1800 px bands | Preserve the tower silhouette; retain 3400 × 10800 bounds |
| Flow | Base is dense; upper stages have long 280–300 px gaps and center-heavy transitions | Add 33 short route supports, bringing the static platform count from 55 to 88; 140–150 px midpoint steps make carrier progress and recovery more deliberate |
| Connectivity | Grapples, ladders, six lifts, wind lanes, and side ledges exist, but the carrier cannot use jetpack and some stages rely heavily on special movement | Give every climb band intermediate foot routes and lateral alternatives; keep movement tools as shortcuts and skill expression |
| Combat hotspots | Base, tunnel boundary, wind bridge, L4 bridge, L5 lava/mech section, and summit | Keep six distinct engagement bands; add intermediate ledges to create more cross-route skirmishes without creating one continuous firing lane |
| Downtime and circulation | 300 px rises can stall a flag carrier; upper checkpoints are sparse | Checkpoints now cover base and L2–L6; respawning teams re-enter closer to active objective lanes |
| Empty/dead space | Wide gaps between old upper platforms make some cross-level sightlines feel disconnected | New ledges are staggered and route-colored; no full-width firing deck is added |

The shape provides quick vertical re-entry, but CTF carrier movement previously had avoidable dead time. The added route platforms reduce isolated jumps while retaining open gaps, hazards, and exposure that defenders can contest.

## 2. Gameplay problems addressed

- Long rises were tuned around jetpack/grapple movement even though flag carriers lose jetpack access. Midpoint platforms now keep the climb legible and contestable on foot.
- L4 checkpoints were previously paired on a narrow central ledge, making a respawning player easy to pressure. They now sit on separated west/east checkpoint wings.
- Upper stages had no checkpoint between L2 and the summit. L3, L4, and L5 checkpoints now make returns proportional to progress.
- The L5 east elevator sweep intersected the newly added east mid-step. The elevator track moved to the far east edge, with the ledge retained as a foot route.
- Four ladder mechanics had absent or mismatched visual art. Matching 96 × 384 ladder art is now placed at each climb; ladder collision lengths align with the art.
- The decorative spike prop at L1 implied a damaging hazard without matching gameplay. It is removed.
- The full level strips used as backgrounds contained baked-in text, drawn platforms, and sight lines that did not match live colliders. They are no longer rendered as gameplay backdrops; per-level color washes, platform tints, the base silhouette, and the existing dusk gradient preserve theme while restoring collision readability.

## 3. Movement problems and improvements

The new upper-stage stepping cadence is roughly 140 px between old landings and midpoint supports, with side-to-side offsets creating deliberate jumps. L2 receives seven intermediate supports; L3 seven including a right-side checkpoint shelf; L4 and L5 each receive five intermediate supports and two checkpoint wings; L6 receives five summit-approach supports. Existing ladders, lifts, grapple points, wind, collapses, and trapdoors remain active.

The summit elevator remains in its dedicated x=1200–1500 shaft; new summit supports sit outside that shaft. The L5 rotator remains clear of the west mid-step. The L5 east lift now occupies x=2700–3200, separate from the static route platform at x=2100–2700.

**Playtest follow-up:** verify jump arcs with each character weight, flag-carrier speed, grapple cooldown, and wall-jump charges. The source has no automated traversal simulation and no Godot runtime was available in this session.

## 4. Combat problems and combat flow

- **Short range:** base crates and the tunnel's compact shelves support shotgun/SMG fights. Upper side steps create brief close contests around checkpoints.
- **Medium range:** staggered 500–600 px shelves provide rifle exchanges with breaks in line of sight; movers and collapses create timing choices.
- **Long range:** L5 remains the intended sniper band, but midpoint and checkpoint shelves interrupt uninterrupted cross-map beams. Avoid adding the reference-pack sniper tower without a dedicated collision/readability pass.
- **Crossfire:** open stage gaps preserve risk for a climber; route alternation gives a choice of approach. The center route is not a safe straight elevator ride.
- **Chokes:** the L2 tunnel, L3 wind bridge, and summit gate remain intentional objective chokes. Each has lateral ledges or movement-tool approaches for a contesting team.
- **Weapons:** shotguns and SMGs have close lanes at the base/tunnels; rifles control mid-stage transitions; snipers get exposed L5 sightlines; grenades can flush movers/checkpoint wings; rockets can punish clustered shelves but limited cover and lateral routes provide escape.

The map still needs match telemetry to confirm that sniper downs and grenade splash do not overperform at the new shelves. The design intent is useful windows for every weapon family rather than fixed weapon-specific rooms.

## 5. Hazard analysis

Skyfall uses falling rocks, timed lava/fire, mines, pendulums, wind, collapsing platforms, and trapdoors. These are retained in their current stages. Their controls/damage logic are separate from the layout data, so this redesign does not change hazard damage values or timings.

The spike decoration without a damage mechanic is removed. The asset audit notes open trapdoors read almost black and should stay over dark tunnel ground; inspect each trapdoor state in a runtime screenshot. Wind zones have faint square edges and use a semi-transparent overlay; increase edge contrast only if a playtest shows players miss the push zone. All damage zones should retain warning animation and a visible safe/hot state.

## 6. Spawn issues and new checkpoint design

The 12 base spawns remain split across west/east base territory. They are outside the summit firing lane and spread across two base elevations. Team spawn protection and extraction behavior remain governed by existing game logic.

Six paired team checkpoints now sit at base, L2, L3, L4, L5, and L6. Upper pairs are laterally separated, and the L3 pair is on the same safe shelf outside the wind band. `SF_CHECKPOINT_LEVELS` now maps indices to `[0, 2, 3, 4, 5, 6]`; CTF progression evaluates checkpoint arrays dynamically, so future stages do not require hard-coded index branches. L6's checkpoint index is now 5.

## 7. Asset quality review

Verdicts refer to the active Skyfall scene, not every file in the pack.

| Asset group | Source quality / resolution | Readability and gameplay impact | Verdict |
|---|---|---|---|
| Solid, collapsing, elevator, trapdoor tiles | Clean 512 × 96 slabs; repeated at authored scale | Strong platform silhouette; cracks/stripes/door state are recognizable | Keep |
| Emergency ladder | Clean transparent 96 × 384 | Small but legible; now visibly matches all four ladder mechanics | Keep and place |
| Flags and extraction zones | 256 × 256; flags read well, rings are low-opacity | Objective rings can be subtle over busy floors; retain current pulse and consider stronger contrast after playtest | Keep; monitor |
| Wind zone | 384 × 384 translucent overlay | Functional cue, but square boundary is faint | Keep; improve edge contrast if missed in play |
| Falling rocks and lightning | 192 × 192 / 192 × 512 transparent art | Clear hazard language at current sprite scale | Keep |
| Level strips | 1800 × 450 opaque reference scenes with labels/platform art | Caused fake floors, baked annotations, and sightline noise against real collision | Remove from active background rendering; keep as reference |
| Sniper tower | 256 × 384 with thin legs | Current collision is not authored as matching tower geometry; adding it could create false cover | Do not place until matching collision is designed |
| HUD bars / mode card | Baked fills; mode card says 5v5 while room cap is 8 | Can misstate live state or lobby capacity | Upgrade/slice UI separately; outside map geometry |

## 8. Resolution and art standards

Do not upscale every texture to 1024 just to meet generic size targets. These assets are stylized, drawn for a 3400 px world, and mostly used at native or small display sizes; indiscriminate upscaling increases memory without adding detail. Keep the current platform strips at 512 × 96 and gameplay props at 192–384 px. If art is repainted, use 1024 px source for large structures, 512–1024 px for landmark sheets, 512 px for close props, and 256–512 px for distant background details. A summit landmark could use 1024 px source art, but only with a collision-matched silhouette.

## 9. Performance optimization suggestions

- Retaining authored sprite sizes avoids wasted texture memory; do not load both individual power-up icons and the equivalent sheet.
- Removing twelve full-width level-strip sprites avoids duplicate drawn geometry and reduces overdraw; the existing per-level wash/tint system stays inexpensive.
- Keep platform tile reuse and the existing shared texture resources. Profile node counts after the added 33 platforms; each platform adds collision and art nodes, so batching repeated route trim is a later optimization if device profiling finds a bottleneck.
- Avoid per-frame allocations in hazard/mover updates; continue updating existing nodes.
- Revisit texture import filtering/compression on mobile targets after an actual export profile.

## 10. Exploit and edge-case list

| Risk | Fix / status |
|---|---|
| Pixel ledges or geometry seams | New supports use 48 px solid rectangles with visible tile art; validate edges in engine and online play |
| L5 lift clipping through east mid-step | Lift moved to x=2700–3200; route support ends at x=2700 |
| Summit lift clipping new step surfaces | New L6 support platforms are outside the x=1200–1500 lift shaft |
| Rotator clipping a new support | L5 y=2364 support occupies x=900–1500, clear of the x=1700–2100 orbit bounds |
| Ladder art/mechanic mismatch | Four art anchors match 96 × 384 ladder rectangles |
| Decorative hazard without damage | Removed L1 `if_spikes` decoration |
| Fake background platform / one-way sightline cue | Removed annotated level strips from active background rendering |
| Out-of-bounds escape | World boundaries remain 0–3400; new supports stay within x=600–2700 |
| Infinite jetpack hover/camping | Fuel limits remain; no enclosed refill perch added. Verify fuel reset behavior in multiplayer |
| Spawn abuse / spawn visibility | Base spawns unchanged; elevated respawn shelves are laterally split and now occur at every stage |
| Unreachable route or one-way drop | Midpoints are supplemental landings, not sealed rooms; confirm all new transitions in engine traversal |

## 11–16. Redesigned layout and annotated decisions

See [the annotated vertical layout](assets/skyfall/skyfall_redesign_layout.svg). It shows all six bands, route supports, checkpoint pairs, ladders, lift tracks, hazards, summit flags, relay locations, and base extraction zones. The 33 new platforms are appended after original indices 0–54 so trap/collapse references remain stable.

| Band | New placement and purpose |
|---|---|
| L1 base | Preserve dense warm-up, existing distributed spawns, extraction, and rock lane; remove false spike prop |
| L2 tunnels | Seven mid-steps split west/center/east; retain tunnel identity and existing lifts/pendulum/mines |
| L3 bridge | Six climb steps plus a right checkpoint shelf; retain wind bridge, relay, and crossing options |
| L4 hanging bridge | Five staggered steps plus separated checkpoint wings, reducing a single central respawn target |
| L5 sniper/mech | Five steps plus checkpoint wings; east lift moved away from the new east route; rotator clearance preserved |
| L6 summit | Five approach steps flank the lift shaft; preserve gate, flag pair, summit objective, and CTF relay |

Hazard placements are unchanged except removal of the nonfunctional L1 spike decoration. Checkpoint additions are exact at `(1200,6950)/(2400,6950)`, `(1200,3870)/(2400,3870)`, and `(1200,2190)/(2400,2190)` for L3–L5.

## 17. Competitive balance report

The redesign lowers carrier traversal friction while preserving defender opportunities: climbers use visible staged landings, defenders can contest exposed midpoints, and teams have several routes to challenge elevated positions. High ground remains advantageous for information and rifle pressure, but no newly created perch spans the arena. Checkpoints reduce re-entry downtime without moving the objective away from the summit/base loop.

This is a layout hypothesis. Competitive balance still requires mirrored team scrims across weapon sets, including flag carries, spawn pressure, and overtime/late-match gate access. Particular watch items: L5 sniper uptime, whether the east lift becomes a low-risk bypass, and whether L3 relay visits overpower the summit capture route.

## 18. Final arena redesign

Skyfall remains a vertical CTF ascent with distinct environmental stages. The updated map has more carrier-friendly footholds, a distributed checkpoint ladder, visible functional ladders, a safer L5 lift route, fewer fake visual cues, and unchanged signature hazards/objectives. It gives every stage at least two approach lines while retaining intentional choke points and exposed decisions.

## 19. QA status and reference principles

Applied design principles: readable silhouettes and clear counter-routes (Brawlhalla/Halo arenas), interconnected movement lanes and air control (Soldat/Teeworlds), risk/reward shortcuts and recoverable falls (Worms), and distinct arena hotspots with meaningful vertical control (Quake). These are design references only; no assets or map geometry were copied.

Static source consistency was reviewed for platform/checkpoint counts and dynamic indices. Godot was not available in this session, so the scene was not launched and the existing feature tests or multiplayer traversal were not executed. Before shipping, visually inspect all six bands and run two-team CTF traversal, weapon, spawn, hazard, and edge-collision playtests.

extends Node2D

# Game scene: side-view arena, LAN multiplayer (ENet), HUD, touch controls.
# LAN only. No online play, no bots, no accounts.
#
# JOIN FIX (v2): the server spawns a client's player ONLY after that client
# has loaded this scene and sent a `request_spawn` RPC (see _announce_ready).
# v1 spawned in _on_peer_connected, before the client had a MultiplayerSpawner,
# so the spawn was dropped and the client sat on "Connecting..." forever.
# v2.4: the client retries the request every 2 s until it is spawned or
# the 8 s timeout fires, so one lost UDP packet can no longer strand it.
# There is also an 8s join timeout with Back / Retry, and players are
# despawned when their peer disconnects.
#
# HOST-AUTHORITATIVE (v2.4): the host decides damage, kills, health,
# deaths, respawns, timer, scoreboard and settings. Clients send inputs
# and fire requests; the host validates (fire rate + ammo) and applies
# damage. No client can award itself kills or damage another player.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const PICKUP_SCENE: PackedScene = preload("res://pickups/pickup.tscn")
const BULLET_SCENE: PackedScene = preload("res://weapons/bullet.tscn")
const JOYSTICK_SCRIPT: Script = preload("res://hud/joystick.gd")
const AUDIO_SCRIPT: Script = preload("res://audio/audio.gd")

# v3.2 NEON ARENA theme (THEME_SPEC.md): Orbitron titles, Rajdhani
# body/numbers, cyan-on-navy. Fonts are SIL OFL 1.1 (see Settings
# credit line in main.gd). The gohud theme drives the look; these
# consts are only for the few places game code still sets a colour
# directly (HUD numbers, bar inks).
const FONT_TITLE: Font = preload("res://assets/fonts/orbitron/Orbitron-Variable.ttf")
const FONT_BODY: Font = preload("res://assets/fonts/rajdhani/Rajdhani-Regular.ttf")
const FONT_BODY_MEDIUM: Font = preload("res://assets/fonts/rajdhani/Rajdhani-Medium.ttf")
const FONT_BODY_SEMIBOLD: Font = preload("res://assets/fonts/rajdhani/Rajdhani-SemiBold.ttf")
const FONT_BODY_BOLD: Font = preload("res://assets/fonts/rajdhani/Rajdhani-Bold.ttf")
const UI_ACCENT := Color(0.0, 0.898, 1.0) # cyan #00E5FF
const UI_ACCENT_DARK := Color(0.012, 0.071, 0.102) # on-accent #03121A
const UI_FONT := Color(0.847, 0.957, 1.0) # ice #D8F4FF
const UI_FONT_MUTED := Color(0.522, 0.655, 0.741) # muted #85A7BD
const UI_SUCCESS := Color(0.231, 1.0, 0.647) # mint #3BFFA5
const UI_DANGER := Color(1.0, 0.302, 0.427) # coral #FF4D6D
const UI_WARNING := Color(1.0, 0.773, 0.239) # amber #FFC53D

const PORT := 7777
const DISCOVERY_PORT := 7778
const DISCOVERY_MAGIC := "LANARENA"
const MAX_PLAYERS := 12 # absolute cap; the room setting is max_players (GameData)
const JOIN_TIMEOUT := 8.0

# Phase 5 — Sky Brawl arena backgrounds as a FAR parallax layer
# (viewport scale ~1.3x, parallax 0.25, never stretched over a map).
# QA-095 (v3.7): 3 left — Index matches the map's "bg" key:
# 0 Ironfall + Outpost (new, code-drawn dusk factory skyline),
# 1 Volcanic Cavern, 2 Neon City. Pirate Island keeps the
# procedural gradient (no "bg" key), as before.
# QA-112 (v3.9): 3 Skyfall dusk sky (pack's bg_sky_dusk.png,
# 1920x1080 landscape — used as the far parallax layer only,
# never stretched over the 10800 px world).
# QA-112 (v3.9): Skyfall pack art (assets/skyfall/ASSET_AUDIT.md —
# every file below verified clean, real transparency, no dark box).
# QA-124 (v3.11): per-level backdrops — the pack's 8 level images
# (1800x450 each; drawn at 2x = 3600x900 per half-level band).
# Merged levels use BOTH their images (cliffs over camp, last
# stand under summit).
# QA-125/126/129 (v3.11): dynamic-effect overlays (50-pack, static
# 512x512 PNGs, animated in-engine). Only the ones below are
# preloaded — import only what is used (see BUGS.md QA-125).
# QA-132: thunder/storm cloud, snow, smoke, whirl, portal,
# portal sparks and arc are un-preloaded with the items that used
# them (clean-up); the textures stay in assets/ for later use.
# QA-137 (v3.14): trap art from the user's trap sheet
# (assets/user_assets_v3/trap_new_*.png). The fire-vent frames
# (row 4) animate the fire-jet hazards; the intact grate (row 1)
# is the collapsing-platform texture and the broken grate (row 6)
# is its falling visual; the spiked ball (cropped from row 1)
# is the new swinging pendulum trap.
# QA-137 (v3.14): HUD kit art (assets/user_assets_v3/hud/).
# Bars are sliced into frame (empty track) + fill so the fill can
# be clipped to the live value (see HudBar). Buttons are the kit's
# flat square buttons (143 px); the radar and shield icons are
# deliberately NOT wired (radar was removed in QA-130; the shield
# icon has no matching HUD element - see BUGS.md QA-137).
const HUD_TEX_BAR_HEALTH_FRAME: Texture2D = preload("res://assets/user_assets_v3/hud/hud_bar_health_frame.png")
const HUD_TEX_BAR_HEALTH_FILL: Texture2D = preload("res://assets/user_assets_v3/hud/hud_bar_health_fill.png")
const HUD_TEX_BAR_JETPACK_FRAME: Texture2D = preload("res://assets/user_assets_v3/hud/hud_bar_jetpack_frame.png")
const HUD_TEX_BAR_JETPACK_FILL: Texture2D = preload("res://assets/user_assets_v3/hud/hud_bar_jetpack_fill.png")
const HUD_TEX_STICK_MOVE_BASE: Texture2D = preload("res://assets/user_assets_v3/hud/hud_stick_move_base.png")
const HUD_TEX_STICK_MOVE_KNOB: Texture2D = preload("res://assets/user_assets_v3/hud/hud_stick_move_knob.png")
const HUD_TEX_STICK_AIM_BASE: Texture2D = preload("res://assets/user_assets_v3/hud/hud_stick_aim_base.png")
const HUD_TEX_STICK_AIM_KNOB: Texture2D = preload("res://assets/user_assets_v3/hud/hud_stick_aim_knob.png")
const HUD_TEX_BTN_GRENADE: Texture2D = preload("res://assets/user_assets_v3/hud/hud_button_grenade.png")
const HUD_TEX_BTN_RELOAD: Texture2D = preload("res://assets/user_assets_v3/hud/hud_button_reload.png")
const HUD_TEX_BTN_WEAPON: Texture2D = preload("res://assets/user_assets_v3/hud/hud_button_weapon.png")
const HUD_TEX_BTN_WEAPON_SWITCH: Texture2D = preload("res://assets/user_assets_v3/hud/hud_button_weapon_switch.png")
const HUD_TEX_BTN_PAUSE: Texture2D = preload("res://assets/user_assets_v3/hud/hud_button_pause.png")
const HUD_TEX_MESSAGE_BOX: Texture2D = preload("res://assets/user_assets_v3/hud/hud_message_box.png")
# QA-119 (v3.11): Thunder Strike bolt art (user's power-up effects pack).
# QA-114 (v3.9): colour-coded climbing routes — WEST (left third),
# CENTRE (middle third), EAST (right third). Same colours on the
# map platforms, the HUD height bar, and the legend.
const SF_ROUTE_COLORS: Array[Color] = [Color(0.2, 0.8, 0.9), Color(0.95, 0.75, 0.2), Color(0.3, 0.85, 0.4)]
const SF_ROUTE_NAMES: Array[String] = ["WEST", "CENTRE", "EAST"]


# QA-112 (v3.9): power-up HUD — the 3 slot backgrounds + the 64 px
# icons for the 7 power-ups (user rule: every player has 3 slots).
# Jungle Ruins slices (from the user's asset pack; black atlas background
# removed, transparency verified — no dark box in-game).
# QA-096 (v3.7) — Operation Ironfall slices (assets/ironfall_sliced/):
# the user's 10-sheet pack, hand-boxed, background flood-filled
# from the crop border, verified on magenta/dark-green (no dark
# box in-game). See assets/ASSET_MANIFEST.md Part 5.
# Phase 5 — Sky Brawl structures (SKY_BRAWL_USE.md). Huts/blocks/
# vents/crates are SOLID cover (see SOLID_DECOR_KINDS); slabs,
# trapezoids and the altar stone are visual dressing only.

const MAPS := MapData.MAPS # QA-140: data lives in maps/map_data.gd
const EXPLOSION_TEX: Texture2D = preload("res://assets/effects/explosion1.png")
const FIREBALL_TEX: Texture2D = preload("res://assets/effects/fireball1.png")
const SMOKE_TEX: Texture2D = preload("res://assets/effects/smoke.png")
# Phase 4/6 — Sky Brawl art (SKY_BRAWL_USE.md): flat-vector effects
# with clean transparency. effect_006 is the small hit spark,
# effect_001 the explosion sunburst.
const SB_HIT_TEX: Texture2D = preload("res://assets/skybrawl/effects/effect_006.png")
const SB_SMOKE_TEX: Texture2D = preload("res://assets/skybrawl/effects/effect_004.png")
# QA-085 (v3.7): drawn dust puff. The dust texture is a soft
# white puff drawn over the landing spot.
# QA-091 (v3.7): soft dot for the GPUParticles2D blast burst.
const PARTICLE_DOT_TEX: Texture2D = preload("res://assets/effects/particle_dot.png")
# QA-092 (v3.7): Stylized 2D VFX Lite (REEBOO Labs, MIT, v1.0.0,
# Godot 4.4) — shader + GPUParticles2D effects, self-freeing.
# hit_spark = bullet impacts, explosion_small = blast core,
# coin_pickup = pickup grab. slash_arc is NOT used: the game has
# no melee attack, so there is nothing to slash.

var players_node: Node2D
var bullets_node: Node2D
var pickups_node: Node2D
var grenades_node: Node2D
var fx_node: Node2D
var spawner: MultiplayerSpawner
var audio # GameAudio
var map_size: Vector2 = Vector2(2880, 1440)
var map_id: int = 0
var game_mode: int = 0 # 0 FFA, 1 TDM
var kill_limit: int = 10
var match_over: bool = false
var _leaving: bool = false # set when leaving for the menu or rematching: _process must stop (multiplayer is torn down / the instance is detached before the scene change lands)

var hud: CanvasLayer
var hp_bar: HudBar # QA-137: kit bar (frame + clipped fill), was gohud GoBar
var fuel_bar: HudBar # QA-137: kit bar (frame + clipped fill), was gohud GoBar
var kills_label: Label
var deaths_label: Label
var players_label: Label
var weapon_icon: TextureRect
var weapon_label: Label
var grenade_label: Label
var timer_label: Label
var score_label: Label
var message_label: Label
var host_ip_label: Label
var scoreboard_panel: PanelContainer
var scoreboard_list: VBoxContainer
var pause_panel: PanelContainer
var end_panel: PanelContainer
var end_title: Label
var end_list: VBoxContainer
var _end_box: VBoxContainer # Phase 4: MVP banner is inserted here
var _mvp_nodes: Array = [] # Phase 4: banner widgets, cleared per match
var end_rematch_btn: Button
var end_hint: Label # QA-145 (v4.1, Worker V): what-happens-next line under Rematch (host vs non-host text set in game_match.gd)
var error_panel: PanelContainer
var error_label: Label
var move_stick
var aim_stick
var grenade_button: Button
var switch_button: Button
var reload_button: Button # v2.4
var pause_button: Button
var score_button: Button
var _topright_btn_row: HBoxContainer # QA-057: SCORE + pause live in the top-right panel
var hint_label: Label
var bullet_pool: BulletPool # v2.4: pooled bullets
var shooting_sync: ShootingSync # v2.4: host-side fire-rate/ammo validation
var skyfall_builder: SkyfallBuilder # QA-139 (v3.15): Skyfall map building (was game.gd)
var skyfall_dynamics: SkyfallDynamics # QA-139 (v3.15): Skyfall runtime (hazards, storm, movers, FX)
var skyfall_hazards: SkyfallHazards # QA-140 (v3.15): Skyfall hazards (collapsing, trapdoors, rocks, pendulums, barricades)
var skyfall_powerups: SkyfallPowerups # QA-139 (v3.15): Skyfall power-up slots + targeting
var skyfall_ctf: SkyfallCtf # QA-139 (v3.15): Vertical CTF (Skyfall only)
var arena_builder: ArenaBuilder # QA-139 (v3.15): arena + background + hazards building
var hud_builder: HudBuilder # QA-139 (v3.15): HUD / menus / touch controls building
var hud_screens: HudScreens # QA-140 (v3.15): HUD screens (pause, end, scoreboard, error, weapon panel)
var game_fx: GameFx # QA-140 (v3.15): FX (impact, pickup, dust, explosion)
var game_match: GameMatch # QA-140 (v3.15): match flow (countdown, timer, round end, end screen)
var game_feed: GameFeed # QA-140 (v3.15): kill feed, spectator, broadcast
var game_hud: GameHud # QA-140 (v3.15): HUD updates, scoreboard, net stats
var game_touch: GameTouch # QA-140 (v3.15): touch controls + input
var game_spawn: GameSpawn # QA-140 (v3.15): spawn, player list, peer handlers, bullet pool
var game_pickups: GamePickups # QA-140 (v3.15): pickup spawning + join timeout
var skyfall_helpers: SkyfallHelpers # QA-140 (v3.15): skyfall route/level/powerup-target helpers
var smoke_test: SmokeTest # QA-140 (v3.15): smoke test + screenshot drivers
var workerS_shots: WorkerSShots # QA-145 (v4.1, Worker S): staged trap/route screenshots
var workerT_shots: WorkerTShots # QA-145 (v4.1, Worker T): staged mine/beacon/streak screenshots
var workerV_shots: WorkerVShots # QA-145 (v4.1, Worker V): staged end-screen + capture-feed screenshots
var joystick_test: JoystickTest # QA-140 (v3.15): joystick acceptance test
var scale_test: ScaleTest # QA-140 (v3.15): scale + collision acceptance test
var fire_test: FireTest # QA-140 (v3.15): fire acceptance test
var net_test: NetTest # QA-140 (v3.15): net/flow/restart/jointest/perftest
var replsim_test: ReplsimTest # QA-140 (v3.15): replication-sim test (cases 0-21)
var physics_test: PhysicsTest # QA-140 (v3.15): physics acceptance test
var features_test: FeaturesTest # QA-140 (v3.15): features acceptance test
var features_skyfall_test: FeaturesSkyfallTest # QA-140 (v3.15): Skyfall features (CTF, powerups, paths)
var features_skyfall_traps: FeaturesSkyfallTraps # QA-140 (v3.15): Skyfall features (traps, hazards, events)
var net_test_steps: NetTestSteps # QA-140 (v3.15): net test step list builder
var max_players: int = 8 # room setting (GameData); MAX_PLAYERS is the cap

# Touch input state, read by the local player.
# v2.2: the left stick is a full 2D vector now (x = move, y = jump/fly).
# There is no JUMP button any more — pushing the left stick up jumps,
# holding it up while airborne is the jetpack.
# v3.2: firing comes from the AIM stick (Mini Militia style) — the
# right stick aims AND fires while held (see _update_touch_state).
# There is no FIRE button any more (CONTROLS_CHANGE.md).
var touch_move_vec: Vector2 = Vector2.ZERO
var touch_aim: Vector2 = Vector2.ZERO
var touch_aim_active: bool = false
var touch_firing: bool = false

var _move_touch_id: int = -1
var _aim_touch_id: int = -1
# QA-054: when the last touch ended (msec clock). The mouse-aim
# fallback in player.gd must never fire from a touch Godot emulated
# as a mouse press — touch_recently_used() is true while any stick
# is held and for 500 ms after the last touch ends, so even a stale
# emulated button-up in the release frame cannot swing the aim.
var _last_touch_msec: int = -1000000
# v3.2 right-stick fire (CONTROLS_CHANGE.md §2): semi-auto weapons fire
# once per fresh ZERO -> non-zero transition of the aim vector. The
# transition arms one pending shot (QA-027 carry-over: a flick fires
# even if the finger is gone by the time the shooting step runs);
# the shooting step consumes it, reload/respawn/pause/countdown
# discard it. Auto weapons ignore the flag and fire on touch_firing.
var _aim_fire_pending: bool = false
var _aim_vec_prev_nonzero: bool = false
var _next_index: int = 1
var _spawned: Dictionary = {}
var _spawn_data: Dictionary = {} # v3.2 QA-047: pid -> spawn data dict, kept so the server can re-send a spawn (retry / late joiner) and answer player-list requests.
var _server_answered: bool = false # v3.2 QA-047: any spawn/list packet received from the server (shown in the join error so a Wi-Fi problem can be told apart from a game bug).
var _udp_broadcast: PacketPeerUDP
var _udp_broadcast_sockets: Array[PacketPeerUDP] = [] # v2.4: one socket per broadcast address
var _broadcast_timer: float = 0.0
var _pickup_timer: float = 0.0
# Phase 5 — pinned centre weapon: pickups[3] is the centre spot on
# every map; it spawns ONLY Sniper (3) / Rocket (4), alternating,
# and the HUD shows a visible timer for the next one.
var _centre_kind_next: int = 3 # Sniper first, then Rocket, alternating
var _centre_label: Label
var _ctf_flag_labels: Array = [] # QA-112 (v3.9): RED/BLUE flag status lines (CTF only)
var _sf_slot_buttons: Array = [] # QA-119 (v3.11): 3 tappable power-up slot Buttons (top-right)
var _sf_slot_panel: PanelContainer # QA-119 (v3.11): top-right slot panel (visibility toggle)
var _sf_active_boost_label: Label # QA-112 (v3.9): active boost + time left
var _sf_slot_row: HBoxContainer # QA-112 (v3.9): the 3-slot row (inside the top-right panel)
# Phase 3B physics systems (GAP-37/45/51/64/66):
var _pickup_spot_timers: Dictionary = {} # spot index -> seconds until respawn
var _damage_event_seq: int = 0 # unique damage event ids (GAP-43)
# QA-031 (T-56): host-side kill-credit lock. Two shooters landing
# lethal hits on the same victim in the same moment used to both
# credit a kill: the host reads the victim's replicated health,
# stale by ~33 ms + latency, so both hits computed lethal. The first
# credit locks the victim (peer id -> lock msec); a second credit
# inside KILL_CREDIT_LOCK_MS is denied. The lock expires after 1 s
# so a later genuine kill in the victim's next life is never blocked
# (respawn takes 3 s, and the lock is also cleared on disconnect /
# round reset). Server-only: only the host ever populates it.
var _kill_credit_lock: Dictionary = {}
const KILL_CREDIT_LOCK_MS: int = 1000
var _barrels: Array = [] # {rect, sprite, shape, hp, alive} (GAP-64)
var _bounce_pads: Array = [] # {rect, area, cooldowns{peer: t}} (GAP-66)
# ---------------------------------------------------------------------------
# QA-112 (v3.9) — SKYFALL: Vertical CTF (mode 4, Skyfall-only) + the
# climbing mechanics. Restored from the v3.6 CTF (QA-080, git
# e972393) and adapted: both flags live at the SUMMIT, captures
# score at the base EXTRACTION ZONES, grabbing takes a 1.5 s hold,
# a dropped flag returns after 15 s, the carrier is 15% slower
# with no jetpack (player.gd reads carrying_flag). Clients never
# decide flag state — the host syncs it on ctf_sync (0.5 s
# heartbeat + on change), exactly like v3.6.
# ---------------------------------------------------------------------------
var _ctf_flags: Array = [] # {team, home, pos, carrier, dropped, node, sprite}
var _ctf_scores: Dictionary = {0: 0, 1: 0} # captures per team
var _ctf_captures: Dictionary = {} # peer id -> captures (scoreboard)
var _ctf_sync_timer: float = 0.0
var _ctf_grab: Dictionary = {} # peer id -> seconds held on a flag
var _ctf_dropped_timer: Dictionary = {} # flag team -> seconds dropped
var _ctf_checkpoints: Dictionary = {0: 0, 1: 0} # team -> highest level 0-3
var _ctf_hold_grace: Dictionary = {0: 0.0, 1: 0.0} # QA-114 (v3.9): 5 s freeze before a wiped team's checkpoint drops
var _ctf_extract_nodes: Array = [] # extraction-zone sprites (pulse)
var _ctf_hud_labels: Array = [] # flag-status labels (rebuilt in _build_hud)
# Skyfall mechanics state (all host-driven, rendered on every peer).
var _sf_elevators: Array = [] # {body, sprite, cfg, phase}
var _sf_rotator: Dictionary = {} # {body, sprite, cfg, angle}
var _sf_summit_elevator: Dictionary = {} # {body, sprite, cfg, state, timer}
var _sf_collapsing: Array = [] # {idx, shape, sprite, state, timer}
var _sf_trapdoors: Array = [] # {idx, shape, spr_closed, spr_open, state, timer}
var _sf_gate_shape: CollisionShape2D = null # summit gate (removed on open)
var _sf_gate_sprite: Sprite2D = null
var _sf_gate_open: bool = false
var _sf_gate_timer: float = 0.0 # opens 45 s after match start
var _sf_switch_on: bool = false # control switch pressed (visual)
var _sf_switch_timer: float = 0.0 # 1 s stand-on channel
var _sf_summit_timer: float = 0.0 # summit elevator active time left
var _sf_comeback_team: int = -1 # QA-114 (v3.9): team trailing by >= 2 pts — gets catch-up help
var _sf_comeback_pu_timer: float = 0.0 # QA-114: bonus power-up timer for the trailing team (25 s)
var _sf_event_timer: float = 0.0 # QA-114 (v3.9): countdown to the next RANDOM event (45-90 s)
var _sf_event_active: String = "" # QA-114: current random event ("" = none)
var _sf_event_time_left: float = 0.0 # QA-114: seconds left on the current event
var _sf_event_wind_flip: bool = false # QA-114: route-shift flips the wind for 20 s
var _sf_event_collapse_idx: int = -1 # QA-114: platform collapsed by the random event
var _sf_scenery: Dictionary = {} # QA-115 (v3.9): dynamic scenery nodes (clouds, waterfall, heli, gears, steam, flash)
var _sf_pings: Array = [] # QA-114 (v3.9): active team pings {node, label, pos, timer}
var _sf_ping_cooldown: float = 0.0 # QA-114: 3 s between pings
var ping_button: Button # QA-114 (v3.9): PING button (Skyfall only)


# QA-135 (v3.13): Wind Blast / Thunder Strike targeting — the
# target enemy must be (1) standing on the SAME PLATFORM as the
# activator AND (2) at the SAME HEIGHT (within
# SF_POWERUP_HEIGHT_TOL px — both stand on the same platform
# surface, so this excludes an enemy jetpacking high above the
# platform or hanging below it).
const SF_POWERUP_HEIGHT_TOL := 60.0
func _sf_platform_under(pos: Vector2) -> int:
	return skyfall_powerups._sf_platform_under(pos)


# QA-143 (v4.0): merged-surface identity (see skyfall_powerups.gd)
# — the "same platform" Wind Blast / Thunder Strike targeting
# compares, seam- and mover-aware.
func _sf_surface_under(pos: Vector2) -> String:
	return skyfall_powerups._sf_surface_under(pos)


func _sf_surface_rect_under(pos: Vector2) -> Rect2:
	return skyfall_powerups._sf_surface_rect_under(pos)


func _sf_find_powerup_target(activator: Node2D, kind: int = 0) -> Node2D:
	return skyfall_powerups._sf_find_powerup_target(activator, kind)


var _sf_barricades: Array = [] # {rect, sprite, shape, hp, alive, timer}
var _sf_mines: Array = [] # QA-145 (v4.1, Worker T): {pos, node, dot, state, timer} proximity mines
var _sf_beacon: Dictionary = {} # QA-145 (v4.1, Worker T): supply-drop beacon {pos, beam, ring, timer}
var _sf_rocks: Array = [] # {node, vel} falling rocks (host spawns)
var _sf_rock_timer: float = 0.0
var _sf_storm_timer: float = 90.0 # Summit Storm every 90 s
var _sf_storm_active: bool = false
var _sf_storm_time_left: float = 0.0
var _sf_storm_nodes: Array = [] # lightning sprites shown during a storm
var _sf_pickup_timers: Dictionary = {} # skyfall power-up spot -> seconds
# QA-126 (v3.11): hazard damage state. Host-only damage ticks;
# visuals are pure functions of the match clock so all peers agree.
var _sf_hazard_tick: Dictionary = {} # peer id -> seconds until next hazard tick
var _sf_strike_timer: float = 3.0 # seconds until the next storm lightning strike
var _sf_strike: Dictionary = {} # pending strike {peer, pos, node, ring, timer}
# QA-135 (v3.13): L4 is the storm-lightning level — its own strike
# system, independent of the Summit Storm: a bolt every 6 s at a
# random living player in L4 (y 3600-5400), same 0.6 s telegraph
# and 15 HP as the storm strikes (QA-126).
var _sf_strike_l4_timer: float = 6.0 # seconds until the next L4 lightning strike
var _sf_strike_l4: Dictionary = {} # pending L4 strike {peer, pos, ring, bolt, timer}
# QA-143 (v4.0) ITEM 9/11: still-tracking state (host only) —
# peer id -> last-known position / match-time of the last move
# (> 4 px). ITEM 11: pending L5 thunder-trap strike
# {peer, pos, timer} — the 0.6 s telegraph is RPC'd to all peers.
var _sf_still_pos: Dictionary = {}
var _sf_still_since: Dictionary = {}
var _sf_trap_l5: Dictionary = {}
var _wind_tornado_node: Node2D = null # QA-135: the active Wind Blast tornado (tests read it)
var _sf_hazard_fx: Array = [] # {kind, rect, flame, lava, magma} hazard visuals
var _sf_pendulums: Array = [] # QA-137: {pivot, len, node, chain, ball, angle, tick} swinging wrecking balls
# QA-129 (v3.11): bridge wind gusts — every 15 s the bridge wind
# doubles for 3 s (pure function of the match clock, so every peer
# agrees; see skyfall_wind_at).
var _sf_gust_fx: Array = [] # sweeping gust sprites (bridge wind zone)
var _sf_initial_powerups_done: bool = false
var _sf_match_time: float = 0.0 # seconds since countdown ended
var _sf_boost_slots: Array = [] # HUD power-up slot icons (3)
# QA-112 (v3.9): spawn counters for the FT-SF-RARITY test (power-ups
# must spawn less often than weapons). Read by the features test
# only; they cost nothing in normal play.
var _test_weapon_spawns: int = 0
var _test_powerup_spawns: int = 0
var _initial_pickups_done: bool = false
var _local_player: Node = null
var _join_timer: float = 0.0
var _join_failed: bool = false
var _ready_announced: bool = false
var _time_left: float = 300.0
var _time_sync_timer: float = 0.0
var _end_shown: bool = false
var _hint_timer: float = 10.0
var _lava_cd: Dictionary = {} # peer id -> seconds until next lava damage tick
# QA-145 (v4.1): Volcanic Cavern fire traps (QA-126 rules, built +
# updated in arena_builder.gd — this is state only, no logic).
# _fire_trap_fx: {rect, kind, flame, base, cycle} visuals;
# _fire_trap_tick: peer id -> seconds until next 10 HP trap tick;
# _fire_trap_time: local match clock driving the 4 s HOT/safe cycle
# (same pattern as _sf_match_time — visuals are pure functions of
# it so every peer sees the same telegraph).
var _fire_trap_fx: Array = []
var _fire_trap_tick: Dictionary = {}
var _fire_trap_time: float = 0.0
var _round_wins: Dictionary = {} # v2.4 Survival: peer id -> rounds won
# Phase 4 — kill feed, streaks, countdown, hitmarkers, spectator.
var _kill_feed_list: VBoxContainer
var _invis_warning_chip: PanelContainer = null # QA-121 (v3.11): red "Enemy is invisible!" chip (top of the feed)
var _kill_feed_entries: Array = [] # {label, expiry}
var _kill_streaks: Dictionary = {} # peer id -> current kill streak
var _best_streaks: Dictionary = {} # peer id -> best kill streak this match
var _first_blood_done: bool = false # QA-145 (v4.1, Worker T): first real kill of the match already announced
var _fed_deaths: Dictionary = {} # peer id -> true once this death was fed (no double entries)
var _alive_watch: Dictionary = {} # peer id -> was alive last frame (host death watcher)
var _countdown_active: bool = false
var _countdown_t: float = 0.0
var _countdown_last_shown: int = -1
var _fight_timer: float = 0.0
var _countdown_label: Label
var _countdown_sub: Label
var _hitmarker_label: Label
var _hitmark_timer: float = 0.0
var _last_hitmark_seq: int = 0
var fps_label: Label
var _spectate_cam: Camera2D
var _spectate_label: Label
var _spectate_next_btn: Button
var _spectate_target: Node = null
var _spectate_idx: int = 0
var _spectating: bool = false
var _weapon_panel: PanelContainer
var _weapon_list: VBoxContainer
# Phase 4 — features test harness (--features-test).
var _round_number: int = 1 # v2.4 Survival: current round
var _kd_label: Label # QA-079: slim "K 3 • D 1" line under the score, always visible
var _pause_info_label: Label # QA-113 (v3.9): map • mode • time left line in the pause menu
var _sfx_value_label: Label # QA-113 (v3.9): "75%" next to the Sound slider
var _music_value_label: Label # QA-113 (v3.9): "75%" next to the Music slider
var _stats_recorded: bool = false # QA-078: record_match runs once per match
var _spawn_retry_timer: float = 0.0 # v2.4: request_spawn retry clock
# v3.2 two-peer join regression test (--join-test-host / --join-test-client).
var _join_test_timer: float = 0.0
var _join_test_done: bool = false
var _join_test_status_t: float = 0.0
var _join_test_moved: bool = false
var _join_test_pos_snap: Dictionary = {}
# v3.2 QA-047 — replication simulation harness (--repl-sim-test).
# True two-peer ENet cannot run in the sandbox (the OS blocks UDP
# sends), so this simulates the wire in one process: a server game
# instance plus a shadow client instance, with the server's spawn /
# list payloads delivered to the shadow by hand. It proves the
# handler logic and the retry re-send; it does NOT prove live ENet
# delivery — that still needs two real phones (see BUGS.md QA-047).
# QA-073: dev-only network-stats display (spec §7). Hidden by
# default — never visible in normal play. Enabled with the
# --net-stats flag or the F3 key (desktop/dev). Shows ping/RTT,
# packet loss, updates/s, buffer size, interpolation delay,
# extrapolation time, local vs authoritative position, FPS.
var _net_stats_label: Label = null
var _net_stats_visible: bool = false
var _net_stats_timer: float = 0.0
# QA-073: host-side divergence guard (spec §4). Per-peer seconds
# the host's rendered copy has sat >300 px from the newest snapshot
# while the stream stayed fresh; _diverge_corr_seq numbers the
# corrections so a stale one is ignored on the client.
var _diverge_time: Dictionary = {}
var _diverge_timer: float = 0.0
var _diverge_corr_seq: int = 0
var _nt_dc_kills_a: int = 0 # QA-031 double-credit test state
var _nt_dc_first: bool = false
var _nt_dc_second: bool = false
# v2.4 full-flow check: handed over from the menu via GameData
# (flow_phase 1 = in the match). The menu prints the final result
# when we return (phase 2).
var _map_timer: float = 0.0
var _map_stage: int = -1
var _sf_shot_timer: float = 0.0 # QA-112 (v3.9): --skyfall-shots stage clock
var _sf_shot_stage: int = -1 # QA-112 (v3.9): --skyfall-shots stage
var _land_timer: float = 0.0
var _land_stage: int = -1
var _land_armed: bool = false
var _land_t0: float = 0.0
var _land_maxfall: float = 0.0
var _gs_timer: float = 0.0
var _gs_stage: int = -1
# v3.5 restart check (--restart-test, QA-060): start a match, leave
# it, start a SECOND match from the menu, end it, rematch (scene
# reload) and play again. Counts live in GameData so they survive
# the scene changes; the phase does too (see game_data.gd).


var _restart_steps: Array = []
var _restart_step: int = 0
var _restart_in_step: bool = false
var _restart_timer: float = 0.0
var _restart_done: bool = false


func _ready() -> void:
	add_to_group("game")
	# v3.2 NEON ARENA: wire the gohud theme once, early, so the HUD
	# and dialogs inherit it (same preset as the menu in main.gd).
	GoUi.config = preload("res://ui/gohud_config.tres")
	GoUi.use_preset(GoThemePresets.SCIFI_DARK)
	process_mode = Node.PROCESS_MODE_ALWAYS
	map_id = clampi(GameData.map_id, 0, MAPS.size() - 1)
	game_mode = GameData.game_mode
	# QA-112 (v3.9): CTF (mode 4) exists ONLY on Skyfall. A stale
	# mode 4 from another map (or an old lobby) falls back to FFA
	# here, so CTF can never start on the wrong map — the same
	# guard the lobby applies in main.gd.
	if game_mode == 4 and map_id != GameData.SKYFALL_MAP_ID:
		game_mode = 0
	kill_limit = GameData.kill_limit
	max_players = clampi(GameData.max_players, 2, MAX_PLAYERS)
	_time_left = float(GameData.match_minutes * 60)
	# QA-140 (v3.15): test modules are built BEFORE the flag parsing
	# below, so the flags (which now live on the test modules)
	# can be set here.
	smoke_test = SmokeTest.new(self)
	workerS_shots = WorkerSShots.new(self)
	workerT_shots = WorkerTShots.new(self)
	workerV_shots = WorkerVShots.new(self)
	joystick_test = JoystickTest.new(self)
	scale_test = ScaleTest.new(self)
	fire_test = FireTest.new(self)
	net_test = NetTest.new(self)
	replsim_test = ReplsimTest.new(self)
	physics_test = PhysicsTest.new(self)
	features_test = FeaturesTest.new(self)
	features_skyfall_test = FeaturesSkyfallTest.new(self)
	features_skyfall_traps = FeaturesSkyfallTraps.new(self)
	net_test_steps = NetTestSteps.new(self)
	smoke_test._smoke_test = "--smoke-test" in OS.get_cmdline_user_args()
	joystick_test._joystick_test = "--joystick-test" in OS.get_cmdline_user_args()
	fire_test._fire_test = "--fire-test" in OS.get_cmdline_user_args()
	net_test._net_test = "--net-test" in OS.get_cmdline_user_args()
	net_test._flow_test = GameData.flow_test and GameData.flow_phase == 1
	scale_test._scale_test = "--scale-test" in OS.get_cmdline_user_args()
	scale_test._collision_test = "--collision-test" in OS.get_cmdline_user_args()
	physics_test._physics_test = "--physics-test" in OS.get_cmdline_user_args()
	net_test._perf_test = "--perf-test" in OS.get_cmdline_user_args()
	features_test._features_test = "--features-test" in OS.get_cmdline_user_args()
	smoke_test._game_shots = "--game-shots" in OS.get_cmdline_user_args()
	smoke_test._v37_shots = "--v37-shots" in OS.get_cmdline_user_args()
	smoke_test._v38_shots = "--v38-shots" in OS.get_cmdline_user_args()
	smoke_test._glitch_shots = "--glitch-shots" in OS.get_cmdline_user_args()
	smoke_test._map_shots = "--map-shot" in OS.get_cmdline_user_args()
	smoke_test._land_shots = "--land-shot" in OS.get_cmdline_user_args()
	smoke_test._skyfall_shots = "--skyfall-shots" in OS.get_cmdline_user_args() # QA-112 (v3.9): --skyfall-shots captures the 6 Skyfall levels
	smoke_test._qa145_shots = "--qa145-shots" in OS.get_cmdline_user_args() # QA-145: --qa145-shots captures the reload magazine drop (rifle + sniper) + the MMC camera offset while aiming
	workerS_shots._workerS_shots = "--workerS-shots" in OS.get_cmdline_user_args() # QA-145 (v4.1, Worker S): --workerS-shots + --shot-pos=x,y captures staged trap/route views
	workerT_shots._workerT_shots = "--workerT-shots" in OS.get_cmdline_user_args() # QA-145 (v4.1, Worker T): --workerT-shots + --shot-pos=x,y [--shot-beacon=x,y] [--shot-streak] captures staged mine/beacon/streak views
	workerV_shots._workerV_shots = "--workerV-shots" in OS.get_cmdline_user_args() # QA-145 (v4.1, Worker V): --workerV-shots captures the staged end screen + capture feed line
	smoke_test._join_test_host = "--join-test-host" in OS.get_cmdline_user_args()
	smoke_test._join_test_client = "--join-test-client" in OS.get_cmdline_user_args() or "--join-test-client-quick" in OS.get_cmdline_user_args()
	replsim_test._repl_sim_test = "--repl-sim-test" in OS.get_cmdline_user_args()
	net_test._restart_test = "--restart-test" in OS.get_cmdline_user_args()
	# QA-073: dev-only net-stats panel (spec §7). Off by default;
	# --net-stats turns it on for a dev session, F3 toggles it live.
	_net_stats_visible = "--net-stats" in OS.get_cmdline_user_args()
	# Test-only map override: --map=N loads that map (the collision
	# test uses it to run its pass-through checks on Outpost).
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			map_id = clampi(int(a.trim_prefix("--map=")), 0, MAPS.size() - 1)
		elif a.begins_with("--perf-seconds="):
			net_test._perf_seconds = maxf(10.0, float(a.trim_prefix("--perf-seconds=")))
		elif a.begins_with("--perf-bots="):
			net_test._perf_bots = clampi(int(a.trim_prefix("--perf-bots=")), 0, 11)
	audio = AUDIO_SCRIPT.new()
	add_child(audio)
	audio.set_volumes(GameData.sfx_volume, GameData.music_volume)
	audio.set_music_enabled(GameData.music_enabled)
	audio.set_sfx_enabled(GameData.sfx_enabled)
	# Phase 6: the match plays the battle track. The menu scene owns
	# the menu track; leaving the match stops this one (see
	# _on_leave_pressed) so music never overlaps or plays on.
	audio.play_battle_music()
	# Phase 4 — spectator camera (Survival/LMS): off until the local
	# player dies with no respawn coming (see _update_spectator).
	_spectate_cam = Camera2D.new()
	_spectate_cam.name = "SpectateCam"
	_spectate_cam.enabled = false
	add_child(_spectate_cam)
	# Phase 4 — match countdown (3-2-1-FIGHT). Skipped in every
	# scripted harness (they move/shoot from frame one) and in the
	# features test, which drives the countdown itself in step 1.
	var _is_test_mode := smoke_test._smoke_test or joystick_test._joystick_test or fire_test._fire_test or net_test._net_test or net_test._flow_test or scale_test._scale_test or scale_test._collision_test or physics_test._physics_test or net_test._perf_test or features_test._features_test or replsim_test._repl_sim_test or net_test._restart_test or smoke_test._v37_shots or smoke_test._v38_shots or smoke_test._glitch_shots or smoke_test._map_shots or smoke_test._land_shots or smoke_test._skyfall_shots or smoke_test._qa145_shots or workerS_shots._workerS_shots or workerT_shots._workerT_shots or workerV_shots._workerV_shots
	if not _is_test_mode:
		_countdown_active = true
		_countdown_t = 3.0
		_countdown_last_shown = -1
	var map: Dictionary = MAPS[map_id]
	map_size = map["size"]
	# QA-139 (v3.15): system modules are built here, before any of
	# their build/update functions run. Each holds a reference to
	# this game node and owns no state of its own.
	skyfall_builder = SkyfallBuilder.new(self)
	skyfall_dynamics = SkyfallDynamics.new(self)
	skyfall_hazards = SkyfallHazards.new(self)
	skyfall_powerups = SkyfallPowerups.new(self)
	skyfall_ctf = SkyfallCtf.new(self)
	arena_builder = ArenaBuilder.new(self)
	hud_builder = HudBuilder.new(self)
	hud_screens = HudScreens.new(self)
	game_fx = GameFx.new(self)
	game_match = GameMatch.new(self)
	game_feed = GameFeed.new(self)
	game_hud = GameHud.new(self)
	game_touch = GameTouch.new(self)
	game_spawn = GameSpawn.new(self)
	game_pickups = GamePickups.new(self)
	skyfall_helpers = SkyfallHelpers.new(self)
	_build_background(map)
	_build_arena(map)
	_build_ice_zone(map)
	_build_bounce_pads(map)
	_build_lava(map)
	_build_fire_traps(map) # QA-145 (v4.1): Volcanic Cavern fire traps (no-op on other maps)
	_build_ambient_fx(map)
	# QA-112 (v3.9): Skyfall mechanics + CTF flags (no-op on other maps).
	_build_skyfall(map)
	arena_builder._build_nodes()
	# v2.4: bullet pool + host-side shooting validation live on the game.
	bullet_pool = BulletPool.new(BULLET_SCENE, bullets_node, 160) # GAP-67: 96 = 12/player at 8 players, below the 16-32 spec budget
	shooting_sync = ShootingSync.new()
	_build_hud()
	_build_touch_controls()
	_countdown_sub.text = game_match._match_goal_text()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if multiplayer.is_server():
		game_feed._start_broadcast()
		# Host spawns its own player now that the spawner exists.
		game_spawn.call_deferred("_spawn_self")
	else:
		# Client: tell the server we are ready ONLY now that our scene
		# (and its MultiplayerSpawner) exists. This is the v2 join fix.
		call_deferred("_announce_ready")
	game_hud._update_host_ip_label()


# --- Bullet pool (v2.4) ---


func _build_background(map: Dictionary) -> void:
	arena_builder._build_background(map)


# QA-030: solid decor kinds — these are real cover. They get a
# collision rectangle on layer 1 (the same layer the bullet raycast
# and the player use), so bullets stop at them and players cannot walk
# through them. Everything else (trees, palms, bushes, bridges,
# arches) stays visual dressing with no collision, exactly as before.
const SOLID_DECOR_KINDS := ["crate", "barrels", "sandbags", "rock", "column",
	"jpillar", "jstatue", "jtower", "jcrate", "jrock",
	# Phase 5 — Sky Brawl solid structures (huts/blocks/vents/crate).
	"sb_hut", "sb_hut_pink", "sb_hut_blue", "sb_vent", "sb_vent_orange",
	"sb_shrine", "sb_block", "sb_hut_green", "sb_crate",
	# QA-096: Ironfall solid props (crate / barrel / sandbags).
	"if_crate", "if_barrel", "if_sandbags",
	# QA-112 (v3.9): Skyfall sniper tower — solid cover (256x384).
	"sf_tower"]
# GAP-13: bridges/arches look walkable — they now get a thin top plank
# (24 px at the sprite's top edge), not the full texture.
const BRIDGE_DECOR_KINDS := ["bridge", "jbridge", "jarch"]


func _build_arena(map: Dictionary) -> void:
	arena_builder._build_arena(map)


func _build_ice_zone(map: Dictionary) -> void:
	arena_builder._build_ice_zone(map)


func _build_bounce_pads(map: Dictionary) -> void:
	arena_builder._build_bounce_pads(map)


func try_barrel_hit(hit_pos: Vector2, dmg: int, owner_id: int) -> bool:
	return arena_builder.try_barrel_hit(hit_pos, dmg, owner_id)


@rpc("any_peer", "call_local")
func barrel_destroyed_remote(idx: int) -> void:
	arena_builder.barrel_destroyed_remote(idx)


func _build_lava(map: Dictionary) -> void:
	arena_builder._build_lava(map)


func _build_fire_traps(map: Dictionary) -> void:
	arena_builder._build_fire_traps(map)


func _update_fire_traps(delta: float) -> void:
	arena_builder._update_fire_traps(delta)


func _build_ambient_fx(map: Dictionary) -> void:
	arena_builder._build_ambient_fx(map)


func _update_skyfall(delta: float) -> void:
	skyfall_dynamics._update_skyfall(delta)


func _sf_trailing_team() -> int:
	return skyfall_dynamics._sf_trailing_team()


@rpc("any_peer", "call_local")
func sf_rock_remote(x: float) -> void:
	skyfall_hazards.sf_rock_remote(x)


@rpc("any_peer", "call_local")
func sf_mine_trigger_remote(idx: int) -> void:
	skyfall_hazards.sf_mine_trigger_remote(idx)


@rpc("any_peer", "call_local")
func sf_beacon_remote(pos: Vector2) -> void:
	skyfall_dynamics._sf_build_beacon(pos)


func _sf_clear_strike_marker() -> void:
	skyfall_dynamics._sf_clear_strike_marker()


func _sf_clear_strike_l4_marker() -> void:
	skyfall_dynamics._sf_clear_strike_l4_marker()


@rpc("any_peer", "call_local")
func show_wind_tornado_fx(pos: Vector2) -> void:
	skyfall_dynamics.show_wind_tornado_fx(pos)


# --- Skyfall power-ups: RARER than weapons (user rule, 2026-11-20).
# Weapons: 6 spots, 14 s respawn, max 3 active, 3 at match start.
# Power-ups (QA-132): 7 spots (one per kind), 30 s respawn, max 4
# active (was 2), 3 at match start spread across the heights (was
# 1 random spot) — low L1, mid L3, high L6 — and a 30 s pickup
# lifetime (was 20 s, see pickup.gd). The respawn was 15 s in the
# first QA-132 pass, but the FT-SF-RARITY sim then counted MORE
# power-ups than weapons in 300 s (106 vs 93) — the loop spawns
# one per frame up to the active cap, so a 15 s cooldown refills
# the cap every clear-window. At 30 s the spots re-arm staggered
# (~60 in the sim) while a real match still keeps up to 4 on the
# tower at once — a climbing player still meets a power-up about
# every level instead of almost never seeing one.
# ---------------------------------------------------------------------------
const SF_POWERUP_COOLDOWN := 30.0
const SF_POWERUP_MAX_ACTIVE := 4
# Match-start spread: one low (spot 0, Jetpack, L1), one mid
# (spot 3, Thunder, L3), one high (spot 5, Speed, L6).
# QA-143 (v4.0): Health Potion removed — the old [0, 4, 6] pointed
# at the deleted kind-7 spot (0) and past the end of the 6-spot list.
const SF_POWERUP_INITIAL_SPOTS: Array[int] = [0, 3, 5]


func _update_skyfall_powerups(delta: float) -> void:
	skyfall_powerups._update_skyfall_powerups(delta)


func _spawn_skyfall_powerup(spot_idx: int) -> void:
	skyfall_powerups._spawn_skyfall_powerup(spot_idx)


func _draw_tiles(map: Dictionary, platforms: Array) -> void:
	skyfall_builder._draw_tiles(map, platforms)

func _build_skyfall(map: Dictionary) -> void:
	skyfall_builder._build_skyfall(map)


func _sf_arena_shape_at(center: Vector2) -> CollisionShape2D:
	return skyfall_builder._sf_arena_shape_at(center)


func _sf_tile_sprites_at(rect: Rect2) -> Array:
	return skyfall_builder._sf_tile_sprites_at(rect)


func try_barricade_hit(hit_pos: Vector2, dmg: int) -> bool:
	return skyfall_hazards.try_barricade_hit(hit_pos, dmg)


@rpc("any_peer", "call_local")
func sf_barricade_remote(idx: int, alive: bool) -> void:
	skyfall_hazards.sf_barricade_remote(idx, alive)


func _ctf_team_color(team: int) -> Color:
	return skyfall_ctf._ctf_team_color(team)


func _build_ctf_flags() -> void:
	skyfall_ctf._build_ctf_flags()


@rpc("any_peer", "call_local")
func ctf_sync(state: Array, scores: Dictionary, checkpoints: Dictionary = {0: 0, 1: 0}) -> void:
	skyfall_ctf.ctf_sync(state, scores, checkpoints)


func _on_slot_pressed(idx: int) -> void:
	skyfall_powerups._on_slot_pressed(idx)


func _update_invis_warning(lp) -> void:
	skyfall_powerups._update_invis_warning(lp)


func _ctf_feed(text: String, color: Color) -> void:
	skyfall_ctf._ctf_feed(text, color)
	# QA-145 (v4.1, Worker V): a flag capture is the biggest
	# moment in a CTF match, but it arrived as one small 18 px
	# feed line that expired in 5 s like any kill — easy to miss
	# in a fight, and a busy feed could push it out in seconds.
	# Captures and relay banks now stay on screen longer and
	# print bigger; a full capture also plays the win fanfare.
	# (Feed-only: the flag, points and rules are untouched, and
	# the call still funnels through skyfall_ctf._ctf_feed.)
	if text.contains("captured the flag!") or text.contains("banked the flag"):
		var big := text.contains("captured the flag!")
		if not _kill_feed_entries.is_empty():
			var e: Dictionary = _kill_feed_entries[_kill_feed_entries.size() - 1]
			if e.has("label") and String((e["label"] as Label).text) == text:
				e["expiry"] = 10.0 if big else 8.0
				(e["label"] as Label).add_theme_font_size_override("font_size", 22 if big else 20)
		if big and audio != null:
			audio.play("win")


func _update_ctf(delta: float) -> void:
	skyfall_ctf._update_ctf(delta)


func skyfall_ladder_at(pos: Vector2) -> Rect2:
	return skyfall_dynamics.skyfall_ladder_at(pos)


func _sf_gust_active() -> bool:
	return skyfall_dynamics._sf_gust_active()


func _build_hud() -> void:
	hud_builder._build_hud()


var _sf_height_bar: Control # QA-114 (v3.9): vertical HUD height bar (Skyfall only)
var _sf_height_dots: Array = [] # QA-114: 12 player dots on the height bar
var _sf_height_ping_dots: Array = [] # QA-114: 4 ping dots on the height bar
var _sf_comeback_label: Label # QA-114 (v3.9): comeback-help line under the score
var _sf_event_label: Label # QA-114 (v3.9): random-event / storm line under the score


@rpc("any_peer")
func version_mismatch_remote(text: String) -> void:
	_show_error(text)


func _show_error(text: String) -> void:
	_join_failed = true
	error_label.text = text
	error_panel.visible = true
	audio.play("death")


func _on_retry_pressed() -> void:
	error_panel.visible = false
	_join_failed = false
	_join_timer = 0.0
	_spawn_retry_timer = 0.0
	# v3.2 QA-047: Retry re-attempts the whole join, not just the spawn
	# request. If the ENet link is still up, re-request spawn + player
	# list. If the link itself is gone, go back to the menu with the
	# host IP prefilled so the user can rejoin in one tap — a dropped
	# client cannot rejoin a running match from here, because the
	# host's lobby is gone once the match started.
	var peer = multiplayer.multiplayer_peer
	var connected := peer is ENetMultiplayerPeer and (peer as ENetMultiplayerPeer).get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	if connected:
		_ready_announced = false
		game_spawn._announce_ready()
	else:
		GameData.last_host_ip = GameData.host_ip
		_on_leave_pressed()


func _on_leave_pressed() -> void:
	# The scene change is deferred to the end of the frame, but this
	# node's _process would still run once more with `multiplayer`
	# already torn down (script errors in the update tail). Stop it.
	_leaving = true
	get_tree().paused = false
	# Phase 6: stop the battle track here — the menu scene starts its
	# own menu track on load, so music never overlaps or keeps playing
	# after leaving a match.
	if audio != null:
		audio.stop_music()
	# QA-060: close the network resources explicitly instead of
	# relying on the old peer's refcount to drop. A dropped-but-open
	# ENet peer can keep UDP 7777 bound, so the next host attempt in
	# the same process fails with "Couldn't create an ENet host".
	game_feed._stop_broadcast()
	var old_peer := multiplayer.multiplayer_peer
	if old_peer is ENetMultiplayerPeer:
		(old_peer as ENetMultiplayerPeer).close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	get_tree().change_scene_to_file("res://main.tscn")


func _on_rematch_pressed() -> void:
	if multiplayer.is_server():
		rpc("rematch_remote")


@rpc("any_peer", "call_local")
func rematch_remote() -> void:
	get_tree().paused = false
	# QA-060: the reload is synchronous — the rest of THIS frame's
	# _process would otherwise keep running on this (now tree-less)
	# instance, where `multiplayer` is null and every is_server()
	# call in the update tail throws a script error (5 of them, at
	# the rematch boundary). Same guard as _on_leave_pressed.
	_leaving = true
	get_tree().reload_current_scene()


func _on_sfx_volume_changed(v: float) -> void:
	GameData.sfx_volume = v
	GameData.save_settings()
	if _sfx_value_label != null:
		_sfx_value_label.text = "%d%%" % int(v * 100.0)
	if audio != null:
		audio.set_volumes(GameData.sfx_volume, GameData.music_volume)


func _on_music_volume_changed(v: float) -> void:
	GameData.music_volume = v
	GameData.save_settings()
	if _music_value_label != null:
		_music_value_label.text = "%d%%" % int(v * 100.0)
	if audio != null:
		audio.set_volumes(GameData.sfx_volume, GameData.music_volume)


func _build_touch_controls() -> void:
	hud_builder._build_touch_controls()


func _notification(what: int) -> void:
	# QA-016: a touch interrupted by the OS (app switch, notification
	# shade, incoming call, gesture cancel) never delivers a release
	# event. If we did nothing, the last stick vector would stay live
	# forever and the gun would keep firing. Reset all touch state here.
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		game_touch._reset_all_touch_state()
	# QA-060: leaving by any path (leave, rematch reload, error
	# retry) must close the announcement sockets now, not when the
	# RefCounted sockets happen to drop.
	if what == NOTIFICATION_EXIT_TREE:
		game_feed._stop_broadcast()


func _physics_process(_delta: float) -> void:
	# QA-071b: a physics-time clock (seconds of physics, not wall
	# time) — the P01/P02 accel times are wall-clock measurements,
	# and the physics/wall ratio drifts between the two steps under
	# xvfb load (P02 read 0.31 vs 0.27 s, want >1.3x, although the
	# physics times are 0.20 vs 0.115 s = 1.74x). Measuring in
	# physics time makes the ratio load-independent.
	physics_test._phys_data["phys_clock"] = float(physics_test._phys_data.get("phys_clock", 0.0)) + _delta
	# QA-071b: t200 tracking at physics rate. Sampling it in
	# _update_physicstest (idle _process, ~5 Hz under llvmpipe)
	# quantizes the ground/air times to the idle frame period
	# (~0.2 s), hiding the physics difference between ground
	# (3.0x headroom) and air (1.5x headroom) accel — P02 read
	# 0.30 vs 0.27 s (want >1.3x) on map 10. Physics-rate sampling
	# resolves the crossing to one physics step. Test-only: it
	# only reads velocity while tracking is enabled, and changes
	# no gameplay. QA-141: the crossing is 200 px/s, not 300 —
	# MMC's sustained top speed is ~250, so 300 is unreachable.
	if bool(physics_test._phys_data.get("track_t200", false)) and not physics_test._phys_data.has("t200"):
		var lp = _get_local_player()
		if lp != null and lp.velocity.x >= 200.0:
			physics_test._phys_data["t200"] = float(physics_test._phys_data.get("phys_clock", 0.0)) - float(physics_test._phys_data.get("t0_phys", 0.0))
	# QA-071b: min_y at physics rate too — the idle-rate sample missed the
	# brief tap-jump apex by a few px (P07b read 114 vs the hold-40 bound
	# of 113, a 1 px miss on a real 39 px cut).
	if bool(physics_test._phys_data.get("track_min_y", false)):
		var lp2 = _get_local_player()
		if lp2 != null:
			physics_test._phys_data["min_y"] = minf(float(physics_test._phys_data.get("min_y", 1e9)), lp2.position.y)
	# QA-074b: fastest vy sampled WHILE the jetpack is thrusting —
	# the jump's own -220 (QA-141, was -660) must not count, so
	# samples are gated on lp._jetpacking. Sampled here, at physics
	# _update_physicstest: the ~5 Hz idle sample can miss a short
	# climb window entirely (same lesson as track_min_y above).
	if bool(physics_test._phys_data.get("track_min_vy_jet", false)):
		var lp3 = _get_local_player()
		if lp3 != null and lp3._jetpacking:
			physics_test._phys_data["min_vy_jet"] = minf(float(physics_test._phys_data.get("min_vy_jet", 0.0)), lp3.velocity.y)
	# QA-099 (v3.7): pad launch, ungated — the only upward force in
	# the pad step is the pad (no jump input), so a min vy below
	# -600 can only mean the pad fired.
	if bool(physics_test._phys_data.get("track_min_vy_pad", false)):
		var lp4 = _get_local_player()
		if lp4 != null:
			physics_test._phys_data["pad_min_vy"] = minf(float(physics_test._phys_data.get("pad_min_vy", 0.0)), lp4.velocity.y)


# =====================================================================
# QA-145 ITEM 2 — MMC smoothed camera view offset
# (SoldierLocalController::getViewOffsetV4, 0x8ec59c).
# MMC: if a primary weapon exists,
#   t = int(214.3 * primary->getViewOffset() * (2.0 - [SLC, +0x2b4]))
#   [SLC, +0x294] -= t, clamped to [-1.0, 1.0]
#   return int([SLC, +0x294])
# The returned int is the camera's view offset for the frame.
#
# ASSUMPTION (recorded, unproven — see BUGS.md QA-143 ITEM 2):
# [SLC, +0x2b4] semantics were NOT proven in the extraction. This port
# reads it as the WEAPON's +0x2b4 bullet-speed base from the per-class
# table (QA143-workerB-notes.md §3): rifle 1300, smg 1400, shotgun
# 1300, sniper 10000, rocket 1, pistol 1300. Consequence, computed
# not assumed: (2.0 - speedBase) is hugely negative for five weapons
# and exactly +1.0 for the rocket, so the smoothed value SATURATES
# to +1 on the first frame for rifle/smg/shotgun/sniper/pistol and
# to -1 for the rocket. The MMC "smoothing" is degenerate under this
# reading — the ported value is effectively a per-weapon sign, and
# the visible easing comes from MMC_VIEW_EASE_RATE below (so a
# weapon switch never jumps the view in one frame).
#
# PIXEL SCALE (Frag Arena choice, not an MMC number): MMC returns a
# unitless int in [-1, 1]; it is mapped to +/-MMC_VIEW_OFFSET_PX px
# along the aim direction (while aiming) or the facing direction
# (otherwise) — half the 80 px CAMERA_LOOKAHEAD, so it stays a
# subtle lead, not a second look-ahead.
#
# WIRING NOTE: player_visuals._update_visuals ASSIGNS camera.offset
# every frame (shake-or-zero) in the player's _process, which runs
# AFTER game._process — a direct write here would be erased the same
# frame. So game.gd queues a deferred apply (end of frame, after the
# player's _process): it ADDS exactly the wanted offset on top of
# whatever player_visuals wrote, so camera shake survives. Same
# delta-add idea as addons/sprite_juice_lite/screen_shake.gd, except
# no bookkeeping is needed here: player_visuals resets offset
# absolutely every frame, so nothing of ours persists into the next
# frame and a plain += want is exact. If player_visuals.gd ever wires
# this natively (add the offset to _cam_look or to the shake
# assignment), DELETE _apply_mmc_camera_offset below — otherwise the
# offset would apply twice.
# =====================================================================
const MMC_VIEW_OFFSET := {0: 0.45, 1: 0.40, 2: 0.45, 3: 0.70, 4: 0.65, 5: 0.25} # Weapon::getViewOffset (+0x28c)
const MMC_SPEED_BASE := {0: 1300, 1: 1400, 2: 1300, 3: 10000, 4: 1, 5: 1300} # Weapon +0x2b4 (see assumption above)
const MMC_VIEW_OFFSET_PX := 40.0
const MMC_VIEW_EASE_RATE := 240.0 # px/s, same rate as _cam_look

var _mmc_view_s: float = 0.0 # smoothed MMC value ([SLC, +0x294] analogue), [-1, 1]
var _mmc_view_px: float = 0.0 # eased pixel offset actually applied
var _mmc_view_want: Vector2 = Vector2.ZERO # offset vector for this frame
var _mmc_applied_frame: int = -1 # guard: apply at most once per frame


func _process(delta: float) -> void:
	if _leaving:
		return
	if smoke_test._join_test_host or smoke_test._join_test_client:
		net_test._update_jointest(delta)
		if _join_test_done:
			return
	if replsim_test._repl_sim_test:
		replsim_test._update_replsimtest(delta)
		if replsim_test._repl_sim_done:
			return
	if get_tree().paused:
		# Touch state must not stay stale while paused: zero it so the
		# player cannot resume firing from a finger lifted mid-pause.
		game_touch._update_touch_state()
		# The joystick test must still advance while paused (its pause
		# test waits on this timer).
		if joystick_test._joystick_test:
			joystick_test._update_joytest(delta)
		if net_test._flow_test:
			net_test._update_flowtest(delta)
		if smoke_test._game_shots:
			smoke_test._update_gameshots(delta)
		return
	if smoke_test._smoke_test:
		smoke_test._update_smoke_test(delta)
	elif joystick_test._joystick_test:
		game_touch._update_touch_state()
		joystick_test._update_joytest(delta)
	elif fire_test._fire_test:
		game_touch._update_touch_state()
		fire_test._update_firetest(delta)
	elif net_test._net_test:
		game_touch._update_touch_state()
		net_test._update_nettest(delta)
	elif net_test._flow_test:
		game_touch._update_touch_state()
		net_test._update_flowtest(delta)
	elif net_test._restart_test:
		game_touch._update_touch_state()
		net_test._update_restarttest(delta)
	elif scale_test._scale_test:
		game_touch._update_touch_state()
		scale_test._update_scaletest(delta)
	elif scale_test._collision_test:
		game_touch._update_touch_state()
		scale_test._update_collisiontest(delta)
	elif physics_test._physics_test:
		game_touch._update_touch_state()
		physics_test._update_physicstest(delta)
	elif net_test._perf_test:
		game_touch._update_touch_state()
		net_test._update_perftest(delta)
	elif features_test._features_test:
		game_touch._update_touch_state()
		features_test._update_featurestest(delta)
	elif smoke_test._game_shots:
		game_touch._update_touch_state()
		smoke_test._update_gameshots(delta)
	elif smoke_test._v37_shots:
		game_touch._update_touch_state()
		smoke_test._update_v37shots(delta)
	elif smoke_test._v38_shots:
		game_touch._update_touch_state()
		smoke_test._update_v38shots(delta)
	elif smoke_test._glitch_shots:
		game_touch._update_touch_state()
		smoke_test._update_glitchshots(delta)
	elif smoke_test._map_shots:
		game_touch._update_touch_state()
		smoke_test._update_mapshots(delta)
	elif smoke_test._land_shots:
		game_touch._update_touch_state()
		smoke_test._update_landshots(delta)
	elif smoke_test._skyfall_shots:
		game_touch._update_touch_state()
		smoke_test._update_skyfallshots(delta)
	elif smoke_test._qa145_shots:
		game_touch._update_touch_state()
		smoke_test._update_qa145shots(delta)
	elif workerS_shots._workerS_shots:
		game_touch._update_touch_state()
		workerS_shots._update_workerSshots(delta)
	elif workerT_shots._workerT_shots:
		game_touch._update_touch_state()
		workerT_shots._update_workerTshots(delta)
	elif workerV_shots._workerV_shots:
		game_touch._update_touch_state()
		workerV_shots._update_workerVshots(delta)
	else:
		game_touch._update_touch_state()
	# The flow test (or a button) may have started leaving mid-frame
	# — or a rematch reload may have detached this instance from the
	# tree (QA-060). Either way the update tail must not run: on a
	# detached instance `multiplayer` is null.
	if _leaving:
		return
	game_match._update_countdown(delta)
	game_feed._update_kill_feed(delta)
	game_feed._update_hitmarker(delta)
	game_feed._update_death_watcher()
	game_feed._update_spectator(delta)
	_update_hud(delta)
	_update_net_stats(delta) # QA-073: dev-only panel, no-op while hidden
	game_hud._update_divergence_check(delta) # QA-073: host-only, no-op solo/offline
	game_feed._update_broadcast(delta)
	game_pickups._update_pickup_spawn(delta)
	game_pickups._update_join_timeout(delta)
	game_spawn._retry_spawn_if_needed(delta)
	game_match._update_match_timer(delta)
	arena_builder._update_lava(delta)
	_update_fire_traps(delta) # QA-145 (v4.1): Volcanic fire traps (no-op off Volcanic)
	_update_skyfall(delta) # QA-112 (v3.9): CTF + mechanics, no-op off Skyfall
	_update_mmc_camera_offset(delta) # QA-145 ITEM 2: MMC camera view offset, no-op in the menu / while dead


# QA-145 ITEM 2: one MMC getViewOffsetV4 step for the equipped
# weapon. Returns the smoothed value in [-1, 1]. Under the
# speed-base reading this saturates to +1 (rifle/smg/shotgun/
# sniper/pistol) or -1 (rocket) on the first call — see the block
# above _process for the arithmetic.
func _mmc_view_offset_step(weapon_id: int) -> float:
	var vo: float = float(MMC_VIEW_OFFSET.get(weapon_id, 0.45))
	var sb: float = float(MMC_SPEED_BASE.get(weapon_id, 1300))
	var t: int = int(214.3 * vo * (2.0 - sb))
	_mmc_view_s = clampf(_mmc_view_s - float(t), -1.0, 1.0)
	return _mmc_view_s


# QA-145 ITEM 2: compute this frame's camera view offset from the
# local player's weapon and aim, and queue the deferred apply.
# No-ops in the menu (no local player) and while dead (the spectator
# camera is current then). Never touches _cam_look or the smoothing
# speed, so the P19 camera test is unaffected.
func _update_mmc_camera_offset(delta: float) -> void:
	var lp = _get_local_player()
	if lp == null or lp._camera == null or not lp.alive:
		_mmc_view_want = Vector2.ZERO
		_mmc_view_px = 0.0
		return
	var s: float = _mmc_view_offset_step(lp.weapon)
	var dir: Vector2
	if lp._aiming:
		dir = Vector2(cos(lp.aim_angle), sin(lp.aim_angle))
	else:
		dir = Vector2(float(lp.facing), 0.0)
	_mmc_view_px = move_toward(_mmc_view_px, s * MMC_VIEW_OFFSET_PX, delta * MMC_VIEW_EASE_RATE)
	_mmc_view_want = dir * _mmc_view_px
	call_deferred("_apply_mmc_camera_offset")


# QA-145 ITEM 2: deferred half of the camera offset (see the block
# above _process). Runs at end of frame, after
# player_visuals._update_visuals has assigned camera.offset
# (shake-or-zero): adds exactly the wanted offset on top, so shake
# survives and the offset is exact.
func _apply_mmc_camera_offset() -> void:
	var frame: int = Engine.get_process_frames()
	if frame == _mmc_applied_frame:
		return # already applied this frame (double queue)
	_mmc_applied_frame = frame
	var lp = _get_local_player()
	if lp == null or lp._camera == null or not is_instance_valid(lp._camera):
		return
	if not lp.alive:
		return
	lp._camera.offset += _mmc_view_want


# ---------------------------------------------------------------------------
# Phase 4 — kill feed, countdown, hitmarkers, spectator, end stats.
# ---------------------------------------------------------------------------


# =====================================================================
# v3.2 QA-047 — replication simulation (--repl-sim-test).
# One process plays BOTH roles: this instance is the server, a second
# Game instance (the shadow) is the client. The server's spawn/list
# payloads are delivered to the shadow by hand, simulating the wire.
# Steps: (0) server spawns host + client; (1) shadow starts at the
# v3.1 symptom state (0 players, "Connecting..."); (2) the first
# spawn is "lost", the client retries, the server re-sends, the
# shadow heals via the player list; (3) double delivery stays
# idempotent; (4) disconnect despawns on the client. Verdict + quit.
# Steps 8-11 (v3.4 QA-053): the RPC snapshot channel replaces the
# synchronizer — no MultiplayerSynchronizer on any copy, snapshots
# hand-delivered to the receiver's receive_move_snapshot (the same
# hand-delivery the spawn RPCs get), streamed at a steady +5 px/frame
# so smoothness can be asserted too (small forward steps, no
# snap-back). Steps 12-13 (v3.4 QA-055): the same rifle bullet fired
# on both instances must track the same path frame by frame.
# The sim can only hand-deliver payloads (no live ENet) — see the
# note in step 10 for the one-process limit (pid-1 is "local" on both
# instances) and its workaround.
# =====================================================================


# --- FX (impact / explosion) ---


# --- Headless smoke test: drives the REAL joystick API with simulated
# touches (fake touch indices 950/951), so the test exercises the same
# press/drag/release path a phone uses. Verifies movement, facing,
# animation, stick-up jump/jetpack, aim and shooting follow the sticks.


# --- Joystick acceptance tests (--joystick-test) ---
# Drives the REAL touch handlers with simulated touches (fake indices
# 900 = move, 901 = aim) and checks every acceptance criterion from the
# left-joystick spec plus the v2.2 fire-button fix (QA-016). Each step:
# setup runs once, then after `wait` seconds the check runs and the
# result is printed as "JOYTEST <name>: PASS/FAIL — <detail>".
# Run: xvfb-run -a godot --path . --auto-host --joystick-test


# --- Joystick-test helpers: simulated touches through the real handlers ---


# v3.2: the FIRE button is gone — "fire" means deflecting the AIM
# stick (fake touch index 902). If the aim stick is already held by
# _jt_press_aim (901), pressing "fire" is a no-op (it already fires);
# otherwise the 902 press owns the aim stick until released.
var _jt_fire_owns_aim: bool = false


# QA-140 (v3.15): thin wrappers for the GameFx module — these are
# called from outside game.gd (bullet.gd, grenade.gd, pickup.gd,
# player_movement.gd, arena_builder.gd), so they stay on the game node.
func spawn_impact_fx(pos: Vector2, small: bool = false) -> void:
	game_fx.spawn_impact_fx(pos, small)


func spawn_pickup_fx(pos: Vector2) -> void:
	game_fx.spawn_pickup_fx(pos)


func spawn_dust_fx(pos: Vector2) -> void:
	game_fx.spawn_dust_fx(pos)


func request_explosion(pos: Vector2, radius: float, damage: int, from_id: int, weapon_id: int = -1) -> void:
	game_fx.request_explosion(pos, radius, damage, from_id, weapon_id)


# QA-140 (v3.15): thin wrappers for the GameMatch module. The @rpc
# ones stay on the game node (RefCounted modules cannot carry @rpc);
# _check_match_end / _end_match / _player_name are called from
# skyfall/ctf.gd, bullet.gd and the test modules.
@rpc("any_peer", "call_local")
func sync_countdown(n: int) -> void:
	game_match.sync_countdown(n)


@rpc("any_peer", "call_local")
func sync_time_left(t: float) -> void:
	game_match.sync_time_left(t)


func _check_match_end() -> void:
	game_match._check_match_end()


@rpc("any_peer", "call_local")
func reset_round_remote_all() -> void:
	game_match.reset_round_remote_all()


func _end_match(winner: String, reason: String) -> void:
	game_match._end_match(winner, reason)


@rpc("any_peer", "call_local")
func show_end_screen(winner: String, reason: String, rows: Array) -> void:
	game_match.show_end_screen(winner, reason, rows)


func _player_name(peer_id: int) -> String:
	return game_match._player_name(peer_id)


# QA-140 (v3.15): thin wrappers for the GameFeed module. announce_kill
# is @rpc (stays on the game node); try_credit_kill is called from
# bullet.gd and the tests; _add_kill_feed_entry from smoke_test;
# _stop_spectating from features_test.
func try_credit_kill(killer_id: int, victim_id: int, weapon_id: int) -> bool:
	return game_feed.try_credit_kill(killer_id, victim_id, weapon_id)


@rpc("any_peer", "call_local")
func announce_kill(killer_id: int, victim_id: int, weapon_id: int) -> void:
	game_feed.announce_kill(killer_id, victim_id, weapon_id)


func _add_kill_feed_entry(killer_id: int, victim_id: int, weapon_id: int) -> void:
	game_feed._add_kill_feed_entry(killer_id, victim_id, weapon_id)


func _stop_spectating() -> void:
	game_feed._stop_spectating()


# QA-140 (v3.15): thin wrappers for the GameHud module. _get_local_player
# is called from player.gd and skyfall_powerups.gd; _update_hud /
# toggle_net_stats / _update_net_stats are called from replsim_test
# (incl. on the shadow Game instance); _update_scoreboard_rows from
# features_test.
func _get_local_player():
	return game_hud._get_local_player()


func _update_hud(delta: float) -> void:
	game_hud._update_hud(delta)


func _update_scoreboard_rows(list: VBoxContainer) -> void:
	game_hud._update_scoreboard_rows(list)


func toggle_net_stats() -> void:
	game_hud.toggle_net_stats()


func _update_net_stats(delta: float) -> void:
	game_hud._update_net_stats(delta)


# QA-140 (v3.15): thin wrappers for the GameTouch module. ping_remote
# is @rpc (stays on the game node); the button handlers are connected
# from hud_builder.gd / hud_screens.gd and called from fire_test;
# has_aim_fire_edge / consume_aim_fire_edge / touch_recently_used /
# is_hud_control_pos are called from player_movement.gd /
# player_weapons.gd.
func _on_reload_pressed() -> void:
	game_touch._on_reload_pressed()


func _on_score_pressed() -> void:
	game_touch._on_score_pressed()


func _on_grenade_pressed() -> void:
	game_touch._on_grenade_pressed()


func _on_switch_pressed() -> void:
	game_touch._on_switch_pressed()


func _on_ping_pressed() -> void:
	game_touch._on_ping_pressed()


@rpc("any_peer", "call_local")
func ping_remote(pos: Vector2, team: int, pname: String) -> void:
	game_touch.ping_remote(pos, team, pname)


func is_hud_control_pos(viewport_pos: Vector2) -> bool:
	return game_touch.is_hud_control_pos(viewport_pos)


func touch_recently_used() -> bool:
	return game_touch.touch_recently_used()


func has_aim_fire_edge() -> bool:
	return game_touch.has_aim_fire_edge()


func consume_aim_fire_edge() -> void:
	game_touch.consume_aim_fire_edge()


func _toggle_pause() -> void:
	game_touch._toggle_pause()


# QA-140 (v3.15): more GameTouch wrappers. _update_touch_state is
# called from smoke_test / joystick_test / fire_test; the three button
# updaters are called from game_hud._update_hud.
func _update_touch_state() -> void:
	game_touch._update_touch_state()


func _update_reload_button(lp) -> void:
	game_touch._update_reload_button(lp)


func _update_ping_button(lp) -> void:
	game_touch._update_ping_button(lp)


func _update_grenade_button(lp) -> void:
	game_touch._update_grenade_button(lp)


# QA-140 (v3.15): GameTouch wrappers for the touch sim — smoke_test
# and joystick_test drive the real touch handlers directly.
# QA-141: the engine calls _unhandled_input on the game NODE, not
# on the RefCounted GameTouch module — the QA-140 split moved the
# handler into game_touch.gd but left no delegate here, so real
# touch input through the viewport pipeline (GUI first, then
# _unhandled_input) was dead: no phone finger could reach a stick.
# The direct-call path (g._on_touch_press, used by most test steps)
# still worked, which is why only the GUI-PRESS-LEFT steps caught
# it. Forward to the module, same as the wrappers above.
func _unhandled_input(event: InputEvent) -> void:
	game_touch._unhandled_input(event)


func _on_touch_press(index: int, pos: Vector2) -> void:
	game_touch._on_touch_press(index, pos)


func _on_touch_drag(index: int, pos: Vector2) -> void:
	game_touch._on_touch_drag(index, pos)


func _on_touch_release(index: int) -> void:
	game_touch._on_touch_release(index)


# QA-141: thin wrappers the QA-140 split missed — _to_canvas_pos /
# _to_viewport_pos are called from scale_test / joystick_test /
# fire_test (touch sim coordinate conversion), and _outline_label
# from game_feed / ctf / skyfall_powerups. They live in
# GameTouch / GameHud; game.gd only forwards, same as the
# wrappers above. (Found because the joystick suite failed on
# "Nonexistent function '_to_viewport_pos'" — a QA-140 regression,
# not a QA-141 change.)
func _to_canvas_pos(viewport_pos: Vector2) -> Vector2:
	return game_touch._to_canvas_pos(viewport_pos)


func _to_viewport_pos(canvas_pos: Vector2) -> Vector2:
	return game_touch._to_viewport_pos(canvas_pos)


func _outline_label(l: Label) -> void:
	game_hud._outline_label(l)


# QA-141: more thin wrappers the QA-140 split missed — found because
# the features / features-skyfall suites failed on "Nonexistent
# function '_do_spawn' / '_stats_header_row' / '_spawn_pickup_at' /
# '_update_pickup_spawn'" (a QA-140 regression, not a QA-141 change).
# _do_spawn lives in GameSpawn; _stats_header_row in GameHud;
# _spawn_pickup_at / _update_pickup_spawn in GamePickups. Callers
# are the test harness (features_test, skyfall tests) and, for
# _update_pickup_spawn, the game loop (game.gd already calls
# game_pickups._update_pickup_spawn directly — the wrapper is for
# the tests that call g._update_pickup_spawn).
func _do_spawn(pid: int, pname: String, color_idx: int, helmet_style: int, team_pref: int = -1) -> void:
	game_spawn._do_spawn(pid, pname, color_idx, helmet_style, team_pref)


func _stats_header_row(extra: String = "") -> HBoxContainer:
	return game_hud._stats_header_row(extra)


func _stats_row(rank: int, name_txt: String, team_txt: String, kills: int, deaths: int, kd: float, acc: int, is_self: bool, color: Color, extra: String = "") -> HBoxContainer:
	# QA-141: same QA-140 miss as _stats_header_row — found by the
	# features / features-skyfall / flow re-runs ("Nonexistent
	# function '_stats_row'"), called from game_match.gd:344 when
	# the end-match panel builds its rows. Lives in GameHud.
	return game_hud._stats_row(rank, name_txt, team_txt, kills, deaths, kd, acc, is_self, color, extra)


func _spawn_pickup_at(spot_idx: int, kind: int) -> void:
	game_pickups._spawn_pickup_at(spot_idx, kind)


func _update_pickup_spawn(delta: float) -> void:
	game_pickups._update_pickup_spawn(delta)


# QA-141: four more found by a systematic sweep (every `g._*(` call
# site checked against game.gd) — same QA-140 miss, all live callers:
# _announce_ready / _player_list_data live in GameSpawn (called from
# tests/replsim_test.gd); _reset_all_touch_state /
# _set_touch_controls_visible live in GameTouch (called from
# gameplay/game_match.gd when a match ends). Added pre-emptively so
# the suite does not surface them one run at a time.
func _announce_ready() -> void:
	game_spawn._announce_ready()


func _player_list_data() -> Array:
	return game_spawn._player_list_data()


func _reset_all_touch_state() -> void:
	game_touch._reset_all_touch_state()


func _set_touch_controls_visible(v: bool) -> void:
	game_touch._set_touch_controls_visible(v)


# QA-140 (v3.15): thin wrappers for the GameSpawn module. The @rpc
# ones stay on the game node; get_valid_spawn_point / is_on_ice /
# get_spawn_point / is_spawn_valid / has_line_of_sight /
# next_damage_event_id are called from player.gd; obtain_bullet /
# return_bullet from bullet.gd; the _on_peer_* handlers are connected
# in _ready.
func obtain_bullet() -> Node:
	return game_spawn.obtain_bullet()


func return_bullet(b: Node) -> void:
	game_spawn.return_bullet(b)


func get_spawn_point(player_index: int) -> Vector2:
	return game_spawn.get_spawn_point(player_index)


func next_damage_event_id() -> int:
	return game_spawn.next_damage_event_id()


func is_spawn_valid(pos: Vector2, exclude_peer: int) -> bool:
	return game_spawn.is_spawn_valid(pos, exclude_peer)


func get_valid_spawn_point(player_index: int, exclude_peer: int, avoid_pos: Vector2 = Vector2.INF) -> Vector2:
	return game_spawn.get_valid_spawn_point(player_index, exclude_peer, avoid_pos)


func is_on_ice(pos: Vector2) -> bool:
	return game_spawn.is_on_ice(pos)


func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	return game_spawn.has_line_of_sight(from, to)


@rpc("any_peer")
func spawn_player_remote(data: Dictionary) -> void:
	game_spawn.spawn_player_remote(data)


@rpc("any_peer")
func despawn_player_remote(pid: int) -> void:
	game_spawn.despawn_player_remote(pid)


@rpc("any_peer")
func request_player_list() -> void:
	game_spawn.request_player_list()


@rpc("any_peer")
func player_list_remote(players: Array) -> void:
	game_spawn.player_list_remote(players)


@rpc("any_peer")
func request_spawn(pid: int, pname: String, color_idx: int, helmet_style: int, version: String = "", team_pref: int = -1) -> void:
	game_spawn.request_spawn(pid, pname, color_idx, helmet_style, version, team_pref)


func _on_peer_connected(id: int) -> void:
	game_spawn._on_peer_connected(id)


func _on_peer_disconnected(id: int) -> void:
	game_spawn._on_peer_disconnected(id)


func _on_server_disconnected() -> void:
	game_spawn._on_server_disconnected()


# QA-140 (v3.15): thin wrappers for the GamePickups module.
# on_pickup_gone is called from pickup.gd; spawn_pickup_remote is @rpc.
func on_pickup_gone(spot_idx: int) -> void:
	game_pickups.on_pickup_gone(spot_idx)


@rpc("any_peer", "call_local")
func spawn_pickup_remote(pos: Vector2, pname: String, kind: int, spot_idx: int = -1) -> void:
	game_pickups.spawn_pickup_remote(pos, pname, kind, spot_idx)


# QA-140 (v3.15): thin wrappers for the SkyfallHelpers module.
# skyfall_route_of / _sf_level_of are called from the skyfall modules
# and game_touch; _sf_validate_powerup_target from player.gd;
# show_thunder_strike_fx is @rpc.
func skyfall_route_of(x: float) -> int:
	return skyfall_helpers.skyfall_route_of(x)


func _sf_level_of(y: float) -> int:
	return skyfall_helpers._sf_level_of(y)


func _sf_validate_powerup_target(activator: Node2D, target: Node2D, kind: int = 0) -> bool:
	return skyfall_helpers._sf_validate_powerup_target(activator, target, kind)


@rpc("any_peer", "call_local")
func show_thunder_strike_fx(pos: Vector2) -> void:
	skyfall_helpers.show_thunder_strike_fx(pos)


@rpc("any_peer", "call_local")
func show_thunder_trap_telegraph(pos: Vector2) -> void:
	# QA-143 ITEM 11: the L5 trap's 0.6 s warning, drawn on every
	# peer (the host RPCs it when the trap arms).
	skyfall_dynamics.show_thunder_trap_telegraph(pos)

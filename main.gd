extends Control

# Main menu + customization + settings + LAN lobby.
# LAN / local Wi-Fi only. No online multiplayer, no accounts, no bots.

const GAME_SCENE := "res://game.tscn"
const PORT := 7777
const JOIN_TIMEOUT := 8.0
const AUDIO_SCRIPT: Script = preload("res://audio.gd")

# QA-095 (v3.7): 5 maps only — 0 Ironfall (new), 1 Jungle Ruins,
# 2 Neon City (new thumb, drawn for v3.7), 3 Volcanic Cavern,
# 4 Pirate Island. The 8 deleted maps' thumbs are gone.
const MAP_THUMBS := {
	0: preload("res://assets/thumbs/thumb_ironfall.png"),
	1: preload("res://assets/thumbs/thumb_jungle.png"),
	2: preload("res://assets/thumbs/thumb_neon.png"),
	3: preload("res://assets/thumbs/thumb_volcanic.png"),
	4: preload("res://assets/thumbs/thumb_pirate.png"),
}
# QA-095 (v3.7): the lobby map cards show the map's REAL art —
# the in-game far-parallax background for the 3 maps that have
# one (Ironfall, Neon City, Volcanic Cavern — same files game.gd
# uses as the far parallax layer), the existing thumb for the 2
# maps that keep the procedural gradient (Jungle Ruins, Pirate
# Island). The 960×540 backgrounds are cropped to the card
# thumbnail (COVERED), never stretched.
const MAP_CARD_ART := {
	0: preload("res://assets/skybrawl/maps/bg_ironfall.png"),
	1: preload("res://assets/thumbs/thumb_jungle.png"),
	2: preload("res://assets/skybrawl/maps/bg_neon.png"),
	3: preload("res://assets/skybrawl/maps/bg_volcanic.png"),
	4: preload("res://assets/thumbs/thumb_pirate.png"),
}
# v3.5 QA-059: the menu background is arena_clean.png — a plain
# starry navy sky with mountain silhouettes and NO panel shapes.
# The old arena_blue.png (Sky Brawl arena_map_02) had a rounded-rect
# sign top-left and floating platform pills baked in; those showed
# through the semi-transparent panels on every page as empty
# "ghost boxes" (the v3.4 lobby's floating outlines). The old file
# stays in the repo unused; nothing references it any more.
# QA-089 (v3.7): richer military-arena-at-dusk menu background
# (was the plain starry sky arena_clean.png). Dark and uncluttered
# behind the menu UI — the detail lives at the edges and horizon.
const MENU_BG: Texture2D = preload("res://assets/backgrounds/menu_arena_dusk.png")
const FRAG_LOGO: Texture2D = preload("res://assets/logo/frag_arena_logo.png") # v3.5: Frag Arena logo (crosshair + Orbitron wordmark, drawn in code/PIL)
# v3.2 NEON ARENA fonts (SIL OFL 1.1 — see THEME_SPEC.md §1b).
const FONT_TITLE: Font = preload("res://assets/fonts/orbitron/Orbitron-Variable.ttf")
const FONT_BODY: Font = preload("res://assets/fonts/rajdhani/Rajdhani-Regular.ttf")
const FONT_BODY_MEDIUM: Font = preload("res://assets/fonts/rajdhani/Rajdhani-Medium.ttf")
const FONT_BODY_SEMIBOLD: Font = preload("res://assets/fonts/rajdhani/Rajdhani-SemiBold.ttf")
const FONT_BODY_BOLD: Font = preload("res://assets/fonts/rajdhani/Rajdhani-Bold.ttf")
const HELMET_ICONS := {
	1: preload("res://assets/headgear/helmet_green.png"),
	2: preload("res://assets/headgear/cap_tan.png"),
	3: preload("res://assets/headgear/helmet_black.png"),
	# QA-090 (v3.7): 4 red bandana, 5 night-vision goggles, 6 camo
	# helmet. Indices 1-3 unchanged, so saved choices do not shift.
	4: preload("res://assets/headgear/bandana_red.png"),
	5: preload("res://assets/headgear/nvg.png"),
	6: preload("res://assets/headgear/helmet_camo.png"),
}
const HELMET_NAMES := ["No helmet", "Helmet", "Cap", "Black helmet", "Bandana", "Night vision", "Camo helmet"]

var _audio
var _peer: ENetMultiplayerPeer
# v2.4: LAN discovery is one LanDiscovery node (discovery.gd) instead of
# two raw PacketPeerUDPs. It broadcasts to every subnet broadcast
# address (192.168.x.255 etc.), not just 255.255.255.255, and carries
# the full room card (name, host, players/max, map, mode, status).
var _discovery: LanDiscovery
var _broadcast_timer: float = 0.0
var _room_sig_cache: String = ""
var _is_host: bool = false
var _starting_match: bool = false
var _match_started: bool = false # QA-060: start_match RPC idempotency guard (see start_match)
var _joining: bool = false
var _join_ip: String = ""
var _join_password: String = ""
var _join_timer: float = 0.0
var _join_rejected: bool = false
var _lobby_players: Dictionary = {}
var _room_status: String = "lobby" # "lobby" while waiting, "playing" in a match

var _menu_panel: PanelContainer
var _custom_panel: PanelContainer
var _settings_panel: PanelContainer
var _mp_panel: PanelContainer
var _lobby_panel: PanelContainer
var _host_buttons: VBoxContainer
var _status: Label
var _my_ip_label: Label
var _ip_input: LineEdit
var _join_password_input: LineEdit
var _room_name_input: LineEdit
var _room_password_input: LineEdit
var _private_check: CheckButton
var _lobby_status: Label
var _host_ip_label: Label
var _host_ip_chip: PanelContainer # v3.5 QA-059: the IP sits in a cyan-bordered chip, not a bare text line
var _room_info_label: Label # kept for compatibility; v3.5 uses _room_info_values (labelled fields) instead
var _room_info_values: Dictionary = {} # v3.5 QA-059: field name -> value Label in the room info panel
var _lobby_list: VBoxContainer
var _lobby_left_scroll: ScrollContainer # v3.5 QA-059: left column (room + players + setup) scrolls on its own
var _map_cards: Array = [] # v3.5 QA-059: map card panels (visuals), parallel to _map_buttons (input)
var _map_card_badges: Array = [] # v3.5 QA-059: "✓ SELECTED" badge per card, parallel to _map_buttons
var _lobby_start_btn: Button
var _lobby_players_badge: GoBadge # v3.6 QA-069: header players pill ("1/4 PLAYERS"), updated in _refresh_lobby_buttons
var _profile_portrait: TextureRect # QA-078: main-menu profile card
var _profile_name_lbl: Label
var _profile_level_lbl: Label
var _profile_stats_lbl: Label
var _team_buttons: Array = [] # QA-078: RED / BLUE / AUTO team pick (team modes only)
var _team_section_label: Label # QA-078: hidden with the team row in FFA modes
var _lobby_color_buttons: Array = [] # QA-078: in-lobby appearance
var _lobby_helmet_buttons: Array = []
var _limit_label: Label # "Kill limit:" label in the lobby room strip
var _strip_limit_cap: Label # QA-080: stat-strip caption, same switch
var _room_code_input: LineEdit # QA-078: join by room code
var _my_team: int = -1 # QA-078: my team pick in this room (-1 auto)
var _ready_btn: Button
var _ff_check: CheckButton
var _map_buttons: Array = []
var _mode_buttons: Array = []
var _limit_buttons: Array = []
var _time_buttons: Array = []
var _max_buttons: Array = []
var _create_mode_buttons: Array = [] # QA-098: mode pick on the create page
var _color_buttons: Array = []
var _helmet_buttons: Array = []
var _portrait_tex: TextureRect
var _name_input: LineEdit
# Phase 4 — settings screen controls.
var _music_check: CheckButton
var _fps_check: CheckButton
var _invert_check: CheckButton
# Phase 4 — map vote (lobby): candidates on the ballot + vote counts.
var _vote_candidates: Array = []
var _vote_buttons: Array = []
var _vote_box: VBoxContainer
var _my_vote: int = -1 # my voted map id (-1 = no vote yet)

# v2.4 menu net test (--menu-net-test): headless pass/fail harness.
var _menu_net_test: bool = false
var _menu_net_done: bool = false
var _menu_net_steps: Array = []
var _menu_net_step: int = 0
var _menu_net_in_step: bool = false
var _menu_net_timer: float = 0.0
var _menu_net_passed: int = 0
var _menu_net_failed: int = 0
# v2.4 full-flow check (--flow-test): menu side. Verifies menu ->
# create room -> lobby (host IP shown) -> start match, then hands
# over to the game scene via GameData.flow_phase. When the game side
# returns to the menu (phase 2), _ready prints the final result.
var _flow_test: bool = false
var _flow_done: bool = false
var _flow_steps: Array = []
var _flow_step: int = 0
var _flow_in_step: bool = false
var _flow_timer: float = 0.0
var _flow_passed: int = 0
var _flow_failed: int = 0
# v3.5 restart check (--restart-test, QA-060): start a match, leave
# it, start a SECOND match from the menu, end it, rematch. The game
# side runs the play checks; this side only drives the two starts.
var _restart_test: bool = false
# v3.2 scroll test (--scroll-test) + screenshot mode (--shot-all).
var _scroll_test: bool = false
var _scroll_done: bool = false
var _scroll_steps: Array = []
var _scroll_step: int = 0
var _scroll_in_step: bool = false
var _scroll_timer: float = 0.0
var _scroll_passed: int = 0
var _scroll_failed: int = 0
var _lobby_scroll: ScrollContainer
var _mp_scroll: ScrollContainer
var _settings_scroll: ScrollContainer
var _controls_hint_label: Label
var _map_section_label: Label
var _players_section_label: Label # v3.6 QA-078: "Players in the room:" header inside the left scroll (the scroll test drags on it)
var _scroll_hint_label: Label
var _shot_all: bool = false
var _shot_idx: int = 0
# v3.2 join regression test (--join-test-host): auto-create a room
# and auto-start the match, so a second process can join for real.
var _join_test_host: bool = false
var _join_test_client_quick: bool = false
var _rejoin_test_host: bool = false # v3.5 QA-060: --rejoin-test-host (stays in lobby, quits after 30 s)
var _rejoin_test_client: bool = false # v3.5 QA-060: --rejoin-test-client (join → leave → re-join)


func _ready() -> void:
	# v3.2 NEON ARENA: gohud scifi_dark drives every screen (see
	# THEME_SPEC.md). Set once, early, before any panel is built;
	# the root theme is inherited by all children.
	GoUi.config = preload("res://ui/gohud_config.tres")
	GoUi.use_preset(GoThemePresets.SCIFI_DARK)
	theme = GoUi.theme()
	GameData.load_settings()
	# Test-only mode override (--mode=N, QA-080 screenshots): must
	# run before the lobby is built so the mode buttons style the
	# right selection. Parsed here, not in _handle_cli_args, because
	# the lobby is built earlier in _ready.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			GameData.game_mode = clampi(int(a.trim_prefix("--mode=")), 0, GameData.MODE_NAMES.size() - 1)
	_audio = AUDIO_SCRIPT.new()
	add_child(_audio)
	_audio.set_volumes(GameData.sfx_volume, GameData.music_volume)
	_audio.set_music_enabled(GameData.music_enabled)
	# Phase 6: the menu plays the calm track. The game scene stops
	# it when a match starts (battle track) and restarts it on return.
	_audio.play_menu_music()
	_build_background()
	_build_menu()
	_build_customize()
	_build_settings()
	_build_multiplayer()
	_build_lobby()
	_show_only(_menu_panel)
	# v2.4 full-flow check: the game side finished and returned to
	# the menu — print the final result and stop (do NOT restart the
	# menu-side harness, or it would loop forever).
	if GameData.flow_test and GameData.flow_phase == 2:
		print("FLOWTEST BACK-AT-MENU: PASS — main menu visible again after leaving the match")
		print("FLOWTEST DONE: menu → create room → lobby → start match → play → pause → scoreboard → end screen → back")
		GameData.flow_test = false
		GameData.flow_phase = 0
		get_tree().quit()
		return
	# v2.4: one discovery node for the whole menu. It listens for room
	# announcements and (when hosting) broadcasts ours every second.
	_discovery = LanDiscovery.new()
	add_child(_discovery)
	_discovery.start_listening()
	_discovery.room_found.connect(_on_room_found)
	_discovery.room_expired.connect(_on_room_expired)
	# Reconnect hint: after a host disconnect, the game scene saved
	# the host IP — prefill it so the player can rejoin in one tap.
	if GameData.last_host_ip != "":
		_ip_input.text = GameData.last_host_ip
		_set_status("Last host was " + GameData.last_host_ip + " — tap JOIN to reconnect, or pick a room below.")
	_update_my_ip_label()
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_handle_cli_args()
	if _restart_test and GameData.restart_phase == 0:
		call_deferred("_restarttest_begin")
	elif GameData.restart_phase == 2:
		# Second leg of --restart-test: back at the menu after
		# leaving match 1 — create a fresh room and start match 2.
		# (Phase 0 above is the first leg; phase 2 must NOT run the
		# first leg again or the run would loop forever.)
		call_deferred("_restarttest_second_start")
	if _join_test_host:
		call_deferred("_jointest_host_begin")
	if _join_test_client_quick:
		call_deferred("_jointest_client_quick_begin")
	if _rejoin_test_host:
		call_deferred("_rejointest_host_begin")
	if _rejoin_test_client:
		call_deferred("_rejointest_client_begin")
	if _scroll_test:
		call_deferred("_scrolltest_begin")
	if _shot_all:
		call_deferred("_shotall_begin")
	if "--menu-shot" in OS.get_cmdline_user_args():
		get_tree().create_timer(3.0).timeout.connect(_capture_menu_shot)


func _capture_menu_shot() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("user://menu_shot.png")
	print("MENU SHOT: user://menu_shot.png err=", err, " size=", img.get_size())
	get_tree().quit()


# LOOP 5: synchronous capture — the async _capture_flow_shot dies
# when the scene changes on the next frame (the lobby/end checks are
# immediately followed by a scene change), so the lobby and end
# screenshots must be taken in the same frame as the check.
func _capture_flow_shot_now(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("FLOW SHOT NOW: ", path, " err=", err, " size=", img.get_size())


func _handle_cli_args() -> void:
	var args := OS.get_cmdline_user_args()
	if "--join-test-host" in args:
		_join_test_host = true
		return
	if "--join-test-client-quick" in args:
		_join_test_client_quick = true
		return
	if "--rejoin-test-host" in args:
		_rejoin_test_host = true
		return
	if "--rejoin-test-client" in args:
		_rejoin_test_client = true
		return
	if "--scroll-test" in args:
		_scroll_test = true
		return
	if "--shot-all" in args:
		_shot_all = true
		return
	if "--menu-net-test" in args:
		_menu_net_test = true
		return
	if "--flow-test" in args and GameData.flow_phase == 0:
		_flow_test = true
		return
	if "--restart-test" in args:
		_restart_test = true
		return
	if "--auto-host" in args:
		call_deferred("_cli_auto_host")
		return
	for a in args:
		if a.begins_with("--auto-join="):
			var ip := a.trim_prefix("--auto-join=")
			call_deferred("join_game", ip)
			return


func _cli_auto_host() -> void:
	# Smoke-test path: host and go straight into the game scene.
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(_server_port(), 7)
	if err != OK:
		return
	multiplayer.multiplayer_peer = peer
	get_tree().change_scene_to_file(GAME_SCENE)


func _build_background() -> void:
	# v3.2 NEON ARENA (THEME_SPEC.md §6): ONE imported image — the
	# clean starry sky (arena_clean.png) — stretched full-rect,
	# with a 0.55-alpha dark scrim over it so text stays readable.
	# v3.5 QA-059: the old arena_blue.png is gone — its baked-in
	# rounded-rect sign and platform pills showed through every
	# semi-transparent panel as empty ghost boxes. This image has
	# no rectangles, pills or outlines at all, so nothing can show
	# through any more. The old procedural gradient sky + sun +
	# ground band is gone too.
	var bg := TextureRect.new()
	bg.texture = MENU_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(bg)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.035, 0.078, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)


# ---------------------------------------------------------------------------
# Modern UI system (v2.3).
# v2.2 BUG (host lobby blank): panels used PRESET_CENTER plus manual offset
# centring (_center_panel). Hidden panels had size.x == 44 (stylebox margins
# only) when _center_all_panels ran, so offset_left was -22 instead of
# -size/2; worse, the lobby's minimum height transiently computed to ~2877 px
# (the autowrap hint label at width 0 wraps to ~85 one-char lines) and the
# panel was sized to that and NEVER shrank back. Result: the lobby spanned
# y -1078..1798, every button sat above the screen, and the user saw an
# empty dark band with the menu world behind it ("blank, no options").
# The new system removes manual centring entirely: every screen is a
# full-rect PanelContainer (size set by anchors, never by content minimum
# size), tall content lives in a ScrollContainer, and buttons have a
# 56 px minimum touch target. This makes the bug structurally impossible.
# ---------------------------------------------------------------------------
# v3.2 NEON ARENA palette (THEME_SPEC.md §2 — measured from the
# live scifi_dark theme tokens). No green accent anywhere; green
# appears only as the semantic success token, sparingly.
const UI_ACCENT := Color(0.0, 0.898, 1.0) # cyan #00E5FF — THE accent
const UI_ACCENT_DARK := Color(0.012, 0.071, 0.102) # on-accent #03121A
const UI_SUCCESS := Color(0.231, 1.0, 0.647) # mint #3BFFA5
const UI_DANGER := Color(1.0, 0.302, 0.427) # coral #FF4D6D
const UI_WARNING := Color(1.0, 0.773, 0.239) # amber #FFC53D
const UI_FONT := Color(0.847, 0.957, 1.0) # ice #D8F4FF
const UI_FONT_MUTED := Color(0.522, 0.655, 0.741) # muted #85A7BD
const UI_FONT_DISABLED := Color(0.522, 0.655, 0.741)
const UI_FONT_SECONDARY := Color(0.498, 0.706, 0.8) # secondary #7FB4CC


# v3.2 NEON ARENA styling (THEME_SPEC.md §4–§5).
# The gohud scifi_dark theme drives the look: cut-corner navy
# buttons with a steel-blue border, ice text. The old manual
# StyleBoxFlat overrides (green, rounded) are deleted — a bare
# use_preset() call alone changed almost nothing while every button
# carried explicit overrides. _style_button now only clears stale
# overrides, sets the Rajdhani font + size + touch target, and — for
# primary/selected buttons — applies the theme's own GoStyleBoxCut
# shape filled with the theme accent (cyan fill + dark text + "✓").

func _cut_accent_stylebox() -> GoStyleBoxCut:
	var sb := GoStyleBoxCut.new()
	sb.bg_color = UI_ACCENT
	sb.border_color = UI_ACCENT
	sb.border_width = 1.0
	sb.cut = 10.2
	sb.cut_corners = GoStyleBoxCut.ALL
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _style_button(b: Button, font_size: int = 22, min_h: int = 56, accent: bool = false) -> void:
	# Clear any manual stylebox overrides so the gohud theme shows.
	for kind in ["normal", "hover", "pressed", "disabled"]:
		b.remove_theme_stylebox_override(kind)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_override("font", FONT_BODY_SEMIBOLD)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", UI_FONT)
	b.add_theme_color_override("font_hover_color", UI_FONT)
	b.add_theme_color_override("font_pressed_color", Color(0.0, 0.898, 1.0))
	b.add_theme_color_override("font_disabled_color", UI_FONT_DISABLED)
	if accent:
		# Primary / selected: cyan fill + dark text (theme accent,
		# theme cut-corner shape). Hover keeps the same fill.
		var sb := _cut_accent_stylebox()
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_color_override("font_color", UI_ACCENT_DARK)
		b.add_theme_color_override("font_hover_color", UI_ACCENT_DARK)
		b.add_theme_color_override("font_pressed_color", UI_ACCENT_DARK)
	b.custom_minimum_size = Vector2(b.custom_minimum_size.x, min_h)


# Selected toggle state (map / mode / limit / time / colour / helmet).
func _style_selected(b: Button, selected: bool, font_size: int = 22) -> void:
	_style_button(b, font_size, int(b.custom_minimum_size.y), selected)


# Danger action (Leave / disconnect): danger-red fill via the same
# cut-corner shape, white text.
func _style_danger_button(b: Button, font_size: int = 22, min_h: int = 56) -> void:
	_style_button(b, font_size, min_h, false)
	var sb := GoStyleBoxCut.new()
	sb.bg_color = Color(1.0, 0.302, 0.427, 0.92)
	sb.border_color = UI_DANGER
	sb.border_width = 1.0
	sb.cut = 10.2
	sb.cut_corners = GoStyleBoxCut.ALL
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))


func _panel(style_bg: Color = Color(0.07, 0.11, 0.18, 0.96), transparent: bool = false) -> PanelContainer:
	# Full-rect card: size comes from anchors, never from content minimum
	# size, so a transiently wrong content size can never push it off-screen.
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.offset_left = 16
	p.offset_top = 12
	p.offset_right = -16
	p.offset_bottom = -12
	p.theme = GoUi.theme()
	if transparent:
		# Menu: no panel fill at all — title + buttons float over the
		# arena background + scrim (as in the gohud demo proof shot).
		p.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	else:
		# Theme's own cut-corner panel stylebox, slightly translucent
		# so the arena artwork reads faintly through the edges.
		var s := GoUi.theme().get_stylebox("panel", "PanelContainer")
		if s != null:
			var sb := s.duplicate()
			if sb is GoStyleBoxCut:
				(sb as GoStyleBoxCut).bg_color = Color(style_bg.r, style_bg.g, style_bg.b, 0.92)
				(sb as GoStyleBoxCut).content_margin_left = 24
				(sb as GoStyleBoxCut).content_margin_right = 24
				(sb as GoStyleBoxCut).content_margin_top = 18
				(sb as GoStyleBoxCut).content_margin_bottom = 18
			p.add_theme_stylebox_override("panel", sb)
	p.visible = false
	add_child(p)
	return p


# SCROLL_BUG.md §4 — forward drags that start on a button inside a
# ScrollContainer to the container. A Button captures the touch and
# the ScrollContainer never sees the drag otherwise (proven root
# cause). Taps still go through the button's normal pressed path.
func _connect_scroll_button(b: Button, scroll: ScrollContainer) -> void:
	b.gui_input.connect(_on_scrolled_button_gui_input.bind(scroll, b))


func _on_scrolled_button_gui_input(event: InputEvent, scroll: ScrollContainer, b: Button) -> void:
	# Touch drags ONLY. The MouseMotion branch is deliberately NOT
	# here: pointing/emulate_touch_from_mouse duplicates every touch
	# drag as mouse motion, so a motion branch would apply the same
	# delta a second time (a 200 px drag scrolled 400 px). Desktop
	# users scroll with the wheel, which the container handles natively.
	if event is InputEventScreenTouch and event.pressed:
		# A new press starts a new gesture: forget any earlier drag.
		b.set_meta("sc_dragged", false)
	if event is InputEventScreenDrag:
		scroll.scroll_vertical -= event.relative.y
		# v3.5 QA-059: a drag is a scroll, not a tap. The 216 px map
		# cards are taller than the frame-lag offset, so the pointer
		# never leaves the card during a scroll-drag and the release
		# would fire pressed (QA-048 regression in the scroll test).
		# The press handler checks this flag and ignores the tap.
		b.set_meta("sc_dragged", true)


# v3.2: gohud icons replace the hand-drawn _make_icon() shapes.
func _gohud_icon(icon_name: String) -> Texture2D:
	if GoUi.icons().has_icon(StringName(icon_name)):
		return GoUi.icons().texture(StringName(icon_name))
	return null


func _vbox(parent: Control, sep: int = 12) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", sep)
	parent.add_child(box)
	return box


func _section_label(text: String) -> Label:
	# QA-058: section headers are cyan, 22 px SemiBold — the same
	# hierarchy on every page (menu, multiplayer, lobby, settings,
	# customize), so a section reads as a section at a glance.
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT_BODY_SEMIBOLD)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", UI_ACCENT)
	return l


func _title_label(text: String, size: int = 30) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", FONT_TITLE)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", UI_FONT)
	return l


# Body / hint / status text (THEME_SPEC.md §3): Rajdhani Regular, NOT
# Orbitron — the variable Orbitron renders too thin and light at
# 16-20 px to read (the menu subtitle showed this in the v3.2 shots).
func _body_label(text: String, size: int = 18) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", FONT_BODY)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", UI_FONT_MUTED)
	return l


func _show_only(panel: PanelContainer) -> void:
	for p in [_menu_panel, _custom_panel, _settings_panel, _mp_panel, _lobby_panel]:
		if p != null:
			p.visible = (p == panel)
	if panel == _menu_panel:
		_refresh_profile_card() # QA-078: stats may have changed after a match



func _click() -> void:
	if _audio != null:
		_audio.play("click")


func _build_menu() -> void:
	# QA-097 (v3.7): home redesign — same controls, more air.
	# The menu was a tight stack (14 px gaps, 64 px buttons);
	# it now breathes at 20 px gaps with 68 px buttons and a
	# roomier profile card, matching the lobby/create spacing.
	_menu_panel = _panel(Color(0.07, 0.11, 0.18, 0.96), true)
	var box := _vbox(_menu_panel, 20)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	# v3.5 Frag Arena: the logo (crosshair emblem + Orbitron
	# wordmark) is the menu heading now — the old "LAN ARENA
	# SHOOTER" text title is gone. 1239x320 art, shown ~460 px
	# wide (same width as the menu buttons), aspect kept.
	var logo := TextureRect.new()
	logo.texture = FRAG_LOGO
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(460, 119)
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(logo)
	var sub := _body_label("2D shooter - local Wi-Fi only, no accounts", 20)
	sub.add_theme_color_override("font_color", UI_FONT_MUTED)
	box.add_child(sub)
	var title_sep := HSeparator.new()
	title_sep.custom_minimum_size = Vector2(420, 0)
	title_sep.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(title_sep)
	# QA-078: profile card — avatar, name, level and lifetime
	# stats, all local (no account, no server). The numbers come
	# from GameData.record_match, called once per finished match.
	var profile_card := PanelContainer.new()
	profile_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pc_sb := StyleBoxFlat.new()
	pc_sb.bg_color = Color(0.10, 0.16, 0.25, 0.95)
	pc_sb.set_corner_radius_all(10)
	pc_sb.border_color = Color(0.25, 0.38, 0.52)
	pc_sb.set_border_width_all(1)
	pc_sb.content_margin_left = 18
	pc_sb.content_margin_right = 18
	pc_sb.content_margin_top = 14
	pc_sb.content_margin_bottom = 14
	profile_card.add_theme_stylebox_override("panel", pc_sb)
	profile_card.custom_minimum_size = Vector2(460, 0)
	profile_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(profile_card)
	var pc_row := HBoxContainer.new()
	pc_row.add_theme_constant_override("separation", 12)
	profile_card.add_child(pc_row)
	_profile_portrait = TextureRect.new()
	_profile_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_profile_portrait.custom_minimum_size = Vector2(56, 72)
	_profile_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_profile_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pc_row.add_child(_profile_portrait)
	var pc_vb := VBoxContainer.new()
	pc_vb.add_theme_constant_override("separation", 2)
	pc_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc_row.add_child(pc_vb)
	_profile_name_lbl = Label.new()
	_profile_name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_profile_name_lbl.add_theme_font_override("font", FONT_BODY_SEMIBOLD)
	_profile_name_lbl.add_theme_font_size_override("font_size", 24)
	_profile_name_lbl.add_theme_color_override("font_color", UI_FONT)
	pc_vb.add_child(_profile_name_lbl)
	_profile_level_lbl = Label.new()
	_profile_level_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_profile_level_lbl.add_theme_font_override("font", FONT_BODY_SEMIBOLD)
	_profile_level_lbl.add_theme_font_size_override("font_size", 20)
	_profile_level_lbl.add_theme_color_override("font_color", UI_ACCENT)
	pc_vb.add_child(_profile_level_lbl)
	_profile_stats_lbl = Label.new()
	_profile_stats_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_profile_stats_lbl.add_theme_font_override("font", FONT_BODY)
	_profile_stats_lbl.add_theme_font_size_override("font_size", 18)
	_profile_stats_lbl.add_theme_color_override("font_color", UI_FONT_MUTED)
	_profile_stats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pc_vb.add_child(_profile_stats_lbl)
	_refresh_profile_card()
	var mp_btn := Button.new()
	mp_btn.text = "LOCAL MULTIPLAYER"
	mp_btn.icon = _gohud_icon("play")
	mp_btn.expand_icon = true
	mp_btn.custom_minimum_size = Vector2(460, 68)
	mp_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_button(mp_btn, 26, 64, true)
	mp_btn.pressed.connect(func() -> void: _click(); _show_only(_mp_panel))
	box.add_child(mp_btn)
	var cust_btn := Button.new()
	cust_btn.text = "CUSTOMIZATION"
	cust_btn.icon = _gohud_icon("user")
	cust_btn.expand_icon = true
	cust_btn.custom_minimum_size = Vector2(460, 68)
	cust_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_button(cust_btn, 26, 64)
	cust_btn.pressed.connect(func() -> void: _click(); _show_only(_custom_panel))
	box.add_child(cust_btn)
	var set_btn := Button.new()
	set_btn.text = "SETTINGS"
	set_btn.icon = _gohud_icon("settings")
	set_btn.expand_icon = true
	set_btn.custom_minimum_size = Vector2(460, 68)
	set_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_button(set_btn, 26, 64)
	set_btn.pressed.connect(func() -> void: _click(); _show_only(_settings_panel))
	box.add_child(set_btn)
	var hint := _body_label("All phones must be on the same Wi-Fi network.", 18)
	hint.add_theme_color_override("font_color", UI_FONT_MUTED)
	box.add_child(hint)
	# Phase 6: short music credit on the menu (full text is in Settings).
	var credit := _body_label(GameData.MUSIC_CREDITS_SHORT, 16)
	credit.add_theme_color_override("font_color", UI_FONT_MUTED)
	box.add_child(credit)


# QA-078: fill the main-menu profile card from the saved lifetime
# stats. Called at build time and every time the menu is shown
# (a match just played may have changed the numbers). Safe to call
# before the card exists (the menu builds it first).
func _refresh_profile_card() -> void:
	if _profile_name_lbl == null:
		return
	_profile_portrait.texture = _portrait_texture(GameData.portrait)
	_profile_name_lbl.text = GameData.player_name
	var lvl := GameData.level_for_kills(GameData.stat_kills)
	var into := GameData.kills_into_level(GameData.stat_kills)
	_profile_level_lbl.text = "Level %d  •  %d/50 kills to level %d" % [lvl, into, lvl + 1]
	var kd := float(GameData.stat_kills) / float(maxi(GameData.stat_deaths, 1))
	# Two lines on purpose: one line wraps with the K/D value alone
	# on the second line at 460 px card width.
	_profile_stats_lbl.text = "Matches %d  •  Wins %d  •  K/D %.2f\nKills %d  •  Deaths %d" % [
		GameData.stat_matches, GameData.stat_wins, kd, GameData.stat_kills, GameData.stat_deaths,
	]


func _build_customize() -> void:
	_custom_panel = _panel()
	var box := _vbox(_custom_panel, 12)
	box.add_child(_title_label("CUSTOMIZATION", 30))
	# Portrait preview + name.
	var preview_row := HBoxContainer.new()
	preview_row.add_theme_constant_override("separation", 14)
	box.add_child(preview_row)
	_portrait_tex = TextureRect.new()
	_portrait_tex.custom_minimum_size = Vector2(96, 128)
	_portrait_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_row.add_child(_portrait_tex)
	var prev_btn := Button.new()
	prev_btn.text = "<"
	prev_btn.custom_minimum_size = Vector2(56, 56)
	_style_button(prev_btn, 24, 56)
	prev_btn.pressed.connect(_on_portrait_prev)
	preview_row.add_child(prev_btn)
	var next_btn := Button.new()
	next_btn.text = ">"
	next_btn.custom_minimum_size = Vector2(56, 56)
	_style_button(next_btn, 24, 56)
	next_btn.pressed.connect(_on_portrait_next)
	preview_row.add_child(next_btn)
	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Your name"
	_name_input.text = GameData.player_name
	_name_input.max_length = 12
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_input.custom_minimum_size = Vector2(0, 56)
	_name_input.add_theme_font_size_override("font_size", 22)
	_name_input.text_changed.connect(_on_name_changed)
	preview_row.add_child(_name_input)
	_update_portrait()
	# Colour choice.
	box.add_child(_section_label("Colour"))
	var color_row := HBoxContainer.new()
	color_row.add_theme_constant_override("separation", 8)
	box.add_child(color_row)
	for i in GameData.COLOR_NAMES.size():
		var b := Button.new()
		b.text = GameData.COLOR_NAMES[i]
		b.custom_minimum_size = Vector2(0, 56)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(b, 20, 56)
		b.pressed.connect(_on_color_pressed.bind(i))
		color_row.add_child(b)
		_color_buttons.append(b)
	# Helmet choice.
	box.add_child(_section_label("Helmet"))
	var helmet_row := HBoxContainer.new()
	helmet_row.add_theme_constant_override("separation", 8)
	box.add_child(helmet_row)
	for i in HELMET_NAMES.size():
		var b := Button.new()
		b.text = HELMET_NAMES[i]
		if HELMET_ICONS.has(i):
			b.icon = HELMET_ICONS[i]
		b.custom_minimum_size = Vector2(0, 56)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(b, 20, 56)
		b.pressed.connect(_on_helmet_pressed.bind(i))
		helmet_row.add_child(b)
		_helmet_buttons.append(b)
	_refresh_customize_buttons()
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(0, 56)
	_style_button(back_btn, 22, 56)
	back_btn.pressed.connect(func() -> void: _click(); _show_only(_menu_panel))
	box.add_child(back_btn)


func _on_name_changed(text: String) -> void:
	GameData.player_name = text.strip_edges() if text.strip_edges() != "" else "Player"
	GameData.save_settings()


func _on_color_pressed(i: int) -> void:
	_click()
	GameData.color_index = i
	GameData.save_settings()
	_refresh_customize_buttons()


func _on_helmet_pressed(i: int) -> void:
	_click()
	GameData.helmet = i
	GameData.save_settings()
	_refresh_customize_buttons()


func _refresh_customize_buttons() -> void:
	for i in _color_buttons.size():
		var b: Button = _color_buttons[i]
		b.text = ("✓ " if i == GameData.color_index else "") + GameData.COLOR_NAMES[i]
		_style_selected(b, i == GameData.color_index, 20)
	for i in _helmet_buttons.size():
		var b2: Button = _helmet_buttons[i]
		b2.text = ("✓ " if i == GameData.helmet else "") + HELMET_NAMES[i]
		_style_selected(b2, i == GameData.helmet, 20)


func _on_portrait_prev() -> void:
	_click()
	GameData.portrait = (GameData.portrait + 19) % 20
	GameData.save_settings()
	_update_portrait()


func _on_portrait_next() -> void:
	_click()
	GameData.portrait = (GameData.portrait + 1) % 20
	GameData.save_settings()
	_update_portrait()


# Phase 4 — portraits 0-14 are the original soldier variants;
# 15-19 are the Sky Brawl robot colour variants (lobby select only —
# single static frames, never the in-game sprite).
func _portrait_texture(i: int) -> Texture2D:
	var idx := clampi(i, 0, 19)
	if idx < 15:
		return load("res://assets/characters/alt_%02d.png" % idx)
	return load("res://assets/skybrawl/characters/character_%03d.png" % (idx - 14))


func _update_portrait() -> void:
	if _portrait_tex == null:
		return
	_portrait_tex.texture = _portrait_texture(GameData.portrait)


func _build_settings() -> void:
	_settings_panel = _panel()
	var box := _vbox(_settings_panel, 12)
	# Tall content scrolls (same pattern as the lobby).
	var scroll := ScrollContainer.new()
	_settings_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	box = inner
	box.add_child(_title_label("SETTINGS", 30))
	box.add_child(_section_label("Audio"))
	box.add_child(_slider_row("Sound volume", GameData.sfx_volume, _on_sfx_changed))
	box.add_child(_slider_row("Music volume", GameData.music_volume, _on_music_changed))
	# Phase 6: music on/off (separate from volume — off stops the
	# track entirely; on resumes the menu track).
	_music_check = CheckButton.new()
	_music_check.text = "Music on"
	_music_check.add_theme_font_size_override("font_size", 20)
	_music_check.button_pressed = GameData.music_enabled
	_music_check.toggled.connect(_on_music_enabled_toggled)
	box.add_child(_music_check)
	box.add_child(_section_label("Controls"))
	box.add_child(_slider_row("Control sensitivity", GameData.sensitivity, _on_sensitivity_changed, 0.5, 2.0))
	# v3.2: the FIRE button is gone — the right stick aims AND fires
	# (CONTROLS_CHANGE.md). No size/side setting remains.
	var controls_note := Label.new()
	controls_note.text = "Controls: left stick moves, push up to jump / fly, right stick aims and shoots."
	controls_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_note.add_theme_font_override("font", FONT_BODY)
	controls_note.add_theme_font_size_override("font_size", 18)
	controls_note.add_theme_color_override("font_color", UI_FONT_MUTED)
	box.add_child(controls_note)
	_fps_check = CheckButton.new()
	_fps_check.text = "Show FPS counter (in matches)"
	_fps_check.add_theme_font_size_override("font_size", 20)
	_fps_check.button_pressed = GameData.show_fps
	_fps_check.toggled.connect(_on_fps_toggled)
	box.add_child(_fps_check)
	_invert_check = CheckButton.new()
	_invert_check.text = "Invert aim (up = down)"
	_invert_check.add_theme_font_size_override("font_size", 20)
	_invert_check.button_pressed = GameData.invert_aim
	_invert_check.toggled.connect(_on_invert_toggled)
	box.add_child(_invert_check)
	# Phase 6: music attribution (CC BY 4.0 — must appear in-game).
	box.add_child(_section_label("Music credits"))
	var credits := Label.new()
	credits.text = GameData.MUSIC_CREDITS
	credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credits.add_theme_font_size_override("font_size", 18)
	credits.add_theme_color_override("font_color", UI_FONT_MUTED)
	box.add_child(credits)
	var font_credit := Label.new()
	font_credit.text = "Orbitron © 2018 The Orbitron Project Authors, Rajdhani © 2014 Indian Type Foundry — SIL Open Font License 1.1"
	font_credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	font_credit.add_theme_font_override("font", FONT_BODY)
	font_credit.add_theme_font_size_override("font_size", 16)
	font_credit.add_theme_color_override("font_color", UI_FONT_MUTED)
	box.add_child(font_credit)
	# v3.2 QA-047: privacy policy in-app (Play compliance). The full
	# policy is also in PRIVACY_POLICY.md in the project.
	box.add_child(_section_label("Privacy"))
	var privacy_lbl := Label.new()
	privacy_lbl.text = "Frag Arena collects no personal data. No accounts, no sign-in, no ads, no analytics, no tracking. Phones talk directly to each other over your Wi-Fi (LAN) only — nothing is sent to the internet or any server. Settings (name, controls, volume) stay on your phone."
	privacy_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	privacy_lbl.add_theme_font_override("font", FONT_BODY)
	privacy_lbl.add_theme_font_size_override("font_size", 18)
	privacy_lbl.add_theme_color_override("font_color", UI_FONT_MUTED)
	box.add_child(privacy_lbl)
	var version_lbl := Label.new()
	version_lbl.text = "Frag Arena v3.6  •  LAN only — no accounts, no servers"
	version_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	version_lbl.add_theme_font_size_override("font_size", 18)
	version_lbl.add_theme_color_override("font_color", UI_FONT_MUTED)
	box.add_child(version_lbl)
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(0, 56)
	_style_button(back_btn, 22, 56)
	back_btn.pressed.connect(func() -> void: _click(); _show_only(_menu_panel))
	box.add_child(back_btn)
	_connect_scroll_button(back_btn, _settings_scroll)


func _slider_row(label_text: String, value: float, on_change: Callable, min_v: float = 0.0, max_v: float = 1.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(190, 0)
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = 0.05
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(on_change)
	row.add_child(slider)
	return row


func _on_sfx_changed(v: float) -> void:
	GameData.sfx_volume = v
	GameData.save_settings()
	if _audio != null:
		_audio.set_volumes(GameData.sfx_volume, GameData.music_volume)


func _on_music_changed(v: float) -> void:
	GameData.music_volume = v
	GameData.save_settings()
	if _audio != null:
		_audio.set_volumes(GameData.sfx_volume, GameData.music_volume)


func _on_sensitivity_changed(v: float) -> void:
	GameData.sensitivity = v
	GameData.save_settings()


func _on_music_enabled_toggled(on: bool) -> void:
	GameData.music_enabled = on
	GameData.save_settings()
	if _audio != null:
		_audio.set_music_enabled(on)


func _on_fps_toggled(on: bool) -> void:
	GameData.show_fps = on
	GameData.save_settings()


func _on_invert_toggled(on: bool) -> void:
	GameData.invert_aim = on
	GameData.save_settings()


func _build_multiplayer() -> void:
	_mp_panel = _panel()
	var box := _vbox(_mp_panel, 12)
	box.add_child(_title_label("LOCAL MULTIPLAYER", 36))
	var hint := _body_label("All phones must be on the same Wi-Fi network (or one phone's hotspot).", 18)
	hint.add_theme_color_override("font_color", UI_FONT_MUTED)
	box.add_child(hint)
	# v2.4: show our own LAN IP up front, so the host can read it out
	# and a joiner can type it even if discovery fails.
	_my_ip_label = Label.new()
	_my_ip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_my_ip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_my_ip_label.add_theme_font_size_override("font_size", 20)
	box.add_child(_my_ip_label)
	# v3.2 QA-047: in-app permission explanation (Android / Play).
	# LAN play uses plain Wi-Fi sockets only — no accounts, no
	# internet, no location. The app needs only Internet + network
	# state, both granted at install with no pop-up.
	var perm_note := Label.new()
	perm_note.text = "Permissions: Internet + network state only, so phones on this Wi-Fi can find each other. No location, no accounts, no data leaves your phones."
	perm_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	perm_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	perm_note.add_theme_font_override("font", FONT_BODY)
	perm_note.add_theme_font_size_override("font_size", 16)
	perm_note.add_theme_color_override("font_color", UI_FONT_MUTED)
	box.add_child(perm_note)
	# v3.2: the whole panel scrolls (see note below at the room list).
	var scroll := ScrollContainer.new()
	_mp_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	box = inner

	# --- Create a room ---
	# v3.6 QA-068 — FULL REDESIGN. v3.5 was a flat stack of bare
	# inputs (placeholder-only room name, a tiny CheckButton for
	# private, the password beside it with no label). Now the
	# whole create form lives on one designed gohud card with
	# real labels above every field (GoField: label + input +
	# hint), a big segmented max-players row, a proper GoSwitch
	# for Private, and a 72 px hero CREATE ROOM button. Every
	# control keeps its exact v3.5 behaviour (same nodes, same
	# handlers, same create flow); only the presentation
	# changed. The card itself is mouse-transparent (see the
	# v3.5 room-panel note): a drag starting on the card must
	# reach _mp_scroll.
	var create_card := PanelContainer.new()
	create_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var create_sb := GoUi.theme().get_stylebox("panel", "PanelContainer")
	if create_sb != null:
		var create_dup := create_sb.duplicate()
		if create_dup is GoStyleBoxCut:
			(create_dup as GoStyleBoxCut).bg_color = Color(0.09, 0.14, 0.22, 0.96)
			(create_dup as GoStyleBoxCut).content_margin_left = 24
			(create_dup as GoStyleBoxCut).content_margin_right = 24
			(create_dup as GoStyleBoxCut).content_margin_top = 16
			(create_dup as GoStyleBoxCut).content_margin_bottom = 16
		create_card.add_theme_stylebox_override("panel", create_dup)
	box.add_child(create_card)
	var create_box := VBoxContainer.new()
	create_box.add_theme_constant_override("separation", 14)
	create_card.add_child(create_box)
	var create_head := HBoxContainer.new()
	create_head.add_theme_constant_override("separation", 10)
	create_box.add_child(create_head)
	var create_title := Label.new()
	create_title.text = "CREATE A ROOM"
	create_title.add_theme_font_override("font", FONT_TITLE)
	create_title.add_theme_font_size_override("font_size", 26)
	create_title.add_theme_color_override("font_color", UI_FONT)
	create_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_head.add_child(create_title)
	var host_badge := GoBadge.make(0, "YOU HOST", false, UI_ACCENT)
	host_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	create_head.add_child(host_badge)
	var create_sub := Label.new()
	create_sub.text = "Start a room on this Wi-Fi — friends on the same network see it in their room list."
	create_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	create_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	create_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	create_sub.add_theme_font_override("font", FONT_BODY)
	create_sub.add_theme_font_size_override("font_size", 18)
	create_sub.add_theme_color_override("font_color", UI_FONT_MUTED)
	create_box.add_child(create_sub)
	_room_name_input = LineEdit.new()
	_room_name_input.placeholder_text = "Room name, e.g. Tharun's Room"
	_room_name_input.text = GameData.room_name
	_room_name_input.custom_minimum_size = Vector2(0, 56)
	_room_name_input.add_theme_font_size_override("font_size", 22)
	var name_field := GoField.make("Room name", _room_name_input, "Shown to friends on this Wi-Fi")
	name_field.label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_field.hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	create_box.add_child(name_field)
	var max_cap := Label.new()
	max_cap.text = "Max players — how many phones can join"
	max_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	max_cap.add_theme_font_override("font", FONT_BODY_SEMIBOLD)
	max_cap.add_theme_font_size_override("font_size", 20)
	max_cap.add_theme_color_override("font_color", UI_FONT)
	create_box.add_child(max_cap)
	var max_row := HBoxContainer.new()
	max_row.add_theme_constant_override("separation", 8)
	create_box.add_child(max_row)
	for n in [2, 4, 6, 8, 10, 12]:
		var b := Button.new()
		b.text = str(n)
		b.custom_minimum_size = Vector2(64, 56)
		_style_button(b, 22, 56)
		b.pressed.connect(_on_max_pressed.bind(n))
		max_row.add_child(b)
		_max_buttons.append(b)
		_connect_scroll_button(b, _mp_scroll)
	# QA-098 (v3.7): the create form now picks the mode up front
	# (was lobby-only). Same value the lobby uses (GameData.game_mode)
	# — the room card, the lobby display and the match start all read
	# it from there, so nothing else changes. Two rows of mode buttons
	# (3 + 2) like the lobby. The map pick that was added here in
	# v3.7 was removed in v3.8 (QA-102): the host picks the map in
	# the lobby instead.
	var create_mode_cap := Label.new()
	create_mode_cap.text = "Game mode"
	create_mode_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	create_mode_cap.add_theme_font_override("font", FONT_BODY_SEMIBOLD)
	create_mode_cap.add_theme_font_size_override("font_size", 20)
	create_mode_cap.add_theme_color_override("font_color", UI_FONT)
	create_box.add_child(create_mode_cap)
	var create_mode_row := HBoxContainer.new()
	create_mode_row.add_theme_constant_override("separation", 8)
	create_box.add_child(create_mode_row)
	var create_mode_row2 := HBoxContainer.new()
	create_mode_row2.add_theme_constant_override("separation", 8)
	create_box.add_child(create_mode_row2)
	for i in GameData.MODE_NAMES.size():
		var mb := Button.new()
		mb.text = GameData.MODE_NAMES[i]
		mb.custom_minimum_size = Vector2(0, 56)
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(mb, 20, 56)
		mb.pressed.connect(_on_create_mode_pressed.bind(i))
		(create_mode_row if i < 3 else create_mode_row2).add_child(mb)
		_create_mode_buttons.append(mb)
		_connect_scroll_button(mb, _mp_scroll)
	# QA-102 (v3.8): the map pick was REMOVED from the create form
	# (user: "remove map selection while creating room") — the host
	# picks the map in the lobby instead. The mode pick stays here.
	# GameData.map_id keeps its default (0 = Ironfall) until the
	# host changes it on a lobby map card; the room card, lobby
	# display and match start all read it from there.
	_refresh_create_mode_buttons()
	# The password input is created BEFORE the Private switch:
	# flipping the switch calls _on_private_toggled, which greys
	# the password field out when Private is off — and the field
	# must already exist when that runs at build time.
	_room_password_input = LineEdit.new()
	_room_password_input.placeholder_text = "Room password (if private)"
	_room_password_input.text = GameData.room_password
	_room_password_input.secret = true # v3.6: a password field masks what you type (was plain text)
	_room_password_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_password_input.custom_minimum_size = Vector2(0, 56)
	_room_password_input.add_theme_font_size_override("font_size", 20)
	var priv_row := HBoxContainer.new()
	priv_row.add_theme_constant_override("separation", 10)
	create_box.add_child(priv_row)
	var priv_lbl := Label.new()
	priv_lbl.text = "Private room"
	priv_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	priv_lbl.add_theme_font_override("font", FONT_BODY_SEMIBOLD)
	priv_lbl.add_theme_font_size_override("font_size", 22)
	priv_lbl.add_theme_color_override("font_color", UI_FONT)
	priv_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	priv_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	priv_row.add_child(priv_lbl)
	_private_check = GoSwitch.new()
	_private_check.custom_minimum_size = Vector2(72, 56)
	_private_check.button_pressed = GameData.room_private
	_private_check.toggled.connect(_on_private_toggled)
	priv_row.add_child(_private_check)
	var pw_field := GoField.make("Room password", _room_password_input, "Only friends with this password can join")
	pw_field.label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pw_field.hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	create_box.add_child(pw_field)
	var create_btn := Button.new()
	create_btn.text = "CREATE ROOM"
	create_btn.custom_minimum_size = Vector2(0, 72)
	_style_button(create_btn, 26, 72, true)
	create_btn.pressed.connect(_on_create_room_pressed)
	create_box.add_child(create_btn)
	_connect_scroll_button(create_btn, _mp_scroll)
	_on_private_toggled(GameData.room_private) # grey the password field out when Private starts off

	# --- Join area: TWO COLUMNS (QA-103, v3.8) ---
	# User: "have the rooms on the right like available room and
	# quick join also on the right like bottom of the right when the
	# rooms available". Left column = join by IP / room code.
	# Right column = available rooms list, with QUICK LAN MATCH at
	# the bottom of the right column, below the rooms. REFRESH moves
	# into the right column header (it refreshes the room list).
	# Both columns share the width 50/50; the whole page still
	# scrolls in _mp_scroll, so nothing is cut off.
	var join_columns := HBoxContainer.new()
	join_columns.add_theme_constant_override("separation", 16)
	join_columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(join_columns)
	var left_col := _vbox(join_columns, 12)
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right_col := _vbox(join_columns, 12)
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# --- Left column: join a room ---
	left_col.add_child(_section_label("Join a room:"))
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 10)
	left_col.add_child(join_row)
	_ip_input = LineEdit.new()
	_ip_input.placeholder_text = "Host IP, e.g. 192.168.1.5"
	_ip_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_input.custom_minimum_size = Vector2(0, 60)
	_ip_input.add_theme_font_size_override("font_size", 22)
	# v3.6 QA-068: the join IP gets a real label too (GoField),
	# like the create form above — same node, same JOIN flow.
	var ip_field := GoField.make("Host IP", _ip_input, "Or tap a room on the right — same Wi-Fi only")
	ip_field.label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ip_field.hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ip_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(ip_field)
	var join_btn := Button.new()
	join_btn.text = "JOIN"
	join_btn.custom_minimum_size = Vector2(120, 60)
	join_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_button(join_btn, 26, 60, true)
	join_btn.pressed.connect(_on_join_pressed)
	join_row.add_child(join_btn)
	_connect_scroll_button(join_btn, _mp_scroll)
	_join_password_input = LineEdit.new()
	_join_password_input.placeholder_text = "Only for private rooms"
	_join_password_input.secret = true # v3.6 QA-068: mask the password (was plain text)
	_join_password_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_password_input.custom_minimum_size = Vector2(0, 56)
	_join_password_input.add_theme_font_size_override("font_size", 20)
	var join_pw_field := GoField.make("Password", _join_password_input, "Only for private rooms")
	join_pw_field.label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	join_pw_field.hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_col.add_child(join_pw_field)
	# QA-078: join by room code — the host reads the code out
	# (it is on the lobby's host-IP chip) and a friend types it
	# here instead of the IP. LAN-local only: the code is looked
	# up in the discovered-room list on this Wi-Fi, no server.
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 10)
	left_col.add_child(code_row)
	_room_code_input = LineEdit.new()
	_room_code_input.placeholder_text = "Room code, e.g. FRAG-1234"
	_room_code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_code_input.custom_minimum_size = Vector2(0, 60)
	_room_code_input.add_theme_font_size_override("font_size", 22)
	var code_field := GoField.make("Room code", _room_code_input, "Ask the host for the code — same Wi-Fi only")
	code_field.label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	code_field.hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	code_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(code_field)
	var code_btn := Button.new()
	code_btn.text = "JOIN CODE"
	code_btn.custom_minimum_size = Vector2(160, 60)
	code_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_button(code_btn, 22, 60, true)
	code_btn.pressed.connect(_on_join_code_pressed)
	code_row.add_child(code_btn)
	_connect_scroll_button(code_btn, _mp_scroll)

	# --- Right column: available rooms + Quick Join at the bottom ---
	var rooms_head := HBoxContainer.new()
	rooms_head.add_theme_constant_override("separation", 10)
	right_col.add_child(rooms_head)
	var rooms_cap := _section_label("Games found on this Wi-Fi:")
	rooms_cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rooms_cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rooms_head.add_child(rooms_cap)
	var refresh_btn := Button.new()
	refresh_btn.text = "REFRESH"
	refresh_btn.custom_minimum_size = Vector2(140, 56)
	refresh_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_button(refresh_btn, 20, 56)
	refresh_btn.pressed.connect(_on_refresh_pressed)
	rooms_head.add_child(refresh_btn)
	_connect_scroll_button(refresh_btn, _mp_scroll)
	var rooms_hint := _body_label("Tap a room to join it. If nothing appears, type the host IP on the left.", 18)
	rooms_hint.add_theme_color_override("font_color", UI_FONT_MUTED)
	right_col.add_child(rooms_hint)
	# Room list: plain VBox inside the outer scroll (the v3.1 inner
	# ScrollContainer got zero height — see the note at the top of
	# this function). Room buttons forward drags to _mp_scroll.
	_host_buttons = VBoxContainer.new()
	_host_buttons.add_theme_constant_override("separation", 8)
	_host_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.add_child(_host_buttons)
	# QUICK LAN MATCH sits at the bottom of the right column,
	# below the rooms list — reachable without scrolling when the
	# list is short, one scroll away when it is long.
	var quick_btn := Button.new()
	quick_btn.text = "QUICK LAN MATCH"
	quick_btn.custom_minimum_size = Vector2(0, 60)
	quick_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(quick_btn, 22, 60, true)
	quick_btn.pressed.connect(_on_quick_match_pressed)
	right_col.add_child(quick_btn)
	_connect_scroll_button(quick_btn, _mp_scroll)
	_status = Label.new()
	_status.text = ""
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 20)
	box.add_child(_status)
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(0, 56)
	_style_button(back_btn, 22, 56)
	back_btn.pressed.connect(func() -> void: _click(); _show_only(_menu_panel))
	box.add_child(back_btn)
	_connect_scroll_button(back_btn, _mp_scroll)
	_refresh_max_buttons()
	_refresh_create_mode_buttons()


func _refresh_create_mode_buttons() -> void:
	for i in _create_mode_buttons.size():
		var b: Button = _create_mode_buttons[i]
		b.text = ("✓ " if i == GameData.game_mode else "") + GameData.MODE_NAMES[i]
		_style_selected(b, i == GameData.game_mode, 20)


func _on_create_mode_pressed(i: int) -> void:
	_click()
	GameData.game_mode = i
	_refresh_create_mode_buttons()


func _build_lobby() -> void:
	# v3.6 QA-069 — REDESIGNED AGAIN. The user said the v3.5
	# two-column lobby is still not good, and he is right about
	# what the screenshot shows: the left column opens with a
	# big half-empty room-info grid, the host IP chip and two
	# hint lines push the players and the match setup below the
	# fold ("Match setup:" is clipped at the bottom edge), and
	# the whole page is flat navy-on-navy with one hierarchy.
	# The new layout keeps two columns for the scrollable
	# content, but the room is no longer a column — it is a
	# header + stat strip across the top:
	#   HEADER: "GAME LOBBY" left, live players pill right
	#       (gohud GoBadge, "1/4 PLAYERS"), status line under.
	#   STAT STRIP: 7 tiles (Room / Players / Map / Mode /
	#       Kill limit / Time / Friendly fire) — the same
	#       labelled fields as v3.5, now as tiles with a caption
	#       above each value, so the room reads at a glance.
	#   HOST IP chip: full-width, under the strip (unchanged).
	#   LEFT column (~45%): PLAYERS first (cards with bigger
	#       portraits + gohud GoBadge HOST / YOU / READY chips),
	#       then MATCH SETUP (mode / friendly fire / kill
	#       limit / time), then the map vote — all reachable
	#       without scrolling past room info first.
	#   RIGHT column (~55%): the map cards, bigger art.
	#   BOTTOM bar (fixed): I'M READY / START MATCH / Leave.
	# Every control keeps its exact v3.5 behaviour (same
	# pressed handlers, same refresh paths, same scroll
	# containers and drag-forwarding); only the arrangement
	# and the presentation changed.
	# QA-097 (v3.7): lobby redesign — the user said the page is
	# CONGESTED. Same controls, same handlers, same scroll
	# containers — only air: 16 px gaps (was 10), 20 px between
	# the columns (was 14), bigger map cards (252 px, 164 px art,
	# was 228/140) now that 5 maps fill the grid instead of 13.
	_lobby_panel = _panel()
	var box := _vbox(_lobby_panel, 12)
	# ---- Header: title left, players pill right ----
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 12)
	box.add_child(head_row)
	var lobby_title := Label.new()
	lobby_title.text = "GAME LOBBY"
	lobby_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lobby_title.add_theme_font_override("font", FONT_TITLE)
	lobby_title.add_theme_font_size_override("font_size", 40)
	lobby_title.add_theme_color_override("font_color", UI_FONT)
	lobby_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(lobby_title)
	_lobby_players_badge = GoBadge.make(0, "1/4 PLAYERS", false, UI_ACCENT)
	_lobby_players_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lobby_players_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head_row.add_child(_lobby_players_badge)
	_lobby_status = Label.new()
	_lobby_status.text = ""
	_lobby_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_lobby_status.add_theme_font_size_override("font_size", 20)
	_lobby_status.add_theme_color_override("font_color", UI_FONT_MUTED)
	box.add_child(_lobby_status)
	# ---- Stat strip: the room as 7 tiles in two rows ----
	# v3.6 fix (same day, after the first screenshot review):
	# the first version used a 4-column GridContainer and the
	# equal tiles were too narrow — "ShotTest • Public" wrapped
	# to 3 lines and "Free-for-All" to 3 lines, inflating the
	# strip so far that the first map row was cut in half. Two
	# HBox rows with stretch ratios give the long values room:
	# Room gets double width, so nothing wraps any more.
	var strip := VBoxContainer.new()
	strip.add_theme_constant_override("separation", 14)
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(strip)
	var strip_row1 := HBoxContainer.new()
	strip_row1.add_theme_constant_override("separation", 14)
	strip.add_child(strip_row1)
	var strip_row2 := HBoxContainer.new()
	strip_row2.add_theme_constant_override("separation", 14)
	strip.add_child(strip_row2)
	var strip_rows := {"Room": strip_row1, "Players": strip_row1, "Map": strip_row1, "Mode": strip_row2, "Kill limit": strip_row2, "Time": strip_row2, "Friendly fire": strip_row2}
	var strip_ratios := {"Room": 2.0, "Players": 1.0, "Map": 1.2, "Mode": 1.2, "Kill limit": 0.8, "Time": 0.8, "Friendly fire": 1.0}
	for field in ["Room", "Players", "Map", "Mode", "Kill limit", "Time", "Friendly fire"]:
		var tile := PanelContainer.new()
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.size_flags_stretch_ratio = float(strip_ratios[field])
		var tile_sb := StyleBoxFlat.new()
		tile_sb.bg_color = Color(0.10, 0.16, 0.25, 0.95)
		tile_sb.set_corner_radius_all(10)
		tile_sb.border_color = Color(0.25, 0.38, 0.52)
		tile_sb.set_border_width_all(1)
		tile_sb.content_margin_left = 16
		tile_sb.content_margin_right = 16
		tile_sb.content_margin_top = 8
		tile_sb.content_margin_bottom = 8
		tile.add_theme_stylebox_override("panel", tile_sb)
		(strip_rows[field] as HBoxContainer).add_child(tile)
		var tile_vb := VBoxContainer.new()
		tile_vb.add_theme_constant_override("separation", 2)
		tile.add_child(tile_vb)
		var cap := Label.new()
		cap.text = field.to_upper()
		if field == "Kill limit":
			_strip_limit_cap = cap
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cap.add_theme_font_override("font", FONT_BODY_SEMIBOLD)
		cap.add_theme_font_size_override("font_size", 15)
		cap.add_theme_color_override("font_color", UI_FONT_MUTED)
		tile_vb.add_child(cap)
		var v := Label.new()
		v.text = "—"
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_font_override("font", FONT_BODY_SEMIBOLD)
		v.add_theme_font_size_override("font_size", 18)
		v.add_theme_color_override("font_color", UI_FONT)
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile_vb.add_child(v)
		_room_info_values[field] = v
	# v2.4: the host's LAN IP, big and clear — this is the number a
	# friend types to join when discovery does not find the room.
	# v3.5: it sits in a prominent cyan-bordered chip, not a bare
	# text line. v3.6: the chip moves up under the stat strip so
	# it is visible without scrolling either column.
	_host_ip_chip = PanelContainer.new()
	_host_ip_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chip_sb := StyleBoxFlat.new()
	chip_sb.bg_color = Color(0.0, 0.25, 0.32, 0.92)
	chip_sb.set_corner_radius_all(10)
	chip_sb.border_color = UI_ACCENT
	chip_sb.set_border_width_all(2)
	chip_sb.content_margin_left = 14
	chip_sb.content_margin_right = 14
	chip_sb.content_margin_top = 8
	chip_sb.content_margin_bottom = 8
	_host_ip_chip.add_theme_stylebox_override("panel", chip_sb)
	box.add_child(_host_ip_chip)
	_host_ip_label = Label.new()
	_host_ip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host_ip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_host_ip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_host_ip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host_ip_label.add_theme_font_override("font", FONT_BODY_BOLD)
	_host_ip_label.add_theme_font_size_override("font_size", 22)
	_host_ip_label.add_theme_color_override("font_color", UI_ACCENT)
	_host_ip_chip.add_child(_host_ip_label)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(cols)
	# ---- LEFT column: players + setup + vote (scrolls) ----
	var left_col := VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.size_flags_stretch_ratio = 0.9
	cols.add_child(left_col)
	var left_scroll := ScrollContainer.new()
	_lobby_left_scroll = left_scroll
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_col.add_child(left_scroll)
	var left_inner := VBoxContainer.new()
	left_inner.add_theme_constant_override("separation", 12)
	left_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(left_inner)
	_players_section_label = _section_label("Players in the room:")
	left_inner.add_child(_players_section_label)
	_lobby_list = VBoxContainer.new()
	_lobby_list.add_theme_constant_override("separation", 10)
	left_inner.add_child(_lobby_list)
	# Match setup sits directly under the players now (it used
	# to sit below the room panel + IP chip + hints, under the
	# fold). The host IP chip already says how friends join,
	# so the old join-hint line is gone.
	left_inner.add_child(_section_label("Match setup:"))
	# QA-080: five modes now — one row of five buttons needs ~740 px
	# of text width, which forces the left column wider than its
	# 0.9 stretch share and squeezes the map cards (a Button's
	# content minimum still applies under custom_minimum_size).
	# Two rows (3 + 2) keep the full mode names and fit the column.
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	left_inner.add_child(mode_row)
	var mode_row2 := HBoxContainer.new()
	mode_row2.add_theme_constant_override("separation", 8)
	left_inner.add_child(mode_row2)
	for i in GameData.MODE_NAMES.size():
		var b := Button.new()
		b.text = GameData.MODE_NAMES[i]
		b.custom_minimum_size = Vector2(0, 56)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(b, 20, 56)
		b.pressed.connect(_on_mode_pressed.bind(i))
		(mode_row if i < 3 else mode_row2).add_child(b)
		_mode_buttons.append(b)
		_connect_scroll_button(b, _lobby_left_scroll)
	# v3.6 QA-069: friendly fire is a Label + GoSwitch (pill),
	# like the Private switch on the create page — the old
	# CheckButton's tiny box read as a checkbox, not a setting.
	var ff_row := HBoxContainer.new()
	ff_row.add_theme_constant_override("separation", 10)
	left_inner.add_child(ff_row)
	var ff_lbl := Label.new()
	ff_lbl.text = "Friendly fire (Team Deathmatch only)"
	ff_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ff_lbl.add_theme_font_override("font", FONT_BODY_SEMIBOLD)
	ff_lbl.add_theme_font_size_override("font_size", 20)
	ff_lbl.add_theme_color_override("font_color", UI_FONT)
	ff_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ff_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ff_row.add_child(ff_lbl)
	_ff_check = GoSwitch.new()
	_ff_check.custom_minimum_size = Vector2(72, 56)
	_ff_check.button_pressed = GameData.friendly_fire
	_ff_check.toggled.connect(_on_friendly_fire_toggled)
	ff_row.add_child(_ff_check)
	_ff_check.gui_input.connect(_on_scrolled_button_gui_input.bind(_lobby_left_scroll, _ff_check))
	var limit_row := HBoxContainer.new()
	limit_row.add_theme_constant_override("separation", 8)
	left_inner.add_child(limit_row)
	var limit_lbl := Label.new()
	_limit_label = limit_lbl
	limit_lbl.text = "Kill limit:"
	limit_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	limit_lbl.add_theme_font_size_override("font_size", 20)
	limit_row.add_child(limit_lbl)
	for kl in [5, 10, 15]:
		var b := Button.new()
		b.text = str(kl)
		b.custom_minimum_size = Vector2(64, 56)
		_style_button(b, 20, 56)
		b.pressed.connect(_on_limit_pressed.bind(kl))
		limit_row.add_child(b)
		_limit_buttons.append(b)
		_connect_scroll_button(b, _lobby_left_scroll)
	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 8)
	left_inner.add_child(time_row)
	var time_lbl := Label.new()
	time_lbl.text = "Match time:"
	time_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_lbl.add_theme_font_size_override("font_size", 20)
	time_row.add_child(time_lbl)
	for mins in [3, 5, 10]:
		var b := Button.new()
		b.text = "%d min" % mins
		b.custom_minimum_size = Vector2(90, 56)
		_style_button(b, 20, 56)
		b.pressed.connect(_on_time_pressed.bind(mins))
		time_row.add_child(b)
		_time_buttons.append(b)
		_connect_scroll_button(b, _lobby_left_scroll)
	# QA-078: team pick — only for team modes (TDM, Capture the
	# Flag). RED / BLUE / AUTO; the host honours the pick when the
	# match starts unless that team is already full (6), then it
	# falls back to auto. The row hides for free-for-all modes.
	left_inner.add_child(_section_label("Your team (team modes):"))
	_team_section_label = left_inner.get_child(left_inner.get_child_count() - 1) as Label
	var team_row := HBoxContainer.new()
	team_row.add_theme_constant_override("separation", 8)
	left_inner.add_child(team_row)
	for t in [-1, 0, 1]:
		var tb := Button.new()
		tb.text = "AUTO" if t == -1 else ("RED" if t == 0 else "BLUE")
		tb.custom_minimum_size = Vector2(0, 56)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(tb, 20, 56)
		tb.pressed.connect(_on_team_pressed.bind(t))
		team_row.add_child(tb)
		_team_buttons.append(tb)
		_connect_scroll_button(tb, _lobby_left_scroll)
	# QA-078: change appearance without leaving the room — colour
	# and helmet, same choices as Customization. The change syncs
	# to every phone in the room at once (host broadcast, see
	# update_appearance / _broadcast_lobby).
	left_inner.add_child(_section_label("Appearance in this room:"))
	var lobby_color_row := HBoxContainer.new()
	lobby_color_row.add_theme_constant_override("separation", 8)
	left_inner.add_child(lobby_color_row)
	for i in GameData.COLOR_NAMES.size():
		var cb := Button.new()
		cb.text = GameData.COLOR_NAMES[i]
		cb.custom_minimum_size = Vector2(0, 56)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(cb, 18, 56)
		cb.pressed.connect(_on_lobby_color_pressed.bind(i))
		lobby_color_row.add_child(cb)
		_lobby_color_buttons.append(cb)
		_connect_scroll_button(cb, _lobby_left_scroll)
	var lobby_helmet_row := HBoxContainer.new()
	lobby_helmet_row.add_theme_constant_override("separation", 8)
	left_inner.add_child(lobby_helmet_row)
	for i in HELMET_NAMES.size():
		var hb := Button.new()
		hb.text = HELMET_NAMES[i]
		hb.custom_minimum_size = Vector2(0, 56)
		hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(hb, 18, 56)
		hb.pressed.connect(_on_lobby_helmet_pressed.bind(i))
		lobby_helmet_row.add_child(hb)
		_lobby_helmet_buttons.append(hb)
		_connect_scroll_button(hb, _lobby_left_scroll)
	# Phase 4 — map vote: every player picks one of 3 maps on the
	# ballot (the host's pick + the next two). The host tallies the
	# votes when the match starts; ties and no-votes keep the host's
	# pick. Votes travel in the lobby player dicts (see set_vote).
	left_inner.add_child(_section_label("Map vote — pick the next map:"))
	_vote_box = VBoxContainer.new()
	_vote_box.add_theme_constant_override("separation", 8)
	left_inner.add_child(_vote_box)
	for k in 3:
		var vb := Button.new()
		vb.text = ""
		vb.custom_minimum_size = Vector2(0, 56)
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_style_button(vb, 20, 56)
		vb.pressed.connect(_on_vote_pressed.bind(k))
		_vote_box.add_child(vb)
		_vote_buttons.append(vb)
		_connect_scroll_button(vb, _lobby_left_scroll)
	var vote_hint := Label.new()
	vote_hint.text = "Most votes wins. If nobody votes, or on a tie, the host's map is played."
	vote_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vote_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vote_hint.add_theme_font_size_override("font_size", 18)
	vote_hint.add_theme_color_override("font_color", UI_FONT_MUTED)
	left_inner.add_child(vote_hint)
	# Controls hint, small and muted, at the bottom of the left
	# column — no panel behind it, nothing that can show
	# through as a ghost box.
	var controls_hint := Label.new()
	controls_hint.text = "Left stick: move • Push up: jump / fly • Right stick: aim and shoot"
	controls_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_hint.custom_minimum_size = Vector2(0, 24)
	controls_hint.add_theme_font_override("font", FONT_BODY)
	controls_hint.add_theme_font_size_override("font_size", 18)
	controls_hint.add_theme_color_override("font_color", UI_FONT)
	_controls_hint_label = controls_hint
	left_inner.add_child(controls_hint)
	# ---- RIGHT column: map cards (scrolls) ----
	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_stretch_ratio = 1.1
	cols.add_child(right_col)
	var scroll := ScrollContainer.new()
	_lobby_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_col.add_child(scroll)
	var map_inner := VBoxContainer.new()
	map_inner.add_theme_constant_override("separation", 16)
	map_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(map_inner)
	_map_section_label = _section_label("Maps — tap a card to select:")
	map_inner.add_child(_map_section_label)
	var map_grid := GridContainer.new()
	map_grid.columns = 2
	map_grid.add_theme_constant_override("h_separation", 16)
	map_grid.add_theme_constant_override("v_separation", 16)
	map_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_inner.add_child(map_grid)
	for i in GameData.MAP_NAMES.size():
		map_grid.add_child(_build_map_card(i))
	# THEME_SPEC.md §8: visible scroll hint under the map grid — it
	# is also a label, so a drag starting on it scrolls (SCROLL_BUG.md).
	var scroll_hint := Label.new()
	scroll_hint.text = "Scroll for more maps ↓"
	scroll_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scroll_hint.add_theme_font_override("font", FONT_BODY)
	scroll_hint.add_theme_font_size_override("font_size", 18)
	scroll_hint.add_theme_color_override("font_color", UI_ACCENT)
	_scroll_hint_label = scroll_hint
	map_inner.add_child(scroll_hint)
	# Fixed action row — always visible, never scrolled away.
	var top_sep := HSeparator.new()
	box.add_child(top_sep)
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 14)
	box.add_child(btn_row)
	_ready_btn = Button.new()
	_ready_btn.text = "I'M READY"
	_ready_btn.custom_minimum_size = Vector2(180, 64)
	_style_button(_ready_btn, 22, 64)
	_ready_btn.pressed.connect(_on_ready_pressed)
	btn_row.add_child(_ready_btn)
	_lobby_start_btn = Button.new()
	_lobby_start_btn.text = "START MATCH"
	_lobby_start_btn.custom_minimum_size = Vector2(0, 64)
	_lobby_start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(_lobby_start_btn, 24, 64, true)
	_lobby_start_btn.pressed.connect(_on_start_pressed)
	btn_row.add_child(_lobby_start_btn)
	var leave_btn := Button.new()
	leave_btn.text = "Leave"
	leave_btn.custom_minimum_size = Vector2(140, 64)
	_style_danger_button(leave_btn, 22, 64)
	leave_btn.pressed.connect(_on_lobby_leave_pressed)
	btn_row.add_child(leave_btn)
	_refresh_lobby_buttons()


# v3.5 QA-059 (v3.6 QA-069): one map card — real map art
# thumbnail + name + size info + a gohud GoBadge ("✓ SELECTED")
# when selected. The visible card is a PanelContainer; a
# transparent full-rect Button on top is the input, so
# _map_buttons stays an Array of Buttons: the QA-048 scroll
# test, taps and drag-forwarding all work exactly as before.
func _map_card_stylebox(selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	if selected:
		sb.bg_color = Color(0.05, 0.35, 0.42, 0.98)
		sb.border_color = UI_ACCENT
		sb.set_border_width_all(3)
	else:
		sb.bg_color = Color(0.10, 0.16, 0.25, 0.92)
		sb.border_color = Color(0.25, 0.38, 0.52)
		sb.set_border_width_all(1)
	return sb


func _build_map_card(i: int) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(0, 252)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", _map_card_stylebox(false))
	root.add_child(panel)
	_map_cards.append(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	panel.add_child(vb)
	var thumb := TextureRect.new()
	thumb.texture = MAP_CARD_ART[i]
	thumb.custom_minimum_size = Vector2(0, 164)
	thumb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	vb.add_child(thumb)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	vb.add_child(name_row)
	# v3.6 QA-069: the selected state is a gohud GoBadge
	# ("✓ SELECTED") instead of the bare ✓ Label; bigger art
	# (148 px thumb, was 132) and name 24 px (was 22).
	var badge := GoBadge.make(0, "✓ SELECTED", false, UI_SUCCESS)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.visible = false
	name_row.add_child(badge)
	_map_card_badges.append(badge)
	var name_lbl := Label.new()
	name_lbl.text = GameData.MAP_NAMES[i]
	name_lbl.add_theme_font_override("font", FONT_BODY_SEMIBOLD)
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.add_theme_color_override("font_color", UI_FONT)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_contents = true
	name_row.add_child(name_lbl)
	var info_lbl := Label.new()
	info_lbl.text = GameData.MAP_CARD_INFO[i]
	info_lbl.add_theme_font_override("font", FONT_BODY)
	info_lbl.add_theme_font_size_override("font_size", 18)
	info_lbl.add_theme_color_override("font_color", UI_FONT_MUTED)
	vb.add_child(info_lbl)
	var hit := Button.new()
	hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit.text = ""
	hit.focus_mode = Control.FOCUS_NONE
	for kind in ["normal", "hover", "pressed", "disabled"]:
		hit.add_theme_stylebox_override(kind, StyleBoxEmpty.new())
	hit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	hit.pressed.connect(_on_map_pressed.bind(i))
	root.add_child(hit)
	_map_buttons.append(hit)
	_connect_scroll_button(hit, _lobby_scroll)
	return root


# v3.6 QA-069: one lobby chip — a gohud GoBadge with words
# (HOST / YOU / READY ✓ / NOT READY). Replaces the hand-rolled
# _badge_chip PanelContainer (v3.5). Display-only: mouse-transparent
# so a drag starting on a chip scrolls the left column.
func _lobby_chip(text: String, ink: Color) -> GoBadge:
	var b := GoBadge.make(0, text, false, ink)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


func _on_map_pressed(i: int) -> void:
	# v3.5 QA-059: a scroll-drag ending on a card must not select
	# it — the drag flag is set by _on_scrolled_button_gui_input
	# (see QA-048). A real tap has no drag, so it still selects.
	if i < _map_buttons.size() and bool((_map_buttons[i] as Button).get_meta("sc_dragged", false)):
		(_map_buttons[i] as Button).set_meta("sc_dragged", false)
		return
	if not _is_host:
		return
	_click()
	GameData.map_id = i
	GameData.save_settings()
	_broadcast_lobby()


# Phase 4 — map vote: the ballot is the host's pick + the next two
# maps. Everyone may vote; the host tallies at match start.
func _vote_candidates_now() -> Array:
	return [GameData.map_id, (GameData.map_id + 1) % GameData.MAP_NAMES.size(), (GameData.map_id + 2) % GameData.MAP_NAMES.size()]


func _on_vote_pressed(slot: int) -> void:
	_click()
	var cands := _vote_candidates_now()
	if slot < 0 or slot >= cands.size():
		return
	var map_choice: int = cands[slot]
	_my_vote = map_choice
	var my_id := multiplayer.get_unique_id()
	if _is_host:
		if _lobby_players.has(my_id):
			_lobby_players[my_id]["vote"] = map_choice
		_broadcast_lobby()
	else:
		rpc_id(1, "set_vote", map_choice)
	_refresh_vote_buttons()


@rpc("any_peer")
func set_vote(map_choice: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if _lobby_players.has(sender):
		_lobby_players[sender]["vote"] = clampi(map_choice, 0, GameData.MAP_NAMES.size() - 1)
		_broadcast_lobby()


func _refresh_vote_buttons() -> void:
	if _vote_buttons.is_empty():
		return
	_vote_candidates = _vote_candidates_now()
	var counts := {}
	for c in _vote_candidates:
		counts[int(c)] = 0
	for id in _lobby_players.keys():
		var v: int = int((_lobby_players[id] as Dictionary).get("vote", -1))
		if counts.has(v):
			counts[v] = int(counts[v]) + 1
	for k in _vote_buttons.size():
		var mid: int = _vote_candidates[k]
		var b: Button = _vote_buttons[k]
		var mine: bool = _my_vote == mid
		var n: int = int(counts[mid])
		b.text = "%s%s  —  %d vote%s" % ["✓ " if mine else "", GameData.MAP_NAMES[mid], n, "" if n == 1 else "s"]
		_style_selected(b, mine, 20)


func _on_mode_pressed(i: int) -> void:
	if not _is_host:
		return
	_click()
	GameData.game_mode = i
	GameData.save_settings()
	_broadcast_lobby()


func _on_limit_pressed(kl: int) -> void:
	if not _is_host:
		return
	_click()
	GameData.kill_limit = kl
	GameData.save_settings()
	_broadcast_lobby()


func _on_time_pressed(mins: int) -> void:
	if not _is_host:
		return
	_click()
	GameData.match_minutes = mins
	GameData.save_settings()
	_broadcast_lobby()


# QA-078: team pick (team modes only). Stored per player in the
# lobby dict, so every phone sees it; the host reads it at spawn
# time (game.gd _do_spawn honours it unless the team is full).
func _on_team_pressed(t: int) -> void:
	_click()
	_my_team = clampi(t, -1, 1)
	GameData.team_pref = _my_team
	var my_id := multiplayer.get_unique_id()
	if _is_host:
		if _lobby_players.has(my_id):
			_lobby_players[my_id]["team"] = _my_team
		_broadcast_lobby()
	else:
		rpc_id(1, "set_team", _my_team)
	_refresh_lobby_buttons()


@rpc("any_peer")
func set_team(t: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if _lobby_players.has(sender):
		_lobby_players[sender]["team"] = clampi(t, -1, 1)
		_broadcast_lobby()


# QA-078: in-lobby appearance change. Updates my saved settings
# AND my lobby entry, then syncs to the whole room at once.
func _on_lobby_color_pressed(i: int) -> void:
	_click()
	GameData.color_index = i
	GameData.save_settings()
	_refresh_customize_buttons()
	_sync_my_appearance()


func _on_lobby_helmet_pressed(i: int) -> void:
	_click()
	GameData.helmet = i
	GameData.save_settings()
	_refresh_customize_buttons()
	_sync_my_appearance()


func _sync_my_appearance() -> void:
	var my_id := multiplayer.get_unique_id()
	if _is_host:
		if _lobby_players.has(my_id):
			_lobby_players[my_id]["color"] = GameData.color_index
			_lobby_players[my_id]["helmet"] = GameData.helmet
		_broadcast_lobby()
	else:
		rpc_id(1, "update_appearance", GameData.color_index, GameData.helmet)
	_refresh_lobby_buttons()
	_refresh_lobby_list()


@rpc("any_peer")
func update_appearance(color_idx: int, helmet_style: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if _lobby_players.has(sender):
		_lobby_players[sender]["color"] = clampi(color_idx, 0, GameData.COLOR_NAMES.size() - 1)
		_lobby_players[sender]["helmet"] = clampi(helmet_style, 0, HELMET_NAMES.size() - 1)
		_broadcast_lobby()


func _refresh_lobby_buttons() -> void:
	# v3.5 QA-059: map buttons are invisible hit areas over the map
	# cards — no text or button style on them. The selected state
	# lives on the CARD: cyan border + teal fill + ✓ badge.
	for i in _map_buttons.size():
		var mb: Button = _map_buttons[i]
		var selected: bool = i == GameData.map_id
		mb.disabled = not _is_host
		if i < _map_cards.size():
			(_map_cards[i] as PanelContainer).add_theme_stylebox_override("panel", _map_card_stylebox(selected))
			(_map_cards[i] as Control).modulate = Color(1, 1, 1, 1) if _is_host else Color(1, 1, 1, 0.6)
		if i < _map_card_badges.size():
			(_map_card_badges[i] as Control).visible = selected # v3.6 QA-069: GoBadge now, was a Label
	for i in _mode_buttons.size():
		var ob: Button = _mode_buttons[i]
		ob.text = ("✓ " if i == GameData.game_mode else "") + GameData.MODE_NAMES[i]
		ob.disabled = not _is_host
		_style_selected(ob, i == GameData.game_mode, 20)
	for i in _limit_buttons.size():
		var kl: int = [5, 10, 15][i]
		var lb: Button = _limit_buttons[i]
		lb.text = ("✓ " if kl == GameData.kill_limit else "") + str(kl)
		lb.disabled = not _is_host
		_style_selected(lb, kl == GameData.kill_limit, 20)
	for i in _time_buttons.size():
		var mins: int = [3, 5, 10][i]
		var tb: Button = _time_buttons[i]
		tb.text = ("✓ " if mins == GameData.match_minutes else "") + "%d min" % mins
		tb.disabled = not _is_host
		_style_selected(tb, mins == GameData.match_minutes, 20)
	if _lobby_start_btn != null:
		_lobby_start_btn.visible = _is_host
		# Force-start is explicit: the host may start with players not
		# ready, but the button says so.
		var ready_count := 0
		for id in _lobby_players.keys():
			if bool(_lobby_players[id].get("ready", false)):
				ready_count += 1
		if ready_count < _lobby_players.size():
			_lobby_start_btn.text = "START ANYWAY (%d/%d ready)" % [ready_count, _lobby_players.size()]
		else:
			_lobby_start_btn.text = "START MATCH"
	if _ready_btn != null:
		var my_id := multiplayer.get_unique_id()
		var me_ready: bool = bool(_lobby_players.get(my_id, {}).get("ready", false))
		_ready_btn.text = "READY ✓" if me_ready else "I'M READY"
		_style_selected(_ready_btn, me_ready, 22)
	if _ff_check != null:
		_ff_check.button_pressed = GameData.friendly_fire
		_ff_check.disabled = not _is_host
	if _lobby_status != null:
		_lobby_status.text = "You are the host - pick a map and mode, then start!" if _is_host else "Waiting for the host to start the match..."
	if _host_ip_label != null:
		# The joiner's lifeline: the host IP is always visible here,
		# in its chip (v3.5 QA-059). Keep the label's own visibility
		# in sync with the chip — the flow test reads the label.
		# QA-078: the LAN-local room code rides on the same chip,
		# so the host can read it out to friends.
		var ip_visible := false
		var code_txt := ""
		if _is_host:
			var ip := LanDiscovery.lan_ip()
			if ip != "":
				code_txt = "  •  Room code: " + GameData.room_code(ip, GameData.room_name)
				_host_ip_label.text = "HOST IP: " + ip + "  —  friends type this IP to join" + code_txt
			else:
				_host_ip_label.text = "No Wi-Fi IP found — connect to Wi-Fi or a hotspot, then re-host"
			ip_visible = true
		elif GameData.host_ip != "":
			code_txt = "  •  Room code: " + GameData.room_code(GameData.host_ip, GameData.room_name)
			_host_ip_label.text = "Connected to host: " + GameData.host_ip + code_txt
			ip_visible = true
		_host_ip_label.visible = ip_visible
		if _host_ip_chip != null:
			_host_ip_chip.visible = ip_visible
	# v3.5 QA-059: room info is labelled fields in the room panel,
	# not one long plain text line. v3.6 QA-069: the fields are
	# tiles in the stat strip now, and the header pill shows the
	# same player count — both updated here, same values.
	if not _room_info_values.is_empty():
		var priv := "Private" if GameData.room_private else "Public"
		_room_info_values["Room"].text = "%s • %s" % [GameData.room_name, priv]
		_room_info_values["Players"].text = "%d/%d" % [_lobby_players.size(), GameData.max_players]
		_room_info_values["Map"].text = GameData.MAP_NAMES[GameData.map_id]
		_room_info_values["Mode"].text = GameData.MODE_NAMES[GameData.game_mode]
		_room_info_values["Kill limit"].text = str(GameData.kill_limit)
		_room_info_values["Time"].text = "%d min" % GameData.match_minutes
		_room_info_values["Friendly fire"].text = "On" if GameData.friendly_fire else "Off"
	if _lobby_players_badge != null:
		_lobby_players_badge.label_text = "%d/%d PLAYERS" % [_lobby_players.size(), GameData.max_players]
	# QA-107 (v3.8): the limit is always kills now — Capture the
	# Flag (whose limit was captures) was removed.
	if _limit_label != null:
		_limit_label.text = "Kill limit:"
	if _strip_limit_cap != null:
		_strip_limit_cap.text = "KILL LIMIT"
	# QA-078: team pick row only exists for team modes; the
	# appearance rows always show the current saved choice.
	var team_mode := GameData.game_mode == 1
	if _team_section_label != null:
		_team_section_label.visible = team_mode
	for i in _team_buttons.size():
		var tb: Button = _team_buttons[i]
		tb.visible = team_mode
		var tv: int = [-1, 0, 1][i]
		tb.text = ("✓ " if tv == _my_team else "") + ("AUTO" if tv == -1 else ("RED" if tv == 0 else "BLUE"))
		_style_selected(tb, tv == _my_team, 20)
	for i in _lobby_color_buttons.size():
		var cb: Button = _lobby_color_buttons[i]
		cb.text = ("✓ " if i == GameData.color_index else "") + GameData.COLOR_NAMES[i]
		_style_selected(cb, i == GameData.color_index, 18)
	for i in _lobby_helmet_buttons.size():
		var hb: Button = _lobby_helmet_buttons[i]
		hb.text = ("✓ " if i == GameData.helmet else "") + HELMET_NAMES[i]
		_style_selected(hb, i == GameData.helmet, 18)
	_refresh_vote_buttons()


func _refresh_lobby_list() -> void:
	for c in _lobby_list.get_children():
		c.queue_free()
	var ids: Array = _lobby_players.keys()
	ids.sort()
	for id in ids:
		var info: Dictionary = _lobby_players[id]
		# v3.5 QA-059: proper player cards — thicker colour bar,
		# bigger portrait, name + HOST / YOU badge chips, and the
		# READY status as a coloured chip (green = ready, grey =
		# not ready) instead of a bare text tag.
		var card := PanelContainer.new()
		# v3.5 QA-059: the card itself is mouse-transparent so a
		# drag on a player card scrolls the left column (same
		# PanelContainer trap as the room panel); the KICK button
		# inside keeps its own input.
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var card_sb := StyleBoxFlat.new()
		card_sb.bg_color = Color(0.10, 0.16, 0.25, 0.92)
		card_sb.set_corner_radius_all(10)
		card_sb.border_color = Color(0.25, 0.38, 0.52)
		card_sb.set_border_width_all(1)
		card_sb.content_margin_left = 10
		card_sb.content_margin_right = 10
		card_sb.content_margin_top = 8
		card_sb.content_margin_bottom = 8
		card.add_theme_stylebox_override("panel", card_sb)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(row)
		var bar := ColorRect.new()
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.color = GameData.PLAYER_COLORS[int(info.get("color", 0)) % GameData.PLAYER_COLORS.size()]
		bar.custom_minimum_size = Vector2(8, 0)
		bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_child(bar)
		# v3.6 QA-069: the HOST / YOU / READY chips are gohud
		# GoBadges now (the hand-rolled _badge_chip is deleted);
		# portrait 60x72 (was 52x64). Badges stay
		# mouse-transparent so drags scroll the left column.
		var portrait := TextureRect.new()
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.texture = _portrait_texture(int(info.get("portrait", 0)))
		portrait.custom_minimum_size = Vector2(60, 72)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(portrait)
		var lbl := Label.new()
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.text = String(info.get("name", "Player"))
		lbl.add_theme_font_override("font", FONT_BODY_SEMIBOLD)
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.add_theme_color_override("font_color", GameData.PLAYER_COLORS[int(info.get("color", 0)) % GameData.PLAYER_COLORS.size()])
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(lbl)
		if int(id) == 1:
			row.add_child(_lobby_chip("HOST", UI_WARNING))
		elif int(id) == multiplayer.get_unique_id():
			row.add_child(_lobby_chip("YOU", UI_ACCENT))
		var is_ready: bool = bool(info.get("ready", false))
		if is_ready:
			row.add_child(_lobby_chip("READY ✓", UI_SUCCESS))
		else:
			row.add_child(_lobby_chip("NOT READY", UI_FONT_MUTED))
		# QA-078: team chip in team modes (RED / BLUE / AUTO).
		if GameData.game_mode == 1:
			var pt: int = int(info.get("team", -1))
			if pt == 0:
				row.add_child(_lobby_chip("RED", UI_DANGER))
			elif pt == 1:
				row.add_child(_lobby_chip("BLUE", Color(0.25, 0.55, 0.95)))
			else:
				row.add_child(_lobby_chip("AUTO", UI_FONT_MUTED))
		# The host can remove a player from the room.
		if _is_host and int(id) != 1 and int(id) != multiplayer.get_unique_id():
			var kick_btn := Button.new()
			kick_btn.text = "KICK"
			kick_btn.custom_minimum_size = Vector2(90, 56)
			_style_button(kick_btn, 20, 56)
			kick_btn.pressed.connect(_on_kick_pressed.bind(int(id)))
			row.add_child(kick_btn)
			_connect_scroll_button(kick_btn, _lobby_left_scroll)
		_lobby_list.add_child(card)


func _on_max_pressed(n: int) -> void:
	_click()
	GameData.max_players = clampi(n, 2, 12)
	_refresh_max_buttons()


func _refresh_max_buttons() -> void:
	for i in _max_buttons.size():
		var n: int = [2, 4, 6, 8, 10, 12][i]
		var b: Button = _max_buttons[i]
		b.text = ("✓ " if n == GameData.max_players else "") + str(n)
		_style_selected(b, n == GameData.max_players, 22) # v3.6 QA-068: 64 px buttons, 22 px font (was 20)


func _on_private_toggled(on: bool) -> void:
	GameData.room_private = on
	# v3.6 QA-068: the password field greys out when Private is
	# off, so it is obvious it does nothing until Private is on.
	# The text is kept, not cleared — flip Private back on and
	# the password is still there.
	if _room_password_input != null:
		_room_password_input.editable = on


func _on_friendly_fire_toggled(on: bool) -> void:
	if not _is_host:
		return
	GameData.friendly_fire = on
	_broadcast_lobby()


func _update_my_ip_label() -> void:
	if _my_ip_label == null:
		return
	var ip := LanDiscovery.lan_ip()
	if ip != "":
		_my_ip_label.text = "Your IP on this Wi-Fi: " + ip + "  —  if you host, friends can type this number to join."
	else:
		_my_ip_label.text = "No Wi-Fi IP found — connect to Wi-Fi or a hotspot first."


func _room_card() -> Dictionary:
	# The announcement other phones see in their room list.
	return {
		"room_name": GameData.room_name,
		"host_name": GameData.player_name,
		"players": _lobby_players.size(),
		"max_players": GameData.max_players,
		"map_id": GameData.map_id,
		"mode": GameData.game_mode,
		"status": _room_status,
		"port": _server_port(),
		"private": GameData.room_private,
	}


func _on_create_room_pressed() -> void:
	_click()
	var room_name := _room_name_input.text.strip_edges()
	if room_name == "":
		room_name = "Room"
	GameData.room_name = LanDiscovery.sanitise(room_name)
	GameData.room_private = _private_check.button_pressed
	GameData.room_password = _room_password_input.text.strip_edges()
	if GameData.room_private and GameData.room_password == "":
		_set_status("A private room needs a password — type one, or turn Private off.")
		return
	_create_room()


func _server_port() -> int:
	# Test-only override (--port=N): lets the restart/join tests run
	# on a different port when another suite is using 7777 on this
	# machine. Production always uses PORT (7777).
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			return clampi(int(a.trim_prefix("--port=")), 1024, 65535)
	return PORT


func _create_room() -> bool:
	if multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer is not OfflineMultiplayerPeer:
		_set_status("You are already in a game — leave it first.")
		return false
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(_server_port(), GameData.max_players - 1)
	if err != OK:
		_set_status("Could not host a game (error " + str(err) + "). Another game may already be hosting on this phone.")
		return false
	multiplayer.multiplayer_peer = peer
	_is_host = true
	_room_status = "lobby"
	_lobby_players.clear()
	_lobby_players[multiplayer.get_unique_id()] = _my_lobby_info()
	# Start announcing the room on every subnet broadcast address.
	_discovery.start_broadcasting()
	_broadcast_timer = 0.0
	_show_only(_lobby_panel)
	_refresh_lobby_buttons()
	_refresh_lobby_list()
	_set_status("")
	return true


func _on_join_pressed() -> void:
	_click()
	var ip := _ip_input.text.strip_edges()
	if ip == "":
		_set_status("Type the host IP first, or tap a game found below.")
		return
	join_game(ip, _join_password_input.text.strip_edges())


func _on_quick_match_pressed() -> void:
	# Join the first open lobby room with space. Private rooms and
	# rooms already playing are skipped.
	_click()
	for room in _discovery.get_rooms():
		if String(room.get("status", "")) != "lobby":
			continue
		if bool(room.get("private", false)):
			continue
		if int(room.get("players", 99)) >= int(room.get("max_players", 0)):
			continue
		join_game(String(room["ip"]))
		return
	_set_status("No open rooms found — tap REFRESH, type the host IP, or host your own room.")


func _on_join_code_pressed() -> void:
	# QA-078: join by room code — look the code up in the rooms
	# discovered on this Wi-Fi and join that room's IP. Private
	# rooms still need their password (the password field above).
	_click()
	var code := _room_code_input.text.strip_edges().to_upper()
	if code == "":
		_set_status("Type the room code first — ask the host for it.")
		return
	if not code.begins_with("FRAG-"):
		code = "FRAG-" + code
	for room in _discovery.get_rooms():
		if GameData.room_code(String(room["ip"]), String(room["room_name"])) == code:
			if String(room.get("status", "")) != "lobby":
				_set_status("That room is already in a match.")
				return
			join_game(String(room["ip"]), _join_password_input.text.strip_edges())
			return
	_set_status("No room with code %s on this Wi-Fi — tap REFRESH and try again." % code)


func _on_refresh_pressed() -> void:
	# Drop the cached list and rebuild it from fresh announcements.
	_click()
	_discovery.forget_all_rooms()
	_room_sig_cache = ""
	_refresh_room_list()
	_set_status("Looking for rooms on this Wi-Fi...")


func join_game(ip: String, password: String = "") -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer is not OfflineMultiplayerPeer:
		return
	GameData.host_ip = ip
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		_set_status("Could not connect to " + ip + " (error " + str(err) + "). Check the IP and Wi-Fi.")
		return
	_peer = peer
	multiplayer.multiplayer_peer = peer
	_joining = true
	_join_ip = ip
	_join_password = password
	_join_timer = 0.0
	_join_rejected = false
	_set_status("Connecting to " + ip + "...")


func _on_connected() -> void:
	_joining = false
	_set_status("Connected, waiting for game...")
	_is_host = false
	_show_only(_lobby_panel)
	_refresh_lobby_buttons()
	_refresh_lobby_list()
	# Tell the host who we are for the lobby list (password included
	# only in this one message; it is never broadcast to other players).
	rpc_id(1, "register_lobby_player", _my_lobby_info())


# QA-060: close the current ENet peer explicitly before dropping
# it. A dropped-but-open peer can keep its UDP socket bound, so the
# next create_server / create_client on the same port fails with
# "Couldn't create an ENet host". Every teardown site uses this.
func _close_peer() -> void:
	var old_peer := multiplayer.multiplayer_peer
	if old_peer is ENetMultiplayerPeer:
		(old_peer as ENetMultiplayerPeer).close()


func _on_connection_failed() -> void:
	_joining = false
	_close_peer()
	_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_set_status("Could not reach that host. Check the IP and Wi-Fi, then tap JOIN to retry.")


func _my_lobby_info() -> Dictionary:
	var my_id := multiplayer.get_unique_id()
	var ready := false
	if _lobby_players.has(my_id):
		ready = bool(_lobby_players[my_id].get("ready", false))
	return {
		"name": GameData.player_name,
		"color": GameData.color_index,
		"helmet": GameData.helmet,
		"portrait": GameData.portrait,
		"ready": ready,
		"vote": _my_vote,
		"team": _my_team, # QA-078: RED 0 / BLUE 1 / AUTO -1 (team modes)
		# Only used by register_lobby_player on the host; stripped
		# before the player list is broadcast to anyone else.
		"password": _join_password,
	}


@rpc("any_peer")
func register_lobby_player(info: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	# Room full?
	if _lobby_players.size() >= GameData.max_players:
		rpc_id(sender, "join_rejected", "Room is full.")
		multiplayer.multiplayer_peer.disconnect_peer(sender)
		return
	# Wrong password for a private room?
	var pw: String = str(info.get("password", ""))
	if GameData.room_private and pw != GameData.room_password:
		rpc_id(sender, "join_rejected", "Wrong room password.")
		multiplayer.multiplayer_peer.disconnect_peer(sender)
		return
	var clean := info.duplicate()
	clean.erase("password")
	_lobby_players[sender] = clean
	_broadcast_lobby()


@rpc("any_peer", "call_local")
func join_rejected(reason: String) -> void:
	# The host turned us away (full room / wrong password). Show the
	# reason and stop — the disconnect that follows must not overwrite
	# this message (see _on_server_disconnected).
	_join_rejected = true
	_joining = false
	# QA-060: close the refused connection now; the server-side
	# disconnect that follows would close it via _leave_lobby, but
	# an explicit close here frees the socket immediately.
	_close_peer()
	_peer = null
	_show_only(_mp_panel)
	_set_status("Could not join: " + reason)


@rpc("any_peer")
func set_ready(ready: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if _lobby_players.has(sender):
		_lobby_players[sender]["ready"] = ready
		_broadcast_lobby()


func _on_ready_pressed() -> void:
	_click()
	var my_id := multiplayer.get_unique_id()
	var cur: bool = bool(_lobby_players.get(my_id, {}).get("ready", false))
	var next: bool = not cur
	if _is_host:
		_lobby_players[my_id]["ready"] = next
		_broadcast_lobby()
	else:
		rpc_id(1, "set_ready", next)


@rpc("any_peer", "call_local")
func kicked_from_lobby(reason: String) -> void:
	# The host removed us. Leave the lobby cleanly and say why.
	_join_rejected = true
	_leave_lobby()
	_show_only(_mp_panel)
	_set_status(reason)


func _on_kick_pressed(id: int) -> void:
	_click()
	if not _is_host:
		return
	rpc_id(id, "kicked_from_lobby", "The host removed you from the room.")
	multiplayer.multiplayer_peer.disconnect_peer(id)
	_lobby_players.erase(id)
	_broadcast_lobby()


func _broadcast_lobby() -> void:
	if not multiplayer.is_server():
		return
	var settings := {
		"map": GameData.map_id, "mode": GameData.game_mode,
		"limit": GameData.kill_limit, "minutes": GameData.match_minutes,
		"max": GameData.max_players, "ff": GameData.friendly_fire,
		"room": GameData.room_name, "private": GameData.room_private,
	}
	# Never broadcast passwords: strip them from every player entry.
	var safe_players := {}
	for id in _lobby_players.keys():
		var clean: Dictionary = (_lobby_players[id] as Dictionary).duplicate()
		clean.erase("password")
		safe_players[id] = clean
	rpc("lobby_update", safe_players, settings)
	_refresh_lobby_buttons()
	_refresh_lobby_list()


@rpc("any_peer", "call_local")
func lobby_update(players: Dictionary, settings: Dictionary) -> void:
	_lobby_players = players
	GameData.map_id = int(settings.get("map", GameData.map_id))
	# QA-107 (v3.8): clamp the mode — a lobby hosted on v3.7 could
	# still send mode 4 (Capture the Flag, removed), and a stale
	# saved value would break MODE_NAMES[4].
	GameData.game_mode = clampi(int(settings.get("mode", GameData.game_mode)), 0, GameData.MODE_NAMES.size() - 1)
	GameData.kill_limit = int(settings.get("limit", GameData.kill_limit))
	GameData.match_minutes = int(settings.get("minutes", GameData.match_minutes))
	GameData.max_players = int(settings.get("max", GameData.max_players))
	GameData.friendly_fire = bool(settings.get("ff", GameData.friendly_fire))
	GameData.room_name = str(settings.get("room", GameData.room_name))
	GameData.room_private = bool(settings.get("private", GameData.room_private))
	_refresh_lobby_buttons()
	_refresh_lobby_list()


func _on_peer_connected(id: int) -> void:
	# The joining client registers itself; nothing to spawn here (no game yet).
	pass


func _on_server_disconnected() -> void:
	# The host left the lobby while we were waiting. If we were
	# rejected/kicked, that message already explains it — keep it.
	if not _is_host:
		_leave_lobby()
		_show_only(_mp_panel)
		if not _join_rejected:
			_set_status("The host left. Pick another game or host your own.")
		_join_rejected = false


func _on_peer_disconnected(id: int) -> void:
	if _is_host and _lobby_players.has(id):
		_lobby_players.erase(id)
		_broadcast_lobby()


func _on_start_pressed() -> void:
	_click()
	if not _is_host or _starting_match:
		return
	# Phase 4: the map vote decides the map (host's pick on ties /
	# no votes, per GameData.tally_map_vote).
	var votes := {}
	for id in _lobby_players.keys():
		votes[id] = int((_lobby_players[id] as Dictionary).get("vote", -1))
	GameData.map_id = GameData.tally_map_vote(votes, _vote_candidates_now(), GameData.map_id)
	_starting_match = true
	rpc("start_match", GameData.map_id, GameData.game_mode, GameData.kill_limit, GameData.match_minutes)


@rpc("any_peer", "call_local")
func start_match(map_id: int, mode: int, kill_limit: int, minutes: int) -> void:
	# QA-060: idempotency guard on the RPC itself — the host button
	# is guarded by _starting_match, but a duplicated or late RPC
	# would call change_scene_to_file again unguarded. The flag is
	# per main-scene instance (a fresh instance is created when the
	# game returns to the menu), and _leave_lobby clears it.
	if _match_started:
		return
	_match_started = true
	GameData.map_id = map_id
	# QA-107 (v3.8): clamp — a v3.7 host could still send mode 4
	# (Capture the Flag, removed); it falls back to FFA (0).
	GameData.game_mode = clampi(mode, 0, GameData.MODE_NAMES.size() - 1)
	GameData.kill_limit = kill_limit
	GameData.match_minutes = minutes
	_room_status = "playing"
	# The game scene runs its own discovery broadcast from here on.
	if _discovery != null:
		_discovery.stop_broadcasting()
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_lobby_leave_pressed() -> void:
	_click()
	_leave_lobby()
	_show_only(_mp_panel)


func _leave_lobby() -> void:
	if _discovery != null:
		_discovery.stop_broadcasting()
	# QA-060: close the old ENet peer explicitly before replacing
	# it — a dropped-but-open peer can keep UDP 7777 bound, so the
	# next host attempt in the same process fails to create a host.
	_close_peer()
	if multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer is not OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_peer = null
	_is_host = false
	_starting_match = false
	_match_started = false
	_joining = false
	_join_rejected = false
	_room_status = "lobby"
	_my_vote = -1
	_my_team = -1 # QA-078: a new room starts on AUTO team
	GameData.team_pref = -1
	_lobby_players.clear()


func _on_room_found(_room: Dictionary) -> void:
	# The room list rebuilds in _process from get_rooms().
	pass


func _on_room_expired(_ip: String) -> void:
	pass


func _room_signature() -> String:
	var parts: Array[String] = []
	var rooms := _discovery.get_rooms()
	rooms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["ip"]) < String(b["ip"]))
	for room in rooms:
		parts.append("%s|%s|%s|%d|%d|%s" % [
			String(room["ip"]), String(room["room_name"]), String(room["host_name"]),
			int(room["players"]), int(room["max_players"]), String(room["status"]),
		])
	return "|".join(parts)


func _refresh_room_list() -> void:
	for c in _host_buttons.get_children():
		c.queue_free()
	var rooms := _discovery.get_rooms()
	rooms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["ip"]) < String(b["ip"]))
	if rooms.is_empty():
		var none := Label.new()
		none.text = "No rooms found yet — make sure both phones are on the same Wi-Fi, or type the host IP above."
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.add_theme_font_size_override("font_size", 18)
		none.add_theme_color_override("font_color", UI_FONT_MUTED)
		_host_buttons.add_child(none)
		return
	for room in rooms:
		var ip := String(room["ip"])
		var map_name := GameData.MAP_NAMES[int(room["map_id"])] if int(room["map_id"]) < GameData.MAP_NAMES.size() else "?"
		var mode_name := GameData.MODE_NAMES[int(room["mode"])] if int(room["mode"]) < GameData.MODE_NAMES.size() else "?"
		var lock := " 🔒" if bool(room["private"]) else ""
		var code := GameData.room_code(ip, String(room["room_name"]))
		var b := Button.new()
		b.text = "%s%s — %s • %d/%d • %s • %s • %s • %s • %s" % [
			String(room["room_name"]), lock, String(room["host_name"]),
			int(room["players"]), int(room["max_players"]),
			map_name, mode_name, String(room["status"]), ip, code,
		]
		b.custom_minimum_size = Vector2(0, 56)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_style_button(b, 20, 56)
		var full: bool = int(room["players"]) >= int(room["max_players"])
		var playing: bool = String(room["status"]) != "lobby"
		b.disabled = full or playing
		if full:
			b.text += " (FULL)"
		elif playing:
			b.text += " (IN GAME)"
		b.pressed.connect(join_game.bind(ip))
		_host_buttons.add_child(b)
		_connect_scroll_button(b, _mp_scroll)


func _process(delta: float) -> void:
	# Keep the discovered-room list fresh (rooms appear, fill up, or
	# expire) without rebuilding the buttons every frame.
	if _discovery != null and _mp_panel != null and _mp_panel.visible:
		var sig := _room_signature()
		if sig != _room_sig_cache:
			_room_sig_cache = sig
			_refresh_room_list()
	# Host: announce the room every second on every subnet broadcast.
	if _is_host and _discovery != null:
		_broadcast_timer += delta
		if _broadcast_timer >= 1.0:
			_broadcast_timer = 0.0
			_discovery.broadcast_room(_room_card())
	if _joining:
		_join_timer += delta
		if _join_timer >= JOIN_TIMEOUT:
			_joining = false
			_close_peer()
			_peer = null
			multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
			_set_status("Could not connect - check the Wi-Fi and IP, then try again. Tap JOIN to retry.")
	if _menu_net_test:
		_update_menu_nettest(delta)
	if _flow_test:
		_update_flowtest(delta)
	if _scroll_test:
		_update_scrolltest(delta)
	if _shot_all:
		_update_shotall(delta)


func _set_status(text: String) -> void:
	_status.text = text


# =====================================================================
# v3.2 SCROLL TEST (--scroll-test) — SCROLL_BUG.md §5
# Drives REAL touch drags through Input.parse_input_event (the real
# viewport GUI path) on the host lobby: drag starting on a map button
# must scroll, taps must still select, a drag-release over another
# button must not select it, and the last map must be reachable.
# Run: xvfb-run -a godot --path . -- --scroll-test
# (add --resolution 2400x1080 for the tall-phone pass)
# =====================================================================

func _scrolltest_begin() -> void:
	GameData.room_name = "ScrollTest"
	GameData.max_players = 4
	GameData.room_private = false
	GameData.room_password = ""
	_room_name_input.text = "ScrollTest"
	_create_room()


func _sc_vp_pos(ctrl: Control, local: Vector2) -> Vector2:
	# Canvas position of the point, then into VIEWPORT pixels — the
	# space touch events live in. get_canvas_transform() does NOT
	# carry the stretch (it is identity here); the real scale is
	# window size / visible-rect size (1.0 at 1280x720, 1.5 at
	# 2400x1080 with stretch expand). The old code fed canvas
	# coordinates as viewport coordinates, so at 2400x1080 every tap
	# landed a third of the screen off and missed its button.
	var canvas_pos: Vector2 = ctrl.get_global_transform_with_canvas() * local
	var s := _sc_vp_scale_vec()
	return Vector2(canvas_pos.x * s.x, canvas_pos.y * s.y)


func _sc_vp_scale_vec() -> Vector2:
	var vis := get_viewport().get_visible_rect().size
	var win := get_window().size
	return Vector2(win.x / vis.x, win.y / vis.y)


func _sc_press(idx: int, vp_pos: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = vp_pos
	e.pressed = true
	Input.parse_input_event(e)


func _sc_release(idx: int, vp_pos: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = vp_pos
	e.pressed = false
	Input.parse_input_event(e)


func _sc_drag(idx: int, vp_pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = vp_pos
	e.relative = rel
	Input.parse_input_event(e)


# Press at vp_pos, drag up by total_px CANVAS px in 50 canvas-px
# steps, release. Positions are viewport px (scaled by the canvas
# transform), so the finger path matches the intended canvas drag
# at every window size.
# _sc_drag_done gates the step check: the drag is async (a frame
# between steps, so the button sees the pointer leave), and at
# 2400x1080 under llvmpipe a frame can take 100+ ms — the 0.6 s
# check wait would otherwise fire with only some steps applied
# (DRAG-ON-BUTTON measured exactly 150 = 3 of 4 steps, the label
# drag 50 = 1 step, settings 0). The check waits for the drag to
# finish (hard-capped at +2 s so a stuck drag cannot hang the suite).
var _sc_drag_done: bool = true


func _sc_drag_up(idx: int, vp_pos: Vector2, total_px: float, vp_scale: float = 1.0) -> void:
	# A frame between press / each drag step / release, like a real
	# finger: without the frames the button never sees the pointer
	# leave its rect while the list scrolls under it, and a
	# drag-release can falsely count as a tap on the original button.
	_sc_drag_done = false
	_sc_press(idx, vp_pos)
	await get_tree().process_frame
	var steps := int(total_px / 50.0)
	var cur := vp_pos
	for i in steps:
		cur += Vector2(0, -50.0 * vp_scale)
		_sc_drag(idx, cur, Vector2(0, -50.0 * vp_scale))
		await get_tree().process_frame
	_sc_release(idx, cur)
	_sc_drag_done = true


func _sc_vp_scale(ctrl: Control) -> float:
	# The stretch scale (viewport px per canvas px): 1.0 at
	# 1280x720, 1.5 at 2400x1080. Neither the control's canvas
	# transform nor get_canvas_transform() carries it (both report
	# 1.0); it is window size / visible-rect size.
	return _sc_vp_scale_vec().y


func _sc_tap(idx: int, vp_pos: Vector2) -> void:
	_sc_press(idx, vp_pos)
	_sc_release(idx, vp_pos)


func _update_scrolltest(delta: float) -> void:
	if _scroll_done:
		return
	if _scroll_steps.is_empty():
		_scrolltest_build_steps()
		_scroll_step = 0
		_scroll_in_step = false
		_scroll_timer = 0.0
	if _scroll_step >= _scroll_steps.size():
		_scroll_done = true
		print("SCROLLTEST DONE: %d/%d passed" % [_scroll_passed, _scroll_passed + _scroll_failed])
		get_tree().quit()
		return
	var step: Dictionary = _scroll_steps[_scroll_step]
	if not _scroll_in_step:
		(step["setup"] as Callable).call()
		_scroll_in_step = true
		_scroll_timer = float(step["wait"])
	_scroll_timer -= delta
	# The check waits for an in-flight async drag to finish (see
	# _sc_drag_up): at slow frame rates the drag steps outlive the
	# step's wait, and checking early measures a partial drag.
	if _scroll_timer <= 0.0 and (_sc_drag_done or _scroll_timer < -2.0):
		var result: Array = (step["check"] as Callable).call()
		var ok: bool = bool(result[0])
		if ok:
			_scroll_passed += 1
		else:
			_scroll_failed += 1
		print("SCROLLTEST %s: %s — %s" % [String(step["name"]), "PASS" if ok else "FAIL", String(result[1])])
		_scroll_step += 1
		_scroll_in_step = false
		_scroll_timer = 0.0


func _scrolltest_build_steps() -> void:
	_scroll_steps = [
		{"name": "DRAG-ON-BUTTON", "wait": 0.6, "setup": _sct_s_drag_button, "check": _sct_c_drag_button},
		{"name": "DRAG-ON-LABEL", "wait": 0.6, "setup": _sct_s_drag_label, "check": _sct_c_drag_label},
		{"name": "TAP-MAP-SELECTS", "wait": 0.6, "setup": _sct_s_tap_map, "check": _sct_c_tap_map},
		{"name": "DRAG-RELEASE-NO-SELECT", "wait": 0.6, "setup": _sct_s_drag_release, "check": _sct_c_drag_release},
		{"name": "SCROLL-MAX-LAST-MAP-VISIBLE", "wait": 0.5, "setup": _sct_s_scroll_max, "check": _sct_c_last_visible},
		{"name": "TAP-LAST-MAP", "wait": 0.6, "setup": _sct_s_tap_last, "check": _sct_c_tap_last},
		{"name": "MP-ROOM-DRAG", "wait": 0.6, "setup": _sct_s_mp_drag, "check": _sct_c_mp_drag},
		{"name": "SETTINGS-DRAG", "wait": 0.6, "setup": _sct_s_settings_drag, "check": _sct_c_settings_drag},
		{"name": "LEFT-COLUMN-DRAG", "wait": 0.6, "setup": _sct_s_left_drag, "check": _sct_c_left_drag},
	]


func _sct_s_drag_button() -> void:
	_lobby_scroll.scroll_vertical = 0
	var b: Button = _map_buttons[0]
	_sc_drag_up(800, _sc_vp_pos(b, b.size * 0.5), 200.0, _sc_vp_scale(b))


func _sct_c_drag_button() -> Array:
	var v := _lobby_scroll.scroll_vertical
	return [v >= 150.0, "scroll_vertical=%d (want >=150 after 200 px drag on map button)" % int(v)]


func _sct_s_drag_label() -> void:
	# Drag on the "Map:" section label INSIDE the scroll area (the
	# lobby controls_hint above the scroll cannot scroll it, and the
	# "Scroll for more maps" hint sits below the fold at scroll 0).
	# The scroll position only applies on the next frame, so wait
	# for layout before measuring the label's position.
	_lobby_scroll.scroll_vertical = 0
	await get_tree().process_frame
	await get_tree().process_frame
	_sc_drag_up(801, _sc_vp_pos(_map_section_label, Vector2(_map_section_label.size.x * 0.5, _map_section_label.size.y * 0.5)), 200.0, _sc_vp_scale(_map_section_label))


func _sct_c_drag_label() -> Array:
	var v := _lobby_scroll.scroll_vertical
	return [v >= 150.0, "scroll_vertical=%d (want >=150 after 200 px drag on label)" % int(v)]


func _sct_s_tap_map() -> void:
	_lobby_scroll.scroll_vertical = 0
	await get_tree().process_frame
	await get_tree().process_frame
	_sc_tap(802, _sc_vp_pos(_map_buttons[1], _map_buttons[1].size * 0.5))


func _sct_c_tap_map() -> Array:
	var ok: bool = GameData.map_id == 1
	return [ok, "map_id=%d (want 1 after tapping map button [1])" % GameData.map_id]


func _sct_s_drag_release() -> void:
	# Drag from button [0] up 200 px; the release lands over a
	# different button — it must NOT select anything.
	_sc_drag_up(803, _sc_vp_pos(_map_buttons[0], _map_buttons[0].size * 0.5), 200.0, _sc_vp_scale(_map_buttons[0]))


func _sct_c_drag_release() -> Array:
	var ok: bool = GameData.map_id == 1
	return [ok, "map_id=%d (want still 1 — drag-release must not select)" % GameData.map_id]


func _sct_s_scroll_max() -> void:
	# Scroll just enough to bring the last map row into view (max
	# scroll shows the mode/limit rows at the bottom — the last map
	# row has scrolled past the top by then).
	var b: Button = _map_buttons[4]
	var btop: float = b.get_global_rect().position.y - _lobby_scroll.get_global_rect().position.y + _lobby_scroll.scroll_vertical
	_lobby_scroll.scroll_vertical = btop - 100.0


func _sct_c_last_visible() -> Array:
	var b: Button = _map_buttons[4]
	var brect := Rect2(_sc_vp_pos(b, Vector2.ZERO), b.size)
	var srect := Rect2(_sc_vp_pos(_lobby_scroll, Vector2.ZERO), _lobby_scroll.size)
	var inter := brect.intersection(srect)
	var ok: bool = inter.size.y > 30.0
	return [ok, "last map button visible height=%d px (want >30) at max scroll" % int(inter.size.y)]


func _sct_s_tap_last() -> void:
	await get_tree().process_frame
	# QA-099 (v3.7): tap the VISIBLE part of the last map card, not
	# its centre — the taller v3.7 cards (252 px) put the centre 8 px
	# below the scroll viewport at this scroll position, so the tap
	# landed outside the scroll container and selected nothing. A
	# real player taps the part they can see; the card is reachable
	# and tappable, the old tap point just wasn't on it any more.
	var b: Button = _map_buttons[4]
	var brect := b.get_global_rect()
	var inter := brect.intersection(_lobby_scroll.get_global_rect())
	var tap_local := inter.get_center() - brect.position
	_sc_tap(804, _sc_vp_pos(b, tap_local))


func _sct_c_tap_last() -> Array:
	var ok: bool = GameData.map_id == 4
	return [ok, "map_id=%d (want 4 — every map reachable and tappable)" % GameData.map_id]


func _sct_s_mp_drag() -> void:
	_show_only(_mp_panel)
	# Fake a long room list (no real rooms on this sandbox Wi-Fi).
	for c in _host_buttons.get_children():
		c.queue_free()
	for i in 12:
		var b := Button.new()
		b.text = "Test Room %d" % i
		b.custom_minimum_size = Vector2(0, 56)
		_style_button(b, 20, 56)
		_host_buttons.add_child(b)
		_connect_scroll_button(b, _mp_scroll)
	await get_tree().process_frame
	await get_tree().process_frame
	_mp_scroll.scroll_vertical = 450
	await get_tree().process_frame
	var first: Button = _host_buttons.get_child(0)
	_sc_drag_up(805, _sc_vp_pos(first, first.size * 0.5), 200.0, _sc_vp_scale(first))


func _sct_c_mp_drag() -> Array:
	var v := _mp_scroll.scroll_vertical
	var mx := _mp_scroll.get_v_scroll_bar().max_value
	var n := _host_buttons.get_child_count()
	for c in _host_buttons.get_children():
		c.queue_free()
	_show_only(_lobby_panel)
	return [v >= 100.0, "mp scroll_vertical=%d max=%d children=%d (want >=100 after 200 px drag on a room button)" % [int(v), int(mx), n]]


func _sct_s_settings_drag() -> void:
	_show_only(_settings_panel)
	_settings_scroll.scroll_vertical = 0
	# The Back button lives inside the settings scroll area.
	var back_btn: Button = null
	for c in _settings_scroll.get_children():
		for sub in (c as VBoxContainer).get_children():
			if sub is Button and (sub as Button).text == "Back":
				back_btn = sub
	if back_btn != null:
		_sc_drag_up(806, _sc_vp_pos(back_btn, back_btn.size * 0.5), 150.0, _sc_vp_scale(back_btn))


func _sct_c_settings_drag() -> Array:
	var v := _settings_scroll.scroll_vertical
	var mx := _settings_scroll.get_v_scroll_bar().max_value
	_show_only(_menu_panel)
	return [v > 0.0, "settings scroll_vertical=%d (max=%d, want >0 after drag on Back button)" % [int(v), int(mx)]]


# v3.5 QA-059: the lobby's LEFT column (players, setup, vote) must
# scroll on its own — at 720p it holds ~1000 px of content in ~460 px.
# Drag on the "Players in the room:" header INSIDE the left scroll
# and check the left scroll moves (the map scroll must NOT move).
# v3.6 QA-078 fix (test only): the old step dragged on the Room info
# value label, but the QA-078 redesign moved the room info out of the
# left column into the top stat strip, which sits outside every
# ScrollContainer — so the drag scrolled nothing (8/9 in the final
# run). The left column itself still scrolls; the step now drags on
# a label that actually lives inside it. No game code changed.
func _sct_s_left_drag() -> void:
	_show_only(_lobby_panel)
	_lobby_left_scroll.scroll_vertical = 0
	_lobby_scroll.scroll_vertical = 0
	await get_tree().process_frame
	await get_tree().process_frame
	var lbl: Label = _players_section_label
	_sc_drag_up(807, _sc_vp_pos(lbl, Vector2(lbl.size.x * 0.5, lbl.size.y * 0.5)), 200.0, _sc_vp_scale(lbl))


func _sct_c_left_drag() -> Array:
	var v := _lobby_left_scroll.scroll_vertical
	var mx := _lobby_left_scroll.get_v_scroll_bar().max_value
	var map_v := _lobby_scroll.scroll_vertical
	return [v >= 150.0 and map_v == 0.0, "left scroll_vertical=%d (max=%d, want >=150) map scroll=%d (want 0)" % [int(v), int(mx), int(map_v)]]


# =====================================================================
# v3.2 SCREENSHOT MODE (--shot-all): captures every menu-side screen
# to user://shot_*.png for the visual review (THEME_SPEC.md §9).
# =====================================================================

var _shot_steps: Array = []
var _shot_step: int = 0
var _shot_in_step: bool = false
var _shot_timer: float = 0.0


func _shotall_begin() -> void:
	_shot_steps = [
		{"name": "menu", "wait": 0.5, "setup": _shot_s_menu, "file": "user://shot_menu.png"},
		{"name": "customize", "wait": 0.5, "setup": _shot_s_customize, "file": "user://shot_customize.png"},
		{"name": "settings", "wait": 0.5, "setup": _shot_s_settings, "file": "user://shot_settings.png"},
		{"name": "multiplayer", "wait": 0.5, "setup": _shot_s_multiplayer, "file": "user://shot_multiplayer.png"},
		{"name": "join", "wait": 0.5, "setup": _shot_s_join, "file": "user://shot_join.png"},
		{"name": "lobby", "wait": 0.5, "setup": _shot_s_lobby, "file": "user://shot_lobby.png"},
	]
	_shot_step = 0
	_shot_in_step = false
	_shot_timer = 0.0


func _update_shotall(delta: float) -> void:
	if _shot_step >= _shot_steps.size():
		print("SHOTALL DONE")
		get_tree().quit()
		return
	var step: Dictionary = _shot_steps[_shot_step]
	if not _shot_in_step:
		(step["setup"] as Callable).call()
		_shot_in_step = true
		_shot_timer = float(step["wait"])
	_shot_timer -= delta
	if _shot_timer <= 0.0:
		_capture_flow_shot_now(String(step["file"]))
		_shot_step += 1
		_shot_in_step = false
		_shot_timer = 0.0


func _shot_s_menu() -> void:
	_show_only(_menu_panel)


func _shot_s_customize() -> void:
	_show_only(_custom_panel)


func _shot_s_settings() -> void:
	_show_only(_settings_panel)


func _shot_s_multiplayer() -> void:
	_show_only(_mp_panel)


# QA-103 (v3.8): the join area is below the Create Room card in the
# same scroll — scroll to the bottom so the two-column join layout
# (rooms list on the right, QUICK LAN MATCH at the bottom of the
# right column) is in frame for the capture.
func _shot_s_join() -> void:
	_show_only(_mp_panel)
	_mp_scroll.scroll_vertical = 100000


func _shot_s_lobby() -> void:
	GameData.room_name = "ShotTest"
	GameData.max_players = 4
	GameData.room_private = false
	GameData.room_password = ""
	_room_name_input.text = "ShotTest"
	_create_room()


# =====================================================================
# v3.2 JOIN TEST — host side (--join-test-host) + Quick Play client
# side (--join-test-client-quick). Two real Godot processes on
# loopback: host creates a room and auto-starts; the client finds the
# room via discovery and joins with QUICK LAN MATCH (the exact path
# the user used), then both sides report in game.gd (JOINTEST).
# =====================================================================

func _jointest_host_begin() -> void:
	GameData.room_name = "JoinTest"
	GameData.max_players = 4
	GameData.room_private = false
	GameData.room_password = ""
	_room_name_input.text = "JoinTest"
	_create_room()
	print("JOINTEST HOST: room created, starting match in 3 s")
	get_tree().create_timer(3.0).timeout.connect(_on_start_pressed)


func _jointest_client_quick_begin() -> void:
	# Wait for discovery to hear the host's broadcast, then press
	# QUICK LAN MATCH exactly as the user did (room list NOT used,
	# no manual IP). If no room is heard in 5 s, fail loudly —
	# discovery itself is then the problem, not the spawn handshake.
	for i in 50:
		await get_tree().create_timer(0.1).timeout
		if not _discovery.get_rooms().is_empty():
			break
	var rooms := _discovery.get_rooms()
	print("JOINTEST CLIENT: rooms heard via discovery: ", rooms)
	if rooms.is_empty():
		print("JOINTEST CLIENT: FAIL — no room discovered in 5 s (broadcast/listen broken)")
		get_tree().quit()
		return
	_on_quick_match_pressed()


# =====================================================================
# v3.5 REJOIN CHECK (--rejoin-test-host / --rejoin-test-client, QA-060)
# Two processes on loopback. The host creates a room and STAYS in the
# lobby (no match start). The client joins, verifies it is in the
# lobby, leaves (the teardown that must close() the ENet peer), waits,
# verifies the peer is offline, then joins AGAIN and verifies it is
# back in the lobby. A leaked socket or a stale peer breaks the second
# join — that is the crash-path regression this test guards.
# SANDBOX LIMIT: this test needs real UDP between the two processes.
# In this sandbox UDP sends fail ("Sending failed" in the client log)
# and the client can never connect — the test reports JOIN-1 FAIL
# there, which is the sandbox, not the game. Run it on two real
# phones (or an unsandboxed runner) for a verdict. The in-process
# proof stands on the restart test (host re-creates its room on the
# same port) plus the shared _leave_lobby teardown it exercises.
# =====================================================================

func _rejointest_host_begin() -> void:
	GameData.room_name = "RejoinTest"
	GameData.max_players = 4
	GameData.room_private = false
	GameData.room_password = ""
	_room_name_input.text = "RejoinTest"
	_create_room()
	print("REJOINTEST HOST: room created, staying in lobby for 30 s")
	get_tree().create_timer(30.0).timeout.connect(func() -> void:
		print("REJOINTEST HOST: done")
		get_tree().quit()
	)


func _rejointest_client_begin() -> void:
	# No discovery wait: two Godot instances on ONE machine cannot
	# both bind the discovery listen port (UDP 7778) — the second
	# bind fails, so the client would never hear the room. That is a
	# single-machine artifact (real phones each have their own 7778);
	# discovery itself is covered by the menu-net test. The client
	# therefore joins the host by loopback IP directly — the ENet
	# join / leave / re-join under test is identical either way.
	join_game("127.0.0.1")
	await get_tree().create_timer(3.0).timeout
	var in_lobby_1: bool = _lobby_panel.visible and not _is_host and _lobby_players.has(multiplayer.get_unique_id())
	print("REJOINTEST JOIN-1: %s — lobby=%s players=%d" % ["PASS" if in_lobby_1 else "FAIL", _lobby_panel.visible, _lobby_players.size()])
	if not in_lobby_1:
		get_tree().quit()
		return
	# Leave: the teardown under test — _leave_lobby must close() the
	# client ENet peer and drop back to an offline peer.
	_leave_lobby()
	_show_only(_mp_panel)
	await get_tree().create_timer(2.0).timeout
	var offline: bool = multiplayer.multiplayer_peer is OfflineMultiplayerPeer
	print("REJOINTEST TEARDOWN: %s — peer offline=%s" % ["PASS" if offline else "FAIL", offline])
	if not offline:
		get_tree().quit()
		return
	join_game("127.0.0.1")
	await get_tree().create_timer(3.0).timeout
	var in_lobby_2: bool = _lobby_panel.visible and not _is_host and _lobby_players.has(multiplayer.get_unique_id())
	print("REJOINTEST JOIN-2: %s — lobby=%s players=%d" % ["PASS" if in_lobby_2 else "FAIL", _lobby_panel.visible, _lobby_players.size()])
	print("REJOINTEST DONE: %s" % ("PASS" if in_lobby_1 and offline and in_lobby_2 else "FAIL"))
	get_tree().quit()


# =====================================================================
# v2.4 MENU NET TEST (--menu-net-test)
# Headless checks for the room/lobby flow. Real two-phone ENet traffic
# cannot run in this sandbox (UDP blocked), so this covers what one
# process can prove: packet build/parse, subnet broadcast addresses,
# the bad-IP error path, room creation (server + lobby + host IP
# shown), and the Ready toggle. Two-device play is covered by the
# README testing guide instead.
# =====================================================================

func _update_menu_nettest(delta: float) -> void:
	if _menu_net_done:
		return
	if _menu_net_steps.is_empty():
		_mnt_build_steps()
		_menu_net_step = 0
		_menu_net_in_step = false
		_menu_net_timer = 0.0
	if _menu_net_step >= _menu_net_steps.size():
		_menu_net_done = true
		print("MENUNET DONE: %d/%d passed" % [_menu_net_passed, _menu_net_passed + _menu_net_failed])
		get_tree().quit()
		return
	var step: Dictionary = _menu_net_steps[_menu_net_step]
	if not _menu_net_in_step:
		(step["setup"] as Callable).call()
		_menu_net_in_step = true
		_menu_net_timer = float(step["wait"])
	_menu_net_timer -= delta
	if _menu_net_timer <= 0.0:
		var result: Array = (step["check"] as Callable).call()
		var ok: bool = bool(result[0])
		if ok:
			_menu_net_passed += 1
		else:
			_menu_net_failed += 1
		print("MENUNET %s: %s — %s" % [String(step["name"]), "PASS" if ok else "FAIL", String(result[1])])
		_menu_net_step += 1
		_menu_net_in_step = false
		_menu_net_timer = 0.0


func _mnt_build_steps() -> void:
	_menu_net_steps = [
		{"name": "PAYLOAD-ROUNDTRIP", "wait": 0.3, "setup": _mnt_s_noop, "check": _mnt_c_payload},
		{"name": "PROFILE-LEVEL", "wait": 0.2, "setup": _mnt_s_noop, "check": _mnt_c_profile},
		{"name": "ROOM-CODE", "wait": 0.2, "setup": _mnt_s_noop, "check": _mnt_c_roomcode},
		{"name": "SUBNET-BROADCAST", "wait": 0.3, "setup": _mnt_s_noop, "check": _mnt_c_subnet},
		{"name": "BAD-IP-ERROR", "wait": 1.0, "setup": _mnt_s_bad_ip, "check": _mnt_c_bad_ip},
		{"name": "CREATE-ROOM", "wait": 0.5, "setup": _mnt_s_create_room, "check": _mnt_c_create_room},
		{"name": "READY-TOGGLE", "wait": 0.3, "setup": _mnt_s_ready, "check": _mnt_c_ready},
		{"name": "LEAVE-CLEANUP", "wait": 0.3, "setup": _mnt_s_leave, "check": _mnt_c_leave},
	]


func _mnt_s_noop() -> void:
	pass


# QA-078: level math — 1 + one level per 50 lifetime kills.
func _mnt_c_profile() -> Array:
	var ok: bool = GameData.level_for_kills(0) == 1 and GameData.level_for_kills(49) == 1 and GameData.level_for_kills(50) == 2 and GameData.level_for_kills(120) == 3 and GameData.kills_into_level(120) == 20
	# The card itself is filled (name + level line + stats line).
	var card_ok: bool = _profile_name_lbl != null and _profile_name_lbl.text == GameData.player_name and _profile_level_lbl.text.begins_with("Level ")
	return [ok and card_ok, "level(0/49/50/120)=%d/%d/%d/%d into=%d card='%s'" % [GameData.level_for_kills(0), GameData.level_for_kills(49), GameData.level_for_kills(50), GameData.level_for_kills(120), GameData.kills_into_level(120), _profile_level_lbl.text]]


# QA-078: room code — deterministic for one room, different for
# different rooms, always FRAG- + 4 digits.
func _mnt_c_roomcode() -> Array:
	var a := GameData.room_code("192.168.1.5", "Tharun's Room")
	var b := GameData.room_code("192.168.1.5", "Tharun's Room")
	var c := GameData.room_code("192.168.1.6", "Tharun's Room")
	var d := GameData.room_code("192.168.1.5", "Other Room")
	var ok: bool = a == b and a != c and a != d and a.begins_with("FRAG-") and a.length() == 9
	return [ok, "code=%s repeat=%s other-ip=%s other-name=%s" % [a, b, c, d]]


func _mnt_c_payload() -> Array:
	var room := {"room_name": "Test Room", "host_name": "Host", "players": 2, "max_players": 8, "map_id": 5, "mode": 1, "status": "lobby", "port": 7777, "private": true}
	var pkt := LanDiscovery.build_room_packet(room)
	var back := LanDiscovery.parse_room_packet(pkt.get_string_from_utf8(), "192.168.1.7")
	var ok: bool = back["room_name"] == "Test Room" and back["host_name"] == "Host" and int(back["players"]) == 2 and int(back["max_players"]) == 8 and int(back["map_id"]) == 5 and int(back["mode"]) == 1 and back["status"] == "lobby" and int(back["port"]) == 7777 and bool(back["private"]) and back["ip"] == "192.168.1.7"
	return [ok, "round-trip fields match: %s" % ok]


func _mnt_c_subnet() -> Array:
	var addrs := LanDiscovery.broadcast_addresses()
	var ok: bool = addrs.has("255.255.255.255")
	var lan := LanDiscovery.lan_ip()
	if lan != "":
		var parts := lan.split(".")
		ok = ok and addrs.has("%s.%s.%s.255" % [parts[0], parts[1], parts[2]])
	return [ok, "broadcast addrs=%s lan_ip=%s" % [addrs, lan]]


func _mnt_s_bad_ip() -> void:
	join_game("999.999.999.999")


func _mnt_c_bad_ip() -> Array:
	# Either create_client rejects the bad address at once, or the
	# join attempt is in progress with a clear status — both are a
	# visible error path, never a silent hang.
	var status := _status.text
	var ok: bool = status != "" and ("Could not connect" in status or "Could not reach" in status or "Connecting to" in status)
	if _joining or multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		_close_peer()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		_peer = null
		_joining = false
	return [ok, "status after bad IP: '%s'" % status]


func _mnt_s_create_room() -> void:
	GameData.room_name = "MenuTest"
	GameData.max_players = 4
	GameData.room_private = false
	GameData.room_password = ""
	_room_name_input.text = "MenuTest"
	_create_room()


func _mnt_c_create_room() -> Array:
	var ip := LanDiscovery.lan_ip()
	var label_ok := _host_ip_label.visible
	if ip != "":
		label_ok = label_ok and ip in _host_ip_label.text
	else:
		label_ok = label_ok and "No Wi-Fi IP" in _host_ip_label.text
	var ok: bool = _is_host and multiplayer.is_server() and _lobby_panel.visible and _lobby_players.size() == 1 and label_ok
	return [ok, "host=%s server=%s lobby visible=%s players=%d host-ip label ok=%s (lan_ip='%s')" % [_is_host, multiplayer.is_server(), _lobby_panel.visible, _lobby_players.size(), label_ok, ip]]


func _mnt_s_ready() -> void:
	_on_ready_pressed()


func _mnt_c_ready() -> Array:
	var my_id := multiplayer.get_unique_id()
	var ready: bool = bool(_lobby_players.get(my_id, {}).get("ready", false))
	return [ready, "own ready state after toggle: %s (want true)" % ready]


func _mnt_s_leave() -> void:
	_leave_lobby()
	_show_only(_mp_panel)


func _mnt_c_leave() -> Array:
	var ok: bool = not _is_host and _lobby_players.is_empty() and _mp_panel.visible
	return [ok, "left cleanly: host=%s players=%d mp panel visible=%s" % [_is_host, _lobby_players.size(), _mp_panel.visible]]


# =====================================================================
# v2.4 FULL-FLOW CHECK (menu side, --flow-test)
# menu -> create room -> lobby (host IP shown) -> start match. The
# game scene continues the check (play / pause / scoreboard / end /
# back) and returns here with GameData.flow_phase == 2.
# =====================================================================

func _update_flowtest(delta: float) -> void:
	if _flow_done:
		return
	if _flow_steps.is_empty():
		_flowtest_build_steps()
		_flow_step = 0
		_flow_in_step = false
		_flow_timer = 0.0
	if _flow_step >= _flow_steps.size():
		_flow_done = true
		print("FLOWTEST MENU: %d/%d passed" % [_flow_passed, _flow_passed + _flow_failed])
		return
	var step: Dictionary = _flow_steps[_flow_step]
	if not _flow_in_step:
		(step["setup"] as Callable).call()
		_flow_in_step = true
		_flow_timer = float(step["wait"])
	_flow_timer -= delta
	if _flow_timer <= 0.0:
		var result: Array = (step["check"] as Callable).call()
		var ok: bool = bool(result[0])
		if ok:
			_flow_passed += 1
		else:
			_flow_failed += 1
		print("FLOWTEST %s: %s — %s" % [String(step["name"]), "PASS" if ok else "FAIL", String(result[1])])
		_flow_step += 1
		_flow_in_step = false
		_flow_timer = 0.0


func _flowtest_build_steps() -> void:
	_flow_steps = [
		{"name": "MENU-VISIBLE", "wait": 0.3, "setup": _flm_s_noop, "check": _flm_c_menu},
		{"name": "CREATE-ROOM", "wait": 0.5, "setup": _flm_s_create, "check": _flm_c_lobby},
		{"name": "START-MATCH", "wait": 0.3, "setup": _flm_s_start, "check": _flm_c_started},
	]


func _flm_s_noop() -> void:
	pass


func _flm_c_menu() -> Array:
	var ok: bool = _menu_panel.visible
	_capture_flow_shot_now("user://shot_menu.png")
	return [ok, "main menu visible=%s" % _menu_panel.visible]


func _flm_s_create() -> void:
	GameData.room_name = "FlowTest"
	GameData.max_players = 4
	GameData.room_private = false
	GameData.room_password = ""
	_room_name_input.text = "FlowTest"
	_create_room()


func _flm_c_lobby() -> Array:
	var ip := LanDiscovery.lan_ip()
	var label_ok := _host_ip_label.visible and (ip == "" or ip in _host_ip_label.text)
	var ok: bool = _lobby_panel.visible and _is_host and label_ok
	_capture_flow_shot_now("user://shot_lobby.png")
	return [ok, "lobby visible=%s host=%s host-ip label ok=%s (lan_ip='%s')" % [_lobby_panel.visible, _is_host, label_ok, ip]]


func _flm_s_start() -> void:
	# Hand over to the game scene: it runs the rest of the check.
	GameData.flow_test = true
	GameData.flow_phase = 1
	_on_start_pressed()


func _flm_c_started() -> Array:
	# The scene change happens in start_match; this check is only
	# reached if the match did not start.
	return [false, "still in the menu after START MATCH"]


# =====================================================================
# v3.5 RESTART CHECK (menu side, --restart-test, QA-060)
# First leg: create a room and start match 1 (game side plays, then
# leaves with restart_phase == 2). Second leg: this scene loads
# again with phase 2 — create a FRESH room and start match 2 (the
# exact path a player takes after leaving a match). The game side
# then ends match 2 and rematches (scene reload, phase 4).
# =====================================================================

func _restarttest_begin() -> void:
	GameData.room_name = "RestartTest"
	GameData.max_players = 4
	GameData.room_private = false
	GameData.room_password = ""
	_room_name_input.text = "RestartTest"
	_create_room()
	GameData.restart_phase = 1
	_on_start_pressed()


func _restarttest_second_start() -> void:
	GameData.room_name = "RestartTest2"
	GameData.max_players = 4
	GameData.room_private = false
	GameData.room_password = ""
	_room_name_input.text = "RestartTest2"
	_create_room()
	var ok: bool = _lobby_panel.visible and _is_host
	if ok:
		GameData.restart_passed += 1
	else:
		GameData.restart_failed += 1
	print("RESTARTTEST %s: %s" % ["SECOND-LOBBY", "PASS" if ok else "FAIL"])
	GameData.restart_phase = 3
	_on_start_pressed()

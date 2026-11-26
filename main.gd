extends Control

# Main menu + customization + settings + LAN lobby.
# LAN / local Wi-Fi only. No online multiplayer, no accounts, no bots.

const GAME_SCENE := "res://game.tscn"
const PORT := 7777
const JOIN_TIMEOUT := 8.0
const AUDIO_SCRIPT: Script = preload("res://audio/audio.gd")

# v3.2 NEON ARENA fonts (SIL OFL 1.1 — see THEME_SPEC.md §1b).
const FONT_TITLE: Font = preload("res://assets/fonts/orbitron/Orbitron-Variable.ttf")
const FONT_BODY: Font = preload("res://assets/fonts/rajdhani/Rajdhani-Regular.ttf")
const FONT_BODY_SEMIBOLD: Font = preload("res://assets/fonts/rajdhani/Rajdhani-SemiBold.ttf")


var _audio
var menu_ui: MenuUi # UI helpers (background, styles, panels, labels)
var menu_screens: MenuScreens # menu, customize, settings screens
var menu_multiplayer: MenuMultiplayer # multiplayer page (create/join)
var menu_lobby: MenuLobby # lobby build, map/mode/vote
var menu_lobby_setup: MenuLobbySetup # team/role/appearance, lobby refresh
var menu_net: MenuNet # room create/join, lobby RPCs, start match
var menu_test: MenuTest # test harness (scroll, shots, menu-net, flow, restart)
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
var _lobby_practice_btn: Button
var _lobby_players_badge: GoBadge # v3.6 QA-069: header players pill ("1/4 PLAYERS"), updated in _refresh_lobby_buttons
var _profile_portrait: TextureRect # QA-078: main-menu profile card
var _profile_name_lbl: Label
var _profile_level_lbl: Label
var _profile_stats_lbl: Label
var _team_buttons: Array = [] # QA-078: RED / BLUE / AUTO team pick (team modes only)
var _team_section_label: Label # QA-078: hidden with the team row in FFA modes
var _role_buttons: Array = [] # QA-112 (v3.9): Skyfall role pick (Attacker / Defender / Sniper / Support)
var _role_section_label: Label # QA-112: hidden with the role row when the map is not Skyfall
var _role_row: HBoxContainer # QA-112: the role button row (Skyfall only)
var _skyfall_banner_row: HBoxContainer # QA-112: red + blue team banners (Skyfall CTF only)
var _lobby_color_buttons: Array = [] # QA-078: in-lobby appearance
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
var _portrait_tex: TextureRect
var _name_input: LineEdit
# Phase 4 — settings screen controls.
var _music_check: CheckButton
var _sfx_check: CheckButton
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
	menu_ui = MenuUi.new(self)
	menu_screens = MenuScreens.new(self)
	menu_multiplayer = MenuMultiplayer.new(self)
	menu_lobby = MenuLobby.new(self)
	menu_lobby_setup = MenuLobbySetup.new(self)
	menu_net = MenuNet.new(self)
	menu_test = MenuTest.new(self)
	_audio.set_volumes(GameData.sfx_volume, GameData.music_volume)
	_audio.set_music_enabled(GameData.music_enabled)
	_audio.set_sfx_enabled(GameData.sfx_enabled)
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
	return menu_ui._build_background()


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
	return menu_ui._cut_accent_stylebox()


func _style_button(b: Button, font_size: int = 22, min_h: int = 56, accent: bool = false) -> void:
	return menu_ui._style_button(b, font_size, min_h, accent)


# Selected toggle state (map / mode / limit / time / colour).
func _style_selected(b: Button, selected: bool, font_size: int = 22) -> void:
	return menu_ui._style_selected(b, selected, font_size)


# Danger action (Leave / disconnect): danger-red fill via the same
# cut-corner shape, white text.
func _style_danger_button(b: Button, font_size: int = 22, min_h: int = 56) -> void:
	return menu_ui._style_danger_button(b, font_size, min_h)


func _panel(style_bg: Color = Color(0.07, 0.11, 0.18, 0.96), transparent: bool = false) -> PanelContainer:
	return menu_ui._panel(style_bg)


# SCROLL_BUG.md §4 — forward drags that start on a button inside a
# ScrollContainer to the container. A Button captures the touch and
# the ScrollContainer never sees the drag otherwise (proven root
# cause). Taps still go through the button's normal pressed path.
func _connect_scroll_button(b: Button, scroll: ScrollContainer) -> void:
	return menu_ui._connect_scroll_button(b, scroll)


func _on_scrolled_button_gui_input(event: InputEvent, scroll: ScrollContainer, b: Button) -> void:
	return menu_ui._on_scrolled_button_gui_input(event, scroll, b)


# v3.2: gohud icons replace the hand-drawn _make_icon() shapes.
func _gohud_icon(icon_name: String) -> Texture2D:
	return menu_ui._gohud_icon(icon_name)


func _vbox(parent: Control, sep: int = 12) -> VBoxContainer:
	return menu_ui._vbox(parent, sep)


func _section_label(text: String) -> Label:
	return menu_ui._section_label(text)


func _title_label(text: String, size: int = 30) -> Label:
	return menu_ui._title_label(text, size)


# Body / hint / status text (THEME_SPEC.md §3): Rajdhani Regular, NOT
# Orbitron — the variable Orbitron renders too thin and light at
# 16-20 px to read (the menu subtitle showed this in the v3.2 shots).
func _body_label(text: String, size: int = 18) -> Label:
	return menu_ui._body_label(text, size)


func _show_only(panel: PanelContainer) -> void:
	return menu_ui._show_only(panel)



func _click() -> void:
	return menu_ui._click()


func _build_menu() -> void:
	return menu_screens._build_menu()


# QA-078: fill the main-menu profile card from the saved lifetime
# stats. Called at build time and every time the menu is shown
# (a match just played may have changed the numbers). Safe to call
# before the card exists (the menu builds it first).
func _refresh_profile_card() -> void:
	return menu_screens._refresh_profile_card()


func _build_customize() -> void:
	return menu_screens._build_customize()


func _on_name_changed(text: String) -> void:
	return menu_screens._on_name_changed(text)


func _on_color_pressed(i: int) -> void:
	return menu_screens._on_color_pressed(i)


func _refresh_customize_buttons() -> void:
	return menu_screens._refresh_customize_buttons()


func _on_portrait_prev() -> void:
	return menu_screens._on_portrait_prev()


func _on_portrait_next() -> void:
	return menu_screens._on_portrait_next()


# Phase 4 — portraits 0-14 are the original soldier variants;
# 15-19 are the Sky Brawl robot colour variants (lobby select only —
# single static frames, never the in-game sprite).
func _portrait_texture(i: int) -> Texture2D:
	return menu_screens._portrait_texture(i)


func _update_portrait() -> void:
	return menu_screens._update_portrait()


func _build_settings() -> void:
	return menu_screens._build_settings()


func _slider_row(label_text: String, value: float, on_change: Callable, min_v: float = 0.0, max_v: float = 1.0) -> HBoxContainer:
	return menu_screens._slider_row(label_text, value, on_change, min_v, max_v)


func _on_sfx_changed(v: float) -> void:
	return menu_screens._on_sfx_changed(v)


func _on_music_changed(v: float) -> void:
	return menu_screens._on_music_changed(v)


func _on_sensitivity_changed(v: float) -> void:
	return menu_screens._on_sensitivity_changed(v)


func _on_music_enabled_toggled(on: bool) -> void:
	return menu_screens._on_music_enabled_toggled(on)


func _on_sfx_enabled_toggled(on: bool) -> void:
	return menu_screens._on_sfx_enabled_toggled(on)


func _on_fps_toggled(on: bool) -> void:
	return menu_screens._on_fps_toggled(on)


func _on_invert_toggled(on: bool) -> void:
	return menu_screens._on_invert_toggled(on)


func _build_multiplayer() -> void:
	return menu_multiplayer._build_multiplayer()


# QA-112 (v3.9): Capture the Flag (mode 4) is only on Skyfall.
# Every mode refresh and mode press goes through this check, so
# CTF can never be picked — or stay picked — on the other 4 maps.
func _ctf_available() -> bool:
	return menu_lobby._ctf_available()


func _refresh_create_mode_buttons() -> void:
	return menu_lobby._refresh_create_mode_buttons()


func _on_create_mode_pressed(i: int) -> void:
	return menu_lobby._on_create_mode_pressed(i)


func _build_lobby() -> void:
	return menu_lobby._build_lobby()


# v3.5 QA-059 (v3.6 QA-069): one map card — real map art
# thumbnail + name + size info + a gohud GoBadge ("✓ SELECTED")
# when selected. The visible card is a PanelContainer; a
# transparent full-rect Button on top is the input, so
# _map_buttons stays an Array of Buttons: the QA-048 scroll
# test, taps and drag-forwarding all work exactly as before.
func _map_card_stylebox(selected: bool) -> StyleBoxFlat:
	return menu_lobby._map_card_stylebox(selected)


func _build_map_card(i: int) -> Control:
	return menu_lobby._build_map_card(i)


# v3.6 QA-069: one lobby chip — a gohud GoBadge with words
# (HOST / YOU / READY ✓ / NOT READY). Replaces the hand-rolled
# _badge_chip PanelContainer (v3.5). Display-only: mouse-transparent
# so a drag starting on a chip scrolls the left column.
func _lobby_chip(text: String, ink: Color) -> GoBadge:
	return menu_lobby._lobby_chip(text, ink)


func _on_map_pressed(i: int) -> void:
	return menu_lobby._on_map_pressed(i)


# Phase 4 — map vote: the ballot is the host's pick + the next two
# maps. Everyone may vote; the host tallies at match start.
func _vote_candidates_now() -> Array:
	return menu_lobby._vote_candidates_now()


func _on_vote_pressed(slot: int) -> void:
	return menu_lobby._on_vote_pressed(slot)


@rpc("any_peer")
func set_vote(map_choice: int) -> void:
	return menu_lobby.set_vote(map_choice)


func _refresh_vote_buttons() -> void:
	return menu_lobby._refresh_vote_buttons()


func _on_mode_pressed(i: int) -> void:
	return menu_lobby._on_mode_pressed(i)


func _on_limit_pressed(kl: int) -> void:
	return menu_lobby._on_limit_pressed(kl)


func _on_time_pressed(mins: int) -> void:
	return menu_lobby._on_time_pressed(mins)


# QA-078: team pick (team modes only). Stored per player in the
# lobby dict, so every phone sees it; the host reads it at spawn
# time (game.gd _do_spawn honours it unless the team is full).
func _on_team_pressed(t: int) -> void:
	return menu_lobby_setup._on_team_pressed(t)


@rpc("any_peer")
func set_team(t: int) -> void:
	return menu_lobby_setup.set_team(t)


# QA-112 (v3.9): Skyfall role icon for a team + role. Team 1 is
# blue, team 0 and AUTO (-1 / unset) fall back to the red icons.
# Roles are LABELS ONLY — no gameplay effect.
func _role_icon(team: int, role: int) -> Texture2D:
	return menu_lobby_setup._role_icon(team, role)


# QA-112: role pick (Skyfall only). Same sync pattern as the team
# pick: the host writes my lobby entry and broadcasts; a joiner
# sends set_role to the host, which clamps it to 0-3 and broadcasts.
func _on_role_pressed(i: int) -> void:
	return menu_lobby_setup._on_role_pressed(i)


@rpc("any_peer")
func set_role(r: int) -> void:
	return menu_lobby_setup.set_role(r)


# QA-078: in-lobby appearance change. Updates my saved settings
# AND my lobby entry, then syncs to the whole room at once.
func _on_lobby_color_pressed(i: int) -> void:
	return menu_lobby_setup._on_lobby_color_pressed(i)


func _sync_my_appearance() -> void:
	return menu_lobby_setup._sync_my_appearance()


@rpc("any_peer")
func update_appearance(color_idx: int) -> void:
	return menu_lobby_setup.update_appearance(color_idx)


# QA-112 (v3.9): minimum to start a match — a match starts with
# whoever is in the room, NEVER a full team (5v5 = 10). At least 2
# players total; in team modes (TDM mode 1, CTF mode 4) at least 1
# player on EACH team (RED 0 / BLUE 1). AUTO (-1) counts as able to
# fill either side: the minimum is met when (red + auto) >= 1 AND
# (blue + auto) >= 1 AND total >= 2. No maximum / full-team check.
func _start_minimum_reason() -> String:
	return menu_lobby_setup._start_minimum_reason()


func _start_minimum_met() -> bool:
	return menu_lobby_setup._start_minimum_met()


func _refresh_lobby_buttons() -> void:
	return menu_lobby_setup._refresh_lobby_buttons()


func _refresh_lobby_list() -> void:
	return menu_lobby_setup._refresh_lobby_list()


func _on_max_pressed(n: int) -> void:
	return menu_lobby_setup._on_max_pressed(n)


func _refresh_max_buttons() -> void:
	return menu_lobby_setup._refresh_max_buttons()


func _on_private_toggled(on: bool) -> void:
	return menu_lobby_setup._on_private_toggled(on)


func _on_friendly_fire_toggled(on: bool) -> void:
	return menu_lobby_setup._on_friendly_fire_toggled(on)


func _update_my_ip_label() -> void:
	return menu_lobby_setup._update_my_ip_label()


func _room_card() -> Dictionary:
	return menu_lobby_setup._room_card()


func _on_create_room_pressed() -> void:
	return menu_net._on_create_room_pressed()


func _server_port() -> int:
	return menu_net._server_port()


func _create_room() -> bool:
	return menu_net._create_room()


func _on_join_pressed() -> void:
	return menu_net._on_join_pressed()


func _on_quick_match_pressed() -> void:
	return menu_net._on_quick_match_pressed()


func _on_join_code_pressed() -> void:
	return menu_net._on_join_code_pressed()


func _on_refresh_pressed() -> void:
	return menu_net._on_refresh_pressed()


func join_game(ip: String, password: String = "") -> void:
	return menu_net.join_game(ip, password)


func _on_connected() -> void:
	return menu_net._on_connected()


# QA-060: close the current ENet peer explicitly before dropping
# it. A dropped-but-open peer can keep its UDP socket bound, so the
# next create_server / create_client on the same port fails with
# "Couldn't create an ENet host". Every teardown site uses this.
func _close_peer() -> void:
	return menu_net._close_peer()


func _on_connection_failed() -> void:
	return menu_net._on_connection_failed()


func _my_lobby_info() -> Dictionary:
	return menu_net._my_lobby_info()


@rpc("any_peer")
func register_lobby_player(info: Dictionary) -> void:
	return menu_net.register_lobby_player(info)


@rpc("any_peer", "call_local")
func join_rejected(reason: String) -> void:
	return menu_net.join_rejected(reason)


@rpc("any_peer")
func set_ready(ready: bool) -> void:
	return menu_net.set_ready(ready)


func _on_ready_pressed() -> void:
	return menu_net._on_ready_pressed()


@rpc("any_peer", "call_local")
func kicked_from_lobby(reason: String) -> void:
	return menu_net.kicked_from_lobby(reason)


func _on_kick_pressed(id: int) -> void:
	return menu_net._on_kick_pressed(id)


func _broadcast_lobby() -> void:
	return menu_net._broadcast_lobby()


@rpc("any_peer", "call_local")
func lobby_update(players: Dictionary, settings: Dictionary) -> void:
	return menu_net.lobby_update(players, settings)


func _on_peer_connected(id: int) -> void:
	return menu_net._on_peer_connected(id)


func _on_server_disconnected() -> void:
	return menu_net._on_server_disconnected()


func _on_peer_disconnected(id: int) -> void:
	return menu_net._on_peer_disconnected(id)


func _on_start_pressed() -> void:
	return menu_net._on_start_pressed()


func _on_lobby_practice_pressed() -> void:
	return menu_net._on_lobby_practice_pressed()


@rpc("any_peer", "call_local")
func start_match(map_id: int, mode: int, kill_limit: int, minutes: int) -> void:
	return menu_net.start_match(map_id, mode, kill_limit, minutes)


func _on_lobby_leave_pressed() -> void:
	return menu_net._on_lobby_leave_pressed()


func _leave_lobby() -> void:
	return menu_net._leave_lobby()


func _on_room_found(_room: Dictionary) -> void:
	return menu_net._on_room_found(_room)


func _on_room_expired(_ip: String) -> void:
	return menu_net._on_room_expired(_ip)


func _room_signature() -> String:
	return menu_net._room_signature()


func _refresh_room_list() -> void:
	return menu_net._refresh_room_list()


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
	return menu_test._scrolltest_begin()


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


func _update_scrolltest(delta: float) -> void:
	return menu_test._update_scrolltest(delta)


# =====================================================================
# v3.2 SCREENSHOT MODE (--shot-all): captures every menu-side screen
# to user://shot_*.png for the visual review (THEME_SPEC.md §9).
# =====================================================================

var _shot_steps: Array = []
var _shot_step: int = 0
var _shot_in_step: bool = false
var _shot_timer: float = 0.0


func _shotall_begin() -> void:
	return menu_test._shotall_begin()


func _update_shotall(delta: float) -> void:
	return menu_test._update_shotall(delta)


# =====================================================================
# v3.2 JOIN TEST — host side (--join-test-host) + Quick Play client
# side (--join-test-client-quick). Two real Godot processes on
# loopback: host creates a room and auto-starts; the client finds the
# room via discovery and joins with QUICK LAN MATCH (the exact path
# the user used), then both sides report in game.gd (JOINTEST).
# =====================================================================

func _jointest_host_begin() -> void:
	return menu_test._jointest_host_begin()


func _jointest_client_quick_begin() -> void:
	return menu_test._jointest_client_quick_begin()


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
	return menu_test._rejointest_host_begin()


func _rejointest_client_begin() -> void:
	return menu_test._rejointest_client_begin()


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
	return menu_test._update_menu_nettest(delta)


# =====================================================================
# v2.4 FULL-FLOW CHECK (menu side, --flow-test)
# menu -> create room -> lobby (host IP shown) -> start match. The
# game scene continues the check (play / pause / scoreboard / end /
# back) and returns here with GameData.flow_phase == 2.
# =====================================================================

func _update_flowtest(delta: float) -> void:
	return menu_test._update_flowtest(delta)


# =====================================================================
# v3.5 RESTART CHECK (menu side, --restart-test, QA-060)
# First leg: create a room and start match 1 (game side plays, then
# leaves with restart_phase == 2). Second leg: this scene loads
# again with phase 2 — create a FRESH room and start match 2 (the
# exact path a player takes after leaving a match). The game side
# then ends match 2 and rematches (scene reload, phase 4).
# =====================================================================

func _restarttest_begin() -> void:
	return menu_test._restarttest_begin()


func _restarttest_second_start() -> void:
	return menu_test._restarttest_second_start()

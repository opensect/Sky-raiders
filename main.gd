extends Control

# Main menu + customization + settings + LAN lobby.
# LAN / local Wi-Fi only. No online multiplayer, no accounts, no bots.

const GAME_SCENE := "res://game.tscn"
const PORT := 7777
const JOIN_TIMEOUT := 8.0
const AUDIO_SCRIPT: Script = preload("res://audio.gd")

const MAP_THUMBS := {
	0: preload("res://assets/thumbs/thumb_catacombs.png"),
	1: preload("res://assets/thumbs/thumb_military.png"),
	2: preload("res://assets/thumbs/thumb_desert.png"),
	3: preload("res://assets/thumbs/thumb_factory.png"),
	4: preload("res://assets/thumbs/thumb_frozen.png"),
	5: preload("res://assets/thumbs/thumb_jungle.png"),
	6: preload("res://assets/thumbs/thumb_space.png"),
	7: preload("res://assets/thumbs/thumb_city.png"),
	8: preload("res://assets/thumbs/thumb_volcanic.png"),
	9: preload("res://assets/thumbs/thumb_pirate.png"),
}
const MENU_BG: Texture2D = preload("res://assets/backgrounds/arena_blue.png")
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
}
const HELMET_NAMES := ["No helmet", "Helmet", "Cap", "Black helmet"]

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
var _room_info_label: Label
var _lobby_list: VBoxContainer
var _lobby_start_btn: Button
var _ready_btn: Button
var _ff_check: CheckButton
var _map_buttons: Array = []
var _mode_buttons: Array = []
var _limit_buttons: Array = []
var _time_buttons: Array = []
var _max_buttons: Array = []
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
var _scroll_hint_label: Label
var _shot_all: bool = false
var _shot_idx: int = 0
# v3.2 join regression test (--join-test-host): auto-create a room
# and auto-start the match, so a second process can join for real.
var _join_test_host: bool = false
var _join_test_client_quick: bool = false


func _ready() -> void:
	# v3.2 NEON ARENA: gohud scifi_dark drives every screen (see
	# THEME_SPEC.md). Set once, early, before any panel is built;
	# the root theme is inherited by all children.
	GoUi.config = preload("res://ui/gohud_config.tres")
	GoUi.use_preset(GoThemePresets.SCIFI_DARK)
	theme = GoUi.theme()
	GameData.load_settings()
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
	if _join_test_host:
		call_deferred("_jointest_host_begin")
	if _join_test_client_quick:
		call_deferred("_jointest_client_quick_begin")
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
	var err := peer.create_server(PORT, 7)
	if err != OK:
		return
	multiplayer.multiplayer_peer = peer
	get_tree().change_scene_to_file(GAME_SCENE)


func _build_background() -> void:
	# v3.2 NEON ARENA (THEME_SPEC.md §6): ONE imported image — the
	# Sky Brawl blue arena (arena_map_02.png) — stretched full-rect,
	# with a 0.55-alpha dark scrim over it so text stays readable.
	# The old procedural gradient sky + sun + ground band is gone.
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
	if event is InputEventScreenDrag:
		scroll.scroll_vertical -= event.relative.y


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
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT_BODY_SEMIBOLD)
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", UI_FONT_MUTED)
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



func _click() -> void:
	if _audio != null:
		_audio.play("click")


func _build_menu() -> void:
	_menu_panel = _panel(Color(0.07, 0.11, 0.18, 0.96), true)
	var box := _vbox(_menu_panel, 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := _title_label("LAN ARENA SHOOTER", 40)
	title.add_theme_color_override("font_color", UI_ACCENT)
	box.add_child(title)
	var sub := _body_label("2D shooter - local Wi-Fi only, no accounts", 20)
	sub.add_theme_color_override("font_color", UI_FONT_MUTED)
	box.add_child(sub)
	var mp_btn := Button.new()
	mp_btn.text = "LOCAL MULTIPLAYER"
	mp_btn.icon = _gohud_icon("play")
	mp_btn.expand_icon = true
	mp_btn.custom_minimum_size = Vector2(420, 64)
	mp_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_button(mp_btn, 26, 64, true)
	mp_btn.pressed.connect(func() -> void: _click(); _show_only(_mp_panel))
	box.add_child(mp_btn)
	var cust_btn := Button.new()
	cust_btn.text = "CUSTOMIZATION"
	cust_btn.icon = _gohud_icon("user")
	cust_btn.expand_icon = true
	cust_btn.custom_minimum_size = Vector2(420, 64)
	cust_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_button(cust_btn, 26, 64)
	cust_btn.pressed.connect(func() -> void: _click(); _show_only(_custom_panel))
	box.add_child(cust_btn)
	var set_btn := Button.new()
	set_btn.text = "SETTINGS"
	set_btn.icon = _gohud_icon("settings")
	set_btn.expand_icon = true
	set_btn.custom_minimum_size = Vector2(420, 64)
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
	privacy_lbl.text = "LAN Arena Shooter collects no personal data. No accounts, no sign-in, no ads, no analytics, no tracking. Phones talk directly to each other over your Wi-Fi (LAN) only — nothing is sent to the internet or any server. Settings (name, controls, volume) stay on your phone."
	privacy_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	privacy_lbl.add_theme_font_override("font", FONT_BODY)
	privacy_lbl.add_theme_font_size_override("font_size", 18)
	privacy_lbl.add_theme_color_override("font_color", UI_FONT_MUTED)
	box.add_child(privacy_lbl)
	var version_lbl := Label.new()
	version_lbl.text = "LAN Arena Shooter v3.3  •  LAN only — no accounts, no servers"
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
	box.add_child(_title_label("LOCAL MULTIPLAYER", 30))
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
	box.add_child(_section_label("Create a room:"))
	_room_name_input = LineEdit.new()
	_room_name_input.placeholder_text = "Room name, e.g. Tharun's Room"
	_room_name_input.text = GameData.room_name
	_room_name_input.custom_minimum_size = Vector2(0, 56)
	_room_name_input.add_theme_font_size_override("font_size", 22)
	box.add_child(_room_name_input)
	var max_row := HBoxContainer.new()
	max_row.add_theme_constant_override("separation", 8)
	box.add_child(max_row)
	var max_lbl := Label.new()
	max_lbl.text = "Max players:"
	max_lbl.add_theme_font_size_override("font_size", 20)
	max_row.add_child(max_lbl)
	for n in [2, 4, 6, 8, 10, 12]:
		var b := Button.new()
		b.text = str(n)
		b.custom_minimum_size = Vector2(56, 56)
		_style_button(b, 20, 56)
		b.pressed.connect(_on_max_pressed.bind(n))
		max_row.add_child(b)
		_max_buttons.append(b)
		_connect_scroll_button(b, _mp_scroll)
	var priv_row := HBoxContainer.new()
	priv_row.add_theme_constant_override("separation", 10)
	box.add_child(priv_row)
	_private_check = CheckButton.new()
	_private_check.text = "Private room"
	_private_check.add_theme_font_size_override("font_size", 20)
	_private_check.button_pressed = GameData.room_private
	_private_check.toggled.connect(_on_private_toggled)
	priv_row.add_child(_private_check)
	_room_password_input = LineEdit.new()
	_room_password_input.placeholder_text = "Room password (if private)"
	_room_password_input.text = GameData.room_password
	_room_password_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_password_input.custom_minimum_size = Vector2(0, 56)
	_room_password_input.add_theme_font_size_override("font_size", 20)
	priv_row.add_child(_room_password_input)
	var create_btn := Button.new()
	create_btn.text = "CREATE ROOM"
	create_btn.custom_minimum_size = Vector2(0, 64)
	_style_button(create_btn, 26, 64, true)
	create_btn.pressed.connect(_on_create_room_pressed)
	box.add_child(create_btn)
	_connect_scroll_button(create_btn, _mp_scroll)

	# --- Join a room ---
	box.add_child(_section_label("Join a room:"))
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 10)
	box.add_child(join_row)
	_ip_input = LineEdit.new()
	_ip_input.placeholder_text = "Host IP, e.g. 192.168.1.5"
	_ip_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_input.custom_minimum_size = Vector2(0, 60)
	_ip_input.add_theme_font_size_override("font_size", 22)
	join_row.add_child(_ip_input)
	var join_btn := Button.new()
	join_btn.text = "JOIN"
	join_btn.custom_minimum_size = Vector2(120, 60)
	_style_button(join_btn, 26, 60, true)
	join_btn.pressed.connect(_on_join_pressed)
	join_row.add_child(join_btn)
	_connect_scroll_button(join_btn, _mp_scroll)
	var pw_row := HBoxContainer.new()
	pw_row.add_theme_constant_override("separation", 10)
	box.add_child(pw_row)
	var pw_lbl := Label.new()
	pw_lbl.text = "Password:"
	pw_lbl.add_theme_font_size_override("font_size", 20)
	pw_row.add_child(pw_lbl)
	_join_password_input = LineEdit.new()
	_join_password_input.placeholder_text = "Only for private rooms"
	_join_password_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_password_input.custom_minimum_size = Vector2(0, 56)
	_join_password_input.add_theme_font_size_override("font_size", 20)
	pw_row.add_child(_join_password_input)
	var quick_row := HBoxContainer.new()
	quick_row.add_theme_constant_override("separation", 10)
	box.add_child(quick_row)
	var quick_btn := Button.new()
	quick_btn.text = "QUICK LAN MATCH"
	quick_btn.custom_minimum_size = Vector2(0, 60)
	quick_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(quick_btn, 22, 60, true)
	quick_btn.pressed.connect(_on_quick_match_pressed)
	quick_row.add_child(quick_btn)
	_connect_scroll_button(quick_btn, _mp_scroll)
	var refresh_btn := Button.new()
	refresh_btn.text = "REFRESH"
	refresh_btn.custom_minimum_size = Vector2(160, 60)
	_style_button(refresh_btn, 22, 60)
	refresh_btn.pressed.connect(_on_refresh_pressed)
	quick_row.add_child(refresh_btn)
	_connect_scroll_button(refresh_btn, _mp_scroll)

	box.add_child(_section_label("Games found on this Wi-Fi:"))
	var rooms_hint := _body_label("Tap a room to join it. If nothing appears, type the host IP above.", 18)
	rooms_hint.add_theme_color_override("font_color", UI_FONT_MUTED)
	box.add_child(rooms_hint)
	# Room list: plain VBox inside the outer scroll (the v3.1 inner
	# ScrollContainer got zero height — see the note at the top of
	# this function). Room buttons forward drags to _mp_scroll.
	_host_buttons = VBoxContainer.new()
	_host_buttons.add_theme_constant_override("separation", 8)
	_host_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_host_buttons)
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


func _build_lobby() -> void:
	# Full-rect panel + ScrollContainer: the lobby fits ANY screen height.
	# The title, status and START MATCH stay fixed; the player list, map
	# grid, mode, kill limit and match time scroll inside.
	_lobby_panel = _panel()
	var box := _vbox(_lobby_panel, 10)
	box.add_child(_title_label("GAME LOBBY", 30))
	_lobby_status = Label.new()
	_lobby_status.text = ""
	_lobby_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby_status.add_theme_font_size_override("font_size", 20)
	box.add_child(_lobby_status)
	# v2.4: the host's LAN IP, big and clear — this is the number a
	# friend types to join when discovery does not find the room.
	_host_ip_label = Label.new()
	_host_ip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_host_ip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_host_ip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host_ip_label.custom_minimum_size = Vector2(0, 30)
	_host_ip_label.add_theme_font_override("font", FONT_BODY_BOLD)
	_host_ip_label.add_theme_font_size_override("font_size", 24)
	_host_ip_label.add_theme_color_override("font_color", UI_ACCENT)
	box.add_child(_host_ip_label)
	_room_info_label = Label.new()
	_room_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_room_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_info_label.custom_minimum_size = Vector2(0, 24)
	_room_info_label.add_theme_font_override("font", FONT_BODY)
	_room_info_label.add_theme_font_size_override("font_size", 18)
	_room_info_label.add_theme_color_override("font_color", UI_FONT_MUTED)
	box.add_child(_room_info_label)
	var controls_hint := Label.new()
	controls_hint.text = "Left stick: move • Push up: jump / fly • Right stick: aim and shoot"
	controls_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_hint.custom_minimum_size = Vector2(0, 24)
	controls_hint.add_theme_font_override("font", FONT_BODY)
	controls_hint.add_theme_font_size_override("font_size", 18)
	controls_hint.add_theme_color_override("font_color", UI_FONT)
	_controls_hint_label = controls_hint
	box.add_child(controls_hint)
	var join_hint := Label.new()
	join_hint.text = "Friends join from LOCAL MULTIPLAYER — they tap your room, or type the host IP above."
	join_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	join_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	join_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_hint.custom_minimum_size = Vector2(0, 24)
	join_hint.add_theme_font_override("font", FONT_BODY)
	join_hint.add_theme_font_size_override("font_size", 18)
	join_hint.add_theme_color_override("font_color", UI_FONT_MUTED)
	box.add_child(join_hint)
	var scroll := ScrollContainer.new()
	_lobby_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	inner.add_child(_section_label("Players in the room:"))
	_lobby_list = VBoxContainer.new()
	_lobby_list.add_theme_constant_override("separation", 4)
	inner.add_child(_lobby_list)
	_map_section_label = _section_label("Map:")
	inner.add_child(_map_section_label)
	var map_grid := GridContainer.new()
	map_grid.columns = 2
	map_grid.add_theme_constant_override("h_separation", 8)
	map_grid.add_theme_constant_override("v_separation", 8)
	inner.add_child(map_grid)
	for i in GameData.MAP_NAMES.size():
		var b := Button.new()
		b.text = GameData.MAP_NAMES[i]
		if MAP_THUMBS.has(i):
			b.icon = MAP_THUMBS[i]
		b.custom_minimum_size = Vector2(0, 72)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_style_button(b, 20, 72)
		b.pressed.connect(_on_map_pressed.bind(i))
		map_grid.add_child(b)
		_map_buttons.append(b)
		_connect_scroll_button(b, _lobby_scroll)
	# THEME_SPEC.md §8: visible scroll hint under the map grid — it
	# is also a label, so a drag starting on it scrolls (SCROLL_BUG.md).
	var scroll_hint := Label.new()
	scroll_hint.text = "Scroll for more maps ↓"
	scroll_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scroll_hint.add_theme_font_override("font", FONT_BODY)
	scroll_hint.add_theme_font_size_override("font_size", 18)
	scroll_hint.add_theme_color_override("font_color", UI_ACCENT)
	_scroll_hint_label = scroll_hint
	inner.add_child(scroll_hint)
	# Phase 4 — map vote: every player picks one of 3 maps on the
	# ballot (the host's pick + the next two). The host tallies the
	# votes when the match starts; ties and no-votes keep the host's
	# pick. Votes travel in the lobby player dicts (see set_vote).
	inner.add_child(_section_label("Map vote — pick the next map:"))
	_vote_box = VBoxContainer.new()
	_vote_box.add_theme_constant_override("separation", 8)
	inner.add_child(_vote_box)
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
		_connect_scroll_button(vb, _lobby_scroll)
	var vote_hint := Label.new()
	vote_hint.text = "Most votes wins. If nobody votes, or on a tie, the host's map is played."
	vote_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vote_hint.add_theme_font_size_override("font_size", 18)
	vote_hint.add_theme_color_override("font_color", UI_FONT_MUTED)
	inner.add_child(vote_hint)
	inner.add_child(_section_label("Game mode:"))
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	inner.add_child(mode_row)
	for i in GameData.MODE_NAMES.size():
		var b := Button.new()
		b.text = GameData.MODE_NAMES[i]
		b.custom_minimum_size = Vector2(0, 56)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(b, 20, 56)
		b.pressed.connect(_on_mode_pressed.bind(i))
		mode_row.add_child(b)
		_mode_buttons.append(b)
		_connect_scroll_button(b, _lobby_scroll)
	var ff_row := HBoxContainer.new()
	ff_row.add_theme_constant_override("separation", 8)
	inner.add_child(ff_row)
	_ff_check = CheckButton.new()
	_ff_check.text = "Friendly fire (Team Deathmatch only)"
	_ff_check.add_theme_font_size_override("font_size", 20)
	_ff_check.button_pressed = GameData.friendly_fire
	_ff_check.toggled.connect(_on_friendly_fire_toggled)
	ff_row.add_child(_ff_check)
	_ff_check.gui_input.connect(_on_scrolled_button_gui_input.bind(_lobby_scroll, _ff_check))
	var limit_row := HBoxContainer.new()
	limit_row.add_theme_constant_override("separation", 8)
	inner.add_child(limit_row)
	var limit_lbl := Label.new()
	limit_lbl.text = "Kill limit:"
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
		_connect_scroll_button(b, _lobby_scroll)
	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 8)
	inner.add_child(time_row)
	var time_lbl := Label.new()
	time_lbl.text = "Match time:"
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
		_connect_scroll_button(b, _lobby_scroll)
	# Fixed action row — always visible, never scrolled away.
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
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


func _on_map_pressed(i: int) -> void:
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


func _refresh_lobby_buttons() -> void:
	for i in _map_buttons.size():
		var mb: Button = _map_buttons[i]
		mb.text = ("✓ " if i == GameData.map_id else "") + GameData.MAP_NAMES[i]
		mb.disabled = not _is_host
		_style_selected(mb, i == GameData.map_id, 20)
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
		# The joiner's lifeline: the host IP is always visible here.
		if _is_host:
			var ip := LanDiscovery.lan_ip()
			if ip != "":
				_host_ip_label.text = "HOST IP: " + ip + "  —  friends type this IP to join"
			else:
				_host_ip_label.text = "No Wi-Fi IP found — connect to Wi-Fi or a hotspot, then re-host"
			_host_ip_label.visible = true
		elif GameData.host_ip != "":
			_host_ip_label.text = "Connected to host: " + GameData.host_ip
			_host_ip_label.visible = true
		else:
			_host_ip_label.visible = false
	if _room_info_label != null:
		var priv := " • Private" if GameData.room_private else ""
		_room_info_label.text = "Room: %s%s • %d/%d players • %s • %s • Kill limit %d • %d min • Friendly fire: %s" % [
			GameData.room_name, priv, _lobby_players.size(), GameData.max_players,
			GameData.MAP_NAMES[GameData.map_id], GameData.MODE_NAMES[GameData.game_mode],
			GameData.kill_limit, GameData.match_minutes, "on" if GameData.friendly_fire else "off",
		]
	_refresh_vote_buttons()


func _refresh_lobby_list() -> void:
	for c in _lobby_list.get_children():
		c.queue_free()
	var ids: Array = _lobby_players.keys()
	ids.sort()
	for id in ids:
		var info: Dictionary = _lobby_players[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var portrait := TextureRect.new()
		portrait.texture = _portrait_texture(int(info.get("portrait", 0)))
		portrait.custom_minimum_size = Vector2(36, 48)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(portrait)
		var lbl := Label.new()
		var tag := ""
		if int(id) == 1:
			tag = " (HOST)"
		elif int(id) == multiplayer.get_unique_id():
			tag = " (YOU)"
		lbl.text = "%s%s" % [String(info.get("name", "Player")), tag]
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.add_theme_color_override("font_color", GameData.PLAYER_COLORS[int(info.get("color", 0)) % GameData.PLAYER_COLORS.size()])
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var ready_lbl := Label.new()
		var is_ready: bool = bool(info.get("ready", false))
		ready_lbl.text = "READY ✓" if is_ready else "not ready"
		ready_lbl.add_theme_font_size_override("font_size", 20)
		ready_lbl.add_theme_color_override("font_color", UI_SUCCESS if is_ready else UI_FONT_MUTED)
		row.add_child(ready_lbl)
		# The host can remove a player from the room.
		if _is_host and int(id) != 1 and int(id) != multiplayer.get_unique_id():
			var kick_btn := Button.new()
			kick_btn.text = "KICK"
			kick_btn.custom_minimum_size = Vector2(90, 56)
			_style_button(kick_btn, 20, 56)
			kick_btn.pressed.connect(_on_kick_pressed.bind(int(id)))
			row.add_child(kick_btn)
			_connect_scroll_button(kick_btn, _lobby_scroll)
		_lobby_list.add_child(row)


func _on_max_pressed(n: int) -> void:
	_click()
	GameData.max_players = clampi(n, 2, 12)
	_refresh_max_buttons()


func _refresh_max_buttons() -> void:
	for i in _max_buttons.size():
		var n: int = [2, 4, 6, 8, 10, 12][i]
		var b: Button = _max_buttons[i]
		b.text = ("✓ " if n == GameData.max_players else "") + str(n)
		_style_selected(b, n == GameData.max_players, 20)


func _on_private_toggled(on: bool) -> void:
	GameData.room_private = on


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
		"port": PORT,
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


func _create_room() -> bool:
	if multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer is not OfflineMultiplayerPeer:
		_set_status("You are already in a game — leave it first.")
		return false
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, GameData.max_players - 1)
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


func _on_connection_failed() -> void:
	_joining = false
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
	GameData.game_mode = int(settings.get("mode", GameData.game_mode))
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
	GameData.map_id = map_id
	GameData.game_mode = mode
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
	if multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer is not OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_peer = null
	_is_host = false
	_starting_match = false
	_joining = false
	_join_rejected = false
	_room_status = "lobby"
	_my_vote = -1
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
		var b := Button.new()
		b.text = "%s%s — %s • %d/%d • %s • %s • %s • %s" % [
			String(room["room_name"]), lock, String(room["host_name"]),
			int(room["players"]), int(room["max_players"]),
			map_name, mode_name, String(room["status"]), ip,
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
	var b: Button = _map_buttons[12]
	var btop: float = b.get_global_rect().position.y - _lobby_scroll.get_global_rect().position.y + _lobby_scroll.scroll_vertical
	_lobby_scroll.scroll_vertical = btop - 100.0


func _sct_c_last_visible() -> Array:
	var b: Button = _map_buttons[12]
	var brect := Rect2(_sc_vp_pos(b, Vector2.ZERO), b.size)
	var srect := Rect2(_sc_vp_pos(_lobby_scroll, Vector2.ZERO), _lobby_scroll.size)
	var inter := brect.intersection(srect)
	var ok: bool = inter.size.y > 30.0
	return [ok, "last map button visible height=%d px (want >30) at max scroll" % int(inter.size.y)]


func _sct_s_tap_last() -> void:
	await get_tree().process_frame
	_sc_tap(804, _sc_vp_pos(_map_buttons[12], _map_buttons[12].size * 0.5))


func _sct_c_tap_last() -> Array:
	var ok: bool = GameData.map_id == 12
	return [ok, "map_id=%d (want 12 — every map reachable and tappable)" % GameData.map_id]


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
		{"name": "SUBNET-BROADCAST", "wait": 0.3, "setup": _mnt_s_noop, "check": _mnt_c_subnet},
		{"name": "BAD-IP-ERROR", "wait": 1.0, "setup": _mnt_s_bad_ip, "check": _mnt_c_bad_ip},
		{"name": "CREATE-ROOM", "wait": 0.5, "setup": _mnt_s_create_room, "check": _mnt_c_create_room},
		{"name": "READY-TOGGLE", "wait": 0.3, "setup": _mnt_s_ready, "check": _mnt_c_ready},
		{"name": "LEAVE-CLEANUP", "wait": 0.3, "setup": _mnt_s_leave, "check": _mnt_c_leave},
	]


func _mnt_s_noop() -> void:
	pass


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

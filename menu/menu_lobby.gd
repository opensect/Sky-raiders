class_name MenuLobby
extends RefCounted


# QA-140 (v3.15): extracted from main.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `m` (dependency injection).


var m # the owner (main.gd)

# QA-095 (v3.7): the lobby map cards show the map's REAL art —
# the in-game far-parallax background for the 4 maps that have
# one (Ironfall, Outpost, Neon City, Volcanic Cavern — same files
# game.gd uses as the far parallax layer; Outpost shares
# Ironfall's bg, both built from the same Outpost TMX), the
# existing thumb for the 1 map that keeps the procedural
# gradient (Pirate Island). The 960×540 backgrounds are cropped
# to the card thumbnail (COVERED), never stretched.
const MAP_CARD_ART := {
	0: preload("res://assets/skybrawl/maps/bg_ironfall.png"),
	1: preload("res://assets/skybrawl/maps/bg_ironfall.png"),
	2: preload("res://assets/skybrawl/maps/bg_neon.png"),
	3: preload("res://assets/skybrawl/maps/bg_volcanic.png"),
	4: preload("res://assets/thumbs/thumb_pirate.png"),
	5: preload("res://assets/thumbs/thumb_skyfall.png"), # QA-112 (v3.9): Skyfall map card art
}
const TEAM_BANNER_RED: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/ui/team_banner_red.png")
const TEAM_BANNER_BLUE: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/ui/team_banner_blue.png")
const FONT_BODY_BOLD: Font = preload("res://assets/fonts/rajdhani/Rajdhani-Bold.ttf")



func _init(owner) -> void:
	m = owner


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
	m._lobby_panel = m.menu_ui._panel()
	var box = m.menu_ui._vbox(m._lobby_panel, 12)
	# ---- Header: title left, players pill right ----
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 12)
	box.add_child(head_row)
	var lobby_title := Label.new()
	lobby_title.text = "GAME LOBBY"
	lobby_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lobby_title.add_theme_font_override("font", m.FONT_TITLE)
	lobby_title.add_theme_font_size_override("font_size", 40)
	lobby_title.add_theme_color_override("font_color", m.UI_FONT)
	lobby_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(lobby_title)
	m._lobby_players_badge = GoBadge.make(0, "1/4 PLAYERS", false, m.UI_ACCENT)
	m._lobby_players_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m._lobby_players_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head_row.add_child(m._lobby_players_badge)
	m._lobby_status = Label.new()
	m._lobby_status.text = ""
	m._lobby_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	m._lobby_status.add_theme_font_size_override("font_size", 20)
	m._lobby_status.add_theme_color_override("font_color", m.UI_FONT_MUTED)
	box.add_child(m._lobby_status)
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
			m._strip_limit_cap = cap
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cap.add_theme_font_override("font", m.FONT_BODY_SEMIBOLD)
		cap.add_theme_font_size_override("font_size", 15)
		cap.add_theme_color_override("font_color", m.UI_FONT_MUTED)
		tile_vb.add_child(cap)
		var v := Label.new()
		v.text = "—"
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_font_override("font", m.FONT_BODY_SEMIBOLD)
		v.add_theme_font_size_override("font_size", 18)
		v.add_theme_color_override("font_color", m.UI_FONT)
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile_vb.add_child(v)
		m._room_info_values[field] = v
	# v2.4: the host's LAN IP, big and clear — this is the number a
	# friend types to join when discovery does not find the room.
	# v3.5: it sits in a prominent cyan-bordered chip, not a bare
	# text line. v3.6: the chip moves up under the stat strip so
	# it is visible without scrolling either column.
	m._host_ip_chip = PanelContainer.new()
	m._host_ip_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chip_sb := StyleBoxFlat.new()
	chip_sb.bg_color = Color(0.0, 0.25, 0.32, 0.92)
	chip_sb.set_corner_radius_all(10)
	chip_sb.border_color = m.UI_ACCENT
	chip_sb.set_border_width_all(2)
	chip_sb.content_margin_left = 14
	chip_sb.content_margin_right = 14
	chip_sb.content_margin_top = 8
	chip_sb.content_margin_bottom = 8
	m._host_ip_chip.add_theme_stylebox_override("panel", chip_sb)
	box.add_child(m._host_ip_chip)
	m._host_ip_label = Label.new()
	m._host_ip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m._host_ip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m._host_ip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m._host_ip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m._host_ip_label.add_theme_font_override("font", FONT_BODY_BOLD)
	m._host_ip_label.add_theme_font_size_override("font_size", 22)
	m._host_ip_label.add_theme_color_override("font_color", m.UI_ACCENT)
	m._host_ip_chip.add_child(m._host_ip_label)
	# QA-112 (v3.9): Skyfall CTF team banners — red and blue side
	# by side, full width under the host IP chip and above the
	# player list / map cards (the lobby header area). The pack
	# banners are 640x160, shown at ~300 px wide each so the pair
	# fits without squeezing the columns below. Hidden unless the
	# map is Skyfall AND the mode is Capture the Flag (see
	# _refresh_lobby_buttons).
	m._skyfall_banner_row = HBoxContainer.new()
	m._skyfall_banner_row.add_theme_constant_override("separation", 16)
	m._skyfall_banner_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(m._skyfall_banner_row)
	for banner_tex in [TEAM_BANNER_RED, TEAM_BANNER_BLUE]:
		var banner := TextureRect.new()
		banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		banner.texture = banner_tex
		banner.custom_minimum_size = Vector2(300, 75)
		banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		m._skyfall_banner_row.add_child(banner)
	m._skyfall_banner_row.visible = false
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
	m._lobby_left_scroll = left_scroll
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_col.add_child(left_scroll)
	var left_inner := VBoxContainer.new()
	left_inner.add_theme_constant_override("separation", 12)
	left_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(left_inner)
	m._players_section_label = m.menu_ui._section_label("Players in the room:")
	left_inner.add_child(m._players_section_label)
	m._lobby_list = VBoxContainer.new()
	m._lobby_list.add_theme_constant_override("separation", 10)
	left_inner.add_child(m._lobby_list)
	# Match setup sits directly under the players now (it used
	# to sit below the room panel + IP chip + hints, under the
	# fold). The host IP chip already says how friends join,
	# so the old join-hint line is gone.
	left_inner.add_child(m.menu_ui._section_label("Match setup:"))
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
		m.menu_ui._style_button(b, 20, 56)
		b.pressed.connect(_on_mode_pressed.bind(i))
		(mode_row if i < 3 else mode_row2).add_child(b)
		m._mode_buttons.append(b)
		m.menu_ui._connect_scroll_button(b, m._lobby_left_scroll)
	# v3.6 QA-069: friendly fire is a Label + GoSwitch (pill),
	# like the Private switch on the create page — the old
	# CheckButton's tiny box read as a checkbox, not a setting.
	var ff_row := HBoxContainer.new()
	ff_row.add_theme_constant_override("separation", 10)
	left_inner.add_child(ff_row)
	var ff_lbl := Label.new()
	ff_lbl.text = "Friendly fire (Team Deathmatch only)"
	ff_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ff_lbl.add_theme_font_override("font", m.FONT_BODY_SEMIBOLD)
	ff_lbl.add_theme_font_size_override("font_size", 20)
	ff_lbl.add_theme_color_override("font_color", m.UI_FONT)
	ff_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ff_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ff_row.add_child(ff_lbl)
	m._ff_check = GoSwitch.new()
	m._ff_check.custom_minimum_size = Vector2(72, 56)
	m._ff_check.button_pressed = GameData.friendly_fire
	m._ff_check.toggled.connect(m._on_friendly_fire_toggled)
	ff_row.add_child(m._ff_check)
	m._ff_check.gui_input.connect(m.menu_ui._on_scrolled_button_gui_input.bind(m._lobby_left_scroll, m._ff_check))
	var limit_row := HBoxContainer.new()
	limit_row.add_theme_constant_override("separation", 8)
	left_inner.add_child(limit_row)
	var limit_lbl := Label.new()
	m._limit_label = limit_lbl
	limit_lbl.text = "Kill limit:"
	limit_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	limit_lbl.add_theme_font_size_override("font_size", 20)
	limit_row.add_child(limit_lbl)
	for kl in [5, 10, 15]:
		var b := Button.new()
		b.text = str(kl)
		b.custom_minimum_size = Vector2(64, 56)
		m.menu_ui._style_button(b, 20, 56)
		b.pressed.connect(_on_limit_pressed.bind(kl))
		limit_row.add_child(b)
		m._limit_buttons.append(b)
		m.menu_ui._connect_scroll_button(b, m._lobby_left_scroll)
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
		m.menu_ui._style_button(b, 20, 56)
		b.pressed.connect(_on_time_pressed.bind(mins))
		time_row.add_child(b)
		m._time_buttons.append(b)
		m.menu_ui._connect_scroll_button(b, m._lobby_left_scroll)
	# QA-078: team pick — only for team modes (TDM, Capture the
	# Flag). RED / BLUE / AUTO; the host honours the pick when the
	# match starts unless that team is already full (6), then it
	# falls back to auto. The row hides for free-for-all modes.
	left_inner.add_child(m.menu_ui._section_label("Your team (team modes):"))
	m._team_section_label = left_inner.get_child(left_inner.get_child_count() - 1) as Label
	var team_row := HBoxContainer.new()
	team_row.add_theme_constant_override("separation", 8)
	left_inner.add_child(team_row)
	for t in [-1, 0, 1]:
		var tb := Button.new()
		tb.text = "AUTO" if t == -1 else ("RED" if t == 0 else "BLUE")
		tb.custom_minimum_size = Vector2(0, 56)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		m.menu_ui._style_button(tb, 20, 56)
		tb.pressed.connect(m._on_team_pressed.bind(t))
		team_row.add_child(tb)
		m._team_buttons.append(tb)
		m.menu_ui._connect_scroll_button(tb, m._lobby_left_scroll)
	# QA-112 (v3.9): role picker — Skyfall only. Four plain buttons
	# (Attacker / Defender / Sniper / Support) with the role icon
	# in the LOCAL player's team colour. Roles are LABELS ONLY —
	# no gameplay effect; they show as icons next to each name in
	# the player list. Anyone in the room can pick their own role
	# (like the team pick); the choice syncs like team/color/helmet
	# (see _on_role_pressed / set_role).
	left_inner.add_child(m.menu_ui._section_label("Your role (Skyfall):"))
	m._role_section_label = left_inner.get_child(left_inner.get_child_count() - 1) as Label
	m._role_row = HBoxContainer.new()
	m._role_row.add_theme_constant_override("separation", 8)
	left_inner.add_child(m._role_row)
	for i in GameData.ROLE_NAMES.size():
		var rb := Button.new()
		rb.text = GameData.ROLE_NAMES[i]
		rb.custom_minimum_size = Vector2(0, 56)
		rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rb.expand_icon = true
		m.menu_ui._style_button(rb, 18, 56)
		rb.pressed.connect(m._on_role_pressed.bind(i))
		m._role_row.add_child(rb)
		m._role_buttons.append(rb)
		m.menu_ui._connect_scroll_button(rb, m._lobby_left_scroll)
	# QA-078: change appearance without leaving the room — colour
	# and helmet, same choices as Customization. The change syncs
	# to every phone in the room at once (host broadcast, see
	# update_appearance / _broadcast_lobby).
	left_inner.add_child(m.menu_ui._section_label("Appearance in this room:"))
	var lobby_color_row := HBoxContainer.new()
	lobby_color_row.add_theme_constant_override("separation", 8)
	left_inner.add_child(lobby_color_row)
	for i in GameData.COLOR_NAMES.size():
		var cb := Button.new()
		cb.text = GameData.COLOR_NAMES[i]
		cb.custom_minimum_size = Vector2(0, 56)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		m.menu_ui._style_button(cb, 18, 56)
		cb.pressed.connect(m._on_lobby_color_pressed.bind(i))
		lobby_color_row.add_child(cb)
		m._lobby_color_buttons.append(cb)
		m.menu_ui._connect_scroll_button(cb, m._lobby_left_scroll)
	var lobby_helmet_row := HBoxContainer.new()
	lobby_helmet_row.add_theme_constant_override("separation", 8)
	left_inner.add_child(lobby_helmet_row)
	for i in m.HELMET_NAMES.size():
		var hb := Button.new()
		hb.text = m.HELMET_NAMES[i]
		hb.custom_minimum_size = Vector2(0, 56)
		hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		m.menu_ui._style_button(hb, 18, 56)
		hb.pressed.connect(m._on_lobby_helmet_pressed.bind(i))
		lobby_helmet_row.add_child(hb)
		m._lobby_helmet_buttons.append(hb)
		m.menu_ui._connect_scroll_button(hb, m._lobby_left_scroll)
	# Phase 4 — map vote: every player picks one of 3 maps on the
	# ballot (the host's pick + the next two). The host tallies the
	# votes when the match starts; ties and no-votes keep the host's
	# pick. Votes travel in the lobby player dicts (see set_vote).
	left_inner.add_child(m.menu_ui._section_label("Map vote — pick the next map:"))
	m._vote_box = VBoxContainer.new()
	m._vote_box.add_theme_constant_override("separation", 8)
	left_inner.add_child(m._vote_box)
	for k in 3:
		var vb := Button.new()
		vb.text = ""
		vb.custom_minimum_size = Vector2(0, 56)
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		m.menu_ui._style_button(vb, 20, 56)
		vb.pressed.connect(_on_vote_pressed.bind(k))
		m._vote_box.add_child(vb)
		m._vote_buttons.append(vb)
		m.menu_ui._connect_scroll_button(vb, m._lobby_left_scroll)
	var vote_hint := Label.new()
	vote_hint.text = "Most votes wins. If nobody votes, or on a tie, the host's map is played."
	vote_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vote_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vote_hint.add_theme_font_size_override("font_size", 18)
	vote_hint.add_theme_color_override("font_color", m.UI_FONT_MUTED)
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
	controls_hint.add_theme_font_override("font", m.FONT_BODY)
	controls_hint.add_theme_font_size_override("font_size", 18)
	controls_hint.add_theme_color_override("font_color", m.UI_FONT)
	m._controls_hint_label = controls_hint
	left_inner.add_child(controls_hint)
	# ---- RIGHT column: map cards (scrolls) ----
	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_stretch_ratio = 1.1
	cols.add_child(right_col)
	var scroll := ScrollContainer.new()
	m._lobby_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_col.add_child(scroll)
	var map_inner := VBoxContainer.new()
	map_inner.add_theme_constant_override("separation", 16)
	map_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(map_inner)
	m._map_section_label = m.menu_ui._section_label("Maps — tap a card to select:")
	map_inner.add_child(m._map_section_label)
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
	scroll_hint.add_theme_font_override("font", m.FONT_BODY)
	scroll_hint.add_theme_font_size_override("font_size", 18)
	scroll_hint.add_theme_color_override("font_color", m.UI_ACCENT)
	m._scroll_hint_label = scroll_hint
	map_inner.add_child(scroll_hint)
	# Fixed action row — always visible, never scrolled away.
	var top_sep := HSeparator.new()
	box.add_child(top_sep)
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 14)
	box.add_child(btn_row)
	m._ready_btn = Button.new()
	m._ready_btn.text = "I'M READY"
	m._ready_btn.custom_minimum_size = Vector2(180, 64)
	m.menu_ui._style_button(m._ready_btn, 22, 64)
	m._ready_btn.pressed.connect(m._on_ready_pressed)
	btn_row.add_child(m._ready_btn)
	m._lobby_start_btn = Button.new()
	m._lobby_start_btn.text = "START MATCH"
	m._lobby_start_btn.custom_minimum_size = Vector2(0, 64)
	m._lobby_start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.menu_ui._style_button(m._lobby_start_btn, 24, 64, true)
	m._lobby_start_btn.pressed.connect(m._on_start_pressed)
	btn_row.add_child(m._lobby_start_btn)
	var leave_btn := Button.new()
	leave_btn.text = "Leave"
	leave_btn.custom_minimum_size = Vector2(140, 64)
	m.menu_ui._style_danger_button(leave_btn, 22, 64)
	leave_btn.pressed.connect(m._on_lobby_leave_pressed)
	btn_row.add_child(leave_btn)
	m._refresh_lobby_buttons()


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
		sb.border_color = m.UI_ACCENT
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
	m._map_cards.append(panel)
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
	var badge = GoBadge.make(0, "✓ SELECTED", false, m.UI_SUCCESS)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.visible = false
	name_row.add_child(badge)
	m._map_card_badges.append(badge)
	var name_lbl := Label.new()
	name_lbl.text = GameData.MAP_NAMES[i]
	name_lbl.add_theme_font_override("font", m.FONT_BODY_SEMIBOLD)
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.add_theme_color_override("font_color", m.UI_FONT)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_contents = true
	name_row.add_child(name_lbl)
	var info_lbl := Label.new()
	info_lbl.text = GameData.MAP_CARD_INFO[i]
	info_lbl.add_theme_font_override("font", m.FONT_BODY)
	info_lbl.add_theme_font_size_override("font_size", 18)
	info_lbl.add_theme_color_override("font_color", m.UI_FONT_MUTED)
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
	m._map_buttons.append(hit)
	m.menu_ui._connect_scroll_button(hit, m._lobby_scroll)
	return root


# v3.6 QA-069: one lobby chip — a gohud GoBadge with words
# (HOST / YOU / READY ✓ / NOT READY). Replaces the hand-rolled
# _badge_chip PanelContainer (v3.5). Display-only: mouse-transparent
# so a drag starting on a chip scrolls the left column.
func _lobby_chip(text: String, ink: Color) -> GoBadge:
	var b = GoBadge.make(0, text, false, ink)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


func _on_map_pressed(i: int) -> void:
	# v3.5 QA-059: a scroll-drag ending on a card must not select
	# it — the drag flag is set by _on_scrolled_button_gui_input
	# (see QA-048). A real tap has no drag, so it still selects.
	if i < m._map_buttons.size() and bool((m._map_buttons[i] as Button).get_meta("sc_dragged", false)):
		(m._map_buttons[i] as Button).set_meta("sc_dragged", false)
		return
	if not m._is_host:
		return
	m.menu_ui._click()
	# QA-112 (v3.9): leaving Skyfall drops Capture the Flag. The
	# mode reset itself happens in _refresh_lobby_buttons (called
	# by _broadcast_lobby below); this only adds the short hint.
	# Set AFTER the broadcast: the refresh rewrites the status
	# line, so setting it before would be overwritten at once.
	var was_ctf: bool = GameData.game_mode == 4
	GameData.map_id = i
	GameData.save_settings()
	m._broadcast_lobby()
	if was_ctf and not _ctf_available() and m._lobby_status != null:
		m._lobby_status.text = "CTF is only on Skyfall"


# Phase 4 — map vote: the ballot is the host's pick + the next two
# maps. Everyone may vote; the host tallies at match start.
func _vote_candidates_now() -> Array:
	return [GameData.map_id, (GameData.map_id + 1) % GameData.MAP_NAMES.size(), (GameData.map_id + 2) % GameData.MAP_NAMES.size()]


func _on_vote_pressed(slot: int) -> void:
	m.menu_ui._click()
	var cands := _vote_candidates_now()
	if slot < 0 or slot >= cands.size():
		return
	var map_choice: int = cands[slot]
	m._my_vote = map_choice
	var my_id = m.multiplayer.get_unique_id()
	if m._is_host:
		if m._lobby_players.has(my_id):
			m._lobby_players[my_id]["vote"] = map_choice
		m._broadcast_lobby()
	else:
		m.rpc_id(1, "set_vote", map_choice)
	_refresh_vote_buttons()


func set_vote(map_choice: int) -> void:
	if not m.multiplayer.is_server():
		return
	var sender = m.multiplayer.get_remote_sender_id()
	if m._lobby_players.has(sender):
		m._lobby_players[sender]["vote"] = clampi(map_choice, 0, GameData.MAP_NAMES.size() - 1)
		m._broadcast_lobby()


func _refresh_vote_buttons() -> void:
	if m._vote_buttons.is_empty():
		return
	m._vote_candidates = _vote_candidates_now()
	var counts := {}
	for c in m._vote_candidates:
		counts[int(c)] = 0
	for id in m._lobby_players.keys():
		var v: int = int((m._lobby_players[id] as Dictionary).get("vote", -1))
		if counts.has(v):
			counts[v] = int(counts[v]) + 1
	for k in m._vote_buttons.size():
		var mid: int = m._vote_candidates[k]
		var b: Button = m._vote_buttons[k]
		var mine: bool = m._my_vote == mid
		var n: int = int(counts[mid])
		b.text = "%s%s  —  %d vote%s" % ["✓ " if mine else "", GameData.MAP_NAMES[mid], n, "" if n == 1 else "s"]
		m.menu_ui._style_selected(b, mine, 20)


func _on_mode_pressed(i: int) -> void:
	if not m._is_host:
		return
	if i == 4 and not _ctf_available():
		return
	m.menu_ui._click()
	GameData.game_mode = i
	GameData.save_settings()
	m._broadcast_lobby()


func _on_limit_pressed(kl: int) -> void:
	if not m._is_host:
		return
	m.menu_ui._click()
	GameData.kill_limit = kl
	GameData.save_settings()
	m._broadcast_lobby()


func _on_time_pressed(mins: int) -> void:
	if not m._is_host:
		return
	m.menu_ui._click()
	GameData.match_minutes = mins
	GameData.save_settings()
	m._broadcast_lobby()


# QA-112 (v3.9): Capture the Flag (mode 4) is only on Skyfall.
# Every mode refresh and mode press goes through this check, so
# CTF can never be picked — or stay picked — on the other 5 maps.
func _ctf_available() -> bool:
	return GameData.map_id == GameData.SKYFALL_MAP_ID


func _refresh_create_mode_buttons() -> void:
	# QA-112: a saved mode 4 on a non-Skyfall map falls back to
	# Free-for-All (the create page has no map pick — the map is
	# still Ironfall by default here, so this only fires on a
	# stale saved setting).
	if not _ctf_available() and GameData.game_mode == 4:
		GameData.game_mode = 0
	for i in m._create_mode_buttons.size():
		var b: Button = m._create_mode_buttons[i]
		b.visible = _ctf_available() or i != 4
		b.text = ("✓ " if i == GameData.game_mode else "") + GameData.MODE_NAMES[i]
		m.menu_ui._style_selected(b, i == GameData.game_mode, 20)


func _on_create_mode_pressed(i: int) -> void:
	m.menu_ui._click()
	if i == 4 and not _ctf_available():
		return
	GameData.game_mode = i
	_refresh_create_mode_buttons()


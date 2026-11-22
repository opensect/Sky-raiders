class_name MenuLobbySetup
extends RefCounted


# QA-140 (v3.15): extracted from main.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `m` (dependency injection).


var m # the owner (main.gd)

# QA-112 (v3.9 Skyfall lobby: CTF gating + roles + team banners).
# Capture the Flag (mode 4) is back, but ONLY on the Skyfall map
# (map 5) — see _ctf_available() below. The role picker shows only
# on Skyfall, and the team banners show only for Skyfall CTF.
# Roles are LABELS ONLY — no gameplay effect, just an icon in the
# lobby player list. Role icons come from the Skyfall asset pack,
# one set per team colour (red = team 0, blue = team 1).
const ROLE_ICONS_RED := {
	0: preload("res://assets/skyfall/SKYFALL_assets/ui/role_icon_red_attacker.png"),
	1: preload("res://assets/skyfall/SKYFALL_assets/ui/role_icon_red_defender.png"),
	2: preload("res://assets/skyfall/SKYFALL_assets/ui/role_icon_red_sniper.png"),
	3: preload("res://assets/skyfall/SKYFALL_assets/ui/role_icon_red_support.png"),
}
const ROLE_ICONS_BLUE := {
	0: preload("res://assets/skyfall/SKYFALL_assets/ui/role_icon_blue_attacker.png"),
	1: preload("res://assets/skyfall/SKYFALL_assets/ui/role_icon_blue_defender.png"),
	2: preload("res://assets/skyfall/SKYFALL_assets/ui/role_icon_blue_sniper.png"),
	3: preload("res://assets/skyfall/SKYFALL_assets/ui/role_icon_blue_support.png"),
}



func _init(owner) -> void:
	m = owner


# QA-078: team pick (team modes only). Stored per player in the
# lobby dict, so every phone sees it; the host reads it at spawn
# time (game.gd _do_spawn honours it unless the team is full).
func _on_team_pressed(t: int) -> void:
	m.menu_ui._click()
	m._my_team = clampi(t, -1, 1)
	GameData.team_pref = m._my_team
	var my_id = m.multiplayer.get_unique_id()
	if m._is_host:
		if m._lobby_players.has(my_id):
			m._lobby_players[my_id]["team"] = m._my_team
		m._broadcast_lobby()
	else:
		m.rpc_id(1, "set_team", m._my_team)
	_refresh_lobby_buttons()


func set_team(t: int) -> void:
	if not m.multiplayer.is_server():
		return
	var sender = m.multiplayer.get_remote_sender_id()
	if m._lobby_players.has(sender):
		m._lobby_players[sender]["team"] = clampi(t, -1, 1)
		m._broadcast_lobby()


# QA-112 (v3.9): Skyfall role icon for a team + role. Team 1 is
# blue, team 0 and AUTO (-1 / unset) fall back to the red icons.
# Roles are LABELS ONLY — no gameplay effect.
func _role_icon(team: int, role: int) -> Texture2D:
	var r: int = clampi(role, 0, GameData.ROLE_NAMES.size() - 1)
	if team == 1:
		return ROLE_ICONS_BLUE[r]
	return ROLE_ICONS_RED[r]


# QA-112: role pick (Skyfall only). Same sync pattern as the team
# pick: the host writes my lobby entry and broadcasts; a joiner
# sends set_role to the host, which clamps it to 0-3 and broadcasts.
func _on_role_pressed(i: int) -> void:
	m.menu_ui._click()
	GameData.role = clampi(i, 0, GameData.ROLE_NAMES.size() - 1)
	var my_id = m.multiplayer.get_unique_id()
	if m._is_host:
		if m._lobby_players.has(my_id):
			m._lobby_players[my_id]["role"] = GameData.role
		m._broadcast_lobby()
	else:
		m.rpc_id(1, "set_role", GameData.role)
	_refresh_lobby_buttons()
	_refresh_lobby_list()


func set_role(r: int) -> void:
	if not m.multiplayer.is_server():
		return
	var sender = m.multiplayer.get_remote_sender_id()
	if m._lobby_players.has(sender):
		m._lobby_players[sender]["role"] = clampi(r, 0, GameData.ROLE_NAMES.size() - 1)
		m._broadcast_lobby()


# QA-078: in-lobby appearance change. Updates my saved settings
# AND my lobby entry, then syncs to the whole room at once.
func _on_lobby_color_pressed(i: int) -> void:
	m.menu_ui._click()
	GameData.color_index = i
	GameData.save_settings()
	m.menu_screens._refresh_customize_buttons()
	_sync_my_appearance()


func _on_lobby_helmet_pressed(i: int) -> void:
	m.menu_ui._click()
	GameData.helmet = i
	GameData.save_settings()
	m.menu_screens._refresh_customize_buttons()
	_sync_my_appearance()


func _sync_my_appearance() -> void:
	var my_id = m.multiplayer.get_unique_id()
	if m._is_host:
		if m._lobby_players.has(my_id):
			m._lobby_players[my_id]["color"] = GameData.color_index
			m._lobby_players[my_id]["helmet"] = GameData.helmet
		m._broadcast_lobby()
	else:
		m.rpc_id(1, "update_appearance", GameData.color_index, GameData.helmet)
	_refresh_lobby_buttons()
	_refresh_lobby_list()


func update_appearance(color_idx: int, helmet_style: int) -> void:
	if not m.multiplayer.is_server():
		return
	var sender = m.multiplayer.get_remote_sender_id()
	if m._lobby_players.has(sender):
		m._lobby_players[sender]["color"] = clampi(color_idx, 0, GameData.COLOR_NAMES.size() - 1)
		m._lobby_players[sender]["helmet"] = clampi(helmet_style, 0, m.HELMET_NAMES.size() - 1)
		m._broadcast_lobby()


# QA-112 (v3.9): minimum to start a match — a match starts with
# whoever is in the room, NEVER a full team (5v5 = 10). At least 2
# players total; in team modes (TDM mode 1, CTF mode 4) at least 1
# player on EACH team (RED 0 / BLUE 1). AUTO (-1) counts as able to
# fill either side: the minimum is met when (red + auto) >= 1 AND
# (blue + auto) >= 1 AND total >= 2. No maximum / full-team check.
func _start_minimum_reason() -> String:
	var total = m._lobby_players.size()
	if total < 2:
		return "NEED 2 PLAYERS"
	if GameData.game_mode == 1 or GameData.game_mode == 4:
		var red := 0
		var blue := 0
		var auto := 0
		for id in m._lobby_players.keys():
			match int((m._lobby_players[id] as Dictionary).get("team", -1)):
				0:
					red += 1
				1:
					blue += 1
				_:
					auto += 1
		if red + auto < 1 or blue + auto < 1:
			return "NEED RED + BLUE"
	return ""


func _start_minimum_met() -> bool:
	return _start_minimum_reason() == ""


func _refresh_lobby_buttons() -> void:
	# QA-112 (v3.9): CTF (mode 4) only lives on Skyfall. If the map
	# is anything else and the mode is still 4 (stale save, old
	# host, vote tally), fall back to Free-for-All before any
	# button is drawn, so CTF never shows as the picked mode.
	if not m.menu_lobby._ctf_available() and GameData.game_mode == 4:
		GameData.game_mode = 0
	# v3.5 QA-059: map buttons are invisible hit areas over the map
	# cards — no text or button style on them. The selected state
	# lives on the CARD: cyan border + teal fill + ✓ badge.
	for i in m._map_buttons.size():
		var mb: Button = m._map_buttons[i]
		var selected: bool = i == GameData.map_id
		mb.disabled = not m._is_host
		if i < m._map_cards.size():
			(m._map_cards[i] as PanelContainer).add_theme_stylebox_override("panel", m.menu_lobby._map_card_stylebox(selected))
			(m._map_cards[i] as Control).modulate = Color(1, 1, 1, 1) if m._is_host else Color(1, 1, 1, 0.6)
		if i < m._map_card_badges.size():
			(m._map_card_badges[i] as Control).visible = selected # v3.6 QA-069: GoBadge now, was a Label
	for i in m._mode_buttons.size():
		var ob: Button = m._mode_buttons[i]
		ob.visible = m.menu_lobby._ctf_available() or i != 4 # QA-112: hide CTF unless the map is Skyfall
		ob.text = ("✓ " if i == GameData.game_mode else "") + GameData.MODE_NAMES[i]
		ob.disabled = not m._is_host
		m.menu_ui._style_selected(ob, i == GameData.game_mode, 20)
	for i in m._limit_buttons.size():
		var kl: int = [5, 10, 15][i]
		var lb: Button = m._limit_buttons[i]
		lb.text = ("✓ " if kl == GameData.kill_limit else "") + str(kl)
		lb.disabled = not m._is_host
		m.menu_ui._style_selected(lb, kl == GameData.kill_limit, 20)
	for i in m._time_buttons.size():
		var mins: int = [3, 5, 10][i]
		var tb: Button = m._time_buttons[i]
		tb.text = ("✓ " if mins == GameData.match_minutes else "") + "%d min" % mins
		tb.disabled = not m._is_host
		m.menu_ui._style_selected(tb, mins == GameData.match_minutes, 20)
	if m._lobby_start_btn != null:
		m._lobby_start_btn.visible = m._is_host
		# QA-112 (v3.9): minimum to start — never a full team. Below
		# the minimum the button is disabled and says why.
		var min_reason := _start_minimum_reason()
		if min_reason != "":
			m._lobby_start_btn.disabled = true
			m._lobby_start_btn.text = min_reason
		else:
			m._lobby_start_btn.disabled = false
			# Force-start is explicit: the host may start with players not
			# ready, but the button says so.
			var ready_count := 0
			for id in m._lobby_players.keys():
				if bool(m._lobby_players[id].get("ready", false)):
					ready_count += 1
			if ready_count < m._lobby_players.size():
				m._lobby_start_btn.text = "START ANYWAY (%d/%d ready)" % [ready_count, m._lobby_players.size()]
			else:
				m._lobby_start_btn.text = "START MATCH"
	if m._ready_btn != null:
		var my_id = m.multiplayer.get_unique_id()
		var me_ready: bool = bool(m._lobby_players.get(my_id, {}).get("ready", false))
		m._ready_btn.text = "READY ✓" if me_ready else "I'M READY"
		m.menu_ui._style_selected(m._ready_btn, me_ready, 22)
	if m._ff_check != null:
		m._ff_check.button_pressed = GameData.friendly_fire
		m._ff_check.disabled = not m._is_host
	if m._lobby_status != null:
		# QA-145 (v4.1, Worker V): the host used to read "pick a
		# map and mode, then start!" even while START sat disabled
		# saying NEED 2 PLAYERS — the status contradicted the
		# button. When the minimum is not met, the status now says
		# what is missing, so a host alone in the room knows they
		# need another phone, not a different button.
		if m._is_host:
			var why := _start_minimum_reason()
			if why == "NEED 2 PLAYERS":
				m._lobby_status.text = "Waiting for another player to join — a match needs at least 2 players."
			elif why == "NEED RED + BLUE":
				m._lobby_status.text = "Team mode needs a player on RED and a player on BLUE — pick a team below."
			else:
				m._lobby_status.text = "You are the host - pick a map and mode, then start!"
		else:
			m._lobby_status.text = "Waiting for the host to start the match..."
	if m._host_ip_label != null:
		# The joiner's lifeline: the host IP is always visible here,
		# in its chip (v3.5 QA-059). Keep the label's own visibility
		# in sync with the chip — the flow test reads the label.
		# QA-078: the LAN-local room code rides on the same chip,
		# so the host can read it out to friends.
		var ip_visible := false
		var code_txt := ""
		if m._is_host:
			var ip := LanDiscovery.lan_ip()
			if ip != "":
				code_txt = "  •  Room code: " + GameData.room_code(ip, GameData.room_name)
				m._host_ip_label.text = "HOST IP: " + ip + "  —  friends type this IP to join" + code_txt
			else:
				m._host_ip_label.text = "No Wi-Fi IP found — connect to Wi-Fi or a hotspot, then re-host"
			ip_visible = true
		elif GameData.host_ip != "":
			code_txt = "  •  Room code: " + GameData.room_code(GameData.host_ip, GameData.room_name)
			m._host_ip_label.text = "Connected to host: " + GameData.host_ip + code_txt
			ip_visible = true
		m._host_ip_label.visible = ip_visible
		if m._host_ip_chip != null:
			m._host_ip_chip.visible = ip_visible
	# v3.5 QA-059: room info is labelled fields in the room panel,
	# not one long plain text line. v3.6 QA-069: the fields are
	# tiles in the stat strip now, and the header pill shows the
	# same player count — both updated here, same values.
	if not m._room_info_values.is_empty():
		var priv := "Private" if GameData.room_private else "Public"
		m._room_info_values["Room"].text = "%s • %s" % [GameData.room_name, priv]
		m._room_info_values["Players"].text = "%d/%d" % [m._lobby_players.size(), GameData.max_players]
		m._room_info_values["Map"].text = GameData.MAP_NAMES[GameData.map_id]
		m._room_info_values["Mode"].text = GameData.MODE_NAMES[GameData.game_mode]
		m._room_info_values["Kill limit"].text = str(GameData.kill_limit)
		m._room_info_values["Time"].text = "%d min" % GameData.match_minutes
		m._room_info_values["Friendly fire"].text = "On" if GameData.friendly_fire else "Off"
	if m._lobby_players_badge != null:
		m._lobby_players_badge.label_text = "%d/%d PLAYERS" % [m._lobby_players.size(), GameData.max_players]
	# QA-107 (v3.8): the limit is always kills now — Capture the
	# Flag (whose limit was captures) was removed.
	if m._limit_label != null:
		m._limit_label.text = "Kill limit:"
	if m._strip_limit_cap != null:
		m._strip_limit_cap.text = "KILL LIMIT"
	# QA-078: team pick row only exists for team modes; the
	# appearance rows always show the current saved choice.
	# QA-112: CTF (mode 4) is a team mode too, so the team row
	# shows for it as well (it was TDM-only while CTF was removed).
	var team_mode := GameData.game_mode == 1 or GameData.game_mode == 4
	if m._team_section_label != null:
		m._team_section_label.visible = team_mode
	for i in m._team_buttons.size():
		var tb: Button = m._team_buttons[i]
		tb.visible = team_mode
		var tv: int = [-1, 0, 1][i]
		tb.text = ("✓ " if tv == m._my_team else "") + ("AUTO" if tv == -1 else ("RED" if tv == 0 else "BLUE"))
		m.menu_ui._style_selected(tb, tv == m._my_team, 20)
	# QA-112 (v3.9): the role row shows on Skyfall (any mode); the
	# team banners show only for Skyfall CTF. Role icons use the
	# local player's team colour, so they refresh here too (the
	# team pick calls this refresh). Roles are labels only.
	var on_skyfall := GameData.map_id == GameData.SKYFALL_MAP_ID
	if m._role_section_label != null:
		m._role_section_label.visible = on_skyfall
	if m._role_row != null:
		m._role_row.visible = on_skyfall
	for i in m._role_buttons.size():
		var rb: Button = m._role_buttons[i]
		rb.visible = on_skyfall
		rb.icon = _role_icon(m._my_team, i)
		rb.text = ("✓ " if i == GameData.role else "") + GameData.ROLE_NAMES[i]
		m.menu_ui._style_selected(rb, i == GameData.role, 18)
	if m._skyfall_banner_row != null:
		m._skyfall_banner_row.visible = on_skyfall and GameData.game_mode == 4
	for i in m._lobby_color_buttons.size():
		var cb: Button = m._lobby_color_buttons[i]
		cb.text = ("✓ " if i == GameData.color_index else "") + GameData.COLOR_NAMES[i]
		m.menu_ui._style_selected(cb, i == GameData.color_index, 18)
	for i in m._lobby_helmet_buttons.size():
		var hb: Button = m._lobby_helmet_buttons[i]
		hb.text = ("✓ " if i == GameData.helmet else "") + m.HELMET_NAMES[i]
		m.menu_ui._style_selected(hb, i == GameData.helmet, 18)
	m.menu_lobby._refresh_vote_buttons()


func _refresh_lobby_list() -> void:
	for c in m._lobby_list.get_children():
		c.queue_free()
	var ids: Array = m._lobby_players.keys()
	ids.sort()
	for id in ids:
		var info: Dictionary = m._lobby_players[id]
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
		portrait.texture = m.menu_screens._portrait_texture(int(info.get("portrait", 0)))
		portrait.custom_minimum_size = Vector2(60, 72)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(portrait)
		var lbl := Label.new()
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.text = String(info.get("name", "Player"))
		lbl.add_theme_font_override("font", m.FONT_BODY_SEMIBOLD)
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.add_theme_color_override("font_color", GameData.PLAYER_COLORS[int(info.get("color", 0)) % GameData.PLAYER_COLORS.size()])
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(lbl)
		# QA-112 (v3.9): each player's Skyfall role icon, small
		# (~32 px), next to their name. The icon matches THAT
		# player's team + role; team -1 / unset falls back to red.
		# Roles are labels only — no gameplay effect.
		var role_icon := TextureRect.new()
		role_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		role_icon.texture = _role_icon(int(info.get("team", -1)), int(info.get("role", 0)))
		role_icon.custom_minimum_size = Vector2(32, 32)
		role_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		role_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		role_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(role_icon)
		if int(id) == 1:
			row.add_child(m.menu_lobby._lobby_chip("HOST", m.UI_WARNING))
		elif int(id) == m.multiplayer.get_unique_id():
			row.add_child(m.menu_lobby._lobby_chip("YOU", m.UI_ACCENT))
		var is_ready: bool = bool(info.get("ready", false))
		if is_ready:
			row.add_child(m.menu_lobby._lobby_chip("READY ✓", m.UI_SUCCESS))
		else:
			row.add_child(m.menu_lobby._lobby_chip("NOT READY", m.UI_FONT_MUTED))
		# QA-078: team chip in team modes (RED / BLUE / AUTO).
		# QA-112: CTF (mode 4) is a team mode too.
		if GameData.game_mode == 1 or GameData.game_mode == 4:
			var pt: int = int(info.get("team", -1))
			if pt == 0:
				row.add_child(m.menu_lobby._lobby_chip("RED", m.UI_DANGER))
			elif pt == 1:
				row.add_child(m.menu_lobby._lobby_chip("BLUE", Color(0.25, 0.55, 0.95)))
			else:
				row.add_child(m.menu_lobby._lobby_chip("AUTO", m.UI_FONT_MUTED))
		# The host can remove a player from the room.
		if m._is_host and int(id) != 1 and int(id) != m.multiplayer.get_unique_id():
			var kick_btn := Button.new()
			kick_btn.text = "KICK"
			kick_btn.custom_minimum_size = Vector2(90, 56)
			m.menu_ui._style_button(kick_btn, 20, 56)
			kick_btn.pressed.connect(m._on_kick_pressed.bind(int(id)))
			row.add_child(kick_btn)
			m.menu_ui._connect_scroll_button(kick_btn, m._lobby_left_scroll)
		m._lobby_list.add_child(card)


func _on_max_pressed(n: int) -> void:
	m.menu_ui._click()
	GameData.max_players = clampi(n, 2, 12)
	_refresh_max_buttons()


func _refresh_max_buttons() -> void:
	for i in m._max_buttons.size():
		var n: int = [2, 4, 6, 8, 10, 12][i]
		var b: Button = m._max_buttons[i]
		b.text = ("✓ " if n == GameData.max_players else "") + str(n)
		m.menu_ui._style_selected(b, n == GameData.max_players, 22) # v3.6 QA-068: 64 px buttons, 22 px font (was 20)


func _on_private_toggled(on: bool) -> void:
	GameData.room_private = on
	# v3.6 QA-068: the password field greys out when Private is
	# off, so it is obvious it does nothing until Private is on.
	# The text is kept, not cleared — flip Private back on and
	# the password is still there.
	if m._room_password_input != null:
		m._room_password_input.editable = on


func _on_friendly_fire_toggled(on: bool) -> void:
	if not m._is_host:
		return
	GameData.friendly_fire = on
	m._broadcast_lobby()


func _update_my_ip_label() -> void:
	if m._my_ip_label == null:
		return
	var ip := LanDiscovery.lan_ip()
	if ip != "":
		m._my_ip_label.text = "Your IP on this Wi-Fi: " + ip + "  —  if you host, friends can type this number to join."
	else:
		m._my_ip_label.text = "No Wi-Fi IP found — connect to Wi-Fi or a hotspot first."


func _room_card() -> Dictionary:
	# The announcement other phones see in their room list.
	return {
		"room_name": GameData.room_name,
		"host_name": GameData.player_name,
		"players": m._lobby_players.size(),
		"max_players": GameData.max_players,
		"map_id": GameData.map_id,
		"mode": GameData.game_mode,
		"status": m._room_status,
		"port": m._server_port(),
		"private": GameData.room_private,
	}


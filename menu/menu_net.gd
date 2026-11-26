class_name MenuNet
extends RefCounted


# QA-140 (v3.15): extracted from main.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `m` (dependency injection).


var m # the owner (main.gd)


func _init(owner) -> void:
	m = owner


func _on_create_room_pressed() -> void:
	m.menu_ui._click()
	var room_name = m._room_name_input.text.strip_edges()
	if room_name == "":
		room_name = "Room"
	GameData.room_name = LanDiscovery.sanitise(room_name)
	GameData.room_private = m._private_check.button_pressed
	GameData.room_password = m._room_password_input.text.strip_edges()
	if GameData.room_private and GameData.room_password == "":
		m._set_status("A private room needs a password — type one, or turn Private off.")
		return
	_create_room()


func _server_port() -> int:
	# Test-only override (--port=N): lets the restart/join tests run
	# on a different port when another suite is using 7777 on this
	# machine. Production always uses PORT (7777).
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			return clampi(int(a.trim_prefix("--port=")), 1024, 65535)
	return m.PORT


func _create_room() -> bool:
	if m.multiplayer.multiplayer_peer != null and m.multiplayer.multiplayer_peer is not OfflineMultiplayerPeer:
		m._set_status("You are already in a game — leave it first.")
		return false
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(_server_port(), GameData.max_players - 1)
	if err != OK:
		m._set_status("Could not host a game (error " + str(err) + "). Another game may already be hosting on this phone.")
		return false
	m.multiplayer.multiplayer_peer = peer
	m._is_host = true
	m._room_status = "lobby"
	m._lobby_players.clear()
	m._lobby_players[m.multiplayer.get_unique_id()] = _my_lobby_info()
	# Start announcing the room on every subnet broadcast address.
	m._discovery.start_broadcasting()
	m._broadcast_timer = 0.0
	m.menu_ui._show_only(m._lobby_panel)
	m.menu_lobby_setup._refresh_lobby_buttons()
	m.menu_lobby_setup._refresh_lobby_list()
	m._set_status("")
	return true


func _on_join_pressed() -> void:
	m.menu_ui._click()
	var ip = m._ip_input.text.strip_edges()
	if ip == "":
		m._set_status("Type the host IP first, or tap a game found below.")
		return
	join_game(ip, m._join_password_input.text.strip_edges())


func _on_quick_match_pressed() -> void:
	# Join the first open lobby room with space. Private rooms and
	# rooms already playing are skipped.
	m.menu_ui._click()
	for room in m._discovery.get_rooms():
		if String(room.get("status", "")) != "lobby":
			continue
		if bool(room.get("private", false)):
			continue
		if int(room.get("players", 99)) >= int(room.get("max_players", 0)):
			continue
		join_game(String(room["ip"]))
		return
	m._set_status("No open rooms found — tap REFRESH, type the host IP, or host your own room.")


func _on_join_code_pressed() -> void:
	# QA-078: join by room code — look the code up in the rooms
	# discovered on this Wi-Fi and join that room's IP. Private
	# rooms still need their password (the password field above).
	m.menu_ui._click()
	var code = m._room_code_input.text.strip_edges().to_upper()
	if code == "":
		m._set_status("Type the room code first — ask the host for it.")
		return
	if not code.begins_with("FRAG-"):
		code = "FRAG-" + code
	for room in m._discovery.get_rooms():
		if GameData.room_code(String(room["ip"]), String(room["room_name"])) == code:
			if String(room.get("status", "")) != "lobby":
				m._set_status("That room is already in a match.")
				return
			join_game(String(room["ip"]), m._join_password_input.text.strip_edges())
			return
	m._set_status("No room with code %s on this Wi-Fi — tap REFRESH and try again." % code)


func _on_refresh_pressed() -> void:
	# Drop the cached list and rebuild it from fresh announcements.
	m.menu_ui._click()
	m._discovery.forget_all_rooms()
	m._room_sig_cache = ""
	_refresh_room_list()
	m._set_status("Looking for rooms on this Wi-Fi...")


func join_game(ip: String, password: String = "") -> void:
	if m.multiplayer.multiplayer_peer != null and m.multiplayer.multiplayer_peer is not OfflineMultiplayerPeer:
		return
	GameData.host_ip = ip
	var peer := ENetMultiplayerPeer.new()
	var err = peer.create_client(ip, m.PORT)
	if err != OK:
		m._set_status("Could not connect to " + ip + " (error " + str(err) + "). Check the IP and Wi-Fi.")
		return
	m._peer = peer
	m.multiplayer.multiplayer_peer = peer
	m._joining = true
	m._join_ip = ip
	m._join_password = password
	m._join_timer = 0.0
	m._join_rejected = false
	m._set_status("Connecting to " + ip + "...")


func _on_connected() -> void:
	m._joining = false
	m._set_status("Connected, waiting for game...")
	m._is_host = false
	m.menu_ui._show_only(m._lobby_panel)
	m.menu_lobby_setup._refresh_lobby_buttons()
	m.menu_lobby_setup._refresh_lobby_list()
	# Tell the host who we are for the lobby list (password included
	# only in this one message; it is never broadcast to other players).
	m.rpc_id(1, "register_lobby_player", _my_lobby_info())


# QA-060: close the current ENet peer explicitly before dropping
# it. A dropped-but-open peer can keep its UDP socket bound, so the
# next create_server / create_client on the same port fails with
# "Couldn't create an ENet host". Every teardown site uses this.
func _close_peer() -> void:
	var old_peer = m.multiplayer.multiplayer_peer
	if old_peer is ENetMultiplayerPeer:
		(old_peer as ENetMultiplayerPeer).close()


func _on_connection_failed() -> void:
	m._joining = false
	_close_peer()
	m._peer = null
	m.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	m._set_status("Could not reach that host. Check the IP and Wi-Fi, then tap JOIN to retry.")


func _my_lobby_info() -> Dictionary:
	var my_id = m.multiplayer.get_unique_id()
	var ready := false
	if m._lobby_players.has(my_id):
		ready = bool(m._lobby_players[my_id].get("ready", false))
	return {
		"name": GameData.player_name,
		"color": GameData.color_index,
		"portrait": GameData.portrait,
		"ready": ready,
		"vote": m._my_vote,
		"team": m._my_team, # QA-078: RED 0 / BLUE 1 / AUTO -1 (team modes)
		"role": GameData.role, # QA-112 (v3.9): Skyfall role 0-3, label only
		# Only used by register_lobby_player on the host; stripped
		# before the player list is broadcast to anyone else.
		"password": m._join_password,
	}


func register_lobby_player(info: Dictionary) -> void:
	if not m.multiplayer.is_server():
		return
	var sender = m.multiplayer.get_remote_sender_id()
	# Room full?
	if m._lobby_players.size() >= GameData.max_players:
		m.rpc_id(sender, "join_rejected", "Room is full.")
		m.multiplayer.multiplayer_peer.disconnect_peer(sender)
		return
	# Wrong password for a private room?
	var pw: String = str(info.get("password", ""))
	if GameData.room_private and pw != GameData.room_password:
		m.rpc_id(sender, "join_rejected", "Wrong room password.")
		m.multiplayer.multiplayer_peer.disconnect_peer(sender)
		return
	var clean := info.duplicate()
	clean.erase("password")
	m._lobby_players[sender] = clean
	_broadcast_lobby()


func join_rejected(reason: String) -> void:
	# The host turned us away (full room / wrong password). Show the
	# reason and stop — the disconnect that follows must not overwrite
	# this message (see _on_server_disconnected).
	m._join_rejected = true
	m._joining = false
	# QA-060: close the refused connection now; the server-side
	# disconnect that follows would close it via _leave_lobby, but
	# an explicit close here frees the socket immediately.
	_close_peer()
	m._peer = null
	m.menu_ui._show_only(m._mp_panel)
	m._set_status("Could not join: " + reason)


func set_ready(ready: bool) -> void:
	if not m.multiplayer.is_server():
		return
	var sender = m.multiplayer.get_remote_sender_id()
	if m._lobby_players.has(sender):
		m._lobby_players[sender]["ready"] = ready
		_broadcast_lobby()


func _on_ready_pressed() -> void:
	m.menu_ui._click()
	var my_id = m.multiplayer.get_unique_id()
	var cur: bool = bool(m._lobby_players.get(my_id, {}).get("ready", false))
	var next: bool = not cur
	if m._is_host:
		m._lobby_players[my_id]["ready"] = next
		_broadcast_lobby()
	else:
		m.rpc_id(1, "set_ready", next)


func kicked_from_lobby(reason: String) -> void:
	# The host removed us. Leave the lobby cleanly and say why.
	m._join_rejected = true
	_leave_lobby()
	m.menu_ui._show_only(m._mp_panel)
	m._set_status(reason)


func _on_kick_pressed(id: int) -> void:
	m.menu_ui._click()
	if not m._is_host:
		return
	m.rpc_id(id, "kicked_from_lobby", "The host removed you from the room.")
	m.multiplayer.multiplayer_peer.disconnect_peer(id)
	m._lobby_players.erase(id)
	_broadcast_lobby()


func _broadcast_lobby() -> void:
	if not m.multiplayer.is_server():
		return
	var settings := {
		"map": GameData.map_id, "mode": GameData.game_mode,
		"limit": GameData.kill_limit, "minutes": GameData.match_minutes,
		"max": GameData.max_players, "ff": GameData.friendly_fire,
		"room": GameData.room_name, "private": GameData.room_private,
	}
	# Never broadcast passwords: strip them from every player entry.
	var safe_players := {}
	for id in m._lobby_players.keys():
		var clean: Dictionary = (m._lobby_players[id] as Dictionary).duplicate()
		clean.erase("password")
		safe_players[id] = clean
	m.rpc("lobby_update", safe_players, settings)
	m.menu_lobby_setup._refresh_lobby_buttons()
	m.menu_lobby_setup._refresh_lobby_list()


func lobby_update(players: Dictionary, settings: Dictionary) -> void:
	m._lobby_players = players
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
	m.menu_lobby_setup._refresh_lobby_buttons()
	m.menu_lobby_setup._refresh_lobby_list()


func _on_peer_connected(id: int) -> void:
	# The joining client registers itself; nothing to spawn here (no game yet).
	pass


func _on_server_disconnected() -> void:
	# The host left the lobby while we were waiting. If we were
	# rejected/kicked, that message already explains it — keep it.
	if not m._is_host:
		_leave_lobby()
		m.menu_ui._show_only(m._mp_panel)
		if not m._join_rejected:
			m._set_status("The host left. Pick another game or host your own.")
		m._join_rejected = false


func _on_peer_disconnected(id: int) -> void:
	if m._is_host and m._lobby_players.has(id):
		m._lobby_players.erase(id)
		_broadcast_lobby()


func _on_start_pressed() -> void:
	m.menu_ui._click()
	GameData.solo_practice = false
	if not m._is_host or m._starting_match:
		return
	# QA-112 (v3.9): minimum to start — never require full teams.
	# The button is disabled below the minimum, but do not trust
	# the button alone (scripted / timer starts reach here too).
	if not m.menu_lobby_setup._start_minimum_met():
		return
	# Phase 4: the map vote decides the map (host's pick on ties /
	# no votes, per GameData.tally_map_vote).
	var votes := {}
	for id in m._lobby_players.keys():
		votes[id] = int((m._lobby_players[id] as Dictionary).get("vote", -1))
	GameData.map_id = GameData.tally_map_vote(votes, m.menu_lobby._vote_candidates_now(), GameData.map_id)
	# QA-112 (v3.9): the vote can pick a non-Skyfall map while the
	# mode is CTF — CTF is only on Skyfall, so fall back to FFA
	# before the match starts instead of starting CTF elsewhere.
	if not m.menu_lobby._ctf_available() and GameData.game_mode == 4:
		GameData.game_mode = 0
	m._starting_match = true
	m.rpc("start_match", GameData.map_id, GameData.game_mode, GameData.kill_limit, GameData.match_minutes)


func _on_lobby_practice_pressed() -> void:
	m.menu_ui._click()
	if not m._is_host:
		return
	# Keep the host's chosen map, close the LAN room cleanly, and launch
	# an offline sandbox without the multiplayer lobby's two-player gate.
	_leave_lobby()
	GameData.solo_practice = true
	GameData.game_mode = 0
	m.get_tree().change_scene_to_file(m.GAME_SCENE)


func start_match(map_id: int, mode: int, kill_limit: int, minutes: int) -> void:
	# QA-060: idempotency guard on the RPC itself — the host button
	# is guarded by _starting_match, but a duplicated or late RPC
	# would call change_scene_to_file again unguarded. The flag is
	# per main-scene instance (a fresh instance is created when the
	# game returns to the menu), and _leave_lobby clears it.
	if m._match_started:
		return
	m._match_started = true
	GameData.map_id = map_id
	# QA-107 (v3.8): clamp — a v3.7 host could still send mode 4
	# (Capture the Flag, removed); it falls back to FFA (0).
	GameData.game_mode = clampi(mode, 0, GameData.MODE_NAMES.size() - 1)
	# QA-112 (v3.9): CTF is only on Skyfall — a stale start_match
	# for mode 4 on any other map falls back to FFA too.
	if GameData.map_id != GameData.SKYFALL_MAP_ID and GameData.game_mode == 4:
		GameData.game_mode = 0
	GameData.kill_limit = kill_limit
	GameData.match_minutes = minutes
	m._room_status = "playing"
	# The game scene runs its own discovery broadcast from here on.
	if m._discovery != null:
		m._discovery.stop_broadcasting()
	m.get_tree().change_scene_to_file(m.GAME_SCENE)


func _on_lobby_leave_pressed() -> void:
	m.menu_ui._click()
	_leave_lobby()
	m.menu_ui._show_only(m._mp_panel)


func _leave_lobby() -> void:
	if m._discovery != null:
		m._discovery.stop_broadcasting()
	# QA-060: close the old ENet peer explicitly before replacing
	# it — a dropped-but-open peer can keep UDP 7777 bound, so the
	# next host attempt in the same process fails to create a host.
	_close_peer()
	if m.multiplayer.multiplayer_peer != null and m.multiplayer.multiplayer_peer is not OfflineMultiplayerPeer:
		m.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	m._peer = null
	m._is_host = false
	m._starting_match = false
	m._match_started = false
	m._joining = false
	m._join_rejected = false
	m._room_status = "lobby"
	m._my_vote = -1
	m._my_team = -1 # QA-078: a new room starts on AUTO team
	GameData.team_pref = -1
	m._lobby_players.clear()


func _on_room_found(_room: Dictionary) -> void:
	# The room list rebuilds in _process from get_rooms().
	pass


func _on_room_expired(_ip: String) -> void:
	pass


func _room_signature() -> String:
	var parts: Array[String] = []
	var rooms = m._discovery.get_rooms()
	rooms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["ip"]) < String(b["ip"]))
	for room in rooms:
		parts.append("%s|%s|%s|%d|%d|%s" % [
			String(room["ip"]), String(room["room_name"]), String(room["host_name"]),
			int(room["players"]), int(room["max_players"]), String(room["status"]),
		])
	return "|".join(parts)


func _refresh_room_list() -> void:
	for c in m._host_buttons.get_children():
		c.queue_free()
	var rooms = m._discovery.get_rooms()
	rooms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["ip"]) < String(b["ip"]))
	if rooms.is_empty():
		var none := Label.new()
		none.text = "No rooms found yet — make sure both phones are on the same Wi-Fi, or type the host IP above."
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.add_theme_font_size_override("font_size", 18)
		none.add_theme_color_override("font_color", m.UI_FONT_MUTED)
		m._host_buttons.add_child(none)
		return
	# The LAN screen intentionally fits without page scrolling. Show
	# the first four room cards; manual IP/code join and Quick Match
	# remain available when discovery finds more rooms.
	var visible_count: int = mini(rooms.size(), 4)
	for room_index in visible_count:
		var room: Dictionary = rooms[room_index]
		var ip := String(room["ip"])
		var map_name := GameData.MAP_NAMES[int(room["map_id"])] if int(room["map_id"]) < GameData.MAP_NAMES.size() else "?"
		var mode_name := GameData.MODE_NAMES[int(room["mode"])] if int(room["mode"]) < GameData.MODE_NAMES.size() else "?"
		var lock := " 🔒" if bool(room["private"]) else ""
		var b := Button.new()
		b.text = "%s%s (%d/%d) | %s | %s" % [String(room["room_name"]), lock, int(room["players"]), int(room["max_players"]), map_name, mode_name]
		b.custom_minimum_size = Vector2(0, 62)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		m.menu_ui._style_button(b, 19, 62)
		var full: bool = int(room["players"]) >= int(room["max_players"])
		var playing: bool = String(room["status"]) != "lobby"
		b.disabled = full or playing
		if full:
			b.text += " (FULL)"
		elif playing:
			b.text += " (IN GAME)"
		b.pressed.connect(join_game.bind(ip))
		m._host_buttons.add_child(b)
		m.menu_ui._connect_scroll_button(b, m._mp_scroll)
	if rooms.size() > visible_count:
		var more := Label.new()
		more.text = "+%d more rooms — use Quick Match or enter a host IP" % (rooms.size() - visible_count)
		more.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		more.add_theme_font_size_override("font_size", 15)
		more.add_theme_color_override("font_color", m.UI_FONT_MUTED)
		m._host_buttons.add_child(more)


class_name MenuTest
extends RefCounted


# QA-140 (v3.15): extracted from main.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `m` (dependency injection).


var m # the owner (main.gd)


func _init(owner) -> void:
	m = owner


func _scrolltest_begin() -> void:
	GameData.room_name = "ScrollTest"
	GameData.max_players = 4
	GameData.room_private = false
	GameData.room_password = ""
	m._room_name_input.text = "ScrollTest"
	m.menu_net._create_room()


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
	var vis = m.get_viewport().get_visible_rect().size
	var win = m.get_window().size
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


func _sc_drag_up(idx: int, vp_pos: Vector2, total_px: float, vp_scale: float = 1.0) -> void:
	# A frame between press / each drag step / release, like a real
	# finger: without the frames the button never sees the pointer
	# leave its rect while the list scrolls under it, and a
	# drag-release can falsely count as a tap on the original button.
	m._sc_drag_done = false
	_sc_press(idx, vp_pos)
	await m.get_tree().process_frame
	var steps := int(total_px / 50.0)
	var cur := vp_pos
	for i in steps:
		cur += Vector2(0, -50.0 * vp_scale)
		_sc_drag(idx, cur, Vector2(0, -50.0 * vp_scale))
		await m.get_tree().process_frame
	_sc_release(idx, cur)
	m._sc_drag_done = true


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
	if m._scroll_done:
		return
	if m._scroll_steps.is_empty():
		_scrolltest_build_steps()
		m._scroll_step = 0
		m._scroll_in_step = false
		m._scroll_timer = 0.0
	if m._scroll_step >= m._scroll_steps.size():
		m._scroll_done = true
		print("SCROLLTEST DONE: %d/%d passed" % [m._scroll_passed, m._scroll_passed + m._scroll_failed])
		m.get_tree().quit()
		return
	var step: Dictionary = m._scroll_steps[m._scroll_step]
	if not m._scroll_in_step:
		(step["setup"] as Callable).call()
		m._scroll_in_step = true
		m._scroll_timer = float(step["wait"])
	m._scroll_timer -= delta
	# The check waits for an in-flight async drag to finish (see
	# _sc_drag_up): at slow frame rates the drag steps outlive the
	# step's wait, and checking early measures a partial drag.
	if m._scroll_timer <= 0.0 and (m._sc_drag_done or m._scroll_timer < -2.0):
		var result: Array = (step["check"] as Callable).call()
		var ok: bool = bool(result[0])
		if ok:
			m._scroll_passed += 1
		else:
			m._scroll_failed += 1
		print("SCROLLTEST %s: %s — %s" % [String(step["name"]), "PASS" if ok else "FAIL", String(result[1])])
		m._scroll_step += 1
		m._scroll_in_step = false
		m._scroll_timer = 0.0


func _scrolltest_build_steps() -> void:
	m._scroll_steps = [
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
	m._lobby_scroll.scroll_vertical = 0
	var b: Button = m._map_buttons[0]
	_sc_drag_up(800, _sc_vp_pos(b, b.size * 0.5), 200.0, _sc_vp_scale(b))


func _sct_c_drag_button() -> Array:
	var v = m._lobby_scroll.scroll_vertical
	return [v >= 150.0, "scroll_vertical=%d (want >=150 after 200 px drag on map button)" % int(v)]


func _sct_s_drag_label() -> void:
	# Drag on the "Map:" section label INSIDE the scroll area (the
	# lobby controls_hint above the scroll cannot scroll it, and the
	# "Scroll for more maps" hint sits below the fold at scroll 0).
	# The scroll position only applies on the next frame, so wait
	# for layout before measuring the label's position.
	m._lobby_scroll.scroll_vertical = 0
	await m.get_tree().process_frame
	await m.get_tree().process_frame
	_sc_drag_up(801, _sc_vp_pos(m._map_section_label, Vector2(m._map_section_label.size.x * 0.5, m._map_section_label.size.y * 0.5)), 200.0, _sc_vp_scale(m._map_section_label))


func _sct_c_drag_label() -> Array:
	var v = m._lobby_scroll.scroll_vertical
	return [v >= 150.0, "scroll_vertical=%d (want >=150 after 200 px drag on label)" % int(v)]


func _sct_s_tap_map() -> void:
	m._lobby_scroll.scroll_vertical = 0
	await m.get_tree().process_frame
	await m.get_tree().process_frame
	_sc_tap(802, _sc_vp_pos(m._map_buttons[1], m._map_buttons[1].size * 0.5))


func _sct_c_tap_map() -> Array:
	var ok: bool = GameData.map_id == 1
	return [ok, "map_id=%d (want 1 after tapping map button [1])" % GameData.map_id]


func _sct_s_drag_release() -> void:
	# Drag from button [0] up 200 px; the release lands over a
	# different button — it must NOT select anything.
	_sc_drag_up(803, _sc_vp_pos(m._map_buttons[0], m._map_buttons[0].size * 0.5), 200.0, _sc_vp_scale(m._map_buttons[0]))


func _sct_c_drag_release() -> Array:
	var ok: bool = GameData.map_id == 1
	return [ok, "map_id=%d (want still 1 — drag-release must not select)" % GameData.map_id]


func _sct_s_scroll_max() -> void:
	# Scroll just enough to bring the last map row into view (max
	# scroll shows the mode/limit rows at the bottom — the last map
	# row has scrolled past the top by then).
	var b: Button = m._map_buttons[4]
	var btop: float = b.get_global_rect().position.y - m._lobby_scroll.get_global_rect().position.y + m._lobby_scroll.scroll_vertical
	m._lobby_scroll.scroll_vertical = btop - 100.0


func _sct_c_last_visible() -> Array:
	var b: Button = m._map_buttons[4]
	var brect := Rect2(_sc_vp_pos(b, Vector2.ZERO), b.size)
	var srect = Rect2(_sc_vp_pos(m._lobby_scroll, Vector2.ZERO), m._lobby_scroll.size)
	var inter := brect.intersection(srect)
	var ok: bool = inter.size.y > 30.0
	return [ok, "last map button visible height=%d px (want >30) at max scroll" % int(inter.size.y)]


func _sct_s_tap_last() -> void:
	await m.get_tree().process_frame
	# QA-099 (v3.7): tap the VISIBLE part of the last map card, not
	# its centre — the taller v3.7 cards (252 px) put the centre 8 px
	# below the scroll viewport at this scroll position, so the tap
	# landed outside the scroll container and selected nothing. A
	# real player taps the part they can see; the card is reachable
	# and tappable, the old tap point just wasn't on it any more.
	var b: Button = m._map_buttons[4]
	var brect := b.get_global_rect()
	var inter = brect.intersection(m._lobby_scroll.get_global_rect())
	var tap_local := inter.get_center() - brect.position
	_sc_tap(804, _sc_vp_pos(b, tap_local))


func _sct_c_tap_last() -> Array:
	var ok: bool = GameData.map_id == 4
	return [ok, "map_id=%d (want 4 — every map reachable and tappable)" % GameData.map_id]


func _sct_s_mp_drag() -> void:
	m.menu_ui._show_only(m._mp_panel)
	# Fake a long room list (no real rooms on this sandbox Wi-Fi).
	for c in m._host_buttons.get_children():
		c.queue_free()
	for i in 12:
		var b := Button.new()
		b.text = "Test Room %d" % i
		b.custom_minimum_size = Vector2(0, 56)
		m.menu_ui._style_button(b, 20, 56)
		m._host_buttons.add_child(b)
		m.menu_ui._connect_scroll_button(b, m._mp_scroll)
	await m.get_tree().process_frame
	await m.get_tree().process_frame
	m._mp_scroll.scroll_vertical = 450
	await m.get_tree().process_frame
	var first: Button = m._host_buttons.get_child(0)
	_sc_drag_up(805, _sc_vp_pos(first, first.size * 0.5), 200.0, _sc_vp_scale(first))


func _sct_c_mp_drag() -> Array:
	var v = m._mp_scroll.scroll_vertical
	var mx = m._mp_scroll.get_v_scroll_bar().max_value
	var n = m._host_buttons.get_child_count()
	for c in m._host_buttons.get_children():
		c.queue_free()
	m.menu_ui._show_only(m._lobby_panel)
	return [v >= 100.0, "mp scroll_vertical=%d max=%d children=%d (want >=100 after 200 px drag on a room button)" % [int(v), int(mx), n]]


func _sct_s_settings_drag() -> void:
	m.menu_ui._show_only(m._settings_panel)
	m._settings_scroll.scroll_vertical = 0
	# The Back button lives inside the settings scroll area.
	var back_btn: Button = null
	for c in m._settings_scroll.get_children():
		for sub in (c as VBoxContainer).get_children():
			if sub is Button and (sub as Button).text == "Back":
				back_btn = sub
	if back_btn != null:
		_sc_drag_up(806, _sc_vp_pos(back_btn, back_btn.size * 0.5), 150.0, _sc_vp_scale(back_btn))


func _sct_c_settings_drag() -> Array:
	var v = m._settings_scroll.scroll_vertical
	var mx = m._settings_scroll.get_v_scroll_bar().max_value
	m.menu_ui._show_only(m._menu_panel)
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
	m.menu_ui._show_only(m._lobby_panel)
	m._lobby_left_scroll.scroll_vertical = 0
	m._lobby_scroll.scroll_vertical = 0
	await m.get_tree().process_frame
	await m.get_tree().process_frame
	var lbl: Label = m._players_section_label
	_sc_drag_up(807, _sc_vp_pos(lbl, Vector2(lbl.size.x * 0.5, lbl.size.y * 0.5)), 200.0, _sc_vp_scale(lbl))


func _sct_c_left_drag() -> Array:
	var v = m._lobby_left_scroll.scroll_vertical
	var mx = m._lobby_left_scroll.get_v_scroll_bar().max_value
	var map_v = m._lobby_scroll.scroll_vertical
	return [v >= 150.0 and map_v == 0.0, "left scroll_vertical=%d (max=%d, want >=150) map scroll=%d (want 0)" % [int(v), int(mx), int(map_v)]]


func _shotall_begin() -> void:
	m._shot_steps = [
		{"name": "menu", "wait": 0.5, "setup": _shot_s_menu, "file": "user://shot_menu.png"},
		{"name": "customize", "wait": 0.5, "setup": _shot_s_customize, "file": "user://shot_customize.png"},
		{"name": "settings", "wait": 0.5, "setup": _shot_s_settings, "file": "user://shot_settings.png"},
		{"name": "multiplayer", "wait": 0.5, "setup": _shot_s_multiplayer, "file": "user://shot_multiplayer.png"},
		{"name": "join", "wait": 0.5, "setup": _shot_s_join, "file": "user://shot_join.png"},
		{"name": "lobby", "wait": 0.5, "setup": _shot_s_lobby, "file": "user://shot_lobby.png"},
	]
	m._shot_step = 0
	m._shot_in_step = false
	m._shot_timer = 0.0


func _update_shotall(delta: float) -> void:
	if m._shot_step >= m._shot_steps.size():
		print("SHOTALL DONE")
		m.get_tree().quit()
		return
	var step: Dictionary = m._shot_steps[m._shot_step]
	if not m._shot_in_step:
		(step["setup"] as Callable).call()
		m._shot_in_step = true
		m._shot_timer = float(step["wait"])
	m._shot_timer -= delta
	if m._shot_timer <= 0.0:
		m._capture_flow_shot_now(String(step["file"]))
		m._shot_step += 1
		m._shot_in_step = false
		m._shot_timer = 0.0


func _shot_s_menu() -> void:
	m.menu_ui._show_only(m._menu_panel)


func _shot_s_customize() -> void:
	m.menu_ui._show_only(m._custom_panel)


func _shot_s_settings() -> void:
	m.menu_ui._show_only(m._settings_panel)


func _shot_s_multiplayer() -> void:
	m.menu_ui._show_only(m._mp_panel)


# QA-103 (v3.8): the join area is below the Create Room card in the
# same scroll — scroll to the bottom so the two-column join layout
# (rooms list on the right, QUICK LAN MATCH at the bottom of the
# right column) is in frame for the capture.
func _shot_s_join() -> void:
	m.menu_ui._show_only(m._mp_panel)
	m._mp_scroll.scroll_vertical = 100000


func _shot_s_lobby() -> void:
	GameData.room_name = "ShotTest"
	GameData.max_players = 4
	GameData.room_private = false
	GameData.room_password = ""
	m._room_name_input.text = "ShotTest"
	m.menu_net._create_room()


func _jointest_host_begin() -> void:
	GameData.room_name = "JoinTest"
	GameData.max_players = 4
	GameData.room_private = false
	GameData.room_password = ""
	m._room_name_input.text = "JoinTest"
	m.menu_net._create_room()
	print("JOINTEST HOST: room created, starting match in 3 s")
	m.get_tree().create_timer(3.0).timeout.connect(m.menu_net._on_start_pressed)


func _jointest_client_quick_begin() -> void:
	# Wait for discovery to hear the host's broadcast, then press
	# QUICK LAN MATCH exactly as the user did (room list NOT used,
	# no manual IP). If no room is heard in 5 s, fail loudly —
	# discovery itself is then the problem, not the spawn handshake.
	for i in 50:
		await m.get_tree().create_timer(0.1).timeout
		if not m._discovery.get_rooms().is_empty():
			break
	var rooms = m._discovery.get_rooms()
	print("JOINTEST CLIENT: rooms heard via discovery: ", rooms)
	if rooms.is_empty():
		print("JOINTEST CLIENT: FAIL — no room discovered in 5 s (broadcast/listen broken)")
		m.get_tree().quit()
		return
	m.menu_net._on_quick_match_pressed()


func _rejointest_host_begin() -> void:
	GameData.room_name = "RejoinTest"
	GameData.max_players = 4
	GameData.room_private = false
	GameData.room_password = ""
	m._room_name_input.text = "RejoinTest"
	m.menu_net._create_room()
	print("REJOINTEST HOST: room created, staying in lobby for 30 s")
	m.get_tree().create_timer(30.0).timeout.connect(func() -> void:
		print("REJOINTEST HOST: done")
		m.get_tree().quit()
	)


func _rejointest_client_begin() -> void:
	# No discovery wait: two Godot instances on ONE machine cannot
	# both bind the discovery listen port (UDP 7778) — the second
	# bind fails, so the client would never hear the room. That is a
	# single-machine artifact (real phones each have their own 7778);
	# discovery itself is covered by the menu-net test. The client
	# therefore joins the host by loopback IP directly — the ENet
	# join / leave / re-join under test is identical either way.
	m.menu_net.join_game("127.0.0.1")
	await m.get_tree().create_timer(3.0).timeout
	var in_lobby_1: bool = m._lobby_panel.visible and not m._is_host and m._lobby_players.has(m.multiplayer.get_unique_id())
	print("REJOINTEST JOIN-1: %s — lobby=%s players=%d" % ["PASS" if in_lobby_1 else "FAIL", m._lobby_panel.visible, m._lobby_players.size()])
	if not in_lobby_1:
		m.get_tree().quit()
		return
	# Leave: the teardown under test — _leave_lobby must close() the
	# client ENet peer and drop back to an offline peer.
	m.menu_net._leave_lobby()
	m.menu_ui._show_only(m._mp_panel)
	await m.get_tree().create_timer(2.0).timeout
	var offline: bool = m.multiplayer.multiplayer_peer is OfflineMultiplayerPeer
	print("REJOINTEST TEARDOWN: %s — peer offline=%s" % ["PASS" if offline else "FAIL", offline])
	if not offline:
		m.get_tree().quit()
		return
	m.menu_net.join_game("127.0.0.1")
	await m.get_tree().create_timer(3.0).timeout
	var in_lobby_2: bool = m._lobby_panel.visible and not m._is_host and m._lobby_players.has(m.multiplayer.get_unique_id())
	print("REJOINTEST JOIN-2: %s — lobby=%s players=%d" % ["PASS" if in_lobby_2 else "FAIL", m._lobby_panel.visible, m._lobby_players.size()])
	print("REJOINTEST DONE: %s" % ("PASS" if in_lobby_1 and offline and in_lobby_2 else "FAIL"))
	m.get_tree().quit()


func _update_menu_nettest(delta: float) -> void:
	if m._menu_net_done:
		return
	if m._menu_net_steps.is_empty():
		_mnt_build_steps()
		m._menu_net_step = 0
		m._menu_net_in_step = false
		m._menu_net_timer = 0.0
	if m._menu_net_step >= m._menu_net_steps.size():
		m._menu_net_done = true
		print("MENUNET DONE: %d/%d passed" % [m._menu_net_passed, m._menu_net_passed + m._menu_net_failed])
		m.get_tree().quit()
		return
	var step: Dictionary = m._menu_net_steps[m._menu_net_step]
	if not m._menu_net_in_step:
		(step["setup"] as Callable).call()
		m._menu_net_in_step = true
		m._menu_net_timer = float(step["wait"])
	m._menu_net_timer -= delta
	if m._menu_net_timer <= 0.0:
		var result: Array = (step["check"] as Callable).call()
		var ok: bool = bool(result[0])
		if ok:
			m._menu_net_passed += 1
		else:
			m._menu_net_failed += 1
		print("MENUNET %s: %s — %s" % [String(step["name"]), "PASS" if ok else "FAIL", String(result[1])])
		m._menu_net_step += 1
		m._menu_net_in_step = false
		m._menu_net_timer = 0.0


func _mnt_build_steps() -> void:
	m._menu_net_steps = [
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
	var card_ok: bool = m._profile_name_lbl != null and m._profile_name_lbl.text == GameData.player_name and m._profile_level_lbl.text.begins_with("Level ")
	return [ok and card_ok, "level(0/49/50/120)=%d/%d/%d/%d into=%d card='%s'" % [GameData.level_for_kills(0), GameData.level_for_kills(49), GameData.level_for_kills(50), GameData.level_for_kills(120), GameData.kills_into_level(120), m._profile_level_lbl.text]]


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
	var room := {"room_name": "Test Room", "host_name": "Host", "players": 2, "max_players": 8, "map_id": 4, "mode": 1, "status": "lobby", "port": 7777, "private": true}
	var pkt := LanDiscovery.build_room_packet(room)
	var back := LanDiscovery.parse_room_packet(pkt.get_string_from_utf8(), "192.168.1.7")
	var ok: bool = back["room_name"] == "Test Room" and back["host_name"] == "Host" and int(back["players"]) == 2 and int(back["max_players"]) == 8 and int(back["map_id"]) == 4 and int(back["mode"]) == 1 and back["status"] == "lobby" and int(back["port"]) == 7777 and bool(back["private"]) and back["ip"] == "192.168.1.7"
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
	m.menu_net.join_game("999.999.999.999")


func _mnt_c_bad_ip() -> Array:
	# Either create_client rejects the bad address at once, or the
	# join attempt is in progress with a clear status — both are a
	# visible error path, never a silent hang.
	var status = m._status.text
	var ok: bool = status != "" and ("Could not connect" in status or "Could not reach" in status or "Connecting to" in status)
	if m._joining or m.multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		m.menu_net._close_peer()
		m.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		m._peer = null
		m._joining = false
	return [ok, "status after bad IP: '%s'" % status]


func _mnt_s_create_room() -> void:
	GameData.room_name = "MenuTest"
	GameData.max_players = 4
	GameData.room_private = false
	GameData.room_password = ""
	m._room_name_input.text = "MenuTest"
	m.menu_net._create_room()


func _mnt_c_create_room() -> Array:
	var ip := LanDiscovery.lan_ip()
	var label_ok = m._host_ip_label.visible
	if ip != "":
		label_ok = label_ok and ip in m._host_ip_label.text
	else:
		label_ok = label_ok and "No Wi-Fi IP" in m._host_ip_label.text
	var ok: bool = m._is_host and m.multiplayer.is_server() and m._lobby_panel.visible and m._lobby_players.size() == 1 and label_ok
	return [ok, "host=%s server=%s lobby visible=%s players=%d host-ip label ok=%s (lan_ip='%s')" % [m._is_host, m.multiplayer.is_server(), m._lobby_panel.visible, m._lobby_players.size(), label_ok, ip]]


func _mnt_s_ready() -> void:
	m.menu_net._on_ready_pressed()


func _mnt_c_ready() -> Array:
	var my_id = m.multiplayer.get_unique_id()
	var ready: bool = bool(m._lobby_players.get(my_id, {}).get("ready", false))
	return [ready, "own ready state after toggle: %s (want true)" % ready]


func _mnt_s_leave() -> void:
	m.menu_net._leave_lobby()
	m.menu_ui._show_only(m._mp_panel)


func _mnt_c_leave() -> Array:
	var ok: bool = not m._is_host and m._lobby_players.is_empty() and m._mp_panel.visible
	return [ok, "left cleanly: host=%s players=%d mp panel visible=%s" % [m._is_host, m._lobby_players.size(), m._mp_panel.visible]]


func _update_flowtest(delta: float) -> void:
	if m._flow_done:
		return
	if m._flow_steps.is_empty():
		_flowtest_build_steps()
		m._flow_step = 0
		m._flow_in_step = false
		m._flow_timer = 0.0
	if m._flow_step >= m._flow_steps.size():
		m._flow_done = true
		print("FLOWTEST MENU: %d/%d passed" % [m._flow_passed, m._flow_passed + m._flow_failed])
		return
	var step: Dictionary = m._flow_steps[m._flow_step]
	if not m._flow_in_step:
		(step["setup"] as Callable).call()
		m._flow_in_step = true
		m._flow_timer = float(step["wait"])
	m._flow_timer -= delta
	if m._flow_timer <= 0.0:
		var result: Array = (step["check"] as Callable).call()
		var ok: bool = bool(result[0])
		if ok:
			m._flow_passed += 1
		else:
			m._flow_failed += 1
		print("FLOWTEST %s: %s — %s" % [String(step["name"]), "PASS" if ok else "FAIL", String(result[1])])
		m._flow_step += 1
		m._flow_in_step = false
		m._flow_timer = 0.0


# QA-112 (v3.9): test-only fake lobby players (flow test /
# restart test). Same dictionary shape as _my_lobby_info, fixed
# ids 9001+ so adding twice just overwrites instead of duplicating.
func _add_fake_lobby_players(red: int, blue: int) -> void:
	var n := 0
	for i in red:
		n += 1
		m._lobby_players[9000 + n] = {"name": "FakeRed%d" % n, "color": 0, "portrait": 0, "ready": true, "vote": -1, "team": 0, "role": 0}
	for i in blue:
		n += 1
		m._lobby_players[9000 + n] = {"name": "FakeBlue%d" % (n - red), "color": 1, "portrait": 0, "ready": true, "vote": -1, "team": 1, "role": 0}


func _flowtest_build_steps() -> void:
	m._flow_steps = [
		{"name": "MENU-VISIBLE", "wait": 0.3, "setup": _flm_s_noop, "check": _flm_c_menu},
		{"name": "CREATE-ROOM", "wait": 0.5, "setup": _flm_s_create, "check": _flm_c_lobby},
		{"name": "MIN-START-SOLO", "wait": 0.3, "setup": _flm_s_noop, "check": _flm_c_min_solo},
		{"name": "MIN-START-CASES", "wait": 0.3, "setup": _flm_s_noop, "check": _flm_c_min_cases},
		{"name": "MIN-START-3V2", "wait": 0.3, "setup": _flm_s_half_full, "check": _flm_c_half_full},
		{"name": "START-MATCH", "wait": 0.3, "setup": _flm_s_start, "check": _flm_c_started},
	]


func _flm_s_noop() -> void:
	pass


func _flm_c_menu() -> Array:
	var ok: bool = m._menu_panel.visible
	m._capture_flow_shot_now("user://shot_menu.png")
	return [ok, "main menu visible=%s" % m._menu_panel.visible]


func _flm_s_create() -> void:
	GameData.room_name = "FlowTest"
	GameData.max_players = 4
	GameData.room_private = false
	GameData.room_password = ""
	m._room_name_input.text = "FlowTest"
	m.menu_net._create_room()


func _flm_c_lobby() -> Array:
	var ip := LanDiscovery.lan_ip()
	var label_ok = m._host_ip_label.visible and (ip == "" or ip in m._host_ip_label.text)
	var ok: bool = m._lobby_panel.visible and m._is_host and label_ok
	m._capture_flow_shot_now("user://shot_lobby.png")
	return [ok, "lobby visible=%s host=%s host-ip label ok=%s (lan_ip='%s')" % [m._lobby_panel.visible, m._is_host, label_ok, ip]]


func _flm_s_start() -> void:
	# QA-112 (v3.9): the 5 fake players (3 RED, 2 BLUE) from the
	# MIN-START-3V2 step are still in the room; re-adding is a
	# no-op (fixed ids), so START runs from a half-full room.
	_add_fake_lobby_players(3, 2)
	# Hand over to the game scene: it runs the rest of the check.
	GameData.flow_test = true
	GameData.flow_phase = 1
	m.menu_net._on_start_pressed()


func _flm_c_started() -> Array:
	# The scene change happens in start_match; this check is only
	# reached if the match did not start.
	return [false, "still in the menu after START MATCH"]


func _flm_c_min_solo() -> Array:
	# QA-112 (v3.9): solo host (1 player) — START disabled, says why.
	var ok: bool = not m.menu_lobby_setup._start_minimum_met() and m._lobby_start_btn.disabled and m._lobby_start_btn.text == "NEED 2 PLAYERS"
	return [ok, "min met=%s btn disabled=%s text='%s'" % [m.menu_lobby_setup._start_minimum_met(), m._lobby_start_btn.disabled, m._lobby_start_btn.text]]


func _flm_s_half_full() -> void:
	# QA-112 (v3.9): half-full room — 5 fake players (3 RED, 2 BLUE)
	# on top of the host. START must work without full teams (5v5 = 10).
	_add_fake_lobby_players(3, 2)
	m.menu_lobby_setup._refresh_lobby_buttons()


func _flm_c_half_full() -> Array:
	# QA-112 (v3.9): half-full room — minimum met, START enabled.
	var ok: bool = m.menu_lobby_setup._start_minimum_met() and not m._lobby_start_btn.disabled and m._lobby_players.size() == 6
	return [ok, "players=%d min met=%s btn disabled=%s text='%s'" % [m._lobby_players.size(), m.menu_lobby_setup._start_minimum_met(), m._lobby_start_btn.disabled, m._lobby_start_btn.text]]


func _flm_min_case(mode: int, teams: Array, want_met: bool, want_reason: String) -> String:
	GameData.game_mode = mode
	m._lobby_players.clear()
	var n := 0
	for t in teams:
		n += 1
		m._lobby_players[8000 + n] = {"name": "Case%d" % n, "color": 0, "portrait": 0, "ready": true, "vote": -1, "team": int(t), "role": 0}
	var got_met = m.menu_lobby_setup._start_minimum_met()
	var got_reason = m.menu_lobby_setup._start_minimum_reason()
	if got_met != want_met or got_reason != want_reason:
		return "mode %d teams %s: met=%s reason='%s' (want met=%s reason='%s')" % [mode, str(teams), got_met, got_reason, want_met, want_reason]
	return ""


func _flm_c_min_cases() -> Array:
	# QA-112 (v3.9): direct rule cases on temp lobby state; the real
	# room (solo host) and mode are restored before returning.
	var saved_players: Dictionary = m._lobby_players.duplicate()
	var saved_mode: int = GameData.game_mode
	var failures: Array[String] = []
	for args in [
		[0, [], false, "NEED 2 PLAYERS"],
		[0, [0], false, "NEED 2 PLAYERS"],
		[0, [0, 1], true, ""],
		[1, [0, 0], false, "NEED RED + BLUE"],
		[1, [0, 1], true, ""],
		[1, [0, -1], true, ""],
		[1, [-1, -1], true, ""],
		[1, [0, 0, 0, 1, 1], true, ""],
		[4, [0, 0], false, "NEED RED + BLUE"],
		[4, [0, 1], true, ""],
	]:
		var err := _flm_min_case(int(args[0]), args[1], bool(args[2]), String(args[3]))
		if err != "":
			failures.append(err)
	m._lobby_players = saved_players
	GameData.game_mode = saved_mode
	m.menu_lobby_setup._refresh_lobby_buttons()
	if failures.is_empty():
		return [true, "10/10 minimum cases pass (FFA/TDM/CTF, incl. AUTO fills either side)"]
	return [false, "; ".join(failures)]


func _restarttest_begin() -> void:
	GameData.room_name = "RestartTest"
	GameData.max_players = 4
	GameData.room_private = false
	GameData.room_password = ""
	m._room_name_input.text = "RestartTest"
	m.menu_net._create_room()
	GameData.restart_phase = 1
	# QA-112 (v3.9): solo host cannot start any more (2-player
	# minimum) — the restart test is about restarting, not the
	# minimum, so it runs from a half-full room like the flow test.
	_add_fake_lobby_players(3, 2)
	m.menu_net._on_start_pressed()


func _restarttest_second_start() -> void:
	GameData.room_name = "RestartTest2"
	GameData.max_players = 4
	GameData.room_private = false
	GameData.room_password = ""
	m._room_name_input.text = "RestartTest2"
	m.menu_net._create_room()
	var ok: bool = m._lobby_panel.visible and m._is_host
	if ok:
		GameData.restart_passed += 1
	else:
		GameData.restart_failed += 1
	print("RESTARTTEST %s: %s" % ["SECOND-LOBBY", "PASS" if ok else "FAIL"])
	GameData.restart_phase = 3
	# QA-112 (v3.9): same as _restarttest_begin — half-full room so
	# the 2-player minimum is met.
	_add_fake_lobby_players(3, 2)
	m.menu_net._on_start_pressed()


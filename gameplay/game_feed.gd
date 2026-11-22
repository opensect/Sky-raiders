class_name GameFeed
extends RefCounted


# QA-140 (v3.15): extracted from game.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `g` (dependency injection).


var g # the owner (game.gd)


func _init(owner) -> void:
	g = owner


# Host-side kill-credit lock (QA-031, T-56). Called by the host only,
# from bullet.gd _hit_player and request_explosion, when a hit is
# computed lethal. Returns true only for the FIRST credit for this
# victim inside the lock window: the kill is awarded to the killer
# (self-kills excluded, as before) and the kill feed is announced
# exactly once. A second lethal hit in the same window returns false
# and credits/announces nothing — no double kill, no double feed
# line. After the window expires a new credit is allowed again, so
# the victim's next life is unaffected.
func try_credit_kill(killer_id: int, victim_id: int, weapon_id: int) -> bool:
	if not g.multiplayer.is_server():
		return false
	var now := Time.get_ticks_msec()
	if g._kill_credit_lock.has(victim_id):
		if now - int(g._kill_credit_lock[victim_id]) < g.KILL_CREDIT_LOCK_MS:
			return false
	g._kill_credit_lock[victim_id] = now
	if killer_id != victim_id:
		var killer = g.players_node.get_node_or_null(str(killer_id))
		if killer != null:
			if killer.get_multiplayer_authority() == g.multiplayer.get_unique_id():
				killer.add_kill()
			elif g.multiplayer.get_peers().has(killer.get_multiplayer_authority()):
				killer.rpc_id(killer.get_multiplayer_authority(), "add_kill")
	g.rpc("announce_kill", killer_id, victim_id, weapon_id)
	return true


func clear_kill_credit(peer_id: int) -> void:
	g._kill_credit_lock.erase(peer_id)


func announce_kill(killer_id: int, victim_id: int, weapon_id: int) -> void:
	# Only the host announces kills (it decided the damage).
	var sender = g.multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	# Streaks: every peer tracks them from the same feed, so the end
	# screen agrees everywhere.
	if killer_id > 0 and killer_id != victim_id:
		var s = int(g._kill_streaks.get(killer_id, 0)) + 1
		g._kill_streaks[killer_id] = s
		g._best_streaks[killer_id] = maxi(int(g._best_streaks.get(killer_id, 0)), s)
		# QA-145 (v4.1, Worker T): First Blood + multi-kill callouts.
		# The streaks were already tracked (and shown on the end
		# screen) but never announced mid-match — a 2nd/3rd kill in
		# a row without dying now gets its own gold feed line, and
		# the very first real kill of the match gets FIRST BLOOD.
		# Feed-only: no scores, no rules change. announce_kill
		# runs on every peer from the same RPC, so every phone
		# shows the same line.
		if not g._first_blood_done:
			g._first_blood_done = true
			g._ctf_feed("FIRST BLOOD! %s drew first blood!" % g.game_match._player_name(killer_id), Color(1.0, 0.85, 0.3))
		var callout := ""
		if s == 2:
			callout = "DOUBLE KILL!"
		elif s == 3:
			callout = "TRIPLE KILL!"
		elif s == 4:
			callout = "RAMPAGE!"
		elif s >= 5:
			callout = "UNSTOPPABLE!"
		if callout != "":
			g._ctf_feed("%s %s — %d in a row!" % [callout, g.game_match._player_name(killer_id), s], Color(1.0, 0.85, 0.3))
	g._kill_streaks[victim_id] = 0
	# Mark this death as fed so the host's death watcher (lava, falls,
	# anything without a killer) does not post a second line for it.
	g._fed_deaths[victim_id] = true
	_add_kill_feed_entry(killer_id, victim_id, weapon_id)


func _add_kill_feed_entry(killer_id: int, victim_id: int, weapon_id: int) -> void:
	if g._kill_feed_list == null:
		return
	var victim_name = g.game_match._player_name(victim_id)
	var text := ""
	if killer_id == 0:
		text = "☠ %s died" % victim_name
	elif killer_id == victim_id:
		text = "%s blew themself up" % victim_name
	else:
		text = "%s  ☠  %s   —  %s" % [g.game_match._player_name(killer_id), victim_name, _kill_feed_weapon_text(weapon_id)]
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", g.FONT_BODY_MEDIUM)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", g.UI_FONT)
	g._outline_label(lbl)
	# QA-130 (v3.11): feed chips restyled to the gohud pill look
	# (same dark navy + rounded corners as the top-right pill and
	# the slot panel) so the message area reads as one clean unit.
	# QA-145 (Worker F): the chip wears the UI-frames blue bar now
	# (same content margins as before; nothing else changed here).
	var chip := PanelContainer.new()
	var chip_bg: StyleBoxTexture = g.hud_builder._ui_frame_stylebox(g.hud_builder.TEX_UI_BAR_BLUE_MED, 12, 10, 10, 4, 4)
	chip.add_theme_stylebox_override("panel", chip_bg)
	chip.add_child(lbl)
	g._kill_feed_list.add_child(chip)
	g._kill_feed_entries.append({"label": lbl, "panel": chip, "expiry": 5.0})
	while g._kill_feed_entries.size() > 4:
		var old: Dictionary = g._kill_feed_entries.pop_front()
		(old["panel"] as PanelContainer).queue_free()


func _update_kill_feed(delta: float) -> void:
	if g._kill_feed_entries.is_empty():
		return
	var kept: Array = []
	for e in g._kill_feed_entries:
		var d: Dictionary = e
		d["expiry"] = float(d["expiry"]) - delta
		if float(d["expiry"]) <= 0.0:
			# Free the whole chip (the label goes with it).
			if d.has("panel"):
				(d["panel"] as PanelContainer).queue_free()
			else:
				(d["label"] as Label).queue_free()
		else:
			kept.append(d)
	g._kill_feed_entries = kept


func _kill_feed_weapon_text(weapon_id: int) -> String:
	if weapon_id >= 0:
		return String(WeaponData.get_weapon(weapon_id).get("name", "Rifle"))
	if weapon_id == -2:
		return "Grenade"
	return "Explosion"


func _update_death_watcher() -> void:
	# Host only: a death with no killer (lava, barrel chain with no
	# shooter, anything the bullet/explosion paths did not announce)
	# still deserves one feed line — but never a second line for a
	# death announce_kill already covered (see _fed_deaths).
	if not g.multiplayer.is_server() or g.match_over:
		return
	for child in g.players_node.get_children():
		var pid: int = child.peer_id
		if child.alive:
			g._alive_watch[pid] = true
			g._fed_deaths.erase(pid)
		elif bool(g._alive_watch.get(pid, true)):
			g._alive_watch[pid] = false
			if not g._fed_deaths.has(pid):
				# QA-069: an uncredited death (lava, barrel chain
				# with no shooter) still locks the victim for the
				# QA-031 window. Without this, a stale in-flight
				# bullet could credit a kill for a corpse while
				# the host's copy still showed them alive — the
				# shooter gains a kill for a lava death.
				g._kill_credit_lock[pid] = Time.get_ticks_msec()
				g.rpc("announce_kill", 0, pid, -1)


func _show_hitmarker(dmg: int, pos: Vector2, lethal: bool) -> void:
	# Centre cross (red on a lethal hit) + a floating damage number
	# at the hit point in the world.
	if g._hitmarker_label != null:
		g._hitmarker_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2) if lethal else Color(1, 1, 1))
		g._hitmarker_label.visible = true
		g._hitmark_timer = 0.18
	var num := Label.new()
	num.text = str(dmg)
	num.position = pos + Vector2(-14, -30)
	num.add_theme_font_size_override("font_size", 22)
	num.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2) if lethal else Color(1.0, 0.85, 0.3))
	num.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	num.add_theme_constant_override("outline_size", 4)
	g.fx_node.add_child(num)
	var tw = g.create_tween()
	tw.tween_property(num, "position:y", num.position.y - 44.0, 0.7)
	tw.parallel().tween_property(num, "modulate:a", 0.0, 0.7)
	tw.tween_callback(num.queue_free)


func _update_hitmarker(delta: float) -> void:
	if g._hitmark_timer > 0.0:
		g._hitmark_timer -= delta
		if g._hitmark_timer <= 0.0 and g._hitmarker_label != null:
			g._hitmarker_label.visible = false


func _spectate_targets() -> Array:
	var out: Array = []
	for child in g.players_node.get_children():
		if child.alive and child.get_multiplayer_authority() != g.multiplayer.get_unique_id():
			out.append(child)
	return out


func _update_spectator(delta: float) -> void:
	# Phase 4 (stretch) — Survival/LMS only: after death, watch a
	# living player instead of staring at your own corpse. The
	# spectate camera takes over; respawning hands it back.
	if g.game_mode != 2 and g.game_mode != 3:
		return
	var lp = g._get_local_player()
	if lp == null or g.match_over:
		if g._spectating:
			_stop_spectating()
		return
	if lp.alive:
		if g._spectating:
			_stop_spectating()
		return
	var targets := _spectate_targets()
	if targets.is_empty():
		g._spectate_label.text = "Eliminated! Waiting for the round to end..."
		g._spectate_label.visible = true
		g._spectate_next_btn.visible = false
		if g._spectate_cam != null:
			g._spectate_cam.enabled = false
		g._spectating = false
		return
	g._spectating = true
	if g._spectate_target == null or not is_instance_valid(g._spectate_target) or not g._spectate_target.alive:
		g._spectate_idx = 0
		g._spectate_target = targets[0]
	g._spectate_cam.enabled = true
	g._spectate_cam.make_current()
	# Smooth-follow the target (no teleport snapping).
	g._spectate_cam.global_position = g._spectate_cam.global_position.lerp(g._spectate_target.global_position, clampf(delta * 8.0, 0.0, 1.0))
	g._spectate_label.text = "SPECTATING: %s  —  you are out" % String(g._spectate_target.player_name)
	g._spectate_label.visible = true
	g._spectate_next_btn.visible = targets.size() > 1


func _on_spectate_next_pressed() -> void:
	var targets := _spectate_targets()
	if targets.is_empty():
		return
	g._spectate_idx = (g._spectate_idx + 1) % targets.size()
	g._spectate_target = targets[g._spectate_idx]
	if g._spectate_cam != null and g._spectate_target != null:
		g._spectate_cam.global_position = g._spectate_target.global_position


func _stop_spectating() -> void:
	g._spectating = false
	g._spectate_target = null
	if g._spectate_cam != null:
		g._spectate_cam.enabled = false
	if g._spectate_label != null:
		g._spectate_label.visible = false
	if g._spectate_next_btn != null:
		g._spectate_next_btn.visible = false
	var lp = g._get_local_player()
	if lp != null and lp._camera != null:
		lp._camera.make_current()


func _stop_broadcast() -> void:
	# QA-060: close the room-announcement sockets explicitly (leave
	# / scene change). PacketPeerUDP is RefCounted so the sockets
	# close when the last reference drops, but an explicit close
	# means a re-host in the same process never finds the port busy.
	for s in g._udp_broadcast_sockets:
		if s != null:
			s.close()
	g._udp_broadcast_sockets.clear()
	g._udp_broadcast = null


func _start_broadcast() -> void:
	# Announce the room on every broadcast address (limited + subnet),
	# so clients find it on routers and hotspots that drop 255.255.255.255.
	g._udp_broadcast = PacketPeerUDP.new()
	g._udp_broadcast.set_broadcast_enabled(true)
	g._udp_broadcast.set_dest_address("255.255.255.255", g.DISCOVERY_PORT)
	var subnets := LanDiscovery.broadcast_addresses()
	g._udp_broadcast_sockets.clear()
	g._udp_broadcast_sockets.append(g._udp_broadcast)
	for addr in subnets:
		if addr == "255.255.255.255":
			continue
		var s := PacketPeerUDP.new()
		s.set_broadcast_enabled(true)
		s.set_dest_address(addr, g.DISCOVERY_PORT)
		g._udp_broadcast_sockets.append(s)


func _room_card() -> Dictionary:
	return {
		"room_name": GameData.room_name,
		"host_name": GameData.player_name,
		"players": g.players_node.get_child_count(),
		"max_players": g.max_players,
		"map_id": g.map_id,
		"mode": g.game_mode,
		"status": "playing" if not g.match_over else "playing",
		"port": g.PORT,
		"private": GameData.room_private,
	}


func _update_broadcast(delta: float) -> void:
	if g._udp_broadcast == null:
		return
	g._broadcast_timer += delta
	if g._broadcast_timer >= 1.0:
		g._broadcast_timer = 0.0
		var pkt := LanDiscovery.build_room_packet(_room_card())
		for s in g._udp_broadcast_sockets:
			s.put_packet(pkt)


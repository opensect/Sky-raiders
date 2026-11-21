class_name GameHud
extends RefCounted


# QA-140 (v3.15): extracted from game.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `g` (dependency injection).


var g # the owner (game.gd)


func _init(owner) -> void:
	g = owner


func _cut_accent_stylebox() -> GoStyleBoxCut:
	return g.hud_builder._cut_accent_stylebox()


func _outline_label(l: Label) -> void:
	g.hud_builder._outline_label(l)


func _update_hud(delta: float) -> void:
	var lp = _get_local_player()
	var count = g.players_node.get_child_count()
	g.players_label.text = "Players: %d/%d" % [count, g.max_players] # v3.4: room max (was MAX_PLAYERS=12, so a default 8-player room wrongly showed "2/12")
	# Timer (THEME_SPEC.md §3): ice normally, amber under 30 s,
	# danger red under 10 s.
	var t = int(maxf(0.0, g._time_left))
	g.timer_label.text = "%d:%02d" % [t / 60, t % 60]
	g.timer_label.add_theme_color_override("font_color", g.UI_DANGER if t < 10 else (g.UI_WARNING if t < 30 else g.UI_FONT))
	if g.game_mode == 1:
		var red := 0
		var blue := 0
		for child in g.players_node.get_children():
			if child.team == 0:
				red += child.kills
			elif child.team == 1:
				blue += child.kills
		g.score_label.text = "RED %d  -  %d BLUE" % [red, blue]
	elif g.game_mode == 4:
		# QA-112 (v3.9): CTF scores captures, not kills.
		g.score_label.text = "⚑ RED %d  -  %d BLUE" % [int(g._ctf_scores.get(0, 0)), int(g._ctf_scores.get(1, 0))]
	else:
		g.score_label.text = "First to %d kills" % g.kill_limit
	# QA-112 (v3.9): flag status + power-up slots (Skyfall only).
	_update_skyfall_hud()
	# Phase 5 — centre weapon status: "SNIPER HERE" while the pinned
	# centre pickup is live, else a countdown to the next one.
	if g._centre_label != null:
		var centre_active := false
		var centre_kind := 0
		for child in g.pickups_node.get_children():
			if int(child.get("spot_index")) == 3:
				centre_active = true
				centre_kind = int(child.get("kind"))
		if centre_active:
			var cname := "SNIPER" if centre_kind == 3 else "ROCKET" if centre_kind == 4 else "WEAPON"
			g._centre_label.text = "CENTRE: %s HERE" % cname
		else:
			var next_name := "WEAPON"
			if g.multiplayer.is_server():
				next_name = "SNIPER" if g._centre_kind_next == 3 else "ROCKET"
			var cdown = int(ceil(maxf(0.0, float(g._pickup_spot_timers.get(3, 0.0)))))
			g._centre_label.text = "CENTRE: %s in %ds" % [next_name, cdown]
	# v2.2 control hint: visible until 10 s after the local player spawns.
	if g.hint_label != null:
		if lp != null:
			g._hint_timer -= delta
		g.hint_label.visible = g._hint_timer > 0.0
	if lp == null:
		if not g._join_failed:
			g.message_label.text = "Connecting..." if g.multiplayer.is_server() == false else "Starting..."
		return
	g.hp_bar.set_values(lp.health, 100, false)
	g.fuel_bar.set_values(lp.fuel, PhysicsConfig.FUEL_MAX, false) # QA-132: max is 405, not 100
	# QA-079: the bars change colour with the value, so a glance
	# reads the state without reading the number — HP green >
	# amber > red, fuel cyan > amber when nearly empty.
	g.hp_bar.ink = g.UI_SUCCESS if lp.health >= 50 else (g.UI_WARNING if lp.health >= 25 else g.UI_DANGER)
	g.fuel_bar.ink = g.UI_ACCENT if lp.fuel >= PhysicsConfig.FUEL_MAX * 0.3 else g.UI_WARNING # QA-132: 30% of the 405 tank
	g.kills_label.text = "Kills: %d" % lp.kills
	g.deaths_label.text = "Deaths: %d" % lp.deaths
	if g._kd_label != null:
		g._kd_label.text = "K %d • D %d" % [lp.kills, lp.deaths]
	g.weapon_icon.texture = GameAssets.WEAPON_ICONS[lp.weapon]
	var wname: String = lp.WEAPONS[lp.weapon]["name"]
	var mag_total: int = int(lp.WEAPONS[lp.weapon]["mag"])
	var res: int = lp.ammo_reserve()
	var res_txt := "∞" if res < 0 else str(res)
	if lp.reloading:
		g.weapon_label.text = "%s - reloading %d%%" % [wname, int(lp.reload_progress() * 100.0)]
	else:
		g.weapon_label.text = "%s %d/%s" % [wname, lp.mag_ammo, res_txt]
	# QA-079: the ammo line turns red when the magazine is nearly
	# empty, so a low mag reads at a glance mid-fight.
	g.weapon_label.add_theme_color_override("font_color", g.UI_DANGER if lp.mag_ammo <= maxi(1, mag_total / 4) else g.UI_FONT)
	g._update_reload_button(lp) # QA-070: simple reload button (text label, no ring)
	g._update_ping_button(lp) # QA-114: PING button (Skyfall only)
	g.grenade_label.text = "Grenades: %d" % lp.grenades
	g._update_grenade_button(lp) # QA-070: simple grenade button (text label, no ring/badge)
	# Phase 4: FPS counter (settings toggle).
	if g.fps_label != null:
		g.fps_label.visible = GameData.show_fps
		if GameData.show_fps:
			g.fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	# Phase 4: hitmarker — the host confirmed a hit for the local player.
	if lp._hitmark_seq != g._last_hitmark_seq:
		g._last_hitmark_seq = lp._hitmark_seq
		g.game_feed._show_hitmarker(lp._hitmark_dmg, lp._hitmark_pos, lp._hitmark_lethal)
	if g.match_over:
		g.message_label.text = ""
	elif not lp.alive:
		g.message_label.text = "Eliminated! Respawning..."
	elif count < 2:
		if g.multiplayer.is_server():
			g.message_label.text = "Waiting for other players - share your IP!"
		else:
			g.message_label.text = "Waiting for other players..."
	else:
		g.message_label.text = ""


func _get_local_player():
	if g._local_player != null and is_instance_valid(g._local_player):
		return g._local_player
	for child in g.players_node.get_children():
		if child.get_multiplayer_authority() == g.multiplayer.get_unique_id():
			g._local_player = child
			return child
	return null


func _update_skyfall_hud() -> void:
	# QA-112 (v3.9): CTF flag status + power-up slots. Everything
	# here hides itself off Skyfall / outside CTF.
	var is_sf = g.map_id == GameData.SKYFALL_MAP_ID
	var is_ctf = g.game_mode == 4 and not g._ctf_flags.is_empty()
	for i in g._ctf_flag_labels.size():
		var fl: Label = g._ctf_flag_labels[i]
		fl.visible = is_ctf
		if is_ctf and i < g._ctf_flags.size():
			var d: Dictionary = g._ctf_flags[i]
			var team_name := "RED" if i == 0 else "BLUE"
			var carrier := int(d.get("carrier", -1))
			if carrier >= 0:
				fl.text = "⚑ %s: carried by %s" % [team_name, g.game_match._player_name(carrier)]
			elif bool(d.get("dropped", false)):
				fl.text = "⚑ %s: DROPPED" % team_name
			else:
				fl.text = "⚑ %s: at summit" % team_name
	if g._sf_slot_panel != null:
		g._sf_slot_panel.visible = is_sf
	if g._sf_active_boost_label != null:
		g._sf_active_boost_label.visible = false
	if g._invis_warning_chip != null:
		g._invis_warning_chip.visible = false
	if not is_sf:
		return
	var lp = _get_local_player()
	if lp == null:
		return
	# 3 slots: a filled slot shows the stored power-up's icon,
	# an empty one its numbered background. A slot button is
	# tappable only when it holds a power-up the player CAN use
	# right now: timed kinds stay greyed out while another boost
	# is active or while carrying the flag (carrier rule wins);
	# instant kinds (wind, thunder) are always tappable.
	var stored: Array = lp.get("stored_boosts")
	var ab0 := int(lp.get("active_boost_kind"))
	var carrying := int(lp.get("carrying_flag")) != 0
	for i in g._sf_slot_buttons.size():
		var btn: Button = g._sf_slot_buttons[i]
		if i < stored.size():
			var kind := int(stored[i])
			btn.icon = GameAssets.SF_TEX_PU64.get(kind, GameAssets.SF_TEX_SLOT[i])
			var timed := kind in [8, 9, 10, 13]
			btn.disabled = timed and (ab0 != 0 or carrying)
		else:
			btn.icon = GameAssets.SF_TEX_SLOT[i]
			btn.disabled = true
	# Active boost: name + seconds left (one active at a time).
	var ab := ab0
	if ab != 0:
		var t := 0.0
		var nm := ""
		match ab:
			8:
				t = float(lp.get("shield_timer"))
				nm = "Shield"
			9:
				t = float(lp.get("speed_timer"))
				nm = "Speed"
			10:
				t = float(lp.get("jetpack_boost_timer"))
				nm = "Jetpack Boost"
			13:
				t = float(lp.get("invisibility_timer"))
				nm = "Invisible"
		if t > 0.0 and g._sf_active_boost_label != null:
			g._sf_active_boost_label.text = "%s %ds" % [nm, int(ceil(t))]
			g._sf_active_boost_label.visible = true
	# QA-121 (v3.11): red invisibility warning — while ANY living
	# enemy is invisible, a red chip sits at the top of the
	# top-left message area; it clears the moment the 10 s ends.
	g._update_invis_warning(lp)
	# QA-114 (v3.9): comeback + event lines (CTF, both teams see them).
	if g._sf_comeback_label != null:
		var trail = g._sf_trailing_team()
		g._sf_comeback_label.visible = is_sf and g.game_mode == 4 and trail >= 0
		if g._sf_comeback_label.visible:
			g._sf_comeback_label.text = "COMEBACK: %s gets help — elevator + extra power-ups" % ("RED" if trail == 0 else "BLUE")
	if g._sf_event_label != null:
		var ev_txt := ""
		if g._sf_event_active == "route_shift":
			ev_txt = "EVENT: ROUTE SHIFT — wind reversed! %ds" % int(ceil(g._sf_event_time_left))
		elif g._sf_event_active != "":
			ev_txt = "EVENT: %s!" % g._sf_event_active.to_upper().replace("_", " ")
		elif g._sf_storm_active:
			ev_txt = "SUMMIT STORM! %ds" % int(ceil(g._sf_storm_time_left))
		g._sf_event_label.visible = is_sf and ev_txt != ""
		g._sf_event_label.text = ev_txt
	# QA-114 (v3.9): height bar — live dots for every living player
	# (white = you, red/blue = teams) + gold diamonds for pings.
	if g._sf_height_bar != null:
		g._sf_height_bar.visible = is_sf and not g.match_over
		if g._sf_height_bar.visible:
			var my_id = g.multiplayer.get_unique_id()
			var di := 0
			for child in g.players_node.get_children():
				if di >= g._sf_height_dots.size():
					break
				var dot: ColorRect = g._sf_height_dots[di]
				if child.alive:
					dot.visible = true
					dot.position = Vector2(11, 360.0 * clampf(child.position.y, 0.0, 10800.0) / 10800.0 - 6.0)
					if int(child.peer_id) == my_id:
						dot.color = Color(1, 1, 1)
					elif int(child.team) == 0:
						dot.color = Color(0.95, 0.3, 0.25)
					elif int(child.team) == 1:
						dot.color = Color(0.25, 0.55, 0.95)
					else:
						dot.color = Color(0.85, 0.85, 0.85)
					# QA-121: an invisible ENEMY's dot is faint
					# (10% visible, like the player) — teammates
					# keep full colour, and you always see yourself.
					if int(child.peer_id) != my_id and float(child.get("invisibility_timer")) > 0.0 and (int(lp.team) < 0 or int(child.team) != int(lp.team)):
						var faint: Color = dot.color
						faint.a = 0.25
						dot.color = faint
				else:
					dot.visible = false
				di += 1
			for j in range(di, g._sf_height_dots.size()):
				(g._sf_height_dots[j] as ColorRect).visible = false
			for pi in g._sf_height_ping_dots.size():
				var pdot: ColorRect = g._sf_height_ping_dots[pi]
				if pi < g._sf_pings.size():
					var ppos: Vector2 = (g._sf_pings[pi] as Dictionary).get("pos", Vector2.ZERO)
					pdot.visible = true
					pdot.position = Vector2(11, 360.0 * clampf(ppos.y, 0.0, 10800.0) / 10800.0 - 6.0)
				else:
					pdot.visible = false


# QA-113 (v3.9): statistics / pause redesign — clean, spacious
# gohud style (same as the v3.7/v3.8 lobby). Stats rows are aligned
# columns (rank / name / K / D / K-D / ACC) instead of one long
# string, so nothing wraps or clips at 1280x720 or 2400x1080.
# Layout only — no logic changes.
func _stats_cell(text: String, width: float, align: HorizontalAlignment, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(width, 0)
	lbl.horizontal_alignment = align
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.clip_text = true
	return lbl


func _stats_header_row(extra: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var muted := Color(0.62, 0.66, 0.72)
	row.add_child(_stats_cell("#", 40, HORIZONTAL_ALIGNMENT_CENTER, 18, muted))
	row.add_child(_stats_cell("PLAYER", 0, HORIZONTAL_ALIGNMENT_LEFT, 18, muted))
	row.get_child(1).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_stats_cell("K", 48, HORIZONTAL_ALIGNMENT_CENTER, 18, muted))
	row.add_child(_stats_cell("D", 48, HORIZONTAL_ALIGNMENT_CENTER, 18, muted))
	row.add_child(_stats_cell("K/D", 64, HORIZONTAL_ALIGNMENT_CENTER, 18, muted))
	row.add_child(_stats_cell("ACC", 56, HORIZONTAL_ALIGNMENT_CENTER, 18, muted))
	if extra != "":
		row.add_child(_stats_cell(extra, 72, HORIZONTAL_ALIGNMENT_CENTER, 18, muted))
	return row


func _stats_row(rank: int, name_txt: String, team_txt: String, kills: int, deaths: int, kd: float, acc: int, is_self: bool, color: Color, extra: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name_color := Color(1, 1, 1) if is_self else color
	row.add_child(_stats_cell(("► " if is_self else "") + str(rank), 40, HORIZONTAL_ALIGNMENT_CENTER, 20, name_color))
	var nm := Label.new()
	nm.text = name_txt + team_txt + ("  (YOU)" if is_self else "")
	nm.add_theme_font_size_override("font_size", 20)
	nm.add_theme_color_override("font_color", name_color)
	nm.clip_text = true
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(nm)
	row.add_child(_stats_cell(str(kills), 48, HORIZONTAL_ALIGNMENT_CENTER, 20, Color(0.92, 0.94, 0.96)))
	row.add_child(_stats_cell(str(deaths), 48, HORIZONTAL_ALIGNMENT_CENTER, 20, Color(0.92, 0.94, 0.96)))
	row.add_child(_stats_cell("%.2f" % kd, 64, HORIZONTAL_ALIGNMENT_CENTER, 20, Color(0.92, 0.94, 0.96)))
	row.add_child(_stats_cell("%d%%" % acc, 56, HORIZONTAL_ALIGNMENT_CENTER, 20, Color(0.92, 0.94, 0.96)))
	if extra != "":
		row.add_child(_stats_cell(extra, 72, HORIZONTAL_ALIGNMENT_CENTER, 20, Color(0.92, 0.94, 0.96)))
	return row


func _update_scoreboard_rows(list: VBoxContainer) -> void:
	for c in list.get_children():
		c.queue_free()
	var rows: Array = []
	for child in g.players_node.get_children():
		rows.append(child)
	rows.sort_custom(func(a, b) -> bool: return a.kills > b.kills)
	# Phase 4: team totals header in Team Deathmatch.
	if g.game_mode == 1:
		var red := 0
		var blue := 0
		for child in g.players_node.get_children():
			if child.team == 0:
				red += child.kills
			elif child.team == 1:
				blue += child.kills
		var totals := Label.new()
		totals.text = "RED %d  —  %d BLUE" % [red, blue]
		totals.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		totals.add_theme_font_size_override("font_size", 22)
		list.add_child(totals)
	# QA-112 (v3.9): CTF totals are captures (points), not kills.
	if g.game_mode == 4:
		var totals := Label.new()
		totals.text = "⚑ RED %d  —  %d BLUE" % [int(g._ctf_scores.get(0, 0)), int(g._ctf_scores.get(1, 0))]
		totals.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		totals.add_theme_font_size_override("font_size", 22)
		list.add_child(totals)
	list.add_child(_stats_header_row())
	list.add_child(HSeparator.new())
	var rank := 1
	var my_id = g.multiplayer.get_unique_id()
	for p in rows:
		var team_txt := ""
		if p.team == 0:
			team_txt = " [RED]"
		elif p.team == 1:
			team_txt = " [BLUE]"
		var st: Dictionary = GameData.compute_stats(p.kills, p.deaths, p._shots_fired, p._shots_hit)
		var is_self = int(p.peer_id) == my_id
		list.add_child(_stats_row(rank, p.player_name, team_txt, p.kills, p.deaths, float(st["kd"]), int(st["accuracy"]), is_self, p.player_color))
		rank += 1
		rank += 1


func _update_host_ip_label() -> void:
	if g.multiplayer.is_server():
		var ip := LanDiscovery.lan_ip()
		if ip == "":
			g.host_ip_label.text = "You are the HOST"
		else:
			g.host_ip_label.text = "You are the HOST. Your IP: " + ip
		g.host_ip_label.visible = true
	else:
		g.host_ip_label.visible = false


# QA-073: dev-only network-stats display (spec §7). Hidden by
# default; enabled with --net-stats or F3. The text refreshes 4x/s
# while visible and the function returns at once while hidden, so
# normal play pays nothing for it. RTT / packet loss come from the
# live ENet peer statistics (PEER_ROUND_TRIP_TIME is ms;
# PEER_PACKET_LOSS is scaled by PACKET_LOSS_SCALE = 65536); offline
# or solo they read "--". The rest comes from the first remote
# player's snapshot counters (player.gd get_net_stats): updates/s,
# buffer size, adaptive interpolation delay, extrapolation time,
# and the authoritative snapshot position vs the rendered position.
func set_net_stats_visible(v: bool) -> void:
	g._net_stats_visible = v
	if g._net_stats_label != null:
		g._net_stats_label.visible = v
	if v:
		g._net_stats_timer = 99.0 # refresh at once on show


func toggle_net_stats() -> void:
	set_net_stats_visible(not g._net_stats_visible)


func _update_net_stats(delta: float) -> void:
	if g._net_stats_label == null or not g._net_stats_visible:
		return
	g._net_stats_timer += delta
	if g._net_stats_timer < 0.25:
		return
	g._net_stats_timer = 0.0
	var fps := Engine.get_frames_per_second()
	var lp = _get_local_player()
	var local_txt := "(--, --)"
	if lp != null:
		local_txt = "(%d, %d)" % [int(lp.position.x), int(lp.position.y)]
	# ENet RTT / loss for the first connected peer, if any.
	var rtt_txt := "--"
	var loss_txt := "--"
	var mp = g.multiplayer.multiplayer_peer
	if mp is ENetMultiplayerPeer and not g.multiplayer.get_peers().is_empty():
		var first_peer: int = g.multiplayer.get_peers()[0]
		var epeer = (mp as ENetMultiplayerPeer).get_peer(first_peer)
		if epeer != null:
			rtt_txt = "%d ms" % int(epeer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
			loss_txt = "%.1f%%" % (float(epeer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS)) * 100.0 / 65536.0)
	var remote = null
	for child in g.players_node.get_children():
		if not child.is_local_player():
			remote = child
			break
	if remote == null:
		g._net_stats_label.text = "NET (dev) — solo, no remote players\nFPS %d | RTT %s | loss %s\nlocal %s" % [fps, rtt_txt, loss_txt, local_txt]
		return
	var st: Dictionary = remote.get_net_stats()
	var auth_pos: Vector2 = st.get("auth_pos", Vector2.ZERO)
	g._net_stats_label.text = "NET (dev) — peer %d\nFPS %d | RTT %s | loss %s\nsnap %.0f/s | lost %d dup %d ooo %d | recv %d\nbuf %d | delay %.0f ms | jitter %.0f ms | extrap %.0f ms | gap %.0f ms\nlocal %s | auth (%d, %d) | shown (%d, %d)" % [
		remote.peer_id, fps, rtt_txt, loss_txt,
		float(st.get("ups", 0.0)), int(st.get("lost", 0)), int(st.get("dup", 0)), int(st.get("ooo", 0)), int(st.get("recv", 0)),
		int(st.get("buf", 0)), float(st.get("delay_ms", 0.0)), float(st.get("jitter_ms", 0.0)),
		float(st.get("extrap_ms", 0.0)), float(st.get("gap_ms", 0.0)),
		local_txt, int(auth_pos.x), int(auth_pos.y),
		int(remote.position.x), int(remote.position.y)]


# QA-073: host-side divergence guard (spec §4, last resort). The
# host compares its rendered copy of each remote player against
# that player's newest snapshot: normal interpolation lag stays
# under ~60 px (100 ms delay x 350 px/s + clamp glide), so a gap
# over 300 px means the copy genuinely lost the client (e.g. a
# missed teleport snapshot). Only when the gap holds for 1 s AND
# the snapshot stream is still fresh (<0.2 s since the last one —
# a stale stream means the copy is dead-reckoning by design and a
# correction to an old snapshot would drag the client backwards)
# does the host RPC a correction to the client's own newest
# snapshot position. The client reconciles it (small = blend,
# large = snap) and ignores stale corrections by sequence.
func _update_divergence_check(delta: float) -> void:
	if not g.multiplayer.is_server():
		return
	if g.multiplayer.get_peers().is_empty():
		return
	g._diverge_timer += delta
	if g._diverge_timer < 0.5:
		return
	g._diverge_timer = 0.0
	var now := Time.get_ticks_msec() / 1000.0
	for child in g.players_node.get_children():
		if child.is_local_player():
			continue
		var pid: int = child.peer_id
		var gap: float = child.position.distance_to(child.sync_position)
		if gap > 300.0:
			var t: float = float(g._diverge_time.get(pid, 0.0)) + 0.5
			g._diverge_time[pid] = t
			var last_gap: float = now - child._last_snap_receipt
			if t >= 1.0 and last_gap < 0.2:
				g._diverge_corr_seq += 1
				child.rpc_id(pid, "apply_authoritative_correction", child.sync_position, child.sync_velocity, g._diverge_corr_seq)
				g._diverge_time[pid] = 0.0
		else:
			g._diverge_time[pid] = 0.0


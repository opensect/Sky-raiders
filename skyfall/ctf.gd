class_name SkyfallCtf
extends RefCounted


# QA-139 (v3.15): extracted from game.gd. This module owns no
# state of its own: every field it reads or writes lives on the
# game node and is reached through `g` (dependency injection).
# game.gd keeps a thin delegating wrapper for each function the
# rest of the game calls, so no call site had to change.


var g # the game node (game.gd)


func _init(game) -> void:
	g = game


func _ctf_team_color(team: int) -> Color:
	return Color(0.95, 0.3, 0.25) if team == 0 else Color(0.25, 0.55, 0.95)


func _ctf_flag_visual(team: int) -> Node2D:
	# Pack art (flag_red/blue.png, 256 px, real transparency) at
	# half scale, with a small team tag underneath. The dropped
	# variant swaps in when the flag is on the ground.
	var node := Node2D.new()
	node.name = "Flag%d" % team
	node.z_index = 5
	var spr := Sprite2D.new()
	spr.texture = GameAssets.SF_TEX_FLAG_RED if team == 0 else GameAssets.SF_TEX_FLAG_BLUE
	spr.scale = Vector2(0.5, 0.5)
	spr.position = Vector2(0, -64)
	node.add_child(spr)
	var tag := Label.new()
	tag.text = "RED FLAG" if team == 0 else "BLUE FLAG"
	tag.position = Vector2(-40, 6)
	tag.size = Vector2(80, 20)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 16)
	tag.add_theme_color_override("font_color", _ctf_team_color(team))
	tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	tag.add_theme_constant_override("outline_size", 4)
	node.add_child(tag)
	node.set_meta("sprite", spr)
	return node


func _build_ctf_flags() -> void:
	# One flag per team, both at the summit (map["ctf"] homes).
	# Idempotent: the features test rebuilds CTF mid-run and must
	# not stack flags.
	for f in g._ctf_flags:
		var old_node: Node = (f as Dictionary).get("node")
		if old_node != null and is_instance_valid(old_node):
			old_node.queue_free()
	g._ctf_flags.clear()
	g._ctf_scores = {0: 0, 1: 0}
	g._ctf_captures.clear()
	g._ctf_grab.clear()
	g._ctf_dropped_timer.clear()
	g._ctf_checkpoints = {0: 0, 1: 0}
	if g.game_mode != 4:
		return
	var ctf: Dictionary = g.MAPS[g.map_id].get("ctf", {})
	if ctf.is_empty():
		return
	for team in [0, 1]:
		var home: Vector2 = ctf.get("flag_red" if team == 0 else "flag_blue", Vector2(1400 + team * 800, 862))
		var node := _ctf_flag_visual(team)
		node.position = home
		g.add_child(node)
		g._ctf_flags.append({"team": team, "home": home, "pos": home, "carrier": -1, "dropped": false, "node": node, "sprite": node.get_meta("sprite")})


func _ctf_carrier_of(pid: int) -> int:
	# QA-133 (v3.12): the carrier flag MUST use player.gd's enum —
	# 0 none, 1 RED flag, 2 BLUE flag. The old code returned the
	# flag's team (0 RED / 1 BLUE) for a carrier and -1 for a
	# non-carrier, which every reader (player.gd: speed, jetpack,
	# activate_slot) treats as "carrying" when != 0. So after the
	# first 0.5 s ctf_sync, EVERY non-carrier in CTF was 15% slow,
	# jetpack-less and unable to activate ANY timed power-up — and
	# a RED-flag carrier (0) was treated as free. That is the deep
	# root cause of the user's "power-ups have no use": in a real
	# CTF match every timed tap was refused (silently, before the
	# QA-132 feed messages). The v3.11 tests never caught it —
	# they all activate synchronously in setup, before the first
	# sync rewrites the flag; the QA-132 PATH tests activate in the
	# check (after a 1 s wait) and exposed it.
	for f in g._ctf_flags:
		if int((f as Dictionary).get("carrier", -1)) == pid:
			return int((f as Dictionary).get("team", -1)) + 1 # team 0 RED -> 1, team 1 BLUE -> 2
	return 0 # not carrying


func _ctf_state() -> Array:
	var out: Array = []
	for f in g._ctf_flags:
		var d: Dictionary = f
		out.append({"team": int(d.get("team", 0)), "pos": d.get("pos"), "carrier": int(d.get("carrier", -1)), "dropped": bool(d.get("dropped", false))})
	return out


func _ctf_send_sync() -> void:
	if g._ctf_flags.is_empty():
		return
	g.rpc("ctf_sync", _ctf_state(), g._ctf_scores.duplicate(), g._ctf_checkpoints.duplicate())


func ctf_sync(state: Array, scores: Dictionary, checkpoints: Dictionary = {0: 0, 1: 0}) -> void:
	# Only the host may set flag state.
	var sender = g.multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	g._ctf_scores = scores.duplicate()
	g._ctf_checkpoints = checkpoints.duplicate()
	for i in mini(state.size(), g._ctf_flags.size()):
		var s: Dictionary = state[i]
		var f: Dictionary = g._ctf_flags[i]
		f["pos"] = s.get("pos", f.get("pos"))
		f["carrier"] = int(s.get("carrier", -1))
		f["dropped"] = bool(s.get("dropped", false))
	_ctf_update_carrying_flags()


func _ctf_update_carrying_flags() -> void:
	# Every player node carries its flag state (player.gd reads
	# carrying_flag for the 15% slowdown + no jetpack). The host
	# sets it from the flag state; clients get it from ctf_sync.
	if g.players_node == null:
		return
	for child in g.players_node.get_children():
		child.set("carrying_flag", _ctf_carrier_of(int(child.peer_id)))


func _ctf_feed(text: String, color: Color) -> void:
	# Plain-text line on the kill feed (same chip + 5 s expiry as
	# a kill line — _add_kill_feed_entry is kill-shaped, so CTF
	# gets its own small builder instead of bending that one).
	if g._kill_feed_list == null:
		return
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", g.FONT_BODY_MEDIUM)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", color)
	g._outline_label(lbl)
	var chip := PanelContainer.new()
	var chip_bg := StyleBoxFlat.new()
	chip_bg.bg_color = Color(0.03, 0.07, 0.13, 0.88)
	chip_bg.set_corner_radius_all(8)
	chip_bg.content_margin_left = 10
	chip_bg.content_margin_right = 10
	chip_bg.content_margin_top = 4
	chip_bg.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", chip_bg)
	chip.add_child(lbl)
	g._kill_feed_list.add_child(chip)
	g._kill_feed_entries.append({"label": lbl, "panel": chip, "expiry": 5.0})
	while g._kill_feed_entries.size() > 4:
		var old: Dictionary = g._kill_feed_entries.pop_front()
		(old["panel"] as PanelContainer).queue_free()


func _update_ctf(delta: float) -> void:
	if g.game_mode != 4 or g._ctf_flags.is_empty():
		return
	# Render (every peer, every frame): a carried flag rides above
	# its carrier's head; a dropped flag lies where it fell (fallen
	# art); a home flag stands at the summit.
	for f in g._ctf_flags:
		var d: Dictionary = f
		var node: Node = d.get("node")
		if node == null or not is_instance_valid(node):
			continue
		var spr: Sprite2D = d.get("sprite")
		var carrier: int = int(d.get("carrier", -1))
		if spr != null:
			if bool(d.get("dropped", false)):
				spr.texture = GameAssets.SF_TEX_FLAG_RED_DROPPED if int(d.get("team", 0)) == 0 else GameAssets.SF_TEX_FLAG_BLUE_DROPPED
			else:
				spr.texture = GameAssets.SF_TEX_FLAG_RED if int(d.get("team", 0)) == 0 else GameAssets.SF_TEX_FLAG_BLUE
		if carrier >= 0:
			var cp = g.players_node.get_node_or_null(str(carrier))
			if cp != null:
				(node as Node2D).position = cp.position + Vector2(0, -80)
				continue
		(node as Node2D).position = d.get("pos", d.get("home"))
	# Host logic only — clients never move a flag.
	if not g.multiplayer.is_server() or g.match_over or g._countdown_active:
		return
	var changed := false
	var ctf: Dictionary = g.MAPS[g.map_id].get("ctf", {})
	for f in g._ctf_flags:
		var d: Dictionary = f
		var team: int = int(d.get("team", 0))
		var carrier: int = int(d.get("carrier", -1))
		if carrier >= 0:
			var cp = g.players_node.get_node_or_null(str(carrier))
			if cp == null or not cp.alive:
				# Carrier died (or left): the flag drops where
				# they fell. Either team can recover it from here.
				d["pos"] = cp.position if cp != null else d.get("pos")
				d["carrier"] = -1
				d["dropped"] = true
				g._ctf_dropped_timer[team] = 0.0
				_ctf_feed("⚑ %s dropped the %s flag!" % [g._player_name(carrier), "RED" if team == 0 else "BLUE"], _ctf_team_color(team))
				changed = true
				continue
			# Capture: the carrier reached their OWN extraction
			# zone while their own flag is home (no capture while
			# your flag is away). The carrier stole flag `team`,
			# so their own flag is the other one (1 - team), and
			# their own extraction zone is the other side's.
			var own: Dictionary = g._ctf_flags[1 - team]
			var own_home: bool = int(own.get("carrier", -1)) == -1 and not bool(own.get("dropped", false))
			var zone: Vector2 = ctf.get("extract_red" if int(cp.team) == 0 else "extract_blue", Vector2.ZERO)
			if own_home and cp.position.distance_to(zone) < 120.0:
				var ct: int = int(cp.team)
				g._ctf_scores[ct] = int(g._ctf_scores.get(ct, 0)) + GameData.CTF_CAPTURE_POINTS
				g._ctf_captures[carrier] = int(g._ctf_captures.get(carrier, 0)) + 1
				d["pos"] = d.get("home")
				d["carrier"] = -1
				d["dropped"] = false
				_ctf_feed("⚑ %s captured the flag! +%d pts  RED %d — %d BLUE" % [g._player_name(carrier), GameData.CTF_CAPTURE_POINTS, int(g._ctf_scores.get(0, 0)), int(g._ctf_scores.get(1, 0))], _ctf_team_color(ct))
				changed = true
				g._check_match_end()
			else:
				# QA-114 (v3.9): PARTIAL SCORING — the carrier banks
				# the flag at a relay station (levels 4 / 7) for +1
				# point. The flag returns to the summit, so the run
				# ends here (no double-banking the same run); the
				# team must steal it again for the next bank or the
				# full +3 capture. This breaks stalemates: a team
				# that cannot finish the long run down still scores
				# for getting halfway.
				var relays: Array = g.MAPS[g.map_id].get("relay", [])
				for ri in relays.size():
					var rp: Vector2 = relays[ri]
					if cp.position.distance_to(rp) < 140.0:
						var ct2: int = int(cp.team)
						g._ctf_scores[ct2] = int(g._ctf_scores.get(ct2, 0)) + GameData.CTF_RELAY_POINTS
						d["pos"] = d.get("home")
						d["carrier"] = -1
						d["dropped"] = false
						var lvl := 4 if ri == 0 else 7
						_ctf_feed("⚑ %s banked the flag at the Level %d relay! +%d pt  RED %d — %d BLUE" % [g._player_name(carrier), lvl, GameData.CTF_RELAY_POINTS, int(g._ctf_scores.get(0, 0)), int(g._ctf_scores.get(1, 0))], _ctf_team_color(ct2))
						changed = true
						g._check_match_end()
						break
			continue
		# Dropped flag: 15 s unretrieved and it returns to the summit.
		if bool(d.get("dropped", false)):
			var dt = float(g._ctf_dropped_timer.get(team, 0.0)) + delta
			g._ctf_dropped_timer[team] = dt
			if dt >= 15.0:
				d["pos"] = d.get("home")
				d["dropped"] = false
				g._ctf_dropped_timer[team] = 0.0
				_ctf_feed("⚑ The %s flag returned to the summit!" % ("RED" if team == 0 else "BLUE"), _ctf_team_color(team))
				changed = true
		# Free flag: an enemy steals it with a 1.5 s hold; a
		# teammate returns a dropped flag by walking over it.
		# QA-114 (v3.9): the hold is keyed by (peer, flag) — the
		# old peer-only key was wiped every frame by the OTHER
		# flag's distance check (the player is always > 80 px from
		# one flag), so the hold never reached 1.5 s and a flag
		# could never be grabbed. The features test caught it.
		for child in g.players_node.get_children():
			if not child.alive:
				continue
			var ppos: Vector2 = child.position
			var fpos: Vector2 = d.get("pos")
			var gkey := int(child.peer_id) * 10 + team
			if ppos.distance_to(fpos) > 80.0:
				g._ctf_grab.erase(gkey)
				continue
			if bool(d.get("dropped", false)) and int(child.team) == team:
				d["pos"] = d.get("home")
				d["dropped"] = false
				g._ctf_dropped_timer[team] = 0.0
				_ctf_feed("⚑ %s returned the %s flag!" % [g._player_name(child.peer_id), "RED" if team == 0 else "BLUE"], _ctf_team_color(team))
				changed = true
				break
			if int(child.team) != team:
				# Hold 1.5 s on the flag to grab it. Moving away
				# resets the hold (the erase above, on distance).
				var held = float(g._ctf_grab.get(gkey, 0.0)) + delta
				g._ctf_grab[gkey] = held
				if held >= 1.5:
					d["carrier"] = int(child.peer_id)
					g._ctf_grab.erase(gkey)
					_ctf_feed("⚑ %s took the %s flag!" % [g._player_name(child.peer_id), "RED" if team == 0 else "BLUE"], _ctf_team_color(team))
					changed = true
				break
	if changed:
		_ctf_update_carrying_flags()
	g._ctf_sync_timer += delta
	if changed or g._ctf_sync_timer >= 0.5:
		g._ctf_sync_timer = 0.0
		_ctf_send_sync()

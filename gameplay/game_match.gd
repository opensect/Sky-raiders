class_name GameMatch
extends RefCounted


# QA-140 (v3.15): extracted from game.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `g` (dependency injection).


var g # the owner (game.gd)


func _init(owner) -> void:
	g = owner


func _update_countdown(delta: float) -> void:
	if g._fight_timer > 0.0:
		g._fight_timer -= delta
		if g._fight_timer <= 0.0:
			g._countdown_label.visible = false
			g._countdown_sub.visible = false
	if not g._countdown_active:
		return
	if g.multiplayer.is_server():
		g._countdown_t -= delta
		var n = int(ceil(g._countdown_t))
		if n != g._countdown_last_shown:
			g._countdown_last_shown = n
			g.rpc("sync_countdown", n)
		if g._countdown_t <= 0.0:
			g._countdown_active = false
			g.rpc("sync_countdown", 0)
	else:
		# Watchdog: a client that missed the host's sync (late join)
		# must never stay frozen — end the countdown locally.
		g._countdown_t -= delta
		if g._countdown_t <= 0.0:
			g._countdown_active = false
			g._fight_timer = 0.9
	_update_countdown_labels()


func _update_countdown_labels() -> void:
	if g._countdown_active:
		var n = int(ceil(maxf(g._countdown_t, 0.0)))
		g._countdown_label.text = str(maxi(n, 1))
		g._countdown_label.visible = true
		g._countdown_sub.text = _match_goal_text()
		g._countdown_sub.visible = true
	elif g._fight_timer > 0.0:
		g._countdown_label.text = "FIGHT!"
		g._countdown_label.visible = true
		g._countdown_sub.visible = false


func sync_countdown(n: int) -> void:
	# Only the host drives the countdown; a late joiner syncs to it.
	var sender = g.multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	if n > 0:
		g._countdown_active = true
		g._countdown_t = float(n)
		g._countdown_last_shown = n
	else:
		# n == 0: the fight starts. Show FIGHT! even on the host
		# (its local call runs after _countdown_active was cleared).
		g._fight_timer = 0.9
		g._countdown_active = false
		g._countdown_last_shown = 0
	_update_countdown_labels()


func _update_match_timer(delta: float) -> void:
	if g.match_over:
		return
	# Phase 4: the clock only runs once the countdown has finished.
	if g._countdown_active:
		return
	if g.multiplayer.is_server():
		g._time_left -= delta
		g._time_sync_timer += delta
		if g._time_sync_timer >= 1.0:
			g._time_sync_timer = 0.0
			g.rpc("sync_time_left", g._time_left)
		_check_match_end()


func sync_time_left(t: float) -> void:
	# Only the host may set the match clock.
	var sender = g.multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	g._time_left = t


func _check_match_end() -> void:
	if g.match_over:
		return
	# Survival (2) and Last Man Standing (3) end by elimination;
	# the round check (Survival) runs separately in _check_round_end.
	if g.game_mode == 2:
		_check_round_end()
		# A Survival match can also end on the timer: most rounds won.
		if g._time_left <= 0.0:
			_end_survival_on_time()
		return
	if g.game_mode == 3:
		var alive_count := 0
		var last_alive: Node = null
		for child in g.players_node.get_children():
			if child.alive:
				alive_count += 1
				last_alive = child
		# At least 2 players must have joined before elimination can
		# end the match (otherwise the host alone would "win" instantly).
		if g.players_node.get_child_count() >= 2 and alive_count <= 1 and last_alive != null:
			_end_match(last_alive.player_name, "is the last one standing!")
			return
		if g._time_left <= 0.0:
			_end_lms_on_time()
		return
	# QA-112 (v3.9): Capture the Flag ends on POINTS (first to
	# CTF_POINTS_LIMIT = 9), or on the timer — most points wins.
	# QA-114: full capture = 3 pts, relay bank = 1 pt, so 3 full
	# captures still win (3 x 3 = 9), but relay banks count too.
	if g.game_mode == 4:
		var red_pts: int = int(g._ctf_scores.get(0, 0))
		var blue_pts: int = int(g._ctf_scores.get(1, 0))
		if red_pts >= GameData.CTF_POINTS_LIMIT:
			_end_match("RED TEAM", "reached %d points!" % GameData.CTF_POINTS_LIMIT)
			return
		if blue_pts >= GameData.CTF_POINTS_LIMIT:
			_end_match("BLUE TEAM", "reached %d points!" % GameData.CTF_POINTS_LIMIT)
			return
		if g._time_left <= 0.0:
			if red_pts > blue_pts:
				_end_match("RED TEAM", "time up - most points wins!")
			elif blue_pts > red_pts:
				_end_match("BLUE TEAM", "time up - most points wins!")
			else:
				_end_match("DRAW", "time up - tied on points!")
			return
		return
	var winner := ""
	var reason := ""
	if g.game_mode == 0:
		for child in g.players_node.get_children():
			if child.kills >= g.kill_limit:
				winner = child.player_name
				reason = "reached %d kills!" % g.kill_limit
				break
	else:
		var red := 0
		var blue := 0
		for child in g.players_node.get_children():
			if child.team == 0:
				red += child.kills
			elif child.team == 1:
				blue += child.kills
		if red >= g.kill_limit:
			winner = "RED TEAM"
			reason = "reached %d kills!" % g.kill_limit
		elif blue >= g.kill_limit:
			winner = "BLUE TEAM"
			reason = "reached %d kills!" % g.kill_limit
	if winner == "" and g._time_left <= 0.0:
		if g.game_mode == 0:
			var best_kills := -1
			for child in g.players_node.get_children():
				if child.kills > best_kills:
					best_kills = child.kills
					winner = child.player_name
			reason = "time up - most kills wins!"
		else:
			var red := 0
			var blue := 0
			for child in g.players_node.get_children():
				if child.team == 0:
					red += child.kills
				elif child.team == 1:
					blue += child.kills
			if red > blue:
				winner = "RED TEAM"
			elif blue > red:
				winner = "BLUE TEAM"
			else:
				winner = "DRAW"
			reason = "time up!"
	if winner == "":
		return
	_end_match(winner, reason)


func _check_round_end() -> void:
	# Survival: a round ends when one player is left alive. That
	# player wins the round; first to the kill limit (rounds) wins
	# the match. Needs at least 2 players, like LMS.
	if g.players_node.get_child_count() < 2:
		return
	var alive_count := 0
	var last_alive: Node = null
	for child in g.players_node.get_children():
		if child.alive:
			alive_count += 1
			last_alive = child
	if alive_count == 1 and last_alive != null:
		var pid: int = last_alive.peer_id
		g._round_wins[pid] = int(g._round_wins.get(pid, 0)) + 1
		if int(g._round_wins[pid]) >= g.kill_limit:
			_end_match(last_alive.player_name, "won %d rounds!" % g.kill_limit)
			return
		_reset_round()


func _reset_round() -> void:
	# Next round: everyone respawns fresh (positions, health, weapons).
	g._round_number += 1
	g._kill_credit_lock.clear() # QA-031: fresh round, fresh locks
	g.rpc("reset_round_remote_all")


func reset_round_remote_all() -> void:
	var sender = g.multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	for child in g.players_node.get_children():
		if child.get_multiplayer_authority() == g.multiplayer.get_unique_id():
			child.reset_round_remote()


func _end_survival_on_time() -> void:
	var best := -1
	var winner := "DRAW"
	for pid in g._round_wins.keys():
		if int(g._round_wins[pid]) > best:
			best = int(g._round_wins[pid])
			var node = g.players_node.get_node_or_null(str(pid))
			winner = node.player_name if node != null else "DRAW"
	_end_match(winner, "time up - most rounds wins!")


func _end_lms_on_time() -> void:
	var best_kills := -1
	var winner := "DRAW"
	for child in g.players_node.get_children():
		if child.kills > best_kills:
			best_kills = child.kills
			winner = child.player_name
	_end_match(winner, "time up - most kills wins!")


func _end_match(winner: String, reason: String) -> void:
	g.match_over = true
	var rows: Array = []
	for child in g.players_node.get_children():
		# Phase 4: end stats carry shots/hits (accuracy) + best streak.
		# QA-078: "id" lets the end screen record THIS phone's stats.
		rows.append({"id": child.peer_id, "name": child.player_name, "kills": child.kills, "deaths": child.deaths, "team": child.team, "color": child.player_color, "rounds": int(g._round_wins.get(child.peer_id, 0)), "shots": child._shots_fired, "hits": child._shots_hit, "streak": int(g._best_streaks.get(child.peer_id, 0))})
	rows.sort_custom(func(a, b) -> bool: return a["kills"] > b["kills"])
	g.rpc("show_end_screen", winner, reason, rows)


func show_end_screen(winner: String, reason: String, rows: Array) -> void:
	# Only the host may end the match for everyone.
	var sender = g.multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	g.match_over = true
	g._end_shown = true
	# Phase 6: the match is over — back to the calm menu track.
	if g.audio != null:
		g.audio.play_menu_music()
	# "You win!" not "You wins!" — winner is "You" for the local
	# player, a name for anyone else.
	# QA-145 (v4.1, Worker V): team wins said "RED TEAM wins!"
	# even to a player ON the red team, and an FFA win said
	# "<my own name> wins!" — the player never read that *they*
	# won. If the winner is my team, or my own name, say so.
	var win_word := "%s wins!" % winner
	if winner != "DRAW":
		if winner == "You":
			win_word = "You win!"
		else:
			var me = g.players_node.get_node_or_null(str(g.multiplayer.get_unique_id()))
			if me != null:
				if (winner == "RED TEAM" and int(me.team) == 0) or (winner == "BLUE TEAM" and int(me.team) == 1):
					win_word = "You win!"
				elif winner == String(me.player_name):
					win_word = "You win!"
	g.end_title.text = "%s\n%s" % [win_word, reason] if winner != "DRAW" else "Draw!\n%s" % reason
	# Phase 4: MVP / match summary banner (most kills, best accuracy).
	# Rows arrive sorted by kills, so rows[0] is the MVP.
	for n in g._mvp_nodes:
		if is_instance_valid(n):
			n.queue_free()
	g._mvp_nodes.clear()
	if not rows.is_empty():
		var mvp: Dictionary = rows[0]
		var mvp_st: Dictionary = GameData.compute_stats(int(mvp["kills"]), int(mvp["deaths"]), int(mvp.get("shots", 0)), int(mvp.get("hits", 0)))
		var mvp_row := HBoxContainer.new()
		mvp_row.alignment = BoxContainer.ALIGNMENT_CENTER
		mvp_row.add_theme_constant_override("separation", 8)
		var star := TextureRect.new()
		star.texture = preload("res://assets/skybrawl/pickups/pickup_012.png")
		star.custom_minimum_size = Vector2(44, 44)
		star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mvp_row.add_child(star)
		var mvp_lbl := Label.new()
		# QA-113 (v3.9): the old text ("... best streak N") ran
		# past the 560 px panel — the streak is already a column
		# in the table below, so the banner keeps kills + accuracy
		# only. clip_text is a safety net for very long names.
		mvp_lbl.text = "MVP: %s — %d kills, %d%% accuracy" % [
			String(mvp["name"]), int(mvp["kills"]), int(mvp_st["accuracy"]),
		]
		mvp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mvp_lbl.add_theme_font_size_override("font_size", 24)
		mvp_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		mvp_row.add_child(mvp_lbl)
		g._end_box.add_child(mvp_row)
		g._end_box.move_child(mvp_row, 1)
		g._mvp_nodes.append(mvp_row)
		var best_acc := -1.0
		var best_acc_name := ""
		for r in rows:
			var st: Dictionary = GameData.compute_stats(int(r["kills"]), int(r["deaths"]), int(r.get("shots", 0)), int(r.get("hits", 0)))
			if int(r.get("shots", 0)) > 0 and float(st["accuracy"]) > best_acc:
				best_acc = float(st["accuracy"])
				best_acc_name = String(r["name"])
		if best_acc_name != "":
			var acc_lbl := Label.new()
			acc_lbl.text = "Best accuracy: %s (%d%%)" % [best_acc_name, int(best_acc)]
			acc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			acc_lbl.add_theme_font_size_override("font_size", 20)
			acc_lbl.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88))
			g._end_box.add_child(acc_lbl)
			g._end_box.move_child(acc_lbl, 2)
			g._mvp_nodes.append(acc_lbl)
	for c in g.end_list.get_children():
		c.queue_free()
	# QA-113 (v3.9): end-of-match rows use the same aligned columns
	# as the scoreboard (Survival shows Rounds, other modes Streak).
	g.end_list.add_child(g._stats_header_row("ROUNDS" if g.game_mode == 2 else "STREAK"))
	g.end_list.add_child(HSeparator.new())
	var rank := 1
	for r in rows:
		var team_txt := ""
		if int(r["team"]) == 0:
			team_txt = " [RED]"
		elif int(r["team"]) == 1:
			team_txt = " [BLUE]"
		var st2: Dictionary = GameData.compute_stats(int(r["kills"]), int(r["deaths"]), int(r.get("shots", 0)), int(r.get("hits", 0)))
		var extra = str(int(r.get("rounds", 0))) if g.game_mode == 2 else str(int(r.get("streak", 0)))
		# QA-145 (v4.1, Worker V): the end screen passed is_self
		# = false for every row, so (unlike the scoreboard) the
		# player could not spot their own row — "►" + "(YOU)" was
		# built into _stats_row but never used here. Fake rows
		# (features test) carry no id and still show unmarked.
		var is_self: bool = int(r.get("id", -1)) == g.multiplayer.get_unique_id()
		g.end_list.add_child(g._stats_row(rank, String(r["name"]), team_txt, int(r["kills"]), int(r["deaths"]), float(st2["kd"]), int(st2["accuracy"]), is_self, r["color"], extra))
		rank += 1
	# QA-078: record this match in the local lifetime stats, once
	# per match. The rows carry the peer id now, so each phone
	# finds its own row. Fake rows (features test) carry no id and
	# record nothing. A draw is not a win.
	if not g._stats_recorded:
		var my_id = g.multiplayer.get_unique_id()
		for r in rows:
			if int(r.get("id", -1)) == my_id:
				var won := false
				if winner != "DRAW":
					if g.game_mode == 1:
						var me = g.players_node.get_node_or_null(str(my_id))
						var my_team := int(me.team) if me != null else -1
						won = (winner == "RED TEAM" and my_team == 0) or (winner == "BLUE TEAM" and my_team == 1)
					else:
						won = winner == String(r["name"]) or winner == "You"
				GameData.record_match(int(r["kills"]), int(r["deaths"]), won)
				g._stats_recorded = true
				break
	g.end_rematch_btn.visible = g.multiplayer.is_server()
	# QA-145 (v4.1, Worker V): Rematch is host-only, so a
	# non-host player used to see no way back into a game and no
	# warning that the host's Rematch would pull everyone into a
	# new match. Each side now reads what happens next.
	if g.end_hint != null:
		if g.multiplayer.is_server():
			g.end_hint.text = "Tap Rematch to play again with the same players."
		else:
			g.end_hint.text = "Waiting for the host — a rematch starts a new game with everyone here."
	g.end_panel.visible = true
	# QA-035: hide the touch controls under the end panel — the
	# RELOAD/GRENADE/WEAPON column sat on top of the stats rows and
	# the Rematch button (the sticks are dead input
	# once the match is over, so hiding them loses nothing).
	g._reset_all_touch_state()
	g._set_touch_controls_visible(false)
	g.audio.play("win")


func _match_goal_text() -> String:
	match g.game_mode:
		0:
			return "First to %d kills  •  %s" % [g.kill_limit, GameData.MAP_NAMES[g.map_id]]
		1:
			return "RED vs BLUE — first to %d kills  •  %s" % [g.kill_limit, GameData.MAP_NAMES[g.map_id]]
		2:
			return "Survival — last one standing wins the round  •  %s" % GameData.MAP_NAMES[g.map_id]
		3:
			return "Last Man Standing — one life, no respawns  •  %s" % GameData.MAP_NAMES[g.map_id]
		4:
			return "Capture the Flag — steal the flag from the summit, first to %d points (capture 3, relay bank 1)  •  %s" % [GameData.CTF_POINTS_LIMIT, GameData.MAP_NAMES[g.map_id]]
		_:
			return "Last Man Standing — one life, no respawns  •  %s" % GameData.MAP_NAMES[g.map_id]


func _player_name(peer_id: int) -> String:
	var node = g.players_node.get_node_or_null(str(peer_id))
	if node != null:
		return String(node.player_name)
	return "Player"


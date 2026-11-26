class_name NetTest
extends RefCounted


# QA-140 (v3.15): extracted from game.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `g` (dependency injection).


var g # the owner (game.gd)

var _perf_test: bool = false # --perf-test harness (GAP-73)
var _perf_elapsed: float = 0.0
var _perf_mem0: int = 0
var _perf_done: bool = false
var _perf_seconds: float = 60.0 # T-73: --perf-seconds=N overrides (default 60)
var _perf_bots: int = 0 # T-73: --perf-bots=N idle bot players (default 0)
var _perf_bots_spawned: bool = false
var _net_test: bool = false # v2.4: --net-test harness
var _net_steps: Array = []
var _net_step: int = 0
var _net_in_step: bool = false
var _net_timer: float = 0.0
var _net_passed: int = 0
var _net_failed: int = 0
var _net_done: bool = false
var _flow_test: bool = false
var _flow_steps: Array = []
var _flow_step: int = 0
var _flow_in_step: bool = false
var _flow_timer: float = 0.0
var _flow_passed: int = 0
var _flow_failed: int = 0
var _flow_done: bool = false
var _restart_test: bool = false


func _init(owner) -> void:
	g = owner


func _fl_c_back() -> Array:
	# The scene change happens in _on_leave_pressed; this check is
	# only reached if the change did not happen.
	return [false, "still in the game scene after Back"]


func _fl_c_end() -> Array:
	var ok: bool = g.match_over and g.end_panel.visible
	# LOOP 5: synchronous capture — the next step changes scene, so
	# the async _capture_shot would die before saving.
	var img = g.get_viewport().get_texture().get_image()
	var err = img.save_png("user://shot_end.png")
	print("FLOW SHOT NOW: user://shot_end.png err=", err, " size=", img.get_size())
	return [ok, "match_over=%s end panel visible=%s" % [g.match_over, g.end_panel.visible]]


func _fl_c_fire() -> Array:
	var lp = g._get_local_player()
	var ok: bool = lp._shots_fired > 0
	g.fire_test._ft_release_aim()
	g.fire_test._ft_release_fire()
	return [ok, "shots fired in the match: %d" % lp._shots_fired]


func _fl_c_loaded() -> Array:
	var lp = g._get_local_player()
	var ok: bool = lp != null and lp.alive and not g.match_over
	return [ok, "local player alive=%s match_over=%s" % [lp != null and lp.alive, g.match_over]]


func _fl_c_paused() -> Array:
	var ok: bool = g.get_tree().paused and g.pause_panel.visible
	# LOOP 5: synchronous capture — the async _capture_shot lands
	# after the RESUME step and shows the unpaused game instead.
	var img = g.get_viewport().get_texture().get_image()
	var err = img.save_png("user://shot_pause.png")
	print("FLOW SHOT NOW: user://shot_pause.png err=", err, " size=", img.get_size())
	return [ok, "paused=%s pause panel visible=%s" % [g.get_tree().paused, g.pause_panel.visible]]


func _fl_c_resumed() -> Array:
	var ok: bool = not g.get_tree().paused and not g.pause_panel.visible
	return [ok, "paused=%s pause panel visible=%s" % [g.get_tree().paused, g.pause_panel.visible]]


func _fl_c_score() -> Array:
	var shown: bool = g.scoreboard_panel.visible
	# LOOP 5: synchronous capture before closing — the async version
	# landed after the END-MATCH step and showed the end screen.
	var img = g.get_viewport().get_texture().get_image()
	var err = img.save_png("user://shot_scoreboard.png")
	print("FLOW SHOT NOW: user://shot_scoreboard.png err=", err, " size=", img.get_size())
	g._on_score_pressed()
	var ok: bool = shown and not g.scoreboard_panel.visible
	return [ok, "scoreboard opened=%s closed again=%s" % [shown, not g.scoreboard_panel.visible]]


func _fl_s_back() -> void:
	# Hand the check back to the menu: it prints the final result
	# when the main scene loads again.
	GameData.flow_phase = 2
	g._on_leave_pressed()


func _fl_s_end() -> void:
	g._end_match("FlowTest", "flow check")


func _fl_s_fire() -> void:
	g.fire_test._ft_press_aim(Vector2(60, 0))
	g.fire_test._ft_press_fire()


func _fl_s_noop() -> void:
	pass


func _fl_s_pause() -> void:
	g._toggle_pause()


func _fl_s_resume() -> void:
	g._toggle_pause()


func _fl_s_score() -> void:
	g._on_score_pressed()


func _flowtest_build_steps() -> void:
	_flow_steps = [
		{"name": "MATCH-LOADED", "wait": 0.5, "setup": _fl_s_noop, "check": _fl_c_loaded},
		{"name": "PLAY-FIRE", "wait": 0.5, "setup": _fl_s_fire, "check": _fl_c_fire},
		{"name": "PAUSE", "wait": 0.3, "setup": _fl_s_pause, "check": _fl_c_paused},
		{"name": "RESUME", "wait": 0.3, "setup": _fl_s_resume, "check": _fl_c_resumed},
		{"name": "SCOREBOARD", "wait": 0.3, "setup": _fl_s_score, "check": _fl_c_score},
		{"name": "END-MATCH", "wait": 0.5, "setup": _fl_s_end, "check": _fl_c_end},
		{"name": "BACK-TO-MENU", "wait": 0.3, "setup": _fl_s_back, "check": _fl_c_back},
	]


func _nt_bot():
	return g.players_node.get_node_or_null("99")


func _nt_c_combat_hit() -> Array:
	var lp = _nt_lp()
	# One pistol shot at a player 300 px away: the bullet must have
	# hit (despawned on impact) instead of flying on (0.9 s life).
	var n = g.fire_test._ft_count_bullets(lp.peer_id, 5)
	var ok: bool = lp._shots_fired >= 1 and n == 0
	g.fire_test._ft_release_aim()
	g.fire_test._ft_release_fire()
	return [ok, "shots=%d active pistol bullets after 0.6 s: %d (want 0 = hit)" % [lp._shots_fired, n]]


func _nt_c_damage() -> Array:
	var lp = _nt_lp()
	var health_after_30: int = lp.health
	var ok: bool = health_after_30 == 70 and lp.alive
	if ok:
		lp.take_damage(500, 1)
		ok = not lp.alive and lp.deaths == 1
	return [ok, "health after 30 dmg: %d, dead after lethal: %s" % [health_after_30, not lp.alive]]


func _nt_c_dc_shot1() -> Array:
	var lp = _nt_lp()
	var ok: bool = lp.kills == g._nt_dc_kills_a + 1
	g.fire_test._ft_release_aim()
	g.fire_test._ft_release_fire()
	return [ok, "kills %d->%d after first lethal bullet (want +1)" % [g._nt_dc_kills_a, lp.kills]]


func _nt_c_dc_shot2() -> Array:
	var lp = _nt_lp()
	var ok: bool = lp.kills == g._nt_dc_kills_a
	g.fire_test._ft_release_aim()
	g.fire_test._ft_release_fire()
	return [ok, "kills %d->%d after second lethal bullet (want +0)" % [g._nt_dc_kills_a, lp.kills]]


func _nt_c_disconnect() -> Array:
	var ok: bool = g.players_node.get_node_or_null("99") == null and not g._spawned.has(99)
	return [ok, "bot node gone=%s spawned erased=%s" % [g.players_node.get_node_or_null("99") == null, not g._spawned.has(99)]]


func _nt_c_discovery_bind() -> Array:
	var d := LanDiscovery.new()
	g.add_child(d)
	var bound: bool = d.start_listening()
	d.broadcast_room({"room_name": "T", "host_name": "H", "players": 1, "max_players": 8, "map_id": 0, "mode": 0, "status": "lobby", "port": 7777, "private": false})
	d.stop()
	d.queue_free()
	return [bound, "listener bound=%s (false means UDP is blocked in this sandbox)" % bound]


func _nt_c_double_credit() -> Array:
	var lp = _nt_lp()
	var ok: bool = g._nt_dc_first and not g._nt_dc_second
	ok = ok and lp.kills == g._nt_dc_kills_a + 1
	return [ok, "first=%s second=%s kills A %d->%d (want +1)" % [g._nt_dc_first, g._nt_dc_second, g._nt_dc_kills_a, lp.kills]]


func _nt_c_double_credit_expire() -> Array:
	var lp = _nt_lp()
	var third: bool = g.try_credit_kill(1, 99, 5)
	var ok: bool = third and lp.kills == g._nt_dc_kills_a + 1
	return [ok, "third credit after 1.2 s=%s kills A %d->%d (want +1)" % [third, g._nt_dc_kills_a, lp.kills]]


func _nt_c_host_left() -> Array:
	var vis: bool = g.error_panel.visible
	var ok: bool = vis and GameData.last_host_ip == "192.168.1.5"
	g.error_panel.visible = false
	g._join_failed = false
	return [ok, "error panel visible=%s last_host_ip=%s (want 192.168.1.5)" % [vis, GameData.last_host_ip]]


func _nt_c_lms() -> Array:
	var over: bool = g.match_over
	var ok: bool = over
	g.match_over = false
	g.end_panel.visible = false
	g.game_mode = 0
	# QA-031: MODE-SURVIVAL left kill_limit = 1 behind; with the
	# DOUBLE-CREDIT-SHOT steps crediting the local player a kill,
	# the per-frame FFA check would end the match instantly once
	# FFA resumes (1 kill >= limit 1) and break HOST-LEFT-SAFE-EXIT.
	g.kill_limit = GameData.kill_limit
	return [ok, "match_over=%s (want true, local player last standing)" % over]


func _nt_c_payload() -> Array:
	var room := {"room_name": "Test Room", "host_name": "Host", "players": 2, "max_players": 8, "map_id": 4, "mode": 1, "status": "lobby", "port": 7777, "private": true}
	var pkt := LanDiscovery.build_room_packet(room)
	var back := LanDiscovery.parse_room_packet(pkt.get_string_from_utf8(), "192.168.1.7")
	var ok: bool = back["room_name"] == "Test Room" and back["host_name"] == "Host" and int(back["players"]) == 2 and int(back["max_players"]) == 8 and int(back["map_id"]) == 4 and int(back["mode"]) == 1 and back["status"] == "lobby" and int(back["port"]) == 7777 and bool(back["private"]) and back["ip"] == "192.168.1.7"
	# Malformed packets must be rejected, not crash.
	var bad := LanDiscovery.parse_room_packet("LANARENA|1|only", "1.2.3.4")
	var bad2 := LanDiscovery.parse_room_packet("GARBAGE|1|a|b|1|8|0|0|lobby|7777|0", "1.2.3.4")
	ok = ok and bad.is_empty() and bad2.is_empty()
	return [ok, "round-trip fields match, malformed rejected: %s" % ok]


func _nt_c_respawned() -> Array:
	var lp = _nt_lp()
	var ok: bool = lp.alive and lp.health == 100
	g.game_mode = 0
	return [ok, "respawned alive=%s health=%d" % [lp.alive, lp.health]]


func _nt_c_spawn_idem() -> Array:
	var n = g.players_node.get_child_count()
	var ok: bool = n == 1 and g._get_local_player() != null
	return [ok, "players after 3x announce: %d (want 1)" % n]


func _nt_c_subnet() -> Array:
	var addrs := LanDiscovery.broadcast_addresses()
	var ok: bool = addrs.has("255.255.255.255")
	var lan := LanDiscovery.lan_ip()
	if lan != "":
		var parts := lan.split(".")
		var expect := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
		ok = ok and addrs.has(expect)
	return [ok, "broadcast addrs=%s lan_ip=%s" % [addrs, lan]]


func _nt_c_survival() -> Array:
	var over: bool = g.match_over
	var ok: bool = over and int(g._round_wins.get(1, 0)) == 1
	g.match_over = false
	g.end_panel.visible = false
	return [ok, "match_over=%s rounds won by host=%d (want 1)" % [over, int(g._round_wins.get(1, 0))]]


func _nt_lp():
	return g._get_local_player()


func _nt_s_combat_hit() -> void:
	var lp = _nt_lp()
	g.fire_test._ft_set_weapon(5)
	lp.position = Vector2(300, 1318) # QA-071: floor 1352, centre top-34
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	var b = _nt_spawn_bot()
	if b != null:
		b.position = Vector2(600, 1318) # QA-071: floor 1352, centre top-34
		b.sync_position = b.position
		b.velocity = Vector2.ZERO
	g.fire_test._ft_press_aim(Vector2(60, 0))
	g.fire_test._ft_press_fire()


func _nt_s_damage() -> void:
	var lp = _nt_lp()
	# Spawn protection (2 s) would swallow the damage: clear it.
	lp._spawn_protect_timer = 0.0
	lp.take_damage(30, 1)


func _nt_s_dc_shot1() -> void:
	# QA-031 end-to-end: the victim bot sits at 5 HP and the local
	# player fires one lethal pistol shot at it. The host's copy of
	# the bot's health never drops in this harness (take_hit goes to
	# the fake peer 99, which is not connected), so this reproduces
	# the stale-health condition that used to double-credit kills.
	var lp = _nt_lp()
	g.fire_test._ft_set_weapon(5)
	lp.position = Vector2(300, 1318) # QA-071: floor 1352, centre top-34
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	var b = _nt_bot()
	if b != null:
		b.position = Vector2(600, 1318) # QA-071: floor 1352, centre top-34
		b.sync_position = b.position
		b.velocity = Vector2.ZERO
		b._spawn_protect_timer = 0.0
		b.health = 5
	g._nt_dc_kills_a = lp.kills
	g.fire_test._ft_press_aim(Vector2(60, 0))
	g.fire_test._ft_press_fire()


func _nt_s_dc_shot2() -> void:
	# Second lethal bullet at the same 5 HP victim, inside the 1 s
	# lock window: the host must deny the second credit.
	var lp = _nt_lp()
	g._nt_dc_kills_a = lp.kills
	g.fire_test._ft_press_aim(Vector2(60, 0))
	g.fire_test._ft_press_fire()


func _nt_s_disconnect() -> void:
	_nt_spawn_bot()
	g._on_peer_disconnected(99)


func _nt_s_double_credit() -> void:
	# QA-031 (T-56): two shooters land lethal hits on the same victim
	# in the same tick. The host must credit exactly ONE kill (to the
	# first shooter) and deny the second.
	# No fake nodes are spawned: try_credit_kill only needs the
	# killer node (peer 1, the local player) — the victim and the
	# second shooter are bare ids, and a shooter with no node simply
	# gets no add_kill, exactly as in production when the shooter
	# has disconnected mid-flight.
	var lp = _nt_lp()
	g._nt_dc_kills_a = lp.kills
	g._nt_dc_first = g.try_credit_kill(1, 99, 5)
	g._nt_dc_second = g.try_credit_kill(98, 99, 5)


func _nt_s_double_credit_expire() -> void:
	# The lock must expire: record the local player's kills now;
	# the check runs 1.2 s later, past the 1 s lock, and a fresh
	# credit must succeed (the victim's next life is never blocked).
	# The credit goes through the local player because a fake remote
	# peer can never receive its add_kill RPC in this harness.
	var lp = _nt_lp()
	g._nt_dc_kills_a = lp.kills


func _nt_s_host_left() -> void:
	GameData.host_ip = "192.168.1.5"
	g._on_server_disconnected()


func _nt_s_lms() -> void:
	# Last Man Standing: kill the only other player; the local
	# player must be the last one standing and the match must end.
	g.game_mode = 3
	g.match_over = false
	var b = _nt_spawn_bot()
	if b != null and not b.alive:
		b._respawn()
		b._spawn_protect_timer = 0.0
	if b != null:
		b.take_damage(500, 1)


func _nt_s_noop() -> void:
	pass


func _nt_s_spawn_idem() -> void:
	# request_spawn is idempotent on the server: three identical
	# requests must still leave exactly one local player. (The
	# host's _announce_ready is a no-op — it spawned via
	# _spawn_self — so the handler is exercised directly here.)
	# request_spawn no longer takes a helmet_style arg (removed with the helmet) — version defaults to "".
	g.request_spawn(1, "Host", 0)
	g.request_spawn(1, "Host", 0)
	g.request_spawn(1, "Host", 0)


func _nt_s_survival() -> void:
	# Survival, first to 1 round: kill the only other player and the
	# local player must win the round and the match.
	g.game_mode = 2
	g.kill_limit = 1
	g.match_over = false
	g._round_wins.clear()
	var b = _nt_spawn_bot()
	if b != null and not b.alive:
		b._respawn()
		b._spawn_protect_timer = 0.0
	if b != null:
		b.take_damage(500, 1)


func _nt_spawn_bot() -> Node:
	if _nt_bot() == null:
		g._do_spawn(99, "TestBot", 0, 0)
	var b = _nt_bot()
	if b != null:
		b._spawn_protect_timer = 0.0
	return b


func _repl_sim_check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		g.replsim_test._repl_sim_passed += 1
		print("REPLSIM %s: PASS %s" % [label, detail])
	else:
		g.replsim_test._repl_sim_failed += 1
		print("REPLSIM %s: FAIL %s" % [label, detail])


func _repl_sim_deliver_recorded() -> void:
	# Hand the recorded payloads to the shadow client, in order,
	# exactly as the network would deliver them.
	for item in g.replsim_test._repl_sim_sent:
		var d := item as Dictionary
		if d.get("kind", "") == "spawn_player_remote":
			g.replsim_test._repl_sim_shadow.spawn_player_remote(d.get("data", {}))
		elif d.get("kind", "") == "player_list_remote":
			g.replsim_test._repl_sim_shadow.player_list_remote(d.get("data", []))
	g.replsim_test._repl_sim_sent.clear()


func _repl_sim_has_sync(p) -> bool:
	if p == null:
		return false
	for c in p.get_children():
		if c is MultiplayerSynchronizer:
			return true
	return false


func _repl_sim_snapshot(seq: int, pos: Vector2, vel: Vector2, k: int = 0, d: int = 0, al: bool = true, ls: int = 0) -> Dictionary:
	# One QA-053 move snapshot, exactly as _send_move_snapshot builds
	# it (same keys the receiver reads). QA-068: "st" advances at a
	# steady 33 ms per sequence step — the sender's clock, which is
	# what the receiver interpolates on now; "prot" is 0 (no spawn
	# protection in the movement stream). QA-073: "id" is 0 here
	# ("unspecified" — the receiver accepts it; a real sender puts
	# its peer id in) and the gameplay-state flags default to
	# ground / not firing / not jetpacking / not reloading.
	return {"seq": seq, "st": float(seq) * 0.033, "prot": 0,
		"id": 0, "jet": 0, "fire": 0, "rel": 0, "air": 0,
		"p": pos, "v": vel, "aim": 0.0, "face": 1,
		"wpn": 0, "hp": 100, "k": k, "d": d, "al": al, "fuel": 100.0,
		"ls": ls, "mag": 30, "gr": 2, "sf": 0, "sh": 0}


func _repl_sim_track(pos: Vector2, frame_delta: float) -> void:
	# Smoothness tracker: biggest single-frame step RATE (px/s), and
	# biggest backward (snap-back) move from the furthest-forward x
	# reached. The rate is used, not the raw step, because the sim
	# runs at ~10 fps under llvmpipe: a healthy 300 px/s glide is a
	# 30 px step between _process frames there, but still 300 px/s.
	# A freeze-then-catch-up burst or a snap-back to an old position
	# shows up here as a multi-thousand px/s step or a backward jump.
	if g.replsim_test._repl_sim_track_prev == Vector2.INF:
		g.replsim_test._repl_sim_track_prev = pos
		g.replsim_test._repl_sim_track_best_x = pos.x
		return
	var step_rate = pos.distance_to(g.replsim_test._repl_sim_track_prev) / maxf(frame_delta, 0.001)
	if step_rate > 900.0:
		# QA-073 diagnostic: a step over the chaos bar — log the
		# sample so the cause (resync snap? fast frame? catch-up
		# chase?) is visible instead of guessed. Test-only print.
		print("REPLSIM SPIKE step_rate=%.0f px/s step=%.1f px frame_delta=%.3f s pos=%s" % [step_rate, pos.distance_to(g.replsim_test._repl_sim_track_prev), frame_delta, pos])
	if step_rate > g.replsim_test._repl_sim_track_max_step:
		g.replsim_test._repl_sim_track_max_step = step_rate
	if pos.x < g.replsim_test._repl_sim_track_best_x:
		var back = g.replsim_test._repl_sim_track_best_x - pos.x
		if back > g.replsim_test._repl_sim_track_max_back:
			g.replsim_test._repl_sim_track_max_back = back
	if pos.x > g.replsim_test._repl_sim_track_best_x:
		g.replsim_test._repl_sim_track_best_x = pos.x
	g.replsim_test._repl_sim_track_prev = pos


func _repl_sim_track_reset(pos: Vector2) -> void:
	g.replsim_test._repl_sim_track_prev = pos
	g.replsim_test._repl_sim_track_max_step = 0.0
	g.replsim_test._repl_sim_track_max_back = 0.0
	g.replsim_test._repl_sim_track_best_x = pos.x


func _restarttest_build_steps(phase: int) -> void:
	if phase == 1:
		g._restart_steps = [
			{"name": "SPAWN-1", "wait": 0.5, "setup": _rs_s_noop, "check": _rs_c_spawn},
			{"name": "PLAY-1", "wait": 0.8, "setup": _rs_s_play, "check": _rs_c_play},
			{"name": "LEAVE-1", "wait": 0.3, "setup": _rs_s_leave, "check": _rs_c_left},
		]
	elif phase == 3:
		g._restart_steps = [
			{"name": "SPAWN-2", "wait": 0.5, "setup": _rs_s_noop, "check": _rs_c_spawn},
			{"name": "PLAY-2", "wait": 0.8, "setup": _rs_s_play, "check": _rs_c_play},
			{"name": "END-2", "wait": 0.5, "setup": _rs_s_end, "check": _rs_c_end},
			{"name": "REMATCH-2", "wait": 0.3, "setup": _rs_s_rematch, "check": _rs_c_left},
		]
	else: # phase 4 — the scene reloaded by rematch
		g._restart_steps = [
			{"name": "SPAWN-3", "wait": 0.5, "setup": _rs_s_noop, "check": _rs_c_spawn},
			{"name": "PLAY-3", "wait": 0.8, "setup": _rs_s_play, "check": _rs_c_play},
		]


func _rs_c_end() -> Array:
	var ok: bool = g.match_over and g.end_panel.visible
	return [ok, "match_over=%s end panel visible=%s" % [g.match_over, g.end_panel.visible]]


func _rs_c_left() -> Array:
	# The scene change happens in _on_leave_pressed / rematch; this
	# check is only reached if the change did not happen.
	return [false, "still in the game scene after leave/rematch (phase %d)" % GameData.restart_phase]


func _rs_c_play() -> Array:
	var lp = g._get_local_player()
	g.fire_test._ft_release_move()
	g.fire_test._ft_release_aim()
	g.fire_test._ft_release_fire()
	if lp == null:
		return [false, "no local player to play with (phase %d)" % GameData.restart_phase]
	var ok: bool = lp._shots_fired > 0 and lp.alive
	return [ok, "shots fired=%d alive=%s (phase %d)" % [lp._shots_fired, lp.alive, GameData.restart_phase]]


func _rs_c_spawn() -> Array:
	var lp = g._get_local_player()
	var ok: bool = lp != null and lp.alive and not g.match_over
	return [ok, "local player spawned+alive=%s match_over=%s (phase %d)" % [lp != null and lp.alive, g.match_over, GameData.restart_phase]]


func _rs_s_end() -> void:
	g._end_match("RestartTest", "second match over")


func _rs_s_leave() -> void:
	# Hand back to the menu: it starts match 2 from a fresh room.
	GameData.restart_phase = 2
	g._on_leave_pressed()


func _rs_s_noop() -> void:
	pass


func _rs_s_play() -> void:
	# Move right and fire, like a real first few seconds of play.
	g.fire_test._ft_press_move(Vector2(60, 0))
	g.fire_test._ft_press_aim(Vector2(60, 0))
	g.fire_test._ft_press_fire()


func _rs_s_rematch() -> void:
	# Rematch reloads this scene; the reloaded scene runs phase 4.
	GameData.restart_phase = 4
	g._on_rematch_pressed()


func _update_flowtest(delta: float) -> void:
	if _flow_done:
		return
	var lp = g._get_local_player()
	if lp == null:
		_flow_timer += delta
		if _flow_timer > 5.0:
			_flow_done = true
			print("FLOWTEST DONE: 0/0 passed — no local player spawned")
			g.get_tree().quit()
		return
	if _flow_steps.is_empty():
		_flowtest_build_steps()
		_flow_step = 0
		_flow_in_step = false
		_flow_timer = 0.0
	if _flow_step >= _flow_steps.size():
		_flow_done = true
		print("FLOWTEST GAME: %d/%d passed" % [_flow_passed, _flow_passed + _flow_failed])
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


# v3.2 two-peer join regression test. Runs in the game scene on
# BOTH processes: the host auto-started the match, the client joined
# via Quick Play (or --auto-join). After 12 s each side prints its
# verdict and quits. The client also holds the move stick from t=2 s
# so the host can verify the client's player actually MOVES as seen
# on the host (the frozen-2nd-player symptom).
func _update_jointest(delta: float) -> void:
	if g._join_test_done:
		return
	g._join_test_timer += delta
	g._join_test_status_t += delta
	if g._join_test_client and g._join_test_timer >= 2.0 and g.move_stick != null and not g.move_stick.is_active():
		g._on_touch_press(930, g.move_stick.get_global_rect().get_center() + Vector2(60, 0))
	if g._join_test_status_t >= 2.0:
		g._join_test_status_t = 0.0
		var lp = g._get_local_player()
		print("JOINTEST STATUS t=", int(g._join_test_timer), "s role=", "host" if g._join_test_host else "client",
			" players=", g.players_node.get_child_count(), " local=", lp != null,
			" peers=", g.multiplayer.get_peers(), " join_failed=", g._join_failed,
			" spawned=", g._spawned.keys())
	if g._join_test_host and g._join_test_timer >= 8.0 and g._join_test_pos_snap.is_empty():
		for child in g.players_node.get_children():
			g._join_test_pos_snap[int(child.peer_id)] = child.position
	if g._join_test_timer < 12.0:
		return
	g._join_test_done = true
	if g._join_test_host:
		var n = g.players_node.get_child_count()
		var moved := false
		for child in g.players_node.get_children():
			var pid := int(child.peer_id)
			if pid == 1:
				continue
			var before: Vector2 = g._join_test_pos_snap.get(pid, child.position)
			if child.position.distance_to(before) > 50.0:
				moved = true
		var ok: bool = n >= 2 and moved
		print("JOINTEST HOST: %s — players=%d spawned=%s moved_remote=%s (want players>=2 and the remote player moving)" % ["PASS" if ok else "FAIL", n, g._spawned.keys(), moved])
	else:
		var lp2 = g._get_local_player()
		var n2 = g.players_node.get_child_count()
		var conn := "?"
		var peer = g.multiplayer.multiplayer_peer
		if peer is ENetMultiplayerPeer:
			conn = str((peer as ENetMultiplayerPeer).get_connection_status())
		var ok2: bool = lp2 != null and n2 >= 2
		print("JOINTEST CLIENT: %s — local_spawned=%s players=%d connection=%s join_failed=%s join_timer=%.1f (want local player + players>=2)" % ["PASS" if ok2 else "FAIL", lp2 != null, n2, conn, g._join_failed, g._join_timer])
	g.get_tree().quit()


func _update_nettest(delta: float) -> void:
	if _net_done:
		return
	var lp = g._get_local_player()
	if lp == null:
		_net_timer += delta
		if _net_timer > 5.0:
			_net_done = true
			print("NETTEST DONE: 0/0 passed — no local player spawned")
			g.get_tree().quit()
		return
	if _net_steps.is_empty():
		g.net_test_steps._nettest_build_steps()
		_net_step = 0
		_net_in_step = false
		_net_timer = 0.0
	if _net_step >= _net_steps.size():
		_net_done = true
		print("NETTEST DONE: %d/%d passed" % [_net_passed, _net_passed + _net_failed])
		g.get_tree().quit()
		return
	var step: Dictionary = _net_steps[_net_step]
	if not _net_in_step:
		(step["setup"] as Callable).call()
		_net_in_step = true
		_net_timer = float(step["wait"])
	_net_timer -= delta
	if _net_timer <= 0.0:
		var result: Array = (step["check"] as Callable).call()
		var ok: bool = bool(result[0])
		if ok:
			_net_passed += 1
		else:
			_net_failed += 1
		print("NETTEST %s: %s — %s" % [String(step["name"]), "PASS" if ok else "FAIL", String(result[1])])
		_net_step += 1
		_net_in_step = false
		_net_timer = 0.0


func _update_perftest(delta: float) -> void:
	if _perf_done:
		return
	var lp = g._get_local_player()
	if lp == null:
		return
	if _perf_elapsed == 0.0:
		_perf_mem0 = OS.get_static_memory_usage()
		print("PERFTEST start: mem=%d bytes" % _perf_mem0)
		# T-73: soak on the rifle with a topped-up reserve — the rifle
		# is full-auto, so holding FIRE churns bullets continuously.
		# (The pistol has infinite reserve but is semi-auto: holding
		# FIRE fires exactly once. The rifle's 90 reserve + 30 mag
		# runs dry after ~20 s, so the reserve is refilled here and
		# again every 10 s below.)
		lp._reserve[0] = 90
		if _perf_bots > 0 and not _perf_bots_spawned:
			# T-73: idle bot players, instantiated directly (NOT via
			# the MultiplayerSpawner — a fake never-connected peer id
			# makes the spawner log an engine RPC error; direct
			# instantiation is clean, proven by the QA-031 probes).
			# They stand idle; the local player provides the churn
			# (full-auto fire + grenades). Honest limit: only 1 of
			# the 8 players shoots.
			_perf_bots_spawned = true
			var spawns: Array = g.MAPS[g.map_id]["spawns"]
			for i in _perf_bots:
				var pid = 100 + i
				var p = g.PLAYER_SCENE.instantiate()
				p.name = str(pid)
				p.peer_id = pid
				p.player_index = (i + 2) % 12
				p.player_name = "SoakBot%d" % pid
				p.color_index = i % GameAssets.PLAYER_COLORS.size()
				p.player_color = GameAssets.PLAYER_COLORS[i % GameAssets.PLAYER_COLORS.size()]
				p.team = -1
				g.players_node.add_child(p)
				var spot: Vector2 = spawns[(i + 2) % spawns.size()]
				p.position = spot
				p.sync_position = spot
			print("PERFTEST bots: %d idle bot players added (total %d)" % [_perf_bots, g.players_node.get_child_count()])
	_perf_elapsed += delta
	# Hold FIRE + wiggle the move stick; throw a grenade every 5 s.
	g.smoke_test._smoke_set_fire(true)
	if int(_perf_elapsed) % 4 < 2:
		g.smoke_test._smoke_set_move(Vector2(60, 0))
	else:
		g.smoke_test._smoke_set_move(Vector2(-60, 0))
	if lp != null and lp.grenades > 0 and int(_perf_elapsed) % 5 == 0 and int((_perf_elapsed - delta)) % 5 != 0:
		lp.throw_grenade()
	if int(_perf_elapsed) % 10 == 0 and int((_perf_elapsed - delta)) % 10 != 0:
		# T-73: keep the rifle fed so the soak churns the whole run.
		if lp != null:
			lp._reserve[0] = 90
		print("PERFTEST t=%ds mem=%d bytes active_bullets=%d players=%d shots=%d" % [int(_perf_elapsed), OS.get_static_memory_usage(), g.bullet_pool.active_count(), g.players_node.get_child_count(), lp._shots_fired if lp != null else -1])
	if _perf_elapsed >= _perf_seconds:
		g.smoke_test._smoke_set_fire(false)
		g.smoke_test._smoke_set_move(null)
		_perf_done = true
		var growth = OS.get_static_memory_usage() - _perf_mem0
		print("PERFTEST DONE: %d s soak (%d players), mem growth=%d bytes (limit 50 MB), active_bullets=%d (drains to 0 within 2 s of stopping)" % [int(_perf_seconds), g.players_node.get_child_count(), growth, g.bullet_pool.active_count()])
		g.get_tree().quit()






func _update_restarttest(delta: float) -> void:
	if g._restart_done:
		return
	var phase := GameData.restart_phase
	if phase != 1 and phase != 3 and phase != 4:
		g._restart_done = true
		GameData.restart_failed += 1
		print("RESTARTTEST FAIL: unexpected restart_phase=%d in the game scene (want 1, 3 or 4)" % phase)
		print("RESTARTTEST DONE: %d/%d passed" % [GameData.restart_passed, GameData.restart_passed + GameData.restart_failed])
		g.get_tree().quit()
		return
	if g._restart_steps.is_empty():
		_restarttest_build_steps(phase)
		g._restart_step = 0
		g._restart_in_step = false
		g._restart_timer = 0.0
	if g._restart_step >= g._restart_steps.size():
		g._restart_done = true
		print("RESTARTTEST DONE: %d/%d passed" % [GameData.restart_passed, GameData.restart_passed + GameData.restart_failed])
		g.get_tree().quit()
		return
	var step: Dictionary = g._restart_steps[g._restart_step]
	if not g._restart_in_step:
		(step["setup"] as Callable).call()
		g._restart_in_step = true
		g._restart_timer = float(step["wait"])
	g._restart_timer -= delta
	if g._restart_timer <= 0.0:
		var result: Array = (step["check"] as Callable).call()
		var ok: bool = bool(result[0])
		if ok:
			GameData.restart_passed += 1
		else:
			GameData.restart_failed += 1
		print("RESTARTTEST %s: %s — %s" % [String(step["name"]), "PASS" if ok else "FAIL", String(result[1])])
		g._restart_step += 1
		g._restart_in_step = false
		g._restart_timer = 0.0


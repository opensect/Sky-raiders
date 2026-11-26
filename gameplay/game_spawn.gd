class_name GameSpawn
extends RefCounted


# QA-140 (v3.15): extracted from game.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `g` (dependency injection).


var g # the owner (game.gd)


func _init(owner) -> void:
	g = owner


func obtain_bullet() -> Node:
	if g.bullet_pool != null:
		return g.bullet_pool.obtain()
	var b = g.BULLET_SCENE.instantiate()
	b.pooled = false
	return b


func return_bullet(b: Node) -> void:
	if g.bullet_pool != null:
		g.bullet_pool.release(b)
	else:
		b.queue_free()


func get_spawn_point(player_index: int) -> Vector2:
	var spawns: Array = g.MAPS[g.map_id]["spawns"]
	return spawns[(player_index - 1) % spawns.size()]


func next_damage_event_id() -> int:
	# Unique damage event ids (GAP-43, spec §17.8): the host numbers
	# every damage event; victims ignore repeats of an id they saw.
	g._damage_event_seq += 1
	return g._damage_event_seq


func is_spawn_valid(pos: Vector2, exclude_peer: int) -> bool:
	# Validated spawn (GAP-45, spec §17.7): inside the map, not
	# overlapping solid geometry, and >150 px from any live enemy.
	if pos.x < 40.0 or pos.y < 40.0 or pos.x > g.map_size.x - 40.0 or pos.y > g.map_size.y - 40.0:
		return false
	for child in g.players_node.get_children():
		if child.peer_id == exclude_peer or not child.alive:
			continue
		if child.global_position.distance_to(pos) < PhysicsConfig.SPAWN_ENEMY_CLEARANCE:
			return false
	var cap := CapsuleShape2D.new()
	cap.radius = 20.0 # QA-071b: 1.20x player capsule (was 17)
	cap.height = 62.0 # QA-071b: 1.20x player capsule (was 52)
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = cap
	q.transform = Transform2D(0.0, pos)
	q.collision_mask = 1
	q.collide_with_bodies = true
	q.collide_with_areas = false
	var space = g.get_world_2d().direct_space_state
	return space.intersect_shape(q, 1).is_empty()


func get_valid_spawn_point(player_index: int, exclude_peer: int, avoid_pos: Vector2 = Vector2.INF) -> Vector2:
	# Try the player's own spawn first, then every other spawn in
	# order; if none is valid, return INF and the caller retries
	# (0.5 s) instead of teleporting into a wall or a camper.
	# Phase 5 (TDM): spawns[0:6] are the left half (team 0) and
	# spawns[6:12] the right half (team 1) — a team tries its own
	# half first, then the other half, so teams never spawn
	# interleaved. FFA keeps the old round-robin order.
	# QA-063: avoid_pos (a stuck player's current spot) — a
	# recovery must never drop the player back into the same trap.
	# First pass skips spawns within 150 px of avoid_pos; if that
	# leaves nothing, fall back to the old behaviour.
	var spawns: Array = g.MAPS[g.map_id]["spawns"]
	var n := spawns.size()
	var start := (player_index - 1) % n
	var order: Array = []
	# QA-112 (v3.9): CTF respawns at the team's highest checkpoint
	# (L1 base / L3 tunnel / L5 top / L7 arena), so a dead carrier
	# does not climb the whole tower again. The checkpoint is tried
	# first; if it is not valid (enemy camping it), the normal
	# team-half order below runs instead.
	if g.game_mode == 4:
		var node = g.players_node.get_node_or_null(str(exclude_peer))
		var team := (player_index - 1) % 2
		if node != null and int(node.team) in [0, 1]:
			team = int(node.team)
		var cps: Array = g.MAPS[g.map_id].get("checkpoints", [])
		var lvl = int(g._ctf_checkpoints.get(team, 0))
		if lvl > 0 and lvl < cps.size():
			var cp: Vector2 = (cps[lvl] as Array)[team]
			if (avoid_pos == Vector2.INF or cp.distance_to(avoid_pos) >= 150.0) and is_spawn_valid(cp, exclude_peer):
				return cp
	if g.game_mode == 1 or g.game_mode == 4:
		# QA-078: use the player's REAL team, not index parity —
		# a lobby team pick can put a player on the other half
		# from what their spawn index would suggest. Fall back to
		# parity only when the node is not there yet (first spawn).
		var team := (player_index - 1) % 2
		var node = g.players_node.get_node_or_null(str(exclude_peer))
		if node != null and int(node.team) in [0, 1]:
			team = int(node.team)
		var half_start := team * 6
		for k in 6:
			order.append(half_start + ((start - half_start + k) % 6))
		for k in 6:
			order.append((1 - team) * 6 + k)
	else:
		for k in n:
			order.append((start + k) % n)
	for idx in order:
		var cand: Vector2 = spawns[int(idx)]
		if avoid_pos != Vector2.INF and cand.distance_to(avoid_pos) < 150.0:
			continue
		if is_spawn_valid(cand, exclude_peer):
			return cand
	if avoid_pos != Vector2.INF:
		for idx in order:
			var cand2: Vector2 = spawns[int(idx)]
			if is_spawn_valid(cand2, exclude_peer):
				return cand2
	return Vector2.INF


func is_on_ice(pos: Vector2) -> bool:
	# Ice zone (GAP-51, spec §18.A): the old ice map only — that
	# map is deleted in v3.7 (QA-095), so no map has ice any more.
	# Kept as a query (player.gd calls it) that always answers
	# false; the friction/accel constants in physics_config.gd
	# stay for reference. Do NOT re-add a map-id check here.
	return false


func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	# Explosion wall obstruction (GAP-12, spec §10): a solid body
	# between the blast and the player blocks the damage/knockback.
	var space = g.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, to, 1)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return true
	var hit_pos: Vector2 = hit["position"]
	return hit_pos.distance_to(from) >= from.distance_to(to) - 10.0


func _spawn_player_node(data) -> Node:
	var p = g.PLAYER_SCENE.instantiate()
	var pid: int = int(data["id"])
	p.name = str(pid)
	p.peer_id = pid
	p.player_index = int(data["index"])
	p.player_name = str(data["name"])
	p.color_index = int(data["color"])
	p.player_color = GameAssets.PLAYER_COLORS[int(data["color"]) % GameAssets.PLAYER_COLORS.size()]
	p.team = int(data["team"])
	return p


func _spawn_self() -> void:
	_do_spawn(g.multiplayer.get_unique_id(), GameData.player_name, GameData.color_index, GameData.team_pref)


func _announce_ready() -> void:
	if g._ready_announced:
		return
	g._ready_announced = true
	if g.multiplayer.is_server():
		# The host spawned itself directly (_spawn_self). Asking
		# itself over RPC is not allowed (it only logs an error),
		# and request_spawn is idempotent anyway.
		return
	g.rpc_id(1, "request_spawn", g.multiplayer.get_unique_id(), GameData.player_name, GameData.color_index, GameData.BUILD_VERSION, GameData.team_pref)
	# v3.2 QA-047: also ask for the full player list — if our spawn
	# RPC was the one that got lost, the list heals us (it includes
	# our own player and the host's player). The 2 s retry in
	# _retry_spawn_if_needed re-sends both requests.
	g.rpc_id(1, "request_player_list")


func _retry_spawn_if_needed(delta: float) -> void:
	# v2.4: one lost UDP packet must never strand a client. While we
	# are still unspawned, re-send the request every 2 s until the
	# join timeout fires. request_spawn is idempotent on the server.
	if g.multiplayer.is_server() or g._join_failed or g.match_over:
		return
	if g.game_hud._get_local_player() != null:
		return
	g._spawn_retry_timer += delta
	if g._spawn_retry_timer >= 2.0:
		g._spawn_retry_timer = 0.0
		g._ready_announced = false
		_announce_ready()


func _do_spawn(pid: int, pname: String, color_idx: int, team_pref: int = -1) -> void:
	# v3.2 QA-047: a re-request means the client's first spawn never
	# landed (the v3.1 bug) — re-send it instead of silently assuming
	# the client already has the player. The old code returned here
	# and the single dropped spawn RPC was never re-sent.
	if g._spawned.has(pid):
		if g.multiplayer.is_server():
			_send_all_players_to(pid)
		return
	print("SPAWN: spawning peer ", pid, " (", pname, ") on ", "server" if g.multiplayer.is_server() else "client", " players_before=", g.players_node.get_child_count())
	g._spawned[pid] = true
	var team := -1
	if g.game_mode == 1 or g.game_mode == 4:
		# QA-078: honour the lobby team pick when that team still
		# has room (max 6 per team); otherwise fall back to the
		# old alternating assignment. QA-112 (v3.9): CTF (mode 4)
		# needs teams too — the old code only assigned them for
		# TDM, so CTF players spawned team -1 and the flag logic
		# (which checks child.team) never saw a RED or BLUE.
		if team_pref == 0 or team_pref == 1:
			var picked_count := 0
			for child in g.players_node.get_children():
				if child.team == team_pref:
					picked_count += 1
			if picked_count < 6:
				team = team_pref
		if team == -1:
			team = (g._next_index - 1) % 2
	# Survival (2) and Last Man Standing (3) are free-for-all: team -1.
	var data = {"id": pid, "index": g._next_index, "name": pname, "color": color_idx, "team": team}
	g._next_index += 1
	g._spawn_data[pid] = data
	g.spawner.spawn(data)
	# v3.2 QA-047: explicit spawn broadcast. v3.1 relied ONLY on the
	# MultiplayerSpawner's internal spawn RPC; on real phones the
	# client never received it (host showed 2 players, client 0).
	# The handler is idempotent, so a double delivery (spawner +
	# this RPC) is harmless. Guarded to real peers so offline
	# harnesses (net test) stay silent.
	if g.multiplayer.is_server() and g.multiplayer.get_peers().size() > 0:
		g.rpc("spawn_player_remote", data)


# v3.2 QA-047: send one peer every spawned player + the full list.
# Used when a client re-requests its spawn (retry) and when a peer
# connects to the game scene (late joiner / host player catch-up).
func _send_all_players_to(peer_id: int) -> void:
	if g.replsim_test._repl_sim_test:
		# Test hook: record what WOULD be sent — offline there are no
		# real peers, so the guard below would skip the RPCs. The sim
		# delivers the recorded payloads to the shadow client by hand.
		for pid in g._spawn_data.keys():
			g.replsim_test._repl_sim_sent.append({"kind": "spawn_player_remote", "to": peer_id, "data": (g._spawn_data[pid] as Dictionary).duplicate()})
		g.replsim_test._repl_sim_sent.append({"kind": "player_list_remote", "to": peer_id, "data": _player_list_data()})
		return
	if not g.multiplayer.get_peers().has(peer_id):
		return
	for pid in g._spawn_data.keys():
		g.rpc_id(peer_id, "spawn_player_remote", g._spawn_data[pid])
	g.rpc_id(peer_id, "player_list_remote", _player_list_data())


func _player_list_data() -> Array:
	var out: Array = []
	for k in g._spawn_data.keys():
		out.append(g._spawn_data[k])
	return out


func spawn_player_remote(data: Dictionary) -> void:
	# v3.2 QA-047: explicit spawn broadcast from the server (see
	# _do_spawn). Idempotent: a player with this id already present
	# is left alone, so spawner + RPC double delivery is harmless.
	# The player's own _ready places it at a valid spawn point.
	var pid := int(data.get("id", 0))
	if pid <= 0:
		return
	if g.players_node.get_node_or_null(str(pid)) != null:
		return
	g._server_answered = true
	g._spawned[pid] = true
	var p := _spawn_player_node(data)
	g.players_node.add_child(p)


func despawn_player_remote(pid: int) -> void:
	# v3.2 QA-047: explicit despawn to match the explicit spawn — the
	# spawner's despawn RPC is the same single channel that lost the
	# spawn in v3.1, so a disconnect is also announced directly.
	var node = g.players_node.get_node_or_null(str(pid))
	if node != null:
		node.queue_free()


func request_player_list() -> void:
	# v3.2 QA-047: a client that missed its spawn asks for the whole
	# player list; the server answers with every spawned player.
	if not g.multiplayer.is_server():
		return
	var sender = g.multiplayer.get_remote_sender_id()
	if sender > 0:
		g.rpc_id(sender, "player_list_remote", _player_list_data())


func player_list_remote(players: Array) -> void:
	# v3.2 QA-047: self-healing sync — the server's player list is
	# the authority. Spawn anything missing locally (including our
	# own player and the host's player, both of which v3.1 could
	# lose), and drop any ghost the server no longer lists.
	g._server_answered = true
	var seen := {}
	for item in players:
		var d := item as Dictionary
		if d.is_empty():
			continue
		seen[int(d.get("id", 0))] = true
		spawn_player_remote(d)
	for child in g.players_node.get_children():
		if not seen.has(int(child.get("peer_id"))):
			child.queue_free()


func request_spawn(pid: int, pname: String, color_idx: int, version: String = "", team_pref: int = -1) -> void:
	# Server only, and only after the client signalled it is ready.
	if not g.multiplayer.is_server():
		return
	# Version handshake (GAP-61, spec §21.G): a mismatched build is
	# refused with a readable message instead of desyncing silently.
	# Empty version = an older test caller; accept it.
	if version != "" and version != GameData.BUILD_VERSION:
		print("VERSION MISMATCH: peer %d runs %s, host runs %s — spawn refused" % [pid, version, GameData.BUILD_VERSION])
		if g.multiplayer.get_peers().has(pid):
			g.rpc_id(pid, "version_mismatch_remote", "Version mismatch: host runs %s, you run %s. Update and rejoin." % [GameData.BUILD_VERSION, version])
		return
	# Validate: the sender must be the peer it claims to be, the room
	# must not be full, and the spawn index must be in range.
	var sender = g.multiplayer.get_remote_sender_id()
	print("SPAWN REQ: from sender=", sender, " claiming pid=", pid, " version='", version, "' players=", g.players_node.get_child_count(), "/", g.max_players)
	if sender != 0 and sender != pid:
		print("SPAWN REQ: REJECTED sender != pid")
		return
	if g.players_node.get_child_count() >= g.max_players:
		print("SPAWN REQ: REJECTED room full")
		return
	_do_spawn(pid, pname, color_idx, team_pref)


func _on_peer_connected(id: int) -> void:
	print("Peer connected: ", id)
	# v2: do NOT spawn here. The client sends request_spawn once its
	# game scene (with MultiplayerSpawner) is ready.
	# v3.2 QA-047: but DO re-send every already-spawned player to the
	# newcomer. The spawner's late-joiner catch-up only covers peers
	# that connect while the spawner is in the tree; our client
	# connected while the host was still in the menu, so without this
	# the host's own player never appears on the client.
	if g.multiplayer.is_server():
		_send_all_players_to(id)


func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: ", id)
	if g.multiplayer.is_server():
		g._spawned.erase(id)
		g._spawn_data.erase(id) # v3.2 QA-047: the list must forget them too
		g._round_wins.erase(id)
		g.game_feed.clear_kill_credit(id) # QA-031: a gone victim holds no lock
		if g.shooting_sync != null:
			g.shooting_sync.reset_peer(id)
		var node = g.players_node.get_node_or_null(str(id))
		if node != null:
			node.queue_free()
		# v3.2 QA-047: tell every remaining client directly (same
		# reason as the explicit spawn: do not rely on the spawner
		# alone for membership changes).
		if g.multiplayer.get_peers().size() > 0:
			g.rpc("despawn_player_remote", id)
		# v2.4: a disconnect mid-match can end a Survival round or a
		# Last Man Standing match — re-check immediately.
		if g.game_mode == 2:
			g.game_match._check_round_end()
		elif g.game_mode == 3:
			g.game_match._check_match_end()


func _on_server_disconnected() -> void:
	if g.match_over:
		return
	# Remember where we were, so the main menu can offer a reconnect.
	GameData.last_host_ip = GameData.host_ip
	g._show_error("The host left the game.")


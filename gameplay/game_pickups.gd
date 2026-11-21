class_name GamePickups
extends RefCounted


# QA-140 (v3.15): extracted from game.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `g` (dependency injection).


var g # the owner (game.gd)


func _init(owner) -> void:
	g = owner


func _spawn_initial_pickups() -> void:
	# 3 pickups present at match start (GAP-37: the map was empty
	# for the first 14 s), from distinct spots. Phase 4: a health
	# pack is always among them, so the new health pickup is visible
	# from the first seconds.
	if not g.multiplayer.is_server():
		return
	var spots: Array = g.MAPS[g.map_id]["pickups"]
	# [spot, kind]: SMG on the left, SNIPER pinned to the centre
	# spot (index 3), Health on the right.
	var init := [[0, 1], [3, 3], [4, 5]]
	for pair in init:
		_spawn_pickup_at(int(pair[0]), int(pair[1]))
	g._centre_kind_next = 4 # the next centre weapon is the Rocket


func _spawn_pickup_at(spot_idx: int, kind: int) -> void:
	var spots: Array = g.MAPS[g.map_id]["pickups"]
	var pos: Vector2 = spots[spot_idx % spots.size()]
	var pname := "pickup_" + str(Time.get_ticks_msec()) + "_" + str(spot_idx)
	g._test_weapon_spawns += 1
	g.rpc("spawn_pickup_remote", pos, pname, kind, spot_idx)


func on_pickup_gone(spot_idx: int) -> void:
	# A pickup was collected or despawned: restart its per-spot
	# 14 s timer (GAP-37). Only the server tracks this.
	# QA-112: power-up spots (100+) restart the 30 s power-up
	# timer instead — they must stay rarer than weapons.
	if spot_idx >= 200:
		# QA-114: comeback bonus (200+team) — the next bonus comes
		# 25 s after this one is collected, via the comeback timer.
		g._sf_comeback_pu_timer = 25.0
		return
	if spot_idx >= 100:
		g._sf_pickup_timers[spot_idx - 100] = g.SF_POWERUP_COOLDOWN
		return
	g._pickup_spot_timers[spot_idx] = 14.0


func _update_pickup_spawn(delta: float) -> void:
	if not g.multiplayer.is_server() or g.match_over:
		return
	if not g._initial_pickups_done:
		g._initial_pickups_done = true
		_spawn_initial_pickups()
	# Per-spot timers (GAP-37): each spot respawns 14 s after its
	# pickup was collected/despawned; total active never exceeds the cap.
	var spots: Array = g.MAPS[g.map_id]["pickups"]
	var active_spots := {}
	var weapon_active := 0
	for child in g.pickups_node.get_children():
		active_spots[int(child.get("spot_index"))] = true
		if int(child.get("kind")) <= 6:
			weapon_active += 1
	for i in spots.size():
		if active_spots.has(i):
			continue
		var t = float(g._pickup_spot_timers.get(i, 0.0)) - delta
		g._pickup_spot_timers[i] = t
		# QA-112: the 3-active cap counts WEAPONS only — Skyfall
		# power-ups (kind 7+) have their own cap (max 2), so a
		# power-up on the field must never block a weapon spawn.
		if t <= 0.0 and weapon_active < 3:
			g._pickup_spot_timers[i] = 14.0
			if i == 3:
				# Centre spot: pinned Sniper/Rocket, alternating.
				_spawn_pickup_at(i, g._centre_kind_next)
				g._centre_kind_next = 3 if g._centre_kind_next == 4 else 4
			else:
				var kinds := [1, 1, 2, 2, 5, 6]
				_spawn_pickup_at(i, kinds[randi() % kinds.size()])


func spawn_pickup_remote(pos: Vector2, pname: String, kind: int, spot_idx: int = -1) -> void:
	if g.pickups_node.has_node(pname):
		return
	var p = g.PICKUP_SCENE.instantiate()
	p.name = pname
	p.position = pos
	p.kind = kind
	p.spot_index = spot_idx
	g.pickups_node.add_child(p)


func _update_join_timeout(delta: float) -> void:
	if g.multiplayer.is_server() or g._join_failed or g.match_over:
		return
	if g.game_hud._get_local_player() != null:
		return
	g._join_timer += delta
	# Spawn retries run every 2 s in _retry_spawn_if_needed; the
	# timeout below is the last resort.
	if g._join_timer >= g.JOIN_TIMEOUT:
		# v3.2 QA-047: show the actual state instead of a generic
		# message, so a Wi-Fi/IP problem can be told apart from a
		# game bug: which IP was tried, whether ENet is up, whether
		# the server answered anything, and how many players were seen.
		var peer = g.multiplayer.multiplayer_peer
		var enet_state := "no network peer"
		if peer is ENetMultiplayerPeer:
			enet_state = "ENet: " + str((peer as ENetMultiplayerPeer).get_connection_status())
		g._show_error("Could not connect to %s.\n%s. Server answered: %s. Players seen: %d/8.\nCheck the Wi-Fi and IP, then tap Retry." % [
			GameData.host_ip if GameData.host_ip != "" else "the host",
			enet_state,
			"yes" if g._server_answered else "no",
			g.players_node.get_child_count()])


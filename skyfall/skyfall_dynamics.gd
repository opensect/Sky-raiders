class_name SkyfallDynamics
extends RefCounted


# QA-139 (v3.15): extracted from game.gd. This module owns no
# state of its own: every field it reads or writes lives on the
# game node and is reached through `g` (dependency injection).
# game.gd keeps a thin delegating wrapper for each function the
# rest of the game calls, so no call site had to change.


var g # the game node (game.gd)


func _init(game) -> void:
	g = game


func _update_skyfall(delta: float) -> void:
	if g.map_id != GameData.SKYFALL_MAP_ID:
		return
	# Match clock (drives the gate + storm + movers). Counts only
	# after the countdown, so every peer agrees on the schedule.
	if not g._countdown_active and not g.match_over:
		g._sf_match_time += delta
	# --- Summit gate: opens 45 s into the match. The side ledges
	# are always open, so it never blocks the climb. ---
	if not g._sf_gate_open and not g.match_over and g._sf_match_time >= 45.0:
		g._sf_gate_open = true
		if g._sf_gate_shape != null:
			g._sf_gate_shape.set_deferred("disabled", true)
		if g._sf_gate_sprite != null:
			g._sf_gate_sprite.visible = false
		g._ctf_feed("The summit gate is open!", Color(0.9, 0.9, 0.9))
	# --- Wind: push every player inside a wind zone (player.gd
	# applies wind_force as extra acceleration). ---
	for child in g.players_node.get_children():
		if "wind_force" in child:
			child.set("wind_force", skyfall_wind_at(child.position))
	# --- Moving elevators + rotating platform: pure functions of
	# the match clock, so every peer agrees with no RPC. ---
	for e in g._sf_elevators:
		var cfg: Dictionary = e["cfg"]
		var period := 6.0
		var t = fmod(g._sf_match_time + float(e.get("phase", 0.0)) * period, period)
		var y: float
		if t < period * 0.5:
			y = lerpf(float(cfg["y_bottom"]), float(cfg["y_top"]), t / (period * 0.5))
		else:
			y = lerpf(float(cfg["y_top"]), float(cfg["y_bottom"]), (t - period * 0.5) / (period * 0.5))
		(e["body"] as AnimatableBody2D).position = Vector2(float(cfg["x"]) + float(cfg["w"]) * 0.5, y + 24.0)
	if not g._sf_rotator.is_empty():
		var rcfg: Dictionary = g._sf_rotator["cfg"]
		var ang = g._sf_match_time * float(rcfg.get("speed", 0.5))
		var centre: Vector2 = rcfg["center"]
		(g._sf_rotator["body"] as AnimatableBody2D).position = centre + Vector2(cos(ang), sin(ang)) * float(rcfg.get("radius", 120.0))
	# --- Control switch: stand within 90 px for 1 s (any player).
	# Activates the summit elevator for 30 s. Detected locally on
	# every peer (the 1 s channel is long enough that all agree). ---
	if not g._sf_summit_elevator.is_empty():
		var sw: Dictionary = g.MAPS[g.map_id].get("switch", {})
		var spos: Vector2 = sw.get("pos", Vector2(1800, 1712))
		var near := false
		for child in g.players_node.get_children():
			if child.alive and child.position.distance_to(spos) < 90.0:
				near = true
				break
		if near and g._sf_summit_timer <= 0.0:
			g._sf_switch_timer += delta
			if g._sf_switch_timer >= 1.0:
				g._sf_switch_timer = 0.0
				g._sf_summit_timer = 30.0
				g._sf_switch_on = true
				g._ctf_feed("Summit elevator activated for 30 s!", Color(0.5, 1.0, 0.5))
		else:
			g._sf_switch_timer = 0.0
		if g._sf_summit_timer > 0.0:
			g._sf_summit_timer -= delta
			_sf_update_summit_elevator(delta)
	# --- Collapsing platforms + trapdoors: local state machines
	# (every peer sees the same player positions, so they agree). ---
	g.skyfall_hazards._sf_update_collapsing(delta)
	g.skyfall_hazards._sf_update_trapdoors(delta)
	# --- Falling rocks (host spawns, all peers simulate the fall). ---
	g.skyfall_hazards._sf_update_rocks(delta)
	# --- Summit Storm every 90 s: lightning strikes the summit. ---
	_sf_update_storm(delta)
	# --- QA-135 (v3.13): L4 storm lightning — its own strike
	# cadence (every 6 s) at a random living player in L4. ---
	_sf_update_strike_l4(delta)
	# --- QA-143 (v4.0) ITEM 11: L5 thunder trap — any player
	# still 5 s on level 5 is struck automatically (no power-up). ---
	_sf_update_thunder_trap_l5(delta)
	# --- QA-126 (v3.11): lava / fire hazard damage ticks. ---
	g.skyfall_hazards._sf_update_hazards(delta)
	# --- QA-137 (v3.14): swinging wrecking-ball pendulums. ---
	g.skyfall_hazards._sf_update_pendulums(delta)
	# --- QA-145 (v4.1, Worker T): proximity mines. ---
	g.skyfall_hazards._sf_update_mines(delta)
	# --- Dynamic scenery (QA-115): clouds, waterfall, helicopter,
	# gears, steam, storm lightning — scenery only. ---
	_update_skyfall_scenery(delta)
	# --- Barricade respawn (host only; clients get the RPC). ---
	if g.multiplayer.is_server():
		for b in g._sf_barricades:
			if not bool(b["alive"]):
				b["timer"] = float(b["timer"]) - delta
				if float(b["timer"]) <= 0.0:
					b["alive"] = true
					b["hp"] = 100.0
					(b["sprite"] as Node2D).visible = true
					if b["shape"] != null:
						(b["shape"] as CollisionShape2D).set_deferred("disabled", false)
					g.rpc("sf_barricade_remote", g._sf_barricades.find(b), true)
	# --- CTF checkpoints (QA-114, v3.9): a team's checkpoint is the
	# HIGHEST level any living member currently stands at or above
	# (levels 2, 4, 6 — QA-123 rebuild). It is
	# recomputed live every frame, so it ADVANCES as the team climbs
	# and DROPS BACK DOWN when the team loses the level (everyone
	# dead or fallen below it) — dying on level 7 no longer sends a
	# player back to the bottom while the team still holds 7, and
	# losing 7 drops the respawn back to 5 (or 3, or base). The
	# thresholds come from the checkpoint spots themselves (their
	# y), so the list stays configurable in one place (map data
	# "checkpoints" + GameData.SF_CHECKPOINT_LEVELS). Host tracks,
	# ctf_sync carries it to clients.
	# GRACE (QA-114): when a team has NO living members at all, the
	# checkpoint FREEZES for 5 s instead of dropping instantly —
	# a single death (respawn 3 s) must not drop the respawn to the
	# bottom while the team still held the level. Only a full wipe
	# that lasts 5 s drops it. A living member walking down drops
	# it immediately (no grace — the team is alive and below).
	if g.game_mode == 4 and g.multiplayer.is_server() and not g.match_over:
		var cps: Array = g.MAPS[g.map_id].get("checkpoints", [])
		if cps.size() >= 4:
			var held := {0: 0, 1: 0}
			var any_alive := {0: false, 1: false}
			for child in g.players_node.get_children():
				if not child.alive:
					continue
				var team := int(child.team)
				if team < 0 or team > 1:
					continue
				any_alive[team] = true
				var y: float = child.position.y
				# Checkpoint spots sit ~34 px above the platform
				# top (the player's centre stands 31 px above it)
				# — allow a 40 px tolerance or a standing player
				# never counts as "at" the level (the L6 spot is
				# 1678 but a standing player is at y 1681).
				var lvl := 0
				if y <= float((cps[3] as Array)[team].y) + 40.0:
					lvl = 3
				elif y <= float((cps[2] as Array)[team].y) + 40.0:
					lvl = 2
				elif y <= float((cps[1] as Array)[team].y) + 40.0:
					lvl = 1
				held[team] = maxi(int(held[team]), lvl)
			for team in [0, 1]:
				var prev = int(g._ctf_checkpoints.get(team, 0))
				var now := int(held[team])
				if bool(any_alive[team]):
					g._ctf_hold_grace[team] = 0.0
					if now != prev:
						g._ctf_checkpoints[team] = now
						if now > prev:
							g._ctf_feed("⚑ %s holds Level %d — respawn moved up!" % ["RED" if team == 0 else "BLUE", GameData.SF_CHECKPOINT_LEVELS[now]], g._ctf_team_color(team))
						else:
							g._ctf_feed("⚑ %s lost Level %d — respawn moved back down." % ["RED" if team == 0 else "BLUE", GameData.SF_CHECKPOINT_LEVELS[prev]], g._ctf_team_color(team))
				elif prev > 0:
					# Whole team dead: freeze the checkpoint for 5 s.
					var local_g = float(g._ctf_hold_grace.get(team, 0.0)) + delta
					g._ctf_hold_grace[team] = local_g
					if local_g >= 5.0:
						g._ctf_hold_grace[team] = 0.0
						g._ctf_checkpoints[team] = 0
						g._ctf_feed("⚑ %s lost Level %d — respawn moved back down." % ["RED" if team == 0 else "BLUE", GameData.SF_CHECKPOINT_LEVELS[prev]], g._ctf_team_color(team))
	# --- Power-up spawning (host only; rarer than weapons — see
	# _update_skyfall_powerups). ---
	g._update_skyfall_powerups(delta)
	# --- Comeback help + random events (QA-114, host only). ---
	_sf_update_comeback(delta)
	_sf_update_random_events(delta)
	# --- QA-145 (v4.1, Worker T): supply-drop beacon countdown
	# (runs on every peer — each counts its own 10 s from the RPC). ---
	_sf_update_beacon(delta)
	# --- Extraction-zone pulse. ---
	var pulse = 0.9 + 0.1 * sin(g._sf_match_time * 3.0)
	for z in g._ctf_extract_nodes:
		(z as Sprite2D).scale = Vector2(pulse, pulse)
	# --- Team pings (QA-114): 5 s lifetime, 3 s cooldown. ---
	if g._sf_ping_cooldown > 0.0:
		g._sf_ping_cooldown -= delta
	for i in range(g._sf_pings.size() - 1, -1, -1):
		var pg: Dictionary = g._sf_pings[i]
		pg["timer"] = float(pg.get("timer", 0.0)) - delta
		if float(pg.get("timer", 0.0)) <= 0.0:
			if is_instance_valid(pg.get("node")):
				(pg["node"] as Node).queue_free()
			if is_instance_valid(pg.get("label")):
				(pg["label"] as Node).queue_free()
			g._sf_pings.remove_at(i)
	# --- CTF (flags, grabs, captures). ---
	g._update_ctf(delta)


func _sf_trailing_team() -> int:
	# QA-114 (v3.9): the team behind by >= 2 points is the trailing
	# team (-1 when the scores are level or within 1). Pure — from
	# _ctf_scores only, so every peer computes the same answer and
	# the HUD agrees on all phones. CTF only.
	if g.game_mode != 4:
		return -1
	var red = int(g._ctf_scores.get(0, 0))
	var blue = int(g._ctf_scores.get(1, 0))
	if red - blue >= 2:
		return 1
	if blue - red >= 2:
		return 0
	return -1


func _sf_update_comeback(delta: float) -> void:
	# QA-114 (v3.9): COMEBACK HELP — the trailing team gets a modest
	# advantage, never a guaranteed win: (1) the summit elevator
	# runs continuously while they trail (the switch normally gives
	# 30 s; the comeback tops the timer up so it never docks), and
	# (2) a bonus power-up spawns near their base every 25 s.
	# Both teams see it in the HUD, so it is never a hidden buff.
	# The leading team KEEPS its checkpoint — comeback help and
	# checkpoints do not cancel each other (opposite-feature rule).
	var trail := _sf_trailing_team()
	if trail != g._sf_comeback_team:
		if trail >= 0:
			g._ctf_feed("COMEBACK: %s is behind — summit elevator running + extra power-ups at their base!" % ("RED" if trail == 0 else "BLUE"), Color(1.0, 0.8, 0.2))
			g._sf_comeback_pu_timer = 5.0 # first bonus arrives fast
		g._sf_comeback_team = trail
	if not g.multiplayer.is_server() or g.match_over or trail < 0:
		return
	# (1) Elevator: keep the timer topped up so it never docks
	# while the comeback is active. Runs after the switch block's
	# decrement, so the top-up wins every frame.
	g._sf_summit_timer = maxf(g._sf_summit_timer, 5.0)
	# (2) Bonus power-up near the trailing team's base (their own
	# side only — never on a level the other team holds).
	g._sf_comeback_pu_timer -= delta
	if g._sf_comeback_pu_timer > 0.0:
		return
	g._sf_comeback_pu_timer = 25.0
	var spot := 200 + trail
	var active := false
	for child in g.pickups_node.get_children():
		if int(child.get("spot_index")) == spot:
			active = true
			break
	if active:
		return
	var kind := randi_range(8, 13)
	var pos := Vector2(700, 10548) if trail == 0 else Vector2(2900, 10548)
	var pname := "sfcomeback_" + str(Time.get_ticks_msec()) + "_" + str(trail)
	g.rpc("spawn_pickup_remote", pos, pname, kind, spot)


func _sf_update_random_events(delta: float) -> void:
	# QA-114 (v3.9): RANDOM mid-match events — the fixed 90 s Summit
	# Storm alone is too predictable, so events fire at RANDOM times
	# (45-90 s apart) with a RANDOM type: supply drop, collapsing
	# level, or route shift. Announced to both teams in the feed.
	# Independent of the storm timer, so an event CAN coincide with
	# a storm — that combination is tested, not prevented.
	if not g.multiplayer.is_server() or g.match_over or g._countdown_active:
		return
	if g._sf_event_active != "":
		g._sf_event_time_left -= delta
		if g._sf_event_time_left <= 0.0:
			if g._sf_event_active == "route_shift":
				g._sf_event_wind_flip = false
				g._ctf_feed("EVENT over: the wind is back to normal.", Color(0.9, 0.9, 0.9))
			g._sf_event_active = ""
			g._sf_event_timer = randf_range(45.0, 90.0)
		return
	if g._sf_event_timer <= 0.0:
		g._sf_event_timer = randf_range(45.0, 90.0)
		return
	g._sf_event_timer -= delta
	if g._sf_event_timer > 0.0:
		return
	match randi() % 3:
		0:
			_sf_event_supply_drop()
			g._sf_event_active = "supply_drop"
			g._sf_event_time_left = 1.0 # instant effect; ends next frame
		1:
			_sf_event_collapse()
			g._sf_event_active = "collapse"
			g._sf_event_time_left = 1.0 # the collapse runs its own 8 s cycle
		2:
			g._sf_event_wind_flip = true
			g._sf_event_active = "route_shift"
			g._sf_event_time_left = 20.0
			g._ctf_feed("EVENT: ROUTE SHIFT! The wind has reversed for 20 s!", Color(0.6, 0.9, 1.0))


func _sf_event_supply_drop() -> void:
	# A weapon or power-up drops on a random reachable platform.
	var plats: Array = g.MAPS[g.map_id].get("platforms", [])
	if plats.is_empty():
		return
	var r: Rect2 = plats[randi() % plats.size()]
	var pos := r.get_center() + Vector2(0, -60)
	var kind := randi_range(1, 6) if randi() % 2 == 0 else randi_range(8, 13)
	var pname := "sfsupply_" + str(Time.get_ticks_msec())
	# Event drops do NOT count toward the FT-SF-RARITY test — that
	# test measures the regular spawn loop only.
	g.rpc("spawn_pickup_remote", pos, pname, kind, -1)
	# QA-145 (v4.1, Worker T): the drop was announced in the feed
	# but invisible across the tower — RPC the beacon too, so every
	# peer sees the green pillar marking the landing spot.
	g.rpc("sf_beacon_remote", pos)
	g._ctf_feed("EVENT: SUPPLY DROP! Something landed on the tower — go get it!", Color(0.6, 1.0, 0.6))


func _sf_build_beacon(pos: Vector2) -> void:
	# QA-145 (v4.1, Worker T): supply-drop beacon — a green light
	# pillar (600 px tall) + a pulsing ground ring marking the
	# landing spot for 10 s. Code-drawn, no new art. Replaces any
	# live beacon (only one drop at a time — the event timer blocks
	# overlap). Called on every peer via sf_beacon_remote.
	_sf_clear_beacon()
	var beam := Polygon2D.new()
	beam.polygon = PackedVector2Array([Vector2(-20, 0), Vector2(20, 0), Vector2(20, -600), Vector2(-20, -600)])
	beam.color = Color(0.4, 1.0, 0.5, 0.30)
	beam.position = pos
	beam.z_index = 1
	g.add_child(beam)
	var ring := Polygon2D.new()
	var rpts := PackedVector2Array()
	for i in 24:
		var a := TAU * float(i) / 24.0
		rpts.append(Vector2(cos(a), sin(a)) * 60.0)
	ring.polygon = rpts
	ring.color = Color(0.4, 1.0, 0.5, 0.5)
	ring.position = pos + Vector2(0, 8)
	ring.z_index = 1
	g.add_child(ring)
	g._sf_beacon = {"pos": pos, "beam": beam, "ring": ring, "timer": 10.0}


func _sf_update_beacon(delta: float) -> void:
	if g._sf_beacon.is_empty():
		return
	var beam: Node = g._sf_beacon.get("beam")
	if beam == null or not is_instance_valid(beam):
		g._sf_beacon = {}
		return
	var t := float(g._sf_beacon.get("timer", 0.0)) - delta
	g._sf_beacon["timer"] = t
	if t <= 0.0:
		_sf_clear_beacon()
		return
	# The ring breathes (alpha 0.3-0.65) so the spot reads at a
	# glance from two levels down.
	var ring: Polygon2D = g._sf_beacon.get("ring")
	if ring != null and is_instance_valid(ring):
		var c: Color = ring.color
		c.a = 0.3 + 0.35 * (0.5 + 0.5 * sin(g._sf_match_time * 4.0))
		ring.color = c


func _sf_clear_beacon() -> void:
	if g._sf_beacon.is_empty():
		return
	for k in ["beam", "ring"]:
		var n: Node = g._sf_beacon.get(k)
		if n != null and is_instance_valid(n):
			n.queue_free()
	g._sf_beacon = {}


func _sf_event_collapse() -> void:
	# A random bridge-level platform collapses (same 0.8 s shake ->
	# fall -> 8 s gone -> back cycle as the built-in collapsing
	# platform). Never a spawn, checkpoint, relay, extraction, or
	# summit platform — those are protected, so the event can never
	# remove a route home or a respawn.
	var plats: Array = g.MAPS[g.map_id].get("platforms", [])
	var protected: Array = []
	for sp in g.MAPS[g.map_id].get("spawns", []):
		protected.append(sp)
	for cps in g.MAPS[g.map_id].get("checkpoints", []):
		for cp in cps:
			protected.append(cp)
	for rp in g.MAPS[g.map_id].get("relay", []):
		protected.append(rp)
	var ctf: Dictionary = g.MAPS[g.map_id].get("ctf", {})
	protected.append(ctf.get("extract_red", Vector2.ZERO))
	protected.append(ctf.get("extract_blue", Vector2.ZERO))
	var candidates: Array = []
	for i in plats.size():
		var r: Rect2 = plats[i]
		if int(i) in (g.MAPS[g.map_id].get("collapsing", []) as Array): # already a built-in collapsing platform
			continue
		var safe := true
		for pp in protected:
			if absf(float(pp.y) - float(r.position.y)) < 120.0 and float(pp.x) >= float(r.position.x) - 100.0 and float(pp.x) <= float(r.end.x) + 100.0:
				safe = false
				break
		if safe:
			candidates.append(i)
	if candidates.is_empty():
		return
	var idx: int = candidates[randi() % candidates.size()]
	var rect: Rect2 = plats[idx]
	for c in g._sf_collapsing:
		if int(c.get("idx", -1)) == idx:
			c["state"] = "shaking"
			c["timer"] = 0.8
			g._sf_event_collapse_idx = idx
			g._ctf_feed("EVENT: A LEVEL IS COLLAPSING! Watch your step!", Color(1.0, 0.6, 0.2))
			return
	g._sf_collapsing.append({"idx": idx, "rect": rect, "shape": g._sf_arena_shape_at(rect.get_center()), "sprites": g._sf_tile_sprites_at(rect), "state": "shaking", "timer": 0.8})
	g._sf_event_collapse_idx = idx
	g._ctf_feed("EVENT: A LEVEL IS COLLAPSING! Watch your step!", Color(1.0, 0.6, 0.2))


func _sf_update_summit_elevator(delta: float) -> void:
	# Shuttles arena <-> summit while active: up 4 s, wait 6 s at
	# the top, down 4 s, wait 6 s at the bottom, repeat. Docked at
	# the arena when the timer runs out.
	var se: Dictionary = g._sf_summit_elevator
	var body := se["body"] as AnimatableBody2D
	var cfg: Dictionary = se["cfg"]
	var y_top := float(cfg["y_top"])
	var y_bot := float(cfg["y_bottom"])
	var state: String = str(se.get("state", "docked"))
	var timer := float(se.get("timer", 0.0)) + delta
	se["timer"] = timer
	var x := float(cfg["x"]) + float(cfg.get("w", 300)) * 0.5
	match state:
		"docked":
			body.position = Vector2(x, y_bot + 24.0)
			if g._sf_summit_timer > 0.0:
				se["state"] = "up"
				se["timer"] = 0.0
		"up":
			var k := clampf(timer / 4.0, 0.0, 1.0)
			body.position = Vector2(x, lerpf(y_bot, y_top, k) + 24.0)
			if timer >= 4.0:
				se["state"] = "top"
				se["timer"] = 0.0
		"top":
			body.position = Vector2(x, y_top + 24.0)
			if timer >= 6.0 or g._sf_summit_timer <= 0.0:
				se["state"] = "down"
				se["timer"] = 0.0
		"down":
			var k := clampf(timer / 4.0, 0.0, 1.0)
			body.position = Vector2(x, lerpf(y_top, y_bot, k) + 24.0)
			if timer >= 4.0:
				se["state"] = "bottom"
				se["timer"] = 0.0
		"bottom":
			body.position = Vector2(x, y_bot + 24.0)
			if timer >= 6.0 or g._sf_summit_timer <= 0.0:
				se["state"] = "docked" if g._sf_summit_timer <= 0.0 else "up"
				se["timer"] = 0.0


func _sf_player_standing_on(rect: Rect2) -> bool:
	# Any alive player whose feet are on this platform (within
	# 8 px of its top, inside its x-range).
	for child in g.players_node.get_children():
		if not child.alive:
			continue
		var feet: Vector2 = child.position + Vector2(0, 31)
		if feet.x >= rect.position.x - 4.0 and feet.x <= rect.end.x + 4.0 and absf(feet.y - rect.position.y) <= 8.0:
			return true
	return false












func _sf_update_storm(delta: float) -> void:
	# Summit Storm every 90 s: lightning strikes the summit for
	# 10 s (telegraphs + damage + rumble). Driven by the match
	# clock, so every peer agrees with no RPC.
	# QA-132: the storm NO LONGER disables platforms — the two
	# L6 side perches went visible-but-unlandable for 10 s every
	# storm (user report), so the disable mechanic is deleted;
	# the perches stay landable through every storm.
	if g.match_over or g._countdown_active:
		return
	if g._sf_storm_active:
		g._sf_storm_time_left -= delta
		# Lightning flicker while the storm runs.
		for n in g._sf_storm_nodes:
			(n as Sprite2D).modulate.a = 0.5 + 0.5 * sin(g._sf_match_time * 9.0 + float((n as Sprite2D).position.x))
		# QA-126 (v3.11): LIGHTNING STRIKES — every 3 s a bolt is
		# telegraphed (ground ring + bolt sprite, 0.6 s warning) at
		# a random player in the top two levels (L5/L6, y < 3600),
		# then hits for 15 damage if they are still within 200 px
		# of the marker — step away and it misses. Host picks the
		# target; the marker is local (every peer sees the same
		# match clock, so the strike schedule agrees).
		_sf_update_strike(delta)
		if g._sf_storm_time_left <= 0.0:
			g._sf_storm_active = false
			g._sf_storm_timer = 90.0
			_sf_clear_strike_marker() # never leave a telegraph hanging
			g._sf_strike_timer = 3.0
			for n in g._sf_storm_nodes:
				(n as Sprite2D).visible = false
			g._ctf_feed("The storm has passed.", Color(0.8, 0.85, 1.0))
		return
	g._sf_storm_timer -= delta
	if g._sf_storm_timer <= 0.0:
		g._sf_storm_active = true
		g._sf_storm_time_left = 10.0
		if g._sf_storm_nodes.is_empty():
			for lx in [900, 1800, 2700]:
				var bolt := Sprite2D.new()
				bolt.texture = GameAssets.SF_TEX_LIGHTNING
				bolt.position = Vector2(lx, 500)
				bolt.z_index = 4
				g.add_child(bolt)
				g._sf_storm_nodes.append(bolt)
		for n in g._sf_storm_nodes:
			(n as Sprite2D).visible = true
		g._ctf_feed("SUMMIT STORM! Lightning strikes the summit!", Color(0.65, 0.8, 1.0))
		# QA-126 (v3.11): storm rumble once per storm (map-wide event).
		if g.audio != null:
			g.audio.play("storm")


func _sf_update_strike(delta: float) -> void:
	# QA-126 (v3.11): one lightning strike every 3 s while the storm
	# runs. Two phases: TELEGRAPH (0.6 s — red ground ring + bolt
	# sprite at the target's feet) then HIT (15 damage if the target
	# is still within 200 px, else a miss). The shield absorbs the
	# hit (take_damage), the victim flashes + shakes, and a
	# shockwave ring blooms at the strike point.
	if not g._sf_strike.is_empty():
		var t = float(g._sf_strike.get("timer", 0.0)) - delta
		g._sf_strike["timer"] = t
		if t <= 0.0:
			var pos: Vector2 = g._sf_strike["pos"]
			var peer: int = int(g._sf_strike.get("peer", -1))
			_sf_clear_strike_marker()
			if g.multiplayer.is_server() and peer >= 0:
				for child in g.players_node.get_children():
					if not child.alive:
						continue
					if int(child.get_multiplayer_authority()) != peer:
						continue
					if child.position.distance_to(pos) <= 200.0:
						g.skyfall_hazards._sf_damage_player(child, 15)
					break
			_sf_spawn_shockwave(pos)
			_sf_play_hazard_sound("thunder", pos, 1400.0)
			if g._sf_scenery.get("flash") != null:
				g._sf_scenery["flash_alpha"] = 0.15
		return
	g._sf_strike_timer -= delta
	if g._sf_strike_timer > 0.0:
		return
	g._sf_strike_timer = 3.0
	var cands: Array = []
	for child in g.players_node.get_children():
		if child.alive and child.position.y < 3600.0:
			cands.append(child)
	var pos := Vector2.ZERO
	var peer := -1
	if not cands.is_empty():
		var target: Node = cands[randi() % cands.size()]
		pos = target.position + Vector2(0, 31)
		peer = int(target.get_multiplayer_authority())
	else:
		# Nobody up top: strike a random summit platform (visual only).
		var plats: Array = g.MAPS[g.map_id].get("platforms", [])
		var r: Rect2 = plats[randi() % plats.size()]
		if r.position.y > 1800.0:
			r = plats[52] # QA-132: summit floor (was plats[67] in the 98-list)
		pos = r.get_center() + Vector2(0, -24)
	var ring := Line2D.new()
	ring.width = 5.0
	ring.default_color = Color(1.0, 0.25, 0.2, 0.9)
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * float(i) / 24.0
		pts.append(pos + Vector2(cos(a), sin(a)) * 60.0)
	pts.append(pos + Vector2(60.0, 0))
	ring.points = pts
	ring.z_index = 4
	g.add_child(ring)
	var bolt := Sprite2D.new()
	bolt.texture = GameAssets.FX_TEX_BOLT if randi() % 2 == 0 else GameAssets.FX_TEX_FORKED
	bolt.position = pos + Vector2(0, -120)
	bolt.scale = Vector2(0.7, 0.7)
	bolt.modulate = Color(1, 1, 1, 0.9)
	bolt.z_index = 4
	g.add_child(bolt)
	g._sf_strike = {"peer": peer, "pos": pos, "ring": ring, "bolt": bolt, "timer": 0.6}


func _sf_clear_strike_marker() -> void:
	if g._sf_strike.is_empty():
		return
	for k in ["ring", "bolt"]:
		var n: Node = g._sf_strike.get(k)
		if n != null and is_instance_valid(n):
			n.queue_free()
	g._sf_strike = {}


func _sf_update_strike_l4(delta: float) -> void:
	# QA-135 (v3.13): L4 storm lightning — same strike shape as
	# the Summit Storm (0.6 s telegraph: red ground ring + bolt
	# sprite, then 15 damage if the target is still within 200 px
	# — step away and it misses; shield absorbs it), but its own
	# cadence (one bolt every 6 s) and its own zone (a random
	# living player in L4, y 3600-5400). Runs all match, not only
	# during a storm. Host picks the target; the marker is local
	# (every peer sees the same match clock, so the strike
	# schedule agrees). No player in L4: no strike that cycle.
	if g.match_over or g._countdown_active:
		return
	if not g._sf_strike_l4.is_empty():
		var t = float(g._sf_strike_l4.get("timer", 0.0)) - delta
		g._sf_strike_l4["timer"] = t
		if t <= 0.0:
			var pos: Vector2 = g._sf_strike_l4["pos"]
			var peer: int = int(g._sf_strike_l4.get("peer", -1))
			_sf_clear_strike_l4_marker()
			if g.multiplayer.is_server() and peer >= 0:
				for child in g.players_node.get_children():
					if not child.alive:
						continue
					if int(child.get_multiplayer_authority()) != peer:
						continue
					if child.position.distance_to(pos) <= 200.0:
						g.skyfall_hazards._sf_damage_player(child, 15)
					break
			_sf_spawn_shockwave(pos)
			_sf_play_hazard_sound("thunder", pos, 1400.0)
			if g._sf_scenery.get("flash") != null:
				g._sf_scenery["flash_alpha"] = 0.15
		return
	g._sf_strike_l4_timer -= delta
	if g._sf_strike_l4_timer > 0.0:
		return
	g._sf_strike_l4_timer = 6.0
	var cands: Array = []
	for child in g.players_node.get_children():
		if child.alive and child.position.y >= 3600.0 and child.position.y < 5400.0:
			cands.append(child)
	if cands.is_empty():
		return
	var target: Node = cands[randi() % cands.size()]
	var pos: Vector2 = target.position + Vector2(0, 31)
	var peer := int(target.get_multiplayer_authority())
	var ring := Line2D.new()
	ring.width = 5.0
	ring.default_color = Color(1.0, 0.25, 0.2, 0.9)
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * float(i) / 24.0
		pts.append(pos + Vector2(cos(a), sin(a)) * 60.0)
	pts.append(pos + Vector2(60.0, 0))
	ring.points = pts
	ring.z_index = 4
	g.add_child(ring)
	var bolt := Sprite2D.new()
	bolt.texture = GameAssets.FX_TEX_BOLT if randi() % 2 == 0 else GameAssets.FX_TEX_FORKED
	bolt.position = pos + Vector2(0, -120)
	bolt.scale = Vector2(0.7, 0.7)
	bolt.modulate = Color(1, 1, 1, 0.9)
	bolt.z_index = 4
	g.add_child(bolt)
	g._sf_strike_l4 = {"peer": peer, "pos": pos, "ring": ring, "bolt": bolt, "timer": 0.6}


func _sf_clear_strike_l4_marker() -> void:
	if g._sf_strike_l4.is_empty():
		return
	for k in ["ring", "bolt"]:
		var n: Node = g._sf_strike_l4.get(k)
		if n != null and is_instance_valid(n):
			n.queue_free()
	g._sf_strike_l4 = {}


func _sf_update_thunder_trap_l5(delta: float) -> void:
	# QA-143 (v4.0) ITEM 11 — Level 5 thunder TRAP. Separate from
	# the Thunder Strike power-up (item 9): no power-up is involved
	# and no one activates anything. Any living player, either
	# team, who stands still in the same place for 5 s on level 5
	# (Mechanical Ascent) is struck automatically. Two phases, same
	# shape as the L4 strike: TELEGRAPH (0.6 s — red ground ring +
	# latest-asset bolt, RPC'd so every peer sees the warning) then
	# HIT (15 HP — the QA-126 storm-lightning value, NOT the
	# power-up's health-halving — if the target is still within
	# 200 px; step away and it misses; shield absorbs it via
	# _sf_damage_player). Host-authoritative: only the host picks
	# the victim and lands the damage. The still clock restarts
	# after a strike, so a player who keeps standing still is
	# struck again after another full 5 s. One victim at a time
	# (the longest-still); a second still player is picked next.
	if g.map_id != GameData.SKYFALL_MAP_ID:
		return
	if g.match_over or g._countdown_active:
		return
	if not g._sf_trap_l5.is_empty():
		var t = float(g._sf_trap_l5.get("timer", 0.0)) - delta
		g._sf_trap_l5["timer"] = t
		if t <= 0.0:
			var pos: Vector2 = g._sf_trap_l5["pos"]
			var peer: int = int(g._sf_trap_l5.get("peer", -1))
			g._sf_trap_l5 = {}
			if g.multiplayer.is_server() and peer >= 0:
				for child in g.players_node.get_children():
					if not child.alive:
						continue
					if int(child.get_multiplayer_authority()) != peer:
						continue
					if child.position.distance_to(pos) <= 200.0:
						g.skyfall_hazards._sf_damage_player(child, 15)
					break
				g.skyfall_powerups._sf_reset_still(peer)
				if g.has_method("show_thunder_strike_fx"):
					g.rpc("show_thunder_strike_fx", pos + Vector2(0, -31))
		return
	if not g.multiplayer.is_server():
		return
	var best: Node = null
	var best_still := 0.0
	for child in g.players_node.get_children():
		if not child.alive:
			continue
		if g.skyfall_helpers._sf_level_of(child.position.y) != 5:
			continue
		var s: float = g.skyfall_powerups._sf_still_seconds(child)
		if s >= 5.0 and s > best_still:
			best_still = s
			best = child
	if best == null:
		return
	var pos: Vector2 = best.position + Vector2(0, 31)
	var peer := int(best.get_multiplayer_authority())
	g._sf_trap_l5 = {"peer": peer, "pos": pos, "timer": 0.6}
	if g.has_method("show_thunder_trap_telegraph"):
		g.rpc("show_thunder_trap_telegraph", pos)


func show_thunder_trap_telegraph(pos: Vector2) -> void:
	# QA-143 ITEM 11: the trap's 0.6 s warning — red ground ring
	# + the LATEST thunder asset (assets/user_assets_v3/
	# thunder_strike.png, 1252x1568, so scale 0.25 keeps the bolt
	# ~310 px tall like the L4 telegraph). RPC'd by the host, so
	# every peer draws it; it frees itself after 0.6 s, in step
	# with the host's strike countdown.
	var ring := Line2D.new()
	ring.width = 5.0
	ring.default_color = Color(1.0, 0.25, 0.2, 0.9)
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * float(i) / 24.0
		pts.append(pos + Vector2(cos(a), sin(a)) * 60.0)
	pts.append(pos + Vector2(60.0, 0))
	ring.points = pts
	ring.z_index = 4
	g.add_child(ring)
	var bolt := Sprite2D.new()
	bolt.texture = GameAssets.FX_TEX_THUNDER
	bolt.position = pos + Vector2(0, -120)
	bolt.scale = Vector2(0.25, 0.25)
	bolt.modulate = Color(1, 1, 1, 0.9)
	bolt.z_index = 4
	g.add_child(bolt)
	var tw = g.create_tween()
	tw.tween_interval(0.6)
	tw.tween_callback(ring.queue_free)
	tw.tween_callback(bolt.queue_free)


func show_wind_tornado_fx(pos: Vector2) -> void:
	# QA-145 (v4.1): Wind Blast tornado — the user's fire-tornado
	# frames (3 rotation variants) as an AnimatedSprite2D at ~8 fps,
	# replacing the QA-135 code-drawn funnel (4 ellipses + dust
	# sprite — the tornado frames already carry embers/dust at the
	# base, so the dust sprite is dropped). Mechanics untouched
	# (pull 0.7 s, throw down, no damage, shield does not stop it).
	# The tornado is now FIRE-coloured for a wind power-up — a
	# slight thematic mismatch, but exactly what the user asked.
	# Sender guard: only the host (id 1, or 0 in a local sim) may
	# trigger it. Spins for ~1 s, then fades.
	var sender = g.multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	g.audio.play("wind")
	if g._wind_tornado_node != null and is_instance_valid(g._wind_tornado_node):
		g._wind_tornado_node.queue_free()
	var n := Node2D.new()
	n.position = pos + Vector2(0, -90)
	n.z_index = 6
	g.add_child(n)
	var frames := SpriteFrames.new()
	frames.add_animation("spin")
	frames.set_animation_speed("spin", 8.0)
	frames.set_animation_loop("spin", true)
	for ftex in GameAssets.FX_TEX_FIRE_TORNADO:
		frames.add_frame("spin", ftex)
	var torn := AnimatedSprite2D.new()
	torn.sprite_frames = frames
	torn.animation = "spin"
	torn.scale = Vector2(0.8, 0.8)
	torn.play()
	n.add_child(torn)
	g._wind_tornado_node = n
	var tw = g.create_tween()
	tw.tween_property(n, "rotation", TAU, 0.55)
	tw.tween_property(n, "rotation", TAU * 2.0, 0.45)
	tw.tween_property(n, "modulate:a", 0.0, 0.2)
	tw.tween_callback(n.queue_free)
	tw.tween_callback(_clear_wind_tornado_node.bind(n))


func _clear_wind_tornado_node(n: Node2D) -> void:
	# QA-135: the tornado frees itself after the fade — clear the
	# reference, or it dangles and any later typed read of it
	# errors ("Trying to assign invalid previously freed
	# instance"). Only clears if it still points at THIS tornado
	# (a newer tornado may have replaced it).
	if g._wind_tornado_node == n:
		g._wind_tornado_node = null


func show_thunder_strike_fx(pos: Vector2) -> void:
	# QA-119 (v3.11): Thunder Strike bolt — the host RPCs it, so
	# every peer sees the same strike at the same spot and hears
	# the crack once. Sender guard: only the host (id 1, or 0 in a
	# local sim) may trigger it.
	var sender = g.multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	g.audio.play("thunder")
	var bolt := Sprite2D.new()
	bolt.texture = GameAssets.FX_TEX_THUNDER
	bolt.position = pos
	# QA-137: the new bolt art is 1252x1568 (was 512x512), so the
	# scale drops to 0.22->0.30 to keep the same ~280-380 px strike.
	bolt.scale = Vector2(0.22, 0.22)
	bolt.z_index = 6
	g.add_child(bolt)
	var tw = g.create_tween()
	tw.tween_property(bolt, "scale", Vector2(0.30, 0.30), 0.15)
	tw.tween_property(bolt, "modulate:a", 0.0, 0.45)
	tw.tween_callback(bolt.queue_free)


func _sf_spawn_shockwave(pos: Vector2) -> void:
	# One-shot expanding ring (fades in _update_skyfall_scenery).
	var sw := Sprite2D.new()
	sw.texture = GameAssets.FX_TEX_SHOCKWAVE
	sw.position = pos
	sw.scale = Vector2(0.3, 0.3)
	sw.modulate = Color(1, 1, 1, 0.9)
	sw.z_index = 4
	g.add_child(sw)
	var shots: Array = g._sf_scenery.get("one_shots", [])
	shots.append({"node": sw, "t": 0.0})
	g._sf_scenery["one_shots"] = shots






func _update_skyfall_scenery(delta: float) -> void:
	# QA-115 (v3.9): animate the scenery — all cheap transforms,
	# no allocations, no gameplay reads. Runs on every peer (pure
	# functions of _sf_match_time + delta), so all phones agree.
	if g._sf_scenery.is_empty():
		return
	for c in g._sf_scenery.get("clouds", []):
		var node: Node2D = c["node"]
		node.position.x += float(c["speed"]) * delta
		if node.position.x > 3800.0:
			node.position.x = -400.0
	for st in g._sf_scenery.get("streaks", []):
		var line := st as Line2D
		var pts: PackedVector2Array = line.points
		pts[0].y += 140.0 * delta
		pts[1].y += 140.0 * delta
		if pts[0].y > 10480.0:
			pts[0].y = 9320.0
			pts[1].y = 9420.0
		line.points = pts
	var heli: Node2D = g._sf_scenery.get("heli")
	if heli != null:
		heli.position.x += 55.0 * delta
		if heli.position.x > 3800.0:
			heli.position.x = -200.0
			heli.position.y = 420.0 + randf() * 300.0
	# Distant lightning: only during the Summit Storm, at random
	# 2-5 s gaps — a brief pale flash over the sky.
	if g._sf_storm_active:
		g._sf_scenery["flash_timer"] = float(g._sf_scenery.get("flash_timer", 3.0)) - delta
		if float(g._sf_scenery.get("flash_timer", 0.0)) <= 0.0:
			g._sf_scenery["flash_timer"] = randf_range(2.0, 5.0)
			g._sf_scenery["flash_alpha"] = 0.10
		var fa = float(g._sf_scenery.get("flash_alpha", 0.0))
		if fa > 0.0:
			fa = maxf(0.0, fa - delta * 0.8)
			g._sf_scenery["flash_alpha"] = fa
		var flash: Polygon2D = g._sf_scenery.get("flash")
		if flash != null:
			var fcol: Color = flash.color
			fcol.a = fa
			flash.color = fcol
	elif g._sf_scenery.get("flash") != null:
		var flash2: Polygon2D = g._sf_scenery.get("flash")
		var fcol2: Color = flash2.color
		fcol2.a = 0.0
		flash2.color = fcol2
	# QA-126 (v3.11): one-shot shockwave rings (lightning strikes) —
	# expand + fade over 0.5 s, then free.
	var shots: Array = g._sf_scenery.get("one_shots", [])
	for i in range(shots.size() - 1, -1, -1):
		var sd: Dictionary = shots[i]
		var node: Sprite2D = sd["node"]
		if node == null or not is_instance_valid(node):
			shots.remove_at(i)
			continue
		var t := float(sd.get("t", 0.0)) + delta
		sd["t"] = t
		node.scale = Vector2(0.3 + t * 3.0, 0.3 + t * 3.0)
		node.modulate.a = maxf(0.0, 0.9 * (1.0 - t / 0.5))
		if t >= 0.5:
			node.queue_free()
			shots.remove_at(i)
	# QA-129 (v3.11): per-level weather + ambient life animation.
	_update_skyfall_weather(delta)


func _update_skyfall_weather(delta: float) -> void:
	# Animate the QA-129 weather + ambient life. Pure functions of
	# the match clock + delta (no gameplay reads), so all peers agree.
	# QA-132: the leaves / steam / snow / storm-cloud / mid-cloud /
	# bird / portal / whirl / arc loops are gone with the items.
	var w: Dictionary = g._sf_scenery.get("weather", {})
	if w.is_empty():
		return
	for d in w.get("dust", []):
		var n: Node2D = d["node"]
		n.position.x += float(d["speed"]) * delta
		if n.position.x > 3400.0:
			n.position.x = 0.0
	for dr in w.get("drips", []):
		var n2: Node2D = dr
		n2.position.y += 55.0 * delta
		if n2.position.y > 8900.0:
			n2.position.y = 7300.0
	for r in w.get("rain", []):
		var n8: Node2D = r
		n8.visible = g._sf_storm_active
		if g._sf_storm_active:
			n8.position.y += 700.0 * delta
			if n8.position.y > 3500.0:
				n8.position.y = 0.0
	var dark: Polygon2D = w.get("storm_dark")
	if dark != null:
		var dc: Color = dark.color
		dc.a = lerpf(dc.a, 0.25 if g._sf_storm_active else 0.0, clampf(delta * 2.0, 0.0, 1.0))
		dark.color = dc
	for fi in (w.get("flags", []) as Array).size():
		var pen: Polygon2D = (w.get("flags", []) as Array)[fi]
		var skew = sin(g._sf_match_time * 3.0 + float(fi) * 2.0) * 6.0
		pen.polygon = PackedVector2Array([Vector2(0, 0), Vector2(64, 10 + skew), Vector2(0, 22)])
	var gust_on := _sf_gust_active()
	for gi in (w.get("gusts", []) as Array).size():
		var local_g: Sprite2D = (w.get("gusts", []) as Array)[gi]
		if gust_on:
			local_g.modulate.a = 0.7
			local_g.position.x += 500.0 * delta
			if local_g.position.x > 3100.0:
				local_g.position.x = 500.0
		else:
			local_g.modulate.a = 0.0










func skyfall_ladder_at(pos: Vector2) -> Rect2:
	# Ladder rect containing pos (player.gd calls this every
	# physics frame; empty rect = no ladder / not Skyfall).
	if g.map_id != GameData.SKYFALL_MAP_ID:
		return Rect2()
	for r in g.MAPS[g.map_id].get("ladders", []):
		if (r as Rect2).has_point(pos):
			return r
	return Rect2()


func skyfall_wind_at(pos: Vector2) -> Vector2:
	# Wind push at a position (player.gd applies it as extra
	# acceleration). Zero outside the wind zones / off Skyfall.
	if g.map_id != GameData.SKYFALL_MAP_ID:
		return Vector2.ZERO
	for w in g.MAPS[g.map_id].get("wind", []):
		if (w["rect"] as Rect2).has_point(pos):
			var wind: Vector2 = (w["dir"] as Vector2) * float(w.get("strength", 120.0))
			# QA-114 (v3.9): a ROUTE SHIFT event reverses the wind
			# for 20 s. Jetpack lines still shield the rider (the
			# line wins over the wind — opposite-feature rule).
			if g._sf_event_wind_flip:
				wind = -wind
			# QA-129 (v3.11): bridge gusts — every 15 s the bridge
			# wind (y 6000-6800) doubles for 3 s. The gust streaks
			# show it coming; the jetpack line still shields.
			if _sf_gust_active() and pos.y >= 6000.0 and pos.y < 6800.0:
				wind *= 2.0
			return wind
	return Vector2.ZERO


func _sf_gust_active() -> bool:
	# Bridge wind gust: 3 s of doubled wind every 15 s of match
	# time. A pure function of the match clock, so host and clients
	# agree with no RPC.
	return not g.match_over and not g._countdown_active and fmod(g._sf_match_time, 15.0) < 3.0


func _sf_play_hazard_sound(sound_name: String, pos: Vector2, max_dist: float) -> void:
	# QA-126 (v3.11): hazard SFX, only when the local player can
	# plausibly hear it (within max_dist of the event) — a strike
	# at the far end of the tower stays silent. The AudioStreamPlayer
	# pool caps overlap (6 players); hazard events are already
	# throttled (strikes 3 s, ticks 1 s, rocks 4 s), so no spam.
	if g.audio == null:
		return
	var lp = g._get_local_player()
	if lp == null:
		return
	if lp.position.distance_to(pos) <= max_dist:
		g.audio.play(sound_name)




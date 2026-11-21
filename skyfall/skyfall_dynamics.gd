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
	_sf_update_collapsing(delta)
	_sf_update_trapdoors(delta)
	# --- Falling rocks (host spawns, all peers simulate the fall). ---
	_sf_update_rocks(delta)
	# --- Summit Storm every 90 s: lightning strikes the summit. ---
	_sf_update_storm(delta)
	# --- QA-135 (v3.13): L4 storm lightning — its own strike
	# cadence (every 6 s) at a random living player in L4. ---
	_sf_update_strike_l4(delta)
	# --- QA-126 (v3.11): lava / fire hazard damage ticks. ---
	_sf_update_hazards(delta)
	# --- QA-137 (v3.14): swinging wrecking-ball pendulums. ---
	_sf_update_pendulums(delta)
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
	var kind := randi_range(7, 13)
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
	var kind := randi_range(1, 6) if randi() % 2 == 0 else randi_range(7, 13)
	var pname := "sfsupply_" + str(Time.get_ticks_msec())
	# Event drops do NOT count toward the FT-SF-RARITY test — that
	# test measures the regular spawn loop only.
	g.rpc("spawn_pickup_remote", pos, pname, kind, -1)
	g._ctf_feed("EVENT: SUPPLY DROP! Something landed on the tower — go get it!", Color(0.6, 1.0, 0.6))


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


func _sf_update_collapsing(delta: float) -> void:
	for c in g._sf_collapsing:
		var state: String = str(c.get("state", "idle"))
		var rect: Rect2 = c["rect"]
		if state == "idle":
			if _sf_player_standing_on(rect):
				c["state"] = "shaking"
				c["timer"] = 0.8
		elif state == "shaking":
			# Shake the tile sprites; the shape stays solid.
			var t := float(c.get("timer", 0.0)) - delta
			c["timer"] = t
			var off := sin(t * 40.0) * 3.0
			for s in c["sprites"]:
				(s as Sprite2D).offset = Vector2(off, 0)
			if t <= 0.0:
				c["state"] = "falling"
				c["timer"] = 0.6
				# QA-137: the grate breaks as it falls - swap the
				# tile sprites to the broken-grate art (trap sheet
				# row 6, 164x50) so the break reads clearly. Only
				# the built-in grate platforms (grate=true); the
				# random-event platforms keep their own tile art.
				if bool(c.get("grate", false)):
					for s in c["sprites"]:
						(s as Sprite2D).texture = g.TRAP_TEX_GRATE_BROKEN
				if c["shape"] != null:
					(c["shape"] as CollisionShape2D).set_deferred("disabled", true)
		elif state == "falling":
			var t := float(c.get("timer", 0.0)) - delta
			c["timer"] = t
			for s in c["sprites"]:
				(s as Sprite2D).modulate.a = maxf(0.0, t / 0.6)
				(s as Sprite2D).offset = Vector2(0, (0.6 - t) * 120.0)
			if t <= 0.0:
				c["state"] = "gone"
				c["timer"] = 8.0
				for s in c["sprites"]:
					(s as Sprite2D).visible = false
		elif state == "gone":
			var t := float(c.get("timer", 0.0)) - delta
			c["timer"] = t
			if t <= 0.0:
				c["state"] = "idle"
				if c["shape"] != null:
					(c["shape"] as CollisionShape2D).set_deferred("disabled", false)
				for s in c["sprites"]:
					# QA-137: the platform comes back whole - swap
					# the tile sprites back to the intact grate
					# (built-in grate platforms only).
					if bool(c.get("grate", false)):
						(s as Sprite2D).texture = g.TRAP_TEX_GRATE
					(s as Sprite2D).visible = true
					(s as Sprite2D).modulate.a = 1.0
					(s as Sprite2D).offset = Vector2.ZERO


func _sf_update_trapdoors(delta: float) -> void:
	for td in g._sf_trapdoors:
		var state: String = str(td.get("state", "closed"))
		var rect: Rect2 = td["rect"]
		if state == "closed":
			if _sf_player_standing_on(rect):
				var t := float(td.get("timer", 0.0)) + delta
				td["timer"] = t
				if t >= 1.0:
					td["state"] = "open"
					td["timer"] = 5.0
					if td["shape"] != null:
						(td["shape"] as CollisionShape2D).set_deferred("disabled", true)
					for s in td["sprites"]:
						(s as Sprite2D).texture = g.SF_TEX_TRAPDOOR_OPEN
			else:
				td["timer"] = 0.0
		elif state == "open":
			var t := float(td.get("timer", 0.0)) - delta
			td["timer"] = t
			if t <= 0.0:
				td["state"] = "closed"
				td["timer"] = 0.0
				if td["shape"] != null:
					(td["shape"] as CollisionShape2D).set_deferred("disabled", false)
				for s in td["sprites"]:
					(s as Sprite2D).texture = g.SF_TEX_TRAPDOOR_CLOSED


func _sf_update_rocks(delta: float) -> void:
	# Host spawns a rock every 4 s (max 3 falling); every peer
	# simulates the same fall (gravity + land on the first
	# platform below). Host-only damage on impact with a player.
	if g.multiplayer.is_server() and not g.match_over and not g._countdown_active:
		g._sf_rock_timer -= delta
		if g._sf_rock_timer <= 0.0:
			g._sf_rock_timer = float(g.MAPS[g.map_id].get("rocks", {}).get("interval", 4.0))
			var active := 0
			for r in g._sf_rocks:
				if not bool(r.get("landed", false)):
					active += 1
			var rocks: Dictionary = g.MAPS[g.map_id].get("rocks", {})
			if active < int(rocks.get("max", 3)):
				var rx := randf_range(float(rocks.get("x_min", 1000)), float(rocks.get("x_max", 2600)))
				g.rpc("sf_rock_remote", rx)
	for i in range(g._sf_rocks.size() - 1, -1, -1):
		var r: Dictionary = g._sf_rocks[i]
		var node: Node2D = r["node"]
		if node == null or not is_instance_valid(node):
			g._sf_rocks.remove_at(i)
			continue
		if bool(r.get("landed", false)):
			var ft := float(r.get("fade", 0.0)) - delta
			r["fade"] = ft
			(node as Sprite2D).modulate.a = maxf(0.0, ft)
			if ft <= 0.0:
				node.queue_free()
				g._sf_rocks.remove_at(i)
			continue
		var vel := float(r.get("vel", 0.0)) + 1400.0 * delta
		r["vel"] = vel
		var prev_y: float = node.position.y
		node.position.y += vel * delta
		node.rotation += 3.0 * delta
		# Land on the first platform top crossed this frame.
		var landed := false
		for p in g.MAPS[g.map_id]["platforms"]:
			var pr: Rect2 = p
			if node.position.x >= pr.position.x and node.position.x <= pr.end.x and prev_y + 30.0 <= pr.position.y and node.position.y + 30.0 >= pr.position.y:
				node.position.y = pr.position.y - 30.0
				node.rotation = 0.0
				r["landed"] = true
				r["fade"] = 1.0
				landed = true
				break
		if landed:
			_sf_free_rock_marker(r)
			_sf_play_hazard_sound("rock_impact", node.position, 1100.0)
			continue
		# Host-only: 25 damage + knockback on a player hit mid-fall.
		if g.multiplayer.is_server() and not g.match_over:
			for child in g.players_node.get_children():
				if not child.alive:
					continue
				var box := Rect2(child.position - Vector2(20, 31), Vector2(40, 62))
				var rock_box := Rect2(node.position - Vector2(30, 30), Vector2(60, 60))
				if box.intersects(rock_box):
					if child.get_multiplayer_authority() == g.multiplayer.get_unique_id():
						child.take_damage(25, 0)
					elif g.multiplayer.get_peers().has(child.get_multiplayer_authority()):
						child.rpc_id(child.get_multiplayer_authority(), "take_damage", 25, 0)
					_sf_free_rock_marker(r)
					_sf_play_hazard_sound("rock_impact", node.position, 1100.0)
					node.queue_free()
					g._sf_rocks.remove_at(i)
					break


func _sf_free_rock_marker(r: Dictionary) -> void:
	var m: Node = r.get("marker")
	if m != null and is_instance_valid(m):
		m.queue_free()
	r["marker"] = null


func sf_rock_remote(x: float) -> void:
	var rocks: Dictionary = g.MAPS[g.map_id].get("rocks", {})
	var node := Sprite2D.new()
	node.texture = g.SF_TEX_ROCK
	node.scale = Vector2(0.6, 0.6)
	node.position = Vector2(x, float(rocks.get("y_top", 9050)))
	node.z_index = 3
	g.add_child(node)
	# QA-129 (v3.11): landing warning — a ground-crack marker on
	# the first platform below the spawn x, so the impact point is
	# telegraphed from the moment the rock appears (0.5-1.5 s of
	# warning depending on the drop). Freed when the rock lands.
	var marker: Sprite2D = null
	var land_y := -1.0
	for p in g.MAPS[g.map_id]["platforms"]:
		var pr: Rect2 = p
		# Nearest platform below the spawn (smallest top y above
		# y_top) — the array runs bottom-to-top, so take the min.
		if x >= pr.position.x and x <= pr.end.x and pr.position.y > float(rocks.get("y_top", 9050)) and (land_y < 0.0 or pr.position.y < land_y):
			land_y = pr.position.y
	if land_y > 0.0:
		marker = Sprite2D.new()
		marker.texture = g.FX_TEX_CRACK
		marker.position = Vector2(x, land_y - 6)
		marker.scale = Vector2(0.5, 0.5)
		marker.modulate = Color(1, 0.5, 0.3, 0.85)
		marker.z_index = 2
		g.add_child(marker)
	g._sf_rocks.append({"node": node, "vel": 0.0, "landed": false, "fade": 0.0, "marker": marker})


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
				bolt.texture = g.SF_TEX_LIGHTNING
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
						_sf_damage_player(child, 15)
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
	bolt.texture = g.FX_TEX_BOLT if randi() % 2 == 0 else g.FX_TEX_FORKED
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
						_sf_damage_player(child, 15)
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
	bolt.texture = g.FX_TEX_BOLT if randi() % 2 == 0 else g.FX_TEX_FORKED
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


func show_wind_tornado_fx(pos: Vector2) -> void:
	# QA-135 (v3.13): Wind Blast tornado — a code-drawn funnel
	# (stacked ellipses, wide top -> narrow base) + a dust ring
	# at the base. Spins for ~1 s (the 0.7 s sweep + the throw),
	# then fades. The host RPCs it, so every peer sees the same
	# tornado at the same spot. Sender guard: only the host
	# (id 1, or 0 in a local sim) may trigger it.
	var sender = g.multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	g.audio.play("wind")
	if g._wind_tornado_node != null and is_instance_valid(g._wind_tornado_node):
		g._wind_tornado_node.queue_free()
	var n := Node2D.new()
	n.position = pos + Vector2(0, -20)
	n.z_index = 6
	g.add_child(n)
	var radii := [70.0, 55.0, 38.0, 22.0]
	var offs := [-95.0, -55.0, -15.0, 25.0]
	for i in radii.size():
		var e := Polygon2D.new()
		var pts := PackedVector2Array()
		for k in 20:
			var a := TAU * float(k) / 20.0
			pts.append(Vector2(cos(a) * radii[i], sin(a) * radii[i] * 0.45))
		e.polygon = pts
		e.color = Color(0.92, 0.93, 0.96, 0.5)
		e.position = Vector2(0, offs[i])
		n.add_child(e)
	var dust := Sprite2D.new()
	dust.texture = g.FX_TEX_DUST
	dust.position = Vector2(0, 30)
	dust.scale = Vector2(0.9, 0.9)
	dust.modulate = Color(1, 1, 1, 0.55)
	n.add_child(dust)
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
	bolt.texture = g.FX_TEX_THUNDER
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
	sw.texture = g.FX_TEX_SHOCKWAVE
	sw.position = pos
	sw.scale = Vector2(0.3, 0.3)
	sw.modulate = Color(1, 1, 1, 0.9)
	sw.z_index = 4
	g.add_child(sw)
	var shots: Array = g._sf_scenery.get("one_shots", [])
	shots.append({"node": sw, "t": 0.0})
	g._sf_scenery["one_shots"] = shots


func _sf_update_hazards(delta: float) -> void:
	# QA-126 (v3.11): lava / fire hazard zones deal damage — 10 HP
	# per 1 s tick while a player stands in the zone, and ONLY while
	# the jets are HOT (2 s on / 2 s off per 4 s cycle — the flame
	# sprite shows the phase, so the danger is always telegraphed).
	# Fair: no one-hit kills (10 HP/tick, walk out between ticks),
	# the shield blocks it (take_damage), and the health regen
	# restarts from the hit. Host-only damage; visuals are pure
	# functions of the match clock so every peer agrees.
	for h in g._sf_hazard_fx:
		var hd: Dictionary = h
		var cycle := float(hd.get("cycle", 4.0))
		var hot = fmod(g._sf_match_time, cycle) < cycle * 0.5
		var flame: Sprite2D = hd["flame"]
		if flame != null:
			flame.visible = hot
			if hot:
				var pulse = 0.55 + 0.15 * sin(g._sf_match_time * 9.0)
				if str(hd.get("kind", "")) == "fire":
					# QA-137: cycle the fire-vent frames (8 fps,
					# so the vent plays twice per 2 s hot phase)
					# and keep the grate pinned to the rect bottom
					# as the frame height changes (158-227 px).
					var fi = int(g._sf_match_time * 8.0) % g.TRAP_TEX_FIRE_VENT.size()
					var ftex: Texture2D = g.TRAP_TEX_FIRE_VENT[fi]
					flame.texture = ftex
					flame.scale.y = pulse * 1.6
					var r: Rect2 = hd["rect"]
					flame.position = Vector2(r.get_center().x, r.end.y - float(ftex.get_height()) * 0.5 * flame.scale.y)
				else:
					flame.scale.y = pulse
		var magma: Sprite2D = hd.get("magma")
		if magma != null:
			magma.visible = hot
			if hot:
				var k = fmod(g._sf_match_time, cycle) / (cycle * 0.5)
				magma.scale = Vector2(0.5 + k * 0.7, 0.5 + k * 0.7)
				magma.modulate.a = 0.85 * (1.0 - k * 0.6)
		if not hot:
			continue
		if not g.multiplayer.is_server() or g.match_over:
			continue
		var r: Rect2 = hd["rect"]
		for child in g.players_node.get_children():
			if not child.alive:
				continue
			var box := Rect2(child.position - Vector2(20, 31), Vector2(40, 62))
			if not box.intersects(r):
				continue
			var pid := int(child.get_multiplayer_authority())
			var tick = float(g._sf_hazard_tick.get(pid, 0.0)) - delta
			g._sf_hazard_tick[pid] = tick
			if tick <= 0.0:
				g._sf_hazard_tick[pid] = 1.0
				_sf_damage_player(child, 10)
				_sf_play_hazard_sound("fire_burn", child.position, 900.0)




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


func _sf_update_pendulums(delta: float) -> void:
	# QA-137: the ball swings +-40 deg on a 5.7 s period (a pure
	# function of the match clock, so every peer agrees). The ball
	# is telegraphed - the chain shows exactly where it sweeps -
	# and it deals 25 HP on contact (QA-126, like a falling rock:
	# dodgeable, no one-hit kill, shield blocks it, host-only).
	# A per-player 1 s cooldown stops one swing from multi-hitting.
	for p in g._sf_pendulums:
		var pd: Dictionary = p
		var plen := float(pd.get("len", 220.0))
		var ang = 0.7 * sin(g._sf_match_time * 1.1 + float(pd.get("phase", 0.0)))
		var dir = Vector2(sin(ang), cos(ang))
		var ball_pos: Vector2 = (pd["pivot"] as Vector2) + dir * plen
		(pd["ball"] as Sprite2D).position = dir * plen
		(pd["chain"] as Line2D).points = PackedVector2Array([Vector2.ZERO, dir * plen])
		if not g.multiplayer.is_server() or g.match_over:
			continue
		var tick: Dictionary = pd.get("tick", {})
		for child in g.players_node.get_children():
			if not child.alive:
				continue
			var pid := int(child.get_multiplayer_authority())
			var cd := float(tick.get(pid, 0.0)) - delta
			tick[pid] = cd
			if cd > 0.0:
				continue
			if child.position.distance_to(ball_pos) < 48.0:
				tick[pid] = 1.0
				_sf_damage_player(child, 25)
		pd["tick"] = tick


func try_barricade_hit(hit_pos: Vector2, dmg: int) -> bool:
	# Bullet vs destructible barricade (QA-112). Host-authorised:
	# only the server damages barricades; clients return false
	# (just the spark). Returns true when a barricade was hit.
	if not g.multiplayer.is_server():
		return false
	for b in g._sf_barricades:
		if not bool(b["alive"]):
			continue
		var r: Rect2 = b["rect"]
		if r.grow(6.0).has_point(hit_pos):
			b["hp"] = float(b["hp"]) - dmg
			if float(b["hp"]) <= 0.0:
				_sf_break_barricade(b)
			return true
	return false


func _sf_break_barricade(b: Dictionary) -> void:
	b["alive"] = false
	b["timer"] = 30.0
	(b["sprite"] as Node2D).visible = false
	if b["shape"] != null:
		(b["shape"] as CollisionShape2D).set_deferred("disabled", true)
	g.rpc("sf_barricade_remote", g._sf_barricades.find(b), false)


func sf_barricade_remote(idx: int, alive: bool) -> void:
	if idx < 0 or idx >= g._sf_barricades.size():
		return
	var b: Dictionary = g._sf_barricades[idx]
	b["alive"] = alive
	(b["sprite"] as Node2D).visible = alive
	if b["shape"] != null:
		(b["shape"] as CollisionShape2D).set_deferred("disabled", not alive)
	if not alive:
		b["timer"] = 30.0


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


func _sf_damage_player(child: Node, amount: int) -> void:	# Host-authoritative damage to one player (same routing as the
	# falling rocks): direct when the host owns the victim, RPC to
	# the owning peer otherwise. The victim's take_damage applies
	# the shield (blocks ALL damage) + hit flash + shake, and the
	# health-regen timer restarts from the hit.
	if child.get_multiplayer_authority() == g.multiplayer.get_unique_id():
		child.take_damage(amount, 0)
	elif g.multiplayer.get_peers().has(child.get_multiplayer_authority()):
		child.rpc_id(child.get_multiplayer_authority(), "take_damage", amount, 0)


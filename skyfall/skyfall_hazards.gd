class_name SkyfallHazards
extends RefCounted


# QA-140 (v3.15): extracted from skyfall/skyfall_dynamics.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `g` (dependency injection).


var g # the owner (skyfall/skyfall_dynamics.gd)


func _init(owner) -> void:
	g = owner


func _sf_update_collapsing(delta: float) -> void:
	for c in g._sf_collapsing:
		var state: String = str(c.get("state", "idle"))
		var rect: Rect2 = c["rect"]
		if state == "idle":
			if g.skyfall_dynamics._sf_player_standing_on(rect):
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
						(s as Sprite2D).texture = GameAssets.TRAP_TEX_GRATE_BROKEN
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
						(s as Sprite2D).texture = GameAssets.TRAP_TEX_GRATE
					(s as Sprite2D).visible = true
					(s as Sprite2D).modulate.a = 1.0
					(s as Sprite2D).offset = Vector2.ZERO


func _sf_update_trapdoors(delta: float) -> void:
	for td in g._sf_trapdoors:
		var state: String = str(td.get("state", "closed"))
		var rect: Rect2 = td["rect"]
		if state == "closed":
			if g.skyfall_dynamics._sf_player_standing_on(rect):
				var t := float(td.get("timer", 0.0)) + delta
				td["timer"] = t
				if t >= 1.0:
					td["state"] = "open"
					td["timer"] = 5.0
					if td["shape"] != null:
						(td["shape"] as CollisionShape2D).set_deferred("disabled", true)
					for s in td["sprites"]:
						(s as Sprite2D).texture = GameAssets.SF_TEX_TRAPDOOR_OPEN
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
					(s as Sprite2D).texture = GameAssets.SF_TEX_TRAPDOOR_CLOSED


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
			g.skyfall_dynamics._sf_play_hazard_sound("rock_impact", node.position, 1100.0)
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
					g.skyfall_dynamics._sf_play_hazard_sound("rock_impact", node.position, 1100.0)
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
	node.texture = GameAssets.SF_TEX_ROCK
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
		marker.texture = GameAssets.FX_TEX_CRACK
		marker.position = Vector2(x, land_y - 6)
		marker.scale = Vector2(0.5, 0.5)
		marker.modulate = Color(1, 0.5, 0.3, 0.85)
		marker.z_index = 2
		g.add_child(marker)
	g._sf_rocks.append({"node": node, "vel": 0.0, "landed": false, "fade": 0.0, "marker": marker})


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
					var fi = int(g._sf_match_time * 8.0) % GameAssets.TRAP_TEX_FIRE_VENT.size()
					var ftex: Texture2D = GameAssets.TRAP_TEX_FIRE_VENT[fi]
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
				g.skyfall_dynamics._sf_play_hazard_sound("fire_burn", child.position, 900.0)


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


func _sf_damage_player(child: Node, amount: int) -> void:	# Host-authoritative damage to one player (same routing as the
	# falling rocks): direct when the host owns the victim, RPC to
	# the owning peer otherwise. The victim's take_damage applies
	# the shield (blocks ALL damage) + hit flash + shake, and the
	# health-regen timer restarts from the hit.
	if child.get_multiplayer_authority() == g.multiplayer.get_unique_id():
		child.take_damage(amount, 0)
	elif g.multiplayer.get_peers().has(child.get_multiplayer_authority()):
		child.rpc_id(child.get_multiplayer_authority(), "take_damage", amount, 0)


class_name ArenaBuilder
extends RefCounted


# QA-139 (v3.15): extracted from game.gd. This module owns no
# state of its own: every field it reads or writes lives on the
# game node and is reached through `g` (dependency injection).
# game.gd keeps a thin delegating wrapper for each function the
# rest of the game calls, so no call site had to change.


var g # the game node (game.gd)


func _init(game) -> void:
	g = game


func _build_background(map: Dictionary) -> void:
	var grad := Gradient.new()
	grad.set_color(0, map["sky_top"])
	grad.set_color(1, map["sky_bottom"])
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.width = 4
	gtex.height = 512
	gtex.fill_from = Vector2(0.5, 0.0)
	gtex.fill_to = Vector2(0.5, 1.0)
	var sky := Sprite2D.new()
	sky.texture = gtex
	sky.position = g.map_size * 0.5
	sky.scale = Vector2(g.map_size.x / 4.0, g.map_size.y / 512.0)
	sky.z_index = -10
	g.add_child(sky)
	# Phase 5 — far parallax image layer (Sky Brawl arena art).
	# Viewport scale only (~1.3x upscale of the 960x540 image),
	# horizontal parallax 0.25, tiled so it never runs out; the
	# procedural gradient stays in front at 50% alpha so the horizon
	# still matches the map palette. Maps without a "bg" key (the 5
	# POOR-fit day maps) keep the full procedural gradient.
	var bg_idx := int(map.get("bg", -1))
	if bg_idx >= 0 and bg_idx < g.BG_TEX.size():
		sky.modulate = Color(1, 1, 1, 0.5)
		var pb := ParallaxBackground.new()
		pb.layer = -100
		g.add_child(pb)
		var player_layer := ParallaxLayer.new()
		player_layer.motion_scale = Vector2(0.25, 0.0)
		player_layer.motion_mirroring = Vector2(1286, 0)
		pb.add_child(player_layer)
		var bg_spr := Sprite2D.new()
		bg_spr.texture = g.BG_TEX[bg_idx]
		bg_spr.scale = Vector2(1286.0 / 960.0, 723.0 / 540.0)
		bg_spr.position = Vector2(643, 362)
		player_layer.add_child(bg_spr)
	# Sun / moon.
	var sun := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 32:
		var a := TAU * float(i) / 32.0
		pts.append(Vector2(cos(a), sin(a)) * 70.0)
	sun.polygon = pts
	sun.color = Color(map["sun"].r, map["sun"].g, map["sun"].b, 0.9)
	sun.position = Vector2(g.map_size.x * 0.8, 180)
	sun.z_index = -9
	g.add_child(sun)
	# QA-111 (v3.8): Ironfall's helicopter silhouette in the dusk
	# sky, top right near the moon — the concept shows one flying
	# past the full moon. Code-drawn dark silhouette (no heli sprite
	# in the sliced pack), same depth as the sun, behind the hills.
	if g.map_id == 0:
		var heli := Node2D.new()
		heli.position = Vector2(g.map_size.x * 0.7, 130)
		heli.z_index = -9
		g.add_child(heli)
		var hcol := Color(0.08, 0.10, 0.18, 0.85)
		var hbody := Polygon2D.new()
		hbody.polygon = PackedVector2Array([Vector2(-32, -4), Vector2(-22, -10), Vector2(8, -10), Vector2(24, -4), Vector2(30, 0), Vector2(24, 6), Vector2(0, 9), Vector2(-24, 8), Vector2(-32, 2)])
		hbody.color = hcol
		heli.add_child(hbody)
		var htail := Polygon2D.new()
		htail.polygon = PackedVector2Array([Vector2(24, -3), Vector2(56, -5), Vector2(56, 1), Vector2(24, 3)])
		htail.color = hcol
		heli.add_child(htail)
		var hrotor := Polygon2D.new()
		hrotor.polygon = PackedVector2Array([Vector2(-46, -17), Vector2(46, -17), Vector2(46, -14), Vector2(-46, -14)])
		hrotor.color = hcol
		heli.add_child(hrotor)
		var hmast := Polygon2D.new()
		hmast.polygon = PackedVector2Array([Vector2(-2, -14), Vector2(2, -14), Vector2(2, -8), Vector2(-2, -8)])
		hmast.color = hcol
		heli.add_child(hmast)
		var htailrotor := Polygon2D.new()
		htailrotor.polygon = PackedVector2Array([Vector2(54, -12), Vector2(57, -12), Vector2(57, 2), Vector2(54, 2)])
		htailrotor.color = hcol
		heli.add_child(htailrotor)
		var hskid := Polygon2D.new()
		hskid.polygon = PackedVector2Array([Vector2(-24, 13), Vector2(24, 13), Vector2(24, 15), Vector2(-24, 15)])
		hskid.color = hcol
		heli.add_child(hskid)
	# Distant hills.
	for h in 2:
		var hill := Polygon2D.new()
		var hp := PackedVector2Array()
		var base_y = g.map_size.y - 130.0 - h * 60.0
		hp.append(Vector2(0, g.map_size.y))
		var steps := 24
		for i in steps + 1:
			var x = g.map_size.x * float(i) / steps
			var y = base_y - sin(float(i) * 0.9 + h * 2.0) * 70.0 - sin(float(i) * 0.37) * 40.0
			hp.append(Vector2(x, y))
		hp.append(Vector2(g.map_size.x, g.map_size.y))
		hill.polygon = hp
		hill.color = Color(map["hill"].r, map["hill"].g, map["hill"].b, 0.75 - h * 0.2)
		hill.z_index = -8 + h
		g.add_child(hill)
	# QA-072 (map artwork): midground silhouette layer — a stepped
	# skyline of distant buildings / pillars / dunes in the map's own
	# hill colour (darkened), seeded by map_id so every map's skyline
	# differs. Purely visual (z -7, behind platforms and players);
	# the gradient + parallax image + 2 hill ridges stay as they were.
	var sil := Polygon2D.new()
	var sp := PackedVector2Array()
	var sil_base = g.map_size.y - 60.0
	sp.append(Vector2(0, g.map_size.y))
	var seed = 12345 + g.map_id * 7919
	var sx := 0.0
	while sx < g.map_size.x:
		seed = (seed * 1103515245 + 12345) & 0x7fffffff
		var sw = 120.0 + float(seed % 140)
		seed = (seed * 1103515245 + 12345) & 0x7fffffff
		var sh = 60.0 + float(seed % 200)
		sp.append(Vector2(sx, sil_base - sh))
		sp.append(Vector2(minf(sx + sw, g.map_size.x), sil_base - sh))
		sx += sw + 30.0 + float(seed % 60)
	sp.append(Vector2(g.map_size.x, g.map_size.y))
	sil.polygon = sp
	var hc: Color = map["hill"]
	sil.color = Color(hc.r * 0.6, hc.g * 0.6, hc.b * 0.6, 0.55)
	sil.z_index = -7
	g.add_child(sil)


func _build_arena(map: Dictionary) -> void:
	var arena := StaticBody2D.new()
	arena.name = "Arena"
	arena.collision_layer = 1
	arena.collision_mask = 0
	g.add_child(arena)
	var platforms: Array = map["platforms"]
	for rect in platforms:
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = rect.size
		shape.shape = box
		shape.position = rect.get_center()
		arena.add_child(shape)
	g._draw_tiles(map, platforms)
	# Walls + ceiling (collision only, no visual).
	var bounds := [
		Rect2(0, 0, 24, g.map_size.y), Rect2(g.map_size.x - 24, 0, 24, g.map_size.y),
		Rect2(0, 0, g.map_size.x, 24),
	]
	for rect in bounds:
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = rect.size
		shape.shape = box
		shape.position = rect.get_center()
		arena.add_child(shape)
	# Decorations (visual only, behind the players).
	var decor: Array = map["decor"]
	for d in decor:
		var tex: Texture2D = g.DECOR_TEX[d[0]]
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.position = Vector2(float(d[1]), float(d[2]) - tex.get_height() * 0.5)
		spr.z_index = -1
		g.add_child(spr)
		# QA-030: solid decor gets real collision on layer 1 (same
		# layer as platforms/walls, so the bullet raycast and the
		# player both hit it). The rectangle matches the sprite's
		# visible size and is centred on the sprite, so it covers
		# exactly what the player sees. Non-solid dressing (trees,
		# palms, bushes, bridges, arches) gets no shape and stays
		# pass-through, as before.
		if String(d[0]) in g.SOLID_DECOR_KINDS:
			var shape := CollisionShape2D.new()
			var box := RectangleShape2D.new()
			var inset = float(g.DECOR_INSETS.get(String(d[0]), 6))
			# Sides and top are inset (transparent sprite edges);
			# the bottom sits ON the ground point. An inset bottom
			# floats 6-10 px above the floor and the capsule's
			# rounded bottom rides up over low cover (crate, etc).
			box.size = Vector2(maxf(8.0, tex.get_width() - inset * 2.0), maxf(8.0, tex.get_height() - inset))
			shape.shape = box
			shape.position = Vector2(spr.position.x, spr.position.y + inset * 0.5)
			arena.add_child(shape)
			if String(d[0]) == "barrels":
				# Explosive barrel (GAP-64): the art is already on
				# every map and already solid cover; this registers
				# it as damageable (100 HP, explodes on death).
				g._barrels.append({"rect": Rect2(shape.position - box.size * 0.5, box.size),
					"sprite": spr, "shape": shape, "hp": PhysicsConfig.BARREL_HEALTH, "alive": true})
		elif String(d[0]) in g.BRIDGE_DECOR_KINDS:
			# Walkable-looking bridge/arch: thin top plank only.
			var shape2 := CollisionShape2D.new()
			var box2 := RectangleShape2D.new()
			box2.size = Vector2(tex.get_width(), 24.0)
			shape2.shape = box2
			shape2.position = Vector2(spr.position.x, spr.position.y - tex.get_height() * 0.5 + 12.0)
			arena.add_child(shape2)
	# QA-111 (v3.8): Ironfall's red flag on the bunker roof — the
	# concept's central fortress flies a red flag beside the dish.
	# Code-drawn (no flag sprite in the sliced pack): a thin dark
	# pole + red pennant, placed above the if_bunker decor entry.
	# The pole starts 6 px below the sprite's top edge so it sits
	# into the roof instead of floating on transparent padding.
	if g.map_id == 0:
		for d in decor:
			if String(d[0]) == "if_bunker":
				var bx := float(d[1])
				var btop = float(d[2]) - float(g.DECOR_IF_BUNKER.get_height())
				var pole := Polygon2D.new()
				pole.polygon = PackedVector2Array([Vector2(bx - 2, btop + 6), Vector2(bx + 2, btop + 6), Vector2(bx + 2, btop - 32), Vector2(bx - 2, btop - 32)])
				pole.color = Color(0.15, 0.15, 0.18)
				pole.z_index = -1
				g.add_child(pole)
				var flag := Polygon2D.new()
				flag.polygon = PackedVector2Array([Vector2(bx + 2, btop - 32), Vector2(bx + 30, btop - 25), Vector2(bx + 2, btop - 18)])
				flag.color = Color(0.85, 0.12, 0.12)
				flag.z_index = -1
				g.add_child(flag)
				break


func _build_ice_zone(map: Dictionary) -> void:
	# Ice zone visual (GAP-51): the old ice map is deleted in v3.7
	# (QA-095), so there is no ice floor to draw a sheen on.
	return
	var sheen := Polygon2D.new()
	sheen.polygon = PackedVector2Array([
		Vector2(450, 1352), Vector2(1750, 1352),
		Vector2(1750, 1400), Vector2(450, 1400)])
	sheen.color = Color(0.65, 0.85, 1.0, 0.35)
	sheen.z_index = -1
	g.add_child(sheen)


func _build_bounce_pads(map: Dictionary) -> void:
	# Bounce pads (GAP-66, spec §22.E): two per map on the floor,
	# velocity.y = -750 on touch, one launch per contact (0.3 s
	# per-player cooldown). Visual: a yellow spring pad.
	var floor_top := 1352.0
	var plats: Array = map["platforms"]
	if not plats.is_empty():
		floor_top = float((plats[0] as Rect2).position.y)
	for fx in [0.3, 0.7]:
		var cx: float = g.map_size.x * float(fx)
		var pad := Area2D.new()
		pad.name = "BouncePad_%d" % int(cx)
		pad.collision_layer = 8 # trigger (spec §24.D, GAP-71)
		pad.collision_mask = 2 # players only
		pad.position = Vector2(cx, floor_top - 8.0)
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(90, 16)
		shape.shape = rect
		pad.add_child(shape)
		var vis := Polygon2D.new()
		vis.polygon = PackedVector2Array([
			Vector2(-45, -8), Vector2(45, -8), Vector2(45, 8), Vector2(-45, 8)])
		vis.color = Color(1.0, 0.85, 0.2, 0.95)
		pad.add_child(vis)
		g.add_child(pad)
		g._bounce_pads.append({"rect": Rect2(cx - 45, floor_top - 16, 90, 16),
			"area": pad, "cooldowns": {}})
		pad.body_entered.connect(_on_bounce_pad_body.bind(pad))


func _on_bounce_pad_body(body: Node2D, pad: Area2D) -> void:
	# One launch per contact: the per-player cooldown stops the pad
	# retriggering every physics frame while the player overlaps it.
	if not body.is_in_group("players"):
		return
	var p = body
	if not p.alive:
		return
	for entry in g._bounce_pads:
		if entry["area"] == pad:
			var cds: Dictionary = entry["cooldowns"]
			var now := Time.get_ticks_msec() / 1000.0
			if float(cds.get(p.peer_id, -10.0)) + PhysicsConfig.BOUNCE_COOLDOWN > now:
				return
			cds[p.peer_id] = now
			p.velocity.y = PhysicsConfig.BOUNCE_VELOCITY
			if p.has_method("_play_sound"):
				p._play_sound("jump")
			return


func try_barrel_hit(hit_pos: Vector2, dmg: int, owner_id: int) -> bool:
	# Bullet vs explosive barrel (GAP-64). Host-authorised: only the
	# server damages barrels; clients return false (just the spark).
	# Returns true when a barrel was hit (bullet is consumed).
	if not g.multiplayer.is_server():
		return false
	for b in g._barrels:
		if not bool(b["alive"]):
			continue
		var r: Rect2 = b["rect"]
		if r.grow(6.0).has_point(hit_pos):
			b["hp"] = float(b["hp"]) - dmg
			if float(b["hp"]) <= 0.0:
				b["alive"] = false
				(b["sprite"] as Node2D).visible = false
				(b["shape"] as CollisionShape2D).set_deferred("disabled", true)
				g.rpc("barrel_destroyed_remote", g._barrels.find(b))
				g.request_explosion(r.get_center(), PhysicsConfig.BARREL_BLAST_RADIUS,
					int(PhysicsConfig.BARREL_BLAST_DAMAGE), owner_id)
			return true
	return false


func barrel_destroyed_remote(idx: int) -> void:
	if idx < 0 or idx >= g._barrels.size():
		return
	var b: Dictionary = g._barrels[idx]
	b["alive"] = false
	(b["sprite"] as Node2D).visible = false
	(b["shape"] as CollisionShape2D).set_deferred("disabled", true)


func _build_lava(map: Dictionary) -> void:
	# Volcanic Cavern: glowing lava pools in the gaps of the floor.
	# Clearly visible (bright orange top), avoidable (safe platforms on
	# both sides, pools only 300 px wide), and never under a spawn/pickup.
	var pools: Array = map.get("lava", [])
	for r in pools:
		var rect: Rect2 = r
		var base := Polygon2D.new()
		base.polygon = PackedVector2Array([
			rect.position, Vector2(rect.position.x + rect.size.x, rect.position.y),
			rect.position + rect.size, Vector2(rect.position.x, rect.position.y + rect.size.y)])
		base.color = Color(0.85, 0.22, 0.05, 0.95)
		base.z_index = -1
		g.add_child(base)
		var top := Polygon2D.new()
		top.polygon = PackedVector2Array([
			rect.position, Vector2(rect.position.x + rect.size.x, rect.position.y),
			Vector2(rect.position.x + rect.size.x, rect.position.y + 12),
			Vector2(rect.position.x, rect.position.y + 12)])
		top.color = Color(1.0, 0.62, 0.12, 1.0)
		top.z_index = -1
		g.add_child(top)


func _build_ambient_fx(map: Dictionary) -> void:
	# Per-theme ambient particles (snow, embers, dust, rain, sparks,
	# leaves). They sit BEHIND the players (z_index -2) and are faint
	# enough never to hide a player, a bullet or the HUD.
	var kind: String = str(map.get("fx", "none"))
	if kind == "none":
		return
	var p := CPUParticles2D.new()
	p.amount = 80
	p.lifetime = 5.0
	p.preprocess = 5.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = g.map_size * 0.5
	p.position = g.map_size * 0.5
	p.z_index = -2
	match kind:
		"snow":
			p.direction = Vector2(0, 1)
			p.spread = 20.0
			p.gravity = Vector2(0, 60)
			p.initial_velocity_min = 30.0
			p.initial_velocity_max = 50.0
			p.color = Color(0.95, 0.97, 1.0, 0.85)
			p.scale_amount_min = 2.0
			p.scale_amount_max = 4.0
		"embers":
			p.amount = 40
			p.lifetime = 2.5
			p.direction = Vector2(0, -1)
			p.spread = 30.0
			p.gravity = Vector2(0, -30)
			p.initial_velocity_min = 40.0
			p.initial_velocity_max = 70.0
			p.color = Color(1.0, 0.55, 0.15, 0.9)
			p.scale_amount_min = 2.0
			p.scale_amount_max = 3.0
		"dust":
			p.amount = 50
			p.lifetime = 6.0
			p.direction = Vector2(1, 0)
			p.spread = 30.0
			p.gravity = Vector2.ZERO
			p.initial_velocity_min = 10.0
			p.initial_velocity_max = 20.0
			p.color = Color(0.8, 0.75, 0.65, 0.30)
			p.scale_amount_min = 3.0
			p.scale_amount_max = 5.0
		"rain":
			p.amount = 100
			p.lifetime = 1.2
			p.direction = Vector2(0, 1)
			p.spread = 5.0
			p.gravity = Vector2(0, 300)
			p.initial_velocity_min = 400.0
			p.initial_velocity_max = 500.0
			p.color = Color(0.7, 0.8, 1.0, 0.45)
			p.scale_amount_min = 1.0
			p.scale_amount_max = 2.0
		"sparks":
			p.amount = 30
			p.lifetime = 1.5
			p.direction = Vector2(0, -1)
			p.spread = 45.0
			p.gravity = Vector2(0, 100)
			p.initial_velocity_min = 60.0
			p.initial_velocity_max = 100.0
			p.color = Color(1.0, 0.75, 0.2, 0.9)
			p.scale_amount_min = 1.0
			p.scale_amount_max = 2.0
		"leaves":
			p.amount = 40
			p.lifetime = 7.0
			p.direction = Vector2(0.5, 1)
			p.spread = 40.0
			p.gravity = Vector2(0, 25)
			p.initial_velocity_min = 20.0
			p.initial_velocity_max = 30.0
			p.color = Color(0.4, 0.7, 0.3, 0.7)
			p.scale_amount_min = 2.0
			p.scale_amount_max = 4.0
	g.add_child(p)


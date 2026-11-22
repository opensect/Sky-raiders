class_name GameFx
extends RefCounted


# QA-140 (v3.15): extracted from game.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `g` (dependency injection).


var g # the owner (game.gd)


func _init(owner) -> void:
	g = owner


func spawn_impact_fx(pos: Vector2, small: bool = false) -> void:
	if small:
		# QA-092 (v3.7): bullet impacts + hard landings use the
		# library hit spark (white-gold flash + twinkle + ring +
		# fast sparks) instead of the old static Sky Brawl spark
		# sprite. Same call sites, same timing, better look.
		ReebooFx2D.spawn(GameAssets.HIT_SPARK_SCENE, g.fx_node, pos)
		return
	var spr := Sprite2D.new()
	# Phase 4: Sky Brawl hit spark (small) / explosion sunburst
	# (large) instead of the old smoke/explosion sprites.
	spr.texture = GameAssets.SB_EXPLOSION_TEX
	spr.position = pos
	spr.scale = Vector2(0.7, 0.7)
	spr.modulate = Color(1, 1, 1, 0.9)
	g.fx_node.add_child(spr)
	var tw = g.create_tween()
	tw.tween_property(spr, "scale", spr.scale * 1.6, 0.25)
	tw.parallel().tween_property(spr, "modulate:a", 0.0, 0.25)
	tw.tween_callback(spr.queue_free)
	g.audio.play("hit")


# QA-092 (v3.7): pickup grab sparkle — the library coin-pickup
# effect (gold ring + twinkle + rising glints) at the spot where a
# pickup was taken. Called from pickup.gd despawn(grabbed=true),
# which runs on every peer, so everyone sees the grab.
func spawn_pickup_fx(pos: Vector2) -> void:
	ReebooFx2D.spawn(GameAssets.COIN_PICKUP_SCENE, g.fx_node, pos)


# QA-085 (v3.7): landing dust — a soft tan dust puff at the feet.
# Purely visual, same tween-and-free pattern as spawn_impact_fx.
func spawn_dust_fx(pos: Vector2) -> void:
	var spr := Sprite2D.new()
	spr.texture = GameAssets.DUST_TEX
	spr.position = pos
	spr.scale = Vector2(0.8, 0.8)
	spr.rotation = randf() * TAU
	spr.modulate = Color(1, 1, 1, 0.85)
	g.fx_node.add_child(spr)
	var tw = g.create_tween()
	tw.tween_property(spr, "scale", spr.scale * 1.6, 0.35)
	tw.parallel().tween_property(spr, "modulate:a", 0.0, 0.35)
	tw.tween_callback(spr.queue_free)


func request_explosion(pos: Vector2, radius: float, damage: int, from_id: int, weapon_id: int = -1) -> void:
	# FX on every peer; damage only on the server.
	# weapon_id: the weapon that caused it (4 = rocket), -2 = grenade,
	# -1 = barrel/other explosion (kill feed label).
	_spawn_explosion_fx(pos, radius)
	if g.multiplayer.is_server():
		var killer = g.players_node.get_node_or_null(str(from_id))
		var event_id = g.next_damage_event_id()
		for child in g.players_node.get_children():
			if child.alive:
				var dist: float = child.global_position.distance_to(pos)
				if dist > radius:
					continue
				# Line of sight (GAP-12): a wall/crate between the
				# blast and the player blocks damage AND knockback.
				if not g.has_line_of_sight(pos, child.global_position):
					continue
				# Lethal check (QA-141: MMC formula, same as
				# take_explosion_damage — the `damage` argument is
				# legacy and ignored there too): the host credits
				# the kill when its explosion kills. QA-069: same
				# guard as bullet.gd — only if the host's copy
				# still shows the victim alive and unprotected, or
				# a refused hit (spawn protection / already dead)
				# becomes a phantom kill in the feed and on the
				# scoreboard.
				var amount := int(round(maxf(PhysicsConfig.EXPLOSION_DAMAGE_MIN, PhysicsConfig.EXPLOSION_DAMAGE_MAX - PhysicsConfig.EXPLOSION_DAMAGE_FALLOFF * dist)))
				var lethal: bool = int(child.health) - amount <= 0 and child.alive and child._spawn_protect_timer <= 0.0
				# RPC to yourself is not allowed: call directly in that case.
				# A peer that disconnected mid-flight gets no RPC either.
				if child.get_multiplayer_authority() == g.multiplayer.get_unique_id():
					child.take_explosion_damage(pos, radius, damage, from_id, event_id)
				elif g.multiplayer.get_peers().has(child.get_multiplayer_authority()):
					child.rpc_id(child.get_multiplayer_authority(), "take_explosion_damage", pos, radius, damage, from_id, event_id)
				if lethal:
					# QA-031 (T-56): one credit per victim per lock
					# window — the credit + feed announce go through
					# the lock, not direct (as in bullet.gd).
					g.try_credit_kill(from_id, child.peer_id, weapon_id)
				# Phase 4: hitmarker for the shooter/thrower on every
				# victim actually hurt, kill feed on every lethal hit
				# (self-kills included — no hitmarker for hurting
				# yourself, but the feed shows it).
				if amount > 0 and killer != null and from_id != child.peer_id:
					if killer.get_multiplayer_authority() == g.multiplayer.get_unique_id():
						killer.hit_confirm(amount, child.global_position, lethal)
					elif g.multiplayer.get_peers().has(killer.get_multiplayer_authority()):
						killer.rpc_id(killer.get_multiplayer_authority(), "hit_confirm", amount, child.global_position, lethal)
		# Chain: barrels caught in the blast explode too (GAP-64).
		for b in g._barrels:
			if not bool(b["alive"]):
				continue
			var r: Rect2 = b["rect"]
			if r.get_center().distance_to(pos) <= radius:
				if g.has_line_of_sight(pos, r.get_center()):
					b["alive"] = false
					(b["sprite"] as Node2D).visible = false
					(b["shape"] as CollisionShape2D).set_deferred("disabled", true)
					g.rpc("barrel_destroyed_remote", g._barrels.find(b))
					request_explosion(r.get_center(), PhysicsConfig.BARREL_BLAST_RADIUS,
						int(PhysicsConfig.EXPLOSION_DAMAGE_MAX), from_id)


func _spawn_explosion_fx(pos: Vector2, radius: float) -> void:
	# QA-092 (v3.7): the blast core is the library explosion_small
	# (toon fireball + smoke + shockwave + embers, shader-driven)
	# instead of the old static fireball/smoke sprites. The base
	# effect is ~125 px wide, so it scales by radius / 62.5.
	# The white flash, debris, GPUParticles2D burst (QA-091) and
	# distance-scaled shake stay — the library's own shockwave ring
	# replaces the old Line2D ring, so the ring is not drawn twice.
	var boom = ReebooFx2D.spawn(GameAssets.EXPLOSION_SMALL_SCENE, g.fx_node, pos)
	boom.scale = Vector2(radius / 62.5, radius / 62.5)
	# QA-145 (v4.1): the user's explosion frames as a quick one-shot
	# sprite animation (3 frames over ~0.3 s) alongside the library
	# blast. Visual only; no damage code anywhere in this FX.
	var blast := Sprite2D.new()
	blast.texture = GameAssets.FX_TEX_EXPLOSION_FRAMES[0]
	var bscale := radius / 130.0
	blast.scale = Vector2(bscale, bscale)
	blast.position = pos
	blast.z_index = 5
	g.fx_node.add_child(blast)
	var twb = g.create_tween()
	twb.tween_interval(0.1)
	twb.tween_callback(func() -> void: blast.texture = GameAssets.FX_TEX_EXPLOSION_FRAMES[1])
	twb.tween_interval(0.1)
	twb.tween_callback(func() -> void: blast.texture = GameAssets.FX_TEX_EXPLOSION_FRAMES[2])
	twb.tween_interval(0.1)
	twb.tween_callback(blast.queue_free)
	# GAP-24: white flash + debris. Visual-only; no damage code
	# anywhere in this FX.
	var flash := Polygon2D.new()
	var fpts := PackedVector2Array()
	for i in 16:
		var a := TAU * float(i) / 16.0
		fpts.append(Vector2(cos(a), sin(a)) * radius * 0.5)
	flash.polygon = fpts
	flash.color = Color(1, 1, 1, 0.95)
	flash.position = pos
	g.fx_node.add_child(flash)
	var twf = g.create_tween()
	twf.tween_property(flash, "modulate:a", 0.0, 0.08)
	twf.tween_callback(flash.queue_free)
	for i in 8:
		var deb := Polygon2D.new()
		deb.polygon = PackedVector2Array([Vector2(-3, -3), Vector2(3, -3), Vector2(3, 3), Vector2(-3, 3)])
		deb.color = Color(0.9, 0.5, 0.15, 0.9)
		deb.position = pos
		g.fx_node.add_child(deb)
		var ang := randf() * TAU
		var dst := randf_range(40.0, radius)
		var twd = g.create_tween()
		twd.tween_property(deb, "position", pos + Vector2(cos(ang), sin(ang)) * dst, 0.4)
		twd.parallel().tween_property(deb, "modulate:a", 0.0, 0.4)
		twd.tween_callback(deb.queue_free)
	# QA-091 (v3.7, GRENADE_SPEC §4): GPUParticles2D blast burst —
	# orange sparks that fly out, slow under gravity and fade — plus
	# camera shake for the LOCAL player scaled by distance (full at
	# the blast, none past 3x the blast radius). The short white
	# flash on detonation already existed (GAP-24, above), and the
	# wall ray-check already existed in request_explosion (GAP-12),
	# so neither is added here. Purely visual: no damage code.
	var parts := GPUParticles2D.new()
	parts.texture = g.PARTICLE_DOT_TEX
	parts.amount = 28
	parts.lifetime = 0.55
	parts.one_shot = true
	parts.explosiveness = 0.9
	parts.position = pos
	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0, -1, 0)
	pmat.spread = 180.0
	# QA-101 (v3.8): particle speed scales with the blast radius, so
	# the smaller grenade burst (120) reads smaller. QA-109: rockets
	# are 120 too now; only barrels (still 170) are unchanged. The
	# boom core, flash and debris above already scale with radius.
	pmat.initial_velocity_min = 120.0 * radius / 170.0
	pmat.initial_velocity_max = 420.0 * radius / 170.0
	pmat.gravity = Vector3(0, 500, 0)
	pmat.damping_min = 50.0
	pmat.damping_max = 120.0
	pmat.scale_min = 0.5
	pmat.scale_max = 1.2
	pmat.color = Color(1.0, 0.6, 0.2)
	parts.process_material = pmat
	g.fx_node.add_child(parts)
	parts.emitting = true
	var twp = g.create_tween()
	twp.tween_interval(1.2)
	twp.tween_callback(parts.queue_free)
	var lp = g._get_local_player()
	if lp != null:
		var d: float = lp.global_position.distance_to(pos)
		var k := clampf(1.0 - d / (radius * 3.0), 0.0, 1.0)
		if k > 0.0:
			lp.add_shake(0.6 * k)
	g.audio.play("explosion")


class_name SkyfallBuilder
extends RefCounted


# QA-139 (v3.15): extracted from game.gd. This module owns no
# state of its own: every field it reads or writes lives on the
# game node and is reached through `g` (dependency injection).
# game.gd keeps a thin delegating wrapper for each function the
# rest of the game calls, so no call site had to change.


var g # the game node (game.gd)


func _init(game) -> void:
	g = game


func _draw_tiles(map: Dictionary, platforms: Array) -> void:
	var tex: Texture2D = GameAssets.TILE_TEX[clampi(int(map["tile"]), 0, GameAssets.TILE_TEX.size() - 1)]
	var tile_w := float(tex.get_width())
	var tile_h := float(tex.get_height())
	for rect in platforms:
		var r: Rect2 = rect
		var x: float = r.position.x
		while x < r.position.x + r.size.x - 0.5:
			var w := minf(tile_w, r.position.x + r.size.x - x)
			var spr := Sprite2D.new()
			spr.texture = tex
			spr.centered = false
			spr.position = Vector2(x, r.position.y)
			if w < tile_w:
				spr.region_enabled = true
				spr.region_rect = Rect2(0, 0, w, tile_h)
			g.add_child(spr)
			x += tile_w
		# QA-072 (terrain depth): a dark 16 px skirt under each
		# platform so the battlefield reads as solid ground, not a
		# floating dash. 16 px is far less than the >=122 px level
		# clearance, so it never touches anything below.
		var skirt := Polygon2D.new()
		skirt.polygon = PackedVector2Array([
			Vector2(r.position.x, r.position.y + r.size.y),
			Vector2(r.position.x + r.size.x, r.position.y + r.size.y),
			Vector2(r.position.x + r.size.x, r.position.y + r.size.y + 16.0),
			Vector2(r.position.x, r.position.y + r.size.y + 16.0)])
		skirt.color = Color(0, 0, 0, 0.25)
		g.add_child(skirt)


# ---------------------------------------------------------------------------
# QA-112 (v3.9) — SKYFALL builders + Vertical CTF + mechanics.
# Everything here is a no-op unless the loaded map has "skyfall".
# Moving platforms use AnimatableBody2D (sync_to_physics carries
# players standing on them); static platform shapes are found by
# position in the Arena body so _build_arena stays untouched.
# ---------------------------------------------------------------------------


func _build_skyfall(map: Dictionary) -> void:
	if not bool(map.get("skyfall", false)):
		return
	# QA-123 (v3.11): L2 Underground Tunnels: a dark band over the
	# tunnel level (y 7200-9000) so the corridor reads as a tunnel,
	# not open sky. Drawn here (behind the players, z -2).
	# QA-134 (v3.13): the lamp dots (small warm circles along the
	# tunnel floors) are REMOVED — the user asked for no yellow
	# circles. The dark tunnel band stays.
	var band := Polygon2D.new()
	band.polygon = PackedVector2Array([Vector2(0, 7200), Vector2(g.map_size.x, 7200), Vector2(g.map_size.x, 9000), Vector2(0, 9000)])
	band.color = Color(0.02, 0.02, 0.04, 0.45)
	band.z_index = -2
	g.add_child(band)
	# Summit roof: a red triangle over the gate + two dark pillars
	# flanking it, so the summit reads as a gatehouse. The pack has
	# no standalone summit building (ASSET_AUDIT.md §9) — this is
	# code-drawn from the gate + wall art, not a pasted strip.
	var roof := Polygon2D.new()
	roof.polygon = PackedVector2Array([Vector2(1660, 478), Vector2(1940, 478), Vector2(1800, 380)])
	roof.color = Color(0.62, 0.12, 0.12)
	roof.z_index = -1
	g.add_child(roof)
	for px in [1690, 1890]:
		var pillar := Polygon2D.new()
		pillar.polygon = PackedVector2Array([Vector2(px, 478), Vector2(px + 20, 478), Vector2(px + 20, 862), Vector2(px, 862)])
		pillar.color = Color(0.16, 0.16, 0.20)
		pillar.z_index = -1
		g.add_child(pillar)
	# Wind-zone overlays (faint, so the square edge barely shows).
	for w in map.get("wind", []):
		var wr: Rect2 = w["rect"]
		var ov := Sprite2D.new()
		ov.texture = GameAssets.SF_TEX_WIND
		ov.position = wr.get_center()
		ov.scale = Vector2(wr.size.x / 384.0, wr.size.y / 384.0)
		ov.modulate = Color(1, 1, 1, 0.55)
		ov.z_index = -1
		g.add_child(ov)
	# Extraction-zone rings at the bases (pulse in _update_skyfall).
	var ctf: Dictionary = map.get("ctf", {})
	for team in [0, 1]:
		var zpos: Vector2 = ctf.get("extract_red" if team == 0 else "extract_blue", Vector2.ZERO)
		var zspr := Sprite2D.new()
		zspr.texture = GameAssets.SF_TEX_ZONE_RED if team == 0 else GameAssets.SF_TEX_ZONE_BLUE
		zspr.position = zpos + Vector2(0, -10)
		zspr.scale = Vector2(0.9, 0.9)
		zspr.z_index = 1
		g.add_child(zspr)
		g._ctf_extract_nodes.append(zspr)
	# QA-114 (v3.9): relay stations — gold rings (radius = the 140 px
	# bank radius, so the zone is exactly what you see) + a label.
	for ri in (map.get("relay", []) as Array).size():
		var rp: Vector2 = (map.get("relay", []) as Array)[ri]
		var ring := Line2D.new()
		ring.width = 6.0
		ring.default_color = Color(1.0, 0.8, 0.2)
		var pts := PackedVector2Array()
		for i in 32:
			var a := TAU * float(i) / 32.0
			pts.append(rp + Vector2(cos(a), sin(a)) * 140.0)
		pts.append(rp + Vector2(140.0, 0))
		ring.points = pts
		ring.z_index = 1
		g.add_child(ring)
		var rlbl := Label.new()
		rlbl.text = "RELAY L%d  •  +1 pt" % [3 if ri == 0 else 6]
		# QA-114: below the ring, not above — above puts the label
		# in the top UI band (it collided with the "Waiting for
		# other players" message in the L4 screenshot).
		rlbl.position = rp + Vector2(-80, 60)
		rlbl.add_theme_font_size_override("font_size", 24)
		rlbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
		rlbl.z_index = 1
		g.add_child(rlbl)
	# QA-114 (v3.9): grapple points — gold ring, so a player can
	# spot them while climbing. QA-134 (v3.13): the solid yellow
	# centre dot is REMOVED (user: no yellow circles) — the thin
	# gold ring stays so the spot is still findable, and the
	# grapple mechanic itself is unchanged.
	for gp in map.get("grapple", []):
		var gpos: Vector2 = gp
		var gring := Line2D.new()
		gring.width = 4.0
		gring.default_color = Color(1.0, 0.85, 0.3)
		var gpts := PackedVector2Array()
		for i in 20:
			var a := TAU * float(i) / 20.0
			gpts.append(gpos + Vector2(cos(a), sin(a)) * 26.0)
		gpts.append(gpos + Vector2(26.0, 0))
		gring.points = gpts
		gring.z_index = 1
		g.add_child(gring)
	# QA-114 (v3.9): jetpack lines — QA-134 (v3.13): the bright
	# cyan guide lines through the wind zones and their
	# up-chevrons are REMOVED entirely (user: no blue lines or
	# arrows). The wind zones and the jetpack stay working, just
	# unmarked. The map data "jetpack_lines" is KEPT (FT-SF-MAP
	# asserts size == 2); only the drawing is deleted.
	# QA-114 (v3.9): colour-coded routes — every platform gets a
	# small strip in its route colour (WEST cyan / CENTRE gold /
	# EAST green, by x-centre). Same colours on the HUD height bar.
	var plats: Array = map.get("platforms", [])
	for pr in plats:
		var prect: Rect2 = pr
		var route = g.skyfall_route_of(prect.get_center().x)
		var strip := Polygon2D.new()
		var sx := prect.position.x
		var sy := prect.position.y
		strip.polygon = PackedVector2Array([Vector2(sx, sy - 6), Vector2(sx + 60, sy - 6), Vector2(sx + 60, sy), Vector2(sx, sy)])
		strip.color = g.SF_ROUTE_COLORS[route]
		strip.z_index = 1
		g.add_child(strip)
	# QA-115 (v3.9): dynamic scenery — the map must feel alive, not
	# a still picture. Scenery only, no gameplay effect.
	_build_skyfall_scenery(map)
	# QA-124 (v3.11): per-level themes — backdrop image + lighting +
	# mid silhouette + platform tint, one distinct look per level.
	_build_skyfall_themes(map)
	# QA-129 (v3.11): per-level weather/mood + ambient life.
	_build_skyfall_weather(map)
	# QA-126 (v3.11): hazard visuals (lava pool, fire jets) — the
	# damage itself runs in _sf_update_hazards.
	_build_skyfall_hazards(map)
	_build_skyfall_pendulums(map)
	_build_skyfall_movers(map)
	_build_skyfall_gate(map)
	_build_skyfall_switch(map)
	_build_skyfall_barricades(map)
	_build_skyfall_mines(map)
	_build_skyfall_platform_refs(map)
	g._build_ctf_flags()


func _sf_arena_shape_at(center: Vector2) -> CollisionShape2D:
	# The Arena StaticBody2D's shapes are positioned at their rect
	# centres — find one by position (within 1 px).
	var arena = g.get_node_or_null("Arena")
	if arena == null:
		return null
	for child in arena.get_children():
		if child is CollisionShape2D and (child as CollisionShape2D).position.distance_to(center) < 1.0:
			return child as CollisionShape2D
	return null


func _sf_tile_sprites_at(rect: Rect2) -> Array:
	# _draw_tiles adds one sprite per 512 px of platform, as a child
	# of the game, at (rect.x + k*512, rect.y). Collect them.
	var out: Array = []
	for child in g.get_children():
		if child is Sprite2D and absf((child as Sprite2D).position.y - rect.position.y) < 0.5 and (child as Sprite2D).position.x >= rect.position.x - 0.5 and (child as Sprite2D).position.x < rect.end.x:
			out.append(child)
	return out


func _build_skyfall_scenery(map: Dictionary) -> void:
	# QA-115 (v3.9): DYNAMIC SCENERY — drifting clouds, a flowing
	# waterfall, a helicopter crossing the sky, and distant
	# lightning flashes during the storm. All code-drawn (the pack
	# has no art for these) and all scenery-only: no collision, no
	# gameplay effect, ~20 nodes of cheap transforms (no per-frame
	# allocations), so phones are unaffected. The colours stay muted
	# so the routes stay readable. QA-132: the gears and steam
	# puffs are deleted (they read as solid platforms/circles).
	var clouds: Array = []
	for ci in 5:
		var cloud := Node2D.new()
		cloud.position = Vector2(float(ci) * 700.0 + 200.0, 600.0 + float(ci) * 1900.0)
		cloud.z_index = -2
		g.add_child(cloud)
		for bi in 3:
			var blob := Polygon2D.new()
			var pts := PackedVector2Array()
			for i in 16:
				var a := TAU * float(i) / 16.0
				pts.append(Vector2(cos(a) * (90.0 + float(bi) * 30.0), sin(a) * 28.0))
			blob.polygon = pts
			blob.color = Color(0.85, 0.88, 0.95, 0.10)
			blob.position = Vector2(float(bi) * 110.0 - 110.0, float(bi % 2) * 14.0)
			cloud.add_child(blob)
		clouds.append({"node": cloud, "speed": 12.0 + float(ci) * 4.0})
	# Waterfall on the left cliff face (Broken Cliffs, new L1,
	# y 9300-10500): a translucent sheet + 5 white streaks that
	# scroll downward.
	var fall := Polygon2D.new()
	fall.polygon = PackedVector2Array([Vector2(250, 9300), Vector2(330, 9300), Vector2(330, 10500), Vector2(250, 10500)])
	fall.color = Color(0.55, 0.75, 0.95, 0.30)
	fall.z_index = -1
	g.add_child(fall)
	var streaks: Array = []
	for si in 5:
		var st := Line2D.new()
		st.width = 3.0
		st.default_color = Color(1, 1, 1, 0.55)
		st.points = PackedVector2Array([Vector2(258 + float(si) * 14.0, 9350), Vector2(258 + float(si) * 14.0, 9450)])
		st.z_index = -1
		g.add_child(st)
		streaks.append(st)
	# Helicopter silhouette crossing the sky above the summit.
	var heli := Node2D.new()
	heli.position = Vector2(-200, 520)
	heli.z_index = -2
	g.add_child(heli)
	var hbody := Polygon2D.new()
	hbody.polygon = PackedVector2Array([Vector2(-40, 0), Vector2(30, -12), Vector2(60, 0), Vector2(30, 12), Vector2(-40, 10)])
	hbody.color = Color(0.08, 0.08, 0.10, 0.85)
	heli.add_child(hbody)
	var htail := Polygon2D.new()
	htail.polygon = PackedVector2Array([Vector2(-40, -4), Vector2(-95, -14), Vector2(-95, -6), Vector2(-40, 4)])
	htail.color = Color(0.08, 0.08, 0.10, 0.85)
	heli.add_child(htail)
	var hrotor := Line2D.new()
	hrotor.width = 3.0
	hrotor.default_color = Color(0.08, 0.08, 0.10, 0.85)
	hrotor.points = PackedVector2Array([Vector2(-70, -18), Vector2(70, -18)])
	heli.add_child(hrotor)
	# QA-132: the rotating gears are GONE (user report — toothed
	# circles that looked solid but had no collision) and the
	# steam puffs are GONE (same reason — circles you cannot land
	# on). The waterfall, helicopter and lightning flash stay.
	# Distant lightning flash: a full-map white sheet, invisible
	# until a storm flash fires (see _update_skyfall_scenery).
	var flash := Polygon2D.new()
	flash.polygon = PackedVector2Array([Vector2(0, 0), Vector2(3400, 0), Vector2(3400, 10800), Vector2(0, 10800)])
	flash.color = Color(1, 1, 1, 0.0)
	flash.z_index = -2
	g.add_child(flash)
	g._sf_scenery = {"clouds": clouds, "streaks": streaks, "heli": heli, "flash": flash, "flash_timer": 3.0, "flash_alpha": 0.0}


# QA-124 (v3.11) — PER-LEVEL THEMES: each of the 6 levels gets its
# OWN different visual theme — the ENTIRE background AND platforms
# change per level, not just a tint. Three depth layers per level:
# FAR = the pack's level image (z -6), MID = a level-specific
# silhouette (z -4), NEAR = decor + tinted platform tiles (z -1/0).
# Merged levels use BOTH their images (top half / bottom half).
# Level bands (y grows downward): L1 9000-10800, L2 7200-9000,
# L3 5400-7200, L4 3600-5400, L5 1800-3600, L6 0-1800.
func _build_skyfall_themes(map: Dictionary) -> void:
	# [top image, bottom image, platform tint, light overlay, name]
	var themes := [
		# QA-145 (v4.1, Worker U): L1 + L3 washes DEEPENED — the
		# L1 level_1 sunset was a flat saturated orange field
		# (red nameplates unreadable on it) and the L3 level_4
		# sky was a washed-out pale blue (white HUD text unreadable,
		# white cloud blobs glaring). Both washes are now dark and
		# cool, so the images mute to a calm terracotta (L1) and a
		# calm slate blue (L3); the themes stay distinct and the
		# platform tints are untouched (drawn above the wash).
		[GameAssets.SF_TEX_LVL_2, GameAssets.SF_TEX_LVL_1, Color(0.95, 0.85, 0.70), Color(0.12, 0.10, 0.18, 0.42), "Twin Base Camp + Broken Cliffs"],
		[GameAssets.SF_TEX_LVL_3, GameAssets.SF_TEX_LVL_3, Color(0.55, 0.55, 0.65), Color(0.0, 0.0, 0.10, 0.30), "Underground Tunnels"],
		[GameAssets.SF_TEX_LVL_4, GameAssets.SF_TEX_LVL_4, Color(1.0, 0.80, 0.55), Color(0.06, 0.09, 0.20, 0.38), "Hanging Bridge"],
		[GameAssets.SF_TEX_LVL_5, GameAssets.SF_TEX_LVL_5, Color(0.70, 0.85, 0.70), Color(0.05, 0.10, 0.20, 0.10), "Sniper Territory"],
		[GameAssets.SF_TEX_LVL_6, GameAssets.SF_TEX_LVL_6, Color(0.75, 0.80, 0.90), Color(1.0, 0.60, 0.30, 0.07), "Mechanical Ascent"],
		[GameAssets.SF_TEX_LVL_8, GameAssets.SF_TEX_LVL_7, Color(0.90, 0.95, 1.0), Color(0.10, 0.15, 0.35, 0.16), "The Last Stand + Flag Summit"],
	]
	for li in 6:
		var lvl := li + 1
		var y_top := 10800.0 - float(lvl) * 1800.0
		var th: Array = themes[li]
		# FAR: one image per 900 px half-band (2x scale, uniform —
		# the 1800x450 image covers 3600x900 with no distortion).
		for half in 2:
			var spr := Sprite2D.new()
			spr.texture = th[half]
			spr.position = Vector2(1800, y_top + 450.0 + float(half) * 900.0)
			spr.scale = Vector2(2.0, 2.0)
			spr.z_index = -6
			g.add_child(spr)
		# LIGHTING: a translucent mood wash over the whole level —
		# tunnels darkest, summit storm-blue, base warm. Day-to-dusk
		# as you climb: the wash darkens and cools with height.
		var wash := Polygon2D.new()
		wash.polygon = PackedVector2Array([Vector2(0, y_top), Vector2(3400, y_top), Vector2(3400, y_top + 1800), Vector2(0, y_top + 1800)])
		wash.color = th[3]
		wash.z_index = -5
		g.add_child(wash)
		# MID: a level-specific silhouette (z -4) + the platform
		# tint below. Silhouettes are code-drawn, muted, and never
		# touch the routes.
		_sf_build_level_silhouette(lvl, y_top)
	# NEAR: tint every platform's tile sprites in the level's colour.
	for pr in map.get("platforms", []):
		var prect: Rect2 = pr
		var tint: Color = (themes[g._sf_level_of(prect.position.y + 24.0) - 1] as Array)[2]
		for s in _sf_tile_sprites_at(prect):
			(s as Sprite2D).modulate = tint


func _sf_build_level_silhouette(lvl: int, y_top: float) -> void:
	# One muted mid-ground shape per level, drawn in the level band.
	# QA-132: only L1 keeps its silhouette (the cliff ridge — L1
	# is untouched). L2-L6 silhouettes are DELETED (user: clean
	# everything unnecessary): stalactites hung over the routes,
	# rope curves and watchtowers read as structures, the L5 pipes
	# were full-width bars that read as floors, and the L6 storm
	# peaks crowded the summit. The per-level FAR backdrops +
	# lighting wash stay (QA-124 themes), so each level still has
	# its own look.
	match lvl:
		1: # Broken Cliffs: a jagged cliff ridge across the top half.
			var ridge := Polygon2D.new()
			var pts := PackedVector2Array([Vector2(0, y_top + 900)])
			var seed := 777
			var x := 0.0
			while x < 3400.0: # QA-132: right boundary is 3400 now, not 3600
				seed = (seed * 1103515245 + 12345) & 0x7fffffff
				var w := 200.0 + float(seed % 260)
				seed = (seed * 1103515245 + 12345) & 0x7fffffff
				var h := 120.0 + float(seed % 220)
				pts.append(Vector2(x, y_top + 900.0 - h))
				pts.append(Vector2(minf(x + w, 3400.0), y_top + 900.0 - h))
				x += w + 60.0
			pts.append(Vector2(3400, y_top + 900))
			ridge.polygon = pts
			ridge.color = Color(0.32, 0.26, 0.20, 0.55)
			ridge.z_index = -4
			g.add_child(ridge)
		_: # L2-L6: no mid silhouette (QA-132 clean-up).
			pass


# QA-129 (v3.11) — PER-LEVEL WEATHER / MOOD + AMBIENT LIFE. All
# sprites are cheap transforms (no particles nodes, no shaders):
# dust in Base Camp, drips in the Tunnels, the base-camp waving
# flag, and storm rain + dark overlay (hidden until a storm).
# QA-132: leaves, steam, snow, storm/mid clouds, birds, portals,
# whirlpool and arcs are deleted (clean-up). Gust streaks stay
# (storm telegraphs). Counts are capped so phones stay safe.


# QA-129 (v3.11) — PER-LEVEL WEATHER / MOOD + AMBIENT LIFE. All
# sprites are cheap transforms (no particles nodes, no shaders):
# dust in Base Camp, drips in the Tunnels, the base-camp waving
# flag, and storm rain + dark overlay (hidden until a storm).
# QA-132: leaves, steam, snow, storm/mid clouds, birds, portals,
# whirlpool and arcs are deleted (clean-up). Gust streaks stay
# (storm telegraphs). Counts are capped so phones stay safe.
func _build_skyfall_weather(map: Dictionary) -> void:
	var w: Dictionary = {}
	var dust: Array = []
	for i in 4:
		var d := Sprite2D.new()
		d.texture = GameAssets.FX_TEX_DUST
		d.position = Vector2(400.0 + float(i) * 800.0, 9900.0 + float(i % 2) * 500.0)
		d.scale = Vector2(0.5, 0.5)
		d.modulate = Color(1, 1, 1, 0.35)
		d.z_index = -3
		g.add_child(d)
		dust.append({"node": d, "speed": 14.0 + float(i) * 5.0})
	w["dust"] = dust
	var drips: Array = []
	for i in 4:
		var d := Sprite2D.new()
		d.texture = GameAssets.FX_TEX_RAIN
		d.position = Vector2(500.0 + float(i) * 800.0, 7400.0 + float(i % 2) * 600.0)
		d.scale = Vector2(0.35, 0.35)
		d.modulate = Color(1, 1, 1, 0.4)
		d.z_index = -3
		g.add_child(d)
		drips.append(d)
	w["drips"] = drips
	# QA-132: leaves (L3), steam (L5), snow (L6), storm clouds
	# (L6) and mid clouds (L5) are DELETED (user: clean everything
	# unnecessary). Dust (L1) and drips (L2) stay.
	# Storm rain over the top two levels — hidden until a storm.
	var rain: Array = []
	for i in 8:
		var r := Sprite2D.new()
		r.texture = GameAssets.FX_TEX_RAIN
		r.position = Vector2(200.0 + float(i) * 420.0, 200.0 + float(i % 4) * 500.0)
		r.scale = Vector2(0.8, 0.8)
		r.modulate = Color(1, 1, 1, 0.6)
		r.z_index = 3
		r.visible = false
		g.add_child(r)
		rain.append(r)
	w["rain"] = rain
	# Storm dark overlay over the top two levels (fades in with the storm).
	var dark := Polygon2D.new()
	dark.polygon = PackedVector2Array([Vector2(0, 0), Vector2(3400, 0), Vector2(3400, 3600), Vector2(0, 3600)])
	dark.color = Color(0.05, 0.08, 0.20, 0.0)
	dark.z_index = -5
	g.add_child(dark)
	w["storm_dark"] = dark
	# Waving flag: base camp only (pennant skews with sin).
	# QA-132: the L4 flag at (3000,3664) is DELETED (clean-up).
	var flags: Array = []
	for fp in [Vector2(400, 10752)]:
		var pole := Polygon2D.new()
		pole.polygon = PackedVector2Array([Vector2(fp.x - 2, fp.y), Vector2(fp.x + 2, fp.y), Vector2(fp.x + 2, fp.y - 90), Vector2(fp.x - 2, fp.y - 90)])
		pole.color = Color(0.15, 0.15, 0.18)
		pole.z_index = -1
		g.add_child(pole)
		var pen := Polygon2D.new()
		pen.polygon = PackedVector2Array([Vector2(0, 0), Vector2(64, 10), Vector2(0, 22)])
		pen.color = Color(0.85, 0.12, 0.12)
		pen.position = Vector2(fp.x + 2, fp.y - 90)
		pen.z_index = -1
		g.add_child(pen)
		flags.append(pen)
	w["flags"] = flags
	# QA-132: the portal markers (1800,6100) + (1800,2050) are
	# DELETED — big rotating discs with no collision and no
	# teleport, they read as platforms you cannot land on. The
	# grapple points at those exact spots STAY (gold ring + dot,
	# drawn in _build_skyfall). The wind whirlpool (1800,6400)
	# and the electric arcs by the gears are DELETED too.
	# Gust streaks for the bridge wind gusts (hidden until a gust).
	# QA-135 (v3.13): 5 streaks now — the first 3 cover the old
	# L3 wind zone (y 6000-6800), the last 2 the new upper L3 zone
	# (y 5400-6000).
	var gusts: Array = []
	var gust_pos := [Vector2(600, 6200), Vector2(1500, 6500), Vector2(2400, 6200), Vector2(1500, 5600), Vector2(2100, 5750)]
	for i in gust_pos.size():
		var local_g := Sprite2D.new()
		local_g.texture = GameAssets.FX_TEX_GUST_R if i % 2 == 0 else GameAssets.FX_TEX_GUST_L
		local_g.position = gust_pos[i]
		local_g.scale = Vector2(0.9, 0.9)
		local_g.modulate = Color(1, 1, 1, 0.0)
		local_g.z_index = 2
		g.add_child(local_g)
		gusts.append(local_g)
	w["gusts"] = gusts
	g._sf_scenery["weather"] = w


# QA-126 (v3.11) — HAZARD VISUALS: lava pool + fire jet sprites on
# the Mechanical Ascent hazard rects. The flames are pure functions
# of the match clock (2 s hot / 2 s safe per 4 s cycle) so every peer
# sees the same telegraph; the damage tick itself is host-only in
# _sf_update_hazards.
func _build_skyfall_hazards(map: Dictionary) -> void:
	for hz in map.get("hazards", []):
		var r: Rect2 = hz["rect"]
		var kind: String = str(hz.get("kind", "lava"))
		var flame := Sprite2D.new()
		if kind == "fire":
			# QA-145 (v4.1): the fire jet is now the user's flame_jet
			# art (152x305 canvas, growth sequence — ping-ponged in
			# _sf_update_hazards). At rect width 200 the raw scale
			# would be 1.32 wide / ~400 tall, so it runs at 0.75
			# (150 wide, ~229 tall). Anchored by the rect bottom.
			flame.texture = GameAssets.FX_TEX_FLAME_JET[1]
			flame.scale = Vector2(r.size.x / 152.0 * 0.75, 0.75)
			flame.position = Vector2(r.get_center().x, r.end.y - 305.0 * 0.75 * 0.5)
		else:
			# QA-145 (v4.1): lava pools use the ground_fire frames
			# (269x134 canvas, forward loop in _sf_update_hazards
			# while HOT). Anchored by the rect bottom, not centred.
			flame.texture = GameAssets.FX_TEX_GROUND_FIRE[0]
			var ls := r.size.x / 269.0
			flame.scale = Vector2(ls, ls)
			flame.position = Vector2(r.get_center().x, r.end.y - 134.0 * ls * 0.5)
		flame.modulate = Color(1, 1, 1, 0.85)
		flame.z_index = 1
		g.add_child(flame)
		var magma: Sprite2D = null
		if kind == "lava":
			magma = Sprite2D.new()
			magma.texture = GameAssets.FX_TEX_MAGMA
			magma.position = r.get_center() + Vector2(0, -30)
			magma.scale = Vector2(0.5, 0.5)
			magma.modulate = Color(1, 1, 1, 0.0)
			magma.z_index = 1
			g.add_child(magma)
		g._sf_hazard_fx.append({"kind": kind, "rect": r, "flame": flame, "magma": magma, "cycle": float(hz.get("cycle", 4.0)), "base_scale": flame.scale})


func _build_skyfall_pendulums(map: Dictionary) -> void:
	# QA-137 (v3.14): swinging spiked wrecking-ball pendulums
	# (the user's trap sheet). A pivot Node2D holds a chain
	# (Line2D) and the ball sprite; the swing is a pure function
	# of the match clock, so every peer agrees with no sync.
	for cfg in map.get("pendulums", []):
		var pivot: Vector2 = cfg.get("pivot", Vector2(1800, 3650))
		var plen := float(cfg.get("len", 220.0))
		var node := Node2D.new()
		node.name = "Pendulum_%d_%d" % [int(pivot.x), int(pivot.y)]
		node.position = pivot
		node.z_index = 2
		g.add_child(node)
		# Anchor bolt at the pivot so the chain reads as mounted.
		var mount := Polygon2D.new()
		var mpts := PackedVector2Array()
		for i in 8:
			var a := TAU * float(i) / 8.0
			mpts.append(Vector2(cos(a), sin(a)) * 10.0)
		mount.polygon = mpts
		mount.color = Color(0.25, 0.25, 0.28)
		node.add_child(mount)
		var chain := Line2D.new()
		chain.width = 4.0
		chain.default_color = Color(0.35, 0.35, 0.38)
		chain.points = PackedVector2Array([Vector2.ZERO, Vector2(0, plen)])
		node.add_child(chain)
		var ball := Sprite2D.new()
		ball.texture = GameAssets.TRAP_TEX_BALL
		ball.position = Vector2(0, plen)
		ball.z_index = 2
		node.add_child(ball)
		g._sf_pendulums.append({"pivot": pivot, "len": plen, "node": node, "chain": chain, "ball": ball, "phase": float(g._sf_pendulums.size()) * 1.3, "tick": {}})


func _build_skyfall_movers(map: Dictionary) -> void:
	# Moving elevators (L6): AnimatableBody2D, ping-pong between
	# y_top and y_bottom. sync_to_physics carries riders.
	for cfg in map.get("elevators", []):
		var body := AnimatableBody2D.new()
		body.name = "Elevator_%d" % int(cfg["x"])
		body.collision_layer = 1
		body.collision_mask = 0
		body.sync_to_physics = true
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(float(cfg["w"]), 48.0)
		shape.shape = box
		body.add_child(shape)
		var spr := Sprite2D.new()
		spr.texture = GameAssets.SF_TEX_ELEVATOR
		spr.position = Vector2(0, 24) # slab art is 96 tall; top aligns with the collision top
		body.add_child(spr)
		var y_mid := (float(cfg["y_top"]) + float(cfg["y_bottom"])) * 0.5
		body.position = Vector2(float(cfg["x"]) + float(cfg["w"]) * 0.5, y_mid + 24.0)
		g.add_child(body)
		g._sf_elevators.append({"body": body, "sprite": spr, "cfg": cfg, "phase": float(cfg.get("phase", 0.0))})
	# Rotating platform (L6): orbits its centre.
	var rot: Dictionary = map.get("rotator", {})
	if not rot.is_empty():
		var body := AnimatableBody2D.new()
		body.name = "Rotator"
		body.collision_layer = 1
		body.collision_mask = 0
		body.sync_to_physics = true
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(float(rot.get("w", 400)), 48.0)
		shape.shape = box
		body.add_child(shape)
		var spr := Sprite2D.new()
		spr.texture = GameAssets.SF_TEX_ELEVATOR
		spr.region_enabled = true
		spr.region_rect = Rect2(0, 0, float(rot.get("w", 400)), 96)
		spr.position = Vector2(0, 24)
		body.add_child(spr)
		body.position = (rot["center"] as Vector2) + Vector2(float(rot.get("radius", 120.0)), 0)
		g.add_child(body)
		g._sf_rotator = {"body": body, "sprite": spr, "cfg": rot, "angle": 0.0}
	# Summit elevator: docked at the arena until the control switch
	# activates it (then it shuttles arena <-> summit for 30 s).
	var se: Dictionary = map.get("summit_elevator", {})
	if not se.is_empty():
		var body := AnimatableBody2D.new()
		body.name = "SummitElevator"
		body.collision_layer = 1
		body.collision_mask = 0
		body.sync_to_physics = true
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(float(se.get("w", 300)), 48.0)
		shape.shape = box
		body.add_child(shape)
		var spr := Sprite2D.new()
		spr.texture = GameAssets.SF_TEX_ELEVATOR
		spr.region_enabled = true
		spr.region_rect = Rect2(0, 0, float(se.get("w", 300)), 96)
		spr.position = Vector2(0, 24)
		body.add_child(spr)
		body.position = Vector2(float(se["x"]) + float(se.get("w", 300)) * 0.5, float(se["y_bottom"]) + 24.0)
		g.add_child(body)
		g._sf_summit_elevator = {"body": body, "sprite": spr, "cfg": se, "state": "docked", "timer": 0.0, "dir": -1.0}


func _build_skyfall_gate(map: Dictionary) -> void:
	# Summit gate: stands on the summit floor, bars vertical, gaps
	# transparent (the pack's gate art). Blocks the middle of the
	# summit floor until it opens 45 s into the match; the side
	# ledges are always open, so it never blocks the climb.
	var local_g: Dictionary = map.get("gate", {})
	if local_g.is_empty():
		return
	var gx := float(local_g.get("x", 1800))
	var gy := float(local_g.get("y", 862))
	var spr := Sprite2D.new()
	spr.texture = GameAssets.SF_TEX_GATE
	spr.position = Vector2(gx, gy - 192)
	spr.z_index = 2
	g.add_child(spr)
	g._sf_gate_sprite = spr
	var arena = g.get_node_or_null("Arena")
	if arena != null:
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(116, 378)
		shape.shape = box
		shape.position = Vector2(gx, gy - 189)
		arena.add_child(shape)
		g._sf_gate_shape = shape
	g._sf_gate_open = false
	g._sf_gate_timer = 45.0


func _build_skyfall_switch(map: Dictionary) -> void:
	# Summit Control Switch on the arena floor: stand next to it
	# for 1 s to activate the summit elevator for 30 s.
	var sw: Dictionary = map.get("switch", {})
	if sw.is_empty():
		return
	var pos: Vector2 = sw.get("pos", Vector2(1800, 1712))
	var spr := Sprite2D.new()
	spr.texture = GameAssets.SF_TEX_SWITCH
	spr.position = pos + Vector2(0, -128)
	spr.z_index = 2
	g.add_child(spr)
	# The 1 s channel is checked by distance in _update_skyfall
	# (any alive player within 90 px of the switch) — no Area2D
	# needed, and distance is simpler to test.
	g._sf_switch_on = false
	g._sf_switch_timer = 0.0


func _build_skyfall_barricades(map: Dictionary) -> void:
	# Destructible wooden barricades on the arena floor: solid
	# cover, 100 HP, break when shot (try_barricade_hit, same
	# pattern as barrels) or caught in a blast, respawn in 30 s.
	var arena = g.get_node_or_null("Arena")
	for b in map.get("barricades", []):
		var pos: Vector2 = b.get("pos", Vector2.ZERO)
		var spr := Sprite2D.new()
		spr.texture = GameAssets.SF_TEX_BARRICADE
		spr.position = pos + Vector2(0, -96)
		spr.z_index = 2
		g.add_child(spr)
		var shape: CollisionShape2D = null
		if arena != null:
			shape = CollisionShape2D.new()
			var box := RectangleShape2D.new()
			box.size = Vector2(148, 180)
			shape.shape = box
			shape.position = pos + Vector2(0, -90)
			arena.add_child(shape)
		g._sf_barricades.append({"rect": Rect2(pos + Vector2(-74, -180), Vector2(148, 180)), "sprite": spr, "shape": shape, "hp": 100.0, "alive": true, "timer": 0.0})


func _build_skyfall_mines(map: Dictionary) -> void:
	# QA-145 (v4.1, Worker T): proximity mines (see map_data).
	# Code-drawn, no new art: a dark disc (14 px) with a red dot
	# (5 px) that blinks at 2 Hz while armed and 8 Hz during the
	# fuse — the blink is a pure function of the match clock in
	# _sf_update_mines, so every peer agrees. Mines are NOT solid
	# (no Arena shape — players walk over them, which is the point).
	for cfg in map.get("mines", []):
		var pos: Vector2 = cfg.get("pos", Vector2.ZERO)
		var node := Node2D.new()
		node.name = "Mine_%d_%d" % [int(pos.x), int(pos.y)]
		node.position = pos
		node.z_index = 2
		g.add_child(node)
		var disc := Polygon2D.new()
		var pts := PackedVector2Array()
		for i in 16:
			var a := TAU * float(i) / 16.0
			pts.append(Vector2(cos(a), sin(a)) * 14.0)
		disc.polygon = pts
		disc.color = Color(0.12, 0.12, 0.14)
		node.add_child(disc)
		var dot := Polygon2D.new()
		var dpts := PackedVector2Array()
		for i in 8:
			var a := TAU * float(i) / 8.0
			dpts.append(Vector2(cos(a), sin(a)) * 5.0)
		dot.polygon = dpts
		dot.color = Color(1.0, 0.15, 0.1)
		node.add_child(dot)
		g._sf_mines.append({"pos": pos, "node": node, "dot": dot, "state": "armed", "timer": 0.0})


func _build_skyfall_platform_refs(map: Dictionary) -> void:
	# Collapsing bridge middle + trapdoors: find their Arena shapes
	# + tile sprites by position (see _sf_arena_shape_at /
	# _sf_tile_sprites_at). QA-132: the storm-perch loop is gone
	# with the disable mechanic — the perches stay landable.
	var plats: Array = map["platforms"]
	for idx in map.get("collapsing", []):
		var r: Rect2 = plats[int(idx)]
		var sprs: Array = _sf_tile_sprites_at(r)
		# QA-137: the collapsing platforms wear the user's grate
		# art (trap sheet row 1, 164x48 - exactly the platform
		# height). Each tile sprite shows one grate stretched to
		# its segment width, so the platform reads as a grate.
		for s in sprs:
			var sp := s as Sprite2D
			var seg_w := minf(512.0, r.end.x - sp.position.x)
			sp.texture = GameAssets.TRAP_TEX_GRATE
			sp.region_enabled = true
			sp.region_rect = Rect2(0, 0, 164, 48)
			sp.scale = Vector2(seg_w / 164.0, 1.0)
		g._sf_collapsing.append({"idx": int(idx), "rect": r, "shape": _sf_arena_shape_at(r.get_center()), "sprites": sprs, "state": "idle", "timer": 0.0, "grate": true})
	for idx in map.get("trapdoors", []):
		var r: Rect2 = plats[int(idx)]
		var sprs: Array = _sf_tile_sprites_at(r)
		for s in sprs:
			(s as Sprite2D).texture = GameAssets.SF_TEX_TRAPDOOR_CLOSED
			(s as Sprite2D).region_enabled = true
			(s as Sprite2D).region_rect = Rect2(0, 0, minf(512.0, r.size.x), 48)
		g._sf_trapdoors.append({"idx": int(idx), "rect": r, "shape": _sf_arena_shape_at(r.get_center()), "sprites": sprs, "state": "closed", "timer": 0.0})


# ---------------------------------------------------------------------------
# QA-112 (v3.9) — Vertical CTF (mode 4, SKYFALL ONLY). Restored from
# the v3.6 CTF (QA-080) and adapted: BOTH flags live at the SUMMIT,
# captures score at the base EXTRACTION ZONES, grabbing takes a
# 1.5 s hold, a dropped flag returns after 15 s, the carrier is
# 15% slower with no jetpack (player.gd reads carrying_flag).
# Host-authoritative; clients only render what ctf_sync sends.
# ---------------------------------------------------------------------------


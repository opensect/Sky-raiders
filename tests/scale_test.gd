class_name ScaleTest
extends RefCounted


# QA-140 (v3.15): extracted from game.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `g` (dependency injection).


var g # the owner (game.gd)

var _scale_test: bool = false
var _scale_done: bool = false
var _scale_steps: Array = []
var _scale_step: int = 0
var _scale_in_step: bool = false
var _scale_timer: float = 0.0
var _scale_passed: int = 0
var _scale_failed: int = 0
var _collision_test: bool = false
var _ct_done: bool = false
var _ct_steps: Array = []
var _ct_step: int = 0
var _ct_in_step: bool = false
var _ct_timer: float = 0.0
var _ct_passed: int = 0
var _ct_failed: int = 0
var _ct_walk_start_x: float = 0.0
var _ct_grenade: Node = null
var _ct_walk_dir: int = 1


func _init(owner) -> void:
	g = owner


func _ct_build_steps() -> void:
	_ct_steps = [
		{"name": "STATIC-ALL-MAPS", "wait": 0.3, "setup": _ct_s_noop, "check": _ct_c_static_all_maps},
		{"name": "BULLET-STOPS-SOLID", "wait": 0.3, "setup": _ct_s_noop, "check": _ct_c_bullet_stops},
		{"name": "BULLET-BLOCKS-TARGET", "wait": 0.3, "setup": _ct_s_noop, "check": _ct_c_bullet_blocks_target},
		{"name": "WALK-BLOCKED", "wait": 1.0, "setup": _ct_s_walk_into_solid, "check": _ct_c_walk_blocked},
		{"name": "BULLET-STOPS-FLOOR", "wait": 0.3, "setup": _ct_s_noop, "check": _ct_c_bullet_stops_floor},
		{"name": "GRENADE-BLOCKED", "wait": 1.2, "setup": _ct_s_throw_grenade, "check": _ct_c_grenade_blocked},
		{"name": "BULLET-PASSES-BUSH", "wait": 0.3, "setup": _ct_s_noop, "check": _ct_c_bullet_passes_bush},
		{"name": "WALK-PASSES-BUSH", "wait": 2.0, "setup": _ct_s_walk_into_bush, "check": _ct_c_walk_passes_bush},
	]


# (a) a ray aimed at a point behind the cover still stops at the cover
# — a target behind it takes no damage.
func _ct_c_bullet_blocks_target() -> Array:
	var cover := _ct_floor_cover()
	if cover == Rect2():
		return [true, "no low solid cover on this map"]
	var cy := cover.get_center().y
	# QA-033: same clamp as _ct_c_bullet_stops — a near-edge cover
	# would otherwise let the boundary wall at x=0 stop the ray and
	# pass this check for the wrong reason.
	var from := Vector2(maxf(cover.position.x - 120.0, 5.0), cy)
	var to := Vector2(cover.end.x + 120.0, cy)
	var hit := _ct_ray(from, to)
	if hit.is_empty():
		return [false, "ray %s -> %s passed clean through %s" % [from, to, cover]]
	var hp: Vector2 = hit["position"]
	var ok: bool = hp.x <= cover.position.x + 4.0
	return [ok, "ray stopped at %s (cover %s); nothing behind it is reachable" % [hp, cover]]


# (d) a ray through a bush / tree / palm passes clean through — the
# dressing has no collision.
func _ct_c_bullet_passes_bush() -> Array:
	var bush := _ct_nonsolid_rect()
	if bush == Rect2():
		return [true, "no pass-through decor on this map — covered on Jungle Ruins"]
	var cy := bush.get_center().y
	# Start the ray just left of the decor, but never off the map
	# (the left wall would stop it first and the test would lie).
	var from := Vector2(maxf(bush.position.x - 120.0, 30.0), cy)
	var hit := _ct_ray(from, Vector2(bush.end.x + 120.0, cy))
	if hit.is_empty():
		return [true, "ray passed clean through %s (no hit)" % bush]
	var hp: Vector2 = hit["position"]
	return [false, "ray stopped at %s inside pass-through decor %s" % [hp, bush]]


# (a) a ray at a solid cover's face stops there — the bullet never
# passes through it.
func _ct_c_bullet_stops() -> Array:
	var cover := _ct_floor_cover()
	if cover == Rect2():
		return [true, "no low solid cover on this map — nothing to stop"]
	var cy := cover.get_center().y
	# QA-033: clamp the ray start inside the map — a cover near the
	# left edge (e.g. sandbags at x=120) puts
	# cover.x - 120 outside the arena, and the ray then hits the
	# boundary wall at x=0 instead of the cover face.
	var from := Vector2(maxf(cover.position.x - 120.0, 5.0), cy)
	var to := Vector2(cover.position.x + 120.0, cy)
	var hit := _ct_ray(from, to)
	if hit.is_empty():
		return [false, "ray %s -> %s passed through %s with no hit" % [from, to, cover]]
	var hp: Vector2 = hit["position"]
	var ok: bool = absf(hp.x - cover.position.x) <= 4.0
	return [ok, "ray hit at %s (cover face x=%.0f, cover %s)" % [hp, cover.position.x, cover]]


# (c) a ray straight down stops at the floor top.
func _ct_c_bullet_stops_floor() -> Array:
	var x := _ct_floor_ray_x()
	var m: Dictionary = g.MAPS[g.map_id]
	var plats: Array = m["platforms"]
	var floor_top := 0.0
	for p in plats:
		var r: Rect2 = p
		if x >= r.position.x and x <= r.end.x:
			floor_top = maxf(floor_top, r.position.y)
	var hit := _ct_ray(Vector2(x, floor_top - 100.0), Vector2(x, floor_top + 100.0))
	if hit.is_empty():
		return [false, "downward ray at x=%.0f passed through the floor (top %.0f)" % [x, floor_top]]
	var hp: Vector2 = hit["position"]
	var ok: bool = absf(hp.y - floor_top) <= 4.0
	return [ok, "ray hit at %s (floor top %.0f at x=%.0f)" % [hp, floor_top, x]]


# (g) a grenade thrown at a tall solid bounces off it and never
# crosses its face.
func _ct_c_grenade_blocked() -> Array:
	var tall := _ct_tall_solid()
	if tall == Rect2():
		return [true, "no tall solid on this map"]
	# QA-132: Skyfall's decor is L1-only now (user: clean everything
	# unnecessary) and its tallest solid is 40 px — a grenade thrown
	# with init vel (575, -490) rises ~86 px and clears it, so there
	# is nothing tall enough to bounce off. The bounce itself is
	# covered on the other maps; a short solid is not a failure.
	if tall.size.y < 90.0:
		return [true, "tallest solid only %.0f px tall — too short to block a grenade arc (covered on Ironfall)" % tall.size.y]
	if _ct_grenade == null or not is_instance_valid(_ct_grenade):
		return [false, "grenade never spawned"]
	var grn: Node2D = _ct_grenade
	var ok: bool = grn.position.x < tall.position.x
	return [ok, "grenade x=%.0f after 1.2 s (solid face %.0f, solid %s)" % [grn.position.x, tall.position.x, tall]]


func _ct_c_static_all_maps() -> Array:
	var problems: Array = []
	var checked_spawns := 0
	var checked_pickups := 0
	var checked_rects := 0
	for mi in g.MAPS.size():
		var m: Dictionary = g.MAPS[mi]
		var rects := _ct_solid_rects(m)
		checked_rects += rects.size()
		var spawns: Array = m["spawns"]
		var pickups: Array = m["pickups"]
		var plats: Array = m["platforms"]
		# (f) spawns: the player capsule is 40 wide, 62 tall, centred
		# on the spawn point — it must not start inside a solid.
		for si in spawns.size():
			var sp: Vector2 = spawns[si]
			checked_spawns += 1
			var box := Rect2(sp - Vector2(20, 31), Vector2(40, 62)) # QA-071b: 40x62 capsule
			for rr in rects:
				if (rr as Rect2).intersects(box):
					problems.append("%s spawn#%d inside solid %s" % [m["name"], si, rr])
		# (f) pickups: the collection circle is radius 22 — its centre
		# must be reachable, i.e. the circle must not overlap a solid.
		for pi in pickups.size():
			var pp: Vector2 = pickups[pi]
			checked_pickups += 1
			for rr in rects:
				var r: Rect2 = rr
				var cx := clampf(pp.x, r.position.x, r.position.x + r.size.x)
				var cy := clampf(pp.y, r.position.y, r.position.y + r.size.y)
				if Vector2(cx, cy).distance_to(pp) < 22.0:
					problems.append("%s pickup#%d inside solid %s" % [m["name"], pi, rr])
		# (f) no solid may seal a platform: a solid that spans a
		# platform's full width with <100 px clearance above it would
		# block the only route across that platform.
		for rr in rects:
			var r: Rect2 = rr
			for p in plats:
				var pr: Rect2 = p
				if absf(r.end.y - pr.position.y) < 2.0 and r.position.x <= pr.position.x + 4.0 and r.end.x >= pr.end.x - 4.0:
					var top := r.position.y
					var above := 0.0
					for p2 in plats:
						var pr2: Rect2 = p2
						if pr2.end.y <= top + 1.0 and pr2.position.x <= r.get_center().x and pr2.end.x >= r.get_center().x:
							above = maxf(above, pr2.end.y)
					if top - above < 100.0:
						problems.append("%s solid %s seals platform %s" % [m["name"], r, pr])
		# (f) reachability: every spawn and pickup must attach to a
		# platform reachable from spawn#0 through jump/jetpack moves.
		if not _ct_map_reachable(m):
			problems.append("%s not fully reachable" % m["name"])
	var ok := problems.is_empty()
	return [ok, "%d maps, %d solid rects, %d spawns, %d pickups: %s" % [g.MAPS.size(), checked_rects, checked_spawns, checked_pickups, "all clear" if ok else "; ".join(problems)]]


# (b) walking into a solid cover: the player is blocked and slides
# along it, never passing through.
func _ct_c_walk_blocked() -> Array:
	g._on_touch_release(930)
	var cover := _ct_floor_cover()
	if cover == Rect2():
		return [true, "no low solid cover on this map"]
	var lp = g._get_local_player()
	if _ct_walk_dir > 0:
		var moved: bool = lp.position.x > _ct_walk_start_x + 20.0
		var stopped: bool = lp.position.x <= cover.position.x - 20.0 + 4.0
		return [moved and stopped, "player x=%.0f (started %.0f, cover face %.0f, capsule edge %.0f)" % [lp.position.x, _ct_walk_start_x, cover.position.x, cover.position.x - 20.0]]
	var moved2: bool = lp.position.x < _ct_walk_start_x - 20.0
	var stopped2: bool = lp.position.x >= cover.end.x + 20.0 - 4.0
	return [moved2 and stopped2, "player x=%.0f (started %.0f, cover face %.0f, capsule edge %.0f, walking left)" % [lp.position.x, _ct_walk_start_x, cover.end.x, cover.end.x + 20.0]]


# (e) walking through a bush / tree: the player passes it, unblocked.
func _ct_c_walk_passes_bush() -> Array:
	g._on_touch_release(930)
	var bush := _ct_nonsolid_rect()
	if bush == Rect2():
		return [true, "no pass-through decor on this map — covered on Jungle Ruins"]
	var lp = g._get_local_player()
	var ok: bool = lp.position.x > bush.end.x + 20.0
	return [ok, "player x=%.0f (bush %s, must be past %.0f)" % [lp.position.x, bush, bush.end.x + 20.0]]


# First low solid cover sitting on the floor (crate / barrels / rock /
# sandbags / jungle crate / jungle rock) — the cover the bullet and
# walk tests use. Empty when the map has none.
func _ct_floor_cover() -> Rect2:
	var m: Dictionary = g.MAPS[g.map_id]
	var plats: Array = m["platforms"]
	var floor_top := 0.0
	for p in plats:
		var r: Rect2 = p
		floor_top = maxf(floor_top, r.position.y)
	for rr in _ct_solid_rects(m):
		var r: Rect2 = rr
		if absf(r.end.y - floor_top) < 2.0 and r.size.y <= 100.0:
			return r
	return Rect2()


# A clear x on the floor (no solid decor over it) for the floor ray.
func _ct_floor_ray_x() -> float:
	var m: Dictionary = g.MAPS[g.map_id]
	var plats: Array = m["platforms"]
	var floor_top := 0.0
	var floor_x := 0.0
	var floor_w := 0.0
	for p in plats:
		var r: Rect2 = p
		if r.position.y > floor_top:
			floor_top = r.position.y
			floor_x = r.position.x
			floor_w = r.size.x
		elif r.position.y == floor_top and r.size.x > floor_w:
			floor_x = r.position.x
			floor_w = r.size.x
	var x := floor_x + floor_w * 0.5
	for rr in _ct_solid_rects(m):
		var r: Rect2 = rr
		if r.end.y >= floor_top - 1.0 and r.position.x - 40.0 < x and x < r.end.x + 40.0:
			x = r.end.x + 60.0
	return x


# Platform graph: two platforms connect when the player can jump or
# jetpack between them (up to 320 px up, 340 px across) or drop down
# (up to 420 px). BFS from spawn#0's platform must reach every spawn
# and pickup platform.
func _ct_map_reachable(m: Dictionary) -> bool:
	var plats: Array = m["platforms"]
	var n := plats.size()
	var adj: Array = []
	for i in n:
		adj.append([])
	for i in n:
		var a: Rect2 = plats[i]
		for j in n:
			if i == j:
				continue
			var b: Rect2 = plats[j]
			var hgap := 0.0
			if a.end.x < b.position.x:
				hgap = b.position.x - a.end.x
			elif b.end.x < a.position.x:
				hgap = a.position.x - b.end.x
			var vgap := b.position.y - a.position.y
			if hgap <= 340.0 and vgap >= -320.0 and vgap <= 420.0:
				(adj[i] as Array).append(j)
	var spawns: Array = m["spawns"]
	var start := _ct_platform_below(plats, spawns[0])
	if start < 0:
		return false
	var seen := {start: true}
	var stack: Array = [start]
	while not stack.is_empty():
		var cur: int = stack.pop_back()
		for nb in adj[cur]:
			if not seen.has(nb):
				seen[nb] = true
				stack.append(nb)
	for sp in spawns:
		if not seen.has(_ct_platform_below(plats, sp)):
			return false
	for pp in m["pickups"]:
		if not seen.has(_ct_platform_below(plats, pp)):
			return false
	return true


# First pass-through decor rect on the loaded map (bush / tree / palm /
# bridge / arch — kinds with no collision). Empty when the map has none.
func _ct_nonsolid_rect() -> Rect2:
	var m: Dictionary = g.MAPS[g.map_id]
	var decor: Array = m["decor"]
	for d in decor:
		if not (String(d[0]) in g.SOLID_DECOR_KINDS):
			var tex: Texture2D = GameAssets.DECOR_TEX[d[0]]
			var w := float(tex.get_width())
			var h := float(tex.get_height())
			return Rect2(float(d[1]) - w * 0.5, float(d[2]) - h, w, h)
	return Rect2()


# Platform whose top is just below a point (within 60 px), i.e. the
# platform the point stands on. -1 when there is none.
func _ct_platform_below(plats: Array, point: Vector2) -> int:
	var best := -1
	var best_top := -1.0
	for i in plats.size():
		var r: Rect2 = plats[i]
		if point.x >= r.position.x - 4.0 and point.x <= r.end.x + 4.0 and r.position.y >= point.y - 60.0 and r.position.y <= point.y + 60.0:
			if r.position.y > best_top:
				best_top = r.position.y
				best = i
	return best


# Direct space raycast, same mask as the bullet's swept raycast
# (mask 3: world + players), excluding the local player.
func _ct_ray(from: Vector2, to: Vector2) -> Dictionary:
	var space = g.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, to, 3)
	var lp = g._get_local_player()
	if lp != null:
		query.exclude = [lp.get_rid()]
	return space.intersect_ray(query)


func _ct_s_noop() -> void:
	pass


func _ct_s_throw_grenade() -> void:
	var tall := _ct_tall_solid()
	if tall == Rect2():
		return
	var lp = g._get_local_player()
	# QA-071b: throw from 60 px, not 150 px — at 150 px the grenade's
	# arc (init vel (575, -490)) cleared the 108-tall column by 5 px
	# once the throw origin rose 10 px with the bigger player; the
	# 60 px throw tests the same property (grenade bounces off a tall
	# solid) with 30+ px of margin on every map.
	lp.position = Vector2(tall.position.x - 60.0, tall.end.y - 34.0)
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	lp.facing = 1
	_ct_grenade = null
	lp.throw_grenade()
	if not g.grenades_node.get_children().is_empty():
		_ct_grenade = g.grenades_node.get_children()[0]


func _ct_s_walk_into_bush() -> void:
	var bush := _ct_nonsolid_rect()
	if bush == Rect2():
		return
	var lp = g._get_local_player()
	lp.position = Vector2(bush.position.x - 60.0, bush.end.y - 34.0)
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	_ct_walk_start_x = lp.position.x
	g._on_touch_press(930, g.move_stick.get_global_rect().get_center() + Vector2(60, 0))


func _ct_s_walk_into_solid() -> void:
	var cover := _ct_floor_cover()
	if cover == Rect2():
		return
	var lp = g._get_local_player()
	# Approach from the right (walk left) when the usual left
	# approach would cross a bounce pad and launch over the cover.
	var right_approach: bool = not _ct_walk_path_has_pad(cover.position.x - 60.0, cover.position.x - 20.0)
	if right_approach:
		_ct_walk_dir = 1
		lp.position = Vector2(cover.position.x - 60.0, cover.end.y - 34.0)
	else:
		_ct_walk_dir = -1
		lp.position = Vector2(cover.end.x + 60.0, cover.end.y - 34.0)
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	_ct_walk_start_x = lp.position.x
	g._on_touch_press(930, g.move_stick.get_global_rect().get_center() + Vector2(60 * _ct_walk_dir, 0))


# Solid decor rectangles for a map — the same rectangles _build_arena
# turns into collision shapes: the texture rect shrunk by the
# per-kind DECOR_INSETS (GAP-14), centred on the decor entry.
# (The test used to expect the full-texture face; the inset face is
# the real collision, 6-10 px inside the sprite's transparent edge.)
func _ct_solid_rects(m: Dictionary) -> Array:
	var out: Array = []
	var decor: Array = m["decor"]
	for d in decor:
		if String(d[0]) in g.SOLID_DECOR_KINDS:
			var tex: Texture2D = GameAssets.DECOR_TEX[d[0]]
			var w := float(tex.get_width())
			var h := float(tex.get_height())
			var inset = float(GameAssets.DECOR_INSETS.get(String(d[0]), 6))
			var w2 := maxf(8.0, w - inset * 2.0)
			var h2 := maxf(8.0, h - inset)
			out.append(Rect2(float(d[1]) - w2 * 0.5, float(d[2]) - h + inset, w2, h2))
	return out


# The tallest solid decor on the loaded map (column / watchtower /
# statue) — the grenade test throws at it because a tall face cannot
# be arced over.
func _ct_tall_solid() -> Rect2:
	var best := Rect2()
	for rr in _ct_solid_rects(g.MAPS[g.map_id]):
		var r: Rect2 = rr
		if r.size.y > best.size.y:
			best = r
	return best


func _ct_walk_path_has_pad(from_x: float, to_x: float) -> bool:
	for entry in g._bounce_pads:
		var r: Rect2 = entry["rect"]
		if r.position.x - 20.0 < maxf(from_x, to_x) and r.end.x + 20.0 > minf(from_x, to_x):
			return true
	return false


func _scaletest_build_steps() -> void:
	_scale_steps = []
	var resolutions: Array = [Vector2(1280, 720), Vector2(2400, 1080), Vector2(1920, 1080), Vector2(800, 480), Vector2(2340, 1080)]
	for res in resolutions:
		var tag := "%dx%d" % [int(res.x), int(res.y)]
		_scale_steps.append({"name": tag + "-RESIZE", "wait": 0.8, "setup": _st_s_resize.bind(res), "check": _st_c_resize.bind(res)})
		_scale_steps.append({"name": tag + "-DIAG", "wait": 0.3, "setup": _st_s_diag, "check": _st_c_diag})
		_scale_steps.append({"name": tag + "-MOVE-CENTRE", "wait": 0.3, "setup": _st_s_press_move_centre, "check": _st_c_move_centre})
		_scale_steps.append({"name": tag + "-MOVE-UP", "wait": 0.3, "setup": _st_s_drag_move.bind(Vector2(0, -60)), "check": _st_c_move_up})
		_scale_steps.append({"name": tag + "-MOVE-DOWN", "wait": 0.3, "setup": _st_s_drag_move.bind(Vector2(0, 60)), "check": _st_c_move_down})
		_scale_steps.append({"name": tag + "-MOVE-LEFT", "wait": 0.3, "setup": _st_s_drag_move.bind(Vector2(-60, 0)), "check": _st_c_move_left})
		_scale_steps.append({"name": tag + "-MOVE-RIGHT", "wait": 0.3, "setup": _st_s_drag_move.bind(Vector2(60, 0)), "check": _st_c_move_right})
		_scale_steps.append({"name": tag + "-MOVE-DIAG", "wait": 0.3, "setup": _st_s_drag_move.bind(Vector2(42, -42)), "check": _st_c_move_diag})
		_scale_steps.append({"name": tag + "-MOVE-RELEASE", "wait": 0.3, "setup": _st_s_release_move, "check": _st_c_move_released})
		_scale_steps.append({"name": tag + "-AIM-CENTRE", "wait": 0.3, "setup": _st_s_press_aim_centre, "check": _st_c_aim_centre})
		_scale_steps.append({"name": tag + "-AIM-UP", "wait": 0.3, "setup": _st_s_drag_aim.bind(Vector2(0, -60)), "check": _st_c_aim_up})
		_scale_steps.append({"name": tag + "-AIM-RELEASE", "wait": 0.3, "setup": _st_s_release_aim, "check": _st_c_aim_released})
		_scale_steps.append({"name": tag + "-AIM-FIRE-CENTRE", "wait": 0.3, "setup": _st_s_press_fire_centre, "check": _st_c_fire_held})
		_scale_steps.append({"name": tag + "-AIM-FIRE-RELEASE", "wait": 0.3, "setup": _st_s_release_fire, "check": _st_c_fire_released})


func _st_c_aim_centre() -> Array:
	var v = g.touch_aim
	var ok: bool = v.length() < 0.05
	return [ok, "aim=%s" % v]


func _st_c_aim_released() -> Array:
	var ok: bool = g.touch_aim == Vector2.ZERO
	return [ok, "aim=%s" % g.touch_aim]


func _st_c_aim_up() -> Array:
	var v = g.touch_aim
	var ok: bool = v.y < -0.4 and absf(v.x) < 0.2
	return [ok, "aim=%s" % v]


func _st_c_diag() -> Array:
	return [true, "see DIAG line above"]


func _st_c_fire_held() -> Array:
	var ok: bool = g.touch_firing and g.aim_stick.is_active()
	return [ok, "firing=%s aim_active=%s" % [g.touch_firing, g.aim_stick.is_active()]]


func _st_c_fire_released() -> Array:
	var ok: bool = not g.touch_firing and g.touch_aim == Vector2.ZERO
	return [ok, "firing=%s aim=%s" % [g.touch_firing, g.touch_aim]]


func _st_c_move_centre() -> Array:
	var v = g.touch_move_vec
	var k: Vector2 = g.move_stick.get_knob_offset()
	var ok: bool = v.length() < 0.05 and k.length() < 3.0
	return [ok, "vec=%s knob=%s" % [v, k]]


func _st_c_move_diag() -> Array:
	var v = g.touch_move_vec
	var k: Vector2 = g.move_stick.get_knob_offset()
	var ok: bool = v.x > 0.25 and v.y < -0.25 and v.length() > 0.4 and v.length() < 1.05 and k.y < 0.0
	return [ok, "vec=%s knob=%s" % [v, k]]


func _st_c_move_down() -> Array:
	var v = g.touch_move_vec
	var k: Vector2 = g.move_stick.get_knob_offset()
	var ok: bool = v.y > 0.4 and absf(v.x) < 0.2 and k.y > 10.0
	return [ok, "vec=%s knob=%s" % [v, k]]


func _st_c_move_left() -> Array:
	var v = g.touch_move_vec
	var ok: bool = v.x < -0.4 and absf(v.y) < 0.2
	return [ok, "vec=%s" % v]


func _st_c_move_released() -> Array:
	var ok: bool = g.touch_move_vec == Vector2.ZERO
	return [ok, "vec=%s" % g.touch_move_vec]


func _st_c_move_right() -> Array:
	var v = g.touch_move_vec
	var ok: bool = v.x > 0.4 and absf(v.y) < 0.2
	return [ok, "vec=%s" % v]


func _st_c_move_up() -> Array:
	var v = g.touch_move_vec
	var k: Vector2 = g.move_stick.get_knob_offset()
	var ok: bool = v.y < -0.4 and absf(v.x) < 0.2 and k.y < -10.0
	return [ok, "vec=%s knob=%s" % [v, k]]


func _st_c_resize(res: Vector2) -> Array:
	var ok: bool = Vector2(g.get_window().size) == res
	return [ok, "win=%s" % g.get_window().size]


func _st_drag(idx: int, screen_pos: Vector2) -> void:
	var e = InputEventScreenDrag.new()
	e.index = idx
	e.position = screen_pos
	g._unhandled_input(e)


func _st_press(idx: int, screen_pos: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = screen_pos
	e.pressed = true
	g._unhandled_input(e)


func _st_release(idx: int) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = Vector2.ZERO
	e.pressed = false
	g._unhandled_input(e)


func _st_s_diag() -> void:
	var ct = g.get_viewport().get_canvas_transform()
	var cam = g.get_viewport().get_camera_2d()
	var cam_center = cam.get_screen_center_position() if cam != null else Vector2.ZERO
	var mrect: Rect2 = g.move_stick.get_global_rect()
	var mgt: Transform2D = g.move_stick.get_global_transform_with_canvas()
	var scenter = _st_screen_center(g.move_stick)
	var converted = g._to_canvas_pos(scenter)
	var buggy = g.get_viewport().get_canvas_transform().affine_inverse() * scenter
	print("SCALETEST DIAG win=%s vis=%s canvas_t origin=%s x=%s y=%s hud_final=%s cam_center=%s move_rect=%s move_gt origin=%s x=%s y=%s screen_centre=%s converted=%s buggy_viewport_canvas=%s rect_centre=%s" % [g.get_window().size, g.get_viewport().get_visible_rect().size, ct.origin, ct.x, ct.y, g.hud.get_final_transform(), cam_center, mrect, mgt.origin, mgt.x, mgt.y, scenter, converted, buggy, mrect.get_center()])


func _st_s_drag_aim(offset_px: Vector2) -> void:
	_st_drag(921, _st_screen_center(g.aim_stick) + offset_px)


func _st_s_drag_move(offset_px: Vector2) -> void:
	_st_drag(920, _st_screen_center(g.move_stick) + offset_px)


func _st_s_press_aim_centre() -> void:
	_st_press(921, _st_screen_center(g.aim_stick))


func _st_s_press_fire_centre() -> void:
	# v3.2: no FIRE button — the scale check now presses the AIM
	# stick's screen centre and drags it 60 px right: the deflection
	# must register as aiming AND firing at every resolution.
	_st_press(922, _st_screen_center(g.aim_stick))
	_st_drag(922, _st_screen_center(g.aim_stick) + Vector2(60, 0))


func _st_s_press_move_centre() -> void:
	_st_press(920, _st_screen_center(g.move_stick))


func _st_s_release_aim() -> void:
	_st_release(921)


func _st_s_release_fire() -> void:
	_st_release(922)


func _st_s_release_move() -> void:
	_st_release(920)


func _st_s_resize(res: Vector2) -> void:
	g.get_window().size = res


func _st_screen_center(ctrl: Control) -> Vector2:
	return ctrl.get_global_transform_with_canvas() * (ctrl.size * 0.5)


func _update_collisiontest(delta: float) -> void:
	if _ct_done:
		return
	var lp = g._get_local_player()
	if lp == null:
		_ct_timer += delta
		if _ct_timer > 5.0:
			_ct_done = true
			print("COLLISIONTEST DONE: 0/0 passed — no local player spawned")
			g.get_tree().quit()
		return
	if _ct_steps.is_empty():
		_ct_build_steps()
		_ct_step = 0
		_ct_in_step = false
		_ct_timer = 0.0
	if _ct_step >= _ct_steps.size():
		_ct_done = true
		print("COLLISIONTEST DONE: %d/%d passed (map: %s)" % [_ct_passed, _ct_passed + _ct_failed, String(g.MAPS[g.map_id]["name"])])
		g.get_tree().quit()
		return
	var step: Dictionary = _ct_steps[_ct_step]
	if not _ct_in_step:
		(step["setup"] as Callable).call()
		_ct_in_step = true
		_ct_timer = float(step["wait"])
	_ct_timer -= delta
	if _ct_timer <= 0.0:
		var result: Array = (step["check"] as Callable).call()
		var ok: bool = bool(result[0])
		if ok:
			_ct_passed += 1
		else:
			_ct_failed += 1
		print("COLLISIONTEST %s: %s — %s" % [String(step["name"]), "PASS" if ok else "FAIL", String(result[1])])
		_ct_step += 1
		_ct_in_step = false
		_ct_timer = 0.0


func _update_scaletest(delta: float) -> void:
	if _scale_done:
		return
	var lp = g._get_local_player()
	if lp == null:
		_scale_timer += delta
		if _scale_timer > 5.0:
			_scale_done = true
			print("SCALETEST DONE: 0/0 passed — no local player spawned")
			g.get_tree().quit()
		return
	if _scale_steps.is_empty():
		_scaletest_build_steps()
		_scale_step = 0
		_scale_in_step = false
		_scale_timer = 0.0
	if _scale_step >= _scale_steps.size():
		_scale_done = true
		g.get_window().size = Vector2(1280, 720)
		print("SCALETEST DONE: %d/%d passed" % [_scale_passed, _scale_passed + _scale_failed])
		g.get_tree().quit()
		return
	var step: Dictionary = _scale_steps[_scale_step]
	if not _scale_in_step:
		(step["setup"] as Callable).call()
		_scale_in_step = true
		_scale_timer = float(step["wait"])
	_scale_timer -= delta
	if _scale_timer <= 0.0:
		var result: Array = (step["check"] as Callable).call()
		var ok: bool = bool(result[0])
		if ok:
			_scale_passed += 1
		else:
			_scale_failed += 1
		print("SCALETEST %s: %s — %s" % [String(step["name"]), "PASS" if ok else "FAIL", String(result[1])])
		_scale_step += 1
		_scale_in_step = false
		_scale_timer = 0.0


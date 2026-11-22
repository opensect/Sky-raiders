class_name SkyfallPowerups
extends RefCounted


# QA-139 (v3.15): extracted from game.gd. This module owns no
# state of its own: every field it reads or writes lives on the
# game node and is reached through `g` (dependency injection).
# game.gd keeps a thin delegating wrapper for each function the
# rest of the game calls, so no call site had to change.


var g # the game node (game.gd)


func _init(game) -> void:
	g = game


# QA-143 (v4.0) ITEM 9 — Thunder stationary rule. A player who has
# not moved (position change <= 4 px) for 5 s is "still". The
# tracker lives on the game node (g._sf_still_pos / _sf_still_since,
# keyed by peer id, times in g._sf_match_time seconds) and is
# updated every frame on the host from _update_skyfall_powerups —
# targeting is host-authoritative, so only the host needs it. The
# still clock resets the moment the player moves, and the test
# helpers below let a test seed it (see FT-SF-THUNDER-STILL).
const SF_STILL_SECONDS := 5.0
const SF_STILL_MOVE_EPS := 4.0
const SF_STILL_LEVEL := 5 # the stationary rule applies ONLY here


func _sf_update_still_tracking() -> void:
	var now := float(g._sf_match_time)
	var seen := {}
	for child in g.players_node.get_children():
		if not child.alive:
			continue
		var pid := int(child.peer_id)
		seen[pid] = true
		var pos: Vector2 = child.position
		if not g._sf_still_pos.has(pid):
			g._sf_still_pos[pid] = pos
			g._sf_still_since[pid] = now
		else:
			var last: Vector2 = g._sf_still_pos[pid]
			if pos.distance_to(last) > SF_STILL_MOVE_EPS:
				g._sf_still_pos[pid] = pos
				g._sf_still_since[pid] = now
	for pid in g._sf_still_pos.keys():
		if not seen.has(pid):
			g._sf_still_pos.erase(pid)
			g._sf_still_since.erase(pid)


func _sf_still_seconds(target: Node2D) -> float:
	if target == null or not is_instance_valid(target):
		return 0.0
	var pid := int(target.peer_id)
	if not g._sf_still_since.has(pid):
		return 0.0
	return float(g._sf_match_time) - float(g._sf_still_since[pid])


func _sf_is_still_on_level5(target: Node2D) -> bool:
	# ITEM 9, level-5-only scope: the target must be still for
	# 5+ s AND standing on Skyfall level 5 (Mechanical Ascent).
	# Still on any other level adds nothing.
	if target == null or not is_instance_valid(target) or not target.alive:
		return false
	if g.skyfall_helpers._sf_level_of(target.position.y) != SF_STILL_LEVEL:
		return false
	return _sf_still_seconds(target) >= SF_STILL_SECONDS


func _sf_seed_still(target: Node2D, seconds: float) -> void:
	# Test helper: pretend the target has already been still for
	# `seconds` (pos seeded too, so the per-frame tracker sees no
	# move and does not overwrite it). Only used by tests.
	if target == null or not is_instance_valid(target):
		return
	var pid := int(target.peer_id)
	g._sf_still_pos[pid] = target.position
	g._sf_still_since[pid] = float(g._sf_match_time) - seconds


func _sf_reset_still(peer_id: int) -> void:
	# Restart one player's still clock at "now" (the L5 trap calls
	# this after a strike, so a player who keeps standing still is
	# struck again only after another full 5 s).
	g._sf_still_since[peer_id] = float(g._sf_match_time)
	var found: Node2D = null
	for child in g.players_node.get_children():
		if int(child.peer_id) == peer_id:
			found = child
			break
	if found != null:
		g._sf_still_pos[peer_id] = found.position


# _sf_platform_under returns the platform index under a player's
# feet, or -1 when they are not standing on any static platform
# (airborne, on an elevator, on a mover). It is kept for the Wind
# Blast throw-side fallback and FT-SF-WIND-THROW (both need a raw
# index into MAPS["platforms"]); the targeting checks below do NOT
# use it — see _sf_surface_under.
#
# QA-143 (v4.0): _sf_surface_under is the platform identity Wind
# Blast / Thunder Strike targeting compares. The old index compare
# had TWO defects, both reported as "No enemy on your platform"
# while the enemy stood on the same platform:
# (1) SEAM: the L2 boundary row (y 8764) is FIVE adjacent rects
# (indices 19-23) tiling one continuous floor. The first-match rule
# gave two players 8 px apart across a seam DIFFERENT indices
# (x 348 -> piece 19, x 356 -> piece 20). A "surface" merges
# adjacent same-top rects into one run, so the whole floor is one
# platform. (2) MOVERS: a player riding an elevator / the rotator /
# the summit elevator is on no STATIC platform, so the old check
# returned -1 and targeting could never fire on a mover. Each live
# mover instance is its own surface. Two players share a surface
# iff they stand on the same run / the same mover. Returns "" when
# the player is standing on nothing (airborne).
func _sf_surface_under(pos: Vector2) -> String:
	return _sf_surface_at(pos)[0]


func _sf_surface_rect_under(pos: Vector2) -> Rect2:
	return _sf_surface_at(pos)[1]


func _sf_surface_at(pos: Vector2) -> Array:
	var feet := pos + Vector2(0, 31)
	var runs := _sf_merged_surface_rects()
	for i in runs.size():
		var r: Rect2 = runs[i]
		if feet.x >= r.position.x - 4.0 and feet.x <= r.end.x + 4.0 and absf(feet.y - r.position.y) <= 10.0:
			return ["s%d" % i, r]
	# Live movers: the body origin is the box centre (48 tall), so
	# the top the player stands on is body.position.y - 24.
	for ei in g._sf_elevators.size():
		var e: Dictionary = g._sf_elevators[ei]
		var body := e.get("body") as Node2D
		if body == null:
			continue
		var cfg: Dictionary = e.get("cfg", {})
		var w := float(cfg.get("w", 0.0))
		var mr := Rect2(body.position.x - w * 0.5, body.position.y - 24.0, w, 48.0)
		if feet.x >= mr.position.x - 4.0 and feet.x <= mr.end.x + 4.0 and absf(feet.y - mr.position.y) <= 10.0:
			return ["e%d" % ei, mr]
	if not g._sf_rotator.is_empty():
		var rbody := g._sf_rotator.get("body") as Node2D
		var rcfg: Dictionary = g._sf_rotator.get("cfg", {})
		if rbody != null:
			var rw := float(rcfg.get("w", 400.0))
			var rr := Rect2(rbody.position.x - rw * 0.5, rbody.position.y - 24.0, rw, 48.0)
			if feet.x >= rr.position.x - 4.0 and feet.x <= rr.end.x + 4.0 and absf(feet.y - rr.position.y) <= 10.0:
				return ["r", rr]
	if not g._sf_summit_elevator.is_empty():
		var sbody := g._sf_summit_elevator.get("body") as Node2D
		var scfg: Dictionary = g._sf_summit_elevator.get("cfg", {})
		if sbody != null:
			var sw := float(scfg.get("w", 300.0))
			var sr := Rect2(sbody.position.x - sw * 0.5, sbody.position.y - 24.0, sw, 48.0)
			if feet.x >= sr.position.x - 4.0 and feet.x <= sr.end.x + 4.0 and absf(feet.y - sr.position.y) <= 10.0:
				return ["se", sr]
	return ["", Rect2()]


func _sf_merged_surface_rects() -> Array:
	# Adjacent rects at the same top y that touch or overlap (within
	# the 8 px bridge = the ±4 px edge margin on both sides) form ONE
	# surface. The L2 boundary row merges into a single 200–3400 run;
	# same-y platforms with a real gap between them stay separate.
	var plats: Array = g.MAPS[g.map_id].get("platforms", [])
	var by_y := {}
	for r in plats:
		var rr: Rect2 = r
		if not by_y.has(rr.position.y):
			by_y[rr.position.y] = []
		(by_y[rr.position.y] as Array).append(rr)
	var out: Array = []
	for y in by_y:
		var row: Array = by_y[y]
		row.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.x < b.position.x)
		var cur: Rect2 = row[0]
		for k in range(1, row.size()):
			var nxt: Rect2 = row[k]
			if nxt.position.x <= cur.end.x + 8.0:
				cur = Rect2(cur.position.x, cur.position.y, maxf(cur.end.x, nxt.end.x) - cur.position.x, maxf(cur.size.y, nxt.size.y))
			else:
				out.append(cur)
				cur = nxt
		out.append(cur)
	return out


func _sf_platform_under(pos: Vector2) -> int:
	var feet := pos + Vector2(0, 31)
	var plats: Array = g.MAPS[g.map_id].get("platforms", [])
	for i in plats.size():
		var r: Rect2 = plats[i]
		if feet.x >= r.position.x - 4.0 and feet.x <= r.end.x + 4.0 and absf(feet.y - r.position.y) <= 10.0:
			return i
	return -1


# QA-143 (v4.0) ITEM 9: `kind` selects the rule set. Rule (A)
# SAME-PLATFORM (same merged surface + within 60 px height) applies
# to Wind (11) and Thunder (12) on EVERY level. Rule (B)
# STATIONARY (enemy still 5+ s on level 5) applies ONLY to Thunder
# (kind 12) and ONLY on level 5 — it is an ADDITIONAL way to hit,
# not a replacement: a still L5 enemy is a valid target even when
# the platform / height check fails, and a still enemy on any other
# level is not hit by this rule at all.
func _sf_find_powerup_target(activator: Node2D, kind: int = 0) -> Node2D:
	if g.map_id != GameData.SKYFALL_MAP_ID:
		return null
	var my_surf := _sf_surface_under(activator.position)
	var allow_still := kind == 12
	if my_surf == "" and not allow_still:
		return null
	var best: Node2D = null
	var best_d := 1e9
	for other in g.players_node.get_children():
		if other == activator or not other.alive:
			continue
		if int(other.team) == int(activator.team):
			continue
		var same_platform: bool = my_surf != "" and _sf_surface_under(other.position) == my_surf and absf(other.position.y - activator.position.y) <= g.SF_POWERUP_HEIGHT_TOL
		var still_hit: bool = allow_still and _sf_is_still_on_level5(other)
		if not same_platform and not still_hit:
			continue
		var d: float = other.position.distance_to(activator.position)
		if d < best_d:
			best_d = d
			best = other
	return best


func _sf_validate_powerup_target(activator: Node2D, target: Node2D, kind: int = 0) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not target.alive:
		return false
	if int(target.team) == int(activator.team):
		return false
	# ITEM 9 rule (B): still 5+ s on level 5 is a direct hit for
	# Thunder, with no platform / height requirement.
	if kind == 12 and _sf_is_still_on_level5(target):
		return true
	# Rule (A): same platform + within 60 px height, any level.
	var my_surf := _sf_surface_under(activator.position)
	if my_surf == "":
		return false
	if _sf_surface_under(target.position) != my_surf:
		return false
	if absf(target.position.y - activator.position.y) > g.SF_POWERUP_HEIGHT_TOL:
		return false
	return true
func _update_skyfall_powerups(delta: float) -> void:
	if g.map_id != GameData.SKYFALL_MAP_ID:
		return
	if not g.multiplayer.is_server() or g.match_over:
		return
	# QA-143 ITEM 9: still-tracking runs on the host every frame
	# (targeting + the L5 trap both read it); clients never use it.
	_sf_update_still_tracking()
	var spots: Array = g.MAPS[g.map_id].get("skyfall_pickups", [])
	if spots.is_empty():
		return
	if not g._sf_initial_powerups_done:
		g._sf_initial_powerups_done = true
		for si in g.SF_POWERUP_INITIAL_SPOTS:
			_spawn_skyfall_powerup(si)
		for i in spots.size():
			g._sf_pickup_timers[i] = g.SF_POWERUP_COOLDOWN
		return
	var active := 0
	for child in g.pickups_node.get_children():
		if int(child.get("kind")) >= 8:
			active += 1
	if active >= g.SF_POWERUP_MAX_ACTIVE:
		return
	for i in spots.size():
		var t = float(g._sf_pickup_timers.get(i, 0.0)) - delta
		g._sf_pickup_timers[i] = t
		if t <= 0.0:
			g._sf_pickup_timers[i] = g.SF_POWERUP_COOLDOWN
			_spawn_skyfall_powerup(i)
			return # one spawn per frame at most


func _spawn_skyfall_powerup(spot_idx: int) -> void:
	var spots: Array = g.MAPS[g.map_id].get("skyfall_pickups", [])
	if spot_idx < 0 or spot_idx >= spots.size():
		return
	var spot: Array = spots[spot_idx]
	var pos := Vector2(float(spot[0]), float(spot[1]))
	var kind := int(spot[2])
	var pname := "sfpowerup_" + str(Time.get_ticks_msec()) + "_" + str(spot_idx)
	# Spot index 100+ keeps power-ups out of the standard weapon
	# spot timers (on_pickup_gone routes 100+ to the power-up timer).
	g._test_powerup_spawns += 1
	g.rpc("spawn_pickup_remote", pos, pname, kind, 100 + spot_idx)


func _on_slot_pressed(idx: int) -> void:
	# QA-119 (v3.11): tap a HUD slot button to activate the stored
	# power-up. activate_slot() enforces the rules (timed needs no
	# active boost and no flag carried); a refused tap just does
	# nothing. "tap" sound only on a real activation.
	# QA-132: a refused tap now SAYS why in the feed (it used to
	# fail silently — the player could not tell a rule from a bug).
	var lp = g._get_local_player()
	if lp == null:
		return
	if bool(lp.call("activate_slot", idx)):
		g.audio.play("tap")
		return
	var stored: Array = lp.get("stored_boosts")
	if idx < 0 or idx >= stored.size():
		return
	if int(stored[idx]) in [8, 9, 10, 13]:
		if int(lp.get("active_boost_kind")) != 0:
			g._ctf_feed("Boost already active", Color(1.0, 0.8, 0.2))
		elif int(lp.get("carrying_flag")) != 0:
			g._ctf_feed("Cannot use while carrying the flag", Color(1.0, 0.8, 0.2))


func _update_invis_warning(lp) -> void:
	# QA-121 (v3.11): while any living ENEMY is invisible, a red
	# chip sits at the top of the top-left message area; it clears
	# the moment the invisibility ends. Teammates are not warned
	# (they see the faint outline). Runs every frame from
	# _update_hud; the chip is NOT a feed entry (no 5 s expiry, no
	# place in the 4-entry cap).
	if g._kill_feed_list == null:
		return
	var warn := false
	var my_team := int(lp.team)
	for child in g.players_node.get_children():
		if int(child.peer_id) == int(lp.peer_id) or not child.alive:
			continue
		var enemy := my_team < 0 or int(child.team) != my_team
		if enemy and float(child.get("invisibility_timer")) > 0.0:
			warn = true
			break
	if not warn:
		if g._invis_warning_chip != null:
			g._invis_warning_chip.visible = false
		return
	if g._invis_warning_chip == null:
		var lbl := Label.new()
		lbl.text = "Enemy is invisible!"
		lbl.add_theme_font_override("font", g.FONT_BODY_MEDIUM)
		lbl.add_theme_font_size_override("font_size", 18)
		lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
		g._outline_label(lbl)
		var chip := PanelContainer.new()
		# QA-145 (Worker F): the chip wears the UI-frames red bar
		# now (same content margins as before; red label text and
		# all warning logic unchanged). bar_red_med, not strip_red:
		# strip_red.png is actually the BLUE strip (phase 1
		# misread the sheet), and bar_red_med was the PLAN's own
		# fallback for this chip.
		var chip_bg: StyleBoxTexture = g.hud_builder._ui_frame_stylebox(g.hud_builder.TEX_UI_BAR_RED_MED, 12, 10, 10, 4, 4)
		chip.add_theme_stylebox_override("panel", chip_bg)
		chip.add_child(lbl)
		g._invis_warning_chip = chip
		g._kill_feed_list.add_child(chip)
	g._kill_feed_list.move_child(g._invis_warning_chip, 0)
	g._invis_warning_chip.visible = true


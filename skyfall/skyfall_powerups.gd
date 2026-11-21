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


# _sf_platform_under returns the platform index under a player's
# feet, or -1 when they are not standing on any static platform
# (airborne, on an elevator, on a mover). _sf_find_powerup_target
# returns the nearest valid living enemy, or null. The host
# re-validates the named target with _sf_validate_powerup_target
# before executing (positions may have moved since the tap).
func _sf_platform_under(pos: Vector2) -> int:
	var feet := pos + Vector2(0, 31)
	var plats: Array = g.MAPS[g.map_id].get("platforms", [])
	for i in plats.size():
		var r: Rect2 = plats[i]
		if feet.x >= r.position.x - 4.0 and feet.x <= r.end.x + 4.0 and absf(feet.y - r.position.y) <= 10.0:
			return i
	return -1


func _sf_find_powerup_target(activator: Node2D) -> Node2D:
	if g.map_id != GameData.SKYFALL_MAP_ID:
		return null
	var my_plat := _sf_platform_under(activator.position)
	if my_plat < 0:
		return null
	var best: Node2D = null
	var best_d := 1e9
	for other in g.players_node.get_children():
		if other == activator or not other.alive:
			continue
		if int(other.team) == int(activator.team):
			continue
		if _sf_platform_under(other.position) != my_plat:
			continue
		if absf(other.position.y - activator.position.y) > g.SF_POWERUP_HEIGHT_TOL:
			continue
		var d: float = other.position.distance_to(activator.position)
		if d < best_d:
			best_d = d
			best = other
	return best


func _sf_validate_powerup_target(activator: Node2D, target: Node2D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not target.alive:
		return false
	if int(target.team) == int(activator.team):
		return false
	var my_plat := _sf_platform_under(activator.position)
	if my_plat < 0:
		return false
	if _sf_platform_under(target.position) != my_plat:
		return false
	if absf(target.position.y - activator.position.y) > g.SF_POWERUP_HEIGHT_TOL:
		return false
	return true
func _update_skyfall_powerups(delta: float) -> void:
	if g.map_id != GameData.SKYFALL_MAP_ID:
		return
	if not g.multiplayer.is_server() or g.match_over:
		return
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
		if int(child.get("kind")) >= 7:
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
		var chip_bg := StyleBoxFlat.new()
		chip_bg.bg_color = Color(0.35, 0.05, 0.08, 0.88)
		chip_bg.set_corner_radius_all(8)
		chip_bg.content_margin_left = 10
		chip_bg.content_margin_right = 10
		chip_bg.content_margin_top = 4
		chip_bg.content_margin_bottom = 4
		chip.add_theme_stylebox_override("panel", chip_bg)
		chip.add_child(lbl)
		g._invis_warning_chip = chip
		g._kill_feed_list.add_child(chip)
	g._kill_feed_list.move_child(g._invis_warning_chip, 0)
	g._invis_warning_chip.visible = true


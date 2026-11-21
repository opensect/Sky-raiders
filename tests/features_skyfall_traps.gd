class_name FeaturesSkyfallTraps
extends RefCounted


# QA-140 (v3.15): extracted from game.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `g` (dependency injection).


var g # the owner (game.gd)


func _init(owner) -> void:
	g = owner


func _ft_sf_s_shield_storm() -> void:
	# OPPOSITE: shield active while the Summit Storm fires — the
	# storm must not damage the player or break the shield.
	var lp = g.fire_test._ft_lp()
	lp.get("stored_boosts").clear()
	lp.set("active_boost_kind", 0)
	lp.set("shield_timer", 0.0)
	lp.set("speed_timer", 0.0)
	lp.set("jetpack_boost_timer", 0.0)
	lp.set("invisibility_timer", 0.0)
	lp.set("carrying_flag", 0)
	g.features_skyfall_test._ft_sf_hp0 = float(lp.health)
	lp.apply_powerup(8) # shield
	g._sf_storm_timer = 0.01 # fire the storm now


func _ft_sf_c_shield_storm() -> Array:
	var lp = g.fire_test._ft_lp()
	var stored: Array = lp.get("stored_boosts")
	var ab := int(lp.get("active_boost_kind"))
	var shield_held := ab == 8 or 8 in stored
	var ok = bool(g._sf_storm_active) and shield_held and float(lp.health) >= g.features_skyfall_test._ft_sf_hp0
	return [ok, "storm=%s shield held=%s health=%.0f (was %.0f)" % [str(bool(g._sf_storm_active)), str(shield_held), float(lp.health), g.features_skyfall_test._ft_sf_hp0]]


func _ft_sf_s_comeback() -> void:
	var lp = g.fire_test._ft_lp()
	lp.set("carrying_flag", 0)
	# QA-132 fix: RED already led 4-0 from RELAY-BANK, so the trail
	# never CHANGED in this setup and the 5 s bonus timer never
	# re-armed — the earlier bonus (spawned mid-test) was freed by
	# the PATH setups' pickup cleanup, and the 25 s cycle did not
	# fire again inside the 6 s wait. Force the trail-change branch
	# and clear any stale bonus pickup so a fresh one spawns at 5 s.
	for child in g.pickups_node.get_children():
		if int(child.get("spot_index")) == 201:
			child.free()
	g._sf_comeback_team = -1
	g._ctf_scores = {0: 4, 1: 0} # RED leads by 4 — BLUE trails


func _ft_sf_c_comeback() -> Array:
	var bonus := false
	for child in g.pickups_node.get_children():
		if int(child.get("spot_index")) == 201: # BLUE's comeback bonus spot
			bonus = true
			break
	var ok = g._sf_comeback_team == 1 and g._sf_summit_timer > 0.0 and bool(g._sf_comeback_label.visible) and bonus
	return [ok, "trailing=%d (want 1=BLUE) elevator timer=%.1fs label=%s bonus pickup=%s comeback_pu_timer=%.1fs scores=%s" % [g._sf_comeback_team, g._sf_summit_timer, str(bool(g._sf_comeback_label.visible)), str(bonus), g._sf_comeback_pu_timer, str(g._ctf_scores)]]


func _ft_sf_s_event() -> void:
	g._sf_event_timer = 0.01 # fire a random event now


func _ft_sf_c_event() -> Array:
	var ok = g._sf_event_active != "" or g._sf_event_timer >= 45.0
	return [ok, "event=%s timer=%.1fs (an event fired at a random time)" % [g._sf_event_active, g._sf_event_timer]]


func _ft_sf_s_storm() -> void:
	g._sf_storm_timer = 0.01 # fire the storm now


func _ft_sf_c_storm() -> Array:
	var ok = bool(g._sf_storm_active)
	return [ok, "storm active=%s" % str(bool(g._sf_storm_active))]


func _ft_sf_s_combo_event_storm() -> void:
	# COINCIDENCE: a random event fires WHILE the storm is active.
	# If the storm is already running, refresh its duration — the
	# timer alone does nothing while it is active (and the storm's
	# end resets the timer to 90, which would swallow a fresh 0.01).
	g._sf_storm_timer = 0.01
	if g._sf_storm_active:
		g._sf_storm_time_left = 10.0
	g._sf_event_timer = 0.01


func _ft_sf_c_combo_event_storm() -> Array:
	var ok = bool(g._sf_storm_active) and (g._sf_event_active != "" or g._sf_event_timer >= 45.0) and g._ctf_flags.size() == 2
	return [ok, "storm=%s event=%s flags=%d (both systems live, no crash)" % [str(bool(g._sf_storm_active)), g._sf_event_active, g._ctf_flags.size()]]


func _ft_sf_s_combo_trap() -> void:
	# COINCIDENCE: falling onto a trap door — it must open under
	# the player after 1 s standing.
	var rect: Rect2 = (g.MAPS[g.map_id].get("platforms", []) as Array)[20]
	g.fire_test._ft_teleport(rect.get_center() + Vector2(0, -40))


func _ft_sf_c_combo_trap() -> Array:
	var lp = g.fire_test._ft_lp()
	var td: Dictionary = g._sf_trapdoors[0]
	var rect: Rect2 = td["rect"]
	var py: float = lp.position.y
	var ok: bool = str(td.get("state", "")) == "open" and py > rect.position.y + 50.0
	return [ok, "trapdoor=%s player y=%.0f (platform y=%.0f, want player below it)" % [str(td.get("state", "")), py, rect.position.y]]


func _ft_sf_s_hazard_lava() -> void:
	# QA-126: stand in the L5 lava pool while the jets are HOT —
	# health must drop by 10 per 1 s tick. Clear the shield first
	# (an earlier step may have left one up) and force the hot
	# phase (match clock 0.5 s into the 4 s cycle).
	var lp = g.fire_test._ft_lp()
	lp.get("stored_boosts").clear()
	lp.set("active_boost_kind", 0)
	lp.set("shield_timer", 0.0)
	lp.set("speed_timer", 0.0)
	lp.set("jetpack_boost_timer", 0.0)
	lp.set("invisibility_timer", 0.0)
	lp.set("health", 100.0) # full health, so the -10/tick is measurable
	g.features_skyfall_test._ft_sf_hp0 = float(lp.health)
	g._sf_match_time = 0.5
	g.fire_test._ft_teleport(Vector2(1100, 2460)) # on the lava pool (950,2420,300,84)


func _ft_sf_c_hazard_lava() -> Array:
	var lp = g.fire_test._ft_lp()
	var ok = float(lp.health) <= g.features_skyfall_test._ft_sf_hp0 - 10.0
	return [ok, "health=%.0f (was %.0f, want <= -10 from the lava ticks)" % [float(lp.health), g.features_skyfall_test._ft_sf_hp0]]


func _ft_sf_s_lightning() -> void:
	# QA-126: force the Summit Storm + a strike on the local player
	# (teleported to the summit, y < 3600). The 0.6 s telegraph
	# runs, then the bolt hits for 15 — unless the shield is up
	# (that case is covered by FT-SF-OPP-SHIELD-STORM).
	var lp = g.fire_test._ft_lp()
	lp.get("stored_boosts").clear()
	lp.set("active_boost_kind", 0)
	lp.set("shield_timer", 0.0)
	lp.set("speed_timer", 0.0)
	lp.set("jetpack_boost_timer", 0.0)
	lp.set("invisibility_timer", 0.0)
	lp.set("health", 100.0) # full health, so the -15 strike is measurable
	g.features_skyfall_test._ft_sf_hp0 = float(lp.health)
	# QA-132 fix: a leftover TestBot (peer 99, from the base
	# KILLFEED step) stands at the summit, so the strike picked a
	# RANDOM candidate (50/50) — free every other player NOW
	# (free() is immediate; queue_free would leave the bot alive
	# for the first strike schedule) so the local player is the
	# only strike target. Later steps spawn their own bots.
	for child in g.players_node.get_children():
		if child != lp:
			g._spawned.erase(int(child.peer_id))
			child.free()
	g.fire_test._ft_teleport(Vector2(1800, 1000)) # summit, inside the strike zone
	g._sf_storm_active = true
	g._sf_storm_time_left = 10.0
	# A strike may already be pending from the earlier forced storm
	# (its 3 s cadence is longer than this step's 2 s wait, and it
	# could be a visual-only strike on an empty platform) — clear
	# it so a fresh strike is scheduled on the local player at once.
	g._sf_clear_strike_marker()
	g._sf_strike_timer = 0.01


func _ft_sf_c_lightning() -> Array:
	var lp = g.fire_test._ft_lp()
	var ok = float(lp.health) <= g.features_skyfall_test._ft_sf_hp0 - 15.0
	# Tidy up: end the forced storm so later steps run in clear air.
	g._sf_storm_active = false
	g._sf_storm_time_left = 0.0
	g._sf_storm_timer = 90.0
	g._sf_clear_strike_marker()
	return [ok, "health=%.0f (was %.0f, want <= -15 from the strike)" % [float(lp.health), g.features_skyfall_test._ft_sf_hp0]]


# QA-135 (v3.13): new traps per level. Rocks (L1): force the
# spawn timer to 0 — a rock must exist after the wait.
func _ft_sf_s_trap_rocks() -> void:
	g.fire_test._ft_lp()
	g._sf_rock_timer = 0.0


func _ft_sf_c_trap_rocks() -> Array:
	var ok = g._sf_rocks.size() > 0
	return [ok, "falling rocks=%d (want >0 — L1 interval 2.5 s, max 4)" % g._sf_rocks.size()]


# Trapdoors (L2): the new trapdoor idx 19 must open after the
# player stands on it for 1.0 s.
func _ft_sf_s_trap_trapdoor_l2() -> void:
	var lp = g.fire_test._ft_lp()
	lp.set("health", 100.0)
	for td in g._sf_trapdoors:
		if int(td.get("idx", -1)) == 19:
			var r: Rect2 = td["rect"]
			lp.position = Vector2(r.get_center().x, r.position.y - 31.0)
			lp.velocity = Vector2.ZERO
			lp.sync_position = lp.position
			break


func _ft_sf_c_trap_trapdoor_l2() -> Array:
	var state := "missing"
	for td in g._sf_trapdoors:
		if int(td.get("idx", -1)) == 19:
			state = str(td.get("state", "?"))
			break
	var ok := state == "open"
	return [ok, "trapdoor idx 19 state=%s (want open after standing 1 s)" % state]


# Lava (L5): the new lava2 hazard (2150,2980) must deal 10 HP
# per tick while HOT. The match clock is reset to 0 so the zone
# is HOT for the whole wait (2 s on / 2 s off per 4 s cycle).
func _ft_sf_s_trap_lava2() -> void:
	var lp = g.fire_test._ft_lp()
	lp.set("health", 100.0)
	lp.set("shield_timer", 0.0)
	g._sf_match_time = 0.0
	# Teleport 40 px BELOW the hazard top (inside the lava, like
	# the old HAZARD-LAVA test) so the player box overlaps the
	# hazard rect — a standing player's box only touches its top
	# edge, which Rect2.intersects does not count.
	g.fire_test._ft_teleport(Vector2(2300.0, 3020.0)) # in the new lava2 pool (2150,2980,300,84)


func _ft_sf_c_trap_lava2() -> Array:
	var lp = g.fire_test._ft_lp()
	var hp := float(lp.get("health"))
	var ok := hp <= 90.0
	return [ok, "player health=%.0f (want <=90 after a 10 HP lava tick)" % hp]


# Storm lightning (L4): force the strike timer to 0 with the
# player in L4 — the bolt must land within 1.5 s (0.6 s
# telegraph + strike) for 15 HP.
func _ft_sf_s_trap_lightning_l4() -> void:
	# QA-136 (v3.13 build gate): the old setup stood the player on
	# the FIRST L4 platform in list order — platform #36, which is
	# a COLLAPSING platform (0.8 s shake, then the shape drops and
	# the player falls out of the strike's 200 px radius before the
	# 0.6 s telegraph resolves). Stand on the first STATIC L4
	# platform instead (not collapsing, not a trapdoor), clear any
	# in-flight strike marker, and move every other living player
	# out of L4 so the random target pick can only choose the local
	# player — the strike must be deterministic in a test.
	var lp = g.fire_test._ft_lp()
	lp.set("health", 100.0)
	lp.set("shield_timer", 0.0)
	g._sf_clear_strike_l4_marker()
	var plats: Array = g.MAPS[g.map_id].get("platforms", [])
	var collapse: Array = g.MAPS[g.map_id].get("collapsing", [])
	var traps: Array = g.MAPS[g.map_id].get("trapdoors", [])
	for i in plats.size():
		var r: Rect2 = plats[i]
		if r.position.y >= 3600.0 and r.position.y < 5400.0 and not collapse.has(i) and not traps.has(i):
			lp.position = Vector2(r.get_center().x, r.position.y - 31.0)
			lp.velocity = Vector2.ZERO
			lp.sync_position = lp.position
			break
	for child in g.players_node.get_children():
		if child == lp or not child.alive:
			continue
		child.position = Vector2(1800.0, 10378.0)
		child.velocity = Vector2.ZERO
		child.sync_position = child.position
	g._sf_strike_l4_timer = 0.0


func _ft_sf_c_trap_lightning_l4() -> Array:
	var lp = g.fire_test._ft_lp()
	var hp := float(lp.get("health"))
	var ok := hp <= 85.0
	return [ok, "player health=%.0f (want <=85 after a 15 HP lightning strike)" % hp]


# Collapsing (L6): the new summit step idx 50 must start
# shaking after the player stands on it.
func _ft_sf_s_trap_collapse_l6() -> void:
	var lp = g.fire_test._ft_lp()
	lp.set("health", 100.0)
	for c in g._sf_collapsing:
		if int(c.get("idx", -1)) == 50:
			var r: Rect2 = c["rect"]
			lp.position = Vector2(r.get_center().x, r.position.y - 31.0)
			lp.velocity = Vector2.ZERO
			lp.sync_position = lp.position
			break


func _ft_sf_c_trap_collapse_l6() -> Array:
	var state := "missing"
	for c in g._sf_collapsing:
		if int(c.get("idx", -1)) == 50:
			state = str(c.get("state", "?"))
			break
	var ok := state == "shaking" or state == "falling"
	return [ok, "collapsing idx 50 state=%s (want shaking/falling after standing on it)" % state]


# Wind gusts (L3): the new upper wind zone (1400,5400,800,600,
# pushes left) must push the player left.
func _ft_sf_s_trap_wind_l3() -> void:
	var lp = g.fire_test._ft_lp()
	lp.position = Vector2(1800.0, 5700.0)
	lp.velocity = Vector2.ZERO
	lp.sync_position = lp.position
	g.features_skyfall_test._ft_sf_wind_x0 = lp.position.x


func _ft_sf_c_trap_wind_l3() -> Array:
	var lp = g.fire_test._ft_lp()
	var ok: bool = lp.position.x < g.features_skyfall_test._ft_sf_wind_x0 - 20.0
	return [ok, "player x=%.0f (was %.0f, want <%.0f — pushed left by the new L3 wind zone)" % [lp.position.x, g.features_skyfall_test._ft_sf_wind_x0, g.features_skyfall_test._ft_sf_wind_x0 - 20.0]]


# Pendulum (L4, QA-137): the swinging wrecking ball must exist,
# swing, and deal 25 HP on contact (QA-126 rules). The match clock
# is reset to 0 so the L4 ball (phase 0) sits at the bottom of its
# swing; the player stands on the (2100,4184) platform right where
# the ball passes (ball centre 2400,4150; player centre 2400,4153).
func _ft_sf_s_trap_pendulum() -> void:
	var lp = g.fire_test._ft_lp()
	lp.set("health", 100.0)
	lp.set("shield_timer", 0.0)
	g._sf_match_time = 0.0
	g.fire_test._ft_teleport(Vector2(2400.0, 4153.0))


func _ft_sf_c_trap_pendulum() -> Array:
	var lp = g.fire_test._ft_lp()
	var hp := float(lp.get("health"))
	var n = g._sf_pendulums.size()
	var ok = n == 2 and hp <= 75.0
	return [ok, "pendulums=%d (want 2) player health=%.0f (want <=75 after a 25 HP ball hit)" % [n, hp]]


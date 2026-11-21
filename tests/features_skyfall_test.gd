class_name FeaturesSkyfallTest
extends RefCounted


# QA-140 (v3.15): extracted from game.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `g` (dependency injection).


var g # the owner (game.gd)

var _ft_sf_hp0: float = 0.0 # FT-SF-OPP-SHIELD-STORM: health before the storm
var _ft_sf_heli_x0: float = 0.0 # FT-SF-SCENERY: helicopter x before the wait
var _ft_sf_wind_x0: float = 0.0 # FT-SF-TRAP-WIND-L3: player x before the wait
var _ft_sf_path_kind: int = 0 # FT-SF-PATH-*: the kind under test (7-13)


func _init(owner) -> void:
	g = owner


func _ft_sf_s_mode() -> void:
	# The features test starts in FFA (mode 0); Skyfall CTF needs
	# mode 4 + a real team. Switch the scene var (not just
	# GameData) and rebuild the flags (idempotent).
	g.game_mode = 4
	var lp = g.fire_test._ft_lp()
	lp.team = 0
	g._build_ctf_flags()


func _ft_sf_c_mode() -> Array:
	var lp = g.fire_test._ft_lp()
	var ok = g.game_mode == 4 and g._ctf_flags.size() == 2 and int(lp.team) == 0
	return [ok, "mode=%d flags=%d team=%d" % [g.game_mode, g._ctf_flags.size(), int(lp.team)]]


func _ft_sf_c_map() -> Array:
	var m: Dictionary = g.MAPS[g.map_id]
	var ok := int(m.get("size", Vector2.ZERO).x) == 3400 and int(m.get("size", Vector2.ZERO).y) == 10800
	ok = ok and (m.get("platforms", []) as Array).size() == 55
	ok = ok and (m.get("spawns", []) as Array).size() == 12
	ok = ok and (m.get("grapple", []) as Array).size() == 8
	ok = ok and (m.get("jetpack_lines", []) as Array).size() == 2
	ok = ok and (m.get("relay", []) as Array).size() == 2
	ok = ok and (m.get("checkpoints", []) as Array).size() == 4
	ok = ok and (m.get("pickups", []) as Array).size() == 6
	ok = ok and (m.get("skyfall_pickups", []) as Array).size() == 7
	return [ok, "size=%s platforms=%d spawns=%d grapple=%d lines=%d relay=%d cps=%d weapons=%d powerups=%d" % [str(m.get("size")), (m.get("platforms", []) as Array).size(), (m.get("spawns", []) as Array).size(), (m.get("grapple", []) as Array).size(), (m.get("jetpack_lines", []) as Array).size(), (m.get("relay", []) as Array).size(), (m.get("checkpoints", []) as Array).size(), (m.get("pickups", []) as Array).size(), (m.get("skyfall_pickups", []) as Array).size()]]


func _ft_sf_s_grab() -> void:
	g.fire_test._ft_teleport(Vector2(2200, 820)) # above the BLUE flag (2200,862)


func _ft_sf_c_grab() -> Array:
	var carrier = int((g._ctf_flags[1] as Dictionary).get("carrier", -1))
	var ok = carrier == g.multiplayer.get_unique_id()
	return [ok, "blue flag carrier=%d (me=%d)" % [carrier, g.multiplayer.get_unique_id()]]


func _ft_sf_s_capture() -> void:
	g.fire_test._ft_teleport(Vector2(450, 10710)) # above RED extraction (450,10752)


func _ft_sf_c_capture() -> Array:
	var ok = int(g._ctf_scores.get(0, 0)) == GameData.CTF_CAPTURE_POINTS and int((g._ctf_flags[1] as Dictionary).get("carrier", -1)) == -1
	return [ok, "RED=%d pts (capture=%d), blue flag carrier=%d" % [int(g._ctf_scores.get(0, 0)), GameData.CTF_CAPTURE_POINTS, int((g._ctf_flags[1] as Dictionary).get("carrier", -1))]]


func _ft_sf_s_relay_grab() -> void:
	g.fire_test._ft_teleport(Vector2(2200, 820))
	# QA-114: the grab key is (peer, flag team) — BLUE flag is team 1.
	g._ctf_grab[g.multiplayer.get_unique_id() * 10 + 1] = 1.4 # nearly held — grabs on the next frame


func _ft_sf_c_relay_grab() -> Array:
	var carrier = int((g._ctf_flags[1] as Dictionary).get("carrier", -1))
	var ok = carrier == g.multiplayer.get_unique_id()
	return [ok, "blue flag carrier=%d (me=%d)" % [carrier, g.multiplayer.get_unique_id()]]


func _ft_sf_s_relay_bank() -> void:
	g.fire_test._ft_teleport(Vector2(1800, 6620)) # above the Level 3 relay (1800,6670)


func _ft_sf_c_relay_bank() -> Array:
	var ok = int(g._ctf_scores.get(0, 0)) == GameData.CTF_CAPTURE_POINTS + GameData.CTF_RELAY_POINTS
	ok = ok and int((g._ctf_flags[1] as Dictionary).get("carrier", -1)) == -1
	ok = ok and not bool((g._ctf_flags[1] as Dictionary).get("dropped", false))
	return [ok, "RED=%d pts (3 capture + 1 relay), flag home=%s" % [int(g._ctf_scores.get(0, 0)), str(not bool((g._ctf_flags[1] as Dictionary).get("dropped", false)))]]


func _ft_sf_s_cp_up() -> void:
	g.fire_test._ft_teleport(Vector2(1800, 1640)) # Level 6 arena


func _ft_sf_c_cp_up() -> Array:
	var ok = int(g._ctf_checkpoints.get(0, -1)) == 3
	return [ok, "RED checkpoint=%d (want 3 = Level 6)" % int(g._ctf_checkpoints.get(0, -1))]


func _ft_sf_s_cp_down() -> void:
	g.fire_test._ft_teleport(Vector2(1800, 10700)) # back to the base (new L1 floor y 10752)


func _ft_sf_c_cp_down() -> Array:
	var ok = int(g._ctf_checkpoints.get(0, -1)) == 0
	return [ok, "RED checkpoint=%d (want 0 = base)" % int(g._ctf_checkpoints.get(0, -1))]


func _ft_sf_s_die_l6_setup() -> void:
	g.fire_test._ft_teleport(Vector2(1800, 1640)) # Level 6 arena — checkpoint must advance first


func _ft_sf_c_die_l6_setup() -> Array:
	var ok = int(g._ctf_checkpoints.get(0, -1)) == 3
	return [ok, "RED checkpoint=%d before dying (want 3)" % int(g._ctf_checkpoints.get(0, -1))]


func _ft_sf_s_die_l6() -> void:
	var lp = g.fire_test._ft_lp()
	lp._apply_damage(999, 1, Vector2.ZERO, 0.0, 0) # lethal — respawn takes 3 s


func _ft_sf_c_die_l6() -> Array:
	var lp = g.fire_test._ft_lp()
	var ok := bool(lp.alive) and absf(lp.position.y - 1678.0) < 300.0
	return [ok, "alive=%s y=%.0f (want alive near L6 y=1678)" % [str(bool(lp.alive)), lp.position.y]]


func _ft_sf_s_slots() -> void:
	# QA-119 slot rule (user 2026-11-20 ~21:00): pickup NEVER
	# activates — every kind goes to a free slot and waits for a
	# tap, INCLUDING Health (7). So all three are stored, none active.
	var lp = g.fire_test._ft_lp()
	lp.apply_powerup(9) # speed (timed)
	lp.apply_powerup(8) # shield (timed)
	lp.apply_powerup(7) # health — takes a slot too, no instant heal


func _ft_sf_c_slots() -> Array:
	var lp = g.fire_test._ft_lp()
	var stored: Array = lp.get("stored_boosts")
	var ab := int(lp.get("active_boost_kind"))
	var total := stored.size() + (1 if ab != 0 else 0)
	var ok := total == 3 and stored.size() == 3 and ab == 0
	return [ok, "held=%d (want 3: speed+shield+health, all stored), slots used=%d (max 3), active=%d (want 0)" % [total, stored.size(), ab]]


func _ft_sf_s_active() -> void:
	# OPPOSITE: one active boost at a time, via the real tap path.
	# Speed (9) is active; Jetpack (10) is stored, then the player
	# taps its slot — the tap must do nothing and the boost stays
	# stored (kind 12 is instant Thunder in the new set, not a timed
	# boost, so the old "apply 12" setup no longer tests this rule).
	var lp = g.fire_test._ft_lp()
	lp.get("stored_boosts").clear()
	lp.set("active_boost_kind", 9)
	lp.set("speed_timer", 30.0)
	lp.apply_powerup(10) # jetpack boost (timed) — goes to a slot
	lp.call("activate_slot", 0) # tap the slot: must be refused


func _ft_sf_c_active() -> Array:
	var lp = g.fire_test._ft_lp()
	var stored: Array = lp.get("stored_boosts")
	var ab := int(lp.get("active_boost_kind"))
	var ok := ab == 9 and 10 in stored
	lp.set("active_boost_kind", 0)
	lp.set("speed_timer", 0.0)
	return [ok, "active=%d (want 9 speed), jetpack stored=%s (want [10])" % [ab, str(stored)]]


func _ft_sf_s_carrier_ctrl() -> void:
	# CONTROL: a free player (not carrying) activates a timed boost
	# by tapping its slot. Kind 10 Jetpack is timed; kind 12 is
	# instant Thunder in the new set, so it cannot test this rule.
	var lp = g.fire_test._ft_lp()
	lp.get("stored_boosts").clear()
	lp.set("active_boost_kind", 0)
	lp.set("shield_timer", 0.0)
	lp.set("speed_timer", 0.0)
	lp.set("jetpack_boost_timer", 0.0)
	lp.set("invisibility_timer", 0.0)
	lp.set("carrying_flag", 0)
	lp.apply_powerup(10) # jetpack boost — stored, not active yet
	lp.call("activate_slot", 0) # tap: must activate


func _ft_sf_c_carrier_ctrl() -> Array:
	var lp = g.fire_test._ft_lp()
	var ab := int(lp.get("active_boost_kind"))
	lp.set("active_boost_kind", 0)
	lp.set("jetpack_boost_timer", 0.0)
	var ok := ab == 10
	return [ok, "free player jetpack boost active=%d (want 10)" % ab]


func _ft_sf_s_carrier() -> void:
	# OPPOSITE: the flag carrier must NOT activate a timed boost —
	# it stays stored until the flag is dropped/delivered. Timed
	# kind 10 Jetpack (kind 12 is instant Thunder in the new set).
	var lp = g.fire_test._ft_lp()
	lp.get("stored_boosts").clear()
	lp.set("active_boost_kind", 0)
	lp.set("shield_timer", 0.0)
	lp.set("speed_timer", 0.0)
	lp.set("jetpack_boost_timer", 0.0)
	lp.set("invisibility_timer", 0.0)
	lp.set("carrying_flag", 1)
	lp.apply_powerup(10)
	lp.call("activate_slot", 0) # tap: must be refused (carrier rule)


func _ft_sf_c_carrier() -> Array:
	var lp = g.fire_test._ft_lp()
	var stored: Array = lp.get("stored_boosts")
	var ab := int(lp.get("active_boost_kind"))
	lp.set("carrying_flag", 0)
	var ok := ab == 0 and 10 in stored
	return [ok, "carrier jetpack boost active=%d (want 0), stored=%s (want [10])" % [ab, str(stored)]]


func _ft_sf_s_slot_btns() -> void:
	# QA-119 (v3.11): the 3 HUD slot buttons show the stored
	# power-up's icon and are tappable when the player CAN use it.
	var lp = g.fire_test._ft_lp()
	lp.get("stored_boosts").clear()
	lp.set("active_boost_kind", 0)
	lp.set("shield_timer", 0.0)
	lp.set("speed_timer", 0.0)
	lp.set("jetpack_boost_timer", 0.0)
	lp.set("invisibility_timer", 0.0)
	lp.set("carrying_flag", 0)
	lp.apply_powerup(8) # shield (timed) — slot 0
	lp.apply_powerup(10) # jetpack boost (timed) — slot 1


func _ft_sf_c_slot_btns() -> Array:
	var b0: Button = g._sf_slot_buttons[0]
	var b1: Button = g._sf_slot_buttons[1]
	var b2: Button = g._sf_slot_buttons[2]
	var icons_ok = b0.icon == GameAssets.SF_TEX_PU64[8] and b1.icon == GameAssets.SF_TEX_PU64[10] and b2.icon == GameAssets.SF_TEX_SLOT[2]
	var ok = icons_ok and not b0.disabled and not b1.disabled and b2.disabled
	return [ok, "icons shield/jetpack/empty=%s, disabled=%s/%s/%s (want false/false/true)" % [str(icons_ok), str(b0.disabled), str(b1.disabled), str(b2.disabled)]]


func _ft_sf_path_spot(kind: int) -> int:
	var spots: Array = g.MAPS[g.map_id].get("skyfall_pickups", [])
	for i in spots.size():
		if int((spots[i] as Array)[2]) == kind:
			return i
	return -1


# QA-132: FT-SF-SLOT-TAP setup — tap a FILLED slot button through
# the REAL viewport input pipeline, at the button's screen position
# (QA-117 lesson: a tap swallowed by another control must fail
# this test, not pass on a direct activate_slot call). Shield is
# the timed kind used: it needs no target and no flag.
func _ft_sf_s_slot_tap() -> void:
	var lp = g.fire_test._ft_lp()
	lp.get("stored_boosts").clear()
	lp.set("active_boost_kind", 0)
	lp.set("shield_timer", 0.0)
	lp.set("speed_timer", 0.0)
	lp.set("jetpack_boost_timer", 0.0)
	lp.set("invisibility_timer", 0.0)
	lp.set("carrying_flag", 0)
	lp.apply_powerup(8) # shield -> slot 0
	var b0: Button = g._sf_slot_buttons[0]
	var centre: Vector2 = b0.get_global_rect().get_center()
	var to_vp: Vector2 = g.hud.get_final_transform() * centre
	var press := InputEventScreenTouch.new()
	press.index = 904
	press.pressed = true
	press.position = to_vp
	g.get_viewport().push_input(press)
	var rel := InputEventScreenTouch.new()
	rel.index = 904
	rel.pressed = false
	rel.position = to_vp
	g.get_viewport().push_input(rel)


func _ft_sf_c_slot_tap() -> Array:
	var lp = g.fire_test._ft_lp()
	var ab := int(lp.get("active_boost_kind"))
	var st := float(lp.get("shield_timer"))
	var ok := ab == 8 and st > 0.0
	lp.set("active_boost_kind", 0)
	lp.set("shield_timer", 0.0)
	return [ok, "real-touch tap on slot 0: active=%d shield=%.1fs (want 8 / >0)" % [ab, st]]


# QA-132: shared FT-SF-PATH-<kind> setup (7-13) — clean slate,
# spawn the kind's own power-up on its spot, teleport the player
# onto it. Wind/thunder need a live enemy in range to prove the
# effect, so a BLUE bot stands 300 px to the right of the spot
# (inside wind 520 / thunder 800). Wait 1.0 s covers the physical
# Area2D collection; the shared check then taps the slot and
# verifies the effect.
func _ft_sf_s_path(kind: int) -> void:
	_ft_sf_path_kind = kind
	var lp = g.fire_test._ft_lp()
	lp.get("stored_boosts").clear()
	lp.set("active_boost_kind", 0)
	lp.set("shield_timer", 0.0)
	lp.set("speed_timer", 0.0)
	lp.set("jetpack_boost_timer", 0.0)
	lp.set("invisibility_timer", 0.0)
	lp.set("carrying_flag", 0)
	lp.set("health", 50.0) # kind 7 must heal visibly; harmless for the rest
	lp.set("fuel", PhysicsConfig.FUEL_MAX)
	for child in g.pickups_node.get_children():
		if int(child.get("kind")) >= 7:
			child.free() # leftover power-ups from earlier steps
	for pid in [201, 202]:
		var old = g.players_node.get_node_or_null(str(pid))
		if old != null:
			old.queue_free() # leftover test bots from earlier steps
		# QA-132 fix: _do_spawn early-returns when _spawned still
		# has the pid (it never clears on free) — without this the
		# PATH-12 bot never spawns at all (PATH-11 already used 202).
		g._spawned.erase(pid)
	var si := _ft_sf_path_spot(kind)
	g._spawn_skyfall_powerup(si)
	var spot: Array = (g.MAPS[g.map_id].get("skyfall_pickups", []) as Array)[si]
	if kind == 11 or kind == 12:
		g._do_spawn(202, "PathBot", 1, 0, 1)
		var b = g.players_node.get_node_or_null("202")
		if b != null:
			# QA-132 fix: +150 px, NOT +300 — +300 put the bot on
			# a platform seam (thunder spot x1200 + 300 = x1500,
			# the exact edge of two rows) and it fell out of the
			# 800 px thunder range. +150 lands on the SAME platform
			# as the player, 150 px away.
			b.position = Vector2(float(spot[0]) + 150.0, float(spot[1]))
			b.sync_position = b.position
			b.velocity = Vector2.ZERO
			b.health = 100
			b.set("_spawn_protect_timer", 0.0) # else take_hit ignores the blast
	g.fire_test._ft_teleport(Vector2(float(spot[0]), float(spot[1]) - 40.0))


func _ft_sf_s_path7() -> void: _ft_sf_s_path(7)


func _ft_sf_s_path8() -> void: _ft_sf_s_path(8)


func _ft_sf_s_path9() -> void: _ft_sf_s_path(9)


func _ft_sf_s_path10() -> void: _ft_sf_s_path(10)


func _ft_sf_s_path11() -> void: _ft_sf_s_path(11)


func _ft_sf_s_path12() -> void: _ft_sf_s_path(12)


func _ft_sf_s_path13() -> void: _ft_sf_s_path(13)


func _ft_sf_c_path() -> Array:
	var lp = g.fire_test._ft_lp()
	var kind = _ft_sf_path_kind
	var stored: Array = lp.get("stored_boosts")
	if kind not in stored:
		return [false, "kind %d never reached a slot (stored=%s)" % [kind, str(stored)]]
	var idx := stored.find(kind)
	var ok := false
	var detail := ""
	var ab0 := int(lp.get("active_boost_kind"))
	var cf0 := int(lp.get("carrying_flag"))
	match kind:
		7:
			var tapped7 := bool(lp.call("activate_slot", idx))
			ok = float(lp.health) >= 99.0
			detail = "tap=%s health=%.0f (want 100 after +50 from 50)" % [str(tapped7), float(lp.health)]
		8:
			var tapped8 := bool(lp.call("activate_slot", idx))
			ok = int(lp.get("active_boost_kind")) == 8 and float(lp.get("shield_timer")) > 0.0
			detail = "tap=%s pre_active=%d pre_flag=%d active=%d shield=%.1fs" % [str(tapped8), ab0, cf0, int(lp.get("active_boost_kind")), float(lp.get("shield_timer"))]
		9:
			var tapped9 := bool(lp.call("activate_slot", idx))
			ok = int(lp.get("active_boost_kind")) == 9 and float(lp.get("speed_timer")) > 0.0
			detail = "tap=%s pre_active=%d pre_flag=%d active=%d speed=%.1fs" % [str(tapped9), ab0, cf0, int(lp.get("active_boost_kind")), float(lp.get("speed_timer"))]
		10:
			var tapped10 := bool(lp.call("activate_slot", idx))
			var ab := int(lp.get("active_boost_kind"))
			var fuel_ok = absf(float(lp.fuel) - PhysicsConfig.FUEL_MAX) < 1.0
			# QA-137 (v3.14): the boost flame is a SEPARATE
			# texture now (the user's sheet), not a 1.5x stretch
			# of the normal flame — so the flame's scale factor
			# no longer proves the boost (the boost texture is
			# 616x926 drawn 30x33, scale.y ~0.04). The DRAWN
			# height is the proof: boost draws 33 px tall, plain
			# thrust 22 px. Force one visual update at full
			# thrust and read the drawn height.
			lp.set("_jetpacking", true)
			lp.velocity = Vector2(0, -320)
			lp.set("_jet_thrust_factor", 1.0)
			lp.call("_update_visuals", 0.016)
			var flame = lp.get("_flame")
			var fdrawn := 0.0
			var fvis := false
			var fboost := false
			if flame != null:
				var ftex = (flame as Sprite2D).texture
				fdrawn = float((flame as Sprite2D).scale.y) * float(ftex.get_height()) if ftex != null else 0.0
				fvis = bool((flame as Sprite2D).visible)
				fboost = ftex != null and ftex.resource_path == "res://assets/user_assets_v3/jetpack_flame_boost.png"
			lp.set("_jetpacking", false)
			ok = ab == 10 and float(lp.get("jetpack_boost_timer")) > 0.0 and fuel_ok and fvis and fboost and fdrawn > 28.0
			detail = "tap=%s pre_active=%d pre_flag=%d active=%d timer=%.1fs fuel=%.0f flame visible=%s boost_tex=%s drawn_h=%.1f (want >28)" % [str(tapped10), ab0, cf0, ab, float(lp.get("jetpack_boost_timer")), float(lp.fuel), str(fvis), str(fboost), fdrawn]
		11:
			var bot = g.players_node.get_node_or_null("202")
			var tapped11 := bool(lp.call("activate_slot", idx))
			# QA-135: Wind Blast is a tornado now, not a shove — the
			# tap must spawn the tornado at the bot and start the
			# sweep on it (velocity is set by the victim's own
			# physics next frame, so the sweep timer + tornado node
			# are the synchronous proof; the throw-down is covered
			# by FT-SF-WIND-THROW with a longer wait).
			var torn_raw = g.get("_wind_tornado_node")
			var torn_ok := torn_raw != null and is_instance_valid(torn_raw)
			var sweep_t := 0.0
			if bot != null:
				sweep_t = float(bot.get("_wind_sweep_timer"))
			ok = int(lp.get("_fx_flash_kind")) == 11 and kind not in lp.get("stored_boosts") and torn_ok and sweep_t > 0.0
			detail = "tap=%s flash=%d tornado=%s sweep=%.2fs (want tornado + sweep > 0)" % [str(tapped11), int(lp.get("_fx_flash_kind")), str(torn_ok), sweep_t]
			if bot != null:
				bot.queue_free()
		12:
			var bot12 = g.players_node.get_node_or_null("202")
			var bp := Vector2(-1, -1)
			if bot12 != null:
				bp = bot12.position
			var tapped12 := bool(lp.call("activate_slot", idx))
			var hp1 := 100.0
			if bot12 != null:
				hp1 = float(bot12.health)
			# QA-135: Thunder Strike halves the target's CURRENT
			# health (100 -> 50), single target, no area damage.
			ok = int(lp.get("_fx_flash_kind")) == 12 and hp1 == 50.0
			detail = "tap=%s flash=%d bot pos=%s player pos=%s dist=%.0f bot health=%.0f (want 50 after halving 100)" % [str(tapped12), int(lp.get("_fx_flash_kind")), str(bp), str(lp.position), lp.position.distance_to(bp) if bp.x >= 0.0 else -1.0, hp1]
			if bot12 != null:
				bot12.queue_free()
		13:
			var tapped13 := bool(lp.call("activate_slot", idx))
			ok = int(lp.get("active_boost_kind")) == 13 and float(lp.get("invisibility_timer")) > 0.0
			detail = "tap=%s pre_active=%d pre_flag=%d active=%d invis=%.1fs" % [str(tapped13), ab0, cf0, int(lp.get("active_boost_kind")), float(lp.get("invisibility_timer"))]
	# Tidy up: end any timed boost so the next step starts clean.
	lp.set("active_boost_kind", 0)
	lp.set("shield_timer", 0.0)
	lp.set("speed_timer", 0.0)
	lp.set("jetpack_boost_timer", 0.0)
	lp.set("invisibility_timer", 0.0)
	return [ok, "kind %d path spawn->pickup->slot->tap->effect: %s" % [kind, detail]]


func _ft_sf_s_slot_grey_active() -> void:
	# Timed slots grey out while a boost is active; an instant
	# kind stays tappable even then.
	var lp = g.fire_test._ft_lp()
	lp.get("stored_boosts").clear()
	lp.set("active_boost_kind", 9)
	lp.set("speed_timer", 30.0)
	lp.set("shield_timer", 0.0)
	lp.set("jetpack_boost_timer", 0.0)
	lp.set("invisibility_timer", 0.0)
	lp.set("carrying_flag", 0)
	lp.apply_powerup(8) # shield (timed) — must grey out
	lp.apply_powerup(7) # health (instant) — must stay tappable


func _ft_sf_c_slot_grey_active() -> Array:
	var b0: Button = g._sf_slot_buttons[0]
	var b1: Button = g._sf_slot_buttons[1]
	var ok := b0.disabled and not b1.disabled
	var lp = g.fire_test._ft_lp()
	lp.set("active_boost_kind", 0)
	lp.set("speed_timer", 0.0)
	return [ok, "shield disabled=%s (want true), health disabled=%s (want false) while Speed active" % [str(b0.disabled), str(b1.disabled)]]


func _ft_sf_s_slot_grey_carrier() -> void:
	# Same split while carrying the flag: timed greys out
	# (carrier rule wins), instant stays tappable.
	var lp = g.fire_test._ft_lp()
	lp.get("stored_boosts").clear()
	lp.set("active_boost_kind", 0)
	lp.set("shield_timer", 0.0)
	lp.set("speed_timer", 0.0)
	lp.set("jetpack_boost_timer", 0.0)
	lp.set("invisibility_timer", 0.0)
	lp.set("carrying_flag", 1)
	# QA-133: make the GAME state agree — the 0.5 s ctf_sync
	# rewrites carrying_flag from _ctf_carrier_of every 0.5 s, so
	# a manually-set flag would be wiped mid-wait and the button
	# would enable. The RED player carries the BLUE flag:
	# _ctf_flags[1] carrier = local peer -> carrying_flag 2.
	if g._ctf_flags.size() > 1:
		(g._ctf_flags[1] as Dictionary)["carrier"] = int(lp.peer_id)
	lp.apply_powerup(8) # shield (timed) — must grey out
	lp.apply_powerup(7) # health (instant) — must stay tappable


func _ft_sf_c_slot_grey_carrier() -> Array:
	var b0: Button = g._sf_slot_buttons[0]
	var b1: Button = g._sf_slot_buttons[1]
	var ok := b0.disabled and not b1.disabled
	var lp = g.fire_test._ft_lp()
	lp.set("carrying_flag", 0)
	if g._ctf_flags.size() > 1:
		(g._ctf_flags[1] as Dictionary)["carrier"] = -1 # QA-133: give the flag back
	return [ok, "shield disabled=%s (want true), health disabled=%s (want false) while carrying" % [str(b0.disabled), str(b1.disabled)]]


func _ft_sf_s_invis_warn() -> void:
	# QA-121 (v3.11): a living invisible ENEMY puts the red chip
	# at the top of the top-left message area.
	g._do_spawn(201, "InvisBot", 1, 0, 1) # BLUE enemy
	var bot = g.players_node.get_node_or_null("201")
	if bot != null:
		bot.set("invisibility_timer", 10.0)


func _ft_sf_c_invis_warn() -> Array:
	var chip_ok = g._invis_warning_chip != null and g._invis_warning_chip.visible
	var txt := ""
	if g._invis_warning_chip != null:
		txt = (g._invis_warning_chip.get_child(0) as Label).text
	var ok = chip_ok and txt == "Enemy is invisible!"
	return [ok, "warning chip visible=%s text='%s' (want true / 'Enemy is invisible!')" % [str(chip_ok), txt]]


func _ft_sf_s_invis_clear() -> void:
	var bot = g.players_node.get_node_or_null("201")
	if bot != null:
		bot.set("invisibility_timer", 0.0)


func _ft_sf_c_invis_clear() -> Array:
	var ok = g._invis_warning_chip == null or not g._invis_warning_chip.visible
	var bot = g.players_node.get_node_or_null("201")
	if bot != null:
		bot.queue_free()
	return [ok, "warning chip hidden=%s after the invisibility ends" % str(ok)]


func _ft_sf_c_levels() -> Array:
	# QA-123: the rebuilt tower is 6 levels x 1800 px (L1 bottom,
	# L6 summit). Check the level function at one sample per level,
	# the relay levels (3 and 6), the checkpoint levels, and the
	# bridge gust schedule (3 s on / 12 s off per 15 s).
	var got = [g._sf_level_of(10000.0), g._sf_level_of(8000.0), g._sf_level_of(6300.0), g._sf_level_of(4500.0), g._sf_level_of(2700.0), g._sf_level_of(900.0)]
	var ok = got == [1, 2, 3, 4, 5, 6]
	ok = ok and g._sf_level_of(6384.0) == 3 and g._sf_level_of(1678.0) == 6
	ok = ok and GameData.SF_CHECKPOINT_LEVELS == [0, 2, 4, 6]
	g._sf_match_time = 1.0
	var gust_on = g._sf_gust_active()
	g._sf_match_time = 5.0
	var gust_off = not g._sf_gust_active()
	ok = ok and gust_on and gust_off
	return [ok, "levels=%s (want [1,2,3,4,5,6]) relay L%d/L%d cps=%s gust 1s=%s 5s=%s" % [str(got), g._sf_level_of(6384.0), g._sf_level_of(1678.0), str(GameData.SF_CHECKPOINT_LEVELS), str(gust_on), str(not gust_off)]]


func _ft_sf_s_heightbar() -> void:
	g.fire_test._ft_teleport(Vector2(1800, 2660)) # Level 5


func _ft_sf_c_heightbar() -> Array:
	var want_y := 360.0 * 2660.0 / 10800.0 - 6.0
	var dot: ColorRect = g._sf_height_dots[0]
	var ok = bool(g._sf_height_bar.visible) and dot.visible and absf(dot.position.y - want_y) < 15.0
	return [ok, "height bar=%s dot0 y=%.1f (want %.1f)" % [str(bool(g._sf_height_bar.visible)), dot.position.y, want_y]]


func _ft_sf_s_ping() -> void:
	g._on_ping_pressed()


func _ft_sf_c_ping() -> Array:
	var bar_dot := false
	for pd in g._sf_height_ping_dots:
		if (pd as ColorRect).visible:
			bar_dot = true
			break
	var ok = g._sf_pings.size() >= 1 and bar_dot
	return [ok, "pings=%d height-bar ping dot=%s" % [g._sf_pings.size(), str(bar_dot)]]


func _ft_sf_c_routes() -> Array:
	var ok = g.skyfall_route_of(500.0) == 0 and g.skyfall_route_of(1800.0) == 1 and g.skyfall_route_of(3000.0) == 2
	var legend_n := 0
	for c in g._sf_height_bar.get_children():
		if c is VBoxContainer:
			legend_n = c.get_child_count()
			break
	ok = ok and legend_n == 3
	return [ok, "routes WEST/CENTRE/EAST=%d/%d/%d legend rows=%d" % [g.skyfall_route_of(500.0), g.skyfall_route_of(1800.0), g.skyfall_route_of(3000.0), legend_n]]


func _ft_sf_s_scenery() -> void:
	_ft_sf_heli_x0 = float((g._sf_scenery.get("heli") as Node2D).position.x)


func _ft_sf_c_scenery() -> Array:
	var heli: Node2D = g._sf_scenery.get("heli")
	var ok = heli != null and heli.position.x > _ft_sf_heli_x0
	ok = ok and (g._sf_scenery.get("clouds", []) as Array).size() == 5
	ok = ok and not g._sf_scenery.has("gears") # QA-132: gears deleted
	ok = ok and not g._sf_scenery.has("puffs") # QA-132: steam puffs deleted
	ok = ok and (g._sf_scenery.get("streaks", []) as Array).size() == 5
	ok = ok and g._sf_scenery.get("flash") != null
	return [ok, "heli moved %.0f -> %.0f, clouds=%d gears=%s puffs=%s streaks=%d flash=%s" % [_ft_sf_heli_x0, heli.position.x if heli != null else -1.0, (g._sf_scenery.get("clouds", []) as Array).size(), str(not g._sf_scenery.has("gears")), str(not g._sf_scenery.has("puffs")), (g._sf_scenery.get("streaks", []) as Array).size(), str(g._sf_scenery.get("flash") != null)]]


# QA-134 (v3.13): no mover's travel path may pass under, through,
# or overlap any static platform rect. Swept rect = x..x+w,
# y_top..y_bottom+48 (the body is 48 tall, top = y). The summit
# elevator the same. Rotator: the body (400x48) orbits a 120 px
# circle — sample 36 angles and check the body rect at each.
# Rect2.intersects excludes edge-touching, so docking flush
# against a platform top is fine. Collapsing platforms only drop
# 120 px then fade (no travel path); trapdoors only swap texture.
func _ft_sf_s_noop() -> void:
	pass


func _ft_sf_c_mover_clear() -> Array:
	var plats: Array = g.MAPS[g.map_id].get("platforms", [])
	var bad: Array = []
	for e in g.MAPS[g.map_id].get("elevators", []):
		var r := Rect2(float(e["x"]), float(e["y_top"]), float(e["w"]), float(e["y_bottom"]) - float(e["y_top"]) + 48.0)
		for i in plats.size():
			if r.intersects(plats[i]):
				bad.append("elev x%d plat %d" % [int(e["x"]), i])
	var se: Dictionary = g.MAPS[g.map_id].get("summit_elevator", {})
	if not se.is_empty():
		var sr := Rect2(float(se["x"]), float(se["y_top"]), float(se.get("w", 300)), float(se["y_bottom"]) - float(se["y_top"]) + 48.0)
		for i in plats.size():
			if sr.intersects(plats[i]):
				bad.append("summit plat %d" % i)
	var rc: Dictionary = g.MAPS[g.map_id].get("rotator", {})
	if not rc.is_empty():
		var c: Vector2 = rc["center"]
		var rad := float(rc.get("radius", 120.0))
		var hw := float(rc.get("w", 400)) * 0.5
		for a in 36:
			var ang := TAU * float(a) / 36.0
			var bc: Vector2 = c + Vector2(cos(ang), sin(ang)) * rad
			var br := Rect2(bc - Vector2(hw, 24.0), Vector2(hw * 2.0, 48.0))
			for i in plats.size():
				if br.intersects(plats[i]):
					bad.append("rotator a%d plat %d" % [a, i])
					break
	var ok := bad.is_empty()
	return [ok, "mover overlaps=%s (want none)" % str(bad)]


# QA-135 (v3.13): Wind Blast / Thunder Strike targeting — the
# target must be on the SAME PLATFORM at the SAME HEIGHT (within
# 60 px). Shared setup for the no-target / height tests: clean
# slate, the kind in a slot, the player on the wind/thunder spot
# (row 14), no other players. `bot_y` places a bot 150 px away
# on the same spot with a vertical offset (0 = same platform,
# -150 = hovering above it); -999 = no bot at all.
func _ft_sf_s_pu_target(kind: int, bot_y: float) -> void:
	var lp = g.fire_test._ft_lp()
	lp.get("stored_boosts").clear()
	lp.set("active_boost_kind", 0)
	lp.set("shield_timer", 0.0)
	lp.set("speed_timer", 0.0)
	lp.set("jetpack_boost_timer", 0.0)
	lp.set("invisibility_timer", 0.0)
	lp.set("carrying_flag", 0)
	lp.set("health", 100.0)
	lp.set("fuel", PhysicsConfig.FUEL_MAX)
	for child in g.pickups_node.get_children():
		if int(child.get("kind")) >= 7:
			child.free()
	for pid in [201, 202]:
		var old = g.players_node.get_node_or_null(str(pid))
		if old != null:
			old.queue_free()
		g._spawned.erase(pid)
	var si := _ft_sf_path_spot(11)
	var spot: Array = (g.MAPS[g.map_id].get("skyfall_pickups", []) as Array)[si]
	lp.position = Vector2(float(spot[0]), float(spot[1]))
	lp.velocity = Vector2.ZERO
	lp.sync_position = lp.position
	lp.call("apply_powerup", kind)
	if bot_y > -900.0:
		g._do_spawn(202, "PathBot", 1, 0, 1)
		var b = g.players_node.get_node_or_null("202")
		if b != null:
			b.position = Vector2(float(spot[0]) + 150.0, float(spot[1]) + bot_y)
			b.sync_position = b.position
			b.velocity = Vector2.ZERO
			b.health = 100
			b.set("_spawn_protect_timer", 0.0)


func _ft_sf_s_wind_no_target() -> void:
	_ft_sf_s_pu_target(11, -999.0)


func _ft_sf_c_wind_no_target() -> Array:
	var lp = g.fire_test._ft_lp()
	var idx := int(lp.get("stored_boosts").find(11))
	var tapped := false
	if idx >= 0:
		tapped = bool(lp.call("activate_slot", idx))
	var kept: bool = 11 in lp.get("stored_boosts")
	# QA-135: read the tornado through a Variant + is_instance_valid
	# — a typed Node2D assignment errors if the reference dangles
	# (a freed tornado from an earlier step).
	var torn_raw = g.get("_wind_tornado_node")
	var torn_ok := torn_raw != null and is_instance_valid(torn_raw)
	var ok := not tapped and kept and not torn_ok
	return [ok, "tap=%s slot kept=%s tornado=%s (want tap=false, kept, no tornado)" % [str(tapped), str(kept), str(torn_ok)]]


func _ft_sf_s_thunder_no_target() -> void:
	_ft_sf_s_pu_target(12, -999.0)


func _ft_sf_c_thunder_no_target() -> Array:
	var lp = g.fire_test._ft_lp()
	var idx := int(lp.get("stored_boosts").find(12))
	var tapped := false
	if idx >= 0:
		tapped = bool(lp.call("activate_slot", idx))
	var kept: bool = 12 in lp.get("stored_boosts")
	var ok := not tapped and kept
	return [ok, "tap=%s slot kept=%s (want tap=false, kept)" % [str(tapped), str(kept)]]


# QA-135: Wind Blast throw-down — the tap happens in the setup
# (sweep starts at t=0); after 1.5 s the bot must have fallen
# below the platform it stood on (sweep 0.7 s + throw 0.5 s +
# fall), with full health (no damage).
func _ft_sf_s_wind_throw() -> void:
	_ft_sf_s_pu_target(11, 0.0)
	var lp = g.fire_test._ft_lp()
	var idx := int(lp.get("stored_boosts").find(11))
	if idx >= 0:
		lp.call("activate_slot", idx)


func _ft_sf_c_wind_throw() -> Array:
	var lp = g.fire_test._ft_lp()
	var bot = g.players_node.get_node_or_null("202")
	var plat_idx = g._sf_platform_under(lp.position)
	var top := 0.0
	if plat_idx >= 0:
		top = (g.MAPS[g.map_id].get("platforms", []) as Array)[plat_idx].position.y
	var by := -1.0
	var bh := -1.0
	if bot != null:
		by = float(bot.position.y)
		bh = float(bot.health)
	var ok := bot != null and by > top + 200.0 and bh == 100.0
	return [ok, "bot y=%.0f plat top=%.0f (want >%.0f) bot health=%.0f (want 100, no damage)" % [by, top, top + 200.0, bh]]


# QA-135: Thunder Strike vs a shielded enemy — the strike fires
# (the bot IS on the platform) but the shield absorbs it all.
func _ft_sf_s_thunder_shield() -> void:
	_ft_sf_s_pu_target(12, 0.0)
	var bot = g.players_node.get_node_or_null("202")
	if bot != null:
		bot.set("shield_timer", 10.0)


func _ft_sf_c_thunder_shield() -> Array:
	var lp = g.fire_test._ft_lp()
	var bot = g.players_node.get_node_or_null("202")
	var idx := int(lp.get("stored_boosts").find(12))
	var tapped := false
	if idx >= 0:
		tapped = bool(lp.call("activate_slot", idx))
	var bh := -1.0
	if bot != null:
		bh = float(bot.health)
	var ok := tapped and bh == 100.0
	return [ok, "tap=%s bot health=%.0f (want tap=true, health 100 — shield absorbed the halving)" % [str(tapped), bh]]


# QA-135: height exclusion — the enemy hovers 150 px above the
# platform (jetpacking), so it is NOT on the platform surface and
# its height is far outside the 60 px tolerance. Neither
# power-up may fire; the slot is kept.
func _ft_sf_s_wind_height() -> void:
	_ft_sf_s_pu_target(11, -150.0)


func _ft_sf_c_wind_height() -> Array:
	var lp = g.fire_test._ft_lp()
	var idx := int(lp.get("stored_boosts").find(11))
	var tapped := false
	if idx >= 0:
		tapped = bool(lp.call("activate_slot", idx))
	var kept: bool = 11 in lp.get("stored_boosts")
	var ok := not tapped and kept
	return [ok, "tap=%s slot kept=%s (want tap=false, kept — bot 150 px above the platform)" % [str(tapped), str(kept)]]


func _ft_sf_s_thunder_height() -> void:
	_ft_sf_s_pu_target(12, -150.0)


func _ft_sf_c_thunder_height() -> Array:
	var lp = g.fire_test._ft_lp()
	var idx := int(lp.get("stored_boosts").find(12))
	var tapped := false
	if idx >= 0:
		tapped = bool(lp.call("activate_slot", idx))
	var kept: bool = 12 in lp.get("stored_boosts")
	var ok := not tapped and kept
	return [ok, "tap=%s slot kept=%s (want tap=false, kept — bot 150 px above the platform)" % [str(tapped), str(kept)]]


func _ft_sf_s_rarity() -> void:
	# Simulate 300 s of the spawn loops (1 s steps) and count.
	# Start from an empty field (as at match start) and clear the
	# field every 10 s — in a real match players grab pickups, and
	# without that the field sits at its cap and nothing respawns
	# (the first version of this test measured 0 power-ups for
	# exactly that reason). free() is immediate here (queue_free
	# would wait for the next frame, which never comes mid-loop).
	g._test_weapon_spawns = 0
	g._test_powerup_spawns = 0
	for child in g.pickups_node.get_children():
		child.free()
	g._pickup_spot_timers.clear()
	g._sf_pickup_timers.clear()
	g._initial_pickups_done = false
	g._sf_initial_powerups_done = false
	for i in 300:
		g._update_pickup_spawn(1.0)
		g._update_skyfall_powerups(1.0)
		if i % 10 == 9:
			for child in g.pickups_node.get_children():
				child.free()


func _ft_sf_c_rarity() -> Array:
	var ok = g._test_weapon_spawns > g._test_powerup_spawns and g._test_powerup_spawns > 0
	return [ok, "300 s sim: weapons=%d power-ups=%d (power-ups must be rarer)" % [g._test_weapon_spawns, g._test_powerup_spawns]]


func _ft_sf_s_5v5() -> void:
	# 10 players in the game scene (test-only fake peers — never in
	# the real game, which has no bots). Remove the TestBot left by
	# the base KILLFEED/SPECTATOR steps first, then spawn 9 fakes
	# with explicit teams: local (RED) + 4 RED + 5 BLUE = 5v5.
	GameData.max_players = 10
	for child in g.players_node.get_children():
		if String(child.player_name).begins_with("TestBot"):
			child.queue_free()
	for i in range(1, 5):
		g._do_spawn(100 + i, "TestBot%d" % i, i % 4, 0, 0)
	for i in range(5, 10):
		g._do_spawn(100 + i, "TestBot%d" % i, i % 4, 0, 1)


func _ft_sf_c_5v5() -> Array:
	var red := 0
	var blue := 0
	for child in g.players_node.get_children():
		if int(child.team) == 0:
			red += 1
		elif int(child.team) == 1:
			blue += 1
	var ok = g.players_node.get_child_count() == 10 and red == 5 and blue == 5
	return [ok, "players=%d RED=%d BLUE=%d (want 10 / 5 / 5)" % [g.players_node.get_child_count(), red, blue]]


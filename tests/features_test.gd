class_name FeaturesTest
extends RefCounted


# QA-140 (v3.15): extracted from game.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `g` (dependency injection).


var g # the owner (game.gd)

var _features_test: bool = false
var _feat_steps: Array = []
var _feat_step: int = 0
var _feat_in_step: bool = false
var _feat_timer: float = 0.0
var _feat_passed: int = 0
var _feat_failed: int = 0
var _feat_done: bool = false
var _feat_bot: Node = null
var _feat_data: Dictionary = {}


func _init(owner) -> void:
	g = owner


func _update_featurestest(delta: float) -> void:
	if _feat_done:
		return
	var lp = g._get_local_player()
	if lp == null:
		_feat_timer += delta
		if _feat_timer > 5.0:
			_feat_done = true
			print("FEATTEST DONE: 0/0 passed — no local player spawned")
			g.get_tree().quit()
		return
	if _feat_steps.is_empty():
		_featurestest_build_steps()
		_feat_step = 0
		_feat_in_step = false
		_feat_timer = 0.0
	if _feat_step >= _feat_steps.size():
		_feat_done = true
		print("FEATTEST DONE: %d/%d passed" % [_feat_passed, _feat_passed + _feat_failed])
		g.get_tree().quit()
		return
	var step: Dictionary = _feat_steps[_feat_step]
	if not _feat_in_step:
		(step["setup"] as Callable).call()
		_feat_in_step = true
		_feat_timer = float(step["wait"])
	_feat_timer -= delta
	if _feat_timer <= 0.0:
		var result: Array = (step["check"] as Callable).call()
		var ok: bool = bool(result[0])
		if ok:
			_feat_passed += 1
		else:
			_feat_failed += 1
		print("FEATTEST %s: %s — %s" % [String(step["name"]), "PASS" if ok else "FAIL", String(result[1])])
		_feat_step += 1
		_feat_in_step = false
		_feat_timer = 0.0


func _featurestest_build_steps() -> void:
	_feat_steps = [
		{"name": "COUNTDOWN-FREEZE", "wait": 0.6, "setup": _ft_s_countdown, "check": _ft_c_countdown},
		{"name": "COUNTDOWN-END", "wait": 3.0, "setup": _ft_s_release_all, "check": _ft_c_countdown_end},
		{"name": "KILLFEED-HITMARKER", "wait": 0.9, "setup": _ft_s_killfeed, "check": _ft_c_killfeed},
		{"name": "STREAK-CALLOUTS", "wait": 0.3, "setup": _ft_s_streaks, "check": _ft_c_streaks},
		{"name": "END-STATS-MVP", "wait": 0.3, "setup": _ft_s_endstats, "check": _ft_c_endstats},
		{"name": "SETTINGS-PERSIST", "wait": 0.3, "setup": _ft_s_settings, "check": _ft_c_settings},
		{"name": "MAP-VOTE", "wait": 0.2, "setup": g.fire_test._ft_s_noop, "check": _ft_c_mapvote},
		{"name": "PICKUPS-HEALTH-GRENADE", "wait": 0.3, "setup": _ft_s_pickups, "check": _ft_c_pickups},
		{"name": "MUSIC", "wait": 0.5, "setup": _ft_s_music, "check": _ft_c_music},
		{"name": "SPECTATOR", "wait": 0.6, "setup": _ft_s_spectator, "check": _ft_c_spectator},
		{"name": "SCOREBOARD", "wait": 0.2, "setup": _ft_s_scoreboard, "check": _ft_c_scoreboard},
		{"name": "FIRE-LAYOUT", "wait": 0.2, "setup": _ft_s_firelayout, "check": _ft_c_firelayout},
		{"name": "HUD-READOUTS", "wait": 0.3, "setup": g.fire_test._ft_s_noop, "check": _ft_c_hud},
	]
	# QA-112/114/115 (v3.9): Skyfall steps — only on map 4. The
	# base steps above run first (countdown done, match running).
	# Order matters: grab -> capture -> relay -> checkpoints ->
	# death/respawn -> power-ups -> comeback -> events -> storm ->
	# combos -> HUD -> routes -> scenery -> rarity -> 5v5 (last:
	# it spawns 9 fake players, test-only, never in the real game).
	if g.map_id == GameData.SKYFALL_MAP_ID:
		_feat_steps += [
			{"name": "FT-SF-MODE", "wait": 0.3, "setup": g.features_skyfall_test._ft_sf_s_mode, "check": g.features_skyfall_test._ft_sf_c_mode},
			{"name": "FT-SF-MAP", "wait": 0.2, "setup": g.fire_test._ft_s_noop, "check": g.features_skyfall_test._ft_sf_c_map},
			{"name": "FT-SF-GRAB", "wait": 2.0, "setup": g.features_skyfall_test._ft_sf_s_grab, "check": g.features_skyfall_test._ft_sf_c_grab},
			{"name": "FT-SF-CAPTURE", "wait": 0.5, "setup": g.features_skyfall_test._ft_sf_s_capture, "check": g.features_skyfall_test._ft_sf_c_capture},
			{"name": "FT-SF-RELAY-GRAB", "wait": 0.3, "setup": g.features_skyfall_test._ft_sf_s_relay_grab, "check": g.features_skyfall_test._ft_sf_c_relay_grab},
			{"name": "FT-SF-RELAY-BANK", "wait": 0.5, "setup": g.features_skyfall_test._ft_sf_s_relay_bank, "check": g.features_skyfall_test._ft_sf_c_relay_bank},
			{"name": "FT-SF-CHECKPOINT-UP", "wait": 0.5, "setup": g.features_skyfall_test._ft_sf_s_cp_up, "check": g.features_skyfall_test._ft_sf_c_cp_up},
			{"name": "FT-SF-CHECKPOINT-DOWN", "wait": 0.5, "setup": g.features_skyfall_test._ft_sf_s_cp_down, "check": g.features_skyfall_test._ft_sf_c_cp_down},
			{"name": "FT-SF-DIE-L6-SETUP", "wait": 0.5, "setup": g.features_skyfall_test._ft_sf_s_die_l6_setup, "check": g.features_skyfall_test._ft_sf_c_die_l6_setup},
			{"name": "FT-SF-DIE-L6", "wait": 4.5, "setup": g.features_skyfall_test._ft_sf_s_die_l6, "check": g.features_skyfall_test._ft_sf_c_die_l6},
			{"name": "FT-SF-POWERUP-SLOTS", "wait": 0.3, "setup": g.features_skyfall_test._ft_sf_s_slots, "check": g.features_skyfall_test._ft_sf_c_slots},
			{"name": "FT-SF-POWERUP-ACTIVE", "wait": 0.3, "setup": g.features_skyfall_test._ft_sf_s_active, "check": g.features_skyfall_test._ft_sf_c_active},
			{"name": "FT-SF-SLOT-BTNS", "wait": 0.3, "setup": g.features_skyfall_test._ft_sf_s_slot_btns, "check": g.features_skyfall_test._ft_sf_c_slot_btns},
			{"name": "FT-SF-SLOT-GREY-ACTIVE", "wait": 0.3, "setup": g.features_skyfall_test._ft_sf_s_slot_grey_active, "check": g.features_skyfall_test._ft_sf_c_slot_grey_active},
			{"name": "FT-SF-SLOT-GREY-CARRIER", "wait": 0.3, "setup": g.features_skyfall_test._ft_sf_s_slot_grey_carrier, "check": g.features_skyfall_test._ft_sf_c_slot_grey_carrier},
			{"name": "FT-SF-OPP-CARRIER-CTRL", "wait": 0.3, "setup": g.features_skyfall_test._ft_sf_s_carrier_ctrl, "check": g.features_skyfall_test._ft_sf_c_carrier_ctrl},
			{"name": "FT-SF-OPP-CARRIER", "wait": 0.3, "setup": g.features_skyfall_test._ft_sf_s_carrier, "check": g.features_skyfall_test._ft_sf_c_carrier},
			{"name": "FT-SF-SLOT-TAP", "wait": 0.3, "setup": g.features_skyfall_test._ft_sf_s_slot_tap, "check": g.features_skyfall_test._ft_sf_c_slot_tap},
			{"name": "FT-SF-PATH-8", "wait": 1.0, "setup": g.features_skyfall_test._ft_sf_s_path8, "check": g.features_skyfall_test._ft_sf_c_path},
			{"name": "FT-SF-PATH-9", "wait": 1.0, "setup": g.features_skyfall_test._ft_sf_s_path9, "check": g.features_skyfall_test._ft_sf_c_path},
			{"name": "FT-SF-PATH-10", "wait": 1.0, "setup": g.features_skyfall_test._ft_sf_s_path10, "check": g.features_skyfall_test._ft_sf_c_path},
			{"name": "FT-SF-PATH-11", "wait": 1.0, "setup": g.features_skyfall_test._ft_sf_s_path11, "check": g.features_skyfall_test._ft_sf_c_path},
			{"name": "FT-SF-PATH-12", "wait": 1.0, "setup": g.features_skyfall_test._ft_sf_s_path12, "check": g.features_skyfall_test._ft_sf_c_path},
			{"name": "FT-SF-PATH-13", "wait": 1.0, "setup": g.features_skyfall_test._ft_sf_s_path13, "check": g.features_skyfall_test._ft_sf_c_path},
			{"name": "FT-SF-OPP-SHIELD-STORM", "wait": 1.0, "setup": g.features_skyfall_traps._ft_sf_s_shield_storm, "check": g.features_skyfall_traps._ft_sf_c_shield_storm},
			{"name": "FT-SF-COMEBACK", "wait": 6.0, "setup": g.features_skyfall_traps._ft_sf_s_comeback, "check": g.features_skyfall_traps._ft_sf_c_comeback},
			{"name": "FT-SF-EVENT", "wait": 1.0, "setup": g.features_skyfall_traps._ft_sf_s_event, "check": g.features_skyfall_traps._ft_sf_c_event},
		{"name": "FT-SF-EVENT-BEACON", "wait": 0.5, "setup": g.features_skyfall_traps._ft_sf_s_event_beacon, "check": g.features_skyfall_traps._ft_sf_c_event_beacon},
			{"name": "FT-SF-STORM", "wait": 1.0, "setup": g.features_skyfall_traps._ft_sf_s_storm, "check": g.features_skyfall_traps._ft_sf_c_storm},
			{"name": "FT-SF-COMBO-EVENT-STORM", "wait": 1.0, "setup": g.features_skyfall_traps._ft_sf_s_combo_event_storm, "check": g.features_skyfall_traps._ft_sf_c_combo_event_storm},
			{"name": "FT-SF-COMBO-TRAP", "wait": 2.0, "setup": g.features_skyfall_traps._ft_sf_s_combo_trap, "check": g.features_skyfall_traps._ft_sf_c_combo_trap},
			{"name": "FT-SF-LEVELS", "wait": 0.2, "setup": g.fire_test._ft_s_noop, "check": g.features_skyfall_test._ft_sf_c_levels},
			{"name": "FT-SF-HAZARD-LAVA", "wait": 2.0, "setup": g.features_skyfall_traps._ft_sf_s_hazard_lava, "check": g.features_skyfall_traps._ft_sf_c_hazard_lava},
			{"name": "FT-SF-LIGHTNING", "wait": 2.0, "setup": g.features_skyfall_traps._ft_sf_s_lightning, "check": g.features_skyfall_traps._ft_sf_c_lightning},
			{"name": "FT-SF-HEIGHTBAR", "wait": 0.3, "setup": g.features_skyfall_test._ft_sf_s_heightbar, "check": g.features_skyfall_test._ft_sf_c_heightbar},
			{"name": "FT-SF-INVIS-WARN", "wait": 0.3, "setup": g.features_skyfall_test._ft_sf_s_invis_warn, "check": g.features_skyfall_test._ft_sf_c_invis_warn},
			{"name": "FT-SF-INVIS-CLEAR", "wait": 0.3, "setup": g.features_skyfall_test._ft_sf_s_invis_clear, "check": g.features_skyfall_test._ft_sf_c_invis_clear},
			{"name": "FT-SF-PING", "wait": 0.3, "setup": g.features_skyfall_test._ft_sf_s_ping, "check": g.features_skyfall_test._ft_sf_c_ping},
			{"name": "FT-SF-ROUTES", "wait": 0.2, "setup": g.fire_test._ft_s_noop, "check": g.features_skyfall_test._ft_sf_c_routes},
			{"name": "FT-SF-SCENERY", "wait": 1.0, "setup": g.features_skyfall_test._ft_sf_s_scenery, "check": g.features_skyfall_test._ft_sf_c_scenery},
			{"name": "FT-SF-RARITY", "wait": 0.2, "setup": g.features_skyfall_test._ft_sf_s_rarity, "check": g.features_skyfall_test._ft_sf_c_rarity},
			{"name": "FT-SF-5V5", "wait": 0.5, "setup": g.features_skyfall_test._ft_sf_s_5v5, "check": g.features_skyfall_test._ft_sf_c_5v5},
			{"name": "FT-SF-MOVER-CLEAR", "wait": 0.5, "setup": g.features_skyfall_test._ft_sf_s_noop, "check": g.features_skyfall_test._ft_sf_c_mover_clear},
			{"name": "FT-SF-WIND-NO-TARGET", "wait": 1.0, "setup": g.features_skyfall_test._ft_sf_s_wind_no_target, "check": g.features_skyfall_test._ft_sf_c_wind_no_target},
			{"name": "FT-SF-WIND-THROW", "wait": 1.5, "setup": g.features_skyfall_test._ft_sf_s_wind_throw, "check": g.features_skyfall_test._ft_sf_c_wind_throw},
			{"name": "FT-SF-THUNDER-NO-TARGET", "wait": 1.0, "setup": g.features_skyfall_test._ft_sf_s_thunder_no_target, "check": g.features_skyfall_test._ft_sf_c_thunder_no_target},
			{"name": "FT-SF-THUNDER-SHIELD", "wait": 1.0, "setup": g.features_skyfall_test._ft_sf_s_thunder_shield, "check": g.features_skyfall_test._ft_sf_c_thunder_shield},
			{"name": "FT-SF-WIND-HEIGHT", "wait": 1.0, "setup": g.features_skyfall_test._ft_sf_s_wind_height, "check": g.features_skyfall_test._ft_sf_c_wind_height},
			{"name": "FT-SF-THUNDER-HEIGHT", "wait": 1.0, "setup": g.features_skyfall_test._ft_sf_s_thunder_height, "check": g.features_skyfall_test._ft_sf_c_thunder_height},
			{"name": "FT-SF-PU-SEAM", "wait": 0.5, "setup": g.features_skyfall_test._ft_sf_s_pu_seam, "check": g.features_skyfall_test._ft_sf_c_pu_seam},
			{"name": "FT-SF-PU-MOVER", "wait": 0.5, "setup": g.features_skyfall_test._ft_sf_s_pu_mover, "check": g.features_skyfall_test._ft_sf_c_pu_mover},
			{"name": "FT-SF-THUNDER-STILL", "wait": 0.5, "setup": g.features_skyfall_test._ft_sf_s_thunder_still, "check": g.features_skyfall_test._ft_sf_c_thunder_still},
			{"name": "FT-SF-THUNDER-STILL-L3", "wait": 0.5, "setup": g.features_skyfall_test._ft_sf_s_thunder_still_l3, "check": g.features_skyfall_test._ft_sf_c_thunder_still_l3},
			{"name": "FT-SF-THUNDER-SAME-L3", "wait": 0.5, "setup": g.features_skyfall_test._ft_sf_s_thunder_same_l3, "check": g.features_skyfall_test._ft_sf_c_thunder_same_l3},
			{"name": "FT-SF-THUNDER-TRAP-L5", "wait": 1.5, "setup": g.features_skyfall_test._ft_sf_s_thunder_trap_l5, "check": g.features_skyfall_test._ft_sf_c_thunder_trap_l5},
			{"name": "FT-SF-TRAP-ROCKS", "wait": 1.0, "setup": g.features_skyfall_traps._ft_sf_s_trap_rocks, "check": g.features_skyfall_traps._ft_sf_c_trap_rocks},
			{"name": "FT-SF-TRAP-TRAPDOOR-L2", "wait": 1.5, "setup": g.features_skyfall_traps._ft_sf_s_trap_trapdoor_l2, "check": g.features_skyfall_traps._ft_sf_c_trap_trapdoor_l2},
			{"name": "FT-SF-TRAP-LAVA2", "wait": 1.0, "setup": g.features_skyfall_traps._ft_sf_s_trap_lava2, "check": g.features_skyfall_traps._ft_sf_c_trap_lava2},
			{"name": "FT-SF-TRAP-LIGHTNING-L4", "wait": 1.5, "setup": g.features_skyfall_traps._ft_sf_s_trap_lightning_l4, "check": g.features_skyfall_traps._ft_sf_c_trap_lightning_l4},
			{"name": "FT-SF-TRAP-COLLAPSE-L6", "wait": 1.0, "setup": g.features_skyfall_traps._ft_sf_s_trap_collapse_l6, "check": g.features_skyfall_traps._ft_sf_c_trap_collapse_l6},
			{"name": "FT-SF-TRAP-WIND-L3", "wait": 1.0, "setup": g.features_skyfall_traps._ft_sf_s_trap_wind_l3, "check": g.features_skyfall_traps._ft_sf_c_trap_wind_l3},
			{"name": "FT-SF-TRAP-PENDULUM", "wait": 1.0, "setup": g.features_skyfall_traps._ft_sf_s_trap_pendulum, "check": g.features_skyfall_traps._ft_sf_c_trap_pendulum},
		{"name": "FT-SF-TRAP-MINE", "wait": 1.5, "setup": g.features_skyfall_traps._ft_sf_s_trap_mine, "check": g.features_skyfall_traps._ft_sf_c_trap_mine},
			{"name": "FT-SF-WIND-SHOT", "wait": 0.5, "setup": g.features_skyfall_test._ft_sf_s_wind_shot, "check": g.features_skyfall_test._ft_sf_c_wind_shot},
		]


func _ft_s_release_all() -> void:
	g.fire_test._ft_release_move()
	g.fire_test._ft_release_aim()
	g.fire_test._ft_release_fire()


func _ft_s_countdown() -> void:
	# Drive the countdown ourselves (it is off in test modes).
	g._countdown_active = true
	g._countdown_t = 3.0
	g._countdown_last_shown = -1
	# Hold every control: nothing may move, aim or fire until FIGHT.
	g.fire_test._ft_press_move(Vector2(60, 0))
	g.fire_test._ft_press_aim(Vector2(60, 0))
	g.fire_test._ft_press_fire()


func _ft_c_countdown() -> Array:
	var frozen: bool = g.touch_move_vec == Vector2.ZERO and g.touch_aim == Vector2.ZERO and not g.touch_firing
	var shown: bool = g._countdown_label.visible and g._countdown_label.text == "3"
	var sub: bool = g._countdown_sub.visible and g._countdown_sub.text.contains("First to")
	var ok: bool = frozen and shown and sub
	return [ok, "frozen=%s label=%s/%s sub=%s" % [frozen, g._countdown_label.text, g._countdown_label.visible, g._countdown_sub.text]]


func _ft_c_countdown_end() -> Array:
	var ok: bool = not g._countdown_active and g._countdown_label.visible and g._countdown_label.text == "FIGHT!"
	return [ok, "countdown_active=%s label=%s" % [g._countdown_active, g._countdown_label.text]]


func _ft_s_killfeed() -> void:
	var lp = g._get_local_player()
	_ft_s_release_all()
	g.fire_test._ft_set_weapon(5) # pistol: 10 dmg, one lethal shot vs 5 HP
	lp.position = Vector2(300, 1318) # QA-071: floor 1352, centre top-34
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	var b = g.players_node.get_node_or_null("99")
	if b == null:
		g._do_spawn(99, "TestBot", 0, 0)
		b = g.players_node.get_node_or_null("99")
	_feat_bot = b
	if b != null:
		b.position = Vector2(600, 1318) # QA-071: floor 1352, centre top-34
		b.sync_position = b.position
		b.velocity = Vector2.ZERO
		b.health = 5
		b._spawn_protect_timer = 0.0
	lp._spawn_protect_timer = 0.0
	g.fire_test._ft_press_aim(Vector2(60, 0))
	g.fire_test._ft_press_fire()


func _ft_c_killfeed() -> Array:
	var lp = g._get_local_player()
	g.fire_test._ft_release_aim()
	g.fire_test._ft_release_fire()
	var feed_text := ""
	for e in g._kill_feed_entries:
		feed_text += String((e["label"] as Label).text) + "|"
	var feed_ok: bool = feed_text.contains("TestBot") and feed_text.contains("Pistol")
	var hit_ok: bool = lp._hitmark_seq >= 1 and lp._shots_hit >= 1
	var kill_ok: bool = lp.kills >= 1
	var streak_ok: bool = int(g._best_streaks.get(1, 0)) >= 1
	var ok: bool = feed_ok and hit_ok and kill_ok and streak_ok
	return [ok, "feed='%s' hitmark_seq=%d shots_hit=%d kills=%d best_streak=%d" % [feed_text, lp._hitmark_seq, lp._shots_hit, lp.kills, int(g._best_streaks.get(1, 0))]]


func _ft_s_streaks() -> void:
	# QA-145 (v4.1, Worker T): First Blood + multi-kill callouts.
	# Reset the streak state (the KILLFEED step just left the local
	# player on a 1-kill streak), then announce two kills by the
	# local player on the TestBot through announce_kill — the real
	# feed path (a direct call has sender 0, so it passes the
	# host-only guard, exactly as the real RPC does on the host).
	var lp = g._get_local_player()
	g._kill_streaks.clear()
	g._best_streaks.clear()
	g._first_blood_done = false
	var kid := int(lp.peer_id)
	g.game_feed.announce_kill(kid, 99, 5)
	g.game_feed.announce_kill(kid, 99, 5)


func _ft_c_streaks() -> Array:
	var feed_text := ""
	for e in g._kill_feed_entries:
		feed_text += String((e["label"] as Label).text) + "|"
	var ok: bool = feed_text.contains("FIRST BLOOD") and feed_text.contains("DOUBLE KILL") and bool(g._first_blood_done) and int(g._kill_streaks.get(1, 0)) == 2
	return [ok, "feed='%s' first_blood=%s streak=%d" % [feed_text, str(bool(g._first_blood_done)), int(g._kill_streaks.get(1, 0))]]


func _ft_s_endstats() -> void:
	# Fake final rows: Player 5/2 with 20 shots 12 hits (K/D 2.50,
	# 60% accuracy), TestBot 3/5 with 10 shots 2 hits (K/D 0.60, 20%).
	var rows := [
		{"name": "Player", "kills": 5, "deaths": 2, "team": -1, "color": Color(1, 0, 0), "rounds": 0, "shots": 20, "hits": 12, "streak": 3},
		{"name": "TestBot", "kills": 3, "deaths": 5, "team": -1, "color": Color(0, 0, 1), "rounds": 0, "shots": 10, "hits": 2, "streak": 1},
	]
	g.show_end_screen("Player", "reached 10 kills!", rows)


func _ft_collect_label_texts(list: VBoxContainer) -> Array:
	# QA-113 (v3.9): the stats redesign puts rows in HBoxContainers
	# with one Label per column — collect every Label's text, direct
	# children and one level inside row boxes.
	var out: Array = []
	for c in list.get_children():
		if c is Label:
			out.append(String(c.text))
		elif c is HBoxContainer:
			for sub in c.get_children():
				if sub is Label:
					out.append(String(sub.text))
	return out


func _ft_c_endstats() -> Array:
	var mvp_ok := false
	for n in g._mvp_nodes:
		if n is HBoxContainer:
			for c in n.get_children():
				if c is Label and String(c.text).contains("MVP: Player") and String(c.text).contains("60%"):
					mvp_ok = true
	# QA-113: rows are column HBoxes now — a row holds the K/D cell
	# ("2.50") and the ACC cell ("60%") as separate Labels.
	var row_ok := false
	for c in g.end_list.get_children():
		if c is HBoxContainer:
			var has_kd := false
			var has_acc := false
			for sub in c.get_children():
				if sub is Label and String(sub.text) == "2.50":
					has_kd = true
				if sub is Label and String(sub.text) == "60%":
					has_acc = true
			if has_kd and has_acc:
				row_ok = true
	var stats_ok := false
	var st: Dictionary = GameData.compute_stats(10, 4, 20, 12)
	stats_ok = absf(float(st["kd"]) - 2.5) < 0.01 and absf(float(st["accuracy"]) - 60.0) < 0.01
	var st2: Dictionary = GameData.compute_stats(7, 0, 0, 0)
	stats_ok = stats_ok and absf(float(st2["kd"]) - 7.0) < 0.01 and float(st2["accuracy"]) == 0.0
	var ok: bool = g.end_panel.visible and mvp_ok and row_ok and stats_ok
	# The match is not really over: put the panel away and resume.
	var was_visible: bool = g.end_panel.visible
	g.end_panel.visible = false
	g.match_over = false
	return [ok, "end_visible=%s mvp=%s row=%s stats=%s" % [was_visible, mvp_ok, row_ok, stats_ok]]


func _ft_s_settings() -> void:
	# Stash the real settings, then write distinctive test values.
	_feat_data = {
		"sfx": GameData.sfx_volume, "music": GameData.music_volume,
		"enabled": GameData.music_enabled, "sens": GameData.sensitivity,
		"fps": GameData.show_fps, "invert": GameData.invert_aim,
	}
	GameData.sfx_volume = 0.44
	GameData.music_volume = 0.33
	GameData.music_enabled = false
	GameData.sensitivity = 1.5
	GameData.show_fps = true
	GameData.invert_aim = true
	GameData.save_settings()


func _ft_c_settings() -> Array:
	# Wipe the values in memory, reload from disk, compare.
	GameData.sfx_volume = 0.9
	GameData.music_volume = 0.9
	GameData.music_enabled = true
	GameData.sensitivity = 0.9
	GameData.show_fps = false
	GameData.invert_aim = false
	GameData.load_settings()
	var ok: bool = absf(GameData.sfx_volume - 0.44) < 0.01 and absf(GameData.music_volume - 0.33) < 0.01 and GameData.music_enabled == false and absf(GameData.sensitivity - 1.5) < 0.01 and GameData.show_fps == true and GameData.invert_aim == true
	var fps_ok: bool = g.fps_label.visible
	# Restore the player's real settings.
	GameData.sfx_volume = float(_feat_data["sfx"])
	GameData.music_volume = float(_feat_data["music"])
	GameData.music_enabled = bool(_feat_data["enabled"])
	GameData.sensitivity = float(_feat_data["sens"])
	GameData.show_fps = bool(_feat_data["fps"])
	GameData.invert_aim = bool(_feat_data["invert"])
	GameData.save_settings()
	ok = ok and fps_ok
	return [ok, "persist_ok=%s fps_label_visible=%s (restored real settings)" % [ok, fps_ok]]


func _ft_c_mapvote() -> Array:
	var cands := [0, 1, 2]
	var w1: int = GameData.tally_map_vote({2: 0, 3: 1, 4: 1}, cands, 0)
	var w2: int = GameData.tally_map_vote({2: 0, 3: 1}, cands, 0)
	var w3: int = GameData.tally_map_vote({}, cands, 2)
	var w4: int = GameData.tally_map_vote({2: 5}, cands, 0) # vote for a map not on the ballot: ignored
	var map_ok: bool = g.MAPS[w1].has("size") and g.MAPS[w1].has("spawns") and int(g.MAPS[w1]["spawns"].size()) == 12
	var ok: bool = w1 == 1 and w2 == 0 and w3 == 2 and w4 == 0 and map_ok
	return [ok, "tally 2-1=%d tie=%d none=%d off-ballot=%d voted_map=%s spawns=%d" % [w1, w2, w3, w4, GameData.MAP_NAMES[w1], int(g.MAPS[w1]["spawns"].size())]]


func _ft_s_pickups() -> void:
	var lp = g._get_local_player()
	lp.health = 40
	lp.grenades = 0
	# A real health pickup on a real spot (kind 5, Sky Brawl icon).
	g._spawn_pickup_at(0, 5)


func _ft_c_pickups() -> Array:
	var lp = g._get_local_player()
	lp.give_pickup(5)
	var health_ok: bool = lp.health == 90
	lp.give_pickup(6)
	var gren_ok: bool = lp.grenades == 2
	var node_ok := false
	var icon_ok := false
	for c in g.pickups_node.get_children():
		if int(c.kind) == 5:
			node_ok = true
			for sub in c.get_children():
				if sub is Sprite2D and (sub as Sprite2D).texture != null:
					icon_ok = true
			c.queue_free()
	var ok: bool = health_ok and gren_ok and node_ok and icon_ok
	return [ok, "health 40->%d grenades 0->%d pickup_node=%s icon=%s" % [lp.health, lp.grenades, node_ok, icon_ok]]


func _ft_s_music() -> void:
	g.audio.play_battle_music()


func _ft_c_music() -> Array:
	var battle_ok: bool = g.audio.current_track() == "battle" and g.audio.is_music_playing()
	var battle_stream_ok: bool = g.audio._music_player.stream == g.audio.BATTLE_TRACK
	var menu_loop_ok: bool = g.audio.MENU_TRACK.loop == true
	g.audio.play_menu_music()
	var menu_ok: bool = g.audio.current_track() == "menu" and g.audio.is_music_playing()
	g.audio.set_music_enabled(false)
	var off_ok: bool = not g.audio.is_music_playing()
	g.audio.set_music_enabled(true)
	var back_ok: bool = g.audio.current_track() == "menu" and g.audio.is_music_playing()
	var credits_ok: bool = GameData.MUSIC_CREDITS.contains("\"At Rest\"") and GameData.MUSIC_CREDITS.contains("\"Five Armies\"") and GameData.MUSIC_CREDITS.contains("creativecommons.org/licenses/by/4.0")
	g.audio.stop_music()
	var stop_ok: bool = not g.audio.is_music_playing() and g.audio.current_track() == ""
	# Leave the match music playing again for the steps after this one.
	g.audio.play_battle_music()
	var ok: bool = battle_ok and battle_stream_ok and menu_loop_ok and menu_ok and off_ok and back_ok and credits_ok and stop_ok
	return [ok, "battle=%s stream=%s menu_loop=%s menu=%s off=%s back=%s credits=%s stop=%s" % [battle_ok, battle_stream_ok, menu_loop_ok, menu_ok, off_ok, back_ok, credits_ok, stop_ok]]


func _ft_s_spectator() -> void:
	g.game_mode = 3 # Last Man Standing: no respawn, spectator applies
	var b = _feat_bot
	if b == null or not is_instance_valid(b):
		b = g.players_node.get_node_or_null("99")
	if b != null and not b.alive:
		b._respawn()
		b.position = Vector2(600, 1318) # QA-071: floor 1352, centre top-34
		b.sync_position = b.position
	# A second living player: with only one alive, LMS would end the
	# match the moment the local player "dies" (alive_count <= 1),
	# which is exactly what spectator mode must outlive.
	var b2 = g.players_node.get_node_or_null("98")
	if b2 == null:
		g._do_spawn(98, "TestBot2", 1, 0)
		b2 = g.players_node.get_node_or_null("98")
	if b2 != null and not b2.alive:
		b2._respawn()
		b2.position = Vector2(900, 1318) # QA-071: floor 1352, centre top-34
		b2.sync_position = b2.position
	var lp = g._get_local_player()
	lp.alive = false
	lp._respawn_timer = 30.0 # do not auto-respawn during the check


func _ft_c_spectator() -> Array:
	var ok: bool = g._spectating and g._spectate_cam.enabled and g._spectate_label.visible and g._spectate_target != null and String(g._spectate_target.player_name) == "TestBot"
	# Capture the diagnostic BEFORE cleanup clears it all.
	var detail = "spectating=%s cam=%s target=%s label=%s" % [g._spectating, g._spectate_cam.enabled, String(g._spectate_target.player_name) if g._spectate_target != null else "none", g._spectate_label.visible]
	var lp = g._get_local_player()
	lp._respawn()
	g.game_mode = 0
	g._stop_spectating()
	# Remove the second bot again (it only existed to keep LMS alive).
	var b2 = g.players_node.get_node_or_null("98")
	if b2 != null:
		b2.queue_free()
		g._spawned.erase(98)
	return [ok, detail]


func _ft_s_scoreboard() -> void:
	g._update_scoreboard_rows(g.scoreboard_list)
	g.scoreboard_panel.visible = true


func _ft_c_scoreboard() -> Array:
	# QA-113: the header row holds "K/D" and "ACC" as separate
	# column Labels, and the self row holds "(YOU)" in its name
	# cell — collect all Label texts (direct + inside row HBoxes).
	var texts: Array = _ft_collect_label_texts(g.scoreboard_list)
	var kd_ok := "K/D" in texts and "ACC" in texts
	var self_ok := false
	for t in texts:
		if String(t).contains("(YOU)"):
			self_ok = true
	var team_ok := false # TDM totals header: must be found below
	# TDM totals header: flip the mode, rebuild, check, restore.
	g.game_mode = 1
	g._update_scoreboard_rows(g.scoreboard_list)
	for t in _ft_collect_label_texts(g.scoreboard_list):
		if String(t).contains("RED") and String(t).contains("BLUE"):
			team_ok = true
	g.game_mode = 0
	g._update_scoreboard_rows(g.scoreboard_list)
	g.scoreboard_panel.visible = false
	var ok: bool = kd_ok and self_ok and team_ok
	return [ok, "kd_col=%s self=%s tdm_totals=%s" % [kd_ok, self_ok, team_ok]]


func _ft_s_firelayout() -> void:
	# v3.2: the layout is fixed (move left, aim right, no mirror) —
	# presses must still land on the stick whose half they fall in.
	g._on_touch_press(920, g.fire_test._ft_move_center())
	g._on_touch_press(921, g.fire_test._ft_aim_center())


func _ft_c_firelayout() -> Array:
	var move_ok: bool = g.move_stick.is_active()
	var aim_ok: bool = g.aim_stick.is_active()
	g._on_touch_release(920)
	g._on_touch_release(921)
	var ok: bool = move_ok and aim_ok
	return [ok, "move_stick=%s aim_stick=%s (fixed layout, no FIRE button)" % [move_ok, aim_ok]]


# QA-079: HUD readouts — the K/D line is filled, the ammo line
# shows mag/reserve, the HP bar is green at full health.
func _ft_c_hud() -> Array:
	var lp = g._get_local_player()
	var kd_ok: bool = g._kd_label != null and String(g._kd_label.text).begins_with("K ") and "• D " in String(g._kd_label.text)
	var ammo_ok: bool = "/" in g.weapon_label.text
	var hp_ok: bool = g.hp_bar.ink == g.UI_SUCCESS
	return [kd_ok and ammo_ok and hp_ok, "kd='%s' ammo='%s' hp_ink_green=%s" % [g._kd_label.text if g._kd_label != null else "?", g.weapon_label.text, hp_ok]]


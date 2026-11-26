class_name GameTouch
extends RefCounted


# QA-140 (v3.15): extracted from game.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `g` (dependency injection).


var g # the owner (game.gd)


func _init(owner) -> void:
	g = owner


func _on_reload_pressed() -> void:
	var lp = g.game_hud._get_local_player()
	if lp != null:
		lp.start_reload()


func _on_score_pressed() -> void:
	g.game_hud._update_scoreboard_rows(g.scoreboard_list)
	g.scoreboard_panel.visible = not g.scoreboard_panel.visible
	# QA-035: same as pause/end — the sticks and buttons draw over
	# the scoreboard while it is open. Reset any held touch first so
	# a hidden aim stick cannot keep firing (QA-016 rule).
	if g.scoreboard_panel.visible:
		_reset_all_touch_state()
	_set_touch_controls_visible(not g.scoreboard_panel.visible)


func _on_grenade_pressed() -> void:
	var lp = g.game_hud._get_local_player()
	if lp != null:
		lp.throw_grenade()


# QA-070: grenade button state, refreshed every HUD frame from the
# local player. Simple button, no loading visuals — disabled only
# when the count is 0 (standard Button disabled look). The count is
# the plain "Grenades: N" text in the top-right HUD. Throw
# behaviour is untouched — player.gd still owns the 0.5 s cooldown
# and the count.
func _update_grenade_button(lp) -> void:
	if g.grenade_button == null or lp == null:
		return
	g.grenade_button.disabled = int(lp.grenades) <= 0
	# QA-137: the button is icon-only now (the kit's grenade icon);
	# the count rides in the top-right ammo line (grenades_label),
	# so no text is set here any more.


# QA-070 (v3.6): simple button, no loading visuals. Disabled
# while reloading or when the mag is already full — same rule as
# the old rectangular button.
func _update_reload_button(lp) -> void:
	if g.reload_button == null or lp == null:
		return
	var mag_total: int = int(lp.WEAPONS[lp.weapon]["mag"])
	g.reload_button.disabled = lp.reloading or lp.mag_ammo >= mag_total


# QA-143: scoping removed - this used to be _update_scope_button;
# now it only refreshes the PING button state every HUD frame.
# QA-114 (v3.9): PING is for living players in Skyfall team modes.
func _update_ping_button(lp) -> void:
	# QA-113 (v3.9): never over a dialog — the button drew over the
	# pause/scoreboard/end panels. _set_touch_controls_visible
	# hides it, but this runs every frame and would show it again.
	var dialog_open = g.get_tree().paused or (g.scoreboard_panel != null and g.scoreboard_panel.visible) or (g.end_panel != null and g.end_panel.visible)
	if g.ping_button != null:
		var team_mode: bool = g.game_mode in [1, 4]
		var assigned_team: bool = lp != null and int(lp.team) in [0, 1]
		g.ping_button.visible = g.map_id == GameData.SKYFALL_MAP_ID and team_mode and assigned_team and lp.alive and not g.match_over and not dialog_open


func _on_switch_pressed() -> void:
	var lp = g.game_hud._get_local_player()
	if lp != null:
		lp.switch_weapon()


func _on_ping_pressed() -> void:
	# QA-114 (v3.9): ping the local player's position for their
	# team in Skyfall TDM/CTF, with a 3 s cooldown.
	if g.map_id != GameData.SKYFALL_MAP_ID or g.game_mode not in [1, 4] or g.match_over or g._countdown_active:
		return
	var lp = g.game_hud._get_local_player()
	if lp == null or not lp.alive or int(lp.team) not in [0, 1]:
		return
	if g._sf_ping_cooldown > 0.0:
		return
	g._sf_ping_cooldown = 3.0
	var team := int(lp.team) if "team" in lp else -1
	g.rpc("ping_remote", lp.position, team, lp.player_name)


func ping_remote(pos: Vector2, team: int, pname: String) -> void:
	# A teammate's ping: a gold diamond in the world + a dot on the
	# height bar + a feed line, for 5 s. Enemy pings are never
	# shown (a ping only ever reaches its own team).
	if g.map_id != GameData.SKYFALL_MAP_ID or g.game_mode not in [1, 4]:
		return
	var lp = g.game_hud._get_local_player()
	if lp == null or team < 0 or int(lp.team) not in [0, 1]:
		return
	var my_team := int(lp.team) if "team" in lp else -1
	if team != my_team:
		return
	var lvl = g._sf_level_of(pos.y)
	var diamond := Polygon2D.new()
	diamond.polygon = PackedVector2Array([Vector2(0, -22), Vector2(16, 0), Vector2(0, 22), Vector2(-16, 0)])
	diamond.color = Color(1.0, 0.8, 0.2)
	diamond.position = pos + Vector2(0, -90)
	diamond.z_index = 50
	g.add_child(diamond)
	var plbl := Label.new()
	plbl.text = "⚑ %s (L%d)" % [pname, lvl]
	plbl.position = pos + Vector2(-60, -130)
	plbl.add_theme_font_size_override("font_size", 20)
	plbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	plbl.z_index = 50
	g.add_child(plbl)
	g._sf_pings.append({"node": diamond, "label": plbl, "pos": pos, "timer": 5.0})
	g._ctf_feed("⚑ %s pinged Level %d!" % [pname, lvl], Color(1.0, 0.8, 0.2))


# v2.4 (QA-023): game touches go through _unhandled_input, NOT
# _input. GUI Buttons (GRENADE / WEAPON / RELOAD / pause / score, and
# the pause/scoreboard/end panels) consume their touches first, so a
# tap on one of them can never reach the sticks — the old _input path
# grabbed every touch before the GUI saw it, and the only protection
# was a rect check that compared the event's viewport-pixel position
# against canvas-space button rects (wrong under stretch mode), so a
# GRENADE/WEAPON tap fell through to the aim stick and the gun fired.
# The rect checks below are only a belt-and-braces fallback, and they
# compare in canvas space (see _to_canvas_pos).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		# Touch events arrive in viewport-pixel coordinates; the HUD
		# rects are in canvas (logical) coordinates. Convert once,
		# here, at the boundary — everything downstream is canvas.
		var cpos := _to_canvas_pos(e.position)
		if e.pressed:
			_on_touch_press(e.index, cpos)
		else:
			_on_touch_release(e.index)
	elif event is InputEventScreenDrag:
		var e := event as InputEventScreenDrag
		_on_touch_drag(e.index, _to_canvas_pos(e.position))
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			_toggle_pause()
		# QA-073: F3 toggles the dev-only net-stats panel (spec §7).
		# No other key touches it, and it is hidden by default.
		elif k.pressed and not k.echo and k.keycode == KEY_F3:
			g.game_hud.toggle_net_stats()


# QA-029: the viewport's canvas transform carries the CAMERA offset
# (the camera follows the player, so its origin is far from (0,0) once
# the player leaves the spawn), but the HUD CanvasLayer does NOT follow
# the camera. Converting a touch with get_canvas_transform() therefore
# shifted every touch by the camera displacement — a touch on a stick's
# exact centre landed ~680 px below it, so the knob slammed to the
# bottom and the vector pointed straight down on every touch, at every
# resolution (even 1280x720, scale 1). The HUD layer's own transform
# is the correct converter for HUD touches: it has no camera term.
func _to_canvas_pos(viewport_pos: Vector2) -> Vector2:
	return g.hud.get_final_transform().affine_inverse() * viewport_pos


# Canvas position -> viewport position (for tests that simulate a real
# touch at a control's on-screen location). Inverse of _to_canvas_pos.
func _to_viewport_pos(canvas_pos: Vector2) -> Vector2:
	return g.hud.get_final_transform() * canvas_pos


# True when a viewport point is on any HUD control. Uses each control's
# own global transform with canvas (the ground truth for its on-screen
# position), never a shared rect in a possibly different space.
# Used by the player's mouse fallback (desktop testing) and by the
# touch router.
func is_hud_control_pos(viewport_pos: Vector2) -> bool:
	for c in [g.grenade_button, g.switch_button, g.reload_button, g.pause_button, g.score_button]:
		if c == null:
			continue
		var ctrl := c as Control
		var local := ctrl.get_global_transform_with_canvas().affine_inverse() * viewport_pos
		if Rect2(Vector2.ZERO, ctrl.size).has_point(local):
			return true
	return false


func _reset_all_touch_state() -> void:
	g._move_touch_id = -1
	g._aim_touch_id = -1
	g._last_touch_msec = Time.get_ticks_msec()
	if g.move_stick != null:
		g.move_stick.reset_input()
	if g.aim_stick != null:
		g.aim_stick.reset_input()
	g.touch_move_vec = Vector2.ZERO
	g.touch_aim = Vector2.ZERO
	g.touch_aim_active = false
	g.touch_firing = false
	g._aim_fire_pending = false
	g._aim_vec_prev_nonzero = false


# QA-054: true while a stick is held, or within 500 ms of the last
# touch press/release. The player's mouse-aim fallback consults this
# so a touch can never be mistaken for a mouse click.
func touch_recently_used() -> bool:
	if g._move_touch_id != -1 or g._aim_touch_id != -1:
		return true
	return Time.get_ticks_msec() - g._last_touch_msec < 500


# QA-035: hide/show the gameplay touch cluster (sticks,
# RELOAD / GRENADE / WEAPON) when a full-screen panel opens (pause,
# scoreboard, end screen) so the controls cannot draw over the
# panel's text and buttons. The top-right SCORE / pause buttons stay
# visible — they sit outside the centred panels. Callers reset the
# touch state first (see _reset_all_touch_state) so a hidden stick
# cannot keep firing. Rematch reloads the scene, so there is
# no end-screen restore path to maintain.
func _set_touch_controls_visible(v: bool) -> void:
	for c in [g.move_stick, g.aim_stick, g.reload_button, g.grenade_button, g.switch_button]:
		if c != null:
			c.visible = v
	# QA-113 (v3.9): PING (added v3.9) was never in this list, so it
	# drew over the pause/scoreboard panels. Hide it too — but
	# never show it here: _update_hud owns its visibility (ping
	# Skyfall-only) and restores it on the next frame. (SCOPE was
	# removed in QA-143.)
	if not v:
		if g.ping_button != null:
			g.ping_button.visible = false
		for c in [g._sf_slot_panel, g._sf_active_boost_label, g._invis_warning_chip]:
			if c != null:
				c.visible = false


func _on_touch_press(index: int, pos: Vector2) -> void:
	# All positions here are canvas space (converted in _unhandled_input).
	# Order matters — check the controls first, sticks last:
	# 1. GUI buttons (belt-and-braces: _unhandled_input means the GUI
	#    already declined them, but a stray touch must never reach a
	#    stick — return without routing).
	# 2. Sticks by screen half (move left, aim right).
	g._last_touch_msec = Time.get_ticks_msec() # QA-054: mouse-aim latch
	if is_hud_control_pos(pos):
		return
	var vp = g.get_viewport().get_visible_rect().size
	if pos.x < vp.x * 0.5:
		# press_touch() refuses if the stick already has a finger, so a
		# second finger can never hijack the move stick.
		if g.move_stick.press_touch(index, pos):
			g._move_touch_id = index
	else:
		if g.aim_stick.press_touch(index, pos):
			g._aim_touch_id = index
			# QA-141: reference fires only past the stick edge (Joypad::
			# beginTouch 0x688188 — isFiring=1 when deflection >
			# radius). A press that lands already deflected to
			# >= 0.98 arms the semi-auto shot NOW (synchronously)
			# — a flick pressed and released between two _process
			# frames would otherwise never be seen by
			# _update_touch_state and the shot would be lost
			# (QA-027 carry-over).
			if g.aim_stick.get_vector().length() >= 0.98:
				g._aim_fire_pending = true
				g._aim_vec_prev_nonzero = true


func _on_touch_drag(index: int, pos: Vector2) -> void:
	if index == g._move_touch_id:
		g.move_stick.drag_touch(index, pos)
	elif index == g._aim_touch_id:
		g.aim_stick.drag_touch(index, pos)


func _on_touch_release(index: int) -> void:
	g._last_touch_msec = Time.get_ticks_msec() # QA-054: mouse-aim latch
	if index == g._move_touch_id:
		g._move_touch_id = -1
		g.move_stick.release_touch(index)
	elif index == g._aim_touch_id:
		g._aim_touch_id = -1
		g.aim_stick.release_touch(index)


func _update_touch_state() -> void:
	if g.get_tree().paused:
		g.touch_move_vec = Vector2.ZERO
		g.touch_aim = Vector2.ZERO
		g.touch_aim_active = false
		g.touch_firing = false
		g._aim_fire_pending = false
		g._aim_vec_prev_nonzero = false
		return
	# v3.2 (CONTROLS_CHANGE.md §2): get_vector() is zero unless the
	# stick has an actively held touch. QA-141: firing is true ONLY
	# while the AIM stick is deflected to >= 0.98 (reference: push past
	# the stick edge to fire, Joypad::beginTouch 0x688188) — never
	# from a partial deflection, a stale knob position or any other
	# control. Aiming itself is still any non-zero vector.
	g.touch_move_vec = g.move_stick.get_vector()
	var aim_vec = g.aim_stick.get_vector()
	# Phase 4: invert aim (settings) flips the aim stick vertically.
	if GameData.invert_aim:
		aim_vec.y = -aim_vec.y
	g.touch_aim = aim_vec
	# QA-141: reference has NO dead zone (Joypad, B §9). Any non-zero aim
	# vector counts as aiming here.
	g.touch_aim_active = aim_vec.length() > 0.0
	# Semi-auto edge (QA-027 carry-over): a fresh crossing to
	# firing-level deflection (>= 0.98) arms one pending shot, so a
	# quick flick fires even if the finger is gone by the time the
	# shooting step runs. Holding a semi-auto weapon deflected does
	# NOT re-arm (no auto-repeat). _aim_vec_prev_nonzero tracks the
	# firing-level state now (was: any non-zero vector).
	var aim_now: bool = aim_vec.length() >= 0.98
	if aim_now and not g._aim_vec_prev_nonzero:
		g._aim_fire_pending = true
	g._aim_vec_prev_nonzero = aim_now
	g.touch_firing = aim_now
	# Phase 4: during the match countdown nobody moves, aims or fires
	# — the fight starts on "FIGHT!".
	if g._countdown_active:
		g.touch_move_vec = Vector2.ZERO
		g.touch_aim = Vector2.ZERO
		g.touch_aim_active = false
		g.touch_firing = false
		g._aim_fire_pending = false
		g._aim_vec_prev_nonzero = false


# v3.2: the pending semi-auto shot (see _update_touch_state). Peeked by
# the player in _read_input, consumed when the shot fires, discarded on
# reload / respawn / weapon switch.
func has_aim_fire_edge() -> bool:
	return g._aim_fire_pending


func consume_aim_fire_edge() -> void:
	g._aim_fire_pending = false


func _toggle_pause() -> void:
	if g.match_over:
		return
	g.get_tree().paused = not g.get_tree().paused
	g.pause_panel.visible = g.get_tree().paused
	if g.get_tree().paused:
		# QA-113 (v3.9): match info line — map, mode, time left.
		if g._pause_info_label != null:
			var t = int(maxf(0.0, g._time_left))
			g._pause_info_label.text = "%s  •  %s  •  %d:%02d left" % [GameData.MAP_NAMES[g.map_id], GameData.MODE_NAMES[g.game_mode], t / 60, t % 60]
		# A finger held on the aim stick while pausing must not resume firing
		# on unpause from a stale touch (QA-016 rule).
		_reset_all_touch_state()
	# QA-035: the touch controls stay on top of the pause panel
	# otherwise (same overlap as the end screen) — hide while
	# paused, restore on resume.
	_set_touch_controls_visible(not g.get_tree().paused)


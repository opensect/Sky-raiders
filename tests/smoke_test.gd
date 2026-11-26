class_name SmokeTest
extends RefCounted


# QA-140 (v3.15): extracted from game.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `g` (dependency injection).


var g # the owner (game.gd)

var _smoke_test: bool = false
var _smoke_elapsed: float = 0.0
var _smoke_phase: int = -1
var _smoke_logged: bool = false
var _smoke_grenade_done: bool = false
var _smoke_switch_done: bool = false
var _smoke_shot_aim_done: bool = false
var _smoke_shot_boom_done: bool = false
var _smoke_move_idx: int = -1
var _smoke_aim_idx: int = -1
var _smoke_fire_owns_aim: bool = false # v3.2: _smoke_set_fire holds the aim stick when nothing else does
var _join_test_host: bool = false
var _join_test_client: bool = false
var _game_shots: bool = false # v3.2: --game-shots captures HUD/countdown/pause/scoreboard/end to user://shot_*.png
var _v37_shots: bool = false # v3.7: --v37-shots captures jetpack flame + muzzle flash, pickups, hit flash to user://shot_v37_*.png
var _v37_timer: float = 0.0
var _v37_stage: int = -1
var _v38_shots: bool = false # v3.8 QA-105: --v38-shots captures sniper sight line (clear/blocked), rifle, SMG to user://shot_v38_*.png (QA-143: no scope any more)
var _v38_timer: float = 0.0
var _v38_stage: int = -1
var _glitch_shots: bool = false # v3.8 QA-108: --glitch-shots captures gun hold (6 weapons) + headgear (7) in every state to user://shot_glitch_*.png
var _glitch_timer: float = 0.0
var _glitch_stage: int = -1
var _glitch_steps: Array = []
var _map_shots: bool = false # v3.8 QA-111: --map-shot captures the Ironfall map in 4 views (left, centre peak, centre floor/waterfall, right) to user://shot_map_*.png
var _land_shots: bool = false # v3.8 QA-110: --land-shot drops the player from high and captures the landing frame + 0.15 s later to user://shot_land_*.png
var _skyfall_shots: bool = false # QA-112 (v3.9): --skyfall-shots captures the 6 Skyfall levels to user://shot_sf_*.png
var _qa145_shots: bool = false # QA-145: --qa145-shots captures the reload magazine drop (rifle + sniper) + the reference camera offset while aiming to user://shot_qa145_*.png
var _qa145_timer: float = 0.0
var _qa145_rifle_done: bool = false
var _qa145_reload_at: float = -1.0
var _qa145_rifle_frozen: bool = false
var _qa145_sniper_clear_done: bool = false
var _qa145_sniper_done: bool = false
var _qa145_sniper_at: float = -1.0
var _qa145_sniper_frozen: bool = false
var _qa145_cam_done: bool = false
var _qa145_cam_at: float = -1.0
var _qa145_cam_shot_done: bool = false


func _init(owner) -> void:
	g = owner


func _smoke_set_move(offset) -> void:
	# offset: Vector2 from the move stick centre, or null to release.
	if offset == null:
		if _smoke_move_idx != -1:
			g._on_touch_release(_smoke_move_idx)
			_smoke_move_idx = -1
		return
	var pos: Vector2 = g.move_stick.get_global_rect().get_center() + offset
	if _smoke_move_idx == -1:
		_smoke_move_idx = 950
		g._on_touch_press(_smoke_move_idx, pos)
	else:
		g._on_touch_drag(_smoke_move_idx, pos)


func _smoke_set_aim(offset) -> void:
	# offset: Vector2 from the aim stick centre, or null to release.
	if offset == null:
		if _smoke_aim_idx != -1:
			g._on_touch_release(_smoke_aim_idx)
			_smoke_aim_idx = -1
		_smoke_fire_owns_aim = false
		return
	var pos: Vector2 = g.aim_stick.get_global_rect().get_center() + offset
	if _smoke_aim_idx == -1:
		_smoke_aim_idx = 951
		g._on_touch_press(_smoke_aim_idx, pos)
	else:
		g._on_touch_drag(_smoke_aim_idx, pos)


func _smoke_set_fire(held: bool) -> void:
	# v3.2: firing comes from the AIM stick — "fire" means holding the
	# aim stick deflected. If the aim stick is already held by
	# _smoke_set_aim, firing is already happening; otherwise hold it
	# at a fixed firing offset (60,0) so the perf test can churn
	# bullets without an aim driver. Ownership is tracked so a
	# release here never drops an aim press owned by _smoke_set_aim.
	if held:
		if _smoke_aim_idx == -1:
			_smoke_aim_idx = 951
			_smoke_fire_owns_aim = true
			g._on_touch_press(_smoke_aim_idx, g.aim_stick.get_global_rect().get_center() + Vector2(60, 0))
	else:
		if _smoke_fire_owns_aim and _smoke_aim_idx != -1:
			g._on_touch_release(_smoke_aim_idx)
			_smoke_aim_idx = -1
			_smoke_fire_owns_aim = false


func _update_smoke_test(delta: float) -> void:
	_smoke_elapsed += delta
	var phase = int(_smoke_elapsed / 1.0)
	# Phases (1s each): 0-1 idle, 2-3 move right, 4 small push, 5 move left,
	# 6 release, 7-8 stick-up jump+jetpack, 9 land, 10-11 aim up-right+fire,
	# 12 aim left+fire, 13 tiny push below the dead zone (no aim, no fire),
	# 14 grenade, 15 weapon switch, 16+ summary.
	if phase != _smoke_phase:
		_smoke_phase = phase
		_log_smoke_phase(phase)
	# Teleport to open sky before the jump test (no platform overhead).
	if _smoke_elapsed >= 6.5 and _smoke_elapsed < 7.0:
		var lp0 = g._get_local_player()
		if lp0 != null and lp0.position.x < 2000.0:
			lp0.position = Vector2(2100, 1350)
			lp0.sync_position = lp0.position
			lp0.velocity = Vector2.ZERO
	# Drive the simulated sticks (real press/drag/release path).
	if _smoke_elapsed >= 2.0 and _smoke_elapsed < 4.0:
		_smoke_set_move(Vector2(60, 0))
	elif _smoke_elapsed >= 4.0 and _smoke_elapsed < 5.0:
		_smoke_set_move(Vector2(18, 0))
	elif _smoke_elapsed >= 5.0 and _smoke_elapsed < 6.0:
		_smoke_set_move(Vector2(-60, 0))
	elif _smoke_elapsed >= 7.0 and _smoke_elapsed < 9.0:
		_smoke_set_move(Vector2(0, -60))
	else:
		_smoke_set_move(null)
	if _smoke_elapsed >= 10.0 and _smoke_elapsed < 12.0:
		_smoke_set_aim(Vector2(42, -42))
		_smoke_set_fire(true)
	elif _smoke_elapsed >= 12.0 and _smoke_elapsed < 13.0:
		_smoke_set_aim(Vector2(-60, 0))
		_smoke_set_fire(true)
	elif _smoke_elapsed >= 13.0 and _smoke_elapsed < 14.0:
		# v3.2: there is no aim-without-fire any more — any deflection
		# past the dead zone fires. This phase now pushes (0,10),
		# BELOW the 0.20 dead zone, so the stick stays centred: no
		# aim, no fire (dead-zone check).
		_smoke_set_aim(Vector2(0, 10))
		_smoke_set_fire(false)
	else:
		_smoke_set_aim(null)
		_smoke_set_fire(false)
	# Propagate the stick vectors into touch_move_vec / touch_firing
	# (normally done by _update_touch_state in _process).
	g._update_touch_state()
	if _smoke_elapsed >= 11.5 and not _smoke_shot_aim_done:
		_smoke_shot_aim_done = true
		_capture_shot("user://shot_aim.png")
	if _smoke_elapsed >= 16.05 and not _smoke_shot_boom_done:
		_smoke_shot_boom_done = true
		_capture_shot("user://shot_explosion.png")
	if _smoke_elapsed > 18.0:
		print("SMOKE: quitting after screenshots")
		g.get_tree().quit()
		return
	if _smoke_elapsed >= 14.0 and not _smoke_grenade_done:
		_smoke_grenade_done = true
		var lp = g._get_local_player()
		if lp != null:
			lp.throw_grenade()
			print("SMOKE: grenade thrown, grenades now=", lp.grenades)
	if _smoke_elapsed >= 15.0 and not _smoke_switch_done:
		_smoke_switch_done = true
		var lp2 = g._get_local_player()
		if lp2 != null:
			lp2.give_pickup(1)
			print("SMOKE: pickup gave weapon=", lp2.weapon, " (", lp2.WEAPONS[lp2.weapon]["name"], "), owned=", lp2.owned_weapons())
			lp2.switch_weapon()
			print("SMOKE: weapon switched to=", lp2.weapon, " (", lp2.WEAPONS[lp2.weapon]["name"], ")")
	if _smoke_elapsed > 17.0 and not _smoke_logged:
		_smoke_logged = true
		var lp3 = g._get_local_player()
		print("SMOKE DONE: players=", g.players_node.get_child_count(),
			" local_alive=", lp3 != null and lp3.alive,
			" shots_fired=", lp3._shots_fired if lp3 != null else -1,
			" bullets=", g.bullets_node.get_child_count(),
			" grenades_node=", g.grenades_node.get_child_count(),
			" fuel=", lp3.fuel if lp3 != null else -1.0,
			" anim=", lp3._current_anim if lp3 != null else "none")


func _capture_shot(path: String) -> void:
	await g.get_tree().process_frame
	await g.get_tree().process_frame
	var img = g.get_viewport().get_texture().get_image()
	var err = img.save_png(path)
	print("SMOKE: screenshot ", path, " err=", err, " size=", img.get_size())


# v3.2 GAME-SCREENSHOT MODE (--game-shots): staged captures of the
# in-game screens for the visual review (THEME_SPEC.md §9) — the
# countdown, the HUD (with a kill-feed chip), pause, scoreboard and
# the end screen. Runs as auto-host; the countdown is NOT skipped
# (this flag is deliberately left out of _is_test_mode in _ready).
# Stages are 1 s apart so the async capture (2 frames) lands while
# the screen is still in the staged state.
func _update_gameshots(delta: float) -> void:
	g._gs_timer += delta
	var stage = int(g._gs_timer / 1.0)
	if stage == g._gs_stage:
		return
	g._gs_stage = stage
	match stage:
		0:
			pass # countdown "3" is showing
		1:
			_capture_shot("user://shot_countdown.png")
		4:
			# Countdown done — HUD + hint visible. Seed one kill-feed
			# entry so the chip renders in the HUD shot. On Skyfall
			# also seed the 3 slots (QA-119) + an invisible enemy
			# (QA-121 red warning) so the HUD shot proves the new
			# top-left / top-right design.
			g._add_kill_feed_entry(1, 1, 0)
			var lp4 = g._get_local_player()
			if lp4 != null and g.map_id == GameData.SKYFALL_MAP_ID:
				lp4.apply_powerup(8)
				lp4.apply_powerup(10)
				lp4.apply_powerup(13) # QA-143 (v4.0): Health Potion (7) removed — Invisibility fills the third slot
				g._do_spawn(201, "InvisBot", 1, 0, -1)
				var bot4 = g.players_node.get_node_or_null("201")
				if bot4 != null:
					bot4.set("invisibility_timer", 30.0)
			# QA-122 (v3.11): low-bar proof — the HUD capture shows
			# health 35 (amber) + fuel 20 (amber) so the redesigned
			# bars are verified at low values too; the level shots
			# already prove the full (100/100) state.
			if lp4 != null:
				lp4.health = 35
				lp4.fuel = 20.0
			_capture_shot("user://shot_hud.png")
		5:
			if not g.get_tree().paused:
				g._toggle_pause()
			_capture_shot("user://shot_pause.png")
		6:
			if g.get_tree().paused:
				g._toggle_pause()
			g._on_score_pressed()
			_capture_shot("user://shot_scoreboard.png")
		7:
			if g.scoreboard_panel.visible:
				g._on_score_pressed()
			g._end_match("You", "screenshot — first to 10 kills")
			_capture_shot("user://shot_end.png")
		8:
			print("GAMESHOTS DONE")
			g.get_tree().quit()


# v3.7 VISUALS-SCREENSHOT MODE (--v37-shots): staged captures of
# the new v3.7 visuals for the proof shots. Runs as auto-host; the
# countdown is skipped (this flag is in _is_test_mode). The sticks
# are driven through the same real touch handlers as the smoke
# test. Stage 1 holds the move stick up (jetpack) and the aim
# stick up-right (firing the rifle); stage 2 captures the flame +
# muzzle flash; stage 3 stops, spawns a health + a weapon pickup
# in front of the player and captures them; stage 4 forces the
# shader hit flash and captures it; stage 5 quits.
func _update_v37shots(delta: float) -> void:
	_v37_timer += delta
	var stage = int(_v37_timer / 1.0)
	if stage == _v37_stage:
		return
	_v37_stage = stage
	var lp = g._get_local_player()
	match stage:
		1:
			if lp != null:
				lp.fuel = PhysicsConfig.FUEL_MAX
				lp.position = Vector2(2100, 1350)
				lp.sync_position = lp.position
				lp.velocity = Vector2.ZERO
			_smoke_set_move(Vector2(0, -60))
			_smoke_set_aim(Vector2(42, -42))
			_smoke_set_fire(true)
		2:
			_capture_shot("user://shot_v37_flame.png")
		3:
			_smoke_set_move(null)
			_smoke_set_aim(null)
			_smoke_set_fire(false)
			if lp != null:
				g.spawn_pickup_remote(lp.position + Vector2(150, -20), "v37_health", 5)
				g.spawn_pickup_remote(lp.position + Vector2(280, -20), "v37_smg", 1)
			_capture_shot("user://shot_v37_pickup.png")
		4:
			if lp != null:
				lp._hit_flash_timer = 0.09
			_capture_shot("user://shot_v37_hitflash.png")
		5:
			print("V37SHOTS DONE")
			g.get_tree().quit()


# v3.8 SIGHT-LINE-SCREENSHOT MODE (--v38-shots, QA-105): staged captures
# of the sniper sight line. QA-143: scoping was removed, so the
# stages no longer zoom — they capture the sight line only. Runs as
# auto-host; the countdown is skipped. Stage 1: sniper, open sky,
# aim LEFT from the right y670 tower tier — the sight line
# is GREEN (clear). Stage 3: same sniper, aim straight down at
# the platform below — the line is RED (blocked). Stage 5: rifle
# (no zoom, no sight line). Stage 7: SMG — no sight line.
# Each capture waits a full second so the scene settles.
# QA-111: stage 1 used to stand at (1500,300)
# aiming right, but the Ironfall peak (y330 platform + bunker +
# comms tower) now blocks that path, so the "clear" line came out
# red — moved to (2950,639) aiming left, where the y645 band is
# clear for the full 2560 px sight range.
func _update_v38shots(delta: float) -> void:
	_v38_timer += delta
	var stage = int(_v38_timer / 1.0)
	if stage == _v38_stage:
		return
	_v38_stage = stage
	var lp = g._get_local_player()
	match stage:
		1:
			if lp != null:
				lp.weapon = 3
				lp.mag_ammo = int(lp.WEAPONS[3]["mag"])
				lp._update_gun_texture()
				lp.position = Vector2(2950, 639)
				lp.sync_position = lp.position
				lp.velocity = Vector2.ZERO
			_smoke_set_move(null)
			_smoke_set_aim(Vector2(-60, 0))
			_smoke_set_fire(true)
		2:
			_capture_shot("user://shot_v38_scope_clear.png")
		3:
			if lp != null:
				lp.position = Vector2(1500, 700)
				lp.sync_position = lp.position
				lp.velocity = Vector2.ZERO
			_smoke_set_aim(Vector2(0, 60))
			_smoke_set_fire(true)
		4:
			_capture_shot("user://shot_v38_scope_blocked.png")
		5:
			if lp != null:
				lp.weapon = 0
				lp.mag_ammo = int(lp.WEAPONS[0]["mag"])
				lp._update_gun_texture()
				lp.position = Vector2(1500, 300)
				lp.sync_position = lp.position
				lp.velocity = Vector2.ZERO
			_smoke_set_aim(Vector2(60, 0))
			_smoke_set_fire(true)
		6:
			_capture_shot("user://shot_v38_rifle_scope.png")
		7:
			if lp != null:
				lp.weapon = 1
				lp.mag_ammo = int(lp.WEAPONS[1]["mag"])
				lp._update_gun_texture()
			_smoke_set_aim(Vector2(60, 0))
			_smoke_set_fire(true)
		8:
			_capture_shot("user://shot_v38_smg_noscope.png")
		9:
			print("V38SHOTS DONE")
			g.get_tree().quit()


# QA-145 SCREENSHOT MODE (--qa145-shots): staged captures of the
# reload magazine drop (rifle, then sniper) and the reference camera view
# offset while aiming. Runs as auto-host; the countdown is skipped.
# Threshold-gated (not exact stages) so a slow xvfb frame cannot
# skip a step. Timeline: 1.0 rifle reload, aim held right by direct
# aim_angle (no stick — the stick would fire); at mag age ~0.15 s the
# tree is PAUSED, freezing the mag ~20 px below the gun, and the
# capture is taken of the frozen frame (the capture awaits 2 frames,
# and at 2400x1080 under llvmpipe that await alone is ~0.4 s — an
# unpaused grab landed at mag age ~0.55 s, ~150 px down at the screen
# edge). A 0.8 s timer (runs while paused) unpauses so the driver
# continues. All stages stand on the y1010 tier at (1100, 976) — the
# mag falls into open air, not onto the floor edge where it was
# camouflaged. 3.0 clear the rifle reload, 3.3 sniper reload (the
# clear and the restart MUST be separate frames — same-frame
# clear+start masks the reloading transition the hook reads, and no
# mag spawns), freeze + capture the same way; 5.0 rifle, aim stick
# up-right (firing) so the camera offset eases in; ~5.6 capture;
# 6.5 quit.
func _update_qa145shots(delta: float) -> void:
	_qa145_timer += delta
	var lp = g._get_local_player()
	if lp == null:
		return
	if _qa145_timer >= 1.0 and not _qa145_rifle_done:
		_qa145_rifle_done = true
		lp.weapon = 0
		lp.mag_ammo = 5
		lp._update_gun_texture()
		lp.position = Vector2(1100, 976)
		lp.sync_position = lp.position
		lp.velocity = Vector2.ZERO
		lp.aim_angle = 0.0
		lp.facing = 1
		lp.start_reload()
		_qa145_reload_at = _qa145_timer
		print("QA145SHOTS: rifle reload started reloading=", lp.reloading, " mags=", _qa145_count_mags())
	if _qa145_reload_at > 0.0 and not _qa145_rifle_frozen and _qa145_timer - _qa145_reload_at >= 0.15:
		_qa145_rifle_frozen = true
		_qa145_freeze_and_capture("user://shot_qa145_mag_rifle.png")
	if _qa145_timer >= 3.0 and not _qa145_sniper_clear_done:
		_qa145_sniper_clear_done = true
		lp.reloading = false
		lp._reload_timer = 0.0
		lp._reload_transfer = 0
	if _qa145_timer >= 3.3 and not _qa145_sniper_done:
		_qa145_sniper_done = true
		lp.weapon = 3
		lp.mag_ammo = 2
		lp._update_gun_texture()
		lp.position = Vector2(1100, 976)
		lp.sync_position = lp.position
		lp.velocity = Vector2.ZERO
		lp.aim_angle = 0.0
		lp.facing = 1
		lp.start_reload()
		_qa145_sniper_at = _qa145_timer
		print("QA145SHOTS: sniper reload started reloading=", lp.reloading, " mags=", _qa145_count_mags())
	if _qa145_sniper_at > 0.0 and not _qa145_sniper_frozen and _qa145_timer - _qa145_sniper_at >= 0.15:
		_qa145_sniper_frozen = true
		_qa145_freeze_and_capture("user://shot_qa145_mag_sniper.png")
	if _qa145_timer >= 5.0 and not _qa145_cam_done:
		_qa145_cam_done = true
		lp.reloading = false
		lp._reload_timer = 0.0
		lp._reload_transfer = 0
		lp.weapon = 0
		lp.mag_ammo = int(lp.WEAPONS[0]["mag"])
		lp._update_gun_texture()
		lp.position = Vector2(1100, 976)
		lp.sync_position = lp.position
		lp.velocity = Vector2.ZERO
		_smoke_set_aim(Vector2(42, -42))
		_smoke_set_fire(true)
		_qa145_cam_at = _qa145_timer
	if _qa145_cam_at > 0.0 and not _qa145_cam_shot_done and _qa145_timer - _qa145_cam_at >= 0.6:
		_qa145_cam_shot_done = true
		print("QA145SHOTS: camera capture ref_s=", g._ref_view_s, " ref_px=", g._ref_view_px, " cam_offset=", lp._camera.offset if lp._camera != null else Vector2.ZERO, " aiming=", lp._aiming, " aim_angle=", lp.aim_angle)
		_capture_shot("user://shot_qa145_camera_aim.png")
	if _qa145_timer >= 6.5:
		print("QA145SHOTS DONE")
		g.get_tree().quit()


func _qa145_count_mags() -> int:
	var n := 0
	for c in g.get_children():
		if c is MagazineDrop:
			n += 1
	return n


# QA-145: freeze the falling magazine for a screenshot — pause the
# tree (the mag's _process stops, so it hangs mid-fall ~20 px below
# the gun), capture the frozen frame, and unpause on a timer. The
# timer runs while paused (process_always), so the driver resumes
# even if the capture itself stalls. The capture's 2-frame await
# still fires while paused (process_frame is emitted every
# iteration); the viewport keeps rendering the frozen frame.
func _qa145_freeze_and_capture(path: String) -> void:
	print("QA145SHOTS: freeze mags=", _qa145_count_mags(), " -> ", path)
	# Ground truth for the eye-check: the mag's exact screen pixel
	# at freeze time (screen centre already includes the camera
	# offset), so the bar in the screenshot can be matched by number.
	var lp = g._get_local_player()
	if lp != null and lp._camera != null:
		var center: Vector2 = lp._camera.get_screen_center_position()
		var vp: Vector2 = g.get_viewport().get_visible_rect().size
		for c in g.get_children():
			if c is MagazineDrop:
				var sp: Vector2 = c.global_position - center + vp * 0.5
				print("QA145SHOTS: mag screen pos=", sp, " world=", c.global_position, " age=", c._age)
	g.get_tree().paused = true
	_capture_shot(path)
	g.get_tree().create_timer(0.8).timeout.connect(_qa145_unpause)


func _qa145_unpause() -> void:
	g.get_tree().paused = false


# v3.8 QA-108 GLITCH-SCREENSHOT MODE (--glitch-shots): staged
# captures of the gun hold (all 6 weapons: aim right / up / down /
# firing) and the headgear (all 7: idle / jetpack / landed after
# jetpack / run / fall) to user://shot_glitch_*.png. Runs as
# auto-host; the countdown is skipped (this flag is in
# _is_test_mode). Each step is two 1 s stages: setup, then capture.
# The capture stage prints the gun's barrel-tip vs muzzle-flash
# positions, so a misalignment is
# visible in the log as well as in the picture.
func _update_glitchshots(delta: float) -> void:
	_glitch_timer += delta
	var stage = int(_glitch_timer / 1.0)
	if stage == _glitch_stage:
		return
	_glitch_stage = stage
	if _glitch_steps.is_empty():
		_glitch_build_steps()
	var step_idx = stage / 2
	if stage % 2 == 0:
		if step_idx >= _glitch_steps.size():
			print("GLITCHSHOTS DONE")
			g.get_tree().quit()
			return
		_glitch_setup(_glitch_steps[step_idx])
	else:
		if step_idx >= _glitch_steps.size():
			return
		var step: Dictionary = _glitch_steps[step_idx]
		var lp = g._get_local_player()
		if lp != null and String(step.get("repos", "")) == "air":
			var floor_top = float((g.MAPS[g.map_id]["platforms"] as Array)[0].position.y)
			lp.position = Vector2(1500, floor_top - 300.0)
			lp.sync_position = lp.position
			lp.velocity = Vector2.ZERO
		if lp != null and bool(step.get("fire_flash", false)):
			lp._muzzle_timer = 1.0
		if lp != null:
			var gp := Vector2.ZERO
			var grot := 0.0
			if lp._gun != null:
				gp = lp._gun.position
				grot = lp._gun.rotation
			var dir := Vector2(cos(grot), sin(grot))
			var tip: Vector2 = gp + dir * 27.5
			# QA-108: read the REAL muzzle-flash node, not a hardcoded
			# 55 px — the flash used to sit 27.5 px past the barrel tip.
			var flash: Vector2 = gp + dir * 55.0
			if lp._muzzle != null:
				flash = lp.to_local(lp._muzzle.global_position)
			print("GLITCH %s gun_pos=%s rot=%.2f tip=%s flash=%s anim=%s" % [String(step["name"]), str(gp), grot, str(tip), str(flash), String(lp._current_anim)])
		_capture_shot("user://" + String(step["file"]))


func _glitch_build_steps() -> void:
	_glitch_steps = []
	# Gun hold: every weapon, aim right + aim up + firing flash.
	for w in range(6):
		_glitch_steps.append({"name": "G%d_RIGHT" % w, "file": "shot_glitch_gun%d_right.png" % w, "w": w, "h": 0, "pos": "floor", "aim": Vector2(60, 0)})
		_glitch_steps.append({"name": "G%d_UP" % w, "file": "shot_glitch_gun%d_up.png" % w, "w": w, "h": 0, "pos": "floor", "aim": Vector2(0, -60)})
		_glitch_steps.append({"name": "G%d_FIRE" % w, "file": "shot_glitch_gun%d_fire.png" % w, "w": w, "h": 0, "pos": "floor", "aim": Vector2(60, 0), "fire_flash": true})
	# Aim down (rifle + sniper) and running with the rifle.
	_glitch_steps.append({"name": "G0_DOWN", "file": "shot_glitch_gun0_down.png", "w": 0, "h": 0, "pos": "floor", "aim": Vector2(0, 60)})
	_glitch_steps.append({"name": "G3_DOWN", "file": "shot_glitch_gun3_down.png", "w": 3, "h": 0, "pos": "floor", "aim": Vector2(0, 60)})
	_glitch_steps.append({"name": "G0_RUN", "file": "shot_glitch_gun0_run.png", "w": 0, "h": 0, "pos": "floor", "pos_x": 900.0, "aim": Vector2(60, 0), "move": Vector2(60, 0)})
	# Headgear: every piece, idle / mid-jetpack / landed after jetpack.
	for h in range(7):
		_glitch_steps.append({"name": "H%d_IDLE" % h, "file": "shot_glitch_cap%d_idle.png" % h, "w": 0, "h": h, "pos": "floor", "aim": Vector2(60, 0)})
		_glitch_steps.append({"name": "H%d_JET" % h, "file": "shot_glitch_cap%d_jet.png" % h, "w": 0, "h": h, "pos": "floor", "move": Vector2(0, -55)})
		_glitch_steps.append({"name": "H%d_LAND" % h, "file": "shot_glitch_cap%d_land.png" % h, "w": -1, "h": -1, "pos": "floor", "aim": Vector2(60, 0)})
	# Cap (2) while running and while falling.
	_glitch_steps.append({"name": "H2_RUN", "file": "shot_glitch_cap2_run.png", "w": 0, "h": 2, "pos": "floor", "pos_x": 900.0, "aim": Vector2(60, 0), "move": Vector2(60, 0)})
	_glitch_steps.append({"name": "H2_FALL", "file": "shot_glitch_cap2_fall.png", "w": 0, "h": 2, "pos": "air", "repos": "air"})


func _glitch_setup(step: Dictionary) -> void:
	var lp = g._get_local_player()
	_smoke_set_aim(null)
	_smoke_set_fire(false)
	_smoke_set_move(null)
	if lp == null:
		return
	if int(step.get("w", -1)) >= 0:
		lp.weapon = int(step["w"])
		lp.mag_ammo = int(lp.WEAPONS[int(step["w"])]["mag"])
		lp._update_gun_texture()
	var floor_top = float((g.MAPS[g.map_id]["platforms"] as Array)[0].position.y)
	# QA-127 (v3.11): default x1400, NOT 1500 — Ironfall has a live
	# weapon pickup spawn at (1500, 1320) and the player teleports
	# onto it, so a shotgun spawned mid-run once auto-switched the
	# weapon (G3_UP captured "Shotgun 6/18" instead of the Sniper).
	# Picking it up is correct game behaviour; the teleport spot
	# was the bug. 1400 is 100 px clear of that spawn.
	var px := float(step.get("pos_x", 1400.0))
	var pos_kind := String(step.get("pos", "floor"))
	if pos_kind == "floor":
		lp.position = Vector2(px, floor_top - 43.0)
	elif pos_kind == "air":
		lp.position = Vector2(px, floor_top - 300.0)
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	lp.health = 100
	if not lp.alive:
		lp._respawn()
	var aim = step.get("aim", null)
	if aim != null:
		_smoke_set_aim(aim)
	var move = step.get("move", null)
	if move != null:
		_smoke_set_move(move)


# v3.8 QA-111 MAP-SCREENSHOT MODE (--map-shot): staged captures
# of the Ironfall map in 5 views — left tower, centre peak
# (bunker + dish + red flag + helicopter), centre floor
# (waterfall + pool + tunnel), right tower, and the full moon —
# to user://shot_map_*.png. Runs as auto-host; the countdown is
# skipped. Each view is two 1 s stages (setup, then capture); the
# camera smoothing is reset on teleport so the view is settled
# by the capture. The tower views stand the player on the y840
# perches so the y670 towers are in frame.
func _update_mapshots(delta: float) -> void:
	g._map_timer += delta
	var stage = int(g._map_timer / 1.0)
	if stage == g._map_stage:
		return
	g._map_stage = stage
	var lp = g._get_local_player()
	var floor_top = float((g.MAPS[g.map_id]["platforms"] as Array)[0].position.y)
	match stage:
		1:
			if lp != null:
				# QA-143: stand on the new y840 left shelf (185-800),
				# centre-ish, so the y670 tower is in frame.
				lp.position = Vector2(600, 800)
				lp.sync_position = lp.position
				lp.velocity = Vector2.ZERO
				if lp._camera != null:
					lp._camera.reset_smoothing()
			_smoke_set_move(null)
			_smoke_set_aim(null)
			_smoke_set_fire(false)
		2:
			_capture_shot("user://shot_map_left.png")
		3:
			if lp != null:
				lp.position = Vector2(1750, 287)
				lp.sync_position = lp.position
				lp.velocity = Vector2.ZERO
				if lp._camera != null:
					lp._camera.reset_smoothing()
			_smoke_set_move(null)
			_smoke_set_aim(null)
			_smoke_set_fire(false)
		4:
			_capture_shot("user://shot_map_peak.png")
		5:
			if lp != null:
				lp.position = Vector2(1600, floor_top - 43.0)
				lp.sync_position = lp.position
				lp.velocity = Vector2.ZERO
				if lp._camera != null:
					lp._camera.reset_smoothing()
			_smoke_set_move(null)
			_smoke_set_aim(null)
			_smoke_set_fire(false)
		6:
			_capture_shot("user://shot_map_waterfall.png")
		7:
			if lp != null:
				# QA-111: stand on the (2831,840) perch — the camera
				# sits ~190 px left of the player, so standing on the
				# (2277,840) perch put the (2900,670) tower off-frame.
				# QA-143: perch moved 2800-3176 -> 2831-2954, tower
				# 3030 -> 2900; stand at its centre (2890,800).
				lp.position = Vector2(2890, 800)
				lp.sync_position = lp.position
				lp.velocity = Vector2.ZERO
				if lp._camera != null:
					lp._camera.reset_smoothing()
			_smoke_set_move(null)
			_smoke_set_aim(null)
			_smoke_set_fire(false)
		8:
			_capture_shot("user://shot_map_right.png")
		9:
			if lp != null:
				lp.position = Vector2(2250, 467)
				lp.sync_position = lp.position
				lp.velocity = Vector2.ZERO
				if lp._camera != null:
					lp._camera.reset_smoothing()
			_smoke_set_move(null)
			_smoke_set_aim(null)
			_smoke_set_fire(false)
		10:
			_capture_shot("user://shot_map_moon.png")
		11:
			print("MAPSHOTS DONE")
			g.get_tree().quit()


# QA-112 (v3.9) SKYFALL-SCREENSHOT MODE (--skyfall-shots): one
# capture per level (6 levels, centre x1800), to
# user://shot_sf_L1.png ... shot_sf_L6.png. Runs as auto-host
# on map 4; the countdown is skipped. Odd stages move the player
# to the level, even stages capture (1 s apart, so the camera
# smoothing settles).
func _update_skyfallshots(delta: float) -> void:
	g._sf_shot_timer += delta
	var stage = int(g._sf_shot_timer / 1.0)
	if stage == g._sf_shot_stage:
		return
	g._sf_shot_stage = stage
	var lp = g._get_local_player()
	if stage >= 1 and stage <= 12:
		var lvl = (stage + 1) / 2 # 1-6
		if stage % 2 == 1:
			if lp != null:
				var cy := 10800.0 - (float(lvl) - 0.5) * 1800.0
				# QA-123: L6's centre x1800 is INSIDE the summit
				# gate (box x1742-1858, y484-862) and embedded in
				# the summit platform, so the stuck-recovery fires
				# and moves the player to the base spawn before
				# the capture — the L6 shot showed the base, not
				# the summit. Stand left of the gate instead, on
				# the same (1200, 862) summit platform, with open
				# sky above; the gate and flag stay in frame.
				var cx := 1400.0 if lvl == 6 else 1800.0
				lp.position = Vector2(cx, cy - 40.0)
				lp.sync_position = lp.position
				lp.velocity = Vector2.ZERO
				if lp._camera != null:
					lp._camera.reset_smoothing()
			_smoke_set_move(null)
			_smoke_set_aim(null)
			_smoke_set_fire(false)
			# QA-119/121/130 (v3.11): seed the HUD proof — filled
			# slots + an invisible enemy (red warning) at stage 1,
			# feed messages refreshed at stage 7 (5 s expiry).
			if stage == 1 and lp != null:
				lp.apply_powerup(8)
				lp.apply_powerup(10)
				lp.apply_powerup(13) # QA-143 (v4.0): Health Potion (7) removed — Invisibility fills the third slot
				# QA-132: activate the shield (slot 0) so the L1
				# shot shows a live effect (shield ring + active
				# boost label), not just filled slots.
				lp.activate_slot(0)
				g._do_spawn(201, "InvisBot", 1, 0, 1)
				var sf_bot = g.players_node.get_node_or_null("201")
				if sf_bot != null:
					sf_bot.set("invisibility_timer", 30.0)
			if stage == 1 or stage == 7:
				g._ctf_feed("Player  ☠  TestBot   —  Rifle", g.UI_FONT)
				g._ctf_feed("⚑ BLUE: at summit", Color(0.25, 0.55, 0.95))
		else:
			_capture_shot("user://shot_sf_L%d.png" % lvl)
	elif stage >= 13 and stage <= 22:
		# QA-137 (v3.14): FX proof stages — fire vent (L5), thunder
		# strike, normal + boost jetpack flames, pendulum (L4).
		# Odd stages move/set up, even stages capture (1 s apart).
		if stage == 13:
			# Fire vent (L5): stand on the (1500,2224) platform in
			# the fire jet (1750,2140,200,84); the match clock is
			# set so the vent is HOT through the capture (2 s on /
			# 2 s off per 4 s cycle).
			g._sf_match_time = 0.5
			if lp != null:
				lp.position = Vector2(1850, 2193)
				lp.sync_position = lp.position
				lp.velocity = Vector2.ZERO
				if lp._camera != null:
					lp._camera.reset_smoothing()
			_smoke_set_move(null)
			_smoke_set_aim(null)
			_smoke_set_fire(false)
		elif stage == 14:
			_capture_shot("user://shot_sf_fire.png")
		elif stage == 15:
			# Thunder: stand clear on the L1 base; the bolt is
			# triggered in the capture stage (it only lives 0.6 s).
			if lp != null:
				lp.position = Vector2(1800, 10721)
				lp.sync_position = lp.position
				lp.velocity = Vector2.ZERO
				if lp._camera != null:
					lp._camera.reset_smoothing()
			_smoke_set_move(null)
			_smoke_set_aim(null)
			_smoke_set_fire(false)
		elif stage == 16:
			if lp != null:
				g.show_thunder_strike_fx(lp.position + Vector2(0, -150))
			_capture_shot("user://shot_sf_thunder.png")
		elif stage == 17:
			# Normal jetpack flame: hold the stick up while
			# airborne (thrusting, no boost). The flame shows
			# below the player as they rise.
			if lp != null:
				lp.position = Vector2(1800, 10500)
				lp.sync_position = lp.position
				lp.velocity = Vector2.ZERO
				lp.set("jetpack_boost_timer", 0.0)
				lp.set("fuel", 405.0)
				if lp._camera != null:
					lp._camera.reset_smoothing()
			_smoke_set_move(Vector2(0, -60))
			_smoke_set_aim(null)
			_smoke_set_fire(false)
		elif stage == 18:
			_capture_shot("user://shot_sf_flame.png")
		elif stage == 19:
			# Boost flame: same thrust, but the Jetpack Boost
			# power-up runs (the bigger blue-core flame).
			if lp != null:
				lp.position = Vector2(1800, 10500)
				lp.sync_position = lp.position
				lp.velocity = Vector2.ZERO
				lp.set("jetpack_boost_timer", 30.0)
				lp.set("fuel", 405.0)
				if lp._camera != null:
					lp._camera.reset_smoothing()
			_smoke_set_move(Vector2(0, -60))
			_smoke_set_aim(null)
			_smoke_set_fire(false)
		elif stage == 20:
			_capture_shot("user://shot_sf_flame_boost.png")
		elif stage == 21:
			# Pendulum (L4): stand on the (2100,4184) platform
			# where the ball sweeps; the clock is reset so the
			# ball starts at the bottom of its swing.
			g._sf_match_time = 0.0
			if lp != null:
				lp.position = Vector2(2400, 4153)
				lp.sync_position = lp.position
				lp.velocity = Vector2.ZERO
				if lp._camera != null:
					lp._camera.reset_smoothing()
			_smoke_set_move(null)
			_smoke_set_aim(null)
			_smoke_set_fire(false)
		elif stage == 22:
			_capture_shot("user://shot_sf_pendulum.png")
	elif stage >= 23:
		print("SKYFALLSHOTS DONE")
		g.get_tree().quit()


# v3.8 QA-110 LAND-SCREENSHOT MODE (--land-shot): drops the
# player from high (600 px, x1100 — a clean gap through every
# tier to the floor) and captures the exact landing frame plus
# one 0.15 s later, to user://shot_land_*.png. Runs as auto-host;
# the countdown is skipped. The hard-landing FX (fall speed
# > 550) used to be a white-gold hit spark at the legs plus a
# dust puff; the spark call is removed, so the shots must show
# dust only and no sparkle.
func _update_landshots(delta: float) -> void:
	g._land_timer += delta
	var lp = g._get_local_player()
	if g._land_stage == -1 and lp != null:
		var floor_top = float((g.MAPS[g.map_id]["platforms"] as Array)[0].position.y)
		lp.position = Vector2(1100, floor_top - 600.0)
		lp.sync_position = lp.position
		lp.velocity = Vector2.ZERO
		if lp._camera != null:
			lp._camera.reset_smoothing()
		_smoke_set_move(null)
		_smoke_set_aim(null)
		_smoke_set_fire(false)
		g._land_stage = 0
		g._land_armed = true
		return
	if g._land_stage == 0 and g._land_armed and lp != null:
		if not lp.is_on_floor():
			# Sample the falling speed while airborne: reading
			# _fall_speed after landing is one physics frame too
			# late (it resets to a single frame of gravity, ~23).
			g._land_maxfall = maxf(g._land_maxfall, lp._fall_speed)
		elif lp.is_on_floor():
			print("LAND impact_speed=%.0f" % g._land_maxfall)
			_capture_shot("user://shot_land_at.png")
			g._land_t0 = g._land_timer
			g._land_stage = 1
	elif g._land_stage == 1 and g._land_timer - g._land_t0 >= 0.15:
		_capture_shot("user://shot_land_after.png")
		g._land_stage = 2
	elif g._land_stage == 2 and g._land_timer - g._land_t0 >= 0.5:
		# Quit a full stage after the last capture: _capture_shot
		# awaits 2 frames before saving, and quitting in the same
		# stage kills the save (that lost shot_land_after.png once).
		print("LANDSHOTS DONE")
		g.get_tree().quit()


func _log_smoke_phase(phase: int) -> void:
	var lp = g._get_local_player()
	if lp == null:
		print("SMOKE phase ", phase, ": no local player yet")
		return
	var gun_rot := rad_to_deg(lp._gun.rotation) if lp._gun != null else -999.0
	print("SMOKE phase ", phase, ": anim=", lp._current_anim,
		" facing=", lp.facing,
		" aim_deg=", round(rad_to_deg(lp.aim_angle)),
		" gun_rot_deg=", round(gun_rot),
		" vel=", Vector2(round(lp.velocity.x), round(lp.velocity.y)),
		" pos=", Vector2(round(lp.position.x), round(lp.position.y)),
		" on_floor=", lp.is_on_floor(),
		" fuel=", round(lp.fuel),
		" alive=", lp.alive)


class_name WorkerSShots
extends RefCounted


# QA-145 (v4.1, Worker S): staged screenshots for the trap/route
# review (maps 0/2/3/4/5 — Ironfall needs none, Skyfall uses the
# existing --skyfall-shots mode). Runs as auto-host; the countdown
# is skipped (game.gd _is_test_mode). Positions come from repeated
# --shot-pos=x,y CLI args; one capture per position, 1 s apart so
# the camera smoothing settles. Output: user://shot_workerS_N.png
# (N = 1-based position index). On map 3 the fire-trap clock is
# reset at each stage so the flames are HOT through the capture
# (2 s on / 2 s off per 4 s cycle).


var g # the owner (game.gd)

var _workerS_shots: bool = false
var _ws_timer: float = 0.0
var _ws_stage: int = -1
var _ws_positions: Array = []


func _init(owner) -> void:
	g = owner


func _ws_parse_positions() -> void:
	_ws_positions = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-pos="):
			var parts: PackedStringArray = a.trim_prefix("--shot-pos=").split(",")
			if parts.size() == 2:
				_ws_positions.append(Vector2(float(parts[0]), float(parts[1])))


func _update_workerSshots(delta: float) -> void:
	if _ws_positions.is_empty():
		_ws_parse_positions()
	if _ws_positions.is_empty():
		print("WORKERSHOTS DONE (no --shot-pos= given)")
		g.get_tree().quit()
		return
	_ws_timer += delta
	var stage = int(_ws_timer / 1.0)
	if stage == _ws_stage:
		return
	_ws_stage = stage
	var lp = g._get_local_player()
	if stage >= 1 and stage <= _ws_positions.size() * 2:
		var idx = (stage - 1) / 2
		if stage % 2 == 1:
			# Setup: teleport the player to the staged spot.
			if lp != null:
				lp.position = _ws_positions[idx]
				lp.sync_position = lp.position
				lp.velocity = Vector2.ZERO
				if lp._camera != null:
					lp._camera.reset_smoothing()
			g.smoke_test._smoke_set_move(null)
			g.smoke_test._smoke_set_aim(null)
			g.smoke_test._smoke_set_fire(false)
			# Map 3 (Volcanic): reset the fire-trap clock so the
			# flames are HOT (visible) through the capture 1 s later.
			if g.map_id == 3:
				g._fire_trap_time = 0.5
		else:
			g.smoke_test._capture_shot("user://shot_workerS_%d.png" % (idx + 1))
	elif stage > _ws_positions.size() * 2:
		print("WORKERSHOTS DONE")
		g.get_tree().quit()

class_name WorkerTShots
extends RefCounted


# QA-145 (v4.1, Worker T): staged screenshots for the new ideas
# (proximity mine, supply-drop beacon, streak callouts). Runs as
# auto-host; the countdown is skipped (game.gd _is_test_mode).
# Positions come from repeated --shot-pos=x,y CLI args; one capture
# per position, 1 s apart so the camera smoothing settles. Output:
# user://shot_workerT_N.png (N = 1-based position index).
# --shot-beacon=x,y builds a supply-drop beacon at that spot before
# the first capture (the real event drops at a random platform, so
# the staged spot matches the event geometry: platform centre -60).
# --shot-streak announces two kills by the local player before the
# first capture, so the FIRST BLOOD + DOUBLE KILL feed lines show.


var g # the owner (game.gd)

var _workerT_shots: bool = false
var _wt_timer: float = 0.0
var _wt_stage: int = -1
var _wt_positions: Array = []
var _wt_beacon: Vector2 = Vector2.INF
var _wt_streak: bool = false
var _wt_staged: bool = false


func _init(owner) -> void:
	g = owner


func _wt_parse_args() -> void:
	_wt_positions = []
	_wt_beacon = Vector2.INF
	_wt_streak = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-pos="):
			var parts: PackedStringArray = a.trim_prefix("--shot-pos=").split(",")
			if parts.size() == 2:
				_wt_positions.append(Vector2(float(parts[0]), float(parts[1])))
		elif a.begins_with("--shot-beacon="):
			var bparts: PackedStringArray = a.trim_prefix("--shot-beacon=").split(",")
			if bparts.size() == 2:
				_wt_beacon = Vector2(float(bparts[0]), float(bparts[1]))
		elif a == "--shot-streak":
			_wt_streak = true


func _update_workerTshots(delta: float) -> void:
	if _wt_positions.is_empty() and not _wt_staged:
		_wt_parse_args()
		_wt_staged = true
	if _wt_positions.is_empty():
		print("WORKERTSHOTS DONE (no --shot-pos= given)")
		g.get_tree().quit()
		return
	_wt_timer += delta
	var stage = int(_wt_timer / 1.0)
	if stage == _wt_stage:
		return
	_wt_stage = stage
	var lp = g._get_local_player()
	if stage >= 1 and stage <= _wt_positions.size() * 2:
		var idx = (stage - 1) / 2
		if stage % 2 == 1:
			# Setup: teleport the player to the staged spot.
			if lp != null:
				lp.position = _wt_positions[idx]
				lp.sync_position = lp.position
				lp.velocity = Vector2.ZERO
				if lp._camera != null:
					lp._camera.reset_smoothing()
			g.smoke_test._smoke_set_move(null)
			g.smoke_test._smoke_set_aim(null)
			g.smoke_test._smoke_set_fire(false)
			if idx == 0:
				# First setup only: stage the beacon + streak lines
				# so the first capture shows them live.
				if _wt_beacon != Vector2.INF:
					g.skyfall_dynamics._sf_build_beacon(_wt_beacon)
				if _wt_streak and lp != null:
					g._kill_streaks.clear()
					g._best_streaks.clear()
					g._first_blood_done = false
					# Spawn the TestBot so the feed lines name a real
					# victim (same spawn the KILLFEED test uses).
					if g.players_node.get_node_or_null("99") == null:
						g._do_spawn(99, "TestBot", 0, 0)
					var kid := int(lp.peer_id)
					g.game_feed.announce_kill(kid, 99, 5)
					g.game_feed.announce_kill(kid, 99, 5)
		else:
			g.smoke_test._capture_shot("user://shot_workerT_%d.png" % (idx + 1))
	elif stage > _wt_positions.size() * 2:
		print("WORKERTSHOTS DONE")
		g.get_tree().quit()

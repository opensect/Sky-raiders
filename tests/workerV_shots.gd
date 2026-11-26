class_name WorkerVShots
extends RefCounted


# QA-145 (v4.1, Worker V): staged screenshots for the convenience +
# engagement fixes — the end screen (host view: "You win!" for a
# team win, own row marked ► + (YOU), rematch hint line) and the
# flag-capture feed line (bigger, longer-lived, with the win
# fanfare). Runs as auto-host; the countdown is skipped (game.gd
# _is_test_mode). Two captures, 1.5 s apart:
#   user://shot_workerV_1.png — end screen
#   user://shot_workerV_2.png — capture feed line over live play
# The end screen is faked with show_end_screen (same path the
# features test uses); _stats_recorded is set first so the fake
# rows never touch the saved lifetime stats.


var g # the owner (game.gd)

var _workerV_shots: bool = false
var _wv_timer: float = 0.0
var _wv_stage: int = -1
var _wv_staged: bool = false


func _init(owner) -> void:
	g = owner


func _update_workerVshots(delta: float) -> void:
	if not _wv_staged:
		_wv_staged = true
	_wv_timer += delta
	var stage = int(_wv_timer / 1.5)
	if stage == _wv_stage:
		return
	_wv_stage = stage
	if stage == 1:
		# Stage the end screen: local player on RED (team 0) so
		# a "RED TEAM" win reads as "You win!", rows carrying
		# peer ids so the local row shows ► + (YOU).
		var lp = g._get_local_player()
		if lp == null:
			g._do_spawn(1, "Player", 0, 0)
			lp = g._get_local_player()
		if lp != null:
			lp.team = 0
		g._stats_recorded = true
		var rows := [
			{"id": 1, "name": "Player", "kills": 7, "deaths": 3, "team": 0, "color": Color(1, 0, 0), "rounds": 0, "shots": 30, "hits": 18, "streak": 4},
			{"id": 99, "name": "TestBot", "kills": 4, "deaths": 6, "team": 1, "color": Color(0, 0, 1), "rounds": 0, "shots": 20, "hits": 5, "streak": 2},
		]
		g.show_end_screen("RED TEAM", "reached 9 points!", rows)
	elif stage == 2:
		g.smoke_test._capture_shot("user://shot_workerV_1.png")
	elif stage == 3:
		# Back to live play: hide the end panel, then post a
		# full capture (+3 pts) so the bigger, longer feed line
		# shows at the top-left.
		g.end_panel.visible = false
		g.match_over = false
		g._first_blood_done = true # no FIRST BLOOD side-line: the shot is about the capture line
		g._ctf_feed("⚑ Player captured the flag! +3 pts  RED 3 — 0 BLUE", Color(1.0, 0.3, 0.3))
		g.game_feed.announce_kill(99, 1, 5)
	elif stage == 4:
		g.smoke_test._capture_shot("user://shot_workerV_2.png")
	elif stage > 4:
		print("WORKERVSHOTS DONE")
		g.get_tree().quit()

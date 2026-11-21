class_name ReplsimTest
extends RefCounted


# QA-140 (v3.15): extracted from tests/net_test.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `g` (dependency injection).


var g # the owner (tests/net_test.gd)

var _repl_sim_test: bool = false
var _repl_sim_step: int = 0
var _repl_sim_timer: float = 0.0
var _repl_sim_passed: int = 0
var _repl_sim_failed: int = 0
var _repl_sim_done: bool = false
var _repl_sim_sent: Array = [] # payloads _send_all_players_to recorded in sim mode
var _repl_sim_shadow = null # second Game instance playing the client
var _repl_sim_server_list: Array = []
var _repl_sim_move_start: Vector2 = Vector2.ZERO # CONTROLS-ATTACH snapshot
var _repl_sim_c2s_start: Vector2 = Vector2.ZERO # QA-053 RPC-C2S baseline (server pid-2 pos)
var _repl_sim_s2c_start: Vector2 = Vector2.ZERO # QA-053 RPC-S2C baseline (shadow pid-1 pos)
var _repl_sim_seq: int = 0 # QA-053: snapshot sequence for streamed snapshots
var _repl_sim_stream_x: float = 0.0 # QA-053: streamed snapshot target x (steady +5 px/frame)
var _repl_sim_stream_y: float = 0.0 # QA-053: streamed snapshot target y
var _repl_sim_track_prev: Vector2 = Vector2.INF # QA-053: smoothness tracker, previous pos
var _repl_sim_track_max_step: float = 0.0 # QA-053: biggest single-frame step RATE (px/s) seen
var _repl_sim_track_max_back: float = 0.0 # QA-053: biggest backward (snap-back) step seen
var _repl_sim_track_best_x: float = -INF # QA-053: furthest forward x reached (snap-back baseline)
var _repl_sim_warm_done: bool = false # QA-053: warm-up window passed (buffer full, tracking live)
var _repl_sim_bullet_a = null # QA-055: server instance bullet under test
var _repl_sim_bullet_b = null # QA-055: shadow instance bullet under test
var _repl_sim_bullet_max_err: float = 0.0 # QA-055: max pos error between the two bullets
var _repl_sim_bullet_max_step: float = 0.0 # QA-055: max step RATE (px/s) of the shadow bullet
var _repl_sim_bullet_prev_b: Vector2 = Vector2.INF # QA-055: previous shadow bullet pos
var _repl_sim_bullet_frames: int = 0 # QA-055: frames both bullets were tracked
var _repl_sim_kill_k0: int = 0 # QA-069: killer kills before the kill-chain steps
var _repl_sim_kill_d0: int = 0 # QA-069: victim deaths before the kill-chain steps
var _repl_sim_kill_feed0: int = 0 # QA-069: kill-feed entries before a kill-chain step
var _repl_sim_kill_lock_wait: bool = false # QA-069: step 15/16 is waiting out the 1 s QA-031 lock
var _repl_sim_kill_snaps_done: bool = false # QA-069: step 16 score snapshots already delivered to the shadow
var _repl_sim_burst_pending: Array = [] # QA-068: step 17 snapshots held back, then delivered in bursts (Wi-Fi jitter)
var _repl_sim_delayed: Array = [] # QA-073: step 18 snapshots held back 300 ms (delayed delivery)
var _repl_sim_last_snap: Dictionary = {} # QA-073: step 18 last snapshot actually delivered (duplicate probe)


func _init(owner) -> void:
	g = owner


func _update_replsimtest(delta: float) -> void:
	if _repl_sim_done:
		return
	_repl_sim_timer += delta
	if _repl_sim_step >= 11:
		_update_replsimtest_b(delta)
		return
	match _repl_sim_step:
		0:
			# Wait for the deferred self-spawn, then spawn the client.
			if _repl_sim_timer < 1.0:
				return
			g._do_spawn(2, "SimClient", 1, 0)
			g.net_test._repl_sim_check("SERVER-SPAWN", g.players_node.get_child_count() == 2 and g._spawn_data.size() == 2,
				"server players=%d spawn_data=%d (want 2/2)" % [g.players_node.get_child_count(), g._spawn_data.size()])
			_repl_sim_server_list = g._player_list_data()
			# Shadow client: a second Game instance (same map).
			var shadow = load("res://game.tscn").instantiate()
			_repl_sim_shadow = shadow
			g.get_tree().root.add_child(shadow)
			shadow._repl_sim_test = false # this instance owns the sim
			shadow._repl_sim_done = true
			_repl_sim_step = 1
			_repl_sim_timer = 0.0
		1:
			# Wait for the shadow's own deferred self-spawn, then reset
			# it to the v3.1 symptom state: 0 players, no local player.
			if _repl_sim_timer < 1.5:
				return
			for child in _repl_sim_shadow.players_node.get_children():
				child.queue_free()
			# Freeing is deferred: wait a frame before counting.
			_repl_sim_step = 2
			_repl_sim_timer = 0.0
		2:
			if _repl_sim_timer < 0.3:
				return
			_repl_sim_shadow._spawned.clear()
			_repl_sim_shadow._spawn_data.clear()
			_repl_sim_shadow._local_player = null
			_repl_sim_shadow._server_answered = false
			_repl_sim_shadow._update_hud(0.0)
			g.net_test._repl_sim_check("BUG-STATE", _repl_sim_shadow.players_node.get_child_count() == 0 and (_repl_sim_shadow.message_label.text == "Connecting..." or _repl_sim_shadow.message_label.text == "Starting..."),
				"shadow players=%d message='%s' (v3.1 symptom reproduced; a real ENet client shows 'Connecting...', the offline shadow shows 'Starting...')" % [_repl_sim_shadow.players_node.get_child_count(), _repl_sim_shadow.message_label.text])
			# The first spawn is "lost" (v3.1): deliver nothing. The
			# client retries -> server re-sends -> deliver by hand.
			_repl_sim_sent.clear()
			g._do_spawn(2, "SimClient", 1, 0) # retry: already spawned
			g.net_test._repl_sim_check("RETRY-RESEND", _repl_sim_sent.size() == 3 and g.players_node.get_child_count() == 2,
				"re-sent payloads=%d server players=%d (want 3 payloads, still 2 players)" % [_repl_sim_sent.size(), g.players_node.get_child_count()])
			g.net_test._repl_sim_deliver_recorded()
			_repl_sim_step = 3
			_repl_sim_timer = 0.0
		3:
			if _repl_sim_timer < 0.3:
				return
			_repl_sim_shadow._update_hud(0.0)
			var lp = _repl_sim_shadow.players_node.get_node_or_null("2")
			g.net_test._repl_sim_check("CLIENT-HEALED", _repl_sim_shadow.players_node.get_child_count() == 2 and lp != null,
				"shadow players=%d has_peer2=%s (want 2/true)" % [_repl_sim_shadow.players_node.get_child_count(), lp != null])
			g.net_test._repl_sim_check("CONNECTING-CLEARS", _repl_sim_shadow.message_label.text != "Connecting..." and _repl_sim_shadow._get_local_player() != null,
				"message='%s' local=%s (want no 'Connecting...', local player found)" % [_repl_sim_shadow.message_label.text, _repl_sim_shadow._get_local_player() != null])
			g.net_test._repl_sim_check("HOST-PLAYER-TOO", _repl_sim_shadow.players_node.get_node_or_null("1") != null,
				"host player visible on the client (v3.1 lost it as well)")
			# QA-053: there must be NO MultiplayerSynchronizer on the
			# player any more — the RPC snapshot channel is the only
			# channel (a leftover synchronizer would be a second
			# writer on the same position). Authority still 2.
			var sync_node = null
			if lp != null:
				for c in lp.get_children():
					if c is MultiplayerSynchronizer:
						sync_node = c
						break
			g.net_test._repl_sim_check("RPC-CHANNEL", sync_node == null and lp != null and lp.get_multiplayer_authority() == 2,
				"client player has synchronizer=%s authority=%s (want none/2 — snapshots are the only channel)" % [sync_node != null, lp.get_multiplayer_authority() if lp != null else -1])
			# Double delivery must stay idempotent.
			_repl_sim_shadow.player_list_remote(_repl_sim_server_list)
			_repl_sim_step = 4
			_repl_sim_timer = 0.0
		4:
			if _repl_sim_timer < 0.3:
				return
			g.net_test._repl_sim_check("IDEMPOTENT", _repl_sim_shadow.players_node.get_child_count() == 2,
				"shadow players=%d after the list arrived twice (want 2)" % [_repl_sim_shadow.players_node.get_child_count()])
			# Disconnect: server forgets peer 2, client must despawn it.
			g._on_peer_disconnected(2)
			_repl_sim_shadow.despawn_player_remote(2)
			_repl_sim_step = 5
			_repl_sim_timer = 0.0
		5:
			if _repl_sim_timer < 0.3:
				return
			g.net_test._repl_sim_check("DESPAWN", g.players_node.get_child_count() == 1 and _repl_sim_shadow.players_node.get_child_count() == 1,
				"server players=%d shadow players=%d (want 1/1)" % [g.players_node.get_child_count(), _repl_sim_shadow.players_node.get_child_count()])
			# Steps 6-8: the signal-path checks (QA-047 audit items).
			# Re-spawn peer 2 on the server, then reset the shadow to
			# 0 players and heal it ONLY via the peer_connected
			# signal handler — the path a late joiner takes.
			g._do_spawn(2, "SimClient", 1, 0)
			for child in _repl_sim_shadow.players_node.get_children():
				child.queue_free()
			_repl_sim_shadow._spawned.clear()
			_repl_sim_shadow._spawn_data.clear()
			_repl_sim_shadow._local_player = null
			_repl_sim_shadow._server_answered = false
			_repl_sim_sent.clear()
			g._on_peer_connected(2)
			_repl_sim_step = 6
			_repl_sim_timer = 0.0
		6:
			if _repl_sim_timer < 0.3:
				return
			# SIGNAL-ORDER: the handlers were connected in _ready,
			# before any event could fire (a connection made after
			# the event is the classic missed-signal race).
			g.net_test._repl_sim_check("SIGNAL-ORDER", g.multiplayer.peer_connected.is_connected(g._on_peer_connected) and g.multiplayer.peer_disconnected.is_connected(g._on_peer_disconnected) and g.multiplayer.server_disconnected.is_connected(g._on_server_disconnected) and _repl_sim_shadow.multiplayer.peer_connected.is_connected(_repl_sim_shadow._on_peer_connected),
				"peer_connected/disconnected + server_disconnected connected on server and shadow (want all true)")
			# SIGNAL-PEER-CONNECTED: the recorded payloads came from
			# the signal handler; delivering them must heal the shadow.
			g.net_test._repl_sim_check("SIGNAL-PEER-CONNECTED", _repl_sim_sent.size() == 3,
				"payloads recorded by the signal handler=%d (want 3: spawn x2 + list)" % _repl_sim_sent.size())
			g.net_test._repl_sim_deliver_recorded()
			_repl_sim_shadow._update_hud(0.0)
			g.net_test._repl_sim_check("SIGNAL-HEALS", _repl_sim_shadow.players_node.get_child_count() == 2 and _repl_sim_shadow.players_node.get_node_or_null("2") != null and _repl_sim_shadow.message_label.text != "Connecting..." and _repl_sim_shadow.message_label.text != "Starting...",
				"shadow players=%d message='%s' (want 2, no waiting text)" % [_repl_sim_shadow.players_node.get_child_count(), _repl_sim_shadow.message_label.text])
			# SIGNAL-GUARD: _ready_announced blocks a double announce
			# (checked on the server branch, which returns before any
			# RPC — the guard logic is identical on the client).
			g._ready_announced = false
			g._announce_ready()
			var guard_set = g._ready_announced
			g._announce_ready()
			g.net_test._repl_sim_check("SIGNAL-GUARD", guard_set and g._ready_announced,
				"flag set after first announce=%s, still set after second (double announce is a no-op)=%s" % [guard_set, g._ready_announced])
			# CONTROLS-ATTACH: hold the move stick and watch the
			# shadow's local player (pid 1) actually move. The press
			# goes to THIS instance's stick: a player finds its game
			# via get_first_node_in_group("game"), and in this one
			# process that is the server instance — so the shadow's
			# player reads the server instance's input state. (On a
			# real phone there is only one game instance, so the
			# client reads its own.) The shadow's own stick state is
			# verified by the debug print in step 7.
			var lp0 = _repl_sim_shadow.players_node.get_node_or_null("1")
			if lp0 != null:
				_repl_sim_move_start = lp0.position
				g._on_touch_press(930, g.move_stick.get_global_rect().get_center() + Vector2(60, 0))
			_repl_sim_step = 7
			_repl_sim_timer = 0.0
		7:
			if _repl_sim_timer < 1.0:
				return
			var lp1 = _repl_sim_shadow.players_node.get_node_or_null("1")
			var moved := 0.0
			if lp1 != null:
				moved = lp1.position.distance_to(_repl_sim_move_start)
			g._on_touch_release(930)
			g.net_test._repl_sim_check("CONTROLS-ATTACH", moved > 50.0,
				"list-spawned local player moved %.0f px under the move stick (want >50)" % moved)
			_repl_sim_step = 8
			_repl_sim_timer = 0.0
		8:
			# Steps 8-11 (v3.4 QA-053): the RPC snapshot channel.
			# (a) NO MultiplayerSynchronizer on any of the 4 player
			# copies — one channel only. (b) Client->server: stream
			# snapshots of the shadow's pid-2 player moving steadily
			# right (+5 px/frame, as a 30/s snapshot flow would) and
			# hand-deliver each one to the server copy's
			# receive_move_snapshot — the same hand-delivery the
			# spawn RPCs get. Step 9 asserts the server copy follows
			# smoothly (moves, small steps, no snap-back).
			if _repl_sim_timer < 0.3:
				return
			var s_p1 = g.players_node.get_node_or_null("1")
			var s_p2 = g.players_node.get_node_or_null("2")
			var c_p1 = _repl_sim_shadow.players_node.get_node_or_null("1")
			var c_p2 = _repl_sim_shadow.players_node.get_node_or_null("2")
			var no_sync: bool = s_p1 != null and s_p2 != null and c_p1 != null and c_p2 != null \
				and not g.net_test._repl_sim_has_sync(s_p1) and not g.net_test._repl_sim_has_sync(s_p2) \
				and not g.net_test._repl_sim_has_sync(c_p1) and not g.net_test._repl_sim_has_sync(c_p2)
			g.net_test._repl_sim_check("NO-SYNC", no_sync,
				"synchronizer present on server p1/p2=%s/%s shadow p1/p2=%s/%s (want none — snapshots are the only channel)" % [
					g.net_test._repl_sim_has_sync(s_p1), g.net_test._repl_sim_has_sync(s_p2),
					g.net_test._repl_sim_has_sync(c_p1), g.net_test._repl_sim_has_sync(c_p2)])
			if s_p2 != null and c_p2 != null:
				_repl_sim_c2s_start = s_p2.position
				_repl_sim_stream_x = c_p2.position.x
				_repl_sim_stream_y = c_p2.position.y
				_repl_sim_seq = 0
				g.net_test._repl_sim_track_reset(s_p2.position)
				_repl_sim_seq += 1
				s_p2.receive_move_snapshot(g.net_test._repl_sim_snapshot(_repl_sim_seq,
					Vector2(_repl_sim_stream_x, _repl_sim_stream_y), Vector2(300, 0)))
			g.net_test._repl_sim_check("RPC-C2S-DELIVER", s_p2 != null and s_p2.sync_position == Vector2(_repl_sim_stream_x, _repl_sim_stream_y) and s_p2._snapshots.size() >= 1,
				"server pid-2 last snapshot=%s buffered=%d (want the delivered pos, >=1 snapshot)" % [s_p2.sync_position if s_p2 != null else Vector2.INF, s_p2._snapshots.size() if s_p2 != null else -1])
			_repl_sim_step = 9
			_repl_sim_timer = 0.0
		9:
			# Stream three snapshots per frame (30/s, +10 px each
			# in x, 300 px/s) and track the server copy's rendered
			# position: it must glide forward in small steps, never
			# freeze and jump, never snap back to an old position. The first 0.2 s is
			# warm-up (the interpolation buffer fills; the very first
			# snapshot pins the copy at the stream start, which is a
			# join-moment placement, not steady-state motion) — the
			# tracker starts after it so only steady motion is scored.
			var s_p2b = g.players_node.get_node_or_null("2")
			if s_p2b != null:
				# Stream at the sender's TRUE rate: 3 snapshots per
				# sim frame, 33 ms apart on the sender's clock
				# (30/s — the rate _send_move_snapshot actually
				# emits at). One snapshot per frame would stamp the
				# sender's clock 3x slower than wall time, which
				# no real sender does.
				for n9 in 3:
					_repl_sim_stream_x += 300.0 * 0.033
					_repl_sim_seq += 1
					s_p2b.receive_move_snapshot(g.net_test._repl_sim_snapshot(_repl_sim_seq,
						Vector2(_repl_sim_stream_x, _repl_sim_stream_y), Vector2(300, 0)))
				if _repl_sim_timer < 0.2:
					pass
				elif not _repl_sim_warm_done:
					_repl_sim_warm_done = true
					g.net_test._repl_sim_track_reset(s_p2b.position)
				else:
					g.net_test._repl_sim_track(s_p2b.position, delta)
			if _repl_sim_timer < 0.6:
				return
			var moved_c2s := 0.0
			if s_p2b != null:
				moved_c2s = s_p2b.position.distance_to(_repl_sim_c2s_start)
			g.net_test._repl_sim_check("RPC-C2S-MOVE", moved_c2s > 50.0,
				"server pid-2 copy moved %.0f px under the streamed snapshots (want >50)" % moved_c2s)
			g.net_test._repl_sim_check("RPC-C2S-SMOOTH", _repl_sim_track_max_step < 600.0 and _repl_sim_track_max_back < 5.0,
				"max step rate=%.0f px/s, max snap-back=%.1f px (want <600 px/s / <5 px — steady 300 px/s glide, no jumps)" % [_repl_sim_track_max_step, _repl_sim_track_max_back])
			# (d) setup: the HOST's player (pid 1) now moves +300 px
			# on the server; its snapshots are what the client must
			# render. The shadow's pid-1 copy is "local" in this one
			# process (both instances share the offline peer, unique
			# id 1), so its local branch would swallow a delivered
			# snapshot and never run the interpolation path. A real
			# client has unique id 2, so pid-1 is remote there.
			# Emulate that here by overriding the shadow copy's ROOT
			# authority to 2, then stream its snapshots in step 11.
			var s_p1b = g.players_node.get_node_or_null("1")
			var c_p1s = _repl_sim_shadow.players_node.get_node_or_null("1")
			if s_p1b != null and c_p1s != null:
				_repl_sim_s2c_start = c_p1s.position
				_repl_sim_stream_x = s_p1b.position.x + 300.0
				_repl_sim_stream_y = s_p1b.position.y
				c_p1s.set_multiplayer_authority(2)
				_repl_sim_seq = 1000
				g.net_test._repl_sim_track_reset(c_p1s.position)
				_repl_sim_seq += 1
				c_p1s.receive_move_snapshot(g.net_test._repl_sim_snapshot(_repl_sim_seq,
					Vector2(_repl_sim_stream_x, _repl_sim_stream_y), Vector2(300, 0)))
			g.net_test._repl_sim_check("RPC-S2C-DELIVER", c_p1s != null and c_p1s.sync_position == Vector2(_repl_sim_stream_x, _repl_sim_stream_y) and c_p1s._snapshots.size() >= 1,
				"shadow pid-1 last snapshot=%s buffered=%d (want the delivered pos, >=1 snapshot)" % [c_p1s.sync_position if c_p1s != null else Vector2.INF, c_p1s._snapshots.size() if c_p1s != null else -1])
			_repl_sim_warm_done = false
			_repl_sim_step = 10
			_repl_sim_timer = 0.0
		10:
			# Same stream, server -> client: the shadow's pid-1 copy
			# (authority overridden to 2 in step 9, so it runs the
			# remote branch) receives three snapshots per frame, as
			# in step 9. First 0.2 s warms the interpolation buffer
			# up; then the tracker scores steady motion only.
			var c_p1t = _repl_sim_shadow.players_node.get_node_or_null("1")
			if c_p1t != null:
				# Same true-rate stream as step 9 (3 snapshots per
				# frame, 33 ms apart on the sender's clock).
				for n10 in 3:
					_repl_sim_stream_x += 300.0 * 0.033
					_repl_sim_seq += 1
					c_p1t.receive_move_snapshot(g.net_test._repl_sim_snapshot(_repl_sim_seq,
						Vector2(_repl_sim_stream_x, _repl_sim_stream_y), Vector2(300, 0)))
				if _repl_sim_timer < 0.2:
					pass
				elif not _repl_sim_warm_done:
					_repl_sim_warm_done = true
					g.net_test._repl_sim_track_reset(c_p1t.position)
				else:
					g.net_test._repl_sim_track(c_p1t.position, delta)
			if _repl_sim_timer < 0.6:
				return
			var c_p1c = _repl_sim_shadow.players_node.get_node_or_null("1")
			var moved_s2c := 0.0
			if c_p1c != null:
				moved_s2c = c_p1c.position.distance_to(_repl_sim_s2c_start)
			g.net_test._repl_sim_check("RPC-S2C-MOVE", moved_s2c > 50.0,
				"shadow pid-1 copy moved %.0f px under the streamed snapshots (want >50)" % moved_s2c)
			g.net_test._repl_sim_check("RPC-S2C-SMOOTH", _repl_sim_track_max_step < 600.0 and _repl_sim_track_max_back < 5.0,
				"max step rate=%.0f px/s, max snap-back=%.1f px (want <600 px/s / <5 px — steady 300 px/s glide, no jumps)" % [_repl_sim_track_max_step, _repl_sim_track_max_back])
			# (e) QA-055 bullet tracking: fire the SAME rifle bullet
			# on both instances (identical spawn params, direct
			# calls = the spawn RPC hand-delivered) from open air
			# (1700, 455) on map 0, and compare the two flights
			# frame by frame in steps 11-12.
			var s_p1f = g.players_node.get_node_or_null("1")
			var muzzle := Vector2(1700, 455)
			if s_p1f != null:
				s_p1f.spawn_bullet(muzzle, Vector2.RIGHT, 1100.0, 12, 0, 1, 999, Vector2(1100, 0))
			var b_bullet = _repl_sim_shadow.obtain_bullet()
			b_bullet.setup(muzzle, Vector2.RIGHT, 1100.0, 12, 0, 1, false, 0.0, 1.2, 999, Vector2(1100, 0), 0.0)
			if b_bullet.get_parent() == null:
				_repl_sim_shadow.bullets_node.add_child(b_bullet)
			_repl_sim_bullet_a = null
			_repl_sim_bullet_b = null
			for b in g.bullets_node.get_children():
				if b.active:
					_repl_sim_bullet_a = b
			for b in _repl_sim_shadow.bullets_node.get_children():
				if b.active:
					_repl_sim_bullet_b = b
			_repl_sim_bullet_max_err = 0.0
			_repl_sim_bullet_max_step = 0.0
			_repl_sim_bullet_prev_b = Vector2.INF
			_repl_sim_bullet_frames = 0
			_repl_sim_step = 11
			_repl_sim_timer = 0.0


func _update_replsimtest_b(delta: float) -> void:
	# QA-140: cases 11-21 of the repl-sim step machine, split out of
	# _update_replsimtest so no .gd file is over 1000 lines. Called
	# from _update_replsimtest when _repl_sim_step >= 11.
	match _repl_sim_step:
		11:
			# Track both bullets every frame: their positions must
			# agree (same params, same fixed physics step) and the
			# shadow bullet must advance in small per-frame steps.
			if is_instance_valid(_repl_sim_bullet_a) and is_instance_valid(_repl_sim_bullet_b) \
					and _repl_sim_bullet_a.active and _repl_sim_bullet_b.active:
				var err: float = _repl_sim_bullet_a.position.distance_to(_repl_sim_bullet_b.position)
				if err > _repl_sim_bullet_max_err:
					_repl_sim_bullet_max_err = err
				if _repl_sim_bullet_prev_b != Vector2.INF:
					var st: float = _repl_sim_bullet_b.position.distance_to(_repl_sim_bullet_prev_b) / maxf(delta, 0.001)
					if st > _repl_sim_bullet_max_step:
						_repl_sim_bullet_max_step = st
				_repl_sim_bullet_prev_b = _repl_sim_bullet_b.position
				_repl_sim_bullet_frames += 1
			if _repl_sim_timer < 0.1:
				return
			var a_pos: Vector2 = _repl_sim_bullet_a.position if is_instance_valid(_repl_sim_bullet_a) else Vector2.INF
			var b_pos: Vector2 = _repl_sim_bullet_b.position if is_instance_valid(_repl_sim_bullet_b) else Vector2.INF
			g.net_test._repl_sim_check("BULLET-SPAWN", is_instance_valid(_repl_sim_bullet_a) and is_instance_valid(_repl_sim_bullet_b) \
					and _repl_sim_bullet_a.active and _repl_sim_bullet_b.active and a_pos.distance_to(b_pos) < 5.0,
				"server bullet=%s shadow bullet=%s (want both active, <5 px apart at spawn)" % [a_pos, b_pos])
			_repl_sim_step = 12
			_repl_sim_timer = 0.0
		12:
			# Keep tracking the flight for 1.0 s (~1100 px at rifle
			# speed, still inside map 0 and clear of platforms; the
			# bullet lives 1.2 s, so it is still flying at the check.
			# 1.0 s is needed because the sim runs ~10 fps under
			# llvmpipe — 0.5 s was only ~5 tracked frames.
			if is_instance_valid(_repl_sim_bullet_a) and is_instance_valid(_repl_sim_bullet_b) \
					and _repl_sim_bullet_a.active and _repl_sim_bullet_b.active:
				var err: float = _repl_sim_bullet_a.position.distance_to(_repl_sim_bullet_b.position)
				if err > _repl_sim_bullet_max_err:
					_repl_sim_bullet_max_err = err
				if _repl_sim_bullet_prev_b != Vector2.INF:
					var st: float = _repl_sim_bullet_b.position.distance_to(_repl_sim_bullet_prev_b) / maxf(delta, 0.001)
					if st > _repl_sim_bullet_max_step:
						_repl_sim_bullet_max_step = st
				_repl_sim_bullet_prev_b = _repl_sim_bullet_b.position
				_repl_sim_bullet_frames += 1
			if _repl_sim_timer < 1.0:
				return
			g.net_test._repl_sim_check("BULLET-TRACK", _repl_sim_bullet_frames >= 10 and _repl_sim_bullet_max_err < 10.0,
				"tracked %d frames, max position error=%.1f px (want >=10 frames, <10 px — same path, realtime)" % [_repl_sim_bullet_frames, _repl_sim_bullet_max_err])
			g.net_test._repl_sim_check("BULLET-SMOOTH", _repl_sim_bullet_max_step < 2200.0,
				"max step rate of the shadow bullet=%.0f px/s (want <2200 — rifle is 1100 px/s; a freeze-then-jump would be far faster)" % _repl_sim_bullet_max_step)
			# (f) QA-061 rifle straightness, remote: the server's
			# pid-1 player fires the rifle 5 times with aim dead
			# right and _recoil_accum forced to 1.5 (far past a
			# 2 s hold — pre-fix that is ±46° of spray). The shot
			# directions are recorded in shot_devs (the LOCAL
			# check). The last shot's direction is then fired
			# again from open air (1700, 455) on BOTH instances
			# with identical params — the spawn RPC hand-delivered
			# — and step 13 tracks the pair for straightness.
			var s_p1r = g.players_node.get_node_or_null("1")
			var twin_dir := Vector2.RIGHT
			if s_p1r != null:
				s_p1r.weapon = 0
				s_p1r.mag_ammo = 30
				s_p1r.aim_angle = 0.0
				s_p1r.velocity = Vector2.ZERO
				s_p1r._recoil_accum = 1.5
				s_p1r.shot_devs.clear()
				for i in 5:
					s_p1r._fire()
				if not s_p1r.shot_devs.is_empty():
					twin_dir = Vector2.RIGHT.rotated(float(s_p1r.shot_devs[s_p1r.shot_devs.size() - 1]))
			var muzzle_r := Vector2(1700, 455)
			var b_a = g.obtain_bullet()
			b_a.setup(muzzle_r, twin_dir, 1100.0, 12, 0, 1, false, 0.0, 1.2, 997, twin_dir * 1100.0, 0.0)
			if b_a.get_parent() == null:
				g.bullets_node.add_child(b_a)
			var b_b = _repl_sim_shadow.obtain_bullet()
			b_b.setup(muzzle_r, twin_dir, 1100.0, 12, 0, 1, false, 0.0, 1.2, 997, twin_dir * 1100.0, 0.0)
			if b_b.get_parent() == null:
				_repl_sim_shadow.bullets_node.add_child(b_b)
			_repl_sim_bullet_a = b_a
			_repl_sim_bullet_b = b_b
			_repl_sim_bullet_max_err = 0.0
			_repl_sim_bullet_max_step = 0.0
			_repl_sim_bullet_prev_b = Vector2.INF
			_repl_sim_bullet_frames = 0
			_repl_sim_step = 13
			_repl_sim_timer = 0.0
		13:
			# Track the rifle twin flight for 0.5 s and score
			# straightness on both sides: each bullet must hold
			# its line (travel angle ~0°) and the pair must agree.
			if is_instance_valid(_repl_sim_bullet_a) and is_instance_valid(_repl_sim_bullet_b) \
					and _repl_sim_bullet_a.active and _repl_sim_bullet_b.active:
				var err: float = _repl_sim_bullet_a.position.distance_to(_repl_sim_bullet_b.position)
				if err > _repl_sim_bullet_max_err:
					_repl_sim_bullet_max_err = err
				if _repl_sim_bullet_prev_b != Vector2.INF:
					var st: float = _repl_sim_bullet_b.position.distance_to(_repl_sim_bullet_prev_b) / maxf(delta, 0.001)
					if st > _repl_sim_bullet_max_step:
						_repl_sim_bullet_max_step = st
				_repl_sim_bullet_prev_b = _repl_sim_bullet_b.position
				_repl_sim_bullet_frames += 1
			if _repl_sim_timer < 0.5:
				return
			var s_p1s = g.players_node.get_node_or_null("1")
			var max_dev := 0.0
			var n_dev := 0
			if s_p1s != null:
				for d in s_p1s.shot_devs:
					max_dev = maxf(max_dev, absf(float(d)))
					n_dev += 1
			g.net_test._repl_sim_check("RIFLE-STRAIGHT-LOCAL", n_dev >= 5 and rad_to_deg(max_dev) < 0.5,
				"server rifle shots=%d max deviation=%.2f° at recoil 1.5 (want >=5 shots, <0.5° — pre-fix this was ±46°)" % [n_dev, rad_to_deg(max_dev)])
			var a_ok: bool = is_instance_valid(_repl_sim_bullet_a) and _repl_sim_bullet_a.active
			var b_ok: bool = is_instance_valid(_repl_sim_bullet_b) and _repl_sim_bullet_b.active
			var a_travel := 0.0
			var b_travel := 0.0
			if a_ok:
				a_travel = absf(rad_to_deg(_repl_sim_bullet_a.direction.angle()))
			if b_ok:
				b_travel = absf(rad_to_deg(_repl_sim_bullet_b.direction.angle()))
			g.net_test._repl_sim_check("RIFLE-STRAIGHT-REMOTE", a_ok and b_ok and _repl_sim_bullet_frames >= 4 and a_travel < 1.0 and b_travel < 1.0 and _repl_sim_bullet_max_err < 10.0,
				"tracked %d frames, server travel angle=%.2f° shadow travel angle=%.2f° max pair error=%.1f px (want >=4 frames, both alive, <1.0° each, <10 px)" % [_repl_sim_bullet_frames, a_travel, b_travel, _repl_sim_bullet_max_err])
			# Steps 14-16 (v3.6 QA-069): the full kill → respawn →
			# scoreboard chain on two simulated peers. The server
			# instance is peer 1 (killer) + peer 2 (victim); the
			# shadow is the second peer that must end with
			# IDENTICAL scores. Baselines are recorded here so any
			# stray damage from the rifle steps above cannot skew
			# the counts.
			var k_p1 = g.players_node.get_node_or_null("1")
			var k_p2 = g.players_node.get_node_or_null("2")
			if k_p1 != null:
				_repl_sim_kill_k0 = k_p1.kills
			if k_p2 != null:
				_repl_sim_kill_d0 = k_p2.deaths
				# Fresh life for the chain, whatever the rifle steps did.
				k_p2.health = 10
				k_p2.alive = true
				k_p2.life_state = 0
				k_p2._spawn_protect_timer = 0.0
			_repl_sim_kill_feed0 = g._kill_feed_entries.size()
			_repl_sim_step = 14
			_repl_sim_timer = 0.0
		14:
			# KILL-ONCE: one lethal hit = one death, one kill, one
			# feed line. A duplicate lethal hit in the same life
			# (new event id, victim already DYING) and a duplicate
			# credit attempt must change nothing — the LifeState
			# guard in _apply_damage and the QA-031 lock in
			# try_credit_kill.
			if _repl_sim_timer < 0.3:
				return
			var v14 = g.players_node.get_node_or_null("2")
			var k14 = g.players_node.get_node_or_null("1")
			var ok14 := false
			var det14 := ""
			if v14 != null and k14 != null:
				v14.take_hit(50, 1, Vector2.ZERO, 0.0, g.next_damage_event_id())
				var died_once: bool = v14.deaths == _repl_sim_kill_d0 + 1 and not v14.alive
				var credited: bool = g.try_credit_kill(1, 2, 0)
				var kill_once: bool = credited and k14.kills == _repl_sim_kill_k0 + 1
				v14.take_hit(50, 1, Vector2.ZERO, 0.0, g.next_damage_event_id())
				var dup_hit_ok: bool = v14.deaths == _repl_sim_kill_d0 + 1
				var credited2: bool = g.try_credit_kill(1, 2, 0)
				var dup_credit_ok: bool = not credited2 and k14.kills == _repl_sim_kill_k0 + 1
				var feed_once: bool = g._kill_feed_entries.size() == _repl_sim_kill_feed0 + 1
				ok14 = died_once and kill_once and dup_hit_ok and dup_credit_ok and feed_once
				det14 = "deaths=%d (want %d) kills=%d (want %d) dup_hit_deaths=%d dup_credit=%s feed=%d (want %d)" % [
					v14.deaths, _repl_sim_kill_d0 + 1, k14.kills, _repl_sim_kill_k0 + 1,
					v14.deaths, credited2, g._kill_feed_entries.size(), _repl_sim_kill_feed0 + 1]
			g.net_test._repl_sim_check("KILL-ONCE", ok14, det14)
			_repl_sim_kill_lock_wait = false
			_repl_sim_step = 15
			_repl_sim_timer = 0.0
		15:
			# KILL-SECOND-LIFE: after the 1 s QA-031 lock expires,
			# the victim respawns (fresh life, deaths kept) and a
			# second lethal hit credits a SECOND kill — the lock
			# must not block a genuine kill in the next life. The
			# feed must grow by exactly one more line (the death
			# watcher must not have added a second line for the
			# step-14 death in the meantime).
			if _repl_sim_timer < 1.2:
				return
			var v15 = g.players_node.get_node_or_null("2")
			var k15 = g.players_node.get_node_or_null("1")
			var ok15 := false
			var det15 := ""
			if v15 != null and k15 != null:
				v15._respawn()
				v15._spawn_protect_timer = 0.0 # protection expired (test only — real play waits it out)
				var respawned: bool = v15.alive and v15.health == 100 and v15.deaths == _repl_sim_kill_d0 + 1
				v15.health = 10
				v15.take_hit(50, 1, Vector2.ZERO, 0.0, g.next_damage_event_id())
				var died2: bool = v15.deaths == _repl_sim_kill_d0 + 2 and not v15.alive
				var credited15: bool = g.try_credit_kill(1, 2, 0)
				var kill2: bool = credited15 and k15.kills == _repl_sim_kill_k0 + 2
				var feed2: bool = g._kill_feed_entries.size() == _repl_sim_kill_feed0 + 2
				ok15 = respawned and died2 and kill2 and feed2
				det15 = "respawned=%s deaths=%d (want %d) kills=%d (want %d) feed=%d (want %d)" % [
					respawned, v15.deaths, _repl_sim_kill_d0 + 2, k15.kills, _repl_sim_kill_k0 + 2,
					g._kill_feed_entries.size(), _repl_sim_kill_feed0 + 2]
			g.net_test._repl_sim_check("KILL-SECOND-LIFE", ok15, det15)
			_repl_sim_kill_lock_wait = false
			_repl_sim_kill_snaps_done = false
			_repl_sim_step = 16
			_repl_sim_timer = 0.0
		16:
			# SCORE-SYNC + LAVA + REMOTE-DEATH: (a) the victim dies
			# to lava — no killer, no credit; the death watcher
			# announces it once AND sets the QA-031 lock, so a
			# stale in-flight bullet afterwards credits nothing;
			# (b) the final scores are hand-delivered to the shadow
			# as snapshots, and both peers must agree exactly;
			# (c) the shadow's copy of the dead victim must play
			# the death pose (QA-069 remote-die fix).
			if _repl_sim_timer < 1.2:
				return
			var v16 = g.players_node.get_node_or_null("2")
			var k16 = g.players_node.get_node_or_null("1")
			if v16 == null or k16 == null:
				g.net_test._repl_sim_check("SCORE-SYNC", false, "killer or victim missing")
				_repl_sim_done = true
				print("REPLSIM DONE: %d passed, %d failed (simulated wire only — live two-phone ENet still needs real phones, see BUGS.md QA-047/QA-053)" % [_repl_sim_passed, _repl_sim_failed])
				g.get_tree().quit()
				return
			if not _repl_sim_kill_lock_wait:
				# Respawn first and let the death watcher OBSERVE
				# alive frames (as in real play, where 2 s of spawn
				# protection guarantees them) before the lava kill
				# below — respawning and dying in the same frame
				# would leave the watcher's per-life "already fed"
				# flag stale from the previous life.
				v16._respawn()
				v16._spawn_protect_timer = 0.0
				_repl_sim_kill_feed0 = g._kill_feed_entries.size()
				_repl_sim_kill_lock_wait = true
				return
			if _repl_sim_timer < 1.6:
				return # watcher observes the fresh life
			if _repl_sim_timer < 2.0:
				# Lava kill, once: take_damage only fires while the
				# victim is still alive, so this branch is a no-op
				# on later frames. The watcher then has 0.4 s to
				# observe the death, lock, and announce before the
				# check at 2.0.
				if v16.alive:
					v16.take_damage(200, 0) # lava: from_id 0, no kill credit
				return
			if not _repl_sim_kill_snaps_done:
				var lava_ok: bool = v16.deaths == _repl_sim_kill_d0 + 3 and not v16.alive
				var stale_credit: bool = g.try_credit_kill(1, 2, 0)
				var lava_feed_ok: bool = g._kill_feed_entries.size() == _repl_sim_kill_feed0 + 1
				var lava_credit_ok: bool = not stale_credit and k16.kills == _repl_sim_kill_k0 + 2
				g.net_test._repl_sim_check("LAVA-NO-CREDIT", lava_ok and lava_feed_ok and lava_credit_ok,
					"deaths=%d (want %d) feed=%d (want %d) stale_credit=%s kills=%d (want %d — a lava death credits nobody)" % [
						v16.deaths, _repl_sim_kill_d0 + 3, g._kill_feed_entries.size(), _repl_sim_kill_feed0 + 1,
						stale_credit, k16.kills, _repl_sim_kill_k0 + 2])
				# Deliver the final scores to the shadow as
				# snapshots, exactly as the wire would.
				var c_p1 = _repl_sim_shadow.players_node.get_node_or_null("1")
				var c_p2 = _repl_sim_shadow.players_node.get_node_or_null("2")
				if c_p1 != null:
					_repl_sim_seq += 1
					c_p1.receive_move_snapshot(g.net_test._repl_sim_snapshot(_repl_sim_seq, k16.position, Vector2.ZERO, k16.kills, k16.deaths, true, 0))
				if c_p2 != null:
					_repl_sim_seq += 1
					c_p2.receive_move_snapshot(g.net_test._repl_sim_snapshot(_repl_sim_seq, v16.position, Vector2.ZERO, v16.kills, v16.deaths, false, 1))
				_repl_sim_kill_snaps_done = true
				return
			if _repl_sim_timer < 1.9:
				return # let the shadow run a physics frame (remote death pose)
			var c_p1f = _repl_sim_shadow.players_node.get_node_or_null("1")
			var c_p2f = _repl_sim_shadow.players_node.get_node_or_null("2")
			var sync_ok: bool = c_p1f != null and c_p2f != null \
				and c_p1f.kills == k16.kills and c_p1f.deaths == k16.deaths \
				and c_p2f.kills == v16.kills and c_p2f.deaths == v16.deaths
			g.net_test._repl_sim_check("SCORE-SYNC", sync_ok,
				"server killer K/D=%d/%d shadow K/D=%d/%d; server victim K/D=%d/%d shadow K/D=%d/%d (want identical on both peers)" % [
					k16.kills, k16.deaths, c_p1f.kills if c_p1f != null else -1, c_p1f.deaths if c_p1f != null else -1,
					v16.kills, v16.deaths, c_p2f.kills if c_p2f != null else -1, c_p2f.deaths if c_p2f != null else -1])
			var die_ok: bool = c_p2f != null and c_p2f._current_anim == "die"
			g.net_test._repl_sim_check("REMOTE-DEATH-POSE", die_ok,
				"shadow victim anim='%s' (want 'die' — pre-fix the remote copy kept its run/idle loop)" % [c_p2f._current_anim if c_p2f != null else "?"])
			# Step 17 (QA-068): sustained burst-jitter smoothness.
			_repl_sim_kill_snaps_done = false # reused as the step-17 setup flag
			_repl_sim_warm_done = false
			_repl_sim_step = 17
			_repl_sim_timer = 0.0
		17:
			# SUSTAINED BURST-JITTER: stream the server pid-2 copy
			# for 2 s (1 s at 300 px/s, then 1 s at 150 px/s), but
			# deliver the snapshots in BURSTS of 9 at a time, the
			# way Wi-Fi actually delivers them — nine packets
			# landing in the same frame after ~300 ms of silence.
			# The sender still emits at 30/s (3 snapshots per sim
			# frame, 33 ms apart on the sender's clock); only the
			# DELIVERY is bursty. With the old receipt-time stamps
			# all nine would share one timestamp, the lerp between
			# them would collapse, and the copy would jump; with
			# the sender's stamps (QA-068) the spacing stays a
			# steady 33 ms and the copy must glide. The step bar
			# here is 900 px/s, not the 600 of steps 9/10: the sim
			# samples at ~10 fps, so one sample can hold a whole
			# burst's catch-up (90 px in 0.1 s = 900 px/s) while
			# the same motion on a 60 fps phone is 5 px per
			# physics frame; a true freeze-then-teleport would
			# read several thousand px/s. Snap-back stays <5 px —
			# that is the real jump detector, and it reads 0.0.
			var s17 = g.players_node.get_node_or_null("2")
			if s17 == null:
				g.net_test._repl_sim_check("BURST-SMOOTH", false, "server pid-2 missing")
				_repl_sim_done = true
				print("REPLSIM DONE: %d passed, %d failed (simulated wire only — live two-phone ENet still needs real phones, see BUGS.md QA-047/QA-053)" % [_repl_sim_passed, _repl_sim_failed])
				g.get_tree().quit()
				return
			if not _repl_sim_kill_snaps_done:
				s17._respawn() # live again after the step-16 lava death
				s17._spawn_protect_timer = 0.0
				s17.position = Vector2(500, 455)
				s17._snapshots.clear()
				s17._last_snap_seq = -1
				_repl_sim_stream_x = 500.0
				_repl_sim_stream_y = 455.0
				_repl_sim_seq = 5000
				_repl_sim_burst_pending.clear()
				g.net_test._repl_sim_track_reset(s17.position)
				_repl_sim_kill_snaps_done = true
				_repl_sim_seq += 1
				s17.receive_move_snapshot(g.net_test._repl_sim_snapshot(_repl_sim_seq,
					Vector2(_repl_sim_stream_x, _repl_sim_stream_y), Vector2(300, 0)))
				return
			var speed17 = 300.0 if _repl_sim_timer < 1.0 else 150.0
			# The sender emits 3 snapshots per sim frame (30/s):
			# each advances the sender clock 33 ms and the position
			# by speed x 33 ms. Delivery is bursty (9 at a time).
			for n17 in 3:
				_repl_sim_stream_x += speed17 * 0.033
				_repl_sim_seq += 1
				_repl_sim_burst_pending.append(g.net_test._repl_sim_snapshot(_repl_sim_seq,
					Vector2(_repl_sim_stream_x, _repl_sim_stream_y), Vector2(speed17, 0)))
			if _repl_sim_burst_pending.size() >= 9:
				for snap17 in _repl_sim_burst_pending:
					s17.receive_move_snapshot(snap17)
				_repl_sim_burst_pending.clear()
			if _repl_sim_timer < 0.5:
				pass # warm-up: buffer fills, tracker off
			elif not _repl_sim_warm_done:
				_repl_sim_warm_done = true
				g.net_test._repl_sim_track_reset(s17.position)
			else:
				g.net_test._repl_sim_track(s17.position, delta)
			if _repl_sim_timer < 2.3:
				return
			var moved17: float = s17.position.distance_to(Vector2(500, 455))
			g.net_test._repl_sim_check("BURST-SMOOTH", _repl_sim_track_max_step < 900.0 and _repl_sim_track_max_back < 5.0,
				"max step rate=%.0f px/s, max snap-back=%.1f px over 2 s of burst delivery (want <900 px/s / <5 px — steady glide, no jumps; 900 not 600 because one ~10 fps sample can hold a whole burst's catch-up, see the step comment)" % [_repl_sim_track_max_step, _repl_sim_track_max_back])
			g.net_test._repl_sim_check("BURST-MOVE", moved17 > 300.0,
				"server pid-2 copy moved %.0f px in 2 s of burst delivery (want >300 — 1 s at 300 px/s + 1 s at 150 px/s, minus the 100 ms buffer lag)" % moved17)
			# Step 18 (QA-073): chaos delivery — loss + delay +
			# duplicate + out-of-order, the Wi-Fi shapes steps 9/10/17
			# never produced. _repl_sim_kill_snaps_done is reused as
			# the step-18 setup flag, as in step 17.
			_repl_sim_kill_snaps_done = false
			_repl_sim_warm_done = false
			_repl_sim_step = 18
			_repl_sim_timer = 0.0
		18:
			# CHAOS DELIVERY: stream the server pid-2 copy for 2 s
			# at 300 px/s, but corrupt the delivery the way bad Wi-Fi
			# does — every 7th snapshot is DROPPED (never arrives),
			# every 11th is delivered TWICE, every 5th is DELAYED
			# 300 ms (so it lands after newer snapshots and must be
			# dropped as out-of-order), the rest arrive in bursts of
			# 9. The copy must still glide (no teleport, no snap-back)
			# and the receiver must COUNT each fault (lost / dup /
			# ooo) instead of silently swallowing it. The step bar
			# here is 2000 px/s, derived from the step clamp, not
			# fitted to a run: after a loss gap the copy legitimately
			# chases at the designed clamp (700 px/s + 20 px slack
			# = 31.7 px per physics frame), and one ~10 fps sample
			# can hold 6 physics frames of that chase (6 x 31.7 =
			# 190 px in 0.1 s = 1900 px/s — runs read 780, 922,
			# 1879, 930). A genuine teleport — a 600 px snap in one
			# sample — reads 6000 px/s and still fails the bar.
			# Snap-back stays <5 px — that is the real jump
			# detector, and it reads 0.0 in every run.
			var s18 = g.players_node.get_node_or_null("2")
			if s18 == null:
				g.net_test._repl_sim_check("CHAOS-SMOOTH", false, "server pid-2 missing")
				_repl_sim_done = true
				print("REPLSIM DONE: %d passed, %d failed (simulated wire only — live two-phone ENet still needs real phones, see BUGS.md QA-047/QA-053)" % [_repl_sim_passed, _repl_sim_failed])
				g.get_tree().quit()
				return
			if not _repl_sim_kill_snaps_done:
				s18._respawn() # live again after the step-16 lava death
				s18._spawn_protect_timer = 0.0
				s18.position = Vector2(500, 455)
				s18._snapshots.clear()
				s18._last_snap_seq = -1
				# Fresh counters + fresh adaptive delay, so step 18
				# measures its own delivery faults from zero.
				s18._net_lost_count = 0
				s18._net_dup_count = 0
				s18._net_ooo_count = 0
				s18._net_recv_count = 0
				s18._interp_delay = PhysicsConfig.INTERP_BUFFER
				s18._jitter_ewma = 0.0
				s18._prev_snap_sender_t = -1.0
				_repl_sim_stream_x = 500.0
				_repl_sim_stream_y = 455.0
				_repl_sim_seq = 8000
				_repl_sim_burst_pending.clear()
				_repl_sim_delayed.clear()
				_repl_sim_last_snap = {}
				g.net_test._repl_sim_track_reset(s18.position)
				_repl_sim_kill_snaps_done = true
				_repl_sim_seq += 1
				var seed18 = g.net_test._repl_sim_snapshot(_repl_sim_seq,
					Vector2(_repl_sim_stream_x, _repl_sim_stream_y), Vector2(300, 0))
				s18.receive_move_snapshot(seed18)
				_repl_sim_last_snap = seed18
				return
			for n18 in 3:
				_repl_sim_stream_x += 300.0 * 0.033
				_repl_sim_seq += 1
				var snap18 = g.net_test._repl_sim_snapshot(_repl_sim_seq,
					Vector2(_repl_sim_stream_x, _repl_sim_stream_y), Vector2(300, 0))
				if _repl_sim_seq % 7 == 0:
					pass # DROPPED — packet loss (never delivered)
				elif _repl_sim_seq % 11 == 0:
					_repl_sim_burst_pending.append(snap18)
					_repl_sim_burst_pending.append(snap18) # DUPLICATE
				elif _repl_sim_seq % 5 == 0:
					_repl_sim_delayed.append({"at": _repl_sim_timer + 0.3, "snap": snap18}) # DELAYED 300 ms
				else:
					_repl_sim_burst_pending.append(snap18)
			# Delayed snapshots whose time came: they land AFTER
			# newer ones, so the sequence guard must drop them as
			# out-of-order (counted in _net_ooo_count). _last_snap
			# tracks the last ACCEPTED snapshot (seq == the
			# receiver's newest) — a dropped delayed one must NOT
			# become the duplicate probe's target, or the probe
			# would count an out-of-order instead of a duplicate.
			var still_delayed18: Array = []
			for d18 in _repl_sim_delayed:
				if float(d18["at"]) <= _repl_sim_timer:
					s18.receive_move_snapshot(d18["snap"])
					if int((d18["snap"] as Dictionary).get("seq", -1)) == s18._last_snap_seq:
						_repl_sim_last_snap = d18["snap"]
				else:
					still_delayed18.append(d18)
			_repl_sim_delayed = still_delayed18
			if _repl_sim_burst_pending.size() >= 9:
				for snap18b in _repl_sim_burst_pending:
					s18.receive_move_snapshot(snap18b)
					if int((snap18b as Dictionary).get("seq", -1)) == s18._last_snap_seq:
						_repl_sim_last_snap = snap18b
				_repl_sim_burst_pending.clear()
			if _repl_sim_timer < 0.5:
				pass # warm-up: buffer fills, tracker off
			elif not _repl_sim_warm_done:
				_repl_sim_warm_done = true
				g.net_test._repl_sim_track_reset(s18.position)
			else:
				g.net_test._repl_sim_track(s18.position, delta)
			if _repl_sim_timer < 2.3:
				return
			var moved18: float = s18.position.distance_to(Vector2(500, 455))
			g.net_test._repl_sim_check("CHAOS-SMOOTH", _repl_sim_track_max_step < 2000.0 and _repl_sim_track_max_back < 5.0,
				"max step rate=%.0f px/s, max snap-back=%.1f px over 2 s of chaos delivery (want <2000 px/s / <5 px — loss + delay + duplicates must not teleport the copy; 2000 is the clamp-derived bound, see the step comment)" % [_repl_sim_track_max_step, _repl_sim_track_max_back])
			g.net_test._repl_sim_check("CHAOS-MOVE", moved18 > 200.0,
				"server pid-2 copy moved %.0f px in 2 s of chaos delivery (want >200 — the stream still gets through)" % moved18)
			g.net_test._repl_sim_check("CHAOS-LOSS-DUP-OOO", s18._net_lost_count > 0 and s18._net_dup_count > 0 and s18._net_ooo_count > 0,
				"lost=%d dup=%d ooo=%d recv=%d (want all >0 — the chaos actually happened and the receiver counted every fault)" % [s18._net_lost_count, s18._net_dup_count, s18._net_ooo_count, s18._net_recv_count])
			# Explicit duplicate probe: re-deliver the last snapshot
			# that actually arrived — same seq, so it must be counted
			# and ignored, and the copy must not move backwards.
			var dup_before: int = s18._net_dup_count
			s18.receive_move_snapshot(_repl_sim_last_snap)
			g.net_test._repl_sim_check("CHAOS-DUP-IGNORED", s18._net_dup_count == dup_before + 1,
				"dup=%d (want %d — the re-delivered snapshot was counted and ignored)" % [s18._net_dup_count, dup_before + 1])
			# Explicit out-of-order probe: an older snapshot (2 seqs
			# back, 100 px behind) must be counted and ignored.
			var ooo_before: int = s18._net_ooo_count
			s18.receive_move_snapshot(g.net_test._repl_sim_snapshot(s18._last_snap_seq - 2, s18.position - Vector2(100, 0), Vector2(300, 0)))
			g.net_test._repl_sim_check("CHAOS-OOO-IGNORED", s18._net_ooo_count == ooo_before + 1,
				"ooo=%d (want %d — the stale snapshot was counted and ignored, no snap-back)" % [s18._net_ooo_count, ooo_before + 1])
			# Step 19 (QA-073): prediction + reconciliation on the
			# LOCAL player. _repl_sim_kill_snaps_done is reused as
			# the step-19 setup flag; _repl_sim_warm_done as the
			# "small correction applied" phase flag.
			_repl_sim_kill_snaps_done = false
			_repl_sim_warm_done = false
			_repl_sim_step = 19
			_repl_sim_timer = 0.0
		19:
			# PREDICTION + RECONCILIATION: the server pid-1 player
			# is local here, so it predicts (moves with no network
			# wait) and must reconcile against an authoritative
			# correction. (a) A small 40 px correction must NOT snap
			# the player in the correction frame — it blends in.
			# (b) Half a second later the player must have arrived
			# within 10 px of the corrected position. (c) A large
			# 500 px correction DOES snap at once (teleport-class).
			# (d) A stale correction (older corr_seq) is ignored.
			# (e) The prediction ring must hold recent frames.
			var lp19 = g.players_node.get_node_or_null("1")
			if lp19 == null:
				g.net_test._repl_sim_check("RECONCILE-NO-SNAP", false, "local player missing")
				_repl_sim_done = true
				print("REPLSIM DONE: %d passed, %d failed (simulated wire only — live two-phone ENet still needs real phones, see BUGS.md QA-047/QA-053)" % [_repl_sim_passed, _repl_sim_failed])
				g.get_tree().quit()
				return
			if not _repl_sim_kill_snaps_done:
				# Start on open floor: the step-7 move left the
				# player against a wall, and a +40 px correction
				# from there would stop at the wall instead of
				# arriving. A fresh validated spawn is clear.
				var game19 = g.get_tree().get_first_node_in_group("game")
				if game19 != null:
					lp19.position = game19.get_valid_spawn_point(lp19.player_index, lp19.peer_id)
					lp19.velocity = Vector2.ZERO
				_repl_sim_move_start = lp19.position
				_repl_sim_kill_snaps_done = true
				return
			if _repl_sim_timer < 0.3:
				return
			if not _repl_sim_warm_done:
				var before19: Vector2 = lp19.position
				lp19.apply_authoritative_correction(before19 + Vector2(40, 0), Vector2.ZERO, 9001)
				g.net_test._repl_sim_check("RECONCILE-NO-SNAP", lp19.position.distance_to(before19) < 1.0,
					"pos moved %.1f px in the correction frame (want <1 — a 40 px correction blends, it does not snap)" % lp19.position.distance_to(before19))
				_repl_sim_move_start = before19 + Vector2(40, 0)
				_repl_sim_warm_done = true
				return
			if _repl_sim_timer < 0.8:
				return
			# Horizontal distance only: the blend moves the player
			# toward the corrected position, but gravity still owns
			# the vertical — if the +40 px nudge carries the player
			# off a platform edge it falls while it blends, and a
			# full 2D distance would blame the blend for the fall.
			var arrived19: float = absf(lp19.position.x - _repl_sim_move_start.x)
			g.net_test._repl_sim_check("RECONCILE-BLEND", arrived19 < 10.0,
				"horizontal distance to the corrected position=%.1f px after 0.5 s (want <10 — the blend arrived; pos=%s vel=%s on_floor=%s)" % [arrived19, lp19.position, lp19.velocity, lp19.is_on_floor()])
			var big_before: Vector2 = lp19.position
			lp19.apply_authoritative_correction(big_before + Vector2(500, 0), Vector2.ZERO, 9002)
			g.net_test._repl_sim_check("RECONCILE-BIG-SNAP", lp19.position.distance_to(big_before + Vector2(500, 0)) < 1.0,
				"pos=%s (want %s — a 500 px correction snaps at once, it does not glide across the map)" % [lp19.position, big_before + Vector2(500, 0)])
			var stale_before: Vector2 = lp19.position
			lp19.apply_authoritative_correction(stale_before + Vector2(40, 0), Vector2.ZERO, 9001)
			g.net_test._repl_sim_check("RECONCILE-STALE", lp19.position.distance_to(stale_before) < 1.0,
				"pos moved %.1f px on a stale correction (want <1 — corr_seq 9001 after 9002 is ignored)" % lp19.position.distance_to(stale_before))
			g.net_test._repl_sim_check("PREDICT-HISTORY", lp19._pred_pos.size() >= 10,
				"prediction ring holds %d frames (want >=10 — the local simulation records what it predicted)" % lp19._pred_pos.size())
			# Step 20 (QA-073): the net-stats display. The sim runs
			# without --net-stats, so the panel must start hidden.
			_repl_sim_kill_snaps_done = false
			_repl_sim_step = 20
			_repl_sim_timer = 0.0
		20:
			# NET-STATS DISPLAY: hidden by default, shows on toggle
			# with the spec §7 fields (RTT, FPS, delay), hides again
			# on the next toggle. The sim has no live ENet peer, so
			# RTT reads "--" — the check is that the panel and its
			# fields render, not that a real RTT exists.
			if not _repl_sim_kill_snaps_done:
				g.net_test._repl_sim_check("NETSTATS-HIDDEN-DEFAULT", g._net_stats_label != null and not g._net_stats_label.visible,
					"label visible=%s (want false — dev-only, hidden by default, never in normal play)" % [g._net_stats_label.visible if g._net_stats_label != null else "?"])
				g.toggle_net_stats()
				g._update_net_stats(1.0) # force a refresh past the 0.25 s throttle
				_repl_sim_kill_snaps_done = true
				_repl_sim_timer = 0.0
				return
			if _repl_sim_timer < 0.3:
				return
			var txt20 = g._net_stats_label.text if g._net_stats_label != null else ""
			g.net_test._repl_sim_check("NETSTATS-SHOWS", g._net_stats_label != null and g._net_stats_label.visible and "RTT" in txt20 and "FPS" in txt20 and "delay" in txt20,
				"visible=%s text='%s' (want visible with RTT/FPS/delay fields)" % [g._net_stats_label.visible if g._net_stats_label != null else false, txt20.replace("\n", " | ")])
			g.toggle_net_stats()
			g.net_test._repl_sim_check("NETSTATS-HIDES", g._net_stats_label != null and not g._net_stats_label.visible,
				"visible=%s after toggle off (want false)" % [g._net_stats_label.visible if g._net_stats_label != null else "?"])
			# Step 21 (QA-075): the remote muzzle flash — the
			# shadow's pid-1 copy must show its flash while a
			# firing snapshot stream runs, and the flash must end
			# by itself when the stream stops.
			_repl_sim_warm_done = false
			_repl_sim_step = 21
			_repl_sim_timer = 0.0
		21:
			# REMOTE-MUZZLE: stream firing snapshots to the
			# shadow's pid-1 copy (authority 2 since step 9, so it
			# runs the remote branch) for 0.3 s, then stop and
			# watch the flash end. The remote flash timer is
			# 0.25 s: long enough to bridge the ~0.1 s frames of
			# the sim (a per-weapon 0.05 s flash would expire
			# between frames here), short enough to be gone 0.4 s
			# after the stream stops. Kills/deaths are passed
			# through so the stream does not reset the scores
			# step 16 set on the shadow.
			var c_p1m = _repl_sim_shadow.players_node.get_node_or_null("1")
			if c_p1m != null:
				# QA-075b: the stream runs ONLY before the SHOWS
				# check (the `not _repl_sim_warm_done` gate). The
				# first version of this step re-entered the stream
				# after SHOWS reset the timer (timer < 0.3 again),
				# so the muzzle timer kept refreshing and HIDES
				# read visible=true 0.4 s after the "stop" — the
				# stream had in fact stopped only ~0.1 s earlier.
				# With the gate, the 0.4 s wait is a real silence.
				if _repl_sim_timer < 0.3 and not _repl_sim_warm_done:
					_repl_sim_seq += 1
					var snap21 = g.net_test._repl_sim_snapshot(_repl_sim_seq, c_p1m.position, Vector2.ZERO, c_p1m.kills, c_p1m.deaths, true, 0)
					snap21["fire"] = 1
					c_p1m.receive_move_snapshot(snap21)
					return
				if not _repl_sim_warm_done:
					g.net_test._repl_sim_check("REMOTE-MUZZLE-SHOWS", c_p1m._muzzle.visible and c_p1m._muzzle_timer > 0.0 and c_p1m.alive,
						"remote muzzle visible=%s timer=%.2f alive=%s (want true/>0/true while the firing stream runs)" % [c_p1m._muzzle.visible, c_p1m._muzzle_timer, c_p1m.alive])
					_repl_sim_warm_done = true
					_repl_sim_timer = 0.0
					return
				if _repl_sim_timer < 0.4:
					return
				g.net_test._repl_sim_check("REMOTE-MUZZLE-HIDES", not c_p1m._muzzle.visible,
					"remote muzzle visible=%s 0.4 s after the firing stream stopped (want false — a flash, not stuck on)" % c_p1m._muzzle.visible)
			_repl_sim_done = true
			print("REPLSIM DONE: %d passed, %d failed (simulated wire only — live two-phone ENet still needs real phones, see BUGS.md QA-047/QA-053)" % [_repl_sim_passed, _repl_sim_failed])
			g.get_tree().quit()


class_name PlayerSync
extends RefCounted


# QA-140 (v3.15): extracted from player/player.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `p` (dependency injection).


var p # the owner (player/player.gd)


func _init(owner) -> void:
	p = owner


# QA-053 - movement / state replication over the PROVEN RPC channel.
# v3.3's MultiplayerSynchronizer is deleted: on real phones it delivered
# nothing (its packets are addressed by the synchronizer's node path,
# and a synchronizer created in _ready() gets an auto-uniquified name
# like "@MultiplayerSynchronizer@1335" that differs on every peer, so
# the remote peer has no node at the packet's path and drops it - the
# sim could never catch this because it hand-assigned sync_position
# directly, bypassing the wire entirely). RPCs, by contrast, are
# addressed by the PLAYER node's path (Players/<pid>), which is
# identical on every peer - the same reason spawn_bullet /
# spawn_grenade / spawn_player_remote all arrive on real phones.
#
# _send_move_snapshot runs on the OWNER only, at the spec's snapshot
# rate (PhysicsConfig.SNAPSHOT_INTERVAL = 0.033 s, 30/s, spec §21.F),
# and carries position + velocity + aim + facing + the visible state
# the synchronizer used to carry (weapon, health, kills, deaths,
# alive, fuel, life state, ammo, grenades, accuracy counters) - damage
# RPCs (take_hit / take_damage) go only to the victim's owning peer,
# and weapon switches / reloads are local-only writes, so without this
# payload the remote copies would show stale health, kills, weapons
# and ammo too. Combat stays host-authoritative: snapshots only RELAY
# values the host already decided via its RPCs; nothing here lets a
# client award itself damage, kills or pickups.
# One owner for the remote player's visible position: the snapshot
# buffer, consumed by the remote branch's _interp_position. No second
# channel touches position any more.
func _send_move_snapshot(force: bool = false) -> void:
	if not p.is_local_player():
		return
	# Offline harnesses have no peers to send to (and rpc() with no
	# peer would only spam the log at 30/s); the repl-sim calls
	# receive_move_snapshot directly instead. A host with nobody
	# connected yet has nobody to send to either.
	if not p.multiplayer.has_multiplayer_peer():
		return
	if p.multiplayer.get_peers().is_empty():
		return
	p._move_snap_seq += 1
	# QA-068: the snapshot carries the SENDER's clock ("st") and the
	# spawn-protection flag ("prot"). The receiver must interpolate
	# on the sender's timeline, not on arrival times (see
	# receive_move_snapshot): Wi-Fi arrival jitter otherwise becomes
	# spacing jitter in the buffer. "prot" lets the host's copy know
	# a remote victim is spawn-protected, so a lethal-looking hit
	# during protection is never credited as a kill (QA-069).
	p.rpc("receive_move_snapshot", {
		"seq": p._move_snap_seq, "st": Time.get_ticks_msec() / 1000.0,
		"prot": 1 if p._spawn_protect_timer > 0.0 else 0,
		"id": p.peer_id, # QA-073: player ID in every packet (spec §1) - was only implied by sender/node path
		"jet": 1 if p._jetpacking else 0, "fire": 1 if p._want_fire else 0, # QA-073: jetpack + firing state (spec §5)
		"rel": 1 if p.reloading else 0, "air": 1 if not p.is_on_floor() else 0, # QA-073: reload + airborne state (spec §5)
		"p": p.position, "v": p.velocity,
		"aim": p.aim_angle, "face": p.facing, "wpn": p.weapon,
		"hp": p.health, "k": p.kills, "d": p.deaths, "al": p.alive,
		"fuel": p.fuel, "ls": p.life_state, "mag": p.mag_ammo,
		"gr": p.grenades, "sf": p._shots_fired, "sh": p._shots_hit,
		# QA-112: Skyfall power-up state. "sh" is already taken by
		# _shots_hit, so the shield timer rides as "shd", and the
		# speed timer as "spd" (not "sp" - kept distinct on purpose).
		"shd": p.shield_timer, "spd": p.speed_timer,
		"inv": p.invisibility_timer, "jb": p.jetpack_boost_timer,
		"ab": p.active_boost_kind, "cf": p.carrying_flag,
		"sb": p.stored_boosts,
	})
	if force:
		# A forced send (respawn / stuck-recovery / score change)
		# already went out - do not send again on the next tick.
		p._move_snap_timer = 0.0


func receive_move_snapshot(snap: Dictionary) -> void:
	# Accept only the owner's snapshots (sender 0 = a direct local
	# call in the sim / tests, where there is no sender). A snapshot
	# for our OWN player is ignored - the local branch owns the local
	# position and must never be overwritten by a stale echo.
	var sender = p.multiplayer.get_remote_sender_id()
	if sender != 0 and sender != p.peer_id:
		return
	if p.is_local_player():
		return
	# QA-073: the packet carries its player ID (spec §1). An id of 0
	# means "unspecified" (hand-built / old dicts, and the repl-sim) -
	# accept it. Any other id that is not this player is a misrouted
	# packet and is ignored.
	var snap_id := int(snap.get("id", 0))
	if snap_id != 0 and snap_id != p.peer_id:
		return
	var seq := int(snap.get("seq", 0))
	# QA-073: count delivery faults before dropping. Unreliable RPCs
	# can arrive out of order or twice: only a newer sequence may
	# move the player, so an old packet can never drag a remote
	# player backwards (snap-back) after a newer one arrived. The
	# counters (lost by sequence gap, duplicate, out-of-order) feed
	# the net-stats display - previously this was silent.
	if seq == p._last_snap_seq:
		p._net_dup_count += 1
		return
	if seq < p._last_snap_seq:
		p._net_ooo_count += 1
		return
	if p._last_snap_seq >= 0 and seq > p._last_snap_seq + 1:
		p._net_lost_count += seq - p._last_snap_seq - 1
	p._last_snap_seq = seq
	p._net_recv_count += 1
	var now := Time.get_ticks_msec() / 1000.0
	# QA-073: updates-per-second over a rolling 1 s window.
	if p._net_ups_window_start <= 0.0:
		p._net_ups_window_start = now
	p._net_ups_count += 1
	if now - p._net_ups_window_start >= 1.0:
		p._net_ups = float(p._net_ups_count) / (now - p._net_ups_window_start)
		p._net_ups_count = 0
		p._net_ups_window_start = now
	var pos: Vector2 = snap.get("p", p.position)
	var vel: Vector2 = snap.get("v", Vector2.ZERO)
	p.sync_position = pos
	p.sync_velocity = vel
	p.aim_angle = float(snap.get("aim", p.aim_angle))
	p.facing = int(snap.get("face", p.facing))
	# QA-073: synced gameplay state (spec §5) - jetpack, firing,
	# reload, airborne. Old dicts without these keys keep the
	# previous values (get with the current value as default).
	p._remote_jetpacking = bool(int(snap.get("jet", 1 if p._remote_jetpacking else 0)))
	p._remote_firing = bool(int(snap.get("fire", 1 if p._remote_firing else 0)))
	p._remote_reloading = bool(int(snap.get("rel", 1 if p._remote_reloading else 0)))
	p._remote_airborne = bool(int(snap.get("air", 1 if p._remote_airborne else 0)))
	var new_weapon := int(snap.get("wpn", p.weapon))
	if new_weapon != p.weapon and new_weapon >= 0 and new_weapon < p.WEAPONS.size():
		p.weapon = new_weapon
		p._switch_dip_timer = 0.15 # QA-075: a remote copy dips its gun on switch too
		p._update_gun_texture()
	# QA-075: the remote muzzle flash. The snapshot stream (30/s)
	# refreshes this while the remote player is firing; 0.25 s
	# bridges the frames between snapshots, so the flash shows
	# steadily while firing and ends by itself when the stream
	# stops carrying fire=1. The local flash uses the shorter
	# per-weapon flash_t in _show_muzzle instead.
	if p._remote_firing:
		p._muzzle_timer = maxf(p._muzzle_timer, 0.25)
	p.health = int(snap.get("hp", p.health))
	p.kills = int(snap.get("k", p.kills))
	p.deaths = int(snap.get("d", p.deaths))
	p.alive = bool(snap.get("al", p.alive))
	p.fuel = float(snap.get("fuel", p.fuel))
	p.life_state = int(snap.get("ls", p.life_state))
	p.mag_ammo = int(snap.get("mag", p.mag_ammo))
	p.grenades = int(snap.get("gr", p.grenades))
	p._shots_fired = int(snap.get("sf", p._shots_fired))
	p._shots_hit = int(snap.get("sh", p._shots_hit))
	# QA-112: Skyfall power-up state (old dicts without these keys
	# keep the current values, same as the other synced fields).
	p.shield_timer = float(snap.get("shd", p.shield_timer))
	p.speed_timer = float(snap.get("spd", p.speed_timer))
	p.invisibility_timer = float(snap.get("inv", p.invisibility_timer))
	p.jetpack_boost_timer = float(snap.get("jb", p.jetpack_boost_timer))
	p.active_boost_kind = int(snap.get("ab", p.active_boost_kind))
	p.carrying_flag = int(snap.get("cf", p.carrying_flag))
	var sb: Array = snap.get("sb", p.stored_boosts)
	p.stored_boosts.clear()
	for v in sb:
		p.stored_boosts.append(int(v))
	# Feed the interpolation buffer. QA-068: each entry is stamped
	# with the SENDER's clock ("st", sent in the snapshot), NOT the
	# receipt time - the two phones' clocks are never compared (they
	# differ), the sender stamps only ever order and space the
	# sender's own snapshots, and the render timeline is anchored
	# to the newest sender stamp (see _interp_position). A snapshot
	# without "st" (old / hand-built dicts) falls back to the
	# receipt time, the pre-QA-068 behaviour. "rt" (receipt time)
	# is kept alongside so the receiver can tell how long it has
	# been since a packet arrived and dead-reckon through a gap.
	# "prot" refreshes this copy's spawn-protection timer so the
	# host's view of a remote victim's protection is real (QA-069);
	# when prot is 0 the local countdown is left to run down.
	var sender_t := float(snap.get("st", now))
	# QA-073: adaptive interpolation delay. Jitter is the mismatch
	# between arrival spacing and sender spacing: on clean Wi-Fi
	# both are ~33 ms (jitter ~0); when packets arrive in bursts
	# the arrival gaps are 0 ms then ~300 ms while the sender gaps
	# stay 33 ms (jitter ~tens of ms). The EWMA (alpha 0.1) tracks
	# it, the target delay is 80 ms + 1.5x jitter, clamped to
	# 80-250 ms, and the live delay slews toward the target at most
	# 10 ms per 0.5 s - slow enough that the delay never wobbles the
	# render timeline itself. A resync (long silence) resets the
	# jitter history: the gap is not Wi-Fi jitter, it is a rejoin.
	if p._prev_snap_sender_t >= 0.0 and now - p._last_snap_receipt <= 0.5:
		var arrival_gap = now - p._prev_snap_receipt_t
		var sender_gap = sender_t - p._prev_snap_sender_t
		var jitter := absf(arrival_gap - sender_gap)
		p._jitter_ewma = lerpf(p._jitter_ewma, jitter, 0.1)
		if now >= p._interp_delay_next_adjust:
			var target := clampf(0.08 + 1.5 * p._jitter_ewma, 0.08, 0.25)
			p._interp_delay = move_toward(p._interp_delay, target, 0.01)
			p._interp_delay_next_adjust = now + 0.5
	else:
		p._jitter_ewma = 0.0
	p._prev_snap_sender_t = sender_t
	p._prev_snap_receipt_t = now
	if int(snap.get("prot", 0)) == 1:
		p._spawn_protect_timer = p.SPAWN_PROTECTION
	# QA-068: a snapshot arriving after a long silence (>0.5 s) or
	# into an empty buffer is a re-placement (join / rejoin / long
	# loss burst), not steady motion - the remote branch snaps to
	# it once instead of gliding across the map.
	if p._snapshots.is_empty() or now - p._last_snap_receipt > 0.5:
		p._snap_resync = true
	p._last_snap_receipt = now
	p._snapshots.append({"t": sender_t, "p": pos, "v": vel, "rt": now})
	# Prune by sender-time age (>1 s behind the newest snapshot is
	# useless) as well as by count, so a burst of arrivals cannot
	# evict the snapshots the render time still needs.
	var newest_t := sender_t
	while p._snapshots.size() > 24:
		p._snapshots.pop_front()
	while p._snapshots.size() > 1 and newest_t - float((p._snapshots[0] as Dictionary)["t"]) > 1.0:
		p._snapshots.pop_front()


# QA-073: reconciliation against authoritative state (spec §4).
# The host calls this on the owning client when its view of that
# player has diverged beyond what interpolation lag can explain
# (game.gd _update_divergence_check: fresh snapshot stream, >300 px
# sustained 1 s - it never fires on normal interp lag, which stays
# under ~60 px). Small errors blend in over a few physics frames
# via _reconcile_target (see the local branch); a teleport-class
# error (>300 px, e.g. a respawn the client never heard about)
# snaps at once, because gliding across the map would be worse.
# Stale corrections (older corr_seq) are ignored, so a delayed
# correction can never drag the player back to an old position.
# This is a no-op for remote copies - only the owner reconciles
# its own predicted position.
func apply_authoritative_correction(auth_pos: Vector2, auth_vel: Vector2, corr_seq: int) -> void:
	if not p.is_local_player():
		return
	var sender = p.multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return # only the host may correct a client (0 = direct local call in tests)
	if corr_seq <= p._last_corr_seq:
		return
	p._last_corr_seq = corr_seq
	var dist = p.position.distance_to(auth_pos)
	if dist > 300.0:
		p.position = auth_pos
		p.velocity = auth_vel
		p._reconcile_active = false
		return
	if dist < 2.0:
		return
	p._reconcile_target = auth_pos
	p._reconcile_active = true


# QA-073: one dict with everything the net-stats display needs
# (spec §7). "auth_pos" is the newest authoritative snapshot
# position for this (remote) player; the rendered position is the
# node's own position. For the local player the snapshot fields
# are its own last-received values (0 when solo).
func get_net_stats() -> Dictionary:
	var now := Time.get_ticks_msec() / 1000.0
	return {
		"recv": p._net_recv_count, "lost": p._net_lost_count,
		"dup": p._net_dup_count, "ooo": p._net_ooo_count,
		"ups": p._net_ups, "buf": p._snapshots.size(),
		"delay_ms": p._interp_delay * 1000.0,
		"jitter_ms": p._jitter_ewma * 1000.0,
		"extrap_ms": p._net_extrap_s * 1000.0,
		"gap_ms": (now - p._last_snap_receipt) * 1000.0 if p._last_snap_receipt > 0.0 else 0.0,
		"auth_pos": p.sync_position, "pos": p.position,
		"jet": p._remote_jetpacking, "fire": p._remote_firing,
		"rel": p._remote_reloading,
	}


func _interp_position(now: float) -> Vector2:
	# QA-068: the render timeline is anchored to the SENDER's
	# clock - render at (newest sender stamp - 100 ms), NOT at
	# (receipt time - 100 ms). The sender emits every 33 ms on its
	# own clock, so the spacing between bracketing snapshots is a
	# steady 33 ms whatever the Wi-Fi arrival jitter was; a burst
	# of late arrivals no longer compresses the lerp, and a delayed
	# packet no longer renders as if it were on time. The two
	# clocks are never compared: only the sender's stamps order and
	# space the buffer, and "rt" (receipt time) is used only to
	# measure how long packets have been missing. If packets have
	# stopped arriving, the timeline advances with the wall clock
	# (minus one snapshot interval of grace) so the copy
	# dead-reckons forward on its last velocity instead of freezing
	# at the last bracket - the freeze-then-catch-up jump the user
	# reported. Extrapolation past the newest snapshot is capped
	# at 150 ms of velocity; past that the copy holds rather than
	# guessing a reversal it cannot see. (A capped variant was
	# tried and rejected: holding at the newest snapshot made
	# each burst land as a 1400+ px/s catch-up surge.)
	if p._snapshots.is_empty():
		p._net_extrap_s = 0.0
		return p.position.lerp(p.sync_position, clampf(1.0 / 60.0 * 14.0, 0.0, 1.0))
	var first: Dictionary = p._snapshots[0]
	var last: Dictionary = p._snapshots[p._snapshots.size() - 1]
	if p._snapshots.size() < 2:
		# One snapshot only (join moment): dead-reckon from it on
		# its velocity, capped at 150 ms, instead of the old fixed
		# per-frame lerp toward sync_position.
		var dt0 := clampf(now - float(last.get("rt", now)), 0.0, 0.15)
		p._net_extrap_s = dt0
		return (last["p"] as Vector2) + (last["v"] as Vector2) * dt0
	var newest_t := float(last["t"])
	var since_last := now - float(last.get("rt", now))
	if since_last > PhysicsConfig.SNAPSHOT_INTERVAL:
		newest_t += since_last - PhysicsConfig.SNAPSHOT_INTERVAL
	# QA-073: the render time uses the ADAPTIVE delay (was the fixed
	# 100 ms INTERP_BUFFER): render at (newest sender stamp -
	# _interp_delay). Clean Wi-Fi settles near 80 ms, bursty Wi-Fi
	# grows the buffer. INTERP_BUFFER is still the starting value.
	# QA-073 (render clock): the target render time is then made
	# MONOTONIC - it may never move backwards. When the adaptive
	# delay grows, newest - delay would retreat, and the copy would
	# step back and then surge forward (the first chaos run: 52 px
	# snap-back, 1352 px/s). Holding the clock instead only defers
	# the delay growth itself (tens of ms of sender time, ~10 px),
	# so the copy pauses briefly instead of retreating. There is
	# deliberately NO upper slew: capping the advance by wall time
	# starved the clock whenever physics ticks batched (burst
	# smoothness 937 px/s, burst move 421 -> 332 px) - the render
	# clock must be free to follow the sender's clock, and the
	# per-frame step clamp is what bounds the copy's speed. Only a
	# resync jumps the clock, and the remote branch snaps the copy
	# on a resync anyway.
	var target_render_t = newest_t - p._interp_delay
	var render_t = target_render_t
	if p._snap_resync:
		p._render_t_last = target_render_t
	elif p._render_t_last > -INF:
		render_t = maxf(target_render_t, p._render_t_last)
		p._render_t_last = render_t
	else:
		p._render_t_last = render_t
	if render_t <= float(first["t"]):
		p._net_extrap_s = 0.0
		return first["p"]
	if render_t >= float(last["t"]):
		# Past the newest snapshot: glide on its velocity, at most
		# 150 ms (was: at most one 16.7 ms physics step, then
		# freeze - the freeze-then-jump the user saw on Wi-Fi).
		var dt := minf(render_t - float(last["t"]), 0.15)
		p._net_extrap_s = dt
		return (last["p"] as Vector2) + (last["v"] as Vector2) * dt
	p._net_extrap_s = 0.0
	for i in range(p._snapshots.size() - 1):
		var a: Dictionary = p._snapshots[i]
		var b: Dictionary = p._snapshots[i + 1]
		if float(a["t"]) <= render_t and render_t <= float(b["t"]):
			var span := float(b["t"]) - float(a["t"])
			var f := 0.5 if span <= 0.0 else clampf((render_t - float(a["t"])) / span, 0.0, 1.0)
			return (a["p"] as Vector2).lerp(b["p"], f)
	return last["p"]


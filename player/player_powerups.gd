class_name PlayerPowerups
extends RefCounted


# QA-140 (v3.15): extracted from player/player.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `p` (dependency injection).


# QA-140: mirrors player/player.gd (same order/values); enum values are not reachable through an instance.
enum WeaponState { READY, FIRING, RELOADING }


var p # the owner (player/player.gd)

# QA-119 (v3.11 power-up set, REPLACE - user 2026-11-20 ~20:51):
# QA-143 (v4.0): Health Potion (7) REMOVED entirely (user
# 2026-11-21) - 6 kinds, 8-13. 8 Shield, 9 Speed Boost,
# 10 Jetpack Boost, 11 Wind Blast, 12 Thunder Strike,
# 13 Invisibility. Old Ammo Crate (10), Grenade Pack (11),
# Jetpack Boost (12) and Radar (13) are GONE - Radar is removed
# entirely, Double Damage was never implemented (user replaced it
# with Jetpack Boost, 2026-11-20 ~20:52).
# NO AUTO-ACTIVATION (user rule, 2026-11-20 ~21:00, IMMEDIATE):
# every picked-up power-up goes into one of the 3 slot buttons
# and WAITS - it does nothing until the player taps its slot.
# Timed kinds (8, 9, 10, 13): ONE active at a time; tapping a
# timed slot while a boost is active does nothing. Instant kinds
# (11 wind, 12 thunder) fire at once on tap, even while
# a timed boost is active. A carrier CANNOT activate a timed
# boost while carrying the flag (the carrier rule wins) - instant
# kinds are still allowed for carriers. Same kind twice, or full
# slots, consumes the pickup with no effect.
# carrying_flag is set by game.gd (Vertical CTF): 0 none, 1 RED
# flag, 2 BLUE flag. wind_force is set by game.gd every frame on
# Skyfall wind zones (Vector2.ZERO on every other map).
const SHIELD_DURATION := 7.0 # QA-119: was 6.0 (user 2026-11-20 ~20:48)
const SPEED_DURATION := 8.0 # QA-132: was 7.0 (speed is now x1.5, see below)
const JETPACK_BOOST_DURATION := 15.0 # QA-119: was 7.0 (user 2026-11-20 ~20:48)
const INVISIBILITY_DURATION := 10.0 # QA-119: user corrected 4 -> 10 s (2026-11-20 ~20:49)
const MAX_STORED_BOOSTS := 3
# QA-143: reference gun slots - the rifle plus at most ONE extra gun
# (SLC::addWeapon 0x8e6934: primary + secondary, then the pistol
# sidearm). A second extra drops the first one as a world pickup.
const MAX_SLOT_EXTRAS := 1
const TIMED_BOOST_KINDS: Array[int] = [8, 9, 10, 13] # shield, speed, jetpack, invisibility
const PU_NAMES := {8: "Shield", 9: "Speed Boost", 10: "Jetpack Boost", 11: "Wind Blast", 12: "Thunder Strike", 13: "Invisibility"} # QA-132: feed messages
const WIND_SWEEP_TIME := 0.7 # QA-135: tornado pulls the victim in for 0.7 s, then throws them down
const WIND_THROW_DOWN := 950.0 # QA-135: throw-down velocity (falls below the platform)
const WIND_THROW_SIDE := 700.0 # QA-135: throw sideways velocity — toward the NEAREST platform edge, so the victim actually leaves the platform (a downward velocity alone is blocked by the floor)



func _init(owner) -> void:
	p = owner


func give_pickup(kind: int) -> void:
	# Only the host hands out pickups (pickup.gd enforces this); a
	# client calling this directly is ignored.
	var sender = p.multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	# 1 SMG, 2 Shotgun, 3 Sniper, 4 Rocket, 5 Health, 6 Grenades
	if kind >= 1 and kind <= 4:
		# QA-143: reference weapon slots (SLC::addWeapon 0x8e6934). Two
		# gun slots - the rifle (0, the spawn gun) plus ONE extra -
		# and the pistol (5) as the permanent sidearm outside the
		# slots. _owned_extra holds the extra (at most one). The
		# rifle is never dropped: it is Frag Arena's respawn
		# fallback and the fire test assumes it is always owned
		# (the reference has no permanent weapon - recorded difference, see
		# the QA-143 notes). Pickup routing, reference order:
		# - already owned: refill + equip, no slot change (Frag
		#   Arena keeps one instance per kind; reference would hold a
		#   second copy, which our id-based mag memory cannot).
		# - secondary slot free: add + auto-equip (reference adds as
		#   secondary, then switchWeapons, so the new gun is in
		#   hand at once - the old code already auto-equipped).
		# - both slots full: drop the old extra as a world pickup
		#   (reference removePrimaryWeapon 0x8eade4) and the new gun
		#   takes its place. The dropped gun is the extra, never
		#   the rifle: when the rifle is in hand reference would drop
		#   the primary (the rifle), but the rifle is protected
		#   here, so the secondary goes instead.
		if not p._owned_extra.has(kind) and p._owned_extra.size() >= MAX_SLOT_EXTRAS:
			var drop_kind: int = int(p._owned_extra[0])
			p._owned_extra.erase(drop_kind)
			_drop_weapon_pickup(drop_kind)
		if not p._owned_extra.has(kind):
			p._owned_extra.append(kind)
		# QA-075: picking up a weapon while reloading the old one
		# must not eat the pending reload's ammo (same refund as
		# switch_weapon - the transfer is returned to the reserve).
		p.player_weapons._refund_reload()
		p.weapon = kind
		p.mag_ammo = int(p.WEAPONS[kind]["mag"])
		p._mag_memory[kind] = p.mag_ammo
		p._reserve[kind] = int(p.RESERVE_DEFAULT.get(kind, 0))
		p.reloading = false
		p.weapon_state = WeaponState.READY
		# QA-143: reference sets the view's weapon-angle offset when a
		# primary is equipped (SLC::addPrimaryWeapon 0x8e6ebc).
		p._weapon_angle_offset = float(p.player_visuals.WEAPON_ARM_ANGLE.get(kind, 0.0))
		p._update_gun_texture()
	elif kind == 5:
		p.health = mini(100, p.health + 50)
	elif kind == 6:
		p.grenades = mini(4, p.grenades + 2)
	elif kind >= 8 and kind <= 13:
		# QA-112: Skyfall power-ups (8-13) - kinds 1-6 above are unchanged.
		apply_powerup(kind)
	p._play_sound("pickup")


# QA-119 (v3.11): 6 kinds, 8-13 - Shield (8),
# Speed Boost (9), Jetpack Boost (10), Wind Blast (11), Thunder
# Strike (12), Invisibility (13). QA-143 (v4.0): Health Potion (7)
# REMOVED. Pickup STORES the power-up in a slot - it NEVER
# activates on pickup (user rule, 2026-11-20 ~21:00, IMMEDIATE).
# Every kind goes to a free slot (max 3, distinct kinds); a
# duplicate kind, or full slots, consumes the pickup with no
# effect. The player activates by tapping the slot button (see
# activate_slot). Timed kinds (8, 9, 10, 13): ONE active at a time;
# a carrier cannot activate one while carrying the flag. Instant
# kinds (11, 12) fire at once on tap.
# The old auto-activate / instant-on-pickup behaviour is GONE.
func apply_powerup(kind: int) -> void:
	if kind < 8 or kind > 13:
		return
	if p.stored_boosts.has(kind):
		_pu_feed("Already carrying %s" % PU_NAMES.get(kind, "power-up"))
		return # same kind already held: consumed, no extra effect
	if p.stored_boosts.size() >= MAX_STORED_BOOSTS:
		_pu_feed("Slots full — power-up lost")
		return # slots full: consumed, no effect
	p.stored_boosts.append(kind)


# QA-132: power-up feedback — a lost pickup or a fired instant
# used to fail silently (no message, no visible effect). The feed
# goes through the game scene, into the same top-left message area
# as every other notice. No game node (menu / unit test) = silent.
func _pu_feed(text: String) -> void:
	var game = p.get_game_node()
	if game != null and game.has_method("_ctf_feed"):
		game._ctf_feed(text, Color(1.0, 0.8, 0.2))


# Activate the power-up waiting in slot `idx` (HUD slot-button tap).
# Timed kinds (8, 9, 10, 13): ONE active at a time, and a carrier
# CANNOT activate one while carrying the flag (the carrier rule
# wins - the tap does nothing and the power-up stays in its slot).
# Instant kinds (11 wind, 12 thunder) fire at once and work even
# while a timed boost is active or the flag is carried.
# QA-135 (v3.13): Wind (11) / Thunder (12) need a live enemy on
# the SAME PLATFORM at the SAME HEIGHT — no target, no fire, and
# the power-up STAYS in its slot (never wasted on thin air).
func activate_slot(idx: int) -> bool:
	# Slot input can arrive during the death/respawn transition.
	# Never consume a stored boost unless its owner is alive in the match.
	if not p.alive:
		return false
	if idx < 0 or idx >= p.stored_boosts.size():
		return false
	var kind: int = p.stored_boosts[idx]
	if kind in TIMED_BOOST_KINDS:
		if p.active_boost_kind != 0:
			return false # one active boost at a time
		if p.carrying_flag != 0:
			return false # carrier rule wins over the boost
		p.stored_boosts.remove_at(idx)
		_activate_boost(kind)
		return true
	if kind == 11 or kind == 12:
		var game0 = p.get_game_node()
		var tgt: Node2D = null
		if game0 != null and game0.has_method("_sf_find_powerup_target"):
			tgt = game0._sf_find_powerup_target(p, kind)
		if tgt == null:
			_pu_feed("No enemy on your platform")
			return false
		p.stored_boosts.remove_at(idx)
		_apply_instant(kind, tgt)
		return true
	return false # unknown kind (e.g. the removed Health Potion 7): never stored, never fires


# Fire an instant power-up. Wind Blast sweeps the
# enemy on the activator's platform into a tornado and throws them
# down (no damage); Thunder Strike halves that enemy's current
# health. Wind/thunder are host-authoritative: a client asks the
# host with an RPC, passing the target the tap already picked (in
# the sim the peer IS the host).
# QA-132: wind + thunder announce themselves in the feed, so the
# player sees the activation even when no enemy is in range.
# QA-143 (v4.0): _apply_instant returns whether the blast actually
# fired. If the host re-validates the target and it moved off the
# platform in the meantime, the slot is REFUNDED (see below) — the
# power-up must never be lost with no effect.
func _apply_instant(kind: int, target: Node2D = null) -> bool:
	match kind:
		11:
			p._fx_flash_kind = 11
			p._fx_flash_timer = 0.8
			p._play_sound("wind")
			_pu_feed("Wind Blast!")
			if p.multiplayer.is_server():
				if _do_wind_blast(target):
					return true
				p.apply_powerup(kind) # host validation failed: refund the slot
				return false
			elif target != null:
				p.rpc_id(1, "request_wind_blast", int(target.peer_id))
				return true
			return false
		12:
			p._fx_flash_kind = 12
			p._fx_flash_timer = 0.8
			# Sound plays inside show_thunder_strike_fx (once per
			# peer, via the host RPC) — not here, or the activator
			# would hear the crack twice.
			_pu_feed("Thunder Strike!")
			if p.multiplayer.is_server():
				if _do_thunder_strike(target):
					return true
				p.apply_powerup(kind) # host validation failed: refund the slot
				return false
			elif target != null:
				p.rpc_id(1, "request_thunder_strike", int(target.peer_id))
				return true
			return false
	return false


# QA-143: spawn the world pickup for a gun dropped when its slot
# was taken by a new pickup (reference removePrimaryWeapon 0x8eade4 -
# the dropped weapon becomes a world pickup, thrown forward along
# the fire angle). Host-only: only the server spawns pickups.
# Dropped pickups get a short pickup grace period, preventing an
# immediate weapon swap after collecting a new gun.
# spot_idx -1: a dropped pickup never restarts a spot timer
# (pickup.gd only calls on_pickup_gone for spot_index >= 0) and
# despawns after its 20 s life like any weapon pickup.
func _drop_weapon_pickup(drop_kind: int) -> void:
	var drop_pos: Vector2 = p.global_position - Vector2(cos(p.aim_angle), sin(p.aim_angle)) * 110.0
	if p.multiplayer.is_server():
		var game = p.get_game_node()
		if game != null:
			game.game_pickups.spawn_dropped_pickup(drop_pos, drop_kind)
	else:
		p.rpc_id(1, "request_weapon_drop", drop_kind, drop_pos)


func request_weapon_drop(kind: int, pos: Vector2) -> void:
	# Only the host runs it, and only for the player that asked
	# (the sender must be this node's owner). The kind is
	# re-validated: a dropped pickup is a gun only (0-4).
	if not p.multiplayer.is_server():
		return
	var sender = p.multiplayer.get_remote_sender_id()
	if sender != 0 and sender != p.get_multiplayer_authority():
		return
	if kind < 0 or kind > 4:
		return
	var game = p.get_game_node()
	if game == null:
		return
	game.game_pickups.spawn_dropped_pickup(pos, kind)


func request_wind_blast(target_peer: int) -> void:
	# Only the host runs it, and only for the player that asked
	# (the sender must be this node's owner). The target the tap
	# picked is re-validated on the host (same platform + height)
	# before anything happens. QA-143 (v4.0): if the re-validation
	# fails, the power-up is REFUNDED to the activator — the tap
	# already consumed their slot, and losing it to a target that
	# moved in the last few ms is a silent loss.
	if not p.multiplayer.is_server():
		return
	var sender = p.multiplayer.get_remote_sender_id()
	if sender != 0 and sender != p.get_multiplayer_authority():
		return
	var game = p.get_game_node()
	if game == null:
		return
	var target: Node2D = game.players_node.get_node_or_null(str(target_peer))
	if _do_wind_blast(target):
		return
	var activator: Node2D = game.players_node.get_node_or_null(str(sender))
	if activator != null and activator.alive:
		activator.rpc_id(sender, "give_pickup", 11)


func request_thunder_strike(target_peer: int) -> void:
	if not p.multiplayer.is_server():
		return
	var sender = p.multiplayer.get_remote_sender_id()
	if sender != 0 and sender != p.get_multiplayer_authority():
		return
	var game = p.get_game_node()
	if game == null:
		return
	var target: Node2D = game.players_node.get_node_or_null(str(target_peer))
	if _do_thunder_strike(target):
		return
	var activator: Node2D = game.players_node.get_node_or_null(str(sender))
	if activator != null and activator.alive:
		activator.rpc_id(sender, "give_pickup", 12)


# Host only: the Wind Blast tornado. The target (same platform +
# same height as the activator, picked at tap time and re-validated
# here) gets a tornado at their feet, is swept into it (pulled to
# the centre for 0.7 s), then thrown DOWN off the platform. No
# damage; a shield does not stop the push (movement, not damage).
# The throw goes toward the NEAREST edge of the shared platform
# (a downward velocity alone cannot leave a solid platform — the
# floor blocks it), so the victim clears the edge and falls below.
# The sweep itself runs on the victim's owning peer (see
# apply_wind_sweep) so it works for remote victims too; a test bot
# (fake peer, no live connection) is driven on the host copy.
# Returns true when the blast fired, false when the target failed
# re-validation (the caller refunds the slot — QA-143).
func _do_wind_blast(target: Node2D) -> bool:
	var game = p.get_game_node()
	if game == null or target == null or not is_instance_valid(target):
		return false
	if game.has_method("_sf_validate_powerup_target") and not game._sf_validate_powerup_target(p, target, 11):
		return false
	var centre := target.global_position
	if game.has_method("show_wind_tornado_fx"):
		game.rpc("show_wind_tornado_fx", centre)
	var side := 1.0
	# QA-143: nearest edge of the surface the TARGET stands on
	# (merged run / mover rect) — the old raw-rect centre could sit
	# far from the victim on a seamed floor and throw the wrong way.
	var srect: Rect2 = Rect2()
	if game.has_method("_sf_surface_rect_under"):
		srect = game._sf_surface_rect_under(target.global_position)
	if srect != Rect2():
		side = -1.0 if target.global_position.x < srect.get_center().x else 1.0
	elif game.has_method("_sf_platform_under"):
		var plat_idx: int = int(game._sf_platform_under(p.global_position))
		if plat_idx >= 0:
			var rect: Rect2 = game.MAPS[game.map_id]["platforms"][plat_idx]
			side = -1.0 if target.global_position.x < rect.get_center().x else 1.0
	var throw_vec = Vector2(side * WIND_THROW_SIDE, WIND_THROW_DOWN)
	var auth := int(target.get_multiplayer_authority())
	if auth == p.multiplayer.get_unique_id() or not p.multiplayer.get_peers().has(auth):
		target.apply_wind_sweep(centre, throw_vec)
	else:
		target.rpc_id(auth, "apply_wind_sweep", centre, throw_vec)
	return true


func apply_wind_sweep(centre: Vector2, throw_vec: Vector2) -> void:
	# Host-triggered tornado sweep (see _do_wind_blast). Only the
	# host (id 1, or 0 in a local sim) may start it. The victim's
	# own physics pulls them into the funnel for WIND_SWEEP_TIME,
	# then throws them down (see _apply_movement).
	var sender = p.multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	if not p.alive:
		return
	p._wind_sweep_timer = WIND_SWEEP_TIME
	p._wind_sweep_center = centre
	p._wind_throw = throw_vec


# Host only: Thunder Strike halves the target's CURRENT health
# (QA-135: was flat 40 damage) — a single target, no area damage.
# The target is the enemy on the activator's platform at the same
# height (picked at tap time, re-validated here). Shield absorbs
# the strike (take_hit -> _apply_damage zeroes it); the bolt
# visual is drawn by the game (show_thunder_strike_fx).
# Returns true when the strike fired, false when the target failed
# re-validation (the caller refunds the slot — QA-143).
func _do_thunder_strike(target: Node2D) -> bool:
	var game = p.get_game_node()
	if game == null or target == null or not is_instance_valid(target):
		return false
	if game.has_method("_sf_validate_powerup_target") and not game._sf_validate_powerup_target(p, target, 12):
		return false
	if game.has_method("show_thunder_strike_fx"):
		game.rpc("show_thunder_strike_fx", target.global_position)
	var dmg := maxi(1, int(ceil(float(target.health) * 0.5)))
	var dir: Vector2 = (target.global_position - p.global_position).normalized()
	# Bullet routing (bullet.gd): direct when the victim is
	# locally owned, RPC to the owning peer otherwise — and a
	# test bot (fake peer, no live connection) is driven on the
	# host copy, or the strike never lands in the sim.
	var auth := int(target.get_multiplayer_authority())
	if auth == p.multiplayer.get_unique_id() or not p.multiplayer.get_peers().has(auth):
		target.take_hit(dmg, p.peer_id, dir, 150.0, game.next_damage_event_id())
	else:
		target.rpc_id(auth, "take_hit", dmg, p.peer_id, dir, 150.0, game.next_damage_event_id())
	return true


# Start a timed boost now: set its timer (and refill the fuel for
# the jetpack boost) and mark it active.
func _activate_boost(kind: int) -> void:
	p.active_boost_kind = kind
	match kind:
		8:
			p.shield_timer = SHIELD_DURATION
			p._play_sound("shield")
		9:
			p.speed_timer = SPEED_DURATION
			p._play_sound("speed")
		10:
			p.jetpack_boost_timer = JETPACK_BOOST_DURATION
			p.fuel = p.FUEL_MAX
			p._jetpack_empty_locked = false
			p._play_sound("jetpack_boost")
		13:
			p.invisibility_timer = INVISIBILITY_DURATION
			p._play_sound("invis")


# Tick the boost timers every physics frame. When the active boost
# runs out it just ends - stored power-ups NEVER start by
# themselves (tap-to-activate only, QA-119). A carrier's stored
# boost waits in its slot until the player taps it after the drop.
func _tick_boost_timers(delta: float) -> void:
	p.shield_timer = maxf(0.0, p.shield_timer - delta)
	p.speed_timer = maxf(0.0, p.speed_timer - delta)
	p.jetpack_boost_timer = maxf(0.0, p.jetpack_boost_timer - delta)
	p.invisibility_timer = maxf(0.0, p.invisibility_timer - delta)
	if p._fx_flash_timer > 0.0:
		p._fx_flash_timer = maxf(0.0, p._fx_flash_timer - delta)
		if p._fx_flash_timer <= 0.0:
			p._fx_flash_kind = 0
	if p.active_boost_kind == 0:
		return
	var t := 0.0
	match p.active_boost_kind:
		8:
			t = p.shield_timer
		9:
			t = p.speed_timer
		10:
			t = p.jetpack_boost_timer
		13:
			t = p.invisibility_timer
	if t <= 0.0:
		p.active_boost_kind = 0


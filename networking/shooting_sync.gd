class_name ShootingSync
extends RefCounted

# MultiplayerShootingController (server-side validation): the host is
# the only peer that may reject a shot. Every shot arrives at the host
# as a spawn_bullet RPC; the host checks the sender's fire rate and
# ammunition before the bullet is simulated on the host (the server is
# the only peer whose simulation can deal damage, so a rejected shot
# can never hurt anyone — the shooter's local copy is visual only).
#
# Rate: a shot arriving sooner than 0.75x the weapon's configured
# rate after the previous one is impossible from a legit client (the
# local cooldown enforces the full rate); the 0.75 factor leaves room
# for network jitter. Ammo: the host mirrors each sender's magazine
# from the replicated mag_ammo (the synchronizer already replicates
# it). If the replicated value is HIGHER than the mirror, the player
# reloaded or picked up a weapon — adopt it. If the mirror is at 0,
# the shot is rejected (client fired with an empty magazine).
#
# This is deliberately light: it stops fire-rate / infinite-ammo
# abuse without a full lockstep model, and it never blocks a legit
# shot (rate and ammo both come from the same WeaponData table the
# client uses).

var _last_shot_at: Dictionary = {} # peer id -> seconds (msec clock)
var _ammo_mirror: Dictionary = {} # peer id -> mirrored magazine


func validate_shot(sender_id: int, kind: int, replicated_mag: int) -> bool:
	var w: Dictionary = WeaponData.get_weapon(kind)
	var rate: float = float(w["rate"])
	var now := Time.get_ticks_msec() / 1000.0
	var last: float = float(_last_shot_at.get(sender_id, -100.0))
	if now - last < rate * 0.75:
		return false
	# Ammo mirror: adopt reloads / pickups (replicated mag went up),
	# reject when the mirror says the magazine is empty.
	var mirror: int = int(_ammo_mirror.get(sender_id, replicated_mag))
	if replicated_mag > mirror:
		mirror = replicated_mag
	if mirror <= 0:
		return false
	_last_shot_at[sender_id] = now
	_ammo_mirror[sender_id] = mirror - 1
	return true


func reset_peer(peer_id: int) -> void:
	_last_shot_at.erase(peer_id)
	_ammo_mirror.erase(peer_id)


func reset_all() -> void:
	_last_shot_at.clear()
	_ammo_mirror.clear()

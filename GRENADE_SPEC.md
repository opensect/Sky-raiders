# Grenade in Godot 4 — user-shared guide (2026-11-20)

Saved verbatim from the user's message. Audit target for v3.7 (see BUGS.md).
One hard constraint: the guide's MultiplayerSynchronizer suggestion must NOT be
adopted — QA-053 proved on the user's real phones that synchronizer packets are
silently dropped (node-path addressing, auto-uniquified names). Grenades stay on
the proven host-authoritative RPC sync channel.

## 1. Choose the right node
- Use a RigidBody2D for the grenade. Godot handles gravity, bouncing and rolling.
- PhysicsMaterial with bounce ≈ 0.5 and friction ≈ 0.6-0.8.
- linear_damp ≈ 0.1 for light air drag.
- Continuous CD (Ray or Shape) so fast throws don't tunnel through thin platforms.
- CircleShape2D collider, since circles roll and bounce more predictably.

## 2. Throwing
- Convert the aim direction to a unit vector and spawn the grenade slightly ahead of the player.
- Launch with apply_central_impulse(dir * power), or set linear_velocity directly at spawn.
- Add about 40% of the player's velocity so jetpack throws feel natural.
- Use collision layers so the grenade doesn't hit its thrower for the first few frames.

## 3. Fuse and explosion
- Timer child (2-3 s, one-shot) that starts on spawn.
- Impact grenade: contact_monitor = true, max_contacts_reported = 1, explode on body_entered.
- Sticky grenade: on contact set freeze = true and parent it to the hit body.

## 4. Blast damage and knockback
- On detonation, spawn an Area2D with a circle shape of radius R, or run
  PhysicsDirectSpaceState2D.intersect_shape (simpler, runs once).
- For each body: falloff = 1 - dist / R. Damage = maxDamage * falloff.
- Knockback: players are CharacterBody2D, so add dir * force * falloff to velocity.
  RigidBody2D targets: apply_impulse.
- Cast a ray (intersect_ray) from the blast center to each target. If a wall blocks it,
  reduce or skip the damage.
- GPUParticles2D for the blast, Camera2D shake scaled by distance, short flash light.

## 5. Fixed timestep
- Godot physics at 60 Hz by default (physics/common/physics_ticks_per_second).
  All gameplay logic in _physics_process, never _process. Same tick rate on every device.

## 6. LAN multiplayer in Godot
- Transport: ENetMultiplayerPeer (create_server / create_client), reliable + unreliable channels.
- Authority: host (peer ID 1) owns all grenades. Only the host runs physics and explosion logic.
- Throw request: client calls RPC to host (@rpc("any_peer", "call_remote", "reliable"))
  with angle and power. Host validates (cooldown, ammo) and spawns the grenade.
- Spawning: MultiplayerSpawner auto-creates the grenade on all clients when the host adds it.
- Syncing: MultiplayerSynchronizer replicates position, rotation, velocity at 20-30 Hz, unreliable.
  [DO NOT ADOPT — QA-053: synchronizer packets silently dropped on real phones.
  Our grenades sync via host-authoritative RPC snapshots instead.]
- Client grenades: freeze or kinematic mode so they only display the host's data.
  Interpolate between updates; RigidBody2D physics is not deterministic across machines.
- Explosion event: host sends reliable RPC with the position; each client plays effects locally.
  Health/velocity changes arrive via the player synchronizers.
- Finding games: host broadcasts UDP (PacketPeerUDP), clients listen — no typed IPs.

## 7. Common pitfalls
- Running physics on clients as well as the host causes grenades to drift apart — host's data only.
- Forgetting layers/masks makes grenades hit bullets or their own thrower.
- Tiny RigidBody2D mass or huge impulses cause jitter — tune power and damp together.
- Skipping intersect_ray means explosions damage players through walls.

User offered to break down player knockback or MultiplayerSynchronizer settings next
(2026-11-20). Note: the MultiplayerSynchronizer breakdown is NOT needed — QA-053 settled it.

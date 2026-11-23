# Complete Physics System of the reference game — Detailed Game Development Breakdown

User-provided spec, 2026-11-19. Target: our LAN Arena Shooter should be
production-grade in ALL aspects, with this physics system.

Important: The exact source code and internal physics constants of the
reference game are not publicly available. The following is a technical
reconstruction of the mechanics needed to reproduce its characteristic
gameplay, not a claim that these are its original internal algorithms.

the reference game is not simply a character moving left and right while
shooting. Its gameplay depends on several interacting physics systems:

- Player movement and acceleration
- Gravity and jumping
- Jetpack thrust and fuel
- Air resistance and momentum
- Collision detection and response
- Weapon recoil and bullet physics
- Projectile trajectories
- Explosions and knockback
- Rope, terrain and obstacle interactions
- Multiplayer physics synchronization

## 1. Coordinate system and physics fundamentals

2D game, X horizontal, Y vertical. Every player has a position and velocity:
P = (x, y), V = (vx, vy). Also horizontal/vertical acceleration, player mass,
gravity.

Basic movement equations:
vx(t+dt) = vx(t) + ax*dt;  x(t+dt) = x(t) + vx*dt
vy(t+dt) = vy(t) + ay*dt;  y(t+dt) = y(t) + vy*dt

For a production game, use a FIXED physics timestep instead of allowing
movement to depend on the rendering frame rate.

## 2. Player horizontal movement physics

Left joystick controls horizontal movement. Needs more than changing X:
acceleration, maximum movement speed, friction, deceleration, direction
reversal, ground movement, air movement, momentum preservation.

A. Acceleration: ax = Input_x * A, where Input_x ranges -1 to +1.
B. Maximum speed: vx = clamp(vx, -Vmax, Vmax).
C. Ground friction: when the joystick is released, friction gradually
   reduces velocity: vx = vx * (1 - f*dt), or exponential damping
   vx = vx * e^(-f*dt) — the second is more stable across frame rates.
D. Direction reversal: moving right at max speed then pressing left must
   NOT instantly flip direction. Apply leftward acceleration, reduce
   rightward velocity, reach zero, then build leftward velocity. Natural,
   responsive feel.
E. Air control differs from ground control:

| Property           | Ground   | Air      |
| ------------------ | -------- | -------- |
| Acceleration       | Strong   | Moderate |
| Friction           | Higher   | Lower    |
| Direction reversal | Fast     | Slower   |
| Maximum speed      | Ground limit | Air limit |
| Momentum           | Reduced by friction | Preserved longer |

This difference matters for jetpack-based combat.

## 3. Gravity and falling physics

Gravity constantly pulls the player downward when not supported or thrusting.
Fg = m*g; F = m*a so ay = g (positive Y downward).
Falling velocity: vy(t) = vy0 + g*t.
Falling distance: d = vy0*t + 0.5*g*t^2.
Terminal velocity: vy = min(vy, V_terminal) — prevents extreme falling speeds.

Landing: detect collision, check player moving downward, confirm feet
crossed the platform top surface, move player out of the platform, set
vertical velocity to zero, set grounded = true.
```
if player.velocity_y > 0 and player.bottom >= platform.top:
    player.bottom = platform.top
    player.velocity_y = 0
    player.is_grounded = True
```
Collision must prevent passing through thin platforms at high speeds.

## 4. Jumping physics

Jump applies upward velocity: vy = -J (positive Y downward).
Sequence: press jump -> check grounded -> apply upward velocity ->
grounded false -> gravity reduces upward velocity -> apex -> fall ->
landing resets vertical velocity.

Variable jump height: tap = short jump, hold = higher jump, release =
reduce upward velocity: vy <- vy * c (c < 1) when jump is released while
moving upward. More control without changing basic gravity.

## 5. Jetpack physics — the most important mechanic

Not just an animation: a thrust-based physics system.
F_net = F_thrust - F_gravity; ay = g - F_thrust/m (positive Y downward).
- Thrust > gravity: player rises
- Thrust = gravity: player hovers
- Thrust < gravity: player falls, but more slowly

Basic implementation:
```
if jetpack_pressed and fuel > 0:
    player.velocity_y -= jetpack_force * delta_time
    fuel -= fuel_consumption * delta_time
player.velocity_y += gravity * delta_time
```
Continuous thrust: hold to accelerate upwards until max upward velocity:
vy = max(vy, -V_jetpack_max).

Fuel system: max capacity, consumption per second, regeneration,
recharge delay, empty-fuel behaviour.
Fuel_new = Fuel_old - Rc*dt (consumption)
Fuel_new = min(Fuel_max, Fuel_old + Rr*dt) (regen when released)

Jetpack momentum: releasing the jetpack must NOT stop the player
immediately. Thrust stops, upward momentum remains, gravity gradually
reduces upward speed, apex, then fall. Natural flight.

Horizontal movement while flying: retain horizontal control in air,
ax = Input_x * A_air, air acceleration lower than ground acceleration.
Flying + directional control is the characteristic feel.

Jetpack flame effects must follow the actual thrust state:
- Jetpack off: no flame
- Activated: flame appears
- Strong thrust: longer flame
- Fuel low: warning effect
- Fuel empty: flame disappears
- Descending: no thrust flame

## 6. Air resistance and momentum

Air resistance determines how quickly a moving player loses velocity.
Drag force: Fd = -k*v; 2D: Fdx = -kx*vx, Fdy = -ky*vy.
Implement via velocity damping: player.velocity_x *= air_damping.
Frame-rate-independent: damping = exp(-drag * delta_time);
player.velocity_x *= damping.

Ground vs air: standing and moving right vs flying at high speed and
releasing the joystick must decelerate differently — ground responsive,
air smooth.

## 7. Player rotation and aiming physics

Dual-stick: left joystick = movement, right joystick = aiming/firing.
Aiming angle: theta = atan2(dy, dx) from aim stick vector D = (dx, dy).
Weapon rotates to this angle every physics frame / input update.
Facing: if aim_x > 0 face right, if aim_x < 0 face left. Body, weapon,
hands and firing position stay visually consistent.

Independent aiming (essential): aiming must NOT be tied to movement
direction. Move right and shoot left; fly up and shoot diagonally; fall
while shooting horizontally; stand still and shoot up.

Aim dead zone: |D| < D_min => keep previous aim. Prevents unwanted
weapon rotation from small unintended stick movements.

## 8. Weapon recoil physics

When a weapon fires, recoil force pushes opposite to the bullet
(conservation of momentum): m_bullet * v_bullet + m_player * v_player = 0.
Implement as: gun kick (barrel jumps back along aim direction), a small
player velocity impulse opposite the shot, muzzle flash, and screen shake
scaled by weapon power. Heavier weapons = stronger recoil.

## 9. (From the intro — implement to production standard)

- Bullet physics: swept collision so fast bullets never tunnel through
  thin platforms or obstacles; projectile trajectories per weapon
  (speed, spread, gravity-affected grenades/rockets).
- Explosions and knockback: blast radius, damage falloff with distance,
  knockback impulse on players.
- Rope, terrain and obstacle interactions: solid collision with
  platforms, walls and obstacles (crates, barrels, columns); no walking
  or shooting through solid objects.
- Multiplayer physics synchronization: host-authoritative positions,
  shooting, health and deaths; client prediction with reconciliation and
  interpolation so movement stays smooth and fair on LAN.

---

## Points 9–28 (continuation, user-provided 2026-11-19)

Objective: a robust 2D multiplayer shooter with responsive controls,
realistic-enough arcade physics, smooth combat, accurate collision
detection and reliable multiplayer behaviour. Formulas below are proposed
engineering implementations, not the original game's proprietary code.

### 9. Bullet and Projectile Physics

Every projectile has an independent physics state: position X/Y, velocity
X/Y, direction, speed, damage, radius, lifetime, range, gravity, drag,
owner ID, weapon ID, collision mask.

Trajectory: bullet starts at the weapon muzzle. Direction D = (cos θ,
sin θ); velocity vx = S·cos θ, vy = S·sin θ (S = bullet speed, θ = aim
angle). Position: x_new = x_old + vx·dt; y_new = y_old + vy·dt. Straight
for bullets without gravity. With gravity: vy' = vy + g·dt; y' = y + vy'·dt.

Behaviours: standard bullets (straight, high speed, short lifetime,
small radius); shotgun pellets (multiple projectiles at slightly
different angles); rockets (larger, slower, optional gravity, explosive);
energy projectiles (custom patterns, glow, special collision).

Shotgun spread: 7 pellets, θ_i = θ + δ_i, e.g. spread [-15,-10,-5,0,5,
10,15]°. Each pellet has independent position, velocity, collision,
damage, lifetime.

Projectile collision must detect: terrain, walls, platforms, players,
destructible objects. For high-speed bullets use raycasting / swept
collision: raycast the segment P0 → P1 (previous to new position) so a
bullet is caught even when it moves farther than its own diameter in one
physics update.

Projectile pooling: never create/destroy hundreds of projectiles
continuously. Use an object pool (get inactive projectile, activate it;
release deactivates it). Reduces allocation and GC spikes.

### 10. Explosion Physics and Knockback

Explosion parameters: position, radius (e.g. 200), max damage (e.g. 100),
max impulse (e.g. 500), duration (e.g. 0.4), owner ID. Illustrative values.

Distance: d = sqrt((xp-xe)^2 + (yp-ye)^2); if d > R the player is outside.
Damage falloff: linear D = Dmax·(1 - d/R), or smooth D = Dmax·(1-u²)²
where u = d/R (stronger centre blast, gentler edge).
Knockback: normalised direction N = (P-E)/|P-E|; impulse J = K·(1-u)²·N;
ΔV = J/m — player pushed away from the explosion.
Vertical blast: explosions below a player can give stronger upward
knockback via a vertical multiplier Jy = J·Ky.
Explosion obstruction: a wall should protect a player — raycast from the
explosion centre to the player, check for solid obstacles, reduce damage
and knockback accordingly.
Visuals (separate from collision): initial flash, fireball, expanding
shockwave, smoke particles, debris, fade-out. No repeated damage per frame
unless deliberately designed as a damage-over-time field.

### 11. Collision Detection Physics

Poor collision causes: players through walls, bullets missing visible
targets, characters stuck, unexpected falling, overlapping platforms,
players trapped.

Categories (use different collision layers/masks so each object only
checks relevant categories): player body (solid movement), player hitbox
(damage), terrain (obstruction), projectile (bullet collision), pickup
(trigger), explosion (area damage), hazard (environmental damage), sensor
(non-solid interaction).

AABB: A = (L, R, T, B). Overlap iff A_L < B_R AND A_R > B_L AND A_T < B_B
AND A_B > B_T.
Circle: d² = (x2-x1)² + (y2-y1)²; collision iff d² < (r1+r2)² (squared
distance avoids sqrt).

Collision resolution: identify overlap, find minimum separation
direction, move player out of the wall, remove the velocity component
entering the wall, preserve tangential movement (hitting a vertical wall
stops horizontal movement, not falling).

Continuous collision detection (essential for fast bullets/rockets):
a bullet at 500 units/s with dt 1/60 travels 8.33 units — a 3-unit-thick
obstacle can be missed by discrete checks. Solutions: raycasting, shape
casting, swept AABB, CCD.

Hitboxes vs sprite sizes: never assume the visible image is the exact
collision area. Separate shapes: body collision, head damage region,
torso damage region, weapon visual area (e.g. rectangular body but
circular head/torso hit regions).

### 12. Wall, Ceiling and Platform Interaction

Solid walls: player cannot pass through; resolve position, stop velocity
into the wall, allow movement along it.
Ceiling: jetpack can hit it — detect upward collision, move player below
ceiling, set upward velocity to zero, preserve horizontal velocity,
continue gravity.
One-way platforms: collide only when the player is falling AND previous
bottom was above the platform AND new bottom crosses its top AND
horizontal overlap.
Moving platforms: platform has its own velocity Vp; a standing player
inherits its displacement while grounded — track attachment, carry
movement correctly, do not add displacement repeatedly as permanent
velocity.
Destructible terrain: detect damage, reduce health, check destruction,
disable collision shape, spawn debris, trigger effects, update map state;
server determines the result in multiplayer.
Terrain materials: stone (medium friction, normal), ice (low, sliding),
mud (high, slow), metal (medium, optional ricochet), wood (medium,
destructible), rubber (variable, bouncing), glass (low, breakable).

### 13. Grenade Physics

Separate physics controller: grenades experience gravity and bounce.
Initial velocity: vx = S·cos θ, vy = S·sin θ. Gravity: vy' = vy + g·dt.
Air resistance: Fd = -k·v.
Bounce: v_n' = -e·v_n (v_n = velocity perpendicular to surface, e =
restitution); tangential velocity reduced by surface friction.
Fuse: T' = T - dt, independent of movement; at zero, explode.
States: spawned → initial velocity → gravity + drag → collision
detection → ground collision → bounce → continue; or fuse expired →
explosion → damage + knockback → destroyed.
Prevent infinite bouncing: when velocity is small enough, stop bouncing,
enter resting state, continue fuse countdown, explode on time.

### 14. Player-to-Player Collision Physics

Physical collision: players cannot move through each other. Distance
d = sqrt((x2-x1)² + (y2-y1)²); collision when d < r1 + r2. Overlap
O = r1 + r2 - d; separation direction N = (P2-P1)/d; P1' = P1 - (O/2)·N,
P2' = P2 + (O/2)·N (can be weighted by mass/movement state).
Impulse: relative velocity Vr = V2 - V1; J = -(1+e)(Vr·N) / (1/m1 +
1/m2); apply only when players move towards each other.
Alternative (arcade): non-blocking players — bodies do not block
movement, but bullets, explosions, damage and knockback still apply.
Recommended: make it configurable (PLAYER_COLLISION_ENABLED = False,
PLAYER_DAMAGE_COLLISION = True, PLAYER_EXPLOSION_COLLISION = True) and
test both before choosing.

### 15. Weapon Pickup Physics and Interaction

Pickup properties: position, weapon type, collision radius, respawn
time, active state, animation state, spawn ID.
Trigger collision (not solid): if player overlaps an active pickup,
add weapon to inventory, deactivate pickup.
Floating animation: y(t) = y0 + A·sin(ωt) (e.g. amplitude 8, frequency
2 rad/s); collection area follows or stays fixed by design.
Rotation: θ(t) = θ0 + ωt, slight rotation for visual appeal.
Respawn: disable → respawn timer → check spawn location valid →
reactivate → spawn animation. Server controls collection and respawning
in multiplayer.
Weapon drop: initial velocity V_drop = V_player + V_throw, then gravity
and collision; weapon settles on the ground.

### 16. Weapon Firing Rate and Ammunition Physics

Weapon config: RPM, magazine size, reload duration, bullet speed,
damage, recoil, spread, range, fire mode (single / burst / automatic).
Fire interval: T = 60/RPM (600 RPM → 0.1 s). Automatic: if fire pressed
and current_time >= next_fire_time and ammo > 0 and not reloading:
spawn projectile, ammo -= 1, next_fire_time = current_time + interval.
Never spawn one projectile per rendered frame (a 120 FPS device would
fire faster than a 30 FPS device).
Burst: fixed count (e.g. 3), burst interval (e.g. 0.08 s), delay before
next burst (e.g. 0.3 s); burst controller has its own state.
Reload states: READY → FIRING → READY; READY → RELOADING (on command)
→ READY (on timer). Distinguish magazine ammo, reserve ammo, total
ammo, reloading state, infinite-ammo mode. Reloading transfers ammo
from reserve to magazine (e.g. mag 30, remaining 18, reserve 90, reload
1.8 s).
Recoil accumulation: R_n = R_0 + n·K for n consecutive shots; resets
gradually when firing stops; can affect aim, player velocity, or both.

### 17. Damage, Health and Knockback Interaction

Player health: health 100, max 100, is_alive, is_invulnerable,
damage_multiplier 1.0.
Damage: H_new = H_old - D, or D_final = D_base × M_distance × M_armor;
clamp H = max(0, H).
Body hit regions with different multipliers: head 1.5, torso 1.0,
legs (multiplier per design — message cut off here).

### 17. Damage, Health and Knockback Interaction (full)

The damage system connects weapons, projectiles, explosions and player
health. It must communicate with the physics engine without allowing
multiple systems to modify health unpredictably.

17.1 Player health system — health component: max health 100, current
health 100, is_alive, is_invulnerable, damage_multiplier 1.0; plus
optional armor (damage reduction) and regeneration.
17.2 Damage calculation: H_new = H_old - D; advanced: D_final = D_base ×
M_d (distance) × M_w (weapon-specific) × M_a (armor/damage-reduction).
Clamp health: H_new = max(0, H_new). Never allow negative health.
17.3 Hit regions: head 1.5, torso 1.0, legs 0.75, arms 0.85 (configurable
examples). calculate_damage(base, region) uses the region multiplier.
For a cartoon shooter, headshots can be optional — do not over-complicate
collision if the game uses a single body hitbox.
17.4 Damage cooldown / duplicate-hit prevention: a projectile overlapping
a player for multiple physics frames must not apply damage repeatedly.
Use a single-hit projectile state (has_hit flag; on hit, apply damage
once and destroy). For continuous hazards use a separate damage interval
(e.g. damage every 0.5 s, not every frame).
17.5 Knockback physics: impulse J = K·D (K = knockback strength, D =
normalised direction); ΔV = J/m; V_new = V_old + ΔV. Different weapons,
different knockback: pistol very low, assault rifle low, shotgun medium,
heavy weapon medium/high, rocket high, grenade high.
17.6 Death physics: health zero → dedicated death state. Sequence:
disable controls, stop firing, stop pickup collection, optional death
impulse, death animation, change collision state, start respawn timer,
select valid spawn, restore state. Finite state machine: ALIVE → (health
<= 0) DYING → (animation done) DEAD → (respawn timer done) RESPAWNING →
(spawn done) ALIVE.
17.7 Respawn physics: reset position, velocity, health, jetpack fuel,
damage state, weapon state per game rules, collision state, animation
state. ALWAYS check the spawn location first — never spawn inside a wall,
inside the ground, inside a moving obstacle, directly inside an enemy, or
outside map boundaries.
17.8 Production requirements: health must be server-authoritative; damage
events must have unique identifiers; death happens only once per life;
respawn must be atomic; knockback must not bypass collision handling;
invulnerability must have a clearly defined duration; visual hit effects
must not independently apply damage.

### 18. Water and Environmental Physics

Different maps should feel different — regions can modify the player's
physical behaviour.

18.1 Water physics: entering water can modify gravity, drag, movement
acceleration, max speed, jumping, buoyancy. Example multipliers:
gravity 0.5, horizontal acceleration 0.7, air drag 3.0, max speed 0.65,
buoyancy active (vs 1.0 / 0 normally). Illustrative tuning values.
18.2 Buoyancy: Archimedes F_b = ρ·V·g (ρ = fluid density, V = submerged
volume); vertical acceleration a_y = g - F_b/m. No full fluid simulation
needed — simplified upward force when the player's body enters a water
region.
18.3 Ice physics: very low friction (F_f = μ·N; lower μ = slides
farther after releasing the joystick). If player.is_on_ice: use
ice_friction, else ground_friction.
18.4 Mud physics: heavier/slower feel — lower max horizontal speed,
lower acceleration, higher movement resistance, reduced jump height,
slower jetpack fuel regen if desired. Do NOT change actual player mass
unnecessarily; use movement multipliers.
18.5 Conveyor belt physics: belt moves the player horizontally while
standing on it (V_surface = (vx, vy)); player displacement includes the
platform's displacement; avoid adding conveyor speed to velocity every
frame (runaway acceleration).
18.6 Wind physics: external force F_wind = m·a_wind; acceleration depends
on direction and intensity — pushes players left/up, reduces horizontal
movement, affects grenade trajectories.
18.7 Environmental hazards (partial — message cut off here): lava
(continuous damage), spikes (contact damage), electric field (periodic
damage), moving saw (collision damage), falling rocks (gravity and
impact), water (buoyancy and drag), wind (…).

### 18. Environmental Physics System (full — Godot 4)

Environmental physics make different areas of the map behave differently.
Use separate environmental zones with configurable properties — do NOT put
all environmental behaviour directly inside the player controller.

A. Ice: acceleration stays relatively high, friction very low; player
slides after releasing the joystick, direction changes take longer,
jumping while sliding preserves horizontal momentum. Prototype values:
ground friction 1200, ice friction 100, ice acceleration 500, max speed
350, air control 0.65.
B. Water: movement slower, gravity reduced, jumping becomes swimming /
underwater movement, bullets may behave differently by weapon type,
water entry creates splash particles.
C. Mud: reduces movement speed, increases acceleration time, makes
jumping less effective, produces mud particles when walking.
D. Wind: continuous horizontal force; strong wind can affect bullets;
players can be pushed while airborne; wind direction visible through
environmental particles.
E. Damage zones (each needs collision detection, damage interval,
knockback force, visual warning, sound effect): lava, electric fields,
explosive barrels, poison gas, falling rocks.

### 19. Camera Follow and Camera Physics

Camera follows the player smoothly, never teleporting: track player
position, lerp towards it with frame-rate-independent smoothing
(global_position.lerp(target, 1 - exp(-follow_speed * delta)),
follow_speed ~8.0).
Camera dead zone: player can move within a central screen region without
the camera following every small movement (less movement, better aiming,
stable gameplay).
Camera look-ahead: when moving right, reveal more area to the right (and
vice versa) so players can anticipate enemies and obstacles.
Camera shake on explosions, heavy weapon firing, player damage, rocket
impacts, environmental destruction — small and brief (excessive shake
makes aiming difficult).
Camera boundaries: never show areas outside the map, unfinished regions,
or empty background beyond the level — use camera limits from map
dimensions.

### 20. Firing While Moving — Independent Movement and Aiming

Player must move in one direction while aiming/shooting in another
(move right / aim left, fly up / shoot diagonally, etc.).
A. Separate inputs: movement = left joystick, aim = right joystick.
Never let movement direction determine weapon direction.
B. Bullet direction: direction = (aim_position - muzzle.global_position)
.normalized(); bullet_velocity = direction * bullet_speed.
C. Inherit player velocity: bullet.velocity = direction * bullet_speed +
player.velocity * inheritance_factor. Prototype values: bullet speed 900,
velocity inheritance 0.15, rifle 8 shots/sec, pistol 3 shots/sec,
shotgun 6 pellets, rocket speed 450 (starting values for balancing).
D. Recoil: apply small force opposite the shot, muzzle flash, firing
sound, weapon-specific screen feedback, larger recoil for heavy weapons
(apply_recoil(direction, force): player.velocity -= direction * force).
E. Weapon-specific behaviour: pistol (low recoil, fast bullet), rifle
(moderate recoil, rapid fire), shotgun (multiple projectiles), sniper
(high damage, precise trajectory), rocket launcher (explosive
projectile), grenade (gravity + bouncing), flamethrower (short-range
particle/projectile stream).
F. Prevent common shooting bugs: bullets must not spawn inside the
player; bullets must not collide with the shooter immediately; aim must
update independently; fire rate via cooldowns; automatic weapons must
not generate unlimited projectiles; bullets removed after lifetime.

### 21. Multiplayer Physics Synchronization

Goal: all players see approximately the same game state.
A. Server-authoritative architecture: the server controls health, damage
calculation, bullet spawning and hit validation, player positions and
velocities, respawn, score, match timer, game result. Clients send inputs
and receive replicated state.
B. Client-side prediction: client predicts local movement immediately
from input, sends input to server, receives authoritative state, corrects
any difference.
C. Server reconciliation: compare predicted vs authoritative positions,
correct the error, replay unacknowledged inputs, smooth small
corrections, apply larger corrections when necessary.
D. Interpolation: store recent position snapshots of other players,
render between snapshots, smooth movement, interpolate rotation and
animation states (no teleporting between updates).
E. Lag compensation: record recent player positions, estimate firing
time, validate the shot against historical positions within a limited
time window, prevent excessively old or manipulated shots.
F. Suggested networking config (targets to test): physics 60 ticks/sec,
server snapshots 20–30/sec, input updates 30–60/sec, interpolation
buffer 100 ms, local players 2–8, UDP transport, reliable messages for
match events / inventory / results.
G. LAN multiplayer: one device creates a match and starts a local host;
others discover or enter the host IP; join the lobby; host starts the
match; server synchronises state. Production needs: connection timeout,
reconnection handling, player disconnection handling, packet-loss
handling, match ownership and host migration if peer-hosted, version
compatibility checks. NEVER trust clients to decide their own damage,
kills, score, or inventory — validate on the authoritative server.

### 22. Advanced Physics Interactions

Goal: make the map interactive — players interact with objects, destroy
certain structures, trigger environmental events, use physics objects
strategically.

A. Moving platforms — types: horizontal, vertical, rotating, falling
(falls after player contact), timed (moves at fixed intervals), elevator
(carries players between levels). Requirements: detect player standing
on platform, apply platform movement to the player, preserve independent
player movement, prevent slipping through, synchronise platform
positions in multiplayer, configurable speed and range.
B. Destructible environment — materials: wood (breaks with moderate
damage), glass (breaks quickly into small fragments), stone (needs heavy
weapons), metal (highly resistant), explosive barrel (explodes when
damaged), weak wall (breaks after repeated attacks). Every destructible
object has: unique ID, health, material type, damage resistance,
destruction animation, sound effect, particle effects, debris lifetime,
respawn configuration. Example (GDScript): StaticBody2D with max_health
100, take_damage(amount) reduces health and calls destroy_object() at
<= 0 (notify destruction manager, queue_free). Server must authorise
destruction and replicate the resulting state to all clients.
C. Explosive objects — when a barrel takes damage: start explosion
sequence, calculate nearby targets, check line of sight if blocked by
walls, damage by distance, radial knockback, explosion particles,
explosion audio, replicate the event. Damage: D = Dmax × max(0, 1 - d/R)
(Dmax = max damage, d = distance, R = radius).
D. Rope and grappling physics — swinging ropes, hanging chains,
grappling hooks, rope bridges, hanging platforms. Requirements: rope
attachment points, maximum rope length, tension calculation, detachment
controls, collision handling, multiplayer synchronisation.
E. Bounce pads and springs — on touch: detect collision, apply upward
velocity (e.g. player.velocity.y = -750), bounce animation, particles,
sound, prevent repeated triggering during the same contact.
F. Player death physics — on death: disable movement input and weapon
firing, death animation, death sound, optional ragdoll effects, remove
or recycle the body, start respawn timer, restore state after respawn.
G. Physics optimisation — avoid hundreds of independent physics objects:
object pooling for bullets/debris, static collision shapes for map
geometry, limited particle counts, simplified collision shapes,
distance-based simulation management, server-controlled destruction
events.

### 23. Game Physics Architecture and Module Design

A production-ready game must not keep all physics code in one player
script — separate into independent systems for debugging, testing and
future work.
A. Recommended architecture: GAME CORE (game state, match management,
configuration); Player System (movement, health, animation); Physics
System (gravity, collisions, forces); Weapon System (aiming, bullets,
recoil); Environment System (water, ice, hazards); Camera System
(follow, shake, limits); Network System (replication, prediction);
Rendering, Audio and UI (visual effects, menus, HUD, sound).
B. Recommended Godot folder structure: assets/ (characters, weapons,
maps, effects, sounds, UI); scenes/ (player, weapons, projectiles, maps,
objects, menus); scripts/ (player, physics, weapons, networking,
environment, camera, managers); resources/ (weapons, physics, maps);
tests/ (movement, combat, multiplayer).
C. Player scene structure: Player (CharacterBody2D) with CollisionShape2D,
AnimatedSprite2D, Camera2D, WeaponHolder (Node2D) with Muzzle (Marker2D),
HealthComponent, MovementComponent, AimComponent, AnimationController,
AudioComponent. Keep components independent — e.g. the weapon system
requests the player's aim direction rather than controlling the movement
script.
D. Physics update order (every physics tick): read and validate input →
calculate movement direction → calculate acceleration and friction →
apply gravity and environmental forces → resolve player movement and
collisions → update weapon and projectile simulation → process damage and
interaction events → update authoritative multiplayer state. Visual
animation, particles and camera smoothing run separately from physics.
E. Separate physics and rendering: _physics_process(delta) for physics,
_process(delta) for visual updates. Physics: fixed 60 ticks/sec target.
Rendering: display frame rate. Interpolate visual positions when
necessary. Never modify authoritative physics positions from rendering
code. This reduces jitter and makes the simulation easier to test.

### 24. Physics Configuration and Starting Values

Prototype defaults (not the reference game's internal values) — tune to feel.
A. Player movement: max horizontal speed 350 px/s, ground acceleration
1800 px/s², air acceleration 900 px/s², ground friction 1200 px/s²,
gravity 1400 px/s², jump velocity -550 px/s, max fall speed 1000 px/s,
air control multiplier 0.65.
B. Jetpack movement: upward force 1800 px/s², max upward speed 450 px/s,
fuel capacity 100 units, fuel consumption 25 units/sec, fuel recovery 15
units/sec, activation delay 0.1 sec. Tune to feel responsive without
making airborne movement uncontrollable.
C. Weapon physics: pistol (speed 800, 3/sec, low recoil, 2 s lifetime,
bullet); rifle (950, 8/sec, medium, 2 s, bullet); rocket (450, 1/sec,
high, 4 s, explosive).
D. Collision layers: 1 world geometry, 2 player, 3 enemy, 4 projectiles,
5 destructible objects, 6 environmental hazards, 7 pickup items,
8 trigger zones. Prevents unwanted collisions (bullets hitting their own
shooter, players colliding with pickup triggers as if they were walls).
E. Performance targets: 60 physics ticks/sec, 60 FPS on reference
hardware, 2–8 players, 16–32 projectiles/player active budget. Planning
targets, not guarantees — benchmark on minimum supported hardware and
network conditions.

### 25. Common Physics Bugs, Prevention and Optimization

- Player falling through platforms: use CharacterBody2D, correct
  collision shapes and swept collision checks.
- Player stuck inside walls: validate map geometry and collision shapes.
- Bullets passing through players: use ray casting or swept collision
  checks and server-side hit validation.
- Multiplayer jitter: use fixed physics updates, prediction,
  reconciliation and interpolation.
- Infinite bullet generation: use cooldowns, ammunition limits and
  object pooling.
- Optimise physics using spatial partitioning, simplified collision
  geometry and resource cleanup.

### 26. Quality Assurance and Testing

Test player movement, jumping, jetpack, collisions, weapons, ammunition,
explosions, multiplayer synchronization, LAN connections, disconnections,
performance, memory and crash stability. Use automated tests and a
consistent bug-report format. Do not release with critical crashes or
game-breaking multiplayer defects.

### 27. Technology and Implementation Architecture

Use Godot 4, GDScript or C#, Godot Physics 2D, ENet or Godot Multiplayer
API, TileMapLayer, AnimatedSprite2D, Git and automated tests. Separate
player, physics, weapon, networking, environment, camera, audio and UI
systems. Use CharacterBody2D for players, StaticBody2D for fixed
geometry, RigidBody2D for physical objects and Area2D for triggers.

### 28. Complete Production Requirements

Include responsive gameplay, independent aiming, weapons, jetpack,
health, damage, respawning, LAN multiplayer, authoritative game logic,
original maps, visual effects, menus, HUD, security, performance
optimization, crash prevention and release testing.

---
SPEC COMPLETE: points 1–28 all received (2026-11-19 ~01:35 IST).

## QA-141 note (2026-11-21) — reference constants, extracted from the real binary

The reconstruction above is superseded for the values actually ported: the real
constants were extracted by disassembly from reference v0.14.4
(`libcocos2dcpp.so`) — see `~/workspace/reference-analysis/QA141_EXTRACTION_A.md`
and `QA141_EXTRACTION_B.md` — and ported into the game in QA-141 (commit to be
added). Full table, per-file changes, could-not-extract list and known conflicts:
BUGS.md, QA-141 entry. Headline values now live in the game: move base 300,
headroom accel 3.0× (1.5× thrusting), damping 0.598/s, gravity 300 (50 thrusting),
jump Δv 220, fuel 100 / drain 21/s, jetpack rise cap 190, grenade fuse 1.75 /
gravity 250 / radius 125, explosion damage max(10, 100 − 0.8×dist) / knockback
cap 600, weapon stats = AK47/MP5/SPAS-12/M93BA/SMAW/D.EAGLE builder rows, LCG
spread counter=(41c+37)%100, joystick dead zone 0.0, fire at aim deflection ≥0.98,
stick opacity 0.5. NOT ported (could not extract): grenade throw speed, jetpack
fuel regen, rocket blast radius, bullet gravity, per-weapon arm angle / firing
point / weight (gun hold stays QA-127). Known conflict: reference fuel ≈ 4.76 s full
thrust supersedes the user's v3.12 request for a 9 s tank.

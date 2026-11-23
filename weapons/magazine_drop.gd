class_name MagazineDrop
extends Node2D

# QA-145 ITEM 3 — dropping magazine on reload (reference).
# reference drops the magazine at the weapon's design reload point
# (Weapon::getDesignReloadPoint, +0x2e0) when a reload starts
# (every subclass dropMag(float)). Visual only: no gameplay effect,
# no collision, no sound — it falls and fades out, then frees itself.
#
# Design reload points, texture px in the gun's local frame (origin
# at the gun centre, +x toward the muzzle — the same frame QA-143
# uses for the firing point):
#   rifle AK47 (50, 0), smg MP5 (60, 0), sniper M93BA (70, 0),
#   pistol DEAGLE (30, 0).
# Shotgun (SPAS-12) and rocket (SMAW) have NO +0x2e0 store in their
# reference init() — no design reload point exists for them, so they get
# NO magazine visual and their reload stays exactly as-is.
# (Sources: QA143-workerB-notes.md §3; BUGS.md QA-143 ITEM 2.)
#
# QA-145 follow-up: REAL magazine art, cut from the user's weapon
# images by a separate worker into assets/weapons_new/mag_<weapon>.png
# (rifle/smg/sniper/rocket/pistol). When a weapon's PNG exists it is
# used as the falling magazine's texture; when it is missing (none
# exists yet, as of this writing) the code-drawn shape in _draw() is
# the fallback, so the drop always renders. The lookup is runtime
# (ResourceLoader.exists + load), never preload — a missing file can
# never break the reload. The rocket PNG is listed but unused by
# design: SMAW has no reference reload point, so no mag ever spawns for it.
# (The shotgun image was never uploaded, so no mag_shotgun.png exists
# either — and SPAS-12 has no reload point anyway.)
const MAG_TEX_PATHS := {
	0: "res://assets/weapons_new/mag_rifle.png",
	1: "res://assets/weapons_new/mag_smg.png",
	3: "res://assets/weapons_new/mag_sniper.png",
	5: "res://assets/weapons_new/mag_pistol.png",
}
# The spawn position is computed from the gun node's live transform
# (gun.to_global(point)), so the reference texture-px point lands at the
# right spot on Frag Arena's scaled gun (full width = GUN_LENGTH),
# at the gun's current aim angle, including the reload dip.

const RELOAD_POINTS := {
	0: Vector2(50, 0), # rifle / AK47
	1: Vector2(60, 0), # smg / MP5
	3: Vector2(70, 0), # sniper / M93BA
	5: Vector2(30, 0), # pistol / DEAGLE
}
const LIFE := 0.7 # seconds from spawn to freed
const FULL_ALPHA_UNTIL := 0.4 # fully opaque, then fades out over the last 0.3 s
const GRAVITY := 900.0 # px/s^2 — same order as world gravity, reads as a real drop
const INITIAL_VELOCITY := Vector2(0, 60) # small initial downward drift

var _vel: Vector2 = INITIAL_VELOCITY
var _age: float = 0.0
var _spin: float = 0.0
var _tex: Texture2D = null # real magazine art when its PNG exists (see MAG_TEX_PATHS); null = code-drawn fallback


# Spawn a dropping magazine at the weapon's reference design reload point.
# parent is the game scene (world space — the mag must NOT follow the
# player as it falls); gun is the player's gun sprite. Weapons with
# no stored reload point in the reference (shotgun/rocket) spawn nothing.
static func spawn(parent: Node, gun: Sprite2D, weapon_id: int) -> void:
	if parent == null or gun == null or not RELOAD_POINTS.has(weapon_id):
		return
	var mag := MagazineDrop.new()
	mag.z_index = 2 # above the floor, below the gun (z 3)
	# Real magazine art when the PNG exists; otherwise the
	# code-drawn shape (see _draw). Guarded so a missing file can
	# never break the reload — load() is only attempted when the
	# file exists, and a failed load still leaves _tex null.
	var tex_path: String = MAG_TEX_PATHS.get(weapon_id, "")
	if tex_path != "" and ResourceLoader.exists(tex_path):
		mag._tex = load(tex_path) as Texture2D
	parent.add_child(mag)
	mag.global_position = gun.to_global(RELOAD_POINTS[weapon_id])
	mag.global_rotation = gun.global_rotation
	mag._spin = randf_range(-3.0, 3.0)


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFE:
		queue_free()
		return
	_vel.y += GRAVITY * delta
	position += _vel * delta
	rotation += _spin * delta
	if _age > FULL_ALPHA_UNTIL:
		modulate.a = 1.0 - (_age - FULL_ALPHA_UNTIL) / (LIFE - FULL_ALPHA_UNTIL)


func _draw() -> void:
	if _tex != null:
		# Real magazine art, fitted to the same 16 px length as the
		# code-drawn shape (aspect preserved, centred on the node).
		var s: Vector2 = _tex.get_size()
		if s.x > 0.0 and s.y > 0.0:
			var w := 16.0
			var h: float = w * s.y / s.x
			draw_texture_rect(_tex, Rect2(-w * 0.5, -h * 0.5, w, h), false)
			return
	# Fallback: code-drawn dark magazine: 16x6 px body with a lighter
	# top edge so it reads against dark floors as well as light sky.
	draw_rect(Rect2(-8, -3, 16, 6), Color(0.14, 0.14, 0.15))
	draw_rect(Rect2(-8, -3, 16, 2), Color(0.38, 0.38, 0.40))

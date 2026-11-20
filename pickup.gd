extends Area2D

# Weapon / health / grenade pickup. Only the server (host) hands it out,
# so two players can't grab it at once.

# kind: 1 = SMG, 2 = Shotgun, 3 = Sniper, 4 = Rocket Launcher,
#       5 = Health (+50), 6 = Grenades (+2)
#       7-13 = Skyfall power-ups (QA-112, v3.9, Skyfall map only):
#       7 = Health +35%, 8 = Shield 6s, 9 = Speed 7s, 10 = Ammo refill,
#       11 = Grenades +2, 12 = Jetpack boost, 13 = Radar 5s.
# The effect of kinds 7-13 lives in player.gd (give_pickup) — this
# file only shows the pickup picture. Bob, radius and lifetime are
# the same for every kind.
var kind: int = 1
var spot_index: int = -1 # per-spot respawn tracking (GAP-37); -1 = untracked

# QA-088 (v3.7): drawn pickup icons from assets/items/ — the three
# files already in the folder (ammobox / grenade / healthkit) were
# NEVER used anywhere; they are redrawn bigger/clearer and wired in
# here, plus a new weapon glyph for the weapon kinds. The old Sky
# Brawl icons (pickup_007 / pickup_002) are retired for pickups:
# the new icons are bigger, match the game's cartoon style, and read
# at combat speed. Kind system, collision, bob and lifetime are
# unchanged — only the picture changes.
const HEALTH_TEX: Texture2D = preload("res://assets/items/healthkit.png")
const GRENADE_TEX: Texture2D = preload("res://assets/items/grenade.png")
const WEAPON_TEX: Texture2D = preload("res://assets/items/weapon.png")
const AMMOBOX_TEX: Texture2D = preload("res://assets/items/ammobox.png")
# assets/items/shield.png is drawn and ready (QA-088) but NOT wired:
# there is no shield pickup kind (kinds are 1-6 only) and adding a
# kind would change gameplay. It waits for a future shield kind.

# QA-112 (v3.9 Skyfall power-ups): the 7 Skyfall power-up pictures,
# one file each (256x256 RGBA). The spritesheet
# (powerups_spritesheet.png) is NOT loaded — individual files only.
const SKY_HEALTH_TEX: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/powerups/powerup_1_health_pack.png")
const SKY_SHIELD_TEX: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/powerups/powerup_2_energy_shield.png")
const SKY_SPEED_TEX: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/powerups/powerup_3_speed_boost.png")
const SKY_AMMO_TEX: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/powerups/powerup_4_ammo_crate.png")
const SKY_GRENADE_TEX: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/powerups/powerup_5_grenade_pack.png")
const SKY_JETPACK_TEX: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/powerups/powerup_6_jetpack_boost.png")
const SKY_RADAR_TEX: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/powerups/powerup_7_enemy_radar.png")
# Kind -> Skyfall picture, for kinds 7-13.
const SKYFALL_TEX := {
	7: SKY_HEALTH_TEX,
	8: SKY_SHIELD_TEX,
	9: SKY_SPEED_TEX,
	10: SKY_AMMO_TEX,
	11: SKY_GRENADE_TEX,
	12: SKY_JETPACK_TEX,
	13: SKY_RADAR_TEX,
}

var _life: float = 20.0
var _bob_t: float = 0.0
var _base_y: float = 0.0

const KIND_LABEL := {1: "SMG", 2: "BOOM", 3: "SNIPER", 4: "ROCKET", 5: "+", 6: "G",
	7: "HP", 8: "SHIELD", 9: "SPEED", 10: "AMMO", 11: "G", 12: "JET", 13: "RADAR"}
# QA-112: full display names for HUD / logs. KIND_LABEL above is the
# short in-world tag; this one is the readable name. Kinds 1-6 keep
# their old meaning; 7-13 are the Skyfall power-ups.
const KIND_NAME := {
	1: "SMG", 2: "Shotgun", 3: "Sniper", 4: "Rocket Launcher",
	5: "Health +50", 6: "Grenades +2",
	7: "Health +35%", 8: "Shield", 9: "Speed", 10: "Ammo",
	11: "Grenades +2", 12: "Jetpack Boost", 13: "Radar",
}


static func kind_name(kind: int) -> String:
	return KIND_NAME.get(kind, "?")


const KIND_COLOR := {
	1: Color(1.0, 0.6, 0.2),
	2: Color(1.0, 0.5, 0.3),
	3: Color(0.5, 0.9, 1.0),
	4: Color(1.0, 0.3, 0.2),
	5: Color(0.3, 0.9, 0.4),
	6: Color(0.2, 0.6, 0.25),
	7: Color(0.3, 0.9, 0.4),
	8: Color(0.3, 0.6, 1.0),
	9: Color(1.0, 0.85, 0.2),
	10: Color(1.0, 0.6, 0.2),
	11: Color(0.8, 0.2, 0.2),
	12: Color(0.6, 0.4, 1.0),
	13: Color(0.2, 0.8, 0.8),
}


func _ready() -> void:
	collision_layer = 7 # pickup (spec §24.D, GAP-71; was 16)
	collision_mask = 2
	monitoring = true
	monitorable = false
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 22.0
	shape.shape = circle
	add_child(shape)
	if kind >= 5:
		# QA-088: drawn icon sprite for health / grenades, over a
		# faint colour glow (same shape as the weapon boxes). The
		# icons are ~52 px now (was a 64 px Sky Brawl sprite at
		# 0.62x = 40 px) so they read at combat speed on a phone.
		# QA-112: kinds 7-13 use the same shape — the Skyfall
		# power-up badge over the same faint glow, same size.
		var glow := Polygon2D.new()
		glow.polygon = PackedVector2Array([
			Vector2(-26, -18), Vector2(26, -18), Vector2(26, 18), Vector2(-26, 18),
		])
		glow.color = Color(KIND_COLOR.get(kind, Color(0.5, 0.9, 1.0)), 0.35)
		add_child(glow)
		var icon := Sprite2D.new()
		var icon_tex: Texture2D = HEALTH_TEX
		if kind == 6:
			icon_tex = GRENADE_TEX
		elif kind >= 7:
			icon_tex = SKYFALL_TEX.get(kind, HEALTH_TEX)
		icon.texture = icon_tex
		var target := 52.0
		icon.scale = Vector2(target / icon.texture.get_width(), target / icon.texture.get_width())
		add_child(icon)
		_base_y = position.y
		body_entered.connect(_on_body_entered)
		return
	# Weapon kinds (1-4): the ammo crate, tinted with the kind
	# colour, with the rifle glyph on it and the name label below —
	# the crate + glyph + label together read instantly at speed.
	var crate := Sprite2D.new()
	crate.texture = AMMOBOX_TEX
	crate.scale = Vector2(58.0 / AMMOBOX_TEX.get_width(), 58.0 / AMMOBOX_TEX.get_width())
	crate.modulate = KIND_COLOR.get(kind, Color(0.5, 0.9, 1.0))
	add_child(crate)
	var glyph := Sprite2D.new()
	glyph.texture = WEAPON_TEX
	glyph.scale = Vector2(38.0 / WEAPON_TEX.get_width(), 38.0 / WEAPON_TEX.get_width())
	glyph.position = Vector2(0, -2)
	add_child(glyph)
	var label := Label.new()
	label.text = KIND_LABEL.get(kind, "?")
	label.position = Vector2(-29, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(58, 22)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	_base_y = position.y
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_bob_t += delta
	position.y = _base_y + sin(_bob_t * 3.0) * 6.0
	# Gentle sway (GAP-35, spec §15): rotation, not a full spin —
	# a full spin would make the label unreadable.
	rotation = 0.12 * sin(_bob_t * 1.5)
	if multiplayer.is_server():
		_life -= delta
		if _life <= 0.0:
			rpc("despawn")


func _on_body_entered(body: Node2D) -> void:
	if not multiplayer.is_server():
		return
	if body.is_in_group("players"):
		var p = body
		if p.alive:
			if body.get_multiplayer_authority() == multiplayer.get_unique_id():
				body.give_pickup(kind)
			elif multiplayer.get_peers().has(body.get_multiplayer_authority()):
				# QA-032: the peer may have disconnected a split-second
				# before touching the pickup (their puppet still
				# overlaps the area on the host) — an RPC to a gone
				# peer only logs an engine error, so skip it, exactly
				# as bullet.gd / game.gd do for damage RPCs.
				body.rpc_id(body.get_multiplayer_authority(), "give_pickup", kind)
			# QA-092: the grab sparkles on every peer — despawn(true)
			# carries the grab through the same RPC as the expiry.
			rpc("despawn", true)


@rpc("any_peer", "call_local")
func despawn(grabbed: bool = false) -> void:
	# QA-092: a grabbed pickup sparkles where it was taken (every
	# peer sees it — despawn runs call_local). An expired pickup
	# (grabbed=false) just vanishes, as before.
	if grabbed:
		var game_fx = get_tree().get_first_node_in_group("game")
		if game_fx != null:
			game_fx.spawn_pickup_fx(global_position)
	# Tell the host the spot is free so its per-spot timer restarts
	# (GAP-37). Only the server tracks respawn timers.
	if multiplayer.is_server() and spot_index >= 0:
		var game = get_tree().get_first_node_in_group("game")
		if game != null:
			game.on_pickup_gone(spot_index)
	queue_free()

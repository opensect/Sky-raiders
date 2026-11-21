extends Control

# Mini Militia-style virtual joystick (reusable, touch-only).
#
# Circular base + knob, fixed at the bottom-left (move stick) or
# bottom-right (aim stick). The game routes screen touches to it by
# screen half; the stick itself owns the touch that grabbed it.
#
# FIRE-BUG FIX (v2.2, QA-016): the movement vector is ONLY non-zero while
# a finger is actively holding this stick (tracked by touch index). The
# old code derived firing from a knob offset that was only cleared by an
# explicit touch-release event — any release the OS never delivered
# (app backgrounded, notification shade, gesture cancel) left the knob
# displaced and the gun firing forever. Now: no active touch index means
# a zero vector, and the stick also resets itself on window focus loss
# and application pause.

signal vector_changed(vector: Vector2)

# --- Configurable properties (spec section 10) ---
@export var joystick_radius: float = 60.0
@export var knob_radius: float = 34.0
@export var max_movement_speed: float = 330.0
@export var dead_zone: float = 0.20 # GAP-09: THE single dead zone (was 0.12 here + 0.25 in game.gd + 0.25 in player.gd)
@export var horizontal_sensitivity: float = 1.0
@export var vertical_sensitivity: float = 1.0
@export var joystick_opacity: float = 0.85
@export var return_duration: float = 0.08
# QA-137 (v3.14): the sticks wear the user's HUD kit art now
# (assets/user_assets_v3/hud/hud_stick_*.png) instead of the
# code-drawn circles. The base is the kit's ring (the knob is
# erased from it, so it never doubles up) and the knob is the
# kit's round knob; both are drawn as textures, scaled to the
# stick's radius. The aim base already has the cyan ring + d-pad
# arrows baked in, so the code-drawn aim cue is retired.
const STICK_MOVE_BASE: Texture2D = preload("res://assets/user_assets_v3/hud/hud_stick_move_base.png")
const STICK_MOVE_KNOB: Texture2D = preload("res://assets/user_assets_v3/hud/hud_stick_move_knob.png")
const STICK_AIM_BASE: Texture2D = preload("res://assets/user_assets_v3/hud/hud_stick_aim_base.png")
const STICK_AIM_KNOB: Texture2D = preload("res://assets/user_assets_v3/hud/hud_stick_aim_knob.png")

# v3.2 (CONTROLS_CHANGE.md §3): set on the AIM stick only — picks
# the aim (cyan d-pad) base/knob art in _draw() so the player can
# see the right stick is also the fire control. Visual only; never
# affects input.
var is_aim: bool = false

var _touch_id: int = -1
var _knob_offset: Vector2 = Vector2.ZERO
var _vector: Vector2 = Vector2.ZERO
var _return_tween: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	# A touch that is interrupted by the OS (app switch, notification
	# shade, incoming call, gesture cancel) never delivers a release
	# event. Reset here so input can never get stuck (QA-016).
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		reset_input()


# --- Touch API (called by the game, which routes touches by screen half) ---

func press_touch(index: int, global_pos: Vector2) -> bool:
	# One finger per stick: a second finger on the same stick is ignored.
	if _touch_id != -1:
		return false
	_touch_id = index
	if _return_tween != null and _return_tween.is_valid():
		_return_tween.kill()
		_return_tween = null
	_update_from_point(global_pos)
	return true


func drag_touch(index: int, global_pos: Vector2) -> void:
	if index != _touch_id:
		return
	_update_from_point(global_pos)


func release_touch(index: int) -> void:
	if index != _touch_id:
		return
	reset_input()


func reset_input() -> void:
	_touch_id = -1
	# Input goes to zero IMMEDIATELY (the gameplay state); only the
	# knob's visual return is animated.
	var had_input := _vector != Vector2.ZERO
	_vector = Vector2.ZERO
	if had_input:
		vector_changed.emit(_vector)
	if _return_tween != null and _return_tween.is_valid():
		_return_tween.kill()
		_return_tween = null
	if _knob_offset != Vector2.ZERO:
		_return_tween = create_tween()
		_return_tween.tween_method(_set_knob_offset, _knob_offset, Vector2.ZERO, return_duration)
		_return_tween.tween_callback(queue_redraw)
	else:
		queue_redraw()


func is_active() -> bool:
	return _touch_id != -1


func get_touch_id() -> int:
	return _touch_id


# Public movement vector, read by the game / player controller.
# Zero unless a finger is actively holding this stick.
func get_vector() -> Vector2:
	if _touch_id == -1:
		return Vector2.ZERO
	return _vector


# Knob displacement in pixels, clamped to the base radius (for tests).
func get_knob_offset() -> Vector2:
	return _knob_offset


func _set_knob_offset(v: Vector2) -> void:
	_knob_offset = v
	queue_redraw()


func _update_from_point(global_pos: Vector2) -> void:
	# QA-029: the incoming point is in viewport coordinates; the stick's
	# global_position is in canvas-layer coordinates, and the two differ
	# by the camera offset (plus the stretch scale on a real phone).
	# Convert to the stick's own local space first — the global
	# transform with canvas is the ground truth for where this control
	# actually sits on screen — then measure from the local centre.
	# The base never moves; only the knob follows the finger.
	var local := get_global_transform_with_canvas().affine_inverse() * global_pos
	var offset := local - size * 0.5
	# Clamp the knob inside the circular base.
	if offset.length() > joystick_radius:
		offset = offset.normalized() * joystick_radius
	_knob_offset = offset
	# Normalized 360-degree direction + strength (spec section 3).
	var raw := offset / joystick_radius
	var vec := Vector2(raw.x * horizontal_sensitivity, raw.y * vertical_sensitivity)
	if vec.length() > 1.0:
		vec = vec.normalized()
	# Dead zone: below it the stick reports nothing; above it the
	# remaining range is rescaled so full deflection is still 1.0.
	var mag := vec.length()
	if mag < dead_zone:
		vec = Vector2.ZERO
	else:
		var scaled := (mag - dead_zone) / (1.0 - dead_zone)
		vec = vec.normalized() * scaled
	if vec != _vector:
		_vector = vec
		vector_changed.emit(_vector)
	queue_redraw()


# --- Visuals (spec section 1) ---

func _draw() -> void:
	var center := size * 0.5
	var base_r := joystick_radius + 10.0
	var active := _touch_id != -1
	var at_max := _vector.length() >= 0.98
	# QA-137: the kit's base ring + knob, drawn as textures and
	# scaled to the stick's radius. The base brightens while held
	# (the old code did the same with alpha); the aim base's cyan
	# ring + d-pad arrows are baked into the art.
	var base_tex := STICK_AIM_BASE if is_aim else STICK_MOVE_BASE
	var knob_tex := STICK_AIM_KNOB if is_aim else STICK_MOVE_KNOB
	var base_alpha := joystick_opacity if active else joystick_opacity * 0.65
	draw_texture_rect(base_tex, Rect2(center - Vector2(base_r, base_r), Vector2(base_r * 2.0, base_r * 2.0)), false, Color(1, 1, 1, base_alpha))
	# Subtle feedback at maximum displacement: brighter ring.
	if at_max:
		draw_arc(center, base_r - 4.0, 0, TAU, 48, Color(1.0, 0.85, 0.3, 0.8 * joystick_opacity), 3.0)
	# Inner knob: distinct from the base, brighter + slightly larger
	# while touched, biggest at maximum displacement.
	var knob_r := knob_radius * (1.12 if at_max else 1.0)
	var knob_alpha := joystick_opacity if active else joystick_opacity * 0.7
	var knob_c := center + _knob_offset
	draw_texture_rect(knob_tex, Rect2(knob_c - Vector2(knob_r, knob_r), Vector2(knob_r * 2.0, knob_r * 2.0)), false, Color(1, 1, 1, knob_alpha))

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
	# Outer base: semi-transparent dark circle + visible border.
	var base_col := Color(0.05, 0.10, 0.18, 0.55 * joystick_opacity) if active else Color(0.02, 0.03, 0.06, 0.32 * joystick_opacity)
	var border_col := Color(1, 1, 1, 0.70 * joystick_opacity) if active else Color(1, 1, 1, 0.30 * joystick_opacity)
	draw_circle(center, base_r, base_col)
	draw_arc(center, base_r, 0, TAU, 48, border_col, 3.0)
	# Subtle feedback at maximum displacement: brighter ring.
	if at_max:
		draw_arc(center, base_r - 4.0, 0, TAU, 48, Color(1.0, 0.85, 0.3, 0.8 * joystick_opacity), 3.0)
	# Inner knob: distinct from the base, brighter + slightly larger
	# while touched, biggest at maximum displacement.
	var knob_r := knob_radius * (1.12 if at_max else 1.0)
	var knob_col := Color(1, 1, 1, 0.72 * joystick_opacity) if active else Color(1, 1, 1, 0.42 * joystick_opacity)
	draw_circle(center + _knob_offset, knob_r, knob_col)
	draw_arc(center + _knob_offset, knob_r, 0, TAU, 32, Color(1, 1, 1, 0.55 * joystick_opacity), 2.0)

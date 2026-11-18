class_name FireButtonController
extends Control

# FireButtonController: the Mini Militia-style FIRE button.
#
# Circular button, fixed bottom-right (screen space — it lives in the
# HUD CanvasLayer, so it never moves with the camera). Press-and-hold =
# continuous fire at the weapon's rate; release = stop immediately.
#
# TOUCH OWNERSHIP (QA-023): the button owns exactly one touch index.
# `is_held()` is true ONLY while that finger is actively down — the game
# derives `touch_firing` from this and nothing else, so a tap on the
# move stick, the aim stick, GRENADE, WEAPON or any other control can
# never fire the gun. The game routes touches to this button by rect
# (see game.gd _on_touch_press); the button itself never relies on the
# GUI event pipeline, which keeps the behaviour identical headless and
# on a real phone. A finger that slides off the button cancels the shot
# (drag past 1.6x radius releases). Focus loss / app pause resets it,
# so a stuck firing state is impossible (QA-016 lesson).
#
# Semi-auto weapons (pistol, shotgun, sniper) fire one shot per press:
# `consume_press_edge()` returns true exactly once per press; the
# player consumes it in _read_input. Automatic weapons ignore the edge
# and fire while held.

@export var button_radius: float = 45.0

var _touch_id: int = -1
var _press_edge: bool = false
var _pulse_t: float = 0.0
var _press_scale: float = 1.0


func _ready() -> void:
	# The game owns touch routing (see game.gd); this control must not
	# swallow GUI input, or _unhandled_input would never see the touch.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(button_radius * 2.0, button_radius * 2.0)
	size = Vector2(button_radius * 2.0, button_radius * 2.0)
	pivot_offset = size * 0.5


func _notification(what: int) -> void:
	# A touch interrupted by the OS never delivers a release event.
	# Reset here so firing can never get stuck (QA-016).
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		reset_input()


func _process(delta: float) -> void:
	if _touch_id != -1:
		_pulse_t += delta
		queue_redraw()


# --- Touch API (called by the game, which routes touches by rect) ---

func press_touch(index: int, global_pos: Vector2) -> bool:
	if _touch_id != -1:
		return false
	# QA-029: the incoming point is in viewport coordinates. Convert
	# to the button's local space with the global transform with canvas
	# (the ground truth for its on-screen position) before measuring
	# the distance to the centre — comparing against get_global_rect()
	# in a different space missed the button by the camera offset.
	var local := get_global_transform_with_canvas().affine_inverse() * global_pos
	# Only grab touches that actually land on the circle (with a
	# little slack so a thumb near the edge still counts).
	if local.distance_to(size * 0.5) > button_radius * 1.15:
		return false
	_touch_id = index
	_press_edge = true
	_pulse_t = 0.0
	_press_scale = 0.9
	scale = Vector2(_press_scale, _press_scale)
	queue_redraw()
	return true


func drag_touch(index: int, global_pos: Vector2) -> void:
	if index != _touch_id:
		return
	# Sliding the finger off the button cancels the shot.
	var local := get_global_transform_with_canvas().affine_inverse() * global_pos
	if local.distance_to(size * 0.5) > button_radius * 1.6:
		release_touch(index)


func release_touch(index: int) -> void:
	if index != _touch_id:
		return
	reset_input()


func reset_input() -> void:
	_touch_id = -1
	_press_edge = false
	_press_scale = 1.0
	scale = Vector2.ONE
	queue_redraw()


func is_held() -> bool:
	return _touch_id != -1


func get_touch_id() -> int:
	return _touch_id


# True exactly once per press; the player consumes it for semi-auto
# weapons. Consuming clears it, so a held finger never re-triggers.
func consume_press_edge() -> bool:
	var e := _press_edge
	_press_edge = false
	return e


# Peek at the edge WITHOUT consuming it. The player reads the edge in
# _read_input (physics) but touch_firing only updates in _process, so
# a tap that lands just after a physics step would be consumed on a
# frame where the player is not firing yet and the semi-auto shot
# would be lost. The player peeks here and consumes the edge only
# when the shot actually fires (see player.gd _apply_aim_and_fire).
func has_press_edge() -> bool:
	return _press_edge


# --- Visuals: semi-transparent red circle, white outline, white bullet
# icon, subtle pulsing glow while firing. ---

func _draw() -> void:
	var center := size * 0.5
	var held := _touch_id != -1
	# Glow while firing: pulsing outer ring.
	if held:
		var pulse := 0.55 + 0.35 * sin(_pulse_t * 14.0)
		draw_arc(center, button_radius + 8.0, 0, TAU, 48, Color(1.0, 0.45, 0.2, pulse * 0.8), 4.0)
		draw_circle(center, button_radius + 4.0, Color(1.0, 0.35, 0.15, 0.18 + 0.10 * sin(_pulse_t * 14.0)))
	# Base: semi-transparent dark red.
	var base_col := Color(0.75, 0.18, 0.12, 0.62) if held else Color(0.55, 0.14, 0.10, 0.45)
	draw_circle(center, button_radius, base_col)
	draw_arc(center, button_radius, 0, TAU, 48, Color(1, 1, 1, 0.85), 3.0)
	draw_arc(center, button_radius - 5.0, 0, TAU, 48, Color(1, 1, 1, 0.25), 2.0)
	# White bullet icon, pointing up.
	var w := Color(1, 1, 1, 0.95)
	var cx := center.x
	var cy := center.y
	# Tip.
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - 6, cy - 4), Vector2(cx + 6, cy - 4), Vector2(cx, cy - 16),
	]), w)
	# Body.
	draw_rect(Rect2(cx - 6, cy - 4, 12, 16), w)
	# Base rim.
	draw_rect(Rect2(cx - 7, cy + 12, 14, 4), w)

class_name HudBar
extends Control

# QA-137 (v3.14): a health / jetpack bar drawn from the user's HUD
# kit art — the kit's bar frame (empty track) with the kit's fill
# clipped to the current fraction, plus a centred "HP 85" label.
# The kit's bar is one static image, so the fill is a separate
# slice (hud_bar_*_fill.png) drawn only as far as the value goes.
# Same interface as the gohud GoBar it replaces (label_text,
# set_values) so the call sites in game.gd do not change shape.

var label_text: String = "":
	set(value):
		label_text = value
		_refresh_label()

# The bar's state colour (same meaning as the gohud GoBar's ink:
# the game sets it green/cyan normally, yellow when low, red when
# critical). The fill texture already carries the normal colour, so
# a green/cyan ink draws it unmodified (WHITE modulate); a
# yellow/red ink tints the fill toward that warning colour.
var ink: Color = Color.WHITE:
	set(value):
		ink = value
		queue_redraw()

var _frame_tex: Texture2D = null
var _fill_tex: Texture2D = null
var _value: float = 0.0
var _max_value: float = 1.0
var _label: Label = null


func setup(frame_tex: Texture2D, fill_tex: Texture2D) -> void:
	_frame_tex = frame_tex
	_fill_tex = fill_tex
	queue_redraw()


func set_values(value: float, max_value: float, _instant: bool = false) -> void:
	_value = value
	_max_value = maxf(1.0, max_value)
	_refresh_label()
	queue_redraw()


func _ready() -> void:
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 4)
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_refresh_label()


func _refresh_label() -> void:
	if _label == null:
		return
	if label_text.is_empty():
		_label.text = str(int(_value))
	else:
		_label.text = "%s %d" % [label_text, int(_value)]


func _draw() -> void:
	if _frame_tex != null:
		draw_texture_rect(_frame_tex, Rect2(Vector2.ZERO, size), false)
	if _fill_tex != null and _max_value > 0.0:
		# The fill sits in the frame's track: x 4.1%..95.8%,
		# y 14.4%..85.5% of the frame (measured from the kit art).
		var frac := clampf(_value / _max_value, 0.0, 1.0)
		if frac > 0.001:
			var fx := size.x * 0.0414
			var fy := size.y * 0.144
			var fw := size.x * 0.917 * frac
			var fh := size.y * 0.711
			var src_w := float(_fill_tex.get_width()) * frac
			# Green/cyan ink is the fill's own colour (no tint);
			# a yellow/red ink (low health/fuel) tints it.
			var tint := ink if ink.r > 0.7 else Color.WHITE
			draw_texture_rect_region(_fill_tex, Rect2(fx, fy, fw, fh), Rect2(0, 0, src_w, float(_fill_tex.get_height())), tint)

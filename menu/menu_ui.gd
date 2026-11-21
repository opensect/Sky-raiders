class_name MenuUi
extends RefCounted


# QA-140 (v3.15): extracted from main.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `m` (dependency injection).


var m # the owner (main.gd)

# v3.5 QA-059: the menu background is arena_clean.png — a plain
# starry navy sky with mountain silhouettes and NO panel shapes.
# The old arena_blue.png (Sky Brawl arena_map_02) had a rounded-rect
# sign top-left and floating platform pills baked in; those showed
# through the semi-transparent panels on every page as empty
# "ghost boxes" (the v3.4 lobby's floating outlines). The old file
# stays in the repo unused; nothing references it any more.
# QA-089 (v3.7): richer military-arena-at-dusk menu background
# (was the plain starry sky arena_clean.png). Dark and uncluttered
# behind the menu UI — the detail lives at the edges and horizon.
const MENU_BG: Texture2D = preload("res://assets/backgrounds/menu_arena_dusk.png")



func _init(owner) -> void:
	m = owner


func _build_background() -> void:
	# v3.2 NEON ARENA (THEME_SPEC.md §6): ONE imported image — the
	# clean starry sky (arena_clean.png) — stretched full-rect,
	# with a 0.55-alpha dark scrim over it so text stays readable.
	# v3.5 QA-059: the old arena_blue.png is gone — its baked-in
	# rounded-rect sign and platform pills showed through every
	# semi-transparent panel as empty ghost boxes. This image has
	# no rectangles, pills or outlines at all, so nothing can show
	# through any more. The old procedural gradient sky + sun +
	# ground band is gone too.
	var bg := TextureRect.new()
	bg.texture = MENU_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	m.add_child(bg)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.035, 0.078, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_child(dim)


func _cut_accent_stylebox() -> GoStyleBoxCut:
	var sb := GoStyleBoxCut.new()
	sb.bg_color = m.UI_ACCENT
	sb.border_color = m.UI_ACCENT
	sb.border_width = 1.0
	sb.cut = 10.2
	sb.cut_corners = GoStyleBoxCut.ALL
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _style_button(b: Button, font_size: int = 22, min_h: int = 56, accent: bool = false) -> void:
	# Clear any manual stylebox overrides so the gohud theme shows.
	for kind in ["normal", "hover", "pressed", "disabled"]:
		b.remove_theme_stylebox_override(kind)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_override("font", m.FONT_BODY_SEMIBOLD)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", m.UI_FONT)
	b.add_theme_color_override("font_hover_color", m.UI_FONT)
	b.add_theme_color_override("font_pressed_color", Color(0.0, 0.898, 1.0))
	b.add_theme_color_override("font_disabled_color", m.UI_FONT_DISABLED)
	if accent:
		# Primary / selected: cyan fill + dark text (theme accent,
		# theme cut-corner shape). Hover keeps the same fill.
		var sb := _cut_accent_stylebox()
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_color_override("font_color", m.UI_ACCENT_DARK)
		b.add_theme_color_override("font_hover_color", m.UI_ACCENT_DARK)
		b.add_theme_color_override("font_pressed_color", m.UI_ACCENT_DARK)
	b.custom_minimum_size = Vector2(b.custom_minimum_size.x, min_h)


# Selected toggle state (map / mode / limit / time / colour / helmet).
func _style_selected(b: Button, selected: bool, font_size: int = 22) -> void:
	_style_button(b, font_size, int(b.custom_minimum_size.y), selected)


# Danger action (Leave / disconnect): danger-red fill via the same
# cut-corner shape, white text.
func _style_danger_button(b: Button, font_size: int = 22, min_h: int = 56) -> void:
	_style_button(b, font_size, min_h, false)
	var sb := GoStyleBoxCut.new()
	sb.bg_color = Color(1.0, 0.302, 0.427, 0.92)
	sb.border_color = m.UI_DANGER
	sb.border_width = 1.0
	sb.cut = 10.2
	sb.cut_corners = GoStyleBoxCut.ALL
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))


func _panel(style_bg: Color = Color(0.07, 0.11, 0.18, 0.96), transparent: bool = false) -> PanelContainer:
	# Full-rect card: size comes from anchors, never from content minimum
	# size, so a transiently wrong content size can never push it off-screen.
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.offset_left = 16
	p.offset_top = 12
	p.offset_right = -16
	p.offset_bottom = -12
	p.theme = GoUi.theme()
	if transparent:
		# Menu: no panel fill at all — title + buttons float over the
		# arena background + scrim (as in the gohud demo proof shot).
		p.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	else:
		# Theme's own cut-corner panel stylebox, slightly translucent
		# so the arena artwork reads faintly through the edges.
		var s := GoUi.theme().get_stylebox("panel", "PanelContainer")
		if s != null:
			var sb := s.duplicate()
			if sb is GoStyleBoxCut:
				(sb as GoStyleBoxCut).bg_color = Color(style_bg.r, style_bg.g, style_bg.b, 0.92)
				(sb as GoStyleBoxCut).content_margin_left = 24
				(sb as GoStyleBoxCut).content_margin_right = 24
				(sb as GoStyleBoxCut).content_margin_top = 18
				(sb as GoStyleBoxCut).content_margin_bottom = 18
			p.add_theme_stylebox_override("panel", sb)
	p.visible = false
	m.add_child(p)
	return p


# SCROLL_BUG.md §4 — forward drags that start on a button inside a
# ScrollContainer to the container. A Button captures the touch and
# the ScrollContainer never sees the drag otherwise (proven root
# cause). Taps still go through the button's normal pressed path.
func _connect_scroll_button(b: Button, scroll: ScrollContainer) -> void:
	b.gui_input.connect(_on_scrolled_button_gui_input.bind(scroll, b))


func _on_scrolled_button_gui_input(event: InputEvent, scroll: ScrollContainer, b: Button) -> void:
	# Touch drags ONLY. The MouseMotion branch is deliberately NOT
	# here: pointing/emulate_touch_from_mouse duplicates every touch
	# drag as mouse motion, so a motion branch would apply the same
	# delta a second time (a 200 px drag scrolled 400 px). Desktop
	# users scroll with the wheel, which the container handles natively.
	if event is InputEventScreenTouch and event.pressed:
		# A new press starts a new gesture: forget any earlier drag.
		b.set_meta("sc_dragged", false)
	if event is InputEventScreenDrag:
		scroll.scroll_vertical -= event.relative.y
		# v3.5 QA-059: a drag is a scroll, not a tap. The 216 px map
		# cards are taller than the frame-lag offset, so the pointer
		# never leaves the card during a scroll-drag and the release
		# would fire pressed (QA-048 regression in the scroll test).
		# The press handler checks this flag and ignores the tap.
		b.set_meta("sc_dragged", true)


# v3.2: gohud icons replace the hand-drawn _make_icon() shapes.
func _gohud_icon(icon_name: String) -> Texture2D:
	if GoUi.icons().has_icon(StringName(icon_name)):
		return GoUi.icons().texture(StringName(icon_name))
	return null


func _vbox(parent: Control, sep: int = 12) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", sep)
	parent.add_child(box)
	return box


func _section_label(text: String) -> Label:
	# QA-058: section headers are cyan, 22 px SemiBold — the same
	# hierarchy on every page (menu, multiplayer, lobby, settings,
	# customize), so a section reads as a section at a glance.
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", m.FONT_BODY_SEMIBOLD)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", m.UI_ACCENT)
	return l


func _title_label(text: String, size: int = 30) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", m.FONT_TITLE)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", m.UI_FONT)
	return l


# Body / hint / status text (THEME_SPEC.md §3): Rajdhani Regular, NOT
# Orbitron — the variable Orbitron renders too thin and light at
# 16-20 px to read (the menu subtitle showed this in the v3.2 shots).
func _body_label(text: String, size: int = 18) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", m.FONT_BODY)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", m.UI_FONT_MUTED)
	return l


func _show_only(panel: PanelContainer) -> void:
	for p in [m._menu_panel, m._custom_panel, m._settings_panel, m._mp_panel, m._lobby_panel]:
		if p != null:
			p.visible = (p == panel)
	if panel == m._menu_panel:
		m._refresh_profile_card() # QA-078: stats may have changed after a match


func _click() -> void:
	if m._audio != null:
		m._audio.play("click")


class_name MenuScreens
extends RefCounted


# QA-140 (v3.15): extracted from main.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `m` (dependency injection).


var m # the owner (main.gd)

const FRAG_LOGO: Texture2D = preload("res://assets/logo/sky_raiders_logo.png") # QA-145: Sky Raiders logo (crosshair + Orbitron wordmark, drawn in code/PIL) — same style as the v3.5 Frag Arena logo it replaces; const name kept so no other reference changes



func _init(owner) -> void:
	m = owner


func _build_menu() -> void:
	# Home layout: identity and player progress on the left, clear
	# play actions on the right. The two-column layout keeps the
	# main choices visible together without a tall scrolling stack.
	m._menu_panel = m.menu_ui._panel(Color(0.07, 0.11, 0.18, 0.96), true)
	var inset := MarginContainer.new()
	inset.add_theme_constant_override("margin_left", 28)
	inset.add_theme_constant_override("margin_right", 28)
	inset.add_theme_constant_override("margin_top", 18)
	inset.add_theme_constant_override("margin_bottom", 18)
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.size_flags_vertical = Control.SIZE_EXPAND_FILL
	m._menu_panel.add_child(inset)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 32)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inset.add_child(columns)
	var identity := VBoxContainer.new()
	identity.add_theme_constant_override("separation", 18)
	identity.alignment = BoxContainer.ALIGNMENT_CENTER
	identity.custom_minimum_size = Vector2(460, 0)
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(identity)
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 14)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.custom_minimum_size = Vector2(420, 0)
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(actions)
	var box: VBoxContainer = identity
	# QA-145 Sky Raiders: the logo (crosshair emblem + Orbitron
	# wordmark) is the menu heading now — the old "LAN ARENA
	# SHOOTER" text title is gone. 1239x320 art, shown ~460 px
	# wide (same width as the menu buttons), aspect kept.
	var logo := TextureRect.new()
	logo.texture = FRAG_LOGO
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(460, 119)
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(logo)
	var sub = m.menu_ui._body_label("Offline practice or local Wi-Fi matches - no accounts", 20)
	sub.add_theme_color_override("font_color", m.UI_FONT_MUTED)
	box.add_child(sub)
	var title_sep := HSeparator.new()
	title_sep.custom_minimum_size = Vector2(420, 0)
	title_sep.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(title_sep)
	# QA-078: profile card — avatar, name, level and lifetime
	# stats, all local (no account, no server). The numbers come
	# from GameData.record_match, called once per finished match.
	var profile_card := PanelContainer.new()
	profile_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pc_sb := StyleBoxFlat.new()
	pc_sb.bg_color = Color(0.10, 0.16, 0.25, 0.95)
	pc_sb.set_corner_radius_all(10)
	pc_sb.border_color = Color(0.25, 0.38, 0.52)
	pc_sb.set_border_width_all(1)
	pc_sb.content_margin_left = 18
	pc_sb.content_margin_right = 18
	pc_sb.content_margin_top = 14
	pc_sb.content_margin_bottom = 14
	profile_card.add_theme_stylebox_override("panel", pc_sb)
	profile_card.custom_minimum_size = Vector2(460, 0)
	profile_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(profile_card)
	var pc_row := HBoxContainer.new()
	pc_row.add_theme_constant_override("separation", 12)
	profile_card.add_child(pc_row)
	m._profile_portrait = TextureRect.new()
	m._profile_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m._profile_portrait.custom_minimum_size = Vector2(56, 72)
	m._profile_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	m._profile_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pc_row.add_child(m._profile_portrait)
	var pc_vb := VBoxContainer.new()
	pc_vb.add_theme_constant_override("separation", 2)
	pc_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc_row.add_child(pc_vb)
	m._profile_name_lbl = Label.new()
	m._profile_name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m._profile_name_lbl.add_theme_font_override("font", m.FONT_BODY_SEMIBOLD)
	m._profile_name_lbl.add_theme_font_size_override("font_size", 24)
	m._profile_name_lbl.add_theme_color_override("font_color", m.UI_FONT)
	pc_vb.add_child(m._profile_name_lbl)
	m._profile_level_lbl = Label.new()
	m._profile_level_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m._profile_level_lbl.add_theme_font_override("font", m.FONT_BODY_SEMIBOLD)
	m._profile_level_lbl.add_theme_font_size_override("font_size", 20)
	m._profile_level_lbl.add_theme_color_override("font_color", m.UI_ACCENT)
	pc_vb.add_child(m._profile_level_lbl)
	m._profile_stats_lbl = Label.new()
	m._profile_stats_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m._profile_stats_lbl.add_theme_font_override("font", m.FONT_BODY)
	m._profile_stats_lbl.add_theme_font_size_override("font_size", 18)
	m._profile_stats_lbl.add_theme_color_override("font_color", m.UI_FONT_MUTED)
	m._profile_stats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pc_vb.add_child(m._profile_stats_lbl)
	_refresh_profile_card()
	# Primary choices are grouped together in the action column.
	box = actions
	box.add_child(m.menu_ui._section_label("CHOOSE YOUR MODE"))
	var play_row := HBoxContainer.new()
	play_row.add_theme_constant_override("separation", 12)
	play_row.custom_minimum_size = Vector2(420, 68)
	play_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(play_row)
	var solo_btn := Button.new()
	solo_btn.text = "PRACTICE"
	solo_btn.icon = m.menu_ui._gohud_icon("play")
	solo_btn.expand_icon = true
	solo_btn.custom_minimum_size = Vector2(0, 68)
	solo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.menu_ui._style_button(solo_btn, 23, 64, true)
	solo_btn.pressed.connect(_start_solo_practice)
	play_row.add_child(solo_btn)
	var mp_btn := Button.new()
	mp_btn.text = "LAN PLAY"
	mp_btn.expand_icon = true
	mp_btn.custom_minimum_size = Vector2(0, 68)
	mp_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.menu_ui._style_button(mp_btn, 23, 64)
	mp_btn.pressed.connect(func() -> void:
		m.menu_ui._click()
		GameData.solo_practice = false
		m.menu_ui._show_only(m._mp_panel)
	)
	play_row.add_child(mp_btn)
	var cust_btn := Button.new()
	cust_btn.text = "CUSTOMIZATION"
	cust_btn.icon = m.menu_ui._gohud_icon("user")
	cust_btn.expand_icon = true
	cust_btn.custom_minimum_size = Vector2(420, 64)
	cust_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	m.menu_ui._style_button(cust_btn, 26, 64)
	cust_btn.pressed.connect(func() -> void: m.menu_ui._click(); m.menu_ui._show_only(m._custom_panel))
	box.add_child(cust_btn)
	var set_btn := Button.new()
	set_btn.text = "SETTINGS"
	set_btn.icon = m.menu_ui._gohud_icon("settings")
	set_btn.expand_icon = true
	set_btn.custom_minimum_size = Vector2(420, 64)
	set_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	m.menu_ui._style_button(set_btn, 26, 64)
	set_btn.pressed.connect(func() -> void: m.menu_ui._click(); m.menu_ui._show_only(m._settings_panel))
	box.add_child(set_btn)
	var hint = m.menu_ui._body_label("Practice offline, or play together on the same Wi-Fi.", 18)
	hint.add_theme_color_override("font_color", m.UI_FONT_MUTED)
	box.add_child(hint)
	# Phase 6: short music credit on the menu (full text is in Settings).
	var credit = m.menu_ui._body_label(GameData.MUSIC_CREDITS_SHORT, 16)
	credit.add_theme_color_override("font_color", m.UI_FONT_MUTED)
	box.add_child(credit)


func _start_solo_practice() -> void:
	m.menu_ui._click()
	GameData.solo_practice = true
	GameData.game_mode = 0
	m.get_tree().change_scene_to_file(m.GAME_SCENE)


# QA-078: fill the main-menu profile card from the saved lifetime
# stats. Called at build time and every time the menu is shown
# (a match just played may have changed the numbers). Safe to call
# before the card exists (the menu builds it first).
func _refresh_profile_card() -> void:
	if m._profile_name_lbl == null:
		return
	m._profile_portrait.texture = _portrait_texture(GameData.portrait)
	m._profile_name_lbl.text = GameData.player_name
	var lvl := GameData.level_for_kills(GameData.stat_kills)
	var into := GameData.kills_into_level(GameData.stat_kills)
	m._profile_level_lbl.text = "Level %d  •  %d/50 kills to level %d" % [lvl, into, lvl + 1]
	var kd := float(GameData.stat_kills) / float(maxi(GameData.stat_deaths, 1))
	# Two lines on purpose: one line wraps with the K/D value alone
	# on the second line at 460 px card width.
	m._profile_stats_lbl.text = "Matches %d  •  Wins %d  •  K/D %.2f\nKills %d  •  Deaths %d" % [
		GameData.stat_matches, GameData.stat_wins, kd, GameData.stat_kills, GameData.stat_deaths,
	]


func _build_customize() -> void:
	m._custom_panel = m.menu_ui._panel()
	var box = m.menu_ui._vbox(m._custom_panel, 12)
	box.add_child(m.menu_ui._title_label("CUSTOMIZATION", 30))
	# Portrait preview + name.
	var preview_row := HBoxContainer.new()
	preview_row.add_theme_constant_override("separation", 14)
	box.add_child(preview_row)
	m._portrait_tex = TextureRect.new()
	m._portrait_tex.custom_minimum_size = Vector2(96, 128)
	m._portrait_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	m._portrait_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_row.add_child(m._portrait_tex)
	var prev_btn := Button.new()
	prev_btn.text = "<"
	prev_btn.custom_minimum_size = Vector2(56, 56)
	m.menu_ui._style_button(prev_btn, 24, 56)
	prev_btn.pressed.connect(_on_portrait_prev)
	preview_row.add_child(prev_btn)
	var next_btn := Button.new()
	next_btn.text = ">"
	next_btn.custom_minimum_size = Vector2(56, 56)
	m.menu_ui._style_button(next_btn, 24, 56)
	next_btn.pressed.connect(_on_portrait_next)
	preview_row.add_child(next_btn)
	m._name_input = LineEdit.new()
	m._name_input.placeholder_text = "Your name"
	m._name_input.text = GameData.player_name
	m._name_input.max_length = 12
	m._name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m._name_input.custom_minimum_size = Vector2(0, 56)
	m._name_input.add_theme_font_size_override("font_size", 22)
	m._name_input.text_changed.connect(_on_name_changed)
	preview_row.add_child(m._name_input)
	_update_portrait()
	# Colour choice.
	box.add_child(m.menu_ui._section_label("Colour"))
	var color_row := HBoxContainer.new()
	color_row.add_theme_constant_override("separation", 8)
	box.add_child(color_row)
	for i in GameData.COLOR_NAMES.size():
		var b := Button.new()
		b.text = GameData.COLOR_NAMES[i]
		b.custom_minimum_size = Vector2(0, 56)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		m.menu_ui._style_button(b, 20, 56)
		b.pressed.connect(_on_color_pressed.bind(i))
		color_row.add_child(b)
		m._color_buttons.append(b)
	_refresh_customize_buttons()
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(0, 56)
	m.menu_ui._style_button(back_btn, 22, 56)
	back_btn.pressed.connect(func() -> void: m.menu_ui._click(); m.menu_ui._show_only(m._menu_panel))
	box.add_child(back_btn)


func _on_name_changed(text: String) -> void:
	GameData.player_name = text.strip_edges() if text.strip_edges() != "" else "Player"
	GameData.save_settings()


func _on_color_pressed(i: int) -> void:
	m.menu_ui._click()
	GameData.color_index = i
	GameData.save_settings()
	_refresh_customize_buttons()


func _refresh_customize_buttons() -> void:
	for i in m._color_buttons.size():
		var b: Button = m._color_buttons[i]
		b.text = ("✓ " if i == GameData.color_index else "") + GameData.COLOR_NAMES[i]
		m.menu_ui._style_selected(b, i == GameData.color_index, 20)


func _on_portrait_prev() -> void:
	m.menu_ui._click()
	GameData.portrait = (GameData.portrait + 19) % 20
	GameData.save_settings()
	_update_portrait()


func _on_portrait_next() -> void:
	m.menu_ui._click()
	GameData.portrait = (GameData.portrait + 1) % 20
	GameData.save_settings()
	_update_portrait()


# Phase 4 — portraits 0-14 are the original soldier variants;
# 15-19 are the Sky Brawl robot colour variants (lobby select only —
# single static frames, never the in-game sprite).
func _portrait_texture(i: int) -> Texture2D:
	var idx := clampi(i, 0, 19)
	if idx < 15:
		return load("res://assets/characters/alt_%02d.png" % idx)
	return load("res://assets/skybrawl/characters/character_%03d.png" % (idx - 14))


func _update_portrait() -> void:
	if m._portrait_tex == null:
		return
	m._portrait_tex.texture = _portrait_texture(GameData.portrait)


func _build_settings() -> void:
	m._settings_panel = m.menu_ui._panel()
	var box = m.menu_ui._vbox(m._settings_panel, 12)
	# Tall content scrolls (same pattern as the lobby).
	var scroll := ScrollContainer.new()
	m._settings_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	box = inner
	box.add_child(m.menu_ui._title_label("SETTINGS", 30))
	box.add_child(m.menu_ui._section_label("Audio"))
	box.add_child(_slider_row("Sound volume", GameData.sfx_volume, _on_sfx_changed))
	box.add_child(_slider_row("Music volume", GameData.music_volume, _on_music_changed))
	# Phase 6: music on/off (separate from volume — off stops the
	# track entirely; on resumes the menu track).
	m._music_check = CheckButton.new()
	m._music_check.text = "Music on"
	m._music_check.add_theme_font_size_override("font_size", 20)
	m._music_check.button_pressed = GameData.music_enabled
	m._music_check.toggled.connect(_on_music_enabled_toggled)
	box.add_child(m._music_check)
	# QA-128 (v3.11): SFX on/off (separate from volume — off mutes
	# every sound effect, music keeps playing).
	m._sfx_check = CheckButton.new()
	m._sfx_check.text = "Sound effects on"
	m._sfx_check.add_theme_font_size_override("font_size", 20)
	m._sfx_check.button_pressed = GameData.sfx_enabled
	m._sfx_check.toggled.connect(_on_sfx_enabled_toggled)
	box.add_child(m._sfx_check)
	box.add_child(m.menu_ui._section_label("Controls"))
	box.add_child(_slider_row("Control sensitivity", GameData.sensitivity, _on_sensitivity_changed, 0.5, 2.0))
	# v3.2: the FIRE button is gone — the right stick aims AND fires
	# (CONTROLS_CHANGE.md). No size/side setting remains.
	var controls_note := Label.new()
	controls_note.text = "Controls: left stick moves, push up to jump / fly, right stick aims and shoots."
	controls_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_note.add_theme_font_override("font", m.FONT_BODY)
	controls_note.add_theme_font_size_override("font_size", 18)
	controls_note.add_theme_color_override("font_color", m.UI_FONT_MUTED)
	box.add_child(controls_note)
	m._fps_check = CheckButton.new()
	m._fps_check.text = "Show FPS counter (in matches)"
	m._fps_check.add_theme_font_size_override("font_size", 20)
	m._fps_check.button_pressed = GameData.show_fps
	m._fps_check.toggled.connect(_on_fps_toggled)
	box.add_child(m._fps_check)
	m._invert_check = CheckButton.new()
	m._invert_check.text = "Invert aim (up = down)"
	m._invert_check.add_theme_font_size_override("font_size", 20)
	m._invert_check.button_pressed = GameData.invert_aim
	m._invert_check.toggled.connect(_on_invert_toggled)
	box.add_child(m._invert_check)
	# Phase 6: music attribution (CC BY 4.0 — must appear in-game).
	box.add_child(m.menu_ui._section_label("Music credits"))
	var credits := Label.new()
	credits.text = GameData.MUSIC_CREDITS
	credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credits.add_theme_font_size_override("font_size", 18)
	credits.add_theme_color_override("font_color", m.UI_FONT_MUTED)
	box.add_child(credits)
	var font_credit := Label.new()
	font_credit.text = "Orbitron © 2018 The Orbitron Project Authors, Rajdhani © 2014 Indian Type Foundry — SIL Open Font License 1.1"
	font_credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	font_credit.add_theme_font_override("font", m.FONT_BODY)
	font_credit.add_theme_font_size_override("font_size", 16)
	font_credit.add_theme_color_override("font_color", m.UI_FONT_MUTED)
	box.add_child(font_credit)
	# v3.2 QA-047: privacy policy in-app (Play compliance). The full
	# policy is also in PRIVACY_POLICY.md in the project.
	box.add_child(m.menu_ui._section_label("Privacy"))
	var privacy_lbl := Label.new()
	privacy_lbl.text = "Sky Raiders collects no personal data. No accounts, no sign-in, no ads, no analytics, no tracking. Phones talk directly to each other over your Wi-Fi (LAN) only — nothing is sent to the internet or any server. Settings (name, controls, volume) stay on your phone."
	privacy_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	privacy_lbl.add_theme_font_override("font", m.FONT_BODY)
	privacy_lbl.add_theme_font_size_override("font_size", 18)
	privacy_lbl.add_theme_color_override("font_color", m.UI_FONT_MUTED)
	box.add_child(privacy_lbl)
	var version_lbl := Label.new()
	version_lbl.text = "Sky Raiders v" + GameData.BUILD_VERSION + "  •  LAN only — no accounts, no servers" # v3.11: was hardcoded "v3.6" — now follows BUILD_VERSION so it can never go stale again
	version_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	version_lbl.add_theme_font_size_override("font_size", 18)
	version_lbl.add_theme_color_override("font_color", m.UI_FONT_MUTED)
	box.add_child(version_lbl)
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(0, 56)
	m.menu_ui._style_button(back_btn, 22, 56)
	back_btn.pressed.connect(func() -> void: m.menu_ui._click(); m.menu_ui._show_only(m._menu_panel))
	box.add_child(back_btn)
	m.menu_ui._connect_scroll_button(back_btn, m._settings_scroll)


func _slider_row(label_text: String, value: float, on_change: Callable, min_v: float = 0.0, max_v: float = 1.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(190, 0)
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = 0.05
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(on_change)
	row.add_child(slider)
	return row


func _on_sfx_changed(v: float) -> void:
	GameData.sfx_volume = v
	GameData.save_settings()
	if m._audio != null:
		m._audio.set_volumes(GameData.sfx_volume, GameData.music_volume)


func _on_music_changed(v: float) -> void:
	GameData.music_volume = v
	GameData.save_settings()
	if m._audio != null:
		m._audio.set_volumes(GameData.sfx_volume, GameData.music_volume)


func _on_sensitivity_changed(v: float) -> void:
	GameData.sensitivity = v
	GameData.save_settings()


func _on_music_enabled_toggled(on: bool) -> void:
	GameData.music_enabled = on
	GameData.save_settings()
	if m._audio != null:
		m._audio.set_music_enabled(on)


func _on_sfx_enabled_toggled(on: bool) -> void:
	# QA-128 (v3.11): SFX mute toggle — stops any playing SFX and
	# makes audio.play() a no-op until turned back on.
	GameData.sfx_enabled = on
	GameData.save_settings()
	if m._audio != null:
		m._audio.set_sfx_enabled(on)


func _on_fps_toggled(on: bool) -> void:
	GameData.show_fps = on
	GameData.save_settings()


func _on_invert_toggled(on: bool) -> void:
	GameData.invert_aim = on
	GameData.save_settings()


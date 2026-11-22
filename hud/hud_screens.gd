class_name HudScreens
extends RefCounted


# QA-140 (v3.15): extracted from hud/hud_builder.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `g` (dependency injection).


var g # the owner (hud/hud_builder.gd)


func _init(owner) -> void:
	g = owner


func _build_pause_menu() -> void:
	# QA-113 (v3.9): same clean, spacious layout as the scoreboard —
	# wider panel, section labels, slider value labels, match info
	# line, 56 px buttons. Layout only, no logic changes.
	g.pause_panel = PanelContainer.new()
	g.pause_panel.theme = GoUi.theme()
	g.pause_panel.custom_minimum_size = Vector2(520, 0)
	g.pause_panel.add_theme_stylebox_override("panel", g.hud_builder._panel_style())
	g.pause_panel.visible = false
	g.pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	g.hud_builder._dialog_wrap().add_child(g.pause_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	g.pause_panel.add_child(box)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", g.FONT_TITLE)
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", g.UI_FONT)
	box.add_child(title)
	g._pause_info_label = Label.new()
	g._pause_info_label.text = ""
	g._pause_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g._pause_info_label.add_theme_font_size_override("font_size", 18)
	g._pause_info_label.add_theme_color_override("font_color", Color(0.62, 0.66, 0.72))
	g._pause_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(g._pause_info_label)
	var resume_btn := Button.new()
	resume_btn.text = "Resume"
	g.hud_builder._style_hud_button(resume_btn, true)
	g.hud_builder._style_pill_button(resume_btn) # QA-145: bounded pill-button try (screenshot-verified)
	resume_btn.custom_minimum_size = Vector2(0, 56)
	resume_btn.pressed.connect(g._toggle_pause)
	box.add_child(resume_btn)
	# Phase 4: weapon info — damage / fire rate / magazine / reload
	# per weapon, straight from weapons.gd (read-only display).
	var weapons_btn := Button.new()
	weapons_btn.text = "Weapons"
	g.hud_builder._style_hud_button(weapons_btn)
	weapons_btn.custom_minimum_size = Vector2(0, 56)
	weapons_btn.pressed.connect(func() -> void: _show_weapon_panel(true))
	box.add_child(weapons_btn)
	var sound_lbl := Label.new()
	sound_lbl.text = "SOUND"
	sound_lbl.add_theme_font_size_override("font_size", 18)
	sound_lbl.add_theme_color_override("font_color", Color(0.62, 0.66, 0.72))
	box.add_child(sound_lbl)
	var sfx_row := HBoxContainer.new()
	sfx_row.add_theme_constant_override("separation", 8)
	box.add_child(sfx_row)
	var sfx_lbl := Label.new()
	sfx_lbl.text = "Sound"
	sfx_lbl.custom_minimum_size = Vector2(70, 0)
	sfx_row.add_child(sfx_lbl)
	var sfx_slider := HSlider.new()
	sfx_slider.min_value = 0.0
	sfx_slider.max_value = 1.0
	sfx_slider.step = 0.05
	sfx_slider.value = GameData.sfx_volume
	sfx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_slider.value_changed.connect(g._on_sfx_volume_changed)
	sfx_row.add_child(sfx_slider)
	g._sfx_value_label = Label.new()
	g._sfx_value_label.text = "%d%%" % int(GameData.sfx_volume * 100.0)
	g._sfx_value_label.custom_minimum_size = Vector2(52, 0)
	g._sfx_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sfx_row.add_child(g._sfx_value_label)
	var mus_row := HBoxContainer.new()
	mus_row.add_theme_constant_override("separation", 8)
	box.add_child(mus_row)
	var mus_lbl := Label.new()
	mus_lbl.text = "Music"
	mus_lbl.custom_minimum_size = Vector2(70, 0)
	mus_row.add_child(mus_lbl)
	var mus_slider := HSlider.new()
	mus_slider.min_value = 0.0
	mus_slider.max_value = 1.0
	mus_slider.step = 0.05
	mus_slider.value = GameData.music_volume
	mus_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mus_slider.value_changed.connect(g._on_music_volume_changed)
	mus_row.add_child(mus_slider)
	g._music_value_label = Label.new()
	g._music_value_label.text = "%d%%" % int(GameData.music_volume * 100.0)
	g._music_value_label.custom_minimum_size = Vector2(52, 0)
	g._music_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mus_row.add_child(g._music_value_label)
	var leave_btn := Button.new()
	leave_btn.text = "Leave Match"
	g.hud_builder._style_hud_button(leave_btn)
	leave_btn.custom_minimum_size = Vector2(0, 56)
	leave_btn.pressed.connect(g._on_leave_pressed)
	box.add_child(leave_btn)


func _build_end_screen() -> void:
	# QA-113 (v3.9): wider panel, bigger title, more breathing room.
	g.end_panel = PanelContainer.new()
	g.end_panel.theme = GoUi.theme()
	# QA-145 (v4.1, Worker V): 620 px, not 560 — the end screen
	# now marks your own row ("►" + white name + "(YOU)", like
	# the scoreboard), and "Player [RED] (YOU)" clipped to "(Y"
	# in the 560 px panel at both resolutions. The extra 60 px
	# gives the name column room; nothing else moves.
	g.end_panel.custom_minimum_size = Vector2(620, 0)
	g.end_panel.add_theme_stylebox_override("panel", g.hud_builder._panel_style())
	g.end_panel.visible = false
	g.hud_builder._dialog_wrap().add_child(g.end_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	g.end_panel.add_child(box)
	g._end_box = box
	# QA-145 (Worker F): the winged-shield emblem tops the end
	# screen (win/lose-independent — a win-only emblem would need
	# game_match.gd, which this worker cannot touch).
	var emblem := TextureRect.new()
	emblem.texture = g.hud_builder.TEX_UI_EMBLEM
	emblem.custom_minimum_size = Vector2(180, 95)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(emblem)
	g.end_title = Label.new()
	g.end_title.text = ""
	g.end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g.end_title.add_theme_font_override("font", g.FONT_TITLE)
	g.end_title.add_theme_font_size_override("font_size", 34)
	g.end_title.add_theme_color_override("font_color", g.UI_FONT)
	box.add_child(g.end_title)
	g.end_list = VBoxContainer.new()
	g.end_list.add_theme_constant_override("separation", 4)
	box.add_child(g.end_list)
	g.end_rematch_btn = Button.new()
	g.end_rematch_btn.text = "Rematch"
	g.hud_builder._style_hud_button(g.end_rematch_btn, true)
	g.end_rematch_btn.custom_minimum_size = Vector2(0, 56)
	g.end_rematch_btn.pressed.connect(g._on_rematch_pressed)
	box.add_child(g.end_rematch_btn)
	# QA-145 (v4.1, Worker V): the Rematch button is host-only,
	# so a non-host player saw no way back into a game and no
	# warning that the host's Rematch would pull everyone into a
	# new match. This line tells each side what happens next;
	# game_match.gd sets its text when the end screen shows.
	g.end_hint = Label.new()
	g.end_hint.text = ""
	g.end_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g.end_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	g.end_hint.add_theme_font_size_override("font_size", 18)
	g.end_hint.add_theme_color_override("font_color", Color(0.62, 0.66, 0.72))
	box.add_child(g.end_hint)
	var back_btn := Button.new()
	# QA-060: this used to say "Back to Lobby" but it goes to the
	# main menu (_on_leave_pressed changes scene to main.tscn).
	back_btn.text = "Back to Menu"
	g.hud_builder._style_hud_button(back_btn)
	back_btn.custom_minimum_size = Vector2(0, 56)
	back_btn.pressed.connect(g._on_leave_pressed)
	box.add_child(back_btn)


func _build_scoreboard() -> void:
	# QA-113 (v3.9): wider panel, bigger title, breathing room —
	# the old 420 px panel with 30 px title cramped 10-player rows.
	g.scoreboard_panel = PanelContainer.new()
	g.scoreboard_panel.theme = GoUi.theme()
	g.scoreboard_panel.custom_minimum_size = Vector2(560, 0)
	g.scoreboard_panel.add_theme_stylebox_override("panel", g.hud_builder._panel_style())
	g.scoreboard_panel.visible = false
	g.hud_builder._dialog_wrap().add_child(g.scoreboard_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	g.scoreboard_panel.add_child(box)
	var title := Label.new()
	title.text = "SCOREBOARD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", g.FONT_TITLE)
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", g.UI_FONT)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "%s  •  %s" % [GameData.MODE_NAMES[g.game_mode], GameData.MAP_NAMES[g.map_id]]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.62, 0.66, 0.72))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)
	g.scoreboard_list = VBoxContainer.new()
	g.scoreboard_list.add_theme_constant_override("separation", 6)
	box.add_child(g.scoreboard_list)
	var close_btn := Button.new()
	close_btn.text = "Close"
	g.hud_builder._style_hud_button(close_btn)
	close_btn.custom_minimum_size = Vector2(0, 56)
	close_btn.pressed.connect(func() -> void: g.scoreboard_panel.visible = false)
	box.add_child(close_btn)


func _build_error_panel() -> void:
	g.error_panel = PanelContainer.new()
	g.error_panel.theme = GoUi.theme()
	g.error_panel.custom_minimum_size = Vector2(520, 0)
	g.error_panel.add_theme_stylebox_override("panel", g.hud_builder._panel_style_red()) # QA-145: red panel for errors
	g.error_panel.visible = false
	g.hud_builder._dialog_wrap().add_child(g.error_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	g.error_panel.add_child(box)
	g.error_label = Label.new()
	g.error_label.text = ""
	g.error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g.error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	g.error_label.add_theme_font_override("font", g.FONT_BODY_MEDIUM)
	g.error_label.add_theme_font_size_override("font_size", 22)
	g.error_label.add_theme_color_override("font_color", g.UI_FONT)
	box.add_child(g.error_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var retry_btn := Button.new()
	retry_btn.text = "Retry"
	g.hud_builder._style_hud_button(retry_btn, true)
	retry_btn.custom_minimum_size = Vector2(0, 56)
	retry_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	retry_btn.pressed.connect(g._on_retry_pressed)
	row.add_child(retry_btn)
	var back_btn := Button.new()
	back_btn.text = "Back"
	g.hud_builder._style_hud_button(back_btn)
	back_btn.custom_minimum_size = Vector2(0, 56)
	back_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_btn.pressed.connect(g._on_leave_pressed)
	row.add_child(back_btn)


func _build_weapon_panel() -> void:
	g._weapon_panel = PanelContainer.new()
	g._weapon_panel.theme = GoUi.theme()
	g._weapon_panel.custom_minimum_size = Vector2(520, 0)
	g._weapon_panel.add_theme_stylebox_override("panel", g.hud_builder._panel_style())
	g._weapon_panel.visible = false
	g._weapon_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	g.hud_builder._dialog_wrap().add_child(g._weapon_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	g._weapon_panel.add_child(box)
	var title := Label.new()
	title.text = "WEAPONS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", g.FONT_TITLE)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", g.UI_FONT)
	box.add_child(title)
	var hint := Label.new()
	hint.text = "Damage is per hit. Rate is shots per second. Pick up weapons on the map — the pistol is your starting sidearm."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88))
	box.add_child(hint)
	g._weapon_list = VBoxContainer.new()
	g._weapon_list.add_theme_constant_override("separation", 4)
	box.add_child(g._weapon_list)
	for id in WeaponData.TABLE.keys():
		var w: Dictionary = WeaponData.TABLE[id]
		var rate: float = 1.0 / float(w["rate"]) if float(w["rate"]) > 0.0 else 0.0
		var lbl := Label.new()
		lbl.text = "%s — DMG %d  •  %.1f/s  •  Mag %d  •  Reload %.1fs%s%s" % [
			String(w["name"]), int(w["damage"]), rate, int(w["mag"]),
			float(w["reload"]),
			"  •  Auto" if bool(w["auto"]) else "  •  Tap to fire",
			"  •  Explosive" if bool(w["explosive"]) else "",
		]
		lbl.add_theme_font_size_override("font_size", 20)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		g._weapon_list.add_child(lbl)
	var close_btn := Button.new()
	close_btn.text = "Close"
	g.hud_builder._style_hud_button(close_btn, true)
	close_btn.custom_minimum_size = Vector2(0, 56)
	close_btn.pressed.connect(func() -> void: _show_weapon_panel(false))
	box.add_child(close_btn)


func _show_weapon_panel(show: bool) -> void:
	g._weapon_panel.visible = show
	# The pause menu stays behind it; closing returns to pause.


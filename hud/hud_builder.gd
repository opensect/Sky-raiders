class_name HudBuilder
extends RefCounted


# QA-139 (v3.15): extracted from game.gd. This module owns no
# state of its own: every field it reads or writes lives on the
# game node and is reached through `g` (dependency injection).
# game.gd keeps a thin delegating wrapper for each function the
# rest of the game calls, so no call site had to change.


var g # the game node (game.gd)


func _init(game) -> void:
	g = game


# v2.5: dark outline for HUD text so it stays readable over bright
# map skies (bright day ones as well as dark ones).
func _outline_label(l: Label) -> void:
	# v3.2 NEON ARENA: HUD numbers in Rajdhani Bold ice, with a dark
	# outline so they stay readable over bright and dark maps alike.
	l.add_theme_font_override("font", g.FONT_BODY_BOLD)
	l.add_theme_color_override("font_color", g.UI_FONT)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)


func _build_hud() -> void:
	g.hud = CanvasLayer.new()
	g.hud.name = "HUD"
	g.hud.layer = 10
	g.hud.process_mode = Node.PROCESS_MODE_ALWAYS
	g.add_child(g.hud)

	# QA-057: the top bar is three anchored sections, not one HBox —
	# the right side is a real panel (its content is ~230 px tall,
	# far taller than a 52 px bar), and the timer must stay centred
	# on the screen, not centred in the space left over by the sides.
	# QA-122 (v3.11): health + jetpack bars redesigned — one clean
	# dark panel behind both bars (same gohud pill style as the
	# top-right), thicker bars, bigger numbers, so they read at a
	# glance and never fight the message area.
	var bars_panel := PanelContainer.new()
	bars_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	bars_panel.offset_left = 12
	bars_panel.offset_right = 300
	bars_panel.offset_top = 8
	bars_panel.offset_bottom = 94 # QA-137: kit bars are 34 px tall (was 80 for the 26/18 px gohud bars)
	bars_panel.theme = GoUi.theme()
	var bars_sb := GoUi.theme().get_stylebox("panel", "PanelContainer")
	if bars_sb != null:
		var bars_dup := bars_sb.duplicate()
		if bars_dup is GoStyleBoxCut:
			(bars_dup as GoStyleBoxCut).bg_color = Color(0.03, 0.07, 0.13, 0.88)
			(bars_dup as GoStyleBoxCut).content_margin_left = 8
			(bars_dup as GoStyleBoxCut).content_margin_right = 8
			(bars_dup as GoStyleBoxCut).content_margin_top = 6
			(bars_dup as GoStyleBoxCut).content_margin_bottom = 6
		bars_panel.add_theme_stylebox_override("panel", bars_dup)
	g.hud.add_child(bars_panel)

	var left := VBoxContainer.new()
	left.set_anchors_preset(Control.PRESET_TOP_LEFT)
	left.offset_left = 16
	left.offset_top = 12
	left.offset_right = 296
	left.offset_bottom = 86 # QA-137: two 34 px kit bars + 6 px separation (was 72)
	left.add_theme_constant_override("separation", 6)
	g.hud.add_child(left)

	# v3.2: health and jetpack fuel as gohud GoBars — the bar shows
	# its own label + number (readout VALUE, set explicitly so the
	# demo's "1 / 1" fraction can never appear), and the value is
	# set instantly (ease_seconds 0) so hits read at a glance.
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	left.add_child(hp_row)

	# QA-137 (v3.14): health and jetpack bars are the user's HUD kit
	# art now (HudBar: kit frame + kit fill clipped to the value).
	# The kit bar is 628x97 (aspect 6.5), so at 220 px wide it is
	# 34 px tall; the panel grows to fit (was 72 px for the 26/18
	# px gohud bars). Label + number ride centred on the bar.
	g.hp_bar = HudBar.new()
	g.hp_bar.setup(g.HUD_TEX_BAR_HEALTH_FRAME, g.HUD_TEX_BAR_HEALTH_FILL)
	g.hp_bar.label_text = "HP"
	g.hp_bar.custom_minimum_size = Vector2(220, 34)
	g.hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.hp_bar.set_values(100, 100, false)
	hp_row.add_child(g.hp_bar)

	var fuel_row := HBoxContainer.new()
	fuel_row.add_theme_constant_override("separation", 8)
	left.add_child(fuel_row)

	g.fuel_bar = HudBar.new()
	g.fuel_bar.setup(g.HUD_TEX_BAR_JETPACK_FRAME, g.HUD_TEX_BAR_JETPACK_FILL)
	g.fuel_bar.label_text = "JETPACK"
	g.fuel_bar.custom_minimum_size = Vector2(220, 34)
	g.fuel_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.fuel_bar.set_values(PhysicsConfig.FUEL_MAX, PhysicsConfig.FUEL_MAX, false) # QA-132: full 405 tank
	fuel_row.add_child(g.fuel_bar)

	var mid := VBoxContainer.new()
	mid.set_anchors_preset(Control.PRESET_CENTER_TOP)
	mid.offset_left = -200
	mid.offset_right = 200
	mid.offset_top = 12
	mid.offset_bottom = 120
	g.hud.add_child(mid)
	g.timer_label = Label.new()
	g.timer_label.text = "5:00"
	g.timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g.timer_label.add_theme_font_size_override("font_size", 32)
	_outline_label(g.timer_label)
	mid.add_child(g.timer_label)
	g.score_label = Label.new()
	g.score_label.text = ""
	g.score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g.score_label.add_theme_font_size_override("font_size", 20)
	_outline_label(g.score_label)
	mid.add_child(g.score_label)
	# QA-079: slim K/D line, always visible under the score — the
	# v3.6 compact corner hid kills/deaths behind SCORE, so a
	# player could not glance at them mid-fight. One short line,
	# centred, no panel, no extra footprint.
	g._kd_label = Label.new()
	g._kd_label.text = "K 0 • D 0"
	g._kd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g._kd_label.add_theme_font_size_override("font_size", 18)
	_outline_label(g._kd_label)
	mid.add_child(g._kd_label)
	# Phase 5 — visible centre-weapon timer (pinned Sniper/Rocket).
	g._centre_label = Label.new()
	g._centre_label.text = ""
	g._centre_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g._centre_label.add_theme_font_size_override("font_size", 16)
	_outline_label(g._centre_label)
	mid.add_child(g._centre_label)
	# QA-112 (v3.9): CTF flag status lines (Skyfall only — hidden
	# on every other map/mode). "⚑ RED: home / carried / dropped".
	for team in [0, 1]:
		var fl := Label.new()
		fl.text = ""
		fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fl.add_theme_font_size_override("font_size", 16)
		fl.add_theme_color_override("font_color", Color(0.95, 0.3, 0.25) if team == 0 else Color(0.25, 0.55, 0.95))
		_outline_label(fl)
		fl.visible = false
		mid.add_child(fl)
		g._ctf_flag_labels.append(fl)
	# QA-119 (v3.11): power-up slots live in the TOP-RIGHT panel
	# (built below, under the ammo chip) — not in the centre-top
	# mid column any more. Tap a filled slot to activate it; the
	# active boost + time left shows under the row.
	# QA-114 (v3.9): comeback + random-event lines (Skyfall CTF).
	# Both teams see the same lines, so the catch-up help is never
	# a hidden buff and an event is never a surprise.
	g._sf_comeback_label = Label.new()
	g._sf_comeback_label.text = ""
	g._sf_comeback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g._sf_comeback_label.add_theme_font_size_override("font_size", 16)
	g._sf_comeback_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	_outline_label(g._sf_comeback_label)
	g._sf_comeback_label.visible = false
	mid.add_child(g._sf_comeback_label)
	g._sf_event_label = Label.new()
	g._sf_event_label.text = ""
	g._sf_event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g._sf_event_label.add_theme_font_size_override("font_size", 16)
	g._sf_event_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	_outline_label(g._sf_event_label)
	g._sf_event_label.visible = false
	mid.add_child(g._sf_event_label)

	# QA-067 (v3.6) — COMPACT TOP-RIGHT. The v3.5 QA-057 panel was
	# 284x268 px of always-on stats and the user said it BLOCKS THE
	# SCREEN during play. Now only two 56 px icon buttons live in
	# this corner (SCORE + pause, gohud GoIconButtons in a slim
	# pill), and the stats hide behind SCORE: Kills / Deaths /
	# Players are NOT on screen any more — tap SCORE and the
	# scoreboard shows them (same rows as before, sorted by kills).
	# Weapon + ammo and grenades stay visible as ONE slim line
	# under the pill: they are live combat info, not stats (the
	# reload state — "Rifle - reloading 47%" — only ever showed
	# there, and the simple reload button (QA-070) has no other
	# readout). Total top-right footprint is now ~348x94 px
	# (pill 184x56 + one 30 px ammo line) instead of 284x268 —
	# the centre of the screen and the kill-feed area stay clear.
	# Both buttons work exactly as before (SCORE toggles the
	# scoreboard, pause toggles the pause menu); _topright_btn_row
	# still holds them, so _build_touch_controls and
	# is_hud_control_pos need no changes.
	var topright_pill := PanelContainer.new()
	topright_pill.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	topright_pill.offset_left = -196
	topright_pill.offset_right = -12
	topright_pill.offset_top = 12
	topright_pill.offset_bottom = 68
	topright_pill.theme = GoUi.theme()
	var pill_sb := GoUi.theme().get_stylebox("panel", "PanelContainer")
	if pill_sb != null:
		var pill_dup := pill_sb.duplicate()
		if pill_dup is GoStyleBoxCut:
			(pill_dup as GoStyleBoxCut).bg_color = Color(0.03, 0.07, 0.13, 0.88)
			(pill_dup as GoStyleBoxCut).content_margin_left = 8
			(pill_dup as GoStyleBoxCut).content_margin_right = 8
			(pill_dup as GoStyleBoxCut).content_margin_top = 0
			(pill_dup as GoStyleBoxCut).content_margin_bottom = 0
		topright_pill.add_theme_stylebox_override("panel", pill_dup)
	g.hud.add_child(topright_pill)

	# Button row: SCORE + pause land here from _build_touch_controls.
	g._topright_btn_row = HBoxContainer.new()
	g._topright_btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	g._topright_btn_row.add_theme_constant_override("separation", 8)
	topright_pill.add_child(g._topright_btn_row)

	# Slim ammo line under the pill: weapon icon + "Rifle 30/90"
	# + grenades. One row, ~30 px tall, translucent so the map
	# reads through faintly but the text stays readable.
	var ammo_chip := PanelContainer.new()
	ammo_chip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ammo_chip.offset_left = -360
	ammo_chip.offset_right = -12
	ammo_chip.offset_top = 76
	ammo_chip.offset_bottom = 106
	var ammo_sb := StyleBoxFlat.new()
	ammo_sb.bg_color = Color(0.03, 0.07, 0.13, 0.75)
	ammo_sb.set_corner_radius_all(8)
	ammo_sb.content_margin_left = 10
	ammo_sb.content_margin_right = 10
	ammo_sb.content_margin_top = 2
	ammo_sb.content_margin_bottom = 2
	ammo_chip.add_theme_stylebox_override("panel", ammo_sb)
	g.hud.add_child(ammo_chip)
	var ammo_row := HBoxContainer.new()
	ammo_row.alignment = BoxContainer.ALIGNMENT_END
	ammo_row.add_theme_constant_override("separation", 8)
	ammo_chip.add_child(ammo_row)

	# QA-119 (v3.11) + QA-130: power-up slots — TOP-RIGHT, a bit
	# down from the top edge (below the ammo chip, y114), so they
	# clear the SCORE/pause pill, the ammo chip, the message area,
	# the health/jetpack bars and the height bar at both
	# resolutions. Same gohud pill style as the top-right pill:
	# dark navy, rounded, translucent. 3 plain 56 px buttons —
	# empty shows the numbered slot background, filled shows the
	# power-up icon; tap to activate. The active boost + time left
	# shows under the row.
	g._sf_slot_panel = PanelContainer.new()
	g._sf_slot_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	g._sf_slot_panel.offset_left = -360
	g._sf_slot_panel.offset_right = -12
	g._sf_slot_panel.offset_top = 114
	g._sf_slot_panel.offset_bottom = 206
	g._sf_slot_panel.theme = GoUi.theme()
	var slot_sb := GoUi.theme().get_stylebox("panel", "PanelContainer")
	if slot_sb != null:
		var slot_dup := slot_sb.duplicate()
		if slot_dup is GoStyleBoxCut:
			(slot_dup as GoStyleBoxCut).bg_color = Color(0.03, 0.07, 0.13, 0.88)
			(slot_dup as GoStyleBoxCut).content_margin_left = 8
			(slot_dup as GoStyleBoxCut).content_margin_right = 8
			(slot_dup as GoStyleBoxCut).content_margin_top = 6
			(slot_dup as GoStyleBoxCut).content_margin_bottom = 6
		g._sf_slot_panel.add_theme_stylebox_override("panel", slot_dup)
	g._sf_slot_panel.visible = false
	g.hud.add_child(g._sf_slot_panel)
	var slot_box := VBoxContainer.new()
	slot_box.add_theme_constant_override("separation", 4)
	g._sf_slot_panel.add_child(slot_box)
	var slot_row := HBoxContainer.new()
	slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slot_row.add_theme_constant_override("separation", 8)
	slot_box.add_child(slot_row)
	g._sf_slot_row = slot_row
	for i in 3:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(56, 56)
		btn.expand_icon = true
		btn.icon = g.SF_TEX_SLOT[i]
		_style_hud_button(btn)
		btn.pressed.connect(g._on_slot_pressed.bind(i))
		slot_row.add_child(btn)
		g._sf_slot_buttons.append(btn)
	g._sf_active_boost_label = Label.new()
	g._sf_active_boost_label.text = ""
	g._sf_active_boost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g._sf_active_boost_label.add_theme_font_size_override("font_size", 16)
	g._sf_active_boost_label.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	_outline_label(g._sf_active_boost_label)
	g._sf_active_boost_label.visible = false
	slot_box.add_child(g._sf_active_boost_label)

	# Kills / Deaths / Players are HIDDEN behind SCORE in v3.6 —
	# the labels stay alive (_update_hud still writes them every
	# frame, and the scoreboard reads the same player data) but
	# their container is invisible, so nothing draws on screen.
	var hidden_stats := VBoxContainer.new()
	hidden_stats.visible = false
	g.hud.add_child(hidden_stats)

	g.kills_label = Label.new()
	g.kills_label.text = "Kills: 0"
	g.kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	g.kills_label.add_theme_font_size_override("font_size", 24)
	_outline_label(g.kills_label)
	hidden_stats.add_child(g.kills_label)

	g.deaths_label = Label.new()
	g.deaths_label.text = "Deaths: 0"
	g.deaths_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	g.deaths_label.add_theme_font_size_override("font_size", 18)
	_outline_label(g.deaths_label)
	hidden_stats.add_child(g.deaths_label)

	g.players_label = Label.new()
	g.players_label.text = "Players: 1/%d" % g.max_players # v3.4: room max, not the 12-player cap — the HUD must agree with the lobby ("1/4" in a 4-player room, "2/8" in the default 8-player room)
	g.players_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	g.players_label.add_theme_font_size_override("font_size", 20)
	_outline_label(g.players_label)
	hidden_stats.add_child(g.players_label)

	g.weapon_icon = TextureRect.new()
	g.weapon_icon.custom_minimum_size = Vector2(48, 20)
	g.weapon_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	g.weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ammo_row.add_child(g.weapon_icon)
	g.weapon_label = Label.new()
	g.weapon_label.text = "Rifle 30"
	g.weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	g.weapon_label.add_theme_font_size_override("font_size", 18)
	_outline_label(g.weapon_label)
	ammo_row.add_child(g.weapon_label)

	var ammo_sep := Label.new()
	ammo_sep.text = "•"
	ammo_sep.add_theme_font_size_override("font_size", 18)
	_outline_label(ammo_sep)
	ammo_row.add_child(ammo_sep)

	g.grenade_label = Label.new()
	g.grenade_label.text = "Grenades: 2"
	g.grenade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	g.grenade_label.add_theme_font_size_override("font_size", 18)
	_outline_label(g.grenade_label)
	ammo_row.add_child(g.grenade_label)

	# Phase 4: FPS counter (settings toggle, off by default) —
	# v3.6: it sits under the ammo line, not inside a panel, and
	# _update_hud still turns it on/off from GameData.show_fps.
	g.fps_label = Label.new()
	g.fps_label.text = "FPS: --"
	g.fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	g.fps_label.offset_left = -212
	g.fps_label.offset_right = -12
	g.fps_label.offset_top = 112
	g.fps_label.offset_bottom = 136
	g.fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	g.fps_label.add_theme_font_size_override("font_size", 16)
	_outline_label(g.fps_label)
	g.fps_label.visible = GameData.show_fps
	g.hud.add_child(g.fps_label)

	# QA-073: dev-only network-stats panel (spec §7). Hidden by
	# default — _update_net_stats fills it 4x/s only while visible,
	# and nothing in normal play ever turns it on. Top-left under
	# the kill feed (y 208), small text, no panel, no touch target.
	g._net_stats_label = Label.new()
	g._net_stats_label.text = "NET (dev)"
	g._net_stats_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	g._net_stats_label.position = Vector2(16, 208)
	g._net_stats_label.size = Vector2(460, 120)
	g._net_stats_label.add_theme_font_size_override("font_size", 14)
	_outline_label(g._net_stats_label)
	g._net_stats_label.visible = g._net_stats_visible
	g.hud.add_child(g._net_stats_label)

	# QA-137 (v3.14): the message sits on the kit's message-box
	# panel now (a 9-slice StyleBoxTexture so the chamfered corners
	# stay intact while the panel stretches to the message width).
	# The panel is 425 px wide, 40 px tall, centred at the top;
	# the message label draws on top of it, unchanged.
	var msg_box := PanelContainer.new()
	msg_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	msg_box.offset_left = -212
	msg_box.offset_right = 212
	msg_box.offset_top = 178
	msg_box.offset_bottom = 218
	var msg_sb := StyleBoxTexture.new()
	msg_sb.texture = g.HUD_TEX_MESSAGE_BOX
	msg_sb.texture_margin_left = 24
	msg_sb.texture_margin_right = 24
	msg_sb.texture_margin_top = 24
	msg_sb.texture_margin_bottom = 24
	msg_box.add_theme_stylebox_override("panel", msg_sb)
	g.hud.add_child(msg_box)

	g.message_label = Label.new()
	g.message_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	# QA-034: offset_top was 96 — the centre-weapon label (3rd row
	# of the top bar, bottom ~y108) overlapped the 24 px message
	# ("Waiting for other players...") on every solo match start.
	# 116 clears it with room to spare; the kill feed lives at the
	# top-left, so the centred message never collides with it.
	# QA-079: the top bar grew a 4th row (the K/D line), so the
	# centre label's bottom is now ~y130 — 116 would overlap it
	# again. 140 clears the taller stack.
	# QA-114 (v3.9): the top bar grew a 5th row on Skyfall (the
	# 3 power-up slots, bottom ~y175) — 140 now overlaps the
	# slots. 185 clears the full 5-row stack.
	g.message_label.offset_top = 185
	g.message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g.message_label.add_theme_font_size_override("font_size", 24)
	_outline_label(g.message_label)
	g.hud.add_child(g.message_label)

	g.host_ip_label = Label.new()
	g.host_ip_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	# Bottom-anchored labels need BOTH offsets: offset_bottom alone
	# leaves a negative-height rect and the text draws off-screen
	# (the v3.2 HUD shot proved the hint was invisible this way).
	g.host_ip_label.offset_top = -32
	g.host_ip_label.offset_bottom = -8
	g.host_ip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g.host_ip_label.add_theme_font_size_override("font_size", 20)
	_outline_label(g.host_ip_label)
	g.host_ip_label.visible = false
	g.hud.add_child(g.host_ip_label)

	# v3.2 controls: left stick moves (push up = jump/fly), right
	# stick aims and shoots. Say so for the first seconds.
	g.hint_label = Label.new()
	g.hint_label.text = "Left stick: move  •  Push up: jump / fly  •  Right stick: aim and shoot"
	g.hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	# Both offsets (see host_ip_label above): offset_bottom alone
	# gives a negative-height rect and the text draws off-screen.
	g.hint_label.offset_top = -64
	g.hint_label.offset_bottom = -40
	g.hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g.hint_label.add_theme_font_override("font", g.FONT_BODY_MEDIUM)
	g.hint_label.add_theme_font_size_override("font_size", 18)
	g.hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	g.hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	g.hint_label.add_theme_constant_override("outline_size", 4)
	g.hud.add_child(g.hint_label)

	# Phase 4 — kill feed: top-left, under the HP/fuel bars, newest
	# on top, 4 lines max, each line fades after 5 s.
	g._kill_feed_list = VBoxContainer.new()
	g._kill_feed_list.set_anchors_preset(Control.PRESET_TOP_LEFT)
	g._kill_feed_list.position = Vector2(16, 132)
	g._kill_feed_list.add_theme_constant_override("separation", 4)
	g.hud.add_child(g._kill_feed_list)

	# Phase 4 — match countdown: huge centre number, with the match
	# goal ("First to 10 kills") under it.
	g._countdown_label = Label.new()
	g._countdown_label.set_anchors_preset(Control.PRESET_CENTER)
	g._countdown_label.position = Vector2(-80, -140)
	g._countdown_label.size = Vector2(160, 140)
	g._countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g._countdown_label.add_theme_font_size_override("font_size", 96)
	_outline_label(g._countdown_label)
	g._countdown_label.visible = false
	g.hud.add_child(g._countdown_label)
	g._countdown_sub = Label.new()
	g._countdown_sub.set_anchors_preset(Control.PRESET_CENTER)
	g._countdown_sub.position = Vector2(-300, 10)
	g._countdown_sub.size = Vector2(600, 40)
	g._countdown_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g._countdown_sub.add_theme_font_size_override("font_size", 26)
	_outline_label(g._countdown_sub)
	g._countdown_sub.visible = false
	g.hud.add_child(g._countdown_sub)

	# Phase 4 — hitmarker: a cross at screen centre, shown briefly
	# on every confirmed hit (red when the hit was lethal).
	g._hitmarker_label = Label.new()
	g._hitmarker_label.text = "✕"
	g._hitmarker_label.set_anchors_preset(Control.PRESET_CENTER)
	g._hitmarker_label.position = Vector2(-30, -30)
	g._hitmarker_label.size = Vector2(60, 60)
	g._hitmarker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g._hitmarker_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	g._hitmarker_label.add_theme_font_size_override("font_size", 44)
	g._hitmarker_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_outline_label(g._hitmarker_label)
	g._hitmarker_label.visible = false
	g.hud.add_child(g._hitmarker_label)

	# Phase 4 — spectator mode (Survival/LMS): label + NEXT button,
	# only visible while spectating a living player.
	g._spectate_label = Label.new()
	g._spectate_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	g._spectate_label.offset_top = 140
	g._spectate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g._spectate_label.add_theme_font_size_override("font_size", 24)
	_outline_label(g._spectate_label)
	g._spectate_label.visible = false
	g.hud.add_child(g._spectate_label)
	g._spectate_next_btn = Button.new()
	g._spectate_next_btn.text = "NEXT PLAYER >"
	_style_hud_button(g._spectate_next_btn)
	g._spectate_next_btn.custom_minimum_size = Vector2(200, 56)
	g._spectate_next_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	g._spectate_next_btn.position = Vector2(-100, -90)
	g._spectate_next_btn.visible = false
	g._spectate_next_btn.pressed.connect(g._on_spectate_next_pressed)
	g.hud.add_child(g._spectate_next_btn)

	# QA-114 (v3.9): vertical HUD — the height bar (Skyfall only).
	# A live tower map on the left edge: every player's height as
	# a dot, team pings as gold diamonds, level ticks, route legend.
	_build_height_bar()
	_build_scoreboard()
	_build_pause_menu()
	_build_end_screen()
	_build_error_panel()
	_build_weapon_panel()


# v2.3: dialogs are centred by a full-rect CenterContainer, not by manual
# offsets. The menu lobby had the same PRESET_CENTER pattern and it broke:
# a panel sized from a transiently wrong minimum (2877 px) was centred for
# that height and never shrank back, so every button sat off-screen. A
# CenterContainer centres from the live minimum size every frame, so the
# bug cannot recur. The wrapper ignores mouse input; the panel itself
# still receives clicks for its buttons.
func _dialog_wrap() -> CenterContainer:
	var w := CenterContainer.new()
	w.set_anchors_preset(Control.PRESET_FULL_RECT)
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.hud.add_child(w)
	return w


func _cut_accent_stylebox() -> GoStyleBoxCut:
	var sb := GoStyleBoxCut.new()
	sb.bg_color = g.UI_ACCENT
	sb.border_color = g.UI_ACCENT
	sb.border_width = 1.0
	sb.cut = 10.2
	sb.cut_corners = GoStyleBoxCut.ALL
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _panel_style() -> StyleBox:
	# v3.2 NEON ARENA: the dialog panel comes from the gohud theme
	# (cut corners, navy fill, steel border), duplicated so the
	# 0.92 alpha + content margins don't mutate the shared theme.
	var base := GoUi.theme().get_stylebox("panel", "PanelContainer")
	var s := base.duplicate() as StyleBox
	if s is StyleBoxFlat:
		var f := s as StyleBoxFlat
		var c := f.bg_color
		c.a = 0.92
		f.bg_color = c
		f.content_margin_left = 18
		f.content_margin_right = 18
		f.content_margin_top = 14
		f.content_margin_bottom = 14
	return s


# v3.2 NEON ARENA HUD/dialog button: the gohud theme drives the look
# (cut corners, navy fill, steel border, ice text); accent buttons
# (Resume, Rematch, Retry, Close) get the cyan fill + dark text.
# No manual green styleboxes any more — the old v3.1 green is gone.
func _style_hud_button(b: Button, accent: bool = false) -> void:
	for kind in ["normal", "hover", "pressed", "disabled"]:
		b.remove_theme_stylebox_override(kind)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_override("font", g.FONT_BODY_SEMIBOLD)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", g.UI_FONT)
	b.add_theme_color_override("font_hover_color", g.UI_FONT)
	b.add_theme_color_override("font_pressed_color", g.UI_ACCENT)
	if accent:
		var sb := _cut_accent_stylebox()
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_color_override("font_color", g.UI_ACCENT_DARK)
		b.add_theme_color_override("font_hover_color", g.UI_ACCENT_DARK)
		b.add_theme_color_override("font_pressed_color", g.UI_ACCENT_DARK)


func _build_height_bar() -> void:
	# QA-114 (v3.9): VERTICAL HUD — a live tower map on the left
	# edge (Skyfall only, hidden elsewhere). 360 px tall for the
	# 10800 px tower (QA-123): bar y = 360 * world_y / 10800
	# (summit at the top, base at the bottom). Dots: white = you,
	# red/blue = teams, gold diamonds = team pings. Level ticks
	# L1-L6 + the colour-coded route legend underneath.
	# Top-anchored BELOW the kill feed (the feed sits at y108 and
	# stacks up to 4 chips, bottom ~y228) — the old centre anchor
	# put the bar at y~100 at 720p, so feed chips drew over it.
	g._sf_height_bar = Control.new()
	g._sf_height_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	g._sf_height_bar.position = Vector2(12, 264)
	g._sf_height_bar.size = Vector2(100, 444)
	g._sf_height_bar.visible = false
	# QA-118 (v3.9 fix round): the bar is THINNER — the bg panel
	# was 56 px wide, now 34 px (~60%), the user asked for it.
	# Dots re-centred (34/2 - 6 = 11), level ticks moved to x40.
	g.hud.add_child(g._sf_height_bar)
	var title := Label.new()
	title.text = "HEIGHT"
	title.position = Vector2(0, -24)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.62, 0.66, 0.72))
	g._sf_height_bar.add_child(title)
	var bg := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.12, 0.75)
	sb.border_color = Color(0.35, 0.4, 0.5, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	bg.add_theme_stylebox_override("panel", sb)
	bg.position = Vector2(0, 0)
	bg.size = Vector2(34, 360)
	g._sf_height_bar.add_child(bg)
	# Level ticks: L1-L6 at their level centres (QA-123: 1800 px levels).
	for lvl in [1, 2, 3, 4, 5, 6]:
		var cy := 10800.0 - (float(lvl) - 0.5) * 1800.0 # centre y of the level
		var tl := Label.new()
		tl.text = "L%d" % lvl
		tl.position = Vector2(40, 360.0 * cy / 10800.0 - 10.0)
		tl.add_theme_font_size_override("font_size", 16)
		tl.add_theme_color_override("font_color", Color(0.62, 0.66, 0.72))
		g._sf_height_bar.add_child(tl)
	# Player dots (12 = room max) + ping dots (4).
	for i in 12:
		var dot := ColorRect.new()
		dot.size = Vector2(12, 12)
		dot.position = Vector2(11, 0)
		dot.visible = false
		g._sf_height_bar.add_child(dot)
		g._sf_height_dots.append(dot)
	for i in 4:
		var pdot := ColorRect.new()
		pdot.size = Vector2(12, 12)
		pdot.position = Vector2(11, 0)
		pdot.pivot_offset = Vector2(6, 6)
		pdot.rotation = PI / 4.0
		pdot.color = Color(1.0, 0.8, 0.2)
		pdot.visible = false
		g._sf_height_bar.add_child(pdot)
		g._sf_height_ping_dots.append(pdot)
	# Route legend: same colours as the platform strips.
	var legend := VBoxContainer.new()
	legend.position = Vector2(0, 372) # below the 360 px bar
	legend.add_theme_constant_override("separation", 4)
	g._sf_height_bar.add_child(legend)
	for ri in 3:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var sw := ColorRect.new()
		sw.color = g.SF_ROUTE_COLORS[ri]
		sw.custom_minimum_size = Vector2(14, 14)
		row.add_child(sw)
		var rl := Label.new()
		rl.text = g.SF_ROUTE_NAMES[ri]
		rl.add_theme_font_size_override("font_size", 15)
		rl.add_theme_color_override("font_color", g.SF_ROUTE_COLORS[ri])
		row.add_child(rl)
		legend.add_child(row)
	# QA-117 (v3.9 fix round): the bar is display-only — it must
	# NEVER eat touches. Its old 170 px-wide rect overlapped the
	# move stick (x90-240) and swallowed every press on the stick's
	# left/centre, so pushing LEFT on Skyfall did nothing on a real
	# phone (the sim calls _on_touch_press directly and never saw
	# it). A parent's IGNORE does NOT cascade to children — every
	# Control in the subtree (Panel, Labels, ColorRects, legend
	# containers) defaults to STOP, so set IGNORE on all of them.
	var _hb_stack: Array = [g._sf_height_bar]
	while not _hb_stack.is_empty():
		var _hb_n: Node = _hb_stack.pop_back()
		if _hb_n is Control:
			(_hb_n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		for _hb_ch in _hb_n.get_children():
			_hb_stack.append(_hb_ch)


func _build_scoreboard() -> void:
	# QA-113 (v3.9): wider panel, bigger title, breathing room —
	# the old 420 px panel with 30 px title cramped 10-player rows.
	g.scoreboard_panel = PanelContainer.new()
	g.scoreboard_panel.theme = GoUi.theme()
	g.scoreboard_panel.custom_minimum_size = Vector2(560, 0)
	g.scoreboard_panel.add_theme_stylebox_override("panel", _panel_style())
	g.scoreboard_panel.visible = false
	_dialog_wrap().add_child(g.scoreboard_panel)
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
	_style_hud_button(close_btn)
	close_btn.custom_minimum_size = Vector2(0, 56)
	close_btn.pressed.connect(func() -> void: g.scoreboard_panel.visible = false)
	box.add_child(close_btn)


func _build_pause_menu() -> void:
	# QA-113 (v3.9): same clean, spacious layout as the scoreboard —
	# wider panel, section labels, slider value labels, match info
	# line, 56 px buttons. Layout only, no logic changes.
	g.pause_panel = PanelContainer.new()
	g.pause_panel.theme = GoUi.theme()
	g.pause_panel.custom_minimum_size = Vector2(520, 0)
	g.pause_panel.add_theme_stylebox_override("panel", _panel_style())
	g.pause_panel.visible = false
	g.pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_dialog_wrap().add_child(g.pause_panel)
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
	_style_hud_button(resume_btn, true)
	resume_btn.custom_minimum_size = Vector2(0, 56)
	resume_btn.pressed.connect(g._toggle_pause)
	box.add_child(resume_btn)
	# Phase 4: weapon info — damage / fire rate / magazine / reload
	# per weapon, straight from weapons.gd (read-only display).
	var weapons_btn := Button.new()
	weapons_btn.text = "Weapons"
	_style_hud_button(weapons_btn)
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
	_style_hud_button(leave_btn)
	leave_btn.custom_minimum_size = Vector2(0, 56)
	leave_btn.pressed.connect(g._on_leave_pressed)
	box.add_child(leave_btn)


func _build_end_screen() -> void:
	# QA-113 (v3.9): wider panel, bigger title, more breathing room.
	g.end_panel = PanelContainer.new()
	g.end_panel.theme = GoUi.theme()
	g.end_panel.custom_minimum_size = Vector2(560, 0)
	g.end_panel.add_theme_stylebox_override("panel", _panel_style())
	g.end_panel.visible = false
	_dialog_wrap().add_child(g.end_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	g.end_panel.add_child(box)
	g._end_box = box
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
	_style_hud_button(g.end_rematch_btn, true)
	g.end_rematch_btn.custom_minimum_size = Vector2(0, 56)
	g.end_rematch_btn.pressed.connect(g._on_rematch_pressed)
	box.add_child(g.end_rematch_btn)
	var back_btn := Button.new()
	# QA-060: this used to say "Back to Lobby" but it goes to the
	# main menu (_on_leave_pressed changes scene to main.tscn).
	back_btn.text = "Back to Menu"
	_style_hud_button(back_btn)
	back_btn.custom_minimum_size = Vector2(0, 56)
	back_btn.pressed.connect(g._on_leave_pressed)
	box.add_child(back_btn)


func _build_weapon_panel() -> void:
	g._weapon_panel = PanelContainer.new()
	g._weapon_panel.theme = GoUi.theme()
	g._weapon_panel.custom_minimum_size = Vector2(520, 0)
	g._weapon_panel.add_theme_stylebox_override("panel", _panel_style())
	g._weapon_panel.visible = false
	g._weapon_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_dialog_wrap().add_child(g._weapon_panel)
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
	_style_hud_button(close_btn, true)
	close_btn.custom_minimum_size = Vector2(0, 56)
	close_btn.pressed.connect(func() -> void: _show_weapon_panel(false))
	box.add_child(close_btn)


func _show_weapon_panel(show: bool) -> void:
	g._weapon_panel.visible = show
	# The pause menu stays behind it; closing returns to pause.


func _build_error_panel() -> void:
	g.error_panel = PanelContainer.new()
	g.error_panel.theme = GoUi.theme()
	g.error_panel.custom_minimum_size = Vector2(520, 0)
	g.error_panel.add_theme_stylebox_override("panel", _panel_style())
	g.error_panel.visible = false
	_dialog_wrap().add_child(g.error_panel)
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
	_style_hud_button(retry_btn, true)
	retry_btn.custom_minimum_size = Vector2(0, 56)
	retry_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	retry_btn.pressed.connect(g._on_retry_pressed)
	row.add_child(retry_btn)
	var back_btn := Button.new()
	back_btn.text = "Back"
	_style_hud_button(back_btn)
	back_btn.custom_minimum_size = Vector2(0, 56)
	back_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_btn.pressed.connect(g._on_leave_pressed)
	row.add_child(back_btn)


func _build_touch_controls() -> void:
	# v3.2 (CONTROLS_CHANGE.md): fixed layout, no left-handed mirror
	# any more — the FIRE button it mirrored with is gone. Move stick
	# bottom-left, aim stick bottom-right, RELOAD / GRENADE / WEAPON
	# column above the aim stick on the right.
	# v3.3 QA-052: sticks moved inward from the bottom corners —
	# move stick up/right, aim stick up/left, 50 px each way at
	# 1280x720 (anchor offsets, so it scales with the stretch).
	# Was move (40, -190), aim (-290, -190). Aim stick still clears
	# the RELOAD/GRENADE/WEAPON column (x 810-920) by 20 px.
	g.move_stick = g.JOYSTICK_SCRIPT.new()
	g.move_stick.name = "MoveStick"
	g.move_stick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	g.move_stick.position = Vector2(90, -240)
	g.move_stick.size = Vector2(150, 150)
	g.hud.add_child(g.move_stick)

	# v3.2: the aim stick is back at the bottom-right (it moved left in
	# v2.4 to make room for the FIRE button) — and it is also the fire
	# control now: pushing it aims and shoots (Mini Militia style).
	# is_aim draws the cyan ring + crosshair cue (joystick.gd).
	g.aim_stick = g.JOYSTICK_SCRIPT.new()
	g.aim_stick.name = "AimStick"
	g.aim_stick.is_aim = true
	g.aim_stick.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	g.aim_stick.position = Vector2(-340, -240)
	g.aim_stick.size = Vector2(150, 150)
	g.hud.add_child(g.aim_stick)

	# v2.2: no JUMP button. Pushing the left stick up jumps; holding it up
	# while airborne is the jetpack (see player.gd). The hint label in the
	# HUD and the lobby explain the new control.
	# QA-070 (v3.6): SIMPLE buttons, not fancy (user, 2026-11-19
	# ~18:13 — extends the v3.5 "just have plain buttons" rule from
	# grenade/reload to the weapon-switch button too). Plain flat
	# buttons with a clear text label, no gohud styling, no rings,
	# no badges, no icons, no effects, no decorations. Same column,
	# same positions, same 72 px touch targets, same handlers —
	# only the look changed. Throw behaviour unchanged.
	# QA-137 (v3.14): the button wears the user's HUD kit art now
	# (the kit's flat square grenade button). Icon-only - the
	# grenade icon IS the label; the count lives in the top-right
	# ammo line (grenades_label), so the button text is empty.
	# Plain and simple per the standing rule: 72 px, no rings,
	# no badges, no progress effects. Same handler, same position.
	g.grenade_button = Button.new()
	g.grenade_button.text = ""
	_style_simple_button(g.grenade_button)
	g.grenade_button.icon = g.HUD_TEX_BTN_GRENADE
	g.grenade_button.expand_icon = true
	g.grenade_button.custom_minimum_size = Vector2(72, 72)
	g.grenade_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	g.grenade_button.position = Vector2(-451, -260)
	g.grenade_button.pressed.connect(g._on_grenade_pressed)
	g.hud.add_child(g.grenade_button)

	g.switch_button = Button.new()
	# QA-137: kit weapon-switch button (the kit's SMG icon).
	# Icon-only like grenade; the current weapon already shows
	# (icon + name) in the top-right HUD panel. Behaviour unchanged.
	g.switch_button.text = ""
	_style_simple_button(g.switch_button)
	g.switch_button.icon = g.HUD_TEX_BTN_WEAPON_SWITCH
	g.switch_button.expand_icon = true
	g.switch_button.custom_minimum_size = Vector2(72, 72)
	g.switch_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	g.switch_button.position = Vector2(-451, -180)
	g.switch_button.pressed.connect(g._on_switch_pressed)
	g.hud.add_child(g.switch_button)

	# QA-137: kit reload button (the kit's circular-arrows icon).
	# Icon-only; ammo count stays in the weapon label. Behaviour unchanged.
	g.reload_button = Button.new()
	g.reload_button.text = ""
	_style_simple_button(g.reload_button)
	g.reload_button.icon = g.HUD_TEX_BTN_RELOAD
	g.reload_button.expand_icon = true
	g.reload_button.custom_minimum_size = Vector2(72, 72)
	g.reload_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	g.reload_button.position = Vector2(-451, -340)
	g.reload_button.pressed.connect(g._on_reload_pressed)
	g.hud.add_child(g.reload_button)

	# QA-105 (v3.8): SCOPE button — plain and simple like the other
	# three, same column, directly above RELOAD. Only visible with
	# the sniper or rifle equipped (see _update_scope_button).
	# It toggles the scope zoom on the local player; it never
	# touches the right stick, so aim + fire (QA-049) is
	# unaffected. 72 px touch target like the others.
	# QA-137: kit scope button (the kit's crosshair icon), icon-only.
	g.scope_button = Button.new()
	g.scope_button.text = ""
	_style_simple_button(g.scope_button)
	g.scope_button.icon = g.HUD_TEX_BTN_SCOPE
	g.scope_button.expand_icon = true
	g.scope_button.custom_minimum_size = Vector2(72, 72)
	g.scope_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	g.scope_button.position = Vector2(-451, -420)
	g.scope_button.pressed.connect(g._on_scope_pressed)
	g.hud.add_child(g.scope_button)

	# QA-114 (v3.9): PING button — plain and simple like the other
	# four, same column, directly above SCOPE. Pings the local
	# player's position for their TEAM (a gold diamond marker in
	# the world + a dot on the height bar + a feed line), 3 s
	# cooldown so it cannot be spammed. Skyfall only — hidden on
	# other maps (see _update_scope_button's neighbour, updated in
	# _update_hud).
	g.ping_button = Button.new()
	g.ping_button.text = "PING"
	_style_simple_button(g.ping_button)
	g.ping_button.custom_minimum_size = Vector2(72, 72)
	g.ping_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	g.ping_button.position = Vector2(-451, -500)
	g.ping_button.pressed.connect(g._on_ping_pressed)
	g.hud.add_child(g.ping_button)

	# QA-067 (v3.6): the buttons are gohud GoIconButtons now —
	# icon-only (chart = scoreboard, pause = pause), 56x56 px each,
	# sitting in the slim top-right pill from _build_hud. The old
	# text buttons ("SCORE" 96 px + "II") needed the big QA-057
	# panel around them; the icons are the whole point of the
	# compact corner. touch_peers links the two side by side, so
	# one's widened hit area never swallows the other's tap
	# (GoIconButton doc). keyboard_focus is OFF: a clicked HUD
	# button must not keep keyboard focus, or Space/Enter would
	# re-press it mid-match instead of reaching the game.
	# Handlers unchanged (_on_score_pressed / _toggle_pause).
	g.score_button = GoIconButton.new()
	(g.score_button as GoIconButton).visual_size = 56
	(g.score_button as GoIconButton).icon_name = GoIconSet.CHART
	(g.score_button as GoIconButton).keyboard_focus = false
	g.score_button.focus_mode = Control.FOCUS_NONE
	g.score_button.tooltip_text = "Scoreboard"
	g.score_button.pressed.connect(g._on_score_pressed)
	g._topright_btn_row.add_child(g.score_button)

	g.pause_button = GoIconButton.new()
	(g.pause_button as GoIconButton).visual_size = 56
	# QA-137: the pause button is the kit's pause art (the GoIconButton
	# `art` property makes the picture the whole button and darkens
	# it while pressed). The kit's pause icon replaces the gohud glyph.
	(g.pause_button as GoIconButton).art = g.HUD_TEX_BTN_PAUSE
	(g.pause_button as GoIconButton).keyboard_focus = false
	g.pause_button.focus_mode = Control.FOCUS_NONE
	g.pause_button.tooltip_text = "Pause"
	g.pause_button.pressed.connect(g._toggle_pause)
	g._topright_btn_row.add_child(g.pause_button)
	(g.score_button as GoIconButton).touch_peers = [g.pause_button]
	(g.pause_button as GoIconButton).touch_peers = [g.score_button]


# QA-070 (v3.6): SIMPLE button style — plain flat buttons, not
# fancy. One flat dark fill, no border, no accent colour, no
# hover glow, no pressed effect beyond a slightly lighter fill,
# no focus ring. The label (set at creation) is the whole button:
# clear text, readable at a glance. Replaces the v3.5 round style
# (_style_round_button, deleted with its code-drawn icons) at the
# user's 2026-11-19 ~18:13 request.
func _style_simple_button(b: Button) -> void:
	for kind in ["normal", "hover", "pressed", "disabled"]:
		b.remove_theme_stylebox_override(kind)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_override("font", g.FONT_BODY_SEMIBOLD)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", g.UI_FONT)
	b.add_theme_color_override("font_hover_color", g.UI_FONT)
	b.add_theme_color_override("font_pressed_color", g.UI_FONT)
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.6, 0.68))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.09, 0.12, 0.18)
	normal.set_corner_radius_all(6)
	b.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.13, 0.17, 0.24)
	hover.set_corner_radius_all(6)
	b.add_theme_stylebox_override("hover", hover)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0.16, 0.21, 0.29)
	pressed.set_corner_radius_all(6)
	b.add_theme_stylebox_override("pressed", pressed)
	var disabled := StyleBoxFlat.new()
	disabled.bg_color = Color(0.09, 0.12, 0.18, 0.55)
	disabled.set_corner_radius_all(6)
	b.add_theme_stylebox_override("disabled", disabled)

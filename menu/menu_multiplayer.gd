class_name MenuMultiplayer
extends RefCounted


# QA-140 (v3.15): extracted from main.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `m` (dependency injection).


var m # the owner (main.gd)


func _init(owner) -> void:
	m = owner


func _build_multiplayer() -> void:
	m._mp_panel = m.menu_ui._panel()
	var box = m.menu_ui._vbox(m._mp_panel, 12)
	box.add_child(m.menu_ui._title_label("LOCAL MULTIPLAYER", 36))
	var hint = m.menu_ui._body_label("All phones must be on the same Wi-Fi network (or one phone's hotspot).", 18)
	hint.add_theme_color_override("font_color", m.UI_FONT_MUTED)
	box.add_child(hint)
	# v2.4: show our own LAN IP up front, so the host can read it out
	# and a joiner can type it even if discovery fails.
	m._my_ip_label = Label.new()
	m._my_ip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m._my_ip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m._my_ip_label.add_theme_font_size_override("font_size", 20)
	box.add_child(m._my_ip_label)
	# v3.2 QA-047: in-app permission explanation (Android / Play).
	# LAN play uses plain Wi-Fi sockets only — no accounts, no
	# internet, no location. The app needs only Internet + network
	# state, both granted at install with no pop-up.
	var perm_note := Label.new()
	perm_note.text = "Permissions: Internet + network state only, so phones on this Wi-Fi can find each other. No location, no accounts, no data leaves your phones."
	perm_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	perm_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	perm_note.add_theme_font_override("font", m.FONT_BODY)
	perm_note.add_theme_font_size_override("font_size", 16)
	perm_note.add_theme_color_override("font_color", m.UI_FONT_MUTED)
	box.add_child(perm_note)
	# v3.2: the whole panel scrolls (see note below at the room list).
	var scroll := ScrollContainer.new()
	m._mp_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	box = inner

	# --- Create a room ---
	# v3.6 QA-068 — FULL REDESIGN. v3.5 was a flat stack of bare
	# inputs (placeholder-only room name, a tiny CheckButton for
	# private, the password beside it with no label). Now the
	# whole create form lives on one designed gohud card with
	# real labels above every field (GoField: label + input +
	# hint), a big segmented max-players row, a proper GoSwitch
	# for Private, and a 72 px hero CREATE ROOM button. Every
	# control keeps its exact v3.5 behaviour (same nodes, same
	# handlers, same create flow); only the presentation
	# changed. The card itself is mouse-transparent (see the
	# v3.5 room-panel note): a drag starting on the card must
	# reach _mp_scroll.
	var create_card := PanelContainer.new()
	create_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var create_sb := GoUi.theme().get_stylebox("panel", "PanelContainer")
	if create_sb != null:
		var create_dup := create_sb.duplicate()
		if create_dup is GoStyleBoxCut:
			(create_dup as GoStyleBoxCut).bg_color = Color(0.09, 0.14, 0.22, 0.96)
			(create_dup as GoStyleBoxCut).content_margin_left = 24
			(create_dup as GoStyleBoxCut).content_margin_right = 24
			(create_dup as GoStyleBoxCut).content_margin_top = 16
			(create_dup as GoStyleBoxCut).content_margin_bottom = 16
		create_card.add_theme_stylebox_override("panel", create_dup)
	box.add_child(create_card)
	var create_box := VBoxContainer.new()
	create_box.add_theme_constant_override("separation", 14)
	create_card.add_child(create_box)
	var create_head := HBoxContainer.new()
	create_head.add_theme_constant_override("separation", 10)
	create_box.add_child(create_head)
	var create_title := Label.new()
	create_title.text = "CREATE A ROOM"
	create_title.add_theme_font_override("font", m.FONT_TITLE)
	create_title.add_theme_font_size_override("font_size", 26)
	create_title.add_theme_color_override("font_color", m.UI_FONT)
	create_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_head.add_child(create_title)
	var host_badge = GoBadge.make(0, "YOU HOST", false, m.UI_ACCENT)
	host_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	create_head.add_child(host_badge)
	var create_sub := Label.new()
	create_sub.text = "Start a room on this Wi-Fi — friends on the same network see it in their room list."
	create_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	create_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	create_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	create_sub.add_theme_font_override("font", m.FONT_BODY)
	create_sub.add_theme_font_size_override("font_size", 18)
	create_sub.add_theme_color_override("font_color", m.UI_FONT_MUTED)
	create_box.add_child(create_sub)
	m._room_name_input = LineEdit.new()
	m._room_name_input.placeholder_text = "Room name, e.g. Tharun's Room"
	m._room_name_input.text = GameData.room_name
	m._room_name_input.custom_minimum_size = Vector2(0, 56)
	m._room_name_input.add_theme_font_size_override("font_size", 22)
	var name_field = GoField.make("Room name", m._room_name_input, "Shown to friends on this Wi-Fi")
	name_field.label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_field.hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	create_box.add_child(name_field)
	var max_cap := Label.new()
	max_cap.text = "Max players — how many phones can join"
	max_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	max_cap.add_theme_font_override("font", m.FONT_BODY_SEMIBOLD)
	max_cap.add_theme_font_size_override("font_size", 20)
	max_cap.add_theme_color_override("font_color", m.UI_FONT)
	create_box.add_child(max_cap)
	var max_row := HBoxContainer.new()
	max_row.add_theme_constant_override("separation", 8)
	create_box.add_child(max_row)
	for n in [2, 4, 6, 8, 10, 12]:
		var b := Button.new()
		b.text = str(n)
		b.custom_minimum_size = Vector2(64, 56)
		m.menu_ui._style_button(b, 22, 56)
		b.pressed.connect(m._on_max_pressed.bind(n))
		max_row.add_child(b)
		m._max_buttons.append(b)
		m.menu_ui._connect_scroll_button(b, m._mp_scroll)
	# QA-098 (v3.7): the create form now picks the mode up front
	# (was lobby-only). Same value the lobby uses (GameData.game_mode)
	# — the room card, the lobby display and the match start all read
	# it from there, so nothing else changes. Two rows of mode buttons
	# (3 + 2) like the lobby. The map pick that was added here in
	# v3.7 was removed in v3.8 (QA-102): the host picks the map in
	# the lobby instead.
	var create_mode_cap := Label.new()
	create_mode_cap.text = "Game mode"
	create_mode_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	create_mode_cap.add_theme_font_override("font", m.FONT_BODY_SEMIBOLD)
	create_mode_cap.add_theme_font_size_override("font_size", 20)
	create_mode_cap.add_theme_color_override("font_color", m.UI_FONT)
	create_box.add_child(create_mode_cap)
	var create_mode_row := HBoxContainer.new()
	create_mode_row.add_theme_constant_override("separation", 8)
	create_box.add_child(create_mode_row)
	var create_mode_row2 := HBoxContainer.new()
	create_mode_row2.add_theme_constant_override("separation", 8)
	create_box.add_child(create_mode_row2)
	for i in GameData.MODE_NAMES.size():
		var mb := Button.new()
		mb.text = GameData.MODE_NAMES[i]
		mb.custom_minimum_size = Vector2(0, 56)
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		m.menu_ui._style_button(mb, 20, 56)
		mb.pressed.connect(m._on_create_mode_pressed.bind(i))
		(create_mode_row if i < 3 else create_mode_row2).add_child(mb)
		m._create_mode_buttons.append(mb)
		m.menu_ui._connect_scroll_button(mb, m._mp_scroll)
	# QA-102 (v3.8): the map pick was REMOVED from the create form
	# (user: "remove map selection while creating room") — the host
	# picks the map in the lobby instead. The mode pick stays here.
	# GameData.map_id keeps its default (0 = Ironfall) until the
	# host changes it on a lobby map card; the room card, lobby
	# display and match start all read it from there.
	m._refresh_create_mode_buttons()
	# The password input is created BEFORE the Private switch:
	# flipping the switch calls _on_private_toggled, which greys
	# the password field out when Private is off — and the field
	# must already exist when that runs at build time.
	m._room_password_input = LineEdit.new()
	m._room_password_input.placeholder_text = "Room password (if private)"
	m._room_password_input.text = GameData.room_password
	m._room_password_input.secret = true # v3.6: a password field masks what you type (was plain text)
	m._room_password_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m._room_password_input.custom_minimum_size = Vector2(0, 56)
	m._room_password_input.add_theme_font_size_override("font_size", 20)
	var priv_row := HBoxContainer.new()
	priv_row.add_theme_constant_override("separation", 10)
	create_box.add_child(priv_row)
	var priv_lbl := Label.new()
	priv_lbl.text = "Private room"
	priv_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	priv_lbl.add_theme_font_override("font", m.FONT_BODY_SEMIBOLD)
	priv_lbl.add_theme_font_size_override("font_size", 22)
	priv_lbl.add_theme_color_override("font_color", m.UI_FONT)
	priv_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	priv_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	priv_row.add_child(priv_lbl)
	m._private_check = GoSwitch.new()
	m._private_check.custom_minimum_size = Vector2(72, 56)
	m._private_check.button_pressed = GameData.room_private
	m._private_check.toggled.connect(m._on_private_toggled)
	priv_row.add_child(m._private_check)
	var pw_field = GoField.make("Room password", m._room_password_input, "Only friends with this password can join")
	pw_field.label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pw_field.hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	create_box.add_child(pw_field)
	var create_btn := Button.new()
	create_btn.text = "CREATE ROOM"
	create_btn.custom_minimum_size = Vector2(0, 72)
	m.menu_ui._style_button(create_btn, 26, 72, true)
	create_btn.pressed.connect(m._on_create_room_pressed)
	create_box.add_child(create_btn)
	m.menu_ui._connect_scroll_button(create_btn, m._mp_scroll)
	m._on_private_toggled(GameData.room_private) # grey the password field out when Private starts off

	# --- Join area: TWO COLUMNS (QA-103, v3.8) ---
	# User: "have the rooms on the right like available room and
	# quick join also on the right like bottom of the right when the
	# rooms available". Left column = join by IP / room code.
	# Right column = available rooms list, with QUICK LAN MATCH at
	# the bottom of the right column, below the rooms. REFRESH moves
	# into the right column header (it refreshes the room list).
	# Both columns share the width 50/50; the whole page still
	# scrolls in _mp_scroll, so nothing is cut off.
	var join_columns := HBoxContainer.new()
	join_columns.add_theme_constant_override("separation", 16)
	join_columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(join_columns)
	var left_col = m.menu_ui._vbox(join_columns, 12)
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right_col = m.menu_ui._vbox(join_columns, 12)
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# --- Left column: join a room ---
	left_col.add_child(m.menu_ui._section_label("Join a room:"))
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 10)
	left_col.add_child(join_row)
	m._ip_input = LineEdit.new()
	m._ip_input.placeholder_text = "Host IP, e.g. 192.168.1.5"
	m._ip_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m._ip_input.custom_minimum_size = Vector2(0, 60)
	m._ip_input.add_theme_font_size_override("font_size", 22)
	# v3.6 QA-068: the join IP gets a real label too (GoField),
	# like the create form above — same node, same JOIN flow.
	var ip_field = GoField.make("Host IP", m._ip_input, "Or tap a room on the right — same Wi-Fi only")
	ip_field.label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ip_field.hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ip_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(ip_field)
	var join_btn := Button.new()
	join_btn.text = "JOIN"
	join_btn.custom_minimum_size = Vector2(120, 60)
	join_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	m.menu_ui._style_button(join_btn, 26, 60, true)
	join_btn.pressed.connect(m._on_join_pressed)
	join_row.add_child(join_btn)
	m.menu_ui._connect_scroll_button(join_btn, m._mp_scroll)
	m._join_password_input = LineEdit.new()
	m._join_password_input.placeholder_text = "Only for private rooms"
	m._join_password_input.secret = true # v3.6 QA-068: mask the password (was plain text)
	m._join_password_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m._join_password_input.custom_minimum_size = Vector2(0, 56)
	m._join_password_input.add_theme_font_size_override("font_size", 20)
	var join_pw_field = GoField.make("Password", m._join_password_input, "Only for private rooms")
	join_pw_field.label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	join_pw_field.hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_col.add_child(join_pw_field)
	# QA-078: join by room code — the host reads the code out
	# (it is on the lobby's host-IP chip) and a friend types it
	# here instead of the IP. LAN-local only: the code is looked
	# up in the discovered-room list on this Wi-Fi, no server.
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 10)
	left_col.add_child(code_row)
	m._room_code_input = LineEdit.new()
	m._room_code_input.placeholder_text = "Room code, e.g. FRAG-1234"
	m._room_code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m._room_code_input.custom_minimum_size = Vector2(0, 60)
	m._room_code_input.add_theme_font_size_override("font_size", 22)
	var code_field = GoField.make("Room code", m._room_code_input, "Ask the host for the code — same Wi-Fi only")
	code_field.label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	code_field.hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	code_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(code_field)
	var code_btn := Button.new()
	code_btn.text = "JOIN CODE"
	code_btn.custom_minimum_size = Vector2(160, 60)
	code_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	m.menu_ui._style_button(code_btn, 22, 60, true)
	code_btn.pressed.connect(m._on_join_code_pressed)
	code_row.add_child(code_btn)
	m.menu_ui._connect_scroll_button(code_btn, m._mp_scroll)

	# --- Right column: available rooms + Quick Join at the bottom ---
	var rooms_head := HBoxContainer.new()
	rooms_head.add_theme_constant_override("separation", 10)
	right_col.add_child(rooms_head)
	var rooms_cap = m.menu_ui._section_label("Games found on this Wi-Fi:")
	rooms_cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rooms_cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rooms_head.add_child(rooms_cap)
	var refresh_btn := Button.new()
	refresh_btn.text = "REFRESH"
	refresh_btn.custom_minimum_size = Vector2(140, 56)
	refresh_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	m.menu_ui._style_button(refresh_btn, 20, 56)
	refresh_btn.pressed.connect(m._on_refresh_pressed)
	rooms_head.add_child(refresh_btn)
	m.menu_ui._connect_scroll_button(refresh_btn, m._mp_scroll)
	var rooms_hint = m.menu_ui._body_label("Tap a room to join it. If nothing appears, type the host IP on the left.", 18)
	rooms_hint.add_theme_color_override("font_color", m.UI_FONT_MUTED)
	right_col.add_child(rooms_hint)
	# Room list: plain VBox inside the outer scroll (the v3.1 inner
	# ScrollContainer got zero height — see the note at the top of
	# this function). Room buttons forward drags to _mp_scroll.
	m._host_buttons = VBoxContainer.new()
	m._host_buttons.add_theme_constant_override("separation", 8)
	m._host_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.add_child(m._host_buttons)
	# QUICK LAN MATCH sits at the bottom of the right column,
	# below the rooms list — reachable without scrolling when the
	# list is short, one scroll away when it is long.
	var quick_btn := Button.new()
	quick_btn.text = "QUICK LAN MATCH"
	quick_btn.custom_minimum_size = Vector2(0, 60)
	quick_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.menu_ui._style_button(quick_btn, 22, 60, true)
	quick_btn.pressed.connect(m._on_quick_match_pressed)
	right_col.add_child(quick_btn)
	m.menu_ui._connect_scroll_button(quick_btn, m._mp_scroll)
	m._status = Label.new()
	m._status.text = ""
	m._status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m._status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m._status.add_theme_font_size_override("font_size", 20)
	box.add_child(m._status)
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(0, 56)
	m.menu_ui._style_button(back_btn, 22, 56)
	back_btn.pressed.connect(func() -> void: m.menu_ui._click(); m.menu_ui._show_only(m._menu_panel))
	box.add_child(back_btn)
	m.menu_ui._connect_scroll_button(back_btn, m._mp_scroll)
	m._refresh_max_buttons()
	m._refresh_create_mode_buttons()


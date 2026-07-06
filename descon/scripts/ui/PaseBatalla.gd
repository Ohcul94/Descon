extends Control

var is_open = false
var battle_pass_data = null
var bp_config = null
var modal_active = false
var active_modales = []
var scroll_offset = 0

func _ready():
	add_to_group("battlepass_ui")
	add_to_group("hud")
	mouse_filter = Control.MOUSE_FILTER_STOP

	if NetworkManager:
		NetworkManager.battle_pass_state.connect(_on_battle_pass_state)
		if NetworkManager.is_logged_in:
			_request_state()
		else:
			NetworkManager.login_success.connect(func(_d): _request_state())

	visible = false

func _request_state():
	if NetworkManager:
		NetworkManager.send_event("getBattlePassState", {})

func _on_battle_pass_state(data: Variant):
	if typeof(data) == TYPE_DICTIONARY:
		battle_pass_data = data.get("battlePass", {})
		var c = data.get("config")
		bp_config = c if typeof(c) == TYPE_DICTIONARY else {}
		if is_open:
			queue_redraw()

func toggle():
	print("[BATTLEPASS] toggle() called, current is_open=", is_open)
	is_open = !is_open
	visible = is_open

	if is_open:
		_request_state()
		if get_parent():
			get_parent().move_child(self, get_parent().get_child_count() - 1)
			z_index = 100
	else:
		z_index = 0
		for m in active_modales:
			if is_instance_valid(m):
				m.queue_free()
		active_modales.clear()
		modal_active = false

	queue_redraw()

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		while active_modales.size() > 0:
			var m = active_modales.pop_back()
			if is_instance_valid(m):
				m.queue_free()
				modal_active = active_modales.size() > 0
				get_viewport().set_input_as_handled()
				return

		if is_open:
			toggle()
			get_viewport().set_input_as_handled()
			return

	var focusNode = get_viewport().gui_get_focus_owner()
	if focusNode is LineEdit or focusNode is TextEdit:
		return

	if not NetworkManager.is_logged_in:
		return

	if event.is_action_pressed("ui_battlepass"):
		toggle()
		get_viewport().set_input_as_handled()

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP and is_open:
		scroll_offset = max(scroll_offset - 30, 0)
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and is_open:
		scroll_offset += 30
		queue_redraw()

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and is_open:
		var screen_size = get_viewport_rect().size
		var r_size = Vector2(screen_size.x * 0.85, screen_size.y * 0.85)
		var r_pos = (screen_size - r_size) / 2
		var x_rect = Rect2(r_pos.x + r_size.x - 60, r_pos.y, 60, 40)
		if x_rect.has_point(event.position):
			toggle()
			get_viewport().set_input_as_handled()
			return

func _draw():
	if not visible:
		print("[BATTLEPASS] _draw() skipped: not visible")
		return
	print("[BATTLEPASS] _draw() called, visible=", visible, " battle_pass_data=", battle_pass_data != null, " bp_config=", bp_config != null)

	var screen_size = get_viewport_rect().size
	var r_size = Vector2(screen_size.x * 0.85, screen_size.y * 0.85)
	var r_pos = (screen_size - r_size) / 2.0
	var f = get_theme_font("font")
	if not f:
		f = get_theme_default_font()

	draw_rect(Rect2(r_pos, r_size), Color(0.02, 0.02, 0.05, 0.98))
	draw_rect(Rect2(r_pos, Vector2(r_size.x, 35)), Color(0, 0.08, 0.12, 1.0))
	draw_rect(Rect2(r_pos, r_size), Color(0, 0.8, 1, 0.5), false, 1.5)

	if not battle_pass_data or not bp_config:
		var msg = "Cargando..." if not battle_pass_data else "Cargando configuracion..."
		draw_string(f, r_pos + Vector2(20, 60), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.5, 0.5))
		return

	var season = bp_config.get("seasonName", "Pase de Batalla")
	draw_string(f, r_pos + Vector2(20, 22), season, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 1, 1))

	var has_vip = battle_pass_data.get("isVip", false)
	var vip_text = "VIP" if has_vip else "FREE"
	draw_string(f, r_pos + Vector2(r_size.x - 150, 22), vip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.8, 0) if has_vip else Color(0.5, 0.5, 0.5))

	draw_rect(Rect2(r_pos.x + r_size.x - 50, r_pos.y + 6, 40, 24), Color(0, 1, 1), false, 1.2)
	draw_string(f, r_pos + Vector2(r_size.x - 36, 22), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0, 1, 1))

	var level = battle_pass_data.get("level", 1)
	var exp_val = battle_pass_data.get("exp", 0)
	var levels_config = bp_config.get("levels", []) if bp_config else []
	var current_level_config = null
	for l in levels_config:
		if l.get("level") == level:
			current_level_config = l
			break
	var exp_required = current_level_config.get("expRequired", 2000) if current_level_config else 2000

	var header_y = r_pos.y + 50
	draw_string(f, r_pos + Vector2(25, header_y), "NIVEL " + str(level), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0, 1, 1))
	draw_string(f, r_pos + Vector2(150, header_y), "EXP: " + str(exp_val) + " / " + str(exp_required), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 1, 0.5))

	var bar_width = r_size.x - 50
	var bar_x = r_pos.x + 25
	var bar_y = r_pos.y + 60
	var bar_h = 14
	var progress = float(exp_val) / float(exp_required) if exp_required > 0 else 0.0
	draw_rect(Rect2(bar_x, bar_y, bar_width, bar_h), Color(0.1, 0.1, 0.2, 1))
	draw_rect(Rect2(bar_x, bar_y, bar_width * progress, bar_h), Color(0, 0.8, 1, 0.8))

	var levels_start_y = bar_y + 30 - scroll_offset
	var card_w = r_size.x - 50
	var card_h = 110
	var card_gap = 10
	var half_w = card_w / 2 - 5

	for i in range(levels_config.size()):
		var lvl = levels_config[i]
		var lvl_num = lvl.get("level", i + 1)
		var lvl_exp = lvl.get("expRequired", 2000)
		var free_reward = lvl.get("freeReward", null)
		var vip_reward = lvl.get("vipReward", null)
		var y_pos = levels_start_y + i * (card_h + card_gap)

		if y_pos + card_h < r_pos.y or y_pos > r_pos.y + r_size.y:
			continue

		var is_current = lvl_num == level
		var is_locked = lvl_num > level
		var claimed_free = battle_pass_data.get("claimedFree", []).has(lvl_num)
		var claimed_vip = battle_pass_data.get("claimedVip", []).has(lvl_num)

		var card_color = Color(0.05, 0.05, 0.1, 0.9)
		if is_current:
			card_color = Color(0, 0.15, 0.2, 0.9)
		elif is_locked:
			card_color = Color(0.03, 0.03, 0.05, 0.7)

		draw_rect(Rect2(r_pos.x + 25, y_pos, card_w, card_h), card_color)
		draw_rect(Rect2(r_pos.x + 25, y_pos, card_w, card_h), Color(0, 0.8, 1, 0.3), false, 1)

		var lx = r_pos.x + 30
		var rx = r_pos.x + 30 + half_w + 10
		var sep_x = r_pos.x + 25 + half_w + 5

		draw_string(f, Vector2(lx, y_pos + 18), "NIVEL " + str(lvl_num), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0, 1, 1) if not is_locked else Color(0.4, 0.4, 0.4))
		draw_string(f, Vector2(lx + 80, y_pos + 18), "EXP " + str(lvl_exp), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.5, 0.5))
		if is_locked and not is_current:
			draw_string(f, Vector2(r_pos.x + 25 + card_w - 10, y_pos + 18), "BLOQ", HORIZONTAL_ALIGNMENT_RIGHT, -1, 9, Color(0.5, 0.5, 0.5))

		draw_rect(Rect2(sep_x, y_pos + 22, 1, card_h - 24), Color(0.2, 0.2, 0.3, 0.6))

		draw_string(f, Vector2(lx, y_pos + 40), "GRATIS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.3, 1, 0.3))
		draw_string(f, Vector2(rx, y_pos + 40), "VIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.8, 0))

		var free_label = _format_short_reward(free_reward) if free_reward else "-"
		var free_color = Color(0.5, 1, 0.5)
		if claimed_free:
			free_label = "RECLAMADO"
			free_color = Color(0.4, 0.4, 0.4)
		elif free_reward == null:
			free_color = Color(0.3, 0.3, 0.3)
		draw_string(f, Vector2(lx, y_pos + 58), free_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, free_color)

		var vip_label = _format_short_reward(vip_reward) if vip_reward else "-"
		var vip_color = Color(1, 0.9, 0.3)
		if claimed_vip:
			vip_label = "RECLAMADO"
			vip_color = Color(0.4, 0.4, 0.4)
		elif not has_vip:
			vip_label = "BLOQUEADO"
			vip_color = Color(0.4, 0.3, 0.1)
		elif vip_reward == null:
			vip_color = Color(0.3, 0.3, 0.3)
		draw_string(f, Vector2(rx, y_pos + 58), vip_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, vip_color)

		if not has_vip and vip_reward:
			draw_rect(Rect2(rx, y_pos + 68, half_w - 5, 16), Color(0.3, 0.2, 0, 0.5))
			draw_string(f, Vector2(rx + 4, y_pos + 80), "HAZTE VIP PARA ACCEDER", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 0.8, 0.3))

		if is_current:
			draw_string(f, Vector2(r_pos.x + 25 + card_w - 10, y_pos + card_h - 10), "ACTUAL", HORIZONTAL_ALIGNMENT_RIGHT, -1, 9, Color(0, 1, 1))

func _format_short_reward(reward):
	if not reward:
		return "-"
	if reward.get("isPremium", false):
		return "VIP"
	if reward.get("itemName", ""):
		var amt = reward.get("itemAmount", 1)
		return (reward.itemName + " x" + str(amt)) if amt > 1 else reward.itemName
	if reward.get("hubs", 0) > 0:
		return str(reward.hubs) + " Hubs"
	if reward.get("ohcu", 0) > 0:
		return str(reward.ohcu) + " Ohcu"
	if reward.get("exp", 0) > 0:
		return str(reward.exp) + " EXP"
	if reward.get("shipId", 0) > 0:
		return "Nave #" + str(reward.shipId)
	return "-"

func _show_result_modal(title, msg):
	var overlay = PanelContainer.new()
	overlay.name = "ResultOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	active_modales.append(overlay)

	var screen_size = get_viewport_rect().size
	var pz = Vector2(340, 150)
	var px = screen_size.x / 2.0 - pz.x / 2.0
	var py = screen_size.y / 2.0 - pz.y / 2.0
	overlay.position = Vector2(px, py)
	overlay.custom_minimum_size = pz
	overlay.size = pz

	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0, 0.1, 0.05, 1)
	sb.set_corner_radius_all(8)
	sb.border_width_all = 2
	sb.border_color = Color(0, 1, 0.3, 0.8)
	overlay.add_theme_stylebox_override("panel", sb)

	var v = VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	v.add_theme_constant_override("h_separation", 0)
	overlay.add_child(v)

	var tl = Label.new()
	tl.text = title
	tl.modulate = Color(0, 1, 0.3)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.theme_override_font_sizes = { "font_size": 14 }
	v.add_child(tl)

	var m = Label.new()
	m.text = msg
	m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	m.theme_override_font_sizes = { "font_size": 12 }
	v.add_child(m)

	var b = Button.new()
	b.text = "ENTENDIDO"
	b.custom_minimum_size = Vector2(120, 32)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func():
		if is_instance_valid(overlay) and overlay in active_modales:
			active_modales.erase(overlay)
			overlay.queue_free()
			modal_active = active_modales.size() > 0
	)
	v.add_child(b)

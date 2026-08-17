extends Control
# SupportMailboxUI.gd (v2.0) - Buzón de Mensajes de Soporte y Bugs
# Muestra hilos de chat interactivos bidireccionales con soporte.

signal closed

var _overlay: Control
var _panel: PanelContainer
var _scroll: ScrollContainer
var _mailbox_box: VBoxContainer
var _no_mail_label: Label

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_input(true)
	visible = false
	_build_ui()
	get_viewport().size_changed.connect(_recenter)
	
	if NetworkManager:
		NetworkManager.support_mailbox_updated.connect(_on_mailbox_updated)

func open():
	visible = true
	_recenter()
	_refresh_list()

func close():
	visible = false
	closed.emit()

func _input(event: InputEvent):
	if not visible: return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func _recenter():
	if not visible or not is_instance_valid(_panel): return
	_panel.reset_size()
	_panel.custom_minimum_size = Vector2(560, 520)
	_panel.size = Vector2(560, 520)
	var vp = get_viewport_rect().size
	_panel.global_position = (vp - _panel.size) / 2.0

func _build_ui():
	_overlay = Control.new()
	_overlay.name = "SupportMailboxOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

	_panel = PanelContainer.new()
	_panel.name = "SupportMailboxPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.01, 0.03, 0.06, 0.98)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.0, 0.85, 1.0) # Turquesa Sci-Fi
	style.set_corner_radius_all(12)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.custom_minimum_size = Vector2(560, 520)
	_panel.size = Vector2(560, 520)
	_overlay.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "✉️ BUZÓN DE SOPORTE E HISTORIAL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.0, 0.85, 1.0))
	vbox.add_child(title)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll)

	_mailbox_box = VBoxContainer.new()
	_mailbox_box.add_theme_constant_override("separation", 14)
	_mailbox_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_mailbox_box)

	_no_mail_label = Label.new()
	_no_mail_label.text = "NO TIENES RESPUESTAS DE SOPORTE ACTIVAS."
	_no_mail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_no_mail_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_no_mail_label.add_theme_font_size_override("font_size", 12)
	_no_mail_label.modulate = Color(0.5, 0.55, 0.6)
	_no_mail_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_no_mail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mailbox_box.add_child(_no_mail_label)

	var close_btn := Button.new()
	close_btn.text = "CERRAR BUZÓN"
	close_btn.custom_minimum_size = Vector2(160, 40)
	close_btn.modulate = Color(1.0, 0.4, 0.4)
	close_btn.pressed.connect(close)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(close_btn)

func _on_mailbox_updated(_data):
	if visible:
		_refresh_list()

func _refresh_list():
	for child in _mailbox_box.get_children():
		if child != _no_mail_label:
			child.queue_free()

	var list = NetworkManager.support_mailbox if NetworkManager else []
	if list.size() == 0:
		_no_mail_label.visible = true
		return

	_no_mail_label.visible = false

	for entry in list:
		if typeof(entry) != TYPE_DICTIONARY: continue
		var card = _create_mail_card(entry)
		_mailbox_box.add_child(card)

func _create_mail_card(entry: Dictionary) -> PanelContainer:
	var card = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.05, 0.1, 0.9)
	var is_closed = entry.get("status", "open") == "closed"
	style.border_width_left = 3
	style.border_color = Color(1.0, 0.35, 0.3) if is_closed else Color(0.0, 0.85, 1.0)
	style.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	card.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Encabezado (Fecha, Estado y Botón Borrar)
	var header = HBoxContainer.new()
	vbox.add_child(header)

	var status_lbl = Label.new()
	status_lbl.text = "🏁 FINALIZADO" if is_closed else ("✅ RESUELTO" if entry.get("status", "open") == "resolved" else "⏳ ABIERTO")
	status_lbl.add_theme_font_size_override("font_size", 10)
	status_lbl.modulate = Color(1.0, 0.4, 0.4) if is_closed else (Color(0.3, 1.0, 0.4) if entry.get("status", "open") == "resolved" else Color(1.0, 0.65, 0.1))
	header.add_child(status_lbl)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var del_btn = Button.new()
	del_btn.text = "✕"
	del_btn.custom_minimum_size = Vector2(24, 24)
	del_btn.modulate = Color(1.0, 0.3, 0.3)
	del_btn.add_theme_font_size_override("font_size", 10)
	var mid = entry.get("id", "")
	del_btn.pressed.connect(func():
		if NetworkManager:
			NetworkManager.send_event("deleteSupportMail", {"mailId": mid})
	)
	header.add_child(del_btn)

	# Hilo de Conversación (Chat Bubble Container)
	var chat_vbox = VBoxContainer.new()
	chat_vbox.add_theme_constant_override("separation", 6)
	vbox.add_child(chat_vbox)

	# 1. Burbuja Inicial (El reporte original)
	var initial_bubble = PanelContainer.new()
	var style_init_bubble = StyleBoxFlat.new()
	style_init_bubble.bg_color = Color(0.1, 0.12, 0.18, 0.7)
	style_init_bubble.set_corner_radius_all(6)
	initial_bubble.add_theme_stylebox_override("panel", style_init_bubble)
	
	var margin_init = MarginContainer.new()
	margin_init.add_theme_constant_override("margin_left", 8)
	margin_init.add_theme_constant_override("margin_right", 8)
	margin_init.add_theme_constant_override("margin_top", 6)
	margin_init.add_theme_constant_override("margin_bottom", 6)
	initial_bubble.add_child(margin_init)
	
	var init_vbox = VBoxContainer.new()
	margin_init.add_child(init_vbox)
	
	var init_title = Label.new()
	init_title.text = "TÚ (REPORTE ORIGINAL):"
	init_title.add_theme_font_size_override("font_size", 9)
	init_title.modulate = Color(0.0, 0.85, 1.0)
	init_vbox.add_child(init_title)
	
	var init_txt = Label.new()
	init_txt.text = str(entry.get("bugDescription", ""))
	init_txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	init_txt.add_theme_font_size_override("font_size", 11)
	init_vbox.add_child(init_txt)
	
	chat_vbox.add_child(initial_bubble)

	# 2. Respuestas
	var replies = entry.get("replies", [])
	if typeof(replies) == TYPE_ARRAY:
		for rep in replies:
			if typeof(rep) != TYPE_DICTIONARY: continue
			var bubble = PanelContainer.new()
			var is_admin = rep.get("sender", "admin") == "admin"
			
			var style_bubble = StyleBoxFlat.new()
			style_bubble.bg_color = Color(0.05, 0.18, 0.18, 0.8) if is_admin else Color(0.12, 0.14, 0.2, 0.8)
			style_bubble.set_corner_radius_all(6)
			bubble.add_theme_stylebox_override("panel", style_bubble)
			
			var margin_rep = MarginContainer.new()
			margin_rep.add_theme_constant_override("margin_left", 8)
			margin_rep.add_theme_constant_override("margin_right", 8)
			margin_rep.add_theme_constant_override("margin_top", 6)
			margin_rep.add_theme_constant_override("margin_bottom", 6)
			bubble.add_child(margin_rep)
			
			var rep_vbox = VBoxContainer.new()
			margin_rep.add_child(rep_vbox)
			
			var rep_title = Label.new()
			rep_title.text = "SOPORTE:" if is_admin else "TÚ:"
			rep_title.add_theme_font_size_override("font_size", 9)
			rep_title.modulate = Color(0.3, 1.0, 0.4) if is_admin else Color(0.0, 0.85, 1.0)
			rep_vbox.add_child(rep_title)
			
			var rep_txt = Label.new()
			rep_txt.text = str(rep.get("text", ""))
			rep_txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			rep_txt.add_theme_font_size_override("font_size", 11)
			rep_vbox.add_child(rep_txt)
			
			chat_vbox.add_child(bubble)

	# Campo de respuesta de chat in-game
	if not is_closed:
		var reply_row = HBoxContainer.new()
		reply_row.add_theme_constant_override("separation", 8)
		vbox.add_child(reply_row)
		
		var reply_input = LineEdit.new()
		reply_input.placeholder_text = "Escribe tu respuesta para el Soporte..."
		reply_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		reply_input.custom_minimum_size.y = 34
		reply_input.add_theme_font_size_override("font_size", 12)
		reply_row.add_child(reply_input)
		
		var send_btn = Button.new()
		send_btn.text = "RESPONDER"
		send_btn.custom_minimum_size = Vector2(100, 34)
		send_btn.modulate = Color(0.0, 0.85, 1.0)
		send_btn.add_theme_font_size_override("font_size", 11)
		
		var bug_id = entry.get("bugId", 0)
		send_btn.pressed.connect(func():
			var text = reply_input.text.strip_edges()
			if text != "":
				if NetworkManager:
					NetworkManager.send_event("replyToBugReport", {
						"id": bug_id,
						"replyText": text
					})
					reply_input.text = ""
		)
		reply_row.add_child(send_btn)
	else:
		var closed_lbl = Label.new()
		closed_lbl.text = "🏁 ESTE REPORTE HA SIDO FINALIZADO Y CERRADO."
		closed_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		closed_lbl.add_theme_font_size_override("font_size", 11)
		closed_lbl.modulate = Color(1.0, 0.4, 0.4)
		vbox.add_child(closed_lbl)

	return card

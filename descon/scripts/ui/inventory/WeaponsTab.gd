extends Control

# WeaponsTab.gd - SISTEMA DE ARMAMENTO DINÁMICO (v1.0 - Premium AAA)
# Permite asignar dinámicamente las 7 municiones a los slots Q, W, E.

var inv_main = null
var status_lbl = null # v690.0: Etiqueta inferior para mensajes de requisitos en rojo

# Colores y descripciones de las armas para diseño premium
var WEAPONS_DATA = {
	"laser": {
		"name": "LÁSER FRONTAL",
		"desc": "Proyectil de energía continua. Rango medio, daño estable.",
		"color": Color.CYAN,
		"icon": "⚡"
	},
	"missile": {
		"name": "MISIL TÁCTICO",
		"desc": "Misil teleguiado de alta potencia y daño en área.",
		"color": Color(1.0, 0.5, 0.0), # Naranja
		"icon": "🚀"
	},
	"mine": {
		"name": "MINA DE PROXIMIDAD",
		"desc": "Trampa explosiva de alta densidad para control de zona.",
		"color": Color.YELLOW,
		"icon": "💥"
	},
	"melee": {
		"name": "CORTADOR MELEE",
		"desc": "Sierra de plasma a corta distancia para naves ofensivas/tanques.",
		"color": Color.RED,
		"icon": "⚔️"
	},
	"heal": {
		"name": "PROYECTIL CURATIVO",
		"desc": "Soporte táctico. Cura la estructura de la nave aliada seleccionada.",
		"color": Color.GREEN,
		"icon": "💚"
	},
	"siphon": {
		"name": "SIFÓN DE ENERGÍA",
		"desc": "Drena el escudo y la vida del enemigo para reparar tus sistemas.",
		"color": Color(1.0, 0.0, 1.0), # Púrpura/Rosa
		"icon": "🔮"
	},
	"emp": {
		"name": "PULSO EMP",
		"desc": "Desactiva sensores y sistemas enemigos. Silencia habilidades.",
		"color": Color(0.2, 0.5, 1.0), # Azul eléctrico
		"icon": "📡"
	},
	"electron": {
		"name": "ELECTRÓN",
		"desc": "Bomba de energía parabólica. Explota en área y otorga velocidad acumulable al impactar.",
		"color": Color(0.3, 0.7, 1.0), # Celeste eléctrico
		"icon": "⚛️"
	}
}

func setup(p_inv_main):
	inv_main = p_inv_main

func update_ui():
	if not inv_main: return
	var root_tab = self
	
	# Limpieza de nodos antiguos
	for n in root_tab.get_children(): 
		root_tab.remove_child(n)
		n.queue_free()
	
	var master_v = VBoxContainer.new()
	master_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	master_v.offset_top = 10
	master_v.offset_bottom = -10
	master_v.offset_left = 10
	master_v.offset_right = -10
	master_v.add_theme_constant_override("separation", 20)
	root_tab.add_child(master_v)
	
	# 1. Título y estado
	var header = HBoxContainer.new()
	master_v.add_child(header)
	
	var title = Label.new()
	title.text = "SISTEMA DE CONFIGURACIÓN DE ARMAMENTO DE COMBATE"
	title.add_theme_font_size_override("font_size", 13)
	title.modulate = Color.CYAN
	header.add_child(title)
	
	# Comprobar si está en combate
	var p = get_tree().get_first_node_in_group("player")
	var is_comb = p and p.has_method("is_in_combat") and p.is_in_combat()
	
	if is_comb:
		var comb_warning = Label.new()
		comb_warning.text = "⚠️ SISTEMA BLOQUEADO: EN COMBATE"
		comb_warning.modulate = Color.RED
		comb_warning.add_theme_font_size_override("font_size", 11)
		comb_warning.size_flags_horizontal = Control.SIZE_SHRINK_END
		header.add_child(comb_warning)
		
	# Separación
	master_v.add_child(HSeparator.new())
	
	# Layout de dos columnas: Izquierda (Mis Slots) y Derecha (Biblioteca de armas)
	var main_h = HBoxContainer.new()
	main_h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_h.add_theme_constant_override("separation", 25)
	master_v.add_child(main_h)
	
	# Columna Izquierda: Slots Equipados (Q, W, E)
	var slots_v = VBoxContainer.new()
	slots_v.custom_minimum_size = Vector2(300, 0)
	slots_v.add_theme_constant_override("separation", 15)
	main_h.add_child(slots_v)
	
	var slots_title = Label.new()
	slots_title.text = "SLOTS DE ACCESO RÁPIDO HUD"
	slots_title.add_theme_font_size_override("font_size", 11)
	slots_title.modulate = Color(1, 1, 1, 0.6)
	slots_v.add_child(slots_title)
	
	_render_equipped_slots(slots_v, p, is_comb)
	
	# Vertical separator
	var v_sep = VSeparator.new()
	main_h.add_child(v_sep)
	
	# Columna Derecha: Biblioteca de Municiones
	var library_v = VBoxContainer.new()
	library_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_v.add_theme_constant_override("separation", 10)
	main_h.add_child(library_v)
	
	var lib_title = Label.new()
	lib_title.text = "TECNOLOGÍAS DE MUNICIÓN DISPONIBLES"
	lib_title.add_theme_font_size_override("font_size", 11)
	lib_title.modulate = Color(1, 1, 1, 0.6)
	library_v.add_child(lib_title)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	library_v.add_child(scroll)
	
	var grid = GridContainer.new()
	grid.columns = 1
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	
	_render_weapons_library(grid, p, is_comb)
	
	# v690.0: Zona de mensajes de requisitos (rojo) al pie del panel
	status_lbl = Label.new()
	status_lbl.name = "StatusLabel"
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_lbl.add_theme_font_size_override("font_size", 11)
	status_lbl.custom_minimum_size = Vector2(0, 22)
	status_lbl.modulate = Color(1.0, 0.35, 0.35)
	master_v.add_child(status_lbl)

func _render_equipped_slots(parent, p, is_comb):
	if not p or not p.get("ammo_slots"): return
	
	var keys = ["Q", "W", "E"]
	for i in range(3):
		var w_id = p.ammo_slots[i]
		var is_empty = (w_id == "" or w_id == null)
		var w_cfg = WEAPONS_DATA.get(w_id, {"name": "", "desc": "", "color": Color(0.4, 0.4, 0.4, 0.5), "icon": "—"})
		
		# Obtener cantidad del tier seleccionado
		var t_idx = p.selected_ammo.get(w_id, 0) if not is_empty else 0
		var a_list = p.ammo.get(w_id, [0]) if not is_empty else [0]
		var count = a_list[t_idx] if t_idx < a_list.size() else 0
		
		var slot_panel = PanelContainer.new()
		slot_panel.custom_minimum_size = Vector2(0, 90)
		parent.add_child(slot_panel)
		
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0.05, 0.6)
		sb.border_width_left = 4
		sb.border_color = w_cfg["color"]
		sb.set_corner_radius_all(6)
		slot_panel.add_theme_stylebox_override("panel", sb)
		
		var hb = HBoxContainer.new()
		hb.add_theme_constant_override("separation", 15)
		slot_panel.add_child(hb)
		
		# Indicador de Tecla / Icono
		var key_center = CenterContainer.new()
		key_center.custom_minimum_size = Vector2(60, 0)
		hb.add_child(key_center)
		
		var key_vbox = VBoxContainer.new()
		key_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		key_center.add_child(key_vbox)
		
		var key_label = Label.new()
		key_label.text = "[" + keys[i] + "]"
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_label.add_theme_font_size_override("font_size", 14)
		key_label.modulate = Color.CYAN if not is_empty else Color(1, 1, 1, 0.3)
		key_vbox.add_child(key_label)
		
		var ico_label = Label.new()
		ico_label.text = w_cfg["icon"]
		ico_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ico_label.add_theme_font_size_override("font_size", 20)
		ico_label.modulate = w_cfg["color"]
		key_vbox.add_child(ico_label)
		
		if is_empty:
			# v690.2: Slot vacío — solo mostrar tecla, sin detalles
			var empty_lbl = Label.new()
			empty_lbl.text = "VACÍO"
			empty_lbl.add_theme_font_size_override("font_size", 10)
			empty_lbl.modulate = Color(1, 1, 1, 0.3)
			hb.add_child(empty_lbl)
		else:
			# Detalles de arma equipada
			var details_v = VBoxContainer.new()
			details_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			details_v.alignment = BoxContainer.ALIGNMENT_CENTER
			hb.add_child(details_v)
			
			var name_lbl = Label.new()
			name_lbl.text = w_cfg["name"]
			name_lbl.add_theme_font_size_override("font_size", 12)
			name_lbl.modulate = w_cfg["color"]
			details_v.add_child(name_lbl)
			
			var ammo_lbl = Label.new()
			ammo_lbl.text = "Tier " + str(int(t_idx) + 1) + " | Cantidad: " + _format_val(count)
			ammo_lbl.add_theme_font_size_override("font_size", 10)
			ammo_lbl.modulate.a = 0.7
			details_v.add_child(ammo_lbl)
		
		# Efecto visual de deshabilitar si está en combate
		if is_comb:
			slot_panel.modulate.a = 0.5

func _render_weapons_library(grid, p, is_comb):
	if not p: return
	
	for w_id in WEAPONS_DATA:
		var w_cfg = WEAPONS_DATA[w_id]
		
		# v690.0: Validar requisitos del tier actualmente seleccionado para este tipo de munición
		var t_idx = int(p.selected_ammo.get(w_id, 0))
		var locked := false
		var lock_msg := ""
		if NetworkManager and NetworkManager.has_method("check_equip_requirements"):
			var req_check = NetworkManager.check_equip_requirements("", "", w_id, t_idx)
			locked = not req_check.get("ok", true)
			lock_msg = str(req_check.get("msg", "REQUISITOS NO CUMPLIDOS"))
		
		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(400, 75)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(card)
		
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.4)
		sb.border_width_left = 3
		sb.border_color = w_cfg["color"]
		sb.set_corner_radius_all(4)
		card.add_theme_stylebox_override("panel", sb)
		
		var hb = HBoxContainer.new()
		hb.add_theme_constant_override("separation", 15)
		card.add_child(hb)
		
		# Icono grande de arma
		var ico_center = CenterContainer.new()
		ico_center.custom_minimum_size = Vector2(50, 0)
		hb.add_child(ico_center)
		
		var ico = Label.new()
		ico.text = "🔒" if locked else w_cfg["icon"]
		ico.add_theme_font_size_override("font_size", 24)
		ico.modulate = w_cfg["color"] if not locked else Color(1, 0.3, 0.3)
		ico_center.add_child(ico)
		
		# Nombre e Info de arma
		var info_v = VBoxContainer.new()
		info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_v.alignment = BoxContainer.ALIGNMENT_CENTER
		hb.add_child(info_v)
		
		var name_lbl = Label.new()
		name_lbl.text = w_cfg["name"]
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.modulate = w_cfg["color"]
		info_v.add_child(name_lbl)
		
		var desc_lbl = Label.new()
		desc_lbl.text = w_cfg["desc"]
		desc_lbl.add_theme_font_size_override("font_size", 9)
		desc_lbl.modulate.a = 0.6
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_v.add_child(desc_lbl)
		
		# v690.0: Aviso rojo de requisito faltante en la propia tarjeta
		if locked:
			var lock_lbl = Label.new()
			lock_lbl.text = "🔒 BLOQUEADA: " + lock_msg
			lock_lbl.add_theme_font_size_override("font_size", 9)
			lock_lbl.modulate = Color(1.0, 0.35, 0.35)
			info_v.add_child(lock_lbl)
		
		# Botones de asignación Q, W, E
		var btn_h = HBoxContainer.new()
		btn_h.alignment = BoxContainer.ALIGNMENT_CENTER
		btn_h.add_theme_constant_override("separation", 6)
		hb.add_child(btn_h)
		
		var keys = ["Q", "W", "E"]
		# v690.1: Índice del slot donde ya está equipada esta munición (-1 si no está)
		var equipped_slot_idx := -1
		for j in range(3):
			if p.ammo_slots[j] == w_id:
				equipped_slot_idx = j
				break
		for i in range(3):
			var btn = Button.new()
			btn.custom_minimum_size = Vector2(30, 30)
			btn.add_theme_font_size_override("font_size", 10)
			
			if equipped_slot_idx == i:
				btn.text = "✔"
				btn.modulate = Color(0.0, 1.0, 0.0) # Verde brillante limpio para todos los ticks
				btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
			elif equipped_slot_idx >= 0:
				# v690.1: Ya equipada en otro slot → no se puede repetir
				btn.text = "✕"
				btn.modulate = Color(1, 1, 1, 0.35)
				btn.disabled = true
				btn.tooltip_text = "YA EQUIPADA EN SLOT " + keys[equipped_slot_idx]
			elif locked:
				# v690.0: Requisitos no cumplidos → botones bloqueados con candado
				btn.text = "🔒"
				btn.disabled = true
				btn.tooltip_text = "MUNICIÓN BLOQUEADA: " + lock_msg
			else:
				# Deshabilitar todos los botones de equipamiento si está en combate
				if is_comb:
					btn.disabled = true
				btn.text = " " + keys[i] + " "
				btn.pressed.connect(_on_equip_pressed.bind(i, w_id))
			
			btn_h.add_child(btn)

func _on_equip_pressed(slot_idx: int, ammo_type: String):
	print("[WEAPONS-TAB] Intentando equipar munición: ", ammo_type, " en slot ", slot_idx)
	var p = get_tree().get_first_node_in_group("player")
	if not p:
		print("[WEAPONS-TAB] Error: No se encontró el nodo del jugador.")
		return
	
	if p.has_method("is_in_combat") and p.is_in_combat():
		print("[WEAPONS-TAB] Cancelado: El jugador está en combate.")
		return
	
	# v690.1: Cada munición solo puede equiparse una vez (no repetir en 2 slots)
	if ammo_type in p.ammo_slots:
		_show_status("⚠️ " + WEAPONS_DATA.get(ammo_type, {}).get("name", ammo_type.to_upper()) + " YA ESTÁ EQUIPADA EN OTRO SLOT")
		print("[WEAPONS-TAB] Cancelado: munición ya equipada en otro slot.")
		return
	
	# v690.0: Validar requisitos (nivel, misión, desbloqueo, esferas) del tier seleccionado
	if NetworkManager and NetworkManager.has_method("check_equip_requirements"):
		var tier = int(p.selected_ammo.get(ammo_type, 0))
		var req_check = NetworkManager.check_equip_requirements("", "", ammo_type, tier)
		if not req_check.get("ok", true):
			_show_status("🔒 MUNICIÓN BLOQUEADA: " + str(req_check.get("msg", "REQUISITOS NO CUMPLIDOS")))
			print("[WEAPONS-TAB] Cancelado por requisitos: ", req_check.get("msg", ""))
			return
		
	if p.has_method("set_ammo_slot"):
		print("[WEAPONS-TAB] Llamando a set_ammo_slot en Player.")
		p.set_ammo_slot(slot_idx, ammo_type)
		AudioManager.play_sfx("ui_click")
		_show_status("")
		update_ui()
	else:
		print("[WEAPONS-TAB] Error: El jugador no tiene el método set_ammo_slot.")

# v690.0: Mensaje inferior del panel (rojo por defecto)
func _show_status(p_text: String, p_color := Color(1.0, 0.35, 0.35)):
	if is_instance_valid(status_lbl):
		status_lbl.text = p_text
		status_lbl.modulate = p_color
		if p_text != "":
			var lbl = status_lbl
			var timer = get_tree().create_timer(5.0)
			timer.timeout.connect(func():
				if is_instance_valid(lbl):
					lbl.text = ""
			)
	else:
		print("[WEAPONS-TAB] " + p_text)

func _format_val(v):
	var s = str(int(v))
	var r = ""
	var c = 0
	for i in range(s.length()-1,-1,-1):
		r = s[i] + r
		c += 1
		if c == 3 and i != 0:
			r = "." + r
			c = 0
	return r

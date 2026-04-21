extends Control

# Inventory.gd (Omni-Control v164.1 - Phoenix Absolute)
# Saneamiento total de diccionarios (Bracket Notation) + Exorcismo de Título.

var inventory_items = []
var owned_ships = []
var current_ship_id = 1
var equipped_data = {"w": [], "s": [], "e": [], "x": []}
var hubs = 0
var ohcu = 0
var is_open = false

var talent_system = null
var selected_hangar_ship_id = -1 # v210.15: Nave seleccionada para ver en Hangar

var shop_tab = "ships"
var ammo_sub_tab = "laser"
var modal_active = false
var equipped_by_ship = {} # v210.95: Cache local de equipos de toda la flota
var selected_sphere_slot = -1 # Slot siendo reconfigurado
var selected_sphere_type_filter = "ANY" # Filtro de color para la biblioteca
var spheres_manager = null # Referencia al gestor de esferas del jugador



var SKILL_DATA = [
	{ "id": "eng_1", "cat": "engineering", "name": "REFUERZO DE CASCO", "desc": "+2% HP por nivel", "max": 5 },
	{ "id": "eng_2", "cat": "engineering", "name": "ESCUDO DINÁMICO", "desc": "+2% Escudo por nivel", "max": 5 },
	{ "id": "eng_3", "cat": "engineering", "name": "REGEN EMERGENGIA", "desc": "+5% HP Reparación", "max": 5 },
	{ "id": "eng_4", "cat": "engineering", "name": "CAPACITOR OHCU", "desc": "+5% Shield Regen", "max": 5 },
	{ "id": "eng_5", "cat": "engineering", "name": "PLACAS NANOBOTS", "desc": "+1% Armadura total", "max": 5 },
	{ "id": "eng_6", "cat": "engineering", "name": "REACTOR FUSIÓN", "desc": "+3% Eficiencia Energía", "max": 5 },
	{ "id": "eng_7", "cat": "engineering", "name": "MANTE GALÁCTICO", "desc": "-5% Costo Reparación", "max": 5 },
	{ "id": "eng_8", "cat": "engineering", "name": "ESTABL FLOTANTE", "desc": "+1% Estabilidad (Vel)", "max": 5 },
	{ "id": "com_1", "cat": "combat", "name": "LÁSER SOBRECARGA", "desc": "+3% Daño Láser", "max": 5 },
	{ "id": "com_2", "cat": "combat", "name": "MIRILLA TÁCTICA", "desc": "+2% Prob. Crítico", "max": 5 },
	{ "id": "com_3", "cat": "combat", "name": "FURIA DEL PILOTO", "desc": "+5% Daño Crítico", "max": 5 },
	{ "id": "com_4", "cat": "combat", "name": "CARGA PROYECTIL", "desc": "+5% Bonus Munición", "max": 5 },
	{ "id": "com_5", "cat": "combat", "name": "DISPARO PRECISIÓN", "desc": "+2% Puntería", "max": 5 },
	{ "id": "com_6", "cat": "combat", "name": "PERFORACIÓN TÉRM", "desc": "+3% Ignorar Escudo", "max": 5 },
	{ "id": "com_7", "cat": "combat", "name": "CADENCIA MILITAR", "desc": "-2% CD de Disparo", "max": 5 },
	{ "id": "com_8", "cat": "combat", "name": "BLINDAJE ATAQUE", "desc": "+1% Evasión en Combate", "max": 5 },
	{ "id": "sci_1", "cat": "science", "name": "MOTORES FUSIÓN", "desc": "+1.5% Velocidad Base", "max": 5 },
	{ "id": "sci_2", "cat": "science", "name": "ESCÁNER TÁCTICO", "desc": "+10% Rango Minimapa", "max": 5 },
	{ "id": "sci_3", "cat": "science", "name": "MINERÍA OHCU", "desc": "+5% OHCU de Kills", "max": 5 },
	{ "id": "sci_4", "cat": "science", "name": "MERCADO GALÁXIA", "desc": "-2% Descuento Tienda", "max": 5 },
	{ "id": "sci_5", "cat": "science", "name": "ENFRIAMIENTO RÁP", "desc": "-3% CD Habilidades", "max": 5 },
	{ "id": "sci_6", "cat": "science", "name": "SINCRONÍA TACT", "desc": "+1% Bonus en Grupo", "max": 5 },
	{ "id": "sci_7", "cat": "science", "name": "SENSORES PRECI", "desc": "+5% Loot de Bosses", "max": 5 },
	{ "id": "sci_8", "cat": "science", "name": "SALTO HIPERESP", "desc": "+10% Distancia Dash", "max": 5 }
]

func _ready():
	# visible = false # Removido para que el inventario lo controle
	mouse_filter = Control.MOUSE_FILTER_PASS
	
	# PROTOCOLO EXORCISMO (v164.1: Ocultar todo nodo Label externo que diga LOGISTICA o similar)
	_aggressive_hide(self)
	var win_title = get_node_or_null("Window/Label")
	if win_title: 
		win_title.visible = false
		win_title.text = ""
	
	if NetworkManager:
		NetworkManager.inventory_data.connect(_on_inventory_received)
		NetworkManager.login_success.connect(func(d): _on_inventory_received(d))
		NetworkManager.auth_success.connect(func(d): _on_inventory_received(d))
	
	# v190.62: Sincronía Responsive
	get_viewport().size_changed.connect(func(): queue_redraw())
	
	if PartyManager:
		PartyManager.party_updated.connect(func(_d): _update_party_ui())
	
	var tabs = get_node_or_null("Window/TabContainer")
	if tabs:
		tabs.offset_top = 40; tabs.offset_left = 15
		tabs.offset_right = -15; tabs.offset_bottom = -15
		# v219.61: Refresco selectivo al cambiar de pestaña
		if not tabs.tab_changed.is_connected(_update_active_tab_ui):
			tabs.tab_changed.connect(func(_idx): _update_active_tab_ui())
	
	# v164.2: Sincronía Táctica de Moneda (F2 -> F1 Sync)
	_connect_to_player_stats()
	
	# v164.94: Timer para refrescar pilotos cercanos (evita que la lista sea estática)
	var party_timer = Timer.new()
	party_timer.wait_time = 3.0
	party_timer.autostart = true
	party_timer.timeout.connect(_update_party_ui)
	add_child(party_timer)
	
	# v164.95: Buscar y vincular TalentSystem
	# Intentamos buscarlo en el grupo, si no, lo buscaremos bajo el nodo World
	talent_system = get_tree().get_first_node_in_group("talent_system")
	if not is_instance_valid(talent_system):
		var world = get_tree().get_first_node_in_group("world_node")
		if is_instance_valid(world) and world.has_node("TalentSystem"):
			talent_system = world.get_node("TalentSystem")
			
	if is_instance_valid(talent_system):
		talent_system.talents_updated.connect(_update_talent_tree)

	await get_tree().create_timer(1.0).timeout
	_refresh_data()

func _aggressive_hide(node):
	for child in node.get_children():
		if child is Label:
			var t = child.text.to_upper()
			if "LOGISTICA" in t or "EQUIPAMIENTO" in t or "CENTRO" in t:
				child.text = ""
				child.visible = false
				child.queue_free()
		if child.name != "Window":
			_aggressive_hide(child)
		else: # Escanear dentro de Window también por si acaso
			for grandchildren in child.get_children():
				if grandchildren is Label:
					var gt = grandchildren.text.to_upper()
					if "LOGISTICA" in gt or "EQUIPAMIENTO" in gt or "CENTRO" in gt:
						grandchildren.text = ""; grandchildren.visible = false; grandchildren.queue_free()

func _connect_to_player_stats():
	var p = get_tree().get_first_node_in_group("player")
	if is_instance_valid(p):
		if not p.stats_changed.is_connected(_on_player_stats_changed):
			p.stats_changed.connect(_on_player_stats_changed)
			print("[INVENTARIO] Enlace de estadísticas establecido con el Piloto.")

func _on_player_stats_changed(p_data: Dictionary):
	# Actualizar saldos locales para que el dibujo de _draw() sea correcto
	if p_data.has("hubs"): hubs = int(p_data["hubs"])
	if p_data.has("ohcu"): ohcu = int(p_data["ohcu"])
	queue_redraw()

func _draw():
	if not visible: return
	var screen_size = get_viewport_rect().size
	var r_size = Vector2(screen_size.x * 0.85, screen_size.y * 0.85)
	var r_pos = (screen_size - r_size) / 2.0
	
	# Actualizar ventana física (contenedor de pestañas)
	var win = get_node_or_null("Window")
	if win:
		win.position = r_pos
		win.custom_minimum_size = r_size
		win.size = r_size
	
	draw_rect(Rect2(r_pos, r_size), Color(0.02, 0.02, 0.05, 0.98))
	draw_rect(Rect2(r_pos, Vector2(r_size.x, 35)), Color(0, 0.08, 0.12, 1.0))
	draw_rect(Rect2(r_pos, r_size), Color(0, 0.8, 1, 0.5), false, 1.5)
	
	var f = get_theme_font("font")
	draw_string(f, r_pos + Vector2(20, 22), "HUBS: " + _format_val(hubs), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 1, 1))
	draw_string(f, r_pos + Vector2(180, 22), "OHCU: " + _format_val(ohcu), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0, 1))
	
	draw_rect(Rect2(r_pos.x + r_size.x - 65, r_pos.y+8, 20, 18), Color(0, 1, 1), false, 1.0)
	draw_rect(Rect2(r_pos.x + r_size.x - 35, r_pos.y+8, 25, 18), Color(0, 1, 1), false, 1.0)
	draw_string(f, r_pos + Vector2(r_size.x-60, 21), "M", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 1, 1))
	draw_string(f, r_pos + Vector2(r_size.x-30, 21), "[X]", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 1, 1))

func _format_val(v):
	var s = str(int(v)); var r = ""; var c = 0
	for i in range(s.length()-1,-1,-1):
		r = s[i] + r; c += 1
		if c == 3 and i != 0: r = "." + r; c = 0
	return r

func _input(event):
	# v222.98: No procesar shortcuts si el usuario está escribiendo (Chat, etc)
	var focusNode = get_viewport().gui_get_focus_owner()
	if focusNode is LineEdit or focusNode is TextEdit: return

	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		toggle(); get_viewport().set_input_as_handled()
	
	if event is InputEventKey and event.pressed and event.keycode == KEY_M:
		var tabs = get_node_or_null("Window/TabContainer")
		var is_on_map = false
		if tabs and is_open:
			is_on_map = (tabs.get_child(tabs.current_tab).name == "Mapa")
		
		if is_open and is_on_map:
			toggle()
		else:
			if not is_open: toggle()
			if tabs:
				for i in range(tabs.get_child_count()):
					if tabs.get_child(i).name == "Mapa":
						tabs.current_tab = i
						break
		get_viewport().set_input_as_handled()
		
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if is_open:
			toggle()
			get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.pressed and visible:
		var screen_size = get_viewport_rect().size
		var r_size = Vector2(screen_size.x * 0.85, screen_size.y * 0.85)
		var r_pos = (screen_size - r_size) / 2
		var x_rect = Rect2(r_pos.x + r_size.x - 35, r_pos.y + 8, 25, 18)
		if x_rect.has_point(event.position): toggle(); get_viewport().set_input_as_handled()

func toggle():
	is_open = !is_open
	visible = is_open
	
	if is_open: 
		_refresh_data()
		# v190.20: PRIORIDAD ABSOLUTA - Mover al frente de la jerarquía UI
		if get_parent():
			get_parent().move_child(self, get_parent().get_child_count() - 1)
			# Si estamos dentro de un CanvasLayer, esto asegura el dibujo superior
			z_index = 100 
	else:
		z_index = 0
		
	queue_redraw()

func _refresh_data():
	if NetworkManager: NetworkManager.send_event("getInventory", {})

func _on_inventory_received(data: Dictionary):
	if data.has("player"): data = data.player
	
	# v210.50: ACTUALIZACIÓN SEGURA (Detección de Datos Parciales)
	if data.has("inventory") or data.has("items"):
		inventory_items = data.get("inventory", data.get("items", []))
	if data.has("equipped"):
		equipped_data = data.equipped
	if data.has("ownedShips"):
		owned_ships = data.ownedShips
	if data.has("currentShipId"):
		current_ship_id = int(data.currentShipId)
	if data.has("hubs"): hubs = int(data.hubs)
	if data.has("ohcu"): ohcu = int(data.ohcu)
	if data.has("equippedByShip"):
		equipped_by_ship = data.equippedByShip
	
	# v164.11: Sincronizar con el Player (CRÍTICO PARA MMO SYNC)
	# Siempre actualizamos los datos internos aunque la UI esté cerrada
	var p = get_tree().get_first_node_in_group("player")
	if p:
		p.hubs = hubs
		p.ohculianos = ohcu
		if data.has("inventory") or data.has("items"): p.inventory = inventory_items
		if data.has("equipped"): p.equipped = equipped_data
		if data.has("currentShipId"):
			p.current_ship_id = current_ship_id
			if p.has_method("_setup_ship_visuals"): p._setup_ship_visuals()
		if p.has_method("_recalculate_stats"): p._recalculate_stats()
		elif p.has_method("_emit_stats"): p._emit_stats()
		if p.has_method("update_stats"): 
			p.update_stats({"currentShipId": current_ship_id, "equipped": equipped_data})

	# v219.67: Asegurar creación de pestañas dinámicas (Fix desaparición Mapa)
	if is_open:
		_update_active_tab_ui()
	elif not get_node_or_null("Window/TabContainer/Mapa"):
		_update_map_ui() # Solo se llama una vez para crear la pestaña
	
	# v210.16: Conservar selección si es válida
	if selected_hangar_ship_id == -1: selected_hangar_ship_id = current_ship_id

func _update_active_tab_ui():
	var tab_container = get_node_or_null("Window/TabContainer")
	if not tab_container: return
	
	var active_tab_name = tab_container.get_child(tab_container.current_tab).name
	match active_tab_name:
		"Hangar": _update_hangar_ui()
		"Esferas": _update_spheres_ui()
		"Talentos": _update_talent_tree()
		"Tienda": _update_shop_ui()
		"Equipo": _update_party_ui()
		"Mapa": _update_map_ui()
	
	queue_redraw()

# --- HANGAR ---
func _update_hangar_ui():
	var h = get_node_or_null("Window/TabContainer/Hangar")
	if not h: return
	for n in h.get_children(): n.queue_free()

	# v233.05: NUEVO LAYOUT HANGAR (FLOTA ARRIBA / INVENTARIO A LA DERECHA)
	var main_v = VBoxContainer.new()
	main_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_v.add_theme_constant_override("separation", 20)
	h.add_child(main_v)
	
	# --- SECCIÓN 1: FLOTA (ARRIBA INTERIOR) ---
	var fleet_v = VBoxContainer.new()
	main_v.add_child(fleet_v)
	var f_lbl = Label.new(); f_lbl.text = "FLOTA DE COMBATE Y MODELOS ACTIVOS"; f_lbl.modulate = Color.CYAN; f_lbl.add_theme_font_size_override("font_size", 10); f_lbl.modulate.a = 0.6; fleet_v.add_child(f_lbl)
	
	var f_scroll = ScrollContainer.new(); f_scroll.custom_minimum_size = Vector2(0, 75); f_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; fleet_v.add_child(f_scroll)
	var f_grid = HBoxContainer.new(); f_grid.add_theme_constant_override("separation", 12); f_scroll.add_child(f_grid)
	for sid in owned_ships: _create_fleet_card(sid, f_grid)
	
	# --- SECCIÓN 2: CUERPO (EQUIPO IZQ / INVENTARIO DER) ---
	var body_h = HBoxContainer.new(); body_h.size_flags_vertical = 3; body_h.add_theme_constant_override("separation", 30); main_v.add_child(body_h)
	
	# COLUMNA IZQUIERDA: GESTIÓN DE LA NAVE
	var left_v = VBoxContainer.new(); left_v.size_flags_horizontal = 3; left_v.size_flags_stretch_ratio = 1.3; body_h.add_child(left_v)
	
	var model = {}
	var viewing_id = selected_hangar_ship_id if selected_hangar_ship_id != -1 else current_ship_id
	for ship in GameConstants.SHIP_MODELS: 
		if ship["id"] == viewing_id: model = ship; break
	if model.is_empty(): model = GameConstants.SHIP_MODELS[0]
	
	var name_h = HBoxContainer.new(); left_v.add_child(name_h)
	var s_title = Label.new(); s_title.text = model.get("name", "Nave").to_upper(); s_title.add_theme_font_size_override("font_size", 24); name_h.add_child(s_title)
	
	if viewing_id != current_ship_id:
		var btn_act = Button.new(); btn_act.text = " ACTIVAR MODELO "; btn_act.custom_minimum_size = Vector2(140, 35); btn_act.modulate = Color.GREEN; btn_act.pressed.connect(func(): 
			NetworkManager.send_event("switchShip", {"shipId": viewing_id})
			current_ship_id = viewing_id; selected_hangar_ship_id = viewing_id; _update_hangar_ui())
		name_h.add_child(btn_act)

	var slots_v = VBoxContainer.new(); slots_v.add_theme_constant_override("separation", 15); left_v.add_child(slots_v)
	var slots = model.get("slots") if model.has("slots") else {"w":0, "s":0, "e":0, "x":1}
	_render_group(slots_v, "w", "MODULOS DE ATAQUE (LASER/MISIL)", slots["w"])
	_render_group(slots_v, "s", "DEFENSA Y ESCUDOS", slots["s"])
	_render_group(slots_v, "e", "MOTORES Y PROPULSION", slots["e"])
	_render_group(slots_v, "x", "EXTRAS Y CPU", slots.get("x", 1))

	# COLUMNA DERECHA: BODEGA DE MATERIALES (TU MARCA AZUL)
	var right_v = VBoxContainer.new(); right_v.size_flags_horizontal = 3; right_v.size_flags_stretch_ratio = 1.0; body_h.add_child(right_v)
	var inv_lbl = Label.new(); inv_lbl.text = "BODEGA DE CARGA / INVENTARIO"; inv_lbl.modulate = Color.CYAN; inv_lbl.add_theme_font_size_override("font_size", 10); inv_lbl.modulate.a = 0.6; right_v.add_child(inv_lbl)
	
	var inv_scroll = ScrollContainer.new(); inv_scroll.size_flags_vertical = 3; right_v.add_child(inv_scroll)
	var inv_vbox = VBoxContainer.new(); inv_vbox.size_flags_horizontal = 3; inv_scroll.add_child(inv_vbox)
	
	if inventory_items.is_empty(): 
		var no = Label.new(); no.text = "\nBODEGA VACÍA"; no.horizontal_alignment = 1; no.modulate.a = 0.2; inv_vbox.add_child(no)
	else: 
		for item in inventory_items: _create_item_row(item, inv_vbox)

func _create_fleet_card(sid, parent):
	var model = {}
	for m in GameConstants.SHIP_MODELS: 
		if m["id"] == sid: 
			model = m
			break
	if model.is_empty(): return # Anti-crash v164.4
	
	var p = PanelContainer.new(); p.custom_minimum_size = Vector2(140, 55)
	var is_active = (sid == current_ship_id)
	var is_viewing = (sid == selected_hangar_ship_id)
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0, 1, 0, 0.1) if is_active else (Color(0, 0.5, 1, 0.1) if is_viewing else Color(0,0,0,0.5))
	sb.border_width_left = 2; sb.border_color = Color.GREEN if is_active else (Color.CYAN if is_viewing else Color(1,1,1,0.1))
	p.add_theme_stylebox_override("panel", sb)
	
	var v = VBoxContainer.new(); p.add_child(v)
	var n = Label.new(); n.text = model["name"]; n.horizontal_alignment = 1; v.add_child(n)
	var st = Label.new(); st.text = "ACTIVA" if is_active else "DISPONIBLE"; st.horizontal_alignment = 1; st.modulate = Color.GREEN if is_active else Color.WHITE; st.add_theme_font_size_override("font_size", 8); v.add_child(st)
	
	p.gui_input.connect(func(ev): 
		if ev is InputEventMouseButton and ev.pressed: 
			selected_hangar_ship_id = sid
			_update_hangar_ui()
	)
	parent.add_child(p)

func _create_empty_fleet_card(parent):
	var p = PanelContainer.new(); p.custom_minimum_size = Vector2(140, 55); var sb = StyleBoxFlat.new(); sb.bg_color = Color(0,0,0,0.3); sb.border_width_left = 1; sb.border_color = Color(1,1,1,0.05); p.add_theme_stylebox_override("panel", sb)
	var v = VBoxContainer.new(); p.add_child(v); var n = Label.new(); n.text = "SLOT VACÍO"; n.horizontal_alignment = 1; v.add_child(n); parent.add_child(p)

func _render_group(parent, type, title, count):
	var l = Label.new(); l.text = title; l.modulate.a = 0.4; l.add_theme_font_size_override("font_size", 9); parent.add_child(l)
	var grid = GridContainer.new(); grid.columns = 10; parent.add_child(grid)
	
	# v210.96: Usar caché per-ship si no es la nave activa
	# v210.110: Unificar fuente de datos (Priorizar siempre el Mapa de la Flota para evitar bugs de desincronía)
	var eq = []
	var viewing_id = selected_hangar_ship_id if selected_hangar_ship_id != -1 else current_ship_id
	
	if equipped_by_ship.has(str(viewing_id)):
		var ship_e = equipped_by_ship.get(str(viewing_id), {})
		if ship_e: eq = ship_e.get(type, [])
	else:
		# Fallback solo si el mapa no ha llegado aún
		eq = equipped_data.get(type, [])
		
	for i in range(count):
		var p = PanelContainer.new(); p.custom_minimum_size = Vector2(40, 40); var sb = StyleBoxFlat.new(); sb.bg_color = Color(0,0,0,0.6); sb.border_width_left = 1; sb.border_color = Color(1,1,1,0.1); p.add_theme_stylebox_override("panel", sb)
		if i < eq.size():
			var it = Label.new(); it.text = "I"; it.horizontal_alignment = 1; p.add_child(it); sb.border_color = Color.CYAN
			p.gui_input.connect(func(ev): 
				if ev is InputEventMouseButton and ev.pressed: 
					var v_id = selected_hangar_ship_id if selected_hangar_ship_id != -1 else current_ship_id
					print("[HANGAR] Desequipando item en nave ID: ", v_id)
					NetworkManager.send_event("unequipItem", {
						"category": type, 
						"index": i,
						"shipId": v_id
					})
			)
		else: var c = Label.new(); c.text = "+"; c.horizontal_alignment = 1; c.modulate.a = 0.1; p.add_child(c)
		grid.add_child(p)

func _create_item_row(it, parent):
	if not it or not it.has("name"): return # Anti-crash v164.4
	var p = PanelContainer.new(); p.custom_minimum_size = Vector2(0, 45); var sb = StyleBoxFlat.new(); sb.bg_color = Color(1,1,1,0.03); sb.border_width_left = 2; sb.border_color = Color.CYAN; p.add_theme_stylebox_override("panel", sb)
	var hb = HBoxContainer.new(); hb.offset_left = 8; p.add_child(hb); var v = VBoxContainer.new(); v.size_flags_horizontal = 3; hb.add_child(v)
	var n = Label.new(); n.text = str(it.get("name", "ITEM")).to_upper(); n.add_theme_font_size_override("font_size", 10); v.add_child(n)
	var type_txt = str(it.get("type", "OBJ")).to_upper()
	var t = Label.new(); t.text = "MODULO " + type_txt; t.add_theme_font_size_override("font_size", 8); t.modulate = Color.CYAN; v.add_child(t)
	var b = Button.new(); b.text = "EQUIPAR"; b.add_theme_font_size_override("font_size", 9)
	
	b.pressed.connect(func(): 
		var it_type = it.get("type", "w")
		var viewing_id = selected_hangar_ship_id if selected_hangar_ship_id != -1 else current_ship_id
		
		# v210.105: Validación de Slots Local (Anti-Crash)
		var ship_config = null
		for s in GameConstants.SHIP_MODELS:
			if s["id"] == viewing_id: ship_config = s; break
		
		if ship_config:
			var max_s = ship_config["slots"].get(it_type, 0)
			var current_e = []
			if viewing_id == current_ship_id: current_e = equipped_data.get(it_type, [])
			else: 
				var ship_e = equipped_by_ship.get(str(viewing_id), {})
				if ship_e: current_e = ship_e.get(it_type, [])
			
			if current_e.size() >= max_s:
				_show_result_modal("CHASIS LLENO", "Esta nave no tiene más slots de tipo " + it_type.to_upper())
				return

		print("[HANGAR] Equipando item en nave ID: ", viewing_id)
		NetworkManager.send_event("equipItem", {
			"category": it_type, 
			"instanceId": it.get("instanceId", ""),
			"shipId": viewing_id
		})
	)
	hb.add_child(b); parent.add_child(p)

# --- ESFERAS ---
func _update_spheres_ui():
	var root_tab = get_node_or_null("Window/TabContainer/Esferas")
	if not root_tab: return
	for n in root_tab.get_children(): n.queue_free()
	
	# v201.5: Creación de Sub-Pestañas para Esferas
	var sub_tabs = TabContainer.new()
	sub_tabs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_tab.add_child(sub_tabs)
	
	var eq_tab = Control.new(); eq_tab.name = "SISTEMA ORBITAL"; sub_tabs.add_child(eq_tab)
	var lib_tab = Control.new(); lib_tab.name = "BIBLIOTECA DE HABILIDADES"; sub_tabs.add_child(lib_tab)
	
	_render_spheres_equipment(eq_tab, sub_tabs)
	_render_spheres_library(lib_tab)

func _render_spheres_equipment(tab, sub_tabs):
	var master_v = VBoxContainer.new(); master_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); master_v.offset_top = 20; tab.add_child(master_v)
	
	var spheres_h = HBoxContainer.new(); spheres_h.alignment = BoxContainer.ALIGNMENT_CENTER; spheres_h.add_theme_constant_override("separation", 60); master_v.add_child(spheres_h)
	
	spheres_manager = null

	var p = get_tree().get_first_node_in_group("player")
	if is_instance_valid(p): spheres_manager = p.get_node_or_null("SpheresManager")
	
	if not is_instance_valid(spheres_manager):
		var err = Label.new(); err.text = "SISTEMA ORBITAL NO INICIALIZADO"; err.horizontal_alignment = 1; master_v.add_child(err)
		return

	for i in range(4):
		if i >= spheres_manager.spheres_data.size(): break
		var s_data = spheres_manager.spheres_data[i]
		# v205.20: Saneamiento de Color HÍBRIDO (CSV + HEX)
		var s_color = s_data["color"]
		if typeof(s_color) == TYPE_STRING:
			var c_str = s_color.replace("(","").replace(")","").replace(" ","")
			if "," in c_str:
				var parts = c_str.split(",")
				if parts.size() >= 3:
					var r_val = float(parts[0]); var g_val = float(parts[1]); var b_val = float(parts[2])
					var a_val = float(parts[3]) if parts.size() > 3 else 1.0
					s_color = Color(r_val, g_val, b_val, a_val)
			else:
				# Soporte para Hexadecimal (#ffffff)
				s_color = Color(c_str)
		var v_box = VBoxContainer.new(); spheres_h.add_child(v_box)
		
		var s_label = Label.new(); s_label.text = s_data["name"]; s_label.horizontal_alignment = 1; s_label.modulate = s_color; v_box.add_child(s_label)
		
		var p_ui = PanelContainer.new(); p_ui.custom_minimum_size = Vector2(140, 140); v_box.add_child(p_ui)
		p_ui.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; p_ui.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var sb = StyleBoxFlat.new(); sb.bg_color = Color(0,0,0,0.6); sb.border_width_left = 3; sb.border_width_right = 3; sb.border_width_top = 3; sb.border_width_bottom = 3; sb.border_color = s_color; sb.corner_radius_top_left = 70; sb.corner_radius_top_right = 70; sb.corner_radius_bottom_left = 70; sb.corner_radius_bottom_right = 70; p_ui.add_theme_stylebox_override("panel", sb)
		
		# Efecto de brillo interior para esferas vacías
		if not s_data["equipped"]:
			sb.bg_color = s_color; sb.bg_color.a = 0.05
		
		var equipped = s_data["equipped"]
		var center = CenterContainer.new(); p_ui.add_child(center)
		var info_v = VBoxContainer.new(); center.add_child(info_v)
		
		var s_name = "VACÍO"
		if equipped:
			# v206.10: Filtro ANTI-BASURA (Bloquea punteros RESOURCE del servidor)
			var eq_str = str(equipped)
			if eq_str.begins_with("():<RE"): 
				s_name = "VACÍO"
				equipped = null # Forzar reset local para visual limpia
			elif typeof(equipped) == TYPE_DICTIONARY: 
				s_name = str(equipped.get("skill_name", "SKILL"))
			elif "skill_name" in equipped: 
				s_name = str(equipped.skill_name)
			else: 
				s_name = eq_str
		
		var name_lbl = Label.new()
		name_lbl.text = s_name.to_upper()
		name_lbl.horizontal_alignment = 1; name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.modulate.a = 1.0 if equipped else 0.3
		info_v.add_child(name_lbl)
		
		if equipped:
			var p_val = 0
			if typeof(equipped) == TYPE_DICTIONARY: p_val = equipped.get("power_value", 0)
			elif "power_value" in equipped: p_val = equipped.power_value
			var pwr = Label.new(); pwr.text = "POT: " + str(p_val); pwr.add_theme_font_size_override("font_size", 9); pwr.modulate = s_color; pwr.horizontal_alignment = 1; info_v.add_child(pwr)
		
		var type_txt = s_data["type"]
		var final_color = Color.SLATE_GRAY
		if equipped:
			final_color = s_color
			var raw_type = "Ataque"
			if typeof(equipped) == TYPE_DICTIONARY: raw_type = equipped.get("type", "Ataque")
			else: raw_type = equipped.get("type") if equipped.get("type") else "Ataque"
			type_txt = str(raw_type).to_upper()

			# Mapeo visual de colores para los slots equipados
			if type_txt == "ATAQUE": final_color = Color.RED
			elif type_txt == "DEFENSA": final_color = Color.AQUA
			elif type_txt == "CURACIÓN" or type_txt == "CURACION": final_color = Color.GREEN
			elif type_txt == "MOVIMIENTO": final_color = Color.YELLOW
		else:
			type_txt = "NINGUNO"

		
		# Aplicar color al borde del slot
		sb.border_color = final_color
		if not equipped: sb.bg_color = Color.DIM_GRAY; sb.bg_color.a = 0.1

		
		var type_label = Label.new(); type_label.text = type_txt; type_label.modulate = final_color; type_label.horizontal_alignment = 1; type_label.add_theme_font_size_override("font_size", 9); v_box.add_child(type_label)
		var b = Button.new(); b.text = "RECONFIGURAR" if equipped else "EQUIPAR NÚCLEO"; b.add_theme_font_size_override("font_size", 9); v_box.add_child(b)

		var idx = i
		b.pressed.connect(func(): 
			selected_sphere_slot = idx
			# Si está vacío, permitimos todos (ANY), si ya tiene tipo, filtramos por ese tipo
			selected_sphere_type_filter = "ANY"
			if equipped:
				selected_sphere_type_filter = type_txt
			
			if is_instance_valid(sub_tabs): 
				sub_tabs.current_tab = 1
		)

		
		# v214.200: Botón explícito para DESEQUIPAR (v214.201 Feedback Fix)
		if equipped:
			var bu = Button.new(); bu.text = "DESEQUIPAR"; bu.add_theme_font_size_override("font_size", 9); bu.modulate = Color(1, 0.4, 0.4); v_box.add_child(bu)
			bu.pressed.connect(func(): 
				if NetworkManager: 
					# v214.202: Feedback visual instantáneo para UX premium
					if is_instance_valid(spheres_manager):
						spheres_manager.spheres_data[i]["equipped"] = null
						spheres_manager._update_visuals()
					
					NetworkManager.send_event("unequipSphere", {"sphereId": i})
					
					# Refrescar la pestaña actual después de un breve delay
					await get_tree().create_timer(0.1).timeout
					_update_spheres_ui()
			)

func _render_spheres_library(tab):
	var main_v = VBoxContainer.new(); main_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); main_v.offset_left = 20; main_v.offset_right = -20; main_v.offset_top = 20; tab.add_child(main_v)
	
	# v235.65: Barra de Filtros de Color
	var filter_h = HBoxContainer.new(); filter_h.alignment = BoxContainer.ALIGNMENT_CENTER; filter_h.add_theme_constant_override("separation", 15); main_v.add_child(filter_h)
	var filters = ["ANY", "ATAQUE", "DEFENSA", "CURACIÓN", "MOVIMIENTO"]
	for f in filters:
		var fb = Button.new(); fb.text = " " + f + " "; fb.flat = (selected_sphere_type_filter != f)
		fb.add_theme_font_size_override("font_size", 10)
		if f == "ATAQUE": fb.modulate = Color.RED
		elif f == "DEFENSA": fb.modulate = Color.AQUA
		elif f == "CURACIÓN": fb.modulate = Color.GREEN
		elif f == "MOVIMIENTO": fb.modulate = Color.YELLOW
		fb.pressed.connect(func(): selected_sphere_type_filter = f; _update_spheres_ui())
		filter_h.add_child(fb)
	
	main_v.add_child(HSeparator.new())
	
	var scroll = ScrollContainer.new(); scroll.size_flags_vertical = 3; main_v.add_child(scroll)
	var grid = GridContainer.new(); grid.columns = 2; grid.size_flags_horizontal = 3; grid.add_theme_constant_override("h_separation", 20); grid.add_theme_constant_override("v_separation", 20); scroll.add_child(grid)
	
	# v235.66: Catálogo de Habilidades Expandido (2 por color)
	var all_skills = [
		{"class": Skill_TurboImpulse, "color": Color.YELLOW, "icon": "⚡", "type": "MOVIMIENTO"},
		{"class": Skill_HyperDash, "color": Color.YELLOW, "icon": "💨", "type": "MOVIMIENTO"},
		
		{"class": Skill_ShieldCell, "color": Color.AQUA, "icon": "🛡️", "type": "DEFENSA"},
		{"class": Skill_Fortress, "color": Color.AQUA, "icon": "🏰", "type": "DEFENSA"},
		
		{"class": Skill_RepairKit, "color": Color.GREEN, "icon": "🔧", "type": "CURACIÓN"},
		{"class": Skill_RegenPath, "color": Color.GREEN, "icon": "🧪", "type": "CURACIÓN"},
		
		{"class": Skill_Reflect, "color": Color.RED, "icon": "🛡️", "type": "ATAQUE"},
		{"class": Skill_PlasmaBlast, "color": Color.RED, "icon": "💥", "type": "ATAQUE"}
	]
	
	# v235.75: Recolectar lista de habilidades ya equipadas (Evitar duplicados)
	var currently_equipped = []
	if is_instance_valid(spheres_manager):
		for s in spheres_manager.spheres_data:
			var eq = s.get("equipped")
			if eq:
				var e_name = eq.get("skill_name", "") if typeof(eq) == TYPE_DICTIONARY else eq.get("skill_name")
				currently_equipped.append(e_name)

	for s_info in all_skills:
		# Aplicar filtro si no es ANY
		if selected_sphere_type_filter != "ANY" and s_info["type"] != selected_sphere_type_filter:
			continue
			
		var s_inst = s_info["class"].new()
		var is_already_on = s_inst.skill_name in currently_equipped
		_create_skill_card(s_inst, s_info["color"], s_info["icon"], grid, is_already_on)

func _create_skill_card(skill: SphereSkill, color: Color, icon_text: String, parent: Control, is_equipped: bool = false):

	var skill_card = PanelContainer.new()
	skill_card.custom_minimum_size = Vector2(350, 120)
	parent.add_child(skill_card)
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0.05, 0.7)
	sb.border_width_left = 4
	sb.border_color = color
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_right = 8
	skill_card.add_theme_stylebox_override("panel", sb)
	
	var hb = HBoxContainer.new()
	hb.offset_left = 15
	skill_card.add_child(hb)
	
	# Icono Placeholder
	var icon_box = CenterContainer.new()
	icon_box.custom_minimum_size = Vector2(60, 0)
	hb.add_child(icon_box)
	var ico = Label.new()
	ico.text = icon_text
	ico.add_theme_font_size_override("font_size", 30)
	ico.modulate = color
	icon_box.add_child(ico)
	
	var v_info = VBoxContainer.new()
	v_info.size_flags_horizontal = 3
	v_info.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(v_info)
	
	var name_l = Label.new()
	name_l.text = skill.skill_name
	name_l.add_theme_font_size_override("font_size", 14)
	name_l.modulate = color
	v_info.add_child(name_l)
	
	var desc_l = Label.new()
	desc_l.text = skill.description
	desc_l.add_theme_font_size_override("font_size", 10)
	desc_l.modulate.a = 0.6
	desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v_info.add_child(desc_l)
	
	var stats_h = HBoxContainer.new()
	stats_h.add_theme_constant_override("separation", 15)
	v_info.add_child(stats_h)
	
	var stat_p = Label.new()
	stat_p.text = "POTENCIA: " + str(skill.power_value)
	stat_p.add_theme_font_size_override("font_size", 9)
	stat_p.modulate = color
	stats_h.add_child(stat_p)
	
	var stat_c = Label.new()
	stat_c.text = "CD: " + str(skill.cooldown) + "s"
	stat_c.add_theme_font_size_override("font_size", 9)
	stat_c.modulate.a = 0.5
	stats_h.add_child(stat_c)
	
	var b_equip = Button.new()
	b_equip.text = "YA EQUIPADA" if is_equipped else "EQUIPAR"
	b_equip.disabled = is_equipped
	b_equip.custom_minimum_size = Vector2(80, 0)
	b_equip.size_flags_vertical = 4
	hb.add_child(b_equip)
	
	if is_equipped:
		skill_card.modulate.a = 0.5
	
	b_equip.pressed.connect(func():

		var p_node = get_tree().get_first_node_in_group("player")
		if p_node and p_node.has_node("SpheresManager"):
			var sm = p_node.get_node("SpheresManager")
			
			# v235.68: Usar el slot seleccionado o buscar el primero libre si es ANY
			var target_idx = selected_sphere_slot
			if target_idx == -1:
				for i in range(4):
					if sm.spheres_data[i]["equipped"] == null:
						target_idx = i; break
			
			if target_idx != -1:
				NetworkManager.send_event("equipSphere", {
					"sphereId": target_idx,
					"skill": {
						"skill_name": skill.skill_name,
						"power_value": skill.power_value,
						"type": skill.type
					}
				})
				
				# Update local visual (feedback inmediato)
				sm.equip_item(target_idx, skill)
				_update_spheres_ui()
				print("[SPHERES] Equipando en slot ", target_idx, ": ", skill.skill_name)
	)


# --- SHOP ---
func _update_shop_ui():
	var h = get_node_or_null("Window/TabContainer/Tienda")
	if not h: return
	for n in h.get_children(): n.queue_free()
	
	var main_v = VBoxContainer.new(); main_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); h.add_child(main_v)
	var bar = HBoxContainer.new(); bar.add_theme_constant_override("separation", 15); main_v.add_child(bar)
	var lbats = {"ships": "NAVES", "weapons": "ARMAS", "shields": "ESCUDOS", "engines": "MOTORES", "ammo": "MUNICIONES", "extras": "EXTRAS"}
	for k in lbats:
		var b = Button.new(); b.text = lbats[k]; b.flat = true; b.modulate = Color.CYAN if shop_tab == k else Color.WHITE
		b.pressed.connect(func(): shop_tab = k; _update_shop_ui())
		bar.add_child(b)
	
	var s_lbl = Label.new(); s_lbl.text = "\n" + lbats[shop_tab] + " (MERCADO INTERESTELAR)\n"; s_lbl.add_theme_font_size_override("font_size", 12); main_v.add_child(s_lbl)
	var scr = ScrollContainer.new(); scr.size_flags_vertical = 3; main_v.add_child(scr)
	var grid = GridContainer.new(); grid.columns = 3; grid.size_flags_horizontal = 3; grid.add_theme_constant_override("h_separation", 20); grid.add_theme_constant_override("v_separation", 20); scr.add_child(grid)
	
	if shop_tab == "ships":
		for ship in GameConstants.SHIP_MODELS: _create_shop_card(ship, "ships", grid)
	elif shop_tab == "ammo":
		_render_ammo_shop(main_v, grid)
	else:
		var items = GameConstants.SHOP_ITEMS.get(shop_tab, [])
		for it in items: _create_shop_card(it, shop_tab, grid)

func _create_shop_card(it, cat, parent):
	var p = PanelContainer.new(); p.custom_minimum_size = Vector2(280, 110)
	var sb = StyleBoxFlat.new(); sb.bg_color = Color(0,0.02,0.1, 0.4); sb.border_width_top = 1; sb.border_color = Color(0,1,1,0.1); p.add_theme_stylebox_override("panel", sb)
	var v = VBoxContainer.new(); v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); v.offset_left = 10; v.offset_right = -10; p.add_child(v)
	
	var n = Label.new(); n.text = it["name"].to_upper(); n.horizontal_alignment = 1; n.add_theme_font_size_override("font_size", 11); v.add_child(n)
	var d = Label.new(); d.text = it.get("desc", ""); d.horizontal_alignment = 1; d.modulate.a = 0.5; d.add_theme_font_size_override("font_size", 8); v.add_child(d)
	
	var is_owned = (cat == "ships" and owned_ships.has(it["id"]))
	if is_owned:
		var l = Label.new(); l.text = "\nNAVE ADQUIRIDA"; l.modulate = Color.GREEN; l.horizontal_alignment = 1; v.add_child(l)
	else:
		var pr = it["prices"]
		if pr["hubs"] > 0:
			var b1 = Button.new(); b1.text = _format_val(pr["hubs"]) + " HUBS"; v.add_child(b1)
			b1.pressed.connect(func(): _buy_request(cat, it, "hubs"))
		if pr["ohcu"] > 0:
			var b2 = Button.new(); b2.text = _format_val(pr["ohcu"]) + " OHCU"; v.add_child(b2)
			b2.pressed.connect(func(): _buy_request(cat, it, "ohcu"))
	parent.add_child(p)

func _render_ammo_shop(parent, grid):
	var bar = HBoxContainer.new(); bar.add_theme_constant_override("separation", 10); parent.add_child(bar); parent.move_child(bar, 2)
	for t in ["laser", "missile", "mine"]:
		var b = Button.new(); b.text = t.to_upper(); b.flat = true; b.modulate = Color.GOLD if ammo_sub_tab == t else Color.WHITE
		b.pressed.connect(func(): ammo_sub_tab = t; _update_shop_ui())
		bar.add_child(b)
	var ammo_base = GameConstants.SHOP_ITEMS.get("ammo", {})
	var items = ammo_base.get(ammo_sub_tab, [])
	for it in items: _create_shop_card(it, "ammo", grid)

func _buy_request(cat, it, cur):
	var price = it["prices"][cur]; var wallet = hubs if cur == "hubs" else ohcu
	if wallet < price: 
		_show_result_modal("FONDOS INSUFICIENTES", "No tienes suficientes " + cur.to_upper() + " para esta operación.")
		return
	
	if cat == "ammo":
		_show_ammo_modal(it, cur)
		return

	var msg = "¿Deseas adquirir [color=cyan]" + it["name"] + "[/color] por [color=yellow]" + _format_val(price) + " " + cur.to_upper() + "[/color]?"
	_show_modal("CONFIRMAR ADQUISICIÓN", msg, func():
		NetworkManager.send_event("buyItem", {"category": cat, "itemId": it["id"], "currency": cur})
		_show_result_modal("¡COMPRA EXITOSA!", "El ítem " + it["name"] + " ha sido enviado a tu bodega.")
	)

func _show_ammo_modal(it, cur):
	var unit_price = it["prices"][cur]
	var dial_v = VBoxContainer.new()
	var lq = Label.new(); lq.text = "CANTIDAD DE RECARGA:"; lq.horizontal_alignment = 1; dial_v.add_child(lq)
	var slider = HSlider.new(); slider.min_value = 100; slider.max_value = 50000; slider.step = 100; slider.value = 1000; dial_v.add_child(slider)
	var total_lbl = Label.new(); total_lbl.text = "1.000 unidades = " + _format_val(unit_price * 10) + " " + cur.to_upper(); total_lbl.horizontal_alignment = 1; dial_v.add_child(total_lbl)
	slider.value_changed.connect(func(v): total_lbl.text = _format_val(v) + " unidades = " + _format_val(v * (unit_price/100.0)) + " " + cur.to_upper())
	
	_show_modal("SUMINISTROS TÁCTICOS", "Ajusta la cantidad de [color=cyan]" + it["name"] + "[/color] a comprar:", func():
		var qty = int(slider.value)
		var total = int(qty * (unit_price/100.0))
		if (hubs if cur == "hubs" else ohcu) >= total:
			NetworkManager.send_event("buyItem", {"category": "ammo", "itemId": it["id"], "currency": cur, "amount": qty})
			_show_result_modal("SUMINISTROS RECIBIDOS", "Se han acreditado " + _format_val(qty) + " unidades.")
		else:
			_show_result_modal("ERROR", "No tienes fondos para esta cantidad.")
	, dial_v)

func _show_modal(title, msg, on_confirm, custom_node = null):
	modal_active = true
	# v227.60: CENTRADO MATEMÁTICO (Forzar tamaño al Viewport)
	var overlay = ColorRect.new()
	overlay.color = Color(0,0,0,0.85)
	overlay.top_level = true
	overlay.z_index = 1000
	add_child(overlay)
	
	# v227.61: Sincronizar tamaño con la pantalla real
	overlay.size = get_viewport_rect().size
	overlay.global_position = Vector2.ZERO
	
	var p = PanelContainer.new(); p.custom_minimum_size = Vector2(420, 220); p.set_anchors_and_offsets_preset(Control.PRESET_CENTER); overlay.add_child(p)
	var sb = StyleBoxFlat.new(); sb.bg_color = Color(0.01, 0.04, 0.08, 1); sb.border_width_top = 3; sb.border_color = Color.CYAN; p.add_theme_stylebox_override("panel", sb)
	var v = VBoxContainer.new(); v.add_theme_constant_override("separation", 20); p.add_child(v)
	
	var tl = Label.new(); tl.text = title; tl.horizontal_alignment = 1; tl.modulate = Color.CYAN; tl.add_theme_font_size_override("font_size", 14); v.add_child(tl)
	var rt = RichTextLabel.new(); rt.bbcode_enabled = true; rt.text = "[center]" + msg + "[/center]"; rt.fit_content = true; v.add_child(rt)
	
	if custom_node: v.add_child(custom_node)
	
	var hb = HBoxContainer.new(); hb.alignment = BoxContainer.ALIGNMENT_CENTER; hb.add_theme_constant_override("separation", 20); v.add_child(hb)
	var bc = Button.new(); bc.text = "  CONFIRMAR  "; bc.custom_minimum_size = Vector2(120, 40); bc.pressed.connect(func(): on_confirm.call(); overlay.queue_free(); modal_active = false); hb.add_child(bc)
	var bx = Button.new(); bx.text = "   CANCELAR   "; bx.custom_minimum_size = Vector2(120, 40); bx.pressed.connect(func(): overlay.queue_free(); modal_active = false); hb.add_child(bx)

func _show_result_modal(title, msg):
	var overlay = ColorRect.new()
	overlay.color = Color(0,0,0,0.85)
	overlay.top_level = true
	overlay.z_index = 1001
	add_child(overlay)
	
	overlay.size = get_viewport_rect().size
	overlay.global_position = Vector2.ZERO
	
	var p = PanelContainer.new(); p.custom_minimum_size = Vector2(380, 160); p.set_anchors_and_offsets_preset(Control.PRESET_CENTER); overlay.add_child(p)
	var sb = StyleBoxFlat.new(); sb.bg_color = Color(0,0.08,0.04, 1); sb.border_width_top = 2; sb.border_color = Color.GREEN; p.add_theme_stylebox_override("panel", sb)
	var v = VBoxContainer.new(); v.add_theme_constant_override("separation", 15); p.add_child(v); var tl = Label.new(); tl.text = title; tl.modulate = Color.GREEN; tl.horizontal_alignment = 1; v.add_child(tl)
	var m = Label.new(); m.text = msg; m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; m.horizontal_alignment = 1; v.add_child(m)
	var b = Button.new(); b.text = "ENTENDIDO"; b.custom_minimum_size = Vector2(100, 35); b.pressed.connect(func(): overlay.queue_free()); v.add_child(b)

# --- TALENTS ---
func _update_talent_tree():
	if not visible: return
	var tab = get_node_or_null("Window/TabContainer/Talentos")
	if not tab: return
	if not is_instance_valid(talent_system): 
		talent_system = get_tree().get_first_node_in_group("talent_system")
		if not talent_system: return
		
	for n in tab.get_children(): n.queue_free()
	
	var master_v = VBoxContainer.new(); master_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); tab.add_child(master_v)
	var hb = HBoxContainer.new(); master_v.add_child(hb)
	var pts = Label.new(); pts.text = "PUNTOS DISPONIBLES: " + str(int(talent_system.skill_points)); pts.modulate = Color.GREEN; hb.add_child(pts)
	var rb = Button.new()
	rb.text = "RESETEAR ARBOL (5.000 OHCU)"
	rb.size_flags_horizontal = 3
	rb.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rb.pressed.connect(func(): 
		var m = "¿Confirmas el reseteo total de habilidades?\nCosto: [color=yellow]5.000 OHCU[/color]"
		_show_modal("CONFIRMAR RESET", m, func(): talent_system.reset_talents())
	)
	hb.add_child(rb)

	
	var main_scroll = ScrollContainer.new(); main_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; master_v.add_child(main_scroll)
	var grid = HBoxContainer.new(); grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL; grid.size_flags_vertical = Control.SIZE_EXPAND_FILL; main_scroll.add_child(grid)
	grid.add_theme_constant_override("separation", 25)

	var cats = {"engineering": "INGENIERÍA", "combat": "COMBATE", "science": "CIENCIA"}
	for ck in cats:
		var v = VBoxContainer.new(); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; grid.add_child(v)
		var l = Label.new(); l.text = cats[ck]; l.horizontal_alignment = 1; l.modulate = Color.CYAN if ck == "engineering" else (Color.RED if ck == "combat" else Color.PURPLE)
		l.add_theme_font_size_override("font_size", 14); v.add_child(l)
		
		var li = VBoxContainer.new(); v.add_child(li); li.add_theme_constant_override("separation", 10)
		var branch = talent_system.skill_tree.get(ck, [0,0,0,0,0,0,0,0])
		var skills = SKILL_DATA.filter(func(x): return x.cat == ck)
		for i in range(skills.size()):
			var s = skills[i]; var lvl = branch[i] if i < branch.size() else 0
			var node_p = PanelContainer.new(); li.add_child(node_p)
			node_p.size_flags_horizontal = Control.SIZE_EXPAND_FILL; node_p.custom_minimum_size = Vector2(0, 75)
			
			var sb = StyleBoxFlat.new(); sb.bg_color = Color(1,1,1,0.03); sb.set_border_width_all(1); sb.border_color = Color(1,1,1,0.1)
			if lvl > 0: sb.border_color = Color.CYAN if ck == "engineering" else (Color.RED if ck == "combat" else Color.PURPLE)
			node_p.add_theme_stylebox_override("panel", sb)
			
			var item_v = VBoxContainer.new(); node_p.add_child(item_v); item_v.add_theme_constant_override("separation", 4); item_v.alignment = BoxContainer.ALIGNMENT_CENTER
			var l_name = Label.new(); l_name.text = s.name.to_upper(); l_name.add_theme_font_size_override("font_size", 12); l_name.modulate = Color.WHITE; item_v.add_child(l_name)
			var l_desc = Label.new(); l_desc.text = s.desc; l_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l_desc.add_theme_font_size_override("font_size", 10); l_desc.modulate = Color(0.8, 0.8, 0.8); item_v.add_child(l_desc)
			
			var bar_h = HBoxContainer.new(); item_v.add_child(bar_h); bar_h.add_theme_constant_override("separation", 5)
			for b_idx in range(5):
				var bar = ColorRect.new(); bar.custom_minimum_size = Vector2(25, 6); bar_h.add_child(bar)
				var val = lvl
				bar.color = Color.GOLD if b_idx < val else Color(0.2, 0.2, 0.2, 0.5)
			
			var b_click = Button.new(); b_click.flat = true; node_p.add_child(b_click)
			b_click.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			b_click.pressed.connect(func(): talent_system.invest_point(ck, i))


# --- EQUIPO (PARTY) ---
func _update_party_ui():
	if not visible: return # Ahorrar recursos si el Hangar está cerrado
	
	var tab = get_node_or_null("Window/TabContainer/Equipo")
	if not tab: return
	for n in tab.get_children(): n.queue_free()
	
	var master_h = HBoxContainer.new(); master_h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); master_h.add_theme_constant_override("separation", 30); tab.add_child(master_h)
	
	# Columna Izquierda: Miembros del Grupo
	var l_col = VBoxContainer.new(); l_col.size_flags_horizontal = 3; master_h.add_child(l_col)
	var l_title = Label.new(); l_title.text = "MIEMBROS DEL ESCUADRÓN"; l_title.modulate = Color.CYAN; l_title.add_theme_font_size_override("font_size", 11); l_col.add_child(l_title)
	
	var p_scroll = ScrollContainer.new(); p_scroll.size_flags_vertical = 3; l_col.add_child(p_scroll)
	var p_list = VBoxContainer.new(); p_list.size_flags_horizontal = 3; p_scroll.add_child(p_list)
	
	var data = PartyManager.current_party
	if data:
		var members = data.get("members", [])
		var names = data.get("names", [])
		for i in range(members.size()):
			var hb = HBoxContainer.new(); hb.custom_minimum_size = Vector2(0, 40)
			var sb = StyleBoxFlat.new(); sb.bg_color = Color(0,1,1,0.05); sb.border_width_left = 2; sb.border_color = Color.CYAN if i == 0 else Color.WHITE
			var pc = PanelContainer.new(); pc.add_theme_stylebox_override("panel", sb); pc.size_flags_horizontal = 3; hb.add_child(pc)
			
			var name_lbl = Label.new(); name_lbl.text = ("Lider: " if i == 0 else "Piloto: ") + str(names[i]); pc.add_child(name_lbl)
			p_list.add_child(hb)
		
		var leave_btn = Button.new(); leave_btn.text = "ABANDONAR GRUPO"; leave_btn.modulate = Color.RED
		leave_btn.pressed.connect(func(): PartyManager.leave_party())
		l_col.add_child(leave_btn)
	else:
		var no_party = Label.new(); no_party.text = "\nNo perteneces a ningún escuadrón."; no_party.modulate.a = 0.4; p_list.add_child(no_party)

	# Columna Derecha: Jugadores Cercanos
	var r_col = VBoxContainer.new()
	r_col.size_flags_horizontal = 3
	master_h.add_child(r_col)
	
	var r_title = Label.new()
	r_title.text = "PILOTOS EN LA ZONA"
	r_title.modulate = Color.GOLD
	r_title.add_theme_font_size_override("font_size", 11)
	r_col.add_child(r_title)
	
	var n_scroll = ScrollContainer.new()
	n_scroll.size_flags_vertical = 3
	r_col.add_child(n_scroll)
	
	var n_list = VBoxContainer.new()
	n_list.size_flags_horizontal = 3
	n_scroll.add_child(n_list)
	
	var world_node = get_tree().get_first_node_in_group("world_node")
	if is_instance_valid(world_node):
		var players = world_node.remote_players
		if players.is_empty():
			var lbl = Label.new()
			lbl.text = "\nNo hay otros pilotos cerca."
			lbl.modulate.a = 0.3
			n_list.add_child(lbl)
		else:
			for id in players:
				var p = players[id]
				if not is_instance_valid(p): continue
				var hb = HBoxContainer.new()
				var nl = Label.new()
				nl.text = p.username if "username" in p else "Piloto"
				nl.size_flags_horizontal = 3
				var ib = Button.new()
				ib.text = "INVITAR"
				ib.add_theme_font_size_override("font_size", 10)
				ib.pressed.connect(func(): PartyManager.invite_player(nl.text))
				hb.add_child(nl)
				hb.add_child(ib)
				n_list.add_child(hb)

	# Seccion de Invitacion Manual
	var inv_h = HBoxContainer.new()
	r_col.add_child(inv_h)
	var inp = LineEdit.new()
	inp.placeholder_text = "Buscar por nombre..."
	inp.size_flags_horizontal = 3
	inv_h.add_child(inp)
	var btn = Button.new()
	btn.text = "INVITAR"
	inv_h.add_child(btn)
	btn.pressed.connect(func(): 
		if inp.text != "": 
			PartyManager.invite_player(inp.text)
			inp.text = ""
	)

# --- MAPA GALÁCTICO ---
func _update_map_ui():
	var tabs = get_node_or_null("Window/TabContainer")
	if not tabs: return
	
	var tab = tabs.get_node_or_null("Mapa")
	if not tab:
		tab = Control.new()
		tab.name = "Mapa"
		tabs.add_child(tab)
	
	for n in tab.get_children(): n.queue_free()
	
	var master_h = HBoxContainer.new(); master_h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); master_h.add_theme_constant_override("separation", 20); tab.add_child(master_h)
	
	# Columna Izquierda: Lista de Sectores
	var l_col = VBoxContainer.new(); l_col.custom_minimum_size.x = 220; master_h.add_child(l_col)
	var l_title = Label.new(); l_title.text = "SECTORES CONOCIDOS"; l_title.modulate = Color.CYAN; l_title.add_theme_font_size_override("font_size", 11); l_col.add_child(l_title)
	
	var s_scroll = ScrollContainer.new(); s_scroll.size_flags_vertical = 3; l_col.add_child(s_scroll)
	var s_list = VBoxContainer.new(); s_list.size_flags_horizontal = 3; s_scroll.add_child(s_list)
	
	var sectors = [
		{"id": 1, "name": "MAPA 1", "desc": "Sector de inicio y entrenamiento.", "status": "SEGURO", "color": Color.CYAN},
		{"id": 2, "name": "MAPA 2", "desc": "Zona de exploración profunda.", "status": "EXPLORACIÓN", "color": Color.GOLD},
		{"id": 3, "name": "MAPA 3", "desc": "Sector de anomalías espaciales.", "status": "PELIGRO", "color": Color.ORANGE},
		{"id": 4, "name": "MAPA 4", "desc": "Antigua base de suministros.", "status": "SEGURO", "color": Color.CYAN},
		{"id": 5, "name": "MAPA 5", "desc": "Cinturón de radiación estelar.", "status": "PELIGRO", "color": Color.RED},
		{"id": 6, "name": "MAPA 6", "desc": "Sistemas de defensa remotos.", "status": "EXPLORACIÓN", "color": Color.SKY_BLUE},
		{"id": 7, "name": "MAPA 7", "desc": "Vacío intergaláctico.", "status": "DESCONOCIDO", "color": Color.MAGENTA},
		{"id": 8, "name": "MAPA 8", "desc": "Confines del universo conocido.", "status": "LEY SIN LEY", "color": Color.SILVER}
	]
	
	# Detectar zona actual del jugador
	var current_zone_id = 1
	var p_node = get_tree().get_first_node_in_group("player")
	if is_instance_valid(p_node) and "current_zone" in p_node:
		current_zone_id = p_node.current_zone
	
	var current_zone_name = "MAPA 1"

	for s in sectors:
		var is_current = (s.id == current_zone_id)
		if is_current: current_zone_name = s.name

		var p = PanelContainer.new(); p.custom_minimum_size = Vector2(0, 65); s_list.add_child(p)
		
		# v216.10: Estilo dinámico para resaltar sector actual
		var sb = StyleBoxFlat.new()
		if is_current:
			sb.bg_color = Color(1, 0.8, 0, 0.15) # Fondo dorado suave
			sb.border_width_left = 5
			sb.border_color = Color.GOLD
			sb.shadow_color = Color(1, 0.8, 0, 0.2)
			sb.shadow_size = 4
		else:
			sb.bg_color = Color(0,1,1,0.05)
			sb.border_width_left = 3
			sb.border_color = s.color
			
		p.add_theme_stylebox_override("panel", sb)
		var hb = HBoxContainer.new(); p.add_child(hb)
		
		var v = VBoxContainer.new(); v.size_flags_horizontal = 3; hb.add_child(v); v.offset_left = 10; v.alignment = BoxContainer.ALIGNMENT_CENTER
		var n = Label.new(); n.text = s.name; n.add_theme_font_size_override("font_size", 11); v.add_child(n)
		if is_current: n.modulate = Color.GOLD # Resaltar texto también
		
		var st = Label.new(); st.text = "ESTÁS AQUÍ" if is_current else s.status
		st.modulate = Color.GOLD if is_current else s.color
		st.add_theme_font_size_override("font_size", 8); v.add_child(st)
		
		var btn_travel = Button.new()
		btn_travel.text = "VIAJAR\n(10 OHCU)"
		btn_travel.add_theme_font_size_override("font_size", 9)
		btn_travel.custom_minimum_size = Vector2(80, 0)
		btn_travel.disabled = is_current # No puedes viajar a donde ya estás
		hb.add_child(btn_travel)
		
		if not is_current:
			btn_travel.pressed.connect(func():
				if ohcu < 10:
					_show_result_modal("FONDOS INSUFICIENTES", "Necesitas 10 OHCU para saltar a este sector.")
					return
				
				var msg = "¿Confirmas salto hiperespacial a [color=cyan]" + s.name + "[/color]?\nCosto: [color=yellow]10 OHCU[/color]"
				_show_modal("CONFIRMAR SALTO", msg, func():
					NetworkManager.send_event("changeZone", s.id)
					# v227.20: Removido modal de éxito innecesario por petición de UX
					toggle()
				)
			)
	
	# Columna Derecha: El Mapa Interactivo
	var r_col = VBoxContainer.new(); r_col.size_flags_horizontal = 3; master_h.add_child(r_col)
	
	var map_container = PanelContainer.new(); map_container.size_flags_vertical = 3; r_col.add_child(map_container)
	var msb = StyleBoxFlat.new(); msb.bg_color = Color(0,0,0,0.8); msb.set_border_width_all(1); msb.border_color = Color(0,1,1,0.2); map_container.add_theme_stylebox_override("panel", msb)
	
	# Inyectar el script del Mapa Táctico como un componente visual
	var map_logic = Control.new()
	map_logic.name = "MapLogic"
	map_logic.size_flags_horizontal = 3
	map_logic.size_flags_vertical = 3
	
	# Usamos una versión simplificada de AdminMap para los usuarios
	map_logic.set_script(load("res://scripts/ui/AdminMap.gd"))
	map_logic.is_embedded = true # v215.40: Evitar creación de Header
	map_logic.r_pos = Vector2(0, 0)
	map_logic.r_margin = Vector2(5, 5)
	map_container.add_child(map_logic)
	
	# v215.12: Usar referencia directa para evitar errores de conversión de parámetros
	call_deferred("_setup_map_logic", current_zone_name)

func _setup_map_logic(zone_name = "MAPA 1"):
	var tabs = get_node_or_null("Window/TabContainer")
	if not tabs: return
	var tab = tabs.get_node_or_null("Mapa")
	if not tab: return
	
	# Búsqueda recursiva para encontrar el nodo entre los contenedores
	var logic_node = tab.find_child("MapLogic", true, false)
	
	if is_instance_valid(logic_node):
		logic_node.current_sector_name = zone_name # Actualizar nombre del sector
		logic_node.visible = true
		logic_node.custom_minimum_size = Vector2(400, 400)
		logic_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		logic_node.size_flags_vertical = Control.SIZE_EXPAND_FILL
		logic_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

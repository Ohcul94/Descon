extends Control

# Inventory.gd (Omni-Control v164.1 - Phoenix Absolute)
# Saneamiento total de diccionarios (Bracket Notation) + Exorcismo de Título.

var inventory_items = []
var owned_ships = []
var current_ship_id = 1
var equipped_data = {"w": [], "s": [], "e": [], "x": []}
var skill_tree = {"engineering": [0,0,0,0,0,0,0,0], "combat": [0,0,0,0,0,0,0,0], "science": [0,0,0,0,0,0,0,0]}
var skill_points = 0
var hubs = 0
var ohcu = 0
var is_open = false

var shop_tab = "ships"
var ammo_sub_tab = "laser"
var modal_active = false

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
	visible = false
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
	
	if PartyManager:
		PartyManager.party_updated.connect(func(_d): _update_party_ui())
	
	var tabs = get_node_or_null("Window/TabContainer")
	if tabs:
		tabs.offset_top = 40; tabs.offset_left = 15
		tabs.offset_right = -15; tabs.offset_bottom = -15
	
	# v164.2: Sincronía Táctica de Moneda (F2 -> F1 Sync)
	_connect_to_player_stats()
	
	# v164.94: Timer para refrescar pilotos cercanos (evita que la lista sea estática)
	var party_timer = Timer.new()
	party_timer.wait_time = 3.0
	party_timer.autostart = true
	party_timer.timeout.connect(_update_party_ui)
	add_child(party_timer)
	
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
	# Redibujar la cabecera del inventario
	queue_redraw()

func _draw():
	if not visible: return
	var sx = get_viewport_rect().size.x; var sy = get_viewport_rect().size.y
	var r_size = Vector2(940, 600); var r_pos = Vector2((sx - r_size.x)/2, (sy - r_size.y)/2)
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
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		toggle(); get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.pressed and visible:
		var r_pos = (get_viewport_rect().size - Vector2(940,600)) / 2
		var x_rect = Rect2(r_pos.x + 940 - 35, r_pos.y + 8, 25, 18)
		if x_rect.has_point(event.position): toggle(); get_viewport().set_input_as_handled()

func toggle():
	is_open = !is_open; visible = is_open
	if is_open: 
		_refresh_data()
		# v164.92: Asegurar que el Hangar esté siempre por encima del Chat y otros paneles
		get_parent().move_child(self, get_parent().get_child_count() - 1)
	queue_redraw()

func _refresh_data():
	if NetworkManager: NetworkManager.send_event("getInventory", {})

func _on_inventory_received(data: Dictionary):
	if data.has("player"): data = data.player
	inventory_items = data.get("inventory", data.get("items", []))
	equipped_data = data.get("equipped", equipped_data)
	skill_tree = data.get("skillTree", skill_tree)
	skill_points = data.get("skillPoints", 0)
	owned_ships = data.get("ownedShips", [])
	current_ship_id = data.get("currentShipId", 1)
	hubs = int(data.get("hubs", hubs))
	ohcu = int(data.get("ohcu", ohcu))
	
	# v164.11: Intentar sincronizar con el Player real si existe en escena
	var p = get_tree().get_first_node_in_group("player")
	if p:
		p.hubs = hubs
		p.ohculianos = ohcu
		p.inventory = inventory_items
		p.equipped = equipped_data
		if p.has_method("_recalculate_stats"): p._recalculate_stats()
		elif p.has_method("_emit_stats"): p._emit_stats()

	_update_hangar_ui()
	_update_talent_tree()
	_update_shop_ui()
	_update_party_ui()

# --- HANGAR ---
func _update_hangar_ui():
	var h = get_node_or_null("Window/TabContainer/Hangar")
	if not h: return
	for n in h.get_children(): n.queue_free()
	
	var m = HBoxContainer.new(); m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); m.add_theme_constant_override("separation", 25); h.add_child(m)
	var l_col = VBoxContainer.new(); l_col.size_flags_horizontal = 3; l_col.size_flags_stretch_ratio = 2.4; m.add_child(l_col)
	
	var f_lbl = Label.new(); f_lbl.text = "FLOTA DE COMBATE"; f_lbl.modulate = Color.CYAN; f_lbl.add_theme_font_size_override("font_size", 11); l_col.add_child(f_lbl)
	var f_grid = HBoxContainer.new(); f_grid.add_theme_constant_override("separation", 10); l_col.add_child(f_grid)
	for sid in owned_ships: _create_fleet_card(sid, f_grid)
	for i in range(owned_ships.size(), 2): _create_empty_fleet_card(f_grid)
	
	var model = {}
	for ship in GameConstants.SHIP_MODELS: 
		if ship["id"] == current_ship_id: 
			model = ship
			break
	
	if model.is_empty(): # Fallback fail-safe v164.4
		model = GameConstants.SHIP_MODELS[0]
	
	var h_box = HBoxContainer.new(); l_col.add_child(h_box)
	var name_txt = model.get("name", "Nave Desconocida").to_upper()
	var s_title = Label.new(); s_title.text = "\n" + name_txt; s_title.add_theme_font_size_override("font_size", 28); h_box.add_child(s_title)
	
	var slots = model.get("slots") if model.has("slots") else {"w":0, "s":0, "e":0, "x":0}
	var s_mini = Label.new(); s_mini.text = "W:" + str(slots.get("w", 0)) + " S:" + str(slots.get("s", 0)) + " E:" + str(slots.get("e", 0)); s_mini.modulate.a = 0.3; s_mini.size_flags_horizontal = 3; s_mini.horizontal_alignment = 2; h_box.add_child(s_mini)
	
	var slots_v = VBoxContainer.new(); slots_v.add_theme_constant_override("separation", 12); l_col.add_child(slots_v)
	_render_group(slots_v, "w", "BLOQUE DE ARMAMENTO", slots["w"])
	_render_group(slots_v, "s", "GENERADORES DE ESCUDO", slots["s"])
	_render_group(slots_v, "e", "SISTEMAS DE IMPULSIÓN", slots["e"])
	_render_group(slots_v, "x", "MÓDULOS EXTRAS / CPU", slots.get("x", 1))

	var r_col = VBoxContainer.new(); r_col.size_flags_horizontal = 3; r_col.size_flags_stretch_ratio = 1.0; m.add_child(r_col)
	var b_lbl = Label.new(); b_lbl.text = "INVENTARIO"; b_lbl.modulate = Color.CYAN; b_lbl.add_theme_font_size_override("font_size", 11); r_col.add_child(b_lbl)
	var b_vbox = VBoxContainer.new(); b_vbox.size_flags_horizontal = 3; r_col.add_child(b_vbox)
	
	# v164.10: Limpieza Absoluta del Contenedor antes de poblar
	for n in b_vbox.get_children(): n.queue_free()
	
	if inventory_items.is_empty(): 
		var no = Label.new(); no.text = "\nINVENTARIO VACÍO"; no.horizontal_alignment = 1; no.modulate.a = 0.2; b_vbox.add_child(no)
	else: 
		# Pequeña pausa para asegurar que queue_free procesó los nodos anteriores
		for item in inventory_items: _create_item_row(item, b_vbox)

func _create_fleet_card(sid, parent):
	var model = {}
	for m in GameConstants.SHIP_MODELS: 
		if m["id"] == sid: 
			model = m
			break
	if model.is_empty(): return # Anti-crash v164.4
	
	var p = PanelContainer.new(); p.custom_minimum_size = Vector2(140, 55)
	var sb = StyleBoxFlat.new(); sb.bg_color = Color(0, 1, 0, 0.05) if sid == current_ship_id else Color(0,0,0,0.5)
	sb.border_width_left = 1; sb.border_color = Color.GREEN if sid == current_ship_id else Color(1,1,1,0.1); p.add_theme_stylebox_override("panel", sb)
	var v = VBoxContainer.new(); p.add_child(v); var n = Label.new(); n.text = model["name"]; n.horizontal_alignment = 1; v.add_child(n)
	var st = Label.new(); st.text = "NAVE ACTIVA" if sid == current_ship_id else "EN HANGAR"; st.horizontal_alignment = 1; st.modulate = Color.GREEN if sid == current_ship_id else Color.WHITE; st.add_theme_font_size_override("font_size", 8); v.add_child(st)
	if sid != current_ship_id: p.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed: NetworkManager.send_event("switchShip", {"shipId": sid}))
	parent.add_child(p)

func _create_empty_fleet_card(parent):
	var p = PanelContainer.new(); p.custom_minimum_size = Vector2(140, 55); var sb = StyleBoxFlat.new(); sb.bg_color = Color(0,0,0,0.3); sb.border_width_left = 1; sb.border_color = Color(1,1,1,0.05); p.add_theme_stylebox_override("panel", sb)
	var v = VBoxContainer.new(); p.add_child(v); var n = Label.new(); n.text = "SLOT VACÍO"; n.horizontal_alignment = 1; v.add_child(n); parent.add_child(p)

func _render_group(parent, type, title, count):
	var l = Label.new(); l.text = title; l.modulate.a = 0.4; l.add_theme_font_size_override("font_size", 9); parent.add_child(l)
	var grid = GridContainer.new(); grid.columns = 10; parent.add_child(grid)
	var eq = equipped_data.get(type, [])
	for i in range(count):
		var p = PanelContainer.new(); p.custom_minimum_size = Vector2(40, 40); var sb = StyleBoxFlat.new(); sb.bg_color = Color(0,0,0,0.6); sb.border_width_left = 1; sb.border_color = Color(1,1,1,0.1); p.add_theme_stylebox_override("panel", sb)
		if i < eq.size():
			var it = Label.new(); it.text = "I"; it.horizontal_alignment = 1; p.add_child(it); sb.border_color = Color.CYAN
			p.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed: NetworkManager.send_event("unequipItem", {"category": type, "index": i}))
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
		print("[INVENTARIO] Intentando equipar: ", it.get("instanceId", "nan"), " de tipo: ", it_type)
		NetworkManager.send_event("equipItem", {"category": it_type, "instanceId": it.get("instanceId", "")})
	)
	hb.add_child(b); parent.add_child(p)

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
	var overlay = ColorRect.new(); overlay.color = Color(0,0,0,0.7); overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(overlay)
	var p = PanelContainer.new(); p.custom_minimum_size = Vector2(400, 200); p.set_anchors_and_offsets_preset(Control.PRESET_CENTER); overlay.add_child(p)
	var sb = StyleBoxFlat.new(); sb.bg_color = Color(0.01, 0.05, 0.1, 1); sb.border_width_top = 2; sb.border_color = Color.CYAN; p.add_theme_stylebox_override("panel", sb)
	var v = VBoxContainer.new(); v.add_theme_constant_override("separation", 15); p.add_child(v)
	
	var tl = Label.new(); tl.text = title; tl.horizontal_alignment = 1; tl.modulate = Color.CYAN; v.add_child(tl)
	var rt = RichTextLabel.new(); rt.bbcode_enabled = true; rt.text = "[center]" + msg + "[/center]"; rt.fit_content = true; v.add_child(rt)
	
	if custom_node: v.add_child(custom_node)
	
	var hb = HBoxContainer.new(); hb.alignment = BoxContainer.ALIGNMENT_CENTER; v.add_child(hb)
	var bc = Button.new(); bc.text = "CONFIRMAR"; bc.pressed.connect(func(): on_confirm.call(); overlay.queue_free(); modal_active = false); hb.add_child(bc)
	var bx = Button.new(); bx.text = "CANCELAR"; bx.pressed.connect(func(): overlay.queue_free(); modal_active = false); hb.add_child(bx)

func _show_result_modal(title, msg):
	var overlay = ColorRect.new(); overlay.color = Color(0,0,0,0.6); overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(overlay)
	var p = PanelContainer.new(); p.custom_minimum_size = Vector2(350, 150); p.set_anchors_and_offsets_preset(Control.PRESET_CENTER); overlay.add_child(p)
	var sb = StyleBoxFlat.new(); sb.bg_color = Color(0,0.1,0.05, 1); sb.border_width_top = 1; sb.border_color = Color.GREEN; p.add_theme_stylebox_override("panel", sb)
	var v = VBoxContainer.new(); p.add_child(v); var tl = Label.new(); tl.text = title; tl.modulate = Color.GREEN; tl.horizontal_alignment = 1; v.add_child(tl)
	var m = Label.new(); m.text = msg; m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; m.horizontal_alignment = 1; v.add_child(m)
	var b = Button.new(); b.text = "ENTENDIDO"; b.pressed.connect(func(): overlay.queue_free()); v.add_child(b)

# --- TALENTS ---
func _update_talent_tree():
	var tab = get_node_or_null("Window/TabContainer/Talentos")
	if not tab: return
	for n in tab.get_children(): n.queue_free()
	
	var master_v = VBoxContainer.new(); master_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); tab.add_child(master_v)
	var hb = HBoxContainer.new(); master_v.add_child(hb)
	var pts = Label.new(); pts.text = "PUNTOS DISPONIBLES: " + str(skill_points); pts.modulate = Color.GREEN; hb.add_child(pts)
	var rb = Button.new(); rb.text = "RESETEAR ARBOL (5.000 OHCU)"; rb.size_flags_horizontal = 3; rb.alignment = HORIZONTAL_ALIGNMENT_RIGHT; rb.pressed.connect(func(): NetworkManager.send_event("resetSkills", {})); hb.add_child(rb)
	
	var grid = HBoxContainer.new(); grid.size_flags_vertical = 3; grid.add_theme_constant_override("separation", 20); master_v.add_child(grid)
	var cats = {"engineering": "INGENIERÍA", "combat": "COMBATE", "science": "CIENCIA"}
	for ck in cats:
		var v = VBoxContainer.new(); v.size_flags_horizontal = 3; grid.add_child(v)
		var l = Label.new(); l.text = cats[ck]; l.horizontal_alignment = 1; l.modulate = Color.CYAN; v.add_child(l)
		var sc = ScrollContainer.new(); sc.size_flags_vertical = 3; v.add_child(sc)
		var li = VBoxContainer.new(); sc.add_child(li); var branch = skill_tree.get(ck, [0,0,0,0,0,0,0,0])
		var skills = SKILL_DATA.filter(func(x): return x.cat == ck)
		for i in range(skills.size()):
			var s = skills[i]; var lvl = branch[i] if i < branch.size() else 0
			var b = Button.new(); b.text = s.name + " (" + str(lvl) + "/5)"; b.tooltip_text = s.desc
			if lvl >= 5: b.modulate = Color.GOLD
			b.pressed.connect(func(): NetworkManager.send_event("investSkill", {"category": ck, "index": i})); li.add_child(b)

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
	var r_col = VBoxContainer.new(); r_col.size_flags_horizontal = 3; master_h.add_child(r_col)
	var r_title = Label.new(); r_title.text = "PILOTOS EN LA ZONA"; r_title.modulate = Color.GOLD; r_title.add_theme_font_size_override("font_size", 11); r_col.add_child(r_title)
	
	var n_scroll = ScrollContainer.new(); n_scroll.size_flags_vertical = 3; r_col.add_child(n_scroll)
	var n_list = VBoxContainer.new(); n_list.size_flags_horizontal = 3; n_scroll.add_child(n_list)
	
	# v164.93: Detección robusta del nodo Mundo para escaneo de pilotos
	var world = get_tree().get_first_node_in_group("world_node")
	if is_instance_valid(world):
		var players = world.remote_players
		if players.is_empty():
			var lbl = Label.new(); lbl.text = "\nNo hay otros pilotos cerca."; lbl.modulate.a = 0.3; n_list.add_child(lbl)
		else:
			for id in players:
				var p = players[id]
				if not is_instance_valid(p): continue
				var hb = HBoxContainer.new()
				var nl = Label.new(); nl.text = p.username if "username" in p else "Piloto"; nl.size_flags_horizontal = 3
				var ib = Button.new(); ib.text = "INVITAR"; ib.add_theme_font_size_override("font_size", 10)
				ib.pressed.connect(func(): PartyManager.invite_player(nl.text))
				hb.add_child(nl); hb.add_child(ib); n_list.add_child(hb)

	# Seccion de Invitacion Manual
	var inv_h = HBoxContainer.new(); r_col.add_child(inv_h)
	var inp = LineEdit.new(); inp.placeholder_text = "Buscar por nombre..."; inp.size_flags_horizontal = 3; inv_h.add_child(inp)
	var btn = Button.new(); btn.text = "INVITAR"; inv_h.add_child(btn)
	btn.pressed.connect(func(): 
		if inp.text != "": 
			PartyManager.invite_player(inp.text)
			inp.text = ""
	)

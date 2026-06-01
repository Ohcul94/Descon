extends Control

# ShopTab.gd - MÓDULO DE TIENDA INTERESTELAR (v300.70)
# Corregido: Detección de naves adquiridas, limpieza de UI y previsualización 3D en modal centrado.

var inv_main = null
var shop_tab = "ships"
var ammo_sub_tab = "laser"
var preview_mesh: Node3D = null

func setup(p_inv_main):
	inv_main = p_inv_main
	set_process(true)

func update_ui():
	if not inv_main: return
	var h = self
	for n in h.get_children(): 
		h.remove_child(n)
		n.queue_free()
		
	preview_mesh = null
	
	var main_v = VBoxContainer.new()
	main_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_v.mouse_filter = Control.MOUSE_FILTER_STOP # v305.40: Bloquear click-through
	h.add_child(main_v)
	h.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# --- BARRA DE CATEGORÍAS ---
	var bar = HBoxContainer.new(); bar.add_theme_constant_override("separation", 15); main_v.add_child(bar)
	var lbats = {"ships": "NAVES", "weapons": "ARMAS", "shields": "ESCUDOS", "engines": "MOTORES", "ammo": "MUNICIONES", "extras": "EXTRAS"}
	for k in lbats:
		var b = Button.new(); b.text = lbats[k]; b.flat = true
		b.modulate = Color.CYAN if shop_tab == k else Color.WHITE
		b.pressed.connect(func(): shop_tab = k; update_ui())
		bar.add_child(b)
	
	# v262.530: Subtítulo eliminado por pedido del usuario
	
	# Restaurada estética original: Grilla de 3 columnas
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
	var p = PanelContainer.new()
	if cat == "ships":
		p.custom_minimum_size = Vector2(280, 135) # Más alto para acomodar el botón de detalles
	else:
		p.custom_minimum_size = Vector2(280, 110)
		
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0, 0.02, 0.1, 0.4)
	sb.border_width_top = 1
	sb.border_color = Color(0, 1, 1, 0.1)
	p.add_theme_stylebox_override("panel", sb)
	
	var v = VBoxContainer.new(); v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); v.offset_left = 10; v.offset_right = -10; p.add_child(v)
	v.add_theme_constant_override("separation", 4)
	
	var n = Label.new(); n.text = it["name"]; n.horizontal_alignment = 1; n.add_theme_font_size_override("font_size", 11); v.add_child(n)
	
	# Mostrar ICONO en la tienda si existe (Armas, Escudos, etc)
	var icon_path = str(it.get("icon", ""))
	if icon_path != "" and icon_path != "null" and ResourceLoader.exists(icon_path):
		var tex_container = CenterContainer.new()
		v.add_child(tex_container)
		var tex = TextureRect.new()
		tex.texture = load(icon_path)
		tex.custom_minimum_size = Vector2(48, 48)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_container.add_child(tex)
	
	# Mostrar Stats para ítems que no son naves
	var base_val = int(it.get("base", 0))
	var stat_label = Label.new(); stat_label.horizontal_alignment = 1; stat_label.add_theme_font_size_override("font_size", 9); stat_label.modulate = Color.GOLD
	if cat == "weapons": stat_label.text = "POTENCIA DE FUEGO: " + str(base_val)
	elif cat == "shields": stat_label.text = "CAPACIDAD DE ESCUDO: " + str(base_val)
	elif cat == "engines": stat_label.text = "EMPUJE DE MOTOR: +" + str(base_val)
	if stat_label.text != "": v.add_child(stat_label)

	var d = Label.new(); d.text = it.get("desc", ""); d.horizontal_alignment = 1; d.modulate.a = 0.5; d.add_theme_font_size_override("font_size", 8); v.add_child(d)
	
	var is_owned = false
	if cat == "ships":
		var target_id = int(it["id"])
		for owned_id in inv_main.owned_ships:
			if int(owned_id) == target_id:
				is_owned = true; break
				
	if is_owned:
		var l = Label.new(); l.text = "\nNAVE ADQUIRIDA"; l.modulate = Color.GREEN; l.horizontal_alignment = 1; v.add_child(l)
	else:
		var pr = it["prices"]
		if pr.get("hubs", 0) > 0:
			var b1 = Button.new(); b1.text = inv_main._format_val(pr["hubs"]) + " HUBS"; v.add_child(b1)
			b1.pressed.connect(func(): _buy_request(cat, it, "hubs"))
		if pr.get("ohcu", 0) > 0:
			var b2 = Button.new(); b2.text = inv_main._format_val(pr["ohcu"]) + " OHCU"; v.add_child(b2)
			b2.pressed.connect(func(): _buy_request(cat, it, "ohcu"))
			
	# Botón de detalles exclusivo para naves
	if cat == "ships":
		var btn_detalles = Button.new()
		btn_detalles.text = "VER DETALLES 3D"
		btn_detalles.add_theme_font_size_override("font_size", 9)
		btn_detalles.add_theme_color_override("font_color", Color.CYAN)
		btn_detalles.pressed.connect(func(): _open_detail_modal(it))
		v.add_child(btn_detalles)
	
	parent.add_child(p)

func _open_detail_modal(it):
	# Crear CanvasLayer para centrado automático independiente de resolución
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "DetailCanvasLayer"
	canvas_layer.layer = 110
	get_tree().root.add_child(canvas_layer)
	
	if inv_main:
		inv_main.active_modales.append(canvas_layer)
		inv_main.modal_active = true
		
	var close_detail_modal = func():
		preview_mesh = null
		if inv_main:
			if canvas_layer in inv_main.active_modales:
				inv_main.active_modales.erase(canvas_layer)
			inv_main.modal_active = inv_main.active_modales.size() > 0
		canvas_layer.queue_free()
	
	# Crear overlay oscuro translúcido responsivo
	var overlay = ColorRect.new()
	overlay.name = "DetailOverlay"
	overlay.color = Color(0, 0, 0, 0.8)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas_layer.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Contenedor de centrado automático
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	
	# Panel de Detalles
	var p = PanelContainer.new()
	p.custom_minimum_size = Vector2(580, 420)
	center.add_child(p)
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.01, 0.04, 0.08, 0.98)
	sb.border_width_left = 2; sb.border_width_top = 2; sb.border_width_right = 2; sb.border_width_bottom = 2
	sb.border_color = Color.CYAN
	sb.corner_radius_top_left = 8; sb.corner_radius_top_right = 8; sb.corner_radius_bottom_left = 8; sb.corner_radius_bottom_right = 8
	p.add_theme_stylebox_override("panel", sb)
	
	# Margen interno
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	p.add_child(margin)
	
	var v_main = VBoxContainer.new()
	v_main.add_theme_constant_override("separation", 15)
	margin.add_child(v_main)
	
	# Cabecera (Nombre + Botón cerrar X)
	var header = HBoxContainer.new()
	v_main.add_child(header)
	
	var l_title = Label.new()
	l_title.text = str(it["name"]).to_upper() + " - PREVISUALIZACIÓN DE NAVE"
	l_title.add_theme_font_size_override("font_size", 13)
	l_title.modulate = Color.CYAN
	header.add_child(l_title)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	
	# Botón de Cerrar [X] - Agrandado para celulares
	var btn_close_x = Button.new()
	btn_close_x.text = " X "
	btn_close_x.custom_minimum_size = Vector2(50, 50)
	btn_close_x.add_theme_font_size_override("font_size", 16)
	btn_close_x.flat = true
	btn_close_x.modulate = Color.RED
	btn_close_x.pressed.connect(close_detail_modal)
	header.add_child(btn_close_x)
	
	# Separación de contenido (HBox)
	var content_h = HBoxContainer.new()
	content_h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_h.add_theme_constant_override("separation", 20)
	v_main.add_child(content_h)
	
	# --- COLUMNA IZQUIERDA: 3D VIEWPORT ---
	var left_v = VBoxContainer.new()
	left_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_v.size_flags_stretch_ratio = 1.1
	content_h.add_child(left_v)
	
	var vp_container = SubViewportContainer.new()
	vp_container.stretch = true
	vp_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vp_container.custom_minimum_size = Vector2(260, 260)
	left_v.add_child(vp_container)
	
	var vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.positional_shadow_atlas_size = 0
	if "use_hdr_3d" in vp: vp.use_hdr_3d = false
	vp_container.add_child(vp)
	
	var node3d = Node3D.new()
	vp.add_child(node3d)
	
	# Iluminación de tres puntos AAA
	var env = WorldEnvironment.new()
	var world_env = Environment.new()
	world_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_env.ambient_light_color = Color.WHITE
	world_env.ambient_light_energy = 0.8
	env.environment = world_env
	node3d.add_child(env)
	
	# Cámara (Añadida al árbol ANTES de look_at)
	var cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 40.0
	cam.position = Vector3(0, 1.3, 3.3)
	node3d.add_child(cam)
	cam.look_at(Vector3(0, 0.1, 0))
	
	# Luz Clave (Key Light)
	var key_light = DirectionalLight3D.new()
	key_light.light_energy = 1.6
	key_light.shadow_enabled = false
	key_light.rotation_degrees = Vector3(-35, 45, 0)
	node3d.add_child(key_light)
	
	# Luz de Relleno (Fill Light)
	var fill_light = DirectionalLight3D.new()
	fill_light.light_energy = 0.5
	fill_light.shadow_enabled = false
	fill_light.rotation_degrees = Vector3(25, -135, 0)
	node3d.add_child(fill_light)
	
	# Cargar modelo GLB (limpio de tilts de gameplay)
	var ship_id = int(it["id"])
	var glb_path = ""
	match ship_id:
		1: glb_path = "res://assets/Personajes/3D/Nave1/futuristic+jet+3d+model_Clone1.glb"
		2: glb_path = "res://assets/Personajes/3D/Nave2/Nave2.glb"
		3: glb_path = "res://assets/Personajes/3D/Nave3/Nave3.glb"
		4: glb_path = "res://assets/Personajes/3D/Nave4/Nave4.glb"
		5: glb_path = "res://assets/Personajes/3D/Nave5/Nave5.glb"
		6: glb_path = "res://assets/Personajes/3D/Nave6/Nave6.glb"
		
	if glb_path != "" and ResourceLoader.exists(glb_path):
		var model_scene = load(glb_path)
		if model_scene:
			var model = model_scene.instantiate()
			_clean_internal_lights_in_ui(model)
			
			var pivot = Node3D.new()
			pivot.name = "ShipPivot"
			node3d.add_child(pivot)
			pivot.add_child(model)
			
			pivot.scale = Vector3(1.3, 1.3, 1.3)
			
			# Orientación base con corrección específica de modelado
			match ship_id:
				3: model.rotation_degrees = Vector3(0, 1, 98)
				4: model.rotation_degrees = Vector3(0, -180, 52)
				6: model.rotation_degrees.y = 180
				_: model.rotation_degrees = Vector3.ZERO
				
			preview_mesh = pivot
			
	# --- COLUMNA DERECHA: DETALLES Y ACCIÓN ---
	var right_v = VBoxContainer.new()
	right_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_v.size_flags_stretch_ratio = 1.0
	right_v.alignment = BoxContainer.ALIGNMENT_CENTER
	right_v.add_theme_constant_override("separation", 12)
	content_h.add_child(right_v)
	
	# Especificaciones
	var spec_lbl = Label.new()
	spec_lbl.text = "ESPECIFICACIONES TÉCNICAS:"
	spec_lbl.modulate = Color.GOLD
	spec_lbl.add_theme_font_size_override("font_size", 10)
	right_v.add_child(spec_lbl)
	
	var stats_grid = GridContainer.new()
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", 15)
	stats_grid.add_theme_constant_override("v_separation", 8)
	right_v.add_child(stats_grid)
	
	var add_stat = func(lbl_text, val_text, color):
		var l_lbl = Label.new()
		l_lbl.text = lbl_text
		l_lbl.add_theme_font_size_override("font_size", 9)
		l_lbl.modulate = Color(1, 1, 1, 0.5)
		stats_grid.add_child(l_lbl)
		
		var l_val = Label.new()
		l_val.text = val_text
		l_val.add_theme_font_size_override("font_size", 9)
		l_val.modulate = color
		stats_grid.add_child(l_val)
		
	add_stat.call("Integridad de Casco (HP):", inv_main._format_val(it.get("hp", 0)), Color.GREEN)
	add_stat.call("Generador de Escudo (SH):", inv_main._format_val(it.get("shield", 0)), Color.AQUA)
	add_stat.call("Empuje de Motores (VEL):", inv_main._format_val(it.get("speed", 0)), Color.YELLOW)
	
	var slots = it.get("slots", {"w": 0, "s": 0, "e": 0, "x": 0})
	var slots_text = "Armas: %d | Escudos: %d | Motores: %d | Extras: %d" % [slots.get("w", 0), slots.get("s", 0), slots.get("e", 0), slots.get("x", 0)]
	add_stat.call("Distribución de Ranuras:", slots_text, Color.MEDIUM_PURPLE)
	
	# Verificar propiedad de la nave
	var is_owned = false
	var target_id = int(it["id"])
	for owned_id in inv_main.owned_ships:
		if int(owned_id) == target_id:
			is_owned = true; break
			
	# Espacio divisor
	var divisor = Control.new()
	divisor.custom_minimum_size = Vector2(0, 10)
	right_v.add_child(divisor)
	
	if is_owned:
		var l_owned = Label.new()
		l_owned.text = "NAVE ADQUIRIDA Y DISPONIBLE EN EL HANGAR"
		l_owned.modulate = Color.GREEN
		l_owned.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l_owned.add_theme_font_size_override("font_size", 10)
		l_owned.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right_v.add_child(l_owned)
	else:
		var pr = it["prices"]
		var btn_container = VBoxContainer.new()
		btn_container.add_theme_constant_override("separation", 10)
		right_v.add_child(btn_container)
		
		if pr.get("hubs", 0) > 0:
			var b1 = Button.new()
			b1.text = "ADQUIRIR POR " + inv_main._format_val(pr["hubs"]) + " HUBS"
			b1.custom_minimum_size = Vector2(0, 36)
			b1.pressed.connect(func():
				_buy_request("ships", it, "hubs")
				close_detail_modal.call()
			)
			btn_container.add_child(b1)
			
		if pr.get("ohcu", 0) > 0:
			var b2 = Button.new()
			b2.text = "ADQUIRIR POR " + inv_main._format_val(pr["ohcu"]) + " OHCU"
			b2.custom_minimum_size = Vector2(0, 36)
			b2.pressed.connect(func():
				_buy_request("ships", it, "ohcu")
				close_detail_modal.call()
			)
			btn_container.add_child(b2)
			
	# Pie del modal
	var footer = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	v_main.add_child(footer)
	
	var btn_close = Button.new()
	btn_close.text = "   CERRAR DETALLES   "
	btn_close.custom_minimum_size = Vector2(150, 32)
	btn_close.pressed.connect(close_detail_modal)
	footer.add_child(btn_close)

func _clean_internal_lights_in_ui(node):
	for child in node.get_children():
		if child is Light3D:
			child.queue_free()
		else:
			_clean_internal_lights_in_ui(child)

func _process(delta):
	if is_instance_valid(preview_mesh):
		preview_mesh.rotate_y(delta * 0.5)


func _render_ammo_shop(parent, grid):
	var bar = HBoxContainer.new(); bar.add_theme_constant_override("separation", 10); parent.add_child(bar); parent.move_child(bar, 1)
	for t in ["laser", "missile", "mine", "melee", "heal", "siphon", "emp"]:
		var b = Button.new(); b.text = t.to_upper(); b.flat = true; b.modulate = Color.GOLD if ammo_sub_tab == t else Color.WHITE
		b.pressed.connect(func(): ammo_sub_tab = t; update_ui())
		bar.add_child(b)
	var ammo_base = GameConstants.SHOP_ITEMS.get("ammo", {})
	var items = ammo_base.get(ammo_sub_tab, [])
	for it in items: _create_shop_card(it, "ammo", grid)

func _buy_request(cat, it, cur):
	var price = it["prices"][cur]
	var wallet = inv_main.hubs if cur == "hubs" else inv_main.ohcu
	if wallet < price: 
		inv_main._show_result_modal("FONDOS INSUFICIENTES", "No tienes suficientes " + cur.to_upper() + " para esta operación.")
		return
	
	if cat == "ammo":
		_show_ammo_modal(it, cur)
		return

	var msg = "¿Deseas adquirir [color=cyan]" + it["name"] + "[/color] por [color=yellow]" + inv_main._format_val(price) + " " + cur.to_upper() + "[/color]?"
	inv_main._show_modal("CONFIRMAR ADQUISICIÓN", msg, func():
		NetworkManager.send_event("buyItem", {"category": cat, "itemId": it["id"], "currency": cur})
	)

func _show_ammo_modal(it, cur):
	var unit_price = it["prices"][cur]
	var dial_v = VBoxContainer.new()
	var lq = Label.new(); lq.text = "CANTIDAD DE RECARGA:"; lq.horizontal_alignment = 1; dial_v.add_child(lq)
	var slider = HSlider.new(); slider.min_value = 100; slider.max_value = 50000; slider.step = 100; slider.value = 1000; dial_v.add_child(slider)
	var total_lbl = Label.new(); total_lbl.text = "1.000 unidades = " + inv_main._format_val(unit_price * 10) + " " + cur.to_upper(); total_lbl.horizontal_alignment = 1; dial_v.add_child(total_lbl)
	
	slider.value_changed.connect(func(v): 
		total_lbl.text = inv_main._format_val(v) + " unidades = " + inv_main._format_val(v * (unit_price/100.0)) + " " + cur.to_upper()
	)
	
	inv_main._show_modal("SUMINISTROS TÁCTICOS", "Ajusta la cantidad de [color=cyan]" + it["name"] + "[/color] a comprar:", func():
		var qty = int(slider.value)
		var total = int(qty * (unit_price/100.0))
		if (inv_main.hubs if cur == "hubs" else inv_main.ohcu) >= total:
			NetworkManager.send_event("buyItem", {"category": "ammo", "itemId": it["id"], "currency": cur, "amount": qty})
		else:
			inv_main._show_result_modal("ERROR", "No tienes fondos para esta cantidad.")
	, dial_v)

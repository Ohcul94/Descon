extends Control

# HousingPanel.gd - Panel de Control del Hangar Privado (F3)
# Sincronizado con la estética cian y metalizada del juego, con previsualización 3D rotativa.

var is_open = false
var unlocked = false

var title_label: Label
var status_label: Label
var req_label: Label
var price_label: Label
var action_btn: Button

func _ready():
	add_to_group("inventory_ui") # Bloquea clicks globales
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_setup_ui()
	
	if NetworkManager:
		NetworkManager.socket_event_received.connect(_on_socket_event_received)
		NetworkManager.inventory_data.connect(_on_inventory_data)
		
	# Redibujar/ajustar al cambiar de tamaño la pantalla
	get_viewport().size_changed.connect(func(): _setup_ui())

func _process(delta):
	if not visible or not is_open: return
	# Rotar todos los modelos de la tienda continuamente como en el Hangar
	var previews = get_tree().get_nodes_in_group("housing_shop_previews")
	for node in previews:
		if is_instance_valid(node):
			node.rotate_y(delta * 0.6)

func _setup_ui():
	# Asegurar que el contenedor raíz ocupe toda la pantalla para que los anchors de sus hijos se calculen correctamente
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	for child in get_children():
		child.queue_free()
		
	# Determinar si estamos en la zona de housing (100)
	var is_in_housing_zone = false
	var pl = get_tree().get_first_node_in_group("player")
	if pl and pl.get("current_zone") == 100:
		is_in_housing_zone = true
		
	# Panel de Fondo
	var main_panel = Panel.new()
	main_panel.name = "MainPanel"
	main_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(main_panel)
	
	# Centrado dinámico por anchors
	main_panel.anchor_left = 0.5
	main_panel.anchor_right = 0.5
	main_panel.anchor_top = 0.5
	main_panel.anchor_bottom = 0.5
	main_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	main_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	
	var screen_size = get_viewport_rect().size
	var r_size = Vector2.ZERO
	if is_in_housing_zone:
		r_size = Vector2(screen_size.x * 0.75, screen_size.y * 0.75)
		r_size.x = clamp(r_size.x, 700, 1000)
		r_size.y = clamp(r_size.y, 480, 700)
	else:
		r_size = Vector2(screen_size.x * 0.45, screen_size.y * 0.45)
		r_size.x = clamp(r_size.x, 380, 500)
		r_size.y = clamp(r_size.y, 250, 380)
		
	main_panel.custom_minimum_size = r_size
	main_panel.size = r_size
	main_panel.offset_left = -r_size.x / 2.0
	main_panel.offset_right = r_size.x / 2.0
	main_panel.offset_top = -r_size.y / 2.0
	main_panel.offset_bottom = r_size.y / 2.0
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.02, 0.05, 0.98)
	sb.border_width_left = 2; sb.border_width_top = 2
	sb.border_width_right = 2; sb.border_width_bottom = 2
	sb.border_color = Color.CYAN
	sb.set_corner_radius_all(8)
	main_panel.add_theme_stylebox_override("panel", sb)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 20)
	main_panel.add_child(vbox)
	
	# Header
	var header = HBoxContainer.new()
	vbox.add_child(header)
		
	title_label = Label.new()
	title_label.text = "TIENDA DE HANGAR PRIVADO" if is_in_housing_zone else "SISTEMA DE HANGAR DE JUGADOR (HOUSING)"
	title_label.add_theme_color_override("font_color", Color.CYAN)
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	
	var close_x = Button.new()
	close_x.text = " X "
	close_x.custom_minimum_size = Vector2(40, 40)
	close_x.pressed.connect(func(): toggle())
	header.add_child(close_x)
	
	vbox.add_child(HSeparator.new())
	
	# Cuerpo del panel
	if not is_in_housing_zone:
		var body_vbox = VBoxContainer.new()
		body_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body_vbox.add_theme_constant_override("separation", 12)
		vbox.add_child(body_vbox)
		
		status_label = Label.new()
		status_label.text = "ESTADO: DESCONOCIDO"
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_label.add_theme_font_size_override("font_size", 14)
		body_vbox.add_child(status_label)
		
		req_label = Label.new()
		req_label.text = "Requisito de Nivel: Nivel 5"
		req_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body_vbox.add_child(req_label)
		
		price_label = Label.new()
		price_label.text = "Costo: 10000 HUBS"
		price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price_label.add_theme_color_override("font_color", Color.YELLOW)
		body_vbox.add_child(price_label)
		
		action_btn = Button.new()
		action_btn.custom_minimum_size = Vector2(250, 50)
		action_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		action_btn.text = "COMPRAR HANGAR PRIVADO"
		action_btn.pressed.connect(_on_action_pressed)
		body_vbox.add_child(action_btn)
		
		_update_ui()
	else:
		# Pestañas (Tabs) estilo F3
		var tabs = TabContainer.new()
		tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(tabs)
		
		var shop_tab = Control.new()
		shop_tab.name = "TIENDA"
		tabs.add_child(shop_tab)
		
		var shop_vbox = VBoxContainer.new()
		shop_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
		shop_vbox.add_theme_constant_override("separation", 10)
		shop_tab.add_child(shop_vbox)
		
		var desc_lbl = Label.new()
		desc_lbl.text = "Selecciona un objeto para adquirirlo y colocarlo sobre la grilla en 3D."
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		shop_vbox.add_child(desc_lbl)
		
		var scroll = ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		shop_vbox.add_child(scroll)
		
		var grid = GridContainer.new()
		grid.columns = 3
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 15)
		grid.add_theme_constant_override("v_separation", 15)
		scroll.add_child(grid)
		
		var full_config = GameConstants.get("FULL_CONFIG")
		var catalog = []
		if full_config and full_config.has("housingConfig"):
			catalog = full_config.housingConfig.get("placeableItems", [])
			
		for item in catalog:
			var card = PanelContainer.new()
			card.custom_minimum_size = Vector2(235, 230)
			
			var sb_card = StyleBoxFlat.new()
			sb_card.bg_color = Color(0, 0.02, 0.1, 0.45)
			sb_card.border_width_left = 1; sb_card.border_width_top = 1
			sb_card.border_width_right = 1; sb_card.border_width_bottom = 1
			sb_card.border_color = Color(0, 1, 1, 0.2)
			sb_card.set_corner_radius_all(6)
			card.add_theme_stylebox_override("panel", sb_card)
			
			var card_v = VBoxContainer.new()
			card_v.add_theme_constant_override("separation", 6)
			card_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
			card.add_child(card_v)
			
			# Nombre del objeto
			var name_lbl = Label.new()
			name_lbl.text = item.name
			name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_lbl.add_theme_font_size_override("font_size", 11)
			card_v.add_child(name_lbl)
			
			# Contenedor para Viewport 3D
			var vp_container = SubViewportContainer.new()
			vp_container.stretch = true
			vp_container.custom_minimum_size = Vector2(150, 120)
			vp_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
			card_v.add_child(vp_container)
			
			var vp = SubViewport.new()
			vp.own_world_3d = true
			vp.transparent_bg = true
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.size = Vector2(235, 120)
			if "positional_shadow_atlas_size" in vp: vp.positional_shadow_atlas_size = 0
			vp_container.add_child(vp)
			
			var node3d = Node3D.new()
			vp.add_child(node3d)
			
			# Pivot de rotación continua
			var pivot = Node3D.new()
			pivot.name = "ShopPreviewPivot"
			pivot.add_to_group("housing_shop_previews")
			node3d.add_child(pivot)
			
			# Environment estático
			var env = WorldEnvironment.new()
			var world_env = Environment.new()
			world_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			world_env.ambient_light_color = Color(0.15, 0.15, 0.3)
			world_env.ambient_light_energy = 0.4
			world_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
			env.environment = world_env
			node3d.add_child(env)
			
			# Luces para profundidad
			var light_key = DirectionalLight3D.new()
			light_key.light_energy = 1.8
			light_key.light_color = Color(1.0, 0.9, 0.75)
			light_key.rotation_degrees = Vector3(-35, 45, 0)
			node3d.add_child(light_key)
			
			var light_fill = DirectionalLight3D.new()
			light_fill.light_energy = 0.6
			light_fill.light_color = Color(0.7, 0.8, 1.0)
			light_fill.rotation_degrees = Vector3(25, -135, 0)
			node3d.add_child(light_fill)
			
			# Cámara con look_at_from_position
			var cam = Camera3D.new()
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.fov = 40.0
			node3d.add_child(cam)
			cam.look_at_from_position(Vector3(0, 0.75, 3.2), Vector3(0, -0.15, 0))
			
			# Cargar e instanciar modelo
			var model_loaded = false
			if item.has("model") and ResourceLoader.exists(item.model):
				var model_scene = load(item.model)
				if model_scene:
					var model = model_scene.instantiate()
					_clean_internal_lights_in_ui(model)
					pivot.add_child(model)
					# Escala reducida levemente (1.9x para casas, 1.5x para otros) para no recortar bordes
					if "casa" in str(item.id):
						model.scale = Vector3(1.65, 1.65, 1.65)
						model.position = Vector3(0, -0.25, 0)
					else:
						model.scale = Vector3(1.3, 1.3, 1.3)
						model.position = Vector3(0, 0.0, 0)
					model_loaded = true
			
			if not model_loaded:
				# Instanciar el fallback estético 3D idéntico al del mapa y escalado en la tienda
				var fallback = _instance_3d_object_fallback(item.id)
				pivot.add_child(fallback)
				fallback.scale = Vector3(1.3, 1.3, 1.3)
				fallback.position = Vector3(0, -0.2, 0)
			
			# Botón Comprar con Confirmación (Valores sin decimales)
			var btn_buy = Button.new()
			btn_buy.text = "ADQUIRIR (" + str(int(item.cost)) + " " + item.currency.to_upper() + ")"
			btn_buy.add_theme_font_size_override("font_size", 10)
			btn_buy.pressed.connect(func():
				var currency_lbl = item.currency.to_upper()
				var msg = "@Deseas adquirir [color=cyan]" + item.name + "[/color] por [color=yellow]" + str(int(item.cost)) + " " + currency_lbl + "[/color]?"
				_show_confirm_modal("CONFIRMAR ADQUISICIÓN", msg, func():
					var current_map = get_tree().get_first_node_in_group("map")
					if current_map and current_map.has_method("enter_edit_mode"):
						current_map.enter_edit_mode(item.id)
						toggle()
				)
			)
			card_v.add_child(btn_buy)
			
			grid.add_child(card)
			
		shop_vbox.add_child(HSeparator.new())
		
		# Botón para remover último objeto colocado en el pie
		var footer_h = HBoxContainer.new()
		footer_h.alignment = BoxContainer.ALIGNMENT_CENTER
		shop_vbox.add_child(footer_h)
		
		var btn_remove = Button.new()
		btn_remove.text = "Remover Último Objeto (50% Reembolso)"
		btn_remove.modulate = Color.YELLOW
		btn_remove.pressed.connect(func():
			var current_map = get_tree().get_first_node_in_group("map")
			if current_map and "placed_objects" in current_map and current_map.placed_objects.size() > 0:
				var last = current_map.placed_objects[-1]
				NetworkManager.send_event("removeHousingObject", {"id": last.id})
		)
		footer_h.add_child(btn_remove)

func _instance_3d_object_fallback(item_type: String) -> Node3D:
	var node = Node3D.new()
	var mesh_inst = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	var mat = StandardMaterial3D.new()
	
	if item_type == "chair":
		mesh.size = Vector3(0.8, 1.2, 0.8)
		mat.albedo_color = Color(0.6, 0.3, 0.1) # Madera
		mat.roughness = 0.5
	elif item_type == "table":
		mesh.size = Vector3(1.8, 0.9, 1.2)
		mat.albedo_color = Color(0.3, 0.3, 0.35) # Metalizado
		mat.metallic = 0.9
		mat.roughness = 0.2
	elif item_type == "light":
		var cyl = CylinderMesh.new()
		cyl.top_radius = 0.2
		cyl.bottom_radius = 0.2
		cyl.height = 2.5
		mesh = cyl
		mat.albedo_color = Color(0.1, 0.1, 0.1)
		
		# Luz integrada
		var light = OmniLight3D.new()
		light.light_color = Color(0.0, 1.0, 1.0)
		light.light_energy = 3.0
		light.omni_range = 8.0
		light.position.y = 1.2
		node.add_child(light)
		
		# Efecto de neón brillante
		var neon_mesh = MeshInstance3D.new()
		var neon_cyl = CylinderMesh.new()
		neon_cyl.top_radius = 0.15
		neon_cyl.bottom_radius = 0.15
		neon_cyl.height = 1.0
		neon_mesh.mesh = neon_cyl
		neon_mesh.position.y = 0.7
		var neon_mat = StandardMaterial3D.new()
		neon_mat.albedo_color = Color(0.0, 1.0, 1.0)
		neon_mat.emission_enabled = true
		neon_mat.emission = Color(0.0, 1.0, 1.0)
		neon_mat.emission_energy_multiplier = 2.0
		neon_mesh.material_override = neon_mat
		node.add_child(neon_mesh)
	elif item_type == "plant":
		var sph = SphereMesh.new()
		sph.radius = 0.6
		sph.height = 1.0
		mesh = sph
		mat.albedo_color = Color(0.0, 0.8, 0.3) # Verde holográfico
		mat.emission_enabled = true
		mat.emission = Color(0.0, 0.8, 0.3)
		mat.emission_energy_multiplier = 0.8
	else:
		mesh.size = Vector3(1.0, 1.0, 1.0)
		mat.albedo_color = Color(0.8, 0.0, 0.8) # Violeta
		
	node.add_child(mesh_inst)
	mesh_inst.mesh = mesh
	mesh_inst.material_override = mat
	var mesh_h = mesh.get("height")
	mesh_inst.position.y = (mesh_h / 2.0) if mesh_h != null else 0.5
	return node

func _clean_internal_lights_in_ui(node):
	for child in node.get_children():
		if child is Light3D:
			child.queue_free()
		else:
			_clean_internal_lights_in_ui(child)

func _show_confirm_modal(title: String, msg: String, on_confirm: Callable):
	var inv = get_tree().get_first_node_in_group("inventory_ui")
	if inv and inv.has_method("_show_modal"):
		inv._show_modal(title, msg, on_confirm)
		return
		
	# Fallback si no está el inventario principal en escena
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "HousingConfirmCanvas"
	canvas_layer.layer = 120
	get_tree().root.add_child(canvas_layer)
	
	var overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas_layer.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var p = PanelContainer.new()
	p.custom_minimum_size = Vector2(400, 200)
	overlay.add_child(p)
	p.anchor_left = 0.5; p.anchor_right = 0.5; p.anchor_top = 0.5; p.anchor_bottom = 0.5
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH; p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.offset_left = -200; p.offset_right = 200; p.offset_top = -100; p.offset_bottom = 100
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.01, 0.04, 0.08, 1)
	sb.border_width_top = 3
	sb.border_color = Color.CYAN
	p.add_theme_stylebox_override("panel", sb)
	
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 20)
	p.add_child(v)
	
	var tl = Label.new()
	tl.text = title
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.modulate = Color.CYAN
	v.add_child(tl)
	
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.text = "[center]" + msg + "[/center]"
	rt.fit_content = true
	v.add_child(rt)
	
	var hb = HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 20)
	v.add_child(hb)
	
	var bc = Button.new()
	bc.text = "CONFIRMAR"
	bc.pressed.connect(func():
		on_confirm.call()
		canvas_layer.queue_free()
	)
	hb.add_child(bc)
	
	var bx = Button.new()
	bx.text = "CANCELAR"
	bx.pressed.connect(func():
		canvas_layer.queue_free()
	)
	hb.add_child(bx)

func toggle():
	is_open = !is_open
	visible = is_open
	
	if is_open:
		# Traer al frente
		if get_parent():
			get_parent().move_child(self, get_parent().get_child_count() - 1)
		top_level = true
		z_index = 100
		
		# Re-dibujar para cambiar dinámicamente según la zona actual
		_setup_ui()
		
		# Solicitar estado actual al abrir
		if NetworkManager:
			NetworkManager.send_event("getHousingState", {})
	else:
		top_level = false
		z_index = 0
		
	queue_redraw()

func _draw():
	if not visible: return
	# Dibujar un overlay oscuro translúcido en toda la pantalla
	var screen_size = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, screen_size), Color(0, 0, 0, 0.6))

func _input(event):
	if is_open and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		toggle()
		get_viewport().set_input_as_handled()

func _on_action_pressed():
	if not NetworkManager: return
	
	if not unlocked:
		NetworkManager.send_event("buyHousing", {})
	else:
		# Ingresar al Hangar (Zona 100)
		NetworkManager.send_event("changeZone", 100)
		toggle()

func _on_socket_event_received(event_name: String, data: Dictionary):
	if event_name == "housingState":
		unlocked = data.get("unlocked", false)
		# Solo refrescar si no estamos en la zona de construcción para no rehacer los botones continuamente
		var pl = get_tree().get_first_node_in_group("player")
		if pl and pl.get("current_zone") != 100:
			_update_ui()

func _on_inventory_data(data: Dictionary):
	if data.has("housing"):
		var h_data = data["housing"]
		unlocked = h_data.get("unlocked", false)
		var pl = get_tree().get_first_node_in_group("player")
		if pl and pl.get("current_zone") != 100:
			_update_ui()

func _update_ui():
	# Obtener configuración del config del servidor
	var full_config = GameConstants.get("FULL_CONFIG")
	var req_lvl = 5
	var cost = 10000
	var currency = "hubs"
	
	if full_config and full_config.has("housingConfig"):
		var hc = full_config.housingConfig
		req_lvl = int(hc.get("levelRequired", 5))
		cost = int(hc.get("cost", 10000))
		currency = str(hc.get("currency", "hubs")).to_upper()
		
	if req_label: req_label.text = "Requisito de Nivel: Nivel " + str(req_lvl)
	if price_label: price_label.text = "Costo de Adquisición: " + str(int(cost)) + " " + currency
	
	if unlocked:
		if status_label: 
			status_label.text = "ESTADO: ¡HANGAR DESBLOQUEADO!"
			status_label.modulate = Color.GREEN
		if action_btn:
			action_btn.text = "INGRESAR A MI HANGAR"
			action_btn.modulate = Color.CYAN
	else:
		if status_label:
			status_label.text = "ESTADO: PROPIEDAD NO ADQUIRIDA"
			status_label.modulate = Color.YELLOW
		if action_btn:
			action_btn.text = "COMPRAR HANGAR PRIVADO"
			action_btn.modulate = Color.WHITE

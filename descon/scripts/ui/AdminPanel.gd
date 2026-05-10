extends "res://scripts/systems/HUDWindow.gd"

# AdminPanel.gd (Godot Master Admin v3.0)
# Portabilidad total del sistema legacy con soporte para edición en tiempo real.

var current_tab = "ships"

func _ready():
	add_to_group("admin_panel_ui") # v244.86: Coordinación global
	window_id = "AdminPanel"
	header_height = 30
	z_index = 200 # Por encima de todo
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	super._ready()
	_create_drag_handler()
	
	# v190.60: Sincronía de Dimensiones al 85%
	# v190.62: Sincronía Responsive
	get_viewport().size_changed.connect(func(): queue_redraw())
	
	_update_window_size()
	
	# v190.50: Limpiar UI vieja y preparar contenedor dinámico
	for n in get_children(): if n.name != "Header": n.queue_free()
	
	var main_v = VBoxContainer.new()
	main_v.name = "MainVBox"
	main_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_v.offset_top = 45; main_v.offset_bottom = -15; main_v.offset_left = 15; main_v.offset_right = -15
	add_child(main_v)
	
	_build_ui()

func _draw():
	if not visible: return
	var screen_size = get_viewport_rect().size
	var r_size = Vector2(screen_size.x * 0.85, screen_size.y * 0.85)
	var r_pos = Vector2.ZERO # El panel ya está posicionado por _update_window_size()
	
	# v226.35: Fondo consistente con F1 (0.98 opacidad)
	draw_rect(Rect2(r_pos, r_size), Color(0.02, 0.02, 0.05, 0.98))
	draw_rect(Rect2(r_pos, Vector2(r_size.x, 35)), Color(0, 0.08, 0.12, 1.0))
	draw_rect(Rect2(r_pos, r_size), Color(0, 0.8, 1, 0.5), false, 1.5)
	
	# Botones de Control Visuales [X]
	var f = get_theme_font("font")
	draw_rect(Rect2(r_pos.x + r_size.x - 35, r_pos.y+8, 25, 18), Color(0, 1, 1), false, 1.0)
	draw_string(f, r_pos + Vector2(r_size.x-30, 22), "[X]", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 1, 1))

func _input(event):
	# v190.65: Primero capturar clic para el botón cerrar [X] (Sin importar el foco)
	if event is InputEventMouseButton and event.pressed and visible:
		var screen_size = get_viewport_rect().size
		var r_size = Vector2(screen_size.x * 0.85, screen_size.y * 0.85)
		var x_rect = Rect2(global_position.x + r_size.x - 35, global_position.y + 8, 25, 18)
		if x_rect.has_point(event.position): 
			toggle()
			get_viewport().set_input_as_handled()
			return


	if event is InputEventKey and event.pressed:
		# v244.60: Bloquear panel admin en el login
		if not NetworkManager or not NetworkManager.is_logged_in: return

		if event.keycode == KEY_F2:
			toggle()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and visible:
			toggle()
			get_viewport().set_input_as_handled()

func toggle():
	visible = !visible
	if visible: 
		_update_window_size()
		_refresh_ui()
		# v226.36: PRIORIDAD ABSOLUTA - Mover al frente
		if get_parent(): get_parent().move_child(self, get_parent().get_child_count() - 1)
		z_index = 200
	else:
		z_index = 0
	queue_redraw()

func _update_window_size():
	var screen_size = get_viewport_rect().size
	var target_w = screen_size.x * 0.85
	var target_h = screen_size.y * 0.85
	
	custom_minimum_size = Vector2(target_w, target_h)
	size = custom_minimum_size
	
	# Centrar en pantalla
	position = (screen_size - size) / 2.0
	
	# v210.10: El Header ya no es necesario como nodo visual sino como zona de arrastre
	header_height = 35

# v300.20: Arquitectura Modular de Administración
var mod_ships = null
var mod_enemies = null
var mod_modes = null
var mod_items = null
var mod_world = null

func _init_modules():
	if mod_ships: return # Ya cargados
	
	mod_ships = load("res://scripts/ui/admin/AdminShips.gd").new(); mod_ships.setup(self)
	mod_enemies = load("res://scripts/ui/admin/AdminEnemies.gd").new(); mod_enemies.setup(self)
	mod_modes = load("res://scripts/ui/admin/AdminModes.gd").new(); mod_modes.setup(self)
	mod_items = load("res://scripts/ui/admin/AdminItems.gd").new(); mod_items.setup(self)
	mod_world = load("res://scripts/ui/admin/AdminWorld.gd").new(); mod_world.setup(self)

func _build_ui():
	_init_modules()
	var main_v = get_node_or_null("MainVBox")
	if not main_v: return
	for n in main_v.get_children(): n.queue_free()
	
	# 1. Barra de Pestañas Estilizada
	var tab_bar = HBoxContainer.new(); main_v.add_child(tab_bar)
	tab_bar.add_theme_constant_override("separation", 5)
	
	var tabs = {"ships": "NAVES", "enemies": "ENEMIGOS", "modes": "MODOS", "zones": "ZONAS (MAPAS)", "map": "MONITOR", "items": "ITEMS", "ammo": "MUNICIÓN", "spheres": "ESFERAS"}
	for k in tabs:
		var b = Button.new(); b.text = tabs[k]; b.size_flags_horizontal = Control.SIZE_EXPAND_FILL; b.flat = true
		
		# Estilo de Pestaña F1
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0, 0.6, 0.8, 0.3) if current_tab == k else Color(0, 0, 0, 0.2)
		sb.border_width_bottom = 2 if current_tab == k else 0
		sb.border_color = Color.CYAN
		sb.content_margin_top = 8; sb.content_margin_bottom = 8
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		
		b.modulate = Color.CYAN if current_tab == k else Color(0.7, 0.7, 0.7)
		b.pressed.connect(func(): current_tab = k; _build_ui())
		tab_bar.add_child(b)
	
	var sep = Control.new(); sep.custom_minimum_size.y = 10; main_v.add_child(sep)
	
	# 2. Área de Trabajo (Scrollable) con estilo oscuro
	var scroll = ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; main_v.add_child(scroll)
	var content = VBoxContainer.new(); content.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(content)
	content.add_theme_constant_override("separation", 12)
	
	# 3. Renderizado según Tab (DELEGADO A MÓDULOS)
	match current_tab:
		"ships": mod_ships.render(content)
		"enemies": mod_enemies.render(content)
		"modes": mod_modes.render(content)
		"zones": mod_world.render_zones(content)
		"map": mod_world.render_map_selection(content)
		"items": mod_items.render_items(content)
		"ammo": mod_items.render_ammo(content)
		"spheres": mod_world.render_spheres(content)
	
	# 4. Botón de Guardado Maestro Mejorado
	var save_p = PanelContainer.new(); main_v.add_child(save_p)
	var s_sb = StyleBoxFlat.new(); s_sb.bg_color = Color(0.1, 0.5, 0.2, 0.4); s_sb.set_border_width_all(1); s_sb.border_color = Color.GREEN
	save_p.add_theme_stylebox_override("panel", s_sb)
	
	var save_btn = Button.new(); save_btn.text = "Sincronizar Cambios con el Universo (SERVER)"; save_btn.flat = true
	save_btn.pressed.connect(_on_save_global_pressed)
	save_p.add_child(save_btn)


func _on_open_map_pressed():
	var world = get_tree().get_first_node_in_group("world_node")
	if not is_instance_valid(world): return
	
	var hud = world.get_node_or_null("HUD")
	if not hud: hud = world # Fallback si no hay nodo HUD
	
	var amap = hud.get_node_or_null("AdminMap")
	if not amap:
		# Instanciar dinámicamente si no existe
		var script = load("res://scripts/ui/AdminMap.gd")
		if script:
			amap = Control.new()
			amap.name = "AdminMap"
			amap.set_script(script)
			hud.add_child(amap)
			print("[ADMIN] Monitor Táctico instanciado en el HUD.")
	
	if is_instance_valid(amap):
		amap.visible = !amap.visible
		if amap.visible:
			amap.get_parent().move_child(amap, amap.get_parent().get_child_count() - 1)
			print("[ADMIN] Monitor Táctico activado.")
	
	visible = false # Cerrar el panel admin para ver el mapa

# --- HELPERS UI ---
func _create_card(parent, title):
	var p = PanelContainer.new(); parent.add_child(p)
	var sb = StyleBoxFlat.new(); sb.bg_color = Color(0, 0.2, 0.3, 0.2); sb.set_border_width_all(1); sb.border_color = Color(0, 0.8, 1, 0.3)
	p.add_theme_stylebox_override("panel", sb)
	
	var vb = VBoxContainer.new(); vb.add_theme_constant_override("separation", 8); p.add_child(vb)
	var l = Label.new(); l.text = title; l.modulate = Color.CYAN; l.add_theme_font_size_override("font_size", 11); vb.add_child(l)
	return vb

func _create_grid(parent, cols):
	var g = GridContainer.new(); g.columns = cols; g.add_theme_constant_override("h_separation", 15); parent.add_child(g)
	return g

func _add_input(parent, label, val, on_change, is_text = false):
	var hb = VBoxContainer.new(); parent.add_child(hb)
	var l = Label.new(); l.text = label; l.add_theme_font_size_override("font_size", 9); l.modulate.a = 0.5; hb.add_child(l)
	
	var display_val = val
	if not is_text:
		# v226.55: ELIMINACIÓN TOTAL DE DECIMALES (Pedido del usuario para limpieza visual)
		display_val = str(int(float(val)))
	
	var inp = LineEdit.new(); inp.text = str(display_val); inp.custom_minimum_size = Vector2(100, 0); hb.add_child(inp)
	inp.text_changed.connect(on_change)

func _add_color_input(parent, label, val, on_change):
	var hb = VBoxContainer.new(); parent.add_child(hb)
	var l = Label.new(); l.text = label; l.add_theme_font_size_override("font_size", 9); l.modulate.a = 0.5; hb.add_child(l)
	
	var cp = ColorPickerButton.new()
	cp.color = Color(val)
	cp.custom_minimum_size = Vector2(100, 30)
	hb.add_child(cp)
	cp.color_changed.connect(on_change)

func _refresh_ui(): _build_ui()

func _on_save_global_pressed():
	# Enviar TODA la configuración al servidor
	var config = {
		"shipModels": GameConstants.SHIP_MODELS,
		"enemyModels": GameConstants.ENEMY_MODELS,
		"shopItems": GameConstants.SHOP_ITEMS,
		"ammoMultipliers": GameConstants.AMMO_MULTIPLIERS,
		"hordeConfig": GameConstants.HORDES_CONFIG,
		"skillsData": GameConstants.SKILLS_DATA,
		"mapsConfig": GameConstants.MAPS_CONFIG
	}
	NetworkManager.send_event("saveAdminConfig", config)
	print("[ADMIN] Configuración Global enviada al servidor.")
	visible = false

func _create_drag_handler():
	var handle = Panel.new(); handle.name = "Header"; handle.custom_minimum_size = Vector2(500, 25)
	var sb = StyleBoxFlat.new(); sb.bg_color = Color(0, 0, 0, 0.0); handle.add_theme_stylebox_override("panel", sb)
	add_child(handle); move_child(handle, 0)

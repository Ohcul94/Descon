extends "res://scripts/systems/HUDWindow.gd"

# AdminPanel.gd (Godot Master Admin v3.0)
# Portabilidad total del sistema legacy con soporte para edición en tiempo real.

var current_tab = "ships"

func _ready():
	window_id = "AdminPanel"
	header_height = 30
	z_index = 200 # Por encima de todo
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	super._ready()
	_create_drag_handler()
	
	# v190.60: Sincronía de Dimensiones al 85%
	get_viewport().size_changed.connect(_update_window_size)
	_update_window_size()
	
	# v190.50: Limpiar UI vieja y preparar contenedor dinámico
	for n in get_children(): if n.name != "Header": n.queue_free()
	
	var main_v = VBoxContainer.new()
	main_v.name = "MainVBox"
	main_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_v.offset_top = 35; main_v.offset_bottom = -10; main_v.offset_left = 10; main_v.offset_right = -10
	add_child(main_v)
	
	_build_ui()

func _input(event):
	# v190.65: Solo capturar clic para el botón cerrar [X] del 85%
	if event is InputEventMouseButton and event.pressed and visible:
		var screen_size = get_viewport_rect().size
		var r_size = Vector2(screen_size.x * 0.85, screen_size.y * 0.85)
		var r_pos = (screen_size - r_size) / 2
		var x_rect = Rect2(r_pos.x + r_size.x - 35, r_pos.y + 8, 25, 18)
		if x_rect.has_point(event.position): toggle(); get_viewport().set_input_as_handled()

func toggle():
	visible = !visible
	if visible: 
		_update_window_size()
		_refresh_ui()

func _update_window_size():
	var screen_size = get_viewport_rect().size
	var target_w = screen_size.x * 0.85
	var target_h = screen_size.y * 0.85
	
	custom_minimum_size = Vector2(target_w, target_h)
	size = custom_minimum_size
	
	# Centrar en pantalla
	position = (screen_size - size) / 2.0
	
	# Actualizar cabecera si existe
	var header = get_node_or_null("Header")
	if header: header.custom_minimum_size.x = target_w

func _build_ui():
	var main_v = get_node_or_null("MainVBox")
	if not main_v: return
	for n in main_v.get_children(): n.queue_free()
	
	# 1. Barra de Pestañas
	var tab_bar = HBoxContainer.new(); main_v.add_child(tab_bar)
	var tabs = {"ships": "NAVES", "enemies": "ENEMIGOS", "items": "ITEMS", "ammo": "MUNICIÓN"}
	for k in tabs:
		var b = Button.new(); b.text = tabs[k]; b.size_flags_horizontal = 3; b.flat = true
		b.modulate = Color.CYAN if current_tab == k else Color.WHITE
		b.pressed.connect(func(): current_tab = k; _build_ui())
		tab_bar.add_child(b)
	
	# 2. Área de Trabajo (Scrollable)
	var scroll = ScrollContainer.new(); scroll.size_flags_vertical = 3; main_v.add_child(scroll)
	var content = VBoxContainer.new(); content.size_flags_horizontal = 3; scroll.add_child(content)
	
	# 3. Renderizado según Tab
	match current_tab:
		"ships": _render_ships(content)
		"enemies": _render_enemies(content)
		"items": _render_items(content)
	
	# 4. Botón de Guardado Maestro
	var save_btn = Button.new(); save_btn.text = "GUARDAR CONFIGURACIÓN GLOBAL (SERVER)"; save_btn.modulate = Color.GREEN
	save_btn.pressed.connect(_on_save_global_pressed)
	main_v.add_child(save_btn)

func _render_ships(container):
	for i in range(GameConstants.SHIP_MODELS.size()):
		var ship = GameConstants.SHIP_MODELS[i]
		var card = _create_card(container, "CHASIS: " + ship.name.to_upper())
		var grid = _create_grid(card, 3)
		
		_add_input(grid, "HP", str(int(ship.hp)), func(v): GameConstants.SHIP_MODELS[i].hp = int(float(v)))
		_add_input(grid, "SH", str(int(ship.shield)), func(v): GameConstants.SHIP_MODELS[i].shield = int(float(v)))
		_add_input(grid, "SPD", str(int(ship.speed)), func(v): GameConstants.SHIP_MODELS[i].speed = int(float(v)))
		_add_input(grid, "HUBS", str(int(ship.prices.hubs)), func(v): GameConstants.SHIP_MODELS[i].prices.hubs = int(float(v)))
		_add_input(grid, "OHCU", str(int(ship.prices.ohcu)), func(v): GameConstants.SHIP_MODELS[i].prices.ohcu = int(float(v)))

func _render_enemies(container):
	for id in GameConstants.ENEMY_MODELS:
		var enemy = GameConstants.ENEMY_MODELS[id]
		var card = _create_card(container, "ENEMIGO: " + enemy.name.to_upper())
		var grid = _create_grid(card, 3)
		
		_add_input(grid, "HP", str(enemy.hp), func(v): GameConstants.ENEMY_MODELS[id].hp = int(v))
		_add_input(grid, "SH", str(enemy.shield), func(v): GameConstants.ENEMY_MODELS[id].shield = int(v))
		_add_input(grid, "DMG", str(enemy.bulletDamage), func(v): GameConstants.ENEMY_MODELS[id].bulletDamage = int(v))
		_add_input(grid, "RATE", str(enemy.fireRate), func(v): GameConstants.ENEMY_MODELS[id].fireRate = int(v))
		_add_input(grid, "REWARD", str(enemy.rewardHubs), func(v): GameConstants.ENEMY_MODELS[id].rewardHubs = int(v))

func _render_items(container):
	for cat in ["weapons", "shields", "engines"]:
		var label = Label.new(); label.text = "\nCATEGORÍA: " + cat.to_upper(); label.modulate = Color.GOLD; container.add_child(label)
		var list = GameConstants.SHOP_ITEMS.get(cat, [])
		for i in range(list.size()):
			var item = list[i]
			var card = _create_card(container, item.name.to_upper())
			var grid = _create_grid(card, 2)
			_add_input(grid, "BASE", str(item.get("base", 0)), func(v): GameConstants.SHOP_ITEMS[cat][i].base = int(v))
			_add_input(grid, "HUBS", str(item.prices.hubs), func(v): GameConstants.SHOP_ITEMS[cat][i].prices.hubs = int(v))

# --- HELPERS UI ---
func _create_card(parent, title):
	var p = PanelContainer.new(); parent.add_child(p)
	var vb = VBoxContainer.new(); p.add_child(vb)
	var l = Label.new(); l.text = title; l.modulate = Color.CYAN; vb.add_child(l)
	return vb

func _create_grid(parent, cols):
	var g = GridContainer.new(); g.columns = cols; parent.add_child(g)
	return g

func _add_input(parent, label, val, on_change):
	var hb = HBoxContainer.new(); parent.add_child(hb)
	var l = Label.new(); l.text = label; l.custom_minimum_size = Vector2(50, 0); hb.add_child(l)
	# v190.75: Forzar visualización de Enteros en el input de Admin
	var display_val = str(int(float(val)))
	var inp = LineEdit.new(); inp.text = display_val; inp.custom_minimum_size = Vector2(80, 0); hb.add_child(inp)
	inp.text_changed.connect(on_change)

func _refresh_ui(): _build_ui()

func _on_save_global_pressed():
	# Enviar TODA la configuración al servidor
	var config = {
		"shipModels": GameConstants.SHIP_MODELS,
		"enemyModels": GameConstants.ENEMY_MODELS,
		"shopItems": GameConstants.SHOP_ITEMS,
		"ammoMultipliers": GameConstants.AMMO_MULTIPLIERS
	}
	NetworkManager.send_event("saveAdminConfig", config)
	print("[ADMIN] Configuración Global enviada al servidor.")
	visible = false

func _create_drag_handler():
	var handle = Panel.new(); handle.name = "Header"; handle.custom_minimum_size = Vector2(500, 25)
	var sb = StyleBoxFlat.new(); sb.bg_color = Color(0, 0, 0, 0.8); sb.border_width_bottom = 1; sb.border_color = Color.CYAN; handle.add_theme_stylebox_override("panel", sb)
	var label = Label.new(); label.text = "SISTEMA DE CONTROL GALÁCTICO (MASTER ADMIN)"; label.add_theme_font_size_override("font_size", 9); label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); label.modulate = Color.CYAN; handle.add_child(label); add_child(handle); move_child(handle, 0)

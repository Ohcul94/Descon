extends "res://scripts/systems/HUDWindow.gd"

# AdminMap.gd (v1.0 - Galactic Master View)
# Mapa en tiempo real para administración y monitoreo de sectores.

var world_size: float = 4000.0
var current_sector_name: String = "SECTOR CENTRAL"

var zoom: float = 1.0
var offset: Vector2 = Vector2.ZERO
var r_pos: Vector2 = Vector2(10, 40)
var r_margin: Vector2 = Vector2(20, 50)
var is_embedded: bool = false

func _ready():
	window_id = "AdminMap"
	header_height = 30
	# visible = false
	z_index = 250
	
	super._ready()
	
	if not is_embedded:
		_create_drag_handler()
		
		# v1.1: Fondo oscuro semitransparente (Solo en modo ventana)
		var bg = ColorRect.new()
		bg.name = "Background"
		bg.color = Color(0, 0.05, 0.1, 0.95)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
		move_child(bg, 0)
	
	await get_tree().process_frame
	queue_redraw()
	
	custom_minimum_size = Vector2(600, 600)
	size = custom_minimum_size
	
	# Conexión para actualizar tamaño del mundo
	var world = get_tree().get_first_node_in_group("world_node")
	if is_instance_valid(world):
		# v1.2: Intentar detectar tamaño dinámico
		if "WORLD_DRAW_SIZE" in world: world_size = world.WORLD_DRAW_SIZE

func _process(_delta):
	if visible:
		queue_redraw()

func _draw():
	if not visible: return
	
	var r_size = (size - r_margin)
	if r_size.x <= 0 or r_size.y <= 0: return # Protección v215.30
	
	var map_rect = Rect2(r_pos, r_size).abs()
	
	draw_rect(map_rect, Color(0, 0.2, 0.3, 0.3))
	draw_rect(map_rect, Color(0, 0.8, 1, 0.3), false, 1.0)
	
	var map_scale = (r_size.x / world_size) * zoom
	
	# Dibujar Grilla
	var grid_step = 500.0 * map_scale
	if grid_step > 5:
		for i in range(1, int(world_size / 500.0)):
			var d = i * grid_step
			draw_line(r_pos + Vector2(d, 0), r_pos + Vector2(d, r_size.y), Color(1,1,1,0.05))
			draw_line(r_pos + Vector2(0, d), r_pos + Vector2(r_size.x, d), Color(1,1,1,0.05))

	# Dibujar Entidades
	var entities = get_tree().get_nodes_in_group("entities")
	
	for ent in entities:
		if not is_instance_valid(ent) or ent.get("is_dead") == true: continue
		
		# Calcular posición relativa al mundo (Asumiendo 0,0 a WORLD_SIZE,WORLD_SIZE)
		# Nota: En este juego parece que el mundo nace en 0,0 y va a 4000,4000
		var pos = ent.global_position * map_scale
		var draw_p = r_pos + pos
		
		# Verificar que esté dentro del visualizador
		if not map_rect.has_point(draw_p): continue
		
		var color = Color.WHITE
		var size_dot = 3.0
		var label = ""
		
		if ent.is_in_group("player"):
			color = Color.GREEN
			size_dot = 5.0
			var uname = ent.get("username"); if uname == null: uname = "PILOTO"
			label = "YO: " + str(uname)
		elif ent.is_in_group("remote_players"):
			color = Color.CYAN
			size_dot = 4.0
			var uname = ent.get("username"); if uname == null: uname = "ALIADO"
			label = str(uname)
		elif ent.is_in_group("enemies"):
			color = Color.RED
			size_dot = 3.5
			var e_type = ent.get("entity_type"); if e_type == null: e_type = 1
			var uname = ent.get("username"); if uname == null: uname = "ENEMIGO"
			label = "E (T" + str(e_type) + "): " + str(uname)
			if int(e_type) >= 4:
				size_dot = 8.0
				color = Color.MAGENTA
				var bname = ent.get("username"); if bname == null: bname = "JEFE"
				label = "BOSS: " + str(bname)
		elif ent.name.to_lower().contains("loot") or ent.name.to_lower().contains("item") or ent.name.to_lower().contains("cargo"):
			color = Color.GOLD
			size_dot = 4.0
			label = "LOOT: " + str(ent.name)
		else:
			color = Color.GRAY
			size_dot = 2.0
			label = "OBJ: " + str(ent.name)

		draw_circle(draw_p, size_dot, color)
		
		# Dibujar HP/SH mini
		var c_hp = ent.get("current_hp"); if c_hp == null: c_hp = 0.0
		var m_hp = ent.get("max_hp"); if m_hp == null or m_hp == 0: m_hp = 1.0
		var hp_pct = clamp(float(c_hp) / float(m_hp), 0, 1)
		draw_rect(Rect2(draw_p + Vector2(-10, size_dot + 2), Vector2(20 * hp_pct, 2)), Color.GREEN)
		
		# Texto
		var f = get_theme_font("font")
		draw_string(f, draw_p + Vector2(size_dot + 2, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, color)

	# Info del Sector
	var f_title = get_theme_font("font")
	draw_string(f_title, Vector2(20, size.y - 15), "VISTA TÁCTICA: " + current_sector_name + " | ZOOM: " + str(snapped(zoom, 0.1)) + "x", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.CYAN)

func _create_drag_handler():
	var handle = Panel.new(); handle.name = "Header"; handle.custom_minimum_size = Vector2(size.x, 30)
	var sb = StyleBoxFlat.new(); sb.bg_color = Color(0, 0.05, 0.1, 1); sb.border_width_bottom = 2; sb.border_color = Color.CYAN; handle.add_theme_stylebox_override("panel", sb)
	
	var label = Label.new(); label.text = "SISTEMA DE MONITOREO GALÁCTICO"; label.add_theme_font_size_override("font_size", 10); label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); label.modulate = Color.CYAN; handle.add_child(label)
	
	# Botón Cerrar
	var close = Button.new(); close.text = "[X]"; close.flat = true; close.custom_minimum_size = Vector2(30, 0); close.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	close.pressed.connect(func(): visible = false); handle.add_child(close)
	
	add_child(handle); move_child(handle, get_child_count() - 1)

func _gui_input(event):
	super._gui_input(event)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clamp(zoom + 0.1, 0.5, 5.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clamp(zoom - 0.1, 0.5, 5.0)

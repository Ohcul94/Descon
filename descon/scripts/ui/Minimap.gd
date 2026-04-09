extends Control

# Minimap.gd (Tactical Radar v141.80 - RESTORED FEATURE PARITY)
# Gestión de radar con dibujo directo para rendimiento y AUTOPILOTO visual.

const WORLD_DRAW_SIZE = 4000.0

var world_size: float

func _input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# v165.60: Detección global para evitar que la ventana bloquee el radar
			var global_m_pos = get_global_mouse_position()
			if get_global_rect().has_point(global_m_pos):
				var local_m_pos = global_m_pos - global_position
				var map_pos = local_m_pos / size
				var target_world_pos = map_pos * world_size
				
				var p = get_tree().get_first_node_in_group("player")
				if is_instance_valid(p) and p.has_method("set_autopilot"):
					p.set_autopilot(target_world_pos)
					print("[NAV] DESTINO FIJADO: ", target_world_pos)
					get_viewport().set_input_as_handled() # Consumir evento

func _ready():
	world_size = GameConstants.GAME_CONFIG.get("worldSize", WORLD_DRAW_SIZE)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true
	# v141.80: Fondo original restaurado (adiós al rosa de diagnóstico)
	if not get_node_or_null("BG"):
		var bg = ColorRect.new()
		bg.name = "BG"
		bg.color = Color(0, 0.08, 0.12, 0.5) 
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE # Evitar que el BG bloquee al Minimap
		bg.show_behind_parent = true
		add_child(bg)

func _process(_delta):
	if not visible: return
	# v141.80: Usamos queue_redraw() para eficiencia, no instanciamos nodos.
	queue_redraw()

func _draw():
	var player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player): return
	
	var r_size = size
	var map_scale = r_size.x / world_size
	
	# 1. Dibujar Trayectoria del Autopiloto (Línea punteada del JS v66.6)
	if player.get("is_autopilot_active") and player.get("target_position"):
		var start_pos = player.global_position * map_scale
		var end_pos = player.target_position * map_scale
		
		var dist = start_pos.distance_to(end_pos)
		if dist > 5:
			var direction = (end_pos - start_pos).normalized()
			var dash_length = 4.0
			var gap_length = 4.0
			var current_pos = start_pos
			var dash_color = Color(0, 1, 0, 0.5)
			
			while start_pos.distance_to(current_pos) < dist:
				var next_pos = current_pos + direction * dash_length
				if start_pos.distance_to(next_pos) > dist: next_pos = end_pos
				draw_line(current_pos, next_pos, dash_color, 1.0)
				current_pos = next_pos + direction * gap_length
				if start_pos.distance_to(current_pos) >= dist: break
				
		# Punto de destino
		draw_circle(end_pos, 3, Color(0, 1, 0, 0.8))
	
	# 2. Dibujar Jugadores Remotos (Celeste Neón)
	for ent in get_tree().get_nodes_in_group("remote_players"):
		if is_instance_valid(ent):
			var pos = ent.global_position * map_scale
			draw_circle(pos, 2.5, Color(0, 1, 1)) # #00ffff

	# 3. Dibujar Enemigos (Naranja JS v13.1.3)
	for ent in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(ent):
			var pos = ent.global_position * map_scale
			draw_circle(pos, 2.0, Color(1, 0.4, 0)) # #ff6600

	# 4. Jugador Local (Punto Verde + Cuadrito de barrido)
	var local_pos = player.global_position * map_scale
	draw_circle(local_pos, 3.0, Color(0, 1, 0))
	draw_rect(Rect2(local_pos - Vector2(5, 5), Vector2(10, 10)), Color(0, 1, 0, 0.2), false, 1.0)

	# Borde del radar
	draw_rect(Rect2(Vector2.ZERO, r_size), Color(0, 1, 1, 0.1), false, 1.0)

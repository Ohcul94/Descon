extends Control

# Minimap.gd (Tactical Radar v141.80 - RESTORED FEATURE PARITY)
# Gestión de radar con dibujo directo para rendimiento y AUTOPILOTO visual.

const WORLD_DRAW_SIZE = 4000.0

var world_size: float
var info_label: Label = null

func _input(event):
	if event is InputEventMouseButton and event.pressed:
		# v269.150: Bloqueo de navegación durante edición de HUD
		var hud = get_tree().get_first_node_in_group("hud")
		if hud and hud.get("is_editing_layout"): return

		if event.button_index == MOUSE_BUTTON_LEFT:
			# v244.85: Bloqueo inteligente si hay menús superpuestos (F1 / F2)
			var screen_size = get_viewport().get_visible_rect().size
			var r_size = Vector2(screen_size.x * 0.85, screen_size.y * 0.85)
			var r_pos = (screen_size - r_size) / 2.0
			var menu_rect = Rect2(r_pos, r_size)
			
			if menu_rect.has_point(event.position):
				var inv = get_tree().get_first_node_in_group("inventory_ui")
				var admin = get_tree().get_first_node_in_group("admin_panel_ui")
				if (inv and inv.visible) or (admin and admin.visible):
					return # Ignorar clic, cae en el área de un menú abierto

			# v165.60: Detección global para evitar que la ventana bloquee el radar
			var global_m_pos = get_global_mouse_position()
			if get_global_rect().has_point(global_m_pos):
				var local_m_pos = global_m_pos - global_position
				var map_pos = local_m_pos / size
				var target_world_pos = map_pos * world_size
				
				var p = get_tree().get_first_node_in_group("player")
				if is_instance_valid(p) and p.has_method("set_autopilot"):
					if p.get_meta("spawn_locked", false):
						print("[NAV] BLOQUEADO: No puedes fijar rumbo mientras esté activa la barrera de spawn.")
						get_viewport().set_input_as_handled()
						return
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
		
	# Inyectar Label de coordenadas y zona estilo neón
	info_label = Label.new()
	info_label.name = "MapInfoLabel"
	info_label.add_theme_font_size_override("font_size", 10)
	info_label.add_theme_color_override("font_color", Color(0, 1, 1, 0.95)) # Cian
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0, 0.04, 0.08, 0.75)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0, 1, 1, 0.3)
	sb.set_corner_radius_all(3)
	info_label.add_theme_stylebox_override("normal", sb)
	
	# Desactivar clipping para permitir dibujar fuera de la ventana del minimapa
	clip_contents = false
	if get_parent() is Control:
		get_parent().clip_contents = false
		
	add_child(info_label)

func _process(_delta):
	if visible:
		queue_redraw()
		_update_info_label()

func _update_info_label():
	if not is_instance_valid(info_label): return
	var player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		info_label.text = ""
		return
		
	var current_zone_id = str(player.current_zone) if "current_zone" in player else "1"
	var z_name = "SECTOR DESCONOCIDO"
	if current_zone_id in GameConstants.MAPS_CONFIG:
		z_name = GameConstants.MAPS_CONFIG[current_zone_id].name
	elif int(current_zone_id) >= 500:
		z_name = "INSTANCIA PRIVADA"
	else:
		z_name = "SECTOR " + str(current_zone_id).pad_zeros(2)
		
	var px = int(player.global_position.x)
	var py = int(player.global_position.y)
	info_label.text = "%s | X: %d, Y: %d" % [z_name.to_upper(), px, py]
	
	# Centrar dinámicamente adentro del minimapa en la parte superior
	info_label.reset_size()
	info_label.position.x = (size.x - info_label.size.x) / 2.0
	info_label.position.y = 8

func _draw():
	var player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player): return
	
	var current_zone_id = str(player.current_zone) if "current_zone" in player else "1"
	
	# CALCULAR TAMAÑO DE MUNDO DINÁMICAMENTE PARA RADAR
	# 1. Intentar obtener el tamaño del mapa cargado actualmente en pantalla
	var current_map = get_tree().get_first_node_in_group("map")
	if not is_instance_valid(current_map):
		var p_parent = player.get_parent()
		if is_instance_valid(p_parent) and "current_map_node" in p_parent and is_instance_valid(p_parent.current_map_node):
			current_map = p_parent.current_map_node
			
	var is_altar_def_mode = (current_zone_id == "9")
	var full_cfg_temp = GameConstants.get("FULL_CONFIG")
	if full_cfg_temp and full_cfg_temp.has("gameModes") and full_cfg_temp.gameModes.has("altar_defense"):
		var ad_maps = full_cfg_temp.gameModes.altar_defense.get("maps", [])
		for m in ad_maps:
			if int(m) == int(current_zone_id):
				is_altar_def_mode = true
				break

	if is_altar_def_mode:
		world_size = 10000.0
		if full_cfg_temp and full_cfg_temp.gameModes.has("altar_defense"):
			var ad = full_cfg_temp.gameModes.altar_defense
			if ad.has("width") and float(ad.width) > 0:
				world_size = float(ad.width)
	elif is_instance_valid(current_map) and "world_size" in current_map and float(current_map.world_size) > 0:
		world_size = float(current_map.world_size)
	else:
		# 2. Fallback secundario basado en ID de zona
		if current_zone_id == "10" or current_zone_id == "11" or current_zone_id.begins_with("extract_"):
			world_size = 10000.0
			if GameConstants.get("FULL_CONFIG") and GameConstants.FULL_CONFIG.has("gameModes") and GameConstants.FULL_CONFIG.gameModes.has("extraction"):
				var ext = GameConstants.FULL_CONFIG.gameModes.extraction
				if ext.has("width"):
					world_size = float(ext.width)
		else:
			var is_dungeon = current_zone_id == "1" or int(current_zone_id) > 2
			world_size = 2000.0 if is_dungeon else 4000.0
		
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
	
	# 2. Dibujar Jugadores Remotos (Verde=Clan, Celeste=Party, Naranja=Otros)
	var pm = get_node_or_null("/root/PartyManager")
	var vision_r = 1300.0
	if is_instance_valid(player):
		if "vision_range" in player:
			vision_r = player.vision_range
		else:
			if "current_ship_id" in player and GameConstants.SHIP_MODELS:
				for ship in GameConstants.SHIP_MODELS:
					if ship.id == player.current_ship_id:
						vision_r = float(ship.get("vision", 1300.0))
						break

	for ent in get_tree().get_nodes_in_group("remote_players"):
		if is_instance_valid(ent) and not ent.get("is_dead") and ent.visible:
			# Validar si está en rango de visión real
			if is_instance_valid(player) and player.global_position.distance_to(ent.global_position) > vision_r:
				continue

			var is_clan = false
			var is_party = false
			
			if is_instance_valid(player):
				var ent_name = str(ent.get("username")).to_upper()
				
				# 1. PRIORIDAD: Equipo/Party (Celeste) - Comparar por nombre
				if pm and pm.current_party:
					var names = pm.current_party.get("names", [])
					if names is Array:
						for n in names:
							if str(n).to_upper() == ent_name:
								is_party = true
								break
				
				# 2. Clan (Verde) - Solo si no es party (Prevalece Celeste)
				if not is_party:
					var my_clan = player.get("clanId")
					var remote_clan = ent.get("clanId")
					if my_clan != null and str(my_clan) != "" and str(my_clan) != "0":
						if str(my_clan) == str(remote_clan): is_clan = true
					
					if not is_clan:
						var my_tag_raw = player.get("clan_tag")
						var remote_tag_raw = ent.get("clan_tag")
						var my_tag = str(my_tag_raw).strip_edges().to_lower() if my_tag_raw != null else ""
						var remote_tag = str(remote_tag_raw).strip_edges().to_lower() if remote_tag_raw != null else ""
						if my_tag != "" and my_tag == remote_tag:
							is_clan = true
			
			# v245.90: Filtro de Sigilo (Invisibilidad)
			if ent.get("isInvisible"):
				if not (is_clan or is_party): continue # Invisibilidad total para enemigos
				
			var pos = ent.global_position * map_scale
			var dot_color = Color(1, 1, 0) # Amarillo por defecto (Otros Jugadores)
			if is_clan: dot_color = Color(0, 1, 0) # Verde
			elif is_party: dot_color = Color(0, 1, 1) # Celeste
			
			if ent.get("isInvisible"): dot_color.a = 0.4
			draw_circle(pos, 2.5, dot_color)

	# 3. Dibujar Enemigos NPC (Naranja JS v13.1.3)
	for ent in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(ent) and not ent.get("is_dead") and ent.visible:
			# Validar si está en rango de visión real
			if is_instance_valid(player) and player.global_position.distance_to(ent.global_position) > vision_r:
				continue

			var pos = ent.global_position * map_scale
			draw_circle(pos, 2.0, Color(1, 0.4, 0)) # #ff6600

	# 4. Dibujar Portales de Extracción (Cian de Neón con efecto de pulso!)
	if current_zone_id == "10" or current_zone_id == "11" or current_zone_id.begins_with("extract_"):
		var extract_points = []
		if GameConstants.get("FULL_CONFIG") and GameConstants.FULL_CONFIG.has("gameModes") and GameConstants.FULL_CONFIG.gameModes.has("extraction"):
			var ext = GameConstants.FULL_CONFIG.gameModes.extraction
			if ext.has("extractPoints"):
				extract_points = ext.extractPoints
				
		if extract_points.size() == 0:
			# Fallback
			extract_points = [
				{"x": 2974, "y": 5038, "label": "Punto Alfa"},
				{"x": 6920, "y": 5070, "label": "Punto Beta"},
				{"x": 5019, "y": 3025, "label": "Punto Gamma"},
				{"x": 5003, "y": 7019, "label": "Punto Delta"}
			]
			
		var pulse = 0.5 + sin(Time.get_ticks_msec() * 0.005) * 0.3
		for pt in extract_points:
			var pt_pos = Vector2(float(pt.x), float(pt.y)) * map_scale
			
			# Dibujar halo cian de portal radar
			draw_circle(pt_pos, 4.5, Color(0, 0.9, 1.0, 0.8))
			draw_circle(pt_pos, 7.0 + pulse * 2.0, Color(0, 0.9, 1.0, 0.3), false, 1.0)
			
			# Mostrar primera letra de la zona ("A", "B", "G", "D")
			var label = str(pt.get("label", "Portal")).to_lower()
			var letter = "E"
			if label.contains("alfa"): letter = "A"
			elif label.contains("beta"): letter = "B"
			elif label.contains("gamma"): letter = "G"
			elif label.contains("delta"): letter = "D"
			
			var font = get_theme_font("font")
			draw_string(font, pt_pos + Vector2(-3, 3), letter, HORIZONTAL_ALIGNMENT_CENTER, -1, 7, Color.WHITE)

	# 4.5 Dibujar Altar si es zona de Defensa del Altar (Verde neón místico con una 'A' blanca)
	var is_altar_defense = false
	var altar_pos = Vector2(5000.0, 5000.0)
	
	# Fallback directo por ID de zona
	if current_zone_id == "9":
		is_altar_defense = true
		
	var full_cfg = GameConstants.get("FULL_CONFIG")
	if full_cfg and full_cfg.has("gameModes") and full_cfg.gameModes.has("altar_defense"):
		var ad = full_cfg.gameModes.altar_defense
		var ad_maps = ad.get("maps", [])
		for m in ad_maps:
			if int(m) == int(current_zone_id):
				is_altar_defense = true
				break
		if is_altar_defense:
			var a_pos = ad.get("altarPos", {"x": 5000.0, "y": 5000.0})
			altar_pos = Vector2(float(a_pos.x), float(a_pos.y))

	if is_altar_defense:
		var alt_draw_pos = altar_pos * map_scale
		var pulse = 0.5 + sin(Time.get_ticks_msec() * 0.004) * 0.3
		draw_circle(alt_draw_pos, 6.0, Color(0.0, 1.0, 0.5, 0.9)) # Círculo verde brillante
		draw_circle(alt_draw_pos, 9.0 + pulse * 3.0, Color(0.0, 1.0, 0.5, 0.35), false, 1.0) # Brillo
		var font = get_theme_font("font")
		draw_string(font, alt_draw_pos + Vector2(-3.5, 3.5), "A", HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color.WHITE)
		
		# Dibujar Spawns de Jugadores en el radar (Verde/Amarillo suave)
		if full_cfg and full_cfg.has("gameModes") and full_cfg.gameModes.has("altar_defense"):
			var ad = full_cfg.gameModes.altar_defense
			if ad.has("spawnPoints") and ad.spawnPoints is Array:
				for sp in ad.spawnPoints:
					if sp is Dictionary and sp.has("x") and sp.has("y"):
						var sp_pos = Vector2(float(sp.x), float(sp.y)) * map_scale
						var radius_canvas = float(sp.get("radius", 200.0)) * map_scale
						draw_circle(sp_pos, 2.0, Color(0.8, 0.9, 0.0, 0.8))
						draw_circle(sp_pos, radius_canvas, Color(0.8, 0.9, 0.0, 0.12), false, 1.0)
			
			# Dibujar Spawners de Enemigos en el radar (Rojo de advertencia)
			if ad.has("spawners") and ad.spawners is Array:
				for s in ad.spawners:
					if s is Dictionary and s.has("x") and s.has("y"):
						var s_pos = Vector2(float(s.x), float(s.y)) * map_scale
						var radius_canvas = float(s.get("radius", 300.0)) * map_scale
						draw_circle(s_pos, 2.0, Color(1.0, 0.2, 0.2, 0.8))
						draw_circle(s_pos, radius_canvas, Color(1.0, 0.2, 0.2, 0.12), false, 1.0)


	# 6. Dibujar Baúles en el Lobby (Punto dorado brillante con una 'B' blanca)
	for vault in get_tree().get_nodes_in_group("vaults"):
		if is_instance_valid(vault) and vault.visible:
			var vault_pos = vault.global_position * map_scale
			draw_circle(vault_pos, 5.0, Color(1.0, 0.75, 0.0, 0.9)) # Círculo dorado brillante
			draw_circle(vault_pos, 7.0, Color(1.0, 0.75, 0.0, 0.25)) # Brillo exterior suave
			var font = get_theme_font("font")
			draw_string(font, vault_pos + Vector2(-2.5, 3.0), "B", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)

	# 5. Jugador Local (Punto Blanco Puro)
	var local_pos = player.global_position * map_scale
	draw_circle(local_pos, 3.5, Color.WHITE)

	# Borde del radar
	draw_rect(Rect2(Vector2.ZERO, r_size), Color(0, 1, 1, 0.1), false, 1.0)

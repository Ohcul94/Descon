extends Control

# Minimap.gd (Tactical Radar v200.0 - SYNC FIX + WORLD OBJECTS)
# Gestión de radar con dibujo directo para rendimiento y AUTOPILOTO visual.
# SYNC FIX: Lee worldW/worldH desde MAPS_CONFIG (mismo origen que AdminDash)

const WORLD_DEFAULT_SIZE = 10000.0

# world_size se mantiene por compatibilidad legado; usar worldW/worldH para dibujo
var world_size: float = WORLD_DEFAULT_SIZE
var info_label: Label = null

func get_current_world_dimensions() -> Vector2:
	var player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		return Vector2(WORLD_DEFAULT_SIZE, WORLD_DEFAULT_SIZE)
		
	var current_zone_id = str(player.current_zone) if "current_zone" in player else "1"
	var worldW: float = WORLD_DEFAULT_SIZE
	var worldH: float = WORLD_DEFAULT_SIZE
	
	var full_cfg_temp = GameConstants.get("FULL_CONFIG")
	
	# 1. PRIORIDAD: leer width/height desde mapsConfig del servidor
	if current_zone_id in GameConstants.MAPS_CONFIG:
		var mc = GameConstants.MAPS_CONFIG[current_zone_id]
		if mc.has("width") and float(mc.width) > 0:
			worldW = float(mc.width)
		if mc.has("height") and float(mc.height) > 0:
			worldH = float(mc.height)
	
	# 2. Sobreescribir con dimensiones de modos de juego especiales
	var is_altar_def_mode = false
	if full_cfg_temp and full_cfg_temp.has("gameModes") and full_cfg_temp.gameModes.has("altar_defense"):
		var ad_maps = full_cfg_temp.gameModes.altar_defense.get("maps", [])
		for m in ad_maps:
			if int(m) == int(current_zone_id):
				is_altar_def_mode = true
				break
		if is_altar_def_mode:
			var ad = full_cfg_temp.gameModes.altar_defense
			if ad.has("width") and float(ad.width) > 0:
				worldW = float(ad.width)
			if ad.has("height") and float(ad.height) > 0:
				worldH = float(ad.height)
	
	if full_cfg_temp and full_cfg_temp.has("gameModes") and full_cfg_temp.gameModes.has("extraction"):
		var ext_maps = full_cfg_temp.gameModes.extraction.get("maps", [])
		for em in ext_maps:
			if int(em) == int(current_zone_id):
				var ext = full_cfg_temp.gameModes.extraction
				if ext.has("width") and float(ext.width) > 0:
					worldW = float(ext.width)
				if ext.has("height") and float(ext.height) > 0:
					worldH = float(ext.height)
				break
	
	# 3. Fallback final: mapa cargado en escena
	var current_map = get_tree().get_first_node_in_group("map")
	if not is_instance_valid(current_map):
		var p_parent = player.get_parent()
		if is_instance_valid(p_parent) and "current_map_node" in p_parent and is_instance_valid(p_parent.current_map_node):
			current_map = p_parent.current_map_node
	if is_instance_valid(current_map) and "world_size" in current_map and float(current_map.world_size) > 0:
		if worldW == WORLD_DEFAULT_SIZE:
			worldW = float(current_map.world_size)
		if worldH == WORLD_DEFAULT_SIZE:
			worldH = float(current_map.world_size)
			
	return Vector2(worldW, worldH)

func _input(event):
	if event is InputEventMouseButton and event.pressed:
		# v269.150: Bloqueo de navegación durante edición de HUD
		var hud = get_tree().get_first_node_in_group("hud")
		if hud and hud.get("is_editing_layout"): return

		if event.button_index == MOUSE_BUTTON_RIGHT:
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

			# v269.160: Convertir con la transformada global real (soporta escala dinámica del RadarWindow en HUD editor)
			var global_m_pos = get_global_mouse_position()
			if get_global_rect().has_point(global_m_pos):
				var g_tr = get_global_transform()
				var local_m_pos = g_tr.affine_inverse() * global_m_pos
				var target_world_pos = Vector2.ZERO
				var is_rotate = get_node_or_null("/root/SettingsManager") and SettingsManager.minimap_rotate
				var p = get_tree().get_first_node_in_group("player")
				
				var dims = get_current_world_dimensions()
				var worldW = dims.x
				var worldH = dims.y
				
				var scale_uniform = min(size.x / worldW, size.y / worldH)
				if is_rotate and is_instance_valid(p):
					var p_mp = Vector2(p.global_position.x * scale_uniform, p.global_position.y * scale_uniform)
					var offset = local_m_pos - p_mp
					var derotated = p_mp + offset.rotated(PI/2 + p.rotation)
					target_world_pos = Vector2(derotated.x / max(scale_uniform, 0.001), derotated.y / max(scale_uniform, 0.001))
				else:
					var offset_x = (size.x - (worldW * scale_uniform)) / 2.0
					var offset_y = (size.y - (worldH * scale_uniform)) / 2.0
					var adjusted_m_pos = local_m_pos - Vector2(offset_x, offset_y)
					target_world_pos = Vector2(
						clamp(adjusted_m_pos.x / scale_uniform, 0.0, worldW),
						clamp(adjusted_m_pos.y / scale_uniform, 0.0, worldH)
					)
				
				if is_instance_valid(p) and p.has_method("set_autopilot"):
					if p.get_meta("spawn_locked", false):
						print("[NAV] BLOQUEADO: No puedes fijar rumbo mientras esté activa la barrera de spawn.")
						get_viewport().set_input_as_handled()
						return
					p.set_autopilot(target_world_pos)
					print("[NAV] DESTINO FIJADO: ", target_world_pos)
					get_viewport().set_input_as_handled() # Consumir evento

func _ready():
	world_size = GameConstants.GAME_CONFIG.get("worldSize", WORLD_DEFAULT_SIZE)
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
	
	var hovered_dest = ""
	var global_m_pos = get_global_mouse_position()
	var is_hovered = get_global_rect().has_point(global_m_pos)
	# v269.161: Misma conversión transform-aware que _input (escala dinámica del HUD editor)
	var local_m_pos = Vector2.ZERO
	if is_hovered:
		var g_tr_draw = get_global_transform()
		local_m_pos = g_tr_draw.affine_inverse() * global_m_pos
	
	# =====================================================================
	# SYNC FIX v200.0: Calcular worldW/worldH desde MAPS_CONFIG del servidor
	# El AdminDash usa `m.width || 10000` — ahora Godot usa la misma fuente.
	# =====================================================================
	var dims = get_current_world_dimensions()
	var worldW: float = dims.x
	var worldH: float = dims.y
	
	# Mantener world_size por compatibilidad legado
	world_size = worldW
	var r_size = size
	
	# v700.14: Escala uniforme para evitar distorsiones estiradas en mapas rectangulares (ej. Mapa 2)
	var scale_uniform: float = min(r_size.x / worldW, r_size.y / worldH)
	var scale_x: float = scale_uniform
	var scale_y: float = scale_uniform
	# map_scale legacy (para código que lo use)
	var _map_scale: float = scale_x
	
	# v800.0 NIEBLA GRIS en minimapa - overlay de celdas no exploradas
	var fog_overlay_needed = false
	var fog_grid_res = 64
	var fog_explored: Dictionary = {}
	var fog_zone_id = current_zone_id
	# Intentar obtener datos de FogOfWarManager si existe
	var fow_node = null
	var map_node_fog = get_tree().get_first_node_in_group("map")
	if is_instance_valid(map_node_fog) and "fog_of_war" in map_node_fog and is_instance_valid(map_node_fog.fog_of_war):
		fow_node = map_node_fog.fog_of_war
		if fow_node:
			# GRID_RES es const 64, no hace falta check dinámico
			fog_grid_res = 64
			if "explored_by_zone" in fow_node:
				if fow_node.explored_by_zone.has(fog_zone_id):
					fog_explored = fow_node.explored_by_zone[fog_zone_id]
				else:
					# Zona nueva sin datos aún: usar diccionario vacío (toda niebla)
					fog_explored = {}
				fog_overlay_needed = true
	# Fallback: si no hay FogOfWar (zona 1 lobby) no hay niebla
	if fog_zone_id == "1":
		fog_overlay_needed = false
 
	# --- ROTATION MODE: transform all map content around player position ---
	var is_rotate_mode = get_node_or_null("/root/SettingsManager") and SettingsManager.minimap_rotate
	var rot_angle = 0.0
	var player_mp = Vector2.ZERO
	
	# v700.14: Aplicar offsets de centrado en modo estático mediante draw_set_transform
	var offset_x: float = 0.0
	var offset_y: float = 0.0
	if not is_rotate_mode:
		offset_x = (r_size.x - (worldW * scale_uniform)) / 2.0
		offset_y = (r_size.y - (worldH * scale_uniform)) / 2.0
		draw_set_transform(Vector2(offset_x, offset_y))
	
	if is_rotate_mode:
		rot_angle = -PI/2 - player.rotation
		player_mp = Vector2(player.global_position.x * scale_x, player.global_position.y * scale_y)
		draw_set_transform_matrix(Transform2D().translated(player_mp).rotated(rot_angle).translated(-player_mp))
	
	# Dibujar niebla ANTES de entidades para que quede de fondo
	if fog_overlay_needed:
		_draw_minimap_fog(scale_x, scale_y, fog_grid_res, fog_explored, worldW, worldH, player)
	
	# 1. Dibujar Trayectoria del Autopiloto (Línea punteada del JS v66.6)
	if player.get("is_autopilot_active") and player.get("target_position"):
		var start_pos = Vector2(player.global_position.x * scale_x, player.global_position.y * scale_y)
		var end_pos = Vector2(player.target_position.x * scale_x, player.target_position.y * scale_y)
		
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
				
			var pos = Vector2(ent.global_position.x * scale_x, ent.global_position.y * scale_y)
			var dot_color = Color(1, 1, 0) # Amarillo por defecto (Otros Jugadores)
			if is_clan: dot_color = Color(0, 1, 0) # Verde
			elif is_party: dot_color = Color(0, 1, 1) # Celeste
			
			if ent.get("isInvisible"): dot_color.a = 0.4
			draw_circle(pos, 2.5, dot_color)

	# 3. Dibujar Enemigos NPC (Naranja JS v13.1.3) - Bosses/Mini-bosses en Violeta
	for ent in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(ent) and not ent.get("is_dead") and ent.visible:
			# Validar si está en rango de visión real
			if is_instance_valid(player) and player.global_position.distance_to(ent.global_position) > vision_r:
				continue

			var pos = Vector2(ent.global_position.x * scale_x, ent.global_position.y * scale_y)
			var ent_type = int(ent.get("entity_type"))
			var is_boss = ent.get("isBoss") == true
			# Puntito proporcional a la escala 3D real del enemigo (2.0 comunes, 6.0 bosses, 8.0 guardian, 9.0 pilares)
			var ent_scale = 3.0
			var mdl_3d = ent.get("_3d_model")
			if is_instance_valid(mdl_3d) and mdl_3d.scale.x > 0.0:
				ent_scale = mdl_3d.scale.x
			elif ent.get("_enemy_scale") != null:
				ent_scale = float(ent.get("_enemy_scale"))
			if ent_scale <= 0.0: ent_scale = 3.0
			var dot_r = 2.0
			# v269.162: Solo bosses (>=101, pilares 200/201) y mini-bosses reales (10 y 11). El tipo 4 es común.
			if is_boss or ent_type >= 101 or ent_type == 10 or ent_type == 11:
				dot_r = max(4.0, ent_scale * 1.5)
				draw_circle(pos, dot_r, Color(0.65, 0.25, 1.0)) # #a640ff Violeta
			else:
				draw_circle(pos, dot_r, Color(1, 0.4, 0)) # #ff6600

	# 4. Dibujar Portales de Extracción (Cian de Neón con efecto de pulso!)
	var is_extraction_zone = false
	if current_zone_id.begins_with("extract_"):
		is_extraction_zone = true
	else:
		var full_cfg_ext = GameConstants.get("FULL_CONFIG")
		if full_cfg_ext and full_cfg_ext.has("gameModes") and full_cfg_ext.gameModes.has("extraction"):
			for em in full_cfg_ext.gameModes.extraction.get("maps", []):
				if int(em) == int(current_zone_id):
					is_extraction_zone = true
					break
	if is_extraction_zone:
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
			var pt_pos = Vector2(float(pt.x) * scale_x, float(pt.y) * scale_y)
			
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
		var alt_draw_pos = Vector2(altar_pos.x * scale_x, altar_pos.y * scale_y)
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
						var sp_pos = Vector2(float(sp.x) * scale_x, float(sp.y) * scale_y)
						var radius_canvas = float(sp.get("radius", 200.0)) * scale_x
						draw_circle(sp_pos, 2.0, Color(0.8, 0.9, 0.0, 0.8))
						draw_circle(sp_pos, radius_canvas, Color(0.8, 0.9, 0.0, 0.12), false, 1.0)
			
			# Dibujar Spawners de Enemigos en el radar (Rojo de advertencia)
			if ad.has("spawners") and ad.spawners is Array:
				for s in ad.spawners:
					if s is Dictionary and s.has("x") and s.has("y"):
						var s_pos = Vector2(float(s.x) * scale_x, float(s.y) * scale_y)
						var radius_canvas = float(s.get("radius", 300.0)) * scale_x
						draw_circle(s_pos, 2.0, Color(1.0, 0.2, 0.2, 0.8))
						draw_circle(s_pos, radius_canvas, Color(1.0, 0.2, 0.2, 0.12), false, 1.0)


	# 6. Dibujar Baúles en el Lobby via grupo de nodos (Punto dorado brillante)
	for vault in get_tree().get_nodes_in_group("vaults"):
		if is_instance_valid(vault) and vault.visible:
			var vault_pos = Vector2(vault.global_position.x * scale_x, vault.global_position.y * scale_y)
			draw_circle(vault_pos, 5.0, Color(1.0, 0.75, 0.0, 0.9))
			draw_circle(vault_pos, 7.0, Color(1.0, 0.75, 0.0, 0.25))
			var font = get_theme_font("font")
			draw_string(font, vault_pos + Vector2(-2.5, 3.0), "B", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)

	# 7. Dibujar Objetos del Mundo desde MAPS_CONFIG (Baúles, Puertas, Torres)
	# Complementa los vaults de escena con los configurados en AdminDash
	var z_id_str = str(current_zone_id)
	if z_id_str in GameConstants.MAPS_CONFIG:
		var zone_cfg = GameConstants.MAPS_CONFIG[z_id_str]
		if zone_cfg.has("objects") and zone_cfg.objects is Array:
			var font = get_theme_font("font")
			for obj in zone_cfg.objects:
				if not (obj is Dictionary and obj.has("x") and obj.has("y")): continue
				var obj_pos = Vector2(float(obj.x) * scale_x, float(obj.y) * scale_y)
				var obj_type = str(obj.get("type", "chest"))
				
				match obj_type:
					"chest":
						# Baúl - Dorado brillante con 'B'
						draw_circle(obj_pos, 5.0, Color(1.0, 0.85, 0.0, 0.95))
						draw_circle(obj_pos, 7.5, Color(1.0, 0.85, 0.0, 0.2), false, 1.5)
						draw_string(font, obj_pos + Vector2(-2.5, 3.0), "B", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)
					"door":
						# Obtener destino dinámico
						var target_zone = str(obj.get("targetZoneId", obj.get("targetZone", "")))
						
						# Validar si el destino está inactivo/invisible
						if GameConstants.get("MAPS_CONFIG") and GameConstants.MAPS_CONFIG.has(target_zone):
							var target_map_cfg = GameConstants.MAPS_CONFIG[target_zone]
							if target_map_cfg.has("visible") and target_map_cfg.get("visible") == false:
								continue # Omitir el dibujo en el minimapa
						
						# Puerta/Warp - Cian neón con 'P'
						var pulse_door = 0.6 + sin(Time.get_ticks_msec() * 0.004) * 0.3
						draw_circle(obj_pos, 5.5, Color(0.0, 0.9, 1.0, 0.9))
						draw_circle(obj_pos, 8.0 + pulse_door * 2.0, Color(0.0, 0.9, 1.0, 0.25), false, 1.5)
						draw_string(font, obj_pos + Vector2(-2.5, 3.0), "P", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)
						
						if target_zone != "":
							var dest_name = ""
							if GameConstants.MAPS_CONFIG.has(target_zone):
								dest_name = GameConstants.MAPS_CONFIG[target_zone].get("name", "Sector " + target_zone)
							else:
								dest_name = "Sector " + target_zone
							
							# Si el mouse está posicionado encima del portal en el minimapa (rango de 8px)
							if is_hovered and local_m_pos.distance_to(obj_pos) < 8.0:
								hovered_dest = dest_name
					"tower":
						# Torre - Naranja con 'T'
						draw_circle(obj_pos, 5.0, Color(1.0, 0.55, 0.0, 0.9))
						draw_circle(obj_pos, 7.5, Color(1.0, 0.55, 0.0, 0.2), false, 1.5)
						draw_string(font, obj_pos + Vector2(-2.5, 3.0), "T", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)
					
					"nexus":
						# Nexo PVP - Rojo para Red, Azul para Blue, con pulso de energía y letra 'N'
						var team = str(obj.get("team", "red")).to_lower()
						var pulse = 0.5 + sin(Time.get_ticks_msec() * 0.005) * 0.3
						var base_color = Color(1.0, 0.15, 0.15) if team == "red" else Color(0.15, 0.5, 1.0)
						
						draw_circle(obj_pos, 6.0, base_color)
						draw_circle(obj_pos, 8.5 + pulse * 2.5, Color(base_color.r, base_color.g, base_color.b, 0.25), false, 1.5)
						draw_string(font, obj_pos + Vector2(-3.0, 3.0), "N", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)
						
					"pillar":
						# Pilar PVP - Rojo/Azul según equipo y letra 'P'
						var team = str(obj.get("team", "neutral")).to_lower()
						var base_color = Color(0.85, 0.85, 0.85)
						if team == "red":
							base_color = Color(0.9, 0.2, 0.2)
						elif team == "blue":
							base_color = Color(0.2, 0.4, 0.9)
						
						draw_circle(obj_pos, 4.5, base_color)
						draw_circle(obj_pos, 6.5, Color(base_color.r, base_color.g, base_color.b, 0.2), false, 1.0)
						draw_string(font, obj_pos + Vector2(-2.5, 3.0), "P", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)
						
					"market":
						# Mercado - Amarillo/Dorado con 'M'
						draw_circle(obj_pos, 5.0, Color(1.0, 0.85, 0.0, 0.95))
						draw_circle(obj_pos, 7.5, Color(1.0, 0.85, 0.0, 0.2), false, 1.5)
						draw_string(font, obj_pos + Vector2(-3.5, 3.0), "M", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)
						
					_:
						# Objeto genérico - Blanco con 'O'
						draw_circle(obj_pos, 4.0, Color(0.8, 0.8, 0.8, 0.8))
						draw_string(font, obj_pos + Vector2(-2.5, 3.0), "O", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)


	# 5.5 Rectángulo de visión en modo PANEO (cámara libre sin seguir al jugador)
	var map_node = get_tree().get_first_node_in_group("map")
	var is_pan_mode = false
	if is_instance_valid(map_node):
		var fca = map_node.get("free_cam_active")
		var fom = map_node.get("free_orbit_mode")
		is_pan_mode = (fca == true and fom == false)
	if is_pan_mode:
		var cam = map_node.get("camera_3d")
		var svp = map_node.get("sub_viewport")
		var sf = map_node.get("scale_factor")
		var cz = map_node.get("correction_z")
		if is_instance_valid(cam) and is_instance_valid(svp) and sf != null and cz != null:
			var vp_size = svp.size
			if vp_size.x > 0 and vp_size.y > 0:
				var corners_2d_world = []
				for corner in [Vector2(0, 0), Vector2(vp_size.x, 0), Vector2(vp_size.x, vp_size.y), Vector2(0, vp_size.y)]:
					var origin = cam.project_ray_origin(corner)
					var dir = cam.project_ray_normal(corner)
					if dir.y >= 0: continue
					var t = -origin.y / dir.y
					var gp = origin + dir * t
					var wx = gp.x / sf
					var wy = gp.z / (sf * cz)
					corners_2d_world.append(Vector2(wx, wy))
				
				if corners_2d_world.size() == 4:
					var min_p = Vector2(INF, INF)
					var max_p = Vector2(-INF, -INF)
					for c in corners_2d_world:
						var mp = Vector2(c.x * scale_x, c.y * scale_y)
						min_p.x = min(min_p.x, mp.x)
						min_p.y = min(min_p.y, mp.y)
						max_p.x = max(max_p.x, mp.x)
						max_p.y = max(max_p.y, mp.y)
					draw_rect(Rect2(min_p, max_p - min_p), Color.WHITE, false, 1.5)

	# --- NSEO: Indicadores cardinales en bordes del mundo (giran con el mapa en modo rotatorio) ---
	var font_nseo = get_theme_font("font")
	var margin_px = 12.0
	var margin_wx = margin_px / scale_x
	var margin_wy = margin_px / scale_y
	var cardinals = [
		{"label": "N", "pos": Vector2(worldW / 2, margin_wy)},
		{"label": "S", "pos": Vector2(worldW / 2, worldH - margin_wy)},
		{"label": "E", "pos": Vector2(worldW - margin_wx, worldH / 2)},
		{"label": "O", "pos": Vector2(margin_wx, worldH / 2)}
	]
	for c in cardinals:
		var cp = Vector2(c.pos.x * scale_x, c.pos.y * scale_y)
		draw_string(font_nseo, cp - Vector2(3, 3), c.label, HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color(0, 1, 1, 0.7))

	# --- Reset rotation transform before overlay elements ---
	if is_rotate_mode:
		draw_set_transform_matrix(Transform2D())

	# 5. Jugador Local (Punto Blanco Puro) — siempre último para estar arriba
	if is_rotate_mode:
		draw_circle(player_mp, 3.5, Color.WHITE)
		var cone_len = 10.0
		var cone_spread = 0.8
		var cone_angle = -PI/2
		var cone_left = player_mp + Vector2.RIGHT.rotated(cone_angle + cone_spread) * cone_len
		var cone_right = player_mp + Vector2.RIGHT.rotated(cone_angle - cone_spread) * cone_len
		draw_colored_polygon(PackedVector2Array([player_mp, cone_left, cone_right]), Color(0.6, 0.6, 0.6, 0.8))
	else:
		var local_pos = Vector2(player.global_position.x * scale_x, player.global_position.y * scale_y)
		draw_circle(local_pos, 3.5, Color.WHITE)
		var cone_len = 10.0
		var cone_spread = 0.8
		var cone_angle = player.rotation
		var cone_left = local_pos + Vector2.RIGHT.rotated(cone_angle + cone_spread) * cone_len
		var cone_right = local_pos + Vector2.RIGHT.rotated(cone_angle - cone_spread) * cone_len
		draw_colored_polygon(PackedVector2Array([local_pos, cone_left, cone_right]), Color(0.6, 0.6, 0.6, 0.8))

	# v700.14: Restablecer la transformación para dibujar el borde y el tooltip en coordenadas del panel
	draw_set_transform(Vector2.ZERO)

	# Borde del radar
	draw_rect(Rect2(Vector2.ZERO, r_size), Color(0, 1, 1, 0.1), false, 1.0)
	
	# 8. Dibujar Tooltip interactivo si se pasa el mouse por encima de un portal
	if hovered_dest != "":
		var font = get_theme_font("font")
		var radar_tooltip = hovered_dest.to_upper()
		var text_size = font.get_string_size(radar_tooltip, HORIZONTAL_ALIGNMENT_LEFT, -1, 8)
		var rect_size = text_size + Vector2(12, 8)
		var rect_pos = local_m_pos + Vector2(10, 10)
		
		# Evitar que se salga del área del minimapa
		if rect_pos.x + rect_size.x > r_size.x:
			rect_pos.x = local_m_pos.x - rect_size.x - 10
		if rect_pos.y + rect_size.y > r_size.y:
			rect_pos.y = local_m_pos.y - rect_size.y - 10
			
		# Dibujar panel sci-fi con fondo oscuro y borde cian neón
		draw_rect(Rect2(rect_pos, rect_size), Color(0.01, 0.04, 0.08, 0.92), true)
		draw_rect(Rect2(rect_pos, rect_size), Color(0.0, 0.9, 1.0, 0.8), false, 1.0)
		
		# Renderizar texto
		draw_string(font, rect_pos + Vector2(6, 14), radar_tooltip, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.0, 1.0, 1.0))

func _draw_minimap_fog(scale_x: float, scale_y: float, grid_res: int, explored: Dictionary, worldW: float, worldH: float, player):
	# v801.0 NIEBLA PANTANO minimapa - 80% opacidad, multi-tono nube gris, variación, elevación y degradé
	if not is_instance_valid(player):
		return
	var vr = 1300.0
	if "vision_range" in player:
		vr = float(player.vision_range)
	var cell_w = (worldW * scale_x) / float(grid_res)
	var cell_h = (worldH * scale_y) / float(grid_res)
	var px = player.global_position.x
	var py = player.global_position.y
	var vr_sq = vr * vr
	var world_cell_w = worldW / float(grid_res)
	var world_cell_h = worldH / float(grid_res)
	# Tiempo para elevación (niebla que se mueve lenta)
	var t = Time.get_ticks_msec() * 0.00018
	for cy in range(grid_res):
		for cx in range(grid_res):
			var idx = cy * grid_res + cx
			var is_explored = explored.has(idx)
			var cw_x = (float(cx) + 0.5) * world_cell_w
			var cw_y = (float(cy) + 0.5) * world_cell_h
			var dx = cw_x - px
			var dy = cw_y - py
			var dist_sq = dx*dx + dy*dy
			var in_vision = dist_sq <= vr_sq
			if in_vision:
				continue
			# Degradé en terminaciones de niebla: suavizar borde del círculo de visión (80-120% del radio)
			var dist = sqrt(dist_sq)
			var edge_fade = 1.0
			var fade_start = vr * 0.82
			var fade_end = vr * 1.18
			if dist > fade_start:
				edge_fade = 1.0 - clamp((dist - fade_start) / max(fade_end - fade_start, 1.0), 0.0, 1.0)
				# Si está justo en borde exterior, aún dibujar pero con alpha degradada
				if edge_fade <= 0.02:
					continue
			# Hash nube por celda + elevación animada
			var hash = fmod(sin(float(idx) * 12.9898 + float(cx)*78.233 + float(cy)*37.719) * 43758.5453, 1.0)
			hash = abs(hash)
			# Dos capas de nube para variación
			var n1 = fmod(sin(float(idx)* 0.11 + t*0.7 + float(cx)*0.12) * 9.3, 1.0)
			var n2 = fmod(cos(float(idx)* 0.07 - t*0.5 + float(cy)*0.09) * 7.1, 1.0)
			n1 = abs(n1); n2 = abs(n2)
			var cloud = hash * 0.55 + n1 * 0.28 + n2 * 0.17
			# Onda elevación lenta
			var wave = sin(float(cx)*0.18 + t*1.2) * cos(float(cy)*0.16 + t*0.9) * 0.12
			cloud = clamp(cloud + wave, 0.0, 1.0)
			# Degradé de terminación por cloud: bordes de nube más suaves
			var cloud_edge = smoothstep(0.15, 0.85, cloud)
			# Seleccionar tono pantano según cloud
			var col_dark = Color(0.14, 0.16, 0.17)
			var col_mid = Color(0.34, 0.36, 0.39)
			var col_light = Color(0.60, 0.62, 0.64)
			var col_swamp = Color(0.30, 0.34, 0.28)
			var pal = col_dark.lerp(col_mid, smoothstep(0.22, 0.52, cloud))
			pal = pal.lerp(col_light, smoothstep(0.48, 0.86, cloud_edge))
			pal = pal.lerp(col_swamp, cloud * 0.20)
			# Variación fina
			pal.r += (n1 - 0.5) * 0.04
			pal.g += (n2 - 0.5) * 0.04
			pal.b += (hash - 0.5) * 0.03
			var rect = Rect2(float(cx) * cell_w, float(cy) * cell_h, cell_w + 0.6, cell_h + 0.6)
			if not is_explored:
				# NO EXPLORADO: 80% opacidad pantano denso, degradé por edge_fade
				pal.a = 0.80 * edge_fade * (0.88 + cloud_edge * 0.12)
				draw_rect(rect, pal, true)
			else:
				# EXPLORADO penumbra: gris claro 30% pero con nube visible
				var penumbra = pal.lerp(Color(0.66, 0.66, 0.68), 0.45)
				penumbra.a = 0.30 * edge_fade * (0.75 + cloud * 0.25)
				draw_rect(rect, penumbra, true)

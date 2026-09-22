extends Control
class_name Minimap

# Minimap.gd (Tactical Radar v200.0 - SYNC FIX + WORLD OBJECTS)
# Gestión de radar con dibujo directo para rendimiento y AUTOPILOTO visual.
# SYNC FIX: Lee worldW/worldH desde MAPS_CONFIG (mismo origen que AdminDash)

const WORLD_DEFAULT_SIZE = 10000.0

# world_size se mantiene por compatibilidad legado; usar worldW/worldH para dibujo
var world_size: float = WORLD_DEFAULT_SIZE
var info_label: Label = null
static var fog_rendering_enabled: bool = true
var _redraw_accum: float = 0.0
const MINIMAP_REDRAW_INTERVAL: float = 1.0 / 60.0 # Máximo 60 FPS en minimapa para aliviar CPU a 120 FPS



const WORLD_MAP_SCRIPT = preload("res://scripts/ui/WorldMapDialog.gd")
var world_map_dialog: WorldMapDialog = null
var btn_world_map: Button = null

# Zoom fijo del minimapa (sin rueda del ratón)
const MINIMAP_ZOOM: float = 2.5

func get_current_world_rect() -> Rect2:
	var player = get_tree().get_first_node_in_group("player")
	var current_zone_id = str(player.current_zone) if is_instance_valid(player) and "current_zone" in player else "1"
	return WorldMapDialog.get_zone_rect(current_zone_id, get_tree())

func get_current_world_dimensions() -> Vector2:
	return get_current_world_rect().size




## --- RETÍCULA TÁCTICA SCI-FI (DESHABILITADA POR PETICIÓN) ---
func _draw_tactical_grid(_rect: Rect2, _scale_x: float, _scale_y: float, _worldW: float, _worldH: float, _player: Node2D):
	return

func _input(event):
	# Soporte de atajo de teclado para el Mapa Completo
	if event.is_action_pressed("ui_map"):
		var inv = get_tree().get_first_node_in_group("inventory_ui")
		if not (inv and inv.visible):
			toggle_world_map()
			get_viewport().set_input_as_handled()
			return
			
	if is_instance_valid(world_map_dialog) and world_map_dialog.visible:
		if event.is_action_pressed("ui_menu") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
			world_map_dialog.close()
			get_viewport().set_input_as_handled()
			return

	# PC: clic derecho fija rumbo. Móvil: toque (ScreenTouch) fija rumbo.
	var is_nav_press = false
	var nav_view_pos = Vector2.ZERO # coords de viewport (para menu_rect)
	var nav_global_pos = Vector2.ZERO # coords globales del canvas (para get_global_rect)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		is_nav_press = true
		nav_view_pos = event.position
		nav_global_pos = get_global_mouse_position()
	elif event is InputEventScreenTouch and event.pressed:
		is_nav_press = true
		nav_view_pos = event.position
		nav_global_pos = get_canvas_transform().affine_inverse() * event.position

	if is_nav_press:
		# v269.150: Bloqueo de navegación durante edición de HUD
		var hud = get_tree().get_first_node_in_group("hud")
		if hud and hud.get("is_editing_layout"): return

		# v244.85: Bloqueo inteligente si hay menús superpuestos (F1 / F2)
		var screen_size = get_viewport().get_visible_rect().size
		var r_size = Vector2(screen_size.x * 0.85, screen_size.y * 0.85)
		var r_pos = (screen_size - r_size) / 2.0
		var menu_rect = Rect2(r_pos, r_size)
		
		if menu_rect.has_point(nav_view_pos):
			var inv = get_tree().get_first_node_in_group("inventory_ui")
			var admin = get_tree().get_first_node_in_group("admin_panel_ui")
			if (inv and inv.visible) or (admin and admin.visible):
				return # Ignorar clic, cae en el área de un menú abierto

		# v269.160: Convertir con la transformada global real (soporta escala dinámica del RadarWindow en HUD editor)
		var global_m_pos = nav_global_pos
		if get_global_rect().has_point(global_m_pos):
			var g_tr = get_global_transform()
			var local_m_pos = g_tr.affine_inverse() * global_m_pos
			var target_world_pos = Vector2.ZERO
			var is_rotate = get_node_or_null("/root/SettingsManager") and SettingsManager.minimap_rotate
			var p = get_tree().get_first_node_in_group("player")
			
			var world_rect = get_current_world_rect()
			var worldW = world_rect.size.x
			var worldH = world_rect.size.y
			
			var base_scale = min(size.x / worldW, size.y / worldH)
			var effective_scale = base_scale * MINIMAP_ZOOM
			var center_radar = size / 2.0
			var delta_mouse = local_m_pos - center_radar
			
			if is_rotate and is_instance_valid(p):
				var derotated = delta_mouse.rotated(PI/2 + p.rotation)
				target_world_pos = p.global_position + (derotated / max(effective_scale, 0.001))
			elif is_instance_valid(p):
				target_world_pos = p.global_position + (delta_mouse / max(effective_scale, 0.001))
			else:
				target_world_pos = world_rect.position + (local_m_pos / max(effective_scale, 0.001))
			
			target_world_pos.x = clamp(target_world_pos.x, world_rect.position.x, world_rect.end.x)
			target_world_pos.y = clamp(target_world_pos.y, world_rect.position.y, world_rect.end.y)
			
			if is_instance_valid(p) and p.has_method("set_autopilot"):
				if p.get_meta("spawn_locked", false):
					print("[NAV] BLOQUEADO: No puedes fijar rumbo mientras esté activa la barrera de spawn.")
					get_viewport().set_input_as_handled()
					return
				p.set_autopilot(target_world_pos)
				print("[NAV] DESTINO FIJADO: ", target_world_pos)
				get_viewport().set_input_as_handled() # Consumir evento

func _ready():
	WorldMapDialog.terrain_cache_by_zone.clear()
	WorldMapDialog.terrain_bounds_by_zone.clear()
	add_to_group("minimap")
	world_size = GameConstants.GAME_CONFIG.get("worldSize", WORLD_DEFAULT_SIZE)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true
	custom_minimum_size = Vector2.ZERO
	
	# v805.0: Eliminar BG azul estático residual para permitir que el marco SciFiFrame maneje el fondo de forma adaptativa
	var old_bg = get_node_or_null("BG")
	if old_bg:
		old_bg.queue_free()
		
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
	
	# Activar clipping en el canvas del minimapa para recortar el mapa durante el zoom
	clip_contents = true
	if get_parent() is Control:
		get_parent().clip_contents = false
		
	info_label.top_level = true # Evita que el label de coordenadas sea recortado por el clip del minimapa
	add_child(info_label)

	# Botón Sci-Fi para abrir el mapa completo del sector actual
	btn_world_map = Button.new()
	btn_world_map.name = "BtnWorldMap"
	btn_world_map.text = " 🗺️ "
	btn_world_map.tooltip_text = "Abrir Mapa Completo [TAB]"
	btn_world_map.add_theme_font_size_override("font_size", 9)
	var b_sb = StyleBoxFlat.new()
	b_sb.bg_color = Color(0, 0.08, 0.14, 0.85)
	b_sb.border_width_left = 1
	b_sb.border_width_top = 1
	b_sb.border_width_right = 1
	b_sb.border_width_bottom = 1
	b_sb.border_color = Color(0, 1, 1, 0.6)
	b_sb.set_corner_radius_all(3)
	btn_world_map.add_theme_stylebox_override("normal", b_sb)
	var b_sb_h = b_sb.duplicate()
	b_sb_h.bg_color = Color(0, 0.25, 0.35, 0.95)
	b_sb_h.border_color = Color(0, 1, 1, 1.0)
	btn_world_map.add_theme_stylebox_override("hover", b_sb_h)
	btn_world_map.top_level = true
	btn_world_map.custom_minimum_size = Vector2(24, 20)
	btn_world_map.pressed.connect(toggle_world_map)
	add_child(btn_world_map)

func toggle_world_map(zone_id_to_show: String = ""):
	if not is_instance_valid(world_map_dialog):
		world_map_dialog = WORLD_MAP_SCRIPT.new()
		var canvas_root = get_tree().root
		canvas_root.add_child(world_map_dialog)
	
	world_map_dialog.toggle(zone_id_to_show)

func open_world_map(zone_id_to_show: String = ""):
	if not is_instance_valid(world_map_dialog):
		world_map_dialog = WORLD_MAP_SCRIPT.new()
		var canvas_root = get_tree().root
		canvas_root.add_child(world_map_dialog)
	
	world_map_dialog.open(zone_id_to_show)

func _update_parent_window_size():
	var parent = get_parent()
	if not is_instance_valid(parent) or not parent is Control:
		return
		
	# Contenedor de radar siempre perfectamente cuadrado (estilo AAA táctico)
	var max_dim = 220.0
	var target_size = Vector2(max_dim, max_dim)
	
	if parent.size.distance_to(target_size) > 1.0 or parent.custom_minimum_size.distance_to(target_size) > 1.0:
		parent.custom_minimum_size = target_size
		parent.size = target_size

func _process(delta):
	if visible:
		_update_parent_window_size()
		_redraw_accum += delta
		if _redraw_accum >= MINIMAP_REDRAW_INTERVAL:
			_redraw_accum = 0.0
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
	
	# Centrar dinámicamente justo encima del minimapa (soporta top_level = true)
	info_label.reset_size()
	
	# v270: Aplicar escala del padre a label y botón (son top_level, no heredan escala)
	var _par_label = get_parent()
	var _p_sx = 1.0
	var _p_sy = 1.0
	if _par_label and _par_label is Control:
		_p_sx = _par_label.scale.x
		_p_sy = _par_label.scale.y
	info_label.scale = Vector2(_p_sx, _p_sy)
	var _vis_w = size.x * _p_sx
	var _y_offset = -24.0 * _p_sy
	
	if is_instance_valid(btn_world_map) and btn_world_map.visible:
		btn_world_map.reset_size()
		btn_world_map.scale = Vector2(_p_sx, _p_sy)
		var total_top_w = (info_label.size.x + btn_world_map.size.x + 4.0) * _p_sx
		var start_x = global_position.x + (_vis_w - total_top_w) / 2.0
		info_label.global_position.x = start_x
		info_label.global_position.y = global_position.y + _y_offset
		
		btn_world_map.global_position.x = start_x + info_label.size.x * _p_sx + 4.0 * _p_sx
		btn_world_map.global_position.y = global_position.y + _y_offset
	else:
		var total_w = info_label.size.x * _p_sx
		info_label.global_position.x = global_position.x + (_vis_w - total_w) / 2.0
		info_label.global_position.y = global_position.y + _y_offset

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
	# TERRENO DINÁMICO DE GODOT (Sin límites hardcodeados)
	# =====================================================================
	var world_rect = get_current_world_rect()
	var worldW: float = world_rect.size.x
	var worldH: float = world_rect.size.y
	
	# Mantener world_size por compatibilidad legado
	world_size = worldW
	var r_size = size
	
	# Base scale para encajar el mapa completo en el visor cuadrado del minimapa
	var base_scale: float = min(r_size.x / worldW, r_size.y / worldH)
	# v270: Compensar escala del RadarWindow en editor de Layout
	# Escalar el dibujado del mundo para que el contenido NO se achique al reducir el marco
	var _world_scale_comp = 1.0
	var _par = get_parent()
	if _par and _par is Control:
		_world_scale_comp = 1.0 / maxf(_par.scale.x, 0.01)
	var is_rotate_mode = get_node_or_null("/root/SettingsManager") and SettingsManager.minimap_rotate
	var effective_scale: float = base_scale * MINIMAP_ZOOM * _world_scale_comp
	var scale_x: float = effective_scale
	var scale_y: float = effective_scale
	var _map_scale: float = scale_x
	
	var center_screen = r_size / 2.0
	
	# -----------------------------------------------------------------
	# 1. FONDO BASE DEL RADAR
	# -----------------------------------------------------------------
	draw_rect(Rect2(Vector2.ZERO, r_size), Color(0.012, 0.03, 0.055, 0.96), true)
	
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
 
	# -----------------------------------------------------------------
	# 2. TRANSFORMADA DEL MUNDO (JUGADOR CENTRADO) — entidades en espacio-mundo
	# -----------------------------------------------------------------
	var canvas_tr = Transform2D()
	var player_mp = Vector2(player.global_position.x * scale_x, player.global_position.y * scale_y)
	var rot_angle = 0.0
	var world_offset = center_screen - player_mp

	if is_rotate_mode:
		rot_angle = -PI/2 - player.rotation
		canvas_tr = Transform2D().translated(-player_mp).rotated(rot_angle).translated(center_screen)
		draw_set_transform_matrix(canvas_tr)
	else:
		canvas_tr = Transform2D(0, world_offset)
		draw_set_transform(world_offset)

	var world_m_pos = canvas_tr.affine_inverse() * local_m_pos if is_hovered else Vector2.ZERO

	var map_rect = Rect2(
		world_rect.position.x * scale_x,
		world_rect.position.y * scale_y,
		worldW * scale_x,
		worldH * scale_y
	)

	# Terreno con relieves reales 1:1 en espacio-mundo
	var terrain_tex = WorldMapDialog.get_or_create_terrain_texture(current_zone_id, world_rect, get_tree())
	if is_instance_valid(terrain_tex):
		draw_texture_rect(terrain_tex, map_rect, false)

	# Niebla encima del terreno y bajo las naves
	if fog_overlay_needed and fog_rendering_enabled:
		_draw_minimap_fog(scale_x, scale_y, fog_grid_res, fog_explored, world_rect, player)


	
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
			var dist_to_player_w = player.global_position.distance_to(ent.global_position) if is_instance_valid(player) else 99999.0
			if dist_to_player_w > vision_r:
				continue

			var pos = Vector2(ent.global_position.x * scale_x, ent.global_position.y * scale_y)
			var ent_type = int(ent.get("entity_type"))
			var is_boss = ent.get("isBoss") == true

			# 1. Escala del modelo o configuración del enemigo
			var ent_scale = 2.0
			var mdl_3d = ent.get("_3d_model")
			if is_instance_valid(mdl_3d) and mdl_3d.scale.x > 0.0:
				ent_scale = mdl_3d.scale.x
			elif ent.get("_enemy_scale") != null:
				ent_scale = float(ent.get("_enemy_scale"))
			if ent_scale <= 0.0: ent_scale = 2.0

			# 2. Espacio físico real que ocupa el enemigo en el mundo 2D
			var world_radius: float = 0.0
			var col_shape = ent.get("_collision_shape")
			if is_instance_valid(col_shape) and col_shape.shape is CircleShape2D and col_shape.shape.radius > 0.0:
				world_radius = col_shape.shape.radius
			else:
				world_radius = ent_scale * 15.0

			# 3. Radio físico proyectado al minimapa según la escala de dibujo
			var physical_minimap_r = world_radius * scale_x
			var dist_minimap = dist_to_player_w * scale_x

			var is_special = is_boss or ent_type >= 101 or ent_type == 10 or ent_type == 11
			var dot_r = 2.0

			if is_special:
				# Crece conforme crezca la escala del enemigo, respetando el espacio físico en el minimapa
				var tactical_r = clampf(3.5 * (ent_scale / 6.0), 3.5, 12.0)
				dot_r = max(tactical_r, physical_minimap_r)

				# Fidelidad espacial: si el jugador NO está colisionando con el enemigo en el mundo físico,
				# el círculo violeta jamás debe sobrepasar ni cubrir la posición de la nave en el minimapa
				if dist_to_player_w > world_radius:
					dot_r = min(dot_r, max(2.5, dist_minimap - 2.5))

				# Renderizado táctico de Boss: cuerpo violeta + borde de colisión nítido + núcleo central
				draw_circle(pos, dot_r, Color(0.65, 0.25, 1.0, 0.85))
				draw_circle(pos, dot_r, Color(0.85, 0.45, 1.0, 0.95), false, 1.0)
				draw_circle(pos, min(2.0, dot_r * 0.35), Color.WHITE)
			else:
				# Enemigo común: proporcional al tamaño físico con visibilidad mínima
				dot_r = max(2.0, physical_minimap_r)
				if dist_to_player_w > world_radius:
					dot_r = min(dot_r, max(1.5, dist_minimap - 1.5))
				draw_circle(pos, dot_r, Color(1.0, 0.4, 0.0))

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
			
		for pt in extract_points:
			var pt_pos = Vector2(float(pt.x) * scale_x, float(pt.y) * scale_y)
			
			# Dibujar halo cian estático de portal radar (sin parpadeo)
			draw_circle(pt_pos, 4.5, Color(0, 0.9, 1.0, 0.85))
			draw_circle(pt_pos, 7.5, Color(0, 0.9, 1.0, 0.25), false, 1.0)
			
			# Mostrar primera letra de la zona ("A", "B", "G", "D")
			var label = str(pt.get("label", "Portal")).to_lower()
			var letter = "E"
			if label.contains("alfa"): letter = "A"
			elif label.contains("beta"): letter = "B"
			elif label.contains("gamma"): letter = "G"
			elif label.contains("delta"): letter = "D"
			
			var font = get_theme_font("font")
			draw_string(font, pt_pos + Vector2(-3, 3), letter, HORIZONTAL_ALIGNMENT_CENTER, -1, 7, Color.WHITE)

	# 4.5 Dibujar Altar si es zona de Defensa del Altar (Verde neón místico con una 'A' blanca, estático)
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
		draw_circle(alt_draw_pos, 6.0, Color(0.0, 1.0, 0.5, 0.95)) # Círculo verde brillante
		draw_circle(alt_draw_pos, 9.5, Color(0.0, 1.0, 0.5, 0.30), false, 1.0) # Brillo estático
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
				
				# v1000.0: FILTRO INTELIGENTE DE ESTRUCTURAS
				# No mostrar colliders, muros o cajas de física a menos que tengan explícitamente show_on_minimap: true
				var show_explicit = obj.get("show_on_minimap", false) == true or obj.get("showOnMinimap", false) == true
				
				# Detectar si es un altar colocado como muro (ej. Altar1)
				var obj_label = str(obj.get("label", "")).to_lower()
				var asset_path = str(obj.get("assetPath", "")).to_lower()
				if obj_type == "wall" and (obj_label.contains("altar") or asset_path.contains("altar")):
					obj_type = "altar"
				
				match obj_type:
					"altar":
						# Altar: Ícono verde esmeralda con letra 'A' y aura brillante estática
						draw_circle(obj_pos, 6.0, Color(0.0, 1.0, 0.5, 0.95))
						draw_circle(obj_pos, 9.0, Color(0.0, 1.0, 0.5, 0.3), false, 1.5)
						draw_string(font, obj_pos + Vector2(-3.0, 3.5), "A", HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color.WHITE)
					"chest", "vault":
						# Baúl - Dorado brillante con 'B'
						draw_circle(obj_pos, 5.0, Color(1.0, 0.85, 0.0, 0.95))
						draw_circle(obj_pos, 7.5, Color(1.0, 0.85, 0.0, 0.25), false, 1.5)
						draw_string(font, obj_pos + Vector2(-2.5, 3.0), "B", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)
					"door", "portal":
						# Obtener destino dinámico
						var target_zone = str(obj.get("targetZoneId", obj.get("targetZone", "")))
						
						# Validar si el destino está inactivo/invisible
						if GameConstants.get("MAPS_CONFIG") and GameConstants.MAPS_CONFIG.has(target_zone):
							var target_map_cfg = GameConstants.MAPS_CONFIG[target_zone]
							if target_map_cfg.has("visible") and target_map_cfg.get("visible") == false:
								continue # Omitir el dibujo en el minimapa
						
						# Puerta/Warp - Cian neón estático con 'P'
						draw_circle(obj_pos, 5.5, Color(0.0, 0.9, 1.0, 0.9))
						draw_circle(obj_pos, 8.0, Color(0.0, 0.9, 1.0, 0.25), false, 1.5)
						draw_string(font, obj_pos + Vector2(-2.5, 3.0), "P", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)
						
						if target_zone != "":
							var dest_name = ""
							if GameConstants.MAPS_CONFIG.has(target_zone):
								dest_name = GameConstants.MAPS_CONFIG[target_zone].get("name", "Sector " + target_zone)
							else:
								dest_name = "Sector " + target_zone
							
							# Si el mouse está posicionado encima del portal en el minimapa (rango de 8px)
							if is_hovered and world_m_pos.distance_to(obj_pos) < 8.0:
								hovered_dest = dest_name
					"tower":
						# Torre - Naranja con 'T'
						draw_circle(obj_pos, 5.0, Color(1.0, 0.55, 0.0, 0.9))
						draw_circle(obj_pos, 7.5, Color(1.0, 0.55, 0.0, 0.2), false, 1.5)
						draw_string(font, obj_pos + Vector2(-2.5, 3.0), "T", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)
					
					"nexus":
						# Nexo PVP - Rojo para Red, Azul para Blue, estático con letra 'N'
						var team = str(obj.get("team", "red")).to_lower()
						var base_color = Color(1.0, 0.15, 0.15) if team == "red" else Color(0.15, 0.5, 1.0)
						
						draw_circle(obj_pos, 6.0, base_color)
						draw_circle(obj_pos, 9.0, Color(base_color.r, base_color.g, base_color.b, 0.25), false, 1.5)
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
						# Estructura genérica personalizada SOLO si fue explícitamente marcada
						if show_explicit:
							draw_circle(obj_pos, 4.0, Color(0.0, 0.9, 1.0, 0.85))
							var mark_letter = obj.get("minimap_letter", obj.get("letter", "*"))
							draw_string(font, obj_pos + Vector2(-2.5, 3.0), str(mark_letter), HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)
						# En caso contrario, se descarta y NO se dibuja (evita colliders y cajas molestas)


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

	# --- Reset transform ---
	draw_set_transform(Vector2.ZERO)

	# Cruz de referencia en el centro (muy sutil, sin círculos)
	draw_line(center_screen + Vector2(-5, 0), center_screen + Vector2(5, 0), Color(0.0, 0.9, 1.0, 0.20), 1.0)
	draw_line(center_screen + Vector2(0, -5), center_screen + Vector2(0, 5), Color(0.0, 0.9, 1.0, 0.20), 1.0)

	# -----------------------------------------------------------------
	# 5. JUGADOR LOCAL (ESTÉTICA AAA NÍTIDA) — SIEMPRE EN EL CENTRO
	# -----------------------------------------------------------------
	var p_draw_pos = center_screen
	
	# Halo cian sutil y núcleo blanco puro
	draw_circle(p_draw_pos, 5.5, Color(0.0, 0.9, 1.0, 0.25))
	draw_circle(p_draw_pos, 3.0, Color.WHITE)

	
	# Cono de orientación angosto con 80% de opacidad (Petición del usuario)
	var cone_len = 13.0
	var cone_spread = 0.30 # Más angosto y preciso
	var cone_angle = -PI/2 if is_rotate_mode else player.rotation
	var cone_left = p_draw_pos + Vector2.RIGHT.rotated(cone_angle + cone_spread) * cone_len
	var cone_right = p_draw_pos + Vector2.RIGHT.rotated(cone_angle - cone_spread) * cone_len
	draw_colored_polygon(PackedVector2Array([p_draw_pos, cone_left, cone_right]), Color(0.0, 0.95, 1.0, 0.80)) # Opacidad al 80%
	
	# Brújula fija sutil en el bisel exterior del radar (HUD Compass AAA)
	var font_compass = get_theme_font("font")
	draw_string(font_compass, Vector2(center_screen.x - 3, 14), "N", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color(0, 1, 1, 0.45))
	draw_string(font_compass, Vector2(center_screen.x - 3, r_size.y - 4), "S", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color(0, 1, 1, 0.45))
	draw_string(font_compass, Vector2(r_size.x - 10, center_screen.y + 3), "E", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color(0, 1, 1, 0.45))
	draw_string(font_compass, Vector2(4, center_screen.y + 3), "O", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color(0, 1, 1, 0.45))
	
	# -----------------------------------------------------------------
	# 6. MARCO EXTERIOR SCI-FI AAA (ESQUINEROS BRILLANTES TÁCTICOS)
	# -----------------------------------------------------------------
	draw_rect(Rect2(Vector2.ZERO, r_size), Color(0.0, 0.8, 1.0, 0.45), false, 1.0)
	var corner_len = 10.0
	var c_col = Color(0.0, 1.0, 1.0, 0.85)
	# Top-Left
	draw_line(Vector2(0, 0), Vector2(corner_len, 0), c_col, 2.0)
	draw_line(Vector2(0, 0), Vector2(0, corner_len), c_col, 2.0)
	# Top-Right
	draw_line(Vector2(r_size.x, 0), Vector2(r_size.x - corner_len, 0), c_col, 2.0)
	draw_line(Vector2(r_size.x, 0), Vector2(r_size.x, corner_len), c_col, 2.0)
	# Bottom-Left
	draw_line(Vector2(0, r_size.y), Vector2(corner_len, r_size.y), c_col, 2.0)
	draw_line(Vector2(0, r_size.y), Vector2(0, r_size.y - corner_len), c_col, 2.0)
	# Bottom-Right
	draw_line(Vector2(r_size.x, r_size.y), Vector2(r_size.x - corner_len, r_size.y), c_col, 2.0)
	draw_line(Vector2(r_size.x, r_size.y), Vector2(r_size.x, r_size.y - corner_len), c_col, 2.0)
	
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

func _draw_minimap_fog(scale_x: float, scale_y: float, grid_res: int, explored: Dictionary, world_rect_or_w: Variant, worldH_or_player: Variant, maybe_player: Variant = null):
	var world_rect: Rect2
	var player = null
	if world_rect_or_w is Rect2:
		world_rect = world_rect_or_w
		player = worldH_or_player
	else:
		world_rect = Rect2(0.0, 0.0, float(world_rect_or_w), float(worldH_or_player))
		player = maybe_player
		
	if not is_instance_valid(player):
		return
	var vr = 1300.0
	if "vision_range" in player:
		vr = float(player.vision_range)
	var worldW = world_rect.size.x
	var worldH = world_rect.size.y
	var cell_w = (worldW * scale_x) / float(grid_res)
	var cell_h = (worldH * scale_y) / float(grid_res)
	var px = player.global_position.x
	var py = player.global_position.y
	var vr_sq = vr * vr
	var world_cell_w = worldW / float(grid_res)
	var world_cell_h = worldH / float(grid_res)
	
	var fade_start = vr * 0.82
	var fade_end = vr * 1.18
	var fade_end_sq = fade_end * fade_end
	var fade_inv_range = 1.0 / max(fade_end - fade_start, 1.0)
	
	# Bounding box inteligente teniendo en cuenta el origen real del mundo
	var min_cx = clampi(int(((px - fade_end) - world_rect.position.x) / world_cell_w), 0, grid_res - 1)
	var max_cx = clampi(int(((px + fade_end) - world_rect.position.x) / world_cell_w) + 1, 0, grid_res)
	var min_cy = clampi(int(((py - fade_end) - world_rect.position.y) / world_cell_h), 0, grid_res - 1)
	var max_cy = clampi(int(((py + fade_end) - world_rect.position.y) / world_cell_h) + 1, 0, grid_res)
	
	# Tiempo para elevación (niebla que se mueve lenta)
	var t = Time.get_ticks_msec() * 0.00018
	
	for cy in range(min_cy, max_cy):
		var cw_y = world_rect.position.y + (float(cy) + 0.5) * world_cell_h
		var dy = cw_y - py
		var dy_sq = dy * dy
		for cx in range(min_cx, max_cx):
			var cw_x = world_rect.position.x + (float(cx) + 0.5) * world_cell_w
			var dx = cw_x - px
			var dist_sq = dx * dx + dy_sq
			
			# Descarte rápido en CPU sin raíz cuadrada
			if dist_sq <= vr_sq or dist_sq >= fade_end_sq:
				continue
				
			var idx = cy * grid_res + cx
			var is_explored = explored.has(idx)
			
			# Degradé en terminaciones de niebla: suavizar borde del círculo de visión
			var dist = sqrt(dist_sq)
			var edge_fade = 1.0
			if dist > fade_start:
				edge_fade = 1.0 - clamp((dist - fade_start) * fade_inv_range, 0.0, 1.0)
				if edge_fade <= 0.02:
					continue
					
			# Hash nube por celda + elevación animada (idéntico al estilo artístico original)
			var cell_hash = fmod(sin(float(idx) * 12.9898 + float(cx)*78.233 + float(cy)*37.719) * 43758.5453, 1.0)
			cell_hash = abs(cell_hash)
			# Dos capas de nube para variación
			var n1 = fmod(sin(float(idx)* 0.11 + t*0.7 + float(cx)*0.12) * 9.3, 1.0)
			var n2 = fmod(cos(float(idx)* 0.07 - t*0.5 + float(cy)*0.09) * 7.1, 1.0)
			n1 = abs(n1); n2 = abs(n2)
			var cloud = cell_hash * 0.55 + n1 * 0.28 + n2 * 0.17
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
			pal.b += (cell_hash - 0.5) * 0.03
			var world_cell_x = world_rect.position.x + float(cx) * world_cell_w
			var world_cell_y = world_rect.position.y + float(cy) * world_cell_h
			var rect = Rect2(world_cell_x * scale_x, world_cell_y * scale_y, cell_w + 0.6, cell_h + 0.6)
			if not is_explored:
				# NO EXPLORADO: 80% opacidad pantano denso, degradé por edge_fade
				pal.a = 0.80 * edge_fade * (0.88 + cloud_edge * 0.12)
				draw_rect(rect, pal, true)
			else:
				# EXPLORADO penumbra: gris claro 30% pero con nube visible
				var penumbra = pal.lerp(Color(0.66, 0.66, 0.68), 0.45)
				penumbra.a = 0.30 * edge_fade * (0.75 + cloud * 0.25)
				draw_rect(rect, penumbra, true)

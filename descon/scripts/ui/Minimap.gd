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




## --- RETÍCULA TÁCTICA SCI-FI (DESHABILITADA) ---
func _draw_tactical_grid(_rect: Rect2, _scale_x: float, _scale_y: float, _worldW: float, _worldH: float, _player: Node2D):
	return

# 9. JUGADOR LOCAL (Nave Estelar Delta-Wing con halo de radar)
func _draw_local_player(pos: Vector2, heading_angle: float, _is_rotate: bool):
	draw_circle(pos, 8.0, Color(0.0, 0.92, 1.0, 0.18))
	var cone_len = 16.0
	var cone_spread = 0.32
	var cone_arc_pts = PackedVector2Array([pos])
	var num_steps = 7
	for i in range(num_steps + 1):
		var frac = float(i) / float(num_steps)
		var a = (heading_angle - cone_spread) + frac * (cone_spread * 2.0)
		cone_arc_pts.append(pos + Vector2.RIGHT.rotated(a) * cone_len)
	draw_colored_polygon(cone_arc_pts, Color(0.0, 0.95, 1.0, 0.28))
	draw_polyline(cone_arc_pts, Color(0.0, 0.95, 1.0, 0.55), 1.0)
	var fwd = Vector2.RIGHT.rotated(heading_angle)
	var right = Vector2.DOWN.rotated(heading_angle)
	var nose = pos + fwd * 7.5
	var left_wing = pos - fwd * 4.5 - right * 5.5
	var right_wing = pos - fwd * 4.5 + right * 5.5
	var engine_indent = pos - fwd * 2.0
	var ship_poly = PackedVector2Array([nose, right_wing, engine_indent, left_wing])
	draw_colored_polygon(ship_poly, Color(0.0, 0.92, 1.0, 0.95))
	draw_polyline(ship_poly, Color.WHITE, 1.2, true)
	draw_circle(engine_indent, 1.8, Color(1.0, 0.5, 0.1))
	draw_circle(engine_indent, 1.0, Color.WHITE)

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

	# v906.0: Precarga de mapas grandes al entrar al mundo:
	# 1) Instanciar ya el diálogo del mapa grande (evita el coste de _build_ui en la
	#    primera pulsación de TAB) y 2) precalentar su textura de terreno de la zona
	#    actual para que abrir el mapa no regeneré 65k muestras de relieve en vivo.
	_ensure_world_map_dialog.call_deferred()
	_precache_world_map_texture.call_deferred()

func _ensure_world_map_dialog() -> void:
	if is_instance_valid(world_map_dialog):
		return
	world_map_dialog = WORLD_MAP_SCRIPT.new()
	get_tree().root.add_child(world_map_dialog)

func _precache_world_map_texture() -> void:
	# Diferido 2 frames: no bloquea el frame de entrada al mundo
	await get_tree().process_frame
	await get_tree().process_frame
	var player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player) or not ("current_zone" in player):
		return
	var z = str(player.current_zone)
	if WorldMapDialog.terrain_cache_by_zone.has(z) and is_instance_valid(WorldMapDialog.terrain_cache_by_zone[z]):
		return
	var wr = WorldMapDialog.get_zone_rect(z, get_tree())
	WorldMapDialog.get_or_create_terrain_texture(z, wr, get_tree())

func toggle_world_map(zone_id_to_show: String = ""):
	_ensure_world_map_dialog()
	world_map_dialog.toggle(zone_id_to_show)

func open_world_map(zone_id_to_show: String = ""):
	_ensure_world_map_dialog()
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
		var hud = get_tree().get_first_node_in_group("hud")
		if not (hud and hud.get("is_editing_layout")):
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
		draw_rect(map_rect, Color(0.0, 0.85, 1.0, 0.45), false, 1.5)

	# Niebla en minimapa deshabilitada por petición (la delimitación de visión se define con el círculo táctico)
	# if fog_overlay_needed and fog_rendering_enabled:
	# 	_draw_minimap_fog(scale_x, scale_y, fog_grid_res, fog_explored, world_rect, player)


	
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
				var tactical_r = clampf(3.5 * (ent_scale / 6.0), 3.5, 12.0)
				dot_r = max(tactical_r, physical_minimap_r)
				if dist_to_player_w > world_radius:
					dot_r = min(dot_r, max(2.5, dist_minimap - 2.5))
				draw_circle(pos, dot_r, Color(0.7, 0.2, 0.95))
				draw_circle(pos, dot_r + 2.0, Color(0.7, 0.2, 0.95, 0.35), false, 1.2)
			else:
				dot_r = max(2.0, physical_minimap_r)
				if dist_to_player_w > world_radius:
					dot_r = min(dot_r, max(1.5, dist_minimap - 1.5))
				draw_circle(pos, dot_r, Color(1.0, 0.4, 0.0))

	# 4. Dibujar Portales de Extracción (Cian de Neón clásico con letra de sector)
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
			extract_points = [
				{"x": 2974, "y": 5038, "label": "Punto Alfa"},
				{"x": 6920, "y": 5070, "label": "Punto Beta"},
				{"x": 5019, "y": 3025, "label": "Punto Gamma"},
				{"x": 5003, "y": 7019, "label": "Punto Delta"}
			]
			
		for pt in extract_points:
			var pt_pos = Vector2(float(pt.x) * scale_x, float(pt.y) * scale_y)
			draw_circle(pt_pos, 6.0, Color(0.0, 0.95, 1.0, 0.9))
			draw_circle(pt_pos, 9.0, Color(0.0, 0.95, 1.0, 0.3), false, 1.5)
			
			var label = str(pt.get("label", "Portal")).to_lower()
			var letter = "E"
			if label.contains("alfa"): letter = "A"
			elif label.contains("beta"): letter = "B"
			elif label.contains("gamma"): letter = "G"
			elif label.contains("delta"): letter = "D"
			
			var font = get_theme_font("font")
			draw_string(font, pt_pos + Vector2(-3, 3), letter, HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)

	# 4.5 Dibujar Altar si es zona de Defensa del Altar (Verde esmeralda con letra 'A')
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
		draw_circle(alt_draw_pos, 7.0, Color(0.0, 1.0, 0.5, 0.95))
		draw_circle(alt_draw_pos, 10.0, Color(0.0, 1.0, 0.5, 0.3), false, 1.5)
		var font_alt = get_theme_font("font")
		draw_string(font_alt, alt_draw_pos + Vector2(-3.5, 4.0), "A", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color.WHITE)
		
		# Dibujar Spawns de Jugadores en el radar
		if full_cfg and full_cfg.has("gameModes") and full_cfg.gameModes.has("altar_defense"):
			var ad = full_cfg.gameModes.altar_defense
			if ad.has("spawnPoints") and ad.spawnPoints is Array:
				for sp in ad.spawnPoints:
					if sp is Dictionary and sp.has("x") and sp.has("y"):
						var sp_pos = Vector2(float(sp.x) * scale_x, float(sp.y) * scale_y)
						var radius_canvas = float(sp.get("radius", 200.0)) * scale_x
						draw_circle(sp_pos, 2.0, Color(0.8, 0.9, 0.0, 0.8))
						draw_circle(sp_pos, radius_canvas, Color(0.8, 0.9, 0.0, 0.12), false, 1.0)
			
			if ad.has("spawners") and ad.spawners is Array:
				for s in ad.spawners:
					if s is Dictionary and s.has("x") and s.has("y"):
						var s_pos = Vector2(float(s.x) * scale_x, float(s.y) * scale_y)
						var radius_canvas = float(s.get("radius", 300.0)) * scale_x
						draw_circle(s_pos, 2.0, Color(1.0, 0.2, 0.2, 0.8))
						draw_circle(s_pos, radius_canvas, Color(1.0, 0.2, 0.2, 0.12), false, 1.0)

	# 6. Dibujar Baúles en el Lobby via grupo de nodos (Círculo dorado con letra 'B')
	for vault in get_tree().get_nodes_in_group("vaults"):
		if is_instance_valid(vault) and vault.visible:
			var vault_pos = Vector2(vault.global_position.x * scale_x, vault.global_position.y * scale_y)
			draw_circle(vault_pos, 5.0, Color(1.0, 0.85, 0.0, 0.95))
			draw_circle(vault_pos, 7.5, Color(1.0, 0.85, 0.0, 0.25), false, 1.5)
			var font_v = get_theme_font("font")
			draw_string(font_v, vault_pos + Vector2(-2.5, 3.0), "B", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)

	# 7. Dibujar Objetos del Mundo desde MAPS_CONFIG (Íconos clásicos y limpios con letras)
	var z_id_str = str(current_zone_id)
	if z_id_str in GameConstants.MAPS_CONFIG:
		var zone_cfg = GameConstants.MAPS_CONFIG[z_id_str]
		if zone_cfg.has("objects") and zone_cfg.objects is Array:
			var font = get_theme_font("font")
			for obj in zone_cfg.objects:
				if not (obj is Dictionary and obj.has("x") and obj.has("y")): continue
				var obj_pos = Vector2(float(obj.x) * scale_x, float(obj.y) * scale_y)
				var obj_type = str(obj.get("type", "chest"))
				
				var show_explicit = obj.get("show_on_minimap", false) == true or obj.get("showOnMinimap", false) == true
				
				var obj_label = str(obj.get("label", "")).to_lower()
				var asset_path = str(obj.get("assetPath", "")).to_lower()
				if obj_type == "wall" and (obj_label.contains("altar") or asset_path.contains("altar")):
					obj_type = "altar"
				
				match obj_type:
					"altar":
						draw_circle(obj_pos, 6.0, Color(0.0, 1.0, 0.5, 0.95))
						draw_circle(obj_pos, 9.0, Color(0.0, 1.0, 0.5, 0.3), false, 1.5)
						draw_string(font, obj_pos + Vector2(-3.0, 3.5), "A", HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color.WHITE)
					"chest", "vault":
						draw_circle(obj_pos, 5.0, Color(1.0, 0.85, 0.0, 0.95))
						draw_circle(obj_pos, 7.5, Color(1.0, 0.85, 0.0, 0.25), false, 1.5)
						draw_string(font, obj_pos + Vector2(-2.5, 3.0), "B", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)
					"door", "portal":
						var target_zone = str(obj.get("targetZoneId", obj.get("targetZone", "")))
						if GameConstants.get("MAPS_CONFIG") and GameConstants.MAPS_CONFIG.has(target_zone):
							var target_map_cfg = GameConstants.MAPS_CONFIG[target_zone]
							if target_map_cfg.has("visible") and target_map_cfg.get("visible") == false:
								continue
						draw_circle(obj_pos, 5.5, Color(0.0, 0.9, 1.0, 0.9))
						draw_circle(obj_pos, 8.0, Color(0.0, 0.9, 1.0, 0.25), false, 1.5)
						draw_string(font, obj_pos + Vector2(-2.5, 3.0), "P", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)
						
						if target_zone != "":
							var dest_name = ""
							if GameConstants.MAPS_CONFIG.has(target_zone):
								dest_name = GameConstants.MAPS_CONFIG[target_zone].get("name", "Sector " + target_zone)
							else:
								dest_name = "Sector " + target_zone
							
							if is_hovered and world_m_pos.distance_to(obj_pos) < 10.0:
								hovered_dest = dest_name
					"tower":
						draw_circle(obj_pos, 6.0, Color(1.0, 0.5, 0.0, 0.9))
						draw_circle(obj_pos, 8.5, Color(1.0, 0.5, 0.0, 0.25), false, 1.5)
						draw_string(font, obj_pos + Vector2(-2.5, 3.0), "T", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)
					"nexus":
						var team = str(obj.get("team", "red")).to_lower()
						var base_color = Color(1.0, 0.15, 0.15) if team == "red" else Color(0.15, 0.5, 1.0)
						draw_circle(obj_pos, 7.0, base_color)
						draw_circle(obj_pos, 10.0, Color(base_color.r, base_color.g, base_color.b, 0.3), false, 1.5)
						draw_string(font, obj_pos + Vector2(-3.5, 3.5), "N", HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color.WHITE)
					"pillar":
						var team = str(obj.get("team", "neutral")).to_lower()
						var base_color = Color(0.85, 0.85, 0.85)
						if team == "red":
							base_color = Color(0.9, 0.2, 0.2)
						elif team == "blue":
							base_color = Color(0.2, 0.4, 0.9)
						draw_circle(obj_pos, 5.5, base_color)
						draw_circle(obj_pos, 8.0, Color(base_color.r, base_color.g, base_color.b, 0.3), false, 1.5)
						draw_string(font, obj_pos + Vector2(-3.0, 3.0), "C", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)
					"market":
						draw_circle(obj_pos, 6.0, Color(1.0, 0.8, 0.2, 0.95))
						draw_circle(obj_pos, 8.5, Color(1.0, 0.8, 0.2, 0.25), false, 1.5)
						draw_string(font, obj_pos + Vector2(-2.5, 3.0), "$", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)
					_:
						if show_explicit:
							draw_circle(obj_pos, 4.0, Color(0.0, 0.9, 1.0, 0.85))
							var mark_letter = obj.get("minimap_letter", obj.get("letter", "*"))
							draw_string(font, obj_pos + Vector2(-2.5, 3.0), str(mark_letter), HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)


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

	# -----------------------------------------------------------------
	# 4.9 DELIMITACIÓN DEL RANGO DE VISIÓN (CÍRCULO DELICADO)
	# -----------------------------------------------------------------
	var vr_draw = vision_r * scale_x
	if vr_draw > 5.0 and vr_draw < r_size.length():
		# Círculo simple, delicado y limpio con antialiasing
		draw_arc(center_screen, vr_draw, 0.0, TAU, 160, Color(0.0, 0.92, 1.0, 0.75), 1.0, true)

	# Cruz de referencia en el centro (muy sutil, sin círculos)
	draw_line(center_screen + Vector2(-5, 0), center_screen + Vector2(5, 0), Color(0.0, 0.9, 1.0, 0.20), 1.0)
	draw_line(center_screen + Vector2(0, -5), center_screen + Vector2(0, 5), Color(0.0, 0.9, 1.0, 0.20), 1.0)

	# -----------------------------------------------------------------
	# 5. JUGADOR LOCAL (ESTÉTICA AAA NÍTIDA) — SIEMPRE EN EL CENTRO
	# -----------------------------------------------------------------
	var p_draw_pos = center_screen
	var cone_angle = -PI/2 if is_rotate_mode else player.rotation
	_draw_local_player(p_draw_pos, cone_angle, is_rotate_mode)
	
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

func _draw_minimap_fog(_scale_x: float, _scale_y: float, _grid_res: int, _explored: Dictionary, _world_rect_or_w: Variant, _worldH_or_player: Variant, _maybe_player: Variant = null):
	return

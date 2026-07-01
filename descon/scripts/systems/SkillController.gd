extends Node2D

# SkillController.gd (v1.3 - Fixed Stuck Indicator)
# Maneja el apuntado, indicadores y modos de disparo (Quick Cast / On Release / Cancelar)

enum CastMode { QUICK_CAST, ON_RELEASE, NORMAL_CAST }
enum SkillType { DIRECTIONAL, POINT_CLICK, AREA, INSTANT }

var current_skill: Dictionary = {}
var is_aiming: bool = false
var selected_target: Node2D = null

# Configuración del usuario
var config = {
	"cast_mode": CastMode.ON_RELEASE,
	"show_range": true,
	"indicator_color": Color(0, 1, 1, 0.4)
}

func _ready():
	set_process(true)
	z_index = 5
	top_level = false
	
	# v260.98: Cargar configuración persistente
	if get_node_or_null("/root/SettingsManager"):
		config.cast_mode = SettingsManager.get_cast_mode()

var external_aim_vector: Vector2 = Vector2.ZERO # v266.680: Para apuntado MOBA desde HUD
var buffered_skill_data: Dictionary = {} # v266.920: Input Buffering
var buffer_timer: float = 0.0
const BUFFER_WINDOW: float = 0.5 # Segundos que vive un input en la cola

func _process(delta):
	if is_aiming:
		queue_redraw()
		_update_targeting()
	
	# v266.920: Procesar buffer de entrada
	if buffer_timer > 0:
		buffer_timer -= delta
		if not is_aiming and not buffered_skill_data.is_empty():
			var data = buffered_skill_data.duplicate()
			buffered_skill_data = {}
			buffer_timer = 0.0
			start_aiming(data)
	elif not buffered_skill_data.is_empty():
		buffered_skill_data = {}

func _unhandled_input(event):
	if is_aiming:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			var mode = config.cast_mode
			
			# v266.133: En ON_RELEASE, el mouse NO dispara la habilidad.
			# Esto permite mover la nave mientras se mantiene la tecla de habilidad presionada.
			if mode == CastMode.ON_RELEASE:
				return 
				
			if event.pressed:
				# Disparo inmediato (Quick Cast / Normal)
				execute_skill()
				get_viewport().set_input_as_handled()
			
		# v260.99: Cancelar con Click Derecho
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cancel_aiming()
			get_viewport().set_input_as_handled()

func _update_targeting():
	# v302.2: Reset de hover global antes de buscar el nuevo
	get_tree().call_group("entities", "set", "is_hovered", false)
	
	# v302.4: Siempre buscar bajo el mouse para el Highlight visual (incluso si no estamos apuntando skill)
	var is_mobile = get_node_or_null("/root/SettingsManager") and SettingsManager.mobile_mode
	var check_pos = get_global_mouse_position()
	
	if is_mobile and external_aim_vector != Vector2.ZERO:
		check_pos = global_position + external_aim_vector
	
	var target = _find_target_at_pos(check_pos)
	if is_instance_valid(target):
		target.is_hovered = true
		if target.has_node("HUD_Layer_Final"): target.get_node("HUD_Layer_Final").queue_redraw()
	
	if current_skill.get("type") == SkillType.POINT_CLICK:
		selected_target = target

func _find_target_at_pos(pos: Vector2) -> Node2D:
	# v302.7: Detección genérica por posición (Funciona en PC y Móvil)
	var entities = get_tree().get_nodes_in_group("entities")
	var best_target = null
	var min_dist = 60.0 # Radio de detección estilo MOBA
	
	for e in entities:
		if is_instance_valid(e):
			var visual_pos = e.get_visual_position() if e.has_method("get_visual_position") else e.global_position
			var dist = visual_pos.distance_to(pos)
			
			if dist < min_dist:
				min_dist = dist
				best_target = e
			
	return best_target

func _find_target_under_mouse() -> Node2D:
	# Fallback para compatibilidad, ahora usa la función genérica
	return _find_target_at_pos(get_global_mouse_position())

func start_aiming(skill_data: Dictionary):
	# v266.920: Si ya estamos apuntando OTRA cosa, guardamos esta en el buffer
	if is_aiming and current_skill.get("id") != skill_data.id:
		buffered_skill_data = skill_data
		buffer_timer = BUFFER_WINDOW
		return

	current_skill = skill_data
	is_aiming = true
	queue_redraw()
	
	var is_mobile = false
	if get_node_or_null("/root/SettingsManager"):
		is_mobile = SettingsManager.mobile_mode
	
	# En MODO CELULAR: Nunca dispara al presionar.
	# El HUD siempre llama execute_skill() al soltar el dedo (on_release).
	# Así el jugador puede arrastrar para apuntar antes de soltar.
	if is_mobile:
		return
	
	# MODO PC: Comportamiento clásico según cast_mode configurado
	if current_skill.get("type") == SkillType.INSTANT:
		if config.cast_mode != CastMode.ON_RELEASE:
			execute_skill()
		return
	
	if config.cast_mode == CastMode.QUICK_CAST:
		execute_skill()

func execute_skill():
	# v266.840: Separación Drástica PC vs CELU
	if not is_aiming: return
	
	var is_mobile = false
	if get_node_or_null("/root/SettingsManager"):
		is_mobile = SettingsManager.mobile_mode
	
	var payload = {
		"skill_id": current_skill.id,
		"angle": 0.0,
		"target": null,
		"pos": Vector2.ZERO
	}
	
	if is_mobile:
		# --- MODO CELULAR: Solo Arrastre o Frente ---
		if external_aim_vector != Vector2.ZERO:
			payload.angle = external_aim_vector.angle()
			payload.pos = global_position + external_aim_vector
			payload.target = selected_target
		else:
			# Tap simple: Disparo hacia adelante de la nave
			payload.angle = get_parent().rotation
			payload.pos = global_position + Vector2.RIGHT.rotated(payload.angle) * 100.0
			
			# v302.5: Auto-Target Self para habilidades de apoyo (Cura/Escudo) en Tap
			var filters = current_skill.get("filters", {})
			if filters.get("allies", false) and not filters.get("enemies", false):
				payload.target = get_parent()
				# print("[SKILL-MOBILE] Auto-target friendly skill to self")
	else:
		# --- MODO PC: Mouse Clásico ---
		# v2.5D: Corrección de coordenadas de apuntado 3D
		var parent_map = get_parent()._get_map_node()
		var target_pos = Vector2.ZERO
		
		if is_instance_valid(parent_map) and not parent_map.use_orthogonal:
			var aim_3d = get_parent().get_aim_target_3d(get_viewport().get_mouse_position())
			target_pos = Vector2(aim_3d.x / parent_map.scale_factor, aim_3d.z / (parent_map.scale_factor * parent_map.correction_z))
		else:
			target_pos = get_global_mouse_position()
			
		payload.angle = (target_pos - global_position).angle()
		payload.pos = target_pos
		payload.target = selected_target
	
	# Limpiar estado (excepto external_aim_vector, que se necesita en activate())
	is_aiming = false
	selected_target = null
	queue_redraw()
	
	if get_parent().has_method("_on_skill_executed"):
		get_parent()._on_skill_executed(payload)
	
	# Limpiar el vector DESPUÉS de ejecutar la skill (Blink lo necesita en activate())
	external_aim_vector = Vector2.ZERO

func cancel_aiming():
	is_aiming = false
	selected_target = null
	queue_redraw()
	print("[SKILL] Apuntado cancelado.")


func _draw():
	if not is_aiming: return
	if current_skill.get("type") == SkillType.INSTANT: return
	
	var range_val = current_skill.get("range", 500.0)
	var color = config.indicator_color
	
	# v420.3: Detectar si estamos en perspectiva 3D para proyectar indicadores correctamente
	var parent_entity = get_parent()
	var parent_map = parent_entity._get_map_node() if parent_entity.has_method("_get_map_node") else null
	var use_perspective = is_instance_valid(parent_map) and not parent_map.use_orthogonal
	var cam3d: Camera3D = null
	var sub_vp: SubViewport = null
	if use_perspective:
		cam3d = parent_map.get("camera_3d")
		sub_vp = parent_map.get("sub_viewport")
		use_perspective = is_instance_valid(cam3d) and is_instance_valid(sub_vp)
	
	# --- FUNCIÓN INTERNA: convierte posición 2D lógica global a posición local visual ---
	# En ortogonal: retorna el mismo punto (to_local de la posición global)
	# En perspectiva: proyecta via cámara 3D y convierte a espacio local del nodo
	var s_factor = parent_map.scale_factor if is_instance_valid(parent_map) else 0.02
	var correction_z = parent_map.correction_z if is_instance_valid(parent_map) else 1.41421356
	
	# Obtener la posición visual del origen (la nave del jugador)
	var origin_vis: Vector2 = global_position
	if use_perspective and parent_entity.has_method("get_visual_position"):
		var vp = parent_entity.get_visual_position()
		if vp != Vector2.ZERO:
			origin_vis = vp
	
	# Convierte un desplazamiento 2D lógico (relativo a la nave) en un desplazamiento visual en pantalla
	var _proj = func(offset_2d: Vector2) -> Vector2:
		if not use_perspective:
			return offset_2d  # En ortogonal: directo
		# 1. El offset_2d está en el espacio local del CanvasItem.
		# Como el CanvasItem está rotado con el jugador, debemos rotar el offset_2d 
		# con la rotación de la nave para obtener el offset lógico global real del mundo.
		var world_offset = offset_2d.rotated(parent_entity.rotation)
		# 2. Posición 2D global lógica en el mundo
		var world_2d = parent_entity.global_position + world_offset
		# 3. Convertir a 3D
		var pos_3d = Vector3(world_2d.x * s_factor, 0.0, world_2d.y * s_factor * correction_z)
		if cam3d.is_position_behind(pos_3d):
			return offset_2d  # Fallback si está detrás
		# Proyectar a píxeles del SubViewport
		var sv_px = cam3d.unproject_position(pos_3d)
		# Escalar SubViewport → pantalla principal
		var main_size = Vector2(get_viewport().get_visible_rect().size)
		if sub_vp.size.x > 0:
			sv_px *= main_size / Vector2(sub_vp.size)
		# Convertir a coordenadas mundo 2D y luego a espacio local de este nodo
		var world_2d_vis = get_viewport().get_canvas_transform().affine_inverse() * sv_px
		return to_local(world_2d_vis)
	
	# Dibujar círculo de rango máximo (proyectando puntos individuales en perspectiva)
	if range_val > 0:
		if use_perspective:
			# Construir el arco punto a punto proyectado
			var steps = 64
			var pts = PackedVector2Array()
			for i in range(steps + 1):
				var ang = (float(i) / steps) * TAU
				var local_pt = Vector2(cos(ang), sin(ang)) * range_val
				pts.append(_proj.call(local_pt))
			draw_polyline(pts, color, 2.0)
		else:
			draw_arc(Vector2.ZERO, range_val, 0, TAU, 64, color, 2.0)
	
	# v266.810: FIX Visual - Compensar rotación de la nave
	var is_mobile = get_node_or_null("/root/SettingsManager") and SettingsManager.mobile_mode
	var aim_vec: Vector2
	if external_aim_vector != Vector2.ZERO:
		aim_vec = external_aim_vector.rotated(-get_parent().rotation)
	else:
		if is_mobile:
			aim_vec = Vector2.ZERO
		else:
			if use_perspective:
				# 1. Obtener la posición lógica 3D real a la que apunta el mouse en el plano del mapa
				var aim_3d = parent_entity.get_aim_target_3d(get_viewport().get_mouse_position())
				var target_pos_logic = Vector2(aim_3d.x / parent_map.scale_factor, aim_3d.z / (parent_map.scale_factor * parent_map.correction_z))
				
				# 2. El vector de dirección va desde la posición lógica global de la nave hacia esa posición lógica
				var diff_logic = target_pos_logic - parent_entity.global_position
				
				# 3. Des-rotar el vector lógico para el espacio local de dibujo del CanvasItem
				aim_vec = diff_logic.rotated(-parent_entity.rotation)
			else:
				aim_vec = get_local_mouse_position()
	
	# 2. Dibujar Indicador
	if current_skill.get("type") == SkillType.DIRECTIONAL:
		var dist = aim_vec.length()
		var end_point = aim_vec
		if range_val > 0 and dist > range_val:
			end_point = aim_vec.normalized() * range_val
		
		# Punto final proyectado a espacio visual
		var end_proj = _proj.call(end_point)
		var origin_local = to_local(origin_vis) if use_perspective else Vector2.ZERO
		
		# v2.9: Ocultar línea para habilidades de teletransporte o minas
		var s_name = current_skill.get("skill_name", "")
		if s_name != "BLINK" and s_name != "REGENERACIÓN ALFA" and current_skill.id != "mine" and current_skill.id != "electron" and current_skill.id != "emp" and s_name != "BARRERA DE VIENTO" and s_name != "BALIZA DE CURACION" and s_name != "PROVOCACION" and s_name != "RESURRECCIÓN":
			draw_line(origin_local, end_proj, Color(color.r, color.g, color.b, 0.6), 3.0)
		
		if current_skill.id == "emp":
			var dir = aim_vec.normalized()
			if aim_vec.length() < 0.1:
				dir = Vector2.RIGHT
			end_point = dir * range_val
			end_proj = _proj.call(end_point)
			draw_line(origin_local, end_proj, Color(0.1, 0.5, 1.0, 0.25), 60.0)
			draw_line(origin_local, end_proj, Color(0.3, 0.7, 1.0, 0.65), 3.0)
		elif current_skill.id == "electron":
			var radius_val = float(current_skill.get("explosionRadius", 120.0))
			var draw_color = Color(0.2, 0.7, 1.0, 0.5)
			var fill_color = Color(0.2, 0.7, 1.0, 0.1)
			if use_perspective:
				# Proyectar el círculo de explosión en perspectiva
				var steps = 48
				var pts_circle = PackedVector2Array()
				for i in range(steps + 1):
					var ang = (float(i) / steps) * TAU
					var pt = end_point + Vector2(cos(ang), sin(ang)) * radius_val
					pts_circle.append(_proj.call(pt))
				draw_polyline(pts_circle, draw_color, 2.0)
				draw_circle(end_proj, 8.0, draw_color)
			else:
				draw_arc(end_point, radius_val, 0, TAU, 64, draw_color, 2.0)
				draw_circle(end_point, radius_val, fill_color)
				draw_circle(end_point, 8.0, draw_color)
		elif current_skill.id == "melee":
			var dir = aim_vec.normalized()
			if aim_vec.length() < 0.1:
				dir = Vector2.RIGHT
			end_point = dir * range_val
			
			var pts_izq = PackedVector2Array()
			var pts_der = PackedVector2Array()
			var pts_tras_izq = PackedVector2Array()
			var pts_tras_der = PackedVector2Array()
			
			var steps = 12
			for j in range(steps + 1):
				var t = float(j) / steps
				
				var theta_izq = -PI/2.0 + t * (PI/2.0)
				var pt_izq = Vector2(cos(theta_izq), sin(theta_izq)) * range_val
				pts_izq.append(_proj.call(pt_izq.rotated(dir.angle())))
				
				var theta_der = PI/2.0 - t * (PI/2.0)
				var pt_der = Vector2(cos(theta_der), sin(theta_der)) * range_val
				pts_der.append(_proj.call(pt_der.rotated(dir.angle())))
				
				var theta_tras_izq = -PI/2.0 - t * (PI/2.0)
				var pt_tras_izq = Vector2(cos(theta_tras_izq), sin(theta_tras_izq)) * range_val
				pts_tras_izq.append(_proj.call(pt_tras_izq.rotated(dir.angle())))
				
				var theta_tras_der = PI/2.0 + t * (PI/2.0)
				var pt_tras_der = Vector2(cos(theta_tras_der), sin(theta_tras_der)) * range_val
				pts_tras_der.append(_proj.call(pt_tras_der.rotated(dir.angle())))
				
			draw_polyline(pts_izq, Color(1.0, 0.45, 0.0, 0.55), 4.0)
			draw_polyline(pts_der, Color(1.0, 0.45, 0.0, 0.55), 4.0)
			draw_polyline(pts_tras_izq, Color(1.0, 0.45, 0.0, 0.35), 4.0)
			draw_polyline(pts_tras_der, Color(1.0, 0.45, 0.0, 0.35), 4.0)
			draw_circle(end_proj, 10.0, Color(1.0, 0.3, 0.0, 0.75))
			draw_circle(_proj.call(-end_point), 10.0, Color(1.0, 0.3, 0.0, 0.45))
		elif s_name == "BARRERA DE VIENTO":
			var width_val = 150.0
			if GameConstants.SKILLS_DATA.has(s_name):
				width_val = float(GameConstants.SKILLS_DATA[s_name].get("width", 150.0))
			var half_w = width_val / 2.0
			var perp_angle = end_point.angle() + (PI / 2.0)
			var wall_offset = Vector2(cos(perp_angle), sin(perp_angle)) * half_w
			
			var pt_a_proj = _proj.call(end_point - wall_offset)
			var pt_b_proj = _proj.call(end_point + wall_offset)
			draw_line(pt_a_proj, pt_b_proj, Color(0.3, 0.9, 1.0, 0.85), 4.0)
			
			var push_dir = end_point.normalized()
			var pt_a_raw = end_point - wall_offset
			var pt_b_raw = end_point + wall_offset
			draw_line(pt_a_proj, _proj.call(pt_a_raw + push_dir * 18.0), Color(0.3, 0.9, 1.0, 0.4), 2.0)
			draw_line(pt_b_proj, _proj.call(pt_b_raw + push_dir * 18.0), Color(0.3, 0.9, 1.0, 0.4), 2.0)
			draw_line(end_proj, _proj.call(end_point + push_dir * 25.0), Color(0.3, 0.9, 1.0, 0.6), 2.0)
		elif s_name == "BALIZA DE CURACION" or s_name == "RESURRECCIÓN":
			var radius_val = 200.0
			if GameConstants.SKILLS_DATA.has(s_name):
				radius_val = float(GameConstants.SKILLS_DATA[s_name].get("radius", 200.0))
			
			var draw_color = Color(0.1, 0.9, 0.2, 0.35)
			var fill_color = Color(0.1, 0.9, 0.2, 0.08)
			if s_name == "RESURRECCIÓN":
				draw_color = Color(0.9, 0.1, 0.9, 0.45)
				fill_color = Color(0.9, 0.1, 0.9, 0.1)
			
			if use_perspective:
				var steps = 64
				var pts_c = PackedVector2Array()
				for i in range(steps + 1):
					var ang = (float(i) / steps) * TAU
					pts_c.append(_proj.call(end_point + Vector2(cos(ang), sin(ang)) * radius_val))
				draw_polyline(pts_c, draw_color, 2.0)
				draw_circle(end_proj, 8.0, draw_color)
			else:
				draw_arc(end_point, radius_val, 0, TAU, 64, draw_color, 2.0)
				draw_circle(end_point, radius_val, fill_color)
				draw_circle(end_point, 8.0, draw_color)
		elif s_name == "PROVOCACION":
			var radius_val = 220.0
			if GameConstants.SKILLS_DATA.has(s_name):
				radius_val = float(GameConstants.SKILLS_DATA[s_name].get("radius", 220.0))
			
			var time_scale = Time.get_ticks_msec() / 1000.0
			var charge_factor = fmod(time_scale * 1.5, 1.0)
			var charge_radius = radius_val * (1.0 - charge_factor)
			
			if use_perspective:
				var steps = 64
				var pts_outer = PackedVector2Array()
				var pts_charge = PackedVector2Array()
				for i in range(steps + 1):
					var ang = (float(i) / steps) * TAU
					pts_outer.append(_proj.call(end_point + Vector2(cos(ang), sin(ang)) * radius_val))
					pts_charge.append(_proj.call(end_point + Vector2(cos(ang), sin(ang)) * charge_radius))
				draw_polyline(pts_outer, Color(1.0, 0.25, 0.2, 0.45), 2.5)
				draw_polyline(pts_charge, Color(1.0, 0.55, 0.1, 0.65), 1.5)
				draw_circle(end_proj, 7.0, Color(1.0, 0.2, 0.2, 0.95))
			else:
				draw_arc(end_point, radius_val, 0, TAU, 64, Color(1.0, 0.25, 0.2, 0.45), 2.5)
				draw_circle(end_point, radius_val, Color(1.0, 0.2, 0.2, 0.08))
				draw_arc(end_point, charge_radius, 0, TAU, 48, Color(1.0, 0.55, 0.1, 0.65), 1.5)
				draw_circle(end_point, 7.0, Color(1.0, 0.2, 0.2, 0.95))
		else:
			draw_circle(end_proj, 8.0, color)
		
	elif current_skill.get("type") == SkillType.POINT_CLICK:
		if selected_target:
			var t_pos: Vector2
			if use_perspective and selected_target.has_method("get_visual_position"):
				var vis = selected_target.get_visual_position()
				t_pos = to_local(vis) if vis != Vector2.ZERO else to_local(selected_target.global_position)
			else:
				t_pos = to_local(selected_target.global_position)
			draw_arc(t_pos, 40.0, 0, TAU, 32, Color.YELLOW, 3.0)
		else:
			draw_circle(aim_vec, 15.0, Color(1, 1, 1, 0.2))

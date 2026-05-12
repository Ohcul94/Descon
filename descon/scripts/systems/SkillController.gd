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

func _process(_delta):
	if is_aiming:
		queue_redraw()
		_update_targeting()

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
	if current_skill.get("type") == SkillType.POINT_CLICK:
		selected_target = _find_target_under_mouse()

func _find_target_under_mouse() -> Node2D:
	# v266.790: Magnetismo eliminado por pedido del usuario.
	# Esta función ahora solo busca si hay algo EXACTAMENTE bajo el puntero (PC).
	if get_node_or_null("/root/SettingsManager") and SettingsManager.mobile_mode:
		return null # En móvil no hay target bajo mouse
		
	var mouse_pos = get_global_mouse_position()
	var entities = get_tree().get_nodes_in_group("entities")
	var me = get_parent()
	
	for e in entities:
		if e == me: continue
		if e.global_position.distance_to(mouse_pos) < 40.0:
			return e
	return null

func start_aiming(skill_data: Dictionary):
	current_skill = skill_data
	
	if current_skill.get("type") == SkillType.INSTANT:
		is_aiming = true
		if config.cast_mode != CastMode.ON_RELEASE:
			execute_skill()
		return

	is_aiming = true
	queue_redraw()
	
	if config.cast_mode == CastMode.QUICK_CAST:
		execute_skill()

func execute_skill(from_hud: bool = false):
	# v266.830: Blindaje Total -from_hud- 
	# Si disparamos desde la HUD, ignoramos el mouse global siempre.
	if not is_aiming: return
	
	var is_mobile = get_node_or_null("/root/SettingsManager") and SettingsManager.mobile_mode
	var mouse_pos = get_global_mouse_position()
	var angle: float
	var target_pos: Vector2
	
	if from_hud or is_mobile or external_aim_vector != Vector2.ZERO:
		if external_aim_vector != Vector2.ZERO:
			angle = external_aim_vector.angle()
			target_pos = global_position + external_aim_vector
		else:
			# Disparo desde HUD sin drag (tap): disparar hacia adelante
			angle = get_parent().rotation
			target_pos = global_position + Vector2.RIGHT.rotated(angle) * 100.0
		selected_target = null
	else:
		# Disparo desde Teclado (PC): Usar Mouse
		angle = (mouse_pos - global_position).angle()
		target_pos = mouse_pos
	
	var payload = {
		"skill_id": current_skill.id,
		"angle": angle,
		"target": selected_target,
		"pos": target_pos
	}
	
	# v261.10: Limpiar estado ANTES de ejecutar para evitar que se quede pegado
	is_aiming = false
	selected_target = null
	external_aim_vector = Vector2.ZERO # v266.682: Limpiar vector MOBA
	queue_redraw()
	
	if get_parent().has_method("_on_skill_executed"):
		get_parent()._on_skill_executed(payload)

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
	if range_val > 0:
		draw_arc(Vector2.ZERO, range_val, 0, TAU, 64, color, 2.0)
	
	# v266.810: FIX Visual - Compensar rotación de la nave
	# El external_aim_vector viene en espacio de mundo (absoluto).
	# Como este nodo es hijo de la nave, _draw() ocurre en espacio local rotado.
	# Debemos des-rotar el vector para que visualmente apunte a donde dice el dedo.
	var is_mobile = get_node_or_null("/root/SettingsManager") and SettingsManager.mobile_mode
	var aim_vec: Vector2
	if external_aim_vector != Vector2.ZERO:
		aim_vec = external_aim_vector.rotated(-get_parent().rotation)
	else:
		if is_mobile:
			aim_vec = Vector2.ZERO # Sin drag = en la nave
		else:
			aim_vec = get_local_mouse_position()
	
	# 2. Dibujar Indicador
	if current_skill.get("type") == SkillType.DIRECTIONAL:
		var dist = aim_vec.length()
		var end_point = aim_vec
		if range_val > 0 and dist > range_val:
			end_point = aim_vec.normalized() * range_val
		
		# v2.9: Ocultar línea para habilidades de teletransporte o minas (Solo queremos el punto)
		var s_name = current_skill.get("skill_name", "")
		if s_name != "BLINK" and current_skill.id != "mine":
			draw_line(Vector2.ZERO, end_point, Color(color.r, color.g, color.b, 0.6), 3.0)
		
		draw_circle(end_point, 8.0, color)
		
	elif current_skill.get("type") == SkillType.POINT_CLICK:
		if selected_target:
			var t_pos = to_local(selected_target.global_position)
			draw_arc(t_pos, 40.0, 0, TAU, 32, Color.YELLOW, 3.0)
		else:
			draw_circle(aim_vec, 15.0, Color(1, 1, 1, 0.2))

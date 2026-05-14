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
	var target = _find_target_under_mouse()
	if is_instance_valid(target):
		target.is_hovered = true
		if target.has_node("HUD_Layer_Final"): target.get_node("HUD_Layer_Final").queue_redraw()
	
	if current_skill.get("type") == SkillType.POINT_CLICK:
		selected_target = target

func _find_target_under_mouse() -> Node2D:
	# v266.790: Magnetismo eliminado por pedido del usuario.
	# Esta función ahora solo busca si hay algo EXACTAMENTE bajo el puntero (PC).
	if get_node_or_null("/root/SettingsManager") and SettingsManager.mobile_mode:
		return null # En móvil no hay target bajo mouse
		
	var mouse_pos = get_global_mouse_position()
	var entities = get_tree().get_nodes_in_group("entities")
	
	# v301.9: Hitbox Inteligente (Estilo MOBA)
	# Buscamos la entidad más cercana al mouse en un radio generoso (60px)
	var best_target = null
	var min_dist = 60.0 # Radio de detección aumentado para clickear el asset fácil
	
	for e in entities:
		# v301.9: Hitbox Inteligente (Estilo MOBA)
		# Consideramos la posición base y un punto superior (el asset real)
		var base_pos = e.global_position
		var asset_pos = base_pos + Vector2(0, -45) 
		
		var dist_base = base_pos.distance_to(mouse_pos)
		var dist_asset = asset_pos.distance_to(mouse_pos)
		var final_dist = min(dist_base, dist_asset)
		
		if final_dist < min_dist:
			min_dist = final_dist
			best_target = e
			
	return best_target

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
		else:
			# Tap simple: Disparo hacia adelante de la nave
			payload.angle = get_parent().rotation
			payload.pos = global_position + Vector2.RIGHT.rotated(payload.angle) * 100.0
		payload.target = null
	else:
		# --- MODO PC: Mouse Clásico ---
		var mouse_pos = get_global_mouse_position()
		payload.angle = (mouse_pos - global_position).angle()
		payload.pos = mouse_pos
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

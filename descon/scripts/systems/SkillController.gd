extends Node2D

# SkillController.gd (v1.3 - Fixed Stuck Indicator)
# Maneja el apuntado, indicadores y modos de disparo (Quick Cast / On Release / Cancelar)

enum CastMode { QUICK_CAST, ON_RELEASE, NORMAL_CAST }
enum SkillType { DIRECTIONAL, POINT_CLICK, AREA }

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

func _process(_delta):
	if is_aiming:
		queue_redraw()
		_update_targeting()

func _unhandled_input(event):
	if is_aiming:
		# v260.99: Cancelar con Click Derecho
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cancel_aiming()
			get_viewport().set_input_as_handled()

func _update_targeting():
	if current_skill.get("type") == SkillType.POINT_CLICK:
		selected_target = _find_target_under_mouse()

func _find_target_under_mouse() -> Node2D:
	var mouse_pos = get_global_mouse_position()
	var entities = get_tree().get_nodes_in_group("entities")
	var closest = null
	var min_dist = 60.0
	if get_node_or_null("/root/SettingsManager"):
		min_dist = 60.0 * SettingsManager.skill_magnetism
	
	for e in entities:
		if e == get_parent(): continue
		var d = e.global_position.distance_to(mouse_pos)
		if d < min_dist:
			min_dist = d
			closest = e
	return closest

func start_aiming(skill_data: Dictionary):
	current_skill = skill_data
	is_aiming = true
	
	if config.cast_mode == CastMode.QUICK_CAST:
		execute_skill()

func execute_skill():
	if not is_aiming: return
	
	var mouse_pos = get_global_mouse_position()
	var angle = (mouse_pos - global_position).angle()
	
	var payload = {
		"skill_id": current_skill.id,
		"angle": angle,
		"target": selected_target,
		"pos": mouse_pos
	}
	
	# v261.10: Limpiar estado ANTES de ejecutar para evitar que se quede pegado
	is_aiming = false
	selected_target = null
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
	
	var range_val = current_skill.get("range", 500.0)
	var color = config.indicator_color
	var mouse_local = get_local_mouse_position()
	
	# 1. Dibujar Rango (Círculo)
	if config.show_range:
		draw_arc(Vector2.ZERO, range_val, 0, TAU, 64, color, 1.5)
	
	# 2. Dibujar Indicador
	if current_skill.get("type") == SkillType.DIRECTIONAL:
		var dist = mouse_local.length()
		var end_point = mouse_local
		if dist > range_val:
			end_point = mouse_local.normalized() * range_val
		
		draw_line(Vector2.ZERO, end_point, Color(color.r, color.g, color.b, 0.6), 3.0)
		draw_circle(end_point, 8.0, color)
		
	elif current_skill.get("type") == SkillType.POINT_CLICK:
		if selected_target:
			var t_pos = to_local(selected_target.global_position)
			draw_arc(t_pos, 40.0, 0, TAU, 32, Color.YELLOW, 3.0)
		else:
			draw_circle(mouse_local, 15.0, Color(1, 1, 1, 0.2))

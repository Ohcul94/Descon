extends Control

# VirtualJoystick.gd (v1.6 - Multi-Touch & PC-Disable Fix)
# Joystick virtual optimizado. No bloquea skills. Auto-destrucción en PC.

signal joystick_updated(direction: Vector2)

@export var border_color: Color = Color(0, 1, 1, 0.5)
@export var stick_color: Color = Color(0, 1, 1, 0.9)

var is_dragging: bool = false
var stick_pos: Vector2 = Vector2.ZERO
var max_dist: float = 50.0
var active_touch_index: int = -1
var is_mobile_enabled: bool = false

func _ready():
	# 1. DETECCIÓN DE MODO: Si no es modo móvil, el joystick NO EXISTE.
	is_mobile_enabled = false
	if get_node_or_null("/root/SettingsManager"):
		is_mobile_enabled = SettingsManager.mobile_mode
	
	# v266.990: Si no hay soporte táctil y el modo móvil está apagado, nos vamos.
	if not is_mobile_enabled and not DisplayServer.is_touchscreen_available():
		queue_free()
		return
	
	# 2. CONFIGURACIÓN INICIAL
	custom_minimum_size = Vector2(100, 100)
	size = Vector2(100, 100)
	mouse_filter = Control.MOUSE_FILTER_IGNORE # CRÍTICO: Nunca bloquea clics/toques de fondo
	visible = false
	
	# Posición fuera de pantalla por defecto
	global_position = Vector2(-200, -200)

func _draw():
	if not visible: return
	var center = size / 2
	draw_circle(center, max_dist, border_color)
	draw_arc(center, max_dist, 0, TAU, 64, border_color, 3.0)
	draw_circle(center + stick_pos, 25, stick_color)

func _unhandled_input(event):
	# v266.991: Solo procesar toques si el modo está activo
	if not is_mobile_enabled: return
	
	var ev_pos = Vector2.ZERO
	var ev_index = -1
	
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		ev_pos = event.position
		ev_index = event.index
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		# Solo permitir mouse si estamos testeando o si no hay touch disponible
		ev_pos = event.position
		ev_index = 0
	else:
		return
		
	# ZONA IZQUIERDA: El joystick solo nace en la mitad izquierda
	var is_left_zone = ev_pos.x < get_viewport_rect().size.x / 2
	
	# --- INICIO DEL TOQUE ---
	if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed):
		if is_left_zone and active_touch_index == -1:
			active_touch_index = ev_index
			is_dragging = true
			visible = true
			global_position = ev_pos - (size / 2)
			_update_joystick(ev_pos)
			
	# --- FIN DEL TOQUE ---
	elif (event is InputEventScreenTouch and not event.pressed) or (event is InputEventMouseButton and not event.pressed):
		if ev_index == active_touch_index:
			_reset_joystick()
			
	# --- MOVIMIENTO ---
	elif event is InputEventScreenDrag or event is InputEventMouseMotion:
		if is_dragging and ev_index == active_touch_index:
			_update_joystick(ev_pos)

func _update_joystick(p: Vector2):
	var center = global_position + (size / 2)
	var diff = p - center
	stick_pos = diff.limit_length(max_dist)
	joystick_updated.emit(stick_pos / max_dist)
	queue_redraw()

func _reset_joystick():
	is_dragging = false
	active_touch_index = -1
	stick_pos = Vector2.ZERO
	joystick_updated.emit(Vector2.ZERO)
	
	var hud = get_tree().get_first_node_in_group("hud")
	var is_edit = hud and hud.get("is_editing_layout")
	
	if not is_edit:
		visible = false
		global_position = Vector2(-200, -200) # Esconder lejos
	
	queue_redraw()

func _process(_delta):
	# v266.995: Mantenimiento de visibilidad y filtros
	var hud = get_tree().get_first_node_in_group("hud")
	var is_edit = hud and hud.get("is_editing_layout")
	
	if not is_mobile_enabled:
		visible = false
		return
		
	if is_edit:
		visible = true
		mouse_filter = Control.MOUSE_FILTER_STOP # En edición sí queremos tocarlo
	elif not is_dragging:
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE # En juego NUNCA bloquea
	
	queue_redraw()

extends Control

# VirtualJoystick.gd (v1.5 - Final Robust Version)
# Joystick virtual para móviles. Mitad izquierda exclusiva. No consume eventos.

signal joystick_updated(direction: Vector2)

@export var border_color: Color = Color(0, 1, 1, 0.5)
@export var stick_color: Color = Color(0, 1, 1, 0.9)

var is_dragging: bool = false
var stick_pos: Vector2 = Vector2.ZERO
var max_dist: float = 50.0
var active_touch_index: int = -1
var is_mobile_enabled: bool = false

func _ready():
	# Tamaño estándar para el área de dibujo
	custom_minimum_size = Vector2(100, 100)
	size = Vector2(100, 100)
	
	# Asegurar que el anclaje sea correcto
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	
	apply_visibility()

func apply_visibility():
	is_mobile_enabled = false
	if get_node_or_null("/root/SettingsManager"):
		is_mobile_enabled = SettingsManager.mobile_mode
	
	# Desactivar si no es móvil para no interferir en PC
	if not is_mobile_enabled:
		visible = false
		set_process(false)
		set_process_unhandled_input(false)
		return
		
	visible = false
	set_process(true)
	set_process_unhandled_input(true)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw():
	if not visible: return
	var center = size / 2
	draw_circle(center, max_dist, border_color)
	draw_arc(center, max_dist, 0, TAU, 64, border_color, 3.0)
	draw_circle(center + stick_pos, 25, stick_color)

func _unhandled_input(event):
	if not is_mobile_enabled: return
	
	# Capturar posición del evento (Soporta Touch y Mouse para pruebas)
	var ev_pos = Vector2.ZERO
	var ev_index = -1
	
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		ev_pos = event.position
		ev_index = event.index
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		ev_pos = event.position
		ev_index = 0
	else:
		return
		
	var is_left = ev_pos.x < get_viewport_rect().size.x / 2
	
	# --- INICIO DRAG ---
	if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed):
		if is_left and active_touch_index == -1:
			active_touch_index = ev_index
			is_dragging = true
			visible = true
			global_position = ev_pos - (size / 2)
			_update_visuals(ev_pos)
			
	# --- FIN DRAG ---
	elif (event is InputEventScreenTouch and not event.pressed) or (event is InputEventMouseButton and not event.pressed):
		if ev_index == active_touch_index:
			_reset_joystick()
			
	# --- MOVIMIENTO ---
	elif event is InputEventScreenDrag or event is InputEventMouseMotion:
		if is_dragging and ev_index == active_touch_index:
			_update_visuals(ev_pos)

func _update_visuals(p: Vector2):
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
	
	# Solo ocultar si no estamos en modo edición
	var hud = get_tree().get_first_node_in_group("hud")
	if not (hud and hud.get("is_editing_layout")):
		visible = false
		
	queue_redraw()

func _process(_delta):
	var hud = get_tree().get_first_node_in_group("hud")
	var is_edit = hud and hud.get("is_editing_layout")
	
	if is_edit:
		if not visible: visible = true
		mouse_filter = Control.MOUSE_FILTER_STOP
	elif not is_dragging:
		if visible: visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	queue_redraw()

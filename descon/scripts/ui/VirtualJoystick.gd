extends Control

# VirtualJoystick.gd (v1.1 - Dead Zone Fix)
# Joystick virtual para móviles. No interfiere con el click-to-move de PC.

signal joystick_updated(direction: Vector2)

@export var border_color: Color = Color(0, 1, 1, 0.3)
@export var stick_color: Color = Color(0, 1, 1, 0.8)

var is_dragging: bool = false
var stick_pos: Vector2 = Vector2.ZERO
var max_dist: float = 50.0

func _ready():
	# v266.610: Tamaño justo para el círculo visual (2 * max_dist = 100px)
	custom_minimum_size = Vector2(100, 100)
	size = Vector2(100, 100)
	apply_visibility()

func apply_visibility():
	var enabled = false
	if get_node_or_null("/root/SettingsManager"):
		enabled = SettingsManager.mobile_mode
	
	visible = enabled
	# v266.675: Cambiamos a IGNORE porque ahora procesamos en _input manualmente
	# para evitar bloqueos fantasma de multi-touch
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _update_joystick_visibility():
	apply_visibility()

func _draw():
	if not visible: return
	var center = size / 2
	draw_circle(center, max_dist, border_color)
	draw_arc(center, max_dist, 0, TAU, 64, border_color, 2.0)
	draw_circle(center + stick_pos, 20, stick_color)

var active_touch_index: int = -1

func _input(event):
	if not visible: return
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.get("is_editing_layout"): return
	
	# Obtener posición del evento (pantalla)
	var event_pos = Vector2.ZERO
	if "position" in event:
		event_pos = event.position
	else:
		return
	
	# v266.690: Detección de área usando rect global del Control
	var rect = get_global_rect()
	# Área generosa para facilitar el toque
	var expanded_rect = Rect2(rect.position - Vector2(20, 20), rect.size + Vector2(40, 40))
	var is_inside = expanded_rect.has_point(event_pos)
	
	if event is InputEventScreenTouch:
		if event.pressed:
			if is_inside and active_touch_index == -1:
				active_touch_index = event.index
				is_dragging = true
				_update_stick_pos(event_pos)
				get_viewport().set_input_as_handled()
		else:
			if event.index == active_touch_index:
				_reset_joystick()
				get_viewport().set_input_as_handled()
				
	elif event is InputEventScreenDrag:
		if event.index == active_touch_index:
			_update_stick_pos(event_pos)
			get_viewport().set_input_as_handled()

	# Failsafe para PC
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if is_inside:
					is_dragging = true
					_update_stick_pos(event_pos)
					get_viewport().set_input_as_handled()
			else:
				if is_dragging:
					_reset_joystick()
					get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and is_dragging:
		_update_stick_pos(event_pos)
		get_viewport().set_input_as_handled()

func _update_stick_pos(screen_pos: Vector2):
	# Convertir posición de pantalla a coordenada local del Control
	var local_pos = screen_pos - global_position
	var center = size / 2
	var diff = local_pos - center
	stick_pos = diff.limit_length(max_dist)
	joystick_updated.emit(stick_pos / max_dist)
	queue_redraw()


func _reset_joystick():
	is_dragging = false
	active_touch_index = -1
	stick_pos = Vector2.ZERO
	joystick_updated.emit(Vector2.ZERO)
	queue_redraw()

func _process(_delta):
	var hud = get_tree().get_first_node_in_group("hud")
	var is_edit = hud and hud.get("is_editing_layout")
	
	if is_edit:
		# En modo edición: siempre visible y con stop para poder arrastrarlo
		if not visible: visible = true
		if mouse_filter != Control.MOUSE_FILTER_STOP:
			mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		# Fuera del editor: respetar la configuración del usuario
		apply_visibility()
	
	queue_redraw()

extends Control

# VirtualJoystick.gd (v1.3 - MOBA Split-Screen & Floating)
# Joystick virtual para móviles. Mitad izquierda exclusiva.

signal joystick_updated(direction: Vector2)

@export var border_color: Color = Color(0, 1, 1, 0.5) # v266.930: Más brillante
@export var stick_color: Color = Color(0, 1, 1, 0.9)

var is_dragging: bool = false
var stick_pos: Vector2 = Vector2.ZERO
var max_dist: float = 50.0
var initial_pos: Vector2 = Vector2.ZERO
var active_touch_index: int = -1

func _ready():
	# v266.930: No forzar tamaño fijo para respetar el Scale del Layout Editor
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(100, 100)
	
	apply_visibility()
	
	# Esperar a que el sistema de Layout del MainHUD termine de posicionarnos
	await get_tree().process_frame
	await get_tree().process_frame
	initial_pos = global_position
	
	# Failsafe: Si el layout nos dejó en 0,0, ir abajo izq
	if initial_pos.length() < 10:
		var screen = get_viewport_rect().size
		initial_pos = Vector2(120, screen.y - 120)
		global_position = initial_pos

var is_mobile_enabled: bool = false

func apply_visibility():
	is_mobile_enabled = false
	if get_node_or_null("/root/SettingsManager"):
		is_mobile_enabled = SettingsManager.mobile_mode
	
	# v266.930: En modo edición siempre visible. En juego, invisible hasta tocar.
	var hud = get_tree().get_first_node_in_group("hud")
	var is_edit = hud and hud.get("is_editing_layout")
	
	visible = is_edit
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw():
	# v266.930: No retornar si es invisible porque queremos verlo en el Editor
	# Godot ya maneja si dibuja o no segun visible.
	var center = size / 2
	draw_circle(center, max_dist, border_color)
	draw_arc(center, max_dist, 0, TAU, 64, border_color, 3.0) # Arco más grueso
	draw_circle(center + stick_pos, 25, stick_color) # Stick un poco más grande

func _unhandled_input(event):
	if not is_mobile_enabled: return
	
	var event_pos = Vector2.ZERO
	if "position" in event:
		event_pos = event.position
	else:
		return
	
	var screen_width = get_viewport_rect().size.x
	var is_in_joystick_zone = event_pos.x < screen_width / 2
	
	if event is InputEventScreenTouch:
		if event.pressed:
			if is_in_joystick_zone and active_touch_index == -1:
				active_touch_index = event.index
				is_dragging = true
				visible = true # MOSTRAR
				global_position = event_pos - (size / 2)
				_update_stick_pos(event_pos)
		else:
			if event.index == active_touch_index:
				_reset_joystick()
				
	elif event is InputEventScreenDrag:
		if event.index == active_touch_index:
			_update_stick_pos(event_pos)
			get_viewport().set_input_as_handled()

	# Failsafe PC
	elif event is InputEventMouseButton and active_touch_index == -1:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if is_in_joystick_zone:
					is_dragging = true
					visible = true
					global_position = event_pos - (size / 2)
					_update_stick_pos(event_pos)
			else:
				if is_dragging:
					_reset_joystick()
	elif event is InputEventMouseMotion and is_dragging and active_touch_index == -1:
		_update_stick_pos(event_pos)

func _update_stick_pos(screen_pos: Vector2):
	var local_pos = (screen_pos - global_position) 
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
	
	# v266.930: NO mover el nodo de vuelta a initial_pos si el usuario lo soltó.
	# Simplemente se hace invisible y se queda ahí para la próxima.
	# Excepto si el modo edición está activo.
	var hud = get_tree().get_first_node_in_group("hud")
	if not (hud and hud.get("is_editing_layout")):
		visible = false
	
	queue_redraw()

func _process(_delta):
	# v266.930: Respetar configuración de Layout
	var hud = get_tree().get_first_node_in_group("hud")
	var is_edit = hud and hud.get("is_editing_layout")
	
	if is_edit:
		if not visible: visible = true
		mouse_filter = Control.MOUSE_FILTER_STOP
	elif not is_dragging:
		if visible: visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	queue_redraw()

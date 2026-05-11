extends Control

# VirtualJoystick.gd (v1.0 - Mobile Control)
# Un joystick virtual minimalista para movimiento de naves.

signal joystick_updated(direction: Vector2)

@export var border_color: Color = Color(0, 1, 1, 0.3)
@export var stick_color: Color = Color(0, 1, 1, 0.8)

var is_dragging: bool = false
var stick_pos: Vector2 = Vector2.ZERO
var max_dist: float = 50.0

func _ready():
	custom_minimum_size = Vector2(120, 120)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_update_joystick_visibility()

func _update_joystick_visibility():
	if get_node_or_null("/root/SettingsManager"):
		visible = SettingsManager.joystick_enabled
	else:
		visible = false

func _draw():
	if not visible: return
	
	# Dibujar base
	draw_circle(size / 2, max_dist, border_color)
	draw_arc(size / 2, max_dist, 0, TAU, 64, border_color, 2.0)
	
	# Dibujar stick
	var center = size / 2
	draw_circle(center + stick_pos, 20, stick_color)

func _gui_input(event):
	# v266.400: Bloquear input si estamos editando el layout (MainHUD lo manejará)
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.get("is_editing_layout"): return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_dragging = true
			else:
				is_dragging = false
				stick_pos = Vector2.ZERO
				joystick_updated.emit(Vector2.ZERO)
				queue_redraw()
				
	elif event is InputEventMouseMotion and is_dragging:
		var center = size / 2
		var diff = event.position - center
		stick_pos = diff.limit_length(max_dist)
		
		var dir = stick_pos / max_dist
		joystick_updated.emit(dir)
		queue_redraw()

func _process(_delta):
	# v266.400: Asegurar visibilidad en tiempo real
	var hud = get_tree().get_first_node_in_group("hud")
	var is_edit = hud and hud.get("is_editing_layout")
	
	if is_edit:
		visible = true # Siempre visible en edición para posicionar
	else:
		_update_joystick_visibility()
	
	queue_redraw()

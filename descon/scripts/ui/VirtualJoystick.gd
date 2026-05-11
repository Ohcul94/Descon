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
	# v266.610: Centralizamos aquí tanto visible como mouse_filter juntos
	# para que _process no pueda deshacer lo que MainHUD hace
	var enabled = false
	if get_node_or_null("/root/SettingsManager"):
		enabled = SettingsManager.joystick_enabled
	
	visible = enabled
	if enabled:
		mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

func _update_joystick_visibility():
	apply_visibility()

func _draw():
	if not visible: return
	var center = size / 2
	draw_circle(center, max_dist, border_color)
	draw_arc(center, max_dist, 0, TAU, 64, border_color, 2.0)
	draw_circle(center + stick_pos, 20, stick_color)

func _gui_input(event):
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
		joystick_updated.emit(stick_pos / max_dist)
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

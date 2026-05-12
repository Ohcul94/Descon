extends Control

# VirtualJoystick.gd (v1.3 - MOBA Split-Screen & Floating)
# Joystick virtual para móviles. Mitad izquierda exclusiva.

signal joystick_updated(direction: Vector2)

@export var border_color: Color = Color(0, 1, 1, 0.3)
@export var stick_color: Color = Color(0, 1, 1, 0.8)

var is_dragging: bool = false
var stick_pos: Vector2 = Vector2.ZERO
var max_dist: float = 50.0
var initial_pos: Vector2 = Vector2.ZERO
var active_touch_index: int = -1

func _ready():
	custom_minimum_size = Vector2(100, 100)
	size = Vector2(100, 100)
	initial_pos = global_position
	apply_visibility()

func apply_visibility():
	var enabled = false
	if get_node_or_null("/root/SettingsManager"):
		enabled = SettingsManager.mobile_mode
	visible = enabled
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw():
	if not visible: return
	var center = size / 2
	draw_circle(center, max_dist, border_color)
	draw_arc(center, max_dist, 0, TAU, 64, border_color, 2.0)
	draw_circle(center + stick_pos, 20, stick_color)

func _unhandled_input(event):
	if not visible: return
	
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
				global_position = event_pos - (size / 2)
				_update_stick_pos(event_pos)
		else:
			if event.index == active_touch_index:
				_reset_joystick()
				
	elif event is InputEventScreenDrag:
		if event.index == active_touch_index:
			_update_stick_pos(event_pos)
			get_viewport().set_input_as_handled()

	# Failsafe PC (Solo si no hay toques activos)
	elif event is InputEventMouseButton and active_touch_index == -1:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if is_in_joystick_zone:
					is_dragging = true
					global_position = event_pos - (size / 2)
					_update_stick_pos(event_pos)
			else:
				if is_dragging:
					_reset_joystick()
	elif event is InputEventMouseMotion and is_dragging and active_touch_index == -1:
		_update_stick_pos(event_pos)

func _update_stick_pos(screen_pos: Vector2):
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
	global_position = initial_pos
	queue_redraw()

func _process(_delta):
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.get("is_editing_layout"):
		visible = true
		mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		apply_visibility()

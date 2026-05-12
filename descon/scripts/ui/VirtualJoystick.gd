extends Control

# VirtualJoystick.gd (v1.7 - La Versión de la Paz)
# Joystick flotante. No bloquea skills. No se borra a sí mismo.

signal joystick_updated(direction: Vector2)

@export var border_color: Color = Color(0, 1, 1, 0.5)
@export var stick_color: Color = Color(0, 1, 1, 0.9)

var is_dragging: bool = false
var stick_pos: Vector2 = Vector2.ZERO
var max_dist: float = 50.0
var active_touch_index: int = -1
var is_mobile_enabled: bool = false

func _ready():
	# 1. Configuración de Tamaño
	custom_minimum_size = Vector2(100, 100)
	size = Vector2(100, 100)
	
	# 2. Empezar ignorando el mouse para que los botones de abajo funcionen
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	
	# Asegurar que esté en la zona izquierda por defecto
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	global_position = Vector2(100, get_viewport_rect().size.y - 150)

func _draw():
	if not visible: return
	var center = size / 2
	# Dibujar base
	draw_circle(center, max_dist, border_color)
	draw_arc(center, max_dist, 0, TAU, 64, border_color, 3.0)
	# Dibujar stick
	draw_circle(center + stick_pos, 25, stick_color)

func _input(event):
	if not is_mobile_enabled: return
	
	# v1.8: Filtrado Multi-Touch Profesional
	# Priorizamos ScreenTouch/Drag. El mouse solo se usa si no hay toques activos (para testing en PC).
	var is_touch = event is InputEventScreenTouch or event is InputEventScreenDrag
	var is_mouse = event is InputEventMouseButton or event is InputEventMouseMotion
	
	if not (is_touch or is_mouse): return
	
	var ev_pos = event.position
	var ev_index = event.index if is_touch else 0
	var screen_width = get_viewport_rect().size.x
	var is_left_zone = ev_pos.x < screen_width / 2
	
	# --- 1. TOQUE INICIAL ---
	if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed):
		# Solo activamos si es en la zona izquierda y no tenemos un toque ya capturado
		if is_left_zone and active_touch_index == -1:
			active_touch_index = ev_index
			is_dragging = true
			visible = true
			
			# Posicionar el joystick donde se tocó (Joystick Flotante)
			global_position = ev_pos - (size / 2)
			_update_pos(ev_pos)
			
			# IMPORTANTE: Marcamos como manejado para que el Player.gd no intente moverse por click
			get_viewport().set_input_as_handled()
			
	# --- 2. TOQUE FINAL (Release) ---
	elif (event is InputEventScreenTouch and not event.pressed) or (event is InputEventMouseButton and not event.pressed):
		if ev_index == active_touch_index:
			_reset_joystick()
			# No marcamos como manejado aquí para permitir que otros sistemas limpien estados si lo necesitan
			
	# --- 3. MOVIMIENTO (Drag) ---
	elif event is InputEventScreenDrag or event is InputEventMouseMotion:
		if is_dragging and ev_index == active_touch_index:
			_update_pos(ev_pos)
			# Marcamos como manejado mientras arrastramos el joystick
			get_viewport().set_input_as_handled()

func _update_pos(p: Vector2):
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
	
	# Solo ocultar si no estamos editando el layout
	var hud = get_tree().get_first_node_in_group("hud")
	if not (hud and hud.get("is_editing_layout")):
		visible = false
	
	queue_redraw()

func _process(_delta):
	# Actualizar estado de modo celular en tiempo real
	if get_node_or_null("/root/SettingsManager"):
		is_mobile_enabled = SettingsManager.mobile_mode
	
	var hud = get_tree().get_first_node_in_group("hud")
	var is_edit = hud and hud.get("is_editing_layout")
	
	if is_edit:
		if not visible: visible = true
		mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		# En juego normal, NUNCA bloqueamos el mouse para no estorbar a los botones
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Si no hay drag, el joystick es invisible (Flotante)
		if not is_dragging:
			visible = false
			
	queue_redraw()

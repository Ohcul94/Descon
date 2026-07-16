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
	
	# v1.8.1: Bloqueo de seguridad para Login
	if not NetworkManager or not NetworkManager.is_logged_in: return
	
	# v1.8.2: Prioridad de UI - Ignorar si tocamos sobre cualquier botón, skill o elemento interactivo de la interfaz
	if not is_dragging:
		var is_pointer = event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag
		if is_pointer:
			if _is_point_over_ui(event.position):
				return
	
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
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		is_mobile_enabled = sm.mobile_mode
	
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

func _is_point_over_ui(pos: Vector2) -> bool:
	# 1. Verificar MainHUD y sus componentes directos (prioridades, barra de control y skills)
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		if hud.has_method("_is_pos_over_priority_ui") and hud._is_pos_over_priority_ui(pos):
			return true
		if "skills_hud" in hud and is_instance_valid(hud.skills_hud) and hud.skills_hud.visible:
			if hud.skills_hud.get_global_rect().has_point(pos):
				return true
		if "control_bar" in hud and is_instance_valid(hud.control_bar) and hud.control_bar.visible:
			if hud.control_bar.get_global_rect().has_point(pos):
				return true
		# Búsqueda recursiva dentro del propio MainHUD (por si hay botones flotantes como el del chat, etc.)
		if _check_control_at_pos(hud, pos):
			return true

	# 2. Verificar grupo de Inventario
	for inv in get_tree().get_nodes_in_group("inventory_ui"):
		if inv is Control and inv.visible and _check_control_at_pos(inv, pos):
			return true

	# 3. Verificar Portal de Salto en el mapa (Map_Extraction)
	var extraction_map = get_tree().get_first_node_in_group("map")
	if extraction_map:
		var portal_canvas = extraction_map.get_node_or_null("PortalUICanvas")
		if portal_canvas and _check_control_at_pos(portal_canvas, pos):
			return true

	# 4. Verificar interacción física con objetos del escenario (baúles, cofres de botín, etc.)
	var world_touch_pos = get_global_mouse_position()
	
	# A. Verificar baúles en el escenario
	for vault in get_tree().get_nodes_in_group("vaults"):
		if is_instance_valid(vault) and vault.get("is_interactable") == true:
			var dist = vault.global_position.distance_to(world_touch_pos)
			if dist <= 120.0:
				return true
				
	# B. Verificar botín/cofres y otras entidades interactivas en escena
	var world_node = get_tree().get_first_node_in_group("world_node")
	if world_node:
		var entities_parent = world_node.get_node_or_null("Entities")
		if is_instance_valid(entities_parent):
			for child in entities_parent.get_children():
				if is_instance_valid(child) and child.get("is_interactable") == true:
					var dist = child.global_position.distance_to(world_touch_pos)
					# Radio de 100 píxeles para dar un margen cómodo a los dedos en pantalla táctil
					if dist <= 100.0:
						return true

	return false

func _check_control_at_pos(node: Node, pos: Vector2) -> bool:
	if not is_instance_valid(node): return false
	
	if node is Control:
		# Ignorar el propio joystick y sus hijos
		if node == self or is_ancestor_of(node):
			return false
		# Solo nos importan controles visibles e interactivos
		if node.visible and node.get_global_rect().has_point(pos):
			if node.mouse_filter != Control.MOUSE_FILTER_IGNORE:
				return true
				
	for child in node.get_children():
		if child is Control and not child.visible:
			continue
		if _check_control_at_pos(child, pos):
			return true
			
	return false

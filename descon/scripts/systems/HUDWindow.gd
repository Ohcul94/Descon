extends Control
class_name HUDWindow

# HUDWindow.gd (Visual Interface v1.50)
# Base para ventanas HUD con cabecera de arrastre (Draggable).

@export var window_id: String = ""
@export var header_height: int = 24

var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO

signal minimized(id)

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	# v189.70: Backup automático de ID si no se definió en el editor
	if window_id == "": 
		window_id = name
		print("[HUD] ID Automático asignado a ventana: ", window_id)
		
	_load_position()

func _input(event):
	if is_dragging and event is InputEventMouseMotion:
		var target = self
		if name == "DragHandler": target = get_parent()
		target.global_position = get_global_mouse_position() - drag_offset
		accept_event()
	
	if is_dragging and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			is_dragging = false
			modulate.a = 1.0
			_save_position()

func _gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# v165.50: Arrastre inteligente. 
			# Se permite arrastrar desde arriba (header_height) o si es el chat.
			if event.position.y <= header_height:
				is_dragging = true
				drag_offset = event.position
				modulate.a = 0.7
				
				var target = self
				if name == "DragHandler": target = get_parent()
				
				# Traer al frente
				if target.get_parent():
					target.get_parent().move_child(target, target.get_parent().get_child_count() - 1)
				
				accept_event()
				print("[HUD] ARRASTRE INICIADO: ", window_id)

func toggle_minimize():
	visible = !visible
	minimized.emit(window_id)
	_save_position()

func _save_position():
	if window_id == "": return
	
	# v190.10: MODO RESPONSIVO - Guardar como porcentaje de la pantalla (0.0 a 1.0)
	var screen_size = get_viewport_rect().size
	var percent_pos = {
		"x": global_position.x / screen_size.x,
		"y": global_position.y / screen_size.y
	}
	
	if NetworkManager and NetworkManager.network_connected:
		NetworkManager.send_event("saveHUD", {
			"id": window_id,
			"pos": percent_pos
		})
		print("[HUD-TRANS] Enviando posición porcentual: ", percent_pos)

func _load_position():
	# v189.90: Ya no cargamos de disco. El MainHUD aplicará las posiciones desde el servidor
	# al recibir el evento de login_success.
	pass

extends Control

# EventsPanel.gd (v1.1 - Sci-Fi Premium Aesthetic)
# Sincronizado con la estética del Hangar (F1)

@onready var tabs = $Window/TabContainer
@onready var extraction_tab = $Window/TabContainer/Extraction
@onready var modes_tab = $Window/TabContainer/GameModes
@onready var queue_btn = $Window/TabContainer/Extraction/QueueButton
@onready var status_label = $Window/TabContainer/Extraction/StatusLabel

var is_in_queue = false
var is_open = false

func _ready():
	add_to_group("events_ui")
	add_to_group("inventory_ui") # v1.2: Tratar como panel principal
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	var win = get_node_or_null("Window")
	if win: 
		win.mouse_filter = Control.MOUSE_FILTER_STOP
		# Protocolo de exorcismo de títulos (como en Inventory.gd)
		for child in win.get_children():
			if child is Label: child.visible = false
	
	if queue_btn:
		queue_btn.pressed.connect(_on_queue_pressed)
		
	if NetworkManager:
		NetworkManager.extraction_queue_joined.connect(_on_queue_joined)
		NetworkManager.extraction_match_found.connect(_on_match_found)
		NetworkManager.extraction_match_countdown.connect(_on_match_countdown)
		NetworkManager.extraction_match_cancelled.connect(func(_d): is_in_queue = false; _update_ui())
		
	# Sincronía Responsive
	get_viewport().size_changed.connect(func(): queue_redraw())

func toggle():
	is_open = !is_open
	visible = is_open
	
	if is_open:
		# Traer al frente
		if get_parent():
			get_parent().move_child(self, get_parent().get_child_count() - 1)
		top_level = true
		z_index = 100
		_update_ui()
	else:
		top_level = false
		z_index = 0
		
	queue_redraw()

func _draw():
	if not visible: return
	var screen_size = get_viewport_rect().size
	# 80% de la pantalla como pidió el usuario
	var r_size = Vector2(screen_size.x * 0.80, screen_size.y * 0.80)
	var r_pos = (screen_size - r_size) / 2.0
	
	# Actualizar Window física
	var win = get_node_or_null("Window")
	if win:
		win.position = r_pos
		win.size = r_size
		
		var tabs_node = win.get_node_or_null("TabContainer")
		if tabs_node:
			tabs_node.offset_top = 45
			tabs_node.offset_left = 15
			tabs_node.offset_right = -15
			tabs_node.offset_bottom = -15
	
	# Dibujar fondo y bordes (Estética Hangar F1)
	draw_rect(Rect2(r_pos, r_size), Color(0.02, 0.02, 0.05, 0.98)) # Fondo oscuro
	draw_rect(Rect2(r_pos, Vector2(r_size.x, 35)), Color(0, 0.08, 0.12, 1.0)) # Cabecera
	draw_rect(Rect2(r_pos, r_size), Color(0, 0.8, 1, 0.5), false, 1.5) # Borde Cian
	
	# Título
	var f = get_theme_font("font")
	draw_string(f, r_pos + Vector2(20, 22), "CENTRO DE EVENTOS Y MISIONES", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 1, 1))
	
	# Botón Cerrar [X]
	draw_rect(Rect2(r_pos.x + r_size.x - 35, r_pos.y+8, 25, 18), Color(0, 1, 1), false, 1.0)
	draw_string(f, r_pos + Vector2(r_size.x-30, 21), "[X]", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 1, 1))

func _input(event):
	var is_click = false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		is_click = true
	elif event is InputEventScreenTouch and event.pressed:
		is_click = true

	if is_click and visible:
		var screen_size = get_viewport_rect().size
		var r_size = Vector2(screen_size.x * 0.80, screen_size.y * 0.80)
		var r_pos = (screen_size - r_size) / 2
		var x_rect = Rect2(r_pos.x + r_size.x - 35, r_pos.y + 8, 25, 18)
		if x_rect.has_point(event.position): 
			toggle()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if is_open:
			toggle()
			get_viewport().set_input_as_handled()

func _update_ui():
	if status_label:
		if is_in_queue:
			status_label.text = "ESTADO: BUSCANDO PARTIDA..."
			status_label.modulate = Color.GREEN
			queue_btn.text = "CANCELAR COLA"
		else:
			status_label.text = "ESTADO: DISPONIBLE"
			status_label.modulate = Color.WHITE
			queue_btn.text = "APLICAR EN COLA"

func _on_queue_pressed():
	if not NetworkManager: return
	
	if is_in_queue:
		NetworkManager.send_event("leaveExtractionQueue", {})
		is_in_queue = false
		notify("HAS SALIDO DE LA COLA", "warn")
	else:
		NetworkManager.send_event("joinExtractionQueue", {})
		notify("UNIÉNDOSE A LA COLA...", "info")
	
	_update_ui()

func _on_queue_joined(data: Dictionary):
	is_in_queue = true
	var pos = data.get("position", 1)
	notify("ESTÁS EN LA COLA (POSICIÓN: " + str(pos) + ")", "success")
	_update_ui()

func _on_match_found(_data: Dictionary):
	is_in_queue = false
	is_open = false
	visible = false
	notify("¡PARTIDA ENCONTRADA! SALTANDO...", "success")
	_update_ui()

func _on_match_countdown(data: Dictionary):
	is_in_queue = true
	var time = data.get("remaining", 0)
	var ps = data.get("players", 0)
	var min_p = data.get("minPlayers", 0)
	if status_label:
		status_label.text = "PARTIDA INICIANDO EN %ds (%d/%d)" % [time, ps, min_p]
		status_label.modulate = Color.YELLOW

func notify(msg: String, type: String = "info"):
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("notify"):
		hud.notify(msg, type)

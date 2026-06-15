extends Control

# HousingPanel.gd - Panel de Control del Hangar Privado (F3)
# Sincronizado con la estética cian y metalizada del juego.

var is_open = false
var unlocked = false

var title_label: Label
var status_label: Label
var req_label: Label
var price_label: Label
var action_btn: Button

func _ready():
	add_to_group("inventory_ui") # Bloquea clicks globales
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_setup_ui()
	
	if NetworkManager:
		NetworkManager.socket_event_received.connect(_on_socket_event_received)
		NetworkManager.inventory_data.connect(_on_inventory_data)
		
	# Redibujar al cambiar de tamaño
	get_viewport().size_changed.connect(func(): queue_redraw())

func _setup_ui():
	for child in get_children():
		child.queue_free()
		
	# Panel de Fondo
	var main_panel = Panel.new()
	main_panel.name = "MainPanel"
	main_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(main_panel)
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.02, 0.05, 0.98)
	sb.border_width_left = 2; sb.border_width_top = 2
	sb.border_width_right = 2; sb.border_width_bottom = 2
	sb.border_color = Color.CYAN
	sb.set_corner_radius_all(8)
	main_panel.add_theme_stylebox_override("panel", sb)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 25)
	main_panel.add_child(vbox)
	
	# Header
	var header = HBoxContainer.new()
	vbox.add_child(header)
	
	title_label = Label.new()
	title_label.text = "SISTEMA DE HANGAR DE JUGADOR (HOUSING)"
	title_label.add_theme_color_override("font_color", Color.CYAN)
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	
	var close_x = Button.new()
	close_x.text = " X "
	close_x.custom_minimum_size = Vector2(40, 40)
	close_x.pressed.connect(func(): toggle())
	header.add_child(close_x)
	
	vbox.add_child(HSeparator.new())
	
	# Cuerpo del panel
	var body_vbox = VBoxContainer.new()
	body_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	body_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_vbox.add_theme_constant_override("separation", 15)
	vbox.add_child(body_vbox)
	
	status_label = Label.new()
	status_label.text = "ESTADO: DESCONOCIDO"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 14)
	body_vbox.add_child(status_label)
	
	req_label = Label.new()
	req_label.text = "Requisito de Nivel: Nivel 5"
	req_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_vbox.add_child(req_label)
	
	price_label = Label.new()
	price_label.text = "Costo: 10000 HUBS"
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_label.add_theme_color_override("font_color", Color.YELLOW)
	body_vbox.add_child(price_label)
	
	action_btn = Button.new()
	action_btn.custom_minimum_size = Vector2(250, 50)
	action_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	action_btn.text = "COMPRAR HANGAR PRIVADO"
	action_btn.pressed.connect(_on_action_pressed)
	body_vbox.add_child(action_btn)

func toggle():
	is_open = !is_open
	visible = is_open
	
	if is_open:
		# Traer al frente
		if get_parent():
			get_parent().move_child(self, get_parent().get_child_count() - 1)
		top_level = true
		z_index = 100
		
		# Solicitar estado actual al abrir
		if NetworkManager:
			NetworkManager.send_event("getHousingState", {})
	else:
		top_level = false
		z_index = 0
		
	queue_redraw()

func _draw():
	if not visible: return
	var screen_size = get_viewport_rect().size
	var r_size = Vector2(screen_size.x * 0.5, screen_size.y * 0.6) # Tamaño más compacto
	var r_pos = (screen_size - r_size) / 2.0
	
	var main_panel = get_node_or_null("MainPanel")
	if main_panel:
		main_panel.position = r_pos
		main_panel.size = r_size

func _input(event):
	if is_open and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		toggle()
		get_viewport().set_input_as_handled()

func _on_action_pressed():
	if not NetworkManager: return
	
	if not unlocked:
		NetworkManager.send_event("buyHousing", {})
	else:
		# Ingresar al Hangar (Zona 100)
		NetworkManager.send_event("changeZone", 100)
		toggle()

func _on_socket_event_received(event_name: String, data: Dictionary):
	if event_name == "housingState":
		unlocked = data.get("unlocked", false)
		_update_ui()

func _on_inventory_data(data: Dictionary):
	# También se recibe el estado en la sincronización del jugador
	if data.has("housing"):
		var h_data = data["housing"]
		unlocked = h_data.get("unlocked", false)
		_update_ui()

func _update_ui():
	# Obtener configuración del config del servidor
	var full_config = GameConstants.get("FULL_CONFIG")
	var req_lvl = 5
	var cost = 10000
	var currency = "hubs"
	
	if full_config and full_config.has("housingConfig"):
		var hc = full_config.housingConfig
		req_lvl = int(hc.get("levelRequired", 5))
		cost = int(hc.get("cost", 10000))
		currency = str(hc.get("currency", "hubs")).to_upper()
		
	if req_label: req_label.text = "Requisito de Nivel: Nivel " + str(req_lvl)
	if price_label: price_label.text = "Costo de Adquisición: " + str(cost) + " " + currency
	
	if unlocked:
		if status_label: 
			status_label.text = "ESTADO: ¡HANGAR DESBLOQUEADO!"
			status_label.modulate = Color.GREEN
		if action_btn:
			action_btn.text = "INGRESAR A MI HANGAR"
			action_btn.modulate = Color.CYAN
	else:
		if status_label:
			status_label.text = "ESTADO: PROPIEDAD NO ADQUIRIDA"
			status_label.modulate = Color.YELLOW
		if action_btn:
			action_btn.text = "COMPRAR HANGAR PRIVADO"
			action_btn.modulate = Color.WHITE

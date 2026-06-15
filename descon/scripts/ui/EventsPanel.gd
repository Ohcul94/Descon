extends Control

# EventsPanel.gd (v1.3 - Modular Event Center & Altar Defense)
# Sincronizado con la estética del Hangar (F1)

@onready var tabs = $Window/TabContainer
@onready var hunt_tab = get_node_or_null("Window/TabContainer/Hunt")
@onready var extraction_tab = get_node_or_null("Window/TabContainer/Extraction")
@onready var arenas_tab = get_node_or_null("Window/TabContainer/Arenas")
@onready var queue_btn = get_node_or_null("Window/TabContainer/Extraction/QueueButton")
@onready var status_label = get_node_or_null("Window/TabContainer/Extraction/StatusLabel")

var altar_defense_tab: VBoxContainer
var ad_queue_btn: Button
var ad_status_label: Label
var is_in_ad_queue = false

var arena_queue_btn: Button
var arena_status_label: Label
var is_in_arena_queue = false

var is_in_queue = false
var is_open = false

func _ready():
	if tabs:
		tabs.current_tab = 1 # v1.2: Mostrar Extracción (único construido) por defecto

		# Programmatic setup of Arenas Tab
		if arenas_tab:
			for child in arenas_tab.get_children():
				child.queue_free()
			
			var vbox = VBoxContainer.new()
			vbox.alignment = BoxContainer.ALIGNMENT_CENTER
			vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			arenas_tab.add_child(vbox)
			
			var arena_title = Label.new()
			arena_title.text = "COMBATE EN ARENAS (PVP)"
			arena_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			arena_title.add_theme_font_size_override("font_size", 24)
			arena_title.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
			vbox.add_child(arena_title)
			
			arena_status_label = Label.new()
			arena_status_label.text = "ESTADO: DISPONIBLE"
			arena_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vbox.add_child(arena_status_label)
			
			var arena_spacer = Control.new()
			arena_spacer.custom_minimum_size = Vector2(0, 20)
			vbox.add_child(arena_spacer)
			
			arena_queue_btn = Button.new()
			arena_queue_btn.custom_minimum_size = Vector2(240, 50)
			arena_queue_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			arena_queue_btn.text = "BUSCAR PARTIDA PVP"
			vbox.add_child(arena_queue_btn)
			arena_queue_btn.pressed.connect(_on_arena_queue_pressed)

		# Programmatic creation of Altar Defense tab
		altar_defense_tab = VBoxContainer.new()
		altar_defense_tab.name = "Defensa del Altar"
		altar_defense_tab.alignment = BoxContainer.ALIGNMENT_CENTER
		
		var ad_title = Label.new()
		ad_title.text = "DEFENSA DEL ALTAR"
		ad_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ad_title.add_theme_font_size_override("font_size", 24)
		ad_title.add_theme_color_override("font_color", Color(0, 0.8, 1))
		altar_defense_tab.add_child(ad_title)
		
		ad_status_label = Label.new()
		ad_status_label.text = "ESTADO: DISPONIBLE"
		ad_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		altar_defense_tab.add_child(ad_status_label)
		
		var ad_spacer = Control.new()
		ad_spacer.custom_minimum_size = Vector2(0, 20)
		altar_defense_tab.add_child(ad_spacer)
		
		ad_queue_btn = Button.new()
		ad_queue_btn.custom_minimum_size = Vector2(240, 50)
		ad_queue_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ad_queue_btn.text = "INSCRIBIR GRUPO"
		altar_defense_tab.add_child(ad_queue_btn)
		
		tabs.add_child(altar_defense_tab)
		ad_queue_btn.pressed.connect(_on_ad_queue_pressed)

	add_to_group("events_ui")
	add_to_group("inventory_ui") # v1.2: Tratar como panel principal
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
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
		
		NetworkManager.altar_defense_cancelled.connect(func(_d): is_in_ad_queue = false; _update_ui())
		NetworkManager.altar_defense_success.connect(func(_d): is_in_ad_queue = false; is_open = false; visible = false; _update_ui())
		
		NetworkManager.arena_queue_joined.connect(_on_arena_queue_joined)
		NetworkManager.arena_queue_left.connect(func(): is_in_arena_queue = false; _update_ui())
		NetworkManager.arena_queue_update.connect(_on_arena_queue_update)
		NetworkManager.arena_match_started.connect(_on_arena_match_started)
		NetworkManager.arena_finished.connect(func(_d): is_in_arena_queue = false; _update_ui())
		
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
	# 85% de la pantalla para coincidir exactamente con el Inventario (F1)
	var r_size = Vector2(screen_size.x * 0.85, screen_size.y * 0.85)
	var r_pos = (screen_size - r_size) / 2.0
	
	# Actualizar Window física
	var win = get_node_or_null("Window")
	if win:
		win.position = r_pos
		win.size = r_size
		
		var tabs_node = win.get_node_or_null("TabContainer")
		if tabs_node:
			tabs_node.offset_top = 40; tabs_node.offset_left = 15
			tabs_node.offset_right = -15; tabs_node.offset_bottom = -15
	
	# Dibujar fondo y bordes (Estética Hangar F1)
	draw_rect(Rect2(r_pos, r_size), Color(0.02, 0.02, 0.05, 0.98)) # Fondo oscuro
	draw_rect(Rect2(r_pos, Vector2(r_size.x, 35)), Color(0, 0.08, 0.12, 1.0)) # Cabecera
	draw_rect(Rect2(r_pos, r_size), Color(0, 0.8, 1, 0.5), false, 1.5) # Borde Cian
	
	# Título
	var f = get_theme_font("font")
	draw_string(f, r_pos + Vector2(20, 22), "CENTRO DE EVENTOS Y MISIONES", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 1, 1))
	
	# Botón X (Cerrar) optimizado para legibilidad y celulares
	draw_rect(Rect2(r_pos.x + r_size.x - 50, r_pos.y+6, 40, 24), Color(0, 1, 1), false, 1.2)
	draw_string(f, r_pos + Vector2(r_size.x-36, 22), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0, 1, 1))

func _input(event):
	var is_click = false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		is_click = true
	elif event is InputEventScreenTouch and event.pressed:
		is_click = true

	if is_click and visible:
		var screen_size = get_viewport_rect().size
		var r_size = Vector2(screen_size.x * 0.85, screen_size.y * 0.85)
		var r_pos = (screen_size - r_size) / 2
		# Tap target de 60x40 para facil toque en celulares (no solapa con el texto M)
		var x_rect = Rect2(r_pos.x + r_size.x - 60, r_pos.y, 60, 40)
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
			
	if ad_status_label and ad_queue_btn:
		var has_party = PartyManager.current_party != null
		var is_leader = false
		var lp = get_tree().get_first_node_in_group("player")
		if is_instance_valid(lp) and has_party:
			is_leader = (lp.db_id == PartyManager.current_party.id)
			
		if is_in_ad_queue:
			ad_status_label.text = "ESTADO: GRUPO INSCRITO (ESPERANDO EVENTO)"
			ad_status_label.modulate = Color.GREEN
			ad_queue_btn.text = "CANCELAR INSCRIPCIÓN"
			ad_queue_btn.disabled = not is_leader if has_party else false
		else:
			ad_status_label.text = "ESTADO: DISPONIBLE"
			ad_status_label.modulate = Color.WHITE
			if has_party:
				if is_leader:
					ad_queue_btn.text = "INSCRIBIR GRUPO"
					ad_queue_btn.disabled = false
				else:
					ad_queue_btn.text = "SOLO LÍDER PUEDE INSCRIBIR"
					ad_queue_btn.disabled = true
			else:
				ad_queue_btn.text = "INSCRIBIRSE (SOLO)"
				ad_queue_btn.disabled = false
				
	if arena_status_label and arena_queue_btn:
		if is_in_arena_queue:
			arena_status_label.text = "ESTADO: BUSCANDO PARTIDA PVP..."
			arena_status_label.modulate = Color.GREEN
			arena_queue_btn.text = "CANCELAR BÚSQUEDA"
		else:
			arena_status_label.text = "ESTADO: DISPONIBLE"
			arena_status_label.modulate = Color.WHITE
			arena_queue_btn.text = "BUSCAR PARTIDA PVP"

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

func _on_ad_queue_pressed():
	if not NetworkManager: return
	
	if is_in_ad_queue:
		NetworkManager.send_event("leaveAltarDefenseQueue", {})
		is_in_ad_queue = false
		notify("INSCRIPCIÓN CANCELADA", "warn")
	else:
		NetworkManager.send_event("registerAltarDefenseParty", {})
		if PartyManager.current_party == null:
			is_in_ad_queue = true
			notify("TE HAS INSCRITO AL EVENTO", "success")
		else:
			notify("ENVIANDO INVITACIÓN A LOS COMPAÑEROS...", "info")
			
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

func _on_arena_queue_pressed():
	if not NetworkManager: return
	if is_in_arena_queue:
		NetworkManager.send_event("leaveArenaQueue", {})
		is_in_arena_queue = false
		notify("BÚSQUEDA CANCELADA", "warn")
	else:
		NetworkManager.send_event("joinArenaQueue", {})
		notify("UNIÉNDOSE A LA COLA DE ARENAS...", "info")
	_update_ui()

func _on_arena_queue_joined(_data):
	is_in_arena_queue = true
	notify("TE HAS UNIDO A LA COLA DE ARENAS", "success")
	_update_ui()

func _on_arena_queue_update(data):
	var count = data.get("count", 0)
	if arena_status_label and is_in_arena_queue:
		arena_status_label.text = "BUSCANDO PARTIDA... PILOTOS EN COLA: " + str(count)

func _on_arena_match_started(_data):
	is_in_arena_queue = false
	is_open = false
	visible = false
	notify("¡PARTIDA DE ARENA ENCONTRADA! PREPARANDO COMBATE...", "success")
	_update_ui()

extends Control

# MainHUD.gd (Omni-HUD v34.0 - Draggable & Minimizable)
# Ahora soporta el sistema de arrastre y minimización "como en el juego viejo".

@onready var hubs_label = $CenterStats/VBox/Currency/HUBS
@onready var ohcu_label = $CenterStats/VBox/Currency/OHCU
@onready var lvl_label = $CenterStats/VBox/LevelInfo/LVL
@onready var speed_label = null # Se inyectará dinámicamente v164.91

@onready var fps_label = $TopLeft/FPS
@onready var ms_label = $TopLeft/MS
@onready var online_label = $TopLeft/ONLINE

@onready var center_stats = $CenterStats
@onready var radar_window = $RadarWindow
@onready var skills_hud = $Skills

var _ammo_nodes = {}

func _ready():
	mouse_filter = Control.MOUSE_FILTER_PASS
	
	# v167.30: Inyectar Icono de Escuadrón (Identidad Visual Original)
	var c_bar = get_node_or_null("ControlBar")
	if c_bar and not c_bar.has_node("IconSquad"):
		var btn = Button.new()
		btn.name = "IconSquad"
		btn.text = "👥"
		btn.flat = true
		btn.custom_minimum_size = Vector2(30,30)
		
		# Estilo Idéntico al resto de la ControlBar (v167.30)
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0,0,0,0)
		sb.border_width_bottom = 1
		sb.border_color = Color.CYAN
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_font_size_override("font_size", 14)
		
		c_bar.add_child(btn)
		c_bar.move_child(btn, 0) # Posición original
	
	# Configurar barra de control
	for btn in $ControlBar.get_children():
		var id = btn.name.replace("Icon", "")
		if not btn.pressed.is_connected(_on_icon_pressed):
			btn.pressed.connect(_on_icon_pressed.bind(id))
	
	# PROTOCOLO EXORCISMO (v164.55: Borrar títulos y botones redundantes de todos los hijos)
	_aggressive_hide(self)
	
	# Conectar ventanas a la lógica de minimización
	for child in get_children():
		if child.has_method("toggle_minimize"):
			child.minimized.connect(_on_minimize_pressed)
			# v164.54: Lógica de inyección de botones Header/Min ELIMINADA.
			# Todo el control se centraliza en el ControlBar (Footer).
	
	_ammo_nodes["laser"] = get_node_or_null("Skills/LaserSlot/ammo-q")
	_ammo_nodes["missile"] = get_node_or_null("Skills/MissileSlot/ammo-w")
	_ammo_nodes["mine"] = get_node_or_null("Skills/MineSlot/ammo-e")
	
	if center_stats: 
		center_stats.visible = true
		# v164.93: REENCUADRE TOTAL (Centrado y Justificación Pro)
		var vbox = center_stats.get_node_or_null("VBox")
		if vbox:
			vbox.alignment = BoxContainer.ALIGNMENT_CENTER # Centrado Vertical Real
			vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
			vbox.add_theme_constant_override("separation", 10)
			
			# 1. Nivel
			var l_info = vbox.get_node_or_null("LevelInfo")
			if l_info: 
				vbox.move_child(l_info, 0)
				if l_info is BoxContainer: l_info.alignment = BoxContainer.ALIGNMENT_CENTER
				if lvl_label: lvl_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			
			# 2. Inyectar Speed en el centro
			if not speed_label:
				speed_label = Label.new()
				speed_label.name = "SpeedLabel"
				speed_label.add_theme_font_size_override("font_size", 10)
				speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				speed_label.modulate = Color.YELLOW
				vbox.add_child(speed_label)
				vbox.move_child(speed_label, 1)
			
			# 3. Currency al final y vertical
			var curr_box = vbox.get_node_or_null("Currency")
			if curr_box:
				var new_vbox = vbox.get_node_or_null("CurrencyVertical")
				if not new_vbox:
					new_vbox = VBoxContainer.new()
					new_vbox.name = "CurrencyVertical"
					new_vbox.add_theme_constant_override("separation", 2)
					vbox.add_child(new_vbox)
				
				vbox.move_child(new_vbox, 2)
				
				# Mover los labels al nuevo contenedor vertical
				if hubs_label: 
					if hubs_label.get_parent(): hubs_label.get_parent().remove_child(hubs_label)
					new_vbox.add_child(hubs_label)
					hubs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				if ohcu_label: 
					if ohcu_label.get_parent(): ohcu_label.get_parent().remove_child(ohcu_label)
					new_vbox.add_child(ohcu_label)
					ohcu_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				
				curr_box.visible = false # Ocultar el viejo HBox
	
	if skills_hud: skills_hud.visible = true
	if radar_window: radar_window.visible = true
	
	# Inicializar estado visual de los iconos
	for btn in $ControlBar.get_children():
		var id = btn.name.replace("Icon", "")
		var node = _get_hud_node(id)
		if node:
			_update_icon_state(id, node.visible)
	
	# Escuchar datos del servidor (v1.17 - Cloud HUD)
	NetworkManager.login_success.connect(_on_server_data_received)

func _process(_p_delta):
	var p_node = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(p_node) or p_node.get("is_dead") == true or p_node.get("entity_id") == "":
		visible = false; return
	else:
		visible = true
	
	# v166.50: SELECTOR DE MUNICION TACTICO (Muestra overlay al presionar CTRL)
	_handle_ammo_selector()
	
	queue_redraw()
	
	# Ya NO forzamos posiciones fijas en _process para permitir Arrastre
	if is_instance_valid(lvl_label):
		var lvl = p_node.get("level") if "level" in p_node else 1
		var p_exp = p_node.get("current_exp") if "current_exp" in p_node else 0
		var next_exp = p_node.get("next_level_exp") if "next_level_exp" in p_node else 1000
		var pct = (p_exp / next_exp) * 100 if next_exp > 0 else 0
		lvl_label.text = "LEVEL " + str(lvl) + " | EXP " + str(int(pct)) + "%"
		
	if is_instance_valid(hubs_label): 
		hubs_label.text = "HUBS: " + _format_val(p_node.get("hubs") if "hubs" in p_node else 0)
		hubs_label.modulate = Color.CYAN
		
	if is_instance_valid(ohcu_label): 
		ohcu_label.text = "OHCU: " + _format_val(p_node.get("ohculianos") if "ohculianos" in p_node else 0)
		ohcu_label.modulate = Color.MAGENTA

	if is_instance_valid(speed_label):
		var spd = p_node.get("speed") if "speed" in p_node else 300.0
		speed_label.text = "SPEED: " + str(int(spd)) + " KM/H"

	if fps_label: fps_label.text = "FPS: " + str(Engine.get_frames_per_second())
	if ms_label: ms_label.text = "MS: " + str(NetworkManager.current_ms)
	
	# v186.20: Conteo de Jugadores Robusto (Consensuado vía Grupos)
	if online_label:
		var remote_count = get_tree().get_nodes_in_group("remote_players").size()
		online_label.text = "ONLINE: " + str(remote_count + 1)
	
	_update_skill_ui("laser", p_node, get_node_or_null("Skills/LaserSlot"))
	_update_skill_ui("missile", p_node, get_node_or_null("Skills/MissileSlot"))
	_update_skill_ui("mine", p_node, get_node_or_null("Skills/MineSlot"))

func _draw():
	var p_node = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(p_node) or p_node.get("is_dead") == true: return
	
	# Si center_stats está activo, dibujamos en su posición
	if not is_instance_valid(center_stats) or not center_stats.visible: return
	
	# v164.92: Variables de dibujo f y r_pos eliminadas (ya no hay barras que dibujar aquí)
	# v164.90: Barras de HUD ELIMINADAS (Ya son visibles sobre el player para máxima limpieza)
	pass

func _format_val(v):
	var s = str(int(v))
	var r = ""
	var c = 0
	for i in range(s.length()-1,-1,-1):
		r = s[i] + r
		c += 1
		if c == 3 and i != 0:
			r = "." + r
			c = 0
	return r

func _update_skill_ui(type: String, ref, slot):
	if not slot or not is_instance_valid(slot): return
	var l_cd = slot.get_node_or_null("CD")
	var l_fill = slot.get_node_or_null("Fill")
	var l_am = _ammo_nodes.get(type)
	
	var cds = ref.get("cooldowns") if "cooldowns" in ref else {}
	var rv = cds.get(type, 0.0)
	
	# v165.11: Lógica de Cooldown Visual (Fill)
	if l_fill:
		var max_cd = 0.5 if type == "laser" else (2.0 if type == "missile" else 5.0)
		var pct = clamp(rv / max_cd, 0.0, 1.0)
		
		# Forzamos que el ColorRect cubra desde la base hasta el porcentaje de altura
		l_fill.anchor_top = 1.0 - pct
		l_fill.anchor_bottom = 1.0 
		l_fill.offset_top = 0 # Eliminar cualquier margen residual de Godot
		l_fill.offset_bottom = 0
	
	# Timer de Texto
	if l_cd:
		if rv > 0.05: 
			l_cd.visible = true
			l_cd.text = str(snapped(rv, 0.1)) + "s"
			l_cd.modulate = Color.RED
		else: 
			l_cd.visible = false
			
	# Actualización de Munición
	if l_am and "ammo" in ref:
		var ammo_dict = ref.get("ammo")
		var sel_dict = ref.get("selected_ammo") if "selected_ammo" in ref else {}
		var t_idx = sel_dict.get(type, 0)
		var a_list = ammo_dict.get(type, [0, 0, 0, 0, 0, 0])
		var a_count = a_list[t_idx] if a_list.size() > t_idx else 0
		l_am.text = "T" + str(t_idx + 1) + ": " + _format_val(a_count)
		
		# Feedback de color según tier
		var colors = [Color.WHITE, Color.YELLOW, Color.GREEN, Color.CYAN, Color.MAGENTA, Color.GOLD]
		l_am.modulate = colors[t_idx] if t_idx < colors.size() else Color.WHITE

# Señales de minimización
func _on_minimize_pressed(id: String):
	var node = _get_hud_node(id)
	if node:
		node.visible = false
		_update_icon_state(id, false)

func _on_icon_pressed(id: String):
	var node = _get_hud_node(id)
	if node:
		node.visible = !node.visible
		_update_icon_state(id, node.visible)

func _get_hud_node(id: String):
	# Mapeo de IDs
	var real_id = id
	if id == "Chat": real_id = "ChatUI"
	if id == "Stats": real_id = "CenterStats"
	if id == "Squad" or id == "Party": real_id = "PartyHUD"
	
	var node = get_node_or_null(real_id)
	if not node:
		node = get_parent().get_node_or_null(real_id)
	return node

func _update_icon_state(id: String, is_active: bool):
	var icon = get_node_or_null("ControlBar/Icon" + id)
	if icon:
		if is_active:
			icon.modulate = Color.WHITE
		else:
			icon.modulate = Color(0.4, 0.4, 0.4, 0.6) # Oscurecer si está minimizado

func _on_server_data_received(p_data: Dictionary):
	if p_data.has("gameData"):
		var gd = p_data.gameData
		if gd.has("hud_layout"):
			var layout = gd.hud_layout
			for win_id in layout:
				var pos_data = layout[win_id]
				var node = _get_hud_node(win_id)
				if node:
					node.global_position = Vector2(pos_data.x, pos_data.y)
					print("[HUD] Cargado desde Servidor para: ", win_id)

# v164.55: SISTEMA DE LIMPIEZA AGRESIVA (HUD Minimalista)
func _aggressive_hide(node):
	for child in node.get_children():
		# 1. Borrar Botones de Minimizar (Cualquier botón pequeño con "-")
		if child is Button:
			if child.text == "-" or child.name == "MinBtn" or child.name == "Min":
				child.visible = false
				child.queue_free()
		
		# 2. Borrar Títulos Estáticos (Cualquier Label con nombres de sistemas)
		if child is Label:
			var t = child.text.to_upper()
			if "SISTEMA" in t or "RECON" in t or "INTEGRADO" in t or "TACTICA" in t:
				child.text = ""
				child.visible = false
				child.queue_free()
		
# --- SISTEMA DE SELECCIÓN DE MUNICIÓN (CTRL) --- v166.50
var _ammo_menu: Control = null

func _handle_ammo_selector():
	var is_ctrl = Input.is_key_pressed(KEY_CTRL)
	if is_ctrl:
		if not _ammo_menu or not _ammo_menu.visible:
			_toggle_ammo_menu(true)
	else:
		if _ammo_menu and _ammo_menu.visible:
			_toggle_ammo_menu(false)

func _toggle_ammo_menu(p_show: bool):
	if p_show and not _ammo_menu:
		_create_ammo_menu()
	
	if _ammo_menu:
		_ammo_menu.visible = p_show
		if p_show: 
			_ammo_menu.global_position = Vector2((get_viewport_rect().size.x - _ammo_menu.size.x)/2, get_viewport_rect().size.y - 180)

func _create_ammo_menu():
	_ammo_menu = HBoxContainer.new()
	_ammo_menu.name = "AmmoMenuOverlay"
	_ammo_menu.add_theme_constant_override("separation", 20)
	add_child(_ammo_menu)
	
	var types = ["laser", "missile", "mine"]
	var colors = [Color.WHITE, Color.YELLOW, Color.GREEN, Color.CYAN] # T1 a T4
	
	for t in types:
		var col = VBoxContainer.new()
		_ammo_menu.add_child(col)
		
		var title = Label.new()
		title.text = t.to_upper()
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 9)
		title.modulate = Color.CYAN
		col.add_child(title)
		
		var grid = GridContainer.new()
		grid.columns = 2
		col.add_child(grid)
		
		for i in range(4): # 4 Tiers por categoría
			var slot = PanelContainer.new()
			slot.custom_minimum_size = Vector2(35, 35)
			var sb = StyleBoxFlat.new()
			sb.bg_color = Color(0,0,0,0.6)
			sb.border_width_left = 1; sb.border_width_top = 1
			sb.border_width_right = 1; sb.border_width_bottom = 1
			sb.border_color = colors[i] if i < colors.size() else Color.WHITE
			slot.add_theme_stylebox_override("panel", sb)
			
			var lbl = Label.new()
			lbl.text = "x" + str(i+1)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.add_theme_font_size_override("font_size", 10)
			slot.add_child(lbl)
			
			slot.gui_input.connect(_on_ammo_slot_clicked.bind(t, i))
			grid.add_child(slot)
	
	_ammo_menu.size = _ammo_menu.get_combined_minimum_size()

func _on_ammo_slot_clicked(event: InputEvent, type: String, tier: int):
	if event is InputEventMouseButton and event.pressed:
		var p = get_tree().get_first_node_in_group("player")
		if p and p.has_method("change_ammo"):
			p.change_ammo(type, tier)
			# Feedback visual rápido
			var tw = create_tween()
			tw.tween_property(_ammo_menu, "modulate", Color.GREEN, 0.1)
			tw.tween_property(_ammo_menu, "modulate", Color.WHITE, 0.1)

extends Control

# MainHUD.gd (Omni-HUD v190.40 - Clean & Responsive)

@onready var hubs_label = $CenterStats/VBox/Currency/HUBS
@onready var ohcu_label = $CenterStats/VBox/Currency/OHCU
@onready var lvl_label = $CenterStats/VBox/LevelInfo/LVL
@onready var speed_label = null 

@onready var fps_label = $TopLeft/FPS
@onready var ms_label = $TopLeft/MS
@onready var online_label = $TopLeft/ONLINE

@onready var center_stats = $CenterStats
@onready var radar_window = $RadarWindow
@onready var skills_hud = $Skills

var _ammo_nodes = {}
var _ammo_menu: Control = null

func _ready():
	mouse_filter = Control.MOUSE_FILTER_PASS
	print("[HUD] Sistema v190.40 inicializado.")
	
	# v167.30: Inyectar Icono de Escuadrón
	var c_bar = get_node_or_null("ControlBar")
	if c_bar and not c_bar.has_node("IconSquad"):
		var btn = Button.new()
		btn.name = "IconSquad"
		btn.text = "👥"
		btn.flat = true
		btn.custom_minimum_size = Vector2(30,30)
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0,0,0,0)
		sb.border_width_bottom = 1
		sb.border_color = Color.CYAN
		btn.add_theme_stylebox_override("normal", sb)
		c_bar.add_child(btn)
		c_bar.move_child(btn, 0)
	
	for btn in $ControlBar.get_children():
		var b_name = btn.name.replace("Icon", "")
		if not btn.pressed.is_connected(_on_icon_pressed):
			btn.pressed.connect(_on_icon_pressed.bind(b_name))
	
	_aggressive_hide(self)
	
	for child in get_children():
		if child.has_method("toggle_minimize"):
			if not child.minimized.is_connected(_on_minimize_pressed):
				child.minimized.connect(_on_minimize_pressed)
	
	_ammo_nodes["laser"] = get_node_or_null("Skills/LaserSlot/ammo-q")
	_ammo_nodes["missile"] = get_node_or_null("Skills/MissileSlot/ammo-w")
	_ammo_nodes["mine"] = get_node_or_null("Skills/MineSlot/ammo-e")
	
	if center_stats: 
		center_stats.visible = true
		var vbox = center_stats.get_node_or_null("VBox")
		if vbox:
			vbox.alignment = BoxContainer.ALIGNMENT_CENTER
			vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
			vbox.add_theme_constant_override("separation", 10)
			
			if not speed_label:
				speed_label = Label.new()
				speed_label.name = "SpeedLabel"
				speed_label.add_theme_font_size_override("font_size", 10)
				speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				speed_label.modulate = Color.YELLOW
				vbox.add_child(speed_label)
	
	if NetworkManager:
		if not NetworkManager.login_success.is_connected(_on_server_data_received):
			NetworkManager.login_success.connect(_on_server_data_received)

func _on_server_data_received(p_data: Dictionary):
	if p_data.has("gameData"):
		var gd = p_data.gameData
		var layout = gd.get("hudPositions", gd.get("hud_layout", {}))
		var config = gd.get("hudConfig", gd.get("hud_config", {}))
		_apply_hud_data(layout, config)

func _apply_hud_data(layout: Dictionary, config: Dictionary):
	var screen_size = get_viewport_rect().size
	for win_id in layout:
		var pos_data = layout[win_id]
		var node = _get_hud_node(win_id)
		if node and typeof(pos_data) == TYPE_DICTIONARY:
			var rx = float(pos_data.get("x", 0.0))
			var ry = float(pos_data.get("y", 0.0))
			if rx <= 2.0 and ry <= 2.0:
				node.global_position = Vector2(rx * screen_size.x, ry * screen_size.y)
			else:
				node.global_position = Vector2(rx, ry)
	
	for win_id in config:
		var node = _get_hud_node(win_id)
		if node: node.visible = bool(config[win_id])

func _process(_delta):
	var p_node = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(p_node) or p_node.get("is_dead") or p_node.get("entity_id") == "":
		visible = false
		return
	else:
		visible = true
	
	_handle_ammo_selector()
	
	if is_instance_valid(lvl_label):
		var p_exp = p_node.get("current_exp")
		if p_exp == null: p_exp = 0.0
		var lvl = p_node.get("level")
		if lvl == null: lvl = 1
		
		# v193.15: Meta Exponencial Sincronizada (Lvl^1.5 * 1000)
		var next_exp = floor(1000.0 * pow(lvl, 1.5))
		var pct = clamp((p_exp / next_exp) * 100, 0, 100)
		lvl_label.text = "LEVEL " + str(lvl) + " | EXP " + str(int(pct)) + "%"
		
	if is_instance_valid(hubs_label): 
		var val = p_node.get("hubs")
		hubs_label.text = "HUBS: " + _format_val(val if val != null else 0)
		
	if is_instance_valid(ohcu_label): 
		var val = p_node.get("ohculianos")
		ohcu_label.text = "OHCU: " + _format_val(val if val != null else 0)

	if is_instance_valid(speed_label):
		var val = p_node.get("speed")
		speed_label.text = "SPEED: " + str(int(val if val != null else 0.0)) + " KM/H"

	if fps_label: fps_label.text = "FPS: " + str(Engine.get_frames_per_second())
	if ms_label: ms_label.text = "MS: " + str(NetworkManager.current_ms)
	if is_instance_valid(online_label):
		var remote_count = get_tree().get_nodes_in_group("remote_players").size()
		online_label.text = "ONLINE: " + str(remote_count + 1)
	
	_update_skill_ui("laser", p_node, get_node_or_null("Skills/LaserSlot"))
	_update_skill_ui("missile", p_node, get_node_or_null("Skills/MissileSlot"))
	_update_skill_ui("mine", p_node, get_node_or_null("Skills/MineSlot"))
	
	_update_sphere_ui(0, p_node, get_node_or_null("Skills/Sphere1Slot"))
	_update_sphere_ui(1, p_node, get_node_or_null("Skills/Sphere2Slot"))
	_update_sphere_ui(2, p_node, get_node_or_null("Skills/Sphere3Slot"))

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
	if not slot: return
	var l_fill = slot.get_node_or_null("Fill")
	var l_cd = slot.get_node_or_null("CD")
	var l_am = _ammo_nodes.get(type)
	
	var cds = ref.get("cooldowns")
	if cds == null: cds = {}
	var rv = cds.get(type, 0.0) # Esto es un DICCIONARIO, aquí sí van 2 argumentos.
	
	if l_fill:
		var max_cd = 0.5 if type == "laser" else (2.0 if type == "missile" else 5.0)
		var pct = clamp(rv / max_cd, 0.0, 1.0)
		l_fill.anchor_top = 1.0 - pct
		l_fill.anchor_bottom = 1.0 
		l_fill.offset_top = 0
		l_fill.offset_bottom = 0
	
	if l_cd:
		l_cd.visible = rv > 0.05
		l_cd.text = str(snapped(rv, 0.1)) + "s"
			
	if l_am and ref.get("ammo") != null:
		var a_list = ref.get("ammo").get(type, [0,0,0,0,0,0])
		var sel_data = ref.get("selected_ammo")
		var sel = sel_data.get(type, 0) if sel_data != null else 0
		var a_count = a_list[sel] if a_list.size() > sel else 0
		l_am.text = "T" + str(sel + 1) + ": " + _format_val(a_count)
		l_am.modulate = Color(0, 1, 0.2) # VERDE NEÓN ORIGINAL
		l_am.position = Vector2(40, 48) # ESQUINA INFERIOR DERECHA (Dentro del círculo pero visible)
		l_am.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l_am.visible = true

func _update_sphere_ui(id: int, ref, slot):
	if not slot: return
	var l_fill = slot.get_node_or_null("Fill")
	
	var key = "sphere_" + str(id)
	var cds = ref.get("cooldowns")
	if cds == null: cds = {}
	var rv = cds.get(key, 0.0)
	
	if l_fill:
		# Cooldown base de 10s para visualización
		var pct = clamp(rv / 10.0, 0.0, 1.0)
		l_fill.anchor_top = 1.0 - pct
		l_fill.anchor_bottom = 1.0
		l_fill.offset_top = 0
		l_fill.offset_bottom = 0
	
	# Cambiar transparencia si está en CD o si no tiene nada equipado
	var sm = ref.get_node_or_null("SpheresManager")
	var equipped = false
	if is_instance_valid(sm) and sm.spheres_data.size() > id:
		equipped = sm.spheres_data[id]["equipped"] != null
	
	slot.modulate.a = 1.0 if equipped else 0.2
	if rv > 0.05:
		slot.modulate = Color(1, 0.2, 0.2) # Rojo si está en CD
	else:
		slot.modulate = Color.WHITE

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
	var real_id = id
	if id == "Chat": real_id = "ChatUI"
	if id == "Stats": real_id = "CenterStats"
	if id == "Squad" or id == "Party": real_id = "PartyHUD"
	var node = get_node_or_null(real_id)
	if not node: node = get_parent().get_node_or_null(real_id)
	return node

func _update_icon_state(id: String, is_active: bool):
	var icon = get_node_or_null("ControlBar/Icon" + id)
	if icon: icon.modulate = Color.WHITE if is_active else Color(0.4, 0.4, 0.4, 0.6)

func _aggressive_hide(node):
	for child in node.get_children():
		if child is Button:
			if child.text == "-" or child.name == "MinBtn":
				child.visible = false; child.queue_free()
		if child is Label:
			var t = child.text.to_upper()
			if "SISTEMA" in t or "RECON" in t:
				child.text = ""; child.visible = false; child.queue_free()

func _handle_ammo_selector():
	var is_ctrl = Input.is_key_pressed(KEY_CTRL)
	if is_ctrl:
		if not _ammo_menu or not _ammo_menu.visible: _toggle_ammo_menu(true)
	elif _ammo_menu and _ammo_menu.visible:
		_toggle_ammo_menu(false)

func _toggle_ammo_menu(p_show: bool):
	if p_show and not _ammo_menu: _create_ammo_menu()
	if _ammo_menu:
		_ammo_menu.visible = p_show
		if p_show: _ammo_menu.global_position = Vector2((get_viewport_rect().size.x - _ammo_menu.size.x)/2, get_viewport_rect().size.y - 180)

func _create_ammo_menu():
	_ammo_menu = HBoxContainer.new()
	add_child(_ammo_menu)
	var types = ["laser", "missile", "mine"]
	for t in types:
		var col = VBoxContainer.new(); _ammo_menu.add_child(col)
		var grid = GridContainer.new(); grid.columns = 2; col.add_child(grid)
		for i in range(4):
			var slot = PanelContainer.new(); slot.custom_minimum_size = Vector2(35, 35)
			slot.gui_input.connect(_on_ammo_slot_clicked.bind(t, i))
			grid.add_child(slot)
	_ammo_menu.size = _ammo_menu.get_combined_minimum_size()

func _on_ammo_slot_clicked(event: InputEvent, type: String, tier: int):
	if event is InputEventMouseButton and event.pressed:
		var p = get_tree().get_first_node_in_group("player")
		if p and p.has_method("change_ammo"): p.change_ammo(type, tier)

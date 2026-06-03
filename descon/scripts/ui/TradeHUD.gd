extends CanvasLayer

## v300.360: CONTROLADOR ESTABLE CON ASSETS (REVERSIÓN A COLORRECT)
## Basado en la versión que funcionó, agregando iconos de forma segura.

signal trade_cancelled
signal trade_finished

var partner_name_label: Label
var my_offer_grid: GridContainer
var partner_offer_grid: GridContainer
var my_inventory_grid: GridContainer
var my_equipped_grid: GridContainer
var status_label: Label
var confirm_button: Button

# Tooltip Premium
var info_panel: PanelContainer = null
var lbl_info_title: Label = null
var lbl_info_type: Label = null
var lbl_info_stats: Label = null

var trade_id = ""
var partner_id = ""
var my_offered_items = []
var partner_offered_items = []
var is_ready = false
var partner_ready = false
var my_cached_inventory = []
var my_cached_equipped = []

func _find_nodes():
	var cols = get_node_or_null("MainFrame/ContentLayout/Columns")
	if not cols: return
	partner_name_label = get_node_or_null("MainFrame/ContentLayout/Header/PartnerName")
	my_offer_grid = cols.get_node_or_null("MySide/ScrollContainer/OfferGrid")
	partner_offer_grid = cols.get_node_or_null("PartnerSide/ScrollContainer/OfferGrid")
	my_inventory_grid = cols.get_node_or_null("InventorySide/ScrollContainer/InventoryGrid")
	my_equipped_grid = cols.get_node_or_null("EquippedSide/ScrollContainer/EquippedGrid")
	status_label = get_node_or_null("MainFrame/ContentLayout/Footer/StatusLabel")
	confirm_button = get_node_or_null("MainFrame/ContentLayout/Footer/ConfirmButton")

func _ready():
	_find_nodes()
	$MainFrame.mouse_filter = Control.MOUSE_FILTER_STOP
	if NetworkManager:
		NetworkManager.inventory_data.connect(_on_inventory_data_received)
		NetworkManager.trade_partner_update.connect(_on_partner_update)
		NetworkManager.trade_partner_ready.connect(_on_partner_ready_sync)
		NetworkManager.trade_success.connect(_on_trade_success)
		NetworkManager.trade_cancelled.connect(_on_trade_cancelled)
	if confirm_button: confirm_button.pressed.connect(_on_confirm_pressed)
	var close_btn = get_node_or_null("MainFrame/ContentLayout/Header/CloseButton")
	if close_btn: close_btn.pressed.connect(_on_close_pressed)
	
	# Crear el Panel de Información Flotante (Tooltip Premium)
	info_panel = PanelContainer.new()
	info_panel.visible = false
	info_panel.custom_minimum_size = Vector2(180, 80)
	info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(info_panel)
	
	var info_margin = MarginContainer.new()
	info_margin.add_theme_constant_override("margin_left", 10)
	info_margin.add_theme_constant_override("margin_right", 10)
	info_margin.add_theme_constant_override("margin_top", 8)
	info_margin.add_theme_constant_override("margin_bottom", 8)
	info_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_panel.add_child(info_margin)
	
	var info_vbox = VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 4)
	info_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_margin.add_child(info_vbox)
	
	lbl_info_title = Label.new()
	lbl_info_title.add_theme_font_size_override("font_size", 11)
	lbl_info_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_info_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(lbl_info_title)
	
	lbl_info_type = Label.new()
	lbl_info_type.add_theme_font_size_override("font_size", 8)
	lbl_info_type.modulate = Color(0.7, 0.7, 0.7)
	lbl_info_type.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(lbl_info_type)
	
	var info_sep = HSeparator.new()
	info_sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(info_sep)
	
	lbl_info_stats = Label.new()
	lbl_info_stats.add_theme_font_size_override("font_size", 9)
	lbl_info_stats.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	lbl_info_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_info_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(lbl_info_stats)
	
	await get_tree().process_frame
	refresh_ui()

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_hide_info_panel()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_close_pressed()
		get_viewport().set_input_as_handled()

func setup(data):
	_find_nodes()
	trade_id = data.tradeId
	partner_id = data.partnerId
	if partner_name_label: partner_name_label.text = "COMERCIANDO CON: " + data.partnerName.to_upper()
	if NetworkManager: NetworkManager.send_event("getInventory", {})
	show()
	refresh_ui()

func _on_inventory_data_received(p_data: Dictionary):
	my_cached_inventory.clear()
	var inv = p_data.get("inventory", [])
	if inv is Array: my_cached_inventory = inv
	
	my_cached_equipped.clear()
	var current_ship = str(p_data.get("currentShipId", "1"))
	if p_data.has("equippedByShip"):
		var all_eq = p_data.equippedByShip
		if all_eq is Dictionary:
			var ship_data = all_eq.get(current_ship, all_eq.get(int(current_ship)))
			if ship_data is Dictionary:
				for cat in ship_data:
					if ship_data[cat] is Array: my_cached_equipped.append_array(ship_data[cat])
	
	if my_cached_equipped.is_empty() and p_data.has("equipped"):
		var eq = p_data.equipped
		if eq is Array: my_cached_equipped = eq
		elif eq is Dictionary:
			for cat in eq:
				if eq[cat] is Array: my_cached_equipped.append_array(eq[cat])
	refresh_ui()

func refresh_ui():
	if not my_inventory_grid or not my_equipped_grid: return
	
	# Forzar tamaño mínimo de grillas para que no colapsen
	my_inventory_grid.custom_minimum_size.y = 200
	my_equipped_grid.custom_minimum_size.y = 200

	for g in [my_offer_grid, partner_offer_grid, my_inventory_grid, my_equipped_grid]:
		if is_instance_valid(g): 
			for child in g.get_children(): 
				child.name += "_del"
				child.queue_free()
	
	for item in my_cached_inventory:
		if item == null: continue
		var inst_id = item.get("instanceId", "") if item is Dictionary else ""
		if inst_id != "" and inst_id in my_offered_items: continue
		my_inventory_grid.add_child(create_item_slot(item, "inventory"))

	for item in my_cached_equipped:
		if item == null: continue
		var inst_id = item.get("instanceId", "") if item is Dictionary else ""
		if inst_id != "" and inst_id in my_offered_items: continue
		my_equipped_grid.add_child(create_item_slot(item, "equipped"))

	var all_mine = my_cached_inventory + my_cached_equipped
	for inst_id in my_offered_items:
		var it = all_mine.filter(func(i): return i.get("instanceId", "") == inst_id)
		if it.size() > 0: my_offer_grid.add_child(create_item_slot(it[0], "offer"))

	for item in partner_offered_items:
		partner_offer_grid.add_child(create_item_slot(item, "partner"))
	
	_update_status_label()

func create_item_slot(item_data, context = "inventory"):
	var item_id = "ITEM"
	var icon_path = ""
	var rarity = 0
	var item_color = ""
	if item_data is Dictionary:
		item_id = str(item_data.get("itemId", item_data.get("id", "ITEM")))
		icon_path = str(item_data.get("icon", ""))
		rarity = int(item_data.get("rarity", 0))
		item_color = str(item_data.get("color", ""))
	elif item_data is String:
		item_id = item_data
	
	var slot_panel = PanelContainer.new()
	slot_panel.custom_minimum_size = Vector2(80, 80)
	
	# Estilo vacío
	var sb_empty = StyleBoxFlat.new()
	sb_empty.bg_color = Color(1.0, 1.0, 1.0, 0.02)
	sb_empty.border_width_left = 1
	sb_empty.border_width_top = 1
	sb_empty.border_width_right = 1
	sb_empty.border_width_bottom = 1
	sb_empty.border_color = Color(1.0, 1.0, 1.0, 0.05)
	sb_empty.set_corner_radius_all(4)
	
	var rarity_color = _get_rarity_color(rarity)
	if item_color != "":
		rarity_color = Color.from_string(item_color, rarity_color)
		
	var sb_filled = sb_empty.duplicate()
	sb_filled.bg_color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.08)
	sb_filled.border_color = rarity_color
	sb_filled.border_width_left = 2
	sb_filled.border_width_top = 2
	sb_filled.border_width_right = 2
	sb_filled.border_width_bottom = 2
	slot_panel.add_theme_stylebox_override("panel", sb_filled)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_panel.add_child(margin)
	
	# Carga de Iconos (Búsqueda de emergencia)
	var search_id = item_id.to_lower()
	if icon_path == "" or icon_path == "null" or not ResourceLoader.exists(icon_path):
		var emergency_map = {
			"las1": "res://assets/Armas/Arma1/Arma1.png", "las2": "res://assets/Armas/Arma2/Arma2.png", "las3": "res://assets/Armas/Arma3/Arma3.png",
			"las4": "res://assets/Armas/Arma4/Arma4.png", "las5": "res://assets/Armas/Arma5/Arma5.png", "las6": "res://assets/Armas/Arma6/Arma6.png",
			"sh1": "res://assets/Escudos/Escudo1/Escudo1.png", "sh2": "res://assets/Escudos/Escudo2/Escudo2.png", "sh3": "res://assets/Escudos/Escudo3/Escudo3.png",
			"sh4": "res://assets/Escudos/Escudo4/Escudo4.png", "sh5": "res://assets/Escudos/Escudo5/Escudo5.png", "sh6": "res://assets/Escudos/Escudo6/Escudo6.png",
			"en1": "res://assets/Motores/Motor1/Motor1.png", "en2": "res://assets/Motores/Motor2/Motor2.png", "en3": "res://assets/Motores/Motor3/Motor3.png"
		}
		if emergency_map.has(search_id): icon_path = emergency_map[search_id]
	
	var has_icon = false
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var tex_res = load(icon_path)
		if tex_res:
			var tex = TextureRect.new()
			tex.texture = tex_res
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			margin.add_child(tex)
			has_icon = true
			
	if not has_icon:
		var lbl = Label.new()
		lbl.text = item_id.to_upper()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color", Color.YELLOW)
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_child(lbl)
		
	# Eventos de ratón
	if item_data is Dictionary:
		slot_panel.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed:
				if event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
					_hide_info_panel()
					match context:
						"inventory", "equipped": add_to_offer(item_data)
						"offer": remove_from_offer(item_data)
					get_viewport().set_input_as_handled()
				elif event.button_index == MOUSE_BUTTON_LEFT:
					_show_info_panel(item_data, slot_panel)
					get_viewport().set_input_as_handled()
		)
		
	return slot_panel

func add_to_offer(item):
	if is_ready: return
	var iid = item.get("instanceId", "")
	if iid != "" and not iid in my_offered_items:
		my_offered_items.append(iid); update_trade_on_server(); refresh_ui()

func remove_from_offer(item):
	if is_ready: return
	var iid = item.get("instanceId", "")
	if iid != "":
		my_offered_items.erase(iid); update_trade_on_server(); refresh_ui()

func update_trade_on_server():
	is_ready = false; _update_confirm_button_ui(); NetworkManager.send_event("tradeUpdateItems", my_offered_items)

func _on_partner_update(data):
	partner_offered_items = data.items; partner_ready = data.get("partnerReady", false); is_ready = false; refresh_ui(); _update_confirm_button_ui()

func _on_partner_ready_sync(ready_state):
	partner_ready = ready_state; _update_status_label()

func _on_confirm_pressed():
	is_ready = !is_ready; NetworkManager.send_event("tradeConfirm", is_ready); _update_confirm_button_ui()

func _update_confirm_button_ui():
	if not confirm_button: return
	confirm_button.text = "¡LISTO!" if is_ready else "CONFIRMAR OFERTA"
	confirm_button.modulate = Color.GREEN if is_ready else Color.CYAN
	_update_status_label()

func _update_status_label():
	if not status_label: return
	if is_ready and partner_ready: status_label.text = "PROCESANDO INTERCAMBIO..."
	elif is_ready: status_label.text = "ESPERANDO AL OTRO PILOTO..."
	elif partner_ready: status_label.text = "EL SOCIO ESTÁ LISTO"
	else: status_label.text = "NEGOCIANDO OFERTA..."

func _on_trade_success(data):
	if status_label: status_label.text = "¡INTERCAMBIO EXITOSO!"; await get_tree().create_timer(1.5).timeout; queue_free()

func _on_trade_cancelled(_data): queue_free()

func _on_close_pressed():
	NetworkManager.send_event("tradeCancel", {})
	queue_free()

func _show_info_panel(item_data, target_node: Control):
	if not info_panel: return
	if item_data == null:
		print("[TRADE WARNING] item_data es nulo en _show_info_panel")
		return
	if not (item_data is Dictionary):
		print("[TRADE WARNING] item_data no es un Dictionary en _show_info_panel: ", typeof(item_data))
		return
	
	var rarity = 0
	if item_data.has("rarity") and item_data["rarity"] != null:
		rarity = int(item_data["rarity"])
		
	var rarity_color = _get_rarity_color(rarity)
	if item_data.has("color") and item_data["color"] != null and str(item_data["color"]) != "":
		rarity_color = Color.from_string(str(item_data["color"]), rarity_color)
		
	# Estilo del tooltip con borde del color de rareza
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.02, 0.05, 0.96)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = rarity_color
	sb.set_corner_radius_all(6)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 8
	info_panel.add_theme_stylebox_override("panel", sb)
	
	# Llenar datos
	var name_str = "ÍTEM"
	if item_data.has("name") and item_data["name"] != null:
		name_str = str(item_data["name"])
	lbl_info_title.text = name_str.to_upper()
	lbl_info_title.add_theme_color_override("font_color", rarity_color)
	
	var type_str = "MÓDULO"
	if item_data.has("type") and item_data["type"] != null:
		type_str = str(item_data["type"])
	lbl_info_type.text = _get_rarity_label(rarity) + " | " + type_str.to_upper()
	
	# Estadísticas
	var base_val = 0
	if item_data.has("base") and item_data["base"] != null:
		base_val = int(item_data["base"])
		
	var type_str_lower = type_str.to_lower()
	var stat_text = ""
	
	var search_id = ""
	if item_data.has("id") and item_data["id"] != null:
		search_id = str(item_data["id"]).to_lower()
	elif item_data.has("itemId") and item_data["itemId"] != null:
		search_id = str(item_data["itemId"]).to_lower()
	
	if type_str_lower == "laser" or type_str_lower == "weapon" or search_id.begins_with("las"):
		stat_text = "DAÑO: +" + str(base_val)
	elif type_str_lower == "shield" or search_id.begins_with("sh"):
		stat_text = "ESCUDO: +" + str(base_val)
	elif type_str_lower == "engine" or search_id.begins_with("en"):
		stat_text = "PROPULSIÓN: +" + str(base_val)
	else:
		stat_text = "ESTADÍSTICA BASE: +" + str(base_val)
		
	lbl_info_stats.text = stat_text
	
	# Posicionar al lado del nodo de forma inteligente
	info_panel.visible = true
	# Forzar el cálculo del tamaño del panel para que posicione bien
	info_panel.reset_size()
	
	var target_pos = target_node.global_position
	# Posicionar a la derecha del slot
	var new_pos = target_pos + Vector2(target_node.size.x + 10, -10)
	
	# Si se sale por la derecha de la ventana
	if new_pos.x + info_panel.size.x > get_viewport().get_visible_rect().size.x:
		# Posicionar a la izquierda del slot
		new_pos.x = target_pos.x - info_panel.size.x - 10
		
	info_panel.global_position = new_pos

func _hide_info_panel():
	if info_panel:
		info_panel.visible = false

func _get_rarity_color(rarity: int) -> Color:
	match rarity:
		0: return Color(0.7, 0.7, 0.7) # Común
		1: return Color(0.13, 0.77, 0.36) # Raro
		2: return Color(0.23, 0.51, 0.96) # Épico
		3: return Color(0.66, 0.33, 0.97) # Reliquia
		4: return Color(0.98, 0.45, 0.09) # Legendario
		_: return Color.WHITE

func _get_rarity_label(rarity: int) -> String:
	match rarity:
		0: return "COMÚN"
		1: return "RARO"
		2: return "ÉPICO"
		3: return "RELIQUIA"
		4: return "LEGENDARIO"
		_: return "MÓDULO"

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
	await get_tree().process_frame
	refresh_ui()

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
	if item_data is Dictionary:
		item_id = str(item_data.get("itemId", item_data.get("id", "ITEM")))
		icon_path = str(item_data.get("icon", ""))
	elif item_data is String:
		item_id = item_data
	
	# REGRESO AL COLORRECT (Lo que andaba)
	var p = ColorRect.new()
	p.custom_minimum_size = Vector2(60, 60)
	match context:
		"equipped": p.color = Color(0.8, 0.4, 0.1, 0.9) # Naranja
		"inventory": p.color = Color(0, 0.5, 0, 0.7) # Verde
		"offer": p.color = Color(0, 0.6, 0.6, 0.9) # Cian
		_: p.color = Color(0.2, 0.2, 0.2, 1.0) # Gris
	
	# Nombre fallback
	var lbl = Label.new()
	lbl.text = item_id.to_upper()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color.YELLOW)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(lbl)
	
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
	
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var tex_res = load(icon_path)
		if tex_res:
			lbl.visible = false
			var tex = TextureRect.new()
			tex.texture = tex_res
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			p.add_child(tex)
	
	var btn = Button.new()
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.flat = true
	p.add_child(btn)
	
	if item_data is Dictionary:
		match context:
			"inventory": btn.pressed.connect(func(): add_to_offer(item_data))
			"equipped": btn.pressed.connect(func(): add_to_offer(item_data))
			"offer": btn.pressed.connect(func(): remove_from_offer(item_data))
	
	return p

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

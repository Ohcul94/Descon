extends CanvasLayer

# VaultUI.gd (v1.0 - Interfaz AAA de Almacenamiento Personal)
# Interfaz de doble panel de alta gama para almacenar y retirar ítems en el lobby.

var is_open: bool = false
var vault_items: Array = []
var unlocked_tabs: int = 1
var current_tab: int = 0
var vault_config: Dictionary = {}
var player_inventory: Array = []
var player_hubs: int = 0

# Referencias a nodos UI
var control_root: Control = null
var overlay: ColorRect = null
var tab_bar: TabBar = null
var vault_grid: GridContainer = null
var inv_container: VBoxContainer = null
var btn_unlock: Button = null
var lbl_hubs: Label = null
var lbl_slots_info: Label = null

func _ready():
	add_to_group("vault_ui")
	layer = 101 # Dibujar arriba del HUD común
	
	# 1. Overlay oscuro de fondo
	overlay = ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	
	# 2. Contenedor raíz centrado
	control_root = Control.new()
	control_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(control_root)
	
	# Ocultar inicialmente
	overlay.visible = false
	overlay.modulate.a = 0.0
	control_root.visible = false
	
	# 3. Diseñar panel de doble panel (HBoxContainer)
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 25)
	hbox.custom_minimum_size = Vector2(850, 480)
	hbox.position = Vector2(-425, -240) # Centrar en pantalla
	control_root.add_child(hbox)
	
	# A) PANEL IZQUIERDO: EL BAÚL DE SEGURIDAD
	var panel_vault = PanelContainer.new()
	panel_vault.custom_minimum_size = Vector2(460, 480)
	
	var sb_vault = StyleBoxFlat.new()
	sb_vault.bg_color = Color(0.02, 0.02, 0.05, 0.98)
	sb_vault.border_width_top = 3
	sb_vault.border_width_bottom = 2
	sb_vault.border_width_left = 2
	sb_vault.border_width_right = 2
	sb_vault.border_color = Color(1.0, 0.75, 0.0, 0.8) # Borde dorado neón
	sb_vault.corner_radius_top_left = 8
	sb_vault.corner_radius_top_right = 8
	sb_vault.corner_radius_bottom_left = 8
	sb_vault.corner_radius_bottom_right = 8
	sb_vault.shadow_color = Color(0, 0, 0, 0.6)
	sb_vault.shadow_size = 25
	panel_vault.add_theme_stylebox_override("panel", sb_vault)
	hbox.add_child(panel_vault)
	
	var margin_vault = MarginContainer.new()
	margin_vault.add_theme_constant_override("margin_top", 12)
	margin_vault.add_theme_constant_override("margin_bottom", 12)
	margin_vault.add_theme_constant_override("margin_left", 15)
	margin_vault.add_theme_constant_override("margin_right", 15)
	panel_vault.add_child(margin_vault)
	
	var vbox_vault = VBoxContainer.new()
	vbox_vault.add_theme_constant_override("separation", 10)
	margin_vault.add_child(vbox_vault)
	
	# Título Baúl
	var lbl_vault_title = Label.new()
	lbl_vault_title.text = "BAÚL DE SEGURIDAD PERSONAL"
	lbl_vault_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_vault_title.add_theme_font_size_override("font_size", 14)
	lbl_vault_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0)) # Dorado
	vbox_vault.add_child(lbl_vault_title)
	
	# TabBar para pestañas
	tab_bar = TabBar.new()
	tab_bar.custom_minimum_size = Vector2(0, 30)
	tab_bar.tab_changed.connect(_on_tab_changed)
	vbox_vault.add_child(tab_bar)
	
	# Scroll para el Grid de Slots
	var scroll_vault = ScrollContainer.new()
	scroll_vault.custom_minimum_size = Vector2(0, 320)
	scroll_vault.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox_vault.add_child(scroll_vault)
	
	# Grid de Slots (5 columnas x 6 filas = 30 slots)
	vault_grid = GridContainer.new()
	vault_grid.columns = 5
	vault_grid.add_theme_constant_override("h_separation", 10)
	vault_grid.add_theme_constant_override("v_separation", 10)
	scroll_vault.add_child(vault_grid)
	
	# Fila inferior del baúl: Costo desbloqueo y slots
	var hbox_vault_footer = HBoxContainer.new()
	vbox_vault.add_child(hbox_vault_footer)
	
	lbl_slots_info = Label.new()
	lbl_slots_info.text = "Slots: 0/30"
	lbl_slots_info.add_theme_font_size_override("font_size", 10)
	lbl_slots_info.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	hbox_vault_footer.add_child(lbl_slots_info)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_vault_footer.add_child(spacer)
	
	btn_unlock = Button.new()
	btn_unlock.text = "[+] DESBLOQUEAR PESTAÑA"
	btn_unlock.custom_minimum_size = Vector2(180, 26)
	btn_unlock.add_theme_font_size_override("font_size", 10)
	
	var btn_unlock_style = StyleBoxFlat.new()
	btn_unlock_style.bg_color = Color(0.2, 0.15, 0.0, 0.5)
	btn_unlock_style.border_width_left = 1
	btn_unlock_style.border_width_top = 1
	btn_unlock_style.border_width_right = 1
	btn_unlock_style.border_width_bottom = 1
	btn_unlock_style.border_color = Color(1.0, 0.8, 0.0)
	btn_unlock_style.set_corner_radius_all(4)
	btn_unlock.add_theme_stylebox_override("normal", btn_unlock_style)
	
	var btn_unlock_hover = btn_unlock_style.duplicate()
	btn_unlock_hover.bg_color = Color(0.35, 0.25, 0.0, 0.7)
	btn_unlock.add_theme_stylebox_override("hover", btn_unlock_hover)
	
	btn_unlock.pressed.connect(_on_unlock_pressed)
	hbox_vault_footer.add_child(btn_unlock)
	
	# B) PANEL DERECHO: INVENTARIO DEL PILOTO
	var panel_inv = PanelContainer.new()
	panel_inv.custom_minimum_size = Vector2(365, 480)
	
	var sb_inv = StyleBoxFlat.new()
	sb_inv.bg_color = Color(0.01, 0.02, 0.04, 0.98)
	sb_inv.border_width_top = 3
	sb_inv.border_width_bottom = 2
	sb_inv.border_width_left = 2
	sb_inv.border_width_right = 2
	sb_inv.border_color = Color(0.0, 0.8, 1.0, 0.8) # Borde cian neón
	sb_inv.corner_radius_top_left = 8
	sb_inv.corner_radius_top_right = 8
	sb_inv.corner_radius_bottom_left = 8
	sb_inv.corner_radius_bottom_right = 8
	sb_inv.shadow_color = Color(0, 0, 0, 0.6)
	sb_inv.shadow_size = 25
	panel_inv.add_theme_stylebox_override("panel", sb_inv)
	hbox.add_child(panel_inv)
	
	var margin_inv = MarginContainer.new()
	margin_inv.add_theme_constant_override("margin_top", 12)
	margin_inv.add_theme_constant_override("margin_bottom", 12)
	margin_inv.add_theme_constant_override("margin_left", 15)
	margin_inv.add_theme_constant_override("margin_right", 15)
	panel_inv.add_child(margin_inv)
	
	var vbox_inv = VBoxContainer.new()
	vbox_inv.add_theme_constant_override("separation", 10)
	margin_inv.add_child(vbox_inv)
	
	# Título Inventario
	var lbl_inv_title = Label.new()
	lbl_inv_title.text = "INVENTARIO DEL PILOTO"
	lbl_inv_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_inv_title.add_theme_font_size_override("font_size", 14)
	lbl_inv_title.add_theme_color_override("font_color", Color(0.0, 0.9, 1.0))
	vbox_inv.add_child(lbl_inv_title)
	
	# Info de saldo / hubs
	lbl_hubs = Label.new()
	lbl_hubs.text = "Hubs: 0 HUBS"
	lbl_hubs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_hubs.add_theme_font_size_override("font_size", 11)
	lbl_hubs.add_theme_color_override("font_color", Color(0.23, 1.0, 0.2))
	vbox_inv.add_child(lbl_hubs)
	
	# Scroll para lista de ítems de inventario
	var scroll_inv = ScrollContainer.new()
	scroll_inv.custom_minimum_size = Vector2(0, 320)
	scroll_inv.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox_inv.add_child(scroll_inv)
	
	inv_container = VBoxContainer.new()
	inv_container.add_theme_constant_override("separation", 6)
	scroll_inv.add_child(inv_container)
	
	# Botón de Cerrar general
	var btn_close = Button.new()
	btn_close.text = "CERRAR BAÚL"
	btn_close.custom_minimum_size = Vector2(0, 32)
	btn_close.pressed.connect(close_vault)
	vbox_inv.add_child(btn_close)
	
	# 4. Suscribirse a red
	if NetworkManager:
		NetworkManager.vault_data.connect(_on_vault_data_received)
		NetworkManager.vault_updated.connect(_on_vault_updated_received)
		NetworkManager.inventory_data.connect(_on_inventory_received)

func _input(event):
	if is_open:
		# Cerrar con ESC o con la tecla de acción (Y)
		if event.is_action_pressed("loot_claim") and not event.is_echo():
			close_vault()
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			close_vault()
			get_viewport().set_input_as_handled()
		# Click fuera del modal para cerrar
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var root_rect = Rect2(control_root.global_position + control_root.get_child(0).position, control_root.get_child(0).size)
			if not root_rect.has_point(event.position):
				close_vault()
				get_viewport().set_input_as_handled()

func _on_vault_data_received(data: Dictionary):
	vault_items = data.get("items", [])
	unlocked_tabs = int(data.get("unlockedTabs", 1))
	vault_config = data.get("config", {})
	
	# Inicializar pestañas en TabBar
	tab_bar.clear_tabs()
	for i in range(unlocked_tabs):
		tab_bar.add_tab("Pestaña " + str(i + 1))
		
	# Seleccionar última pestaña activa
	current_tab = min(current_tab, unlocked_tabs - 1)
	tab_bar.current_tab = current_tab
	
	open_vault()

func _on_vault_updated_received(data: Dictionary):
	vault_items = data.get("items", [])
	unlocked_tabs = int(data.get("unlockedTabs", 1))
	
	# Sincronizar TabBar
	var old_tab = current_tab
	tab_bar.clear_tabs()
	for i in range(unlocked_tabs):
		tab_bar.add_tab("Pestaña " + str(i + 1))
	current_tab = min(old_tab, unlocked_tabs - 1)
	tab_bar.current_tab = current_tab
	
	_refresh_vault()

func _on_inventory_received(data: Dictionary):
	player_inventory = data.get("inventory", [])
	player_hubs = int(data.get("hubs", 0))
	
	if is_open:
		_refresh_inventory()
		if lbl_hubs:
			lbl_hubs.text = "Hubs: " + str(player_hubs).replace(",", ".") + " HUBS"

func open_vault():
	if not is_open:
		is_open = true
		overlay.visible = true
		control_root.visible = true
		
		# Animación de entrada fluida (escala + fade)
		control_root.scale = Vector2(0.85, 0.85)
		control_root.pivot_offset = Vector2.ZERO # Centro
		overlay.modulate.a = 0.0
		
		var tw = create_tween().set_parallel(true)
		tw.tween_property(overlay, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE)
		tw.tween_property(control_root, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	_refresh_vault()
	_refresh_inventory()

func close_vault():
	if is_open:
		is_open = false
		
		var tw = create_tween().set_parallel(true)
		tw.tween_property(overlay, "modulate:a", 0.0, 0.2).set_trans(Tween.TRANS_SINE)
		tw.tween_property(control_root, "scale", Vector2(0.85, 0.85), 0.2).set_trans(Tween.TRANS_SINE)
		
		await tw.finished
		if not is_open:
			overlay.visible = false
			control_root.visible = false

func _on_tab_changed(index):
	current_tab = index
	_refresh_vault()

func _refresh_vault():
	# Limpiar grid
	for child in vault_grid.get_children():
		child.queue_free()
		
	var slots_max = vault_config.get("slotsPerTab", 30)
	var items_in_tab = []
	for it in vault_items:
		if it.get("tab", 0) == current_tab:
			items_in_tab.append(it)
			
	if lbl_slots_info:
		lbl_slots_info.text = "Slots: " + str(items_in_tab.size()) + "/" + str(slots_max)
		
	# Rellenar slots
	for i in range(slots_max):
		var slot_panel = PanelContainer.new()
		slot_panel.custom_minimum_size = Vector2(80, 80)
		vault_grid.add_child(slot_panel)
		
		# Estilo de slot base vacío
		var sb_empty = StyleBoxFlat.new()
		sb_empty.bg_color = Color(1.0, 1.0, 1.0, 0.02)
		sb_empty.border_width_left = 1
		sb_empty.border_width_top = 1
		sb_empty.border_width_right = 1
		sb_empty.border_width_bottom = 1
		sb_empty.border_color = Color(1.0, 1.0, 1.0, 0.05)
		sb_empty.set_corner_radius_all(4)
		slot_panel.add_theme_stylebox_override("panel", sb_empty)
		
		# Si hay un ítem en este slot
		if i < items_in_tab.size():
			var item = items_in_tab[i]
			var rarity_color = _get_rarity_color(item.get("rarity", 0))
			if item.has("color") and item["color"] != "":
				rarity_color = Color.from_string(item["color"], rarity_color)
				
			# Estilo de slot ocupado
			var sb_filled = sb_empty.duplicate()
			sb_filled.bg_color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.06)
			sb_filled.border_color = rarity_color
			slot_panel.add_theme_stylebox_override("panel", sb_filled)
			
			# Contenedor vertical
			var vbox = VBoxContainer.new()
			vbox.alignment = BoxContainer.ALIGNMENT_CENTER
			vbox.add_theme_constant_override("separation", 4)
			slot_panel.add_child(vbox)
			
			# Nombre del ítem
			var lbl_name = Label.new()
			lbl_name.text = str(item.get("name", "Item")).to_upper()
			lbl_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbl_name.add_theme_font_size_override("font_size", 9)
			lbl_name.add_theme_color_override("font_color", Color.WHITE)
			vbox.add_child(lbl_name)
			
			# Botón retirar
			var btn_get = Button.new()
			btn_get.text = "RETIRAR"
			btn_get.custom_minimum_size = Vector2(60, 20)
			btn_get.add_theme_font_size_override("font_size", 8)
			
			var btn_style = StyleBoxFlat.new()
			btn_style.bg_color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.25)
			btn_style.set_corner_radius_all(3)
			btn_get.add_theme_stylebox_override("normal", btn_style)
			
			var inst_id = item.get("instanceId", "")
			btn_get.pressed.connect(_on_withdraw_pressed.bind(inst_id))
			vbox.add_child(btn_get)
			
	# Actualizar botón de desbloquear pestaña
	var prices = vault_config.get("unlockPrices", [0, 5000, 15000, 45000, 100000])
	if unlocked_tabs >= prices.size():
		btn_unlock.text = "LÍMITE MÁXIMO"
		btn_unlock.disabled = true
	else:
		var price = prices[unlocked_tabs]
		btn_unlock.text = "[+] ABRIR PESTAÑA " + str(unlocked_tabs + 1) + " (" + str(price) + " Hubs)"
		btn_unlock.disabled = (player_hubs < price)

func _refresh_inventory():
	# Limpiar
	for child in inv_container.get_children():
		child.queue_free()
		
	if player_inventory.size() == 0:
		var lbl_empty = Label.new()
		lbl_empty.text = "INVENTARIO VACÍO"
		lbl_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_empty.add_theme_font_size_override("font_size", 10)
		lbl_empty.modulate = Color(0.5, 0.5, 0.5)
		inv_container.add_child(lbl_empty)
		return
		
	# Poblar ítems de inventario
	for item in player_inventory:
		var row = PanelContainer.new()
		row.custom_minimum_size = Vector2(0, 42)
		inv_container.add_child(row)
		
		var rarity_color = _get_rarity_color(item.get("rarity", 0))
		if item.has("color") and item["color"] != "":
			rarity_color = Color.from_string(item["color"], rarity_color)
			
		var sb_row = StyleBoxFlat.new()
		sb_row.bg_color = Color(1.0, 1.0, 1.0, 0.03)
		sb_row.border_width_left = 3
		sb_row.border_color = rarity_color
		sb_row.set_corner_radius_all(3)
		row.add_theme_stylebox_override("panel", sb_row)
		
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		row.add_child(hbox)
		
		var margin = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 8)
		margin.add_theme_constant_override("margin_right", 8)
		row.remove_child(hbox)
		row.add_child(margin)
		margin.add_child(hbox)
		
		# Indicador de rareza
		var dot = ColorRect.new()
		dot.custom_minimum_size = Vector2(8, 8)
		dot.color = rarity_color
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hbox.add_child(dot)
		
		# Nombre e info del ítem
		var vbox_lbls = VBoxContainer.new()
		vbox_lbls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox_lbls.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.add_child(vbox_lbls)
		
		var lbl_name = Label.new()
		lbl_name.text = str(item.get("name", "Ítem")).to_upper()
		lbl_name.add_theme_font_size_override("font_size", 10)
		vbox_lbls.add_child(lbl_name)
		
		var lbl_type = Label.new()
		lbl_type.text = _get_rarity_label(item.get("rarity", 0)) + " | " + str(item.get("type", "MÓDULO")).to_upper()
		lbl_type.add_theme_font_size_override("font_size", 8)
		lbl_type.modulate = Color(0.7, 0.7, 0.7)
		vbox_lbls.add_child(lbl_type)
		
		# Botón Guardar
		var btn_save = Button.new()
		btn_save.text = "GUARDAR"
		btn_save.custom_minimum_size = Vector2(80, 24)
		btn_save.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		btn_save.add_theme_font_size_override("font_size", 9)
		
		var btn_sb = StyleBoxFlat.new()
		btn_sb.bg_color = Color(0.1, 0.1, 0.15, 0.8)
		btn_sb.border_width_left = 1
		btn_sb.border_width_right = 1
		btn_sb.border_width_top = 1
		btn_sb.border_width_bottom = 1
		btn_sb.border_color = rarity_color
		btn_sb.set_corner_radius_all(3)
		btn_save.add_theme_stylebox_override("normal", btn_sb)
		
		var btn_sb_hover = btn_sb.duplicate()
		btn_sb_hover.bg_color = rarity_color
		btn_sb_hover.bg_color.a = 0.2
		btn_save.add_theme_stylebox_override("hover", btn_sb_hover)
		
		var inst_id = item.get("instanceId", "")
		btn_save.pressed.connect(_on_store_pressed.bind(inst_id))
		hbox.add_child(btn_save)

func _on_store_pressed(instance_id: String):
	if NetworkManager:
		NetworkManager.send_event("storeVaultItem", { "instanceId": instance_id, "tab": current_tab })

func _on_withdraw_pressed(instance_id: String):
	if NetworkManager:
		NetworkManager.send_event("withdrawVaultItem", { "instanceId": instance_id })

func _on_unlock_pressed():
	if NetworkManager:
		NetworkManager.send_event("unlockVaultTab", {})

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

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
var player_ohcu: int = 0

# Referencias a nodos UI
var control_root: Control = null
var overlay: ColorRect = null
var tab_bar: TabBar = null
var vault_grid: GridContainer = null
var inv_container: GridContainer = null
var btn_unlock: Button = null
var lbl_hubs: Label = null
var lbl_ohcu: Label = null
var lbl_slots_info: Label = null
var lbl_inv_slots: Label = null
var btn_expand_inv: Button = null
var inventory_max_slots: int = 30
var inventory_config: Dictionary = {}

# Tooltip Premium
var info_panel: PanelContainer = null
var lbl_info_title: Label = null
var lbl_info_type: Label = null
var lbl_info_stats: Label = null

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
	hbox.custom_minimum_size = Vector2(865, 480)
	hbox.position = Vector2(-432, -240) # Centrar en pantalla
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
	panel_inv.custom_minimum_size = Vector2(380, 480)
	
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
	
	# Info de saldo / hubs y ohcu
	var hbox_balances = HBoxContainer.new()
	hbox_balances.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox_inv.add_child(hbox_balances)

	lbl_hubs = Label.new()
	lbl_hubs.text = "Hubs: 0"
	lbl_hubs.add_theme_font_size_override("font_size", 11)
	lbl_hubs.add_theme_color_override("font_color", Color(0.23, 1.0, 0.2))
	hbox_balances.add_child(lbl_hubs)

	var lbl_sep_balances = Label.new()
	lbl_sep_balances.text = "  |  "
	lbl_sep_balances.add_theme_font_size_override("font_size", 11)
	lbl_sep_balances.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hbox_balances.add_child(lbl_sep_balances)

	lbl_ohcu = Label.new()
	lbl_ohcu.text = "Ohcu: 0"
	lbl_ohcu.add_theme_font_size_override("font_size", 11)
	lbl_ohcu.add_theme_color_override("font_color", Color(0.0, 0.8, 1.0))
	hbox_balances.add_child(lbl_ohcu)
	
	# Scroll para lista de ítems de inventario
	var scroll_inv = ScrollContainer.new()
	scroll_inv.custom_minimum_size = Vector2(0, 320)
	scroll_inv.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox_inv.add_child(scroll_inv)
	
	inv_container = GridContainer.new()
	inv_container.columns = 4
	inv_container.add_theme_constant_override("h_separation", 10)
	inv_container.add_theme_constant_override("v_separation", 10)
	scroll_inv.add_child(inv_container)
	
	# Fila para Slots del Piloto y Expansión
	var hbox_slots_inv = HBoxContainer.new()
	vbox_inv.add_child(hbox_slots_inv)
	
	lbl_inv_slots = Label.new()
	lbl_inv_slots.text = "BODEGA: 0/30 SLOTS"
	lbl_inv_slots.add_theme_font_size_override("font_size", 10)
	lbl_inv_slots.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	hbox_slots_inv.add_child(lbl_inv_slots)
	
	var spacer_inv = Control.new()
	spacer_inv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_slots_inv.add_child(spacer_inv)
	
	btn_expand_inv = Button.new()
	btn_expand_inv.text = "[+] AÑADIR SLOT"
	btn_expand_inv.custom_minimum_size = Vector2(120, 22)
	btn_expand_inv.add_theme_font_size_override("font_size", 9)
	
	var btn_expand_style = StyleBoxFlat.new()
	btn_expand_style.bg_color = Color(0.0, 0.15, 0.2, 0.5)
	btn_expand_style.border_width_left = 1
	btn_expand_style.border_width_top = 1
	btn_expand_style.border_width_right = 1
	btn_expand_style.border_width_bottom = 1
	btn_expand_style.border_color = Color(0.0, 0.8, 1.0)
	btn_expand_style.set_corner_radius_all(3)
	btn_expand_inv.add_theme_stylebox_override("normal", btn_expand_style)
	
	var btn_expand_hover = btn_expand_style.duplicate()
	btn_expand_hover.bg_color = Color(0.0, 0.25, 0.35, 0.7)
	btn_expand_inv.add_theme_stylebox_override("hover", btn_expand_hover)
	
	btn_expand_inv.pressed.connect(_on_expand_inv_pressed)
	hbox_slots_inv.add_child(btn_expand_inv)
	
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
		
	# 5. Crear el Panel de Información Flotante (Tooltip Premium)
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
			# Ocultar panel de información en cualquier click de mouse
			_hide_info_panel()
			
			var root_rect = Rect2(control_root.global_position + control_root.get_child(0).position, control_root.get_child(0).size)
			if not root_rect.has_point(event.position):
				close_vault()
				get_viewport().set_input_as_handled()

func _on_vault_data_received(data: Dictionary):
	vault_items = data.get("items", [])
	unlocked_tabs = int(data.get("unlockedTabs", 1))
	vault_config = data.get("vaultConfig", {})
	inventory_config = data.get("inventoryConfig", {})
	inventory_max_slots = int(data.get("inventoryMaxSlots", 30))
	
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
	inventory_max_slots = int(data.get("inventoryMaxSlots", inventory_max_slots))
	
	# Sincronizar TabBar
	var old_tab = current_tab
	tab_bar.clear_tabs()
	for i in range(unlocked_tabs):
		tab_bar.add_tab("Pestaña " + str(i + 1))
	current_tab = min(old_tab, unlocked_tabs - 1)
	tab_bar.current_tab = current_tab
	
	_refresh_vault()
	_refresh_inventory()

func _on_inventory_received(data: Dictionary):
	player_inventory = data.get("inventory", [])
	player_hubs = int(data.get("hubs", 0))
	var player_data = data.get("player", {})
	if player_data.has("inventoryMaxSlots"):
		inventory_max_slots = int(player_data.inventoryMaxSlots)
	if player_data.has("ohcu"):
		player_ohcu = int(player_data.ohcu)
	else:
		player_ohcu = int(data.get("ohcu", 0))
	
	if is_open:
		_refresh_inventory()
		_update_unlock_tab_button()
		if lbl_hubs:
			lbl_hubs.text = "Hubs: " + str(player_hubs)
		if lbl_ohcu:
			lbl_ohcu.text = "Ohcu: " + str(player_ohcu)

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
	_hide_info_panel()
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
	_hide_info_panel()
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
		lbl_slots_info.text = "Slots: " + str(items_in_tab.size()) + "/" + str(int(slots_max))
		
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
				
			# Estilo de slot ocupado con borde y márgenes para la imagen a sangre completa
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
			
			# Imagen del ítem (TextureRect) a pantalla completa de slot
			var icon_path = _get_item_icon(item)
			if icon_path != "":
				var tex_rect = TextureRect.new()
				tex_rect.texture = load(icon_path)
				tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
				margin.add_child(tex_rect)
				
			# Eventos de ratón
			var inst_id = item.get("instanceId", "")
			slot_panel.gui_input.connect(func(event):
				if event is InputEventMouseButton and event.pressed:
					if event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
						_on_withdraw_pressed(inst_id)
						_hide_info_panel()
						get_viewport().set_input_as_handled()
					elif event.button_index == MOUSE_BUTTON_LEFT:
						_show_info_panel(item, slot_panel)
						get_viewport().set_input_as_handled()
			)
			
	# Actualizar botón de desbloquear pestaña
	_update_unlock_tab_button()

func _refresh_inventory():
	# Limpiar grid
	for child in inv_container.get_children():
		child.queue_free()
		
	if lbl_inv_slots:
		lbl_inv_slots.text = "BODEGA: " + str(player_inventory.size()) + "/" + str(int(inventory_max_slots)) + " SLOTS"
		
	_update_expand_inventory_button()
		
	# Rellenar slots del inventario del piloto (grilla simétrica de 80x80)
	for i in range(int(inventory_max_slots)):
		var slot_panel = PanelContainer.new()
		slot_panel.custom_minimum_size = Vector2(80, 80)
		inv_container.add_child(slot_panel)
		
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
		if i < player_inventory.size():
			var item = player_inventory[i]
			var rarity_color = _get_rarity_color(item.get("rarity", 0))
			if item.has("color") and item["color"] != "":
				rarity_color = Color.from_string(item["color"], rarity_color)
				
			# Estilo de slot ocupado
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
			
			# Imagen del ítem (TextureRect) a pantalla completa
			var icon_path = _get_item_icon(item)
			if icon_path != "":
				var tex_rect = TextureRect.new()
				tex_rect.texture = load(icon_path)
				tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
				margin.add_child(tex_rect)
				
			# Eventos de ratón
			var inst_id = item.get("instanceId", "")
			slot_panel.gui_input.connect(func(event):
				if event is InputEventMouseButton and event.pressed:
					if event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
						_on_store_pressed(inst_id)
						_hide_info_panel()
						get_viewport().set_input_as_handled()
					elif event.button_index == MOUSE_BUTTON_LEFT:
						_show_info_panel(item, slot_panel)
						get_viewport().set_input_as_handled()
			)

func _on_store_pressed(instance_id: String):
	_hide_info_panel()
	if NetworkManager:
		NetworkManager.send_event("storeVaultItem", { "instanceId": instance_id, "tab": current_tab })

func _on_withdraw_pressed(instance_id: String):
	_hide_info_panel()
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

func _on_expand_inv_pressed():
	if NetworkManager:
		NetworkManager.send_event("unlockInventorySlot", {})

func _get_item_icon(item_data: Dictionary) -> String:
	var icon_path = str(item_data.get("icon", ""))
	var search_id = str(item_data.get("id", "")).to_lower()
	
	if icon_path == "" or icon_path == "null" or "placeholder" in icon_path or not ResourceLoader.exists(icon_path):
		# Fallback algorítmico básico
		if search_id.begins_with("las"):
			var n = search_id.replace("las", "")
			icon_path = "res://assets/Armas/Arma" + n + "/Arma" + n + ".png"
		elif search_id.begins_with("sh"):
			var n = search_id.replace("sh", "")
			icon_path = "res://assets/Escudos/Escudo" + n + "/Escudo" + n + ".png"
		elif search_id.begins_with("en"):
			var n = search_id.replace("en", "")
			icon_path = "res://assets/Motores/Motor" + n + "/Motor" + n + ".png"
			
		# Fallback secundario si aún no existe
		if not ResourceLoader.exists(icon_path):
			if search_id.begins_with("las"):
				icon_path = "res://assets/Municiones/Laser1.png"
	
	if ResourceLoader.exists(icon_path):
		return icon_path
	return ""

func _show_info_panel(item_data: Dictionary, target_node: Control):
	if not info_panel: return
	
	var rarity = item_data.get("rarity", 0)
	var rarity_color = _get_rarity_color(rarity)
	if item_data.has("color") and item_data["color"] != "":
		rarity_color = Color.from_string(item_data["color"], rarity_color)
		
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
	lbl_info_title.text = str(item_data.get("name", "ÍTEM")).to_upper()
	lbl_info_title.add_theme_color_override("font_color", rarity_color)
	
	lbl_info_type.text = _get_rarity_label(rarity) + " | " + str(item_data.get("type", "MÓDULO")).to_upper()
	
	# Estadísticas
	var base_val = int(item_data.get("base", 0))
	var type_str = str(item_data.get("type", "")).to_lower()
	var stat_text = ""
	var search_id = str(item_data.get("id", "")).to_lower()
	
	if type_str == "laser" or type_str == "weapon" or search_id.begins_with("las"):
		stat_text = "DAÑO: +" + str(base_val)
	elif type_str == "shield" or search_id.begins_with("sh"):
		stat_text = "ESCUDO: +" + str(base_val)
	elif type_str == "engine" or search_id.begins_with("en"):
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

func _parse_price(price_data) -> Dictionary:
	var parsed = { "hubs": 0, "ohcu": 0 }
	if price_data is Dictionary:
		parsed["hubs"] = int(price_data.get("hubs", 0))
		parsed["ohcu"] = int(price_data.get("ohcu", 0))
	elif price_data is float or price_data is int:
		parsed["hubs"] = int(price_data)
	return parsed

func _update_unlock_tab_button():
	if not btn_unlock: return
	var prices = vault_config.get("unlockPrices", [0, 5000, 15000, 45000, 100000])
	if unlocked_tabs >= prices.size():
		btn_unlock.text = "LÍMITE MÁXIMO"
		btn_unlock.disabled = true
		return

	var raw_price = prices[unlocked_tabs]
	var price_dict = _parse_price(raw_price)
	var h_cost = price_dict["hubs"]
	var o_cost = price_dict["ohcu"]

	if h_cost == 0 and o_cost == 0:
		btn_unlock.text = "BLOQUEADO"
		btn_unlock.disabled = true
	else:
		var label_parts = []
		if h_cost > 0:
			label_parts.append(str(h_cost) + " Hubs")
		if o_cost > 0:
			label_parts.append(str(o_cost) + " Ohcu")
		
		btn_unlock.text = "[+] ABRIR PESTAÑA " + str(unlocked_tabs + 1) + " (" + " + ".join(label_parts) + ")"
		
		# Validación de fondos
		var can_afford = true
		if h_cost > 0 and player_hubs < h_cost:
			can_afford = false
		if o_cost > 0 and player_ohcu < o_cost:
			can_afford = false
		btn_unlock.disabled = not can_afford

func _update_expand_inventory_button():
	if not btn_expand_inv: return
	var raw_price = inventory_config.get("unlockSlotPrice", 1000)
	var price_dict = _parse_price(raw_price)
	var h_cost = price_dict["hubs"]
	var o_cost = price_dict["ohcu"]

	if h_cost == 0 and o_cost == 0:
		btn_expand_inv.text = "BLOQUEADO"
		btn_expand_inv.disabled = true
	else:
		var label_parts = []
		if h_cost > 0:
			label_parts.append(str(h_cost) + " Hubs")
		if o_cost > 0:
			label_parts.append(str(o_cost) + " Ohcu")
		
		btn_expand_inv.text = "[+] AÑADIR SLOT (" + " + ".join(label_parts) + ")"
		
		# Validación de fondos
		var can_afford = true
		if h_cost > 0 and player_hubs < h_cost:
			can_afford = false
		if o_cost > 0 and player_ohcu < o_cost:
			can_afford = false
		btn_expand_inv.disabled = not can_afford

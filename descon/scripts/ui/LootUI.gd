extends CanvasLayer

# LootUI.gd (v1.0 - Modal de Botín Programático AAA)
# Interfaz modular de recolección de recompensas, autogenerada y 100% responsiva.

var current_loot_id: String = ""
var items_list: Array = []
var is_open: bool = false

# Referencias a nodos UI creados dinámicamente
var control_root: Control = null
var overlay: ColorRect = null
var panel_container: PanelContainer = null
var items_container: VBoxContainer = null
var btn_claim_all: Button = null

func _ready():
	add_to_group("loot_ui")
	layer = 100 # Dibujar por encima del HUD estándar
	
	# 1. Crear el overlay oscuro de fondo
	overlay = ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	
	# 2. Crear el contenedor raíz para centrar
	control_root = Control.new()
	control_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(control_root)
	
	# Ocultar inicialmente (se hace después de add_child para evitar que Godot lo restablezca a visible al entrar al árbol)
	overlay.visible = false
	overlay.modulate.a = 0.0
	control_root.visible = false

	
	# 3. Crear el modal (PanelContainer)
	panel_container = PanelContainer.new()
	panel_container.custom_minimum_size = Vector2(400, 300)
	# Centrar el panel
	panel_container.position = Vector2(-200, -150)
	
	# Estilo del panel (Fondo espacial oscuro con borde cian brillante)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.02, 0.06, 0.98)
	sb.border_width_top = 3
	sb.border_width_bottom = 2
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_color = Color(0.0, 0.8, 1.0, 0.8) # Cian brillante
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 20
	panel_container.add_theme_stylebox_override("panel", sb)
	control_root.add_child(panel_container)
	
	# 4. Estructura interna del modal (VBoxContainer)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	panel_container.add_child(vbox)
	
	# Margen interno
	var margin_container = MarginContainer.new()
	margin_container.add_theme_constant_override("margin_top", 12)
	margin_container.add_theme_constant_override("margin_bottom", 12)
	margin_container.add_theme_constant_override("margin_left", 15)
	margin_container.add_theme_constant_override("margin_right", 15)
	panel_container.remove_child(vbox)
	panel_container.add_child(margin_container)
	margin_container.add_child(vbox)
	
	# A) Título del modal
	var label_title = Label.new()
	label_title.text = "SUMINISTROS DETECTADOS"
	label_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_title.modulate = Color(0, 1, 1) # Cian
	var font = control_root.get_theme_font("font")
	if font:
		label_title.add_theme_font_override("font", font)
	label_title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(label_title)
	
	# B) Scroll para listado de ítems
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 160)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	
	items_container = VBoxContainer.new()
	items_container.add_theme_constant_override("separation", 8)
	scroll.add_child(items_container)
	
	# C) Fila de botones inferiores
	var hbox_btns = HBoxContainer.new()
	hbox_btns.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox_btns.add_theme_constant_override("separation", 15)
	vbox.add_child(hbox_btns)
	
	# Botón Recoger Todo
	btn_claim_all = Button.new()
	btn_claim_all.text = "RECOGER TODO"
	btn_claim_all.custom_minimum_size = Vector2(140, 36)
	btn_claim_all.pressed.connect(_on_claim_all_pressed)
	
	# Estilo para el botón Recoger Todo (Cian brillante)
	var btn_sb = StyleBoxFlat.new()
	btn_sb.bg_color = Color(0, 0.5, 0.6, 0.4)
	btn_sb.border_width_left = 1
	btn_sb.border_width_right = 1
	btn_sb.border_width_top = 1
	btn_sb.border_width_bottom = 1
	btn_sb.border_color = Color(0, 0.8, 1)
	btn_sb.corner_radius_top_left = 4
	btn_sb.corner_radius_top_right = 4
	btn_sb.corner_radius_bottom_left = 4
	btn_sb.corner_radius_bottom_right = 4
	btn_claim_all.add_theme_stylebox_override("normal", btn_sb)
	
	var btn_sb_hover = btn_sb.duplicate()
	btn_sb_hover.bg_color = Color(0, 0.6, 0.7, 0.6)
	btn_claim_all.add_theme_stylebox_override("hover", btn_sb_hover)
	
	hbox_btns.add_child(btn_claim_all)
	
	# Botón Cerrar
	var btn_close = Button.new()
	btn_close.text = "CERRAR"
	btn_close.custom_minimum_size = Vector2(100, 36)
	btn_close.pressed.connect(close_modal)
	hbox_btns.add_child(btn_close)
	
	# 5. Suscribirse a eventos de red
	if NetworkManager:
		NetworkManager.loot_content.connect(_on_loot_content_received)
		NetworkManager.loot_despawned.connect(_on_loot_despawned_received)

func _input(event):
	if is_open:
		# Cerrar con la misma tecla de interacción que abre el cofre (Y por defecto)
		if event.is_action_pressed("loot_claim") and not event.is_echo():
			close_modal()
			get_viewport().set_input_as_handled()
		# Tecla ESC para cerrar
		elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			close_modal()
			get_viewport().set_input_as_handled()
		# Click fuera del modal para cerrar
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var panel_rect = Rect2(panel_container.global_position, panel_container.size)
			if not panel_rect.has_point(event.position):
				close_modal()
				get_viewport().set_input_as_handled()

func _on_loot_content_received(data: Dictionary):
	if typeof(data) != TYPE_DICTIONARY or not data.has("lootId") or not data.has("items"): return
	open_modal(str(data.lootId), data.items)

func _on_loot_despawned_received(data: Dictionary):
	if typeof(data) != TYPE_DICTIONARY or not data.has("id"): return
	if str(data.id) == current_loot_id:
		close_modal()

func open_modal(loot_id: String, items: Array):
	current_loot_id = loot_id
	items_list = items
	
	# Limpiar listado anterior
	for child in items_container.get_children():
		child.queue_free()
		
	# Poblar el listado de ítems
	for i in range(items.size()):
		var item = items[i]
		_create_item_row(item)
		
	# Si ya no quedan ítems en el drop, mostramos un aviso en la lista en vez de cerrarlo inmediatamente
	if items.size() == 0:
		var label_empty = Label.new()
		label_empty.text = "ESTE CONTENEDOR ESTÁ VACÍO."
		label_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label_empty.modulate = Color(0.6, 0.6, 0.6)
		label_empty.add_theme_font_size_override("font_size", 10)
		label_empty.custom_minimum_size = Vector2(0, 40)
		items_container.add_child(label_empty)
		
	# Habilitar o deshabilitar botón de recoger todo
	btn_claim_all.disabled = (items.size() == 0)
	
	if not is_open:
		is_open = true
		overlay.visible = true
		control_root.visible = true

		
		# Animación de entrada premium (Fade-in + escala progresiva)
		control_root.scale = Vector2(0.85, 0.85)
		control_root.pivot_offset = Vector2.ZERO # Centrado
		overlay.modulate.a = 0.0
		
		var tw = create_tween().set_parallel(true)
		tw.tween_property(overlay, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE)
		tw.tween_property(control_root, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _create_item_row(item: Dictionary):
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	items_container.add_child(row)
	
	# Panel contenedor del Item
	var item_panel = PanelContainer.new()
	item_panel.custom_minimum_size = Vector2(350, 42)
	row.add_child(item_panel)
	
	var rarity_color = _get_rarity_color(item.get("rarity", 0))
	if item.has("color") and item["color"] != "":
		rarity_color = Color.from_string(item["color"], rarity_color)
		
	var sb_row = StyleBoxFlat.new()
	sb_row.bg_color = Color(1.0, 1.0, 1.0, 0.03)
	sb_row.border_width_left = 4
	sb_row.border_color = rarity_color # Borde izquierdo del color de su rareza (AAA style)
	sb_row.corner_radius_top_left = 3
	sb_row.corner_radius_bottom_left = 3
	item_panel.add_theme_stylebox_override("panel", sb_row)
	
	# Layout interno de la fila (HBoxContainer)
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	item_panel.add_child(hbox)
	
	# Margen lateral
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	item_panel.remove_child(hbox)
	item_panel.add_child(margin)
	margin.add_child(hbox)
	
	# Indicador / Icono de color brillante
	var icon_color = ColorRect.new()
	icon_color.custom_minimum_size = Vector2(8, 8)
	icon_color.color = rarity_color
	icon_color.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(icon_color)
	
	# Icono gráfico del ítem
	var icon_path = _get_item_icon(item)
	if icon_path != "":
		var tex_rect = TextureRect.new()
		tex_rect.texture = load(icon_path)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.custom_minimum_size = Vector2(28, 28)
		tex_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hbox.add_child(tex_rect)
	
	# Nombre y Tipo del ítem
	var vbox_text = VBoxContainer.new()
	vbox_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_text.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(vbox_text)
	
	var label_name = Label.new()
	label_name.text = str(item.get("name", "Ítem Desconocido")).to_upper()
	label_name.add_theme_font_size_override("font_size", 11)
	label_name.add_theme_color_override("font_color", Color.WHITE)
	vbox_text.add_child(label_name)
	
	var label_type = Label.new()
	var type_str = str(item.get("type", "MÓDULO")).to_upper()
	var rarity_label = _get_rarity_label(item.get("rarity", 0))
	label_type.text = rarity_label + " | " + type_str
	label_type.add_theme_font_size_override("font_size", 9)
	label_type.add_theme_color_override("font_color", rarity_color.lerp(Color.WHITE, 0.4))
	vbox_text.add_child(label_type)
	
	# Doble clic sobre la fila para recoger el ítem del botín
	var inst_id = str(item.get("instanceId", ""))
	item_panel.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
			_on_claim_item_pressed(inst_id)
			get_viewport().set_input_as_handled()
	)

func close_modal():
	if is_open:
		is_open = false
		
		# Animación de salida (Fade-out + encogimiento)
		var tw = create_tween().set_parallel(true)
		tw.tween_property(overlay, "modulate:a", 0.0, 0.2).set_trans(Tween.TRANS_SINE)
		tw.tween_property(control_root, "scale", Vector2(0.85, 0.85), 0.2).set_trans(Tween.TRANS_SINE)
		
		await tw.finished
		if not is_open: # Validar que no se reabrió durante la animación
			overlay.visible = false
			control_root.visible = false
			current_loot_id = ""
			items_list.clear()
	else:
		overlay.visible = false
		control_root.visible = false
		current_loot_id = ""
		items_list.clear()

func _on_claim_all_pressed():
	if current_loot_id != "" and NetworkManager:
		NetworkManager.send_event("claimAllLoot", { "lootId": current_loot_id })

func _on_claim_item_pressed(instance_id: String):
	if current_loot_id != "" and instance_id != "" and NetworkManager:
		NetworkManager.send_event("claimLootItem", { "lootId": current_loot_id, "instanceId": instance_id })

func _get_rarity_color(rarity: int) -> Color:
	match rarity:
		0: return Color(0.7, 0.7, 0.7) # Común (Gris)
		1: return Color(0.13, 0.77, 0.36) # Raro (Verde)
		2: return Color(0.23, 0.51, 0.96) # Épico (Azul)
		3: return Color(0.66, 0.33, 0.97) # Reliquia (Violeta)
		4: return Color(0.98, 0.45, 0.09) # Legendario (Naranja)
		_: return Color.WHITE

func _get_rarity_label(rarity: int) -> String:
	match rarity:
		0: return "COMÚN"
		1: return "RARO"
		2: return "ÉPICO"
		3: return "RELIQUIA"
		4: return "LEGENDARIO"
		_: return "MÓDULO"

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

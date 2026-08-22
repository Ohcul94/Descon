extends Control

# QuestsTab.gd - DIARIO DE MISIONES GALÁCTICAS (v380)
# Módulo visual e interactivo para visualizar, aceptar y reclamar recompensas de misiones.

var inv_main = null
var active_quests = []
var completed_quests = []
var selected_type_filter = "story" # "story", "daily", "weekly"

func setup(p_inv_main):
	inv_main = p_inv_main
	
	if NetworkManager:
		if not NetworkManager.socket_event_received.is_connected(_on_socket_event_received):
			NetworkManager.socket_event_received.connect(_on_socket_event_received)
		# Solicitar el estado inicial de misiones del jugador
		NetworkManager.send_event("getQuestsState", {})

func _exit_tree():
	if NetworkManager and NetworkManager.socket_event_received.is_connected(_on_socket_event_received):
		NetworkManager.socket_event_received.disconnect(_on_socket_event_received)

func _on_socket_event_received(event_name: String, event_data: Variant):
	if event_name == "questsStateData" and typeof(event_data) == TYPE_DICTIONARY:
		active_quests = event_data.get("active", [])
		completed_quests = event_data.get("completed", [])
		update_ui()

func update_ui():
	if not inv_main: return
	
	# Limpiar
	for n in get_children():
		remove_child(n)
		n.queue_free()
		
	var master_v = VBoxContainer.new()
	master_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	master_v.add_theme_constant_override("separation", 15)
	add_child(master_v)
	
	# Margen superior
	var top_spacer = Control.new()
	top_spacer.custom_minimum_size.y = 10
	master_v.add_child(top_spacer)
	
	# Filtros de tipo de misión
	var filter_hb = HBoxContainer.new()
	filter_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	filter_hb.add_theme_constant_override("separation", 20)
	master_v.add_child(filter_hb)
	
	var filter_options = [
		{"key": "story", "label": "📖 MISIONES DE HISTORIA"},
		{"key": "daily", "label": "⏳ DIARIAS"},
		{"key": "weekly", "label": "📅 SEMANALES"}
	]
	
	for opt in filter_options:
		var btn = Button.new()
		btn.text = opt.label
		btn.custom_minimum_size = Vector2(180, 40)
		btn.toggle_mode = true
		btn.button_pressed = (selected_type_filter == opt.key)
		
		# Estilo personalizado
		var sb_norm = StyleBoxFlat.new()
		sb_norm.bg_color = Color(0, 0.2, 0.3, 0.2)
		sb_norm.border_width_bottom = 2
		sb_norm.border_color = Color(0, 0.6, 0.8, 0.3)
		btn.add_theme_stylebox_override("normal", sb_norm)
		
		var sb_press = StyleBoxFlat.new()
		sb_press.bg_color = Color(0, 0.4, 0.6, 0.4)
		sb_press.border_width_bottom = 3
		sb_press.border_color = Color.CYAN
		btn.add_theme_stylebox_override("pressed", sb_press)
		
		btn.pressed.connect(func():
			selected_type_filter = opt.key
			update_ui()
		)
		filter_hb.add_child(btn)
	
	# Scroll para las misiones
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	master_v.add_child(scroll)
	
	var quests_container = VBoxContainer.new()
	quests_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quests_container.add_theme_constant_override("separation", 12)
	scroll.add_child(quests_container)
	
	# Obtener la lista del config cargado desde el servidor
	var quests_config = []
	if NetworkManager and NetworkManager.server_config.has("questsConfig"):
		quests_config = NetworkManager.server_config["questsConfig"]
		
	# Si no hay misiones cargadas, mostrar mensaje
	var filtered_quests = []
	for q in quests_config:
		if q.get("type", "story") == selected_type_filter:
			filtered_quests.append(q)
			
	if filtered_quests.size() == 0:
		var empty_lbl = Label.new()
		empty_lbl.text = "\n\nNO HAY MISIONES DISPONIBLES EN ESTA CATEGORÍA"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.modulate = Color(0.5, 0.5, 0.5)
		empty_lbl.add_theme_font_size_override("font_size", 14)
		quests_container.add_child(empty_lbl)
		return
		
	for quest in filtered_quests:
		var q_id = str(quest.get("id", ""))
		var q_name = str(quest.get("name", "Misión Desconocida"))
		var q_desc = str(quest.get("desc", ""))
		var target_type = str(quest.get("targetType", "kill"))
		var target_amount = int(quest.get("targetAmount", 1))
		var reward = quest.get("reward", {})
		
		# Buscar si está activa y ver progreso
		var is_active = false
		var progress = 0
		for aq in active_quests:
			if str(aq.get("id", "")) == q_id:
				is_active = true
				progress = int(aq.get("progress", 0))
				break
				
		var is_completed = completed_quests.has(q_id)
		
		# Tarjeta contenedor
		var card = PanelContainer.new()
		card.custom_minimum_size.y = 110
		quests_container.add_child(card)
		
		var sb_card = StyleBoxFlat.new()
		sb_card.bg_color = Color(0.01, 0.05, 0.1, 0.8)
		sb_card.border_width_left = 4
		
		if is_completed:
			sb_card.border_color = Color.GREEN
			sb_card.bg_color = Color(0.01, 0.08, 0.03, 0.5)
		elif is_active:
			if progress >= target_amount or (target_type == "explore" and progress >= 1):
				sb_card.border_color = Color.GOLD
				sb_card.bg_color = Color(0.1, 0.08, 0.01, 0.8)
			else:
				sb_card.border_color = Color.CYAN
		else:
			sb_card.border_color = Color(0.4, 0.4, 0.4)
			
		card.add_theme_stylebox_override("panel", sb_card)
		
		var main_hb = HBoxContainer.new()
		main_hb.add_theme_constant_override("separation", 20)
		card.add_child(main_hb)
		
		# Margen interno izquierdo
		var margin_left = Control.new()
		margin_left.custom_minimum_size.x = 8
		main_hb.add_child(margin_left)
		
		# Info Textos (Nombre, Desc, Progreso)
		var info_vb = VBoxContainer.new()
		info_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_vb.alignment = BoxContainer.ALIGNMENT_CENTER
		main_hb.add_child(info_vb)
		
		var name_lbl = Label.new()
		name_lbl.text = q_name
		name_lbl.add_theme_font_size_override("font_size", 14)
		if is_completed:
			name_lbl.modulate = Color.GREEN
			name_lbl.text += " [COMPLETADA]"
		elif is_active and (progress >= target_amount or (target_type == "explore" and progress >= 1)):
			name_lbl.modulate = Color.GOLD
			name_lbl.text += " [¡LISTA PARA COBRAR!]"
		elif is_active:
			name_lbl.modulate = Color.CYAN
		info_vb.add_child(name_lbl)
		
		var desc_lbl = Label.new()
		desc_lbl.text = q_desc
		desc_lbl.add_theme_font_size_override("font_size", 10)
		desc_lbl.modulate.a = 0.7
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_vb.add_child(desc_lbl)
		
		# Línea de Progreso
		var prog_lbl = Label.new()
		prog_lbl.add_theme_font_size_override("font_size", 10)
		
		# Obtener coordenadas si existen
		var target_x = quest.get("targetX")
		var target_y = quest.get("targetY")
		var has_coords = target_x != null and target_y != null
		
		if is_completed:
			prog_lbl.text = "Progreso: Completada"
			prog_lbl.modulate = Color.GREEN
		elif is_active:
			var target_str = ""
			if target_type == "kill":
				# Buscar nombre de monstruo del config local
				var monster_name = "Enemigos"
				if NetworkManager and NetworkManager.server_config.has("enemyModels"):
					var em = NetworkManager.server_config["enemyModels"]
					if em.has(str(quest.get("targetId"))):
						monster_name = em[str(quest.get("targetId"))].get("name", "Enemigo")
				target_str = "Eliminar " + monster_name + ": " + str(progress) + " / " + str(target_amount)
			elif target_type == "collect":
				target_str = "Recolectar ítems: " + str(progress) + " / " + str(target_amount)
			elif target_type == "explore":
				if has_coords:
					target_str = "Explorar Sector " + str(quest.get("targetId")) + " en (" + str(target_x) + ", " + str(target_y) + "): " + ("Punto Alcanzado" if progress >= 1 else "Pendiente")
				else:
					target_str = "Explorar Sector " + str(quest.get("targetId")) + ": " + ("Sector Consultado" if progress >= 1 else "Pendiente")
			
			prog_lbl.text = "Progreso: " + target_str
			prog_lbl.modulate = Color.GOLD if (progress >= target_amount or (target_type == "explore" and progress >= 1)) else Color.CYAN
		else:
			var req_str = ""
			if target_type == "kill":
				var monster_name = "enemigos"
				if NetworkManager and NetworkManager.server_config.has("enemyModels"):
					var em = NetworkManager.server_config["enemyModels"]
					if em.has(str(quest.get("targetId"))):
						monster_name = em[str(quest.get("targetId"))].get("name", "enemigo")
				req_str = "Eliminar " + str(target_amount) + " " + monster_name + "."
			elif target_type == "collect": 
				req_str = "Recolectar " + str(target_amount) + " unidades de un ítem."
			elif target_type == "explore":
				if has_coords:
					req_str = "Viajar al Sector " + str(quest.get("targetId")) + " e ir a las coordenadas (" + str(target_x) + ", " + str(target_y) + ")."
				else:
					req_str = "Viajar al Sector " + str(quest.get("targetId")) + "."
			
			prog_lbl.text = "Requisito: " + req_str
			prog_lbl.modulate = Color(0.6, 0.6, 0.6)
		info_vb.add_child(prog_lbl)
		
		# v600.2: Aviso de portal sellado por esta misión ("zona" o "zona|etiqueta")
		var gate_zone = quest.get("portalGate", "")
		if str(gate_zone) != "":
			var gate_parts = str(gate_zone).split("|")
			var gate_zone_id = gate_parts[0]
			var gate_display = "Sector " + str(gate_zone_id)
			if NetworkManager and NetworkManager.server_config.has("mapsConfig"):
				var maps_cfg = NetworkManager.server_config["mapsConfig"]
				if maps_cfg.has(str(gate_zone_id)):
					gate_display = str(maps_cfg[str(gate_zone_id)].get("name", gate_display))
			var gate_suffix = ""
			if gate_parts.size() > 1 and str(gate_parts[1]) != "":
				gate_suffix = " · Portal \"" + "|".join(gate_parts.slice(1)) + "\""
			var gate_lbl = Label.new()
			if not is_completed:
				gate_lbl.text = "🚪 PORTAL SELLADO: " + gate_display + gate_suffix + " hasta completar esta misión"
				gate_lbl.modulate = Color(1.0, 0.4, 0.4)
			else:
				gate_lbl.text = "🚪 Al completar: desbloquea el portal a " + gate_display + gate_suffix
				gate_lbl.modulate = Color(0.4, 1.0, 0.5)
			gate_lbl.add_theme_font_size_override("font_size", 8)
			info_vb.add_child(gate_lbl)
		
		# Info Recompensas
		var rewards_vb = VBoxContainer.new()
		rewards_vb.custom_minimum_size.x = 220
		rewards_vb.alignment = BoxContainer.ALIGNMENT_CENTER
		main_hb.add_child(rewards_vb)
		
		var rew_title = Label.new()
		rew_title.text = "Recompensas:"
		rew_title.add_theme_font_size_override("font_size", 9)
		rew_title.modulate = Color(0.7, 0.7, 0.7)
		rewards_vb.add_child(rew_title)
		
		var rew_hb = HBoxContainer.new()
		rew_hb.add_theme_constant_override("separation", 15)
		rewards_vb.add_child(rew_hb)
		
		if int(reward.get("exp", 0)) > 0:
			var exp_lbl = Label.new()
			exp_lbl.text = "EXP: +" + str(int(reward.get("exp", 0)))
			exp_lbl.modulate = Color(0, 0.8, 1)
			exp_lbl.add_theme_font_size_override("font_size", 9)
			rew_hb.add_child(exp_lbl)
			
		if int(reward.get("hubs", 0)) > 0:
			var hubs_lbl = Label.new()
			hubs_lbl.text = "HUBS: +" + str(int(reward.get("hubs", 0)))
			hubs_lbl.modulate = Color.CYAN
			hubs_lbl.add_theme_font_size_override("font_size", 9)
			rew_hb.add_child(hubs_lbl)
			
		if int(reward.get("ohcu", 0)) > 0:
			var ohcu_lbl = Label.new()
			ohcu_lbl.text = "OHCU: +" + str(int(reward.get("ohcu", 0)))
			ohcu_lbl.modulate = Color.MEDIUM_PURPLE
			ohcu_lbl.add_theme_font_size_override("font_size", 9)
			rew_hb.add_child(ohcu_lbl)
			
		# Renderizar ítems extras en recompensas si existen
		var items_reward = reward.get("items", [])
		if items_reward.size() > 0:
			var items_lbl = Label.new()
			items_lbl.text = "+" + str(items_reward.size()) + " Ítems"
			items_lbl.modulate = Color.ORANGE
			items_lbl.add_theme_font_size_override("font_size", 9)
			rew_hb.add_child(items_lbl)
			
		# v600.0: Mostrar desbloqueos de recompensa (🔓 portales, armas, habilidades, talentos)
		var unlocks_reward = reward.get("unlocks", [])
		if unlocks_reward.size() > 0:
			var unlocks_vb = VBoxContainer.new()
			unlocks_vb.add_theme_constant_override("separation", 3)
			rewards_vb.add_child(unlocks_vb)
			for u in unlocks_reward:
				if typeof(u) != TYPE_DICTIONARY: continue
				var u_lbl = Label.new()
				u_lbl.text = "🔓 " + str(u.get("label", "Desbloqueo especial"))
				u_lbl.modulate = Color(1.0, 0.84, 0.0)
				u_lbl.add_theme_font_size_override("font_size", 9)
				unlocks_vb.add_child(u_lbl)
			
		# Columna Botón Acción
		var btn_container = VBoxContainer.new()
		btn_container.custom_minimum_size.x = 140
		btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
		btn_container.add_theme_constant_override("separation", 8)
		main_hb.add_child(btn_container)
		
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(130, 40)
		btn.add_theme_font_size_override("font_size", 10)
		btn_container.add_child(btn)
		
		if is_completed:
			btn.text = "COMPLETADA"
			btn.disabled = true
		elif is_active:
			# Para exploraciones con coordenadas, se requiere que esté en el punto exacto (valida el server al reclamar)
			var meets_condition = false
			if target_type == "explore" and has_coords:
				# Mostramos como posible cobrar para que el piloto intente cobrarlo en el mapa/punto
				meets_condition = true 
			else:
				meets_condition = progress >= target_amount or (target_type == "explore" and progress >= 1)
				
			if meets_condition:
				btn.text = "COBRAR PREMIO"
				var sb_cob = StyleBoxFlat.new()
				sb_cob.bg_color = Color.DARK_GREEN
				sb_cob.border_width_bottom = 2
				sb_cob.border_color = Color.GREEN
				btn.add_theme_stylebox_override("normal", sb_cob)
				btn.pressed.connect(func():
					_on_claim_pressed(quest, q_id)
				)
			else:
				btn.text = "EN PROGRESO"
				btn.disabled = true
				
			# Botón para abandonar/cancelar misión en cualquier lugar
			var btn_abandon = Button.new()
			btn_abandon.text = "ABANDONAR"
			btn_abandon.custom_minimum_size = Vector2(130, 28)
			btn_abandon.add_theme_font_size_override("font_size", 8)
			var sb_ab = StyleBoxFlat.new()
			sb_ab.bg_color = Color(0.4, 0.1, 0.1, 0.8)
			sb_ab.border_width_bottom = 1
			sb_ab.border_color = Color.RED
			btn_abandon.add_theme_stylebox_override("normal", sb_ab)
			btn_abandon.pressed.connect(func():
				NetworkManager.send_event("abandonQuest", {"questId": q_id})
			)
			btn_container.add_child(btn_abandon)
		else:
			btn.text = "ACEPTAR MISIÓN"
			var sb_acc = StyleBoxFlat.new()
			sb_acc.bg_color = Color(0, 0.3, 0.4, 0.8)
			btn.add_theme_stylebox_override("normal", sb_acc)
			btn.pressed.connect(func():
				NetworkManager.send_event("acceptQuest", {"questId": q_id})
			)
			
		# Margen interno derecho
		var margin_right = Control.new()
		margin_right.custom_minimum_size.x = 8
		main_hb.add_child(margin_right)

# --- RECLAMO CON SELECCION DE RECOMPENSA ---
func _on_claim_pressed(quest, q_id):
	var reward = quest.get("reward", {})
	var pool = reward.get("items", [])
	var sel_count = int(reward.get("selectableCount", 0))
	# Si la recompensa es por eleccion (0 < sel_count < cantidad de items), abrimos el selector
	if sel_count > 0 and sel_count < pool.size():
		_open_reward_selector(q_id, pool, sel_count)
	else:
		NetworkManager.send_event("claimQuestReward", {"questId": q_id})

# Resuelve el nombre visible de un item a partir de los catalogos del server_config
func _resolve_item_name(id) -> String:
	var cfg = NetworkManager.server_config if NetworkManager else {}
	if typeof(cfg) != TYPE_DICTIONARY:
		return "Ítem " + str(id)
	var shop = cfg.get("shopItems", {})
	for key in ["weapons", "shields", "engines", "extra", "resources"]:
		if shop.has(key) and typeof(shop[key]) == TYPE_ARRAY:
			for it in shop[key]:
				if typeof(it) == TYPE_DICTIONARY and str(it.get("id", "")) == str(id):
					return str(it.get("name", id))
	if shop.has("ammo") and typeof(shop["ammo"]) == TYPE_DICTIONARY:
		for t in shop["ammo"].keys():
			var arr = shop["ammo"][t]
			if typeof(arr) == TYPE_ARRAY:
				for it in arr:
					if typeof(it) == TYPE_DICTIONARY and str(it.get("id", "")) == str(id):
						return str(it.get("name", id))
	if cfg.has("craftingResources") and typeof(cfg["craftingResources"]) == TYPE_ARRAY:
		for it in cfg["craftingResources"]:
			if typeof(it) == TYPE_DICTIONARY and str(it.get("id", "")) == str(id):
				return str(it.get("name", id))
	return "Ítem " + str(id)

# Abre un popup donde el jugador elige sel_count items del pozo de recompensa
func _open_reward_selector(q_id, pool, sel_count):
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	get_tree().root.add_child(overlay)

	var cc = CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(cc)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 500)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.06, 0.12, 0.98)
	sb.border_color = Color.CYAN
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	panel.add_theme_stylebox_override("panel", sb)
	cc.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.add_theme_constant_override("margin_left", 16)
	vbox.add_theme_constant_override("margin_right", 16)
	vbox.add_theme_constant_override("margin_top", 16)
	vbox.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "🎁 ELIGE TU RECOMPENSA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	var instr = Label.new()
	instr.text = "Selecciona " + str(sel_count) + " de " + str(pool.size()) + " items disponibles:"
	instr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instr.add_theme_font_size_override("font_size", 11)
	instr.modulate.a = 0.85
	vbox.add_child(instr)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var grid = VBoxContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("separation", 6)
	scroll.add_child(grid)

	var selected = []  # indices elegidos

	var confirm_btn = Button.new()
	confirm_btn.text = "CONFIRMAR (0/" + str(sel_count) + ")"
	confirm_btn.disabled = true
	confirm_btn.custom_minimum_size = Vector2(180, 38)
	var sb_conf = StyleBoxFlat.new()
	sb_conf.bg_color = Color.DARK_GREEN
	sb_conf.border_color = Color.GREEN
	sb_conf.border_width_bottom = 2
	confirm_btn.add_theme_stylebox_override("normal", sb_conf)

	for i in range(pool.size()):
		var it = pool[i]
		var id = str(it.get("id", ""))
		var qty = int(it.get("qty", 1))
		var item_name = _resolve_item_name(id)
		var b = Button.new()
		b.text = item_name + "   x" + str(qty)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 40)
		b.toggled.connect(_on_reward_item_toggled.bind(b, i, sel_count, selected, confirm_btn))
		grid.add_child(b)

	var footer = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 15)
	vbox.add_child(footer)

	var cancel = Button.new()
	cancel.text = "CANCELAR"
	cancel.custom_minimum_size = Vector2(140, 38)
	cancel.pressed.connect(func(): overlay.queue_free())
	footer.add_child(cancel)

	confirm_btn.pressed.connect(func():
		if selected.size() != sel_count:
			return
		NetworkManager.send_event("claimQuestReward", {"questId": q_id, "selection": selected.duplicate()})
		overlay.queue_free()
	)
	footer.add_child(confirm_btn)

# Callback de cada boton del selector de recompensa
func _on_reward_item_toggled(on, b, idx, sel_count, selected, confirm_btn):
	if on and not selected.has(idx):
		if selected.size() >= sel_count:
			b.button_pressed = false
			return
		selected.append(idx)
	elif not on and selected.has(idx):
		selected.erase(idx)
	confirm_btn.disabled = selected.size() != sel_count
	confirm_btn.text = "CONFIRMAR (" + str(selected.size()) + "/" + str(sel_count) + ")"

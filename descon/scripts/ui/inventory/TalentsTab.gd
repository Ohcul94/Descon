extends Control

# TalentsTab.gd - ÁRBOL DE TALENTOS VISUAL (v3.0)
# - Left-click: agregar punto pendiente
# - Right-click: quitar punto pendiente (solo los no guardados)
# - Zoom hacia mouse con rueda
# - Guardar/Cancelar puntos pendientes
# - Reset para devolver puntos ya guardados

var inv_main = null
var talent_system = null

# Config del servidor
var talents_config: Dictionary = {}
var talents_list: Array = []
var nodes_data: Dictionary = {}
var connections_data: Array = []
var locked_config: Array = []

# Estado del jugador (guardado en servidor)
var player_skill_tree: Dictionary = {}
var skill_points: int = 0

# Puntos pendientes (no guardados aún): { "talent_id": cantidad_pendiente }
var pending_points: Dictionary = {}
var total_pending_cost: int = 0

# Canvas state
var zoom_level: float = 1.0
var pan_offset: Vector2 = Vector2.ZERO
var is_panning: bool = false
var pan_start: Vector2 = Vector2.ZERO
var hovered_node_id: String = ""

# UI references
var tree_canvas: Control
var points_label: Label
var pending_label: Label
var save_btn: Button
var cancel_btn: Button
var reset_btn: Button
var summary_btn: Button
var summary_panel: PanelContainer
var summary_rtl: RichTextLabel
var summary_header_label: Label
var tooltip_rtl: RichTextLabel
var tooltip_panel: PanelContainer

# Categorías dinámicas
var categories_list: Array = []

# Colores (dinámicos desde config)
var cat_colors: Dictionary = {}
var cat_colors_dark: Dictionary = {}

# Tamaños de nodo
var node_types: Dictionary = {
	"small": {"radius": 22.0, "border": 2.0, "glow": 0.3},
	"notable": {"radius": 30.0, "border": 3.0, "glow": 0.6},
	"keystone": {"radius": 40.0, "border": 4.0, "glow": 1.0}
}

func setup(p_inv_main):
	inv_main = p_inv_main
	mouse_filter = Control.MOUSE_FILTER_PASS

func update_ui():
	if not inv_main:
		return

	talent_system = get_tree().get_first_node_in_group("talent_system")
	if not is_instance_valid(talent_system):
		var p = get_tree().get_first_node_in_group("player")
		if p:
			talent_system = p.get_node_or_null("TalentSystem")

	# Limpiar
	for n in get_children():
		remove_child(n)
		n.queue_free()

	# Reset pending
	pending_points.clear()
	total_pending_cost = 0

	# Cargar config
	_load_talents_config()

	if not is_instance_valid(talent_system):
		var err = Label.new()
		err.text = "ERROR: SISTEMA DE TALENTOS NO INICIALIZADO"
		err.horizontal_alignment = 1
		err.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		add_child(err)
		return

	_build_ui()

func _load_talents_config():
	if NetworkManager and NetworkManager.server_config:
		var tc = NetworkManager.server_config.get("talentsConfig", {})
		talents_config = tc
		talents_list = tc.get("talents", [])
		nodes_data = tc.get("nodes", {})
		connections_data = tc.get("connections", [])
		locked_config = NetworkManager.server_config.get("talentsLockedConfig", [])
		# Cargar categorías dinámicas
		_load_categories_from_config(tc)

	if is_instance_valid(talent_system):
		player_skill_tree = talent_system.skill_tree.duplicate(true)
		skill_points = talent_system.skill_points

func _load_categories_from_config(tc: Dictionary):
	cat_colors.clear()
	cat_colors_dark.clear()
	var categories = tc.get("categories", [])
	# Si no hay categorías en config, usar las defaults
	if categories.size() == 0:
		categories = [
			{"id": "engineering", "name": "Ingeniería", "color": "#00d2ff", "emoji": "🛠️"},
			{"id": "combat", "name": "Combate", "color": "#ff3131", "emoji": "⚔️"},
			{"id": "science", "name": "Ciencia", "color": "#be31ff", "emoji": "🔬"}
		]
	categories_list = categories.duplicate(true)
	for cat in categories_list:
		var id = cat.get("id", "")
		var hex = cat.get("color", "#888888")
		if id != "":
			cat_colors[id] = Color.html(hex)
			var c = Color.html(hex)
			cat_colors_dark[id] = Color(c.r * 0.3, c.g * 0.3, c.b * 0.3)

func _build_ui():
	# Evitar que cualquier elemento de la pestaña desborde hacia los lados
	clip_contents = true

	var master_v = VBoxContainer.new()
	master_v.name = "TalentsMasterVBox"
	master_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	master_v.mouse_filter = Control.MOUSE_FILTER_PASS
	master_v.clip_contents = true
	add_child(master_v)

	# ═══ Header ═══
	var header = HBoxContainer.new()
	header.name = "TalentsHeader"
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	header.add_theme_constant_override("separation", 6)
	master_v.add_child(header)

	points_label = Label.new()
	points_label.add_theme_font_size_override("font_size", 13)
	header.add_child(points_label)

	var sep1 = VSeparator.new()
	sep1.custom_minimum_size.x = 2
	header.add_child(sep1)

	pending_label = Label.new()
	pending_label.add_theme_font_size_override("font_size", 12)
	pending_label.visible = false
	header.add_child(pending_label)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	# Botón de resumen de beneficios (texto compacto para no desbordar)
	summary_btn = Button.new()
	summary_btn.text = "📊 RESUMEN"
	summary_btn.tooltip_text = "Ver desglose detallado de bonificaciones activas del árbol"
	summary_btn.pressed.connect(_toggle_summary_panel)
	header.add_child(summary_btn)

	# Botones de acción
	save_btn = Button.new()
	save_btn.text = "💾 GUARDAR"
	save_btn.visible = false
	save_btn.pressed.connect(_on_save_pressed)
	header.add_child(save_btn)

	cancel_btn = Button.new()
	cancel_btn.text = "❌ CANCELAR"
	cancel_btn.visible = false
	cancel_btn.pressed.connect(_on_cancel_pressed)
	header.add_child(cancel_btn)

	reset_btn = Button.new()
	reset_btn.text = "🔄 RESET (5K)"
	reset_btn.tooltip_text = "Restablecer todos los talentos por 5.000 OHCU"
	reset_btn.pressed.connect(_on_reset_pressed)
	header.add_child(reset_btn)

	# ═══ Contenedor Horizontal para Canvas + Panel Lateral (evita overflow fuera de ventana) ═══
	var body_h = HBoxContainer.new()
	body_h.name = "BodyHBox"
	body_h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_h.mouse_filter = Control.MOUSE_FILTER_PASS
	body_h.add_theme_constant_override("separation", 6)
	body_h.clip_contents = true
	master_v.add_child(body_h)

	# ═══ Canvas ═══
	tree_canvas = Control.new()
	tree_canvas.name = "TreeCanvas"
	tree_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	tree_canvas.clip_contents = true
	body_h.add_child(tree_canvas)

	tree_canvas.draw.connect(_on_tree_draw)
	tree_canvas.gui_input.connect(_on_tree_input)
	tree_canvas.mouse_exited.connect(_on_tree_mouse_exit)

	# Centrar cámara en el origen después del primer resize
	tree_canvas.resized.connect(_center_camera_on_origin)
	call_deferred("_center_camera_on_origin")

	# ═══ Tooltip (hijo de tree_canvas para que la posición sea correcta) ═══
	tooltip_panel = PanelContainer.new()
	tooltip_panel.name = "TooltipPanel"
	tooltip_panel.visible = false
	tooltip_panel.z_index = 99
	tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tooltip_style = StyleBoxFlat.new()
	tooltip_style.bg_color = Color(0.04, 0.05, 0.08, 0.94)
	tooltip_style.border_width_left = 0
	tooltip_style.border_width_right = 0
	tooltip_style.border_width_top = 0
	tooltip_style.border_width_bottom = 0
	tooltip_style.content_margin_left = 14
	tooltip_style.content_margin_right = 14
	tooltip_style.content_margin_top = 10
	tooltip_style.content_margin_bottom = 10
	tooltip_style.shadow_color = Color(0, 0, 0, 0.5)
	tooltip_style.shadow_size = 12
	tooltip_style.shadow_offset = Vector2(0, 4)
	tooltip_panel.add_theme_stylebox_override("panel", tooltip_style)
	tree_canvas.add_child(tooltip_panel)

	tooltip_rtl = RichTextLabel.new()
	tooltip_rtl.name = "Tooltip"
	tooltip_rtl.bbcode_enabled = true
	tooltip_rtl.fit_content = true
	tooltip_rtl.visible = false
	tooltip_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_rtl.z_index = 100
	tooltip_rtl.custom_minimum_size = Vector2(260, 0)
	tooltip_rtl.add_theme_font_size_override("normal_font_size", 13)
	tooltip_rtl.add_theme_color_override("default_color", Color(0.85, 0.85, 0.85))
	tooltip_panel.add_child(tooltip_rtl)

	# ═══ Panel Lateral de Resumen de Beneficios (contenido 100% dentro de la ventana) ═══
	summary_panel = PanelContainer.new()
	summary_panel.name = "SummaryPanel"
	summary_panel.visible = false
	summary_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	summary_panel.custom_minimum_size = Vector2(280, 0)
	summary_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var sum_style = StyleBoxFlat.new()
	sum_style.bg_color = Color(0.03, 0.05, 0.09, 0.96)
	sum_style.border_width_left = 2
	sum_style.border_width_top = 1
	sum_style.border_width_right = 1
	sum_style.border_width_bottom = 1
	sum_style.border_color = Color(0, 0.82, 1, 0.4)
	sum_style.corner_radius_top_left = 6
	sum_style.corner_radius_bottom_left = 6
	sum_style.corner_radius_top_right = 6
	sum_style.corner_radius_bottom_right = 6
	sum_style.content_margin_left = 12
	sum_style.content_margin_right = 12
	sum_style.content_margin_top = 10
	sum_style.content_margin_bottom = 10
	sum_style.shadow_color = Color(0, 0, 0, 0.5)
	sum_style.shadow_size = 10
	summary_panel.add_theme_stylebox_override("panel", sum_style)
	body_h.add_child(summary_panel)

	var sum_vbox = VBoxContainer.new()
	sum_vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	sum_vbox.add_theme_constant_override("separation", 8)
	summary_panel.add_child(sum_vbox)

	var sum_top = HBoxContainer.new()
	sum_top.mouse_filter = Control.MOUSE_FILTER_PASS
	sum_vbox.add_child(sum_top)

	var sum_title = Label.new()
	sum_title.text = "📊 BENEFICIOS DEL ÁRBOL"
	sum_title.add_theme_font_size_override("font_size", 14)
	sum_title.modulate = Color(0, 0.82, 1)
	sum_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sum_top.add_child(sum_title)

	var sum_close_btn = Button.new()
	sum_close_btn.text = "✕"
	sum_close_btn.custom_minimum_size = Vector2(28, 24)
	sum_close_btn.pressed.connect(func(): _set_summary_panel_visible(false))
	sum_top.add_child(sum_close_btn)

	summary_header_label = Label.new()
	summary_header_label.add_theme_font_size_override("font_size", 11)
	summary_header_label.modulate = Color(0.7, 0.75, 0.85)
	sum_vbox.add_child(summary_header_label)

	var sum_sep = HSeparator.new()
	sum_sep.modulate = Color(0, 0.82, 1, 0.3)
	sum_vbox.add_child(sum_sep)

	var sum_scroll = ScrollContainer.new()
	sum_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sum_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sum_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sum_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	sum_vbox.add_child(sum_scroll)

	summary_rtl = RichTextLabel.new()
	summary_rtl.name = "SummaryRTL"
	summary_rtl.bbcode_enabled = true
	summary_rtl.fit_content = true
	summary_rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_rtl.mouse_filter = Control.MOUSE_FILTER_PASS
	summary_rtl.add_theme_font_size_override("normal_font_size", 12)
	sum_scroll.add_child(summary_rtl)

	_update_header_display()
	tree_canvas.queue_redraw()

# ═══════════════════════════════════════════════════════
# HEADER DISPLAY
# ═══════════════════════════════════════════════════════

func _update_header_display():
	if not points_label:
		return

	var available = skill_points - total_pending_cost
	points_label.text = "⚡ PUNTOS: " + str(skill_points) + (" (disp: " + str(available) + ")" if available < skill_points else "")
	points_label.modulate = Color.GREEN if skill_points > 0 else Color.GRAY

	if total_pending_cost > 0:
		pending_label.text = "📝 Pend: " + str(total_pending_cost) + " pts"
		pending_label.modulate = Color("ffd700")
		pending_label.visible = true
		save_btn.visible = true
		cancel_btn.visible = true
	else:
		pending_label.visible = false
		save_btn.visible = false
		cancel_btn.visible = false

	if summary_panel and summary_panel.visible:
		_update_summary_display()

# ═══════════════════════════════════════════════════════
# RESUMEN DETALLADO DE BENEFICIOS DEL ÁRBOL
# ═══════════════════════════════════════════════════════

func _toggle_summary_panel():
	if not summary_panel:
		return
	_set_summary_panel_visible(not summary_panel.visible)

func _set_summary_panel_visible(v: bool):
	if not summary_panel:
		return
	summary_panel.visible = v
	if summary_btn:
		if v:
			summary_btn.text = "📊 CERRAR"
			summary_btn.modulate = Color(0, 0.82, 1)
		else:
			summary_btn.text = "📊 RESUMEN"
			summary_btn.modulate = Color.WHITE
	if v:
		_update_summary_display()
	call_deferred("_clamp_pan")
	if tree_canvas:
		tree_canvas.queue_redraw()

# ═══════════════════════════════════════════════════════
# FORMATEO NUMÉRICO LIMPIO (sin .0 innecesario)
# ═══════════════════════════════════════════════════════

func _format_clean_number(val: float, max_decimals: int = 2) -> String:
	var factor = pow(10.0, max_decimals)
	var rounded = round(val * factor) / factor
	# Si es entero exacto (ej. 10.0 -> "10")
	if is_equal_approx(rounded, round(rounded)):
		return str(int(round(rounded)))
	# Si tiene decimales significativos (ej. 10.1, 10.25)
	var s = ("%." + str(max_decimals) + "f") % rounded
	if "." in s:
		while s.ends_with("0"):
			s = s.substr(0, s.length() - 1)
		if s.ends_with("."):
			s = s.substr(0, s.length() - 1)
	return s

func _format_stat_value(val: float, is_flat: bool = false, show_plus: bool = true) -> String:
	var prefix = ("+" if val > 0.0001 and show_plus else ("-" if val < -0.0001 else ""))
	var abs_val = abs(val)
	if is_flat:
		return prefix + _format_clean_number(abs_val, 2) + "s"
	else:
		return prefix + _format_clean_number(abs_val * 100.0, 2) + "%"

func _update_summary_display():
	if not summary_rtl or not is_instance_valid(summary_rtl):
		return

	# Metadatos para presentación clara y limpia de cada efecto
	var effect_meta = {
		"hp_pct": {"name": "Vida Máxima", "icon": "🛡️", "unit": "%"},
		"sh_pct": {"name": "Escudo Máximo", "icon": "🔵", "unit": "%"},
		"hp_regen": {"name": "Regen. de Vida", "icon": "🔧", "unit": "%"},
		"shield_regen": {"name": "Regen. de Escudo", "icon": "🔋", "unit": "%"},
		"armor_pct": {"name": "Armadura Total", "icon": "⚙️", "unit": "%"},
		"energy_efficiency": {"name": "Eficiencia de Energía", "icon": "⚛️", "unit": "%"},
		"repair_cost_reduction": {"name": "Costo de Reparación", "icon": "💸", "unit": "%"},
		"stability": {"name": "Estabilidad de Vuelo", "icon": "🛸", "unit": "%"},
		"laser_dmg_pct": {"name": "Daño Láser", "icon": "🔫", "unit": "%"},
		"crit_chance": {"name": "Probabilidad Crítica", "icon": "🎯", "unit": "%"},
		"crit_dmg": {"name": "Daño Crítico", "icon": "🔥", "unit": "%"},
		"ammo_bonus_pct": {"name": "Bonus de Munición", "icon": "💣", "unit": "%"},
		"accuracy_pct": {"name": "Puntería de Disparo", "icon": "👁️", "unit": "%"},
		"ignore_shield_pct": {"name": "Perforación de Escudo", "icon": "⚡", "unit": "%"},
		"fire_rate_pct": {"name": "Cadencia de Fuego", "icon": "⚔️", "unit": "%"},
		"evasion_pct": {"name": "Evasión en Combate", "icon": "💨", "unit": "%"},
		"speed_pct": {"name": "Velocidad Base", "icon": "🚀", "unit": "%"},
		"minimap_range": {"name": "Rango de Radar", "icon": "📡", "unit": "%"},
		"ohcu_kill_bonus": {"name": "Bonus OHCU por Bajas", "icon": "💎", "unit": "%"},
		"shop_discount": {"name": "Descuento en Tiendas", "icon": "🏪", "unit": "%"},
		"cooldown_reduction": {"name": "Reducción Enfriamiento", "icon": "❄️", "unit": "%"},
		"cooldown_reduction_flat": {"name": "Reducción Enfriamiento (Fijo)", "icon": "⏱️", "unit": "s"},
		"cast_time_reduction": {"name": "Reducción Tiempo Cast", "icon": "⚡", "unit": "%"},
		"cast_time_reduction_flat": {"name": "Reducción Tiempo Cast (Fijo)", "icon": "⏱️", "unit": "s"},
		"group_bonus": {"name": "Bonus en Escuadrón", "icon": "👥", "unit": "%"},
		"boss_loot_bonus": {"name": "Botín de Jefes", "icon": "👑", "unit": "%"},
		"dash_distance": {"name": "Distancia de Dash", "icon": "🌀", "unit": "%"}
	}

	var saved_effects: Dictionary = {}
	var pend_effects: Dictionary = {}
	var active_by_cat: Dictionary = {}
	var total_points_spent: int = 0
	var total_active_talents: int = 0

	for t in talents_list:
		var tid = t.get("id", "")
		var saved = _get_saved_level(tid)
		var pend = pending_points.get(tid, 0)
		var total = saved + pend
		if total <= 0:
			continue

		total_points_spent += total
		total_active_talents += 1

		var cat = t.get("category", "general")
		if not active_by_cat.has(cat):
			active_by_cat[cat] = []
		active_by_cat[cat].append({
			"talent": t,
			"saved": int(saved),
			"pend": int(pend),
			"total": int(total),
			"max": int(t.get("maxLevel", 5))
		})

		var effects = t.get("effects", {})
		for key in effects:
			var base_val = float(effects[key])
			if saved > 0:
				saved_effects[key] = saved_effects.get(key, 0.0) + (base_val * saved)
			if pend > 0:
				pend_effects[key] = pend_effects.get(key, 0.0) + (base_val * pend)

	# Actualizar cabecera del panel
	if summary_header_label:
		var pend_info = " (+" + str(total_pending_cost) + " pend.)" if total_pending_cost > 0 else ""
		summary_header_label.text = "Invertidos: " + str(total_points_spent) + " pts" + pend_info + " | " + str(total_active_talents) + " talentos"

	summary_rtl.clear()
	var bb = ""

	# ═══ 1. BONIFICADORES TOTALES ACUMULADOS ═══
	bb += "[center][color=#00d2ff][font_size=13][b]⚡ BONIFICADORES TOTALES ACUMULADOS[/b][/font_size][/color][/center]\n\n"

	var all_stat_keys = []
	for k in saved_effects.keys():
		if not all_stat_keys.has(k): all_stat_keys.append(k)
	for k in pend_effects.keys():
		if not all_stat_keys.has(k): all_stat_keys.append(k)

	if all_stat_keys.is_empty():
		bb += "[center][color=#778899][i]Aún no tienes talentos activos.\nAsigna puntos en los nodos del árbol para obtener bonificaciones permanentes para tu nave.[/i][/color][/center]\n\n"
	else:
		for key in all_stat_keys:
			var s_val = saved_effects.get(key, 0.0)
			var p_val = pend_effects.get(key, 0.0)
			if abs(s_val) < 0.0001 and abs(p_val) < 0.0001:
				continue

			var meta = effect_meta.get(key, {"name": key, "icon": "✨", "unit": "%"})
			var is_flat = key.ends_with("_flat")
			var icon = meta.get("icon", "✨")
			var stat_name = meta.get("name", key)

			var s_str = _format_stat_value(s_val, is_flat, true)
			bb += icon + " [b]" + stat_name + ":[/b] [color=#10b981][b]" + s_str + "[/b][/color]"
			if abs(p_val) > 0.0001:
				var p_str = _format_stat_value(p_val, is_flat, true)
				bb += " [color=#ffd700](" + p_str + " pend.)[/color]"
			bb += "\n"

	# ═══ 2. DESGLOSE DETALLADO POR RAMAS ═══
	if not active_by_cat.is_empty():
		# Separador centrado ubicado CORRECTAMENTE entre las dos secciones
		bb += "\n[center][color=#1e2d3d]──────────────────────[/color][/center]\n\n"
		bb += "[center][color=#00d2ff][font_size=13][b]📁 DESGLOSE POR RAMAS[/b][/font_size][/color][/center]\n"

		for cat_id in active_by_cat.keys():
			var cat_obj = {}
			for c in categories_list:
				if c.get("id", "") == cat_id:
					cat_obj = c
					break

			var cat_name = cat_obj.get("name", cat_id.capitalize())
			var cat_emoji = cat_obj.get("emoji", "📁")
			var cat_color_hex = cat_obj.get("color", "#00d2ff")

			var items = active_by_cat[cat_id]
			var cat_pts = 0
			for it in items:
				cat_pts += int(it["total"])

			bb += "\n[color=" + cat_color_hex + "][b]" + cat_emoji + " " + cat_name.to_upper() + "[/b][/color] [color=#778899](" + str(cat_pts) + " pts)[/color]\n"

			for it in items:
				var t = it["talent"]
				var s = int(it["saved"])
				var p = int(it["pend"])
				var m = int(it["max"])
				var icon = t.get("icon", "🌳")
				var tname = t.get("name", "Talento")

				var lvl_str = "Nvl " + str(s)
				if p > 0:
					lvl_str += " [color=#ffd700](+" + str(p) + ")[/color]"
				lvl_str += "/" + str(m)

				bb += "  [color=#667788]•[/color] " + icon + " [b]" + tname + "[/b] — [color=#aaccff]" + lvl_str + "[/color]\n"

				# Efectos individuales de este talento multiplicados por su nivel
				var effs = t.get("effects", {})
				for ek in effs:
					var base_eff = float(effs[ek])
					var cur_eff = base_eff * it["total"]
					var em = effect_meta.get(ek, {"name": ek, "unit": "%"})
					var is_flat = ek.ends_with("_flat")
					var eff_str = _format_stat_value(cur_eff, is_flat, true)
					bb += "    [color=#556677]↳[/color] [color=#8899aa]" + em.get("name", ek) + ":[/color] [color=#10b981]" + eff_str + "[/color]\n"

	summary_rtl.append_text(bb)

# ═══════════════════════════════════════════════════════
# DIBUJADO
# ═══════════════════════════════════════════════════════

func _on_tree_draw():
	if not tree_canvas:
		return
	var sz = tree_canvas.size

	# Fondo
	tree_canvas.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.04, 0.08))

	# Rejilla
	_draw_grid(sz)

	# Centro visual + bounds
	_draw_center_and_bounds(sz)

	# Conexiones
	_draw_connections()

	# Nodos
	_draw_nodes()

func _draw_grid(sz: Vector2):
	var spacing = max(40.0 * zoom_level, 15.0)
	if spacing < 10:
		return
	var ox = fmod(pan_offset.x, spacing)
	var oy = fmod(pan_offset.y, spacing)
	var c = Color(0, 0.82, 1, 0.04)
	var x = ox
	while x < sz.x:
		tree_canvas.draw_line(Vector2(x, 0), Vector2(x, sz.y), c, 1)
		x += spacing
	var y = oy
	while y < sz.y:
		tree_canvas.draw_line(Vector2(0, y), Vector2(sz.x, y), c, 1)
		y += spacing

func _draw_center_and_bounds(_sz: Vector2):
	if nodes_data.is_empty():
		return
	var bounds = _get_node_bounds()
	var tl = _world_to_screen(bounds.position)
	var br = _world_to_screen(bounds.position + bounds.size)
	var bc = Color(0, 0.82, 1, 0.12)
	_draw_dashed_line(tl, Vector2(br.x, tl.y), bc, 1.0, 8.0, 6.0)
	_draw_dashed_line(Vector2(br.x, tl.y), br, bc, 1.0, 8.0, 6.0)
	_draw_dashed_line(br, Vector2(tl.x, br.y), bc, 1.0, 8.0, 6.0)
	_draw_dashed_line(Vector2(tl.x, br.y), tl, bc, 1.0, 8.0, 6.0)

func _draw_connections():
	for conn in connections_data:
		var from_id = conn.get("from", "")
		var to_id = conn.get("to", "")
		var fp = nodes_data.get(from_id, {})
		var tp = nodes_data.get(to_id, {})
		if fp.is_empty() or tp.is_empty():
			continue

		var from_scr = _world_to_screen(Vector2(fp.get("x", 0), fp.get("y", 0)))
		var to_scr = _world_to_screen(Vector2(tp.get("x", 0), tp.get("y", 0)))

		var from_lvl = _get_total_level(from_id)
		var to_lvl = _get_total_level(to_id)
		var active = from_lvl > 0 and to_lvl > 0

		var col = Color(0, 0.82, 1, 0.4) if active else Color(0, 0.82, 1, 0.12)
		var w = 3.0 if active else 2.0

		if not active:
			_draw_dashed_line(from_scr, to_scr, col, w, 8.0, 6.0)
		else:
			tree_canvas.draw_line(from_scr, to_scr, col, w)

func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float, dash: float, gap: float):
	var dir = (to - from).normalized()
	var total = from.distance_to(to)
	var t = 0.0
	var drawing = true
	while t < total:
		var seg = dash if drawing else gap
		var end = from + dir * min(t + seg, total)
		if drawing:
			tree_canvas.draw_line(from + dir * t, end, color, width)
		t += seg
		drawing = not drawing

func _draw_nodes():
	var time = Time.get_ticks_msec() / 1000.0

	for node_id in nodes_data:
		var nd = nodes_data[node_id]
		var scr = _world_to_screen(Vector2(nd.get("x", 0), nd.get("y", 0)))
		var talent = _get_talent_by_id(node_id)
		if talent.is_empty():
			continue

		var ntype = nd.get("nodeType", "small")
		var ti = node_types.get(ntype, node_types["small"])
		var radius = max(ti["radius"] * zoom_level, ti["radius"] * 0.35)
		var cat = talent.get("category", "engineering")
		var cc = cat_colors.get(cat, Color.CYAN)
		var ccd = cat_colors_dark.get(cat, Color.DARK_BLUE)
		var saved_lvl = _get_saved_level(node_id)
		var pend = pending_points.get(node_id, 0)
		var current_lvl = saved_lvl + pend
		var max_lvl = int(talent.get("maxLevel", 5))
		var is_maxed = current_lvl >= max_lvl
		var is_locked = _is_node_locked(node_id)
		var is_hovered = hovered_node_id == node_id
		var alpha = 0.4 if is_locked else 1.0

		# ════════════ HOVER Y GLOW PREMIUM POLIGONAL ════════════
		# Resplandor cristalino armónico con la categoría del nodo (sin colores discordantes ni formas circulares)
		var hover_rim = cc.lerp(Color.WHITE, 0.65)
		var hover_glow = cc.lerp(Color.WHITE, 0.35)

		# ════════════ SMALL (Hexágono compacto con puntas) ════════════
		if ntype == "small":
			if is_hovered:
				# Doble contorno fino hexagonal que acaricia las 6 puntas
				_draw_hexagon_border(scr, radius + 3.0 * zoom_level, Color(hover_glow.r, hover_glow.g, hover_glow.b, 0.45 * alpha), 1.4)
				_draw_hexagon_border(scr, radius + 6.0 * zoom_level, Color(cc.r, cc.g, cc.b, 0.20 * alpha), 1.0)
				_draw_hexagon(scr, radius, Color(ccd.r * 1.25, ccd.g * 1.25, ccd.b * 1.25, alpha), hover_rim, ti["border"] + 0.6)
				# Micro-destellos sutiles en los 6 vértices
				for i in range(6):
					var a = PI / 3.0 * i - PI / 6.0
					var p1 = scr + Vector2(cos(a), sin(a)) * radius
					var p2 = scr + Vector2(cos(a), sin(a)) * (radius + 3.5 * zoom_level)
					tree_canvas.draw_line(p1, p2, hover_rim, 1.2)
			else:
				_draw_hexagon(scr, radius, Color(ccd.r, ccd.g, ccd.b, alpha), Color(cc.r, cc.g, cc.b, alpha * 0.8), ti["border"])

			# Borde hexagonal punteado si tiene pendientes
			if pend > 0:
				_draw_hexagon_dashed(scr, radius + 4.0 * zoom_level, Color(1, 0.84, 0, 0.85 * alpha), 1.8)

		# ════════════ NOTABLE (Hexágono reforzado de doble borde con rayos) ════════════
		elif ntype == "notable":
			var gp = 0.7 + sin(time * 2.5) * 0.3

			if is_hovered:
				# Doble contorno hexagonal exterior fino y delicado
				_draw_hexagon_border(scr, radius + 3.5 * zoom_level, Color(hover_glow.r, hover_glow.g, hover_glow.b, 0.50 * alpha), 1.6)
				_draw_hexagon_border(scr, radius + 7.0 * zoom_level, Color(cc.r, cc.g, cc.b, 0.22 * alpha), 1.0)
				_draw_hexagon(scr, radius, Color(ccd.r * 1.25, ccd.g * 1.25, ccd.b * 1.25, alpha), hover_rim, ti["border"] + 0.6)
				# 6 rayos de energía cristalina que nacen de los vértices
				for i in range(6):
					var a = PI / 3.0 * i - PI / 6.0
					var p1 = scr + Vector2(cos(a), sin(a)) * (radius - 1 * zoom_level)
					var p2 = scr + Vector2(cos(a), sin(a)) * (radius + 6.5 * zoom_level)
					tree_canvas.draw_line(p1, p2, hover_rim, 1.8)
			else:
				# Pulso suave en aristas exteriores
				_draw_hexagon_border(scr, radius + 2 * zoom_level, Color(cc.r, cc.g, cc.b, 0.18 * gp * alpha), 1.0)
				_draw_hexagon(scr, radius, Color(ccd.r, ccd.g, ccd.b, alpha), Color(cc.r, cc.g, cc.b, alpha * 0.85), ti["border"])
				# Rayos normales en los 6 vértices
				for i in range(6):
					var a = PI / 3.0 * i - PI / 6.0
					var p1 = scr + Vector2(cos(a), sin(a)) * (radius - 2 * zoom_level)
					var p2 = scr + Vector2(cos(a), sin(a)) * (radius + 4 * zoom_level)
					tree_canvas.draw_line(p1, p2, Color(cc.r, cc.g, cc.b, 0.45 * alpha), 1.5)

			if pend > 0:
				_draw_hexagon_dashed(scr, radius + 5.5 * zoom_level, Color(1, 0.84, 0, 0.85 * alpha), 2.0)

		# ════════════ KEYSTONE (Escudo octogonal con diamantes angulares) ════════════
		elif ntype == "keystone":
			var gp = 0.6 + sin(time * 1.8) * 0.4

			if is_hovered:
				# Halo octagonal exterior delicado (sigue con exactitud las 8 puntas del escudo)
				_draw_octagon_outline(scr, radius + 4.5 * zoom_level, Color(hover_glow.r, hover_glow.g, hover_glow.b, 0.55 * alpha), 1.8)
				_draw_octagon_outline(scr, radius + 8.5 * zoom_level, Color(cc.r, cc.g, cc.b, 0.22 * alpha), 1.2)
				# Escudo octogonal principal iluminado con el color de su rama
				_draw_octagon_shield(scr, radius, Color(ccd.r * 1.25, ccd.g * 1.25, ccd.b * 1.25, alpha), hover_rim, 2.8)
			else:
				_draw_octagon_outline(scr, radius + 3 * zoom_level, Color(cc.r, cc.g, cc.b, 0.18 * gp * alpha), 1.0)
				_draw_octagon_shield(scr, radius, Color(ccd.r, ccd.g, ccd.b, alpha), Color(cc.r, cc.g, cc.b, alpha), 2.4)

			# 4 Diamantes flotantes en las diagonales (puntas de las 4 esquinas)
			for i in range(4):
				var a = PI / 2.0 * i + PI / 4.0
				var dist_d = radius + (7.0 if is_hovered else 6.0) * zoom_level
				var dx = scr.x + dist_d * cos(a)
				var dy = scr.y + dist_d * sin(a)
				var ds = (3.8 if is_hovered else 3.0) * zoom_level
				var diamond = PackedVector2Array([
					Vector2(dx, dy - ds), Vector2(dx + ds, dy),
					Vector2(dx, dy + ds), Vector2(dx - ds, dy)
				])
				var d_col = hover_rim if is_hovered else Color(cc.r, cc.g, cc.b, 0.8 * gp * alpha)
				tree_canvas.draw_colored_polygon(diamond, d_col)

			# 4 Micro-diamantes en las puntas cardinales (arriba, abajo, izquierda, derecha)
			for i in range(4):
				var a = PI / 2.0 * i
				var dist_d = radius + (5.5 if is_hovered else 5.0) * zoom_level
				var dx = scr.x + dist_d * cos(a)
				var dy = scr.y + dist_d * sin(a)
				var ds = (2.4 if is_hovered else 2.0) * zoom_level
				var diamond = PackedVector2Array([
					Vector2(dx, dy - ds), Vector2(dx + ds, dy),
					Vector2(dx, dy + ds), Vector2(dx - ds, dy)
				])
				var d_col = hover_glow if is_hovered else Color(cc.r, cc.g, cc.b, 0.55 * gp * alpha)
				tree_canvas.draw_colored_polygon(diamond, d_col)

			if pend > 0:
				_draw_octagon_outline_dashed(scr, radius + 6.5 * zoom_level, Color(1, 0.84, 0, 0.85 * alpha), 2.0)

		# ═══════ Barritas de nivel (justo debajo del nodo con margen generoso) ═══════
		var bar_h = 3.5 * zoom_level
		var bar_gap = (12.0 if ntype == "keystone" else (9.0 if ntype == "notable" else 7.0)) * zoom_level
		var bar_y = scr.y + radius + bar_gap
		_draw_level_bars(scr.x, bar_y, saved_lvl, pend, max_lvl, cc, alpha)

		# ═══════ Texto e icono ═══════
		var default_font = ThemeDB.fallback_font
		if default_font:
			# Fondo poligonal oscuro detrás del icono para nitidez
			_draw_hexagon(scr, radius * 0.52, Color(0.01, 0.02, 0.06, 0.65 * alpha), Color(cc.r, cc.g, cc.b, 0.2 * alpha), 1.0)

			# Icono (centrado manualmente)
			var icon = talent.get("icon", "🌳")
			var icon_fs = max(int(16 * zoom_level), 8) if ntype == "small" else (max(int(20 * zoom_level), 10) if ntype == "notable" else max(int(28 * zoom_level), 14))
			var icon_sz = default_font.get_string_size(icon, HORIZONTAL_ALIGNMENT_CENTER, -1, icon_fs)
			tree_canvas.draw_string(default_font, Vector2(scr.x - icon_sz.x * 0.45, scr.y + icon_sz.y * 0.35), icon, HORIZONTAL_ALIGNMENT_LEFT, -1, icon_fs, Color(1, 1, 1, alpha))

			# Nombre: ubicado de manera limpia y con espacio DEBAJO de las barritas (sin taparse jamás)
			var nm = talent.get("name", "")
			var nm_fs = max(int(9 * zoom_level), 6)
			var nm_sz = default_font.get_string_size(nm, HORIZONTAL_ALIGNMENT_CENTER, -1, nm_fs)
			var bg_pad = 2.0 * zoom_level
			var bar_bottom = bar_y + bar_h + bg_pad
			var name_gap = 5.0 * zoom_level
			var name_y = bar_bottom + name_gap + (nm_sz.y * 0.8)
			tree_canvas.draw_string(default_font, Vector2(scr.x - nm_sz.x / 2, name_y), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, nm_fs, Color(1, 1, 1, 0.85 * alpha))

			# Indicador de bloqueado (al centro del nodo si está sellado)
			if is_locked:
				var lk = "🔒"
				var lk_fs = max(int(16 * zoom_level), 6)
				var lk_sz = default_font.get_string_size(lk, HORIZONTAL_ALIGNMENT_CENTER, -1, lk_fs)
				tree_canvas.draw_string(default_font, scr - lk_sz / 2, lk, HORIZONTAL_ALIGNMENT_LEFT, -1, lk_fs, Color(1, 0.84, 0, 0.85))

func _draw_hexagon_border(center: Vector2, radius: float, color: Color, width: float):
	var pts = PackedVector2Array()
	for i in range(6):
		var a = PI / 3.0 * i - PI / 6.0
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	for i in range(6):
		tree_canvas.draw_line(pts[i], pts[(i + 1) % 6], color, width)

func _draw_hexagon(center: Vector2, radius: float, fill: Color, border: Color, bw: float):
	var pts = PackedVector2Array()
	for i in range(6):
		var a = PI / 3.0 * i - PI / 6.0
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	tree_canvas.draw_colored_polygon(pts, fill)
	for i in range(6):
		tree_canvas.draw_line(pts[i], pts[(i + 1) % 6], border, bw)

func _draw_hexagon_dashed(center: Vector2, radius: float, color: Color, width: float):
	var pts = PackedVector2Array()
	for i in range(6):
		var a = PI / 3.0 * i - PI / 6.0
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	for i in range(6):
		_draw_dashed_line(pts[i], pts[(i + 1) % 6], color, width, 4.0 * zoom_level, 3.0 * zoom_level)

func _draw_octagon_shield(center: Vector2, radius: float, fill_color: Color, border_color: Color, width: float = 2.4):
	var outer_r = radius
	var inner_r = radius * 0.82
	var pts = PackedVector2Array()
	for i in range(8):
		var ao = PI / 4.0 * i - PI / 8.0
		var ai = ao + PI / 8.0
		pts.append(center + Vector2(cos(ao), sin(ao)) * outer_r)
		pts.append(center + Vector2(cos(ai), sin(ai)) * inner_r)
	tree_canvas.draw_colored_polygon(pts, fill_color)
	for i in range(pts.size()):
		var ni = (i + 1) % pts.size()
		tree_canvas.draw_line(pts[i], pts[ni], border_color, width)

func _draw_octagon_outline(center: Vector2, radius: float, color: Color, width: float):
	var outer_r = radius
	var inner_r = radius * 0.82
	var pts = PackedVector2Array()
	for i in range(8):
		var ao = PI / 4.0 * i - PI / 8.0
		var ai = ao + PI / 8.0
		pts.append(center + Vector2(cos(ao), sin(ao)) * outer_r)
		pts.append(center + Vector2(cos(ai), sin(ai)) * inner_r)
	for i in range(pts.size()):
		tree_canvas.draw_line(pts[i], pts[(i + 1) % pts.size()], color, width)

func _draw_octagon_outline_dashed(center: Vector2, radius: float, color: Color, width: float):
	var outer_r = radius
	var inner_r = radius * 0.82
	var pts = PackedVector2Array()
	for i in range(8):
		var ao = PI / 4.0 * i - PI / 8.0
		var ai = ao + PI / 8.0
		pts.append(center + Vector2(cos(ao), sin(ao)) * outer_r)
		pts.append(center + Vector2(cos(ai), sin(ai)) * inner_r)
	for i in range(pts.size()):
		_draw_dashed_line(pts[i], pts[(i + 1) % pts.size()], color, width, 4.0 * zoom_level, 3.0 * zoom_level)

func _draw_level_bars(cx: float, y: float, saved: int, pending: int, max_val: int, cat_color: Color, alpha: float):
	if max_val <= 0:
		return
	var bw = 10.0 * zoom_level
	var bh = 3.5 * zoom_level
	var sep = 2.0 * zoom_level
	var total_w = max_val * bw + (max_val - 1) * sep
	var start_x = cx - total_w / 2.0

	# Fondo oscuro estilizado para contraste limpio
	var bg_pad = 2.0 * zoom_level
	tree_canvas.draw_rect(Rect2(start_x - bg_pad, y - bg_pad, total_w + bg_pad * 2, bh + bg_pad * 2), Color(0.02, 0.03, 0.06, 0.85 * alpha))
	tree_canvas.draw_rect(Rect2(start_x - bg_pad, y - bg_pad, total_w + bg_pad * 2, bh + bg_pad * 2), Color(0.12, 0.18, 0.28, 0.5 * alpha), false, 1.0)

	for i in range(max_val):
		var bx = start_x + i * (bw + sep)
		var col: Color
		if i < saved:
			# Nivel guardado: color sólido de categoría
			col = Color(cat_color.r, cat_color.g, cat_color.b, alpha)
		elif i < saved + pending:
			# Nivel pendiente: dorado
			col = Color(1, 0.84, 0, 0.9 * alpha)
		else:
			# Vacío
			col = Color(1, 1, 1, 0.15 * alpha)
		tree_canvas.draw_rect(Rect2(bx, y, bw, bh), col)

	# Borde punteado para barras pendientes
	if pending > 0:
		var pend_start = start_x + saved * (bw + sep)
		var pend_width = pending * bw + (pending - 1) * sep
		_draw_rect_dashed_border(Rect2(pend_start - 1, y - 1, pend_width + 2, bh + 2), Color(1, 0.84, 0, 0.8 * alpha), 1.0)

func _draw_rect_dashed_border(rect: Rect2, color: Color, width: float):
	var p0 = rect.position
	var p1 = rect.position + Vector2(rect.size.x, 0)
	var p2 = rect.position + rect.size
	var p3 = rect.position + Vector2(0, rect.size.y)
	_draw_dashed_line(p0, p1, color, width, 4, 3)
	_draw_dashed_line(p1, p2, color, width, 4, 3)
	_draw_dashed_line(p2, p3, color, width, 4, 3)
	_draw_dashed_line(p3, p0, color, width, 4, 3)

# ═══════════════════════════════════════════════════════
# INPUT
# ═══════════════════════════════════════════════════════

func _on_tree_input(event: InputEvent):
	if not tree_canvas:
		return

	# Cerrar panel de resumen con tecla ESC
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if summary_panel and summary_panel.visible:
			_set_summary_panel_visible(false)
			accept_event()
			return

	if event is InputEventMouseButton:
		# ═══ ZOOM (rueda) ═══
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, 0.1)
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, -0.1)
			return

		# ═══ LEFT CLICK: agregar punto pendiente o pan ═══
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var nid = _get_node_at_position(event.position)
				if nid != "":
					_try_add_pending(nid)
				else:
					is_panning = true
					pan_start = event.position
			else:
				is_panning = false
			return

		# ═══ RIGHT CLICK: quitar punto pendiente ═══
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var nid = _get_node_at_position(event.position)
			if nid != "":
				_try_remove_pending(nid)
			return

		# ═══ MIDDLE CLICK: reset zoom y centrar en origen ═══
		if event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
			zoom_level = 1.0
			if tree_canvas:
				pan_offset = tree_canvas.size / 2.0
			else:
				pan_offset = Vector2.ZERO
			tree_canvas.queue_redraw()
			return

	elif event is InputEventMouseMotion:
		if is_panning:
			pan_offset += event.position - pan_start
			pan_start = event.position
			_clamp_pan()
			tree_canvas.queue_redraw()
		else:
			var new_h = _get_node_at_position(event.position)
			if new_h != hovered_node_id:
				hovered_node_id = new_h
				tree_canvas.queue_redraw()
				_update_tooltip(event.position)

func _on_tree_mouse_exit():
	hovered_node_id = ""
	tree_canvas.queue_redraw()
	_hide_tooltip()

func _zoom_at(mouse_pos: Vector2, delta: float):
	var old_zoom = zoom_level
	zoom_level = clamp(zoom_level + delta, 0.2, 3.0)

	var world_under_mouse = (mouse_pos - pan_offset) / old_zoom
	pan_offset = mouse_pos - world_under_mouse * zoom_level

	_clamp_pan()
	tree_canvas.queue_redraw()

# ═══════════════════════════════════════════════════════
# PUNTOS PENDIENTES
# ═══════════════════════════════════════════════════════

func _try_add_pending(node_id: String):
	var talent = _get_talent_by_id(node_id)
	if talent.is_empty():
		return

	if _is_node_locked(node_id):
		if inv_main:
			inv_main._show_result_modal("BLOQUEADO", "Este talento requiere una misión para desbloquearse.")
		return

	var saved = _get_saved_level(node_id)
	var pend = pending_points.get(node_id, 0)
	var current = saved + pend
	var max_lvl = int(talent.get("maxLevel", 5))

	if current >= max_lvl:
		return

	if skill_points - total_pending_cost <= 0:
		return

	# Verificar requisitos de conexión
	if not _check_connection_reqs(node_id, pend):
		if inv_main:
			inv_main._show_result_modal("REQUISITO", "Necesitas invertir en un nodo conectado primero.")
		return

	pending_points[node_id] = pend + 1
	total_pending_cost += 1
	_update_header_display()
	tree_canvas.queue_redraw()

func _try_remove_pending(node_id: String):
	var pend = pending_points.get(node_id, 0)
	if pend <= 0:
		return

	pending_points[node_id] = pend - 1
	if pending_points[node_id] <= 0:
		pending_points.erase(node_id)
	total_pending_cost -= 1
	_update_header_display()
	tree_canvas.queue_redraw()

func _check_connection_reqs(node_id: String, _extra_pend: int) -> bool:
	# Verificar que al menos un nodo padre tenga nivel > 0 o pendientes
	var _has_incoming = false
	for conn in connections_data:
		if conn.get("to", "") == node_id:
			_has_incoming = true
			var from_id = conn.get("from", "")
			var from_saved = _get_saved_level(from_id)
			var from_pend = pending_points.get(from_id, 0)
			if from_saved + from_pend <= 0:
				return false

	return true  # Si no tiene conexiones de entrada, está bien

# ═══════════════════════════════════════════════════════
# ACCIONES: GUARDAR / CANCELAR / RESETEAR
# ═══════════════════════════════════════════════════════

func _on_save_pressed():
	if total_pending_cost <= 0:
		return

	if not inv_main:
		return

	var n_pend = pending_points.size()
	var msg = "¿Guardar " + str(total_pending_cost) + " punto(s) en " + str(n_pend) + " talento(s)?\n\n"
	msg += "[color=yellow]Esta acción es permanente.[/color]\n"
	msg += "Para revertir, usa el botón de RESETEAR."
	inv_main._show_modal("GUARDAR TALENTOS", msg, _do_save)

func _do_save():
	if not is_instance_valid(talent_system):
		return

	# Enviar cada punto pendiente al servidor uno por uno
	for node_id in pending_points:
		var amount = pending_points[node_id]
		var talent = _get_talent_by_id(node_id)
		if talent.is_empty():
			continue

		var cat = talent.get("category", "")
		var idx = _get_talent_index_in_category(node_id)

		for i in range(amount):
			# Esperar un frame entre cada envío para evitar flood
			talent_system.invest_point(cat, idx)

	# Limpiar pendientes
	pending_points.clear()
	total_pending_cost = 0

	# Actualizar estado local desde el talent system
	if is_instance_valid(talent_system):
		skill_points = talent_system.skill_points
		player_skill_tree = talent_system.skill_tree.duplicate(true)

	_update_header_display()
	tree_canvas.queue_redraw()

	if inv_main:
		inv_main._show_result_modal("GUARDADO", "Tus puntos de talento han sido guardados correctamente.")

func _on_cancel_pressed():
	if total_pending_cost <= 0:
		return

	pending_points.clear()
	total_pending_cost = 0
	_update_header_display()
	tree_canvas.queue_redraw()

func _on_reset_pressed():
	if not inv_main:
		return
	var msg = "¿Resetear todos tus talentos guardados?\nCosto: [color=yellow]5.000 OHCU[/color]\n[i](Se devolverán todos los puntos gastados)[/i]"
	inv_main._show_modal("RESETEAR PROGRESIÓN", msg, func():
		if inv_main.ohcu < 5000:
			inv_main._show_result_modal("FONDOS INSUFICIENTES", "Necesitas 5.000 OHCU.")
			return
		if is_instance_valid(talent_system):
			talent_system.reset_talents()
		# También limpiar pendientes
		pending_points.clear()
		total_pending_cost = 0
	)

# ═══════════════════════════════════════════════════════
# TOOLTIP
# ═══════════════════════════════════════════════════════

func _update_tooltip(screen_pos: Vector2):
	if not tooltip_rtl or not tooltip_panel:
		return
	if hovered_node_id == "":
		tooltip_rtl.visible = false
		tooltip_panel.visible = false
		return

	var talent = _get_talent_by_id(hovered_node_id)
	if talent.is_empty():
		tooltip_rtl.visible = false
		tooltip_panel.visible = false
		return

	var nd = nodes_data.get(hovered_node_id, {})
	var ntype = nd.get("nodeType", "small")
	var type_label = "Pequeño" if ntype == "small" else ("Notable" if ntype == "notable" else "Clave")
	var cat = talent.get("category", "")
	var cat_label = cat  # fallback
	var categories = talents_config.get("categories", [])
	for c in categories:
		if c.get("id", "") == cat:
			cat_label = c.get("name", cat)
			break
	var cc = cat_colors.get(cat, Color.CYAN)
	var saved = _get_saved_level(hovered_node_id)
	var pend = pending_points.get(hovered_node_id, 0)
	var max_lvl = talent.get("maxLevel", 5)
	var is_locked = _is_node_locked(hovered_node_id)

	var effect_labels = {
		"hp_pct": "Vida Máxima", "sh_pct": "Escudo Máximo",
		"hp_regen": "Regen Vida", "shield_regen": "Regen Escudo",
		"armor_pct": "Armadura", "energy_efficiency": "Eficiencia Energía",
		"repair_cost_reduction": "Costo Reparación", "stability": "Estabilidad",
		"laser_dmg_pct": "Daño Láser", "crit_chance": "Prob. Crítico",
		"crit_dmg": "Daño Crítico", "ammo_bonus_pct": "Munición Extra",
		"accuracy_pct": "Puntería", "ignore_shield_pct": "Perforación Escudo",
		"fire_rate_pct": "Cadencia", "evasion_pct": "Evasión",
		"speed_pct": "Velocidad", "minimap_range": "Rango Minimapa",
		"ohcu_kill_bonus": "Bonus OHCU", "shop_discount": "Descuento Tienda",
		"cooldown_reduction": "Reducción CD", "cooldown_reduction_flat": "Reducción CD (fijo)",
		"cast_time_reduction": "Reducción Cast", "cast_time_reduction_flat": "Reducción Cast (fijo)",
		"group_bonus": "Bonus Grupo", "boss_loot_bonus": "Loot Bosses",
		"dash_distance": "Distancia Dash"
	}
	# Efectos aplicados actualmente (solo si tiene puntos asignados o pendientes)
	var current_effects_text = ""
	if (saved + pend) > 0:
		for key in talent.get("effects", {}):
			var val = float(talent["effects"][key])
			var label = effect_labels.get(key, key)
			var is_flat = key.ends_with("_flat")
			var applied_val = val * saved
			var pend_val = val * pend
			var applied_str = _format_stat_value(applied_val, is_flat, true)
			current_effects_text += "  [color=#7ee8a0]▸[/color] " + label + ": [color=#10b981][b]" + applied_str + "[/b][/color]"
			if pend > 0:
				var p_str = _format_stat_value(pend_val, is_flat, true)
				current_effects_text += " [color=#ffd700](" + p_str + " pend.)[/color]"
			current_effects_text += "\n"

	var lock_text = "\n[color=#ff4444]🔒 BLOQUEADO[/color]" if is_locked else ""
	var pend_text = ""
	if pend > 0 and saved == 0:
		pend_text = "\n[color=#ffd700]📝 Pendiente: +" + str(pend) + " punto(s)[/color]"

	tooltip_rtl.clear()
	tooltip_rtl.append_text("[center][color=#" + cc.to_html(false) + "][font_size=16]" + talent.get("name", "") + "[/font_size][/color][/center]")
	tooltip_rtl.append_text("\n[center][color=#667788]" + cat_label.to_upper() + " — " + type_label.to_upper() + "[/color][/center]")
	tooltip_rtl.append_text("\n[center][color=#8899aa]Nivel [color=#ffffff]" + str(int(saved)) + "[/color] / " + str(int(max_lvl)) + "[/color][/center]")
	if pend > 0:
		tooltip_rtl.append_text("\n[center][color=#ffd700](+" + str(pend) + " pendiente)[/color][/center]")
	tooltip_rtl.append_text("\n[color=#556677]─────────────────────[/color]")

	# Sanitizar descripción eliminando cualquier tag residual de cursiva roto
	var raw_desc = talent.get("desc", "Sin descripción").replace("[/i]", "").replace("[i]", "")
	tooltip_rtl.append_text("\n[center][color=#8899aa][i]" + raw_desc + "[/i][/color][/center]")

	if current_effects_text != "":
		tooltip_rtl.append_text("\n[color=#556677]─────────────────────[/color]")
		tooltip_rtl.append_text("\n[color=#aabbcc][font_size=11]EFECTO APLICADO ACTUALMENTE[/font_size][/color]")
		tooltip_rtl.append_text("\n" + current_effects_text)
	tooltip_rtl.append_text(lock_text)
	tooltip_rtl.append_text(pend_text)

	tooltip_rtl.position = Vector2.ZERO
	var tip_pos = screen_pos + Vector2(20, -10)
	if tree_canvas:
		var c_sz = tree_canvas.size
		if tip_pos.x + 280 > c_sz.x:
			tip_pos.x = max(10.0, screen_pos.x - 290)
		if tip_pos.y + 220 > c_sz.y:
			tip_pos.y = max(10.0, c_sz.y - 230)
	tooltip_panel.position = tip_pos
	tooltip_panel.visible = true
	tooltip_rtl.visible = true
	# Ajustar tamaño del panel al contenido
	await get_tree().process_frame
	tooltip_panel.custom_minimum_size = tooltip_rtl.size
	tooltip_panel.size = tooltip_rtl.size

func _hide_tooltip():
	if tooltip_rtl:
		tooltip_rtl.visible = false
	if tooltip_panel:
		tooltip_panel.visible = false

# ═══════════════════════════════════════════════════════
# UTILIDADES
# ═══════════════════════════════════════════════════════

func _center_camera_on_origin():
	if tree_canvas and tree_canvas.size.x > 0:
		pan_offset = tree_canvas.size / 2.0
		tree_canvas.queue_redraw()

func _world_to_screen(world_pos: Vector2) -> Vector2:
	return world_pos * zoom_level + pan_offset

func _get_node_bounds() -> Rect2:
	if nodes_data.is_empty():
		return Rect2(Vector2(-200, -200), Vector2(400, 400))
	var min_pos = Vector2.ZERO
	var max_pos = Vector2.ZERO
	for node_id in nodes_data:
		var nd = nodes_data[node_id]
		var p = Vector2(nd.get("x", 0), nd.get("y", 0))
		min_pos.x = min(min_pos.x, p.x)
		min_pos.y = min(min_pos.y, p.y)
		max_pos.x = max(max_pos.x, p.x)
		max_pos.y = max(max_pos.y, p.y)
	var pad = 200.0
	return Rect2(min_pos - Vector2(pad, pad), (max_pos - min_pos) + Vector2(pad * 2, pad * 2))

func _get_tree_center() -> Vector2:
	return Vector2.ZERO

func _clamp_pan():
	var sz = tree_canvas.size
	# El origen (0,0) siempre debe estar visible, centrado ligeramente
	var origin_scr = _world_to_screen(Vector2.ZERO)
	var margin = sz * 0.2
	if origin_scr.x < margin.x:
		pan_offset.x += margin.x - origin_scr.x
	if origin_scr.y < margin.y:
		pan_offset.y += margin.y - origin_scr.y
	if origin_scr.x > sz.x - margin.x:
		pan_offset.x -= origin_scr.x - (sz.x - margin.x)
	if origin_scr.y > sz.y - margin.y:
		pan_offset.y -= origin_scr.y - (sz.y - margin.y)
	# También limitar por los bounds de nodos
	if nodes_data.is_empty():
		return
	var bounds = _get_node_bounds()
	var tl = bounds.position * zoom_level + pan_offset
	var br = (bounds.position + bounds.size) * zoom_level + pan_offset
	var over_l = max(0.0, tl.x - margin.x)
	var over_t = max(0.0, tl.y - margin.y)
	var over_r = max(0.0, (sz.x - margin.x) - br.x)
	var over_b = max(0.0, (sz.y - margin.y) - br.y)
	if over_l > 0:
		pan_offset.x -= over_l
	if over_t > 0:
		pan_offset.y -= over_t
	if over_r > 0:
		pan_offset.x += over_r
	if over_b > 0:
		pan_offset.y += over_b

func _get_node_at_position(screen_pos: Vector2) -> String:
	var closest_id = ""
	var closest_dist = INF
	for node_id in nodes_data:
		var nd = nodes_data[node_id]
		var scr = _world_to_screen(Vector2(nd.get("x", 0), nd.get("y", 0)))
		var ntype = nd.get("nodeType", "small")
		var ti = node_types.get(ntype, node_types["small"])
		var radius = max(ti["radius"] * zoom_level, ti["radius"] * 0.35)
		var dist = scr.distance_to(screen_pos)
		if dist <= radius + 8 and dist < closest_dist:
			closest_dist = dist
			closest_id = node_id
	return closest_id

func _get_talent_by_id(talent_id: String) -> Dictionary:
	for t in talents_list:
		if t.get("id", "") == talent_id:
			return t
	return {}

func _get_talent_index_in_category(talent_id: String) -> int:
	var talent = _get_talent_by_id(talent_id)
	if talent.is_empty():
		return -1
	var cat = talent.get("category", "")
	var idx = 0
	for t in talents_list:
		if t.get("category") == cat:
			if t.get("id") == talent_id:
				return idx
			idx += 1
	return -1

func _get_saved_level(node_id: String) -> int:
	var talent = _get_talent_by_id(node_id)
	if talent.is_empty():
		return 0
	var cat = talent.get("category", "")
	var branch = player_skill_tree.get(cat, [])
	var idx = _get_talent_index_in_category(node_id)
	if idx == -1 or idx >= branch.size():
		return 0
	return branch[idx]

func _get_total_level(node_id: String) -> int:
	return _get_saved_level(node_id) + pending_points.get(node_id, 0)

func _is_node_locked(talent_id: String) -> bool:
	var talent = _get_talent_by_id(talent_id)
	if talent.is_empty():
		return false
	var cat = talent.get("category", "")
	var idx = _get_talent_index_in_category(talent_id)
	for locked in locked_config:
		if locked.get("category") == cat and int(locked.get("index", -1)) == idx:
			if talent_system and talent_system.has_method("get_unlocks"):
				var unlocks = talent_system.get_unlocks()
				return ("talent:" + cat + ":" + str(idx)) not in unlocks
			return true
	return false

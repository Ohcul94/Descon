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
var tooltip_rtl: RichTextLabel
var tooltip_panel: PanelContainer

# Colores
var cat_colors: Dictionary = {
	"engineering": Color("00d2ff"),
	"combat": Color("ff3131"),
	"science": Color("be31ff")
}
var cat_colors_dark: Dictionary = {
	"engineering": Color("005a7a"),
	"combat": Color("7a1717"),
	"science": Color("5a1777")
}

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

	if is_instance_valid(talent_system):
		player_skill_tree = talent_system.skill_tree.duplicate(true)
		skill_points = talent_system.skill_points

func _build_ui():
	var master_v = VBoxContainer.new()
	master_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	master_v.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(master_v)

	# ═══ Header ═══
	var header = HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	header.add_theme_constant_override("separation", 12)
	master_v.add_child(header)

	points_label = Label.new()
	points_label.add_theme_font_size_override("font_size", 14)
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
	reset_btn.text = "🔄 RESETEAR (5K OHCU)"
	reset_btn.pressed.connect(_on_reset_pressed)
	header.add_child(reset_btn)

	# ═══ Canvas ═══
	tree_canvas = Control.new()
	tree_canvas.name = "TreeCanvas"
	tree_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	master_v.add_child(tree_canvas)

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
		pending_label.text = "📝 Pendientes: " + str(total_pending_cost) + " pts"
		pending_label.modulate = Color("ffd700")
		pending_label.visible = true
		save_btn.visible = true
		cancel_btn.visible = true
	else:
		pending_label.visible = false
		save_btn.visible = false
		cancel_btn.visible = false

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
		var max_lvl = talent.get("maxLevel", 5)
		var is_maxed = current_lvl >= max_lvl
		var is_locked = _is_node_locked(node_id)
		var is_hovered = hovered_node_id == node_id
		var can_add = skill_points - total_pending_cost > 0 and not is_maxed and not is_locked
		var can_remove = pend > 0
		var alpha = 0.4 if is_locked else 1.0

		# ════════════ SMALL ════════════
		if ntype == "small":
			# Glow hover
			if is_hovered:
				var glow_col = Color(cc.r, cc.g, cc.b, 0.25 * alpha)
				if can_add:
					glow_col = Color(0, 1, 0, 0.25)  # Verde = puede agregar
				elif can_remove:
					glow_col = Color(1, 0.3, 0.3, 0.25)  # Rojo = puede quitar
				tree_canvas.draw_circle(scr, radius + 8, glow_col)

			# Círculo base
			tree_canvas.draw_circle(scr, radius, Color(0.02, 0.05, 0.1, alpha))

			# Borde
			var bc = Color.WHITE if is_hovered else cc
			_draw_circle_border(scr, radius, Color(bc.r, bc.g, bc.b, alpha * 0.8), ti["border"])

			# Borde punteado si tiene pendientes
			if pend > 0:
				_draw_circle_border_dashed(scr, radius + 4 * zoom_level, Color(1, 0.84, 0, 0.7 * alpha), 2.0)

		# ════════════ NOTABLE ════════════
		elif ntype == "notable":
			var gp = 0.7 + sin(time * 2.0) * 0.3

			if is_hovered:
				var glow_col = Color(cc.r, cc.g, cc.b, 0.3 * alpha)
				if can_add:
					glow_col = Color(0, 1, 0, 0.3)
				elif can_remove:
					glow_col = Color(1, 0.3, 0.3, 0.3)
				tree_canvas.draw_circle(scr, radius + 12, glow_col)
			else:
				tree_canvas.draw_circle(scr, radius + 6, Color(cc.r, cc.g, cc.b, 0.06 * gp * alpha))

			_draw_hexagon(scr, radius, Color(ccd.r, ccd.g, ccd.b, alpha), Color(cc.r, cc.g, cc.b, alpha * 0.8), ti["border"])

			for i in range(6):
				var a = PI / 3.0 * i - PI / 6.0
				var p1 = scr + Vector2(cos(a), sin(a)) * (radius - 3 * zoom_level)
				var p2 = scr + Vector2(cos(a), sin(a)) * (radius + 4 * zoom_level)
				tree_canvas.draw_line(p1, p2, Color(cc.r, cc.g, cc.b, 0.4 * alpha), 1.5)

			if pend > 0:
				_draw_hexagon_dashed(scr, radius + 5 * zoom_level, Color(1, 0.84, 0, 0.6 * alpha), 2.0)

		# ════════════ KEYSTONE ════════════
		elif ntype == "keystone":
			var gp = 0.6 + sin(time * 1.5) * 0.4

			# Aura animada
			for i in range(12):
				var a = PI / 6.0 * i + time * 0.3
				var r1 = radius + 12 * zoom_level
				var r2 = radius + 16 * zoom_level
				var p1 = scr + Vector2(cos(a), sin(a)) * r1
				var p2 = scr + Vector2(cos(a), sin(a)) * r2
				tree_canvas.draw_line(p1, p2, Color(cc.r, cc.g, cc.b, 0.2 * gp * alpha), 1.5)

			_draw_circle_border(scr, radius + 10 * zoom_level, Color(1, 0.84, 0, 0.2 * alpha), 1.0)

			if is_hovered:
				var glow_col = Color(cc.r, cc.g, cc.b, 0.35 * alpha)
				if can_add:
					glow_col = Color(0, 1, 0, 0.35)
				elif can_remove:
					glow_col = Color(1, 0.3, 0.3, 0.35)
				tree_canvas.draw_circle(scr, radius + 14, glow_col)
			else:
				tree_canvas.draw_circle(scr, radius + 8, Color(1, 0.84, 0, 0.08 * gp * alpha))

			_draw_octagon_shield(scr, radius, cc, alpha)

			# Brillo
			tree_canvas.draw_rect(Rect2(scr.x - radius * 0.6, scr.y - radius, radius * 1.2, radius * 0.5), Color(1, 1, 1, 0.06 * alpha))

			# Diamantes
			for i in range(4):
				var a = PI / 2.0 * i + PI / 4.0
				var dx = scr.x + (radius + 6 * zoom_level) * cos(a)
				var dy = scr.y + (radius + 6 * zoom_level) * sin(a)
				var ds = 3.0 * zoom_level
				var diamond = PackedVector2Array([
					Vector2(dx, dy - ds), Vector2(dx + ds, dy),
					Vector2(dx, dy + ds), Vector2(dx - ds, dy)
				])
				tree_canvas.draw_colored_polygon(diamond, Color(cc.r, cc.g, cc.b, 0.6 * gp * alpha))

			if pend > 0:
				_draw_circle_border_dashed(scr, radius + 18 * zoom_level, Color(1, 0.84, 0, 0.5 * alpha), 2.0)

		# ═══════ Texto e icono ═══════
		var default_font = ThemeDB.fallback_font
		if default_font:
			# Icono (centrado manualmente)
			var icon = talent.get("icon", "🌳")
			var icon_fs = max(int(16 * zoom_level), 8) if ntype == "small" else (max(int(20 * zoom_level), 10) if ntype == "notable" else max(int(28 * zoom_level), 14))
			tree_canvas.draw_circle(scr, radius * 0.5, Color(0, 0, 0, 0.4 * alpha))
			var icon_sz = default_font.get_string_size(icon, HORIZONTAL_ALIGNMENT_CENTER, -1, icon_fs)
			tree_canvas.draw_string(default_font, Vector2(scr.x - icon_sz.x * 0.45, scr.y + icon_sz.y * 0.35), icon, HORIZONTAL_ALIGNMENT_LEFT, -1, icon_fs, Color(1, 1, 1, alpha))

			# Nombre
			var nm = talent.get("name", "")
			var nm_fs = max(int(9 * zoom_level), 6)
			var nm_sz = default_font.get_string_size(nm, HORIZONTAL_ALIGNMENT_CENTER, -1, nm_fs)
			tree_canvas.draw_string(default_font, Vector2(scr.x - nm_sz.x / 2, scr.y + radius + 4 * zoom_level + nm_sz.y), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, nm_fs, Color(1, 1, 1, 0.8 * alpha))

			# Indicador de nivel
			if saved_lvl > 0 or pend > 0:
				var lvl_text = str(int(saved_lvl))
				if pend > 0:
					lvl_text += "(+" + str(int(pend)) + ")"
				lvl_text += "/" + str(int(max_lvl))
				var lvl_fs = max(int(8 * zoom_level), 5)
				var lvl_sz = default_font.get_string_size(lvl_text, HORIZONTAL_ALIGNMENT_CENTER, -1, lvl_fs)
				var lvl_col = Color(1, 0.84, 0, 0.9) if is_maxed else Color(1, 1, 1, 0.7)
				if pend > 0 and saved_lvl == 0:
					lvl_col = Color(1, 0.84, 0, 0.8)
				tree_canvas.draw_string(default_font, Vector2(scr.x - lvl_sz.x / 2, scr.y - radius - 12 * zoom_level + lvl_sz.y), lvl_text, HORIZONTAL_ALIGNMENT_LEFT, -1, lvl_fs, Color(lvl_col.r, lvl_col.g, lvl_col.b, lvl_col.a * alpha))

			# Indicador de bloqueado
			if is_locked:
				var lk = "🔒"
				var lk_fs = max(int(14 * zoom_level), 5)
				var lk_sz = default_font.get_string_size(lk, HORIZONTAL_ALIGNMENT_CENTER, -1, lk_fs)
				tree_canvas.draw_string(default_font, scr - lk_sz / 2, lk, HORIZONTAL_ALIGNMENT_LEFT, -1, lk_fs, Color(1, 0.84, 0, 0.7))

		# Barras de nivel
		var bar_y = scr.y + radius + (18 if ntype == "keystone" else 14) * zoom_level
		_draw_level_bars(scr.x, bar_y, saved_lvl, pend, max_lvl, cc, alpha)

func _draw_circle_border(center: Vector2, radius: float, color: Color, width: float):
	var pts = PackedVector2Array()
	for i in range(33):
		var a = PI * 2.0 * i / 32.0
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	for i in range(32):
		tree_canvas.draw_line(pts[i], pts[i + 1], color, width)

func _draw_circle_border_dashed(center: Vector2, radius: float, color: Color, width: float):
	var pts = PackedVector2Array()
	for i in range(33):
		var a = PI * 2.0 * i / 32.0
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	for i in range(16):
		tree_canvas.draw_line(pts[i * 2], pts[i * 2 + 1], color, width)

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
	for i in range(3):
		tree_canvas.draw_line(pts[i * 2], pts[i * 2 + 1], color, width)

func _draw_octagon_shield(center: Vector2, radius: float, cat_color: Color, alpha: float):
	var outer_r = radius
	var inner_r = radius * 0.82
	var pts = PackedVector2Array()
	for i in range(8):
		var ao = PI / 4.0 * i - PI / 8.0
		var ai = ao + PI / 8.0
		pts.append(center + Vector2(cos(ao), sin(ao)) * outer_r)
		pts.append(center + Vector2(cos(ai), sin(ai)) * inner_r)
	tree_canvas.draw_colored_polygon(pts, Color(0.08, 0.14, 0.22, alpha))
	var bc = Color(1, 0.84, 0, alpha)
	for i in range(pts.size()):
		var ni = (i + 1) % pts.size()
		var t = float(i) / float(pts.size())
		var c = bc.lerp(Color(cat_color.r, cat_color.g, cat_color.b, alpha), t)
		tree_canvas.draw_line(pts[i], pts[ni], c, 3.0)

func _draw_level_bars(cx: float, y: float, saved: int, pending: int, max_val: int, cat_color: Color, alpha: float):
	var bw = 12.0 * zoom_level
	var bh = 3.0 * zoom_level
	var sep = 2.0 * zoom_level
	var total_w = max_val * bw + (max_val - 1) * sep
	var start_x = cx - total_w / 2.0

	for i in range(max_val):
		var bx = start_x + i * (bw + sep)
		var col: Color
		if i < saved:
			# Nivel guardado: color sólido de categoría
			col = Color(cat_color.r, cat_color.g, cat_color.b, alpha)
		elif i < saved + pending:
			# Nivel pendiente: dorado con borde punteado
			col = Color(1, 0.84, 0, 0.8 * alpha)
		else:
			# Vacío
			col = Color(1, 1, 1, 0.12 * alpha)
		tree_canvas.draw_rect(Rect2(bx, y, bw, bh), col)

	# Borde punteado para barras pendientes
	if pending > 0:
		var pend_start = start_x + saved * (bw + sep)
		var pend_width = pending * bw + (pending - 1) * sep
		_draw_rect_dashed_border(Rect2(pend_start - 1, y - 1, pend_width + 2, bh + 2), Color(1, 0.84, 0, 0.6 * alpha), 1.0)

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
	var max_lvl = talent.get("maxLevel", 5)

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
	var cat_labels = {"engineering": "Ingeniería", "combat": "Combate", "science": "Ciencia"}
	var cat_label = cat_labels.get(cat, cat)
	var cc = cat_colors.get(cat, Color.CYAN)
	var saved = _get_saved_level(hovered_node_id)
	var pend = pending_points.get(hovered_node_id, 0)
	var max_lvl = talent.get("maxLevel", 5)
	var is_locked = _is_node_locked(hovered_node_id)

	var effects_text = ""
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
	for key in talent.get("effects", {}):
		var val = talent["effects"][key]
		var label = effect_labels.get(key, key)
		var is_flat = key.ends_with("_flat")
		var total_val = val * max_lvl
		if is_flat:
			effects_text += "  [color=#7ee8a0]▸[/color] " + label + ": [color=#10b981]" + str(int(total_val * 100) / 100.0) + "s[/color]\n"
		else:
			var pct = int(val * 100 * max_lvl)
			effects_text += "  [color=#7ee8a0]▸[/color] " + label + ": [color=#10b981]+" + str(pct) + "%[/color]\n"

	var lock_text = "\n[color=#ff4444]🔒 BLOQUEADO[/color]" if is_locked else ""
	var pend_text = ""
	if pend > 0:
		pend_text = "\n[color=#ffd700]📝 Pendiente: +" + str(pend) + " punto(s)[/color]"

	# Barra de progreso visual
	var bar_len = 10
	var filled = clampi(int(float(saved) / float(max_lvl) * bar_len) if max_lvl > 0 else 0, 0, bar_len)
	var bar = "[color=#2a3a4a]" + "●".repeat(bar_len) + "[/color]"
	if filled > 0:
		bar = "[color=#10b981]" + "●".repeat(filled) + "[/color][color=#2a3a4a]" + "●".repeat(bar_len - filled) + "[/color]"

	tooltip_rtl.clear()
	tooltip_rtl.append_text("[center][color=#" + cc.to_html(false) + "][font_size=16]" + talent.get("name", "") + "[/font_size][/color][/center]")
	tooltip_rtl.append_text("\n[center][color=#667788]" + cat_label.to_upper() + " — " + type_label.to_upper() + "[/color][/center]")
	tooltip_rtl.append_text("\n[center]" + bar + "[/center]")
	tooltip_rtl.append_text("\n[center][color=#8899aa]Nivel [color=#ffffff]" + str(int(saved)) + "[/color] / " + str(int(max_lvl)) + "[/color][/center]")
	if pend > 0:
		tooltip_rtl.append_text("\n[center][color=#ffd700](+" + str(pend) + " pendiente)[/color][/center]")
	tooltip_rtl.append_text("\n[color=#556677]─────────────────────[/color]")
	tooltip_rtl.append_text("\n[i][color=#8899aa]" + talent.get("desc", "Sin descripción") + "[/i][/color]")
	if effects_text != "":
		tooltip_rtl.append_text("\n[color=#556677]─────────────────────[/color]")
		tooltip_rtl.append_text("\n[color=#aabbcc][font_size=11]EFECTOS POR NIVEL[/font_size][/color]")
		tooltip_rtl.append_text("\n" + effects_text)
	tooltip_rtl.append_text(lock_text)
	tooltip_rtl.append_text(pend_text)

	tooltip_rtl.position = Vector2.ZERO
	tooltip_panel.position = screen_pos + Vector2(20, -10)
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

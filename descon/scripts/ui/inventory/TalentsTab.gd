extends Control

# TalentsTab.gd - MÓDULO DE PROGRESIÓN PROFESIONAL (v300.65)
# Diseño optimizado, gestión de inputs y debug integrado.

var inv_main = null
var talent_system = null
var _texture_cache: Dictionary = {}

const SKILL_DATA = [
	{ "id": "eng_1", "cat": "engineering", "name": "REFUERZO DE CASCO", "desc": "+2% HP por nivel", "max": 5 },
	{ "id": "eng_2", "cat": "engineering", "name": "ESCUDO DINÁMICO", "desc": "+2% Escudo por nivel", "max": 5 },
	{ "id": "eng_3", "cat": "engineering", "name": "REGEN EMERGENGIA", "desc": "+5% HP Reparación", "max": 5 },
	{ "id": "eng_4", "cat": "engineering", "name": "CAPACITOR OHCU", "desc": "+5% Shield Regen", "max": 5 },
	{ "id": "eng_5", "cat": "engineering", "name": "PLACAS NANOBOTS", "desc": "+1% Armadura total", "max": 5 },
	{ "id": "eng_6", "cat": "engineering", "name": "REACTOR FUSIÓN", "desc": "+3% Eficiencia Energía", "max": 5 },
	{ "id": "eng_7", "cat": "engineering", "name": "MANTE GALÁCTICO", "desc": "-5% Costo Reparación", "max": 5 },
	{ "id": "eng_8", "cat": "engineering", "name": "ESTABL FLOTANTE", "desc": "+1% Estabilidad (Vel)", "max": 5 },
	{ "id": "com_1", "cat": "combat", "name": "LÁSER SOBRECARGA", "desc": "+3% Daño Láser", "max": 5 },
	{ "id": "com_2", "cat": "combat", "name": "MIRILLA TÁCTICA", "desc": "+2% Prob. Crítico", "max": 5 },
	{ "id": "com_3", "cat": "combat", "name": "FURIA DEL PILOTO", "desc": "+5% Daño Crítico", "max": 5 },
	{ "id": "com_4", "cat": "combat", "name": "CARGA PROYECTIL", "desc": "+5% Bonus Munición", "max": 5 },
	{ "id": "com_5", "cat": "combat", "name": "DISPARO PRECISIÓN", "desc": "+2% Puntería", "max": 5 },
	{ "id": "com_6", "cat": "combat", "name": "PERFORACIÓN TÉRM", "desc": "+3% Ignorar Escudo", "max": 5 },
	{ "id": "com_7", "cat": "combat", "name": "CADENCIA MILITAR", "desc": "-2% CD de Disparo", "max": 5 },
	{ "id": "com_8", "cat": "combat", "name": "BLINDAJE ATAQUE", "desc": "+1% Evasión en Combate", "max": 5 },
	{ "id": "sci_1", "cat": "science", "name": "MOTORES FUSIÓN", "desc": "+1.5% Velocidad Base", "max": 5 },
	{ "id": "sci_2", "cat": "science", "name": "ESCÁNER TÁCTICO", "desc": "+10% Rango Minimapa", "max": 5 },
	{ "id": "sci_3", "cat": "science", "name": "MINERÍA OHCU", "desc": "+5% OHCU de Kills", "max": 5 },
	{ "id": "sci_4", "cat": "science", "name": "MERCADO GALÁXIA", "desc": "-2% Descuento Tienda", "max": 5 },
	{ "id": "sci_5", "cat": "science", "name": "ENFRIAMIENTO RÁP", "desc": "-3% CD Habilidades", "max": 5 },
	{ "id": "sci_6", "cat": "science", "name": "SINCRONÍA TACT", "desc": "+1% Bonus en Grupo", "max": 5 },
	{ "id": "sci_7", "cat": "science", "name": "SENSORES PRECI", "desc": "+5% Loot de Bosses", "max": 5 },
	{ "id": "sci_8", "cat": "science", "name": "SALTO HIPERESP", "desc": "+10% Distancia Dash", "max": 5 }
]

func setup(p_inv_main):
	inv_main = p_inv_main
	# Forzar que el nodo sea interactivo
	mouse_filter = Control.MOUSE_FILTER_PASS

func update_ui():
	if not inv_main: return
	
	# Búsqueda de sistema
	talent_system = get_tree().get_first_node_in_group("talent_system")
	if not is_instance_valid(talent_system):
		var p = get_tree().get_first_node_in_group("player")
		if p: talent_system = p.get_node_or_null("TalentSystem")

	for n in get_children(): 
		remove_child(n)
		n.queue_free()
	
	if not is_instance_valid(talent_system):
		var err = Label.new()
		err.text = "ERROR: SISTEMA DE TALENTOS NO INICIALIZADO\n(Asegúrate de estar en el espacio)"
		err.horizontal_alignment = 1; err.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		add_child(err)
		return
		
	var master_v = VBoxContainer.new()
	master_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	master_v.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(master_v)
	
	# Header
	var hb = HBoxContainer.new(); hb.mouse_filter = Control.MOUSE_FILTER_PASS; master_v.add_child(hb)
	var pts = Label.new(); pts.text = "PUNTOS DISPONIBLES: " + str(int(talent_system.skill_points))
	pts.modulate = Color.GREEN; pts.add_theme_font_size_override("font_size", 14); hb.add_child(pts)
	
	var rb = Button.new(); rb.text = " RESETEAR ÁRBOL (5.000 OHCU) "; rb.size_flags_horizontal = 3; rb.alignment = 2
	rb.pressed.connect(_on_reset_pressed)
	hb.add_child(rb)

	master_v.add_child(HSeparator.new())
	
	var scroll = ScrollContainer.new(); scroll.size_flags_vertical = 3; scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	master_v.add_child(scroll)
	
	var grid = HBoxContainer.new(); grid.size_flags_horizontal = 3; grid.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_theme_constant_override("separation", 20); scroll.add_child(grid)

	var cats = {"engineering": "INGENIERÍA", "combat": "COMBATE", "science": "CIENCIA"}
	for ck in cats:
		var col = VBoxContainer.new(); col.size_flags_horizontal = 3; col.mouse_filter = Control.MOUSE_FILTER_PASS; grid.add_child(col)
		var l = Label.new(); l.text = cats[ck]; l.horizontal_alignment = 1
		l.modulate = Color.CYAN if ck == "engineering" else (Color.RED if ck == "combat" else Color.PURPLE)
		l.add_theme_font_size_override("font_size", 16); col.add_child(l)
		
		var list = VBoxContainer.new(); list.add_theme_constant_override("separation", 8); list.mouse_filter = Control.MOUSE_FILTER_PASS; col.add_child(list)
		
		var branch = talent_system.skill_tree.get(ck, [0,0,0,0,0,0,0,0])
		var skills = SKILL_DATA.filter(func(x): return x.cat == ck)
		
		for i in range(skills.size()):
			var s = skills[i]; var lvl = branch[i] if i < branch.size() else 0
			_create_talent_card(list, s, lvl, ck, i)

func _create_talent_card(parent, skill, lvl, cat, idx):
	var p = PanelContainer.new(); p.custom_minimum_size = Vector2(0, 85); parent.add_child(p)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var sb = StyleBoxFlat.new(); sb.bg_color = Color(1,1,1,0.02); sb.set_border_width_all(1); sb.border_color = Color(1,1,1,0.08)
	var cat_color = Color.CYAN if cat == "engineering" else (Color.RED if cat == "combat" else Color.PURPLE)
	if lvl > 0: sb.border_color = cat_color; sb.bg_color = cat_color; sb.bg_color.a = 0.05
	p.add_theme_stylebox_override("panel", sb)
	
	# HBox principal
	var hb = HBoxContainer.new(); hb.mouse_filter = Control.MOUSE_FILTER_IGNORE; p.add_child(hb)
	hb.add_theme_constant_override("separation", 10)
	
	# Ajustar márgenes internos
	var margins = MarginContainer.new()
	margins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margins.add_theme_constant_override("margin_left", 8)
	margins.add_theme_constant_override("margin_right", 8)
	margins.add_theme_constant_override("margin_top", 4)
	margins.add_theme_constant_override("margin_bottom", 4)
	margins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(margins)
	
	var content_hb = HBoxContainer.new()
	content_hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_hb.add_theme_constant_override("separation", 12)
	margins.add_child(content_hb)
	
	# 1. Obtener datos dinámicos del servidor si están disponibles
	var s_name = skill.name
	var s_desc = skill.desc
	var s_icon = ""
	if NetworkManager and NetworkManager.server_config:
		var talents_config = NetworkManager.server_config.get("talentsConfig", {})
		var server_talents = talents_config.get("talents", [])
		for t in server_talents:
			if t.get("id") == skill.id:
				s_name = t.get("name", s_name)
				s_desc = t.get("desc", s_desc)
				s_icon = t.get("icon", "")
				break
				
	# 2. Contenedor de Icono (Izquierda)
	var icon_box = CenterContainer.new(); icon_box.custom_minimum_size = Vector2(40, 0); content_hb.add_child(icon_box)
	
	var has_png = false
	if s_icon != "" and s_icon.ends_with(".png"):
		var cached_tex = _texture_cache.get(s_icon)
		if cached_tex:
			has_png = true
			var icon_rect = TextureRect.new()
			icon_rect.texture = cached_tex
			icon_rect.custom_minimum_size = Vector2(36, 36)
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			icon_rect.modulate = cat_color
			icon_box.add_child(icon_rect)
		elif ResourceLoader.exists(s_icon):
			var tex = load(s_icon)
			if tex:
				_texture_cache[s_icon] = tex
				has_png = true
				var icon_rect = TextureRect.new()
				icon_rect.texture = tex
				icon_rect.custom_minimum_size = Vector2(36, 36)
				icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
				icon_rect.modulate = cat_color
				icon_box.add_child(icon_rect)
				
	if not has_png:
		# Mostrar emoji o fallback como texto
		var ico_label = Label.new()
		ico_label.text = s_icon if s_icon != "" else "🌳"
		ico_label.add_theme_font_size_override("font_size", 20)
		ico_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_box.add_child(ico_label)

	# 3. Contenedor de Texto y Barras (Derecha)
	var v = VBoxContainer.new(); v.alignment = BoxContainer.ALIGNMENT_CENTER; v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; v.mouse_filter = Control.MOUSE_FILTER_IGNORE; content_hb.add_child(v)
	v.add_theme_constant_override("separation", 2)
	
	var n = Label.new(); n.text = s_name.to_upper(); n.add_theme_font_size_override("font_size", 11); v.add_child(n)
	var d = Label.new(); d.text = s_desc; d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; d.modulate.a = 0.6; d.add_theme_font_size_override("font_size", 9); v.add_child(d)
	
	var bars = HBoxContainer.new(); bars.add_theme_constant_override("separation", 3); v.add_child(bars)
	for b_idx in range(5):
		var bar = ColorRect.new(); bar.custom_minimum_size = Vector2(22, 5)
		bar.color = Color.GOLD if b_idx < lvl else Color(1,1,1,0.1); bars.add_child(bar)

	# Botón de acción (Invisible pero capturador)
	var btn = Button.new(); btn.flat = true; btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); p.add_child(btn)
	
	# Efectos de Hover
	btn.mouse_entered.connect(func(): sb.bg_color.a = 0.15 if lvl > 0 else 0.1; sb.border_color.a = 0.8)
	btn.mouse_exited.connect(func(): sb.bg_color.a = 0.05 if lvl > 0 else 0.02; sb.border_color.a = 0.1)
	
	btn.pressed.connect(_on_talent_clicked.bind(cat, idx))

func _on_talent_clicked(cat, idx):
	print("[TALENT-UI] Intentando invertir en: ", cat, " índice: ", idx)
	if is_instance_valid(talent_system):
		if talent_system.skill_points <= 0:
			inv_main._show_result_modal("SIN PUNTOS", "No tienes puntos de talento disponibles.")
			return
		talent_system.invest_point(cat, idx)
		# Refresco visual de espera (feedback táctil)
		update_ui.call_deferred()

func _on_reset_pressed():
	var m = "¿Deseas resetear todos tus talentos?\nCosto: [color=yellow]5.000 OHCU[/color]\n[i](Se te devolverán todos los puntos gastados)[/i]"
	inv_main._show_modal("RESETEAR PROGRESIÓN", m, func():
		if inv_main.ohcu < 5000:
			inv_main._show_result_modal("FONDOS INSUFICIENTES", "Necesitas 5.000 OHCU para esta operación.")
			return
		print("[TALENT-UI] Enviando orden de RESET al servidor...")
		talent_system.reset_talents()
	)

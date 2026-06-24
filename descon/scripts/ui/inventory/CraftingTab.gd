extends Control

# CraftingTab.gd - MÓDULO DE CRAFTEO GALÁCTICO (v2.0)

var inv_main = null

func setup(p_inv_main):
	inv_main = p_inv_main

func update_ui():
	if not inv_main: return
	
	# Limpiar hijos anteriores
	for child in get_children():
		remove_child(child)
		child.queue_free()
		
	# Contenedor Principal
	var main_v = VBoxContainer.new()
	main_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_v.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(main_v)
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	# --- TÍTULO Y DESCRIPCIÓN DE LA PESTAÑA ---
	var header = VBoxContainer.new()
	header.add_theme_constant_override("separation", 2)
	main_v.add_child(header)
	
	var title = Label.new()
	title.text = "FORJA Y SÍNTESIS INTERESTELAR"
	title.add_theme_font_size_override("font_size", 14)
	title.modulate = Color.CYAN
	header.add_child(title)
	
	var desc = Label.new()
	desc.text = "Combina minerales y esencias espaciales para fabricar módulos, armas o refinar materiales superiores."
	desc.add_theme_font_size_override("font_size", 9)
	desc.modulate = Color(0.7, 0.7, 0.8, 0.8)
	header.add_child(desc)
	
	# Línea separadora estética
	var sep = ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1.5)
	sep.color = Color(0, 0.8, 1, 0.2)
	header.add_child(sep)
	
	# Margen vertical de separación
	var margin_top = Control.new()
	margin_top.custom_minimum_size = Vector2(0, 5)
	main_v.add_child(margin_top)
	
	# --- SUB TABS CONTAINER ---
	var sub_tabs = TabContainer.new()
	sub_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sub_tabs.mouse_filter = Control.MOUSE_FILTER_PASS
	main_v.add_child(sub_tabs)
	
	var sb_tabs = StyleBoxFlat.new()
	sb_tabs.bg_color = Color(0.01, 0.02, 0.05, 0.4)
	sub_tabs.add_theme_stylebox_override("panel", sb_tabs)
	
	# --- SUB TAB 1: RECETAS ---
	var tab_recipes = Control.new()
	tab_recipes.name = "Recetas"
	sub_tabs.add_child(tab_recipes)
	
	var scr_recipes = ScrollContainer.new()
	scr_recipes.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scr_recipes.mouse_filter = Control.MOUSE_FILTER_PASS
	tab_recipes.add_child(scr_recipes)
	
	var grid_recipes = GridContainer.new()
	grid_recipes.columns = 3
	grid_recipes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_recipes.add_theme_constant_override("h_separation", 20)
	grid_recipes.add_theme_constant_override("v_separation", 20)
	scr_recipes.add_child(grid_recipes)
	
	var recipes = GameConstants.FULL_CONFIG.get("craftingRecipes", [])
	if recipes.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "No hay recetas de crafteo cargadas en la base de datos galáctica."
		empty_lbl.modulate = Color.DARK_GRAY
		empty_lbl.add_theme_font_size_override("font_size", 11)
		grid_recipes.add_child(empty_lbl)
	else:
		# Renderizar cada receta
		for recipe in recipes:
			_create_recipe_card(recipe, grid_recipes)
			
	# --- SUB TAB 2: MATERIALES ---
	var tab_materials = Control.new()
	tab_materials.name = "Materiales"
	sub_tabs.add_child(tab_materials)
	
	var scr_materials = ScrollContainer.new()
	scr_materials.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scr_materials.mouse_filter = Control.MOUSE_FILTER_PASS
	tab_materials.add_child(scr_materials)
	
	var grid_materials = GridContainer.new()
	grid_materials.columns = 4
	grid_materials.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_materials.add_theme_constant_override("h_separation", 15)
	grid_materials.add_theme_constant_override("v_separation", 15)
	scr_materials.add_child(grid_materials)
	
	var resources = GameConstants.FULL_CONFIG.get("shopItems", {}).get("resources", [])
	if resources.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "No hay materiales registrados en la base de datos galáctica."
		empty_lbl.modulate = Color.DARK_GRAY
		empty_lbl.add_theme_font_size_override("font_size", 11)
		grid_materials.add_child(empty_lbl)
	else:
		# Renderizar cada material
		for res in resources:
			_create_material_card(res, grid_materials)

func _get_item_icon(category: String, item_id: String) -> String:
	var shop = GameConstants.FULL_CONFIG.get("shopItems", {})
	if category == "ammo":
		for type in shop.get("ammo", {}):
			for item in shop["ammo"][type]:
				if item.get("id", "") == item_id:
					return item.get("icon", "")
	elif shop.has(category):
		var list = shop.get(category, [])
		for item in list:
			if item.get("id", "") == item_id:
				return item.get("icon", "")
	# Fallback: buscar en resources
	var resources = shop.get("resources", [])
	for res in resources:
		if res.get("id", "") == item_id:
			return res.get("icon", "")
	return ""

func _create_recipe_card(recipe: Dictionary, parent: Control):
	var p = PanelContainer.new()
	p.custom_minimum_size = Vector2(290, 240)
	
	# Estilo premium Cyberpunk / Dark Mode
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.01, 0.03, 0.08, 0.7)
	sb.border_width_top = 2
	sb.border_color = Color.CYAN
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0, 0.8, 1, 0.15)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	p.add_theme_stylebox_override("panel", sb)
	
	var v = VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	
	# Renderizado del icono/asset del item resultante con CenterContainer y escala
	var icon_path = _get_item_icon(recipe.get("resultCategory", ""), recipe.get("resultItemId", ""))
	var tex_container = CenterContainer.new()
	v.add_child(tex_container)
	
	var icon_tex = TextureRect.new()
	var base_scale = float(recipe.get("iconScale", 1.0))
	icon_tex.custom_minimum_size = Vector2(48, 48) * base_scale
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_tex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		var tex = load(icon_path)
		if tex:
			icon_tex.texture = tex
	tex_container.add_child(icon_tex)
	
	# 1. TÍTULO DEL RESULTADO
	var name_lbl = Label.new()
	name_lbl.text = recipe.get("name", "Receta")
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.modulate = Color.GOLD
	v.add_child(name_lbl)
	
	# 2. DESCRIPCIÓN
	var desc_lbl = Label.new()
	desc_lbl.text = recipe.get("desc", "")
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 8)
	desc_lbl.modulate = Color(0.6, 0.6, 0.7, 0.8)
	v.add_child(desc_lbl)
	
	# Separador de sección
	var sep_mid = ColorRect.new()
	sep_mid.custom_minimum_size = Vector2(0, 1)
	sep_mid.color = Color(0, 0.8, 1, 0.1)
	v.add_child(sep_mid)
	
	# Contenedor de ingredientes Scrollable
	var ing_scroll = ScrollContainer.new()
	ing_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(ing_scroll)
	
	var ing_v = VBoxContainer.new()
	ing_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ing_v.add_theme_constant_override("separation", 3)
	ing_scroll.add_child(ing_v)
	
	var can_craft = true
	
	# 3. LISTADO DE INGREDIENTES
	var ingredients = recipe.get("ingredients", [])
	for ing in ingredients:
		var ing_id = ing.get("itemId", "")
		var required_amount = int(ing.get("amount", 1))
		
		# Obtener información del material
		var mat_info = _get_resource_info(ing_id)
		var mat_name = mat_info.get("name", ing_id)
		var mat_color_str = mat_info.get("color", "#ffffff")
		var mat_color = Color.from_string(mat_color_str, Color.WHITE)
		
		# Contar cuántos posee el jugador en su inventario
		var owned_amount = 0
		for item in inv_main.inventory_items:
			if item.get("id", "") == ing_id:
				owned_amount += int(item.get("amount", 1))
				
		var ing_row = HBoxContainer.new()
		ing_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ing_row.add_theme_constant_override("separation", 6)
		ing_v.add_child(ing_row)
		
		# Icono en miniatura del material ingrediente
		var ing_icon_path = mat_info.get("icon", "")
		var ing_icon_tex = TextureRect.new()
		ing_icon_tex.custom_minimum_size = Vector2(16, 16)
		ing_icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ing_icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if not ing_icon_path.is_empty() and ResourceLoader.exists(ing_icon_path):
			var tex = load(ing_icon_path)
			if tex:
				ing_icon_tex.texture = tex
		ing_row.add_child(ing_icon_tex)
		
		var ing_name_lbl = Label.new()
		ing_name_lbl.text = mat_name
		ing_name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ing_name_lbl.add_theme_font_size_override("font_size", 9)
		ing_name_lbl.modulate = mat_color
		ing_row.add_child(ing_name_lbl)
		
		var ing_qty_lbl = Label.new()
		ing_qty_lbl.text = str(owned_amount) + " / " + str(required_amount)
		ing_qty_lbl.add_theme_font_size_override("font_size", 9)
		
		if owned_amount >= required_amount:
			ing_qty_lbl.modulate = Color.GREEN
		else:
			ing_qty_lbl.modulate = Color.RED
			can_craft = false
			
		ing_row.add_child(ing_qty_lbl)
		
	# 4. COSTOS DE MONEDA (HUBS / OHCU)
	var hubs_cost = int(recipe.get("costHubs", 0))
	var ohcu_cost = int(recipe.get("costOhcu", 0))
	
	if hubs_cost > 0 or ohcu_cost > 0:
		var coin_v = VBoxContainer.new()
		coin_v.add_theme_constant_override("separation", 2)
		v.add_child(coin_v)
		
		if hubs_cost > 0:
			var row = HBoxContainer.new()
			coin_v.add_child(row)
			
			var lbl = Label.new()
			lbl.text = "Costo Hubs:"
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.add_theme_font_size_override("font_size", 9)
			lbl.modulate = Color(0.8, 0.8, 0.8)
			row.add_child(lbl)
			
			var val = Label.new()
			val.text = inv_main._format_val(hubs_cost) + " HUBS"
			val.add_theme_font_size_override("font_size", 9)
			if inv_main.hubs >= hubs_cost:
				val.modulate = Color.CYAN
			else:
				val.modulate = Color.RED
				can_craft = false
			row.add_child(val)
			
		if ohcu_cost > 0:
			var row = HBoxContainer.new()
			coin_v.add_child(row)
			
			var lbl = Label.new()
			lbl.text = "Costo Ohcu:"
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.add_theme_font_size_override("font_size", 9)
			lbl.modulate = Color(0.8, 0.8, 0.8)
			row.add_child(lbl)
			
			var val = Label.new()
			val.text = inv_main._format_val(ohcu_cost) + " OHCU"
			val.add_theme_font_size_override("font_size", 9)
			if inv_main.ohcu >= ohcu_cost:
				val.modulate = Color.MAGENTA
			else:
				val.modulate = Color.RED
				can_craft = false
			row.add_child(val)

	# 5. BOTÓN DE FABRICAR
	var btn = Button.new()
	btn.text = "CRAFTEAR"
	btn.custom_minimum_size = Vector2(0, 30)
	btn.add_theme_font_size_override("font_size", 10)
	
	if can_craft:
		btn.modulate = Color.WHITE
		btn.pressed.connect(func(): _on_craft_pressed(recipe))
	else:
		btn.disabled = true
		btn.modulate = Color(0.4, 0.4, 0.4, 0.6)
		
	v.add_child(btn)
	parent.add_child(p)

func _create_material_card(res: Dictionary, parent: Control):
	var p = PanelContainer.new()
	p.custom_minimum_size = Vector2(210, 160)
	
	# Estilo premium Cyberpunk / Dark Mode
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.01, 0.03, 0.08, 0.7)
	sb.border_width_top = 2
	var mat_color_str = res.get("color", "#00ffff")
	var mat_color = Color.from_string(mat_color_str, Color.WHITE)
	sb.border_color = mat_color
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(mat_color.r, mat_color.g, mat_color.b, 0.15)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	p.add_theme_stylebox_override("panel", sb)
	
	var v = VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	
	# 1. ICON / TEXTURE RECT con CenterContainer y escala
	var icon_path = res.get("icon", "")
	var tex_container = CenterContainer.new()
	v.add_child(tex_container)
	
	var icon_tex = TextureRect.new()
	var base_scale = float(res.get("iconScale", 1.0))
	icon_tex.custom_minimum_size = Vector2(48, 48) * base_scale
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_tex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		var tex = load(icon_path)
		if tex:
			icon_tex.texture = tex
	tex_container.add_child(icon_tex)
	
	# 2. TÍTULO
	var name_lbl = Label.new()
	name_lbl.text = res.get("name", "Material")
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.modulate = mat_color
	v.add_child(name_lbl)
	
	# 3. DESCRIPCIÓN
	var desc_lbl = Label.new()
	desc_lbl.text = res.get("desc", "")
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 8)
	desc_lbl.modulate = Color(0.6, 0.6, 0.7, 0.8)
	v.add_child(desc_lbl)
	
	# 4. CANTIDAD POSEÍDA
	var owned_amount = 0
	for item in inv_main.inventory_items:
		if item.get("id", "") == res.get("id", ""):
			owned_amount += int(item.get("amount", 1))
			
	var qty_lbl = Label.new()
	qty_lbl.text = "En Inventario: " + str(owned_amount)
	qty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qty_lbl.add_theme_font_size_override("font_size", 9)
	qty_lbl.modulate = Color.GREEN if owned_amount > 0 else Color.RED
	v.add_child(qty_lbl)
	
	parent.add_child(p)

func _get_resource_info(item_id: String) -> Dictionary:
	var resources = GameConstants.FULL_CONFIG.get("shopItems", {}).get("resources", [])
	for res in resources:
		if res.get("id", "") == item_id:
			return res
	return {}

func _on_craft_pressed(recipe: Dictionary):
	var recipe_id = recipe.get("id", "")
	var recipe_name = recipe.get("name", "Objeto")
	
	var msg = "¿Deseas fabricar [color=yellow]" + recipe_name + "[/color] consumiendo los materiales necesarios?"
	inv_main._show_modal("CONFIRMAR CRAFTEO", msg, func():
		NetworkManager.send_event("craftItem", {"recipeId": recipe_id})
	)

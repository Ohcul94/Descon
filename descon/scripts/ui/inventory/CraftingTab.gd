extends Control

# CraftingTab.gd - MÓDULO DE CRAFTEO GALÁCTICO (v1.0)

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
	margin_top.custom_minimum_size = Vector2(0, 10)
	main_v.add_child(margin_top)
	
	# --- SCROLL DE RECETAS ---
	var scr = ScrollContainer.new()
	scr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scr.mouse_filter = Control.MOUSE_FILTER_PASS
	main_v.add_child(scr)
	
	var grid = GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	scr.add_child(grid)
	
	var recipes = GameConstants.FULL_CONFIG.get("craftingRecipes", [])
	if recipes.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "No hay recetas de crafteo cargadas en la base de datos galáctica."
		empty_lbl.modulate = Color.DARK_GRAY
		empty_lbl.add_theme_font_size_override("font_size", 11)
		grid.add_child(empty_lbl)
		return
		
	# Renderizar cada receta
	for recipe in recipes:
		_create_recipe_card(recipe, grid)

func _create_recipe_card(recipe: Dictionary, parent: Control):
	var p = PanelContainer.new()
	p.custom_minimum_size = Vector2(290, 220)
	
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
	
	# Margen interno mediante un contenedor ficticio o padding en el panel
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	
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
				owned_amount += 1
				
		var ing_row = HBoxContainer.new()
		ing_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ing_v.add_child(ing_row)
		
		var ing_name_lbl = Label.new()
		ing_name_lbl.text = "• " + mat_name
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

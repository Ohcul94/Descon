extends Control

# ShopTab.gd - MÓDULO DE TIENDA INTERESTELAR (v300.51)
# Corregido: Detección de naves adquiridas y limpieza de UI.

var inv_main = null
var shop_tab = "ships"
var ammo_sub_tab = "laser"

func setup(p_inv_main):
	inv_main = p_inv_main

func update_ui():
	if not inv_main: return
	var h = self
	for n in h.get_children(): 
		h.remove_child(n)
		n.queue_free()
	
	var main_v = VBoxContainer.new()
	main_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.add_child(main_v)
	
	# --- BARRA DE CATEGORÍAS ---
	var bar = HBoxContainer.new(); bar.add_theme_constant_override("separation", 15); main_v.add_child(bar)
	var lbats = {"ships": "NAVES", "weapons": "ARMAS", "shields": "ESCUDOS", "engines": "MOTORES", "ammo": "MUNICIONES", "extras": "EXTRAS"}
	for k in lbats:
		var b = Button.new(); b.text = lbats[k]; b.flat = true
		b.modulate = Color.CYAN if shop_tab == k else Color.WHITE
		b.pressed.connect(func(): shop_tab = k; update_ui())
		bar.add_child(b)
	
	# v262.530: Subtítulo eliminado por pedido del usuario
	
	var scr = ScrollContainer.new(); scr.size_flags_vertical = 3; main_v.add_child(scr)
	var grid = GridContainer.new(); grid.columns = 3; grid.size_flags_horizontal = 3; grid.add_theme_constant_override("h_separation", 20); grid.add_theme_constant_override("v_separation", 20); scr.add_child(grid)
	
	if shop_tab == "ships":
		for ship in GameConstants.SHIP_MODELS: _create_shop_card(ship, "ships", grid)
	elif shop_tab == "ammo":
		_render_ammo_shop(main_v, grid)
	else:
		var items = GameConstants.SHOP_ITEMS.get(shop_tab, [])
		for it in items: _create_shop_card(it, shop_tab, grid)

func _create_shop_card(it, cat, parent):
	var p = PanelContainer.new(); p.custom_minimum_size = Vector2(280, 110)
	var sb = StyleBoxFlat.new(); sb.bg_color = Color(0,0.02,0.1, 0.4); sb.border_width_top = 1; sb.border_color = Color(0,1,1,0.1); p.add_theme_stylebox_override("panel", sb)
	var v = VBoxContainer.new(); v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); v.offset_left = 10; v.offset_right = -10; p.add_child(v)
	v.add_theme_constant_override("separation", 4) # Espaciado original
	
	var n = Label.new(); n.text = it["name"]; n.horizontal_alignment = 1; n.add_theme_font_size_override("font_size", 11); v.add_child(n)
	
	# v262.860: Mostrar Stats (Sincronizado con Admin)
	var base_val = it.get("base", 0)
	var stat_label = Label.new(); stat_label.horizontal_alignment = 1; stat_label.add_theme_font_size_override("font_size", 9); stat_label.modulate = Color.GOLD
	if cat == "weapons": stat_label.text = "POTENCIA DE FUEGO: " + str(base_val)
	elif cat == "shields": stat_label.text = "CAPACIDAD DE ESCUDO: " + str(base_val)
	elif cat == "engines": stat_label.text = "EMPUJE DE MOTOR: +" + str(base_val)
	if stat_label.text != "": v.add_child(stat_label)

	var d = Label.new(); d.text = it.get("desc", ""); d.horizontal_alignment = 1; d.modulate.a = 0.5; d.add_theme_font_size_override("font_size", 8); v.add_child(d)
	
	var is_owned = false
	if cat == "ships":
		var target_id = int(it["id"])
		for owned_id in inv_main.owned_ships:
			if int(owned_id) == target_id:
				is_owned = true; break
				
	if is_owned:
		var l = Label.new(); l.text = "\nNAVE ADQUIRIDA"; l.modulate = Color.GREEN; l.horizontal_alignment = 1; v.add_child(l)
	else:
		var pr = it["prices"]
		if pr.get("hubs", 0) > 0:
			var b1 = Button.new(); b1.text = inv_main._format_val(pr["hubs"]) + " HUBS"; v.add_child(b1)
			b1.pressed.connect(func(): _buy_request(cat, it, "hubs"))
		if pr.get("ohcu", 0) > 0:
			var b2 = Button.new(); b2.text = inv_main._format_val(pr["ohcu"]) + " OHCU"; v.add_child(b2)
			b2.pressed.connect(func(): _buy_request(cat, it, "ohcu"))
	
	parent.add_child(p)

func _render_ammo_shop(parent, grid):
	var bar = HBoxContainer.new(); bar.add_theme_constant_override("separation", 10); parent.add_child(bar); parent.move_child(bar, 1)
	for t in ["laser", "missile", "mine"]:
		var b = Button.new(); b.text = t.to_upper(); b.flat = true; b.modulate = Color.GOLD if ammo_sub_tab == t else Color.WHITE
		b.pressed.connect(func(): ammo_sub_tab = t; update_ui())
		bar.add_child(b)
	var ammo_base = GameConstants.SHOP_ITEMS.get("ammo", {})
	var items = ammo_base.get(ammo_sub_tab, [])
	for it in items: _create_shop_card(it, "ammo", grid)

func _buy_request(cat, it, cur):
	var price = it["prices"][cur]
	var wallet = inv_main.hubs if cur == "hubs" else inv_main.ohcu
	if wallet < price: 
		inv_main._show_result_modal("FONDOS INSUFICIENTES", "No tienes suficientes " + cur.to_upper() + " para esta operación.")
		return
	
	if cat == "ammo":
		_show_ammo_modal(it, cur)
		return

	var msg = "¿Deseas adquirir [color=cyan]" + it["name"] + "[/color] por [color=yellow]" + inv_main._format_val(price) + " " + cur.to_upper() + "[/color]?"
	inv_main._show_modal("CONFIRMAR ADQUISICIÓN", msg, func():
		NetworkManager.send_event("buyItem", {"category": cat, "itemId": it["id"], "currency": cur})
	)

func _show_ammo_modal(it, cur):
	var unit_price = it["prices"][cur]
	var dial_v = VBoxContainer.new()
	var lq = Label.new(); lq.text = "CANTIDAD DE RECARGA:"; lq.horizontal_alignment = 1; dial_v.add_child(lq)
	var slider = HSlider.new(); slider.min_value = 100; slider.max_value = 50000; slider.step = 100; slider.value = 1000; dial_v.add_child(slider)
	var total_lbl = Label.new(); total_lbl.text = "1.000 unidades = " + inv_main._format_val(unit_price * 10) + " " + cur.to_upper(); total_lbl.horizontal_alignment = 1; dial_v.add_child(total_lbl)
	
	slider.value_changed.connect(func(v): 
		total_lbl.text = inv_main._format_val(v) + " unidades = " + inv_main._format_val(v * (unit_price/100.0)) + " " + cur.to_upper()
	)
	
	inv_main._show_modal("SUMINISTROS TÁCTICOS", "Ajusta la cantidad de [color=cyan]" + it["name"] + "[/color] a comprar:", func():
		var qty = int(slider.value)
		var total = int(qty * (unit_price/100.0))
		if (inv_main.hubs if cur == "hubs" else inv_main.ohcu) >= total:
			NetworkManager.send_event("buyItem", {"category": "ammo", "itemId": it["id"], "currency": cur, "amount": qty})
		else:
			inv_main._show_result_modal("ERROR", "No tienes fondos para esta cantidad.")
	, dial_v)

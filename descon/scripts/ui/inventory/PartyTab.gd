extends Control

# PartyTab.gd - MÓDULO DE ESCUADRÓN (v301.2)
# Lógica de gestión de equipo extraída de Inventory.gd.

var inv_main = null
var party_timer = null

func setup(p_inv_main):
	inv_main = p_inv_main
	
	# Iniciar el timer de refresco aquí para que sea independiente
	party_timer = Timer.new()
	party_timer.wait_time = 3.0
	party_timer.autostart = true
	party_timer.timeout.connect(update_ui)
	add_child(party_timer)

func update_ui():
	if not inv_main or not inv_main.visible: return
	var tab = self
	
	# Estructura Persistente para evitar perder el foco del buscador
	var master_h = tab.get_node_or_null("MasterH")
	if not master_h:
		for n in tab.get_children(): n.queue_free()
		master_h = HBoxContainer.new(); master_h.name = "MasterH"; master_h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		master_h.add_theme_constant_override("separation", 30); tab.add_child(master_h)
		
		# Columna Izquierda: Miembros del Grupo
		var l_col = VBoxContainer.new(); l_col.name = "LCol"; l_col.size_flags_horizontal = 3; master_h.add_child(l_col)
		var l_title = Label.new(); l_title.text = "MIEMBROS DEL ESCUADRÓN"; l_title.modulate = Color.CYAN; l_title.add_theme_font_size_override("font_size", 11); l_col.add_child(l_title)
		var p_scroll = ScrollContainer.new(); p_scroll.name = "PScroll"; p_scroll.size_flags_vertical = 3; l_col.add_child(p_scroll)
		var _p_list = VBoxContainer.new(); _p_list.name = "PList"; _p_list.size_flags_horizontal = 3; p_scroll.add_child(_p_list)
		var _leave_box = VBoxContainer.new(); _leave_box.name = "LeaveBox"; l_col.add_child(_leave_box)
		
		# Columna Derecha: Jugadores Cercanos
		var r_col = VBoxContainer.new(); r_col.name = "RCol"; r_col.size_flags_horizontal = 3; master_h.add_child(r_col)
		var r_title = Label.new(); r_title.text = "PILOTOS EN LA ZONA"; r_title.modulate = Color.GOLD; r_title.add_theme_font_size_override("font_size", 11); r_col.add_child(r_title)
		var n_scroll = ScrollContainer.new(); n_scroll.name = "NScroll"; n_scroll.size_flags_vertical = 3; r_col.add_child(n_scroll)
		var _n_list = VBoxContainer.new(); _n_list.name = "NList"; _n_list.size_flags_horizontal = 3; n_scroll.add_child(_n_list)
		
		# Seccion de Invitacion Manual
		var inv_h = HBoxContainer.new(); inv_h.name = "InvH"; r_col.add_child(inv_h)
		var inp = LineEdit.new(); inp.name = "ManualInput"; inp.placeholder_text = "Buscar por nombre..."
		inp.size_flags_horizontal = 3; inv_h.add_child(inp)
		var btn = Button.new(); btn.text = "INVITAR"; inv_h.add_child(btn)
		btn.pressed.connect(func(): 
			var name_to_inv = inp.text.strip_edges()
			if name_to_inv != "": 
				PartyManager.invite_player(name_to_inv)
				inp.text = ""
		)

	# --- ACTUALIZACIÓN DE LISTAS DINÁMICAS ---
	var p_list = tab.get_node_or_null("MasterH/LCol/PScroll/PList")
	var leave_box = tab.get_node_or_null("MasterH/LCol/LeaveBox")
	if p_list:
		for n in p_list.get_children(): n.queue_free()
		for n in leave_box.get_children(): n.queue_free()
		
		var data = PartyManager.current_party
		if data:
			var members = data.get("members", [])
			var names = data.get("names", [])
			for i in range(members.size()):
				var hb = HBoxContainer.new(); hb.custom_minimum_size = Vector2(0, 40)
				var sb = StyleBoxFlat.new(); sb.bg_color = Color(0,1,1,0.05); sb.border_width_left = 2; sb.border_color = Color.CYAN if i == 0 else Color.WHITE
				var pc = PanelContainer.new(); pc.add_theme_stylebox_override("panel", sb); pc.size_flags_horizontal = 3; hb.add_child(pc)
				var name_lbl = Label.new(); name_lbl.text = ("Lider: " if i == 0 else "Piloto: ") + str(names[i]); pc.add_child(name_lbl)
				p_list.add_child(hb)
			
			var leave_btn = Button.new(); leave_btn.text = "ABANDONAR GRUPO"; leave_btn.modulate = Color.RED
			leave_btn.pressed.connect(func(): PartyManager.leave_party())
			leave_box.add_child(leave_btn)
		else:
			var no_party = Label.new(); no_party.text = "\nNo perteneces a ningún escuadrón."; no_party.modulate.a = 0.4; p_list.add_child(no_party)

	var n_list = tab.get_node_or_null("MasterH/RCol/NScroll/NList")
	if n_list:
		for n in n_list.get_children(): n.queue_free()
		var world_node = get_tree().get_first_node_in_group("world_node")
		if is_instance_valid(world_node):
			var players = world_node.remote_players
			if players.is_empty():
				var lbl = Label.new(); lbl.text = "\nNo hay otros pilotos cerca."; lbl.modulate.a = 0.3; n_list.add_child(lbl)
			else:
				for id in players:
					var p = players[id]
					if not is_instance_valid(p): continue
					var hb = HBoxContainer.new()
					var nl = Label.new(); nl.text = p.username if "username" in p else "Piloto"; nl.size_flags_horizontal = 3
					var ib = Button.new(); ib.text = "INVITAR"; ib.add_theme_font_size_override("font_size", 10)
					ib.pressed.connect(func(): PartyManager.invite_player(nl.text))
					hb.add_child(nl); hb.add_child(ib); n_list.add_child(hb)

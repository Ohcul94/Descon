extends Control

# ClanTab.gd - MÓDULO DE FLOTA (v301.4)
# Estética original restaurada con soporte modular total.

var inv_main = null

func setup(p_inv_main):
	inv_main = p_inv_main

func update_ui():
	if not inv_main: return
	var tab = self
	
	# v301.4: Usar los datos del orquestador principal
	var clan_data = inv_main.clan_data
	var pending_clans = inv_main.pending_clans
	var received_invites = inv_main.received_invites
	var last_clan_subtab = inv_main.last_clan_subtab
	
	for n in tab.get_children(): n.queue_free()
	
	var master_v = VBoxContainer.new(); master_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	master_v.offset_left = 20; master_v.offset_right = -20; master_v.offset_top = 20; tab.add_child(master_v)

	if clan_data == null or typeof(clan_data) != TYPE_DICTIONARY:
		var sub_tabs = TabContainer.new(); sub_tabs.size_flags_vertical = 3; master_v.add_child(sub_tabs)
		
		# 1. GESTIÓN
		var g_tab = Control.new(); g_tab.name = "Gestión"; sub_tabs.add_child(g_tab)
		_render_no_clan_main_tab(g_tab)
		
		# 2. SOLICITUDES
		var total_reqs = pending_clans.size() + received_invites.size()
		var s_tab = Control.new(); s_tab.name = "Solicitudes (" + str(total_reqs) + ")" if total_reqs > 0 else "Solicitudes"
		sub_tabs.add_child(s_tab)
		_render_no_clan_requests_tab(s_tab)
		
		sub_tabs.current_tab = last_clan_subtab
		sub_tabs.tab_changed.connect(func(idx): inv_main.last_clan_subtab = idx)
	else:
		var head = HBoxContainer.new(); master_v.add_child(head)
		var tag_str = str(clan_data.get("tag", "TAG"))
		var name_str = str(clan_data.get("name", "Clan"))
		var title = Label.new(); title.text = "[" + tag_str + "] " + name_str; title.add_theme_font_size_override("font_size", 22); title.modulate = Color.GOLD; title.size_flags_horizontal = 3; head.add_child(title)
		
		var p_node = get_tree().get_first_node_in_group("player")
		var my_id = str(p_node.get("db_id")) if is_instance_valid(p_node) and "db_id" in p_node else ""
		var is_leader = str(clan_data.get("leader", "")) == my_id
		
		var b_leave = Button.new(); b_leave.text = "ABANDONAR"; b_leave.modulate = Color.RED; head.add_child(b_leave)
		b_leave.pressed.connect(func():
			var inp = LineEdit.new(); inp.placeholder_text = "Escribe " + tag_str + " para confirmar..."; inp.alignment = HORIZONTAL_ALIGNMENT_CENTER
			inv_main._show_modal("ABANDONAR FLOTA", "¿Confirmas que deseas abandonar?\nEscribe [color=yellow]" + tag_str + "[/color] para proceder.", func():
				if inp.text.to_upper() == tag_str.to_upper(): NetworkManager.send_event("leaveClan", {})
				else: inv_main._show_result_modal("ERROR", "El TAG ingresado no es correcto.")
			, inp)
		)
		
		master_v.add_child(HSeparator.new())
		
		var sub_tabs = TabContainer.new(); sub_tabs.size_flags_vertical = 3; master_v.add_child(sub_tabs)
		
		# 1. MIEMBROS
		var m_tab = Control.new(); m_tab.name = "Miembros"; sub_tabs.add_child(m_tab)
		_render_clan_members_tab(m_tab, is_leader, p_node)
		
		# 2. SOLICITUDES (Solo Líder/Oficial)
		var s_count = clan_data.get("requests", []).size()
		var s_tab = Control.new(); s_tab.name = "Solicitudes (" + str(s_count) + ")" if s_count > 0 else "Solicitudes"
		sub_tabs.add_child(s_tab)
		_render_clan_requests_tab(s_tab, is_leader)
		
		# 3. CONFIGURACIÓN
		var c_tab = Control.new(); c_tab.name = "Configuración"; sub_tabs.add_child(c_tab)
		_render_clan_config_tab(c_tab, is_leader, tag_str)
		
		sub_tabs.current_tab = last_clan_subtab
		sub_tabs.tab_changed.connect(func(idx): inv_main.last_clan_subtab = idx)

func _render_clan_members_tab(parent, is_leader, p_node):
	var main_v = VBoxContainer.new(); main_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_v.offset_left = 10; main_v.offset_right = -10; main_v.offset_top = 10; parent.add_child(main_v)
	
	var scroll = ScrollContainer.new(); scroll.size_flags_vertical = 3; main_v.add_child(scroll)
	var list = VBoxContainer.new(); list.size_flags_horizontal = 3; scroll.add_child(list)
	
	var members = inv_main.clan_data.get("members", [])
	for m in members:
		if typeof(m) != TYPE_DICTIONARY: continue
		var hb = HBoxContainer.new(); hb.custom_minimum_size.y = 35; list.add_child(hb)
		
		var is_m_online = m.get("online", false)
		var status = Label.new(); status.text = " ● "; status.modulate = Color.GREEN if is_m_online else Color.GRAY; hb.add_child(status)
		
		var role = m.get("role", "member")
		if role == "leader":
			var l_ico = Label.new(); l_ico.text = " [LÍDER] "; l_ico.modulate = Color.GOLD; l_ico.add_theme_font_size_override("font_size", 10); hb.add_child(l_ico)
		
		var nl = Label.new(); nl.text = str(m.get("username", "Piloto")) + " (Lvl " + str(m.get("level", 1)) + ")"; nl.size_flags_horizontal = 3; hb.add_child(nl)
		if not is_m_online: nl.modulate.a = 0.5
		
		var rl = Label.new(); rl.custom_minimum_size.x = 80; rl.add_theme_font_size_override("font_size", 9)
		rl.text = "LÍDER" if role == "leader" else ("OFICIAL" if role == "officer" else "PILOTO")
		rl.modulate = Color.GOLD if role == "leader" else (Color.CYAN if role == "officer" else Color.WHITE)
		hb.add_child(rl)
		
		var m_username = str(m.get("username", ""))
		var m_name = m_username.to_lower()
		var p_name = str(p_node.get("username")).to_lower() if is_instance_valid(p_node) and p_node.get("username") else ""
		
		if m_name != "" and m_name != p_name:
			if is_m_online:
				var in_party = false
				if PartyManager.current_party and PartyManager.current_party.has("members"):
					for pm in PartyManager.current_party["members"]:
						if typeof(pm) == TYPE_DICTIONARY and str(pm.get("username", "")).to_lower() == m_name: in_party = true; break
				if not in_party:
					var bi = Button.new(); bi.text = "PARTY"; bi.add_theme_font_size_override("font_size", 10); hb.add_child(bi)
					bi.pressed.connect(func(): PartyManager.invite_player(m_username))
			
			if is_leader:
				var bk = Button.new(); bk.text = "X"; bk.modulate = Color.RED; bk.tooltip_text = "Expulsar de la Flota"; hb.add_child(bk)
				bk.pressed.connect(func():
					inv_main._show_modal("EXPULSAR MIEMBRO", "¿Seguro que quieres expulsar a " + m_username + " de la flota?", func():
						NetworkManager.send_event("kickClanMember", {"username": m_username})
					)
				)

func _render_clan_requests_tab(parent, is_leader):
	var main_v = VBoxContainer.new(); main_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_v.offset_left = 10; main_v.offset_right = -10; main_v.offset_top = 10; parent.add_child(main_v)
	
	if not is_leader:
		var lbl = Label.new(); lbl.text = "Solo el líder puede ver las solicitudes."; lbl.modulate.a = 0.5; main_v.add_child(lbl)
		return
	
	var inv_h = HBoxContainer.new(); main_v.add_child(inv_h)
	var i_name = LineEdit.new(); i_name.placeholder_text = "Ingresar TAG del piloto a invitar..."; i_name.size_flags_horizontal = 3; inv_h.add_child(i_name)
	var b_inv = Button.new(); b_inv.text = "ENVIAR INVITACIÓN"; b_inv.modulate = Color.CYAN; inv_h.add_child(b_inv)
	b_inv.pressed.connect(func():
		if i_name.text != "":
			NetworkManager.send_event("inviteToClan", {"username": i_name.text})
			i_name.text = ""
	)
	
	main_v.add_child(HSeparator.new())
		
	var reqs = inv_main.clan_data.get("requests", [])
	if reqs.is_empty():
		var lbl = Label.new(); lbl.text = "No hay solicitudes de ingreso pendientes."; lbl.modulate.a = 0.5; main_v.add_child(lbl)
	else:
		var scroll = ScrollContainer.new(); scroll.size_flags_vertical = 3; main_v.add_child(scroll)
		var list = VBoxContainer.new(); list.size_flags_horizontal = 3; scroll.add_child(list)
		for r in reqs:
			var hb = HBoxContainer.new(); hb.custom_minimum_size.y = 40; list.add_child(hb)
			var nl = Label.new(); nl.text = str(r.get("username", "Piloto")) + " (Lvl " + str(r.get("level", 1)) + ")"; nl.size_flags_horizontal = 3; hb.add_child(nl)
			var b_acc = Button.new(); b_acc.text = "ACEPTAR"; b_acc.modulate = Color.GREEN; hb.add_child(b_acc)
			b_acc.pressed.connect(func(): NetworkManager.send_event("handleClanRequest", {"username": r.username, "action": "accept"}))
			var b_den = Button.new(); b_den.text = "RECHAZAR"; b_den.modulate = Color.RED; hb.add_child(b_den)
			b_den.pressed.connect(func(): NetworkManager.send_event("handleClanRequest", {"username": r.username, "action": "deny"}))
			
	var sent = inv_main.clan_data.get("sentInvites", [])
	if not sent.is_empty():
		main_v.add_child(HSeparator.new())
		var t_sent = Label.new(); t_sent.text = "INVITACIONES ENVIADAS POR LA FLOTA"; t_sent.modulate = Color.CYAN; main_v.add_child(t_sent)
		var s_list = VBoxContainer.new(); main_v.add_child(s_list)
		for s in sent:
			var shb = HBoxContainer.new(); s_list.add_child(shb)
			var sl = Label.new(); sl.text = "[INV] " + str(s.get("username", "Piloto")) + " (Lvl " + str(s.get("level", 1)) + ")"; sl.size_flags_horizontal = 3; shb.add_child(sl)
			sl.modulate.a = 0.7
			var b_can = Button.new(); b_can.text = "CANCELAR"; b_can.modulate = Color.ORANGE; b_can.add_theme_font_size_override("font_size", 9)
			shb.add_child(b_can)
			var s_username = str(s.get("username", ""))
			b_can.pressed.connect(func(): NetworkManager.send_event("cancelClanInvite", {"username": s_username}))

func _render_clan_config_tab(parent, is_leader, tag_str):
	var main_v = VBoxContainer.new(); main_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_v.offset_left = 10; main_v.offset_right = -10; main_v.offset_top = 10; parent.add_child(main_v)
	var grid = GridContainer.new(); grid.columns = 2; grid.add_theme_constant_override("h_separation", 20); main_v.add_child(grid)
	grid.add_child(Label.new()); grid.get_child(-1).text = "Nombre:"
	var l_name = Label.new(); l_name.text = inv_main.clan_data.get("name", ""); l_name.modulate = Color.GOLD; grid.add_child(l_name)
	grid.add_child(Label.new()); grid.get_child(-1).text = "TAG:"
	var l_tag = Label.new(); l_tag.text = inv_main.clan_data.get("tag", ""); l_tag.modulate = Color.GOLD; grid.add_child(l_tag)
	grid.add_child(HSeparator.new()); grid.add_child(HSeparator.new())
	
	if is_leader:
		grid.add_child(Label.new()); grid.get_child(-1).text = "Modo de Ingreso:"
		var jt = inv_main.clan_data.get("joinType", "open")
		var btn_jt = Button.new(); btn_jt.text = "ABIERTO" if jt == "open" else "SOLICITUD"
		btn_jt.modulate = Color.GREEN if jt == "open" else Color.YELLOW
		grid.add_child(btn_jt)
		btn_jt.pressed.connect(func():
			var next = "invite" if jt == "open" else "open"
			NetworkManager.send_event("setClanJoinType", {"type": next})
		)
		main_v.add_child(HSeparator.new())
		var t_danger = Label.new(); t_danger.text = "ZONA DE PELIGRO"; t_danger.modulate = Color.RED; main_v.add_child(t_danger)
		var b_disband = Button.new(); b_disband.text = "DISOLVER FLOTA"; b_disband.modulate = Color.ORANGE_RED; main_v.add_child(b_disband)
		b_disband.pressed.connect(func():
			var inp = LineEdit.new(); inp.placeholder_text = "Escribe " + tag_str + " para DISOLVER..."; inp.alignment = HORIZONTAL_ALIGNMENT_CENTER
			inv_main._show_modal("DISOLVER FLOTA", "[color=red]¡ATENCIÓN![/color]\nEsto eliminará el clan.\nEscribe [color=yellow]" + tag_str + "[/color] para confirmar.", func():
				if inp.text.to_upper() == tag_str.to_upper(): NetworkManager.send_event("disbandClan", {})
				else: inv_main._show_result_modal("ERROR", "El TAG ingresado no es correcto.")
			, inp)
		)
	else:
		var lbl = Label.new(); lbl.text = "Solo el líder puede modificar la configuración."; lbl.modulate.a = 0.5; main_v.add_child(lbl)

func _render_no_clan_main_tab(parent):
	var main_v = VBoxContainer.new(); main_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_v.offset_left = 10; main_v.offset_right = -10; main_v.offset_top = 10; parent.add_child(main_v)
	var title = Label.new(); title.text = "CENTRO DE COMANDO DE CLANES"; title.add_theme_font_size_override("font_size", 18); title.modulate = Color.CYAN; main_v.add_child(title)
	main_v.add_child(HSeparator.new())
	var grid = GridContainer.new(); grid.columns = 2; grid.add_theme_constant_override("h_separation", 40); main_v.add_child(grid)
	var v_crear = VBoxContainer.new(); grid.add_child(v_crear)
	var t_crear = Label.new(); t_crear.text = "FUNDAR NUEVO CLAN"; t_crear.modulate = Color.GOLD; v_crear.add_child(t_crear)
	var i_name = LineEdit.new(); i_name.placeholder_text = "Nombre del Clan..."; v_crear.add_child(i_name)
	var i_tag = LineEdit.new(); i_tag.placeholder_text = "TAG (Máx 4 letras)..."; i_tag.max_length = 4; v_crear.add_child(i_tag)
	var b_crear = Button.new(); b_crear.text = "CREAR CLAN (5000 OHCU)"; v_crear.add_child(b_crear)
	b_crear.pressed.connect(func():
		if i_name.text.length() < 3 or i_tag.text.length() < 2: return
		NetworkManager.send_event("createClan", {"name": i_name.text, "tag": i_tag.text})
	)
	var v_unir = VBoxContainer.new(); grid.add_child(v_unir)
	var t_unir = Label.new(); t_unir.text = "UNIRSE A CLAN EXISTENTE"; t_unir.modulate = Color.CYAN; v_unir.add_child(t_unir)
	var i_search = LineEdit.new(); i_search.placeholder_text = "Ingresar TAG del Clan..."; i_search.max_length = 4; v_unir.add_child(i_search)
	var b_unir = Button.new(); b_unir.text = "SOLICITAR INGRESO"; v_unir.add_child(b_unir)
	b_unir.pressed.connect(func():
		if i_search.text != "": NetworkManager.send_event("joinClan", {"tag": i_search.text})
	)

func _render_no_clan_requests_tab(parent):
	var main_v = VBoxContainer.new(); main_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_v.offset_left = 10; main_v.offset_right = -10; main_v.offset_top = 10; parent.add_child(main_v)
	var scroll = ScrollContainer.new(); scroll.size_flags_vertical = 3; main_v.add_child(scroll)
	var list = VBoxContainer.new(); list.size_flags_horizontal = 3; scroll.add_child(list)
	if inv_main.received_invites.is_empty() and inv_main.pending_clans.is_empty():
		var empty = Label.new(); empty.text = "No tienes solicitudes ni invitaciones pendientes."; empty.modulate.a = 0.5; list.add_child(empty)
		return
	if not inv_main.received_invites.is_empty():
		var t_inv = Label.new(); t_inv.text = "INVITACIONES RECIBIDAS (De Clanes)"; t_inv.modulate = Color.CYAN; list.add_child(t_inv)
		for inv in inv_main.received_invites:
			var hb = HBoxContainer.new(); hb.custom_minimum_size.y = 35; list.add_child(hb)
			var l = Label.new(); l.text = "[INV] [" + str(inv.get("tag", "")) + "] " + str(inv.get("name", "")); l.size_flags_horizontal = 3; hb.add_child(l)
			var b_acc = Button.new(); b_acc.text = "ACEPTAR"; b_acc.modulate = Color.GREEN; hb.add_child(b_acc)
			b_acc.pressed.connect(func(): NetworkManager.send_event("handleClanInvite", {"clanId": inv.id, "action": "accept"}))
			var b_den = Button.new(); b_den.text = "RECHAZAR"; b_den.modulate = Color.RED; hb.add_child(b_den)
			b_den.pressed.connect(func(): NetworkManager.send_event("handleClanInvite", {"clanId": inv.id, "action": "deny"}))
		list.add_child(HSeparator.new())
	if not inv_main.pending_clans.is_empty():
		var t_pend = Label.new(); t_pend.text = "SOLICITUDES ENVIADAS (" + str(inv_main.pending_clans.size()) + "/3)"; t_pend.modulate = Color.GOLD; list.add_child(t_pend)
		for p_clan in inv_main.pending_clans:
			var hb = HBoxContainer.new(); hb.custom_minimum_size.y = 35; list.add_child(hb)
			var l = Label.new(); l.text = "[SOL] [" + str(p_clan.get("tag", "")) + "] " + str(p_clan.get("name", "")); l.size_flags_horizontal = 3; hb.add_child(l)
			l.modulate = Color.CYAN; l.add_theme_font_size_override("font_size", 11)
			var b_can = Button.new(); b_can.text = "CANCELAR"; b_can.modulate = Color.ORANGE; b_can.add_theme_font_size_override("font_size", 9)
			hb.add_child(b_can)
			var clan_tag = str(p_clan.get("tag", ""))
			b_can.pressed.connect(func(): NetworkManager.send_event("cancelClanRequest", {"tag": clan_tag}))

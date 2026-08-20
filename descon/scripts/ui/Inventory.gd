extends Control

# Precarga de pestañas de inventario para optimizar transiciones (v313.4)
const HangarTabScript = preload("res://scripts/ui/inventory/HangarTab.gd")
const SpheresTabScript = preload("res://scripts/ui/inventory/SpheresTab.gd")
const ShopTabScript = preload("res://scripts/ui/inventory/ShopTab.gd")
const TalentsTabScript = preload("res://scripts/ui/inventory/TalentsTab.gd")
const PartyTabScript = preload("res://scripts/ui/inventory/PartyTab.gd")
const ClanTabScript = preload("res://scripts/ui/inventory/ClanTab.gd")
const MapTabScript = preload("res://scripts/ui/inventory/MapTab.gd")
const WeaponsTabScript = preload("res://scripts/ui/inventory/WeaponsTab.gd")
const CraftingTabScript = preload("res://scripts/ui/inventory/CraftingTab.gd")
const QuestsTabScript = preload("res://scripts/ui/inventory/QuestsTab.gd")

# Inventory.gd (Omni-Control v164.1 - Phoenix Absolute)
# Saneamiento total de diccionarios (Bracket Notation) + Exorcismo de Título.

var inventory_items = []
var owned_ships = []
var current_ship_id = 1
var equipped_data = {"w": [], "s": [], "e": [], "x": []}
var hubs = 0
var ohcu = 0
var is_open = false

var talent_system = null
var selected_hangar_ship_id = -1 # v210.15: Nave seleccionada para ver en Hangar
var inv_main_preserve_ship_id = -1 # v308.3: ID a preservar tras respuesta del servidor (equip/unequip)

var shop_tab = "ships"
var ammo_sub_tab = "laser"
var modal_active = false
var equipped_by_ship = {} # v210.95: Cache local de equipos de toda la flota
var selected_sphere_slot = -1 # Slot siendo reconfigurado
var selected_sphere_type_filter = "ANY" # Filtro de color para la biblioteca
var spheres_manager = null # Referencia al gestor de esferas del jugador
var clan_data = null # v242.35: Cache de datos de la Flota (Clan)
var last_clan_subtab = 0 # v244.55: Preservar pestaña al refrescar
var pending_clans = [] # v244.90: Solicitudes que el usuario envió y están pendientes
var received_invites = [] # v244.95: Invitaciones que el usuario recibió de clanes
var pending_skill_to_equip = null # v301.5: Habilidad esperando selección de slot
var pending_sphere_slot = -1 # v760.0: Slot esperando selección de esfera (flujo instalación)
var pending_sphere_item = null # v760.0: Esfera (ítem) esperando selección de slot
var active_modales = [] # v307: Registro de modales activos para cerrado en capas (LIFO)




func _ready():
	add_to_group("inventory_ui") # v244.70: Coordinación global de UI
	mouse_filter = Control.MOUSE_FILTER_STOP # v305.65: Cambiado de IGNORE a STOP para bloqueo global
	
	var win = get_node_or_null("Window")
	if win: win.mouse_filter = Control.MOUSE_FILTER_STOP # v244.71: Bloquear click-through
	
	# PROTOCOLO EXORCISMO (v164.1: Ocultar todo nodo Label externo que diga LOGISTICA o similar)
	_aggressive_hide(self)
	var win_title = get_node_or_null("Window/Label")
	if win_title: 
		win_title.visible = false
		win_title.text = ""
	
	if NetworkManager:
		NetworkManager.inventory_data.connect(_on_inventory_received)
		NetworkManager.login_success.connect(func(d): _on_inventory_received(d))
		NetworkManager.auth_success.connect(func(d): _on_inventory_received(d))
		
		# v263.010: Recibir datos de equipamiento de nave específica
		if NetworkManager.has_signal("ship_equip_data"):
			NetworkManager.ship_equip_data.connect(_on_ship_equip_data)
		
		# v242.36: Sincronía de Flota
		NetworkManager.clan_data.connect(_on_clan_data_received)
		NetworkManager.clan_member_status.connect(_on_clan_member_status)
		# v244.101: Escuchar errores globales para mostrar modales explícitos
		NetworkManager.game_notification.connect(_on_game_notification)
	
	# v190.62: Sincronía Responsive
	get_viewport().size_changed.connect(func(): queue_redraw())
	
	if PartyManager:
		PartyManager.party_updated.connect(func(_d): 
			var pt = get_node_or_null("Window/TabContainer/Equipo")
			if pt and pt.has_method("update_ui"): pt.update_ui()
			if is_open: _update_clan_ui()
		)
	
	var tabs = get_node_or_null("Window/TabContainer")
	if tabs:
		tabs.offset_top = 40; tabs.offset_left = 15
		tabs.offset_right = -15; tabs.offset_bottom = -15
		# v219.61: Refresco selectivo al cambiar de pestaña
		if not tabs.tab_changed.is_connected(_update_active_tab_ui):
			tabs.tab_changed.connect(func(_idx): _update_active_tab_ui())
	
	# v164.2: Sincronía Táctica de Moneda (F2 -> F1 Sync)
	_connect_to_player_stats()
	
	# v164.95: Buscar y vincular TalentSystem
	# Intentamos buscarlo en el grupo, si no, lo buscaremos bajo el nodo World
	talent_system = get_tree().get_first_node_in_group("talent_system")
	if not is_instance_valid(talent_system):
		var world = get_tree().get_first_node_in_group("world_node")
		if is_instance_valid(world) and world.has_node("TalentSystem"):
			talent_system = world.get_node("TalentSystem")
			
	if is_instance_valid(talent_system):
		talent_system.talents_updated.connect(_update_active_tab_ui)

	# v302.6: Inicialización inmediata (Eliminado await 1.0s que causaba lag en carga de Hangar)
	await get_tree().process_frame
	
	# v300.01: Inicialización de Módulos (Refactorización Modular)
	var hangar_node = get_node_or_null("Window/TabContainer/Hangar")
	if hangar_node:
		hangar_node.set_script(HangarTabScript)
		if hangar_node.has_method("setup"): hangar_node.setup(self)
	
	var spheres_node = get_node_or_null("Window/TabContainer/Esferas")
	if spheres_node:
		spheres_node.set_script(SpheresTabScript)
		if spheres_node.has_method("setup"): spheres_node.setup(self)

	var shop_node = get_node_or_null("Window/TabContainer/Tienda")
	if shop_node:
		shop_node.set_script(ShopTabScript)
		if shop_node.has_method("setup"): shop_node.setup(self)

	var talents_node = get_node_or_null("Window/TabContainer/Talentos")
	if talents_node:
		talents_node.set_script(TalentsTabScript)
		if talents_node.has_method("setup"): talents_node.setup(self)

	var party_node = get_node_or_null("Window/TabContainer/Equipo")
	if party_node:
		party_node.set_script(PartyTabScript)
		if party_node.has_method("setup"): party_node.setup(self)

	var clan_node = get_node_or_null("Window/TabContainer/Clan")
	if clan_node:
		clan_node.set_script(ClanTabScript)
		if clan_node.has_method("setup"): clan_node.setup(self)

	var map_node = get_node_or_null("Window/TabContainer/Mapa")
	if map_node:
		map_node.set_script(MapTabScript)
		if map_node.has_method("setup"): map_node.setup(self)
	
	# v219.67: Asegurar creación de pestañas dinámicas (Fix desaparición Mapa/Clan)
	_update_weapons_ui()
	_update_map_ui()
	_update_clan_ui()
	_update_crafting_ui()
	_update_quests_ui()
	
	_refresh_data()
	# v302.6: Forzar refresco tras setup para mostrar datos que llegaron durante el frame de carga
	if is_open:
		_update_active_tab_ui()
	

func _aggressive_hide(node):
	for child in node.get_children():
		if child is Label:
			var t = child.text.to_upper()
			if "LOGISTICA" in t or "EQUIPAMIENTO" in t or "CENTRO" in t:
				child.text = ""
				child.visible = false
				child.queue_free()
		if child.name != "Window":
			_aggressive_hide(child)
		else: # Escanear dentro de Window también por si acaso
			for grandchildren in child.get_children():
				if grandchildren is Label:
					var gt = grandchildren.text.to_upper()
					if "LOGISTICA" in gt or "EQUIPAMIENTO" in gt or "CENTRO" in gt:
						grandchildren.text = ""; grandchildren.visible = false; grandchildren.queue_free()

func _connect_to_player_stats():
	var p = get_tree().get_first_node_in_group("player")
	if is_instance_valid(p):
		if not p.stats_changed.is_connected(_on_player_stats_changed):
			p.stats_changed.connect(_on_player_stats_changed)
			print("[INVENTARIO] Enlace de estadísticas establecido con el Piloto.")

func _on_ship_equip_data(data: Dictionary):
	# v263.010: Recibir equipamiento de nave específica y re-renderizar
	var sid = str(data.get("shipId", -1))
	var equip = data.get("equip", {})
	if sid == "-1" or not equip: return
	equipped_by_ship[sid] = equip
	# print("[SHIP-EQUIP] Datos recibidos para nave ", sid, ": w=", equip.get("w",[]).size(), " s=", equip.get("s",[]).size(), " e=", equip.get("e",[]).size())
	# Re-renderizar solo si esta nave está seleccionada actualmente
	if str(selected_hangar_ship_id) == sid or str(current_ship_id) == sid:
		_update_hangar_ui()

func _update_hangar_ui():
	var h = get_node_or_null("Window/TabContainer/Hangar")
	if h and h.has_method("update_ui"): h.update_ui()

func _on_player_stats_changed(p_data: Dictionary):
	# Actualizar saldos locales para que el dibujo de _draw() sea correcto
	if p_data.has("hubs"): hubs = int(p_data["hubs"])
	if p_data.has("ohcu"): ohcu = int(p_data["ohcu"])
	queue_redraw()

func _draw():
	if not visible: return
	var screen_size = get_viewport_rect().size
	var r_size = Vector2(screen_size.x * 0.85, screen_size.y * 0.85)
	var r_pos = (screen_size - r_size) / 2.0
	
	# Actualizar ventana física (contenedor de pestañas)
	var win = get_node_or_null("Window")
	if win:
		win.position = r_pos
		win.custom_minimum_size = r_size
		win.size = r_size
		win.mouse_filter = Control.MOUSE_FILTER_STOP # v244.71: Bloquear click-through
	
	# v244.72: Refuerzo de bloqueo (Invisible Panel que consume eventos)
	var blocker = get_node_or_null("ClickBlocker")
	if not blocker:
		blocker = Control.new(); blocker.name = "ClickBlocker"
		add_child(blocker); move_child(blocker, 0)
	blocker.position = r_pos; blocker.size = r_size
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	
	draw_rect(Rect2(r_pos, r_size), Color(0.02, 0.02, 0.05, 0.98))
	draw_rect(Rect2(r_pos, Vector2(r_size.x, 35)), Color(0, 0.08, 0.12, 1.0))
	draw_rect(Rect2(r_pos, r_size), Color(0, 0.8, 1, 0.5), false, 1.5)
	
	var f = get_theme_font("font")
	draw_string(f, r_pos + Vector2(20, 22), "HUBS: " + _format_val(hubs), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 1, 1))
	draw_string(f, r_pos + Vector2(180, 22), "OHCU: " + _format_val(ohcu), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0, 1))
	
	# Botón X (Cerrar) optimizado para legibilidad y celulares
	draw_rect(Rect2(r_pos.x + r_size.x - 50, r_pos.y+6, 40, 24), Color(0, 1, 1), false, 1.2)
	draw_string(f, r_pos + Vector2(r_size.x-36, 22), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0, 1, 1))

func _format_val(v):
	var s = str(int(v)); var r = ""; var c = 0
	for i in range(s.length()-1,-1,-1):
		r = s[i] + r; c += 1
		if c == 3 and i != 0: r = "." + r; c = 0
	return r

func _input(event):
	# v303.12: Soporte para toques nativos de Android (InputEventScreenTouch) 
	# Evita la pérdida de eventos cuando se emulan clics de mouse.
	var is_click = false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		is_click = true
	elif event is InputEventScreenTouch and event.pressed:
		is_click = true
		
	# v244.75: Las funciones de cerrado de menú (ESC y Botón X) deben funcionar SIEMPRE, incluso si estás escribiendo
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		# v307: Cerrar primero los modales activos por orden de capas (LIFO)
		while active_modales.size() > 0:
			var m = active_modales.pop_back()
			if is_instance_valid(m):
				m.queue_free()
				modal_active = active_modales.size() > 0
				get_viewport().set_input_as_handled()
				return

		if pending_skill_to_equip != null:
			# v301.5: Cancelar equipamiento y volver a la biblioteca
			pending_skill_to_equip = null
			var st = get_node_or_null("Window/TabContainer/Esferas")
			if st and st.has_method("update_ui"):
				# Forzar el subtab de biblioteca (el tab 2 del TabContainer interno de SpheresTab)
				for child in st.get_children():
					if child is TabContainer:
						child.current_tab = 2
						break
				st.update_ui()
			get_viewport().set_input_as_handled()
			return
			
		if pending_sphere_slot >= 0 or pending_sphere_item != null:
			# v760.0: Cancelar selección de esfera (instalación)
			pending_sphere_slot = -1
			pending_sphere_item = null
			var st = get_node_or_null("Window/TabContainer/Esferas")
			if st and st.has_method("update_ui"):
				st.update_ui()
			get_viewport().set_input_as_handled()
			return
			
		if is_open:
			toggle()
			get_viewport().set_input_as_handled()
			return

	if is_click and visible:
		var screen_size = get_viewport_rect().size
		var r_size = Vector2(screen_size.x * 0.85, screen_size.y * 0.85)
		var r_pos = (screen_size - r_size) / 2
		# Tap target de 60x40 para facil toque en celulares (no solapa con el texto M)
		var x_rect = Rect2(r_pos.x + r_size.x - 60, r_pos.y, 60, 40)
		if x_rect.has_point(event.position): 
			toggle()
			get_viewport().set_input_as_handled()
			return

	# v222.98: Bloquear shortcuts de juego (M, F1, etc) si el usuario está escribiendo (Chat, etc)
	var focusNode = get_viewport().gui_get_focus_owner()
	if focusNode is LineEdit or focusNode is TextEdit: return

	var nm = get_node_or_null("/root/NetworkManager")
	if not nm or not nm.is_logged_in: return

	if event.is_action_pressed("ui_inventory"):
		toggle(); get_viewport().set_input_as_handled()
	
	if event is InputEventKey and event.pressed and event.keycode == KEY_M:
		var tabs = get_node_or_null("Window/TabContainer")
		var is_on_map = false
		if tabs and is_open:
			is_on_map = (tabs.get_child(tabs.current_tab).name == "Mapa")
		
		if is_open and is_on_map:
			toggle()
		else:
			if not is_open: toggle()
			if tabs:
				for i in range(tabs.get_child_count()):
					if tabs.get_child(i).name == "Mapa":
						tabs.current_tab = i
						var mt = tabs.get_child(i)
						if mt and "selected_zone_id" in mt:
							mt.selected_zone_id = -1
						break
		get_viewport().set_input_as_handled()

func toggle():
	is_open = !is_open
	visible = is_open
	
	if not is_open:
		# v307: Cerrar de forma limpia cualquier modal huérfano activo al cerrar el inventario
		for m in active_modales:
			if is_instance_valid(m):
				m.queue_free()
		active_modales.clear()
		modal_active = false
		
		# Resetear zona seleccionada al cerrar
		var mt = get_node_or_null("Window/TabContainer/Mapa")
		if mt and "selected_zone_id" in mt:
			mt.selected_zone_id = -1
	
	if is_open: 
		selected_hangar_ship_id = -1
		var mt = get_node_or_null("Window/TabContainer/Mapa")
		if mt and "selected_zone_id" in mt:
			mt.selected_zone_id = -1
		_refresh_data()
	# v302.6: Forzar refresco tras setup para mostrar datos que llegaron durante el frame de carga
	if is_open:
		_update_active_tab_ui()
		# v190.20: PRIORIDAD ABSOLUTA - Mover al frente de la jerarquía UI
		if get_parent():
			get_parent().move_child(self, get_parent().get_child_count() - 1)
			z_index = 100 
	else:
		z_index = 0
		
	queue_redraw()

func _refresh_data():
	if NetworkManager: NetworkManager.send_event("getInventory", {})

func _on_inventory_received(data: Dictionary):
	if data.has("player"): data = data.player
	
	# v210.50: ACTUALIZACIÓN SEGURA (Detección de Datos Parciales)
	if data.has("inventory") or data.has("items"):
		inventory_items = data.get("inventory", data.get("items", []))
	if data.has("equipped"):
		equipped_data = data.equipped
	if data.has("ownedShips"):
		owned_ships = data.ownedShips
	if data.has("currentShipId"):
		current_ship_id = int(data.currentShipId)
	if (data.has("ohcu")): ohcu = int(data.ohcu)
	if (data.has("hubs")): hubs = int(data.hubs)
	
	# v300.05: Sincronizar Gestor de Esferas (Esencial para la nueva arquitectura)
	if spheres_manager == null:
		var player_node = get_tree().get_first_node_in_group("player")
		if is_instance_valid(player_node): spheres_manager = player_node.get_node_or_null("SpheresManager")
	
	# v300.06: NOTIFICAR A MÓDULOS (Refresco de UI en tiempo real)
	# v300.06: El refresco se movió al final para asegurar que todos los datos (incluyendo equippedByShip) estén listos.
	if data.has("gameData"):
		var gd = data.gameData
		if gd.has("pendingClanRequests"): pending_clans = gd.pendingClanRequests
		if gd.has("receivedClanInvites"): received_invites = gd.receivedClanInvites
	
	if data.has("pendingClanRequests"): pending_clans = data.pendingClanRequests
	if data.has("receivedClanInvites"): received_invites = data.receivedClanInvites
		
	if data.has("equippedByShip"):
		# v262.999: Normalizar TODAS las claves a string + diagnóstico
		var raw = data.equippedByShip
		equipped_by_ship = {}
		for key in raw.keys():
			equipped_by_ship[str(key)] = raw[key]
	else:
		pass
	
	if is_open: 
		_update_clan_ui()
		_update_crafting_ui()
		_update_quests_ui()
	
	# v164.11: Sincronizar con el Player (CRÍTICO PARA MMO SYNC)
	# Siempre actualizamos los datos internos aunque la UI esté cerrada
	var p = get_tree().get_first_node_in_group("player")
	if p:
		p.hubs = hubs
		p.ohculianos = ohcu
		if data.has("inventory") or data.has("items"): p.inventory = inventory_items
		if data.has("equipped"): p.equipped = equipped_data
		if data.has("ammo") and typeof(data.ammo) == TYPE_DICTIONARY: p.ammo = data.ammo.duplicate()
		if data.has("selectedAmmo") and typeof(data.selectedAmmo) == TYPE_DICTIONARY: p.selected_ammo = data.selectedAmmo.duplicate()
		if data.has("currentShipId"):
			p.current_ship_id = current_ship_id
			if p.has_method("_setup_ship_visuals"): p._setup_ship_visuals()
		if p.has_method("_recalculate_stats"): p._recalculate_stats()
		elif p.has_method("_emit_stats"): p._emit_stats()
		if p.has_method("update_stats"): 
			p.update_stats({"currentShipId": current_ship_id, "equipped": equipped_data})

	# v303.16: Refresco Diferido (CRÍTICO para Android)
	# Usar call_deferred asegura que el redibujado ocurra en el siguiente frame libre,
	# evitando que la UI se quede "congelada" con los datos viejos.
	call_deferred("_update_active_tab_ui")
	queue_redraw()
	
	# v210.16: Conservar selección si es válida
	var did_preserve = false
	var preserved_id_temp = inv_main_preserve_ship_id
	if inv_main_preserve_ship_id != -1:
		# v308.3: Hay una nave a preservar por acción de equip/unequip reciente
		selected_hangar_ship_id = inv_main_preserve_ship_id
		inv_main_preserve_ship_id = -1
		did_preserve = true
	elif selected_hangar_ship_id == -1:
		selected_hangar_ship_id = current_ship_id
		
	# v308.6: Si modificamos una nave no-activa, pedir su equipamiento definitivo al servidor de inmediato
	if did_preserve and preserved_id_temp != current_ship_id:
		if NetworkManager:
			NetworkManager.send_event("getShipEquip", preserved_id_temp)

func _update_active_tab_ui():
	var tab_container = get_node_or_null("Window/TabContainer")
	if not tab_container: return
	
	var active_tab_name = tab_container.get_child(tab_container.current_tab).name
	match active_tab_name:
		"Hangar": 
			var h = tab_container.get_node_or_null("Hangar")
			if h and h.has_method("update_ui"): h.update_ui()
		"Esferas": 
			var s = tab_container.get_node_or_null("Esferas")
			if s and s.has_method("update_ui"): s.update_ui()
		"Armas":
			var wt = tab_container.get_node_or_null("Armas")
			if wt and wt.has_method("update_ui"): wt.update_ui()
		"Talentos":
			var tl = tab_container.get_node_or_null("Talentos")
			if tl and tl.has_method("update_ui"): tl.update_ui()
		"Tienda":
			var t = tab_container.get_node_or_null("Tienda")
			if t and t.has_method("update_ui"): t.update_ui()
		"Equipo": 
			var pt = tab_container.get_node_or_null("Equipo")
			if pt and pt.has_method("update_ui"): pt.update_ui()
		"Mapa": 
			var mn = tab_container.get_node_or_null("Mapa")
			if mn and mn.has_method("update_ui"): mn.update_ui()
		"Clan": 
			var cn = tab_container.get_node_or_null("Clan")
			if cn and cn.has_method("update_ui"): cn.update_ui()
		"Crafteo": 
			var ct = tab_container.get_node_or_null("Crafteo")
			if ct and ct.has_method("update_ui"): ct.update_ui()
		"Misiones":
			var qt = tab_container.get_node_or_null("Misiones")
			if qt and qt.has_method("update_ui"): qt.update_ui()
	
	queue_redraw()

# v300.10: Limpieza de código muerto tras modularización total.
# Las funciones de UI ahora residen en sus respectivos módulos bajo /inventory/

func _on_clan_data_received(data):
	clan_data = data
	_update_clan_ui()

func _on_clan_member_status(data):
	if clan_data and clan_data.has("members"):
		var target_user = str(data.get("user", "")).to_lower()
		for m in clan_data["members"]:
			if str(m.get("username", "")).to_lower() == target_user:
				m["online"] = data["online"]
				break
	_update_clan_ui()

func _update_clan_ui():
	var ct = get_node_or_null("Window/TabContainer/Clan")
	if not ct:
		var tabs = get_node_or_null("Window/TabContainer")
		if tabs:
			ct = Control.new(); ct.name = "Clan"; tabs.add_child(ct)
			ct.set_script(ClanTabScript)
			if ct.has_method("setup"): ct.setup(self)
			if NetworkManager: NetworkManager.send_event("getClanData", {})
	
	if ct and ct.has_method("update_ui"): ct.update_ui()

func _update_weapons_ui():
	var wt = get_node_or_null("Window/TabContainer/Armas")
	if not wt:
		var tabs = get_node_or_null("Window/TabContainer")
		if tabs:
			wt = Control.new(); wt.name = "Armas"; tabs.add_child(wt)
			wt.set_script(WeaponsTabScript)
			if wt.has_method("setup"): wt.setup(self)
			
			# Reordenar pestaña para que aparezca al lado de Esferas (Esferas suele ser la 2da o 3ra pestaña)
			# Hangar es 0, Esferas es 1. Queremos que Armas sea la pestaña 2.
			tabs.move_child(wt, 2)
	
	if wt and wt.has_method("update_ui"): wt.update_ui()

func _update_map_ui():
	var mt = get_node_or_null("Window/TabContainer/Mapa")
	if not mt:
		var tabs = get_node_or_null("Window/TabContainer")
		if tabs:
			mt = Control.new(); mt.name = "Mapa"; tabs.add_child(mt)
			mt.set_script(MapTabScript)
			if mt.has_method("setup"): mt.setup(self)
	
	if mt and mt.has_method("update_ui"): mt.update_ui()

func _update_crafting_ui():
	var ct = get_node_or_null("Window/TabContainer/Crafteo")
	if not ct:
		var tabs = get_node_or_null("Window/TabContainer")
		if tabs:
			ct = Control.new(); ct.name = "Crafteo"; tabs.add_child(ct)
			ct.set_script(CraftingTabScript)
			if ct.has_method("setup"): ct.setup(self)
	
	if ct and ct.has_method("update_ui"): ct.update_ui()

# v262.520: Traductor de ID de ítem → código de slot (w/s/e/x)
func _get_slot_from_id(item_id: String) -> String:
	if item_id.begins_with("las") or item_id.begins_with("w"): return "w"
	elif item_id.begins_with("sh") or item_id.begins_with("s"): return "s"
	elif item_id.begins_with("en") or item_id.begins_with("e"):
		# v760.0: Las esferas (esfera_*) son consumibles instalables, no motores
		if item_id.begins_with("esfera_"): return "x"
		return "e"
	else: return "x"

func _on_game_notification(data: Dictionary):
	if not is_open: return
	var msg = str(data.get("msg", ""))
	var type = str(data.get("type", "info"))
	
	# v244.101: Si el inventario está abierto y hay un error de flota/piloto, mostrar modal explícito
	if type == "error":
		var m_upper = msg.to_upper()
		if "FLOTA" in m_upper or "PILOTO" in m_upper or "CLAN" in m_upper or "SOLICITUD" in m_upper or "LÍDER" in m_upper or "TAG" in m_upper:
			_show_result_modal("CENTRO DE COMANDO: ERROR", msg)

func _show_modal(title, msg, on_confirm, custom_node = null):
	modal_active = true
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "ModalCanvasLayer"
	canvas_layer.layer = 120
	get_tree().root.add_child(canvas_layer)
	active_modales.append(canvas_layer)
	
	var overlay = Control.new()
	overlay.name = "ModalOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas_layer.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var p = PanelContainer.new(); p.custom_minimum_size = Vector2(420, 220)
	overlay.add_child(p)
	
	# Centrado dinámico robusto
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.offset_left = -p.custom_minimum_size.x / 2.0
	p.offset_right = p.custom_minimum_size.x / 2.0
	p.offset_top = -p.custom_minimum_size.y / 2.0
	p.offset_bottom = p.custom_minimum_size.y / 2.0
	
	var sb = StyleBoxFlat.new(); sb.bg_color = Color(0.01, 0.04, 0.08, 1); sb.border_width_top = 3; sb.border_color = Color.CYAN; p.add_theme_stylebox_override("panel", sb)
	var v = VBoxContainer.new(); v.add_theme_constant_override("separation", 20); p.add_child(v)
	var tl = Label.new(); tl.text = title; tl.horizontal_alignment = 1; tl.modulate = Color.CYAN; tl.add_theme_font_size_override("font_size", 14); v.add_child(tl)
	var rt = RichTextLabel.new(); rt.bbcode_enabled = true; rt.text = "[center]" + msg + "[/center]"; rt.fit_content = true; v.add_child(rt)
	if custom_node: v.add_child(custom_node)
	var hb = HBoxContainer.new(); hb.alignment = BoxContainer.ALIGNMENT_CENTER; hb.add_theme_constant_override("separation", 20); v.add_child(hb)
	var bc = Button.new(); bc.text = "  CONFIRMAR  "; bc.custom_minimum_size = Vector2(120, 40); bc.pressed.connect(func(): 
		on_confirm.call()
		if canvas_layer in active_modales: active_modales.erase(canvas_layer)
		canvas_layer.queue_free()
		modal_active = active_modales.size() > 0
	); hb.add_child(bc)
	var bx = Button.new(); bx.text = "   CANCELAR   "; bx.custom_minimum_size = Vector2(120, 40); bx.pressed.connect(func(): 
		if canvas_layer in active_modales: active_modales.erase(canvas_layer)
		canvas_layer.queue_free()
		modal_active = active_modales.size() > 0
	); hb.add_child(bx)

func _show_result_modal(title, msg):
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "ResultCanvasLayer"
	canvas_layer.layer = 121
	get_tree().root.add_child(canvas_layer)
	active_modales.append(canvas_layer)
	
	var overlay = Control.new()
	overlay.name = "ResultOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas_layer.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var p = PanelContainer.new(); p.custom_minimum_size = Vector2(380, 160)
	overlay.add_child(p)
	
	# Centrado dinámico robusto
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.offset_left = -p.custom_minimum_size.x / 2.0
	p.offset_right = p.custom_minimum_size.x / 2.0
	p.offset_top = -p.custom_minimum_size.y / 2.0
	p.offset_bottom = p.custom_minimum_size.y / 2.0
	
	var sb = StyleBoxFlat.new(); sb.bg_color = Color(0,0.08,0.04, 1); sb.border_width_top = 2; sb.border_color = Color.GREEN; p.add_theme_stylebox_override("panel", sb)
	var v = VBoxContainer.new(); v.add_theme_constant_override("separation", 15); p.add_child(v)
	var tl = Label.new(); tl.text = title; tl.modulate = Color.GREEN; tl.horizontal_alignment = 1; v.add_child(tl)
	var m = Label.new(); m.text = msg; m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; m.horizontal_alignment = 1; v.add_child(m)
	var b = Button.new(); b.text = "ENTENDIDO"; b.custom_minimum_size = Vector2(100, 35); b.pressed.connect(func(): 
		if canvas_layer in active_modales: active_modales.erase(canvas_layer)
		canvas_layer.queue_free()
		modal_active = active_modales.size() > 0
	); v.add_child(b)

func _update_quests_ui():
	var qt = get_node_or_null("Window/TabContainer/Misiones")
	if not qt:
		var tabs = get_node_or_null("Window/TabContainer")
		if tabs:
			qt = Control.new(); qt.name = "Misiones"; tabs.add_child(qt)
			qt.set_script(QuestsTabScript)
			if qt.has_method("setup"): qt.setup(self)
	
	if qt and qt.has_method("update_ui"): qt.update_ui()

extends Node

# NetworkManager.gd (v142.10 GLOBAL SYNC - RECOVERY MODE)
# Manager de red robusto con todas las señales requeridas para evitar crasheos.

signal connection_established
signal connection_lost
signal player_auth_success(data)
signal login_success(data)
signal auth_success(data)
signal auth_error(msg)
signal spawn_entity(data)
signal remove_entity(id)
signal update_wallet(data)
signal combat_log(msg)
signal party_invitation(data)
signal party_update(data)
signal chat_message(data)
signal chat_received(data)
signal inventory_data(data)
signal player_updated(data)
signal player_stat_sync(data)
signal player_disconnected(id)
signal player_fired(data)
signal enemy_updated(data)
signal enemy_fired(data)
signal enemy_dead(data)
signal reward_received(data)
signal level_up(data)
signal admin_config_updated(data)
signal remote_skill_used(data)
signal enemy_kill_session(data)
signal enemy_action(data)
signal enemy_aura(data)

signal loot_spawned(data)
signal loot_despawned(data)
signal loot_content(data)

signal enemy_damaged(data)
signal enemy_healed(data)
signal boss_effect(data)
signal boss_colors_start(data)
signal boss_colors_end(data)
signal blind_state(data)
signal slow_state(data)
signal stun_state(data)
signal hook_pulled(data)
signal config_updated(data)
signal game_notification(data)
signal clear_zone_entities(zoneId)
signal clear_enemy_projectiles(data)
signal online_count_updated(count)
signal clan_data(data)
signal clan_member_status(data)
signal spawn_area(data)
signal remove_area(data)
signal beacon_pulse(data)
signal taunt_event(data)
signal blindness_event(data)
signal interference_event(data) # v268.30
signal freeze_event(data) # v268.40
signal ship_equip_data(data)
signal environment_damaged(data) # v266.350: Daño Ambiental
signal trade_invitation_received(data) # v300.100
signal trade_started(data)
signal trade_partner_update(data)
signal trade_partner_ready(data)
signal trade_success(data)
signal trade_cancelled(data)
signal extraction_queue_joined(data) # v2.2
signal extraction_match_found(data)
signal extraction_match_countdown(data) # v2.5
signal extraction_match_cancelled(data)
signal extraction_start(data)
signal extraction_countdown(data)
signal extraction_cancelled(data)
signal extraction_final_success(data)
signal extraction_failed(data)
signal raid_time_update(data)

signal altar_defense_invitation(data)
signal altar_defense_cancelled(data)
signal altar_defense_success(data)
signal altar_state_update(data)
signal update_exit_portals(data)

signal arena_queue_joined(data)
signal arena_queue_left
signal arena_queue_update(data)
signal arena_match_started(data)
signal arena_state_update(data)
signal arena_finished(data)

signal vault_data(data)
signal vault_updated(data)
signal housing_state(data)
signal socket_event_received(event_name, data)

signal status_effects_sync(data)


var socket: WebSocketPeer = WebSocketPeer.new()
var network_connected: bool = false
var online_count: int = 1 # v220.20: Conteo global persistente
var was_manual_logout: bool = false # v221.21: Evitar bucle de login en debug
var my_socket_id: String = "" # v168.04: ID Local para evitar self-cloning
var auth_token: String = ""
var login_name: String = ""
var is_logged_in: bool = false # v244.60: Control global de estado de sesión
var server_config: Dictionary = {} # v301.7: Cache local de la configuración del servidor
var ping_start_time: int = 0
var current_ms: int = 0
var is_registering: bool = false # v244.10: Soporte para creación de cuenta
var current_user_data: Dictionary = {} 
var current_arena_data: Dictionary = {}

# Sincronización segura del tiempo del servidor (Evita hacks de hora local)
var time_synced: bool = false
var ticks_at_sync: int = 0
var server_time_at_sync: int = 0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

func connect_to_server(ip: String, port: int, p_name: String, p_token: String = "", registering: bool = false):
	is_registering = registering

	var state = socket.get_ready_state()
	if state != WebSocketPeer.STATE_CLOSED and state != WebSocketPeer.STATE_CLOSING:
		print("[NET] Socket activo detectado. Cerrando para nueva conexión...")
		socket.close()
		socket = WebSocketPeer.new()
		socket.inbound_buffer_size = 1024 * 1024
		socket.outbound_buffer_size = 1024 * 1024
		socket.max_queued_packets = 2048
		network_connected = false
		
	# Asegurar que el socket inicial también tenga el buffer configurado
	socket.inbound_buffer_size = 1024 * 1024
	socket.outbound_buffer_size = 1024 * 1024
	socket.max_queued_packets = 2048

	login_name = p_name
	auth_token = p_token
	var url = ""
	if ip.contains(".") and not ip.is_valid_ip_address():
		# Es un dominio (ej. Cloudflare Tunnel), usamos WSS y omitimos el puerto manual si es estándar
		url = "wss://" + ip + "/socket.io/?EIO=4&transport=websocket"
	else:
		# Es una IP clásica (ej. 127.0.0.1 o tu IP pública), usamos WS y el puerto
		url = "ws://" + str(ip) + ":" + str(port) + "/socket.io/?EIO=4&transport=websocket"
		
	print("[NET] Conectando a ", url)
	var err = socket.connect_to_url(url)
	if err != OK:
		print("[NET-ERR] Error al iniciar socket: ", err)
		network_connected = false

func logout():
	print("[NET] Cerrando sesión y limpiando estado...")
	was_manual_logout = true
	network_connected = false
	is_logged_in = false
	auth_token = ""
	login_name = ""
	socket.close()
	socket = WebSocketPeer.new()

func _process(_delta):
	socket.poll()
	var state = socket.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		if not network_connected:
			network_connected = true
			connection_established.emit()
			
		while socket.get_available_packet_count():
			var p = socket.get_packet().get_string_from_utf8()
			_handle_packet(p)
			
	elif state == WebSocketPeer.STATE_CLOSED:
		if network_connected:
			network_connected = false
			connection_lost.emit()
			print("[NET] Desconectado.")

func _handle_packet(p_string: String):
	if p_string.begins_with("2") or p_string.begins_with("3"): 
		if p_string == "2": socket.send_text("3")
		return
		
	if p_string.begins_with("0"):
		socket.send_text("40")
		return
		
	if p_string.begins_with("40"):
		network_connected = true
		connection_established.emit()
		_start_ping_loop()
		if is_registering:
			send_event("register", {"user": login_name, "password": auth_token})
		else:
			send_event("login", {"user": login_name, "password": auth_token})
		return
		
	if p_string.begins_with("42"):
		var json_str = p_string.substr(2)
		var json = JSON.new()
		var res = json.parse(json_str)
		if res == OK:
			var arr = json.data
			if typeof(arr) == TYPE_ARRAY and arr.size() >= 1:
				var event_data = null
				if arr.size() >= 2:
					event_data = arr[1]
				_dispatch_event(arr[0], event_data)

func _dispatch_event(e_name: String, e_data: Variant):
	match e_name:
		"loginSuccess", "authSuccess":
			is_logged_in = true
			my_socket_id = str(e_data.get("socketId", ""))
			current_user_data = e_data
			if e_data.has("adminConfig"):
				server_config = e_data.adminConfig
			
			auth_success.emit(e_data)
			login_success.emit(e_data)
			player_auth_success.emit(e_data)
			
			if e_data.has("adminConfig"):
				config_updated.emit(e_data.adminConfig)
				admin_config_updated.emit(e_data.adminConfig)
		"authError":
			auth_error.emit(e_data)
		"spawnEntity", "enemySpawn":
			spawn_entity.emit(e_data)
			enemy_updated.emit(e_data)
		"removeEntity":
			remove_entity.emit(str(e_data.get("id", "")))
		"playerMoved", "newPlayer", "currentPlayers":
			if typeof(e_data) == TYPE_DICTIONARY:
				if e_name == "newPlayer" or e_name == "playerMoved" or e_data.has("id"):
					if not e_data.has("id") and e_data.has("socketId"): e_data["id"] = str(e_data["socketId"])
					if e_data.has("id") and str(e_data.id) != str(my_socket_id):
						if e_name == "newPlayer": print("[NET] Nuevo Piloto Detectado: ", e_data.id)
						_dispatch_single_player(e_data)
				else:
					# currentPlayers list logic
					print("[NET] Sincronía Inicial de Pilotos: ", e_data.size(), " encontrados.")
					for p_id in e_data: 
						if str(p_id) == str(my_socket_id): continue
						var p_val = e_data[p_id]
						if typeof(p_val) == TYPE_DICTIONARY:
							p_val["id"] = str(p_id)
							_dispatch_single_player(p_val)
		"updateEntity":
			if typeof(e_data) == TYPE_DICTIONARY:
				if str(e_data.get("id", "")) != my_socket_id:
					_dispatch_single_player(e_data)
		"playerUpdated":
			# v221.50: NO filtrar self - el jugador necesita recibir sus propios cambios de PvP
			if typeof(e_data) == TYPE_DICTIONARY and e_data.has("id"):
				player_updated.emit(e_data)
		"onlineCount":
			online_count = int(e_data)
			online_count_updated.emit(online_count)
		"changeZoneDone":
			# Limpia enemigos/players viejos antes de cargar los de la nueva zona
			clear_zone_entities.emit(e_data)
		"enemiesMoved", "currentEnemies":
			if typeof(e_data) == TYPE_DICTIONARY:
				if e_data.has("id"):
					enemy_updated.emit(e_data)
				else:
					for en_id in e_data: 
						var e_val = e_data[en_id]
						if typeof(e_val) == TYPE_DICTIONARY:
							e_val["id"] = str(en_id)
							enemy_updated.emit(e_val)
		"walletData": update_wallet.emit(e_data)
		"combatLog":
			var msg = ""
			if typeof(e_data) == TYPE_DICTIONARY:
				msg = e_data.get("msg", "")
			else:
				msg = str(e_data)
			combat_log.emit(msg)
		"partyInvitation": party_invitation.emit(e_data)
		"partyUpdate": party_update.emit(e_data)
		"chatMessage":
			chat_message.emit(e_data)
			chat_received.emit(e_data)
		"playerFire":
			if str(e_data.get("id", "")) != my_socket_id:
				_dispatch_single_player(e_data, "player_fired")
		"enemyFire", "serverEnemyFire": enemy_fired.emit(e_data)
		"serverEnemyAction": enemy_action.emit(e_data)
		"serverEnemyAura": enemy_aura.emit(e_data)
		"enemyDamaged": enemy_damaged.emit(e_data)
		"enemyHealed": enemy_healed.emit(e_data)
		"enemyDead", "serverEnemyDead": enemy_dead.emit(e_data)
		"enemyKillSession": enemy_kill_session.emit(e_data)
		"bossEffect": boss_effect.emit(e_data)
		"bossColorsStart": boss_colors_start.emit(e_data)
		"bossColorsEnd": boss_colors_end.emit(e_data)
		"lootSpawned": loot_spawned.emit(e_data)
		"lootDespawned": loot_despawned.emit(e_data)
		"lootContent": loot_content.emit(e_data)
		"environmentDamage": environment_damaged.emit(e_data)
		"clanMemberStatus": clan_member_status.emit(e_data)
		"spawnArea": spawn_area.emit(e_data)
		"removeArea": remove_area.emit(e_data)
		"beaconPulse": beacon_pulse.emit(e_data)
		"tauntEvent": taunt_event.emit(e_data)
		"blindState": blind_state.emit(e_data)
		"blindnessEvent": blindness_event.emit(e_data)
		"interferenceEvent": interference_event.emit(e_data) # v268.30
		"freezeEvent": freeze_event.emit(e_data) # v268.40
		"slowState": slow_state.emit(e_data)
		"stunState": stun_state.emit(e_data)
		"hookPulled": hook_pulled.emit(e_data)
		"statusEffectsSync": status_effects_sync.emit(e_data)
		"gameNotification": game_notification.emit(e_data)
		"shipEquipData": ship_equip_data.emit(e_data)
		"clearEnemyProjectiles": clear_enemy_projectiles.emit(e_data)
		"adminConfigUpdated", "adminConfigLoaded": 
			server_config = e_data
			config_updated.emit(e_data)
			admin_config_updated.emit(e_data)
		"rewardReceived", "serverReward": reward_received.emit(e_data)
		"levelUp", "serverLevelUp": level_up.emit(e_data)
		"inventoryData", "inventorySync": 
			# v241.10: Unificación de Sincronía (Soporta Player, Items o Raw)
			var final_data = e_data
			if typeof(e_data) == TYPE_DICTIONARY and e_data.has("player"):
				final_data = e_data["player"]
			elif typeof(e_data) == TYPE_DICTIONARY and e_data.has("items"):
				final_data = e_data["items"]
			
			inventory_data.emit(final_data)
		"playerStatSync":
			if typeof(e_data) == TYPE_DICTIONARY:
				if str(e_data.get("id", "")) != my_socket_id:
					# v214.170: Sincronizar visualmente al aliado con sus esferas nuevas
					_dispatch_single_player(e_data, "player_stat_sync")
				else:
					player_stat_sync.emit(e_data)
		"remotePlayerUsedSkill":
			if typeof(e_data) == TYPE_DICTIONARY:
				remote_skill_used.emit(e_data)
		"remoteStatSync":
			if typeof(e_data) == TYPE_DICTIONARY:
				if str(e_data.get("id", "")) != my_socket_id:
					_dispatch_single_player(e_data, "player_stat_sync")
				else:
					player_stat_sync.emit(e_data)
		"rewardReceived": reward_received.emit(e_data)
		"playerDisconnected":
			player_disconnected.emit(str(e_data))
		"clanData": clan_data.emit(e_data)
		"vaultData": vault_data.emit(e_data)
		"vaultUpdated": vault_updated.emit(e_data)
		"clanMemberStatus": clan_member_status.emit(e_data)
		"pong_custom":
			current_ms = int(Time.get_ticks_msec() - ping_start_time)
			send_event("latencyUpdate", current_ms)
			if typeof(e_data) == TYPE_DICTIONARY and e_data.has("serverTime"):
				_sync_server_time(int(e_data["serverTime"]), current_ms)
		"tradeInvitationReceived": trade_invitation_received.emit(e_data)
		"tradeStarted": trade_started.emit(e_data)
		"tradePartnerUpdate": trade_partner_update.emit(e_data)
		"tradePartnerReady": trade_partner_ready.emit(e_data)
		"tradeSuccess": 
			trade_success.emit(e_data)
			# v300.650: AUTO-SYNC TRAS TRADE EXITOSO
			if typeof(e_data) == TYPE_DICTIONARY and e_data.has("inventoryData"):
				var inv_p = e_data["inventoryData"]
				if inv_p.has("player"): inv_p = inv_p["player"]
				inventory_data.emit(inv_p)
		"tradeCancelled": trade_cancelled.emit(e_data)
		"extraction_queue_joined": extraction_queue_joined.emit(e_data)
		"extraction_match_found": extraction_match_found.emit(e_data)
		"extraction_match_countdown": extraction_match_countdown.emit(e_data)
		"extraction_match_cancelled": extraction_match_cancelled.emit(e_data)
		"extraction_start": extraction_start.emit(e_data)
		"extraction_countdown": extraction_countdown.emit(e_data)
		"extraction_cancelled": extraction_cancelled.emit(e_data)
		"extraction_final_success": extraction_final_success.emit(e_data)
		"extraction_failed": extraction_failed.emit(e_data)
		"raid_time_update": raid_time_update.emit(e_data)
		"altarDefenseInvitation": altar_defense_invitation.emit(e_data)
		"altarDefenseCancelled": altar_defense_cancelled.emit(e_data)
		"altarDefenseSuccess": altar_defense_success.emit(e_data)
		"altarStateUpdate": altar_state_update.emit(e_data)
		"updateExitPortals": update_exit_portals.emit(e_data)
		"arenaQueueJoined": arena_queue_joined.emit(e_data)
		"arenaQueueLeft": arena_queue_left.emit()
		"arenaQueueUpdate": arena_queue_update.emit(e_data)
		"arenaMatchStarted":
			current_arena_data = e_data
			arena_match_started.emit(e_data)
		"arenaStateUpdate": arena_state_update.emit(e_data)
		"arenaFinished": arena_finished.emit(e_data)
		"housingState":
			housing_state.emit(e_data)
			socket_event_received.emit(e_name, e_data)
		_:
			socket_event_received.emit(e_name, e_data)


func _dispatch_single_player(p_data: Dictionary, p_signal: String = "player_updated"):
	# v167.96: No normalizar agresivamente. Confiar en el 'id' del objeto si existe.
	if p_signal == "player_updated": player_updated.emit(p_data)
	elif p_signal == "player_fired": player_fired.emit(p_data)
	elif p_signal == "player_stat_sync": player_stat_sync.emit(p_data)
	
	# v214.99: SINCRONÍA VISUAL DE ESFERAS (Recuperación de Activos Aliados)
	if p_data.has("id"):
		var pid = str(p_data.id)
		var world = get_tree().get_first_node_in_group("world_node")
		if world:
			# Buscar la nave remota en el diccionario del mundo (mucho más rápido y seguro)
			var rp = null
			if "remote_players" in world and world.remote_players.has(pid):
				rp = world.remote_players[pid]
			if is_instance_valid(rp):
				var sm = rp.get_node_or_null("SpheresManager")
				if not is_instance_valid(sm):
					# Inyectar Manager si no existe
					var sm_script = load("res://scripts/systems/SpheresManager.gd")
					if sm_script:
						sm = Node2D.new(); sm.set_script(sm_script)
						sm.name = "SpheresManager"; rp.add_child(sm)
						print("[NET] SpheresManager inyectado en aliado: ", pid)
				
				if is_instance_valid(sm):
					var sps = p_data.get("spheres")
					if typeof(sps) == TYPE_ARRAY:
						# Actualizar los datos (La esfera hará el resto en su _process)
						for i in range(min(sps.size(), 4)):
							var sph_in_data = sps[i]
							if typeof(sph_in_data) == TYPE_DICTIONARY:
								sm.equip_item(i, sph_in_data)
						sm.emit_signal("spheres_updated")

func send_event(p_ename: String, p_val: Variant):
	if p_ename == "changeZone":
		var z_str = str(p_val)
		if GameConstants.get("MAPS_CONFIG") and GameConstants.MAPS_CONFIG.has(z_str):
			var map_cfg = GameConstants.MAPS_CONFIG[z_str]
			var pvp_mode = map_cfg.get("pvpMode", "tranquila")
			if pvp_mode == "mandatory" or pvp_mode == "full_drop" or pvp_mode == "partial_drop":
				show_pvp_warning(p_val, pvp_mode)
				return
	_send_event_direct(p_ename, p_val)

func _send_event_direct(p_ename: String, p_val: Variant):
	if network_connected:
		var pack = "42" + JSON.stringify([p_ename, p_val])
		socket.send_text(pack)

func show_pvp_warning(target_zone_id: Variant, pvp_mode: String):
	# Construir modal independiente premium con la misma estética de viaje
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "PvpWarningCanvas"
	canvas_layer.layer = 125
	get_tree().root.add_child(canvas_layer)
	
	var overlay = Control.new()
	overlay.name = "PvpWarningOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas_layer.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Panel del modal centrado
	var p = PanelContainer.new()
	p.custom_minimum_size = Vector2(430, 240)
	overlay.add_child(p)
	
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
	
	# Estilo oscuro y borde cian neón/rojo
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.01, 0.04, 0.08, 0.98)
	sb.border_width_top = 4
	sb.border_color = Color(1.0, 0.2, 0.2) if pvp_mode == "full_drop" else (Color(1.0, 0.5, 0.1) if pvp_mode == "partial_drop" else Color(0.9, 0.5, 0.1))
	p.add_theme_stylebox_override("panel", sb)
	
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.add_child(v)
	
	# Margen superior
	var margin_top = Control.new()
	margin_top.custom_minimum_size.y = 5
	v.add_child(margin_top)
	
	# Título
	var tl = Label.new()
	tl.text = "🚨 ADVERTENCIA CRÍTICA 🚨" if (pvp_mode == "full_drop" or pvp_mode == "partial_drop") else "🚨 ADVERTENCIA DE SEGURIDAD 🚨"
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.modulate = Color(1.0, 0.2, 0.2) if (pvp_mode == "full_drop" or pvp_mode == "partial_drop") else Color(0.9, 0.5, 0.1)
	tl.add_theme_font_size_override("font_size", 13)
	v.add_child(tl)
	
	# Descripción
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true
	var desc = ""
	if pvp_mode == "mandatory":
		desc = "[center]El sector al que intentas entrar es una:\n\n[color=#ff5555][b]🔥 ZONA DE COMBATE PVP OBLIGATORIO 🔥[/b][/color]\n\n¿Estás seguro de que deseas ingresar?[/center]"
	elif pvp_mode == "full_drop":
		desc = "[center]¡ATENCIÓN PILOTO! El sector tiene:\n[color=#ff3333][b]⚡ PVP OBLIGATORIO Y PÉRDIDA TOTAL DE ITEMS ⚡[/b][/color]\n\nSi eres derrotado en este mapa, [color=yellow][b]perderás y dropearás absolutamente todo[/b][/color] lo que tengas equipado y en el inventario.\n\n¿Deseas ingresar bajo tu propio riesgo?[/center]"
	elif pvp_mode == "partial_drop":
		desc = "[center]¡ATENCIÓN PILOTO! El sector tiene:\n[color=#ffaa33][b]⚡ PVP OBLIGATORIO Y PÉRDIDA DE INVENTARIO ⚡[/b][/color]\n\nSi eres derrotado en este mapa, [color=yellow][b]perderás todo tu inventario[/b][/color], pero conservarás los items equipados.\n\n¿Deseas ingresar bajo tu propio riesgo?[/center]"
	rt.text = desc
	rt.fit_content = true
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(rt)
	
	# Contenedor de Botones
	var hb = HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 25)
	v.add_child(hb)
	
	var bc = Button.new()
	bc.text = "  ENTRAR  "
	bc.custom_minimum_size = Vector2(130, 42)
	bc.add_theme_font_size_override("font_size", 10)
	bc.pressed.connect(func():
		_send_event_direct("changeZone", target_zone_id)
		canvas_layer.queue_free()
	)
	hb.add_child(bc)
	
	var bx = Button.new()
	bx.text = " CANCELAR "
	bx.custom_minimum_size = Vector2(130, 42)
	bx.add_theme_font_size_override("font_size", 10)
	bx.pressed.connect(func():
		canvas_layer.queue_free()
	)
	hb.add_child(bx)

func _start_ping_loop():
	await get_tree().create_timer(1.0).timeout 
	while network_connected:
		ping_start_time = Time.get_ticks_msec()
		send_event("ping_custom", {})
		await get_tree().create_timer(3.0).timeout

func _sync_server_time(server_time_ms: int, latency_ms: int):
	ticks_at_sync = Time.get_ticks_msec()
	server_time_at_sync = server_time_ms + int(latency_ms / 2.0)
	time_synced = true
	# print("[NET-TIME] Sincronizado: server_time=", server_time_at_sync, " ticks=", ticks_at_sync)

func get_secure_server_time_ms() -> int:
	if not time_synced:
		# Fallback seguro: hora del sistema en UTC
		return int(Time.get_unix_time_from_system() * 1000)
	var elapsed = Time.get_ticks_msec() - ticks_at_sync
	return server_time_at_sync + elapsed

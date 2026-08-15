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
signal wind_push(data)
signal config_updated(data)
signal game_notification(data)
signal unlocks_updated(unlocks) # v600.0: Desbloqueos obtenidos por misiones
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
signal market_data(data) # v500.0: Casa de Subastas
signal market_update(data)
signal market_purchase_result(data)
signal market_mailbox_updated(data)
signal socket_event_received(event_name, data)

signal status_effects_sync(data)
signal battle_pass_state(data)
signal combat_meter_update(data)


var socket: WebSocketPeer = WebSocketPeer.new()
var network_connected: bool = false
var online_count: int = 1 # v220.20: Conteo global persistente
var was_manual_logout: bool = false # v221.21: Evitar bucle de login en debug
var my_socket_id: String = "" # v168.04: ID Local para evitar self-cloning
var auth_token: String = ""
var login_name: String = ""
var is_logged_in: bool = false # v244.60: Control global de estado de sesión
var server_config: Dictionary = {} # v301.7: Cache local de la configuración del servidor
var completed_quests_cache: Array = [] # v400.0: Misiones completadas (para requisitos de equipamiento)
var active_quests_cache: Array = [] # v600.1: Misiones activas (portales sellados por misión)
var unlocks_cache: Array = [] # v600.0: Desbloqueos obtenidos (portales, armas, habilidades, talentos)
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
			
			# v400.0: Solicitar misiones completadas para validar requisitos de equipamiento
			send_event("getQuestsState", {})
			
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
		"windPush": wind_push.emit(e_data)
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
			
			# v600.0: Cachear desbloqueos del perfil
			if typeof(final_data) == TYPE_DICTIONARY and final_data.has("unlocks") and typeof(final_data["unlocks"]) == TYPE_ARRAY:
				unlocks_cache = final_data["unlocks"]
				unlocks_updated.emit(unlocks_cache)
			
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
		"marketData": market_data.emit(e_data) # v500.0: Casa de Subastas
		"marketUpdate": market_update.emit(e_data)
		"marketPurchaseResult": market_purchase_result.emit(e_data)
		"marketMailboxUpdated": market_mailbox_updated.emit(e_data)
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
		"battlePassState":
			battle_pass_state.emit(e_data)
			socket_event_received.emit(e_name, e_data)
		"combatMeterUpdate":
			combat_meter_update.emit(e_data)
		"questsStateData":
			# v400.0: Cachear misiones completadas para validar requisitos de equipamiento
			if typeof(e_data) == TYPE_DICTIONARY and e_data.has("completed"):
				completed_quests_cache = e_data["completed"]
			# v600.1: Cachear misiones activas (para portales sellados por misión)
			if typeof(e_data) == TYPE_DICTIONARY and e_data.has("active") and typeof(e_data["active"]) == TYPE_ARRAY:
				active_quests_cache = e_data["active"]
			# v600.0: Cachear desbloqueos obtenidos
			if typeof(e_data) == TYPE_DICTIONARY and e_data.has("unlocks") and typeof(e_data["unlocks"]) == TYPE_ARRAY:
				unlocks_cache = e_data["unlocks"]
				unlocks_updated.emit(unlocks_cache)
			socket_event_received.emit(e_name, e_data)
		"unlocksUpdated":
			# v600.0: El servidor notificó desbloqueos nuevos
			if typeof(e_data) == TYPE_ARRAY:
				unlocks_cache = e_data
				unlocks_updated.emit(unlocks_cache)
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
		var z_str = ""
		if typeof(p_val) == TYPE_DICTIONARY:
			z_str = str(p_val.get("zoneId", "1"))
		else:
			z_str = str(p_val)
			
		if GameConstants.get("MAPS_CONFIG") and GameConstants.MAPS_CONFIG.has(z_str):
			var map_cfg = GameConstants.MAPS_CONFIG[z_str]
			var pvp_mode = map_cfg.get("pvpMode", "tranquila")
			if pvp_mode == "mandatory" or pvp_mode == "full_drop" or pvp_mode == "partial_drop" or pvp_mode == "inferno":
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
	sb.bg_color = Color(0.08, 0.0, 0.0, 0.98) if pvp_mode == "inferno" else Color(0.01, 0.04, 0.08, 0.98)
	sb.border_width_top = 4
	sb.border_color = Color(1.0, 0.0, 0.0) if pvp_mode == "inferno" else (Color(1.0, 0.2, 0.2) if pvp_mode == "full_drop" else (Color(1.0, 0.5, 0.1) if pvp_mode == "partial_drop" else Color(0.9, 0.5, 0.1)))
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
	tl.text = "🔥 INFIERNO - ¡NO HAY RETORNO! 🔥" if pvp_mode == "inferno" else ("🚨 ADVERTENCIA CRÍTICA 🚨" if (pvp_mode == "full_drop" or pvp_mode == "partial_drop") else "🚨 ADVERTENCIA DE SEGURIDAD 🚨")
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.modulate = Color(1.0, 0.0, 0.0) if pvp_mode == "inferno" else (Color(1.0, 0.2, 0.2) if (pvp_mode == "full_drop" or pvp_mode == "partial_drop") else Color(0.9, 0.5, 0.1))
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
	elif pvp_mode == "inferno":
		desc = "[center][color=#ff0000][b]🔥 ¡ZONA INFIERNO! 🔥[/b][/color]\n\n[color=#ff4444][b]⚠️ PVP OBLIGATORIO ⚠️[/b][/color]\n\nSi eres derrotado en este mapa:\n[color=red][b]• Pierdes TODO tu inventario\n• Pierdes TODOS tus items equipados\n• ¡TU NAVE SERÁ DESTRUIDA PERMANENTEMENTE!\n• Serás enviado al Lobby con la nave por defecto[/b][/color]\n\n[color=#ff6666][b]¿ESTÁS ABSOLUTAMENTE SEGURO DE INGRESAR?[/b][/color][/center]"
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

# ============================================================
# v400.0: REQUISITOS DE EQUIPAMIENTO (Validación local UX)
# El servidor es la fuente autoritativa; esto solo evita UI y da feedback.
# Uso:
#   check_equip_requirements(item_id = "las2")
#   check_equip_requirements(skill_name = "AUTO-REPARACIÓN")
#   check_equip_requirements(ammo_type = "laser", ammo_tier = 3)
# Devuelve { ok: bool, msg: String }
# ============================================================
func check_equip_requirements(item_id: String = "", skill_name: String = "", ammo_type: String = "", ammo_tier: int = -1) -> Dictionary:
	var reqs: Array = []
	if ammo_type != "" and ammo_tier >= 0:
		reqs = _get_ammo_requirements(ammo_type, ammo_tier)
	elif skill_name != "":
		reqs = _get_skill_requirements(skill_name)
	elif item_id != "":
		reqs = _get_item_requirements(item_id)
	if reqs.is_empty():
		return {"ok": true, "msg": ""}
	
	var level: int = 1
	var player_node = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player_node) and "level" in player_node:
		level = int(player_node.level)
	
	for req in reqs:
		if typeof(req) != TYPE_DICTIONARY:
			continue
		var type_str: String = str(req.get("type", "")).to_lower()
		if type_str == "level":
			var min_lvl: int = int(req.get("min", 0))
			if level < min_lvl:
				return {"ok": false, "msg": "REQUIERE NIVEL " + str(min_lvl)}
		elif type_str == "quest_completed":
			var qid: String = str(req.get("questId", ""))
			if qid == "":
				continue
			if not completed_quests_cache.has(qid):
				var qname: String = qid
				var quests = server_config.get("questsConfig", []) if server_config.has("questsConfig") else []
				for q in quests:
					if typeof(q) == TYPE_DICTIONARY and str(q.get("id", "")) == qid:
						qname = str(q.get("name", qid))
						break
				return {"ok": false, "msg": "REQUIERE MISIÓN COMPLETADA: " + qname}
		elif type_str == "unlock":
			# v600.0: Desbloqueo otorgado por misión (key ej: "item:w_laser_1", "skill:X", "map:2", "talent:combat:0")
			var unlock_key: String = str(req.get("key", ""))
			if unlock_key == "":
				continue
			if not unlocks_cache.has(unlock_key):
				var ulabel: String = str(req.get("label", unlock_key))
				return {"ok": false, "msg": "REQUIERE DESBLOQUEO: " + ulabel}
		elif type_str == "spheres":
			# v650.0: Esferas de colores (ej: 2 verdes y 1 azul, mezcla dinámica de 1 a 4 esferas)
			var needed: Array = req.get("esferas", [])
			if typeof(needed) != TYPE_ARRAY or needed.is_empty():
				continue
			var counts: Dictionary = _count_player_sphere_colors()
			var any_real := false
			for n in needed:
				if typeof(n) != TYPE_DICTIONARY:
					continue
				var sph_color: String = _normalize_sphere_color(str(n.get("color", "")))
				var sph_count: int = int(n.get("count", 0))
				if sph_color == "" or sph_count <= 0:
					continue
				any_real = true
				if int(counts.get(sph_color, 0)) < sph_count:
					return {"ok": false, "msg": "REQUIERE " + _sphere_requirement_text(needed)}
			if not any_real:
				continue
	return {"ok": true, "msg": ""}

# v600.3: ¿Este portal físico (zona + etiqueta) está sellado por una misión que lo desbloquea?
# El portal permanece SELLADO mientras exista una misión configurada que lo desbloquee,
# sin importar si la misión está aceptada o en curso. Solo se abre al COMPLETAR la misión.
# Retorna el nombre de la misión que lo sella, o "" si está libre.
func get_portal_seal_quest(source_zone: Variant, portal_label: String) -> String:
	if portal_label == "":
		return ""
	var quests_cfg: Array = server_config.get("questsConfig", []) if server_config.has("questsConfig") else []
	for q_def in quests_cfg:
		if typeof(q_def) != TYPE_DICTIONARY:
			continue
		var pg_raw: String = str(q_def.get("portalGate", ""))
		if pg_raw == "" or not pg_raw.contains("|"):
			continue
		var parts: PackedStringArray = pg_raw.split("|")
		if str(parts[0]) != str(source_zone) or "|".join(parts.slice(1)) != portal_label:
			continue
		# Misión completada → el portal que sella queda desbloqueado
		if completed_quests_cache.has(str(q_def.get("id", ""))):
			continue
		# Si el objetivo de la misión es explorar el destino de este portal, no se auto-bloquea
		var maps_a: Dictionary = server_config.get("mapsConfig", {}) if server_config.has("mapsConfig") else {}
		var zone_cfg_a: Dictionary = maps_a.get(str(source_zone), {})
		var objs_a: Array = zone_cfg_a.get("objects", []) if typeof(zone_cfg_a) == TYPE_DICTIONARY else []
		var portal_dest: String = ""
		for o in objs_a:
			if typeof(o) == TYPE_DICTIONARY and o.get("type", "") == "door" and str(o.get("label", "")) == portal_label:
				portal_dest = str(o.get("targetZoneId", ""))
				break
		if q_def.get("targetType", "") == "explore" and portal_dest != "" and str(q_def.get("targetId", "")) == portal_dest:
			continue
		return str(q_def.get("name", q_def.get("id", "")))
	return ""

# v600.3: ¿El sector destino está sellado por una misión (portalGate "zona|etiqueta" cuyo portal apunta aquí, o "zona" legacy)?
# Retorna el nombre de la misión que lo sella, o "" si está libre.
func get_sector_seal_quest(dest_zone: Variant) -> String:
	var quests_cfg: Array = server_config.get("questsConfig", []) if server_config.has("questsConfig") else []
	for q_def in quests_cfg:
		if typeof(q_def) != TYPE_DICTIONARY:
			continue
		var pg_raw: String = str(q_def.get("portalGate", ""))
		if pg_raw == "":
			continue
		# Misión completada → el sector que sella queda desbloqueado
		if completed_quests_cache.has(str(q_def.get("id", ""))):
			continue
		if not pg_raw.contains("|"):
			# Legacy: sella todo el acceso al sector (si el objetivo es explorar este sector, no se auto-bloquea)
			if q_def.get("targetType", "") == "explore" and str(q_def.get("targetId", "")) == str(dest_zone):
				continue
			if str(pg_raw) == str(dest_zone):
				return str(q_def.get("name", q_def.get("id", "")))
			continue
		var parts: PackedStringArray = pg_raw.split("|")
		var gate_zone: String = parts[0]
		var gate_label: String = "|".join(parts.slice(1))
		# Si no hay etiqueta ("zona|" o "zona") → sella todo el acceso al sector
		if gate_label == "":
			if q_def.get("targetType", "") == "explore" and str(q_def.get("targetId", "")) == str(dest_zone):
				continue
			if str(gate_zone) == str(dest_zone):
				return str(q_def.get("name", q_def.get("id", "")))
			continue
		# Resolver el destino del portal sellado y comparar
		var maps: Dictionary = server_config.get("mapsConfig", {}) if server_config.has("mapsConfig") else {}
		var zone_cfg: Dictionary = maps.get(str(gate_zone), {})
		var objs: Array = zone_cfg.get("objects", []) if typeof(zone_cfg) == TYPE_DICTIONARY else []
		for o in objs:
			if typeof(o) == TYPE_DICTIONARY and o.get("type", "") == "door" and str(o.get("label", "")) == gate_label:
				if str(o.get("targetZoneId", "")) == str(dest_zone):
					# Si el objetivo de la misión es explorar este sector, no se auto-bloquea
					if q_def.get("targetType", "") == "explore" and str(q_def.get("targetId", "")) == str(dest_zone):
						continue
					return str(q_def.get("name", q_def.get("id", "")))
	return ""

func _get_ammo_requirements(ammo_type: String, ammo_tier: int) -> Array:
	var shop: Dictionary = server_config.get("shopItems", {}) if server_config.has("shopItems") else {}
	var ammo = shop.get("ammo", {})
	if typeof(ammo) != TYPE_DICTIONARY or not ammo.has(ammo_type):
		return []
	var list = ammo[ammo_type]
	if typeof(list) != TYPE_ARRAY or ammo_tier < 0 or ammo_tier >= list.size():
		return []
	var entry = list[ammo_tier]
	if typeof(entry) == TYPE_DICTIONARY:
		return entry.get("requirements", [])
	return []

func _get_item_requirements(item_id: String) -> Array:
	var lower_id: String = item_id.to_lower()
	if lower_id.begins_with("am_"):
		var shop: Dictionary = server_config.get("shopItems", {}) if server_config.has("shopItems") else {}
		var ammo: Dictionary = shop.get("ammo", {})
		for sub in ammo.keys():
			var list = ammo[sub]
			if typeof(list) != TYPE_ARRAY:
				continue
			for a in list:
				if typeof(a) == TYPE_DICTIONARY and str(a.get("id", "")).to_lower() == lower_id:
					return a.get("requirements", [])
		return []
	var shop_items: Dictionary = server_config.get("shopItems", {}) if server_config.has("shopItems") else {}
	var cats: Array = ["weapons", "shields", "engines", "extras", "extra", "resources"]
	for cat in cats:
		var list = shop_items.get(cat, [])
		if typeof(list) != TYPE_ARRAY:
			continue
		for it in list:
			if typeof(it) == TYPE_DICTIONARY and str(it.get("id", "")).to_lower() == lower_id:
				return it.get("requirements", [])
	return []

func _get_skill_requirements(skill_name: String) -> Array:
	var skills: Dictionary = server_config.get("skillsData", {}) if server_config.has("skillsData") else {}
	var needle: String = _normalize_skill_key(skill_name)
	for key in skills.keys():
		if _normalize_skill_key(str(key)) == needle:
			var entry = skills[key]
			if typeof(entry) == TYPE_DICTIONARY:
				return entry.get("requirements", [])
	return []

func _normalize_skill_key(p_name: String) -> String:
	var n: String = p_name.to_upper().strip_edges()
	n = n.replace("Ó", "O").replace("É", "E").replace("Í", "I").replace("Á", "A").replace("Ú", "U").replace("Ü", "U")
	return n

# ============================================================
# v650.0: Esferas de colores (requisito de equipamiento de habilidades)
# El color de cada esfera se deriva del tipo de habilidad equipada:
#   Ataque → Roja | Defensa → Azul | Curación → Verde | Utilidad/Movimiento → Amarilla
# ============================================================
func _normalize_sphere_color(p_raw: String) -> String:
	var n: String = p_raw.to_lower().strip_edges()
	n = n.replace("ó", "o").replace("é", "e").replace("í", "i").replace("á", "a").replace("ú", "u").replace("ü", "u")
	match n:
		"roja", "rojo", "red": return "roja"
		"azul", "blue": return "azul"
		"verde", "green": return "verde"
		"amarilla", "amarillo", "yellow": return "amarilla"
	return ""

func _sphere_color_from_skill_type(p_type: String) -> String:
	var t: String = p_type.to_lower()
	t = t.replace("ó", "o").replace("é", "e").replace("í", "i").replace("á", "a").replace("ú", "u").replace("ü", "u")
	if t == "ataque": return "roja"
	if t == "defensa": return "azul"
	if t == "curacion": return "verde"
	return "amarilla"

func _sphere_color_of(p_sphere) -> String:
	if typeof(p_sphere) != TYPE_DICTIONARY: return ""
	var explicit: String = _normalize_sphere_color(str(p_sphere.get("type", "")))
	if explicit != "": return explicit
	var equipped = p_sphere.get("equipped")
	if equipped == null: return ""
	var eq_type: String = ""
	if typeof(equipped) == TYPE_DICTIONARY:
		eq_type = str(equipped.get("type", ""))
	else:
		eq_type = str(equipped.get("type"))
	return _sphere_color_from_skill_type(eq_type)

func _count_player_sphere_colors() -> Dictionary:
	var counts := {}
	var player_node = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player_node):
		return counts
	var sm = player_node.get_node_or_null("SpheresManager")
	if not is_instance_valid(sm):
		return counts
	for s in sm.spheres_data:
		var c: String = _sphere_color_of(s)
		if c != "":
			counts[c] = int(counts.get(c, 0)) + 1
	return counts

func _sphere_color_label(p_color: String, p_count: int) -> String:
	var single: Dictionary = {"roja": "ROJA", "azul": "AZUL", "verde": "VERDE", "amarilla": "AMARILLA"}
	var plural: Dictionary = {"roja": "ROJAS", "azul": "AZULES", "verde": "VERDES", "amarilla": "AMARILLAS"}
	var word: String = str(single.get(p_color, p_color.to_upper()))
	if p_count > 1:
		word = str(plural.get(p_color, word + "S"))
	return "%d ESFERA%s %s" % [p_count, "S" if p_count > 1 else "", word]

func _sphere_requirement_text(p_needed: Array) -> String:
	var parts: Array = []
	for n in p_needed:
		if typeof(n) != TYPE_DICTIONARY:
			continue
		var c: String = _normalize_sphere_color(str(n.get("color", "")))
		var cnt: int = int(n.get("count", 0))
		if c == "" or cnt <= 0:
			continue
		parts.append(_sphere_color_label(c, cnt))
	if parts.is_empty():
		return "ESFERAS DE COLORES"
	if parts.size() == 1:
		return str(parts[0])
	var txt: String = ""
	for i in range(parts.size() - 1):
		txt += str(parts[i])
		if i < parts.size() - 2:
			txt += ", "
	return txt + " Y " + str(parts[parts.size() - 1])

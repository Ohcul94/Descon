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

signal enemy_damaged(data)
signal enemy_healed(data)
signal boss_effect(data)
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


var socket: WebSocketPeer = WebSocketPeer.new()
var network_connected: bool = false
var online_count: int = 1 # v220.20: Conteo global persistente
var was_manual_logout: bool = false # v221.21: Evitar bucle de login en debug
var my_socket_id: String = "" # v168.04: ID Local para evitar self-cloning
var auth_token: String = ""
var login_name: String = ""
var is_logged_in: bool = false # v244.60: Control global de estado de sesión
var ping_start_time: int = 0
var current_ms: int = 0
var is_registering: bool = false # v244.10: Soporte para creación de cuenta
var current_user_data: Dictionary = {} 


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

func connect_to_server(ip: String, port: int, p_name: String, p_token: String = "", registering: bool = false):
	is_registering = registering

	var state = socket.get_ready_state()
	if state != WebSocketPeer.STATE_CLOSED and state != WebSocketPeer.STATE_CLOSING:
		print("[NET] Socket activo detectado. Cerrando para nueva conexión...")
		socket.close()
		socket = WebSocketPeer.new()
		network_connected = false
		
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
			if typeof(arr) == TYPE_ARRAY and arr.size() >= 2:
				_dispatch_event(arr[0], arr[1])

func _dispatch_event(e_name: String, e_data: Variant):
	match e_name:
		"loginSuccess", "authSuccess":
			is_logged_in = true
			my_socket_id = str(e_data.get("socketId", ""))
			current_user_data = e_data
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
		"combatLog": combat_log.emit(e_data.get("msg", ""))
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
		"environmentDamage": environment_damaged.emit(e_data)
		"clanMemberStatus": clan_member_status.emit(e_data)
		"spawnArea": spawn_area.emit(e_data)
		"removeArea": remove_area.emit(e_data)
		"blindState": blind_state.emit(e_data)
		"blindnessEvent": blindness_event.emit(e_data)
		"interferenceEvent": interference_event.emit(e_data) # v268.30
		"freezeEvent": freeze_event.emit(e_data) # v268.40
		"slowState": slow_state.emit(e_data)
		"stunState": stun_state.emit(e_data)
		"hookPulled": hook_pulled.emit(e_data)
		"gameNotification": game_notification.emit(e_data)
		"shipEquipData": ship_equip_data.emit(e_data)
		"clearEnemyProjectiles": clear_enemy_projectiles.emit(e_data)
		"adminConfigUpdated", "adminConfigLoaded": 
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
		"clanMemberStatus": clan_member_status.emit(e_data)
		"pong_custom":
			current_ms = int(Time.get_ticks_msec() - ping_start_time)
			send_event("latencyUpdate", current_ms)
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
	if network_connected:
		var pack = "42" + JSON.stringify([p_ename, p_val])
		socket.send_text(pack)

func _start_ping_loop():
	await get_tree().create_timer(1.0).timeout 
	while network_connected:
		ping_start_time = Time.get_ticks_msec()
		send_event("ping_custom", {})
		await get_tree().create_timer(3.0).timeout

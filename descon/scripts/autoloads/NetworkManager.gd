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

signal enemy_damaged(data)
signal boss_effect(data)
signal config_updated(data)
signal game_notification(data)
signal clear_zone_entities(zoneId)

var socket: WebSocketPeer = WebSocketPeer.new()
var network_connected: bool = false
var my_socket_id: String = "" # v168.04: ID Local para evitar self-cloning
var auth_token: String = ""
var login_name: String = ""
var ping_start_time: int = 0
var current_ms: int = 0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

func connect_to_server(ip: String, port: int, p_name: String, p_token: String = ""):
	var state = socket.get_ready_state()
	if state != WebSocketPeer.STATE_CLOSED and state != WebSocketPeer.STATE_CLOSING:
		print("[NET] Reintento de conexión abortado: Socket ya está en uso.")
		return
		
	login_name = p_name
	auth_token = p_token
	var url = "ws://" + str(ip) + ":" + str(port) + "/socket.io/?EIO=4&transport=websocket"
	print("[NET] Conectando a ", url)
	var err = socket.connect_to_url(url)
	if err != OK:
		print("[NET-ERR] Error al iniciar socket: ", err)
		network_connected = false

func _process(_delta):
	socket.poll()
	var state = socket.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
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
			my_socket_id = str(e_data.get("socketId", ""))
			auth_success.emit(e_data)
			login_success.emit(e_data)
			player_auth_success.emit(e_data)
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
		"enemyDamaged": enemy_damaged.emit(e_data)
		"enemyDead", "serverEnemyDead": enemy_dead.emit(e_data)
		"bossEffect": boss_effect.emit(e_data)
		"gameNotification": game_notification.emit(e_data)
		"adminConfigUpdated", "adminConfigLoaded": 
			config_updated.emit(e_data)
			admin_config_updated.emit(e_data)
		"rewardReceived", "serverReward": reward_received.emit(e_data)
		"levelUp", "serverLevelUp": level_up.emit(e_data)
		"inventoryData", "inventorySync": inventory_data.emit(e_data)
		"playerStatSync":
			if typeof(e_data) == TYPE_DICTIONARY:
				if str(e_data.get("id", "")) != my_socket_id:
					# v214.170: Sincronizar visualmente al aliado con sus esferas nuevas
					_dispatch_single_player(e_data, "player_stat_sync")
				else:
					player_stat_sync.emit(e_data)
		"rewardReceived": reward_received.emit(e_data)
		"inventoryData":
			var final_data = e_data
			if typeof(e_data) == TYPE_DICTIONARY and e_data.has("items"):
				final_data = e_data["items"]
			inventory_data.emit(final_data)
		"playerDisconnected":
			player_disconnected.emit(str(e_data))
		"pong_custom":
			current_ms = int(Time.get_ticks_msec() - ping_start_time)
			send_event("latencyUpdate", current_ms)

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
						for i in range(min(sps.size(), 3)):
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

extends Node2D

# World.gd (Controlador Global v73.31 - Phoenix Universal Render)
# Optimización de Instanciación de Entidades y Parallax Stellar.

@onready var player_spawn = $PlayerSpawn
@onready var entities_node = $Entities
@onready var ui_hud = $HUD/MainHUD
@onready var ui_chat = $HUD/ChatUI
@onready var ui_inventory = $HUD/Inventory
@onready var ui_admin = $HUD/AdminPanel
@onready var local_player = $Player 
@onready var combat_system = $CombatSystem
@onready var map_background = $MapParallax/MapWorldLayer/MapBackground
var talent_system = null

var remote_players = {}
var enemies = {}
var save_timer = 0.0
const SAVE_INTERVAL = 10.0
var respawn_timer = 0.0

# 650 Estrellas Procesales (v73.31)
var stars_far = []
var stars_mid = []
var stars_near = []
const WORLD_DRAW_SIZE = 4000.0

func _ready():
	add_to_group("world_node") # v164.37: Para que el ChatUI nos encuentre fácil
	NetworkManager.player_updated.connect(_on_player_updated)
	# v222.75: Conexiones centralizadas
	NetworkManager.player_stat_sync.connect(_on_remote_stat_sync)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.enemy_updated.connect(_on_enemy_updated)
	NetworkManager.login_success.connect(_on_login_success)
	# NetworkManager.chat_received.connect(_on_chat_bubble_received) # v164.36: Centralizado en ChatUI para evitar duplicidad
	NetworkManager.player_fired.connect(_on_player_fired)
	NetworkManager.enemy_fired.connect(_on_enemy_fired)
	NetworkManager.enemy_dead.connect(_on_enemy_dead)
	NetworkManager.enemy_damaged.connect(_on_enemy_damaged) # v167.60: Sincronía de daño total
	NetworkManager.clear_zone_entities.connect(_on_clear_zone_entities)
	NetworkManager.clear_enemy_projectiles.connect(_on_clear_enemy_projectiles)
	NetworkManager.remote_skill_used.connect(_on_remote_skill_used)
	
	# v190.71: Sincronía en Caliente de Configuración Admin
	NetworkManager.config_updated.connect(_on_admin_config_received)
	
	talent_system = get_node_or_null("TalentSystem")
	
	ui_hud.visible = false
	ui_inventory.visible = false
	ui_admin.visible = false
	ui_chat.visible = false
	
	_generate_stellar_data()

func _generate_stellar_data():
	for i in range(400): stars_far.append(Vector2(randf()*WORLD_DRAW_SIZE, randf()*WORLD_DRAW_SIZE))
	for i in range(200): stars_mid.append(Vector2(randf()*WORLD_DRAW_SIZE, randf()*WORLD_DRAW_SIZE))
	for i in range(50): stars_near.append(Vector2(randf()*WORLD_DRAW_SIZE, randf()*WORLD_DRAW_SIZE))

func _draw():
	var cam_pos = Vector2.ZERO
	if is_instance_valid(local_player): cam_pos = local_player.global_position
	for s in stars_far: draw_circle(s + (cam_pos * 0.1), 0.5, Color(1,1,1,0.2))
	for s in stars_mid: draw_circle(s + (cam_pos * 0.3), 0.8, Color(1,1,1,0.4))
	for s in stars_near: draw_circle(s + (cam_pos * 0.6), 1.2, Color(1,1,1,0.8))

func _process(delta):
	queue_redraw()
	save_timer += delta; if save_timer >= SAVE_INTERVAL: save_timer = 0.0; _save_game_progress()
	if is_instance_valid(local_player) and local_player.is_dead:
		respawn_timer += delta
		if respawn_timer >= 3.0:
			respawn_timer = 0.0
			_perform_local_respawn()
	else: 
		respawn_timer = 0.0

func _input(event):
	var focusNode = get_viewport().gui_get_focus_owner()
	if focusNode is LineEdit or focusNode is TextEdit: return
	
	# v190.30: Sistema de Seguridad SuperAdmin (Acceso Exclusivo Caelli94)
	if event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		if is_instance_valid(local_player):
			var user_name = local_player.get("username")
			if user_name and user_name == "Caelli94":
				ui_admin.visible = !ui_admin.visible
				if ui_admin.visible: ui_admin._refresh_ui()
				get_viewport().set_input_as_handled() # Evitar propagación
			else:
				print("[SEGURIDAD] Intento de acceso denegado al Panel Admin.")
				
	# SISTEMA DE DUNGEON (Prueba)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_0:
		print("[DUNGEON] Solicitando ingreso a Dungeon Instanciada...")
		NetworkManager.send_event("enterDungeon", {})

func _perform_local_respawn():
	if is_instance_valid(local_player) and local_player.has_method("respawn"):
		local_player.respawn()
	
	_save_game_progress()

func _on_login_success(data):
	local_player._on_login_success(data)

	if not local_player.shoot_fired.is_connected(_on_local_shoot): local_player.shoot_fired.connect(_on_local_shoot)
	
	# v219.10: Forzar carga de fondo inicial post-login
	if "current_zone" in local_player:
		_update_background(local_player.current_zone)
		
	ui_hud.visible = true
	ui_chat.visible = true

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		if is_instance_valid(ui_hud) and ui_hud.has_method("toggle_esc_menu"):
			ui_hud.toggle_esc_menu()

func _on_player_updated(data):
	if typeof(data) != TYPE_DICTIONARY or not data.has("id"): return
	var id = str(data.id)
	if id == "" or id == "null": return
	
	# v219.50: FILTRO DE ZONA CRÍTICO (Prevenir Fantasmas de otros mapas)
	if is_instance_valid(local_player):
		var remote_zone = int(data.get("zone", -1))
		var local_zone = int(local_player.current_zone)
		
		# Si el jugador está en otra zona, lo eliminamos si existía aquí
		if remote_zone != -1 and remote_zone != local_zone:
			if remote_players.has(id):
				var rp = remote_players[id]
				remote_players.erase(id)
				if is_instance_valid(rp): rp.queue_free()
			return
	
	# v167.93: REGLA DE ORO - Identificación ÚNICA por ID (No por Username)
	if is_instance_valid(local_player) and (id == local_player.entity_id and id != ""):
		# Actualizar stats locales desde el servidor
		if data.has("hp"): local_player.current_hp = float(data.hp)
		if data.has("shield"): local_player.current_shield = float(data.shield)
		elif data.has("sh"): local_player.current_shield = float(data.sh)
		
		# v220.98: Actualizar metadatos visuales (ej. PvP)
		local_player.update_stats(data)
		
		# Sincronizar UI del HUD
		if data.has("pvpEnabled") and is_instance_valid(ui_hud):
			ui_hud.set_pvp_status(data.pvpEnabled)
		return

	# v186.10: Seguridad Extrema - No instanciar si ya es un enemigo conocido
	if enemies.has(id): return 

	if not remote_players.has(id):
		# No usamos set_script si el .tscn ya tiene la referencia del script original (v73.31)
		var rp = load("res://scenes/entities/Ship.tscn").instantiate()
		rp.entity_id = id; rp.add_to_group("remote_players")
		remote_players[id] = rp; entities_node.add_child(rp)
	
	var p = remote_players[id]
	if is_instance_valid(p):
		p.target_position = Vector2(data.get("x", p.global_position.x), data.get("y", p.global_position.y))
		p.target_rotation = data.get("rotation", p.rotation)
		p.update_stats(data)

func _on_enemy_updated(data):
	if typeof(data) != TYPE_DICTIONARY or not data.has("id"): return
	var id = str(data.id)
	
	# v166.81: Evitar que un jugador sea tratado como enemigo por colisión de IDs
	if remote_players.has(id): return
	
	# v225.65: FILTRO DE SEGURIDAD REFORZADO (Bloqueo absoluto de fantasmas)
	if is_instance_valid(local_player):
		var enemy_zone = int(data.get("zone", -1))
		var my_zone = int(local_player.current_zone)
		
		# Si la zona no viene en el paquete o no coincide, ignoramos el update
		if enemy_zone != my_zone:
			# Si ya lo tenemos registrado pero cambió de zona (o es un leak), lo borramos
			if enemies.has(id):
				var old_en = enemies[id]
				if is_instance_valid(old_en): old_en.queue_free()
				enemies.erase(id)
			return

	if not enemies.has(id):
		var en = load("res://scenes/entities/Enemy.tscn").instantiate()
		en.entity_id = id; en.add_to_group("enemies")
		enemies[id] = en; entities_node.add_child(en)
	var eref = enemies[id]
	if is_instance_valid(eref):
		if data.has("x"): eref.target_position = Vector2(data.x, data.get("y", 0))
		if data.has("rotation"): eref.target_rotation = data.rotation
		eref.update_stats(data); eref.visible = true; eref.show()
	else:
		enemies.erase(id)

func _on_player_disconnected(id):
	var sid = str(id)
	if remote_players.has(sid):
		remote_players[sid].queue_free()
		remote_players.erase(sid)

func clear_remote_players():
	# v188.16: Limpieza masiva de red para evitar crashes al re-conectar
	for id in remote_players:
		if is_instance_valid(remote_players[id]): remote_players[id].queue_free()
	remote_players.clear()
	for id in enemies:
		if is_instance_valid(enemies[id]): enemies[id].queue_free()
	enemies.clear()
	print("[NET] Universo limpiado correctamente.")

func _on_enemy_dead(data: Dictionary):
	var id = str(data.get("id", ""))
	if id == "": return
	var enemy = enemies.get(id)
	if is_instance_valid(enemy): enemy.die()
	if enemies.has(id): enemies.erase(id)

func _on_enemy_damaged(data: Dictionary):
	var id = str(data.get("enemyId", data.get("id", "")))
	if id == "" or not enemies.has(id): return
	var en = enemies[id]
	if is_instance_valid(en):
		# v167.61: Sincronía total y visual de daño
		if en.has_method("update_stats"):
			en.update_stats(data)
		if en.has_method("reset_combat_timer"):
			en.reset_combat_timer()

func _save_game_progress():
	if not is_instance_valid(local_player): return
	var d = { 
		"hubs": local_player.hubs, 
		"ohcu": local_player.ohculianos, 
		"level": local_player.level, 
		"exp": local_player.current_exp, 
		"hp": local_player.current_hp, 
		"shield": local_player.current_shield,
		"maxHp": local_player.max_hp,
		"maxShield": local_player.max_shield,
		# "inventory": local_player.inventory, # ELIMINADO para evitar Dupeo v215.20
		# "equipped": local_player.equipped,   # ELIMINADO para evitar Dupeo v215.20
		"skillPoints": local_player.skill_tree.skillPoints if local_player.skill_tree and "skillPoints" in local_player.skill_tree else 0,
		"skillTree": local_player.skill_tree
	}
	NetworkManager.send_event("saveProgress", d)

func route_chat_bubble(data: Dictionary):
	var sid = str(data.get("senderId", "")); 
	var txt = str(data.get("msg", data.get("text", "")))
	
	var target = null
	if is_instance_valid(local_player) and (sid == local_player.entity_id or data.get("sender") == local_player.username):
		target = local_player
	else:
		for pid in remote_players:
			var p = remote_players[pid]
			if is_instance_valid(p) and (p.entity_id == sid or data.get("sender") == p.username):
				target = p; break
				
	if target: target.show_bubble(txt)

func _on_remote_stat_sync(data: Dictionary):
	if typeof(data) != TYPE_DICTIONARY: return
	var id = str(data.get("id", ""))
	
	if is_instance_valid(local_player) and (id == local_player.entity_id or id == ""):
		local_player.update_stats(data)
		return
		
	if id != "" and remote_players.has(id):
		var p = remote_players[id]
		if is_instance_valid(p): p.update_stats(data)

func _on_local_shoot(d): if combat_system: combat_system.handle_local_shoot(d)
func _on_player_fired(d): if combat_system: combat_system.handle_remote_shoot(d)
func _on_enemy_fired(d): if combat_system: combat_system.handle_enemy_shoot(d)
func _on_admin_config_received(data: Dictionary):
	# v190.72: Corrección de referencia a Autoload (GameConstants)
	if GameConstants.has_method("update_from_server"):
		GameConstants.update_from_server(data)
		# Forzar refresco de UI si el Admin o Inventario están abiertos
		if is_instance_valid(ui_admin) and ui_admin.visible: ui_admin._refresh_ui()
		if is_instance_valid(ui_inventory) and ui_inventory.visible: ui_inventory._refresh_data()
		print("[WORLD] Cambios globales aplicados correctamente.")

func _on_clear_zone_entities(_zoneId):
	# Limpiar enemigos visualmente
	for id in enemies:
		if is_instance_valid(enemies[id]): enemies[id].queue_free()
	enemies.clear()
	
	# Limpiar jugadores viejos
	for id in remote_players:
		if is_instance_valid(remote_players[id]): remote_players[id].queue_free()
	remote_players.clear()
	
	# Limpiar proyectiles huérfanos si existe el CombatSystem
	if is_instance_valid(combat_system) and combat_system.has_method("clear_all_bullets"):
		combat_system.clear_all_bullets()
		
	# Si la zona es Dungeon, ajustamos limites. Todo ID tipo texto (dungeon_123) es Dungeon.
	var is_dungeon = str(_zoneId).begins_with("dungeon")
	var new_world_size = 2000.0 if (is_dungeon or int(_zoneId) > 1) else 4000.0
	
	# v215.60: REPOSICIONAR JUGADOR LOCAL (Fix: Escena trabada)
	if is_instance_valid(local_player):
		local_player.global_position = Vector2(new_world_size / 2, new_world_size / 2)
		local_player.target_position = local_player.global_position
		local_player.is_moving = false
		if "current_zone" in local_player:
			local_player.current_zone = int(_zoneId) if not is_dungeon else 99
	
	# Si existe _generar_fondo o similar, podríamos hacerlo pero el Minimap necesita saberlo.
	var radar = ui_hud.get_node_or_null("MinimapUI") if is_instance_valid(ui_hud) else null
	if radar and "world_size" in radar:
		radar.world_size = new_world_size
		
		
	_update_background(_zoneId)
	print("[ZONE] Transición completa a zona: ", _zoneId, " | Nueva Posición: ", local_player.global_position if is_instance_valid(local_player) else "N/A")

func _update_background(zone_id):
	if not is_instance_valid(map_background): return
	
	var zid = int(zone_id)
	var texture_path = ""
	
	match zid:
		1: texture_path = "res://assets/Base de Mapas/mixboard-image.png"
		2: texture_path = "res://assets/Base de Mapas/mixboard-image (1).png"
		3: texture_path = "res://assets/Base de Mapas/mixboard-image (2).png"
		4: texture_path = "res://assets/Base de Mapas/mixboard-image (3).png"
		5: texture_path = "res://assets/Base de Mapas/mixboard-image (4).png"
		6: texture_path = "res://assets/Base de Mapas/mixboard-image (5).png"
		7: texture_path = "res://assets/Base de Mapas/mixboard-image (1).png"
		8: texture_path = "res://assets/Base de Mapas/mixboard-image (4).png"
	
	if texture_path != "":
		# v227.35: OPTIMIZACIÓN DE FONDO (Escalado Masivo para evitar bordes negros)
		var new_tex = load(texture_path)
		if map_background.texture != new_tex:
			map_background.texture = new_tex
			# v227.55: Escalado Total (16000px para cobertura garantizada en 4K/Zoom)
			map_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			map_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			map_background.size = Vector2(16000, 16000)
			map_background.position = Vector2(-8000, -8000) 
			map_background.modulate.a = 0
			map_background.show()
			var tween = create_tween()
			tween.tween_property(map_background, "modulate:a", 0.7, 1.5).set_trans(Tween.TRANS_SINE)
	else:
		map_background.hide()
		map_background.texture = null

func _on_remote_skill_used(data):
	if typeof(data) != TYPE_DICTIONARY: return
	var e_id = str(data.get("id", ""))
	if e_id == "" or (is_instance_valid(local_player) and local_player.entity_id == e_id): return
	
	if remote_players.has(e_id):
		var node = remote_players[e_id]
		if is_instance_valid(node) and node.has_method("play_skill_vfx"):
			node.play_skill_vfx(data.get("skillName", ""), float(data.get("powerValue", 0.0)))

func _on_clear_enemy_projectiles(data: Dictionary):
	var boss_id = str(data.get("bossId", ""))
	if boss_id != "" and is_instance_valid(combat_system) and combat_system.has_method("clear_boss_bullets"):
		combat_system.clear_boss_bullets(boss_id)

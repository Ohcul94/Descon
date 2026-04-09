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
	# NetworkManager.spawn_entity.connect(_on_player_updated) # ELIMINADO v168.09: Evita que enemigos se creen como jugadores
	NetworkManager.player_stat_sync.connect(_on_remote_stat_sync)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.enemy_updated.connect(_on_enemy_updated)
	NetworkManager.login_success.connect(_on_login_success)
	# NetworkManager.chat_received.connect(_on_chat_bubble_received) # v164.36: Centralizado en ChatUI para evitar duplicidad
	NetworkManager.player_fired.connect(_on_player_fired)
	NetworkManager.enemy_fired.connect(_on_enemy_fired)
	NetworkManager.enemy_dead.connect(_on_enemy_dead)
	NetworkManager.enemy_damaged.connect(_on_enemy_damaged) # v167.60: Sincronía de daño total
	
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
	if Input.is_key_pressed(KEY_F2): ui_admin.visible = !ui_admin.visible
	save_timer += delta; if save_timer >= SAVE_INTERVAL: save_timer = 0.0; _save_game_progress()
	if is_instance_valid(local_player) and local_player.is_dead:
		respawn_timer += delta
		if respawn_timer >= 3.0:
			respawn_timer = 0.0
			_perform_local_respawn()
	else: 
		respawn_timer = 0.0

func _perform_local_respawn():
	if is_instance_valid(local_player) and local_player.has_method("respawn"):
		local_player.respawn()
	
	_save_game_progress()

func _on_login_success(data):
	local_player.global_position = player_spawn.global_position; local_player._on_login_success(data)
	if not local_player.shoot_fired.is_connected(_on_local_shoot): local_player.shoot_fired.connect(_on_local_shoot)
	ui_hud.visible = true
	ui_chat.visible = true

func _on_player_updated(data):
	if typeof(data) != TYPE_DICTIONARY or not data.has("id"): return
	var id = str(data.id)
	if id == "" or id == "null": return # v168.03: Ignorar IDs vacíos
	
	# v167.93: REGLA DE ORO - Identificación ÚNICA por ID (No por Username)
	if is_instance_valid(local_player) and (id == local_player.entity_id and id != ""):
		# Actualizar stats locales desde el servidor
		if data.has("hp"): local_player.current_hp = float(data.hp)
		if data.has("shield"): local_player.current_shield = float(data.shield)
		elif data.has("sh"): local_player.current_shield = float(data.sh)
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
		var _old_pos = p.global_position
		p.global_position = Vector2(data.get("x", p.global_position.x), data.get("y", p.global_position.y))
		p.rotation = data.get("rotation", p.rotation)
		p.update_stats(data)

func _on_enemy_updated(data):
	if typeof(data) != TYPE_DICTIONARY or not data.has("id"): return
	var id = str(data.id)
	
	# v166.81: Evitar que un jugador sea tratado como enemigo por colisión de IDs
	if remote_players.has(id): return

	if not enemies.has(id):
		var en = load("res://scenes/entities/Enemy.tscn").instantiate()
		en.entity_id = id; en.add_to_group("enemies")
		enemies[id] = en; entities_node.add_child(en)
	var eref = enemies[id]
	if is_instance_valid(eref):
		if data.has("x"): eref.global_position = Vector2(data.x, data.get("y", 0))
		if data.has("rotation"): eref.rotation = data.rotation
		eref.update_stats(data); eref.visible = true; eref.show()
	else:
		enemies.erase(id)

func _on_player_disconnected(id):
	var sid = str(id)
	if remote_players.has(sid):
		remote_players[sid].queue_free()
		remote_players.erase(sid)

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
	if is_instance_valid(en) and en.has_method("reset_combat_timer"):
		en.reset_combat_timer()

func _save_game_progress():
	if not is_instance_valid(local_player): return
	var d = { "hubs": local_player.hubs, "ohcu": local_player.ohculianos, "level": local_player.level, "exp": local_player.current_exp, "hp": local_player.current_hp, "shield": local_player.current_shield }
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

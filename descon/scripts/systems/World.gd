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
var enemy_pool = []
const ENEMY_SCENE = preload("res://scenes/entities/Enemy.tscn")
var save_timer = 0.0
const SAVE_INTERVAL = 10.0
var respawn_timer = 0.0
var active_areas = {} # v260.80: Cache de zonas de efecto (Humo, etc)


# 650 Estrellas Procesales (v73.31) - PRE-BAKED para rendimiento
var _star_sprites: Array = [] # [far, mid, near] Sprite2Ds
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
	NetworkManager.clear_zone_entities.connect(_update_hud_map_name) # v243.63: Sincronía HUD
	NetworkManager.clear_enemy_projectiles.connect(_on_clear_enemy_projectiles)
	NetworkManager.remote_skill_used.connect(_on_remote_skill_used)
	NetworkManager.spawn_area.connect(_on_spawn_area)
	NetworkManager.remove_area.connect(_on_remove_area)

	
	# v190.71: Sincronía en Caliente de Configuración Admin
	NetworkManager.config_updated.connect(_on_admin_config_received)
	
	talent_system = get_node_or_null("TalentSystem")
	
	ui_hud.visible = false
	ui_inventory.visible = false
	ui_admin.visible = false
	ui_chat.visible = false
	
	_generate_stellar_data()

func _generate_stellar_data():
	# Pre-renderizar estrellas a texturas estáticas (evita 650 draw_circle por frame)
	var layers = [
		{"count": 400, "radius": 1, "alpha": 0.2, "parallax": 0.1},
		{"count": 200, "radius": 2, "alpha": 0.4, "parallax": 0.3},
		{"count": 50, "radius": 3, "alpha": 0.8, "parallax": 0.6}
	]
	var tex_size = int(WORLD_DRAW_SIZE)
	for layer in layers:
		var img = Image.create(tex_size, tex_size, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var r = layer.radius
		var c = Color(1, 1, 1, layer.alpha)
		for i in range(layer.count):
			var sx = randi_range(r, tex_size - r - 1)
			var sy = randi_range(r, tex_size - r - 1)
			for dx in range(-r, r + 1):
				for dy in range(-r, r + 1):
					if dx*dx + dy*dy <= r*r:
						img.set_pixel(sx + dx, sy + dy, c)
		var spr = Sprite2D.new()
		spr.texture = ImageTexture.create_from_image(img)
		spr.centered = false
		spr.z_index = -10
		spr.set_meta("parallax_factor", layer.parallax)
		add_child(spr)
		_star_sprites.append(spr)

func _draw():
	pass # Estrellas ahora son sprites pre-renderizados, no necesitan _draw()

func _process(delta):
	# Parallax de estrellas (solo mover posición, sin redibujar)
	var cam_pos = Vector2.ZERO
	if is_instance_valid(local_player): cam_pos = local_player.global_position
	for spr in _star_sprites:
		if is_instance_valid(spr):
			spr.position = cam_pos * spr.get_meta("parallax_factor")
	
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
	
	# v244.60: Bloquear interacciones si no hay sesión
	if not NetworkManager or not NetworkManager.is_logged_in: return
	
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

func _update_hud_map_name(zone_id):
	var z_id = int(zone_id)
	var z_name = "SECTOR 01"
	
	match z_id:
		1: z_name = "SECTOR ALPHA 1"
		2: z_name = "PUERTO DE COMERCIO"
		3: z_name = "CINTURÓN DE ASTEROIDES"
		4: z_name = "BASE ABANDONADA"
		5: z_name = "NEBULOSA ROJA"
		6: z_name = "SISTEMA BINARIO"
		7: z_name = "ABISMO ESPACIAL"
		_: 
			if z_id >= 500: z_name = "INSTANCIA PRIVADA"
			else: z_name = "SECTOR " + str(z_id).pad_zeros(2)
	
	if is_instance_valid(ui_hud) and ui_hud.has_method("set_map_name"):
		ui_hud.set_map_name(z_name)

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
		_update_hud_map_name(local_player.current_zone) # v243.64: Sincronía HUD inicial
		
	ui_hud.visible = true
	ui_chat.visible = true

func _unhandled_input(event):
	if not NetworkManager or not NetworkManager.is_logged_in: return
	
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
		rp.entity_id = id
		rp.db_id = str(data.get("id", "")) # v243.88: Sincronía de identidad persistente
		rp.add_to_group("remote_players")
		remote_players[id] = rp; entities_node.add_child(rp)
	
	var p = remote_players[id]
	if is_instance_valid(p):
		p.target_position = Vector2(data.get("x", p.global_position.x), data.get("y", p.global_position.y))
		p.target_rotation = data.get("rotation", p.rotation)
		p.update_stats(data)

func _get_enemy_from_pool() -> Node:
	for en in enemy_pool:
		if is_instance_valid(en) and en.get_meta("is_pooled", false):
			en.set_meta("is_pooled", false)
			en.is_dead = false
			en.visible = true
			en.set_process(true)
			en.set_physics_process(true)
			if en.get("_collision_shape"):
				en.get("_collision_shape").set_deferred("disabled", false)
			if en.get("_ui_wrapper"): en.get("_ui_wrapper").visible = true
			return en
			
	var en = ENEMY_SCENE.instantiate()
	enemy_pool.append(en)
	entities_node.add_child(en)
	return en

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
				if is_instance_valid(old_en): 
					old_en.set_meta("is_pooled", true); old_en.visible = false; old_en.set_process(false); old_en.set_physics_process(false)
				enemies.erase(id)
			return

	if not enemies.has(id):
		var en = _get_enemy_from_pool()
		en.entity_id = id
		if not en.is_in_group("enemies"): en.add_to_group("enemies")
		enemies[id] = en
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
		if is_instance_valid(enemies[id]): 
			enemies[id].set_meta("is_pooled", true); enemies[id].visible = false; enemies[id].set_process(false); enemies[id].set_physics_process(false)
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

func _on_spawn_area(data: Dictionary):
	print("[SMOKE-DEBUG] _on_spawn_area RECIBIDO: ", data)
	var type = data.get("type", "SMOKE")
	var id = data.get("id", "")
	if type == "SMOKE":
		print("[SMOKE-DEBUG] Tipo es SMOKE, llamando _spawn_smoke_cloud con id=", id, " radius=", data.radius)
		_spawn_smoke_cloud(id, Vector2(data.x, data.y), data.radius)

func _on_remove_area(data: Dictionary):
	var id = data.get("id", "")
	if active_areas.has(id):
		var area = active_areas[id]
		var tw = create_tween()
		tw.tween_property(area, "modulate:a", 0.0, 1.0)
		tw.tween_callback(area.queue_free)
		active_areas.erase(id)

func _spawn_smoke_cloud(id, pos, radius):
	print("[SMOKE-DEBUG] _spawn_smoke_cloud: id=", id, " pos=", pos, " radius=", radius)
	if active_areas.has(id):
		print("[SMOKE-DEBUG] ABORTADO: id ya existe en active_areas")
		return
	
	# v260.85: Renderizado de Humo 3D Autorizativo
	var wrapper = Node2D.new()
	wrapper.name = id
	wrapper.global_position = pos
	wrapper.z_index = -1 # v2.0 Original: Debajo de las naves
	entities_node.add_child(wrapper)
	active_areas[id] = wrapper
	
	# v2.0: Generar Nube 3D via Viewport (Look MMO Premium)
	var view_size = int(radius * 2.5)
	var vp = SubViewport.new()
	vp.size = Vector2i(view_size, view_size)

	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	wrapper.add_child(vp)
	
	var node3d = Node3D.new()
	vp.add_child(node3d)
	
	var cam = Camera3D.new()
	cam.position = Vector3(0, 0, 10)
	cam.look_at(Vector3.ZERO)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.0 
	node3d.add_child(cam)
	
	var mesh_inst = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(2, 2)
	mesh_inst.mesh = plane
	mesh_inst.rotation_degrees.x = 90 # Restaurado a 90 según commit funcional
	
	var mat = ShaderMaterial.new()
	mat.shader = load("res://resources/shaders/smoke_cloud.gdshader")
	mesh_inst.material_override = mat
	node3d.add_child(mesh_inst)
	
	# Vincular 3D a 2D
	var sprite = Sprite2D.new()
	sprite.texture = vp.get_texture()
	wrapper.add_child(sprite)
	
	# Animación de Entrada Original
	wrapper.modulate.a = 0.0
	wrapper.scale = Vector2(0.5, 0.5) # Original: Empieza pequeño
	var tw = create_tween().set_parallel(true)
	tw.tween_property(wrapper, "modulate:a", 1.0, 0.2)
	tw.tween_property(wrapper, "scale", Vector2(1.0, 1.0), 0.4).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


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
		if is_instance_valid(enemies[id]): 
			enemies[id].set_meta("is_pooled", true); enemies[id].visible = false; enemies[id].set_process(false); enemies[id].set_physics_process(false)
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
	
	# v4.0: Sincronía Visual de Objetivos (NUEVO)
	var sender_id = str(data.get("id", ""))
	var target_id = str(data.get("targetId", sender_id)) # Por defecto al emisor
	
	var target_node = null
	
	# 1. Buscar el objetivo en el universo
	if is_instance_valid(local_player) and local_player.entity_id == target_id:
		# v4.3: Evitar doble VFX si el jugador se lanza la habilidad a sí mismo (ya se reprodujo localmente)
		if sender_id == target_id: return
		target_node = local_player
	elif remote_players.has(target_id):
		target_node = remote_players[target_id]
	elif enemies.has(target_id):
		target_node = enemies[target_id]
	
	# 2. Reproducir efectos y teletransportar si es necesario
	if is_instance_valid(target_node):
		var skill_name = data.get("skillName", "")
		
		# v3.2: BLINK: teletransportar PRIMERO (oculta el nodo), luego VFX de llegada
		if skill_name == "BLINK" and data.has("pos") and target_node.has_method("teleport_to"):
			var new_pos = Vector2(data.pos.x, data.pos.y)
			target_node.teleport_to(new_pos)
			# El BLINK_IN se dispara después del delay interno de teleport_to (0.05s)
		elif target_node.has_method("play_skill_vfx"):
			target_node.play_skill_vfx(skill_name, float(data.get("powerValue", 0.0)))

func _on_clear_enemy_projectiles(data: Dictionary):
	var boss_id = str(data.get("bossId", ""))
	if boss_id != "" and is_instance_valid(combat_system) and combat_system.has_method("clear_boss_bullets"):
		combat_system.clear_boss_bullets(boss_id)

extends Node2D

# World.gd (Controlador Global v73.31 - Phoenix Universal Render)
# Optimización de Instanciación de Entidades y Parallax Stellar.

@onready var player_spawn = $PlayerSpawn
@onready var entities_node = $Entities
@onready var ui_hud = get_node_or_null("HUD/MainHUD")
@onready var ui_chat = get_node_or_null("HUD/ChatUI")
@onready var ui_inventory = get_node_or_null("HUD/Inventory")
@onready var ui_admin = get_node_or_null("HUD/MainHUD/AdminPanel")
@onready var local_player = $Player 
@onready var combat_system = $CombatSystem
var talent_system = null
var current_map_node = null # Referencia al mapa cargado actualmente

var remote_players = {}
var enemies = {}
var enemy_pool = []
const ENEMY_SCENE = preload("res://scenes/entities/Enemy.tscn")
var save_timer = 0.0
const SAVE_INTERVAL = 10.0
var respawn_timer = 0.0
var active_areas = {} # v260.80: Cache de zonas de efecto (Humo, etc)
var active_laser_tracking = {} # v266.730: Indicadores que siguen al jugador {enemy_id: {indicator, target_id}}


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
	NetworkManager.enemy_damaged.connect(_on_enemy_damaged) 
	NetworkManager.enemy_action.connect(_on_enemy_action) # v266.620: Mega Láser Indicator
	NetworkManager.clear_zone_entities.connect(_on_clear_zone_entities)
	NetworkManager.clear_zone_entities.connect(_update_hud_map_name) # v243.63: Sincronía HUD
	NetworkManager.clear_enemy_projectiles.connect(_on_clear_enemy_projectiles)
	NetworkManager.remote_skill_used.connect(_on_remote_skill_used)
	NetworkManager.spawn_area.connect(_on_spawn_area)
	NetworkManager.remove_area.connect(_on_remove_area)

	
	# v190.71: Sincronía en Caliente de Configuración Admin
	NetworkManager.config_updated.connect(_on_admin_config_received)
	
	talent_system = get_node_or_null("TalentSystem")
	
	if ui_hud: ui_hud.visible = false
	if ui_inventory: ui_inventory.visible = false
	if ui_admin: ui_admin.visible = false
	if ui_chat: ui_chat.visible = false
	
	_generate_stellar_data()
	
	# v267.900: Inicializar Overlay de Ceguera
	_setup_blindness_overlay()
	NetworkManager.blindness_event.connect(_on_blindness_event)

func _setup_blindness_overlay():
	var canvas = CanvasLayer.new()
	canvas.name = "BlindnessLayer"
	canvas.layer = 90 # Por debajo del HUD principal pero arriba del mundo
	add_child(canvas)
	
	var overlay = ColorRect.new()
	overlay.name = "Darkness"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 1)
	overlay.visible = false
	canvas.add_child(overlay)
	
	# Shader para el "agujero" de visión
	var mat = ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = """
		shader_type canvas_item;
		uniform vec2 player_pos;
		uniform float radius;
		void fragment() {
			float d = distance(UV, player_pos);
			if (d < radius) {
				discard;
			}
			COLOR = vec4(0.0, 0.0, 0.0, 1.0);
		}
	"""
	# Nota: Usaremos una versión más simple o CanvasModulate si el shader se complica, 
	# pero por ahora un ColorRect negro opaco con discard es lo más limpio.
	overlay.material = mat

func _on_blindness_event(data):
	var duration = data.get("duration", 5000.0) / 1000.0
	var radius_px = data.get("radius", 150.0)
	
	var overlay = get_node("BlindnessLayer/Darkness")
	if overlay:
		overlay.set_meta("radius_px", radius_px)
		overlay.visible = true
		# Animación de entrada
		var tw = create_tween()
		tw.tween_property(overlay, "modulate:a", 1.0, 0.3).from(0.0)
		await get_tree().create_timer(duration).timeout
		# Animación de salida
		var tw_out = create_tween()
		tw_out.tween_property(overlay, "modulate:a", 0.0, 0.5)
		await tw_out.finished
		overlay.visible = false

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
	
	# v267.900: Actualizar Agujero de Visión en Ceguera
	var overlay = get_node_or_null("BlindnessLayer/Darkness")
	if overlay and overlay.visible and is_instance_valid(local_player):
		var screen_pos = local_player.get_global_transform_with_canvas().get_origin()
		var screen_size = get_viewport().get_visible_rect().size
		var uv_pos = screen_pos / screen_size
		overlay.material.set_shader_parameter("player_pos", uv_pos)
		# Ajustar radio basado en la resolución (proporcional al ancho)
		var rad_norm = (overlay.get_meta("radius_px", 150.0) / screen_size.x)
		overlay.material.set_shader_parameter("radius", rad_norm)
	
	save_timer += delta; if save_timer >= SAVE_INTERVAL: save_timer = 0.0; _save_game_progress()
	if is_instance_valid(local_player) and local_player.is_dead:
		respawn_timer += delta
		if respawn_timer >= 3.0:
			respawn_timer = 0.0
			_perform_local_respawn()
	else: 
		respawn_timer = 0.0

	# v267.700: PROCESAR ANIMACIONES Y FÍSICA LOCAL DE VÓRTICES
	for id in active_areas.keys():
		var area = active_areas[id]
		if not is_instance_valid(area): continue
		
		if area.has_meta("type") and area.get_meta("type") == "vortex":
			# 1. Animación Manual (Sin Tweens para evitar el error de loop)
			var time = area.get_meta("time") + delta
			area.set_meta("time", time)
			var pulse = 1.0 + (sin(time * 4.0) * 0.05)
			var visual = area.get_node_or_null("Visual")
			if visual: visual.scale = Vector2(pulse, pulse)
			area.rotation += delta * 0.5
			
			# 2. SUCCIÓN LOCAL (Fuerza Física Real)
			var player = get_tree().get_first_node_in_group("player")
			if player and is_instance_valid(player):
				var dist_vec = area.global_position - player.global_position
				var dist = dist_vec.length()
				var radius = area.get_meta("radius")
				
				if dist < radius:
					# Fuerza de succión basada en el input del Admin Panel
					var pull_strength = area.get_meta("pull_force")
					
					# Normalizar para que valores como "10" o "20" sean razonables
					# (El servidor enviaba 8-12 por defecto)
					var proximity = 1.0 + (1.0 - dist / radius)
					
					# v267.800: Aplicar fuerza real en PX/S (multiplicamos por delta para que sea literal)
					# Si pones 10 en el panel, son 10 pixeles por segundo.
					var force = dist_vec.normalized() * (pull_strength * proximity) * delta
					
					player.global_position += force
					if player.has_method("apply_shake"): player.apply_shake(0.3)

	# v266.730: ACTUALIZACIÓN DE SEGUIMIENTO MAESTRO (Mega Láser)
	for eid in active_laser_tracking.keys():
		var data = active_laser_tracking[eid]
		var indicator = data.get("indicator")
		var t_id = data.get("targetId")
		var length = data.get("range", 1000.0)
		
		if is_instance_valid(indicator) and indicator.get_parent():
			var en = indicator.get_parent()
			var target_node = null
			
			# Buscar el nodo del objetivo (Local o Remoto)
			if is_instance_valid(local_player) and str(local_player.get("entity_id")) == t_id:
				target_node = local_player
			elif remote_players.has(t_id):
				target_node = remote_players[t_id]
			
			# v266.970: Fallback Crítico - Si no coincide el ID, asumimos que somos el target
			if target_node == null and is_instance_valid(local_player):
				target_node = local_player
			
			if is_instance_valid(target_node) and not data.get("is_fixed", false):
				var target_angle = (target_node.global_position - en.global_position).angle()
				indicator.global_position = en.global_position
				
				# v266.940: Interpolación suave del apuntado (Homing Style)
				# 4.0 * delta proporciona un giro orgánico y esquivable
				indicator.global_rotation = lerp_angle(indicator.global_rotation, target_angle, 4.0 * delta)
				indicator.points = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT * length])
			elif data.get("is_fixed", false):
				indicator.global_position = en.global_position
				indicator.global_rotation = data.get("fixed_angle", 0.0)
				indicator.points = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT * length])
			else:
				# Si el target no es válido pero no es fijo, al menos seguimos la posición de la nave
				indicator.global_position = en.global_position
		else:
			active_laser_tracking.erase(eid)

func _input(event):
	var focusNode = get_viewport().gui_get_focus_owner()
	if focusNode is LineEdit or focusNode is TextEdit: return
	
	# v244.60: Bloquear interacciones si no hay sesión
	if not NetworkManager or not NetworkManager.is_logged_in: return
	
	# v266.200: Panel Admin interno desactivado - Usar Command Center (HTML)
	# if event is InputEventKey and event.pressed and event.keycode == KEY_F2:
	# 	if is_instance_valid(local_player):
	# 		var user_name = local_player.get("username")
	# 		if user_name and user_name == "Caelli94":
	# 			ui_admin.visible = !ui_admin.visible
	# 			if ui_admin.visible: ui_admin._refresh_ui()
	# 			get_viewport().set_input_as_handled()
	# 		else:
	# 			print("[SEGURIDAD] Intento de acceso denegado al Panel Admin.")
				
	# SISTEMA DE DUNGEON (Prueba)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_0:
		print("[DUNGEON] Solicitando ingreso a Dungeon Instanciada...")
		NetworkManager.send_event("enterDungeon", {})

func _update_hud_map_name(zone_id):
	var z_id = int(zone_id)
	var z_name = "SECTOR DESCONOCIDO"
	var z_id_str = str(z_id)
	
	if z_id_str in GameConstants.MAPS_CONFIG:
		z_name = GameConstants.MAPS_CONFIG[z_id_str].name
	elif z_id >= 500: 
		z_name = "INSTANCIA PRIVADA"
	else: 
		z_name = "SECTOR " + str(z_id).pad_zeros(2)
	
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
		
	if ui_hud: ui_hud.visible = true
	if ui_chat: ui_chat.visible = true

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


func _on_enemy_action(data: Dictionary):
	var action = data.get("action", "")
	var enemy_id = str(data.get("id", ""))
	
	if enemies.has(enemy_id):
		var en = enemies[enemy_id]
		var duration = float(data.get("duration", 2000.0)) / 1000.0
		var angle = float(data.get("angle", 0.0))
		var length = float(data.get("range", 1500.0))
		var t_id = str(data.get("targetId", ""))
		
		# v266.720: Limpieza de indicadores previos (INSTANTÁNEA v2)
		active_laser_tracking.erase(enemy_id)
		for child in en.get_children():
			if child.has_meta("is_laser_indicator"):
				en.remove_child(child)
				child.queue_free()
		
		if action == "charging":
			# v266.625: Indicador de Lux (Pre-fuego) - Seguimiento Activo
			var indicator = Line2D.new()
			indicator.set_meta("is_laser_indicator", true)
			indicator.width = 2.0
			indicator.default_color = Color(1, 0, 0, 0.4) 
			indicator.z_index = -1 
			
			indicator.top_level = true # v266.950: Desacoplar rotación del padre
			en.add_child(indicator) # Primero agregamos, después transformamos
			
			# v266.910: Usar el ángulo directo del servidor (hacia el player)
			indicator.global_position = en.global_position
			indicator.global_rotation = angle
			indicator.points = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT * length])
			
			# v266.735: Registrar para seguimiento en tiempo real
			if t_id != "":
				active_laser_tracking[enemy_id] = {
					"indicator": indicator,
					"targetId": t_id,
					"range": length,
					"is_fixed": false 
				}
			
			var tw = create_tween()
			tw.tween_property(indicator, "default_color:a", 0.8, duration)
			tw.finished.connect(indicator.queue_free)
			
		elif action == "locked":
			# v266.696: Fase de BLOQUEO - La mira se clava, es el momento de esquivar
			var indicator = Line2D.new()
			indicator.set_meta("is_laser_indicator", true)
			indicator.width = 4.0
			indicator.default_color = Color(1, 0, 0, 0.8)
			indicator.z_index = -1
			
			indicator.top_level = true # Independiente
			en.add_child(indicator)
			
			# v266.910: Clavar ángulo de disparo (Independiente de la nave)
			var fixed_shoot_angle = angle
			indicator.global_position = en.global_position
			indicator.global_rotation = fixed_shoot_angle
			indicator.points = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT * length])
			
			# v266.880: También trackear posición en fase locked para que no "flote"
			active_laser_tracking[enemy_id] = {
				"indicator": indicator,
				"targetId": "", 
				"fixed_angle": fixed_shoot_angle,
				"range": length,
				"is_fixed": true
			}
			
			en.set_meta("is_locked", true)
			await get_tree().create_timer(duration).timeout
			if is_instance_valid(en): en.set_meta("is_locked", false)
			if is_instance_valid(indicator): indicator.queue_free()

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
	var type = data.get("type", "SMOKE")
	var id = data.get("id", "")
	if type == "SMOKE":
		_spawn_smoke_cloud(id, Vector2(data.x, data.y), data.radius)
	elif type == "ICE":
		_spawn_ice_trail(id, Vector2(data.x, data.y), data.radius)
	elif type == "VORTEX_HAZARD":
		print("[VORTEX-DEBUG] Recibido Vórtice ID: ", id, " en pos: ", Vector2(data.x, data.y))
		_spawn_vortex_vfx(id, Vector2(data.x, data.y), data.radius, data)

func _spawn_vortex_vfx(id, pos, radius, data):
	if active_areas.has(id): return
	
	var container = Node2D.new()
	container.name = id
	container.global_position = pos
	container.z_index = 5
	entities_node.add_child(container)
	active_areas[id] = container
	
	# Almacenar datos para la succión local
	container.set_meta("radius", radius)
	container.set_meta("pull_force", data.get("pullForce", 8.0)) # v267.800: Sincronía Real
	container.set_meta("type", "vortex")
	container.set_meta("time", 0.0) # Para la animación manual
	
	var poly = Polygon2D.new()
	var pts = []
	for i in range(33):
		var ang = (i / 32.0) * TAU
		pts.append(Vector2(cos(ang), sin(ang)) * radius)
	
	poly.polygon = PackedVector2Array(pts)
	poly.color = Color(0.1, 0.0, 0.2, 0.6) 
	poly.name = "Visual"
	
	var line = Line2D.new()
	line.points = poly.polygon
	line.width = 3.0
	line.default_color = Color(0.8, 0.0, 1.0, 0.9)
	
	container.add_child(poly)
	container.add_child(line)


func _spawn_ice_trail(id, pos, _radius):
	if active_areas.has(id): return
	
	var container = Node2D.new()
	container.name = id
	entities_node.add_child(container)
	active_areas[id] = container
	
	# v246.3: EFECTO VENTISCA 100% PROCEDURAL (Sin assets externos)
	# Partículas nativas de Godot = 0 errores de carga
	var particles = CPUParticles2D.new()
	particles.emitting = true
	particles.amount = 20
	particles.lifetime = 1.5
	particles.one_shot = false
	particles.explosiveness = 0.0
	particles.z_index = 5
	
	# Forma de emisión circular
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 18.0
	
	# Movimiento de las partículas
	particles.direction = Vector2(0, -1)
	particles.spread = 180.0
	particles.initial_velocity_min = 8.0
	particles.initial_velocity_max = 25.0
	particles.gravity = Vector2.ZERO
	particles.damping_min = 5.0
	particles.damping_max = 10.0
	
	# Tamaño con variación
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 5.0
	
	# Color: degradado de blanco/cian brillante a transparente
	var gradient = Gradient.new()
	gradient.set_color(0, Color(0.8, 0.95, 1.0, 0.8))
	gradient.add_point(0.5, Color(0.4, 0.75, 1.0, 0.6))
	gradient.set_color(1, Color(0.3, 0.6, 1.0, 0.0))
	particles.color_ramp = gradient
	
	# Rotación aleatoria para variedad visual
	particles.angle_min = 0.0
	particles.angle_max = 360.0
	particles.angular_velocity_min = -90.0
	particles.angular_velocity_max = 90.0
	
	particles.global_position = pos
	container.add_child(particles)
	
	# Resplandor central estático (aura de hielo)
	var glow = Sprite2D.new()
	var glow_tex = load("res://assets/Esferas/EsferaAzul1.png")
	if glow_tex:
		glow.texture = glow_tex
		var glow_mat = CanvasItemMaterial.new()
		glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow.material = glow_mat
		glow.modulate = Color(0.5, 0.8, 1.0, 0.35)
		glow.scale = Vector2(0.15, 0.15)
		glow.z_index = 4
		glow.global_position = pos
		container.add_child(glow)
		
		# Animación de aparición suave del resplandor
		var tw = create_tween()
		tw.tween_property(glow, "modulate:a", 0.35, 0.3).set_trans(Tween.TRANS_SINE)

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
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.0 
	node3d.add_child(cam)
	
	# v260.98: look_at requiere que el nodo esté en el árbol (Fix: Node not inside tree)
	cam.look_at(Vector3.ZERO)
	
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
	var new_world_size = 2000.0 if (is_dungeon or int(_zoneId) > 2 or int(_zoneId) == 1) else 4000.0
	
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
	var zid = int(zone_id)
	var scene_path = "res://scenes/maps/Map_Default.tscn"
	
	if zid == 1:
		scene_path = "res://scenes/maps/Map_Loby.tscn"
		
	if is_instance_valid(current_map_node):
		current_map_node.queue_free()
		
	var map_scene = load(scene_path)
	if map_scene:
		current_map_node = map_scene.instantiate()
		add_child(current_map_node)
		move_child(current_map_node, 0) # Asegurar que quede detrás de las entidades
		
		# Si la escena tiene setup_map, lo ejecutamos
		if current_map_node.has_method("setup_map"):
			current_map_node.setup_map()

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

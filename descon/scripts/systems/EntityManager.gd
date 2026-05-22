extends Node

# EntityManager.gd (v1.0 - Gestor de Entidades de Red Desacoplado)

var world = null

var remote_players = {}
var enemies = {}
var enemy_pool = []
var active_areas = {} # Cache de zonas de efecto (Humo, etc)
var active_laser_tracking = {} # Indicadores que siguen al jugador {enemy_id: {indicator, target_id}}

const ENEMY_SCENE = preload("res://scenes/entities/Enemy.tscn")

func setup(world_ref):
	world = world_ref
	print("[EntityManager] Vinculado al controlador de mundo exitosamente.")
	
	# Suscripciones Centralizadas de Eventos de Red
	NetworkManager.player_updated.connect(_on_player_updated)
	NetworkManager.player_stat_sync.connect(_on_remote_stat_sync)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.enemy_updated.connect(_on_enemy_updated)
	NetworkManager.player_fired.connect(_on_player_fired)
	NetworkManager.enemy_fired.connect(_on_enemy_fired)
	NetworkManager.enemy_dead.connect(_on_enemy_dead)
	NetworkManager.enemy_damaged.connect(_on_enemy_damaged) 
	NetworkManager.enemy_healed.connect(_on_enemy_healed)
	NetworkManager.enemy_action.connect(_on_enemy_action)
	NetworkManager.clear_zone_entities.connect(_on_clear_zone_entities)
	NetworkManager.clear_enemy_projectiles.connect(_on_clear_enemy_projectiles)
	NetworkManager.remote_skill_used.connect(_on_remote_skill_used)
	NetworkManager.spawn_area.connect(_on_spawn_area)
	NetworkManager.remove_area.connect(_on_remove_area)
	NetworkManager.beacon_pulse.connect(_on_beacon_pulse)
	NetworkManager.hook_pulled.connect(_on_hook_pulled)

func _process(delta):
	# 0. Filtro Proactivo de Zonas para prevenir Entidades Huérfanas (v3.0)
	if is_instance_valid(world) and is_instance_valid(world.local_player):
		var my_zone = _parse_zone_to_int(world.local_player.current_zone)
		
		# Limpiar Jugadores Remotos Huérfanos
		for pid in remote_players.keys():
			var rp = remote_players[pid]
			if is_instance_valid(rp):
				var rp_zone = rp.get_meta("zone") if rp.has_meta("zone") else -1
				if rp_zone != -1 and rp_zone != my_zone:
					remote_players.erase(pid)
					rp.queue_free()
					print("[EntityManager SINC] Piloto huérfano removido por cambio de zona: ", pid)
					
		# Limpiar Enemigos Huérfanos
		for eid in enemies.keys():
			var en = enemies[eid]
			if is_instance_valid(en):
				var en_zone = en.get_meta("zone") if en.has_meta("zone") else -1
				if en_zone != -1 and en_zone != my_zone:
					en.set_meta("is_pooled", true)
					en.visible = false
					en.set_process(false)
					en.set_physics_process(false)
					if en.get("_collision_shape"):
						en.get("_collision_shape").set_deferred("disabled", true)
					if en.get("_ui_wrapper"): en.get("_ui_wrapper").visible = false
					enemies.erase(eid)
					print("[EntityManager SINC] Enemigo huérfano purgado por cambio de zona: ", eid)

	# 1. Procesar físicas locales de succión de Vórtices y Lazos Curativos
	for id in active_areas.keys():
		var area = active_areas[id]
		if not is_instance_valid(area): continue

		if area.has_meta("type") and area.get_meta("type") == "VITAL_LINK":
			var owner_id = area.get_meta("ownerId")
			var target_id = area.get_meta("targetId")
			
			var owner_node = null
			var target_node = null
			
			if is_instance_valid(world) and is_instance_valid(world.local_player) and world.local_player.entity_id == owner_id:
				owner_node = world.local_player
			elif remote_players.has(owner_id):
				owner_node = remote_players[owner_id]
			elif enemies.has(owner_id):
				owner_node = enemies[owner_id]
				
			if is_instance_valid(world) and is_instance_valid(world.local_player) and world.local_player.entity_id == target_id:
				target_node = world.local_player
			elif remote_players.has(target_id):
				target_node = remote_players[target_id]
			elif enemies.has(target_id):
				target_node = enemies[target_id]
				
			if is_instance_valid(owner_node) and is_instance_valid(target_node):
				# Centrar el contenedor en el emisor
				area.global_position = owner_node.global_position
				
				# Dibujar el rayo de plasma verde usando coordenadas globales directas (gracias a set_as_top_level)
				var rayo_node = area.get_node_or_null("RayoVerde")
				if rayo_node:
					var start_pos = owner_node.global_position + Vector2(0, -20)
					var end_pos = target_node.global_position + Vector2(0, -20)
					rayo_node.points = [start_pos, end_pos]
					
					var pulse = area.get_meta("pulse_timer") + delta * 12.0
					area.set_meta("pulse_timer", pulse)
					rayo_node.width = 5.0 + sin(pulse) * 1.5
				
				# Rotar el anillo celeste de rango maximo (Karma style)
				var ring_node = area.get_node_or_null("LimitRing")
				if ring_node:
					ring_node.rotation += delta * 0.2
			else:
				var rayo_node = area.get_node_or_null("RayoVerde")
				if rayo_node: rayo_node.points = []
			continue
		
		if area.has_meta("type") and area.get_meta("type") == "vortex":
			var time = area.get_meta("time") + delta
			area.set_meta("time", time)
			var pulse = 1.0 + (sin(time * 4.0) * 0.05)
			var visual = area.get_node_or_null("Visual")
			if visual: visual.scale = Vector2(pulse, pulse)
			area.rotation += delta * 0.5
			
			if is_instance_valid(world) and is_instance_valid(world.local_player):
				var player = world.local_player
				var dist_vec = area.global_position - player.global_position
				var dist = dist_vec.length()
				var radius = area.get_meta("radius")
				
				if dist < radius:
					var pull_strength = area.get_meta("pull_force")
					var proximity = 1.0 + (1.0 - dist / radius)
					var force = dist_vec.normalized() * (pull_strength * proximity) * delta
					player.global_position += force
					if player.has_method("apply_shake"): player.apply_shake(0.3)

	# 2. Procesar tracking de lásers en tiempo real (Mega Láser)
	for eid in active_laser_tracking.keys():
		var data = active_laser_tracking[eid]
		var indicator = data.get("indicator")
		var t_id = data.get("targetId")
		var length = data.get("range", 1000.0)
		
		if is_instance_valid(indicator) and indicator.get_parent():
			var en = indicator.get_parent()
			var target_node = null
			
			if is_instance_valid(world) and is_instance_valid(world.local_player) and str(world.local_player.get("entity_id")) == t_id:
				target_node = world.local_player
			elif remote_players.has(t_id):
				target_node = remote_players[t_id]
			
			if target_node == null and is_instance_valid(world) and is_instance_valid(world.local_player):
				target_node = world.local_player
			
			if is_instance_valid(target_node) and not data.get("is_fixed", false):
				var target_angle = (target_node.global_position - en.global_position).angle()
				indicator.global_position = en.global_position
				indicator.global_rotation = lerp_angle(indicator.global_rotation, target_angle, 4.0 * delta)
				indicator.points = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT * length])
			elif data.get("is_fixed", false):
				indicator.global_position = en.global_position
				indicator.global_rotation = data.get("fixed_angle", 0.0)
				indicator.points = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT * length])
			else:
				indicator.global_position = en.global_position
		else:
			active_laser_tracking.erase(eid)

func _parse_zone_to_int(zone_var) -> int:
	var val = zone_var
	if typeof(val) == TYPE_DICTIONARY:
		val = val.get("zoneId", 1)
	
	if typeof(val) == TYPE_STRING:
		if val.begins_with("dungeon"):
			return 99
		elif val.begins_with("extract_"):
			var parts = val.split("_")
			if parts.size() > 1:
				return int(parts[1])
			return 10
		else:
			return int(val)
	return int(val)

func _on_player_updated(data):
	if typeof(data) != TYPE_DICTIONARY or not data.has("id"): return
	var id = str(data.id)
	if id == "" or id == "null": return
	
	var remote_zone = _parse_zone_to_int(data.get("zone", -1))
	
	# Filtro de Zona Crítico
	if is_instance_valid(world) and is_instance_valid(world.local_player):
		var local_zone = _parse_zone_to_int(world.local_player.current_zone)
		
		if remote_zone != -1 and remote_zone != local_zone:
			if remote_players.has(id):
				var rp = remote_players[id]
				remote_players.erase(id)
				if is_instance_valid(rp): rp.queue_free()
			return
	
	if is_instance_valid(world) and is_instance_valid(world.local_player) and (id == world.local_player.entity_id and id != ""):
		if data.has("hp"): world.local_player.current_hp = float(data.hp)
		if data.has("shield"): world.local_player.current_shield = float(data.shield)
		elif data.has("sh"): world.local_player.current_shield = float(data.sh)
		
		world.local_player.update_stats(data)
		
		if data.has("pvpEnabled") and is_instance_valid(world.ui_hud):
			world.ui_hud.set_pvp_status(data.pvpEnabled)
		return

	if enemies.has(id): return 

	var is_new = false
	if not remote_players.has(id):
		var rp = load("res://scenes/entities/Ship.tscn").instantiate()
		rp.entity_id = id
		rp.db_id = str(data.get("id", ""))
		rp.add_to_group("remote_players")
		remote_players[id] = rp
		is_new = true
		if is_instance_valid(world) and is_instance_valid(world.entities_node):
			world.entities_node.add_child(rp)
	
	var p = remote_players[id]
	if is_instance_valid(p):
		var new_pos = Vector2(data.get("x", p.global_position.x), data.get("y", p.global_position.y))
		var new_rot = data.get("rotation", p.rotation)
		p.target_position = new_pos
		p.target_rotation = new_rot
		if is_new:
			p.global_position = new_pos
			p.rotation = new_rot
			if is_instance_valid(p.world_root_3d):
				var s_factor = p.get_meta("map_scale", 0.02)
				p.world_root_3d.position.x = new_pos.x * s_factor
				p.world_root_3d.position.z = new_pos.y * s_factor
				p.world_root_3d.position.y = 0.0
		p.set_meta("zone", remote_zone)
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
	if is_instance_valid(world) and is_instance_valid(world.entities_node):
		world.entities_node.add_child(en)
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
		
		active_laser_tracking.erase(enemy_id)
		for child in en.get_children():
			if child.has_meta("is_laser_indicator"):
				en.remove_child(child)
				child.queue_free()
		
		if action == "charging":
			var indicator = Line2D.new()
			indicator.set_meta("is_laser_indicator", true)
			indicator.width = 2.0
			indicator.default_color = Color(1, 0, 0, 0.4) 
			indicator.z_index = -1 
			
			indicator.top_level = true 
			en.add_child(indicator) 
			
			indicator.global_position = en.global_position
			indicator.global_rotation = angle
			indicator.points = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT * length])
			
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
			var indicator = Line2D.new()
			indicator.set_meta("is_laser_indicator", true)
			indicator.width = 4.0
			indicator.default_color = Color(1, 0, 0, 0.8)
			indicator.z_index = -1
			
			indicator.top_level = true
			en.add_child(indicator)
			
			var fixed_shoot_angle = angle
			indicator.global_position = en.global_position
			indicator.global_rotation = fixed_shoot_angle
			indicator.points = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT * length])
			
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
	
	if remote_players.has(id): return
	
	if is_instance_valid(world) and is_instance_valid(world.local_player):
		var enemy_zone = _parse_zone_to_int(data.get("zone", -1))
		var my_zone = _parse_zone_to_int(world.local_player.current_zone)
		
		if enemy_zone != my_zone:
			if enemies.has(id):
				var old_en = enemies[id]
				if is_instance_valid(old_en): 
					old_en.set_meta("is_pooled", true); old_en.visible = false; old_en.set_process(false); old_en.set_physics_process(false)
				enemies.erase(id)
			return

	var is_new = false
	if not enemies.has(id):
		var en = _get_enemy_from_pool()
		en.entity_id = id
		if not en.is_in_group("enemies"): en.add_to_group("enemies")
		enemies[id] = en
		is_new = true
	var eref = enemies[id]
	if is_instance_valid(eref):
		var new_pos = Vector2(data.get("x", eref.global_position.x), data.get("y", eref.global_position.y) if data.has("y") else eref.global_position.y)
		var new_rot = data.get("rotation", eref.rotation)
		eref.target_position = new_pos
		eref.target_rotation = new_rot
		if is_new:
			eref.global_position = new_pos
			eref.rotation = new_rot
			if is_instance_valid(eref.world_root_3d):
				var s_factor = eref.get_meta("map_scale", 0.02)
				eref.world_root_3d.position.x = new_pos.x * s_factor
				eref.world_root_3d.position.z = new_pos.y * s_factor
				eref.world_root_3d.position.y = 0.0
		var enemy_zone = _parse_zone_to_int(data.get("zone", -1))
		if enemy_zone != -1:
			eref.set_meta("zone", enemy_zone)
		eref.update_stats(data); eref.visible = true; eref.show()
	else:
		enemies.erase(id)

func _on_player_disconnected(id):
	var sid = str(id)
	if remote_players.has(sid):
		remote_players[sid].queue_free()
		remote_players.erase(sid)

func clear_remote_players():
	for id in remote_players:
		if is_instance_valid(remote_players[id]): remote_players[id].queue_free()
	remote_players.clear()
	for id in enemies:
		if is_instance_valid(enemies[id]): 
			enemies[id].set_meta("is_pooled", true); enemies[id].visible = false; enemies[id].set_process(false); enemies[id].set_physics_process(false)
	enemies.clear()
	print("[EntityManager] Universo limpiado correctamente.")

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
		if en.has_method("update_stats"):
			en.update_stats(data)
		if en.has_method("reset_combat_timer"):
			en.reset_combat_timer()

func _on_enemy_healed(data: Dictionary):
	var id = str(data.get("id", ""))
	if id == "" or not enemies.has(id): return
	var en = enemies[id]
	if is_instance_valid(en):
		if en.has_method("update_stats"):
			en.update_stats(data)
		var amount = data.get("amount", 0)
		if en.has_method("_spawn_damage_text"):
			en._spawn_damage_text("+" + str(int(amount)), Color.GREEN)

func _on_hook_pulled(data: Dictionary):
	var attacker_id = str(data.get("attackerId", ""))
	var victim_id = str(data.get("victimId", ""))
	
	var attacker_node = enemies.get(attacker_id)
	var victim_node = null
	
	if is_instance_valid(world) and is_instance_valid(world.local_player) and world.local_player.entity_id == victim_id:
		victim_node = world.local_player
	elif remote_players.has(victim_id):
		victim_node = remote_players[victim_id]
	
	if is_instance_valid(attacker_node) and is_instance_valid(victim_node) and is_instance_valid(world) and is_instance_valid(world.entities_node):
		var chain = Line2D.new()
		chain.width = 4.0
		chain.default_color = Color(0.7, 0.7, 0.7, 0.8) 
		chain.z_index = 4
		world.entities_node.add_child(chain)
		
		var start_pos = attacker_node.global_position
		var end_pos = victim_node.global_position
		chain.points = PackedVector2Array([start_pos, end_pos])
		
		var tw = create_tween()
		tw.tween_property(chain, "modulate:a", 0.0, 0.5)
		tw.finished.connect(chain.queue_free)
		
		var angle = (victim_node.global_position - attacker_node.global_position).angle()
		var target_pos = attacker_node.global_position + Vector2.RIGHT.rotated(angle) * 100.0
		
		var pull_speed = float(data.get("pullSpeed", 1500.0))
		var dist = victim_node.global_position.distance_to(target_pos)
		var duration = clamp(dist / pull_speed, 0.1, 0.8) 
		
		var tw_pull = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw_pull.tween_property(victim_node, "global_position", target_pos, duration)

func route_chat_bubble(data: Dictionary):
	var sid = str(data.get("senderId", ""))
	var txt = str(data.get("msg", data.get("text", "")))
	
	var target = null
	if is_instance_valid(world) and is_instance_valid(world.local_player) and (sid == world.local_player.entity_id or data.get("sender") == world.local_player.username):
		target = world.local_player
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
		_spawn_vortex_vfx(id, Vector2(data.x, data.y), data.radius, data)
	elif type == "HEAL_ZONE":
		_spawn_heal_zone_vfx(id, Vector2(data.x, data.y), data.radius, data)
	elif type == "VITAL_LINK":
		_spawn_vital_link_vfx(id, data)
	elif type == "WIND_BARRIER":
		_spawn_wind_barrier_vfx(id, Vector2(data.x, data.y), data.radius, data)
	elif type == "HEAL_BEACON":
		_spawn_heal_beacon_vfx(id, Vector2(data.x, data.y), data.radius, data)

func _spawn_heal_zone_vfx(id, pos, radius, data = {}):

	if active_areas.has(id): return
	
	var container = Node2D.new()
	container.name = id
	if is_instance_valid(world) and is_instance_valid(world.entities_node):
		world.entities_node.add_child(container)
	active_areas[id] = container
	container.global_position = pos
	
	var owner_id = str(data.get("ownerId", ""))
	var start_pos = pos
	var emisor_node = null
	
	if is_instance_valid(world) and is_instance_valid(world.local_player) and world.local_player.entity_id == owner_id:
		emisor_node = world.local_player
	elif remote_players.has(owner_id):
		emisor_node = remote_players[owner_id]
		
	if is_instance_valid(emisor_node):
		start_pos = emisor_node.global_position

	# 1. Anillo/Círculo base verde translúcido
	var poly = Polygon2D.new()
	var pts = []
	for i in range(33):
		var ang = (i / 32.0) * TAU
		pts.append(Vector2(cos(ang), sin(ang)) * radius)
	
	poly.polygon = PackedVector2Array(pts)
	poly.color = Color(0.0, 0.4, 0.1, 0.12)
	poly.name = "RangeVisual"
	
	var line = Line2D.new()
	line.points = poly.polygon
	line.width = 2.0
	line.default_color = Color(0.0, 1.0, 0.3, 0.45)
	
	container.add_child(poly)
	container.add_child(line)

	# 2. Partículas hermosas de curación verdes
	var particles = CPUParticles2D.new()
	particles.emitting = false
	particles.amount = 15
	particles.lifetime = 1.8
	particles.one_shot = false
	particles.explosiveness = 0.0
	particles.z_index = 5
	
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = float(radius) * 0.7
	
	particles.direction = Vector2(0, -1)
	particles.spread = 45.0
	particles.initial_velocity_min = 15.0
	particles.initial_velocity_max = 35.0
	particles.gravity = Vector2.ZERO
	particles.damping_min = 2.0
	particles.damping_max = 5.0
	
	particles.scale_amount_min = 3.0
	particles.scale_amount_max = 6.0
	
	var gradient = Gradient.new()
	gradient.set_color(0, Color(0.2, 1.0, 0.4, 0.9))
	gradient.add_point(0.5, Color(0.0, 0.8, 0.2, 0.6))
	gradient.set_color(1, Color(0.0, 0.5, 0.1, 0.0))
	particles.color_ramp = gradient
	
	particles.angle_min = 0.0
	particles.angle_max = 360.0
	particles.angular_velocity_min = -60.0
	particles.angular_velocity_max = 60.0
	
	container.add_child(particles)

	# 3. Icono / Esfera flotante y giratoria verde premium (3D Look)
	var item_sprite = Sprite2D.new()
	var item_tex = load("res://assets/Efectos de Skills/Curacion(Transp).png")
	if not item_tex:
		item_tex = load("res://assets/Esferas/EsferaVerde1.png")
	
	if item_tex:
		item_sprite.texture = item_tex
		var item_mat = CanvasItemMaterial.new()
		item_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		item_sprite.material = item_mat
		item_sprite.modulate = Color(0.2, 1.0, 0.4, 0.8)
		item_sprite.scale = Vector2(0.22, 0.22)
		item_sprite.z_index = 6
		container.add_child(item_sprite)

	# Si el emisor está lejos, simular el lanzamiento balístico (viaje del proyectil)
	if start_pos.distance_to(pos) > 50.0:
		poly.visible = false
		line.visible = false
		item_sprite.visible = false
		particles.emitting = false
		
		# Crear el proyectil arrojable visual
		var proj = Sprite2D.new()
		proj.texture = item_tex
		var proj_mat = CanvasItemMaterial.new()
		proj_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		proj.material = proj_mat
		proj.modulate = Color(0.3, 1.0, 0.5, 0.95)
		proj.scale = Vector2(0.12, 0.12)
		proj.global_position = start_pos
		proj.z_index = 8
		if is_instance_valid(world) and is_instance_valid(world.entities_node):
			world.entities_node.add_child(proj)
			
		# Añadir estela al proyectil viajero
		var trail = CPUParticles2D.new()
		trail.amount = 10
		trail.lifetime = 0.3
		trail.gravity = Vector2.ZERO
		trail.scale_amount_min = 2.0
		trail.scale_amount_max = 4.0
		trail.color_ramp = gradient
		proj.add_child(trail)
		
		var travel_time = clamp(start_pos.distance_to(pos) / 950.0, 0.2, 0.5)
		var tw = proj.create_tween().set_parallel(true)
		tw.tween_property(proj, "global_position", pos, travel_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		
		# Simular arco alto 3D inflando la escala a la mitad del trayecto
		tw.tween_property(proj, "scale", Vector2(0.24, 0.24), travel_time / 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.chain().tween_property(proj, "scale", Vector2(0.12, 0.12), travel_time / 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		
		tw.finished.connect(func():
			if is_instance_valid(proj):
				proj.queue_free()
			if is_instance_valid(container):
				poly.visible = true
				line.visible = true
				item_sprite.visible = true
				particles.emitting = true
				
				# Destello de impacto verde brillante
				var flash = Sprite2D.new()
				flash.texture = item_tex
				var flash_mat = CanvasItemMaterial.new()
				flash_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
				flash.material = flash_mat
				flash.modulate = Color(0.4, 1.0, 0.6, 1.0)
				flash.scale = Vector2(0.05, 0.05)
				container.add_child(flash)
				
				var tw_flash = flash.create_tween()
				tw_flash.tween_property(flash, "scale", Vector2(0.55, 0.55), 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				tw_flash.parallel().tween_property(flash, "modulate:a", 0.0, 0.15)
				tw_flash.finished.connect(flash.queue_free)
				
				# Iniciar oscilación e rotación infinitas
				var tw_float = container.create_tween().set_loops()
				tw_float.tween_property(item_sprite, "position:y", -8.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
				tw_float.tween_property(item_sprite, "position:y", 8.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
				
				var tw_rot = container.create_tween().set_loops()
				tw_rot.tween_property(item_sprite, "rotation_degrees", 360.0, 4.0)
		)
	else:
		particles.emitting = true
		var tw_float = container.create_tween().set_loops()
		tw_float.tween_property(item_sprite, "position:y", -8.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw_float.tween_property(item_sprite, "position:y", 8.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		
		var tw_rot = container.create_tween().set_loops()
		tw_rot.tween_property(item_sprite, "rotation_degrees", 360.0, 4.0)

func _spawn_vortex_vfx(id, pos, radius, data):
	if active_areas.has(id): return
	
	var container = Node2D.new()
	container.name = id
	container.global_position = pos
	container.z_index = 5
	if is_instance_valid(world) and is_instance_valid(world.entities_node):
		world.entities_node.add_child(container)
	active_areas[id] = container
	
	container.set_meta("radius", radius)
	container.set_meta("pull_force", data.get("pullForce", 8.0)) 
	container.set_meta("type", "vortex")
	container.set_meta("time", 0.0) 
	
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
	if is_instance_valid(world) and is_instance_valid(world.entities_node):
		world.entities_node.add_child(container)
	active_areas[id] = container
	
	var particles = CPUParticles2D.new()
	particles.emitting = true
	particles.amount = 20
	particles.lifetime = 1.5
	particles.one_shot = false
	particles.explosiveness = 0.0
	particles.z_index = 5
	
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 18.0
	
	particles.direction = Vector2(0, -1)
	particles.spread = 180.0
	particles.initial_velocity_min = 8.0
	particles.initial_velocity_max = 25.0
	particles.gravity = Vector2.ZERO
	particles.damping_min = 5.0
	particles.damping_max = 10.0
	
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 5.0
	
	var gradient = Gradient.new()
	gradient.set_color(0, Color(0.8, 0.95, 1.0, 0.8))
	gradient.add_point(0.5, Color(0.4, 0.75, 1.0, 0.6))
	gradient.set_color(1, Color(0.3, 0.6, 1.0, 0.0))
	particles.color_ramp = gradient
	
	particles.angle_min = 0.0
	particles.angle_max = 360.0
	particles.angular_velocity_min = -90.0
	particles.angular_velocity_max = 90.0
	
	particles.global_position = pos
	container.add_child(particles)
	
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
		
		var tw = create_tween()
		tw.tween_property(glow, "modulate:a", 0.35, 0.3).set_trans(Tween.TRANS_SINE)

func _on_remove_area(data: Dictionary):
	var id = data.get("id", "")
	if active_areas.has(id):
		var area = active_areas[id]
		active_areas.erase(id)
		if is_instance_valid(area):
			var tw = area.create_tween().set_parallel(true)
			tw.tween_property(area, "scale", Vector2.ZERO, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tw.tween_property(area, "modulate:a", 0.0, 0.15)
			tw.chain().tween_callback(area.queue_free)

func _spawn_heal_beacon_vfx(id, pos, radius, _data = {}):
	if active_areas.has(id): return
	
	var vfx_script = load("res://scripts/vfx/HealBeaconVFX.gd")
	if vfx_script:
		var beacon = vfx_script.new()
		beacon.name = id
		beacon.global_position = pos
		beacon.radius = radius
		beacon.z_index = 2 # Capa alta de efectos terrestres y boyas
		
		if is_instance_valid(world) and is_instance_valid(world.entities_node):
			world.entities_node.add_child(beacon)
		else:
			get_parent().add_child(beacon)
			
		active_areas[id] = beacon

func _on_beacon_pulse(data: Dictionary):
	var id = data.get("id", "")
	if active_areas.has(id):
		var beacon = active_areas[id]
		if is_instance_valid(beacon) and beacon.has_method("pulse"):
			var pulse_radius = float(data.get("radius", 200.0))
			beacon.pulse(pulse_radius)

func _spawn_smoke_cloud(id, pos, radius):
	if active_areas.has(id): return
	
	var wrapper = Node2D.new()
	wrapper.name = id
	wrapper.global_position = pos
	wrapper.z_index = -1 
	if is_instance_valid(world) and is_instance_valid(world.entities_node):
		world.entities_node.add_child(wrapper)
	active_areas[id] = wrapper
	
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
	cam.look_at(Vector3.ZERO)
	
	var mesh_inst = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(2, 2)
	mesh_inst.mesh = plane
	mesh_inst.rotation_degrees.x = 90
	
	var mat = ShaderMaterial.new()
	mat.shader = load("res://resources/shaders/smoke_cloud.gdshader")
	mesh_inst.material_override = mat
	node3d.add_child(mesh_inst)
	
	var sprite = Sprite2D.new()
	sprite.texture = vp.get_texture()
	wrapper.add_child(sprite)
	
	wrapper.modulate.a = 0.0
	wrapper.scale = Vector2(0.5, 0.5) 
	var tw = create_tween().set_parallel(true)
	tw.tween_property(wrapper, "modulate:a", 1.0, 0.2)
	tw.tween_property(wrapper, "scale", Vector2(1.0, 1.0), 0.4).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

func _on_remote_stat_sync(data: Dictionary):
	if typeof(data) != TYPE_DICTIONARY: return
	var id = str(data.get("id", ""))
	
	if is_instance_valid(world) and is_instance_valid(world.local_player) and (id == world.local_player.entity_id or id == ""):
		world.local_player.update_stats(data)
		return
		
	if id != "" and remote_players.has(id):
		var p = remote_players[id]
		if is_instance_valid(p): p.update_stats(data)

func _on_local_shoot(d): 
	if is_instance_valid(world) and is_instance_valid(world.combat_system): 
		world.combat_system.handle_local_shoot(d)

func _on_player_fired(d): 
	if is_instance_valid(world) and is_instance_valid(world.combat_system): 
		world.combat_system.handle_remote_shoot(d)

func _on_enemy_fired(d): 
	if is_instance_valid(world) and is_instance_valid(world.combat_system): 
		world.combat_system.handle_enemy_shoot(d)

func _on_remote_skill_used(data):
	if typeof(data) != TYPE_DICTIONARY: return
	
	var sender_id = str(data.get("id", ""))
	var target_id = str(data.get("targetId", sender_id))
	
	var target_node = null
	var skill_name = data.get("skillName", "")
	
	if is_instance_valid(world) and is_instance_valid(world.local_player) and world.local_player.entity_id == target_id:
		if sender_id == target_id and skill_name != "REGENERACIÓN ALFA": return
		target_node = world.local_player
	elif remote_players.has(target_id):
		target_node = remote_players[target_id]
	elif enemies.has(target_id):
		target_node = enemies[target_id]
	
	if is_instance_valid(target_node):
		if skill_name == "BLINK" and data.has("pos") and target_node.has_method("teleport_to"):
			var new_pos = Vector2(data.pos.x, data.pos.y)
			target_node.teleport_to(new_pos)
		elif target_node.has_method("play_skill_vfx"):
			target_node.play_skill_vfx(skill_name, float(data.get("powerValue", 0.0)))

func _on_clear_zone_entities(payload):
	var _zoneId = payload
	var spawn_pos = null

	if typeof(payload) == TYPE_DICTIONARY:
		_zoneId = payload.get("zoneId", 1)
		if payload.has("x") and payload.has("y"):
			spawn_pos = Vector2(payload.x, payload.y)

	for id in enemies:
		if is_instance_valid(enemies[id]): 
			enemies[id].set_meta("is_pooled", true); enemies[id].visible = false; enemies[id].set_process(false); enemies[id].set_physics_process(false)
	enemies.clear()
	
	for id in remote_players:
		if is_instance_valid(remote_players[id]): remote_players[id].queue_free()
	remote_players.clear()
	
	if is_instance_valid(world) and is_instance_valid(world.combat_system) and world.combat_system.has_method("clear_all_bullets"):
		world.combat_system.clear_all_bullets()
		
	var is_dungeon = str(_zoneId).begins_with("dungeon")
	var is_extraction = str(_zoneId).begins_with("extract_")
	var new_world_size = 10000.0 if is_extraction else (2000.0 if (is_dungeon or int(_zoneId) > 2 or int(_zoneId) == 1) else 4000.0)
	
	var zone_int = _parse_zone_to_int(_zoneId)
	if is_instance_valid(world) and is_instance_valid(world.local_player):
		world.local_player.set("current_zone", zone_int)
		print("[EntityManager ZONE] Sincronía Preventiva: Zona actualizada a ", zone_int)

	if is_instance_valid(world) and is_instance_valid(world.local_player):
		if spawn_pos != null:
			world.local_player.global_position = spawn_pos
		else:
			world.local_player.global_position = Vector2(new_world_size / 2, new_world_size / 2)
		world.local_player.target_position = world.local_player.global_position
		world.local_player.is_moving = false
	
	var radar = world.ui_hud.get_node_or_null("MinimapUI") if is_instance_valid(world) and is_instance_valid(world.ui_hud) else null
	if radar and "world_size" in radar:
		radar.world_size = new_world_size
		
	if is_instance_valid(world):
		world._update_background(_zoneId)
		print("[EntityManager ZONE] Transición completa a zona: ", _zoneId, " | Nueva Posición: ", world.local_player.global_position if is_instance_valid(world.local_player) else "N/A")

func _on_clear_enemy_projectiles(data: Dictionary):
	var boss_id = str(data.get("bossId", ""))
	if boss_id != "" and is_instance_valid(world) and is_instance_valid(world.combat_system) and world.combat_system.has_method("clear_boss_bullets"):
		world.combat_system.clear_boss_bullets(boss_id)

func _spawn_vital_link_vfx(id: String, data: Dictionary):
	if active_areas.has(id): return
	
	var container = Node2D.new()
	container.name = id
	if is_instance_valid(world) and is_instance_valid(world.entities_node):
		world.entities_node.add_child(container)
	active_areas[id] = container
	
	container.set_meta("type", "VITAL_LINK")
	container.set_meta("ownerId", str(data.get("ownerId", "")))
	container.set_meta("targetId", str(data.get("targetId", "")))
	container.set_meta("pulse_timer", 0.0)
	
	var break_range = float(data.get("radius", 500.0))
	container.set_meta("radius", break_range)
	
	# 1. Anillo/Límite celeste translúcido centrado en el emisor (Karma style)
	var limit_ring = Line2D.new()
	limit_ring.name = "LimitRing"
	limit_ring.width = 1.5
	limit_ring.default_color = Color(0.0, 0.7, 1.0, 0.28) # Celeste vibrante translúcido
	limit_ring.z_index = -1 # Detrás de las naves
	
	var ring_pts = []
	var segments = 64
	for i in range(segments + 1):
		var ang = (i / float(segments)) * TAU
		ring_pts.append(Vector2(cos(ang), sin(ang)) * break_range)
	limit_ring.points = ring_pts
	container.add_child(limit_ring)
	
	# 2. El rayo vinculante curativo Line2D (Verde brillante sólido y ultra-visible)
	var rayo = Line2D.new()
	rayo.name = "RayoVerde"
	rayo.width = 5.0
	rayo.default_color = Color(0.0, 1.0, 0.3, 0.95) # Verde eléctrico de alta intensidad
	rayo.z_index = 3 # Por encima de las naves para que se distinga perfectamente
	rayo.set_as_top_level(true) # IGNORAR transformaciones del contenedor parent y dibujar en el espacio global
	
	container.add_child(rayo)

func _spawn_wind_barrier_vfx(id, pos, _radius, _data = {}):
	if active_areas.has(id): return
	
	var container = Node2D.new()
	container.name = id
	if is_instance_valid(world) and is_instance_valid(world.entities_node):
		world.entities_node.add_child(container)
	active_areas[id] = container
	container.global_position = pos
	container.z_index = 0 # Nivel normal de naves para que se vea sobre el fondo pero con volumen
	
	# Rotar contenedor en base al ángulo de lanzamiento del viento
	var angle = float(_data.get("angle", 0.0))
	container.rotation = angle
	
	var width = float(_data.get("width", 150.0))
	var half_w = width / 2.0
	
	# PERSPECTIVA 3D (Proyección 2.5D superior):
	# Aumentamos la altura vertical de la barrera para que luzca imponente
	var persp_up = Vector2(0, -1).rotated(-angle)
	var height_3d = 65.0 # Altura volumétrica ampliada de 45 a 65
	
	var base_a = Vector2(0, -half_w)
	var base_b = Vector2(0, half_w)
	var top_a = base_a + persp_up * height_3d
	var top_b = base_b + persp_up * height_3d
	
	# 1. Cortina de viento translúcida (Polígono vertical holográfico de alta visibilidad)
	var poly = Polygon2D.new()
	var poly_pts = [base_a, base_b, top_b, top_a]
	poly.polygon = PackedVector2Array(poly_pts)
	poly.color = Color(0.05, 0.7, 0.95, 0.18) # Opacidad inicial aumentada
	container.add_child(poly)
	
	# Animar oscilación de opacidad para efecto de presión física de aire comprimido
	var tw_poly = container.create_tween().set_loops()
	tw_poly.tween_property(poly, "color", Color(0.1, 0.8, 1.0, 0.26), randf_range(0.35, 0.6)).set_trans(Tween.TRANS_SINE)
	tw_poly.tween_property(poly, "color", Color(0.0, 0.6, 0.9, 0.10), randf_range(0.35, 0.6)).set_trans(Tween.TRANS_SINE)
	
	# 2. Filamentos de corriente vertical (Acentúa el volumen y flujo masivo)
	var num_filaments = 10 # Aumentado de 8 a 10 para mayor densidad
	for i in range(num_filaments):
		var ratio = float(i) / float(num_filaments - 1)
		var pt_base = base_a.lerp(base_b, ratio)
		var pt_top = top_a.lerp(top_b, ratio)
		
		var filament = Line2D.new()
		filament.points = PackedVector2Array([pt_base, pt_top])
		filament.width = randf_range(2.0, 4.5)
		filament.default_color = Color(0.3, 0.9, 1.0, randf_range(0.2, 0.45))
		container.add_child(filament)
		
		# Animar oscilación lateral independiente en cada filamento
		var tw_fil = container.create_tween().set_loops()
		var offset_x = randf_range(-16.0, 16.0) # Mayor rango de deformación
		tw_fil.tween_property(filament, "position:x", offset_x, randf_range(0.35, 0.75)).set_trans(Tween.TRANS_SINE)
		tw_fil.tween_property(filament, "position:x", 0.0, randf_range(0.35, 0.75)).set_trans(Tween.TRANS_SINE)
	
	# 3. Línea de base (Suelo - Doble capa para dar grosor físico al impacto)
	var main_wall_glow = Line2D.new()
	main_wall_glow.points = PackedVector2Array([base_a, base_b])
	main_wall_glow.width = 18.0
	main_wall_glow.default_color = Color(0.0, 0.7, 0.9, 0.14)
	container.add_child(main_wall_glow)
	
	var main_wall = Line2D.new()
	main_wall.points = PackedVector2Array([base_a, base_b])
	main_wall.width = 5.0
	main_wall.default_color = Color(0.25, 0.85, 1.0, 0.55)
	container.add_child(main_wall)
	
	# 4. Línea de corona (Cima del muro - Doble capa brillante)
	var core_wall_glow = Line2D.new()
	core_wall_glow.points = PackedVector2Array([top_a, top_b])
	core_wall_glow.width = 14.0
	core_wall_glow.default_color = Color(0.3, 0.9, 1.0, 0.16)
	container.add_child(core_wall_glow)
	
	var core_wall = Line2D.new()
	core_wall.points = PackedVector2Array([top_a, top_b])
	core_wall.width = 4.5
	core_wall.default_color = Color(0.45, 0.95, 1.0, 0.8)
	container.add_child(core_wall)
	
	# 5. Partículas de viento (Nivel Suelo - Flujo masivo y espeso)
	var particles = CPUParticles2D.new()
	particles.amount = 140 # Aumentado de 100 a 140
	particles.lifetime = 0.55
	particles.preprocess = 0.3
	particles.randomness = 0.4
	
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(8.0, half_w) # Espesor en X aumentado de 2 a 8 para simular volumen
	
	particles.direction = Vector2.RIGHT
	particles.spread = 15.0
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = 200.0 # Velocidad aumentada
	particles.initial_velocity_max = 340.0
	
	particles.angle_min = -15.0
	particles.angle_max = 15.0
	particles.scale_amount_min = 1.5
	particles.scale_amount_max = 6.0 # Partículas más grandes y visibles
	
	var grad = Gradient.new()
	grad.set_color(0, Color(0.3, 0.95, 1.0, 0.7))
	grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	particles.color_ramp = grad
	
	container.add_child(particles)
	particles.emitting = true
	
	# 6. Partículas de viento (Nivel Cima - Flujo volumétrico ascendente)
	var particles_top = CPUParticles2D.new()
	particles_top.amount = 90 # Aumentado de 60 a 90
	particles_top.lifetime = 0.65
	particles_top.preprocess = 0.3
	particles_top.randomness = 0.4
	
	particles_top.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles_top.emission_rect_extents = Vector2(8.0, half_w) # Espesor en X aumentado
	particles_top.position = persp_up * height_3d
	
	particles_top.direction = (Vector2.RIGHT + persp_up * 0.25).normalized()
	particles_top.spread = 20.0
	particles_top.gravity = Vector2.ZERO
	particles_top.initial_velocity_min = 150.0
	particles_top.initial_velocity_max = 260.0
	particles_top.scale_amount_min = 1.0
	particles_top.scale_amount_max = 4.5 # Partículas de cima aumentadas
	
	var grad_top = Gradient.new()
	grad_top.set_color(0, Color(0.0, 0.8, 1.0, 0.6))
	grad_top.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	particles_top.color_ramp = grad_top
	
	container.add_child(particles_top)
	particles_top.emitting = true
	
	# 7. Animación de aparición (Pop-in)
	container.scale = Vector2.ZERO
	container.modulate.a = 0.0
	var tw = container.create_tween().set_parallel(true)
	tw.tween_property(container, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(container, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_SINE)

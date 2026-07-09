extends Node

# EntityManager.gd (v1.0 - Gestor de Entidades de Red Desacoplado)

var world = null

var remote_players = {}
var enemies = {}
var enemy_pool = []
var active_areas = {} # Cache de zonas de efecto (Humo, etc)
var loot_drops = {} # Cache de botines activos en el mapa
var active_laser_tracking = {} # Indicadores que siguen al jugador {enemy_id: {indicator, target_id}}
var zone_cleanup_timer = 0.0
const ZONE_CLEANUP_INTERVAL = 1.0

const ENEMY_SCENE = preload("res://scenes/entities/Enemy.tscn")
const SHIP_SCENE = preload("res://scenes/entities/Ship.tscn")
const LOOT_DROP_SCRIPT = preload("res://scripts/entities/LootDrop.gd")
const WIND_BARRIER_VFX_SCENE = preload("res://VFX/scenes/VFX_Shield_green_plane.tscn")
const SMOKE_CLOUD_SHADER = preload("res://resources/shaders/smoke_cloud.gdshader")
const VFX_SHIELD_GREEN_SCENE = preload("res://VFX/scenes/VFX_Shield_green.tscn")
const BEACON_3D_SCRIPT = preload("res://scripts/vfx/Beacon3D.gd")

# Texturas precargadas estáticamente
const TEX_CURACION_TRANSP = preload("res://assets/Efectos de Skills/Curacion(Transp).png")
const TEX_ESFERA_AZUL_1 = preload("res://assets/Esferas/EsferaAzul1.png")
const TEX_ESFERA_VERDE_1 = preload("res://assets/Esferas/EsferaVerde1.png")

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
	NetworkManager.loot_spawned.connect(_on_loot_spawned)
	NetworkManager.loot_despawned.connect(_on_loot_despawned)
	NetworkManager.boss_colors_start.connect(_on_boss_colors_start)
	NetworkManager.boss_colors_end.connect(_on_boss_colors_end)


func _process(delta):
	# 0. Filtro Proactivo de Zonas para prevenir Entidades Huérfanas (v3.0) - Optimizado (v3.1)
	zone_cleanup_timer += delta
	if zone_cleanup_timer >= ZONE_CLEANUP_INTERVAL:
		zone_cleanup_timer = 0.0
		if is_instance_valid(world) and is_instance_valid(world.local_player):
			var my_zone = _parse_zone_to_int(world.local_player.current_zone)
			
			# Limpiar Jugadores Remotos Huérfanos
			for pid in remote_players.keys():
				var rp = remote_players[pid]
				if is_instance_valid(rp):
					var rp_zone = rp.get_meta("zone") if rp.has_meta("zone") else -1
					if rp_zone == -1 or rp_zone != my_zone:
						remote_players.erase(pid)
						rp.queue_free()
						print("[EntityManager SINC] Piloto huérfano removido por cambio de zona: ", pid)
						
			# Limpiar Enemigos Huérfanos
			for eid in enemies.keys():
				var en = enemies[eid]
				if is_instance_valid(en):
					var en_zone = en.get_meta("zone") if en.has_meta("zone") else -1
					if en_zone == -1 or en_zone != my_zone:
						en.deactivate_for_pooling()
						enemies.erase(eid)
						print("[EntityManager SINC] Enemigo huérfano purgado por cambio de zona: ", eid)
						
			# Limpiar Botines Huérfanos
			for lid in loot_drops.keys():
				var drop = loot_drops[lid]
				if is_instance_valid(drop):
					var drop_zone = drop.get_meta("zone") if drop.has_meta("zone") else -1
					if drop_zone == -1 or drop_zone != my_zone:
						loot_drops.erase(lid)
						drop.queue_free()
						print("[EntityManager SINC] Botín huérfano purgado por cambio de zona: ", lid)


	# 1. Procesar físicas locales de succión de Vórtices y Lazos Curativos
	for id in active_areas.keys():
		var area = active_areas[id]
		if not is_instance_valid(area): continue

		# Sincronización visual 2.5D en perspectiva (proyectar posición lógica a pantalla cada frame)
		if area.has_meta("logical_position"):
			var log_pos = area.get_meta("logical_position")
			area.global_position = _get_projected_position(log_pos)

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
				var owner_vis = _get_entity_visual_position(owner_node)
				var target_vis = _get_entity_visual_position(target_node)
				
				# Centrar el contenedor en el emisor
				area.global_position = owner_vis
				
				# Dibujar el rayo de plasma verde usando coordenadas globales directas (gracias a set_as_top_level)
				var rayo_node = area.get_node_or_null("RayoVerde")
				if rayo_node:
					var start_pos = owner_vis + Vector2(0, -20)
					var end_pos = target_vis + Vector2(0, -20)
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
				var area_pos = area.get_meta("logical_position") if area.has_meta("logical_position") else area.global_position
				var dist_vec = area_pos - player.global_position
				var dist = dist_vec.length()
				var radius = area.get_meta("radius")
				
				if dist < radius:
					var pull_strength = area.get_meta("pull_force")
					var proximity = 1.0 + (1.0 - dist / radius)
					var force = dist_vec.normalized() * (pull_strength * proximity) * delta
					player.global_position += force
					if player.has_method("apply_shake"): player.apply_shake(0.3)

		if id.begins_with("cone_") or id.begins_with("blast_") or id.begins_with("circle_"):
			var enemy_id = area.get_meta("enemy_id")
			if enemies.has(enemy_id):
				var en = enemies[enemy_id]
				if is_instance_valid(en):
					var en_vis = _get_entity_visual_position(en)
					if id.begins_with("circle_"):
						var duration = area.get_meta("duration")
						var lock_time = area.get_meta("lock_time")
						var timer = area.get_meta("charge_timer") + delta
						area.set_meta("charge_timer", timer)
						
						var is_locked = area.get_meta("is_locked")
						if not is_locked and (duration - timer) <= lock_time:
							area.set_meta("is_locked", true)
							area.set_meta("locked_pos", en_vis)
						
						if area.get_meta("is_locked"):
							area.global_position = area.get_meta("locked_pos")
						else:
							area.global_position = en_vis
							
						# Actualizar la escala del círculo interno de carga
						var charge_node = area.get_node_or_null("ChargeVisual")
						if charge_node:
							var inner_r = area.get_meta("inner_range")
							var max_r = area.get_meta("range")
							var progress = clamp(timer / duration, 0.0, 1.0)
							var current_r = lerp(inner_r, max_r, progress)
							charge_node.polygon = _get_ring_points(inner_r, current_r)
					else:
						area.global_position = en_vis
						area.global_rotation = en.global_rotation - PI / 2
			else:
				active_areas.erase(id)
				area.queue_free()
			continue

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
			
			var en_vis = _get_entity_visual_position(en)
			if is_instance_valid(target_node) and not data.get("is_fixed", false):
				var target_vis = _get_entity_visual_position(target_node)
				var target_angle = (target_vis - en_vis).angle()
				indicator.global_position = en_vis
				indicator.global_rotation = lerp_angle(indicator.global_rotation, target_angle, 4.0 * delta)
				indicator.points = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT * length])
			elif data.get("is_fixed", false):
				indicator.global_position = en_vis
				indicator.global_rotation = data.get("fixed_angle", 0.0)
				indicator.points = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT * length])
			else:
				indicator.global_position = en_vis
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
		if data.has("hp") and data.hp != null: world.local_player.current_hp = float(data.hp)
		if data.has("shield") and data.shield != null: world.local_player.current_shield = float(data.shield)
		elif data.has("sh") and data.sh != null: world.local_player.current_shield = float(data.sh)
		
		world.local_player.update_stats(data)
		
		if data.has("pvpEnabled") and is_instance_valid(world.ui_hud):
			world.ui_hud.set_pvp_status(data.pvpEnabled)
		return

	if enemies.has(id): return 

	var is_new = false
	if not remote_players.has(id):
		var rp = SHIP_SCENE.instantiate()
		rp.entity_id = id
		rp.set_meta("socket_id", id) # Guardar ID de socket de red real para comercio
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
			if p.has_method("_update_3d_root_sync"):
				p._update_3d_root_sync()
		p.set_meta("zone", remote_zone)
		p.update_stats(data)

func _get_enemy_from_pool() -> Node:
	for en in enemy_pool:
		if is_instance_valid(en) and en.get_meta("is_pooled", false):
			en.activate_from_pool()
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
			
			var en_vis = _get_entity_visual_position(en)
			indicator.global_position = en_vis
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
			var en_vis = _get_entity_visual_position(en)
			indicator.global_position = en_vis
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
		
		elif action == "cone_charging":
			var range_val = float(data.get("range", 400.0))
			var cone_angle = float(data.get("coneAngle", 60.0))
			
			# Contenedor del cono
			var cone_node = Node2D.new()
			cone_node.name = "ConeIndicator_" + enemy_id
			cone_node.set_meta("is_cone_indicator", true)
			cone_node.set_meta("enemy_id", enemy_id)
			cone_node.rotation = -PI / 2 # Alinear con el frente local de la nave
			cone_node.set_as_top_level(true)
			
			if is_instance_valid(world) and is_instance_valid(world.entities_node):
				world.entities_node.add_child(cone_node)
			else:
				en.add_child(cone_node)
			
			# Polígono de fondo (Área de Peligro)
			var poly_bg = Polygon2D.new()
			poly_bg.polygon = _get_cone_points(range_val, cone_angle)
			poly_bg.color = Color(1.0, 0.0, 0.0, 0.15)
			cone_node.add_child(poly_bg)
			
			# Polígono de carga (Progreso)
			var poly_charge = Polygon2D.new()
			poly_charge.polygon = _get_cone_points(1.0, cone_angle)
			poly_charge.color = Color(1.0, 0.1, 0.1, 0.4)
			cone_node.add_child(poly_charge)
			
			active_areas["cone_" + enemy_id] = cone_node
			
			# Tween para expandir el radio de la carga
			var tw = cone_node.create_tween()
			tw.tween_method(
				func(r: float):
					if is_instance_valid(poly_charge):
						poly_charge.polygon = _get_cone_points(r, cone_angle),
				1.0,
				range_val,
				duration
			)
			
		elif action == "cone_fire":
			var indicator = en.get_node_or_null("ConeIndicator_" + enemy_id)
			if is_instance_valid(indicator):
				indicator.queue_free()
				
			var root_indicator = world.entities_node.get_node_or_null("ConeIndicator_" + enemy_id) if is_instance_valid(world) and is_instance_valid(world.entities_node) else null
			if is_instance_valid(root_indicator):
				root_indicator.queue_free()
				
			var range_val = float(data.get("range", 400.0))
			var cone_angle = float(data.get("coneAngle", 60.0))
			
			var blast = Node2D.new()
			blast.name = "ConeBlast_" + enemy_id
			blast.set_meta("enemy_id", enemy_id)
			blast.rotation = -PI / 2
			blast.set_as_top_level(true)
			
			if is_instance_valid(world) and is_instance_valid(world.entities_node):
				world.entities_node.add_child(blast)
			else:
				en.add_child(blast)
			
			var poly_blast = Polygon2D.new()
			poly_blast.polygon = _get_cone_points(range_val, cone_angle)
			poly_blast.color = Color(1.0, 0.4, 0.0, 0.8) # Naranja brillante
			blast.add_child(poly_blast)
			
			active_areas["blast_" + enemy_id] = blast
			
			# Desvanecer la explosión
			var tw = blast.create_tween()
			tw.tween_property(poly_blast, "color:a", 0.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw.finished.connect(func():
				active_areas.erase("blast_" + enemy_id)
				blast.queue_free()
			)
		
		elif action == "circle_charging":
			var range_val = float(data.get("range", 300.0))
			var charge_dur = float(data.get("duration", 2000.0)) / 1000.0
			var lock_dur = float(data.get("lockTimeMs", 800.0)) / 1000.0
			
			var r_inner = 64.0
			if is_instance_valid(en) and "_collision_shape" in en and is_instance_valid(en._collision_shape) and en._collision_shape.shape is CircleShape2D:
				r_inner = en._collision_shape.shape.radius
				
			var circle_node = Node2D.new()
			circle_node.name = "CircleIndicator_" + enemy_id
			circle_node.z_index = -2 # Dibujar debajo de los assets para no pintarlos de rojo
			circle_node.set_meta("is_circle_indicator", true)
			circle_node.set_meta("enemy_id", enemy_id)
			circle_node.set_meta("range", range_val)
			circle_node.set_meta("inner_range", r_inner)
			circle_node.set_meta("duration", charge_dur)
			circle_node.set_meta("lock_time", lock_dur)
			circle_node.set_meta("charge_timer", 0.0)
			circle_node.set_meta("is_locked", false)
			circle_node.set_meta("locked_pos", Vector2(data.get("x", en.global_position.x), data.get("y", en.global_position.y)))
			circle_node.set_as_top_level(true)
			
			if is_instance_valid(world) and is_instance_valid(world.entities_node):
				world.entities_node.add_child(circle_node)
			else:
				en.add_child(circle_node)
				
			# Círculo de fondo (Área de Peligro - Anillo)
			var poly_bg = Polygon2D.new()
			poly_bg.polygon = _get_ring_points(r_inner, range_val)
			poly_bg.color = Color(1.0, 0.0, 0.0, 0.12)
			circle_node.add_child(poly_bg)
			
			# Borde exterior del círculo
			var border_outer = Line2D.new()
			border_outer.points = _get_circle_outline_points(range_val)
			border_outer.width = 2.0
			border_outer.default_color = Color(1.0, 0.0, 0.0, 0.4)
			circle_node.add_child(border_outer)
			
			# Borde interior del círculo
			var border_inner = Line2D.new()
			border_inner.points = _get_circle_outline_points(r_inner)
			border_inner.width = 2.0
			border_inner.default_color = Color(1.0, 0.0, 0.0, 0.4)
			circle_node.add_child(border_inner)
			
			# Círculo de carga (Progreso - Anillo)
			var poly_charge = Polygon2D.new()
			poly_charge.name = "ChargeVisual"
			poly_charge.polygon = _get_ring_points(r_inner, r_inner + 1.0)
			poly_charge.color = Color(1.0, 0.1, 0.1, 0.35)
			circle_node.add_child(poly_charge)
			
			active_areas["circle_" + enemy_id] = circle_node
			
		elif action == "circle_fire":
			var indicator = en.get_node_or_null("CircleIndicator_" + enemy_id)
			if is_instance_valid(indicator):
				indicator.queue_free()
				
			var root_indicator = world.entities_node.get_node_or_null("CircleIndicator_" + enemy_id) if is_instance_valid(world) and is_instance_valid(world.entities_node) else null
			if is_instance_valid(root_indicator):
				root_indicator.queue_free()
				
			var range_val = float(data.get("range", 300.0))
			var locked_x = float(data.get("x", en.global_position.x))
			var locked_y = float(data.get("y", en.global_position.y))
			
			var r_inner = 64.0
			if is_instance_valid(en) and "_collision_shape" in en and is_instance_valid(en._collision_shape) and en._collision_shape.shape is CircleShape2D:
				r_inner = en._collision_shape.shape.radius
				
			var blast = Node2D.new()
			blast.name = "CircleBlast_" + enemy_id
			blast.z_index = -2 # Dibujar debajo de los assets
			blast.set_meta("enemy_id", enemy_id)
			blast.set_as_top_level(true)
			blast.global_position = Vector2(locked_x, locked_y)
			
			if is_instance_valid(world) and is_instance_valid(world.entities_node):
				world.entities_node.add_child(blast)
			else:
				en.add_child(blast)
				
			var poly_blast = Polygon2D.new()
			poly_blast.polygon = _get_ring_points(r_inner, range_val)
			poly_blast.color = Color(1.0, 0.3, 0.0, 0.75)
			blast.add_child(poly_blast)
			
			# Borde de la explosión exterior
			var blast_border_outer = Line2D.new()
			blast_border_outer.points = _get_circle_outline_points(range_val)
			blast_border_outer.width = 4.0
			blast_border_outer.default_color = Color(1.0, 0.5, 0.0, 0.9)
			blast.add_child(blast_border_outer)
			
			# Borde de la explosión interior
			var blast_border_inner = Line2D.new()
			blast_border_inner.points = _get_circle_outline_points(r_inner)
			blast_border_inner.width = 4.0
			blast_border_inner.default_color = Color(1.0, 0.5, 0.0, 0.9)
			blast.add_child(blast_border_inner)
			
			active_areas["blast_" + enemy_id] = blast
			
			var tw = blast.create_tween().set_parallel(true)
			tw.tween_property(poly_blast, "color:a", 0.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw.tween_property(blast_border_outer, "default_color:a", 0.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw.tween_property(blast_border_inner, "default_color:a", 0.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw.chain().finished.connect(func():
				active_areas.erase("blast_" + enemy_id)
				blast.queue_free()
			)

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
					old_en.deactivate_for_pooling()
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
			if eref.has_method("_update_3d_root_sync"):
				eref._update_3d_root_sync()
		var enemy_zone = _parse_zone_to_int(data.get("zone", -1))
		if enemy_zone != -1:
			eref.set_meta("zone", enemy_zone)
		eref.update_stats(data); eref.visible = true; eref.show()
	else:
		enemies.erase(id)

func _on_player_disconnected(id):
	var sid = str(id)
	if remote_players.has(sid):
		# v301.6: Limpiar resto de naufragio del piloto desconectado
		if remote_players[sid].has_method("_clear_wreckage_marker"):
			remote_players[sid]._clear_wreckage_marker()
		remote_players[sid].queue_free()
		remote_players.erase(sid)

func clear_remote_players():
	for id in remote_players:
		if is_instance_valid(remote_players[id]): remote_players[id].queue_free()
	remote_players.clear()
	for id in enemies:
		if is_instance_valid(enemies[id]): 
			enemies[id].deactivate_for_pooling()
	enemies.clear()
	for en in enemy_pool:
		if is_instance_valid(en):
			en.deactivate_for_pooling()
	for id in loot_drops.keys():
		var drop = loot_drops[id]
		if is_instance_valid(drop): drop.queue_free()
	loot_drops.clear()
	
	# v301.6: Limpiar todos los restos de naufragios del sector
	if is_instance_valid(world) and is_instance_valid(world.get("entities_node")):
		for child in world.entities_node.get_children():
			if child.name.begins_with("Wreckage_"):
				child.queue_free()
				
	print("[EntityManager] Universo y restos limpiados correctamente.")

func _on_enemy_dead(data: Dictionary):
	var id = str(data.get("id", ""))
	if id == "": return
	var enemy = enemies.get(id)
	if is_instance_valid(enemy):
		var indicator = enemy.get_node_or_null("ConeIndicator_" + id)
		if is_instance_valid(indicator):
			indicator.queue_free()
		enemy.die()
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
		
		var start_pos = _get_entity_visual_position(attacker_node)
		var end_pos = _get_entity_visual_position(victim_node)
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
		if data.get("skillName", "") == "REGENERACIÓN ALFA":
			_spawn_alpha_regen_vfx(id, Vector2(data.x, data.y), data.radius, data)
		else:
			_spawn_heal_zone_vfx(id, Vector2(data.x, data.y), data.radius, data)
	elif type == "RESURRECCIÓN":
		_spawn_resurreccion_vfx(id, Vector2(data.x, data.y), data.radius, data)
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
	var proj_pos = _get_projected_position(pos)
	container.global_position = proj_pos
	container.set_meta("logical_position", pos)
	container.set_meta("type", "heal_zone")
	
	var owner_id = str(data.get("ownerId", ""))
	var start_pos = proj_pos
	var emisor_node = null
	
	if is_instance_valid(world) and is_instance_valid(world.local_player) and world.local_player.entity_id == owner_id:
		emisor_node = world.local_player
	elif remote_players.has(owner_id):
		emisor_node = remote_players[owner_id]
		
	if is_instance_valid(emisor_node):
		start_pos = _get_entity_visual_position(emisor_node)

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
	var item_tex = TEX_CURACION_TRANSP
	if not item_tex:
		item_tex = TEX_ESFERA_VERDE_1
	
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
	if start_pos.distance_to(proj_pos) > 50.0:
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
		
		var travel_time = clamp(start_pos.distance_to(proj_pos) / 950.0, 0.2, 0.5)
		var tw = proj.create_tween().set_parallel(true)
		tw.tween_property(proj, "global_position", proj_pos, travel_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		
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

func _spawn_resurreccion_vfx(id, pos, _radius, _data):
	if active_areas.has(id): return
	var current_map = get_tree().get_first_node_in_group("map")
	if not is_instance_valid(current_map) or not current_map.get("sub_viewport"):
		return
	var sub_vp = current_map.sub_viewport
	var s_factor = current_map.scale_factor if "scale_factor" in current_map else 0.02
	var correction_z = current_map.correction_z if "correction_z" in current_map else 1.41421356
	var spark_mat = StandardMaterial3D.new()
	spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	spark_mat.albedo_texture = load("res://VFX/textures/T_VFX_sparks112.jpg")
	var mesh = QuadMesh.new()
	mesh.size = Vector2(0.6, 0.6)
	mesh.material = spark_mat
	var proc_mat = ParticleProcessMaterial.new()
	proc_mat.gravity = Vector3(0, 3.0, 0)
	proc_mat.direction = Vector3.UP
	proc_mat.spread = 45.0
	proc_mat.initial_velocity_min = 2.0
	proc_mat.initial_velocity_max = 6.0
	var grad = Gradient.new()
	grad.set_color(0, Color(0.9, 0.2, 0.9, 1.0))
	grad.add_point(0.3, Color(0.7, 0.1, 0.9, 0.8))
	grad.add_point(0.6, Color(0.4, 0.0, 0.7, 0.4))
	grad.set_color(1, Color(0.2, 0.0, 0.3, 0.0))
	proc_mat.color_ramp = GradientTexture1D.new()
	proc_mat.color_ramp.gradient = grad
	var parts = GPUParticles3D.new()
	parts.name = id
	parts.amount = 40
	parts.lifetime = 0.8
	parts.one_shot = false
	parts.explosiveness = 0.5
	parts.position = Vector3(pos.x * s_factor, 0.0, pos.y * s_factor * correction_z)
	parts.process_material = proc_mat
	parts.draw_pass_1 = mesh
	sub_vp.add_child(parts)
	parts.emitting = true
	var tw = create_tween()
	tw.tween_interval(1.5)
	tw.tween_callback(func():
		if is_instance_valid(parts):
			parts.emitting = false
			parts.queue_free()
	)
	active_areas[id] = parts

func _spawn_vortex_vfx(id, pos, radius, data):
	if active_areas.has(id): return
	
	var container = Node2D.new()
	container.name = id
	container.z_index = 5
	if is_instance_valid(world) and is_instance_valid(world.entities_node):
		world.entities_node.add_child(container)
	
	var proj_pos = _get_projected_position(pos)
	container.global_position = proj_pos
	active_areas[id] = container
	
	container.set_meta("radius", radius)
	container.set_meta("pull_force", data.get("pullForce", 8.0)) 
	container.set_meta("type", "vortex")
	container.set_meta("time", 0.0) 
	container.set_meta("logical_position", pos)
	
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
	
	var proj_pos = _get_projected_position(pos)
	container.global_position = proj_pos
	container.set_meta("logical_position", pos)
	container.set_meta("type", "ice")
	
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
	
	particles.position = Vector2.ZERO
	container.add_child(particles)
	
	var glow = Sprite2D.new()
	var glow_tex = TEX_ESFERA_AZUL_1
	if glow_tex:
		glow.texture = glow_tex
		var glow_mat = CanvasItemMaterial.new()
		glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow.material = glow_mat
		glow.modulate = Color(0.5, 0.8, 1.0, 0.35)
		glow.scale = Vector2(0.15, 0.15)
		glow.z_index = 4
		glow.position = Vector2.ZERO
		container.add_child(glow)
		
		var tw = create_tween()
		tw.tween_property(glow, "modulate:a", 0.35, 0.3).set_trans(Tween.TRANS_SINE)

func _on_remove_area(data: Dictionary):
	var id = data.get("id", "")
	if active_areas.has(id):
		var area = active_areas[id]
		active_areas.erase(id)
		if is_instance_valid(area):
			if area is GPUParticles3D:
				area.emitting = false
				area.queue_free()
			elif area is Node3D:
				var tw = area.create_tween().set_parallel(true)
				tw.tween_property(area, "scale", Vector3(0.001, 0.001, 0.001), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
				tw.tween_property(area, "visible", false, 0.14)
				tw.chain().tween_callback(area.queue_free)
			else:
				var tw = area.create_tween().set_parallel(true)
				tw.tween_property(area, "scale", Vector2(0.001, 0.001), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
				tw.tween_property(area, "modulate:a", 0.0, 0.15)
				tw.chain().tween_callback(area.queue_free)

func _spawn_alpha_regen_vfx(id, pos, _radius, _data):
	if active_areas.has(id): return
	var current_map = get_tree().get_first_node_in_group("map")
	if not is_instance_valid(current_map) or not current_map.get("sub_viewport"):
		return
	var sub_vp = current_map.sub_viewport
	var s_factor = current_map.scale_factor if "scale_factor" in current_map else 0.02
	var correction_z = current_map.correction_z if "correction_z" in current_map else 1.41421356
	
	var vfx = VFX_SHIELD_GREEN_SCENE.instantiate()
	vfx.name = id
	vfx.position = Vector3(pos.x * s_factor, 0.0, pos.y * s_factor * correction_z)
	
	# Mitad de tamaño (0.325 es la mitad de la escala 0.65 que se usa en el jugador)
	vfx.scale = Vector3(0.325, 0.325, 0.325)
	
	sub_vp.add_child(vfx)
	active_areas[id] = vfx
	
	var anim = vfx.get_node_or_null("AnimationPlayer")
	if anim and anim.has_animation("start_animation"):
		anim.play("start_animation")

func _spawn_heal_beacon_vfx(id, pos, _radius, _data = {}):
	if active_areas.has(id): return
	var current_map = get_tree().get_first_node_in_group("map")
	if not is_instance_valid(current_map) or not current_map.get("sub_viewport"):
		return
	var s_factor = current_map.scale_factor if "scale_factor" in current_map else 0.02
	var correction_z = current_map.correction_z if "correction_z" in current_map else 1.41421356
	var sub_vp = current_map.sub_viewport
	var beacon = BEACON_3D_SCRIPT.new()
	beacon.name = id
	beacon._scale_factor = s_factor
	beacon._heal_radius_2d = float(_data.get("radius", 200.0))
	beacon.position = Vector3(pos.x * s_factor, 0.0, pos.y * s_factor * correction_z)
	sub_vp.add_child(beacon)
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
	wrapper.z_index = -1 
	if is_instance_valid(world) and is_instance_valid(world.entities_node):
		world.entities_node.add_child(wrapper)
		
	var proj_pos = _get_projected_position(pos)
	wrapper.global_position = proj_pos
	active_areas[id] = wrapper
	wrapper.set_meta("logical_position", pos)
	wrapper.set_meta("type", "smoke")
	
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
	mat.shader = SMOKE_CLOUD_SHADER
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
	var skill_name = data.get("skillName", "")
	
	if skill_name == "ESFERA DE TERROR":
		var emisor_node = null
		if is_instance_valid(world) and is_instance_valid(world.local_player) and world.local_player.entity_id == sender_id:
			emisor_node = world.local_player
		elif remote_players.has(sender_id):
			emisor_node = remote_players[sender_id]
		
		if is_instance_valid(emisor_node) and is_instance_valid(world) and is_instance_valid(world.combat_system):
			var s_data = GameConstants.SKILLS_DATA.get("ESFERA DE TERROR", {})
			var speed_val = float(s_data.get("speed", 800.0))
			var range_val = float(s_data.get("range", 600.0))
			var dur_val = float(s_data.get("duration", 3000.0))
			var power_val = float(data.get("powerValue", 500.0))
			
			var proj_data = {
				"id": sender_id,
				"senderId": sender_id,
				"x": emisor_node.global_position.x,
				"y": emisor_node.global_position.y,
				"angle": float(data.get("angle", emisor_node.rotation)),
				"bulletType": "fear",
				"type": "fear",
				"damage": power_val,
				"damageBoost": power_val,
				"speed": speed_val,
				"range": range_val,
				"duration": dur_val,
				"owner_type": "player" if sender_id == world.local_player.entity_id else "remote"
			}
			world.combat_system._spawn_projectile(proj_data, proj_data.owner_type)
		return
		
	var target_id = str(data.get("targetId", sender_id))
	
	var target_node = null
	
	if is_instance_valid(world) and is_instance_valid(world.local_player) and world.local_player.entity_id == target_id:
		if sender_id == target_id and skill_name != "REGENERACIÓN ALFA" and skill_name != "BALIZA DE CURACION": return
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
			enemies[id].deactivate_for_pooling()
	enemies.clear()
	
	for en in enemy_pool:
		if is_instance_valid(en):
			en.deactivate_for_pooling()
	
	for id in remote_players:
		if is_instance_valid(remote_players[id]): remote_players[id].queue_free()
	remote_players.clear()
	
	# v371.2: Limpiar restos de naufragios (wreckage markers) antiguos del sector al cambiar de zona
	if is_instance_valid(world) and is_instance_valid(world.get("entities_node")):
		for child in world.entities_node.get_children():
			if is_instance_valid(child) and child.name.begins_with("Wreckage_"):
				child.queue_free()
	
	if is_instance_valid(world) and is_instance_valid(world.combat_system) and world.combat_system.has_method("clear_all_bullets"):
		world.combat_system.clear_all_bullets()
		
	var is_dungeon = str(_zoneId).begins_with("dungeon")
	var is_extraction = str(_zoneId).begins_with("extract_") or str(_zoneId) == "10" or str(_zoneId) == "11"
	
	# Determinar si es un mapa de Altar Defense (dinámico desde el config del servidor)
	var zone_int_check = int(_zoneId) if not is_dungeon and not is_extraction else 0
	var is_altar_defense = false
	var full_cfg = GameConstants.get("FULL_CONFIG")
	if full_cfg and full_cfg.has("gameModes") and full_cfg.gameModes.has("altar_defense"):
		var ad_maps = full_cfg.gameModes.altar_defense.get("maps", [])
		for m in ad_maps:
			if int(m) == zone_int_check:
				is_altar_defense = true
				break
	
	var new_world_size = 10000.0
	if is_extraction or is_altar_defense:
		# Leer ancho del config si está definido
		if is_altar_defense and full_cfg and full_cfg.has("gameModes") and full_cfg.gameModes.has("altar_defense"):
			var ad_w = float(full_cfg.gameModes.altar_defense.get("width", 10000))
			new_world_size = ad_w if ad_w > 0 else 10000.0
		elif is_extraction and full_cfg and full_cfg.has("gameModes") and full_cfg.gameModes.has("extraction"):
			var ex_w = float(full_cfg.gameModes.extraction.get("width", 10000))
			new_world_size = ex_w if ex_w > 0 else 10000.0
		else:
			new_world_size = 10000.0
	elif is_dungeon or int(_zoneId) == 1:
		new_world_size = 2000.0
	else:
		new_world_size = 4000.0
		var z_id_str = str(_zoneId)
		if z_id_str in GameConstants.MAPS_CONFIG:
			var z_cfg = GameConstants.MAPS_CONFIG[z_id_str]
			if z_cfg.has("width") and float(z_cfg.width) > 0:
				new_world_size = float(z_cfg.width)
	
	var zone_int = _parse_zone_to_int(_zoneId)
	if is_instance_valid(world) and is_instance_valid(world.local_player):
		world.local_player.set("current_zone", zone_int)
		print("[EntityManager ZONE] Sincronía Preventiva: Zona actualizada a ", zone_int)

	if is_instance_valid(world) and is_instance_valid(world.local_player):
		var lp = world.local_player
		if spawn_pos != null:
			lp.global_position = spawn_pos
		else:
			lp.global_position = Vector2(new_world_size / 2, new_world_size / 2)
		lp.target_position = lp.global_position
		lp.is_moving = false
		
		# v306.9: Resucitar y restablecer procesos de física/movimiento al cambiar de zona si estaba muerto
		if lp.get("is_dead") == true or lp.current_hp <= 0:
			lp.is_dead = false
			lp.current_hp = lp.max_hp
			lp.current_shield = lp.max_shield
			lp.visible = true
			lp.modulate = Color(1, 1, 1, 1)
			lp.show()
			lp.set_physics_process(true)
			lp.set_process(true)
			if lp.has_method("_update_tags"): lp._update_tags()
			if lp.has_method("_clear_wreckage_marker"): lp._clear_wreckage_marker()
			print("[EntityManager ZONE] Piloto local resucitado automáticamente al ingresar a la zona.")
	
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
	container.z_index = 2 # Nivel de naves para que se vea sobre el mapa con volumen
	if is_instance_valid(world) and is_instance_valid(world.entities_node):
		world.entities_node.add_child(container)
	active_areas[id] = container
	
	container.global_position = _get_projected_position(pos)
	container.set_meta("logical_position", pos)
	container.set_meta("type", "wind_barrier")
	
	# Rotar el contenedor en base al ángulo de lanzamiento del viento
	var angle = float(_data.get("angle", 0.0))
	container.rotation = angle
	
	# Crear el SubViewport 3D para renderizar el VFX 3D
	var vp_size = 384
	var vp = SubViewport.new()
	vp.size = Vector2i(vp_size, vp_size)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(vp)
	
	# Escena 3D interna
	var node3d = Node3D.new()
	vp.add_child(node3d)
	
	# Cámara de Perspectiva con el ángulo 2.5D exacto de la nave
	var cam = Camera3D.new()
	cam.position = Vector3(0, 10, 10)
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 60.0
	node3d.add_child(cam)
	cam.look_at(Vector3.ZERO)
	
	# Luz ambiental blanca para que se vea idéntico al editor
	var env = WorldEnvironment.new()
	var world_env = Environment.new()
	world_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_env.ambient_light_color = Color.WHITE
	world_env.ambient_light_energy = 1.2
	env.environment = world_env
	node3d.add_child(env)
	
	# Instanciar el VFX 3D de la media esfera
	var vfx_scene = WIND_BARRIER_VFX_SCENE
	if vfx_scene:
		var vfx = vfx_scene.instantiate()
		node3d.add_child(vfx)
		
		# Escala 3D ideal para el tamaño del viewport
		vfx.scale = Vector3(3.0, 3.0, 3.0)
		# Rotar 180 grados en Y para que la parte curva mire hacia afuera de la nave
		vfx.rotation_degrees = Vector3(0, 180, 0)
		
		# Iniciar la animación de entrada
		var anim = vfx.get_node_or_null("AnimationPlayer")
		if anim and anim.has_animation("start_animation"):
			anim.play("start_animation")
			
	# Sprite 2D que expone la textura del SubViewport al mundo 2.5D
	var sprite = Sprite2D.new()
	sprite.texture = vp.get_texture()
	
	# Rotar el sprite 90 grados (PI/2) localmente para alinear el eje vertical
	sprite.rotation = PI / 2.0
	sprite.scale = Vector2(1.0, 1.0)
	
	var canvas_mat = CanvasItemMaterial.new()
	canvas_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
	sprite.material = canvas_mat
	container.add_child(sprite)
	
	# Animación de entrada con Tween en 2D (Pop-in fluido)
	container.scale = Vector2.ZERO
	container.modulate.a = 0.0
	var tw = container.create_tween().set_parallel(true)
	tw.tween_property(container, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(container, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_SINE)

func _get_projected_position(pos: Vector2) -> Vector2:
	var current_map = get_tree().get_first_node_in_group("map")
	if is_instance_valid(current_map):
		var use_perspective = not current_map.get("use_orthogonal")
		if use_perspective:
			var cam3d = current_map.get("camera_3d")
			var sub_vp = current_map.get("sub_viewport")
			if is_instance_valid(cam3d) and is_instance_valid(sub_vp) and sub_vp.size.x > 0 and sub_vp.size.y > 0:
				var s_factor = current_map.scale_factor if "scale_factor" in current_map else 0.02
				var correction_z = current_map.correction_z if "correction_z" in current_map else 1.41421356
				var pos_3d = Vector3(pos.x * s_factor, 0.0, pos.y * s_factor * correction_z)
				if not cam3d.is_position_behind(pos_3d):
					var sv_pixel = cam3d.unproject_position(pos_3d)
					var container = current_map.get("viewport_container")
					if is_instance_valid(container) and container.size.x > 0:
						sv_pixel *= Vector2(container.size) / Vector2(sub_vp.size)
						sv_pixel += container.global_position
					else:
						var main_size = Vector2(get_viewport().get_visible_rect().size)
						sv_pixel *= main_size / Vector2(sub_vp.size)
					return get_viewport().get_canvas_transform().affine_inverse() * sv_pixel
	return pos

func _get_entity_visual_position(entity: Node) -> Vector2:
	if is_instance_valid(entity):
		if entity.get_meta("is_single_world", false) and is_instance_valid(entity.get("world_root_3d")):
			var current_map = get_tree().get_first_node_in_group("map")
			if is_instance_valid(current_map) and is_instance_valid(current_map.camera_3d):
				var cam3d = current_map.camera_3d
				var sub_vp = current_map.sub_viewport
				var world_root_3d = entity.world_root_3d
				if not cam3d.is_position_behind(world_root_3d.global_position):
					var sv_pixel = cam3d.unproject_position(world_root_3d.global_position)
					if is_instance_valid(sub_vp) and sub_vp.size.x > 0 and sub_vp.size.y > 0:
						var main_size = Vector2(get_viewport().get_visible_rect().size)
						sv_pixel *= main_size / Vector2(sub_vp.size)
					var world_2d = get_viewport().get_canvas_transform().affine_inverse() * sv_pixel
					return world_2d
		return entity.global_position
	return Vector2.ZERO

func _on_loot_spawned(data: Dictionary):
	if typeof(data) != TYPE_DICTIONARY or not data.has("id"): return
	var id = str(data.id)
	
	if loot_drops.has(id): return
	
	# Filtro de Zona
	if is_instance_valid(world) and is_instance_valid(world.local_player):
		var loot_zone = _parse_zone_to_int(data.get("zone", -1))
		var my_zone = _parse_zone_to_int(world.local_player.current_zone)
		if loot_zone != -1 and loot_zone != my_zone:
			return
			
	var loot_script = LOOT_DROP_SCRIPT
	if loot_script:
		var drop = Area2D.new()
		drop.set_script(loot_script)
		drop.name = id
		drop.loot_id = id
		# Offset aleatorio para que el botín no quede encima del wreckage del enemigo
		var loot_angle = randf() * TAU
		var loot_offset = Vector2(cos(loot_angle), sin(loot_angle)) * randf_range(80.0, 130.0)
		drop.global_position = Vector2(data.x, data.y) + loot_offset
		drop.set_meta("zone", _parse_zone_to_int(data.get("zone", -1)))
		
		if is_instance_valid(world) and is_instance_valid(world.entities_node):
			world.entities_node.add_child(drop)
			loot_drops[id] = drop
			print("[EntityManager] Botín físico instanciado: ", id)

func _on_loot_despawned(data: Dictionary):
	if typeof(data) != TYPE_DICTIONARY or not data.has("id"): return
	var id = str(data.id)
	
	if loot_drops.has(id):
		var drop = loot_drops[id]
		loot_drops.erase(id)
		if is_instance_valid(drop):
			if drop.has_method("fade_out_and_free"):
				drop.fade_out_and_free()
			else:
				drop.queue_free()
			print("[EntityManager] Botín físico removido: ", id)

func _get_cone_points(radius: float, angle_degrees: float) -> PackedVector2Array:
	var points = PackedVector2Array()
	points.append(Vector2.ZERO)
	var angle_rad = deg_to_rad(angle_degrees)
	var half_angle = angle_rad / 2.0
	var steps = 24
	for i in range(steps + 1):
		var ang = -half_angle + (float(i) / steps) * angle_rad
		points.append(Vector2(cos(ang), sin(ang)) * radius)
	points.append(Vector2.ZERO)
	return points

func _get_ring_points(inner_radius: float, outer_radius: float) -> PackedVector2Array:
	var points = PackedVector2Array()
	var steps = 32
	# Bucle exterior (horario)
	for i in range(steps + 1):
		var ang = (float(i) / steps) * TAU
		points.append(Vector2(cos(ang), sin(ang)) * outer_radius)
	# Bucle interior (antihorario)
	for i in range(steps + 1):
		var ang = (1.0 - float(i) / steps) * TAU
		points.append(Vector2(cos(ang), sin(ang)) * inner_radius)
	return points

func _get_circle_outline_points(radius: float) -> PackedVector2Array:
	var points = PackedVector2Array()
	var steps = 32
	for i in range(steps + 1):
		var ang = (float(i) / steps) * TAU
		points.append(Vector2(cos(ang), sin(ang)) * radius)
	return points

func _on_boss_colors_start(data: Dictionary):
	if typeof(data) != TYPE_DICTIONARY: return
	var boss_id = str(data.get("bossId", ""))
	var boss_color = str(data.get("bossColor", ""))
	var player_colors = data.get("playerColors", {})
	
	# Aplicar aura de color al boss
	var boss_node = enemies.get(boss_id)
	if is_instance_valid(boss_node):
		boss_node.set_meta("boss_color", boss_color)
		if boss_node.has_method("apply_color_aura"):
			boss_node.apply_color_aura(boss_color)
		
	# Aplicar aura de color a cada jugador correspondiente
	for socket_id in player_colors.keys():
		var p_color = player_colors[socket_id]
		# Buscar si es el jugador local
		if is_instance_valid(world) and is_instance_valid(world.local_player) and world.local_player.entity_id == socket_id:
			world.local_player.set_meta("my_color", p_color)
			if world.local_player.has_method("apply_color_aura"):
				world.local_player.apply_color_aura(p_color)
		# O si es un jugador remoto
		elif remote_players.has(socket_id):
			var rp = remote_players[socket_id]
			if is_instance_valid(rp):
				rp.set_meta("my_color", p_color)
				if rp.has_method("apply_color_aura"):
					rp.apply_color_aura(p_color)

func _on_boss_colors_end(data: Dictionary):
	if typeof(data) != TYPE_DICTIONARY: return
	var boss_id = str(data.get("bossId", ""))
	
	# Remover aura del boss
	var boss_node = enemies.get(boss_id)
	if is_instance_valid(boss_node):
		if boss_node.has_meta("boss_color"):
			boss_node.remove_meta("boss_color")
		if boss_node.has_method("remove_color_aura"):
			boss_node.remove_color_aura()
		
	# Remover aura del jugador local
	if is_instance_valid(world) and is_instance_valid(world.local_player):
		if world.local_player.has_meta("my_color"):
			world.local_player.remove_meta("my_color")
		if world.local_player.has_method("remove_color_aura"):
			world.local_player.remove_color_aura()
			
	# Remover aura de todos los jugadores remotos
	for rp in remote_players.values():
		if is_instance_valid(rp):
			if rp.has_meta("my_color"):
				rp.remove_meta("my_color")
			if rp.has_method("remove_color_aura"):
				rp.remove_color_aura()

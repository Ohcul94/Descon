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
	NetworkManager.hook_pulled.connect(_on_hook_pulled)

func _process(delta):
	# 1. Procesar físicas locales de succión de Vórtices
	for id in active_areas.keys():
		var area = active_areas[id]
		if not is_instance_valid(area): continue
		
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
	
	# Filtro de Zona Crítico
	if is_instance_valid(world) and is_instance_valid(world.local_player):
		var remote_zone = _parse_zone_to_int(data.get("zone", -1))
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

	if not remote_players.has(id):
		var rp = load("res://scenes/entities/Ship.tscn").instantiate()
		rp.entity_id = id
		rp.db_id = str(data.get("id", ""))
		rp.add_to_group("remote_players")
		remote_players[id] = rp
		if is_instance_valid(world) and is_instance_valid(world.entities_node):
			world.entities_node.add_child(rp)
	
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
		var tw = create_tween()
		tw.tween_property(area, "modulate:a", 0.0, 1.0)
		tw.tween_callback(area.queue_free)
		active_areas.erase(id)

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
	
	if is_instance_valid(world) and is_instance_valid(world.local_player) and world.local_player.entity_id == target_id:
		if sender_id == target_id: return
		target_node = world.local_player
	elif remote_players.has(target_id):
		target_node = remote_players[target_id]
	elif enemies.has(target_id):
		target_node = enemies[target_id]
	
	if is_instance_valid(target_node):
		var skill_name = data.get("skillName", "")
		
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
	var new_world_size = 2000.0 if (is_dungeon or int(_zoneId) > 2 or int(_zoneId) == 1) else 4000.0
	
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

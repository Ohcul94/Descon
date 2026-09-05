extends Node

# EntityManager.gd (v1.0 - Gestor de Entidades de Red Desacoplado)

var world = null

var remote_players = {}
var enemies = {}
var enemy_pool = []
var active_areas = {} # Cache de zonas de efecto (Humo, etc)
var loot_drops = {} # Cache de botines activos en el mapa
var active_laser_tracking = {} # Indicadores que siguen al jugador {enemy_id: {indicator, target_id}}
var active_wind_walls = {} # Paredes de viento en fase de carga {wall_id: Node2D}
var active_meteors = {} # Meteoritos activos {key: {warn_3d, meteor_3d, fall_s, landed}} (v411)
var active_meteor_zones = {} # Zonas persistentes de meteoritos {mId: {zone_2d, elapsed}}
var death_marks = {} # Marks de Ejecución Directa {mark_key: {enemy_id, node, target_id}}
var active_ascensions = {} # Saltos de Ascensión Telúrica {enemy_id: {node, tw_offsets, warn_timer, beam_3d}} (v414)
var enemy_cast_visuals = {} # Casteo generico enemigo {enemyId: {mId: {visual3D, bg, fg, label, startTime, duration, enemyNode}}}
var zone_cleanup_timer = 0.0
const ZONE_CLEANUP_INTERVAL = 1.0

const ENEMY_SCENE = preload("res://scenes/entities/Enemy.tscn")
const SHIP_SCENE = preload("res://scenes/entities/Ship.tscn")
const LOOT_DROP_SCRIPT = preload("res://scripts/entities/LootDrop.gd")
const WIND_BARRIER_VFX_SCENE = "res://VFX/scenes/VFX_Shield_green_plane.tscn"
const VFX_SHIELD_GREEN_SCENE = "res://VFX/scenes/VFX_Shield_green.tscn"
const BEACON_3D_SCRIPT = preload("res://scripts/vfx/Beacon3D.gd")
const METEOR_ZONE_SCRIPT = preload("res://scripts/systems/MeteorZoneVisual.gd")
const FOLLOW_ORB_3D_SCRIPT = preload("res://scripts/entities/projectiles/FollowOrb3D.gd")

# Texturas precargadas estáticamente
const TEX_CURACION_TRANSP = preload("res://assets/Efectos de Skills/Curacion(Transp).png")
const SMOKE_TEXTURE = preload("res://VFX/textures/T_VFX_Smoke_4_alpha.PNG")
const TEX_ESFERA_AZUL_1 = preload("res://assets/Esferas/EsferaAzul1.png")
const TEX_ESFERA_VERDE_1 = preload("res://assets/Esferas/EsferaVerde1.png")

func setup(world_ref):
	world = world_ref
	print("[EntityManager] Vinculado al controlador de mundo exitosamente.")
	
	# Suscripciones Centralizadas de Eventos de Red
	NetworkManager.enemy_cast_started.connect(_on_enemy_cast_started)
	NetworkManager.enemy_cast_ended.connect(_on_enemy_cast_ended)
	NetworkManager.enemy_cast_cancelled.connect(_on_enemy_cast_cancelled)
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
	NetworkManager.wind_push.connect(_on_wind_push)
	NetworkManager.taunt_event.connect(_on_taunt_event)
	NetworkManager.loot_spawned.connect(_on_loot_spawned)
	NetworkManager.loot_despawned.connect(_on_loot_despawned)
	NetworkManager.boss_colors_start.connect(_on_boss_colors_start)
	NetworkManager.boss_colors_end.connect(_on_boss_colors_end)


func _process(delta):
	_update_enemy_cast_visuals(delta)
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
				
				area.global_position = owner_vis
				
				var bolt_timer = area.get_meta("bolt_timer") + delta
				area.set_meta("bolt_timer", bolt_timer)
				if bolt_timer >= 0.08:
					area.set_meta("bolt_timer", 0.0)
					area.set_meta("bolt_seed", randi())
				
				var start_pos = owner_vis + Vector2(0, -20)
				var end_pos = target_vis + Vector2(0, -20)
				var bolt_seed = area.get_meta("bolt_seed")
				var pulse = area.get_meta("pulse_timer") + delta * 12.0
				area.set_meta("pulse_timer", pulse)
				var intensity = 0.5 + sin(pulse * 2.0) * 0.5
				
				var bolt_glow = area.get_node_or_null("BoltGlow")
				var bolt_main = area.get_node_or_null("BoltMain")
				var bolt_brn = area.get_node_or_null("BoltBranches")
				
				var main_pts = _generate_lightning(start_pos, end_pos, 10, bolt_seed, 60.0)
				if bolt_main:
					bolt_main.points = main_pts
					bolt_main.width = 3.5 + intensity * 1.5
				if bolt_glow:
					bolt_glow.points = main_pts
					bolt_glow.width = 10.0 + intensity * 4.0
				
				var branch_pts = _generate_lightning_branches(start_pos, end_pos, main_pts, bolt_seed + 999)
				if bolt_brn:
					bolt_brn.points = branch_pts
				
				var ring_node = area.get_node_or_null("LimitRing")
				if ring_node:
					ring_node.rotation += delta * 0.2
			else:
				for n in ["BoltGlow", "BoltMain", "BoltBranches"]:
					var bn = area.get_node_or_null(n)
					if bn: bn.points = []
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
						var fill_duration = max(0.05, duration - lock_time)
						var progress = clamp(timer / fill_duration, 0.0, 1.0)
						var circle_3d = area.get_meta("circle_3d") if area.has_meta("circle_3d") else null
						if is_instance_valid(circle_3d):
							var current_map_c = get_tree().get_first_node_in_group("map")
							var is_decal_c = area.get_meta("is_decal", false)
							if is_decal_c and is_instance_valid(current_map_c) and is_instance_valid(current_map_c.get("sub_viewport")):
								# Decal: sigue posición 3D proyectada sobre terreno
								var s_f = current_map_c.scale_factor if "scale_factor" in current_map_c else 0.02
								var cz = current_map_c.correction_z if "correction_z" in current_map_c else 1.41421356
								var h = _sample_terrain_height(en.global_position, current_map_c) if is_instance_valid(current_map_c.get("terrain_node")) else _attack_vfx_base_y()
								if area.get_meta("is_locked"):
									var lpos = area.get_meta("locked_pos")
									var h2 = _sample_terrain_height(lpos, current_map_c) if is_instance_valid(current_map_c.get("terrain_node")) else h
									circle_3d.global_position = Vector3(lpos.x * s_f, h2 + 10.0, lpos.y * s_f * cz)
								else:
									circle_3d.global_position = Vector3(en.global_position.x * s_f, h + 10.0, en.global_position.y * s_f * cz)
							elif is_instance_valid(current_map_c) and is_instance_valid(current_map_c.get("terrain_node")):
								# Conforming: container sigue altura terreno, mesh aporta eps
								var h_cur = _sample_terrain_height(en.global_position, current_map_c)
								if area.get_meta("is_locked"):
									var lpos = area.get_meta("locked_pos")
									if lpos is Vector2:
										var cur_logical = en.global_position
										h_cur = _sample_terrain_height(cur_logical, current_map_c)
									circle_3d.position.y = h_cur - _attack_vfx_base_y()
								else:
									circle_3d.position.y = h_cur - _attack_vfx_base_y()
							else:
								# Fallback original
								circle_3d.position.y = _attack_vfx_base_y() - en.world_root_3d.position.y + 0.05
							for i in 5:
								var ring = circle_3d.get_node_or_null("FireRing_" + str(i))
								if is_instance_valid(ring):
									var ring_mat = ring.material_override
									if ring_mat is StandardMaterial3D:
										var t = float(i) / 4.0
										var delay = t * 0.5
										var ring_p = clamp(progress * 2.5 - delay, 0.0, 1.0)
										ring_mat.albedo_color.a = ring_p * 0.35
										ring_mat.emission_energy_multiplier = ring_p * 3.5
										ring.rotation.y = progress * TAU * (1.0 + t * 0.5)
							var fire_core = circle_3d.get_node_or_null("FireCore")
							if is_instance_valid(fire_core):
								var core_mat = fire_core.material_override
								if core_mat is StandardMaterial3D:
									core_mat.albedo_color.a = clamp(progress * 1.5, 0.0, 0.5)
									core_mat.emission_energy_multiplier = clamp(progress * 5.0, 0.0, 4.0)
								fire_core.position.y = 0.15 + progress * 0.3
					else:
						area.global_position = en_vis
						area.global_rotation = en.global_rotation - PI / 2
						
						# Sincronizar rotación del cono 3D
						var cone_rot = area.get_meta("cone_rotator") if area.has_meta("cone_rotator") else null
						if is_instance_valid(cone_rot):
							var dir_2d = Vector2.RIGHT.rotated(en.global_rotation - PI / 2)
							var current_map = get_tree().get_first_node_in_group("map")
							if is_instance_valid(current_map):
								var s_factor = current_map.scale_factor if "scale_factor" in current_map else 0.02
								var correction_z = current_map.correction_z if "correction_z" in current_map else 1.41421356
								var diff_3d = Vector3(dir_2d.x * s_factor, 0.0, dir_2d.y * s_factor * correction_z)
								cone_rot.rotation.y = atan2(-diff_3d.x, -diff_3d.z)
						elif area.get_meta("is_conforming", false):
							var cur_map_h = get_tree().get_first_node_in_group("map")
							var cone_3d_h = area.get_meta("cone_3d")
							# Suavizar altura Y siempre (lerp) para que no pegue saltos en lomas, incluso sin regenerar
							if is_instance_valid(cone_3d_h) and is_instance_valid(cur_map_h) and is_instance_valid(cur_map_h.get("terrain_node")):
								var target_h = _sample_terrain_height(en.global_position, cur_map_h)
								var target_y = target_h - _attack_vfx_base_y()
								cone_3d_h.position.y = lerp(cone_3d_h.position.y, target_y, clamp(delta*10.0, 0.0, 1.0))
							# Regeneración suave para homing: umbral bajo + interpolación
							var last_rot = area.get_meta("last_rot", en.rotation)
							var last_pos = area.get_meta("last_pos", en.global_position)
							# Homing necesita actualización casi por frame para verse fluido: 0.015 rad (~0.9°) y 6px
							if abs(angle_difference(last_rot, en.rotation)) > 0.015 or last_pos.distance_to(en.global_position) > 6.0:
								var cur_map = get_tree().get_first_node_in_group("map")
								if is_instance_valid(cur_map) and is_instance_valid(cur_map.get("terrain_node")):
									var cone_3d = area.get_meta("cone_3d")
									if is_instance_valid(cone_3d):
										var rng = float(area.get_meta("cone_range", 400.0))
										var ang = float(area.get_meta("cone_angle", 60.0))
										var new_mesh = _make_cone_mesh_conforming(en.global_position, rng, ang, en.rotation, cur_map)
										# Actualizar meshes sin resetear escala
										for ch in cone_3d.get_children():
											if ch is MeshInstance3D:
												ch.mesh = new_mesh
									area.set_meta("last_rot", en.rotation)
									area.set_meta("last_pos", en.global_position)
							# --- Sincronizar naranjita 1:1 con barra de casteo real ---
							var _c3d = area.get_meta("cone_3d")
							if is_instance_valid(_c3d) and _c3d.get_child_count() > 1:
								var _fill = _c3d.get_child(1) as MeshInstance3D
								if is_instance_valid(_fill):
									var _mId = str(area.get_meta("mId", ""))
									var _prog = _get_cast_progress(enemy_id, _mId)
									if _prog < 0.0:
										var _dur = float(area.get_meta("charge_duration", 1.0))
										var _st = int(area.get_meta("charge_start", Time.get_ticks_msec()))
										_prog = clamp(float(Time.get_ticks_msec() - _st) / (_dur * 1000.0), 0.0, 1.0)
									var _sc = lerp(0.01, 1.0, _prog)
									_fill.scale = Vector3(_sc, _sc, _sc)
			else:
				active_areas.erase(id)
				area.queue_free()
			continue

	# 2. Procesar tracking de lásers: actualizar posición y rotación Y del indicador 3D siguiendo al objetivo
	for eid in active_laser_tracking.keys():
		var data = active_laser_tracking[eid]
		var indicator_3d = data.get("indicator_3d")
		var en = data.get("enemy_node")
		var t_id = data.get("targetId", "")
		
		if is_instance_valid(indicator_3d) and is_instance_valid(en):
			# Sincronizar posición 3D
			if is_instance_valid(en.get("world_root_3d")):
				indicator_3d.global_position = en.world_root_3d.global_position
				indicator_3d.global_position.y = _attack_vfx_base_y()
			
			# Sincronizar rotación Y con perspectiva 2.5D
			if not data.get("is_fixed", false) and t_id != "":
				var target_node = null
				if is_instance_valid(world) and is_instance_valid(world.local_player) and str(world.local_player.get("entity_id")) == t_id:
					target_node = world.local_player
				elif remote_players.has(t_id):
					target_node = remote_players[t_id]
				
				if target_node == null and is_instance_valid(world) and is_instance_valid(world.local_player):
					target_node = world.local_player
					
				if is_instance_valid(target_node):
					var target_angle = (target_node.global_position - en.global_position).angle()
					var dir_2d = Vector2.RIGHT.rotated(target_angle)
					var current_map = get_tree().get_first_node_in_group("map")
					var s_factor = current_map.scale_factor if is_instance_valid(current_map) and "scale_factor" in current_map else 0.02
					var correction_z = current_map.correction_z if is_instance_valid(current_map) and "correction_z" in current_map else 1.41421356
					var diff_3d = Vector3(dir_2d.x * s_factor, 0.0, dir_2d.y * s_factor * correction_z)
					var target_y_rot = atan2(-diff_3d.x, -diff_3d.z)
					indicator_3d.rotation.y = lerp_angle(indicator_3d.rotation.y, target_y_rot, 4.0 * delta)
			elif data.get("is_fixed", false):
				var fixed_shoot_angle = data.get("fixed_angle", 0.0)
				var dir_2d = Vector2.RIGHT.rotated(fixed_shoot_angle)
				var current_map = get_tree().get_first_node_in_group("map")
				var s_factor = current_map.scale_factor if is_instance_valid(current_map) and "scale_factor" in current_map else 0.02
				var correction_z = current_map.correction_z if is_instance_valid(current_map) and "correction_z" in current_map else 1.41421356
				var diff_3d = Vector3(dir_2d.x * s_factor, 0.0, dir_2d.y * s_factor * correction_z)
				indicator_3d.rotation.y = atan2(-diff_3d.x, -diff_3d.z)
		else:
			if is_instance_valid(indicator_3d):
				indicator_3d.queue_free()
			active_laser_tracking.erase(eid)

# v411.2: Altura 3D a la que deben verse los VFX de ataque enemigo.
# Los bosses tienen world_root_3d elevado (escala mayor, y=2.5); los VFX deben
# apuntar a la altura de jugadores/enemigos comunes (escala normal, y=1.0).
func _attack_vfx_base_y() -> float:
	var pl = get_tree().get_first_node_in_group("player")
	if is_instance_valid(pl) and is_instance_valid(pl.get("world_root_3d")):
		return pl.world_root_3d.position.y
	return 1.0

func _get_enemy_cast_color(mech_type: String, mId: String) -> Color:
	var t = mech_type.to_lower()
	var mid = mId.to_lower()
	
	# Curación
	if "life_steal" in t or "heal" in t or "heal" in mid or "curacion" in mid:
		return Color(0.15, 0.95, 0.15) # Verde curación
	# Defensa
	elif "shield_steal" in t or "wind_wall" in t or "burrow" in t or "shield" in mid or "barrier" in mid:
		return Color(0.3, 0.65, 0.9) # Azul defensa
	# Utilidad / CC / Movimiento
	elif "sleep" in t or "ascension" in t or "stun" in mid or "slow" in mid:
		return Color(0.95, 0.9, 0.35) # Amarillo utilidad
	# Ataque por defecto
	else:
		return Color(0.95, 0.15, 0.15) # Rojo/Naranja de ataque

func _create_enemy_cast_visual(enemy: Node, mId: String, castTimeMs: float, mech_type: String = ""):
	if not is_instance_valid(enemy):
		return
	var wr3d = enemy.get("world_root_3d") if "world_root_3d" in enemy else null
	if not is_instance_valid(wr3d):
		wr3d = enemy.get_node_or_null("WorldRoot3D")
		
	var eid = str(enemy.get("entity_id")) if "entity_id" in enemy else str(enemy.name)
	if not enemy_cast_visuals.has(eid):
		enemy_cast_visuals[eid] = {}
	var count = enemy_cast_visuals[eid].size()
	
	var cast_color = _get_enemy_cast_color(mech_type, mId)
	
	# Guardamos el estado inicial en el diccionario sin el visual 3D
	enemy_cast_visuals[eid][mId] = {
		"visual": null,
		"bg": null,
		"fg": null,
		"label": null,
		"startTime": Time.get_ticks_msec(),
		"duration": max(1.0, castTimeMs),
		"enemy": enemy
	}
	
	# Creación de la barra de casteo 2D en el HUD de la entidad
	var ui = enemy.get_node_or_null("HUD_Layer_Final")
	if not is_instance_valid(ui):
		ui = enemy.get("_ui_wrapper") if "_ui_wrapper" in enemy else null
	if is_instance_valid(ui):
		var base_y = -70.0
		var et = enemy.get("entity_type")
		if et != null and et >= 101:
			base_y = -220.0
		
		var is_projected = enemy.get_meta("is_single_world", false) and is_instance_valid(wr3d)
		if is_projected:
			base_y = 0.0
			
		var container = Control.new()
		container.name = "EnemyCastBar2D_" + mId
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Ancho 44 (mismo de la barra de vida), alto 2 (mitad de 4)
		container.custom_minimum_size = Vector2(44, 2)
		container.size = Vector2(44, 2)
		# Centrada horizontalmente (-22) y debajo de la barra de vida (base_y + 2.0)
		container.position = Vector2(-22, base_y + 2.0 + count * 3.0)
		container.z_index = 10
		
		var bg2 = ColorRect.new()
		bg2.name = "BG"
		bg2.color = Color(0.08, 0.08, 0.1, 0.75)
		bg2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		container.add_child(bg2)
		
		var fg2 = ColorRect.new()
		fg2.name = "FG"
		fg2.color = cast_color
		fg2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fg2.anchor_right = 0
		# Sin offsets para que ocupe todo el espacio alto de 2px
		fg2.offset_left = 0
		fg2.offset_right = 0
		fg2.offset_top = 0
		fg2.offset_bottom = 0
		container.add_child(fg2)
		
		ui.add_child(container)
		enemy_cast_visuals[eid][mId]["visual2D"] = container

func _update_enemy_cast_visuals(_delta: float):
	for eid in enemy_cast_visuals.keys():
		var mDict = enemy_cast_visuals[eid]
		for mId in mDict.keys():
			var data = mDict[mId]
			var dur = float(data.get("duration", 1000))
			var start = int(data.get("startTime", 0))
			var elapsed = Time.get_ticks_msec() - start
			var prog = clamp(float(elapsed) / max(1.0, dur), 0.0, 1.0)
			
			var c2d = data.get("visual2D")
			if is_instance_valid(c2d):
				var fg2 = c2d.get_node_or_null("FG")
				if is_instance_valid(fg2):
					fg2.anchor_right = prog

func _on_enemy_cast_started(data: Dictionary):
	var eid = str(data.get("id", ""))
	var mId = str(data.get("mId", data.get("id", "")))
	var castMs = float(data.get("castTimeMs", data.get("castTime", 0)))
	if eid == "" or castMs <= 0:
		return
	var enemy = enemies.get(eid)
	if not is_instance_valid(enemy):
		return
	_create_enemy_cast_visual(enemy, mId, castMs, data.get("type", ""))

func _on_enemy_cast_ended(data: Dictionary):
	var eid = str(data.get("id", ""))
	var mId = str(data.get("mId", ""))
	if eid == "": return
	if not enemy_cast_visuals.has(eid): return
	var mDict = enemy_cast_visuals[eid]
	if mId != "" and mDict.has(mId):
		var d = mDict[mId]
		var vis = d.get("visual")
		if is_instance_valid(vis): vis.queue_free()
		var vis2 = d.get("visual2D")
		if is_instance_valid(vis2): vis2.queue_free()
		mDict.erase(mId)
		if mDict.is_empty():
			enemy_cast_visuals.erase(eid)
	else:
		# clear all for this enemy
		for k in mDict.keys():
			var d2 = mDict[k]
			var v = d2.get("visual")
			if is_instance_valid(v): v.queue_free()
			var v2 = d2.get("visual2D")
			if is_instance_valid(v2): v2.queue_free()
		enemy_cast_visuals.erase(eid)

func _on_enemy_cast_cancelled(data: Dictionary):
	_on_enemy_cast_ended(data)

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
		if remote_zone != -1:
			p.set_meta("zone", remote_zone)
		p.update_stats(data)

func _get_enemy_from_pool() -> Node:
	for en in enemy_pool:
		if is_instance_valid(en) and en.get_meta("is_pooled", false):
			# v416.1: Si el nodo quedó referenciado bajo un id muerto, limpiar la
			# referencia para no reutilizar el mismo nodo con dos ids a la vez
			for eid in enemies.keys():
				if enemies[eid] == en:
					enemies.erase(eid)
					break
			en.activate_from_pool()
			return en
			
	var en = ENEMY_SCENE.instantiate()
	enemy_pool.append(en)
	if is_instance_valid(world) and is_instance_valid(world.entities_node):
		world.entities_node.add_child(en)
	return en

func _on_laser_indicator_exited(enemy_id: String):
	active_laser_tracking.erase(enemy_id)

func _on_enemy_action(data: Dictionary):
	var action = data.get("action", "")
	var enemy_id = str(data.get("id", ""))
	# v900.0: sonido de mecánica genérico (2D con atenuación)
	if AudioManager and AudioManager.has_method("play_mechanic_sound") and not String(action).is_empty():
		var candidate = String(action).split("_")[0]
		if candidate.is_empty():
			candidate = String(action)
		if GameConstants.MECHANICS_LIB.has(candidate) or GameConstants.DEFENSE_LIB.has(candidate) or GameConstants.MOVEMENT_LIB.has(candidate):
			var epos = Vector2.INF
			if enemies.has(enemy_id) and is_instance_valid(enemies[enemy_id]):
				epos = enemies[enemy_id].global_position
			AudioManager.play_mechanic_sound(candidate, null, epos)
	
	# v410: Shield Steal se gestiona independiente del gate de enemies dict,
	# porque el enemigo que dispara puede no estar renderizado en el cliente.
	if action == "shield_steal_start" or action == "shield_steal_tick" or action == "shield_steal_end":
		_handle_shield_steal_action(data)
		return
	# v412: Life Steal (robo de vida) - igual que shield_steal pero con aros verdes
	if action == "life_steal_start" or action == "life_steal_tick" or action == "life_steal_end":
		_handle_life_steal_action(data)
		return

	# v411: Meteorito - los meteoritos caen sobre posiciones del mapa, no dependen
	# de que el enemigo esté renderizado en el cliente.
	if action == "meteor_summon" or action == "meteor_impact":
		_handle_meteor_action(data)
		return
	if action == "meteor_zone_start" or action == "meteor_zone_end":
		_handle_meteor_zone_action(data)
		return
	# v413: Sueño Inducido - orbe 3D que vuela del enemigo al jugador al lanzar el sleep
	if action == "sleep_cast":
		_handle_sleep_action(data)
		return

	# v413: Ejecución Directa - marca de calavera sobre los targets objetivo (telegrafo)
	if action == "death_cast_start" or action == "death_cast_end":
		_handle_death_mark_action(data)
		return

	# v414: Ascensión Telúrica - el enemigo salta y aterriza sobre el área marcada
	if action == "ascension_cast" or action == "ascension_leap" or action == "ascension_impact":
		_handle_ascension_action(data)
		return

	if enemies.has(enemy_id):
		var en = enemies[enemy_id]
		var duration = float(data.get("duration", 2000.0)) / 1000.0
		var angle = float(data.get("angle", 0.0))
		var length = float(data.get("range", 1500.0))
		var t_id = str(data.get("targetId", ""))
		
		# Limpiar tracking anterior e indicadores viejos
		if active_laser_tracking.has(enemy_id):
			var old_data = active_laser_tracking[enemy_id]
			var old_3d = old_data.get("indicator_3d")
			if is_instance_valid(old_3d): old_3d.queue_free()
			active_laser_tracking.erase(enemy_id)
			
		for child in en.get_children():
			if child.has_meta("is_laser_indicator"):
				en.remove_child(child)
				child.queue_free()
		
		# Limpiar indicador 3D suelto en el viewport (de runs anteriores)
		var current_map = get_tree().get_first_node_in_group("map")
		var is_3d_active = is_instance_valid(current_map) and current_map.get("sub_viewport") != null and is_instance_valid(en.get("world_root_3d"))
		if is_3d_active:
			var old_vp_node = current_map.sub_viewport.get_node_or_null("LaserIndicator3D_" + enemy_id)
			if is_instance_valid(old_vp_node): old_vp_node.queue_free()
		
		if action == "charging":
			if is_3d_active:
				# Fase charging en 3D: indicador fino rojo translúcido
				# Fórmula de rotación Y idéntica a la del proyectil: -angle - PI/2.0
				var s_factor = current_map.scale_factor if "scale_factor" in current_map else 0.02
				var beam_len_3d = length * s_factor
				var half_len = beam_len_3d / 2.0
				
				var indicator_3d = Node3D.new()
				indicator_3d.name = "LaserIndicator3D_" + enemy_id
				# Posición inicial = posición 3D del enemigo
				if is_instance_valid(en.get("world_root_3d")):
					indicator_3d.position = en.world_root_3d.global_position
					indicator_3d.position.y = _attack_vfx_base_y()
				# Rotación Y corregida inicial con perspectiva 2.5D
				var dir_2d = Vector2.RIGHT.rotated(angle)
				var correction_z = current_map.correction_z if "correction_z" in current_map else 1.41421356
				var diff_3d = Vector3(dir_2d.x * s_factor, 0.0, dir_2d.y * s_factor * correction_z)
				indicator_3d.rotation.y = atan2(-diff_3d.x, -diff_3d.z)
				current_map.sub_viewport.add_child(indicator_3d)
				
				var mesh_inst = MeshInstance3D.new()
				var box = BoxMesh.new()
				box.size = Vector3(0.08, 0.08, beam_len_3d)
				mesh_inst.mesh = box
				var mat = StandardMaterial3D.new()
				mat.albedo_color = Color(1.0, 0.0, 0.0, 0.4)
				mat.emission_enabled = true
				mat.emission = Color(1.0, 0.0, 0.0)
				mat.emission_energy_multiplier = 2.0
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mesh_inst.material_override = mat
				mesh_inst.position = Vector3(0, 0.2, -half_len)
				indicator_3d.add_child(mesh_inst)
				
				# Registrar en tracking para actualizar posición y rotación Y en _process
				active_laser_tracking[enemy_id] = {
					"indicator_3d": indicator_3d,
					"enemy_node": en,
					"targetId": t_id,
					"range": length,
					"is_fixed": false
				}
				
				indicator_3d.tree_exiting.connect(_on_laser_indicator_exited.bind(enemy_id))
				
				# Animación de carga
				var tw = create_tween()
				tw.tween_property(mat, "albedo_color:a", 0.8, duration)
				tw.parallel().tween_property(mat, "emission_energy_multiplier", 4.0, duration)
				tw.finished.connect(indicator_3d.queue_free)
			else:
				# Fallback 2D: Line2D hijo local de en con la rotación del ángulo del servidor
				var indicator = Line2D.new()
				indicator.set_meta("is_laser_indicator", true)
				indicator.width = 2.5
				indicator.default_color = Color(1, 0, 0, 0.4) 
				indicator.z_index = -1 
				indicator.top_level = false
				indicator.position = Vector2.ZERO
				indicator.rotation = angle  # ángulo del servidor directamente
				indicator.points = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT * length])
				en.add_child(indicator) 
				var tw = create_tween()
				tw.tween_property(indicator, "default_color:a", 0.8, duration)
				tw.finished.connect(indicator.queue_free)
				
		elif action == "locked":
			if is_3d_active:
				# Fase locked en 3D: rayo más grueso con ángulo fijado del servidor
				var s_factor = current_map.scale_factor if "scale_factor" in current_map else 0.02
				var beam_len_3d = length * s_factor
				var half_len = beam_len_3d / 2.0
				
				var indicator_3d = Node3D.new()
				indicator_3d.name = "LaserIndicator3D_" + enemy_id
				if is_instance_valid(en.get("world_root_3d")):
					indicator_3d.position = en.world_root_3d.global_position
					indicator_3d.position.y = _attack_vfx_base_y()
				# Ángulo fijado corregido inicial con perspectiva 2.5D
				var dir_2d = Vector2.RIGHT.rotated(angle)
				var correction_z = current_map.correction_z if "correction_z" in current_map else 1.41421356
				var diff_3d = Vector3(dir_2d.x * s_factor, 0.0, dir_2d.y * s_factor * correction_z)
				indicator_3d.rotation.y = atan2(-diff_3d.x, -diff_3d.z)
				current_map.sub_viewport.add_child(indicator_3d)
				
				var mesh_inst = MeshInstance3D.new()
				var box = BoxMesh.new()
				box.size = Vector3(0.16, 0.16, beam_len_3d)
				mesh_inst.mesh = box
				var mat = StandardMaterial3D.new()
				mat.albedo_color = Color(1.0, 0.0, 0.0, 0.85)
				mat.emission_enabled = true
				mat.emission = Color(1.0, 0.0, 0.0)
				mat.emission_energy_multiplier = 4.0
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mesh_inst.material_override = mat
				mesh_inst.position = Vector3(0, 0.2, -half_len)
				indicator_3d.add_child(mesh_inst)
				
				# En locked el ángulo está fijado
				active_laser_tracking[enemy_id] = {
					"indicator_3d": indicator_3d,
					"enemy_node": en,
					"range": length,
					"is_fixed": true,
					"fixed_angle": angle
				}
				
				indicator_3d.tree_exiting.connect(_on_laser_indicator_exited.bind(enemy_id))
				
				en.set_meta("is_locked", true)
				await get_tree().create_timer(duration).timeout
				if is_instance_valid(en): en.set_meta("is_locked", false)
				if is_instance_valid(indicator_3d): indicator_3d.queue_free()
			else:
				# Fallback 2D: Line2D hijo de en con el ángulo fijado del servidor
				var indicator = Line2D.new()
				indicator.set_meta("is_laser_indicator", true)
				indicator.width = 5.0
				indicator.default_color = Color(1, 0, 0, 0.85)
				indicator.z_index = -1
				indicator.top_level = false
				indicator.position = Vector2.ZERO
				indicator.rotation = angle  # ángulo fijado del servidor
				indicator.points = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT * length])
				en.add_child(indicator) 
				
				en.set_meta("is_locked", true)
				await get_tree().create_timer(duration).timeout
				if is_instance_valid(en): en.set_meta("is_locked", false)
				if is_instance_valid(indicator): indicator.queue_free()
		
		elif action == "cone_charging":
			var range_val = float(data.get("range", 400.0))
			var cone_angle = float(data.get("coneAngle", 60.0))
			var lock_time_s = float(data.get("lockTimeMs", 0.0)) / 1000.0
			var charge_duration = max(0.05, duration - lock_time_s)
			
			# Contenedor del cono (2D Dummy/Controller)
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
			
			if is_3d_active:
				var s_factor = current_map.scale_factor if "scale_factor" in current_map else 0.02
				var correction_z = current_map.correction_z if "correction_z" in current_map else 1.41421356
				var has_terrain = is_instance_valid(current_map.get("terrain_node")) and current_map.get("terrain_node") != null
				# v501: Si el renderer soporta Decal (Forward+) usamos Decal que SIEMPRE respeta el relieve.
				# En gl_compatibility (tu proyecto actual) usamos MALLA CONFORMANTE muestreando altura por vértice.
				if _render_supports_decal() and has_terrain:
					# ---- Decal Path (Forward+/Mobile) - Proyección real sobre terreno ----
					var h_center = _sample_terrain_height(en.global_position, current_map)
					var pos3d = Vector3(en.global_position.x * s_factor, h_center + 12.0, en.global_position.y * s_factor * correction_z)
					var tex = _generate_decal_texture_cone(256, cone_angle)
					var decal_size = Vector3(range_val * s_factor * 2.2, 24.0, range_val * s_factor * 2.2)
					var decal = _create_decal_node(pos3d, decal_size, tex, Color(1,1,1,1), 1.0, 0.35)
					# Orientar Decal: forward = -Z local, decal proyecta en -Y => girar Y = enemy_rot
					decal.rotation.y = en.rotation
					current_map.sub_viewport.add_child(decal)
					cone_node.set_meta("cone_3d", decal)
					cone_node.set_meta("cone_rotator", null)
					# Animación: fade in via modulate.a
					decal.modulate.a = 0.0
					var tw_d = decal.create_tween()
					tw_d.tween_property(decal, "modulate:a", 1.0, charge_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
				elif has_terrain:
					# ---- Malla Conformante (gl_compatibility) - Muestrea altura por vértice ----
					var cone_3d = Node3D.new()
					cone_3d.name = "Cone3D_" + enemy_id
					# BAKED: sin scale/rotator. world_root_3d.y = base_y (1.0), lo llevamos a h_center; mesh aporta eps=0.12
					var h_center = _sample_terrain_height(en.global_position, current_map)
					cone_3d.position = Vector3(0, h_center - _attack_vfx_base_y(), 0)
					en.world_root_3d.add_child(cone_3d)
					
					# Mesh conformante bakeado con rotación ya incluida y altura por vertice
					var cone_mesh = _make_cone_mesh_conforming(en.global_position, range_val, cone_angle, en.rotation, current_map)
					
					var mesh_bg = MeshInstance3D.new()
					mesh_bg.mesh = cone_mesh
					var mat_bg = StandardMaterial3D.new()
					mat_bg.albedo_color = Color(1.0, 0.0, 0.0, 0.14)
					mat_bg.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mat_bg.cull_mode = BaseMaterial3D.CULL_DISABLED
					mat_bg.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					mat_bg.no_depth_test = true
					mat_bg.render_priority = 2
					mesh_bg.material_override = mat_bg
					cone_3d.add_child(mesh_bg)
					
					var mesh_fill = MeshInstance3D.new()
					mesh_fill.mesh = cone_mesh
					var mat_fill = StandardMaterial3D.new()
					mat_fill.albedo_color = Color(1.0, 0.55, 0.08, 0.42) # naranjita
					mat_fill.emission_enabled = true
					mat_fill.emission = Color(1.0, 0.45, 0.05)
					mat_fill.emission_energy_multiplier = 1.9
					mat_fill.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mat_fill.cull_mode = BaseMaterial3D.CULL_DISABLED
					mat_fill.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					mat_fill.no_depth_test = true
					mat_fill.render_priority = 2
					mesh_fill.material_override = mat_fill
					cone_3d.add_child(mesh_fill)
					mesh_fill.scale = Vector3(0.01, 0.01, 0.01)
					
					cone_node.set_meta("cone_3d", cone_3d)
					cone_node.set_meta("cone_rotator", null)
					cone_node.set_meta("is_conforming", true)
					cone_node.set_meta("cone_range", range_val)
					cone_node.set_meta("cone_angle", cone_angle)
					cone_node.set_meta("last_rot", en.rotation)
					cone_node.set_meta("last_pos", en.global_position)
					cone_node.set_meta("charge_duration", charge_duration)
					cone_node.set_meta("charge_start", Time.get_ticks_msec())
					cone_node.set_meta("mId", str(data.get("mId", data.get("id", enemy_id))))
					# No tween: el naranjita se actualiza por frame según barra de casteo real para estar 1:1
					# Dejar escala inicial pequeña, el _process la llevará a 1.0 siguiendo _get_cast_progress
				else:
					# ---- Fallback plano original (mapas sin terreno) ----
					var cone_3d = Node3D.new()
					cone_3d.name = "Cone3D_" + enemy_id
					cone_3d.scale = Vector3(1.0, 1.0, correction_z)
					en.world_root_3d.add_child(cone_3d)
					cone_3d.position.y = _attack_vfx_base_y() - en.world_root_3d.position.y + 0.05
					var cone_rotator = Node3D.new()
					cone_3d.add_child(cone_rotator)
					var dir_2d = Vector2.RIGHT.rotated(en.rotation - PI / 2)
					var diff_3d = Vector3(dir_2d.x * s_factor, 0.0, dir_2d.y * s_factor * correction_z)
					cone_rotator.rotation.y = atan2(-diff_3d.x, -diff_3d.z)
					var range_3d = range_val * s_factor
					var cone_mesh = _make_cone_mesh_3d(range_3d, cone_angle)
					var mesh_bg = MeshInstance3D.new()
					mesh_bg.mesh = cone_mesh
					var mat_bg = StandardMaterial3D.new()
					mat_bg.albedo_color = Color(1.0, 0.0, 0.0, 0.12)
					mat_bg.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mat_bg.cull_mode = BaseMaterial3D.CULL_DISABLED
					mesh_bg.material_override = mat_bg
					cone_rotator.add_child(mesh_bg)
					var mesh_fill = MeshInstance3D.new()
					mesh_fill.mesh = cone_mesh
					var mat_fill = StandardMaterial3D.new()
					mat_fill.albedo_color = Color(1.0, 0.1, 0.1, 0.35)
					mat_fill.emission_enabled = true
					mat_fill.emission = Color(1.0, 0.1, 0.1)
					mat_fill.emission_energy_multiplier = 1.5
					mat_fill.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mat_fill.cull_mode = BaseMaterial3D.CULL_DISABLED
					mesh_fill.material_override = mat_fill
					cone_rotator.add_child(mesh_fill)
					mesh_fill.scale = Vector3(0.01, 0.01, 0.01)
					cone_node.set_meta("cone_3d", cone_3d)
					cone_node.set_meta("cone_rotator", cone_rotator)
					var tw_3d = cone_rotator.create_tween()
					tw_3d.tween_property(mesh_fill, "scale", Vector3.ONE, charge_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			else:
				# ---- Fallback 2D Cone Indicator ----
				var poly_bg = Polygon2D.new()
				poly_bg.polygon = _get_cone_points(range_val, cone_angle)
				poly_bg.color = Color(1.0, 0.0, 0.0, 0.15)
				cone_node.add_child(poly_bg)
				
				var poly_charge = Polygon2D.new()
				poly_charge.polygon = _get_cone_points(1.0, cone_angle)
				poly_charge.color = Color(1.0, 0.1, 0.1, 0.4)
				cone_node.add_child(poly_charge)
				
				var lambda = func(r: float):
					if is_instance_valid(poly_charge):
						poly_charge.polygon = _get_cone_points(r, cone_angle)
				var tw = cone_node.create_tween()
				tw.tween_method(lambda, 1.0, range_val, charge_duration)
			
			active_areas["cone_" + enemy_id] = cone_node
			
		elif action == "cone_fire":
			var indicator = en.get_node_or_null("ConeIndicator_" + enemy_id)
			if is_instance_valid(indicator):
				var cone_3d = indicator.get_meta("cone_3d") if indicator.has_meta("cone_3d") else null
				if is_instance_valid(cone_3d):
					cone_3d.queue_free()
				indicator.queue_free()
				
			var root_indicator = world.entities_node.get_node_or_null("ConeIndicator_" + enemy_id) if is_instance_valid(world) and is_instance_valid(world.entities_node) else null
			if is_instance_valid(root_indicator):
				var cone_3d = root_indicator.get_meta("cone_3d") if root_indicator.has_meta("cone_3d") else null
				if is_instance_valid(cone_3d):
					cone_3d.queue_free()
				root_indicator.queue_free()
				
			# Also check for orphan 3D cones on world_root_3d
			if is_instance_valid(en.get("world_root_3d")):
				var orphan = en.world_root_3d.get_node_or_null("Cone3D_" + enemy_id)
				if is_instance_valid(orphan):
					orphan.queue_free()
				
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
			
			if is_3d_active:
				var has_terrain_b = is_instance_valid(current_map.get("terrain_node")) and current_map.get("terrain_node") != null
				if _render_supports_decal() and has_terrain_b:
					var h_c = _sample_terrain_height(en.global_position, current_map)
					var pos3d = Vector3(en.global_position.x * current_map.scale_factor, h_c + 12.0, en.global_position.y * current_map.scale_factor * current_map.correction_z)
					var tex = _generate_decal_texture_cone(256, cone_angle)
					var decal_size = Vector3(range_val * current_map.scale_factor * 2.2, 22.0, range_val * current_map.scale_factor * 2.2)
					var decal = _create_decal_node(pos3d, decal_size, tex, Color(1,1,1,1), 2.5, 0.35)
					# Decal 0° = norte (-Z). En charguing usan en.rotation (angle+PI/2). En fire angle viene crudo.
					decal.rotation.y = angle + PI/2
					current_map.sub_viewport.add_child(decal)
					# Reusar blast_3d var para cleanup uniforme
					var blast_3d = decal
					var tw_3d = blast_3d.create_tween()
					tw_3d.tween_property(decal, "modulate:a", 0.0, 0.25)
					tw_3d.finished.connect(blast_3d.queue_free)
				elif has_terrain_b:
					# Cono conformante en blast (misma lógica que charging pero ángulo viene de data)
					var blast_3d = Node3D.new()
					blast_3d.name = "ConeBlast3D_" + enemy_id
					var h_c = _sample_terrain_height(en.global_position, current_map)
					blast_3d.position = Vector3(0, h_c - _attack_vfx_base_y(), 0)
					en.world_root_3d.add_child(blast_3d)
					var dir_angle_for_blast = angle + PI/2 # angle crudo -> +PI/2 para alinear con en.rotation como en charging
					# Si angle es 0 (fallback), usar en.rotation directo que ya trae el offset
					if abs(angle) < 0.001:
						dir_angle_for_blast = en.rotation
					var cone_mesh = _make_cone_mesh_conforming(en.global_position, range_val, cone_angle, dir_angle_for_blast, current_map)
					var mesh_blast = MeshInstance3D.new()
					mesh_blast.mesh = cone_mesh
					var mat_blast = StandardMaterial3D.new()
					mat_blast.albedo_color = Color(1.0, 0.4, 0.0, 0.8)
					mat_blast.emission_enabled = true
					mat_blast.emission = Color(1.0, 0.4, 0.0)
					mat_blast.emission_energy_multiplier = 3.0
					mat_blast.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mat_blast.cull_mode = BaseMaterial3D.CULL_DISABLED
					mat_blast.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					mesh_blast.material_override = mat_blast
					blast_3d.add_child(mesh_blast)
					var tw_3d = mesh_blast.create_tween()
					tw_3d.tween_property(mesh_blast, "material_override:albedo_color:a", 0.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
					tw_3d.parallel().tween_property(mesh_blast, "material_override:emission_energy_multiplier", 0.0, 0.25)
					tw_3d.finished.connect(blast_3d.queue_free)
				else:
					# ---- Fallback plano original ----
					var blast_3d = Node3D.new()
					blast_3d.name = "ConeBlast3D_" + enemy_id
					var s_factor = current_map.scale_factor if "scale_factor" in current_map else 0.02
					var correction_z = current_map.correction_z if "correction_z" in current_map else 1.41421356
					blast_3d.scale = Vector3(1.0, 1.0, correction_z)
					en.world_root_3d.add_child(blast_3d)
					blast_3d.position.y = _attack_vfx_base_y() - en.world_root_3d.position.y + 0.05
					var blast_rotator = Node3D.new()
					blast_3d.add_child(blast_rotator)
					var dir_2d = Vector2.RIGHT.rotated(angle)
					var diff_3d = Vector3(dir_2d.x * s_factor, 0.0, dir_2d.y * s_factor * correction_z)
					blast_rotator.rotation.y = atan2(-diff_3d.x, -diff_3d.z)
					var range_3d = range_val * s_factor
					var cone_mesh = _make_cone_mesh_3d(range_3d, cone_angle)
					var mesh_blast = MeshInstance3D.new()
					mesh_blast.mesh = cone_mesh
					var mat_blast = StandardMaterial3D.new()
					mat_blast.albedo_color = Color(1.0, 0.4, 0.0, 0.8)
					mat_blast.emission_enabled = true
					mat_blast.emission = Color(1.0, 0.4, 0.0)
					mat_blast.emission_energy_multiplier = 3.0
					mat_blast.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mat_blast.cull_mode = BaseMaterial3D.CULL_DISABLED
					mesh_blast.material_override = mat_blast
					blast_rotator.add_child(mesh_blast)
					var tw_3d = blast_rotator.create_tween()
					tw_3d.tween_property(mesh_blast, "material_override:albedo_color:a", 0.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
					tw_3d.parallel().tween_property(mesh_blast, "material_override:emission_energy_multiplier", 0.0, 0.25)
					tw_3d.finished.connect(blast_3d.queue_free)
				
				var tw_dummy = blast.create_tween()
				tw_dummy.tween_interval(0.25)
				tw_dummy.finished.connect(func():
					active_areas.erase("blast_" + enemy_id)
					blast.queue_free()
				)
			else:
				# ---- Fallback 2D Cone Blast ----
				var poly_blast = Polygon2D.new()
				poly_blast.polygon = _get_cone_points(range_val, cone_angle)
				poly_blast.color = Color(1.0, 0.4, 0.0, 0.8) # Naranja brillante
				blast.add_child(poly_blast)
				
				# Desvanecer la explosión (2D)
				var tw = blast.create_tween()
				tw.tween_property(poly_blast, "color:a", 0.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
				tw.finished.connect(func():
					active_areas.erase("blast_" + enemy_id)
					blast.queue_free()
				)
			
			active_areas["blast_" + enemy_id] = blast
		
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
				
			# ---- 3D Circle Charging Aura (Decal / Conforming) ----
			if is_3d_active:
				var has_terrain_c = is_instance_valid(current_map.get("terrain_node")) and current_map.get("terrain_node") != null
				var s_factor = current_map.scale_factor if "scale_factor" in current_map else 0.02
				var correction_z = current_map.correction_z if "correction_z" in current_map else 1.41421356
				var outer_r3d = range_val * s_factor
				var inner_r3d = r_inner * s_factor
				if _render_supports_decal() and has_terrain_c:
					# Decal path: círculo perfecto proyectado
					var h_c = _sample_terrain_height(en.global_position, current_map)
					var pos3d = Vector3(en.global_position.x * s_factor, h_c + 10.0, en.global_position.y * s_factor * correction_z)
					var tex = _generate_decal_texture_circle(256)
					var decal_size = Vector3(range_val * s_factor * 2.2, 20.0, range_val * s_factor * 2.2)
					var decal = _create_decal_node(pos3d, decal_size, tex, Color(1,1,1,1), 1.2, 0.3)
					current_map.sub_viewport.add_child(decal)
					# Guardamos decal como circle_3d para que _process y cleanup lo encuentren (duck typing)
					circle_node.set_meta("circle_3d", decal)
					circle_node.set_meta("is_decal", true)
					circle_node.tree_exiting.connect(func():
						if is_instance_valid(decal):
							decal.queue_free()
					)
					# No creamos rings 3D: el decal ya tiene borde, pero mantenemos compatibilidad
					var dummy_3d = decal
					dummy_3d.set_meta("outer_r3d", outer_r3d)
					dummy_3d.set_meta("inner_r3d", inner_r3d)
				elif has_terrain_c:
					# Conforming disc: malla copia relieve, container a h_center
					var circle_3d = Node3D.new()
					circle_3d.name = "Circle3D_" + enemy_id
					var h_center = _sample_terrain_height(en.global_position, current_map)
					circle_3d.position = Vector3(0, h_center - _attack_vfx_base_y(), 0)
					en.world_root_3d.add_child(circle_3d)
					
					var disc_mesh = _make_circle_disc_conforming(en.global_position, range_val, current_map)
					var ground_disc = MeshInstance3D.new()
					ground_disc.mesh = disc_mesh
					var g_mat = StandardMaterial3D.new()
					g_mat.albedo_color = Color(1.0, 0.15, 0.0, 0.22)
					g_mat.emission_enabled = true
					g_mat.emission = Color(1.0, 0.15, 0.0)
					g_mat.emission_energy_multiplier = 0.7
					g_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					g_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					g_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					g_mat.no_depth_test = true
					g_mat.render_priority = 2
					ground_disc.material_override = g_mat
					circle_3d.add_child(ground_disc)
					
					var num_rings = 5
					for i in num_rings:
						var ring = MeshInstance3D.new()
						ring.name = "FireRing_" + str(i)
						var t_mesh = TorusMesh.new()
						var t = float(i) / float(num_rings - 1)
						var rr = lerp(inner_r3d, outer_r3d, t)
						t_mesh.inner_radius = rr - 0.015
						t_mesh.outer_radius = rr + 0.015
						ring.mesh = t_mesh
						var r_mat = StandardMaterial3D.new()
						r_mat.albedo_color = Color(1.0, 0.3, 0.0, 0.0)
						r_mat.emission_enabled = true
						r_mat.emission = Color(1.0, 0.4, 0.0)
						r_mat.emission_energy_multiplier = 0.0
						r_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
						r_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
						ring.material_override = r_mat
						ring.rotation.x = PI / 2
						# Elevar anillo un pelín sobre el disco conformado (evita z-fighting en lomas)
						ring.position.y = 0.02
						circle_3d.add_child(ring)
					
					var core = MeshInstance3D.new()
					core.name = "FireCore"
					var core_s = SphereMesh.new()
					core_s.radius = inner_r3d * 0.3
					core_s.height = inner_r3d * 0.6
					core.mesh = core_s
					var core_mat = StandardMaterial3D.new()
					core_mat.albedo_color = Color(1.0, 0.5, 0.0, 0.0)
					core_mat.emission_enabled = true
					core_mat.emission = Color(1.0, 0.6, 0.1)
					core_mat.emission_energy_multiplier = 0.0
					core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					core_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					core.material_override = core_mat
					core.position.y = 0.15
					circle_3d.add_child(core)
					circle_3d.set_meta("outer_r3d", outer_r3d)
					circle_3d.set_meta("inner_r3d", inner_r3d)
					circle_node.set_meta("circle_3d", circle_3d)
					circle_node.set_meta("is_decal", false)
					circle_node.set_meta("center_2d", en.global_position)
					circle_node.tree_exiting.connect(func():
						if is_instance_valid(circle_3d):
							circle_3d.queue_free()
					)
				else:
					# Fallback original plano
					var circle_3d = Node3D.new()
					circle_3d.name = "Circle3D_" + enemy_id
					circle_3d.scale = Vector3(1.0, 1.0, correction_z)
					en.world_root_3d.add_child(circle_3d)
					circle_3d.position.y = _attack_vfx_base_y() - en.world_root_3d.position.y
					var ground_disc = MeshInstance3D.new()
					var g_mesh = CylinderMesh.new()
					g_mesh.top_radius = outer_r3d
					g_mesh.bottom_radius = outer_r3d
					g_mesh.height = 0.01
					ground_disc.mesh = g_mesh
					var g_mat = StandardMaterial3D.new()
					g_mat.albedo_color = Color(1.0, 0.15, 0.0, 0.15)
					g_mat.emission_enabled = true
					g_mat.emission = Color(1.0, 0.15, 0.0)
					g_mat.emission_energy_multiplier = 0.5
					g_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					g_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					ground_disc.material_override = g_mat
					circle_3d.add_child(ground_disc)
					var num_rings = 5
					for i in num_rings:
						var ring = MeshInstance3D.new()
						ring.name = "FireRing_" + str(i)
						var t_mesh = TorusMesh.new()
						var t = float(i) / float(num_rings - 1)
						var rr = lerp(inner_r3d, outer_r3d, t)
						t_mesh.inner_radius = rr - 0.015
						t_mesh.outer_radius = rr + 0.015
						ring.mesh = t_mesh
						var r_mat = StandardMaterial3D.new()
						r_mat.albedo_color = Color(1.0, 0.3, 0.0, 0.0)
						r_mat.emission_enabled = true
						r_mat.emission = Color(1.0, 0.4, 0.0)
						r_mat.emission_energy_multiplier = 0.0
						r_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
						r_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
						ring.material_override = r_mat
						ring.rotation.x = PI / 2
						circle_3d.add_child(ring)
					var core = MeshInstance3D.new()
					core.name = "FireCore"
					var core_s = SphereMesh.new()
					core_s.radius = inner_r3d * 0.3
					core_s.height = inner_r3d * 0.6
					core.mesh = core_s
					var core_mat = StandardMaterial3D.new()
					core_mat.albedo_color = Color(1.0, 0.5, 0.0, 0.0)
					core_mat.emission_enabled = true
					core_mat.emission = Color(1.0, 0.6, 0.1)
					core_mat.emission_energy_multiplier = 0.0
					core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					core_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					core.material_override = core_mat
					core.position.y = 0.1
					circle_3d.add_child(core)
					circle_3d.set_meta("outer_r3d", outer_r3d)
					circle_3d.set_meta("inner_r3d", inner_r3d)
					circle_node.set_meta("circle_3d", circle_3d)
					circle_node.tree_exiting.connect(func():
						if is_instance_valid(circle_3d):
							circle_3d.queue_free()
					)

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
			
			# Clean up 3D charging ring from world_root_3d
			if is_3d_active and is_instance_valid(en.get("world_root_3d")):
				var old_3d = en.world_root_3d.get_node_or_null("Circle3D_" + enemy_id)
				if is_instance_valid(old_3d):
					old_3d.queue_free()

			# ---- 3D Circle Explosion VFX (Conforming al terreno) ----
			if is_3d_active:
				var s_factor = current_map.scale_factor if "scale_factor" in current_map else 0.02
				var correction_z = current_map.correction_z if "correction_z" in current_map else 1.41421356
				var vp = current_map.sub_viewport
				var r3d = range_val * s_factor
				var has_terrain_exp = is_instance_valid(current_map.get("terrain_node")) and current_map.get("terrain_node") != null
				var h_lock = _sample_terrain_height(Vector2(locked_x, locked_y), current_map) if has_terrain_exp else 0.0

				var circle_blast_3d = Node3D.new()
				circle_blast_3d.name = "CircleBlast3D_" + enemy_id
				# Container a h_lock; disc conformante aporta eps 0.12 internamente
				circle_blast_3d.position = Vector3(locked_x * s_factor, h_lock + 0.02, locked_y * s_factor * correction_z)
				if not has_terrain_exp:
					circle_blast_3d.scale = Vector3(1.0, 1.0, correction_z)
				vp.add_child(circle_blast_3d)

				var flash = MeshInstance3D.new()
				var flash_s = SphereMesh.new()
				flash_s.radius = r3d * 0.3
				flash_s.height = r3d * 0.6
				flash.mesh = flash_s
				var flash_mat = StandardMaterial3D.new()
				flash_mat.albedo_color = Color(1.0, 0.6, 0.1, 0.9)
				flash_mat.emission_enabled = true
				flash_mat.emission = Color(1.0, 0.6, 0.1)
				flash_mat.emission_energy_multiplier = 8.0
				flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				flash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				flash.material_override = flash_mat
				flash.position = Vector3(0, 1.5, 0)
				circle_blast_3d.add_child(flash)
				var tw_f = flash.create_tween()
				tw_f.tween_property(flash, "scale", Vector3(3.5, 3.5, 3.5), 0.3)
				tw_f.parallel().tween_property(flash_mat, "albedo_color:a", 0.0, 0.3)
				tw_f.parallel().tween_property(flash_mat, "emission_energy_multiplier", 0.0, 0.3)
				tw_f.finished.connect(flash.queue_free)

				var damage_area = MeshInstance3D.new()
				if has_terrain_exp:
					var disc_conforming = _make_circle_disc_conforming(Vector2(locked_x, locked_y), range_val, current_map)
					damage_area.mesh = disc_conforming
					damage_area.position = Vector3(0, -h_lock -0.15 + 0.12, 0) # compensar container ya en h_lock: mesh local baked con h relativo + eps
					# Como disc_conforming ya está bakeado con altura relativa al centro (h - h_center), y el container está en h_center,
					# posicionamos el mesh a 0,0,0 relativo y su Y ya trae el offset. Para evitar doble offset, usamos 0
					damage_area.position = Vector3(0, 0, 0)
				else:
					var area_mesh = CylinderMesh.new()
					area_mesh.top_radius = r3d
					area_mesh.bottom_radius = r3d
					area_mesh.height = 0.01
					damage_area.mesh = area_mesh
					damage_area.position = Vector3(0, 0.01, 0)
				var area_mat = StandardMaterial3D.new()
				area_mat.albedo_color = Color(1.0, 0.2, 0.0, 0.55)
				area_mat.emission_enabled = true
				area_mat.emission = Color(1.0, 0.3, 0.0)
				area_mat.emission_energy_multiplier = 3.0
				area_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				area_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				area_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				area_mat.no_depth_test = true
				area_mat.render_priority = 2
				damage_area.material_override = area_mat
				circle_blast_3d.add_child(damage_area)
				var tw_a = damage_area.create_tween().set_parallel(true)
				tw_a.tween_property(area_mat, "albedo_color:a", 0.0, 0.5).set_ease(Tween.EASE_IN)
				tw_a.tween_property(area_mat, "emission_energy_multiplier", 0.0, 0.5).set_ease(Tween.EASE_IN)
				tw_a.finished.connect(damage_area.queue_free)

				var shockwave = MeshInstance3D.new()
				var sw_mesh = TorusMesh.new()
				sw_mesh.inner_radius = r3d * 0.95
				sw_mesh.outer_radius = r3d * 1.05
				shockwave.mesh = sw_mesh
				var sw_mat = StandardMaterial3D.new()
				sw_mat.albedo_color = Color(1.0, 0.4, 0.05, 0.9)
				sw_mat.emission_enabled = true
				sw_mat.emission = Color(1.0, 0.4, 0.05)
				sw_mat.emission_energy_multiplier = 5.0
				sw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				sw_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				shockwave.material_override = sw_mat
				shockwave.position = Vector3(0, 0.02, 0)
				shockwave.rotation.x = PI / 2
				circle_blast_3d.add_child(shockwave)
				var tw_sw = shockwave.create_tween().set_parallel(true)
				tw_sw.tween_property(shockwave, "scale", Vector3(1.5, 1.5, 1.5), 0.4)
				tw_sw.tween_property(sw_mat, "albedo_color:a", 0.0, 0.4)
				tw_sw.tween_property(sw_mat, "emission_energy_multiplier", 0.0, 0.4)
				tw_sw.finished.connect(shockwave.queue_free)

				var exp_light = OmniLight3D.new()
				exp_light.light_color = Color(1.0, 0.4, 0.05)
				exp_light.light_energy = 15.0
				exp_light.omni_range = r3d * 2.0
				exp_light.position = Vector3(0, 1.5, 0)
				circle_blast_3d.add_child(exp_light)
				var tw_l = exp_light.create_tween()
				tw_l.tween_property(exp_light, "light_energy", 0.0, 0.4)
				
				# Limpiar el contenedor completo al finalizar el VFX
				var clean_all = func():
					if is_instance_valid(circle_blast_3d):
						circle_blast_3d.queue_free()
				tw_l.finished.connect(clean_all)

			active_areas.erase("blast_" + enemy_id)

		elif action == "ice_storm_charging":
			var range_val = float(data.get("range", 300.0))
			var target_x = float(data.get("targetX", 0.0))
			var target_y = float(data.get("targetY", 0.0))
			var _charge_dur = float(data.get("duration", 1500.0)) / 1000.0
			var _lock_dur = float(data.get("lockTimeMs", 500.0)) / 1000.0

			if is_3d_active:
				var s_factor = current_map.scale_factor if "scale_factor" in current_map else 0.02
				var correction_z = current_map.correction_z if "correction_z" in current_map else 1.41421356
				var vp = current_map.sub_viewport
				var outer_r3d = range_val * s_factor

				var circle_3d = Node3D.new()
				circle_3d.name = "IceStormCharging_" + enemy_id
				circle_3d.position = Vector3(target_x * s_factor, 0.0, target_y * s_factor * correction_z)
				# Escalar en Z global para la perspectiva isométrica 2.5D
				circle_3d.scale = Vector3(1.0, 1.0, correction_z)
				vp.add_child(circle_3d)

				var ground_disc = MeshInstance3D.new()
				var g_mesh = CylinderMesh.new()
				g_mesh.top_radius = outer_r3d
				g_mesh.bottom_radius = outer_r3d
				g_mesh.height = 0.01
				ground_disc.mesh = g_mesh
				var g_mat = StandardMaterial3D.new()
				g_mat.albedo_color = Color(0.4, 0.7, 1.0, 0.12)
				g_mat.emission_enabled = true
				g_mat.emission = Color(0.3, 0.6, 1.0)
				g_mat.emission_energy_multiplier = 0.4
				g_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				g_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				ground_disc.material_override = g_mat
				circle_3d.add_child(ground_disc)

				var ring = MeshInstance3D.new()
				var torus = TorusMesh.new()
				torus.inner_radius = outer_r3d * 0.96
				torus.outer_radius = outer_r3d
				ring.mesh = torus
				var r_mat = StandardMaterial3D.new()
				r_mat.albedo_color = Color(0.5, 0.8, 1.0, 0.5)
				r_mat.emission_enabled = true
				r_mat.emission = Color(0.3, 0.7, 1.0)
				r_mat.emission_energy_multiplier = 1.5
				r_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				r_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				ring.material_override = r_mat
				ring.position.y = 0.02
				ring.rotation.y = randf_range(0.0, TAU)
				circle_3d.add_child(ring)

		elif action == "ice_storm_deploy":
			var storm_x = float(data.get("x", en.global_position.x))
			var storm_y = float(data.get("y", en.global_position.y))
			var range_val = float(data.get("range", 300.0))
			var _storm_dur = float(data.get("duration", 5000.0)) / 1000.0

			if active_areas.has("icestorm_" + enemy_id): return

			if is_3d_active:
				var s_factor = current_map.scale_factor if "scale_factor" in current_map else 0.02
				var correction_z = current_map.correction_z if "correction_z" in current_map else 1.41421356
				var vp = current_map.sub_viewport

				# Limpiar el indicador de carga si aún existe
				var old_charge = vp.get_node_or_null("IceStormCharging_" + enemy_id)
				if is_instance_valid(old_charge):
					old_charge.queue_free()

				var r3d = range_val * s_factor

				var storm = Node3D.new()
				storm.name = "IceStorm_" + enemy_id
				storm.position = Vector3(storm_x * s_factor, 0.0, storm_y * s_factor * correction_z)
				# Escalar en Z global para la perspectiva isométrica 2.5D
				storm.scale = Vector3(1.0, 1.0, correction_z)
				vp.add_child(storm)
				active_areas["icestorm_" + enemy_id] = storm

				var ground = MeshInstance3D.new()
				var g_mesh = CylinderMesh.new()
				g_mesh.top_radius = r3d
				g_mesh.bottom_radius = r3d
				g_mesh.height = 0.02
				ground.mesh = g_mesh
				var g_mat = StandardMaterial3D.new()
				g_mat.albedo_color = Color(0.5, 0.8, 1.0, 0.2)
				g_mat.emission_enabled = true
				g_mat.emission = Color(0.3, 0.6, 1.0)
				g_mat.emission_energy_multiplier = 0.6
				g_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				g_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				ground.material_override = g_mat
				ground.position.y = 0.01
				storm.add_child(ground)

				var ring_outer = MeshInstance3D.new()
				var torus = TorusMesh.new()
				torus.inner_radius = r3d * 0.97
				torus.outer_radius = r3d
				ring_outer.mesh = torus
				var r_mat = StandardMaterial3D.new()
				r_mat.albedo_color = Color(0.6, 0.9, 1.0, 0.6)
				r_mat.emission_enabled = true
				r_mat.emission = Color(0.4, 0.7, 1.0)
				r_mat.emission_energy_multiplier = 2.0
				r_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				r_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				ring_outer.material_override = r_mat
				ring_outer.position.y = 0.03
				ring_outer.rotation.y = randf_range(0.0, TAU)
				storm.add_child(ring_outer)

				# Estalactitas de hielo cayendo (pinchos)
				var particles = GPUParticles3D.new()
				particles.amount = 30
				particles.lifetime = 2.0
				particles.one_shot = false
				particles.explosiveness = 0.3
				particles.randomness = 0.8
				particles.preprocess = 0.5
				particles.position.y = 2.0

				var spike_mesh = CylinderMesh.new()
				spike_mesh.top_radius = 0.08
				spike_mesh.bottom_radius = 0.0
				spike_mesh.height = 0.35
				var mesh_mat = StandardMaterial3D.new()
				mesh_mat.albedo_color = Color(0.7, 0.85, 1.0, 0.9)
				mesh_mat.emission_enabled = true
				mesh_mat.emission = Color(0.4, 0.7, 1.0)
				mesh_mat.emission_energy_multiplier = 0.3
				mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				spike_mesh.material = mesh_mat
				particles.draw_pass_1 = spike_mesh

				var pm = ParticleProcessMaterial.new()
				pm.direction = Vector3(0, -1, 0)
				pm.spread = 12.0
				pm.initial_velocity_min = 4.0
				pm.initial_velocity_max = 7.0
				pm.gravity = Vector3(0, -6.0, 0)
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
				pm.emission_sphere_radius = r3d * 0.85
				pm.scale_min = 0.4
				pm.scale_max = 1.0

				var grad = Gradient.new()
				grad.set_color(0, Color(0.7, 0.85, 1.0, 0.0))
				grad.add_point(0.15, Color(0.8, 0.9, 1.0, 0.9))
				grad.add_point(0.6, Color(0.9, 0.95, 1.0, 0.85))
				grad.set_color(grad.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))
				pm.color_ramp = GradientTexture1D.new()
				pm.color_ramp.gradient = grad

				particles.process_material = pm
				particles.scale = Vector3(r3d, r3d, r3d)
				storm.add_child(particles)
				particles.emitting = true

				# Entrada animada
				storm.scale = Vector3.ZERO
				var entry_tw = create_tween().set_parallel(true)
				entry_tw.tween_property(storm, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

		elif action == "ice_storm_expire":
			if active_areas.has("icestorm_" + enemy_id):
				var storm = active_areas["icestorm_" + enemy_id]
				if is_instance_valid(storm):
					var fade_tw = create_tween().set_parallel(true)
					fade_tw.tween_property(storm, "scale", Vector3.ZERO, 0.3)
					fade_tw.finished.connect(storm.queue_free)
				active_areas.erase("icestorm_" + enemy_id)

		elif action == "worm_volley":
			var worms = data.get("worms", [])
			if not worms is Array or worms.size() == 0:
				return
			var worm_script = load("res://scripts/systems/WormVisual.gd")
			if not worm_script:
				return
			for w in worms:
				var worm_node = Node2D.new()
				worm_node.set_script(worm_script)
				worm_node.name = "Worm_" + enemy_id + "_" + str(w.get("id", randi()))
				worm_node.z_index = 6
				worm_node.set_as_top_level(true)
				if is_instance_valid(world) and is_instance_valid(world.entities_node):
					world.entities_node.add_child(worm_node)
				else:
					add_child(worm_node)
				if worm_node.has_method("setup"):
					worm_node.setup(w, current_map, en)

		elif action == "melee_charging" or action == "melee_slash":
			var melee_script = load("res://scripts/systems/MeleeSlashVisual.gd")
			if melee_script:
				var melee_node := Node2D.new()
				melee_node.set_script(melee_script)
				melee_node.name = "MeleeSlash_" + enemy_id + "_" + str(data.get("mId","")) + "_" + action
				melee_node.z_index = 7
				melee_node.set_as_top_level(true)
				if is_instance_valid(world) and is_instance_valid(world.entities_node):
					world.entities_node.add_child(melee_node)
				else:
					add_child(melee_node)
				if melee_node.has_method("setup"):
					melee_node.setup(data, current_map, en)

		elif action == "wind_charging":
			var wall_id := str(data.get("wallId", enemy_id))
			if active_wind_walls.has(wall_id) and is_instance_valid(active_wind_walls[wall_id]):
				active_wind_walls[wall_id].queue_free()
				active_wind_walls.erase(wall_id)

			var wall_script = load("res://scripts/systems/WindWallVisual.gd")
			if not wall_script:
				return
			var charge_data = data.duplicate()
			charge_data["mode"] = "charge"
			var wall_node := Node2D.new()
			wall_node.set_script(wall_script)
			wall_node.name = "WindWall_" + enemy_id + "_" + wall_id
			wall_node.z_index = 6
			wall_node.set_as_top_level(true)
			if is_instance_valid(world) and is_instance_valid(world.entities_node):
				world.entities_node.add_child(wall_node)
			else:
				add_child(wall_node)
			if wall_node.has_method("setup"):
				wall_node.setup(charge_data, current_map, en)
			active_wind_walls[wall_id] = wall_node

		elif action == "wind_fire":
			var wall_id := str(data.get("wallId", enemy_id))
			if active_wind_walls.has(wall_id) and is_instance_valid(active_wind_walls[wall_id]):
				active_wind_walls[wall_id].launch()
				active_wind_walls.erase(wall_id)
				return
			# Fallback: si no había pared en carga (evento perdido), se crea ya en movimiento
			var wall_script = load("res://scripts/systems/WindWallVisual.gd")
			if not wall_script:
				return
			var wall_node := Node2D.new()
			wall_node.set_script(wall_script)
			wall_node.name = "WindWall_" + enemy_id + "_" + wall_id
			wall_node.z_index = 6
			wall_node.set_as_top_level(true)
			if is_instance_valid(world) and is_instance_valid(world.entities_node):
				world.entities_node.add_child(wall_node)
			else:
				add_child(wall_node)
			if wall_node.has_method("setup"):
				wall_node.setup(data, current_map, en)

		elif action == "mech_interrupt":
			# v400.600: El enemigo se hundió y canceló sus canalizaciones en curso.
			# Limpiar todos los indicadores/casts de carga de este enemigo de una vez.
			if is_instance_valid(en):
				en.set_meta("is_locked", false)
				for child in en.get_children():
					if child.has_meta("is_laser_indicator"):
						en.remove_child(child)
						child.queue_free()
				if is_instance_valid(en.get("world_root_3d")):
					for n in ["Cone3D_" + enemy_id, "Circle3D_" + enemy_id]:
						var tgt = en.world_root_3d.get_node_or_null(n)
						if is_instance_valid(tgt):
							tgt.queue_free()

			var current_map_interrupt = get_tree().get_first_node_in_group("map")
			var interrupt_3d = is_instance_valid(current_map_interrupt) and current_map_interrupt.get("sub_viewport") != null and is_instance_valid(en.get("world_root_3d"))
			if interrupt_3d:
				for n in ["LaserIndicator3D_" + enemy_id, "IceStormCharging_" + enemy_id]:
					var old_vp_node = current_map_interrupt.sub_viewport.get_node_or_null(n)
					if is_instance_valid(old_vp_node):
						old_vp_node.queue_free()

			if active_laser_tracking.has(enemy_id):
				var lt_data = active_laser_tracking[enemy_id]
				var lt_3d = lt_data.get("indicator_3d")
				if is_instance_valid(lt_3d): lt_3d.queue_free()
				active_laser_tracking.erase(enemy_id)

			var containers := [en]
			if is_instance_valid(world) and is_instance_valid(world.entities_node):
				containers.append(world.entities_node)
			for ind_name in ["ConeIndicator_" + enemy_id, "CircleIndicator_" + enemy_id]:
				for container in containers:
					if not is_instance_valid(container):
						continue
					var ind = container.get_node_or_null(ind_name)
					if is_instance_valid(ind):
						ind.queue_free()
				active_areas.erase(ind_name)

			# Limpiar paredes de viento en fase de carga de este enemigo
			var wind_keys_to_free := []
			for wkey in active_wind_walls.keys():
				if str(wkey).begins_with(str(enemy_id)):
					wind_keys_to_free.append(wkey)
			for wkey in wind_keys_to_free:
				if is_instance_valid(active_wind_walls[wkey]):
					active_wind_walls[wkey].queue_free()
				active_wind_walls.erase(wkey)

		elif action == "burrow_dive":
			# v400.60: Zambullida Telúrica - el enemigo se hunde, empieza la grieta
			var burrow_id: String = "burrow_" + enemy_id
			if active_areas.has(burrow_id) and is_instance_valid(active_areas[burrow_id]):
				active_areas[burrow_id].queue_free()
				active_areas.erase(burrow_id)

			var dive_s := float(data.get("duration", 1000.0)) / 1000.0
			if en.has_method("play_burrow_dive"):
				en.play_burrow_dive(dive_s)

			var burrow_script = load("res://scripts/systems/BurrowVisual.gd")
			if not burrow_script:
				return
			var dive_data = data.duplicate()
			var burrow_node := Node2D.new()
			burrow_node.set_script(burrow_script)
			burrow_node.name = "Burrow_" + enemy_id
			burrow_node.z_index = 6
			burrow_node.set_as_top_level(true)
			burrow_node.global_position = en.global_position
			if is_instance_valid(world) and is_instance_valid(world.entities_node):
				world.entities_node.add_child(burrow_node)
			else:
				add_child(burrow_node)
			if burrow_node.has_method("setup"):
				burrow_node.setup(dive_data, current_map, en)
			active_areas[burrow_id] = burrow_node

		elif action == "burrow_travel":
			# El enemigo ya viaja oculto; la grieta avanza hacia el target
			var burrow_id: String = "burrow_" + enemy_id
			if active_areas.has(burrow_id) and is_instance_valid(active_areas[burrow_id]):
				if active_areas[burrow_id].has_method("launch_travel"):
					active_areas[burrow_id].launch_travel(data)

		elif action == "burrow_warn":
			# Círculo de aviso en el piso: el enemigo sigue oculto bajo tierra
			var burrow_id: String = "burrow_" + enemy_id
			if active_areas.has(burrow_id) and is_instance_valid(active_areas[burrow_id]):
				if active_areas[burrow_id].has_method("warn_now"):
					active_areas[burrow_id].warn_now(data)
			else:
				# Fallback: crear el visual para mostrar el aviso aunque falte el dive
				var burrow_script = load("res://scripts/systems/BurrowVisual.gd")
				if not burrow_script:
					return
				var burrow_node := Node2D.new()
				burrow_node.set_script(burrow_script)
				burrow_node.name = "Burrow_" + enemy_id
				burrow_node.z_index = 6
				burrow_node.set_as_top_level(true)
				burrow_node.global_position = en.global_position
				if is_instance_valid(world) and is_instance_valid(world.entities_node):
					world.entities_node.add_child(burrow_node)
				else:
					add_child(burrow_node)
				if burrow_node.has_method("setup"):
					burrow_node.setup(data, current_map, en)
				if burrow_node.has_method("warn_now"):
					burrow_node.warn_now(data)
				active_areas[burrow_id] = burrow_node

		elif action == "burrow_emerge":
			# Rompimiento del suelo + círculo de daño
			if en.has_method("play_burrow_emerge"):
				en.play_burrow_emerge()
			var burrow_id: String = "burrow_" + enemy_id
			if active_areas.has(burrow_id) and is_instance_valid(active_areas[burrow_id]):
				if active_areas[burrow_id].has_method("burst_now"):
					active_areas[burrow_id].burst_now(data)
			else:
				# Fallback: evento perdido, crear zona directamente
				var burrow_script = load("res://scripts/systems/BurrowVisual.gd")
				if not burrow_script:
					return
				var burrow_node := Node2D.new()
				burrow_node.set_script(burrow_script)
				burrow_node.name = "Burrow_" + enemy_id
				burrow_node.z_index = 6
				burrow_node.set_as_top_level(true)
				burrow_node.global_position = en.global_position
				if is_instance_valid(world) and is_instance_valid(world.entities_node):
					world.entities_node.add_child(burrow_node)
				else:
					add_child(burrow_node)
				if burrow_node.has_method("setup"):
					burrow_node.setup(data, current_map, en)
				if burrow_node.has_method("burst_now"):
					burrow_node.burst_now(data)
				active_areas[burrow_id] = burrow_node

		elif action == "burrow_zone_end":
			var burrow_id: String = "burrow_" + enemy_id
			if active_areas.has(burrow_id) and is_instance_valid(active_areas[burrow_id]):
				active_areas[burrow_id].end_zone()
				active_areas[burrow_id].queue_free()
				active_areas.erase(burrow_id)

func _handle_shield_steal_action(data: Dictionary):
	var action = data.get("action", "")
	var enemy_id = str(data.get("id", ""))
	var t_id = str(data.get("targetId", ""))
	var steal_id: String = "steal_" + enemy_id

	if action == "shield_steal_start":
		if active_areas.has(steal_id) and is_instance_valid(active_areas[steal_id]):
			active_areas[steal_id].queue_free()
			active_areas.erase(steal_id)

		var steal_script = load("res://scripts/systems/ShieldLinkVisual.gd")
		if not steal_script:
			return
		var steal_node := Node2D.new()
		steal_node.set_script(steal_script)
		steal_node.name = "ShieldSteal_" + enemy_id
		steal_node.z_index = 20
		steal_node.z_as_relative = false
		steal_node.set_as_top_level(true)
		steal_node.set_meta("targetId", t_id)
		if is_instance_valid(world) and is_instance_valid(world.entities_node):
			world.entities_node.add_child(steal_node)
		else:
			add_child(steal_node)
		if steal_node.has_method("setup"):
			var en = enemies.get(enemy_id) if enemies.has(enemy_id) else null
			steal_node.setup(data, en)
		active_areas[steal_id] = steal_node

	elif action == "shield_steal_tick":
		if active_areas.has(steal_id) and is_instance_valid(active_areas[steal_id]):
			var sn = active_areas[steal_id]
			if sn.has_method("update_enemy_position") and data.has("ex") and data.has("ey"):
				sn.update_enemy_position(data.get("ex", 0.0), data.get("ey", 0.0))
			if sn.has_method("update_tick_flash"):
				sn.update_tick_flash()

		# --- EFECTO 3D: Aros de escudo viajando del jugador al enemigo en tiempo real ---
		var current_map = get_tree().get_first_node_in_group("map")
		var has_3d = is_instance_valid(current_map) and current_map.get("sub_viewport") != null and is_instance_valid(current_map.sub_viewport)
		if has_3d:
			var s_factor: float = current_map.scale_factor if "scale_factor" in current_map else 0.02
			var corr_z: float = current_map.correction_z if "correction_z" in current_map else 1.41421356
			var vp: SubViewport = current_map.sub_viewport

			# Identificar origen (jugador) y enemigo
			var ex: float = float(data.get("ex", 0.0))
			var ey: float = float(data.get("ey", 0.0))
			var enemy_pos3d = Vector3(ex * s_factor, 0.5, ey * s_factor * corr_z)

			var player_pos3d: Vector3 = enemy_pos3d
			var player_node: Node2D = null
			if is_instance_valid(world) and is_instance_valid(world.local_player) and str(world.local_player.get("entity_id")) == t_id:
				player_node = world.local_player
			elif remote_players.has(t_id):
				player_node = remote_players[t_id]
			if is_instance_valid(player_node):
				player_pos3d = Vector3(
					player_node.global_position.x * s_factor,
					0.5,
					player_node.global_position.y * s_factor * corr_z
				)

			var enemy_node: Node2D = enemies.get(enemy_id) if enemies.has(enemy_id) else null

			# Crear nodo del efecto con script de seguimiento precompilado
			var orb_root = FOLLOW_ORB_3D_SCRIPT.new()
			vp.add_child(orb_root)
			orb_root.setup(enemy_node, player_pos3d, s_factor, corr_z, 9.0, 0.65, true)

			# --- ARO PRINCIPAL (Torus celeste brillante - Más chico y parado) ---
			var ring1 = MeshInstance3D.new()
			var torus1 = TorusMesh.new()
			torus1.inner_radius = 0.15
			torus1.outer_radius = 0.22
			ring1.mesh = torus1
			ring1.rotation_degrees.x = 90
			var mat1 = StandardMaterial3D.new()
			mat1.albedo_color = Color(0.0, 0.75, 1.0, 0.8)
			mat1.emission_enabled = true
			mat1.emission = Color(0.0, 0.8, 1.0)
			mat1.emission_energy_multiplier = 3.5
			mat1.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat1.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ring1.material_override = mat1
			orb_root.add_child(ring1)

			# --- ARO SECUNDARIO INTERNO (Blanco de alta energía - Más chico y parado) ---
			var ring2 = MeshInstance3D.new()
			var torus2 = TorusMesh.new()
			torus2.inner_radius = 0.17
			torus2.outer_radius = 0.20
			ring2.mesh = torus2
			ring2.rotation_degrees.x = 90
			var mat2 = StandardMaterial3D.new()
			mat2.albedo_color = Color(1.0, 1.0, 1.0, 0.95)
			mat2.emission_enabled = true
			mat2.emission = Color(0.5, 0.9, 1.0)
			mat2.emission_energy_multiplier = 4.5
			mat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ring2.material_override = mat2
			orb_root.add_child(ring2)

			# --- ARO AURA DIFUSO EXTERIOR (Más chico y parado) ---
			var ring3 = MeshInstance3D.new()
			var torus3 = TorusMesh.new()
			torus3.inner_radius = 0.10
			torus3.outer_radius = 0.27
			ring3.mesh = torus3
			ring3.rotation_degrees.x = 90
			var mat3 = StandardMaterial3D.new()
			mat3.albedo_color = Color(0.0, 0.5, 1.0, 0.25)
			mat3.emission_enabled = true
			mat3.emission = Color(0.0, 0.4, 1.0)
			mat3.emission_energy_multiplier = 1.5
			mat3.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat3.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ring3.material_override = mat3
			orb_root.add_child(ring3)

			# --- Luz del orbe para dar ambiente ---
			var orb_light = OmniLight3D.new()
			orb_light.light_color = Color(0.0, 0.8, 1.0)
			orb_light.light_energy = 1.5
			orb_light.omni_range = 3.0
			orb_root.add_child(orb_light)

			# Rotación continua del conjunto en el eje Z (giro de espiral alineado)
			var tw_rot = ring1.create_tween().set_loops()
			tw_rot.tween_property(ring1, "rotation_degrees:z", 360.0, 0.5).set_trans(Tween.TRANS_LINEAR)
			var tw_rot2 = ring3.create_tween().set_loops()
			tw_rot2.tween_property(ring3, "rotation_degrees:z", -360.0, 0.7).set_trans(Tween.TRANS_LINEAR)

	elif action == "shield_steal_end":
		if active_areas.has(steal_id) and is_instance_valid(active_areas[steal_id]):
			active_areas[steal_id].queue_free()
			active_areas.erase(steal_id)


# v412: ROBADOR DE VIDA (life_steal) - Igual que shield_steal pero roba VIDA.
# Los aros que viajan del jugador al enemigo son VERDES (color vida).
func _handle_life_steal_action(data: Dictionary):
	var action = data.get("action", "")
	var enemy_id = str(data.get("id", ""))
	var t_id = str(data.get("targetId", ""))
	var steal_id: String = "lifesteal_" + enemy_id

	if action == "life_steal_start":
		if active_areas.has(steal_id) and is_instance_valid(active_areas[steal_id]):
			active_areas[steal_id].queue_free()
			active_areas.erase(steal_id)

		var steal_script = load("res://scripts/systems/ShieldLinkVisual.gd")
		if not steal_script:
			return
		var steal_node := Node2D.new()
		steal_node.set_script(steal_script)
		steal_node.name = "LifeSteal_" + enemy_id
		steal_node.z_index = 20
		steal_node.z_as_relative = false
		steal_node.set_as_top_level(true)
		steal_node.set_meta("targetId", t_id)
		if is_instance_valid(world) and is_instance_valid(world.entities_node):
			world.entities_node.add_child(steal_node)
		else:
			add_child(steal_node)
		if steal_node.has_method("setup"):
			var en = enemies.get(enemy_id) if enemies.has(enemy_id) else null
			steal_node.setup(data, en)
		active_areas[steal_id] = steal_node

	elif action == "life_steal_tick":
		if active_areas.has(steal_id) and is_instance_valid(active_areas[steal_id]):
			var sn = active_areas[steal_id]
			if sn.has_method("update_enemy_position") and data.has("ex") and data.has("ey"):
				sn.update_enemy_position(data.get("ex", 0.0), data.get("ey", 0.0))
			if sn.has_method("update_tick_flash"):
				sn.update_tick_flash()

		# --- EFECTO 3D: Aros de vida (verdes) viajando del jugador al enemigo en tiempo real ---
		var current_map = get_tree().get_first_node_in_group("map")
		var has_3d = is_instance_valid(current_map) and current_map.get("sub_viewport") != null and is_instance_valid(current_map.sub_viewport)
		if has_3d:
			var s_factor: float = current_map.scale_factor if "scale_factor" in current_map else 0.02
			var corr_z: float = current_map.correction_z if "correction_z" in current_map else 1.41421356
			var vp: SubViewport = current_map.sub_viewport

			# Identificar origen (jugador) y enemigo
			var ex: float = float(data.get("ex", 0.0))
			var ey: float = float(data.get("ey", 0.0))
			var enemy_pos3d = Vector3(ex * s_factor, 0.5, ey * s_factor * corr_z)

			var player_pos3d: Vector3 = enemy_pos3d
			var player_node: Node2D = null
			if is_instance_valid(world) and is_instance_valid(world.local_player) and str(world.local_player.get("entity_id")) == t_id:
				player_node = world.local_player
			elif remote_players.has(t_id):
				player_node = remote_players[t_id]
			if is_instance_valid(player_node):
				player_pos3d = Vector3(
					player_node.global_position.x * s_factor,
					0.5,
					player_node.global_position.y * s_factor * corr_z
				)

			var enemy_node: Node2D = enemies.get(enemy_id) if enemies.has(enemy_id) else null

			# Crear nodo del efecto con script de seguimiento precompilado
			var orb_root = FOLLOW_ORB_3D_SCRIPT.new()
			vp.add_child(orb_root)
			orb_root.setup(enemy_node, player_pos3d, s_factor, corr_z, 9.0, 0.65, true)

			# --- ARO PRINCIPAL (Torus verde brillante - Más chico y parado) ---
			var ring1 = MeshInstance3D.new()
			var torus1 = TorusMesh.new()
			torus1.inner_radius = 0.15
			torus1.outer_radius = 0.22
			ring1.mesh = torus1
			ring1.rotation_degrees.x = 90
			var mat1 = StandardMaterial3D.new()
			mat1.albedo_color = Color(0.1, 0.95, 0.35, 0.8)
			mat1.emission_enabled = true
			mat1.emission = Color(0.2, 1.0, 0.3)
			mat1.emission_energy_multiplier = 3.5
			mat1.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat1.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ring1.material_override = mat1
			orb_root.add_child(ring1)

			# --- ARO SECUNDARIO INTERNO (Blanco de alta energía - Más chico y parado) ---
			var ring2 = MeshInstance3D.new()
			var torus2 = TorusMesh.new()
			torus2.inner_radius = 0.17
			torus2.outer_radius = 0.20
			ring2.mesh = torus2
			ring2.rotation_degrees.x = 90
			var mat2 = StandardMaterial3D.new()
			mat2.albedo_color = Color(1.0, 1.0, 1.0, 0.95)
			mat2.emission_enabled = true
			mat2.emission = Color(0.6, 1.0, 0.7)
			mat2.emission_energy_multiplier = 4.5
			mat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ring2.material_override = mat2
			orb_root.add_child(ring2)

			# --- ARO AURA DIFUSO EXTERIOR (Más chico y parado) ---
			var ring3 = MeshInstance3D.new()
			var torus3 = TorusMesh.new()
			torus3.inner_radius = 0.10
			torus3.outer_radius = 0.27
			ring3.mesh = torus3
			ring3.rotation_degrees.x = 90
			var mat3 = StandardMaterial3D.new()
			mat3.albedo_color = Color(0.05, 0.6, 0.2, 0.25)
			mat3.emission_enabled = true
			mat3.emission = Color(0.1, 0.7, 0.25)
			mat3.emission_energy_multiplier = 1.5
			mat3.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat3.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ring3.material_override = mat3
			orb_root.add_child(ring3)

			# --- Luz del orbe para dar ambiente ---
			var orb_light = OmniLight3D.new()
			orb_light.light_color = Color(0.2, 1.0, 0.3)
			orb_light.light_energy = 1.5
			orb_light.omni_range = 3.0
			orb_root.add_child(orb_light)

			# Rotación continua del conjunto en el eje Z (giro de espiral alineado)
			var tw_rot = ring1.create_tween().set_loops()
			tw_rot.tween_property(ring1, "rotation_degrees:z", 360.0, 0.5).set_trans(Tween.TRANS_LINEAR)
			var tw_rot2 = ring3.create_tween().set_loops()
			tw_rot2.tween_property(ring3, "rotation_degrees:z", -360.0, 0.7).set_trans(Tween.TRANS_LINEAR)

	elif action == "life_steal_end":
		if active_areas.has(steal_id) and is_instance_valid(active_areas[steal_id]):
			active_areas[steal_id].queue_free()
			active_areas.erase(steal_id)


# v413: SUEÑO INDUCIDO - Orbe de sueño 3D que vuela del enemigo al jugador.
# El efecto (slow + stun) lo aplica el servidor al instante; este orbe es el
# feedback visual de que te "tiraron" algo.
func _handle_sleep_action(data: Dictionary):
	var action = str(data.get("action", ""))
	if action != "sleep_cast":
		return
	var enemy_id = str(data.get("id", ""))
	var targets = data.get("targets", [])
	if typeof(targets) != TYPE_ARRAY or targets.size() == 0:
		return

	var ex = float(data.get("ex", 0.0))
	var ey = float(data.get("ey", 0.0))

	var current_map = get_tree().get_first_node_in_group("map")
	if not is_instance_valid(current_map) or current_map.get("sub_viewport") == null:
		return
	var s_factor: float = current_map.scale_factor if "scale_factor" in current_map else 0.02
	var corr_z: float = current_map.correction_z if "correction_z" in current_map else 1.41421356
	var vp: SubViewport = current_map.sub_viewport

	var enemy_node: Node2D = enemies.get(enemy_id) if enemies.has(enemy_id) else null
	var start_pos: Vector2 = Vector2(ex, ey)
	if is_instance_valid(enemy_node):
		start_pos = enemy_node.global_position

	for t_id in targets:
		t_id = str(t_id)
		var player_node: Node2D = null
		if is_instance_valid(world) and is_instance_valid(world.local_player) and str(world.local_player.get("entity_id")) == t_id:
			player_node = world.local_player
		elif remote_players.has(t_id):
			player_node = remote_players[t_id]
		if not is_instance_valid(player_node):
			continue

		var start3d = Vector3(start_pos.x * s_factor, 0.8, start_pos.y * s_factor * corr_z)

		# Orbe de seguimiento precompilado: el orbe sigue al jugador hasta alcanzarlo y desaparece
		var orb_root = FOLLOW_ORB_3D_SCRIPT.new()
		orb_root.name = "SleepOrb3D_" + enemy_id + "_" + t_id
		vp.add_child(orb_root)
		orb_root.setup(player_node, start3d, s_factor, corr_z, 15.0, 0.85, false)

		# Núcleo violeta brillante
		var core = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = 0.25
		sphere.height = 0.5
		core.mesh = sphere
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.45, 1.0, 0.9)
		mat.emission_enabled = true
		mat.emission = Color(0.7, 0.3, 1.0)
		mat.emission_energy_multiplier = 4.0
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		core.material_override = mat
		orb_root.add_child(core)

		# Anillo de energía giratorio
		var ring = MeshInstance3D.new()
		var torus = TorusMesh.new()
		torus.inner_radius = 0.32
		torus.outer_radius = 0.4
		ring.mesh = torus
		var ring_mat = StandardMaterial3D.new()
		ring_mat.albedo_color = Color(1.0, 0.75, 1.0, 0.9)
		ring_mat.emission_enabled = true
		ring_mat.emission = Color(1.0, 0.6, 1.0)
		ring_mat.emission_energy_multiplier = 3.0
		ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring.material_override = ring_mat
		ring.rotation_degrees.x = 90
		orb_root.add_child(ring)

		var tw_rot = ring.create_tween().set_loops()
		tw_rot.tween_property(ring, "rotation_degrees:z", 360.0, 0.6).set_trans(Tween.TRANS_LINEAR)

		# Luz violeta que ilumina el trayecto
		var light = OmniLight3D.new()
		light.light_color = Color(0.75, 0.4, 1.0)
		light.light_energy = 1.8
		light.omni_range = 3.5
		orb_root.add_child(light)

		# Puff violeta al llegar al jugador (timing aproximado al vuelo del orbe)
		var puff = CPUParticles2D.new()
		puff.amount = 22
		puff.lifetime = 0.5
		puff.one_shot = true
		puff.explosiveness = 1.0
		puff.spread = 180.0
		puff.gravity = Vector2.ZERO
		puff.initial_velocity_min = 60.0
		puff.initial_velocity_max = 140.0
		puff.scale_amount_min = 2.0
		puff.scale_amount_max = 4.0
		var puff_grad = Gradient.new()
		puff_grad.set_color(0, Color(0.9, 0.6, 1.0, 0.9))
		puff_grad.add_point(0.5, Color(0.7, 0.3, 1.0, 0.7))
		puff_grad.set_color(1, Color(0.4, 0.1, 0.7, 0.0))
		puff.color_ramp = puff_grad
		if is_instance_valid(world) and is_instance_valid(world.entities_node):
			world.entities_node.add_child(puff)
			puff.global_position = player_node.global_position
			puff.emitting = true
			get_tree().create_timer(0.55).timeout.connect(puff.queue_free)


# v413: EJECUCIÓN DIRECTA - Marcador de calavera sobre los objetivos (telegrafo).
# death_cast_start: crea un mark 3D (calavera giratoria) sobre cada target.
# death_cast_end: destruye todos los marks activos de este enemy_id.
func _handle_death_mark_action(data: Dictionary):
	var action = str(data.get("action", ""))
	var enemy_id = str(data.get("id", ""))
	var targets = data.get("targets", [])
	if typeof(targets) != TYPE_ARRAY:
		targets = []

	var current_map = get_tree().get_first_node_in_group("map")
	if not is_instance_valid(current_map) or current_map.get("sub_viewport") == null:
		return
	var s_factor: float = current_map.scale_factor if "scale_factor" in current_map else 0.02
	var corr_z: float = current_map.correction_z if "correction_z" in current_map else 1.41421356
	var vp: SubViewport = current_map.sub_viewport

	if not is_instance_valid(world):
		return

	if action == "death_cast_end":
		for t_id in death_marks.keys():
			var entry = death_marks[t_id]
			if entry.enemy_id == enemy_id and is_instance_valid(entry.node):
				entry.node.queue_free()
		death_marks.erase(enemy_id)
		return

	if action != "death_cast_start":
		return

	var cast_time_ms = float(data.get("castTimeMs", 1200.0))
	var cast_time_s = cast_time_ms / 1000.0

	for t_id in targets:
		t_id = str(t_id)
		var player_node: Node2D = null
		if is_instance_valid(world.local_player) and str(world.local_player.get("entity_id")) == t_id:
			player_node = world.local_player
		elif remote_players.has(t_id):
			player_node = remote_players[t_id]
		if not is_instance_valid(player_node):
			continue

		var mark_key = enemy_id + "_" + t_id
		if death_marks.has(mark_key) and is_instance_valid(death_marks[mark_key].node):
			death_marks[mark_key].node.queue_free()
			death_marks.erase(mark_key)

		var mark_root = Node3D.new()
		mark_root.name = "ExecutionMark3D_" + mark_key
		var pos3d = Vector3.ZERO
		if is_instance_valid(world.entities_node) and world.entities_node.get("world_root_3d") != null:
			pos3d = world.entities_node.world_root_3d.position
		else:
			pos3d = Vector3(player_node.global_position.x * s_factor, 0.2, player_node.global_position.y * s_factor * corr_z)
		mark_root.global_position = pos3d
		vp.add_child(mark_root)

		# Calavera flotante (esfera hueso) con aro rojo giratorio (estilo meteor summon circle)
		var skull = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = 0.22
		sphere.height = 0.44
		skull.mesh = sphere
		var sk_mat = StandardMaterial3D.new()
		sk_mat.albedo_color = Color(0.78, 0.74, 0.70, 0.85)
		sk_mat.emission_enabled = true
		sk_mat.emission = Color(0.9, 0.4, 0.35)
		sk_mat.emission_energy_multiplier = 2.2
		sk_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sk_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		skull.material_override = sk_mat
		mark_root.add_child(skull)

		# Aro rojo giratorio
		var ring = MeshInstance3D.new()
		var torus = TorusMesh.new()
		torus.inner_radius = 0.32
		torus.outer_radius = 0.40
		ring.mesh = torus
		var ring_mat = StandardMaterial3D.new()
		ring_mat.albedo_color = Color(1.0, 0.22, 0.12, 0.82)
		ring_mat.emission_enabled = true
		ring_mat.emission = Color(1.0, 0.2, 0.12)
		ring_mat.emission_energy_multiplier = 3.0
		ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring.material_override = ring_mat
		ring.rotation_degrees.x = 90
		mark_root.add_child(ring)

		var tw_rot = ring.create_tween().set_loops()
		tw_rot.tween_property(ring, "rotation_degrees:z", 360.0, 0.55).set_trans(Tween.TRANS_LINEAR)

		# Luz roja
		var light = OmniLight3D.new()
		light.light_color = Color(1.0, 0.25, 0.12)
		light.light_energy = 1.5
		light.omni_range = 3.5
		mark_root.add_child(light)

		# Animación de pulso / fade para indicar tiempo de casteo
		var pulse = mark_root.create_tween()
		pulse.set_loops()
		pulse.tween_property(skull, "scale", Vector3(0.26, 1.0, 0.26), 0.35).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(skull, "scale", Vector3(0.22, 0.22, 0.22), 0.35).set_trans(Tween.TRANS_SINE)

		# Auto-eliminarse al expirar el cast (o al recibir death_cast_end)
		mark_root.create_tween().tween_interval(cast_time_s).tween_callback(mark_root.queue_free)

		death_marks[mark_key] = { "enemy_id": enemy_id, "node": mark_root, "target_id": t_id }

		# Actualizar posición del mark para seguir al jugador mientras dura el cast
		var tracker = func():
			if is_instance_valid(player_node) and is_instance_valid(mark_root):
				var follow3d = Vector3.ZERO
				if is_instance_valid(world.entities_node) and world.entities_node.get("world_root_3d") != null:
					var base3d = world.entities_node.world_root_3d
					follow3d = base3d.global_position + Vector3(player_node.global_position.x * s_factor, 0.35, player_node.global_position.y * s_factor * corr_z)
				else:
					follow3d = Vector3(player_node.global_position.x * s_factor, 0.35, player_node.global_position.y * s_factor * corr_z)
				mark_root.global_position = follow3d
		mark_root.set_process(true)
		mark_root._process = tracker


# v414: ASCENSIÓN TELÚRICA - el enemigo salta por los aires y aterriza sobre el área marcada.
# ascension_cast: el enemigo se agacha/prepara (sin telegrafo en el piso, la advertencia real es el vuelo + área).
# ascension_leap: el enemigo vuela en arco hasta el destino + aparece el área de caída.
# ascension_impact: el enemigo aterriza + explosión en el área (daño ya aplicado en servidor).
func _handle_ascension_action(data: Dictionary):
	var action = str(data.get("action", ""))
	var map_node = get_tree().get_first_node_in_group("map")
	if not is_instance_valid(map_node) or map_node.get("sub_viewport") == null:
		return
	var s_factor: float = map_node.scale_factor if "scale_factor" in map_node else 0.02
	var correction_z: float = map_node.correction_z if "correction_z" in map_node else 1.41421356
	var vp: SubViewport = map_node.sub_viewport
	var enemy_id = str(data.get("id", ""))
	var enemy_node = enemies.get(enemy_id) if enemies.has(enemy_id) else null

	if action == "ascension_cast":
		# No se dibuja nada ahora: el tell de la mecánica es el propio salto + el área de caída.
		return

	if action == "ascension_leap":
		var air_s = float(data.get("airTimeMs", 2000)) / 1000.0
		var warn_delay_s = float(data.get("warnDelayMs", 0)) / 1000.0
		var warn_s = float(data.get("warnTimeMs", air_s * 1000.0)) / 1000.0
		var radius = float(data.get("radius", 250))
		var sx = float(data.get("startX", 0.0))
		var sy = float(data.get("startY", 0.0))
		var ex = float(data.get("endX", sx))
		var ey = float(data.get("endY", sy))

		# Si ya hay un salto activo de este enemigo (varios targets), retargetear
		_ascension_clear_jump(enemy_id)

		if is_instance_valid(enemy_node):
			# La posición horizontal la conduce la sync del servidor (el enemigo vuela al
			# destino por su cuenta); aquí solo se anima la elevación vertical del asset.
			var dist = Vector2(sx, sy).distance_to(Vector2(ex, ey))
			var peak_h = clampf(6.0 + dist * 0.008, 6.0, 10.0)
			var tw_offs = enemy_node.create_tween()
			tw_offs.tween_property(enemy_node, "_ascension_y_offset", peak_h, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			# La caída la dispara ascension_impact; aquí solo se queda en el aire
			active_ascensions[enemy_id] = {"node": enemy_node, "tw_pos": null, "tw_offs": tw_offs, "warn_timer": null}

		# Cuando termina de targetear se marca el área de caída en el piso (warnDelayMs=0 por defecto).
		# El círculo queda marcado (pulsando) al menos hasta el impacto.
		var circle_dur_s = max(warn_s, air_s + 0.35)
		var warn_timer = create_tween()
		warn_timer.tween_interval(warn_delay_s)
		warn_timer.tween_callback(func():
			_spawn_ascension_warn_3d(vp, ex, ey, radius, circle_dur_s, s_factor, correction_z)
		)
		return

	if action == "ascension_impact":
		var tx = float(data.get("x", 0.0))
		var ty = float(data.get("y", 0.0))
		var radius = float(data.get("radius", 250))
		var _damage = float(data.get("damage", 0))
		# El enemigo cae sobre la zona del target (caída animada, no corte seco)
		_ascension_land_enemy(enemy_id, Vector2(tx, ty))
		_spawn_ascension_impact_3d(vp, tx, ty, radius, s_factor, correction_z)
		if is_instance_valid(VFXSystem):
			VFXSystem.spawn_explosion(Vector2(tx, ty), max(0.5, radius / 100.0))
		# Shake si el jugador local está dentro del área
		if is_instance_valid(world) and is_instance_valid(world.local_player):
			var lp = world.local_player
			if lp.global_position.distance_to(Vector2(tx, ty)) <= radius and lp.has_method("apply_shake"):
				lp.apply_shake(4.0)
		return


# Aterrizaje de la ascensión: matar los tweens de vuelo y animar la caída al suelo.
func _ascension_land_enemy(enemy_id: String, dest: Vector2):
	if not active_ascensions.has(enemy_id):
		return
	var ent = active_ascensions[enemy_id]
	var node = ent.get("node")
	var tw_pos = ent.get("tw_pos")
	if tw_pos != null and is_instance_valid(tw_pos):
		tw_pos.kill()
	var tw_offs = ent.get("tw_offs")
	if tw_offs != null and is_instance_valid(tw_offs):
		tw_offs.kill()
	if is_instance_valid(node):
		node.target_position = dest
		node.global_position = dest
		if node.get("_ascension_y_offset") != null:
			var drop_tw = node.create_tween()
			drop_tw.tween_property(node, "_ascension_y_offset", 0.0, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	active_ascensions.erase(enemy_id)


# Cancela la animación de salto del enemigo y restaura su offset de ascensión.
func _ascension_clear_jump(enemy_id: String):
	if active_ascensions.has(enemy_id):
		var ent = active_ascensions[enemy_id]
		var node = ent.get("node")
		if is_instance_valid(node):
			var cur = 0.0
			if node.get("_ascension_y_offset") != null:
				cur = node._ascension_y_offset
			if cur != 0.0:
				node._ascension_y_offset = 0.0
			var tw_pos = ent.get("tw_pos")
			if tw_pos != null and is_instance_valid(tw_pos):
				tw_pos.kill()
			var tw_offs = ent.get("tw_offs")
			if tw_offs != null and is_instance_valid(tw_offs):
				tw_offs.kill()
		active_ascensions.erase(enemy_id)


# Restaura el offset de ascensión de todos los jugadores y enemigos (por si se pierde un tween).
func _ascension_reset_all_offsets():
	if is_instance_valid(world) and is_instance_valid(world.local_player):
		var lp = world.local_player
		if lp.get("_ascension_y_offset") != null and lp._ascension_y_offset != 0.0:
			lp._ascension_y_offset = 0.0
	for t_id in remote_players.keys():
		var p = remote_players[t_id]
		if is_instance_valid(p) and p.get("_ascension_y_offset") != null and p._ascension_y_offset != 0.0:
			p._ascension_y_offset = 0.0
	for enemy_id in active_ascensions.keys():
		_ascension_clear_jump(enemy_id)


# Aro de casteo cian sobre el enemigo mientras prepara el salto.
# (v414.2: ELIMINADO - el usuario lo pidió fuera: círculo en el piso sin función previa al casteo.)
# Círculo de aviso cian en el piso: marca el área donde aterrizará el enemigo.
func _spawn_ascension_warn_3d(vp, tx: float, ty: float, radius: float, warn_s: float, s_factor: float, correction_z: float) -> Node3D:
	var root = Node3D.new()
	root.name = "AscWarn3D_" + str(tx) + "_" + str(ty)
	var r3d = radius * s_factor
	root.position = Vector3(tx * s_factor, 0.02, ty * s_factor * correction_z)
	vp.add_child(root)

	var ring = MeshInstance3D.new()
	var rm = TorusMesh.new()
	rm.inner_radius = r3d * 0.92
	rm.outer_radius = r3d
	ring.mesh = rm
	var ring_mat = StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.3, 0.75, 1.0, 0.9)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.3, 0.75, 1.0)
	ring_mat.emission_energy_multiplier = 3.0
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = ring_mat
	ring.rotation.x = PI / 2
	root.add_child(ring)

	var fill = MeshInstance3D.new()
	var fm = CylinderMesh.new()
	fm.top_radius = r3d * 0.9
	fm.bottom_radius = r3d * 0.9
	fm.height = 0.01
	fill.mesh = fm
	var fill_mat = StandardMaterial3D.new()
	fill_mat.albedo_color = Color(0.3, 0.7, 1.0, 0.15)
	fill_mat.emission_enabled = true
	fill_mat.emission = Color(0.3, 0.7, 1.0)
	fill_mat.emission_energy_multiplier = 1.2
	fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.no_depth_test = true
	fill_mat.render_priority = 2
	fill.material_override = fill_mat
	root.add_child(fill)

	# --- Conformar al terreno + no_depth_test ---
	var _map_asc = get_tree().get_first_node_in_group("map")
	if is_instance_valid(_map_asc) and is_instance_valid(_map_asc.get("terrain_node")):
		var _h = _sample_terrain_height(Vector2(tx, ty), _map_asc)
		root.position.y = _h + 0.05
		# Reemplazar cilindro por disco conformante
		var _disc = _make_circle_disc_conforming(Vector2(tx, ty), radius * 0.9, _map_asc)
		fill.mesh = _disc
		ring_mat.no_depth_test = true
		ring_mat.render_priority = 2
		# Elevar anillo un poco sobre el disco conformado
		ring.position.y = 0.05

	# Pulso durante warnTime y auto-eliminación
	var pulse = root.create_tween().set_loops()
	pulse.tween_property(ring, "scale", Vector3(1.12, 1.12, 1.12), warn_s * 0.45).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(ring, "scale", Vector3.ONE, warn_s * 0.45).set_trans(Tween.TRANS_SINE)
	var tw = root.create_tween()
	tw.tween_interval(warn_s + 0.1)
	tw.tween_callback(root.queue_free)
	return root


# Impacto de aterrizaje: onda expansiva cian + polvo. (conformado al terreno)
func _spawn_ascension_impact_3d(vp, tx: float, ty: float, radius: float, s_factor: float, correction_z: float):
	var _map_ai = get_tree().get_first_node_in_group("map")
	var _h_ai = 0.05
	if is_instance_valid(_map_ai) and is_instance_valid(_map_ai.get("terrain_node")):
		_h_ai = _sample_terrain_height(Vector2(tx, ty), _map_ai) + 0.08
	var pos_3d = Vector3(tx * s_factor, _h_ai, ty * s_factor * correction_z)
	var r3d = max(0.1, radius * s_factor)

	var flash = MeshInstance3D.new()
	var flash_s = SphereMesh.new()
	flash_s.radius = r3d * 0.35
	flash_s.height = r3d * 0.7
	flash.mesh = flash_s
	var flash_mat = StandardMaterial3D.new()
	flash_mat.albedo_color = Color(0.5, 0.85, 1.0, 0.9)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(0.5, 0.85, 1.0)
	flash_mat.emission_energy_multiplier = 8.0
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.material_override = flash_mat
	flash.position = pos_3d
	vp.add_child(flash)
	var flash_tw = flash.create_tween()
	flash_tw.tween_property(flash, "scale", Vector3(r3d, r3d, r3d) * 3.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	flash_tw.parallel().tween_property(flash_mat, "albedo_color:a", 0.0, 0.35)
	flash_tw.tween_callback(flash.queue_free)

	var ring = MeshInstance3D.new()
	var rm = TorusMesh.new()
	rm.inner_radius = r3d * 0.85
	rm.outer_radius = r3d
	ring.mesh = rm
	var ring_mat = StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.5, 0.85, 1.0, 0.8)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.5, 0.85, 1.0)
	ring_mat.emission_energy_multiplier = 3.0
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = ring_mat
	ring.rotation.x = PI / 2
	ring.position = pos_3d
	vp.add_child(ring)
	var ring_tw = ring.create_tween()
	ring_tw.tween_property(ring, "scale", Vector3(2.2, 2.2, 2.2), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ring_tw.parallel().tween_property(ring_mat, "albedo_color:a", 0.0, 0.5)
	ring_tw.tween_callback(ring.queue_free)


# v411: METEORITO - Gestión visual de la lluvia de meteoritos.
# meteor_summon: crea círculos de aviso en el piso + meteoritos en el aire que caen.
# meteor_impact: explosión de impacto + limpieza de los meteoritos asociados.
func _handle_meteor_action(data: Dictionary):
	var action = str(data.get("action", ""))
	var map_node = get_tree().get_first_node_in_group("map")
	if not is_instance_valid(map_node) or map_node.get("sub_viewport") == null:
		return
	var s_factor = map_node.scale_factor if "scale_factor" in map_node else 0.02
	var correction_z = map_node.correction_z if "correction_z" in map_node else 1.41421356
	var vp = map_node.sub_viewport

	if action == "meteor_summon":
		var targets = data.get("targets", [])
		var warn_time_s = float(data.get("warnTimeMs", 1200)) / 1000.0
		var fall_height = float(data.get("fallHeight", 800))
		var fall_speed = float(data.get("fallSpeed", 600))
		var meteor_size = float(data.get("meteorSize", 60))
		var radius = float(data.get("radius", 150))
		var fall_s = fall_height / max(0.01, fall_speed)
		for t in targets:
			var tx = float(t.get("x", 0.0))
			var ty = float(t.get("y", 0.0))
			var key = str(tx) + "_" + str(ty)
			var warn = _spawn_meteor_warning_3d(vp, tx, ty, radius, s_factor, correction_z)
			var meteor = _spawn_meteor_model_3d(vp, tx, ty, fall_height, meteor_size, s_factor, correction_z)
			var entry = {"warn_3d": warn, "meteor_3d": meteor, "fall_s": fall_s, "landed": false}
			active_meteors[key] = entry
			var tw = create_tween()
			tw.tween_interval(warn_time_s)
			tw.tween_callback(_start_meteor_fall.bind(key))
	elif action == "meteor_impact":
		var tx = float(data.get("x", 0.0))
		var ty = float(data.get("y", 0.0))
		var radius = float(data.get("radius", 150))
		var meteor_size = float(data.get("meteorSize", 60))
		var key = str(tx) + "_" + str(ty)
		_spawn_meteor_impact_3d(vp, tx, ty, radius, meteor_size, s_factor, correction_z)
		if is_instance_valid(VFXSystem):
			VFXSystem.spawn_explosion(Vector2(tx, ty), max(0.5, radius / 100.0))
		if active_meteors.has(key):
			var entry = active_meteors[key]
			if is_instance_valid(entry.get("warn_3d")):
				entry["warn_3d"].queue_free()
			if is_instance_valid(entry.get("meteor_3d")):
				entry["meteor_3d"].queue_free()
			active_meteors.erase(key)
		else:
			# Fallback: si la clave exacta no matchea (posiciones redondeadas distintas),
			# limpiar la entrada más cercana para no dejar residuos en el piso.
			var best_key := ""
			var best_dist := INF
			for k in active_meteors:
				var parts = String(k).split("_")
				if parts.size() != 2:
					continue
				var d = Vector2(float(parts[0]) - tx, float(parts[1]) - ty).length()
				if d < best_dist:
					best_dist = d
					best_key = k
			if best_key != "" and best_dist < 1.0:
				var entry = active_meteors[best_key]
				if is_instance_valid(entry.get("warn_3d")):
					entry["warn_3d"].queue_free()
				if is_instance_valid(entry.get("meteor_3d")):
					entry["meteor_3d"].queue_free()
				active_meteors.erase(best_key)


# Inicia la caída del meteorito: baja desde la altura hasta el suelo girando.
func _start_meteor_fall(key: String):
	if not active_meteors.has(key):
		return
	var entry = active_meteors[key]
	var meteor = entry.get("meteor_3d")
	if not is_instance_valid(meteor):
		return
	var fall_s = float(entry.get("fall_s", 1.3))
	var tw = meteor.create_tween()
	tw.set_parallel(true)
	tw.tween_property(meteor, "position:y", 0.02, fall_s).set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(meteor, "rotation_degrees", Vector3(720, 480, 360), fall_s).set_trans(Tween.TRANS_LINEAR)


# Círculo de aviso en el piso donde caerá el meteorito (anillo + disco, pulso).
func _spawn_meteor_warning_3d(vp, tx: float, ty: float, radius: float, s_factor: float, correction_z: float) -> Node3D:
	var root = Node3D.new()
	root.name = "MeteorWarn_" + str(tx) + "_" + str(ty)
	var r3d = radius * s_factor
	root.position = Vector3(tx * s_factor, 0.02, ty * s_factor * correction_z)
	# Escalar en Z global para la perspectiva isométrica 2.5D
	root.scale = Vector3(1.0, 1.0, correction_z)
	vp.add_child(root)

	var ring = MeshInstance3D.new()
	var rm = TorusMesh.new()
	rm.inner_radius = r3d * 0.9
	rm.outer_radius = r3d
	ring.mesh = rm
	var ring_mat = StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.4, 0.05, 0.75)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.4, 0.05)
	ring_mat.emission_energy_multiplier = 2.5
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = ring_mat
	# Torus ya es plano XZ como IceStorm - no rotar PI/2 (eso lo deja vertical)
	ring.position.y = 0.02
	root.add_child(ring)

	var fill = MeshInstance3D.new()
	var fm = CylinderMesh.new()
	fm.top_radius = r3d * 0.88
	fm.bottom_radius = r3d * 0.88
	fm.height = 0.01
	fill.mesh = fm
	var fill_mat = StandardMaterial3D.new()
	fill_mat.albedo_color = Color(1.0, 0.35, 0.05, 0.12)
	fill_mat.emission_enabled = true
	fill_mat.emission = Color(1.0, 0.35, 0.05)
	fill_mat.emission_energy_multiplier = 0.4
	fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.no_depth_test = true
	fill_mat.render_priority = 2
	fill.material_override = fill_mat
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.no_depth_test = true
	ring_mat.render_priority = 2
	root.add_child(fill)

	# --- Conformar al terreno + elevar ---
	var _map_m = get_tree().get_first_node_in_group("map")
	if is_instance_valid(_map_m) and is_instance_valid(_map_m.get("terrain_node")):
		var _h = _sample_terrain_height(Vector2(tx, ty), _map_m)
		root.position.y = _h + 0.05
		# Disco conformante reemplaza cilindro plano
		var _disc = _make_circle_disc_conforming(Vector2(tx, ty), radius * 0.88, _map_m)
		fill.mesh = _disc
		ring.position.y = 0.06

	# Pulso de aviso
	var tw = root.create_tween().set_loops()
	tw.tween_property(ring, "scale", Vector3(1.18, 1.18, 1.0), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(ring, "scale", Vector3(1.0, 1.0, 1.0), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	return root


# Modelo 3D del meteorito: roca incandescente + llamas + humo + luz.
func _spawn_meteor_model_3d(vp, tx: float, ty: float, fall_height: float, meteor_size: float, s_factor: float, correction_z: float) -> Node3D:
	var root = Node3D.new()
	root.name = "Meteor3D_" + str(tx) + "_" + str(ty)
	root.position = Vector3(tx * s_factor, fall_height * s_factor, ty * s_factor * correction_z)
	var s3d = meteor_size * s_factor
	root.scale = Vector3(s3d, s3d, s3d)
	vp.add_child(root)

	# Roca principal (esfera deformada)
	var rock = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 16
	sphere.rings = 10
	rock.mesh = sphere
	var rock_mat = StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.18, 0.13, 0.1)
	rock_mat.roughness = 0.95
	rock_mat.metallic = 0.1
	rock_mat.emission_enabled = true
	rock_mat.emission = Color(1.0, 0.4, 0.05)
	rock_mat.emission_energy_multiplier = 0.6
	rock.material_override = rock_mat
	rock.scale = Vector3(1.15, 0.9, 1.0)
	root.add_child(rock)

	# Pedruscos secundarios
	for i in 3:
		var chunk = MeshInstance3D.new()
		var cs = SphereMesh.new()
		cs.radius = 0.14 + i * 0.04
		cs.height = cs.radius * 2.0
		chunk.mesh = cs
		var cm = StandardMaterial3D.new()
		cm.albedo_color = Color(0.22, 0.16, 0.12)
		cm.roughness = 1.0
		cm.emission_enabled = true
		cm.emission = Color(1.0, 0.35, 0.05)
		cm.emission_energy_multiplier = 0.3
		chunk.material_override = cm
		chunk.position = Vector3(randf_range(-0.6, 0.6), randf_range(-0.4, 0.4), randf_range(-0.6, 0.6))
		root.add_child(chunk)

	# Llamas (partículas de fuego desde la superficie de la roca)
	var fire = GPUParticles3D.new()
	fire.amount = 50
	fire.lifetime = 0.5
	var fire_ppm = ParticleProcessMaterial.new()
	fire_ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	fire_ppm.emission_sphere_radius = 0.55
	fire_ppm.direction = Vector3(0, 1, 0)
	fire_ppm.spread = 160.0
	fire_ppm.initial_velocity_min = 0.5
	fire_ppm.initial_velocity_max = 2.5
	fire_ppm.gravity = Vector3(0, 0.8, 0)
	fire_ppm.scale_min = 0.15
	fire_ppm.scale_max = 0.45
	fire_ppm.color = Color(1.0, 0.55, 0.1, 0.95)
	fire.process_material = fire_ppm
	var fire_quad = QuadMesh.new()
	fire_quad.size = Vector2(0.5, 0.5)
	fire.draw_pass_1 = fire_quad
	var fire_tex = load("res://VFX/textures/T_VFX_FireBall_s1_alpha.jpg")
	if fire_tex:
		var fire_mat = StandardMaterial3D.new()
		fire_mat.albedo_texture = fire_tex
		fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fire_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		fire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fire.material_override = fire_mat
	root.add_child(fire)

	# Humo (estela trasera)
	var smoke = GPUParticles3D.new()
	smoke.amount = 20
	smoke.lifetime = 1.0
	var smoke_ppm = ParticleProcessMaterial.new()
	smoke_ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	smoke_ppm.emission_sphere_radius = 0.4
	smoke_ppm.direction = Vector3(0, 1, 0)
	smoke_ppm.spread = 60.0
	smoke_ppm.initial_velocity_min = 0.3
	smoke_ppm.initial_velocity_max = 1.2
	smoke_ppm.gravity = Vector3(0, 1.5, 0)
	smoke_ppm.scale_min = 0.3
	smoke_ppm.scale_max = 0.8
	smoke_ppm.color = Color(0.2, 0.18, 0.16, 0.6)
	smoke.process_material = smoke_ppm
	var smoke_quad = QuadMesh.new()
	smoke_quad.size = Vector2(0.8, 0.8)
	smoke.draw_pass_1 = smoke_quad
	var smoke_tex = load("res://VFX/textures/T_VFX_smoke_1.PNG")
	if smoke_tex:
		var smoke_mat = StandardMaterial3D.new()
		smoke_mat.albedo_texture = smoke_tex
		smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smoke.material_override = smoke_mat
	root.add_child(smoke)

	# Luz incandescente
	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.45, 0.1)
	light.light_energy = 3.0
	light.omni_range = 5.0
	root.add_child(light)

	return root


# Explosión de impacto del meteorito: destello + onda expansiva + lluvia de fuego. (conformado)
func _spawn_meteor_impact_3d(vp, tx: float, ty: float, radius: float, _meteor_size: float, s_factor: float, correction_z: float):
	var _map_mi = get_tree().get_first_node_in_group("map")
	var _h_mi = 0.05
	if is_instance_valid(_map_mi) and is_instance_valid(_map_mi.get("terrain_node")):
		_h_mi = _sample_terrain_height(Vector2(tx, ty), _map_mi) + 0.08
	var pos_3d = Vector3(tx * s_factor, _h_mi, ty * s_factor * correction_z)
	var r3d = max(0.1, radius * s_factor)

	# Destello
	var flash = MeshInstance3D.new()
	var flash_s = SphereMesh.new()
	flash_s.radius = r3d * 0.35
	flash_s.height = r3d * 0.7
	flash.mesh = flash_s
	var flash_mat = StandardMaterial3D.new()
	flash_mat.albedo_color = Color(1.0, 0.5, 0.1, 0.9)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 0.5, 0.1)
	flash_mat.emission_energy_multiplier = 8.0
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.material_override = flash_mat
	flash.position = pos_3d
	vp.add_child(flash)
	var tw_f = flash.create_tween()
	tw_f.tween_property(flash, "scale", Vector3(2.5, 2.5, 2.5), 0.3)
	tw_f.parallel().tween_property(flash_mat, "albedo_color:a", 0.0, 0.3)
	tw_f.parallel().tween_property(flash_mat, "emission_energy_multiplier", 0.0, 0.3)
	tw_f.finished.connect(flash.queue_free)

	# Onda expansiva - plana en el piso como Tormenta de Hielo (sin rot PI/2)
	var shockwave = MeshInstance3D.new()
	var ring_mesh = TorusMesh.new()
	ring_mesh.inner_radius = r3d * 0.5
	ring_mesh.outer_radius = r3d * 0.55
	shockwave.mesh = ring_mesh
	var sw_mat = StandardMaterial3D.new()
	sw_mat.albedo_color = Color(1.0, 0.4, 0.05, 0.8)
	sw_mat.emission_enabled = true
	sw_mat.emission = Color(1.0, 0.4, 0.05)
	sw_mat.emission_energy_multiplier = 3.0
	sw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shockwave.material_override = sw_mat
	shockwave.position = pos_3d + Vector3(0,0.02,0)
	vp.add_child(shockwave)
	var tw_sw = shockwave.create_tween()
	tw_sw.tween_property(shockwave, "scale", Vector3(2.5, 2.5, 2.5), 0.35)
	tw_sw.parallel().tween_property(sw_mat, "albedo_color:a", 0.0, 0.35)
	tw_sw.parallel().tween_property(sw_mat, "emission_energy_multiplier", 0.0, 0.35)
	tw_sw.finished.connect(shockwave.queue_free)

	# Lluvia de fuego/rocas en la explosión
	var burst = GPUParticles3D.new()
	burst.amount = 60
	burst.lifetime = 0.7
	burst.one_shot = true
	burst.explosiveness = 0.95
	var burst_ppm = ParticleProcessMaterial.new()
	burst_ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	burst_ppm.emission_sphere_radius = r3d * 0.2
	burst_ppm.direction = Vector3(0, 1, 0)
	burst_ppm.spread = 180.0
	burst_ppm.initial_velocity_min = 1.0
	burst_ppm.initial_velocity_max = 5.0
	burst_ppm.gravity = Vector3(0, -4.0, 0)
	burst_ppm.scale_min = 0.15
	burst_ppm.scale_max = 0.5
	burst_ppm.color = Color(1.0, 0.5, 0.1, 1.0)
	burst.process_material = burst_ppm
	var burst_quad = QuadMesh.new()
	burst_quad.size = Vector2(0.4, 0.4)
	burst.draw_pass_1 = burst_quad
	var burst_tex = load("res://VFX/textures/T_VFX_sparks42.jpg")
	if burst_tex:
		var burst_mat = StandardMaterial3D.new()
		burst_mat.albedo_texture = burst_tex
		burst_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		burst_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		burst_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		burst.material_override = burst_mat
	burst.position = pos_3d
	vp.add_child(burst)
	burst.emitting = true
	var tw_burst = burst.create_tween()
	tw_burst.tween_interval(1.0)
	tw_burst.tween_callback(burst.queue_free)

	# Luz de impacto
	var impact_light = OmniLight3D.new()
	impact_light.light_color = Color(1.0, 0.5, 0.1)
	impact_light.light_energy = 8.0
	impact_light.omni_range = r3d * 3.0
	impact_light.position = pos_3d
	vp.add_child(impact_light)
	var tw_l = impact_light.create_tween()
	tw_l.tween_property(impact_light, "light_energy", 0.0, 0.3)
	tw_l.finished.connect(impact_light.queue_free)


func _handle_meteor_zone_action(data: Dictionary) -> void:
	var action = str(data.get("action", ""))
	var m_id = str(data.get("mId", ""))
	if m_id.is_empty():
		return
	# meteor_zone_end: limpiar zona
	if action == "meteor_zone_end":
		if active_meteor_zones.has(m_id):
			var entry = active_meteor_zones[m_id]
			if is_instance_valid(entry.get("zone_2d")):
				entry.zone_2d.queue_free()
			active_meteor_zones.erase(m_id)
		return
	# meteor_zone_start: crear zona persistente
	if active_meteor_zones.has(m_id):
		return
	var map_node = get_tree().get_first_node_in_group("map")
	if not is_instance_valid(map_node):
		return
	var zone_2d = METEOR_ZONE_SCRIPT.new()
	zone_2d.name = "MeteorZone_" + m_id
	zone_2d.z_index = 5
	zone_2d.set_as_top_level(true)
	zone_2d.global_position = Vector2(float(data.get("x", 0)), float(data.get("y", 0)))
	if is_instance_valid(world) and is_instance_valid(world.entities_node):
		world.entities_node.add_child(zone_2d)
	else:
		add_child(zone_2d)
	zone_2d.setup(data, map_node)
	active_meteor_zones[m_id] = { "zone_2d": zone_2d }


# --- Spawn safety: evita que enemigos aparezcan dentro de colliders 2D (muro/estructura) ---
# No toca colliders: solo valida el punto y lo desplaza a un lugar libre cercano si está bloqueado.
func _is_spawn_blocked_physics(pos: Vector2) -> bool:
	var map_node = get_tree().get_first_node_in_group("map")
	if not is_instance_valid(map_node):
		return false
	# DirectSpaceState con máscara 2 = paredes/estructuras (BaseMap.gd collision_layer 2)
	var space = map_node.get_world_2d().direct_space_state
	if space == null:
		return false
	var params = PhysicsPointQueryParameters2D.new()
	params.position = pos
	params.collision_mask = 2
	params.collide_with_bodies = true
	params.collide_with_areas = false
	var res = space.intersect_point(params, 1)
	return res.size() > 0

func _find_safe_spawn_near(blocked_pos: Vector2, search_radius: float = 260.0) -> Vector2:
	# Búsqueda en anillos + muestreo aleatorio alrededor de blocked_pos usando física real.
	# Devuelve Vector2.INF si no se encuentra punto libre.
	var rings = [0.25, 0.5, 0.85, 1.0]
	for ring_frac in rings:
		var r = search_radius * ring_frac
		for i in range(16):
			var ang = (float(i) / 16.0) * TAU + ring_frac * 0.71
			var candidate = blocked_pos + Vector2(cos(ang), sin(ang)) * r
			if not _is_spawn_blocked_physics(candidate):
				return candidate
	for i in range(24):
		var ang = randf() * TAU
		var rr = sqrt(randf()) * search_radius
		var candidate = blocked_pos + Vector2(cos(ang), sin(ang)) * rr
		if not _is_spawn_blocked_physics(candidate):
			return candidate
	return Vector2.INF

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
		# Safety client-side: si es spawn nuevo y el punto cae DENTRO de un collider 2D, recolocar visualmente
		# (el servidor ya hace rejection sampling; esto es red de seguridad para desfases de config o mapas custom sin cache)
		if is_new and _is_spawn_blocked_physics(new_pos):
			var safe = _find_safe_spawn_near(new_pos, 280.0)
			if safe != Vector2.INF:
				new_pos = safe
				print("[EntityManager] Spawn bloqueado corregido cliente: ", id, " -> ", safe)
			else:
				print("[EntityManager] Spawn bloqueado sin alternativa libre: ", id, " @ ", new_pos)
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
		eref.update_stats(data)
		if not eref.is_burrowed:
			eref.visible = true; eref.show()
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

func _on_wind_push(data: Dictionary):
	var victim_id = str(data.get("victimId", ""))
	if victim_id == "": return
	
	var victim_node = null
	if is_instance_valid(world) and is_instance_valid(world.local_player) and world.local_player.entity_id == victim_id:
		victim_node = world.local_player
	elif remote_players.has(victim_id):
		victim_node = remote_players[victim_id]
	if not is_instance_valid(victim_node):
		return
	
	var dir := Vector2(float(data.get("dirX", 0.0)), float(data.get("dirY", 0.0)))
	if dir.length_squared() <= 0.0001:
		return
	dir = dir.normalized()
	var distance := float(data.get("distance", 250.0))
	var target_pos: Vector2 = victim_node.global_position + dir * distance
	
	var push_speed := 1600.0
	var duration: float = clamp(distance / push_speed, 0.15, 0.6)
	var tw = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(victim_node, "global_position", target_pos, duration)

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
		_spawn_smoke_cloud(id, Vector2(data.x, data.y), data.radius, data)
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
				if area.has_meta("pool_scene_path"):
					var tw = area.create_tween()
					tw.tween_interval(area.lifetime)
					tw.tween_callback(func(): VFXSystem.recycle_vfx_to_pool(area))
				else:
					area.queue_free()
			elif area is Node3D:
				var particles = area.get_node_or_null("SmokeCloud") as GPUParticles3D
				if is_instance_valid(particles):
					particles.emitting = false
					var tw = area.create_tween().set_parallel(true)
					tw.tween_property(area, "scale", Vector3.ONE * 1.2, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
					var timer = area.get_tree().create_timer(1.8)
					timer.timeout.connect(area.queue_free)
				else:
					var tw = area.create_tween().set_parallel(true)
					tw.tween_property(area, "scale", Vector3(0.001, 0.001, 0.001), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
					tw.tween_property(area, "visible", false, 0.14)
					if area.has_meta("pool_scene_path"):
						tw.chain().tween_callback(func(): VFXSystem.recycle_vfx_to_pool(area))
					else:
						tw.chain().tween_callback(func():
							_recycle_children_recursive(area)
							area.queue_free()
						)
			else:
				var tw = area.create_tween().set_parallel(true)
				tw.tween_property(area, "scale", Vector2(0.001, 0.001), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
				tw.tween_property(area, "modulate:a", 0.0, 0.15)
				tw.chain().tween_callback(area.queue_free)

func _recycle_children_recursive(node: Node):
	for child in node.get_children():
		if child.has_meta("pool_scene_path"):
			VFXSystem.recycle_vfx_to_pool(child)
		else:
			_recycle_children_recursive(child)

func _spawn_alpha_regen_vfx(id, pos, _radius, _data):
	if active_areas.has(id): return
	var current_map = get_tree().get_first_node_in_group("map")
	if not is_instance_valid(current_map) or not current_map.get("sub_viewport"):
		return
	var sub_vp = current_map.sub_viewport
	var s_factor = current_map.scale_factor if "scale_factor" in current_map else 0.02
	var correction_z = current_map.correction_z if "correction_z" in current_map else 1.41421356
	
	var vfx = VFXSystem.get_vfx_from_pool(VFX_SHIELD_GREEN_SCENE)
	vfx.name = id
	vfx.position = Vector3(pos.x * s_factor, 1.5, pos.y * s_factor * correction_z)
	
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
	var h_b = 0.0
	if is_instance_valid(current_map.get("terrain_node")):
		h_b = _sample_terrain_height(pos, current_map)
	var beacon = BEACON_3D_SCRIPT.new()
	beacon.name = id
	beacon._scale_factor = s_factor
	beacon._heal_radius_2d = float(_data.get("radius", 200.0))
	beacon.position = Vector3(pos.x * s_factor, h_b + 0.05, pos.y * s_factor * correction_z)
	sub_vp.add_child(beacon)
	active_areas[id] = beacon
	# Asegurar que el anillo RangeRing sea conformante si se crea a nivel suelo
	if beacon.has_method("_add_range_indicator"):
		# Beacon crea su ring a y=0.02, elevarlo y hacerlo no_depth_test
		var _ring = beacon.get_node_or_null("RangeRing")
		if _ring and _ring.material_override is StandardMaterial3D:
			_ring.material_override.no_depth_test = true
			_ring.material_override.render_priority = 2

func _on_beacon_pulse(data: Dictionary):
	var id = data.get("id", "")
	if active_areas.has(id):
		var beacon = active_areas[id]
		if is_instance_valid(beacon) and beacon.has_method("pulse"):
			var pulse_radius = float(data.get("radius", 200.0))
			beacon.pulse(pulse_radius)

func _spawn_smoke_cloud(id, pos, radius, data = {}):
	if active_areas.has(id): return
	var current_map = get_tree().get_first_node_in_group("map")
	if not is_instance_valid(current_map) or not current_map.get("sub_viewport"):
		return
	var s_factor = current_map.scale_factor if "scale_factor" in current_map else 0.02
	var correction_z = current_map.correction_z if "correction_z" in current_map else 1.41421356
	var sub_vp = current_map.sub_viewport

	var smoke = Node3D.new()
	smoke.name = id
	var radius_3d = max(float(radius), 1.0) * s_factor
	smoke.position = Vector3(pos.x * s_factor, 1.5, pos.y * s_factor * correction_z)
	sub_vp.add_child(smoke)
	active_areas[id] = smoke

	var _duration = float(data.get("duration", 6.0))

	var parts = GPUParticles3D.new()
	parts.name = "SmokeCloud"
	parts.amount = 120
	parts.lifetime = 2.0
	parts.one_shot = false
	parts.explosiveness = 0.0
	parts.randomness = 0.85
	parts.preprocess = 1.0

	var mesh = QuadMesh.new()
	mesh.size = Vector2(2.5, 2.5) # Partículas gigantes para que se solapen y formen volumen denso
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = SMOKE_TEXTURE
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true # Para que el gradiente afecte al albedo correctamente
	mesh.material = mat
	parts.draw_pass_1 = mesh

	var pm = ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.4
	pm.gravity = Vector3(0, 0.15, 0) # Elevación térmica ligera del humo caliente
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35 # Radio de emisión pequeño para que nazcan agrupadas y formen un cuerpo
	
	pm.scale_min = 1.0
	pm.scale_max = 1.8

	# Curva de escala: expandir el humo rápidamente al nacer
	var curve = Curve.new()
	curve.add_point(Vector2(0.0, 0.2))
	curve.add_point(Vector2(0.15, 0.95))
	curve.add_point(Vector2(0.6, 1.25))
	curve.add_point(Vector2(1.0, 1.5))
	var curve_tex = CurveTexture.new()
	curve_tex.curve = curve
	pm.scale_curve = curve_tex

	# Gradiente de humo ceniza oscuro muy denso (como la imagen militar de referencia)
	var grad = Gradient.new()
	grad.set_color(0, Color(0.24, 0.23, 0.22, 0.0)) # Nace invisible
	grad.add_point(0.12, Color(0.28, 0.27, 0.25, 0.92)) # Opacidad altísima rápida en el centro
	grad.add_point(0.45, Color(0.32, 0.31, 0.29, 0.8)) # Masa de humo
	grad.add_point(0.75, Color(0.38, 0.37, 0.35, 0.4)) # Disipándose
	grad.set_color(grad.get_point_count() - 1, Color(0.45, 0.44, 0.42, 0.0)) # Termina invisible
	pm.color_ramp = GradientTexture1D.new()
	pm.color_ramp.gradient = grad

	# Rotación y velocidad angular para simular turbulencias
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -25.0
	pm.angular_velocity_max = 25.0

	parts.process_material = pm
	parts.scale = Vector3(radius_3d, radius_3d, radius_3d)
	smoke.add_child(parts)
	parts.emitting = true

	smoke.scale = Vector3.ZERO
	var tw = create_tween().set_parallel(true)
	tw.tween_property(smoke, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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
	# v900.0: sonido de disparo remoto (ammo) con atenuación
	if AudioManager and AudioManager.has_method("play_sfx_path"):
		var pos = Vector2(float(d.get("x", 0)), float(d.get("y", 0)))
		var btype = String(d.get("bulletType", d.get("ammoType", "")))
		var tier = int(d.get("tier", d.get("ammoTier", 0)))
		if not btype.is_empty() and GameConstants.SHOP_ITEMS and GameConstants.SHOP_ITEMS.has("ammo"):
			var cfg = GameConstants.SHOP_ITEMS["ammo"].get(btype, [])
			if tier < cfg.size():
				var sp = String(cfg[tier].get("sound", ""))
				if not sp.is_empty():
					var ammo_pct = float(cfg[tier].get("soundVolumePercent", cfg[tier].get("soundVolume", 100.0)))
					AudioManager.play_sfx_path(sp, pos, linear_to_db(clamp(ammo_pct / 100.0, 0.0001, 1.0)), float(cfg[tier].get("soundMaxDist", 1000.0)))

func _on_enemy_fired(d): 
	if is_instance_valid(world) and is_instance_valid(world.combat_system): 
		world.combat_system.handle_enemy_shoot(d)
	# v900.0: sonido de mecánica atacante (hybrid)
	if AudioManager and AudioManager.has_method("play_mechanic_sound"):
		var pos = Vector2(float(d.get("x", d.get("posX", 0))), float(d.get("y", d.get("posY", 0))))
		var mtype = String(d.get("mechType", d.get("mechanicType", d.get("type", ""))))
		if not mtype.is_empty():
			var inst = d.get("mechanic", null)
			AudioManager.play_mechanic_sound(mtype, inst if inst is Dictionary else null, pos)

func _on_remote_skill_used(data):
	if typeof(data) != TYPE_DICTIONARY: return
	
	var sender_id = str(data.get("id", ""))
	var skill_name = data.get("skillName", "")
	# v900.0: sonido de habilidad remota (2D)
	if AudioManager and AudioManager.has_method("play_skill_sound") and not skill_name.is_empty():
		var em_sound = null
		if remote_players.has(sender_id):
			em_sound = remote_players[sender_id]
		elif is_instance_valid(world) and is_instance_valid(world.local_player) and world.local_player.entity_id == sender_id:
			em_sound = world.local_player
		elif enemies.has(sender_id):
			em_sound = enemies[sender_id]
		var spos = em_sound.global_position if is_instance_valid(em_sound) else Vector2.INF
		AudioManager.play_skill_sound(skill_name, spos)
	
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
	
	# v410.6: Limpiar mercancías/botines locales activos de la zona anterior
	for id in loot_drops.keys():
		var drop = loot_drops[id]
		if is_instance_valid(drop):
			drop.queue_free()
	loot_drops.clear()
	
	# v371.2: Limpiar restos de naufragios (wreckage markers) antiguos del sector al cambiar de zona
	if is_instance_valid(world) and is_instance_valid(world.get("entities_node")):
		for child in world.entities_node.get_children():
			if is_instance_valid(child) and child.name.begins_with("Wreckage_"):
				child.queue_free()
	
	# Gusano Bumerán: limpiar gusanos activos al cambiar de zona
	if is_instance_valid(world) and is_instance_valid(world.get("entities_node")):
		for child in world.entities_node.get_children():
			if is_instance_valid(child) and (child.name.begins_with("Worm_") or child.name.begins_with("WindWall_")):
				child.queue_free()
	active_wind_walls.clear()

	# v400.60: Limpiar visuales de zambullida (Burrow_) al cambiar de zona
	if is_instance_valid(world) and is_instance_valid(world.get("entities_node")):
		for child in world.entities_node.get_children():
			if is_instance_valid(child) and child.name.begins_with("Burrow_"):
				child.queue_free()
	for key in active_areas.keys():
		if str(key).begins_with("burrow_"):
			active_areas.erase(key)
	
	if is_instance_valid(world) and is_instance_valid(world.combat_system) and world.combat_system.has_method("clear_all_bullets"):
		world.combat_system.clear_all_bullets()
		
	var is_dungeon = str(_zoneId).begins_with("dungeon")
	var is_extraction = str(_zoneId).begins_with("extract_") or str(_zoneId) == "10"
	
	# Determinar si es un mapa de Altar Defense (dinámico desde el config del servidor) - v770.8: 11 ya no es extraction, es altar
	var zone_int_check = int(_zoneId) if not is_dungeon else 0
	# Si es extraction (10) no buscar altar; si es 11 debe poder detectarse como altar aunque is_extraction=false ahora
	if is_extraction:
		zone_int_check = 0
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

func _generate_lightning(from: Vector2, to: Vector2, segments: int, seed_val: int, jitter: float) -> PackedVector2Array:
	var pts = PackedVector2Array()
	var dir = (to - from).normalized()
	var length = from.distance_to(to)
	var perp = Vector2(-dir.y, dir.x)
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val
	
	pts.append(from)
	var step_len = length / float(segments)
	for i in range(1, segments):
		var t = float(i) / float(segments)
		var base = from + dir * (step_len * i)
		var j = jitter * (1.0 - t * 0.7) * (rng.randf() * 2.0 - 1.0)
		pts.append(base + perp * j)
	pts.append(to)
	return pts

func _generate_lightning_branches(from: Vector2, to: Vector2, main_pts: PackedVector2Array, seed_val: int) -> PackedVector2Array:
	if main_pts.size() < 3: return PackedVector2Array()
	var pts = PackedVector2Array()
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val
	var dir = (to - from).normalized()
	var perp = Vector2(-dir.y, dir.x)
	var count = rng.randi_range(2, 4)
	for _b in range(count):
		var idx = rng.randi_range(1, main_pts.size() - 2)
		var origin = main_pts[idx]
		var next_idx = min(idx + rng.randi_range(1, 3), main_pts.size() - 1)
		var target_dir = (main_pts[next_idx] - origin).normalized()
		var branch_len = rng.randf_range(20.0, 50.0)
		var branch_angle = rng.randf_range(-0.8, 0.8)
		var end_pt = origin + target_dir.rotated(branch_angle) * branch_len
		var b_segments = rng.randi_range(2, 4)
		var b_step = 1.0 / float(b_segments)
		for i in range(b_segments + 1):
			var t = i * b_step
			var p = origin.lerp(end_pt, t)
			var j = (1.0 - t * 0.5) * 8.0 * (rng.randf() * 2.0 - 1.0)
			pts.append(p + perp * j)
	return pts

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
	container.set_meta("bolt_timer", 0.0)
	container.set_meta("bolt_seed", randi())
	
	var break_range = float(data.get("radius", 500.0))
	container.set_meta("radius", break_range)
	
	# 1. Anillo/Límite celeste translúcido centrado en el emisor (Karma style)
	var limit_ring = Line2D.new()
	limit_ring.name = "LimitRing"
	limit_ring.width = 1.5
	limit_ring.default_color = Color(0.0, 0.7, 1.0, 0.28)
	limit_ring.z_index = -1
	
	var ring_pts = []
	var ring_segments = 64
	for i in range(ring_segments + 1):
		var ang = (i / float(ring_segments)) * TAU
		ring_pts.append(Vector2(cos(ang), sin(ang)) * break_range)
	limit_ring.points = ring_pts
	container.add_child(limit_ring)
	
	# 2. Rayo mágico tipo lightning (3 capas: glow + main + branches)
	for layer in ["Glow", "Main", "Branches"]:
		var bolt = Line2D.new()
		bolt.name = "Bolt" + layer
		bolt.z_index = 3
		bolt.set_as_top_level(true)
		container.add_child(bolt)
		match layer:
			"Glow":
				bolt.width = 12.0
				bolt.default_color = Color(0.1, 0.9, 0.25, 0.2)
			"Main":
				bolt.width = 4.0
				bolt.default_color = Color(0.2, 1.0, 0.3, 0.95)
			"Branches":
				bolt.width = 1.5
				bolt.default_color = Color(0.3, 1.0, 0.4, 0.5)

func _spawn_wind_barrier_vfx(id, pos, _radius, _data = {}):
	if active_areas.has(id): return
	var current_map = get_tree().get_first_node_in_group("map")
	if not is_instance_valid(current_map) or not current_map.get("sub_viewport"):
		return
	var s_factor = current_map.scale_factor if "scale_factor" in current_map else 0.02
	var correction_z = current_map.correction_z if "correction_z" in current_map else 1.41421356
	var sub_vp = current_map.sub_viewport

	var angle = float(_data.get("angle", 0.0))
	var width = float(_data.get("radius", _data.get("width", 150)))
	var radius_3d = width * s_factor

	var barrier = Node3D.new()
	barrier.name = id
	barrier.position = Vector3(pos.x * s_factor, 1.0, pos.y * s_factor * correction_z)
	barrier.rotation.y = -angle
	sub_vp.add_child(barrier)
	active_areas[id] = barrier

	var vfx_scene = WIND_BARRIER_VFX_SCENE
	if vfx_scene:
		var vfx = VFXSystem.get_vfx_from_pool(vfx_scene)
		vfx.scale = Vector3(radius_3d, radius_3d, radius_3d)
		vfx.rotation_degrees.y = 90
		barrier.add_child(vfx)

		var wind_grad = Gradient.new()
		wind_grad.set_color(0, Color(0.6, 0.8, 1.0, 0.8))
		wind_grad.add_point(0.4, Color(0.75, 0.88, 1.0, 0.4))
		wind_grad.set_color(1, Color(0.85, 0.92, 1.0, 0.0))
		var wind_tex = GradientTexture1D.new()
		wind_tex.gradient = wind_grad

		for child in vfx.get_children():
			if child is MeshInstance3D and child.material_override:
				var mat = child.material_override
				mat.set("shader_parameter/Gradient_1D_Color", wind_tex)

	barrier.scale = Vector3.ZERO
	var tw = create_tween()
	tw.tween_property(barrier, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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

# --- v500.8+ Terrain-Conforming helpers (Decal híbrido) ---
# Detecta si el renderer soporta Decal (Forward+ / Mobile). En gl_compatibility usamos malla conformante.
func _render_supports_decal() -> bool:
	var method = ProjectSettings.get_setting("renderer/rendering_method", "gl_compatibility")
	# En editor mobile setting puede diferir
	if method == "forward_plus" or method == "mobile":
		return true
	# fallback: leer renderer actual
	var cur = ProjectSettings.get_setting("rendering/renderer/rendering_method", "gl_compatibility")
	return cur == "forward_plus" or cur == "mobile"

var _sample_log_count: int = 0
func _sample_terrain_height(p2d: Vector2, map_node) -> float:
	if not is_instance_valid(map_node) or not map_node.has_method("get_terrain_height_at_pos"):
		return 0.0
	var tnode = map_node.get("terrain_node")
	var h: float = 0.0
	var used_data: bool = false
	if is_instance_valid(tnode):
		# Intentar vía data.get_height (API nueva) y vía get_height directo (compat)
		var s = map_node.scale_factor if "scale_factor" in map_node else 0.02
		var cz = map_node.correction_z if "correction_z" in map_node else 1.41421356
		var pos3 = Vector3(p2d.x * s, 0.0, p2d.y * s * cz)
		if tnode.has_method("get_height"):
			h = tnode.get_height(pos3)
			used_data = true
		elif "data" in tnode and is_instance_valid(tnode.data) and tnode.data.has_method("get_height"):
			h = tnode.data.get_height(pos3)
			used_data = true
		elif tnode.has_property("data") and is_instance_valid(tnode.get("data")):
			var d = tnode.get("data")
			if d and d.has_method("get_height"):
				h = d.get_height(pos3)
				used_data = true
		if used_data and not is_nan(h) and not is_inf(h):
			if _sample_log_count < 6:
				print("[TERRAIN_SAMPLE] p2d=", p2d, " pos3=", pos3, " h=", h, " terrain=", tnode.name)
				_sample_log_count+=1
			return h
	# fallback al helper oficial (incluye throttle log)
	var hf = map_node.get_terrain_height_at_pos(p2d)
	if _sample_log_count < 6:
		print("[TERRAIN_SAMPLE_FALLBACK] p2d=", p2d, " h_fallback=", hf, " tnode_valid=", is_instance_valid(tnode))
		_sample_log_count+=1
	return hf

func _get_cast_progress(enemy_id: String, mId: String = "") -> float:
	if not enemy_cast_visuals.has(enemy_id):
		return -1.0
	var dict = enemy_cast_visuals[enemy_id]
	if mId != "" and dict.has(mId):
		var d = dict[mId]
		var dur = float(d.get("duration", 0))
		if dur <= 0.0:
			return -1.0
		var start = int(d.get("startTime", 0))
		var elapsed = Time.get_ticks_msec() - start
		return clamp(float(elapsed) / dur, 0.0, 1.0)
	# fallback: tomar el casteo más reciente de ese enemigo (suele haber uno solo activo)
	var best_prog := -1.0
	var best_start := -1
	for k in dict.keys():
		var d = dict[k]
		var dur = float(d.get("duration", 0))
		if dur <= 0.0:
			continue
		var start = int(d.get("startTime", 0))
		if start > best_start:
			best_start = start
			var elapsed = Time.get_ticks_msec() - start
			best_prog = clamp(float(elapsed) / dur, 0.0, 1.0)
	return best_prog

func _make_cone_mesh_3d(range_3d: float, angle_deg: float) -> ArrayMesh:
	var half_angle = deg_to_rad(angle_deg / 2.0)
	var total_angle = deg_to_rad(angle_deg)
	var segments = 24
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		var a1 = -half_angle + (float(i) / segments) * total_angle
		var a2 = -half_angle + (float(i + 1) / segments) * total_angle
		var p0 = Vector3(0, 0, 0)
		var p1 = Vector3(sin(a1) * range_3d, 0, -cos(a1) * range_3d)
		var p2 = Vector3(sin(a2) * range_3d, 0, -cos(a2) * range_3d)
		var normal = Vector3.UP
		st.set_normal(normal)
		st.add_vertex(p0)
		st.set_normal(normal)
		st.add_vertex(p1)
		st.set_normal(normal)
		st.add_vertex(p2)
	return st.commit()

# Malla de cono CONFORMANTE densa: subdivide radialmente para no atravesar lomas interiores
func _make_cone_mesh_conforming(center_2d: Vector2, range_val_2d: float, angle_deg: float, enemy_rot: float, map_node) -> ArrayMesh:
	var half_angle = deg_to_rad(angle_deg / 2.0)
	var total_angle = deg_to_rad(angle_deg)
	var segs_ang = 24
	var segs_rad = 5 # anillos radiales (0 = apex)
	var s_factor = map_node.scale_factor if is_instance_valid(map_node) and "scale_factor" in map_node else 0.02
	var cz = map_node.correction_z if is_instance_valid(map_node) and "correction_z" in map_node else 1.41421356
	var h_center = _sample_terrain_height(center_2d, map_node)
	var eps = 0.45 # levantar bastante para que no se entierre en picos intermedios no muestreados
	# Para lomas muy empinadas, añadir margen según variación máxima muestreada
	var max_abs_delta: float = 0.0
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Pre-muestrear alturas en grilla para calcular variación y para reutilizar
	for ri in range(segs_rad):
		var r1 = range_val_2d * (float(ri) / segs_rad)
		var r2 = range_val_2d * (float(ri+1) / segs_rad)
		for ai in range(segs_ang):
			var a1 = -half_angle + (float(ai) / segs_ang) * total_angle
			var a2 = -half_angle + (float(ai+1) / segs_ang) * total_angle
			var off_a1_r1 = Vector2(sin(a1) * r1, -cos(a1) * r1).rotated(enemy_rot)
			var off_a2_r1 = Vector2(sin(a2) * r1, -cos(a2) * r1).rotated(enemy_rot)
			var off_a1_r2 = Vector2(sin(a1) * r2, -cos(a1) * r2).rotated(enemy_rot)
			var off_a2_r2 = Vector2(sin(a2) * r2, -cos(a2) * r2).rotated(enemy_rot)
			var w_a1_r1 = center_2d + off_a1_r1
			var w_a2_r1 = center_2d + off_a2_r1
			var w_a1_r2 = center_2d + off_a1_r2
			var w_a2_r2 = center_2d + off_a2_r2
			var h_a1_r1 = _sample_terrain_height(w_a1_r1, map_node)
			var h_a2_r1 = _sample_terrain_height(w_a2_r1, map_node)
			var h_a1_r2 = _sample_terrain_height(w_a1_r2, map_node)
			var h_a2_r2 = _sample_terrain_height(w_a2_r2, map_node)
			max_abs_delta = max(max_abs_delta, abs(h_a1_r1 - h_center))
			max_abs_delta = max(max_abs_delta, abs(h_a2_r1 - h_center))
			max_abs_delta = max(max_abs_delta, abs(h_a1_r2 - h_center))
			max_abs_delta = max(max_abs_delta, abs(h_a2_r2 - h_center))
			var p_a1_r1 = Vector3(off_a1_r1.x * s_factor, (h_a1_r1 - h_center) + eps, off_a1_r1.y * s_factor * cz)
			var p_a2_r1 = Vector3(off_a2_r1.x * s_factor, (h_a2_r1 - h_center) + eps, off_a2_r1.y * s_factor * cz)
			var p_a1_r2 = Vector3(off_a1_r2.x * s_factor, (h_a1_r2 - h_center) + eps, off_a1_r2.y * s_factor * cz)
			var p_a2_r2 = Vector3(off_a2_r2.x * s_factor, (h_a2_r2 - h_center) + eps, off_a2_r2.y * s_factor * cz)
			if ri == 0:
				# Fan desde apex (r1=0 => p_a1_r1 == p_a2_r1 == apex)
				st.set_normal(Vector3.UP)
				st.add_vertex(p_a1_r1) # apex
				st.set_normal(Vector3.UP)
				st.add_vertex(p_a1_r2)
				st.set_normal(Vector3.UP)
				st.add_vertex(p_a2_r2)
			else:
				# Quad en dos triángulos
				st.set_normal(Vector3.UP)
				st.add_vertex(p_a1_r1)
				st.set_normal(Vector3.UP)
				st.add_vertex(p_a2_r1)
				st.set_normal(Vector3.UP)
				st.add_vertex(p_a2_r2)
				st.set_normal(Vector3.UP)
				st.add_vertex(p_a1_r1)
				st.set_normal(Vector3.UP)
				st.add_vertex(p_a2_r2)
				st.set_normal(Vector3.UP)
				st.add_vertex(p_a1_r2)
	if max_abs_delta > 4.0 and _sample_log_count < 4:
		print("[CONE_CONFORM] center=", center_2d, " range=", range_val_2d, " maxDelta=", max_abs_delta, " h_center=", h_center)
	return st.commit()

func _make_circle_disc_conforming(center_2d: Vector2, radius_2d: float, map_node) -> ArrayMesh:
	var segs_ang = 32
	var segs_rad = 6
	var s_factor = map_node.scale_factor if is_instance_valid(map_node) and "scale_factor" in map_node else 0.02
	var cz = map_node.correction_z if is_instance_valid(map_node) and "correction_z" in map_node else 1.41421356
	var h_center = _sample_terrain_height(center_2d, map_node)
	var eps = 0.45
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ri in range(segs_rad):
		var r1 = radius_2d * (float(ri) / segs_rad)
		var r2 = radius_2d * (float(ri+1) / segs_rad)
		for ai in range(segs_ang):
			var ang1 = (float(ai) / segs_ang) * TAU
			var ang2 = (float(ai+1) / segs_ang) * TAU
			var off_a1_r1 = Vector2(cos(ang1), sin(ang1)) * r1
			var off_a2_r1 = Vector2(cos(ang2), sin(ang2)) * r1
			var off_a1_r2 = Vector2(cos(ang1), sin(ang1)) * r2
			var off_a2_r2 = Vector2(cos(ang2), sin(ang2)) * r2
			var h_a1_r1 = _sample_terrain_height(center_2d + off_a1_r1, map_node)
			var h_a2_r1 = _sample_terrain_height(center_2d + off_a2_r1, map_node)
			var h_a1_r2 = _sample_terrain_height(center_2d + off_a1_r2, map_node)
			var h_a2_r2 = _sample_terrain_height(center_2d + off_a2_r2, map_node)
			var p_a1_r1 = Vector3(off_a1_r1.x * s_factor, (h_a1_r1 - h_center) + eps, off_a1_r1.y * s_factor * cz)
			var p_a2_r1 = Vector3(off_a2_r1.x * s_factor, (h_a2_r1 - h_center) + eps, off_a2_r1.y * s_factor * cz)
			var p_a1_r2 = Vector3(off_a1_r2.x * s_factor, (h_a1_r2 - h_center) + eps, off_a1_r2.y * s_factor * cz)
			var p_a2_r2 = Vector3(off_a2_r2.x * s_factor, (h_a2_r2 - h_center) + eps, off_a2_r2.y * s_factor * cz)
			if ri == 0:
				st.set_normal(Vector3.UP)
				st.add_vertex(p_a1_r1)
				st.set_normal(Vector3.UP)
				st.add_vertex(p_a1_r2)
				st.set_normal(Vector3.UP)
				st.add_vertex(p_a2_r2)
			else:
				st.set_normal(Vector3.UP)
				st.add_vertex(p_a1_r1)
				st.set_normal(Vector3.UP)
				st.add_vertex(p_a2_r1)
				st.set_normal(Vector3.UP)
				st.add_vertex(p_a2_r2)
				st.set_normal(Vector3.UP)
				st.add_vertex(p_a1_r1)
				st.set_normal(Vector3.UP)
				st.add_vertex(p_a2_r2)
				st.set_normal(Vector3.UP)
				st.add_vertex(p_a1_r2)
	return st.commit()

func _generate_decal_texture_circle(size: int = 256) -> ImageTexture:
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = Vector2(float(size) / 2.0, float(size) / 2.0)
	var radius = size * 0.48
	for y in size:
		for x in size:
			var d = Vector2(x, y).distance_to(center)
			var a = 0.0
			if d <= radius:
				var rim = 1.0 - clamp((d - radius*0.88)/ (radius*0.12), 0.0, 1.0)
				a = 0.65 * rim * (1.0 - pow(clamp(d/radius,0,1), 2.5))
				# borde más marcado
				if d > radius*0.92:
					a = 0.85
			img.set_pixel(x, y, Color(1,1,1, a))
	var tex = ImageTexture.create_from_image(img)
	return tex

func _generate_decal_texture_cone(size: int = 256, angle_deg: float = 60.0) -> ImageTexture:
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0,0,0,0))
	var center = Vector2(float(size) / 2.0, float(size - 1)) # apex abajo centro
	var half = deg_to_rad(angle_deg/2.0)
	var max_r = size * 0.95
	for y in size:
		for x in size:
			var p = Vector2(x,y) - center
			var dist = p.length()
			if dist < 1.0 or dist > max_r:
				continue
			var ang = atan2(p.x, -p.y) # 0 es arriba (-Y)
			if abs(ang) <= half + 0.02:
				var edge = abs(ang) - half
				var alpha = 0.55
				if edge > 0:
					alpha *= clamp(1.0 - edge/0.25, 0.0, 1.0)
				# fade por distancia cerca apex
				var d_alpha = clamp((dist - 8.0)/ max_r, 0.0, 1.0)
				alpha *= d_alpha
				# borde exterior más brillante
				if abs(ang) > half - 0.08 or dist > max_r*0.92:
					alpha = 0.9
				img.set_pixel(x, y, Color(1,1,1, alpha))
	var tex = ImageTexture.create_from_image(img)
	return tex

func _create_decal_node(pos_3d: Vector3, size_3d: Vector3, tex: Texture2D, col: Color, energy: float, fade: float = 0.3) -> Decal:
	var d = Decal.new()
	d.size = size_3d
	d.texture_albedo = tex
	d.texture_emission = tex
	d.modulate = col
	d.emission_energy = energy
	d.upper_fade = fade
	d.lower_fade = fade
	d.normal_fade = 0.2
	d.cull_mask = 1 # capa 0 / vis-layer
	d.position = pos_3d
	# Decal proyecta en -Y por defecto: no rotar (Y-up). Altura del AABB cubre relieve => Y grande
	return d

# Helper genérico: eleva Node3D al terreno y hace discos conformantes, anillos con no_depth_test
func _conform_ground_node(root: Node3D, center_2d: Vector2, radius_2d: float):
	var map_node = get_tree().get_first_node_in_group("map")
	if not is_instance_valid(map_node) or not is_instance_valid(map_node.get("terrain_node")):
		return
	if not is_instance_valid(root):
		return
	var h = _sample_terrain_height(center_2d, map_node)
	# Elevar root justo por encima del terreno (eps 0.05 base). Si root ya está en altura, ajustar.
	# Detectar si root es hijo de sub_viewport (world pos) o de world_root (local offset)
	var is_world = root.get_parent() and root.get_parent().name == "SubViewport" or root.get_parent() is SubViewport or (is_instance_valid(map_node.sub_viewport) and root.get_parent() == map_node.sub_viewport)
	if is_world:
		var s = map_node.scale_factor if "scale_factor" in map_node else 0.02
		var cz = map_node.correction_z if "correction_z" in map_node else 1.41421356
		root.position = Vector3(center_2d.x * s, h + 0.05, center_2d.y * s * cz)
		# Si es mundo, reemplazar cilindros internos
		for child in root.get_children():
			if child is MeshInstance3D and child.mesh is CylinderMesh:
				var cyl = child.mesh as CylinderMesh
				# Reemplazar por disco conformante del mismo radio (usar radius_2d si provisto, sino derivar de cyl)
				var rad = radius_2d if radius_2d > 0.01 else cyl.top_radius / (map_node.scale_factor if "scale_factor" in map_node else 0.02)
				var disc = _make_circle_disc_conforming(center_2d, rad, map_node)
				child.mesh = disc
				if child.material_override is StandardMaterial3D:
					child.material_override.no_depth_test = true
					child.material_override.render_priority = 2
					child.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			elif child is MeshInstance3D and child.material_override is StandardMaterial3D:
				child.material_override.no_depth_test = true
				child.material_override.render_priority = 2
				child.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		# Local a world_root (offset relativo)
		# root.position.y debe ser delta respecto base_y
		root.position.y = h - _attack_vfx_base_y() + 0.05
		for child in root.get_children():
			if child is MeshInstance3D and child.mesh is CylinderMesh:
				var cyl = child.mesh as CylinderMesh
				var rad = radius_2d if radius_2d > 0.01 else cyl.top_radius / (map_node.scale_factor if "scale_factor" in map_node else 0.02)
				var disc = _make_circle_disc_conforming(center_2d, rad, map_node)
				child.mesh = disc
				if child.material_override is StandardMaterial3D:
					child.material_override.no_depth_test = true
					child.material_override.render_priority = 2
					child.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			elif child is MeshInstance3D and child.material_override is StandardMaterial3D:
				child.material_override.no_depth_test = true
				child.material_override.render_priority = 2
				child.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			# Recursivo para rings dentro de rings
			for sub in child.get_children():
				if sub is MeshInstance3D and sub.material_override is StandardMaterial3D:
					sub.material_override.no_depth_test = true
					sub.material_override.render_priority = 2
					sub.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

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

func _on_taunt_event(data: Dictionary):
	if typeof(data) != TYPE_DICTIONARY: return
	var epicenter = Vector2(data.get("x", 0.0), data.get("y", 0.0))
	var radius = float(data.get("radius", 220.0))
	var duration = float(data.get("duration", 4000.0))
	var affected_ids = data.get("affectedEnemies", [])
	
	var affected_nodes: Array[Node2D] = []
	for eid in affected_ids:
		var en = enemies.get(str(eid))
		if is_instance_valid(en):
			affected_nodes.append(en)
	
	var proj_pos = _get_projected_position(epicenter)
	
	var taunt_vfx = TauntVFX.new()
	if is_instance_valid(world) and is_instance_valid(world.entities_node):
		world.entities_node.add_child(taunt_vfx)
		taunt_vfx.init(null, affected_nodes, proj_pos, radius, duration)
		taunt_vfx.top_level = true

class_name BossActionHandler
extends Node

# BossActionHandler.gd - Submódulo desacoplado de EntityManager para gestionar acciones visuales y 3D de jefes:
# - Robos (Shield Steal, Life Steal)
# - Sueño Inducido (Sleep)
# - Ejecución Directa (Death Mark)
# - Ascensión Telúrica (Salto y Telégrafo de Aterrizaje)
# - Lluvia de Meteoritos y Zonas Persistentes de Meteoros

var em: Node = null # Referencia a EntityManager

var active_meteors = {} # Meteoritos activos {key: {warn_3d, meteor_3d, fall_s, landed}}
var active_meteor_zones = {} # Zonas persistentes de meteoritos {mId: {zone_2d, elapsed}}
var death_marks = {} # Marks de Ejecución Directa {mark_key: {enemy_id, node, target_id}}
var active_ascensions = {} # Saltos de Ascensión Telúrica {enemy_id: {node, tw_offsets, warn_timer, beam_3d}}

const METEOR_ZONE_SCRIPT = preload("res://scripts/systems/MeteorZoneVisual.gd")
const FOLLOW_ORB_3D_SCRIPT = preload("res://scripts/entities/projectiles/FollowOrb3D.gd")

func setup(entity_manager_ref: Node) -> void:
	em = entity_manager_ref

# ==============================================================================
# 1. SHIELD STEAL (Robo de Escudo)
# ==============================================================================
func handle_shield_steal_action(data: Dictionary) -> void:
	if not is_instance_valid(em): return
	var action = data.get("action", "")
	var enemy_id = str(data.get("id", ""))
	var t_id = str(data.get("targetId", ""))
	var steal_id: String = "steal_" + enemy_id

	if action == "shield_steal_start":
		if em.active_areas.has(steal_id) and is_instance_valid(em.active_areas[steal_id]):
			em.active_areas[steal_id].queue_free()
			em.active_areas.erase(steal_id)

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
		if is_instance_valid(em.world) and is_instance_valid(em.world.entities_node):
			em.world.entities_node.add_child(steal_node)
		else:
			em.add_child(steal_node)
		if steal_node.has_method("setup"):
			var en = em.enemies.get(enemy_id) if em.enemies.has(enemy_id) else null
			steal_node.setup(data, en)
		em.active_areas[steal_id] = steal_node

	elif action == "shield_steal_tick":
		if em.active_areas.has(steal_id) and is_instance_valid(em.active_areas[steal_id]):
			var sn = em.active_areas[steal_id]
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
			if is_instance_valid(em.world) and is_instance_valid(em.world.local_player) and str(em.world.local_player.get("entity_id")) == t_id:
				player_node = em.world.local_player
			elif em.remote_players.has(t_id):
				player_node = em.remote_players[t_id]
			if is_instance_valid(player_node):
				player_pos3d = Vector3(
					player_node.global_position.x * s_factor,
					0.5,
					player_node.global_position.y * s_factor * corr_z
				)

			var enemy_node: Node2D = em.enemies.get(enemy_id) if em.enemies.has(enemy_id) else null

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
		if em.active_areas.has(steal_id) and is_instance_valid(em.active_areas[steal_id]):
			em.active_areas[steal_id].queue_free()
			em.active_areas.erase(steal_id)

# ==============================================================================
# 2. LIFE STEAL (Robo de Vida)
# ==============================================================================
func handle_life_steal_action(data: Dictionary) -> void:
	if not is_instance_valid(em): return
	var action = data.get("action", "")
	var enemy_id = str(data.get("id", ""))
	var t_id = str(data.get("targetId", ""))
	var steal_id: String = "lifesteal_" + enemy_id

	if action == "life_steal_start":
		if em.active_areas.has(steal_id) and is_instance_valid(em.active_areas[steal_id]):
			em.active_areas[steal_id].queue_free()
			em.active_areas.erase(steal_id)

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
		if is_instance_valid(em.world) and is_instance_valid(em.world.entities_node):
			em.world.entities_node.add_child(steal_node)
		else:
			em.add_child(steal_node)
		if steal_node.has_method("setup"):
			var en = em.enemies.get(enemy_id) if em.enemies.has(enemy_id) else null
			steal_node.setup(data, en)
		em.active_areas[steal_id] = steal_node

	elif action == "life_steal_tick":
		if em.active_areas.has(steal_id) and is_instance_valid(em.active_areas[steal_id]):
			var sn = em.active_areas[steal_id]
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
			if is_instance_valid(em.world) and is_instance_valid(em.world.local_player) and str(em.world.local_player.get("entity_id")) == t_id:
				player_node = em.world.local_player
			elif em.remote_players.has(t_id):
				player_node = em.remote_players[t_id]
			if is_instance_valid(player_node):
				player_pos3d = Vector3(
					player_node.global_position.x * s_factor,
					0.5,
					player_node.global_position.y * s_factor * corr_z
				)

			var enemy_node: Node2D = em.enemies.get(enemy_id) if em.enemies.has(enemy_id) else null

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
		if em.active_areas.has(steal_id) and is_instance_valid(em.active_areas[steal_id]):
			em.active_areas[steal_id].queue_free()
			em.active_areas.erase(steal_id)

# ==============================================================================
# 3. SLEEP (Sueño Inducido)
# ==============================================================================
func handle_sleep_action(data: Dictionary) -> void:
	if not is_instance_valid(em): return
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

	var enemy_node: Node2D = em.enemies.get(enemy_id) if em.enemies.has(enemy_id) else null
	var start_pos: Vector2 = Vector2(ex, ey)
	if is_instance_valid(enemy_node):
		start_pos = enemy_node.global_position

	for t_id in targets:
		t_id = str(t_id)
		var player_node: Node2D = null
		if is_instance_valid(em.world) and is_instance_valid(em.world.local_player) and str(em.world.local_player.get("entity_id")) == t_id:
			player_node = em.world.local_player
		elif em.remote_players.has(t_id):
			player_node = em.remote_players[t_id]
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
		if is_instance_valid(em.world) and is_instance_valid(em.world.entities_node):
			em.world.entities_node.add_child(puff)
			puff.global_position = player_node.global_position
			puff.emitting = true
			get_tree().create_timer(0.55).timeout.connect(puff.queue_free)

# ==============================================================================
# 4. DEATH MARK (Ejecución Directa)
# ==============================================================================
func handle_death_mark_action(data: Dictionary) -> void:
	if not is_instance_valid(em): return
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

	if not is_instance_valid(em.world):
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
		if is_instance_valid(em.world.local_player) and str(em.world.local_player.get("entity_id")) == t_id:
			player_node = em.world.local_player
		elif em.remote_players.has(t_id):
			player_node = em.remote_players[t_id]
		if not is_instance_valid(player_node):
			continue

		var mark_key = enemy_id + "_" + t_id
		if death_marks.has(mark_key) and is_instance_valid(death_marks[mark_key].node):
			death_marks[mark_key].node.queue_free()
			death_marks.erase(mark_key)

		var mark_root = Node3D.new()
		mark_root.name = "ExecutionMark3D_" + mark_key
		var pos3d = Vector3.ZERO
		if is_instance_valid(em.world.entities_node) and em.world.entities_node.get("world_root_3d") != null:
			pos3d = em.world.entities_node.world_root_3d.position
		else:
			pos3d = Vector3(player_node.global_position.x * s_factor, 0.2, player_node.global_position.y * s_factor * corr_z)
		mark_root.global_position = pos3d
		vp.add_child(mark_root)

		# Calavera flotante (esfera hueso) con aro rojo giratorio
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

		# Auto-eliminarse al expirar el cast
		mark_root.create_tween().tween_interval(cast_time_s).tween_callback(mark_root.queue_free)

		death_marks[mark_key] = { "enemy_id": enemy_id, "node": mark_root, "target_id": t_id }

		# Actualizar posición del mark para seguir al jugador mientras dura el cast
		var tracker = func():
			if is_instance_valid(player_node) and is_instance_valid(mark_root) and is_instance_valid(em) and is_instance_valid(em.world):
				var follow3d = Vector3.ZERO
				if is_instance_valid(em.world.entities_node) and em.world.entities_node.get("world_root_3d") != null:
					var base3d = em.world.entities_node.world_root_3d
					follow3d = base3d.global_position + Vector3(player_node.global_position.x * s_factor, 0.35, player_node.global_position.y * s_factor * corr_z)
				else:
					follow3d = Vector3(player_node.global_position.x * s_factor, 0.35, player_node.global_position.y * s_factor * corr_z)
				mark_root.global_position = follow3d
		mark_root.set_process(true)
		mark_root._process = tracker

# ==============================================================================
# 5. ASCENSIÓN TELÚRICA (Salto, Vuelo y Aterrizaje)
# ==============================================================================
func handle_ascension_action(data: Dictionary) -> void:
	if not is_instance_valid(em): return
	var action = str(data.get("action", ""))
	var map_node = get_tree().get_first_node_in_group("map")
	if not is_instance_valid(map_node) or map_node.get("sub_viewport") == null:
		return
	var s_factor: float = map_node.scale_factor if "scale_factor" in map_node else 0.02
	var correction_z: float = map_node.correction_z if "correction_z" in map_node else 1.41421356
	var vp: SubViewport = map_node.sub_viewport
	var enemy_id = str(data.get("id", ""))
	var enemy_node = em.enemies.get(enemy_id) if em.enemies.has(enemy_id) else null

	if action == "ascension_cast":
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
		ascension_clear_jump(enemy_id)

		if is_instance_valid(enemy_node):
			var dist = Vector2(sx, sy).distance_to(Vector2(ex, ey))
			var peak_h = clampf(6.0 + dist * 0.008, 6.0, 10.0)
			var tw_offs = enemy_node.create_tween()
			tw_offs.tween_property(enemy_node, "_ascension_y_offset", peak_h, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			active_ascensions[enemy_id] = {"node": enemy_node, "tw_pos": null, "tw_offs": tw_offs, "warn_timer": null}

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
		ascension_land_enemy(enemy_id, Vector2(tx, ty))
		_spawn_ascension_impact_3d(vp, tx, ty, radius, s_factor, correction_z)
		if is_instance_valid(VFXSystem):
			VFXSystem.spawn_explosion(Vector2(tx, ty), max(0.5, radius / 100.0))
		if is_instance_valid(em.world) and is_instance_valid(em.world.local_player):
			var lp = em.world.local_player
			if lp.global_position.distance_to(Vector2(tx, ty)) <= radius and lp.has_method("apply_shake"):
				lp.apply_shake(4.0)
		return

func ascension_land_enemy(enemy_id: String, dest: Vector2) -> void:
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

func ascension_clear_jump(enemy_id: String) -> void:
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

func ascension_reset_all_offsets() -> void:
	if not is_instance_valid(em): return
	if is_instance_valid(em.world) and is_instance_valid(em.world.local_player):
		var lp = em.world.local_player
		if lp.get("_ascension_y_offset") != null and lp._ascension_y_offset != 0.0:
			lp._ascension_y_offset = 0.0
	for t_id in em.remote_players.keys():
		var p = em.remote_players[t_id]
		if is_instance_valid(p) and p.get("_ascension_y_offset") != null and p._ascension_y_offset != 0.0:
			p._ascension_y_offset = 0.0
	for enemy_id in active_ascensions.keys():
		ascension_clear_jump(enemy_id)

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

	var _map_asc = get_tree().get_first_node_in_group("map")
	if is_instance_valid(_map_asc) and is_instance_valid(_map_asc.get("terrain_node")) and is_instance_valid(em):
		var _h = em._sample_terrain_height(Vector2(tx, ty), _map_asc)
		root.position.y = _h + 0.05
		var _disc = em._make_circle_disc_conforming(Vector2(tx, ty), radius * 0.9, _map_asc)
		fill.mesh = _disc
		ring_mat.no_depth_test = true
		ring_mat.render_priority = 2
		ring.position.y = 0.05

	var pulse = root.create_tween().set_loops()
	pulse.tween_property(ring, "scale", Vector3(1.12, 1.12, 1.12), warn_s * 0.45).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(ring, "scale", Vector3.ONE, warn_s * 0.45).set_trans(Tween.TRANS_SINE)
	var tw = root.create_tween()
	tw.tween_interval(warn_s + 0.1)
	tw.tween_callback(root.queue_free)
	return root

func _spawn_ascension_impact_3d(vp, tx: float, ty: float, radius: float, s_factor: float, correction_z: float) -> void:
	var _map_ai = get_tree().get_first_node_in_group("map")
	var _h_ai = 0.05
	if is_instance_valid(_map_ai) and is_instance_valid(_map_ai.get("terrain_node")) and is_instance_valid(em):
		_h_ai = em._sample_terrain_height(Vector2(tx, ty), _map_ai) + 0.08
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

# ==============================================================================
# 6. METEOROS (Lluvia de Meteoritos y Caída)
# ==============================================================================
func handle_meteor_action(data: Dictionary) -> void:
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

func _start_meteor_fall(key: String) -> void:
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

func _spawn_meteor_warning_3d(vp, tx: float, ty: float, radius: float, s_factor: float, correction_z: float) -> Node3D:
	var root = Node3D.new()
	root.name = "MeteorWarn_" + str(tx) + "_" + str(ty)
	var r3d = radius * s_factor
	root.position = Vector3(tx * s_factor, 0.02, ty * s_factor * correction_z)
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

	var _map_m = get_tree().get_first_node_in_group("map")
	if is_instance_valid(_map_m) and is_instance_valid(_map_m.get("terrain_node")) and is_instance_valid(em):
		var _h = em._sample_terrain_height(Vector2(tx, ty), _map_m)
		root.position.y = _h + 0.05
		var _disc = em._make_circle_disc_conforming(Vector2(tx, ty), radius * 0.88, _map_m)
		fill.mesh = _disc
		ring.position.y = 0.06

	var tw = root.create_tween().set_loops()
	tw.tween_property(ring, "scale", Vector3(1.18, 1.18, 1.0), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(ring, "scale", Vector3(1.0, 1.0, 1.0), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	return root

func _spawn_meteor_model_3d(vp, tx: float, ty: float, fall_height: float, meteor_size: float, s_factor: float, correction_z: float) -> Node3D:
	var root = Node3D.new()
	root.name = "Meteor3D_" + str(tx) + "_" + str(ty)
	root.position = Vector3(tx * s_factor, fall_height * s_factor, ty * s_factor * correction_z)
	var s3d = meteor_size * s_factor
	root.scale = Vector3(s3d, s3d, s3d)
	vp.add_child(root)

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

	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.45, 0.1)
	light.light_energy = 3.0
	light.omni_range = 5.0
	root.add_child(light)

	return root

func _spawn_meteor_impact_3d(vp, tx: float, ty: float, radius: float, _meteor_size: float, s_factor: float, correction_z: float) -> void:
	var _map_mi = get_tree().get_first_node_in_group("map")
	var _h_mi = 0.05
	if is_instance_valid(_map_mi) and is_instance_valid(_map_mi.get("terrain_node")) and is_instance_valid(em):
		_h_mi = em._sample_terrain_height(Vector2(tx, ty), _map_mi) + 0.08
	var pos_3d = Vector3(tx * s_factor, _h_mi, ty * s_factor * correction_z)
	var r3d = max(0.1, radius * s_factor)

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

	var impact_light = OmniLight3D.new()
	impact_light.light_color = Color(1.0, 0.5, 0.1)
	impact_light.light_energy = 8.0
	impact_light.omni_range = r3d * 3.0
	impact_light.position = pos_3d
	vp.add_child(impact_light)
	var tw_l = impact_light.create_tween()
	tw_l.tween_property(impact_light, "light_energy", 0.0, 0.3)
	tw_l.finished.connect(impact_light.queue_free)

# ==============================================================================
# 7. METEOR ZONE (Zona Persistente de Meteoritos)
# ==============================================================================
func handle_meteor_zone_action(data: Dictionary) -> void:
	if not is_instance_valid(em): return
	var action = str(data.get("action", ""))
	var m_id = str(data.get("mId", ""))
	if m_id.is_empty():
		return
	if action == "meteor_zone_end":
		if active_meteor_zones.has(m_id):
			var entry = active_meteor_zones[m_id]
			if is_instance_valid(entry.get("zone_2d")):
				entry.zone_2d.queue_free()
			active_meteor_zones.erase(m_id)
		return
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
	if is_instance_valid(em.world) and is_instance_valid(em.world.entities_node):
		em.world.entities_node.add_child(zone_2d)
	else:
		em.add_child(zone_2d)
	zone_2d.setup(data, map_node)
	active_meteor_zones[m_id] = { "zone_2d": zone_2d }

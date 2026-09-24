class_name EntityMechanicsVFX
extends Node

# EntityMechanicsVFX.gd - Submódulo desacoplado de Entity.gd para:
# - Acciones y mecánicas visuales de combate de jefes (Survival Dome, Wall Dome, Bomb, Reflect, Orbital Strike)
# - Auras 3D (Daño, Curación, Velocidad)
# - Auras de Color y Pilares (Puzzle de Colores)
# - Setup visual de Orbe de Agua 3D

var entity: CharacterBody2D = null

const ColorBeamShader = preload("res://resources/shaders/color_beam.gdshader")
const ColorAuraShader = preload("res://resources/shaders/color_aura.gdshader")
const VoidAuraShader = preload("res://resources/shaders/void_aura.gdshader")
const DomeForceFieldShader = preload("res://resources/shaders/dome_force_field.gdshader")
const HealAuraShader = preload("res://resources/shaders/heal_aura.gdshader")
const AuraPulseRingShader = preload("res://resources/shaders/aura_pulse_ring.gdshader")
const VFX_HexTexture = preload("res://VFX/textures/T_Hex1_inv.jpg")
const VFX_SmokeTexture = preload("res://VFX/textures/T_VFX_Smoke_4_alpha.PNG")
const VFX_FlareTexture = preload("res://VFX/textures/T_VFX_Flare_15.PNG")
const VFX_SparkleTexture = preload("res://VFX/textures/T_VFX_SparklesF21.jpg")
const VFX_WaterNormalTexture = preload("res://VFX/textures/T_GW_WaterNormal_01_b.PNG")
const TEX_REFLECT_AURA = preload("res://assets/Efectos de Skills/Reflect (Rojo)/Reflect Aura (Transp).png")
const TEX_REFLECT_IMPACT = preload("res://assets/Efectos de Skills/Reflect (Rojo)/Reflect (Transp).png")

var _color_aura_3d_root: Node3D = null
var is_orbital_active: bool = false

func setup(entity_ref: CharacterBody2D) -> void:
	entity = entity_ref

# ==============================================================================
# Domo de Supervivencia - helpers del campo de fuerza
# ==============================================================================
func _get_entity_manager() -> Node:
	var world = get_tree().get_first_node_in_group("world_node")
	if is_instance_valid(world):
		var m = world.get_node_or_null("EntityManager")
		if is_instance_valid(m):
			return m
	return null

func _make_dome_shell_mat(alpha_scale_p: float, noise_scale_p: float, base_alpha_p: float) -> ShaderMaterial:
	var mat = ShaderMaterial.new()
	mat.shader = DomeForceFieldShader
	mat.set_shader_parameter("deep_color", Color(0.5, 0.22, 0.02, 1.0))
	mat.set_shader_parameter("base_color", Color(1.0, 0.68, 0.14, 1.0))
	mat.set_shader_parameter("rim_color", Color(1.0, 0.95, 0.7, 1.0))
	mat.set_shader_parameter("alpha_scale", alpha_scale_p)
	mat.set_shader_parameter("noise_scale", noise_scale_p)
	mat.set_shader_parameter("base_alpha", base_alpha_p)
	mat.set_shader_parameter("intensity", 0.0)
	return mat

func _tween_shader_param(host: Node, mat: ShaderMaterial, param: String, from_v: float, to_v: float, delay: float, dur: float) -> void:
	if not is_instance_valid(host) or not is_instance_valid(mat):
		return
	mat.set_shader_parameter(param, from_v)
	var tw = host.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_method(func(v): mat.set_shader_parameter(param, v), from_v, to_v, dur)

func _play_dome_impact(dome_3d: Node3D, dir_world: Vector3, delay: float, dur: float) -> void:
	if not is_instance_valid(dome_3d):
		return
	var shell_mats = dome_3d.get_meta("shell_mats", [])
	for m in shell_mats:
		if m is ShaderMaterial:
			m.set_shader_parameter("impact_dir", dir_world)
			_tween_shader_param(dome_3d, m, "impact", 0.0, 1.0, delay, dur)

func _spawn_dome_impact_sparks(dome_3d: Node3D, r3d: float, dir_world: Vector3, correction_z: float, delay: float) -> void:
	if not is_instance_valid(dome_3d) or r3d <= 0.01:
		return
	# Local: dome_3d aplica correction_z en Z → hay que quitarlo de la Z del mundo
	var base = Vector3(dir_world.x, 0.0, dir_world.z / maxf(correction_z, 0.001))
	if base.length() < 0.001:
		base = Vector3(1.0, 0.0, 0.0)
	base = base.normalized()
	var root = Node3D.new()
	root.name = "DomeImpactSparks"
	dome_3d.add_child(root)
	var s_grad = Gradient.new()
	s_grad.set_color(0, Color(2.5, 1.8, 0.7, 1.0))
	s_grad.add_point(0.5, Color(1.5, 0.7, 0.15, 0.9))
	s_grad.set_color(1, Color(0.5, 0.1, 0.0, 0.0))
	for i in 3:
		var ang = deg_to_rad(-40.0 + 40.0 * i)
		var d = Vector3(base.x * cos(ang) - base.z * sin(ang), 0.0, base.x * sin(ang) + base.z * cos(ang))
		var p = CPUParticles3D.new()
		p.one_shot = true
		p.emitting = false
		p.amount = 22
		p.lifetime = 0.7
		p.explosiveness = 1.0
		p.position = d * r3d + Vector3(0.0, r3d * 0.15, 0.0)
		p.direction = Vector3(d.x, 0.55, d.z)
		p.spread = 40.0
		p.gravity = Vector3(0.0, -7.0, 0.0)
		p.initial_velocity_min = 3.5
		p.initial_velocity_max = 8.0
		p.scale_amount_min = 0.25
		p.scale_amount_max = 0.55
		p.color_ramp = s_grad
		var q = QuadMesh.new()
		q.size = Vector2(0.3, 0.3)
		var m3 = StandardMaterial3D.new()
		m3.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m3.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m3.vertex_color_use_as_albedo = true
		m3.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m3.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m3.albedo_texture = VFX_FlareTexture
		m3.cull_mode = BaseMaterial3D.CULL_DISABLED
		q.material = m3
		p.mesh = q
		root.add_child(p)
	var tw = root.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func():
		if is_instance_valid(root):
			for c in root.get_children():
				if c is CPUParticles3D:
					c.emitting = true
	)
	tw.tween_interval(2.2)
	tw.tween_callback(func():
		if is_instance_valid(root):
			root.queue_free()
	)

func _fade_out_dome(dome_3d: Node3D, delay: float, dur: float) -> void:
	if not is_instance_valid(dome_3d):
		return
	var shell_mats = dome_3d.get_meta("shell_mats", [])
	for m in shell_mats:
		if m is ShaderMaterial:
			var cur = float(m.get_shader_parameter("intensity"))
			_tween_shader_param(dome_3d, m, "intensity", cur, 0.0, delay, dur)
	var g_mat = dome_3d.get_meta("ground_mat", null)
	if g_mat is ShaderMaterial:
		var cur_g = float(g_mat.get_shader_parameter("intensity"))
		_tween_shader_param(dome_3d, g_mat, "intensity", cur_g, 0.0, delay, dur)
	var light = dome_3d.get_meta("light", null)
	if light is OmniLight3D and is_instance_valid(light):
		var tw = light.create_tween()
		tw.tween_interval(delay)
		tw.tween_property(light, "light_energy", 0.0, dur)
	var embers = dome_3d.get_meta("embers", null)
	if embers is CPUParticles3D and is_instance_valid(embers):
		embers.lifetime = 0.5
		var tw_e = embers.create_tween()
		tw_e.tween_interval(delay)
		tw_e.tween_callback(func():
			if is_instance_valid(embers):
				embers.emitting = false
		)
	var sd_mat = dome_3d.get_meta("safe_disc_mat", null)
	if sd_mat is StandardMaterial3D:
		var tw_s = dome_3d.create_tween()
		tw_s.tween_interval(delay)
		var par = tw_s.set_parallel(true)
		par.tween_property(sd_mat, "albedo_color:a", 0.0, dur)
		par.tween_property(sd_mat, "emission_energy_multiplier", 0.0, dur)
	# danger_disc (área de peligro) - desvanecer y encoger
	var d_mat = dome_3d.get_meta("danger_disc_mat", null)
	if d_mat is StandardMaterial3D:
		var tw_d = dome_3d.create_tween()
		tw_d.tween_interval(delay)
		var par_d = tw_d.set_parallel(true)
		par_d.tween_property(d_mat, "albedo_color:a", 0.0, dur)
		par_d.tween_property(d_mat, "emission_energy_multiplier", 0.0, dur)
	var danger_disc = dome_3d.get_meta("danger_disc", null)
	if danger_disc is MeshInstance3D and danger_disc.mesh is CylinderMesh:
		var tw_disc = dome_3d.create_tween()
		tw_disc.tween_interval(delay)
		tw_disc.tween_property(danger_disc.mesh, "top_radius", 0.01, dur).set_ease(Tween.EASE_IN)
		tw_disc.parallel().tween_property(danger_disc.mesh, "bottom_radius", 0.01, dur).set_ease(Tween.EASE_IN)

# ==============================================================================
# 1. ENEMY ACTION (Acciones de Combate de Enemigos / Jefes)
# ==============================================================================
func handle_enemy_action(data: Dictionary) -> void:
	if not is_instance_valid(entity): return
	if str(data.get("id", "")) != entity.entity_id: return
	var action = str(data.get("action", ""))

	match action:
		"orbital_strike_start": 
			is_orbital_active = true
		"orbital_strike_static":
			stop_orbital_orbit()
		"orbital_strike_fire": 
			is_orbital_active = false
			fire_orbital_strike()
		"survival_dome_charging":
			var boss_x_net = float(data.get("bossX", entity.global_position.x))
			var boss_y_net = float(data.get("bossY", entity.global_position.y))
			entity._active_survival_dome = {
				"safe_pos": Vector2(float(data.get("safeX", 0.0)), float(data.get("safeY", 0.0))),
				"safe_radius": float(data.get("safeRadius", 150.0)),
				"fire_range": float(data.get("fireRange", 800.0)),
				"duration": float(data.get("duration", 3000.0)) / 1000.0,
				"time_elapsed": 0.0,
				"boss_pos": Vector2(boss_x_net, boss_y_net)
			}
			entity.queue_redraw()
			if is_instance_valid(entity.world_root_3d):
				var map_node = get_tree().get_first_node_in_group("map")
				if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
					var s_factor = map_node.scale_factor if "scale_factor" in map_node else 0.02
					var correction_z = map_node.correction_z if "correction_z" in map_node else 1.41421356
					var has_terrain_d = is_instance_valid(map_node.get("terrain_node")) and map_node.get("terrain_node") != null
					var mgr_d = _get_entity_manager()
					var boss_2d = Vector2(boss_x_net, boss_y_net)
					var safe_pos = entity._active_survival_dome.safe_pos
					var safe_r3d = entity._active_survival_dome.safe_radius * s_factor
					var fire_r3d = entity._active_survival_dome.fire_range * s_factor
					# El domo se apoya en el suelo (y=0 o altura de terreno), no en la altura del boss
					var boss_base_y = 0.0
					var safe_base_y = 0.0
					if has_terrain_d and is_instance_valid(mgr_d) and mgr_d.has_method("_sample_terrain_height"):
						boss_base_y = mgr_d._sample_terrain_height(boss_2d, map_node)
						safe_base_y = mgr_d._sample_terrain_height(safe_pos, map_node)
					# Limpia un domo anterior (recasteo mientras aún se está desvaneciendo)
					for old_dome in entity.world_root_3d.get_children():
						if String(old_dome.name).begins_with("Dome3D_") or String(old_dome.name).begins_with("DangerDisc_"):
							old_dome.queue_free()
					var vp = map_node.sub_viewport
					for old_dome in vp.get_children():
						if String(old_dome.name).begins_with("Dome3D_") or String(old_dome.name).begins_with("DangerDisc_"):
							old_dome.queue_free()
					var dome_3d = Node3D.new()
					dome_3d.name = "Dome3D_" + entity.entity_id
					# Posición absoluta en el viewport del mapa (no sigue al boss)
					dome_3d.position = Vector3(safe_pos.x * s_factor, safe_base_y, safe_pos.y * s_factor * correction_z)
					# correction_z del mapa: la huella del domo se dibuja circular en 2D
					dome_3d.scale = Vector3(1.0, 1.0, correction_z)
					vp.add_child(dome_3d)
					dome_3d.set_meta("center_world", dome_3d.position)
					# Posición del boss al casteo (centro de la explosión)
					var explosion_center = Vector3(boss_2d.x * s_factor, boss_base_y, boss_2d.y * s_factor * correction_z)
					dome_3d.set_meta("explosion_center", explosion_center)
					var danger_disc = MeshInstance3D.new()
					danger_disc.name = "DangerDisc_" + entity.entity_id
					var disc_mesh = CylinderMesh.new()
					disc_mesh.top_radius = 0.01
					disc_mesh.bottom_radius = 0.01
					disc_mesh.height = 0.02
					danger_disc.mesh = disc_mesh
					var d_mat = StandardMaterial3D.new()
					d_mat.albedo_color = Color(1.0, 0.1, 0.0, 0.25)
					d_mat.emission_enabled = true
					d_mat.emission = Color(1.0, 0.15, 0.0)
					d_mat.emission_energy_multiplier = 1.5
					d_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					d_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					danger_disc.material_override = d_mat
					# danger_disc se coloca directamente en vp centrado exactamente en explosion_center
					danger_disc.position = explosion_center + Vector3(0, 0.01, 0)
					danger_disc.scale = Vector3(1.0, 1.0, correction_z)
					vp.add_child(danger_disc)
					dome_3d.set_meta("danger_disc", danger_disc)
					dome_3d.set_meta("danger_disc_mat", d_mat)
					dome_3d.set_meta("fire_r3d", fire_r3d)
					entity._active_survival_dome["danger_disc"] = danger_disc
					# El domo ya está centrado en el safe zone; safe_node en origen local
					var safe_node = Node3D.new()
					safe_node.name = "SafeDome3D"
					safe_node.position = Vector3(0, 0, 0)
					dome_3d.add_child(safe_node)

					# --- Campo de fuerza dorado: cáscara exterior + interior ---
					var shell_mats: Array = []
					var dome_hemi = MeshInstance3D.new()
					dome_hemi.name = "DomeShellOuter"
					var hemi_mesh = SphereMesh.new()
					hemi_mesh.radius = safe_r3d
					hemi_mesh.height = safe_r3d * 1.6
					hemi_mesh.is_hemisphere = true
					dome_hemi.mesh = hemi_mesh
					dome_hemi.position.y = -hemi_mesh.get_aabb().position.y
					var h_mat = _make_dome_shell_mat(1.0, 7.0, 0.22)
					dome_hemi.material_override = h_mat
					safe_node.add_child(dome_hemi)
					shell_mats.append(h_mat)

					var dome_inner = MeshInstance3D.new()
					dome_inner.name = "DomeShellInner"
					var inner_mesh = SphereMesh.new()
					inner_mesh.radius = safe_r3d * 0.92
					inner_mesh.height = safe_r3d * 1.47
					inner_mesh.is_hemisphere = true
					dome_inner.mesh = inner_mesh
					dome_inner.position.y = -inner_mesh.get_aabb().position.y
					var i_mat = _make_dome_shell_mat(0.55, 11.0, 0.14)
					dome_inner.material_override = i_mat
					safe_node.add_child(dome_inner)
					shell_mats.append(i_mat)

					# Disco de suelo con remolino dorado (mismo shader que el aura del vacío)
					var ground_disc = _make_ground_disc(VoidAuraShader, safe_r3d, 0.02)
					var g_mat: ShaderMaterial = ground_disc.material_override
					g_mat.set_shader_parameter("core_color", Color(1.0, 0.9, 0.55, 1.0))
					g_mat.set_shader_parameter("mid_color", Color(1.0, 0.6, 0.1, 1.0))
					g_mat.set_shader_parameter("rim_color", Color(1.0, 0.85, 0.35, 1.0))
					g_mat.set_shader_parameter("swirl_speed", 1.1)
					g_mat.set_shader_parameter("intensity", 0.0)
					safe_node.add_child(ground_disc)

					# Brasas doradas ascendentes → sensación de volumen
					var embers = CPUParticles3D.new()
					embers.name = "DomeEmbers"
					_configure_ring_particles(embers, safe_r3d, {
						"amount": 45, "lifetime": 2.0, "preprocess": 1.0,
						"vel_min": 0.4, "vel_max": 1.1, "spread": 16.0,
						"ring_scale": 0.88, "ring_inner": 0.35,
						"scale_min": 0.08, "scale_max": 0.2,
						"quad_size": 0.34, "color": Color(1.0, 0.75, 0.25, 0.7),
						"texture": VFX_FlareTexture
					})
					embers.position.y = 0.06
					safe_node.add_child(embers)
					embers.restart()
					embers.emitting = true

					var dome_light = OmniLight3D.new()
					dome_light.light_color = Color(1.0, 0.78, 0.3)
					dome_light.light_energy = 0.0
					dome_light.omni_range = safe_r3d * 2.5
					dome_light.position.y = safe_r3d * 0.5
					safe_node.add_child(dome_light)

					var safe_disc = MeshInstance3D.new()
					var sd_mesh = CylinderMesh.new()
					sd_mesh.top_radius = safe_r3d
					sd_mesh.bottom_radius = safe_r3d
					sd_mesh.height = 0.015
					safe_disc.mesh = sd_mesh
					var sd_mat = StandardMaterial3D.new()
					sd_mat.albedo_color = Color(1.0, 0.75, 0.2, 0.25)
					sd_mat.emission_enabled = true
					sd_mat.emission = Color(1.0, 0.7, 0.15)
					sd_mat.emission_energy_multiplier = 2.0
					sd_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					sd_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					safe_disc.material_override = sd_mat
					safe_disc.position.y = 0.016
					safe_node.add_child(safe_disc)
					safe_node.set_meta("safe_disc", safe_disc)

					# Aparición del campo de fuerza
					_tween_shader_param(dome_3d, h_mat, "intensity", 0.0, 1.0, 0.0, 0.45)
					_tween_shader_param(dome_3d, i_mat, "intensity", 0.0, 0.62, 0.0, 0.45)
					_tween_shader_param(dome_3d, g_mat, "intensity", 0.0, 0.85, 0.0, 0.45)
					var tw_light = dome_light.create_tween()
					tw_light.tween_property(dome_light, "light_energy", 4.0, 0.45)

					dome_3d.set_meta("shell_mats", shell_mats)
					dome_3d.set_meta("ground_mat", g_mat)
					dome_3d.set_meta("light", dome_light)
					dome_3d.set_meta("embers", embers)
					dome_3d.set_meta("safe_disc_mat", sd_mat)
					entity._active_survival_dome["dome_3d"] = dome_3d
					entity._active_survival_dome["s_factor"] = s_factor
					entity._active_survival_dome["correction_z"] = correction_z
					entity._active_survival_dome["fire_r3d"] = fire_r3d
					entity.tree_exiting.connect(func():
						if is_instance_valid(dome_3d):
							dome_3d.queue_free()
						if is_instance_valid(danger_disc):
							danger_disc.queue_free()
					)
		"survival_dome_fire":
			var dome_3d_ref = entity._active_survival_dome.get("dome_3d")
			var s_factor_f = float(entity._active_survival_dome.get("s_factor", 0.02))
			var cz_f = float(entity._active_survival_dome.get("correction_z", 1.41421356))
			var fire_r3d = float(entity._active_survival_dome.get("fire_r3d", float(entity._active_survival_dome.get("fire_range", 800.0)) * 0.02))
			var safe_r3d_f = float(entity._active_survival_dome.get("safe_radius", 150.0)) * s_factor_f
			
			# Limpiar y desvanecer el disco de peligro si aún existe
			var danger_disc_ref = entity._active_survival_dome.get("danger_disc")
			if not is_instance_valid(danger_disc_ref) and is_instance_valid(dome_3d_ref) and dome_3d_ref.has_meta("danger_disc"):
				danger_disc_ref = dome_3d_ref.get_meta("danger_disc")
			if is_instance_valid(danger_disc_ref):
				var tw_dd = danger_disc_ref.create_tween()
				var dd_mat = danger_disc_ref.material_override
				if is_instance_valid(dd_mat) and dd_mat is StandardMaterial3D:
					tw_dd.tween_property(dd_mat, "albedo_color:a", 0.0, 0.2)
				tw_dd.finished.connect(danger_disc_ref.queue_free)

			if is_instance_valid(dome_3d_ref):
				var map_node = get_tree().get_first_node_in_group("map")
				var vp_ok = is_instance_valid(map_node) and map_node.get("sub_viewport") != null
				var has_terrain_f = vp_ok and is_instance_valid(map_node.get("terrain_node")) and map_node.get("terrain_node") != null
				var mgr_f = _get_entity_manager()
				var h_explosion = 0.0
				if has_terrain_f and is_instance_valid(mgr_f) and mgr_f.has_method("_sample_terrain_height"):
					# Usar posición de la explosión (boss al casteo) para altura de terreno
					var explosion_center_2d = Vector2(dome_3d_ref.get_meta("explosion_center").x / s_factor_f,
													  dome_3d_ref.get_meta("explosion_center").z / (s_factor_f * cz_f))
					h_explosion = mgr_f._sample_terrain_height(explosion_center_2d, map_node)
				# Centro de la explosión = posición del boss al casteo (guardada en meta)
				var explosion_center: Vector3 = dome_3d_ref.get_meta("explosion_center", Vector3.ZERO)
				if explosion_center == Vector3.ZERO:
					var bx = float(data.get("bossX", entity.global_position.x))
					var by = float(data.get("bossY", entity.global_position.y))
					explosion_center = Vector3(bx * s_factor_f, h_explosion, by * s_factor_f * cz_f)
				explosion_center.y = h_explosion
				var center_world: Vector3 = dome_3d_ref.get_meta("center_world", explosion_center)
				var dir_impact = Vector3(center_world.x - explosion_center.x, 0.0, center_world.z - explosion_center.z)
				var dist_hit = dir_impact.length()
				if dist_hit < 0.001:
					dir_impact = Vector3(1.0, 0.0, 0.0)
				else:
					dir_impact = dir_impact.normalized()
				var t_hit = 0.22 + clampf(maxf(dist_hit - safe_r3d_f, 0.0) / maxf(fire_r3d * 1.6, 1.0), 0.05, 0.6)
				if vp_ok:
					var vp = map_node.sub_viewport
					# NOTA: Se eliminó completamente la esfera gigante plateada (flash)
					var damage_area = MeshInstance3D.new()
					var area_mesh = CylinderMesh.new()
					area_mesh.top_radius = fire_r3d
					area_mesh.bottom_radius = fire_r3d
					area_mesh.height = 0.01
					damage_area.mesh = area_mesh
					var area_mat = StandardMaterial3D.new()
					area_mat.albedo_color = Color(1.0, 0.15, 0.0, 0.5)
					area_mat.emission_enabled = true
					area_mat.emission = Color(1.0, 0.2, 0.0)
					area_mat.emission_energy_multiplier = 3.0
					area_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					area_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					damage_area.material_override = area_mat
					damage_area.position = explosion_center + Vector3(0, 0.01, 0)
					damage_area.scale = Vector3(1.0, 1.0, cz_f)
					vp.add_child(damage_area)
					var tw_a = damage_area.create_tween().set_parallel(true)
					tw_a.tween_property(area_mat, "albedo_color:a", 0.0, 0.5).set_ease(Tween.EASE_IN)
					tw_a.tween_property(area_mat, "emission_energy_multiplier", 0.0, 0.5).set_ease(Tween.EASE_IN)
					tw_a.finished.connect(damage_area.queue_free)

					var exp_light = OmniLight3D.new()
					exp_light.light_color = Color(1.0, 0.4, 0.05)
					exp_light.light_energy = 15.0
					exp_light.omni_range = fire_r3d * 2.0
					exp_light.position = explosion_center + Vector3(0, 0.5, 0)
					vp.add_child(exp_light)
					var tw_l = exp_light.create_tween()
					tw_l.tween_property(exp_light, "light_energy", 0.0, 0.4)
					tw_l.finished.connect(exp_light.queue_free)

					# Explosión circular con partículas que chocan contra el campo de fuerza
					if is_instance_valid(mgr_f):
						var blast_root = mgr_f._make_circle_fire_burst_shielded(fire_r3d, has_terrain_f)
						blast_root.position = Vector3(explosion_center.x, h_explosion + 0.02, explosion_center.z)
						blast_root.scale = Vector3(1.0, 1.0, cz_f)
						vp.add_child(blast_root)
						var tw_blast = blast_root.create_tween()
						tw_blast.tween_interval(2.1)
						tw_blast.tween_callback(func():
							if is_instance_valid(blast_root):
								blast_root.queue_free()
						)
						# Huella del domo: 3 esferas de colisión para que ninguna braza atraviese
						var collider_root = mgr_f._create_dome_particle_colliders(vp, center_world, safe_r3d_f)
						var tw_col = collider_root.create_tween()
						tw_col.tween_interval(2.1)
						tw_col.tween_callback(func():
							if is_instance_valid(collider_root):
								collider_root.queue_free()
						)
				# Onda de impacto + chispas sobre la cáscara (aunque no haya mapa activo)
				_play_dome_impact(dome_3d_ref, dir_impact, t_hit, 0.9)
				_spawn_dome_impact_sparks(dome_3d_ref, safe_r3d_f, dir_impact, cz_f, t_hit)
				# Desvanecer domo y área tras la explosión (rápido, ~0.8s)
				_fade_out_dome(dome_3d_ref, 0.5, 0.5)
				var tw_free = dome_3d_ref.create_tween()
				tw_free.tween_interval(1.2)
				tw_free.tween_callback(func():
					if is_instance_valid(dome_3d_ref):
						dome_3d_ref.queue_free()
				)
			entity._active_survival_dome.clear()
			entity.queue_redraw()
			if entity.has_method("_trigger_hit_flash"):
				entity._trigger_hit_flash()
		"wall_dome_start":
			var mId = data.get("mId", "wall_dome")
			if not entity.active_auras.has(mId):
				var spr = Sprite2D.new()
				if TEX_REFLECT_AURA:
					spr.texture = TEX_REFLECT_AURA
				spr.modulate = Color(0.0, 0.6, 1.0, 0.45)
				var radius = float(data.get("radius", 300.0))
				var target_scale = (radius * 2.0) / 512.0
				spr.scale = Vector2.ZERO
				entity._vfx_container_2d.add_child(spr)
				entity.active_auras[mId] = {"node": spr, "target_scale": target_scale, "type": "wall_dome", "radius": radius}
				var tw = create_tween()
				tw.tween_property(spr, "scale", Vector2(target_scale, target_scale), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				entity.queue_redraw()
		"wall_dome_end":
			var mId = data.get("mId", "wall_dome")
			if entity.active_auras.has(mId):
				var a_data = entity.active_auras[mId]
				var spr = a_data.node
				entity.active_auras.erase(mId)
				var tw = create_tween()
				tw.tween_property(spr, "scale", Vector2.ZERO, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
				tw.finished.connect(spr.queue_free)
				entity.queue_redraw()
		"throw_bomb":
			var world = get_tree().get_first_node_in_group("world_node")
			if world and world.has_method("get_node"):
				var cs = world.get_node_or_null("CombatSystem")
				if is_instance_valid(cs):
					var s_x = float(data.get("startX", entity.global_position.x))
					var s_y = float(data.get("startY", entity.global_position.y))
					var t_x = float(data.get("targetX", 0.0))
					var t_y = float(data.get("targetY", 0.0))
					var start_pos = Vector2(s_x, s_y)
					var target_pos = Vector2(t_x, t_y)
					var dist = start_pos.distance_to(target_pos)
					var travel_time = float(data.get("travelTimeMs", 1000.0)) / 1000.0
					var speed_val = dist / max(0.01, travel_time)
					var angle_val = start_pos.angle_to_point(target_pos)
					
					var proj_data = {
						"bulletType": "electron",
						"type": "electron",
						"x": s_x,
						"y": s_y,
						"range": dist,
						"bulletSpeed": speed_val,
						"angle": angle_val,
						"enemyId": entity.entity_id,
						"id": entity.entity_id,
						"lifetimeMs": float(data.get("travelTimeMs", 1000.0)),
						"radius": float(data.get("radius", 150.0)),
						"explosionRadius": float(data.get("radius", 150.0)),
						"damage": float(data.get("damage", 10.0))
					}
					cs._spawn_projectile(proj_data, "enemy")
		"bomb_explode":
			var bx = float(data.get("x", 0.0))
			var by = float(data.get("y", 0.0))
			var radius = float(data.get("radius", 150.0))
			var scale_factor = radius / 100.0
			var map_node = get_tree().get_first_node_in_group("map")
			if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
				var s_factor = map_node.scale_factor if "scale_factor" in map_node else 0.02
				var correction_z = map_node.correction_z if "correction_z" in map_node else 1.41421356
				var vp = map_node.sub_viewport
				var h_bomb = 0.08
				if is_instance_valid(map_node.get("terrain_node")):
					var em_n = get_tree().get_first_node_in_group("world_node")
					if em_n and em_n.has_node("EntityManager"):
						var mgr_b = em_n.get_node("EntityManager")
						if mgr_b and mgr_b.has_method("_sample_terrain_height"):
							h_bomb = mgr_b._sample_terrain_height(Vector2(bx,by), map_node) + 0.06
						elif map_node.has_method("get_terrain_height_at_pos"):
							h_bomb = map_node.get_terrain_height_at_pos(Vector2(bx,by)) + 0.06
					elif map_node.has_method("get_terrain_height_at_pos"):
						h_bomb = map_node.get_terrain_height_at_pos(Vector2(bx,by)) + 0.06
				var pos_3d = Vector3(bx * s_factor, h_bomb, by * s_factor * correction_z)

				var flash = MeshInstance3D.new()
				var flash_s = SphereMesh.new()
				var r3d = radius * 0.02
				flash_s.radius = r3d * 0.3
				flash_s.height = r3d * 0.6
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
		"reflect_start":
			entity.reflect_timer = float(data.get("duration", 3000.0)) / 1000.0
			print("[REFLECT-IN] Enemigo activó reflect por ", entity.reflect_timer, "s")
		"reflect_end":
			entity.reflect_timer = 0.0
			print("[REFLECT-IN] Enemigo desactivó reflect")
		"reflect_trigger":
			var target_id = str(data.get("targetId", ""))
			var target_node = null
			if target_id != "":
				for ent in get_tree().get_nodes_in_group("entities"):
					if str(ent.get("entity_id")) == target_id:
						target_node = ent; break
				if not target_node:
					var local_player = get_tree().get_first_node_in_group("player")
					if local_player and str(local_player.get("entity_id")) == target_id:
						target_node = local_player
			
			var visual_target = Vector2.ZERO
			if target_node: visual_target = target_node.global_position
			if entity.has_method("_trigger_reflect_visual"):
				entity._trigger_reflect_visual(visual_target if visual_target != Vector2.ZERO else entity.global_position + Vector2.UP)

		# ==== CHOQUE DEVASTADOR ====
		"choque_devastador_start":
			_spawn_choque_marker(data)
		"choque_devastador_charge":
			_spawn_choque_charge_trail(data)
		"choque_devastador_impact":
			_spawn_choque_impact_vfx(data)
		"choque_devastador_end":
			_cleanup_choque_marker()

func stop_orbital_orbit() -> void:
	if not is_instance_valid(entity): return
	var projs = get_tree().get_nodes_in_group("projectiles")
	for p in projs:
		if is_instance_valid(p) and str(p.get("owner_id")) == entity.entity_id:
			if p.has_method("stop_orbit"):
				p.stop_orbit()

func fire_orbital_strike() -> void:
	if not is_instance_valid(entity): return
	var projs = get_tree().get_nodes_in_group("projectiles")
	for p in projs:
		if is_instance_valid(p) and str(p.get("owner_id")) == entity.entity_id:
			if p.has_method("release_orbit"):
				p.release_orbit()

# ==============================================================================
# CHOQUE DEVASTADOR - VFX
# ==============================================================================

func _spawn_choque_marker(data: Dictionary) -> void:
	if not is_instance_valid(entity): return
	if not is_instance_valid(entity.world_root_3d): return
	var map_node = get_tree().get_first_node_in_group("map")
	if not is_instance_valid(map_node): return

	var s_factor = map_node.scale_factor if "scale_factor" in map_node else 0.02
	var correction_z = map_node.correction_z if "correction_z" in map_node else 1.41421356

	var marker_x = float(data.get("x", entity.global_position.x))
	var marker_y = float(data.get("y", entity.global_position.y))
	var ch_angle = float(data.get("angle", 0.0))
	var ch_width = float(data.get("radius", 200.0))
	var ch_range = float(data.get("range", 900.0))
	var telegraph_ms = float(data.get("warnTimeMs", 0.0))
	var charge_ms = float(data.get("duration", 1200.0))

	var root_3d = entity.world_root_3d
	var marker_3d = Node3D.new()
	marker_3d.name = "ChoqueMarker3D"
	root_3d.add_child(marker_3d)

	# Posición central del marcador
	var mid_x = marker_x + cos(ch_angle) * (ch_range * 0.5)
	var mid_y = marker_y + sin(ch_angle) * (ch_range * 0.5)
	var pos_3d = Vector3(mid_x * s_factor, 0.02, mid_y * s_factor * correction_z)
	marker_3d.position = pos_3d

	# Rotación del marcador para apuntar en la dirección de la carga
	marker_3d.rotation.y = -ch_angle - PI / 2.0

	# Rectángulo principal (BoxMesh)
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(ch_range * s_factor, 0.01, ch_width * s_factor)
	var box_mat = StandardMaterial3D.new()
	box_mat.albedo_color = Color(1.0, 0.15, 0.05, 0.22)
	box_mat.emission_enabled = true
	box_mat.emission = Color(1.0, 0.2, 0.05)
	box_mat.emission_energy_multiplier = 2.0
	box_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	box_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	box_mat.no_depth_test = true
	box_mat.render_priority = 2
	box_mesh.material = box_mat
	var box_inst = MeshInstance3D.new()
	box_inst.mesh = box_mesh
	box_inst.position.y = 0.01
	marker_3d.add_child(box_inst)

	# Borde del rectángulo (4 líneas ThinInstance o 4 BoxMesh delgados)
	var border_w = ch_width * s_factor
	var border_l = ch_range * s_factor
	var corners = [
		Vector3(-border_l * 0.5, 0.015, -border_w * 0.5),
		Vector3(border_l * 0.5, 0.015, -border_w * 0.5),
		Vector3(border_l * 0.5, 0.015, border_w * 0.5),
		Vector3(-border_l * 0.5, 0.015, border_w * 0.5)
	]
	var border_mat = StandardMaterial3D.new()
	border_mat.albedo_color = Color(1.0, 0.3, 0.1, 0.6)
	border_mat.emission_enabled = true
	border_mat.emission = Color(1.0, 0.3, 0.1)
	border_mat.emission_energy_multiplier = 3.0
	border_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	border_mat.no_depth_test = true
	border_mat.render_priority = 3
	for i in range(4):
		var line_mesh = BoxMesh.new()
		var is_horizontal = (i == 0 or i == 2)
		if is_horizontal:
			line_mesh.size = Vector3(border_l, 0.008, 0.015)
		else:
			line_mesh.size = Vector3(0.015, 0.008, border_w)
		line_mesh.material = border_mat
		var line_inst = MeshInstance3D.new()
		line_inst.mesh = line_mesh
		line_inst.position = corners[i]
		marker_3d.add_child(line_inst)

	# Flecha direccional en el extremo (triángulo simple con 2 cajas)
	var arrow_size = ch_width * 0.3
	var arrow_x = border_l * 0.5 + arrow_size * 0.5
	var arrow_mat = StandardMaterial3D.new()
	arrow_mat.albedo_color = Color(1.0, 0.4, 0.1, 0.7)
	arrow_mat.emission_enabled = true
	arrow_mat.emission = Color(1.0, 0.4, 0.1)
	arrow_mat.emission_energy_multiplier = 4.0
	arrow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	arrow_mat.no_depth_test = true
	arrow_mat.render_priority = 3
	# Ala superior
	var arrow_up = BoxMesh.new()
	arrow_up.size = Vector3(arrow_size, 0.008, border_w * 0.5)
	arrow_up.material = arrow_mat
	var arrow_up_inst = MeshInstance3D.new()
	arrow_up_inst.mesh = arrow_up
	arrow_up_inst.position = Vector3(arrow_x, 0.015, -border_w * 0.25)
	arrow_up_inst.rotation.y = PI / 6.0
	marker_3d.add_child(arrow_up_inst)
	# Ala inferior
	var arrow_down = BoxMesh.new()
	arrow_down.size = Vector3(arrow_size, 0.008, border_w * 0.5)
	arrow_down.material = arrow_mat
	var arrow_down_inst = MeshInstance3D.new()
	arrow_down_inst.mesh = arrow_down
	arrow_down_inst.position = Vector3(arrow_x, 0.015, border_w * 0.25)
	arrow_down_inst.rotation.y = -PI / 6.0
	marker_3d.add_child(arrow_down_inst)

	# Pulso de opacidad
	var pulse_tw = marker_3d.create_tween().set_loops()
	pulse_tw.tween_property(box_mat, "albedo_color:a", 0.38, 0.35)
	pulse_tw.tween_property(box_mat, "albedo_color:a", 0.18, 0.35)

	# Guardar referencia para cleanup
	entity.set_meta("choque_marker_3d", marker_3d)

	# Auto-destroy después de telegraph + charge + margen
	var total_ms = telegraph_ms + charge_ms + 500.0
	get_tree().create_timer(total_ms / 1000.0).timeout.connect(func():
		if is_instance_valid(marker_3d):
			marker_3d.queue_free()
			if entity.has_meta("choque_marker_3d"):
				entity.remove_meta("choque_marker_3d")
	)

func _spawn_choque_charge_trail(data: Dictionary) -> void:
	if not is_instance_valid(entity): return
	if not is_instance_valid(entity.world_root_3d): return
	var map_node = get_tree().get_first_node_in_group("map")
	if not is_instance_valid(map_node): return

	var s_factor = map_node.scale_factor if "scale_factor" in map_node else 0.02
	var correction_z = map_node.correction_z if "correction_z" in map_node else 1.41421356

	# Estela de partículas detrás del enemigo durante la carga
	var trail = GPUParticles3D.new()
	trail.name = "ChoqueTrail3D"
	trail.emitting = true
	trail.amount = 30
	trail.lifetime = 0.6
	trail.one_shot = false
	trail.explosiveness = 0.0
	trail.fixed_fps = 30

	var trail_mat = ParticleProcessMaterial.new()
	trail_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	trail_mat.emission_sphere_radius = 0.15
	trail_mat.direction = Vector3(0, 0, 1)
	trail_mat.spread = 15.0
	trail_mat.initial_velocity_min = 0.5
	trail_mat.initial_velocity_max = 1.5
	trail_mat.gravity = Vector3.ZERO
	trail_mat.scale_min = 0.3
	trail_mat.scale_max = 0.8
	trail_mat.color = Color(1.0, 0.4, 0.1)
	var gradient = Gradient.new()
	gradient.set_color(0, Color(1.0, 0.5, 0.1, 0.7))
	gradient.set_color(1, Color(1.0, 0.2, 0.0, 0.0))
	trail_mat.color_ramp = gradient
	trail.process_material = trail_mat

	var trail_mesh = SphereMesh.new()
	trail_mesh.radius = 0.08
	trail_mesh.height = 0.16
	var trail_mesh_mat = StandardMaterial3D.new()
	trail_mesh_mat.albedo_color = Color(1.0, 0.5, 0.1, 0.6)
	trail_mesh_mat.emission_enabled = true
	trail_mesh_mat.emission = Color(1.0, 0.4, 0.1)
	trail_mesh_mat.emission_energy_multiplier = 3.0
	trail_mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_mesh_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	trail_mesh.material = trail_mesh_mat

	trail.draw_pass_1 = trail_mesh

	entity.world_root_3d.add_child(trail)
	trail.position = Vector3(
		entity.global_position.x * s_factor,
		0.3,
		entity.global_position.y * s_factor * correction_z
	)

	# Seguir al enemigo cada frame
	var follow_tween = trail.create_tween().set_loops()
	follow_tween.tween_method(func(_delta):
		if is_instance_valid(trail) and is_instance_valid(entity):
			trail.position.x = entity.global_position.x * s_factor
			trail.position.z = entity.global_position.y * s_factor * correction_z
			trail.position.y = 0.3
	, 0.0, 1.0, 0.033)

	# Auto-destroy al terminar la carga
	var charge_ms = float(data.get("duration", 1200.0))
	get_tree().create_timer(charge_ms / 1000.0 + 0.3).timeout.connect(func():
		if is_instance_valid(trail):
			trail.emitting = false
			get_tree().create_timer(trail.lifetime + 0.1).timeout.connect(func():
				if is_instance_valid(trail):
					trail.queue_free()
			)
	)

func _spawn_choque_impact_vfx(data: Dictionary) -> void:
	if not is_instance_valid(entity): return
	if not is_instance_valid(entity.world_root_3d): return
	var map_node = get_tree().get_first_node_in_group("map")
	if not is_instance_valid(map_node): return

	var s_factor = map_node.scale_factor if "scale_factor" in map_node else 0.02
	var correction_z = map_node.correction_z if "map_node" in map_node and "correction_z" in map_node else 1.41421356

	var impact_x = float(data.get("x", entity.global_position.x))
	var impact_y = float(data.get("y", entity.global_position.y))
	var pos_3d = Vector3(impact_x * s_factor, 0.3, impact_y * s_factor * correction_z)

	var vp = map_node.sub_viewport if map_node.get("sub_viewport") else null
	if not is_instance_valid(vp):
		vp = entity.world_root_3d

	# Flash de impacto
	var flash = MeshInstance3D.new()
	var flash_s = SphereMesh.new()
	flash_s.radius = 0.3
	flash_s.height = 0.6
	flash.mesh = flash_s
	var flash_mat = StandardMaterial3D.new()
	flash_mat.albedo_color = Color(1.0, 0.6, 0.15, 0.95)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 0.6, 0.15)
	flash_mat.emission_energy_multiplier = 10.0
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.material_override = flash_mat
	flash.position = pos_3d
	vp.add_child(flash)
	var tw_f = flash.create_tween()
	tw_f.tween_property(flash, "scale", Vector3(3.0, 3.0, 3.0), 0.25)
	tw_f.parallel().tween_property(flash_mat, "albedo_color:a", 0.0, 0.25)
	tw_f.parallel().tween_property(flash_mat, "emission_energy_multiplier", 0.0, 0.25)
	tw_f.finished.connect(flash.queue_free)

	# Shockwave
	var shockwave = MeshInstance3D.new()
	var ring_mesh = TorusMesh.new()
	ring_mesh.inner_radius = 0.2
	ring_mesh.outer_radius = 0.25
	shockwave.mesh = ring_mesh
	var sw_mat = StandardMaterial3D.new()
	sw_mat.albedo_color = Color(1.0, 0.45, 0.1, 0.85)
	sw_mat.emission_enabled = true
	sw_mat.emission = Color(1.0, 0.45, 0.1)
	sw_mat.emission_energy_multiplier = 4.0
	sw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shockwave.material_override = sw_mat
	shockwave.position = pos_3d + Vector3(0, 0.02, 0)
	vp.add_child(shockwave)
	var tw_sw = shockwave.create_tween()
	tw_sw.tween_property(shockwave, "scale", Vector3(2.5, 2.5, 2.5), 0.35)
	tw_sw.parallel().tween_property(sw_mat, "albedo_color:a", 0.0, 0.35)
	tw_sw.parallel().tween_property(sw_mat, "emission_energy_multiplier", 0.0, 0.35)
	tw_sw.finished.connect(shockwave.queue_free)

	# Partículas de impacto
	var particles = GPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 25
	particles.lifetime = 0.4
	particles.explosiveness = 0.9
	var p_mat = ParticleProcessMaterial.new()
	p_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	p_mat.emission_sphere_radius = 0.1
	p_mat.direction = Vector3(0, 1, 0)
	p_mat.spread = 180.0
	p_mat.initial_velocity_min = 2.0
	p_mat.initial_velocity_max = 5.0
	p_mat.gravity = Vector3(0, -3.0, 0)
	p_mat.scale_min = 0.4
	p_mat.scale_max = 1.0
	p_mat.color = Color(1.0, 0.5, 0.1)
	particles.process_material = p_mat
	var p_mesh = BoxMesh.new()
	p_mesh.size = Vector3(0.12, 0.12, 0.12)
	var p_mesh_mat = StandardMaterial3D.new()
	p_mesh_mat.albedo_color = Color(1.0, 0.5, 0.1)
	p_mesh_mat.emission_enabled = true
	p_mesh_mat.emission = Color(1.0, 0.5, 0.1)
	p_mesh_mat.emission_energy_multiplier = 5.0
	p_mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p_mesh.material = p_mesh_mat
	particles.draw_pass_1 = p_mesh
	particles.position = pos_3d
	vp.add_child(particles)
	get_tree().create_timer(0.6).timeout.connect(func():
		if is_instance_valid(particles): particles.queue_free()
	)

	# Luz de impacto
	var light = OmniLight3D.new()
	light.position = pos_3d + Vector3(0, 0.5, 0)
	light.light_color = Color(1.0, 0.5, 0.15)
	light.light_energy = 12.0
	light.omni_range = 4.0
	vp.add_child(light)
	var tw_l = light.create_tween()
	tw_l.tween_property(light, "light_energy", 0.0, 0.5)
	tw_l.finished.connect(light.queue_free)

	# Shake a la cámara si el jugador local está cerca
	var local_player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(local_player):
		var dist = local_player.global_position.distance_to(Vector2(impact_x, impact_y))
		if dist < 500.0:
			local_player.apply_shake(3.5)

func _cleanup_choque_marker() -> void:
	if not is_instance_valid(entity): return
	if entity.has_meta("choque_marker_3d"):
		var marker = entity.get_meta("choque_marker_3d")
		if is_instance_valid(marker):
			marker.queue_free()
		entity.remove_meta("choque_marker_3d")

# ==============================================================================
# 2. ENEMY AURA (Auras 3D de Estado / Buffs) — rediseño por tipo
# ==============================================================================
func handle_enemy_aura(data: Dictionary) -> void:
	if not is_instance_valid(entity) or entity.is_queued_for_deletion(): return
	if str(data.get("id", "")) != entity.entity_id: return

	var mId = data.get("mId", "")
	if data.get("active", false):
		if entity.active_auras.has(mId): return

		var radius = data.get("radius", 200)
		var aura_type = str(data.get("type", ""))
		entity.active_auras[mId] = {
			"type": aura_type,
			"radius": radius,
			"interval_ms": float(data.get("intervalMs", 1000)),
			"start_time_3d": Time.get_ticks_msec() / 1000.0
		}

		var current_map = get_tree().get_first_node_in_group("map")
		if is_instance_valid(current_map) and is_instance_valid(current_map.get("sub_viewport")):
			var s_factor = current_map.scale_factor if "scale_factor" in current_map else 0.02
			var correction_z = current_map.correction_z if "correction_z" in current_map else 1.41421356
			var radius_3d = radius * s_factor

			var aura_3d = Node3D.new()
			aura_3d.name = "Aura3D_" + mId
			current_map.sub_viewport.add_child(aura_3d)
			aura_3d.position.x = entity.global_position.x * s_factor
			aura_3d.position.z = entity.global_position.y * s_factor * correction_z
			aura_3d.position.y = 0.01
			aura_3d.scale = Vector3(0.01, 0.01, 0.01)

			var particles = CPUParticles3D.new()
			particles.name = "AuraParticles_" + mId
			current_map.sub_viewport.add_child(particles)
			particles.position.x = entity.global_position.x * s_factor
			particles.position.z = entity.global_position.y * s_factor * correction_z
			particles.position.y = 0.05
			particles.scale = Vector3(0.01, 0.01, 0.01)

			var disc_mat: ShaderMaterial = null
			var column_mat: ShaderMaterial = null
			var rim_mat: StandardMaterial3D = null

			match aura_type:
				"aura_heal":
					var built_h = _build_heal_aura(aura_3d, particles, radius_3d)
					disc_mat = built_h["disc_mat"]
					column_mat = built_h["column_mat"]
					rim_mat = built_h["rim_mat"]
				"aura_speed":
					var built_s = _build_speed_aura(aura_3d, particles, radius_3d)
					disc_mat = built_s["disc_mat"]
					column_mat = built_s["column_mat"]
					rim_mat = built_s["rim_mat"]
				_:
					var built_v = _build_void_aura(aura_3d, particles, radius_3d)
					disc_mat = built_v["disc_mat"]
					column_mat = built_v["column_mat"]
					rim_mat = built_v["rim_mat"]

			var disc_target = 1.0
			if aura_type == "aura_damage":
				disc_target = 1.0
			elif aura_type == "aura_heal":
				disc_target = 0.9
			else:
				disc_target = 0.85

			var column_target_alpha = 0.5 if aura_type != "aura_heal" else 0.42

			if is_instance_valid(disc_mat):
				disc_mat.set_shader_parameter("intensity", 0.0)
			if is_instance_valid(column_mat):
				var start_c = column_mat.get_shader_parameter("albedo_color")
				start_c.a = 0.0
				column_mat.set_shader_parameter("albedo_color", start_c)
			if is_instance_valid(rim_mat):
				rim_mat.albedo_color.a = 0.0
				rim_mat.emission_energy_multiplier = 0.0

			var tw_in = create_tween().set_parallel(true)
			tw_in.tween_property(aura_3d, "scale", Vector3(1.0, 1.0, 1.0), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw_in.tween_property(particles, "scale", Vector3(1.0, 1.0, 1.0), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			if is_instance_valid(disc_mat):
				tw_in.tween_method(func(v): disc_mat.set_shader_parameter("intensity", v), 0.0, disc_target, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			if is_instance_valid(column_mat):
				var target_c = column_mat.get_shader_parameter("albedo_color")
				var end_c = target_c
				end_c.a = column_target_alpha
				tw_in.tween_method(func(c): column_mat.set_shader_parameter("albedo_color", c), target_c, end_c, 0.4)
			if is_instance_valid(rim_mat):
				var rim_end = Color(rim_mat.albedo_color.r, rim_mat.albedo_color.g, rim_mat.albedo_color.b, 0.55)
				tw_in.tween_property(rim_mat, "albedo_color", rim_end, 0.4)
				tw_in.tween_property(rim_mat, "emission_energy_multiplier", 2.2, 0.4)

			entity.active_auras[mId]["node_3d"] = aura_3d
			entity.active_auras[mId]["particles_3d"] = particles
			entity.active_auras[mId]["disc_mat"] = disc_mat
			entity.active_auras[mId]["column_mat"] = column_mat
			entity.active_auras[mId]["rim_mat"] = rim_mat
			entity.active_auras[mId]["disc_target"] = disc_target
			entity.active_auras[mId]["s_factor"] = s_factor
			entity.active_auras[mId]["correction_z"] = correction_z
			entity.active_auras[mId]["radius_3d"] = radius_3d
	else:
		if entity.active_auras.has(mId):
			var a_data = entity.active_auras[mId]
			entity.active_auras.erase(mId)

			if a_data.has("node_3d") and is_instance_valid(a_data.node_3d):
				var tw_out = create_tween().set_parallel(true)

				var d_mat = a_data.get("disc_mat")
				if is_instance_valid(d_mat):
					var cur_i = d_mat.get_shader_parameter("intensity")
					tw_out.tween_method(func(v): d_mat.set_shader_parameter("intensity", v), cur_i, 0.0, 0.4)

				var c_mat = a_data.get("column_mat")
				if is_instance_valid(c_mat):
					var cur_c = c_mat.get_shader_parameter("albedo_color")
					var end_c = cur_c
					end_c.a = 0.0
					tw_out.tween_method(func(c): c_mat.set_shader_parameter("albedo_color", c), cur_c, end_c, 0.4)

				var r_mat = a_data.get("rim_mat")
				if is_instance_valid(r_mat):
					var rim_end = Color(r_mat.albedo_color.r, r_mat.albedo_color.g, r_mat.albedo_color.b, 0.0)
					tw_out.tween_property(r_mat, "albedo_color", rim_end, 0.4)
					tw_out.tween_property(r_mat, "emission_energy_multiplier", 0.0, 0.4)

				if a_data.has("particles_3d") and is_instance_valid(a_data.particles_3d):
					tw_out.tween_property(a_data.particles_3d, "scale", Vector3.ZERO, 0.4)

				var tw_cleanup = create_tween()
				tw_cleanup.tween_interval(0.45)
				tw_cleanup.tween_callback(a_data.node_3d.queue_free)
				if a_data.has("particles_3d") and is_instance_valid(a_data.particles_3d):
					tw_cleanup.tween_callback(a_data.particles_3d.queue_free)
			else:
				if a_data.has("particles_3d") and is_instance_valid(a_data.particles_3d):
					a_data.particles_3d.queue_free()

func handle_enemy_aura_tick(data: Dictionary) -> void:
	if not is_instance_valid(entity) or entity.is_queued_for_deletion(): return
	if str(data.get("id", "")) != entity.entity_id: return
	var mId = data.get("mId", "")
	if not entity.active_auras.has(mId): return
	_spawn_aura_tick_pulse(entity.active_auras[mId])

func _spawn_aura_tick_pulse(a_data: Dictionary) -> void:
	if not a_data.has("node_3d") or not is_instance_valid(a_data.node_3d): return
	var aura_type = str(a_data.get("type", ""))
	var radius_3d = float(a_data.get("radius_3d", 1.0))

	var disc_mat = a_data.get("disc_mat")
	if is_instance_valid(disc_mat):
		var tw_flash = create_tween()
		tw_flash.tween_method(func(v): disc_mat.set_shader_parameter("pulse", v), 1.0, 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	var ring = MeshInstance3D.new()
	var ring_mesh = PlaneMesh.new()
	var ring_size = radius_3d * 2.35
	ring_mesh.size = Vector2(ring_size, ring_size)
	ring.mesh = ring_mesh
	ring.position.y = 0.035

	var ring_mat = ShaderMaterial.new()
	ring_mat.shader = AuraPulseRingShader
	var ring_color = Color(0.75, 0.2, 1.0, 1.0)
	var ring_intensity = 1.5
	var ring_duration = 0.5
	if aura_type == "aura_heal":
		ring_color = Color(0.4, 1.0, 0.55, 1.0)
		ring_intensity = 1.3
		ring_duration = 0.65
	elif aura_type == "aura_speed":
		ring_color = Color(1.0, 0.85, 0.3, 1.0)
		ring_intensity = 1.2
	ring_mat.set_shader_parameter("ring_color", ring_color)
	ring_mat.set_shader_parameter("progress", 0.0)
	ring_mat.set_shader_parameter("intensity", ring_intensity)
	ring_mat.set_shader_parameter("thickness", 0.1)
	ring.material_override = ring_mat
	a_data.node_3d.add_child(ring)

	var tw = create_tween()
	tw.tween_method(func(p): ring_mat.set_shader_parameter("progress", p), 0.0, 1.0, ring_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(ring.queue_free)

	if aura_type == "aura_heal":
		var ring2 = MeshInstance3D.new()
		var ring2_mesh = PlaneMesh.new()
		ring2_mesh.size = Vector2(ring_size * 0.7, ring_size * 0.7)
		ring2.mesh = ring2_mesh
		ring2.position.y = 0.04
		var ring2_mat = ShaderMaterial.new()
		ring2_mat.shader = AuraPulseRingShader
		ring2_mat.set_shader_parameter("ring_color", Color(1.0, 0.95, 0.7, 1.0))
		ring2_mat.set_shader_parameter("progress", 0.0)
		ring2_mat.set_shader_parameter("intensity", 1.1)
		ring2_mat.set_shader_parameter("thickness", 0.14)
		ring2.material_override = ring2_mat
		a_data.node_3d.add_child(ring2)
		var tw2 = create_tween()
		tw2.tween_interval(0.12)
		tw2.tween_method(func(p): ring2_mat.set_shader_parameter("progress", p), 0.0, 1.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw2.tween_callback(ring2.queue_free)

# --- Builders de auras -------------------------------------------------------

func _make_column_mesh(radius_3d: float, top_scale: float, bottom_scale: float) -> CylinderMesh:
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius_3d * top_scale
	mesh.bottom_radius = radius_3d * bottom_scale
	mesh.height = maxf(radius_3d * 2.4, 1.5)
	mesh.cap_top = false
	mesh.cap_bottom = false
	return mesh

func _make_scroll_shader_material(tex: Texture2D, scroll: Vector2, uv_scale: Vector2, fade_exp: float, col: Color) -> ShaderMaterial:
	var shader = Shader.new()
	shader.code = """shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled, unshaded;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec2 scroll_speed = vec2(0.0, -0.5);
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform float fade_exponent = 2.0;

void fragment() {
	vec2 uv = UV * uv_scale + scroll_speed * TIME;
	vec4 tex = texture(albedo_texture, uv);
	float vertical_fade = sin(UV.y * 3.14159265);
	vertical_fade = pow(vertical_fade, fade_exponent);
	ALBEDO = albedo_color.rgb * tex.rgb;
	ALPHA = albedo_color.a * tex.a * vertical_fade;
}"""
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("albedo_texture", tex)
	mat.set_shader_parameter("scroll_speed", scroll)
	mat.set_shader_parameter("uv_scale", uv_scale)
	mat.set_shader_parameter("fade_exponent", fade_exp)
	mat.set_shader_parameter("albedo_color", col)
	return mat

func _make_ground_disc(shader: Shader, radius_3d: float, y: float = 0.02) -> MeshInstance3D:
	var disc = MeshInstance3D.new()
	var mesh = PlaneMesh.new()
	var size = radius_3d * 2.1
	mesh.size = Vector2(size, size)
	disc.mesh = mesh
	disc.position.y = y
	var mat = ShaderMaterial.new()
	mat.shader = shader
	disc.material_override = mat
	return disc

func _configure_ring_particles(particles: CPUParticles3D, radius_3d: float, cfg: Dictionary) -> void:
	particles.amount = int(cfg.get("amount", 70))
	particles.lifetime = float(cfg.get("lifetime", 1.6))
	particles.preprocess = float(cfg.get("preprocess", 0.8))
	particles.randomness = float(cfg.get("randomness", 0.4))
	particles.direction = Vector3.UP
	particles.gravity = Vector3.ZERO
	particles.initial_velocity_min = float(cfg.get("vel_min", 1.0))
	particles.initial_velocity_max = float(cfg.get("vel_max", 2.2))
	particles.spread = float(cfg.get("spread", 10.0))

	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	particles.emission_ring_axis = Vector3.UP
	particles.emission_ring_radius = radius_3d * float(cfg.get("ring_scale", 0.9))
	particles.emission_ring_inner_radius = radius_3d * float(cfg.get("ring_inner", 0.4))
	particles.emission_ring_height = 0.1
	particles.scale_amount_min = float(cfg.get("scale_min", 0.08))
	particles.scale_amount_max = float(cfg.get("scale_max", 0.22))

	var s_curve = Curve.new()
	s_curve.add_point(Vector2(0, 0.1))
	s_curve.add_point(Vector2(0.2, 1.0))
	s_curve.add_point(Vector2(0.8, 0.6))
	s_curve.add_point(Vector2(1.0, 0.0))
	particles.scale_amount_curve = s_curve

	var base: Color = cfg.get("color", Color.WHITE)
	var trans = base
	trans.a = 0.0
	var mid = base
	mid.a = 0.85
	var peak = Color(clampf(base.r * 1.4, 0, 1), clampf(base.g * 1.2, 0, 1), clampf(base.b * 1.2, 0, 1), 0.7)
	var grad = Gradient.new()
	grad.set_color(0, Color(base.r, base.g, base.b, 0.0))
	grad.add_point(0.2, mid)
	grad.add_point(0.75, peak)
	grad.set_color(1, trans)
	particles.color_ramp = grad

	var p_mesh = QuadMesh.new()
	var p_size = float(cfg.get("quad_size", 0.4))
	p_mesh.size = Vector2(p_size, p_size)
	particles.mesh = p_mesh

	var p_mat = StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	p_mat.vertex_color_use_as_albedo = true
	p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var tex: Texture2D = cfg.get("texture", VFX_FlareTexture)
	if tex:
		p_mat.albedo_texture = tex
	particles.material_override = p_mat

func _build_void_aura(aura_3d: Node3D, particles: CPUParticles3D, radius_3d: float) -> Dictionary:
	# Disco de suelo: remolino de vacío que succiona
	var disc = _make_ground_disc(VoidAuraShader, radius_3d, 0.02)
	var disc_mat: ShaderMaterial = disc.material_override
	disc_mat.set_shader_parameter("core_color", Color(0.04, 0.015, 0.07, 1.0))
	disc_mat.set_shader_parameter("mid_color", Color(0.48, 0.12, 0.64, 1.0))
	disc_mat.set_shader_parameter("rim_color", Color(0.88, 0.25, 1.0, 1.0))
	disc_mat.set_shader_parameter("swirl_speed", 1.35)
	disc_mat.set_shader_parameter("intensity", 0.0)
	aura_3d.add_child(disc)

	# Columna de humo oscuro violeta
	var column = MeshInstance3D.new()
	var mesh = _make_column_mesh(radius_3d, 0.7, 1.1)
	column.mesh = mesh
	var column_mat = _make_scroll_shader_material(
		VFX_SmokeTexture,
		Vector2(0.0, -0.35),
		Vector2(2.5, 1.6),
		2.1,
		Color(0.55, 0.1, 0.75, 0.0)
	)
	column.material_override = column_mat
	column.position.y = mesh.height / 2.0
	aura_3d.add_child(column)

	# Aro perimetral magenta — ELIMINADO (generaba un arco vertical feo)
	var rim_mat: StandardMaterial3D = null

	# Partículas: brasas oscuras con borde magenta que ascienden y se enrarecen
	_configure_ring_particles(particles, radius_3d, {
		"amount": 55,
		"lifetime": 1.8,
		"preprocess": 0.9,
		"vel_min": 0.6,
		"vel_max": 1.6,
		"spread": 14.0,
		"ring_scale": 0.92,
		"ring_inner": 0.55,
		"scale_min": 0.1,
		"scale_max": 0.28,
		"quad_size": 0.45,
		"color": Color(0.55, 0.12, 0.85, 0.75),
		"texture": VFX_FlareTexture
	})

	return {"disc_mat": disc_mat, "column_mat": column_mat, "rim_mat": rim_mat}

func _build_heal_aura(aura_3d: Node3D, particles: CPUParticles3D, radius_3d: float) -> Dictionary:
	# Disco de suelo: círculo ritual de sanación
	var disc = _make_ground_disc(HealAuraShader, radius_3d, 0.02)
	var disc_mat: ShaderMaterial = disc.material_override
	disc_mat.set_shader_parameter("core_color", Color(1.0, 0.97, 0.8, 1.0))
	disc_mat.set_shader_parameter("mid_color", Color(0.36, 1.0, 0.54, 1.0))
	disc_mat.set_shader_parameter("rim_color", Color(1.0, 0.84, 0.31, 1.0))
	disc_mat.set_shader_parameter("intensity", 0.0)
	aura_3d.add_child(disc)

	# Columna de luz cálida suave
	var column = MeshInstance3D.new()
	var mesh = _make_column_mesh(radius_3d, 0.62, 1.0)
	column.mesh = mesh
	var column_mat = _make_scroll_shader_material(
		VFX_SmokeTexture,
		Vector2(0.0, -0.18),
		Vector2(2.0, 1.3),
		2.4,
		Color(0.55, 1.0, 0.65, 0.0)
	)
	column.material_override = column_mat
	column.position.y = mesh.height / 2.0
	aura_3d.add_child(column)

	# Aro perimetral dorado-verde — ELIMINADO (generaba un arco vertical feo)
	var rim_mat: StandardMaterial3D = null

	# Partículas: sparkles cálidos que flotan hacia arriba
	_configure_ring_particles(particles, radius_3d, {
		"amount": 75,
		"lifetime": 2.0,
		"preprocess": 1.0,
		"vel_min": 0.5,
		"vel_max": 1.3,
		"spread": 8.0,
		"ring_scale": 0.85,
		"ring_inner": 0.15,
		"scale_min": 0.07,
		"scale_max": 0.18,
		"quad_size": 0.32,
		"color": Color(0.5, 1.0, 0.6, 0.85),
		"texture": VFX_SparkleTexture
	})

	return {"disc_mat": disc_mat, "column_mat": column_mat, "rim_mat": rim_mat}

func _build_speed_aura(aura_3d: Node3D, particles: CPUParticles3D, radius_3d: float) -> Dictionary:
	# Disco ámbar con rotación rápida (pulso leve del sistema nuevo)
	var disc = _make_ground_disc(HealAuraShader, radius_3d, 0.02)
	var disc_mat: ShaderMaterial = disc.material_override
	disc_mat.set_shader_parameter("core_color", Color(1.0, 0.95, 0.7, 1.0))
	disc_mat.set_shader_parameter("mid_color", Color(1.0, 0.7, 0.2, 1.0))
	disc_mat.set_shader_parameter("rim_color", Color(1.0, 0.5, 0.1, 1.0))
	disc_mat.set_shader_parameter("noise_scale", 6.0)
	disc_mat.set_shader_parameter("intensity", 0.0)
	aura_3d.add_child(disc)

	# Columna de viento dorado
	var column = MeshInstance3D.new()
	var mesh = _make_column_mesh(radius_3d, 0.72, 1.05)
	column.mesh = mesh
	var column_mat = _make_scroll_shader_material(
		VFX_SmokeTexture,
		Vector2(0.0, -0.55),
		Vector2(3.0, 1.8),
		1.9,
		Color(1.0, 0.8, 0.3, 0.0)
	)
	column.material_override = column_mat
	column.position.y = mesh.height / 2.0
	aura_3d.add_child(column)

	# Aro perimetral ámbar — ELIMINADO (generaba un arco vertical feo)
	var rim_mat: StandardMaterial3D = null

	_configure_ring_particles(particles, radius_3d, {
		"amount": 65,
		"lifetime": 1.4,
		"preprocess": 0.7,
		"vel_min": 1.4,
		"vel_max": 2.8,
		"spread": 16.0,
		"ring_scale": 0.7,
		"ring_inner": 0.1,
		"scale_min": 0.07,
		"scale_max": 0.16,
		"quad_size": 0.3,
		"color": Color(1.0, 0.8, 0.3, 0.8),
		"texture": VFX_FlareTexture
	})

	return {"disc_mat": disc_mat, "column_mat": column_mat, "rim_mat": rim_mat}

func update_auras(delta: float) -> void:
	if not is_instance_valid(entity): return
	var now = Time.get_ticks_msec() / 1000.0
	for mId in entity.active_auras:
		var a_data = entity.active_auras[mId]

		if a_data.has("node") and is_instance_valid(a_data.node):
			var pulse = 1.0 + sin(now * 4.0) * 0.05
			var s = a_data.get("target_scale", 1.0) * pulse
			a_data.node.scale = Vector2(s, s)
			a_data.node.rotate(delta * 0.5)
			if a_data.get("type") == "wall_dome":
				entity.queue_redraw()

		if a_data.has("node_3d") and is_instance_valid(a_data.node_3d):
			var s_factor = a_data.get("s_factor", 0.02)
			var correction_z = a_data.get("correction_z", 1.41421356)
			a_data.node_3d.position.x = entity.global_position.x * s_factor
			a_data.node_3d.position.z = entity.global_position.y * s_factor * correction_z

		if a_data.has("particles_3d") and is_instance_valid(a_data.particles_3d):
			var s_factor = a_data.get("s_factor", 0.02)
			var correction_z = a_data.get("correction_z", 1.41421356)
			a_data.particles_3d.position.x = entity.global_position.x * s_factor
			a_data.particles_3d.position.z = entity.global_position.y * s_factor * correction_z


# ==============================================================================
# 3. COLOR AURA (Pilares y Puzzle de Colores)
# ==============================================================================
func apply_color_aura(color_name: String) -> void:
	if not is_instance_valid(entity): return
	remove_color_aura()
	
	var clr = Color.WHITE
	match color_name.to_lower():
		"roja": clr = Color("#ff003c")
		"azul": clr = Color("#00aaff")
		"verde": clr = Color("#00ff66")
		"amarilla": clr = Color("#ffdd00")
		"violeta": clr = Color("#d400ff")
		
	var pivot = entity.accessory_pivot_3d if is_instance_valid(entity.accessory_pivot_3d) else entity.world_root_3d
	if not is_instance_valid(pivot):
		return
	
	var s_factor = entity.get_meta("map_scale", 0.02)
	var base_r: float
	if entity.entity_type >= 101:
		base_r = 180.0
	elif entity.entity_type == 200 or "pillar" in entity.entity_id:
		base_r = 100.0
	else:
		base_r = 70.0
	var r = base_r * s_factor
	
	var aura_root = Node3D.new()
	aura_root.name = "ColorAuraVFX"
	pivot.add_child(aura_root)
	_color_aura_3d_root = aura_root
	
	var ring_mesh = TorusMesh.new()
	ring_mesh.inner_radius = r * 0.85
	ring_mesh.outer_radius = r * 1.2
	ring_mesh.rings = 8
	ring_mesh.ring_segments = 32
	
	var ring = MeshInstance3D.new()
	ring.mesh = ring_mesh
	
	var ring_mat = StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring_mat.albedo_color = Color(clr.r, clr.g, clr.b, 0.0)
	ring_mat.emission_enabled = true
	ring_mat.emission = clr
	ring_mat.emission_energy_multiplier = 4.0
	ring.material_override = ring_mat
	ring.position = Vector3(0, -0.02, 0)
	aura_root.add_child(ring)
	
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.top_radius = r * 0.95
	cylinder_mesh.bottom_radius = r * 1.15
	cylinder_mesh.height = r * 4.0
	cylinder_mesh.radial_segments = 32
	cylinder_mesh.rings = 4
	cylinder_mesh.cap_top = false
	cylinder_mesh.cap_bottom = false
	
	var cylinder = MeshInstance3D.new()
	cylinder.mesh = cylinder_mesh
	
	var beam_mat = ShaderMaterial.new()
	beam_mat.shader = ColorBeamShader
	beam_mat.set_shader_parameter("beam_color", Color(clr.r, clr.g, clr.b, 0.0))
	beam_mat.set_shader_parameter("speed", 1.6)
	beam_mat.set_shader_parameter("scale_y", 6.0)
	beam_mat.set_shader_parameter("scale_x", 20.0)
	beam_mat.set_shader_parameter("fresnel_power", 2.2)
	cylinder.material_override = beam_mat
	cylinder.position = Vector3(0, r * 2.0, 0)
	aura_root.add_child(cylinder)
	
	var tex_flare = VFX_FlareTexture
	var particles = CPUParticles3D.new()
	particles.amount = 35
	particles.lifetime = 1.8
	particles.preprocess = 0.5
	particles.randomness = 0.4
	particles.direction = Vector3.UP
	particles.gravity = Vector3(0, 0.2, 0)
	particles.initial_velocity_min = 0.8
	particles.initial_velocity_max = 2.0
	particles.spread = 15.0
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	particles.emission_ring_axis = Vector3.UP
	particles.emission_ring_radius = r * 0.9
	particles.emission_ring_inner_radius = r * 0.3
	particles.emission_ring_height = 0.1
	particles.scale_amount_min = 0.08
	particles.scale_amount_max = 0.2
	
	var s_curve = Curve.new()
	s_curve.add_point(Vector2(0, 0.1))
	s_curve.add_point(Vector2(0.2, 1.0))
	s_curve.add_point(Vector2(0.8, 0.6))
	s_curve.add_point(Vector2(1.0, 0.0))
	particles.scale_amount_curve = s_curve
	
	var grad = Gradient.new()
	grad.set_color(0, Color(clr.r, clr.g, clr.b, 0.0))
	grad.add_point(0.2, Color(clr.r, clr.g, clr.b, 0.8))
	grad.add_point(0.8, Color(clr.r * 1.3, clr.g * 1.3, clr.b * 1.3, 0.6))
	grad.set_color(1, Color(clr.r, clr.g, clr.b, 0.0))
	particles.color_ramp = grad
	
	var p_mesh = QuadMesh.new()
	p_mesh.size = Vector2(0.35, 0.35)
	particles.mesh = p_mesh
	
	var p_mat = StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	p_mat.vertex_color_use_as_albedo = true
	p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if tex_flare:
		p_mat.albedo_texture = tex_flare
	particles.material_override = p_mat
	aura_root.add_child(particles)
	
	var light = OmniLight3D.new()
	light.light_color = clr
	light.light_energy = 0.0
	light.omni_range = r * 5.0
	light.position = Vector3(0, r * 1.5, 0)
	aura_root.add_child(light)
	
	var tw = create_tween().set_parallel(true)
	tw.tween_property(ring_mat, "albedo_color:a", 0.7, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(c): beam_mat.set_shader_parameter("beam_color", c), Color(clr.r, clr.g, clr.b, 0.0), Color(clr.r, clr.g, clr.b, 0.6), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(light, "light_energy", 3.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func remove_color_aura() -> void:
	if is_instance_valid(_color_aura_3d_root):
		_color_aura_3d_root.queue_free()
		_color_aura_3d_root = null

# ==============================================================================
# 4. WATER ORB 3D (Boss Marino / Orbe Acuático)
# ==============================================================================
func setup_water_orb_3d() -> void:
	if not is_instance_valid(entity): return
	var current_map = get_tree().get_first_node_in_group("map")
	var is_single_world = false
	var target_viewport = null
	var map_scale_val = 0.02

	if is_instance_valid(current_map):
		if "sub_viewport" in current_map and is_instance_valid(current_map.sub_viewport):
			is_single_world = true
			target_viewport = current_map.sub_viewport
			if "scale_factor" in current_map:
				map_scale_val = current_map.scale_factor

	entity.set_meta("is_single_world", is_single_world)
	entity.set_meta("map_scale", map_scale_val)

	var viewport = null
	var res = 256
	if not is_single_world:
		var quality = 1
		if get_node_or_null("/root/SettingsManager"):
			quality = SettingsManager.get_graphics_quality()
		match quality:
			0: res = 128
			2: res = 1024
		viewport = SubViewport.new()
		viewport.size = Vector2i(res, res)
		viewport.transparent_bg = true
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.positional_shadow_atlas_size = 0
		entity.add_child(viewport)
		entity.set("_cached_viewport", viewport)

	if is_instance_valid(entity.sprite):
		entity.sprite.visible = not is_single_world
	else:
		entity.sprite = Sprite2D.new()
		entity.sprite.name = "Ship3DRender"
		entity.sprite.z_index = 10
		entity.add_child(entity.sprite)
		entity.sprite.visible = not is_single_world

	var node3d = Node3D.new()
	if is_single_world:
		target_viewport.add_child(node3d)
	else:
		viewport.add_child(node3d)
	entity.world_root_3d = node3d

	entity.accessory_pivot_3d = Node3D.new()
	entity.accessory_pivot_3d.name = "AccessoryPivot"
	node3d.add_child(entity.accessory_pivot_3d)

	if not is_single_world:
		var env = WorldEnvironment.new()
		var world_env = Environment.new()
		world_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		world_env.ambient_light_color = Color(0.2, 0.2, 0.35)
		world_env.ambient_light_energy = 0.6
		world_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.environment = world_env
		node3d.add_child(env)

		var cam_pivot = Node3D.new()
		node3d.add_child(cam_pivot)
		var cam = Camera3D.new()
		cam_pivot.add_child(cam)
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = 45.0
		cam.position = Vector3(0, 1.3, 3.3)
		cam.look_at(Vector3(0, 0.1, 0))

		var key = DirectionalLight3D.new()
		node3d.add_child(key)
		key.rotation_degrees = Vector3(-65, 35, 0)
		key.light_energy = 1.5
		key.light_color = Color(1.0, 0.92, 0.85)
		key.light_specular = 0.5
		key.shadow_enabled = false

		var fill = DirectionalLight3D.new()
		node3d.add_child(fill)
		fill.rotation_degrees = Vector3(25, -135, 0)
		fill.light_energy = 0.6
		fill.light_color = Color(0.7, 0.8, 1.0)
		fill.light_specular = 0.3
		fill.shadow_enabled = false

		if is_instance_valid(entity.sprite):
			entity.sprite.texture = viewport.get_texture()
			entity.sprite.scale = Vector2(1024.0 / float(res), 1024.0 / float(res))

	var orb_size = map_scale_val * 100.0
	var water_normal = VFX_WaterNormalTexture

	var water_shader = Shader.new()
	water_shader.code = """shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled, unshaded;

uniform sampler2D normal_map : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(0.0, 0.6, 1.0, 0.45);
uniform vec4 emission_color : source_color = vec4(0.0, 0.8, 1.0, 1.0);
uniform float emission_energy = 4.0;
uniform float wave_speed = 0.5;
uniform float wave_strength = 0.3;

void vertex() {
	vec3 pos = VERTEX;
	float w = sin(pos.x * 2.5 + TIME * wave_speed) * wave_strength * 0.08;
	w += sin(pos.y * 3.2 + TIME * wave_speed * 1.2) * wave_strength * 0.06;
	w += sin(pos.z * 2.0 + TIME * wave_speed * 0.8) * wave_strength * 0.07;
	VERTEX = pos + NORMAL * w;
}

void fragment() {
	vec2 uv1 = UV * 2.0 + vec2(TIME * 0.04, TIME * 0.02);
	vec2 uv2 = UV * 3.0 + vec2(TIME * -0.03, TIME * 0.05);
	vec3 n1 = texture(normal_map, uv1).rgb - 0.5;
	vec3 n2 = texture(normal_map, uv2).rgb - 0.5;
	vec3 n = normalize(n1 + n2);
	vec3 view_dir = normalize(VIEW);
	float fresnel = pow(1.0 - abs(dot(view_dir, n)), 2.5);
	float ripple = sin(UV.x * 25.0 + UV.y * 18.0 + TIME * 2.5) * 0.5 + 0.5;
	ALBEDO = albedo_color.rgb;
	ALPHA = albedo_color.a * (0.5 + fresnel * 0.5);
	EMISSION = emission_color.rgb * emission_energy * (0.6 + fresnel * 1.2 + ripple * 0.3);
}"""

	var orb_mat = ShaderMaterial.new()
	orb_mat.shader = water_shader
	orb_mat.set_shader_parameter("normal_map", water_normal)
	orb_mat.set_shader_parameter("albedo_color", Color(0.0, 0.6, 1.0, 0.45))
	orb_mat.set_shader_parameter("emission_color", Color(0.0, 0.8, 1.0))
	orb_mat.set_shader_parameter("emission_energy", 4.0)
	orb_mat.set_shader_parameter("wave_speed", 0.5)
	orb_mat.set_shader_parameter("wave_strength", 0.3)

	var orb = MeshInstance3D.new()
	var orb_mesh = SphereMesh.new()
	orb_mesh.radius = orb_size
	orb_mesh.height = orb_size * 2.0
	orb.mesh = orb_mesh
	orb.material_override = orb_mat
	entity.accessory_pivot_3d.add_child(orb)

	var core_mat = StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	core_mat.albedo_color = Color(0.3, 0.85, 1.0, 0.2)
	core_mat.emission_enabled = true
	core_mat.emission = Color(0.2, 0.8, 1.0)
	core_mat.emission_energy_multiplier = 5.0
	core_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var core = MeshInstance3D.new()
	var core_mesh = SphereMesh.new()
	core_mesh.radius = orb_size * 0.45
	core_mesh.height = orb_size * 0.9
	core.mesh = core_mesh
	core.material_override = core_mat
	entity.accessory_pivot_3d.add_child(core)

	var tex_flare = VFX_FlareTexture
	var bubbles = CPUParticles3D.new()
	bubbles.amount = 15
	bubbles.lifetime = 2.5
	bubbles.randomness = 0.6
	bubbles.direction = Vector3.UP
	bubbles.gravity = Vector3(0, 0.15, 0)
	bubbles.initial_velocity_min = 0.1
	bubbles.initial_velocity_max = 0.4
	bubbles.spread = 60.0
	bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	bubbles.emission_sphere_radius = orb_size * 1.1
	bubbles.scale_amount_min = 0.015
	bubbles.scale_amount_max = 0.04
	entity.accessory_pivot_3d.add_child(bubbles)

	var b_curve = Curve.new()
	b_curve.add_point(Vector2(0, 0.0))
	b_curve.add_point(Vector2(0.15, 1.0))
	b_curve.add_point(Vector2(0.7, 0.6))
	b_curve.add_point(Vector2(1.0, 0.0))
	bubbles.scale_amount_curve = b_curve

	var b_grad = Gradient.new()
	b_grad.set_color(0, Color(0.8, 1.0, 1.0, 0.0))
	b_grad.add_point(0.15, Color(0.8, 1.0, 1.0, 0.9))
	b_grad.add_point(0.6, Color(0.5, 0.9, 1.0, 0.3))
	b_grad.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	bubbles.color_ramp = b_grad

	var b_mesh = QuadMesh.new()
	b_mesh.size = Vector2(0.12, 0.12)
	bubbles.mesh = b_mesh

	var b_mat = StandardMaterial3D.new()
	b_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	b_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	b_mat.vertex_color_use_as_albedo = true
	b_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	b_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if tex_flare:
		b_mat.albedo_texture = tex_flare
	bubbles.material_override = b_mat

	var light = OmniLight3D.new()
	light.light_color = Color(0.0, 0.7, 1.0)
	light.light_energy = 1.0
	light.omni_range = orb_size * 4.0
	entity.accessory_pivot_3d.add_child(light)

	var tw = create_tween().set_parallel(true)
	tw.tween_property(orb, "scale", Vector3(1.0, 1.0, 1.0), 0.3).from(Vector3(0.01, 0.01, 0.01)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(core, "scale", Vector3(1.0, 1.0, 1.0), 0.35).from(Vector3(0.01, 0.01, 0.01)).set_delay(0.05).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(light, "light_energy", 1.0, 0.3).from(0.0)

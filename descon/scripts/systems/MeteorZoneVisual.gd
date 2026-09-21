extends Node2D
# Visual de Zona Persistente de Meteorito
# Se crea cuando el meteorito cae con persistentZone habilitado.
# Renderiza un área 3D conformante al terreno con fuego, brasas y luz.
# En modo 3D no dibuja en 2D para evitar desfase de proyección.
# Se destruye automáticamente al expirar.

var map_node = null
var radius: float = 150.0
var zone_duration: float = 4.0
var zone_tick_ms: float = 1.0
var _elapsed: float = 0.0
var _is_3d: bool = false
var _ground_3d: Node3D = null
var _ring_mesh_instance: MeshInstance3D = null
var _fire_light: OmniLight3D = null
var _fire_particles: GPUParticles3D = null
var _ember_particles: GPUParticles3D = null

const ZONE_COLOR := Color(0.8, 0.25, 0.05, 0.25)
const ZONE_RING_COLOR := Color(0.95, 0.35, 0.08, 0.7)
const ZONE_FIRE_TEX = preload("res://VFX/textures/T_VFX_FireBall_s1_alpha.jpg")
const ZONE_SPARKS_TEX = preload("res://VFX/textures/T_VFX_sparks42.jpg")

func setup(data: Dictionary, p_map) -> void:
	map_node = p_map
	radius = float(data.get("radius", 150.0))
	zone_duration = float(data.get("zoneDuration", 4000.0)) / 1000.0
	zone_tick_ms = float(data.get("zoneTickMs", 1000.0)) / 1000.0
	_is_3d = is_instance_valid(map_node) and map_node.get("sub_viewport") != null
	_spawn_ground_area(data)

func _spawn_ground_area(data: Dictionary) -> void:
	if not _is_3d or not is_instance_valid(map_node):
		return
	var s_factor: float = map_node.scale_factor if "scale_factor" in map_node else 0.02
	var correction_z: float = map_node.correction_z if "correction_z" in map_node else 1.41421356
	var vp = map_node.sub_viewport
	if not is_instance_valid(vp):
		return

	var e_x := float(data.get("x", global_position.x))
	var e_y := float(data.get("y", global_position.y))
	var r3d: float = radius * s_factor

	# Altura real del terreno
	var h_zone = 0.05
	if is_instance_valid(map_node.get("terrain_node")):
		var em_n = get_tree().get_first_node_in_group("world_node")
		if em_n and em_n.has_node("EntityManager"):
			var mgr = em_n.get_node("EntityManager")
			if mgr and mgr.has_method("_sample_terrain_height"):
				h_zone = mgr._sample_terrain_height(Vector2(e_x, e_y), map_node) + 0.06
			elif map_node.has_method("get_terrain_height_at_pos"):
				h_zone = map_node.get_terrain_height_at_pos(Vector2(e_x, e_y)) + 0.06
		elif map_node.has_method("get_terrain_height_at_pos"):
			h_zone = map_node.get_terrain_height_at_pos(Vector2(e_x, e_y)) + 0.06

	_ground_3d = Node3D.new()
	_ground_3d.name = "MeteorZone_" + name
	_ground_3d.position = Vector3(e_x * s_factor, h_zone, e_y * s_factor * correction_z)
	vp.add_child(_ground_3d)

	# 1. Disco conformante de terreno (piso quemado/ardiente)
	var disc := MeshInstance3D.new()
	var disc_mesh: Mesh = CylinderMesh.new()
	disc_mesh.top_radius = r3d
	disc_mesh.bottom_radius = r3d
	disc_mesh.height = 0.01
	if is_instance_valid(map_node.get("terrain_node")):
		var em_n2 = get_tree().get_first_node_in_group("world_node")
		if em_n2 and em_n2.has_node("EntityManager"):
			var mgr2 = em_n2.get_node("EntityManager")
			if mgr2 and mgr2.has_method("_make_circle_disc_conforming"):
				disc_mesh = mgr2._make_circle_disc_conforming(Vector2(e_x, e_y), radius, map_node)
	disc.mesh = disc_mesh
	var disc_mat := StandardMaterial3D.new()
	disc_mat.albedo_color = Color(0.85, 0.26, 0.05, 0.28)
	disc_mat.emission_enabled = true
	disc_mat.emission = Color(0.95, 0.32, 0.06)
	disc_mat.emission_energy_multiplier = 1.0
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc_mat.no_depth_test = true
	disc_mat.render_priority = 2
	disc.material_override = disc_mat
	_ground_3d.add_child(disc)

	# 2. Anillo exterior conformante al terreno (borde de peligro exacto)
	var ring := MeshInstance3D.new()
	var ring_mesh = _make_conforming_ring(Vector2(e_x, e_y), radius * 0.93, radius)
	ring.mesh = ring_mesh
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.38, 0.06, 0.8)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.45, 0.1)
	ring_mat.emission_energy_multiplier = 2.5
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.no_depth_test = true
	ring_mat.render_priority = 3
	ring.material_override = ring_mat
	_ground_3d.add_child(ring)
	_ring_mesh_instance = ring

	# 3. VFX de fuego, brasas y luz que emerge del suelo
	_spawn_fire_vfx(r3d)

func _make_conforming_ring(center_2d: Vector2, inner_rad: float, outer_rad: float) -> ArrayMesh:
	var segs_ang = 48
	var s_factor: float = map_node.scale_factor if "scale_factor" in map_node else 0.02
	var cz: float = map_node.correction_z if "correction_z" in map_node else 1.41421356
	var em_n = get_tree().get_first_node_in_group("world_node")
	var mgr = em_n.get_node_or_null("EntityManager") if em_n else null
	
	var h_center = 0.0
	if mgr and mgr.has_method("_sample_terrain_height"):
		h_center = mgr._sample_terrain_height(center_2d, map_node)
	elif map_node.has_method("get_terrain_height_at_pos"):
		h_center = map_node.get_terrain_height_at_pos(center_2d)
	
	var eps = 0.48 # Ligeramente sobre el disco (0.45) para evitar z-fighting
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ai in range(segs_ang):
		var ang1 = (float(ai) / segs_ang) * TAU
		var ang2 = (float(ai + 1) / segs_ang) * TAU
		var off_i1 = Vector2(cos(ang1), sin(ang1)) * inner_rad
		var off_i2 = Vector2(cos(ang2), sin(ang2)) * inner_rad
		var off_o1 = Vector2(cos(ang1), sin(ang1)) * outer_rad
		var off_o2 = Vector2(cos(ang2), sin(ang2)) * outer_rad
		
		var h_i1 = h_center
		var h_i2 = h_center
		var h_o1 = h_center
		var h_o2 = h_center
		if mgr and mgr.has_method("_sample_terrain_height"):
			h_i1 = mgr._sample_terrain_height(center_2d + off_i1, map_node)
			h_i2 = mgr._sample_terrain_height(center_2d + off_i2, map_node)
			h_o1 = mgr._sample_terrain_height(center_2d + off_o1, map_node)
			h_o2 = mgr._sample_terrain_height(center_2d + off_o2, map_node)
		elif map_node.has_method("get_terrain_height_at_pos"):
			h_i1 = map_node.get_terrain_height_at_pos(center_2d + off_i1)
			h_i2 = map_node.get_terrain_height_at_pos(center_2d + off_i2)
			h_o1 = map_node.get_terrain_height_at_pos(center_2d + off_o1)
			h_o2 = map_node.get_terrain_height_at_pos(center_2d + off_o2)
		
		var p_i1 = Vector3(off_i1.x * s_factor, (h_i1 - h_center) + eps, off_i1.y * s_factor * cz)
		var p_i2 = Vector3(off_i2.x * s_factor, (h_i2 - h_center) + eps, off_i2.y * s_factor * cz)
		var p_o1 = Vector3(off_o1.x * s_factor, (h_o1 - h_center) + eps, off_o1.y * s_factor * cz)
		var p_o2 = Vector3(off_o2.x * s_factor, (h_o2 - h_center) + eps, off_o2.y * s_factor * cz)
		
		st.set_normal(Vector3.UP)
		st.add_vertex(p_i1)
		st.set_normal(Vector3.UP)
		st.add_vertex(p_o1)
		st.set_normal(Vector3.UP)
		st.add_vertex(p_o2)

		st.set_normal(Vector3.UP)
		st.add_vertex(p_i1)
		st.set_normal(Vector3.UP)
		st.add_vertex(p_o2)
		st.set_normal(Vector3.UP)
		st.add_vertex(p_i2)
	return st.commit()

func _spawn_fire_vfx(r3d: float) -> void:
	# 1. Llamas de fuego emergiendo del suelo
	var fire = GPUParticles3D.new()
	fire.name = "GroundFire"
	fire.amount = 75
	fire.lifetime = 0.75
	fire.explosiveness = 0.05
	
	var fire_ppm = ParticleProcessMaterial.new()
	fire_ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	fire_ppm.emission_ring_axis = Vector3(0, 1, 0)
	fire_ppm.emission_ring_height = 0.15
	fire_ppm.emission_ring_radius = r3d * 0.85
	fire_ppm.emission_ring_inner_radius = 0.0
	fire_ppm.direction = Vector3(0, 1, 0)
	fire_ppm.spread = 22.0
	fire_ppm.initial_velocity_min = 0.9
	fire_ppm.initial_velocity_max = 2.4
	fire_ppm.gravity = Vector3(0, 2.2, 0)
	fire_ppm.scale_min = 0.35
	fire_ppm.scale_max = 0.75
	fire_ppm.color = Color(1.0, 0.45, 0.08, 0.9)
	
	var scale_curve = Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.25))
	scale_curve.add_point(Vector2(0.3, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.05))
	var scale_tex = CurveTexture.new()
	scale_tex.curve = scale_curve
	fire_ppm.scale_curve = scale_tex
	fire.process_material = fire_ppm
	
	var fire_quad = QuadMesh.new()
	fire_quad.size = Vector2(0.55, 0.75)
	fire.draw_pass_1 = fire_quad
	
	var fire_tex = ZONE_FIRE_TEX
	if fire_tex:
		var fire_mat = StandardMaterial3D.new()
		fire_mat.albedo_texture = fire_tex
		fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fire_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		fire_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		fire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fire_mat.vertex_color_use_as_albedo = true
		fire.material_override = fire_mat
	
	fire.position.y = 0.48
	_ground_3d.add_child(fire)
	_fire_particles = fire

	# 2. Brasas / Chispas ardientes flotantes
	var embers = GPUParticles3D.new()
	embers.name = "GroundEmbers"
	embers.amount = 40
	embers.lifetime = 1.0
	
	var embers_ppm = ParticleProcessMaterial.new()
	embers_ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	embers_ppm.emission_ring_axis = Vector3(0, 1, 0)
	embers_ppm.emission_ring_height = 0.1
	embers_ppm.emission_ring_radius = r3d * 0.82
	embers_ppm.emission_ring_inner_radius = 0.0
	embers_ppm.direction = Vector3(0, 1, 0)
	embers_ppm.spread = 35.0
	embers_ppm.initial_velocity_min = 1.2
	embers_ppm.initial_velocity_max = 3.2
	embers_ppm.gravity = Vector3(0, 1.5, 0)
	embers_ppm.scale_min = 0.12
	embers_ppm.scale_max = 0.28
	embers_ppm.color = Color(2.0, 1.3, 0.4, 1.0)
	embers.process_material = embers_ppm
	
	var embers_quad = QuadMesh.new()
	embers_quad.size = Vector2(0.2, 0.2)
	embers.draw_pass_1 = embers_quad
	
	var embers_tex = ZONE_SPARKS_TEX
	if embers_tex:
		var embers_mat = StandardMaterial3D.new()
		embers_mat.albedo_texture = embers_tex
		embers_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		embers_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		embers_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		embers_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		embers_mat.vertex_color_use_as_albedo = true
		embers.material_override = embers_mat
		
	embers.position.y = 0.48
	_ground_3d.add_child(embers)
	_ember_particles = embers

	# 3. Luz cálida titilante de peligro
	var fire_light = OmniLight3D.new()
	fire_light.name = "FireLight"
	fire_light.light_color = Color(1.0, 0.45, 0.1)
	fire_light.light_energy = 2.5
	fire_light.omni_range = max(3.5, r3d * 2.5)
	fire_light.position.y = 0.65
	_ground_3d.add_child(fire_light)
	_fire_light = fire_light

func _exit_tree() -> void:
	if is_instance_valid(_ground_3d) and is_instance_valid(_ground_3d.get_parent()):
		_ground_3d.queue_free()
	_ground_3d = null

func _process(delta: float) -> void:
	_elapsed += delta

	# Pulsación de intensidad en el anillo de borde
	if is_instance_valid(_ring_mesh_instance) and _ring_mesh_instance.material_override:
		var pulse = 0.5 + 0.5 * sin(_elapsed * 8.0)
		_ring_mesh_instance.material_override.emission_energy_multiplier = 1.8 + 1.2 * pulse

	# Titileo de la luz de fuego
	if is_instance_valid(_fire_light):
		_fire_light.light_energy = 2.0 + 0.7 * sin(_elapsed * 12.0) + randf_range(-0.15, 0.15)

	# Expiración: apagar partículas, fundido suave y liberar
	if _elapsed >= zone_duration:
		if is_instance_valid(_fire_particles):
			_fire_particles.emitting = false
		if is_instance_valid(_ember_particles):
			_ember_particles.emitting = false
		var tw = create_tween()
		if is_instance_valid(_fire_light):
			tw.parallel().tween_property(_fire_light, "light_energy", 0.0, 0.5)
		tw.parallel().tween_property(self, "modulate:a", 0.0, 0.5)
		tw.finished.connect(queue_free)
		set_process(false)
		return

	if not _is_3d:
		queue_redraw()

func _draw() -> void:
	if _is_3d:
		return
	# Fallback 2D puro
	var pulse = 0.5 + 0.5 * sin(_elapsed * 7.0)
	draw_circle(Vector2.ZERO, radius, Color(0.8, 0.25, 0.05, 0.15 + 0.10 * pulse))
	draw_arc(Vector2.ZERO, radius, 0, TAU, 64, Color(0.95, 0.35, 0.08, 0.6 + 0.3 * pulse), 4.0, true)
	draw_arc(Vector2.ZERO, radius * 0.6, 0, TAU, 48, Color(0.9, 0.4, 0.1, 0.3 + 0.2 * pulse), 2.0, true)

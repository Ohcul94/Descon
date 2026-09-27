extends Node2D

# FireballSunVisual.gd (v901.0 - Bola de Fuego Dinámica / Sun Ball)
#
# VFX de la esfera solar que nace y se mueve dentro de un área determinada.
# El servidor es el dueño de la verdad (spawn, posición, daño, duración y cooldown salen
# de Server/behaviors/mechanics/FireballMechanics.js); aquí SOLO se renderiza.
#
# Patrón: este Node2D es el controlador/lifecycle (EntityManager lo spawnea con
# set_as_top_level(true) dentro de world.entities_node) y el cuerpo "tipo sol" se construye
# en 3D dentro de map.sub_viewport, igual que WormVisual / WindWallVisual / MeteorZoneVisual.
# En mapas sin sub_viewport cae a un fallback 2D dibujado con _draw().

var map_node: Node = null
var enemy_node: Node = null

var _mode := "sun" # "sun" (bola activa) | "charge" (telegrafiado del área)

var _radius := 90.0 # px: tamaño de la bola (== radio de daño)
var _area_radius := 350.0 # px: radio del área de deambulo
var _area_center := Vector2.ZERO
var _duration := 6.0 # seg
var _speed := 180.0 # px/s (informativo: la posición la manda el servidor)

var _target_pos := Vector2.ZERO
var _elapsed := 0.0
var _charge_elapsed := 0.0
var _charge_time := 1.2
var _finishing := false

var _is_3d := false
var _sf := 0.02
var _cz := 1.41421356

var root_3d: Node3D = null
var area_root_3d: Node3D = null

var _core: MeshInstance3D = null
var _core_mat: StandardMaterial3D = null
var _corona: MeshInstance3D = null
var _corona_mat: StandardMaterial3D = null
var _glow: MeshInstance3D = null
var _light: OmniLight3D = null
var _flares: GPUParticles3D = null
var _area_disc_mat: StandardMaterial3D = null
var _area_ring_mat: StandardMaterial3D = null

# ------------------------------------------------------------------------------
# API llamada desde EntityManager._handle_fireball_action()
# ------------------------------------------------------------------------------
func setup(p_data: Dictionary, p_map: Node, p_enemy: Node = null) -> void:
	map_node = p_map
	enemy_node = p_enemy
	_mode = "sun"
	_read_params(p_data)
	global_position = Vector2(float(p_data.get("x", _area_center.x)), float(p_data.get("y", _area_center.y)))
	_target_pos = global_position
	_resolve_map_scale()
	_build_area_root()
	_build_sun_3d()
	_connect_cleanup()
	queue_redraw()

func setup_charge(p_data: Dictionary, p_map: Node, p_enemy: Node = null) -> void:
	map_node = p_map
	enemy_node = p_enemy
	_mode = "charge"
	_read_params(p_data)
	_charge_time = maxf(0.05, float(p_data.get("chargeMs", 1200.0)) / 1000.0)
	global_position = _area_center
	_target_pos = global_position
	_resolve_map_scale()
	_build_area_root()
	_connect_cleanup()
	queue_redraw()

func set_target(p_pos: Vector2) -> void:
	if _finishing:
		return
	# Salto grande (evento perdido o re-spawn): corregir de inmediato
	if global_position.distance_to(p_pos) > 300.0:
		global_position = p_pos
	_target_pos = p_pos

func finish() -> void:
	if _finishing:
		return
	_finishing = true

	if is_instance_valid(VFXSystem):
		VFXSystem.spawn_explosion(global_position, clampf(_radius / 100.0, 0.6, 3.0))

	var tw := create_tween().set_parallel(true)
	var has_tween := false
	if is_instance_valid(root_3d):
		tw.tween_property(root_3d, "scale", Vector3.ZERO, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		has_tween = true
	if is_instance_valid(area_root_3d):
		tw.tween_property(area_root_3d, "scale", Vector3.ZERO, 0.3).set_ease(Tween.EASE_IN)
		has_tween = true
	if not has_tween:
		_free_all()
		return
	tw.finished.connect(_free_all)

func _free_all() -> void:
	if is_instance_valid(root_3d):
		root_3d.queue_free()
	if is_instance_valid(area_root_3d):
		area_root_3d.queue_free()
	queue_free()

func _read_params(p_data: Dictionary) -> void:
	_radius = maxf(10.0, float(p_data.get("radius", 90.0)))
	_area_radius = maxf(0.0, float(p_data.get("areaRadius", 350.0)))
	_area_center = Vector2(
		float(p_data.get("areaX", p_data.get("x", 0.0))),
		float(p_data.get("areaY", p_data.get("y", 0.0)))
	)
	_duration = maxf(0.5, float(p_data.get("duration", 6000.0)) / 1000.0)
	_speed = maxf(0.0, float(p_data.get("speed", 180.0)))

func _resolve_map_scale() -> void:
	_is_3d = is_instance_valid(map_node) and ("sub_viewport" in map_node) and is_instance_valid(map_node.get("sub_viewport"))
	if not _is_3d:
		return
	if "scale_factor" in map_node:
		_sf = map_node.scale_factor
	if "correction_z" in map_node:
		_cz = map_node.correction_z

func _connect_cleanup() -> void:
	# El Node2D no libera sus copias 3D al morir: hay que hacerlo a mano
	tree_exiting.connect(func():
		if is_instance_valid(root_3d):
			root_3d.queue_free()
		if is_instance_valid(area_root_3d):
			area_root_3d.queue_free()
	)

# ------------------------------------------------------------------------------
# Construcción 3D
# ------------------------------------------------------------------------------
func _build_area_root() -> void:
	if not _is_3d or _area_radius <= 0.0:
		return
	area_root_3d = Node3D.new()
	area_root_3d.name = "FireballArea_" + str(get_instance_id())
	map_node.sub_viewport.add_child(area_root_3d)

	var r3d := _area_radius * _sf

	# Tinte suave del suelo donde deambula la bola
	var disc := MeshInstance3D.new()
	var dmesh := CylinderMesh.new()
	dmesh.top_radius = r3d
	dmesh.bottom_radius = r3d
	dmesh.height = 0.015
	disc.mesh = dmesh
	_area_disc_mat = StandardMaterial3D.new()
	_area_disc_mat.albedo_color = Color(1.0, 0.42, 0.05, 0.13)
	_area_disc_mat.emission_enabled = true
	_area_disc_mat.emission = Color(1.0, 0.35, 0.03)
	_area_disc_mat.emission_energy_multiplier = 0.7
	_area_disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_area_disc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_area_disc_mat.no_depth_test = true
	_area_disc_mat.render_priority = 2
	disc.material_override = _area_disc_mat
	disc.position.y = 0.012
	area_root_3d.add_child(disc)

	# Borde del área
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(0.01, r3d - 0.12)
	torus.outer_radius = r3d
	ring.mesh = torus
	_area_ring_mat = StandardMaterial3D.new()
	_area_ring_mat.albedo_color = Color(1.0, 0.6, 0.15, 0.75)
	_area_ring_mat.emission_enabled = true
	_area_ring_mat.emission = Color(1.0, 0.5, 0.1)
	_area_ring_mat.emission_energy_multiplier = 2.4
	_area_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_area_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_area_ring_mat.no_depth_test = true
	_area_ring_mat.render_priority = 3
	ring.material_override = _area_ring_mat
	ring.position.y = 0.03
	area_root_3d.add_child(ring)

	_sync_area_3d()

func _build_sun_3d() -> void:
	if not _is_3d:
		return
	root_3d = Node3D.new()
	root_3d.name = "FireballSun3D_" + str(get_instance_id())
	map_node.sub_viewport.add_child(root_3d)

	var r3d := _radius * _sf

	# 1. Núcleo estelar (blanco brillante)
	_core = MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = r3d
	core_mesh.height = r3d * 2.0
	_core.mesh = core_mesh
	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.albedo_color = Color(1.0, 0.93, 0.62)
	_core_mat.emission_enabled = true
	_core_mat.emission = Color(1.0, 0.8, 0.3)
	_core_mat.emission_energy_multiplier = 3.4
	root_3d.add_child(_core)

	# 2. Cromosfera: envolvente aditiva un poco mayor (borde anaranjado)
	_corona = MeshInstance3D.new()
	var corona_mesh := SphereMesh.new()
	corona_mesh.radius = r3d * 1.38
	corona_mesh.height = r3d * 2.76
	_corona.mesh = corona_mesh
	_corona_mat = StandardMaterial3D.new()
	_corona_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_corona_mat.albedo_color = Color(1.0, 0.45, 0.06, 0.35)
	_corona_mat.emission_enabled = true
	_corona_mat.emission = Color(1.0, 0.38, 0.03)
	_corona_mat.emission_energy_multiplier = 2.0
	_corona_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_corona_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_corona_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_corona_mat.no_depth_test = true
	_corona_mat.render_priority = 2
	_corona.material_override = _corona_mat
	root_3d.add_child(_corona)

	# 3. Halo billboard (brillo radial suave tipo sol)
	_glow = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(r3d * 6.0, r3d * 6.0)
	_glow.mesh = quad
	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow_mat.no_depth_test = true
	glow_mat.render_priority = 4
	glow_mat.albedo_color = Color(1.0, 0.55, 0.12, 0.75)
	glow_mat.albedo_texture = _make_radial_gradient(0.5, 1.0, 0.12)
	_glow.material_override = glow_mat
	root_3d.add_child(_glow)

	# 4. Luz que ilumina el entorno
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.58, 0.18)
	_light.light_energy = 4.0
	_light.omni_range = maxf(r3d * 8.0, 3.0)
	_light.shadow_enabled = false
	root_3d.add_child(_light)

	# 5. Prominencias solares (chispas que salen despedidas de la superficie)
	_flares = GPUParticles3D.new()
	_flares.amount = 44
	_flares.lifetime = 1.1
	_flares.randomness = 0.6
	_flares.preprocess = 1.0
	_flares.local_coords = false
	var fmesh := QuadMesh.new()
	fmesh.size = Vector2(maxf(r3d * 0.5, 0.06), maxf(r3d * 0.5, 0.06))
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fmat.albedo_color = Color(1.0, 0.7, 0.25, 0.9)
	fmat.albedo_texture = _make_radial_gradient(0.85, 1.0, 0.25)
	_flares.draw_pass_1 = fmesh

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = r3d * 0.9
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 180.0
	pm.initial_velocity_min = r3d * 0.5
	pm.initial_velocity_max = r3d * 1.4
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.5
	pm.scale_max = 1.6
	var fgrad := Gradient.new()
	fgrad.set_color(0, Color(1.0, 0.85, 0.35, 0.95))
	fgrad.set_color(1, Color(1.0, 0.25, 0.0, 0.0))
	var fgrad_tex := GradientTexture1D.new()
	fgrad_tex.gradient = fgrad
	pm.color_ramp = fgrad_tex
	_flares.process_material = pm
	root_3d.add_child(_flares)
	_flares.emitting = true

	_sync_sun_3d()

func _make_radial_gradient(inner_alpha: float, outer_stop: float, brightness: float) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.9 * brightness + 0.1, 0.45 * brightness, inner_alpha))
	grad.set_color(1, Color(1.0, 0.35, 0.02, 0.0))
	grad.add_point(outer_stop * 0.5, Color(1.0, 0.6 * brightness, 0.1, inner_alpha * 0.5))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	return tex

# ------------------------------------------------------------------------------
# Sincronización de posiciones 2D (px de mundo) -> 3D
# ------------------------------------------------------------------------------
func _terrain_h(pos: Vector2) -> float:
	if is_instance_valid(map_node) and map_node.has_method("get_terrain_height_at_pos") and is_instance_valid(map_node.get("terrain_node")):
		return map_node.get_terrain_height_at_pos(pos)
	# Mapa sin terreno: a la misma altura que entidades/ataques (EntityManager._attack_vfx_base_y)
	var pl := get_tree().get_first_node_in_group("player")
	if is_instance_valid(pl) and is_instance_valid(pl.get("world_root_3d")):
		return pl.world_root_3d.position.y
	return 1.0

func _sync_sun_3d() -> void:
	if not is_instance_valid(root_3d):
		return
	var h := _terrain_h(global_position) + 1.0
	root_3d.position = Vector3(global_position.x * _sf, h, global_position.y * _sf * _cz)

func _sync_area_3d() -> void:
	if not is_instance_valid(area_root_3d):
		return
	var h := _terrain_h(_area_center)
	area_root_3d.position = Vector3(_area_center.x * _sf, h, _area_center.y * _sf * _cz)

# ------------------------------------------------------------------------------
# Animación / lifecycle
# ------------------------------------------------------------------------------
func _process(delta: float) -> void:
	if _finishing:
		return
	_elapsed += delta

	if _mode == "charge":
		_charge_elapsed += delta
		_animate_area(delta, true)
		_sync_area_3d()
		if not _is_3d:
			queue_redraw()
		# Fallback si se perdió el evento de spawn
		if _charge_elapsed > _charge_time + 3.0:
			finish()
		return

	# Interpolación suave hacia la posición autoritativa del servidor
	var dist := global_position.distance_to(_target_pos)
	if dist > 0.5:
		global_position = global_position.lerp(_target_pos, minf(1.0, delta * 14.0))
		if global_position.distance_to(_target_pos) < 1.5:
			global_position = _target_pos

	_animate_sun(delta)
	_animate_area(delta, false)
	_sync_sun_3d()
	_sync_area_3d()
	if not _is_3d:
		queue_redraw()

	# Autoliberación de seguridad (servidor que se calla: enemigo muerto o zona perdida)
	if _elapsed > _duration + 2.0:
		finish()

func _animate_sun(delta: float) -> void:
	var t := _elapsed
	if is_instance_valid(_core):
		var pulse := 1.0 + sin(t * 6.0) * 0.055
		_core.scale = Vector3(pulse, pulse, pulse)
	if is_instance_valid(_core_mat):
		_core_mat.emission_energy_multiplier = 3.2 + sin(t * 8.0) * 0.9
	if is_instance_valid(_corona):
		_corona.scale = Vector3.ONE * (1.0 + sin(t * 3.4) * 0.1)
		_corona.rotation.y += delta * 0.9
	if is_instance_valid(_corona_mat):
		_corona_mat.emission_energy_multiplier = 1.7 + sin(t * 5.5 + 1.0) * 0.7
	if is_instance_valid(_light):
		_light.light_energy = 3.6 + sin(t * 9.0) * 1.3

func _animate_area(_delta: float, is_charge: bool) -> void:
	if not is_instance_valid(_area_disc_mat) or not is_instance_valid(_area_ring_mat):
		return
	var t := _elapsed
	if is_charge:
		# Telegrafiado: pulso rápido mientras se carga
		var k := 0.5 + 0.5 * sin(t * 9.0)
		_area_disc_mat.albedo_color.a = lerpf(0.08, 0.3, k)
		_area_ring_mat.emission_energy_multiplier = lerpf(1.6, 4.5, k)
		_area_disc_mat.emission_energy_multiplier = lerpf(0.5, 1.8, k)
	else:
		_area_disc_mat.albedo_color.a = 0.11 + 0.04 * sin(t * 2.5)
		_area_ring_mat.emission_energy_multiplier = 2.2 + 0.6 * sin(t * 2.5)

# ------------------------------------------------------------------------------
# Fallback 2D (mapas sin sub_viewport)
# ------------------------------------------------------------------------------
func _draw() -> void:
	if _is_3d:
		return # el cuerpo vive en 3D; dibujar en 2D encima rompería la proyección

	var t := _elapsed
	var area_off := _area_center - global_position

	if _mode == "charge":
		var k := 0.5 + 0.5 * sin(t * 9.0)
		draw_circle(Vector2.ZERO, _area_radius, Color(1.0, 0.42, 0.05, lerpf(0.06, 0.2, k)))
		draw_arc(Vector2.ZERO, _area_radius, 0.0, TAU, 56, Color(1.0, 0.6, 0.15, lerpf(0.35, 0.9, k)), 3.0, true)
		return

	if _area_radius > 0.0:
		draw_circle(area_off, _area_radius, Color(1.0, 0.4, 0.05, 0.07))
		draw_arc(area_off, _area_radius, 0.0, TAU, 56, Color(1.0, 0.55, 0.1, 0.3), 2.0, true)

	var pulse := 1.0 + sin(t * 6.0) * 0.06
	var r := _radius * pulse
	draw_circle(Vector2.ZERO, r * 1.7, Color(1.0, 0.35, 0.03, 0.16))
	draw_circle(Vector2.ZERO, r * 1.25, Color(1.0, 0.5, 0.05, 0.3))
	draw_circle(Vector2.ZERO, r, Color(1.0, 0.62, 0.1, 0.8))
	draw_circle(Vector2.ZERO, r * 0.62, Color(1.0, 0.86, 0.4, 0.95))
	draw_circle(Vector2.ZERO, r * 0.34, Color(1.0, 1.0, 0.88, 1.0))

	# Prominencias girando alrededor del borde
	for i in range(10):
		var a := t * 1.6 + TAU * float(i) / 10.0
		var p := Vector2(cos(a), sin(a)) * (r * 1.08)
		draw_circle(p, 4.0 + 2.0 * sin(t * 7.0 + float(i)), Color(1.0, 0.5, 0.08, 0.5))

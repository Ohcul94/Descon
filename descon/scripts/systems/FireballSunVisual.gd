extends Node2D

# FireballSunVisual.gd (v901.0 - Bola de Fuego Dinámica / Sun Ball)
#
# VFX de la esfera solar que nace y se mueve dentro de un área determinada.
# El servidor es el dueño de la verdad (spawn, posición, daño, duración y cooldown salen
# de Server/behaviors/mechanics/FireballMechanics.js); aquí SOLO se renderiza.
#
# Aspecto: silueta CIRCULAR (disco de fuego billboard con degradado radial, sin geometría
# esférica sólida y sin marca en el piso) rodeada de rayos tipo rayo eléctrico (zigzag
# irregular) en colores de fuego: incandescente en la base -> naranja -> rojo transparente
# en la punta. Además halo de brillo, chispas GPU y luz.
# El casteo usa exactamente la misma estructura pero "germinando": disco y rayos crecen
# desde casi nada hasta el tamaño final mientras dura el cast.
#
# Patrón: este Node2D es el controlador/lifecycle (EntityManager lo spawnea con
# set_as_top_level(true) dentro de world.entities_node) y el cuerpo vive en 3D dentro de
# map.sub_viewport, igual que WormVisual / WindWallVisual. Sin sub_viewport cae a un
# fallback 2D dibujado con _draw().

const RAY_COUNT := 30
const BOLT_STEPS := 6

var map_node: Node = null
var enemy_node: Node = null

var _mode := "sun" # "sun" (bola activa) | "charge" (forma la bola al castear)

var _radius := 90.0 # px: tamaño de la bola (== radio de daño)
var _area_center := Vector2.ZERO # px: centro del área (dónde nace la bola)
var _duration := 6.0 # seg
var _speed := 180.0 # px/s (informativo: la posición la manda el servidor)

var _specs: Array = [] # semilla por rayo: ángulo, longitud, ancho, velocidad, fase

var _target_pos := Vector2.ZERO
var _elapsed := 0.0
var _charge_elapsed := 0.0
var _charge_time := 1.2
var _finishing := false

var _is_3d := false
var _sf := 0.02
var _cz := 1.41421356

var root_3d: Node3D = null
var ray_root: Node3D = null
var _ray_nodes: Array = [] # [{node: Node3D, spec: Dictionary}]
var _disc: MeshInstance3D = null
var _glow: MeshInstance3D = null
var _glow_core: MeshInstance3D = null
var _light: OmniLight3D = null
var _flares: GPUParticles3D = null

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
	_build_sun_3d()
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

	if not is_instance_valid(root_3d):
		queue_free()
		return

	var tw := create_tween()
	tw.tween_property(root_3d, "scale", Vector3.ZERO, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.finished.connect(_free_all)

func _free_all() -> void:
	if is_instance_valid(root_3d):
		root_3d.queue_free()
	queue_free()

func _read_params(p_data: Dictionary) -> void:
	_radius = maxf(10.0, float(p_data.get("radius", 90.0)))
	_area_center = Vector2(
		float(p_data.get("areaX", p_data.get("x", 0.0))),
		float(p_data.get("areaY", p_data.get("y", 0.0)))
	)
	_duration = maxf(0.5, float(p_data.get("duration", 6000.0)) / 1000.0)
	_speed = maxf(0.0, float(p_data.get("speed", 180.0)))
	_gen_specs()

func _resolve_map_scale() -> void:
	_is_3d = is_instance_valid(map_node) and ("sub_viewport" in map_node) and is_instance_valid(map_node.get("sub_viewport"))
	if not _is_3d:
		return
	if "scale_factor" in map_node:
		_sf = map_node.scale_factor
	if "correction_z" in map_node:
		_cz = map_node.correction_z

func _connect_cleanup() -> void:
	# El Node2D no libera su copia 3D al morir: hay que hacerlo a mano
	tree_exiting.connect(func():
		if is_instance_valid(root_3d):
			root_3d.queue_free()
	)

# ------------------------------------------------------------------------------
# Semilla de los rayos (compartida por el render 3D y el fallback 2D)
# ------------------------------------------------------------------------------
func _gen_specs() -> void:
	_specs.clear()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(RAY_COUNT):
		var base := TAU * float(i) / float(RAY_COUNT)
		_specs.append({
			"angle": base + rng.randf_range(-0.14, 0.14), # caída en el plano 2D
			"azim": base + rng.randf_range(-0.4, 0.4), # giro alrededor de Y (3D)
			"elev": asin(rng.randf_range(-1.0, 1.0)), # elevación uniforme en la esfera (3D)
			"len": rng.randf_range(1.0, 1.8), # longitud relativa del rayo (corto, tipo chispa)
			"wid": rng.randf_range(0.25, 0.55), # anchura relativa del rayo (angosto)
			"speed": rng.randf_range(2.5, 7.5), # velocidad de parpadeo
			"phase": rng.randf_range(0.0, TAU)
		})

func _ray_direction(spec: Dictionary) -> Vector3:
	var az: float = spec.azim
	var el: float = spec.elev
	var flat := cos(el)
	return Vector3(cos(az) * flat, sin(el), sin(az) * flat)

# ------------------------------------------------------------------------------
# Construcción 3D
# ------------------------------------------------------------------------------
func _build_sun_3d() -> void:
	if not _is_3d:
		return
	root_3d = Node3D.new()
	root_3d.name = "FireballSun3D_" + str(get_instance_id())
	map_node.sub_viewport.add_child(root_3d)

	var r3d := _radius * _sf

	# 1. Rayos tipo rayo eléctrico en colores de fuego: dos láminas cruzadas con
	#    zigzag y degradado por vértice (incandescente -> rojo transparente).
	ray_root = Node3D.new()
	ray_root.name = "Rays"
	root_3d.add_child(ray_root)
	var ray_mat := _make_ray_material()
	_ray_nodes.clear()
	for spec in _specs:
		var dir := _ray_direction(spec)
		if dir.length_squared() < 0.0001:
			dir = Vector3.UP
		var wrap := Node3D.new()
		wrap.quaternion = Quaternion(Vector3.UP, dir.normalized())
		ray_root.add_child(wrap)
		var mi := MeshInstance3D.new()
		mi.mesh = _make_bolt_mesh(r3d * float(spec.len), r3d * float(spec.wid) * 0.5, float(spec.phase))
		mi.material_override = ray_mat
		wrap.add_child(mi)
		_ray_nodes.append({"node": wrap, "spec": spec})

	# 2. Disco de fuego circular (billboard): es la silueta redonda de la bola.
	#    Es un sprite radial, NO una malla esférica.
	_disc = MeshInstance3D.new()
	var disc_quad := QuadMesh.new()
	disc_quad.size = Vector2(r3d * 2.6, r3d * 2.6)
	_disc.mesh = disc_quad
	var disc_mat := _make_billboard_material(Color(1.0, 0.78, 0.32, 0.95), 5)
	disc_mat.albedo_texture = _make_ball_gradient()
	_disc.material_override = disc_mat
	root_3d.add_child(_disc)

	# 3. Halo de fuego (billboard aditivo): dilata la silueta sin endurecerla
	_glow = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(r3d * 7.0, r3d * 7.0)
	_glow.mesh = quad
	var glow_mat := _make_billboard_material(Color(1.0, 0.5, 0.1, 0.6), 4)
	glow_mat.albedo_texture = _make_radial_gradient(1.0, 1.0, 0.55)
	_glow.material_override = glow_mat
	root_3d.add_child(_glow)

	# 4. Centro incandescente (blanco amarillo, pequeño)
	_glow_core = MeshInstance3D.new()
	var core_quad := QuadMesh.new()
	core_quad.size = Vector2(r3d * 1.5, r3d * 1.5)
	_glow_core.mesh = core_quad
	var core_mat := _make_billboard_material(Color(1.0, 0.95, 0.7, 0.9), 6)
	core_mat.albedo_texture = _make_radial_gradient(1.0, 1.0, 1.0)
	_glow_core.material_override = core_mat
	root_3d.add_child(_glow_core)

	# 5. Luz que ilumina el entorno
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.58, 0.18)
	_light.light_energy = 4.0
	_light.omni_range = maxf(r3d * 10.0, 3.0)
	_light.shadow_enabled = false
	root_3d.add_child(_light)

	# 6. Chispas que salen despedidas de la bola (efecto de fuego)
	_flares = GPUParticles3D.new()
	_flares.amount = 64
	_flares.lifetime = 1.0
	_flares.randomness = 0.7
	_flares.preprocess = 1.0
	_flares.local_coords = false
	var fmesh := QuadMesh.new()
	fmesh.size = Vector2(maxf(r3d * 0.55, 0.06), maxf(r3d * 0.55, 0.06))
	var fmat := _make_billboard_material(Color(1.0, 0.72, 0.28, 0.9), 0)
	fmat.billboard_keep_scale = false
	fmat.render_priority = 0
	fmat.albedo_texture = _make_radial_gradient(0.9, 1.0, 0.75)
	fmesh.material = fmat # SI NO SE ASIGNA, el QuadMesh usa el material gris por defecto
	_flares.draw_pass_1 = fmesh

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = r3d * 0.7
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 180.0
	pm.initial_velocity_min = r3d * 0.8
	pm.initial_velocity_max = r3d * 2.4
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.4
	pm.scale_max = 1.7
	var fgrad := Gradient.new()
	fgrad.set_color(0, Color(1.0, 0.9, 0.4, 0.95))
	fgrad.set_color(1, Color(1.0, 0.2, 0.0, 0.0))
	var fgrad_tex := GradientTexture1D.new()
	fgrad_tex.gradient = fgrad
	pm.color_ramp = fgrad_tex
	_flares.process_material = pm
	root_3d.add_child(_flares)
	_flares.emitting = true

	_sync_sun_3d()

func _make_billboard_material(p_color: Color, p_priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.no_depth_test = true
	m.render_priority = p_priority
	m.albedo_color = p_color
	return m

func _make_ray_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true # el degradado vive en los vértices, no en UVs
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = 3
	return m

# Degradado de fuego a lo largo del rayo: incandescente -> naranja -> rojo -> transparente
func _bolt_color(f: float) -> Color:
	if f < 0.25:
		return Color(1.0, 0.97, 0.7, 1.0).lerp(Color(1.0, 0.8, 0.25, 0.9), f / 0.25)
	if f < 0.6:
		return Color(1.0, 0.8, 0.25, 0.9).lerp(Color(1.0, 0.42, 0.05, 0.55), (f - 0.25) / 0.35)
	return Color(1.0, 0.42, 0.05, 0.55).lerp(Color(1.0, 0.15, 0.0, 0.0), (f - 0.6) / 0.4)

# Rayo eléctrico: tira de segmentos con zigzag lateral correlacionado y punta afilada.
# Dos láminas cruzadas (XY e YZ) para que se lea desde cualquier ángulo de cámara.
func _make_bolt_mesh(length: float, half_w: float, phase: float) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(phase * 1000000.0)

	var lateral := PackedFloat32Array()
	var j := 0.0
	for i in range(BOLT_STEPS + 1):
		j = j * 0.35 + rng.randf_range(-1.0, 1.0) * 0.75 # zigzag con memoria (rayo)
		lateral.append(j)

	var mesh := ArrayMesh.new()
	for axis in range(2):
		var verts := PackedVector3Array()
		var vcols := PackedColorArray()
		for i in range(BOLT_STEPS + 1):
			var f := float(i) / float(BOLT_STEPS)
			var w := half_w * pow(1.0 - f, 0.75) + 0.0008
			# El zigzag no se encoge con el ancho: así el rayo sigue leyéndose eléctrico
			var x := lateral[i] * maxf(half_w * 2.4, length * 0.05)
			var y := length * f
			var col := _bolt_color(f)
			var a: Vector3
			var b: Vector3
			if axis == 0:
				a = Vector3(x - w, y, 0.0)
				b = Vector3(x + w, y, 0.0)
			else:
				a = Vector3(0.0, y, x - w)
				b = Vector3(0.0, y, x + w)
			verts.append(a)
			vcols.append(col)
			verts.append(b)
			vcols.append(col)
		var idx := PackedInt32Array()
		for i in range(BOLT_STEPS):
			var v0 := i * 2
			idx.append(v0)
			idx.append(v0 + 1)
			idx.append(v0 + 3)
			idx.append(v0)
			idx.append(v0 + 3)
			idx.append(v0 + 2)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = vcols
		arrays[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _make_radial_gradient(inner_alpha: float, outer_stop: float, brightness: float) -> GradientTexture2D:
	var grad := Gradient.new()
	# Se añaden los puntos ANTES de pintarlos: los índices se reordenan al insertar
	grad.add_point(clampf(outer_stop * 0.35, 0.05, 0.95), Color(1, 1, 1, 1))
	grad.set_color(0, Color(1.0, clampf(0.85 * brightness + 0.15, 0.0, 1.0), clampf(0.45 * brightness + 0.1, 0.0, 1.0), inner_alpha))
	grad.set_color(1, Color(1.0, clampf(0.6 * brightness, 0.0, 1.0), 0.1, inner_alpha * 0.45))
	grad.set_color(2, Color(1.0, 0.3, 0.02, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	return tex

# Degradado del disco: centro blanco caliente -> amarillo -> naranja -> rojo (borde
# transparente para que la silueta sea redonda y no se vea el cuadrado del QuadMesh)
func _make_ball_gradient() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.add_point(0.42, Color(1.0, 0.9, 0.35, 0.9))
	grad.add_point(0.74, Color(1.0, 0.48, 0.06, 0.5))
	grad.add_point(1.0, Color(1.0, 0.18, 0.0, 0.0))
	grad.set_color(0, Color(1.0, 0.98, 0.86, 1.0))
	grad.set_color(1, Color(1.0, 0.9, 0.35, 0.9))
	grad.set_color(2, Color(1.0, 0.48, 0.06, 0.5))
	grad.set_color(3, Color(1.0, 0.18, 0.0, 0.0))
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

# ------------------------------------------------------------------------------
# Animación / lifecycle
# ------------------------------------------------------------------------------
func _process(delta: float) -> void:
	if _finishing:
		return
	_elapsed += delta

	var grow := 1.0
	if _mode == "charge":
		# El casteo "germina" la bola: los rayos y el disco crecen hasta el tamaño final
		_charge_elapsed += delta
		grow = clampf(_charge_elapsed / _charge_time, 0.04, 1.0)
		if _charge_elapsed > _charge_time + 3.0:
			finish() # fallback si se perdió el evento de spawn
			return
	else:
		# Interpolación suave hacia la posición autoritativa del servidor
		if global_position.distance_to(_target_pos) > 0.5:
			global_position = global_position.lerp(_target_pos, minf(1.0, delta * 14.0))
			if global_position.distance_to(_target_pos) < 1.5:
				global_position = _target_pos

	_animate_sun(delta, grow)
	_sync_sun_3d()
	if not _is_3d:
		queue_redraw()

	# Autoliberación de seguridad (servidor que se calla: enemigo muerto o zona perdida)
	if _mode == "sun" and _elapsed > _duration + 2.0:
		finish()

func _animate_sun(delta: float, grow: float) -> void:
	var t := _elapsed
	var charge_boost := 1.0
	if _mode == "charge":
		charge_boost = 1.35 + 0.65 * sin(t * 12.0) # el casteo tiembla más

	# Rayos eléctricos: respiran con su velocidad/fase + destello agudo ocasional
	for entry in _ray_nodes:
		var n: Node3D = entry.node
		if not is_instance_valid(n):
			continue
		var spec: Dictionary = entry.spec
		var ph: float = spec.phase
		var sp: float = spec.speed
		var pulse := 0.7 + 0.5 * (0.5 + 0.5 * sin(t * sp + ph))
		var spark := 1.0
		if sin(t * sp * 6.0 + ph * 3.1) > 0.88:
			spark = 1.7
		var wob := 0.85 + 0.35 * (0.5 + 0.5 * sin(t * sp * 1.7 + ph * 2.0))
		var s := minf(grow * pulse * charge_boost * spark, 1.45)
		var w := wob * minf(grow * 1.4, 1.0)
		n.scale = Vector3(w, s, w)

	if is_instance_valid(ray_root):
		ray_root.rotation.y += delta * (1.1 if _mode == "charge" else 0.35)
		ray_root.rotation.z += delta * 0.12

	if is_instance_valid(_disc):
		_disc.scale = Vector3.ONE * (grow * (1.0 + 0.06 * sin(t * 7.0)))
	if is_instance_valid(_glow):
		_glow.scale = Vector3.ONE * (grow * (1.0 + 0.07 * sin(t * 6.5)))
	if is_instance_valid(_glow_core):
		_glow_core.scale = Vector3.ONE * (grow * (1.0 + 0.12 * sin(t * 9.0 + 0.7)))
	if is_instance_valid(_light):
		_light.light_energy = grow * (3.4 + 1.5 * sin(t * 8.5)) * charge_boost
	if is_instance_valid(_flares):
		_flares.emitting = grow > 0.15

# ------------------------------------------------------------------------------
# Fallback 2D (mapas sin sub_viewport): disco circular + rayos eléctricos
# ------------------------------------------------------------------------------
func _bolt_polygon(angle: float, length: float, half_w: float, phase: float) -> PackedVector2Array:
	var dir_v := Vector2(cos(angle), sin(angle))
	var perp := Vector2(-dir_v.y, dir_v.x)
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in range(BOLT_STEPS + 1):
		var f := float(i) / float(BOLT_STEPS)
		var k := f * 7.0
		var w := half_w * pow(1.0 - f, 0.75)
		var lateral := (
			0.5 * sin(k * 2.3 + phase)
			+ 0.3 * sin(k * 5.1 + phase * 1.7)
			+ 0.25 * sin(k * 9.3 + phase * 0.6)
		) * maxf(half_w * 2.4, length * 0.05) * f
		var c := dir_v * (length * f) + perp * lateral
		left.append(c + perp * w)
		right.append(c - perp * w)
	var poly := PackedVector2Array()
	for i in range(left.size()):
		poly.append(left[i])
	for i in range(right.size() - 1, -1, -1):
		poly.append(right[i])
	return poly

func _draw() -> void:
	if _is_3d:
		return # el cuerpo vive en 3D; dibujar en 2D encima rompería la proyección

	var t := _elapsed
	var grow := 1.0
	if _mode == "charge":
		grow = clampf(_charge_elapsed / _charge_time, 0.04, 1.0)
	var r := _radius * grow
	if _specs.is_empty():
		_gen_specs()

	# Silueta circular: halo concéntrico de fuego (sin esfera sólida ni marca en el piso)
	draw_circle(Vector2.ZERO, r * 2.6, Color(1.0, 0.42, 0.05, 0.14 * grow))
	draw_circle(Vector2.ZERO, r * 1.6, Color(1.0, 0.55, 0.08, 0.26 * grow))
	draw_circle(Vector2.ZERO, r * 0.9, Color(1.0, 0.72, 0.2, 0.5 * grow))
	draw_circle(Vector2.ZERO, r * 0.45, Color(1.0, 0.95, 0.7, 0.85 * grow))

	# Capa lejana: rayos eléctricos largos y tenues
	for spec in _specs:
		var ph: float = spec.phase
		var flick := 0.6 + 0.4 * (0.5 + 0.5 * sin(t * float(spec.speed) + ph))
		if sin(t * float(spec.speed) * 6.0 + ph * 3.1) > 0.88:
			flick *= 1.5
		var len_f := r * float(spec.len) * flick
		var w := r * float(spec.wid) * 0.16
		var poly := _bolt_polygon(float(spec.angle), len_f, w, ph)
		if poly.size() >= 3:
			draw_colored_polygon(poly, Color(1.0, 0.4, 0.05, 0.24 * minf(flick, 1.0) * grow))
	# Capa media
	for spec in _specs:
		var ph: float = spec.phase + 1.3
		var flick := 0.55 + 0.45 * (0.5 + 0.5 * sin(t * float(spec.speed) * 1.3 + ph))
		var len_f := r * float(spec.len) * 0.62 * flick
		var w := r * float(spec.wid) * 0.13
		var poly := _bolt_polygon(float(spec.angle), len_f, w, ph)
		if poly.size() >= 3:
			draw_colored_polygon(poly, Color(1.0, 0.62, 0.12, 0.5 * minf(flick, 1.0) * grow))
	# Capa interna: destellos cortos e incandescentes
	for spec in _specs:
		var ph: float = spec.phase + 2.6
		var flick := 0.5 + 0.5 * (0.5 + 0.5 * sin(t * float(spec.speed) * 1.9 + ph))
		var len_f := r * float(spec.len) * 0.34 * flick
		var w := r * float(spec.wid) * 0.1
		var poly := _bolt_polygon(float(spec.angle), len_f, w, ph)
		if poly.size() >= 3:
			draw_colored_polygon(poly, Color(1.0, 0.9, 0.55, 0.85 * minf(flick, 1.0) * grow))

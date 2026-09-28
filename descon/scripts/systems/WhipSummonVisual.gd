extends Node2D

# WhipSummonVisual.gd (v416.0 - Látigo Dominante AAA)
# Visual de alta fidelidad para la mecánica "Látigo Dominante (whip_summon)".
# Simula un látigo místico de energía ígnea/eléctrica con física de azote real:
#  1. Enrollado/Onda aérea Bezier tridimensional que viaja desde el enemigo.
#  2. Latigazo violento (snap) descendente directamente hacia la nave objetivo.
#  3. Impacto cinemático en el aire a la altura de la nave (chispas 3D, destello billboard, choque de energía).
#  4. Retracción elástica y disolución suave (alfa y emisión a cero).
#  5. Limpieza absoluta: NINGÚN residuo o mancha en el piso.

# Texturas VFX precargadas
const WHIP_THUNDER_TEX = preload("res://VFX/textures/T_VFX_thunder_texture.png")
const WHIP_FIRE_TEX = preload("res://VFX/textures/T_VFX_FireBall_s1_alpha.jpg")
const WHIP_SPARK_TEX = preload("res://VFX/textures/T_VFX_Spark41.jpg")
const WHIP_FLARE_TEX = preload("res://VFX/textures/T_VFX_Flare_15.PNG")

# Parámetros y referencias
var map_node: Node = null
var enemy_node: Node = null
var root_3d: Node3D = null

var _target_id: String = ""
var _target_node: Node = null
var _target_pos := Vector2.ZERO
var _enemy_pos := Vector2.ZERO

var _hits_done := 0
var _total_hits := 3
var _cadence := 300
var _damage := 50
var _cast_time := 0.5
var _is_charging := false
var _charge_elapsed := 0.0
var _finishing := false

var _is_3d := false
var _sf := 0.02
var _cz := 1.41421356

# Nodo de advertencia de casteo 3D
var _charge_beam_3d: MeshInstance3D = null
var _charge_mat: StandardMaterial3D = null

# ------------------------------------------------------------------------------
# INICIALIZACIÓN (Llamada desde BossActionHandler / EntityManager)
# ------------------------------------------------------------------------------
func setup(p_data: Dictionary, p_map: Node, p_enemy: Node = null) -> void:
	map_node = p_map
	enemy_node = p_enemy
	_hits_done = 0
	_total_hits = int(p_data.get("hits", p_data.get("totalHits", 3)))
	_cadence = int(p_data.get("cadence", 300))
	_damage = int(p_data.get("damage", 50))
	_cast_time = maxf(float(p_data.get("castTimeMs", 500.0)) / 1000.0, 0.1)
	_target_id = str(p_data.get("targetId", ""))
	
	_enemy_pos = Vector2(float(p_data.get("x", 0.0)), float(p_data.get("y", 0.0)))
	_target_pos = Vector2(float(p_data.get("targetX", 0.0)), float(p_data.get("targetY", 0.0)))
	
	_resolve_target_node()
	
	_check_3d()
	if _is_3d:
		_build_root_3d()
		_start_charge_visual()
	else:
		_is_charging = true
		_charge_elapsed = 0.0

	# Conectar salida del árbol para garantizar liberación inmediata de recursos 3D
	tree_exiting.connect(_cleanup_all_3d)
	
	# Temporizador de seguridad: autoliberación tras el tiempo total esperado + margen
	var max_life: float = (_total_hits * float(_cadence) / 1000.0) + _cast_time + 4.0
	var tw_safety = create_tween()
	tw_safety.tween_interval(max_life)
	tw_safety.finished.connect(func():
		_cleanup_all_3d()
		queue_free()
	)

func _check_3d() -> void:
	var map = get_tree().get_first_node_in_group("map") if not is_instance_valid(map_node) else map_node
	_is_3d = is_instance_valid(map) and map.get("sub_viewport") != null and is_instance_valid(map.sub_viewport)
	if _is_3d:
		_sf = map.scale_factor if "scale_factor" in map else 0.02
		_cz = map.correction_z if "correction_z" in map else 1.41421356

func _build_root_3d() -> void:
	if not _is_3d: return
	root_3d = Node3D.new()
	root_3d.name = "WhipRoot3D_" + str(get_instance_id())
	map_node.sub_viewport.add_child(root_3d)

func _resolve_target_node() -> void:
	if _target_id.is_empty(): return
	var em = get_node_or_null("/root/Main/World/EntityManager")
	if not is_instance_valid(em): return
	if "world" in em and is_instance_valid(em.world) and "player" in em.world and is_instance_valid(em.world.player):
		var pid = str(em.world.player.get("id", ""))
		if pid == _target_id:
			_target_node = em.world.player
			return
	if "remote_players" in em and em.remote_players.has(_target_id):
		var rp = em.remote_players[_target_id]
		if is_instance_valid(rp):
			_target_node = rp
			return
	if "enemies" in em and em.enemies.has(_target_id):
		var en = em.enemies[_target_id]
		if is_instance_valid(en):
			_target_node = en

func _sample_height(p2d: Vector2) -> float:
	if not is_instance_valid(map_node): return 0.0
	if map_node.has_method("get_terrain_height_at_pos"):
		return map_node.get_terrain_height_at_pos(p2d)
	return 0.0

func _p2d_to_3d(p2d: Vector2, height_offset: float = 0.8) -> Vector3:
	var th = _sample_height(p2d) + height_offset
	return Vector3(p2d.x * _sf, th, p2d.y * _sf * _cz)

# ------------------------------------------------------------------------------
# FASE 1: ANTICIPACIÓN / CARGA (Línea de tensión y concentración)
# ------------------------------------------------------------------------------
func _start_charge_visual() -> void:
	_is_charging = true
	_charge_elapsed = 0.0
	if not is_instance_valid(root_3d): return

	_charge_beam_3d = MeshInstance3D.new()
	_charge_beam_3d.name = "ChargeAimLine"
	_charge_mat = StandardMaterial3D.new()
	_charge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_charge_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_charge_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_charge_mat.albedo_color = Color(1.0, 0.4, 0.1, 0.4)
	_charge_mat.emission_enabled = true
	_charge_mat.emission = Color(1.0, 0.3, 0.0)
	_charge_mat.emission_energy_multiplier = 2.0
	_charge_beam_3d.material_override = _charge_mat
	root_3d.add_child(_charge_beam_3d)
	_update_charge_mesh()

func _update_charge_mesh() -> void:
	if not is_instance_valid(_charge_beam_3d): return
	var from_3d = _get_current_enemy_3d()
	var to_3d = _get_current_target_3d()
	
	var pts: Array[Vector3] = []
	var segs = 14
	var dir = to_3d - from_3d
	for i in range(segs + 1):
		var frac = float(i) / float(segs)
		var pt = from_3d + dir * frac
		if i > 0 and i < segs:
			var jitter = sin(_charge_elapsed * 25.0 + float(i)) * 0.05
			pt.y += jitter
		pts.append(pt)
	var new_mesh = _build_ribbon_mesh(pts, 0.04, 0.02)
	if new_mesh:
		_charge_beam_3d.mesh = new_mesh

func _stop_charge_visual() -> void:
	_is_charging = false
	if is_instance_valid(_charge_beam_3d):
		_charge_beam_3d.queue_free()
		_charge_beam_3d = null

# ------------------------------------------------------------------------------
# FASE 2: GOLPE SUCESIVO (update_hit)
# ------------------------------------------------------------------------------
func update_hit(data: Dictionary) -> void:
	_stop_charge_visual()
	_hits_done += 1
	var tx = float(data.get("targetX", data.get("x", _target_pos.x)))
	var ty = float(data.get("targetY", data.get("y", _target_pos.y)))
	_target_pos = Vector2(tx, ty)
	
	if is_instance_valid(enemy_node):
		_enemy_pos = enemy_node.global_position
		
	var hit_idx = int(data.get("hitIndex", _hits_done - 1))
	_spawn_whip_strike(hit_idx)

# ------------------------------------------------------------------------------
# AZOTE TRIDIMENSIONAL DEL LÁTIGO (Whip Strike Animation)
# ------------------------------------------------------------------------------
func _spawn_whip_strike(hit_idx: int) -> void:
	if _is_3d:
		_spawn_whip_strike_3d(hit_idx)
	else:
		_spawn_whip_strike_2d(hit_idx)

func _get_current_enemy_3d() -> Vector3:
	var ep = enemy_node.global_position if is_instance_valid(enemy_node) else _enemy_pos
	return _p2d_to_3d(ep, 1.2)

func _get_current_target_3d() -> Vector3:
	var tp = _target_node.global_position if is_instance_valid(_target_node) else _target_pos
	return _p2d_to_3d(tp, 0.75)

func _spawn_whip_strike_3d(hit_idx: int) -> void:
	if not is_instance_valid(root_3d):
		_build_root_3d()
	if not is_instance_valid(root_3d): return

	var strike_node = Node3D.new()
	strike_node.name = "Strike_" + str(hit_idx) + "_" + str(Time.get_ticks_msec())
	root_3d.add_child(strike_node)

	var mesh_inst = MeshInstance3D.new()
	mesh_inst.name = "WhipRibbon"
	strike_node.add_child(mesh_inst)

	# Material de fuego/energía puro con blending aditivo
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = WHIP_THUNDER_TEX
	mat.albedo_color = Color(1.0, 0.82, 0.28, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.08)
	mat.emission_energy_multiplier = 6.5
	mesh_inst.material_override = mat

	# Luz dinámica en la punta del látigo
	var tip_light = OmniLight3D.new()
	tip_light.light_color = Color(1.0, 0.65, 0.18)
	tip_light.light_energy = 8.0
	tip_light.omni_range = 5.0
	tip_light.shadow_enabled = false
	strike_node.add_child(tip_light)

	# Variación de arco de azote por golpe para movimiento orgánico
	var side_sign: float = 1.0
	if hit_idx % 3 == 1:
		side_sign = -1.0
	elif hit_idx % 3 == 2:
		side_sign = 0.0

	var duration := 0.58
	var tween = create_tween().set_parallel(true)
	var anim_ref = {"t": 0.0, "impacted": false}

	# Interpolación de progreso del golpe (0.0 -> 1.0)
	tween.tween_method(func(val: float):
		if not is_instance_valid(strike_node) or not is_instance_valid(mesh_inst):
			return
		anim_ref.t = val
		var from_3d = _get_current_enemy_3d()
		var to_3d = _get_current_target_3d()
		
		# Generar curva Bezier del azote con cinta ancha (0.65 a 0.26)
		var curve_pts = _calculate_whip_curve(from_3d, to_3d, val, side_sign)
		var new_mesh = _build_ribbon_mesh(curve_pts, 0.65, 0.26)
		if new_mesh:
			mesh_inst.mesh = new_mesh
		
		# Posicionar la luz en la punta actual del látigo
		if curve_pts.size() > 0:
			tip_light.position = curve_pts[curve_pts.size() - 1]
		
		# ZAS! Impacto en la nave en el momento culminante (val >= 0.48)
		if val >= 0.48 and not anim_ref.impacted:
			anim_ref.impacted = true
			_spawn_hit_impact_3d(to_3d)
		
		# Disolución suave de alfa y emisión tras el impacto
		if val > 0.48:
			var fade = clampf((1.0 - val) / 0.52, 0.0, 1.0)
			mat.albedo_color.a = 0.95 * fade
			mat.emission_energy_multiplier = 6.5 * fade
			tip_light.light_energy = 8.0 * fade
	, 0.0, 1.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	await tween.finished
	if is_instance_valid(strike_node):
		strike_node.queue_free()

# ------------------------------------------------------------------------------
# CÁLCULO CINEMÁTICO DE LA ONDA DEL LÁTIGO (Curvatura Bezier + Onda de Azote)
# ------------------------------------------------------------------------------
func _calculate_whip_curve(p0: Vector3, p_target: Vector3, t: float, side_sign: float) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var segs := 26
	
	var dir = p_target - p0
	var dist = dir.length()
	var fwd = Vector3(dir.x, 0.0, dir.z).normalized()
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	var right = Vector3(-fwd.z, 0.0, fwd.x)
	
	# Puntos de control Bezier dinámicos
	# c1: Curvatura inicial elevada
	var c1 = p0 + fwd * (dist * 0.25) + right * (side_sign * dist * 0.35) + Vector3.UP * 2.4
	
	# c2: Cresta de la onda en el aire
	var c2_elev = 2.6 if t < 0.5 else lerpf(2.6, 0.4, (t - 0.5) / 0.5)
	var c2 = p0 + fwd * (dist * 0.65) + right * (side_sign * dist * 0.2) + Vector3.UP * c2_elev
	
	# c3: Punta del látigo que desciende en picada sobre la nave
	var c3: Vector3
	if t < 0.48:
		var fall_t = t / 0.48
		var tip_y = lerpf(p_target.y + 2.8, p_target.y, ease(fall_t, 2.0))
		var tip_xz = p0.lerp(p_target, fall_t)
		c3 = Vector3(tip_xz.x, tip_y, tip_xz.z)
	else:
		c3 = p_target
	
	# Muestreo de la curva Bezier cúbica con deformación de onda
	var wave_amp = (1.0 - t) * 0.35
	for i in range(segs + 1):
		var u = float(i) / float(segs)
		# Ecuación Bezier cúbica
		var pt = (1.0 - u) * (1.0 - u) * (1.0 - u) * p0 + \
				 3.0 * (1.0 - u) * (1.0 - u) * u * c1 + \
				 3.0 * (1.0 - u) * u * u * c2 + \
				 u * u * u * c3
				
		# Onda elástica senoidal que recorre el cuerpo del látigo
		if i > 0 and i < segs:
			var wave = sin(u * PI * 2.5 - t * 14.0) * wave_amp * (1.0 - u)
			pt += right * (wave * side_sign) + Vector3.UP * (wave * 0.6)
		result.append(pt)
		
	return result

# ------------------------------------------------------------------------------
# CONSTRUCCIÓN DE LA MALLA CINTA (Ribbon Strip Mesh con vista a cámara)
# ------------------------------------------------------------------------------
func _build_ribbon_mesh(points: Array[Vector3], base_w: float, tip_w: float) -> ArrayMesh:
	var num_pts = points.size()
	if num_pts < 2: return null

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Vector hacia la cámara (isométrica 2.5D elevada)
	var cam_dir = Vector3(0.0, 0.85, -0.52).normalized()

	var left_pts: Array[Vector3] = []
	var right_pts: Array[Vector3] = []
	var uvs_u: Array[float] = []

	for i in range(num_pts):
		var p = points[i]
		var tang = Vector3.ZERO
		if i < num_pts - 1:
			tang = (points[i + 1] - p).normalized()
		elif i > 0:
			tang = (p - points[i - 1]).normalized()
		if tang.length_squared() < 0.0001:
			tang = Vector3.FORWARD

		var side = tang.cross(cam_dir).normalized()
		if side.length_squared() < 0.0001:
			side = Vector3.RIGHT

		var u_val = float(i) / float(num_pts - 1)
		var w = lerpf(base_w, tip_w, u_val)

		left_pts.append(p + side * (w * 0.5))
		right_pts.append(p - side * (w * 0.5))
		uvs_u.append(u_val)

	for i in range(num_pts - 1):
		var u1 = uvs_u[i]
		var u2 = uvs_u[i + 1]
		var p0 = left_pts[i]
		var p1 = right_pts[i]
		var p2 = left_pts[i + 1]
		var p3 = right_pts[i + 1]

		# Triángulo 1
		st.set_uv(Vector2(u1, 0.0))
		st.add_vertex(p0)
		st.set_uv(Vector2(u2, 0.0))
		st.add_vertex(p2)
		st.set_uv(Vector2(u1, 1.0))
		st.add_vertex(p1)

		# Triángulo 2
		st.set_uv(Vector2(u1, 1.0))
		st.add_vertex(p1)
		st.set_uv(Vector2(u2, 0.0))
		st.add_vertex(p2)
		st.set_uv(Vector2(u2, 1.0))
		st.add_vertex(p3)

	return st.commit()

# ------------------------------------------------------------------------------
# IMPACTO CINEMÁTICO EN LA NAVE (Hit Spark, Chispas, Anillo - CERO contacto en el piso)
# ------------------------------------------------------------------------------
func _spawn_hit_impact_3d(hit_pos3d: Vector3) -> void:
	if not is_instance_valid(root_3d): return

	var impact_root = Node3D.new()
	impact_root.name = "Impact_" + str(Time.get_ticks_msec())
	impact_root.position = hit_pos3d
	root_3d.add_child(impact_root)

	# 1. Destello Billboard en el centro de la nave (mirando a la cámara)
	var flash_inst = MeshInstance3D.new()
	var qmesh = QuadMesh.new()
	qmesh.size = Vector2(2.0, 2.0)
	flash_inst.mesh = qmesh

	var fmat = StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fmat.albedo_texture = WHIP_SPARK_TEX
	fmat.albedo_color = Color(1.0, 0.92, 0.45, 1.0)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.5, 0.1)
	fmat.emission_energy_multiplier = 6.0
	flash_inst.material_override = fmat
	impact_root.add_child(flash_inst)

	# 2. Onda de choque anular expandiéndose en el aire alrededor de la nave
	var ring_inst = MeshInstance3D.new()
	var rmesh = TorusMesh.new()
	rmesh.inner_radius = 0.35
	rmesh.outer_radius = 0.50
	rmesh.rings = 16
	rmesh.ring_segments = 6
	ring_inst.mesh = rmesh

	var rmat = StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rmat.albedo_color = Color(1.0, 0.7, 0.2, 0.85)
	rmat.emission_enabled = true
	rmat.emission = Color(1.0, 0.35, 0.05)
	rmat.emission_energy_multiplier = 5.0
	ring_inst.material_override = rmat
	impact_root.add_child(ring_inst)

	# 3. Luz instantánea de golpe
	var hit_light = OmniLight3D.new()
	hit_light.light_color = Color(1.0, 0.65, 0.2)
	hit_light.light_energy = 8.0
	hit_light.omni_range = 4.0
	impact_root.add_child(hit_light)

	# Animación de estallido y disipación (0.32s)
	var tw = create_tween().set_parallel(true)
	tw.tween_property(flash_inst, "scale", Vector3.ONE * 1.6, 0.12)
	tw.tween_property(fmat, "albedo_color:a", 0.0, 0.32)
	tw.tween_property(fmat, "emission_energy_multiplier", 0.0, 0.32)
	tw.tween_property(ring_inst, "scale", Vector3(5.0, 0.6, 5.0), 0.32)
	tw.tween_property(rmat, "albedo_color:a", 0.0, 0.32)
	tw.tween_property(rmat, "emission_energy_multiplier", 0.0, 0.32)
	tw.tween_property(hit_light, "light_energy", 0.0, 0.25)

	tw.chain().tween_callback(impact_root.queue_free)

# ------------------------------------------------------------------------------
# FALLBACK 2D (Mapas sin SubViewport 3D)
# ------------------------------------------------------------------------------
func _spawn_whip_strike_2d(hit_idx: int) -> void:
	var from_2d = enemy_node.global_position if is_instance_valid(enemy_node) else _enemy_pos
	var to_2d = _target_node.global_position if is_instance_valid(_target_node) else _target_pos

	var line = Line2D.new()
	line.width = 32.0
	line.default_color = Color(1.0, 0.85, 0.3, 0.95)
	line.z_index = 25
	
	# Variación por golpe
	var side_sign = 1.0 if hit_idx % 2 == 0 else -1.0
	var dir = to_2d - from_2d
	var perp = Vector2(-dir.y, dir.x).normalized() * (dir.length() * 0.3 * side_sign)
	var mid = from_2d.lerp(to_2d, 0.5) + perp
	
	var pts := PackedVector2Array()
	var segs = 20
	for i in range(segs + 1):
		var u = float(i) / float(segs)
		var p = (1.0 - u) * (1.0 - u) * from_2d + 2.0 * (1.0 - u) * u * mid + u * u * to_2d
		pts.append(p)
	line.points = pts
	add_child(line)

	var tween = create_tween().set_parallel(true)
	tween.tween_property(line, "modulate:a", 0.0, 0.55)
	tween.tween_property(line, "width", 4.0, 0.55)
	await tween.finished
	if is_instance_valid(line):
		line.queue_free()

# ------------------------------------------------------------------------------
# PROCESO / ACTUALIZACIÓN CONTINUA DE CARGA
# ------------------------------------------------------------------------------
func _process(delta: float) -> void:
	if _is_charging:
		_charge_elapsed += delta
		if _is_3d:
			_update_charge_mesh()
		else:
			queue_redraw()

func _draw() -> void:
	if _is_3d: return
	if _is_charging:
		var from_2d = enemy_node.global_position if is_instance_valid(enemy_node) else _enemy_pos
		var to_2d = _target_node.global_position if is_instance_valid(_target_node) else _target_pos
		var pulse = 0.5 + 0.5 * sin(_charge_elapsed * 20.0)
		draw_line(from_2d - global_position, to_2d - global_position, Color(1.0, 0.4, 0.1, 0.3 + 0.3 * pulse), 2.0)

# ------------------------------------------------------------------------------
# FINALIZACIÓN Y LIMPIEZA
# ------------------------------------------------------------------------------
func finish() -> void:
	if _finishing: return
	_finishing = true
	_stop_charge_visual()
	# Margen de gracia de 0.65s para que la animación del último azote concluya en pantalla
	var tw = create_tween()
	tw.tween_interval(0.65)
	tw.finished.connect(func():
		_cleanup_all_3d()
		queue_free()
	)

func _cleanup_all_3d() -> void:
	_stop_charge_visual()
	if is_instance_valid(root_3d):
		root_3d.queue_free()
		root_3d = null

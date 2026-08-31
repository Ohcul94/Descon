extends Node2D
# MeleeSlashVisual.gd — Visual para Hachazo Melee 🪓 (melee_slash)
# FASE 1: anticipación (castTimeMs) — hacha se levanta, sin cargar área
# FASE 2: golpe instantáneo — arco o giro 360° que pega directo en el área (fireRange (px))

var slash_data: Dictionary = {}
var map_node: Node = null
var enemy_node: Node = null

var _elapsed := 0.0
var _phase := "charge"
var _cast_duration := 0.35 # Tiempo de Anticipación (ms) → s
var _angle := 0.0 # Ángulo central del arco (rad)
var _arc_angle := 120.0 # Ángulo del Arco (° grados)
var _arc_radius := 140.0 # Alcance del Golpe (px) = fireRange (px)
var _full_circle := false # ¿Giro Completo 360°? (bool)

var _arc_2d: Polygon2D = null
var _arc_outline: Line2D = null
var _haxe: Polygon2D = null

# 3D
var world_root_3d: Node3D = null
var _arc_3d: MeshInstance3D = null
var _arc_mat: StandardMaterial3D = null

func setup(p_data: Dictionary, p_map: Node, p_enemy: Node = null) -> void:
	slash_data = p_data
	map_node = p_map
	enemy_node = p_enemy
	_cast_duration = maxf(float(p_data.get("castTimeMs", 350.0)) / 1000.0, 0.05)
	_angle = float(p_data.get("angle", 0.0))
	_arc_angle = float(p_data.get("arcAngle", 120.0))
	# Compat: fuego usa fireRange (px) como radio; arcRadius legacy si existe
	_arc_radius = float(p_data.get("arcRadius", p_data.get("fireRange", 140.0)))
	if p_data.has("fireRange"):
		_arc_radius = float(p_data.get("fireRange", _arc_radius))
	_full_circle = bool(p_data.get("fullCircle", false))
	if _full_circle:
		_arc_angle = 360.0
	_phase = "charge"
	_elapsed = 0.0
	global_position = enemy_node.global_position if is_instance_valid(enemy_node) else Vector2(float(p_data.get("x",0)), float(p_data.get("y",0)))
	rotation = _angle
	_build_visuals()

func _build_visuals() -> void:
	# 2D arco charge (transparente al inicio)
	_arc_2d = Polygon2D.new()
	_arc_2d.color = Color(1.0, 0.2, 0.05, 0.12)
	_arc_2d.polygon = _make_arc_points(_arc_radius, _arc_angle, _full_circle)
	add_child(_arc_2d)
	_arc_outline = Line2D.new()
	_arc_outline.width = 3.0
	_arc_outline.default_color = Color(1.0, 0.35, 0.08, 0.55)
	_arc_outline.closed = _full_circle
	_arc_outline.points = _arc_outline_points(_arc_radius, _arc_angle, _full_circle)
	add_child(_arc_outline)
	# Hacha icono simple (triángulo)
	_haxe = Polygon2D.new()
	_haxe.polygon = PackedVector2Array([Vector2(0, -8), Vector2(18, 0), Vector2(0, 8), Vector2(-6, 0)])
	_haxe.color = Color(0.9, 0.9, 0.95, 0.9)
	_haxe.position = Vector2.ZERO
	add_child(_haxe)
	# 3D overlay
	_build_3d()

func _sample_height(p2d: Vector2) -> float:
	if not is_instance_valid(map_node) or not map_node.has_method("get_terrain_height_at_pos"):
		return 0.0
	var tn = map_node.get("terrain_node")
	if is_instance_valid(tn):
		var s = map_node.scale_factor if "scale_factor" in map_node else 0.02
		var cz = map_node.correction_z if "correction_z" in map_node else 1.41421356
		var pos3 = Vector3(p2d.x * s, 0.0, p2d.y * s * cz)
		if tn.has_method("get_height"):
			var h = tn.get_height(pos3)
			if not is_nan(h) and not is_inf(h):
				return h
		elif "data" in tn and is_instance_valid(tn.data) and tn.data.has_method("get_height"):
			var h2 = tn.data.get_height(pos3)
			if not is_nan(h2) and not is_inf(h2):
				return h2
	return map_node.get_terrain_height_at_pos(p2d)

func _make_arc_disc_conforming(center: Vector2, radius: float, angle_deg: float, rot: float, full: bool) -> ArrayMesh:
	var s_factor = map_node.scale_factor if "scale_factor" in map_node else 0.02
	var cz = map_node.correction_z if "correction_z" in map_node else 1.41421356
	var h_center = _sample_height(center)
	var eps = 0.45
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if full:
		var segs_ang = 32
		var segs_rad = 5
		for ri in range(segs_rad):
			var r1 = radius * (float(ri)/segs_rad)
			var r2 = radius * (float(ri+1)/segs_rad)
			for ai in range(segs_ang):
				var a1 = (float(ai)/segs_ang)*TAU
				var a2 = (float(ai+1)/segs_ang)*TAU
				var off_a1_r1 = Vector2(cos(a1), sin(a1))*r1
				var off_a2_r1 = Vector2(cos(a2), sin(a2))*r1
				var off_a1_r2 = Vector2(cos(a1), sin(a1))*r2
				var off_a2_r2 = Vector2(cos(a2), sin(a2))*r2
				var h_a1_r1 = _sample_height(center + off_a1_r1)
				var h_a2_r1 = _sample_height(center + off_a2_r1)
				var h_a1_r2 = _sample_height(center + off_a1_r2)
				var h_a2_r2 = _sample_height(center + off_a2_r2)
				var p_a1_r1 = Vector3(off_a1_r1.x*s_factor, (h_a1_r1 - h_center)+eps, off_a1_r1.y*s_factor*cz)
				var p_a2_r1 = Vector3(off_a2_r1.x*s_factor, (h_a2_r1 - h_center)+eps, off_a2_r1.y*s_factor*cz)
				var p_a1_r2 = Vector3(off_a1_r2.x*s_factor, (h_a1_r2 - h_center)+eps, off_a1_r2.y*s_factor*cz)
				var p_a2_r2 = Vector3(off_a2_r2.x*s_factor, (h_a2_r2 - h_center)+eps, off_a2_r2.y*s_factor*cz)
				if ri==0:
					st.set_normal(Vector3.UP); st.add_vertex(p_a1_r1)
					st.set_normal(Vector3.UP); st.add_vertex(p_a1_r2)
					st.set_normal(Vector3.UP); st.add_vertex(p_a2_r2)
				else:
					st.set_normal(Vector3.UP); st.add_vertex(p_a1_r1)
					st.set_normal(Vector3.UP); st.add_vertex(p_a2_r1)
					st.set_normal(Vector3.UP); st.add_vertex(p_a2_r2)
					st.set_normal(Vector3.UP); st.add_vertex(p_a1_r1)
					st.set_normal(Vector3.UP); st.add_vertex(p_a2_r2)
					st.set_normal(Vector3.UP); st.add_vertex(p_a1_r2)
	else:
		var half = deg_to_rad(angle_deg*0.5)
		var segs_ang = 22
		var segs_rad = 5
		for ri in range(segs_rad):
			var r1 = radius * (float(ri)/segs_rad)
			var r2 = radius * (float(ri+1)/segs_rad)
			for ai in range(segs_ang):
				var a1 = -half + (float(ai)/segs_ang)*(half*2)
				var a2 = -half + (float(ai+1)/segs_ang)*(half*2)
				var off_a1_r1 = Vector2(sin(a1)*r1, -cos(a1)*r1).rotated(rot)
				var off_a2_r1 = Vector2(sin(a2)*r1, -cos(a2)*r1).rotated(rot)
				var off_a1_r2 = Vector2(sin(a1)*r2, -cos(a1)*r2).rotated(rot)
				var off_a2_r2 = Vector2(sin(a2)*r2, -cos(a2)*r2).rotated(rot)
				var h_a1_r1 = _sample_height(center + off_a1_r1)
				var h_a2_r1 = _sample_height(center + off_a2_r1)
				var h_a1_r2 = _sample_height(center + off_a1_r2)
				var h_a2_r2 = _sample_height(center + off_a2_r2)
				var p_a1_r1 = Vector3(off_a1_r1.x*s_factor, (h_a1_r1 - h_center)+eps, off_a1_r1.y*s_factor*cz)
				var p_a2_r1 = Vector3(off_a2_r1.x*s_factor, (h_a2_r1 - h_center)+eps, off_a2_r1.y*s_factor*cz)
				var p_a1_r2 = Vector3(off_a1_r2.x*s_factor, (h_a1_r2 - h_center)+eps, off_a1_r2.y*s_factor*cz)
				var p_a2_r2 = Vector3(off_a2_r2.x*s_factor, (h_a2_r2 - h_center)+eps, off_a2_r2.y*s_factor*cz)
				if ri==0:
					var p0 = Vector3(0, eps, 0)
					st.set_normal(Vector3.UP); st.add_vertex(p0)
					st.set_normal(Vector3.UP); st.add_vertex(p_a1_r2)
					st.set_normal(Vector3.UP); st.add_vertex(p_a2_r2)
				else:
					st.set_normal(Vector3.UP); st.add_vertex(p_a1_r1)
					st.set_normal(Vector3.UP); st.add_vertex(p_a2_r1)
					st.set_normal(Vector3.UP); st.add_vertex(p_a2_r2)
					st.set_normal(Vector3.UP); st.add_vertex(p_a1_r1)
					st.set_normal(Vector3.UP); st.add_vertex(p_a2_r2)
					st.set_normal(Vector3.UP); st.add_vertex(p_a1_r2)
	return st.commit()

func _build_3d() -> void:
	if not is_instance_valid(map_node) or not map_node.get("sub_viewport"):
		return
	world_root_3d = Node3D.new()
	world_root_3d.name = "MeleeSlash3D_" + str(get_instance_id())
	map_node.sub_viewport.add_child(world_root_3d)
	_arc_3d = MeshInstance3D.new()
	# Usar disco conformante si hay terreno
	var has_terrain = is_instance_valid(map_node.get("terrain_node"))
	if has_terrain:
		var center = global_position
		var mesh_c = _make_arc_disc_conforming(center, _arc_radius, _arc_angle, rotation, _full_circle)
		_arc_3d.mesh = mesh_c
		# Elevar root al terreno
		var h = _sample_height(center)
		world_root_3d.position.y = h - 1.0 + 0.0 # base_y 1.0
	else:
		var s_factor := 0.02
		if "scale_factor" in map_node:
			s_factor = map_node.scale_factor
		var cyl := CylinderMesh.new()
		cyl.top_radius = _arc_radius * s_factor
		cyl.bottom_radius = _arc_radius * s_factor
		cyl.height = 0.02
		_arc_3d.mesh = cyl
	_arc_mat = StandardMaterial3D.new()
	_arc_mat.albedo_color = Color(1.0, 0.15, 0.02, 0.18)
	_arc_mat.emission_enabled = true
	_arc_mat.emission = Color(1.0, 0.2, 0.05)
	_arc_mat.emission_energy_multiplier = 1.0
	_arc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_arc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_arc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arc_mat.no_depth_test = true
	_arc_mat.render_priority = 2
	_arc_3d.material_override = _arc_mat
	world_root_3d.add_child(_arc_3d)
	# Guardar para reconstrucción si cambia rotación/posición significativamente
	world_root_3d.set_meta("last_center", global_position)
	world_root_3d.set_meta("last_rot", rotation)
	tree_exiting.connect(func():
		if is_instance_valid(world_root_3d):
			world_root_3d.queue_free()
	)

func _make_arc_points(radius: float, angle_deg: float, full: bool) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(Vector2.ZERO)
	if full:
		var steps := 32
		for i in range(steps+1):
			var a := (float(i)/steps) * TAU - PI
			pts.append(Vector2(cos(a), sin(a)) * radius)
	else:
		var half := deg_to_rad(angle_deg * 0.5)
		var steps := 18
		for i in range(steps+1):
			var a := lerpf(-half, half, float(i)/steps)
			pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts

func _arc_outline_points(radius: float, angle_deg: float, full: bool) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if full:
		var steps := 32
		for i in range(steps+1):
			var a := (float(i)/steps) * TAU
			pts.append(Vector2(cos(a), sin(a)) * radius)
	else:
		var half := deg_to_rad(angle_deg * 0.5)
		var steps := 18
		for i in range(steps+1):
			var a := lerpf(-half, half, float(i)/steps)
			pts.append(Vector2(cos(a), sin(a)) * radius)
		pts.append(Vector2.ZERO)
	return pts

func _process(delta: float) -> void:
	_elapsed += delta
	if is_instance_valid(enemy_node):
		global_position = enemy_node.global_position
		if _phase == "charge" and not _full_circle:
			rotation = enemy_node.rotation - PI/2.0
			_angle = rotation
	_sync_3d()
	if _phase == "charge":
		var prog := clampf(_elapsed / _cast_duration, 0.0, 1.0)
		# Solo levanta el hacha, no crece el área (pega directo al terminar)
		if is_instance_valid(_arc_2d):
			_arc_2d.color.a = lerpf(0.08, 0.22, prog) # leve, no invasivo
		if is_instance_valid(_arc_outline):
			_arc_outline.default_color.a = lerpf(0.3, 0.65, prog)
		if is_instance_valid(_haxe):
			_haxe.rotation = lerpf(-0.9, 0.0, prog)
			_haxe.scale = Vector2.ONE * lerpf(0.7, 1.0, prog)
		if is_instance_valid(_arc_mat):
			_arc_mat.emission_energy_multiplier = lerpf(0.6, 2.2, prog)
		if _elapsed >= _cast_duration:
			_trigger_slash()
			_phase = "slash"
			_elapsed = 0.0
	elif _phase == "slash":
		# Flash instantáneo del arco (no dura activeMs, es golpe directo)
		var prog := clampf(_elapsed / 0.18, 0.0, 1.0)
		if is_instance_valid(_arc_2d):
			_arc_2d.color = Color(1.0, 0.85, 0.2, lerpf(0.55, 0.0, prog))
		if is_instance_valid(_arc_outline):
			_arc_outline.default_color.a = lerpf(0.95, 0.0, prog)
			_arc_outline.width = lerpf(5.0, 1.0, prog)
		if is_instance_valid(_haxe):
			_haxe.rotation = lerpf(0.0, 1.2, prog)
		if is_instance_valid(_arc_mat):
			_arc_mat.emission_energy_multiplier = lerpf(5.0, 0.0, prog)
			_arc_mat.albedo_color.a = lerpf(0.4, 0.0, prog)
		if _elapsed >= 0.18:
			_finish()

func _trigger_slash() -> void:
	# Efecto de corte: partículas/ondas
	var burst := CPUParticles2D.new()
	burst.amount = 18
	burst.lifetime = 0.35
	burst.one_shot = true
	burst.explosiveness = 0.9
	burst.spread = _arc_angle if not _full_circle else 360.0
	burst.direction = Vector2.RIGHT.rotated(_angle) if not _full_circle else Vector2.RIGHT
	burst.gravity = Vector2.ZERO
	burst.initial_velocity_min = 120.0
	burst.initial_velocity_max = 260.0
	burst.scale_amount_min = 2.0
	burst.scale_amount_max = 5.0
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.9, 0.4, 0.9))
	grad.add_point(0.4, Color(1.0, 0.3, 0.05, 0.7))
	grad.set_color(1, Color(0.0,0.0,0.0,0.0))
	burst.color_ramp = grad
	burst.global_position = global_position
	get_parent().add_child(burst)
	burst.emitting = true
	get_tree().create_timer(0.4).timeout.connect(burst.queue_free)
	
	# v690.4: Detectar y aplicar VFX de impacto a los jugadores en el rango/arco del hachazo
	var target_players = []
	var pl = get_tree().get_first_node_in_group("player")
	if is_instance_valid(pl) and not pl.is_dead:
		target_players.append(pl)
	var entities = get_tree().get_nodes_in_group("entities")
	for ent in entities:
		if is_instance_valid(ent) and ent.is_in_group("remote_players") and ent.get("is_dead") != true:
			target_players.append(ent)
			
	for p in target_players:
		var dist = global_position.distance_to(p.global_position)
		if dist <= _arc_radius:
			var hit_angle = (p.global_position - global_position).angle()
			var in_angle = true
			if not _full_circle:
				var diff = abs(angle_difference(_angle, hit_angle))
				if diff > deg_to_rad(_arc_angle * 0.5):
					in_angle = false
			if in_angle:
				_spawn_hit_vfx(p)

	# Cámara shake leve si es local player cerca
	if is_instance_valid(enemy_node) and is_instance_valid(map_node):
		var local_pl = get_tree().get_first_node_in_group("player")
		if is_instance_valid(local_pl) and global_position.distance_to(local_pl.global_position) < _arc_radius + 80.0:
			if local_pl.has_method("apply_shake"):
				local_pl.apply_shake(0.6)

func _spawn_hit_vfx(target: Node2D) -> void:
	if not is_instance_valid(target) or not is_instance_valid(target.get("world_root_3d")):
		return
		
	var target_3d = target.world_root_3d

	# 1. Partículas 3D (CPUParticles3D) sobre el jugador
	var particles_3d = CPUParticles3D.new()
	particles_3d.name = "MeleeHitParticles3D_" + str(get_instance_id())
	particles_3d.amount = 18
	particles_3d.lifetime = 0.35
	particles_3d.one_shot = true
	particles_3d.explosiveness = 1.0
	particles_3d.spread = 80.0
	particles_3d.gravity = Vector3(0, -3.0, 0)
	particles_3d.initial_velocity_min = 4.0
	particles_3d.initial_velocity_max = 8.0
	
	var pm = BoxMesh.new()
	pm.size = Vector3(0.09, 0.09, 0.09)
	particles_3d.mesh = pm
	
	var p_mat = StandardMaterial3D.new()
	p_mat.albedo_color = Color(1.0, 0.2, 0.05)
	p_mat.emission_enabled = true
	p_mat.emission = Color(1.0, 0.35, 0.0)
	p_mat.emission_energy_multiplier = 5.0
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particles_3d.material_override = p_mat
	
	# Posición del emisor a la altura de la nave
	particles_3d.position = Vector3(0, 0.5, 0)
	target_3d.add_child(particles_3d)
	particles_3d.emitting = true
	
	# 2. Tajo 3D (Corte tridimensional de energía)
	var slash_mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(2.2, 0.18, 0.02)
	slash_mesh.mesh = box
	
	var s_mat = StandardMaterial3D.new()
	s_mat.albedo_color = Color(1.0, 0.95, 0.7, 0.95)
	s_mat.emission_enabled = true
	s_mat.emission = Color(1.0, 0.3, 0.0)
	s_mat.emission_energy_multiplier = 7.0
	s_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	s_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	slash_mesh.material_override = s_mat
	
	slash_mesh.position = Vector3(0, 0.6, 0)
	slash_mesh.rotation = Vector3(randf_range(-0.4, 0.4), randf_range(0.0, TAU), randf_range(-0.4, 0.4))
	target_3d.add_child(slash_mesh)
	
	var tw = slash_mesh.create_tween().set_parallel(true)
	tw.tween_property(slash_mesh, "scale", Vector3(1.4, 0.0, 1.4), 0.16)
	tw.tween_property(s_mat, "albedo_color:a", 0.0, 0.16)
	tw.tween_property(s_mat, "emission_energy_multiplier", 0.0, 0.16)
	
	# Limpieza programada de los nodos 3D
	var clean_tw = create_tween()
	clean_tw.tween_interval(0.4)
	clean_tw.tween_callback(func():
		if is_instance_valid(particles_3d): particles_3d.queue_free()
		if is_instance_valid(slash_mesh): slash_mesh.queue_free()
	)

func _sync_3d() -> void:
	if not is_instance_valid(world_root_3d) or not is_instance_valid(map_node):
		return
	var s_factor := 0.02
	var correction_z := 1.41421356
	if "scale_factor" in map_node:
		s_factor = map_node.scale_factor
	if "correction_z" in map_node:
		correction_z = map_node.correction_z
	# Altura real del terreno, no la del modelo del enemigo
	var y_3d := 1.0
	if is_instance_valid(map_node) and map_node.has_method("get_terrain_height_at_pos"):
		y_3d = _sample_height(global_position)
	else:
		if is_instance_valid(enemy_node) and is_instance_valid(enemy_node.get("world_root_3d")):
			y_3d = enemy_node.world_root_3d.position.y
	world_root_3d.position = Vector3(global_position.x * s_factor, y_3d + 0.05, global_position.y * s_factor * correction_z)
	world_root_3d.rotation.y = -rotation - PI/2.0
	# Regeneración suave para homing/movimiento: umbral bajo para que no se note salto
	if world_root_3d.has_meta("last_center"):
		var last_c = world_root_3d.get_meta("last_center") as Vector2
		var last_r = world_root_3d.get_meta("last_rot") as float
		if global_position.distance_to(last_c) > 5.0 or abs(angle_difference(last_r, rotation)) > deg_to_rad(1.5):
			if is_instance_valid(_arc_3d):
				var new_mesh = _make_arc_disc_conforming(global_position, _arc_radius, _arc_angle, rotation, _full_circle)
				_arc_3d.mesh = new_mesh
			world_root_3d.set_meta("last_center", global_position)
			world_root_3d.set_meta("last_rot", rotation)
	# Lerp suave de altura aunque no regenere (evita saltos en loma)
	var h_tgt = _sample_height(global_position)
	var cur_y = world_root_3d.position.y
	var tgt_y = h_tgt - 1.0 + 0.05
	var d = get_process_delta_time()
	world_root_3d.position.y = lerp(cur_y, tgt_y, clamp(d*12.0, 0.0, 1.0))

func _finish() -> void:
	if is_instance_valid(world_root_3d):
		world_root_3d.queue_free()
	queue_free()

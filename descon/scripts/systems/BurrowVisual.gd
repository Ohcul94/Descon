extends Node2D
# v400.60: Visual de Zambullida Telúrica (BURROW)
# Fases: dive (hundimiento) -> travel (grieta que avanza) -> emerge (rompimiento + círculo)
# El nodo se queda pegado al enemigo (oculto) durante el viaje y dibuja la grieta bajo sus pies.

var enemy_node = null
var map_node = null
var radius: float = 250.0
var burst_mode: String = "burst"
var _phase: String = "dive"
var _phase_start: float = 0.0
var _dive_duration: float = 1.0
var _start_pos: Vector2 = Vector2.ZERO
var _target_pos: Vector2 = Vector2.ZERO
var _crack_trail: PackedVector2Array = PackedVector2Array()
var _trail_max: int = 40
var _zone_active: bool = false
var _warn_duration: float = 1.5
var _life_elapsed: float = 0.0
var _seed_value: int = 0
var _last_crack_step: float = 0.0
var _is_3d: bool = false
var _ground_3d: Node3D = null

const CRACK_COLOR := Color(0.25, 0.16, 0.08, 0.9)
const ZONE_COLOR := Color(0.6, 0.32, 0.12, 0.28)

func setup(data: Dictionary, p_map, p_enemy) -> void:
	map_node = p_map
	enemy_node = p_enemy
	radius = float(data.get("radius", 250.0))
	burst_mode = str(data.get("burstMode", "burst"))
	_is_3d = is_instance_valid(map_node) and map_node.get("sub_viewport") != null
	_seed_value = randi()
	_phase_start = Time.get_ticks_msec() / 1000.0

	var dur_ms = float(data.get("duration", 1000.0))
	_dive_duration = max(dur_ms / 1000.0, 0.2)
	_phase = "dive"
	_start_pos = global_position

func launch_travel(data: Dictionary) -> void:
	# El enemigo ya está oculto; la grieta avanza desde el punto de inmersión
	_phase = "travel"
	_phase_start = Time.get_ticks_msec() / 1000.0
	_target_pos = Vector2(float(data.get("targetX", global_position.x)), float(data.get("targetY", global_position.y)))
	_crack_trail = PackedVector2Array([global_position])
	_last_crack_step = _phase_start

func warn_now(data: Dictionary) -> void:
	# Aviso: el enemigo sigue oculto bajo tierra; solo se dibuja el círculo de peligro estático
	_phase = "warn"
	_phase_start = Time.get_ticks_msec() / 1000.0
	radius = float(data.get("radius", radius))
	burst_mode = str(data.get("burstMode", burst_mode))
	global_position = Vector2(float(data.get("x", global_position.x)), float(data.get("y", global_position.y)))
	_warn_duration = float(data.get("warns", 1500.0)) / 1000.0
	_spawn_ground_area(data)
	queue_redraw()

func burst_now(data: Dictionary) -> void:
	# Emergencia: rompimiento del suelo + círculo de daño (burst) o zona persistente (zone)
	_phase = "emerge"
	_phase_start = Time.get_ticks_msec() / 1000.0
	radius = float(data.get("radius", radius))
	burst_mode = str(data.get("burstMode", burst_mode))
	var dur_s = float(data.get("zoneDuration", 3000.0)) / 1000.0
	_zone_active = burst_mode == "zone"

	# v400.0: Área dibujada en el PISO (3D) con el radio EXACTO en px configurado en AdminDash.
	# Igual patrón que ice_storm_deploy: disco + anillo en el sub_viewport escalados por scale_factor.
	# Si ya fue creado durante el aviso (warn_now), se reutiliza y solo se actualiza el color.
	if not (is_instance_valid(_ground_3d) and is_instance_valid(_ground_3d.get_parent())):
		_spawn_ground_area(data)

	if burst_mode == "burst":
		var tw = create_tween()
		tw.tween_interval(0.45)
		tw.tween_property(self, "modulate:a", 0.0, 0.35)
		tw.finished.connect(queue_free)
	else:
		var tw = create_tween()
		tw.tween_interval(dur_s)
		tw.tween_property(self, "modulate:a", 0.0, 0.5)
		tw.finished.connect(queue_free)
	queue_redraw()

func _spawn_ground_area(data: Dictionary) -> void:
	if not _is_3d or not is_instance_valid(map_node):
		return
	var s_factor: float = map_node.scale_factor if "scale_factor" in map_node else 0.02
	var correction_z: float = map_node.correction_z if "correction_z" in map_node else 1.41421356
	var vp = map_node.sub_viewport
	if not is_instance_valid(vp):
		return

	# Posición lógica de la emergencia (fallback a la posición actual del nodo)
	var e_x := float(data.get("x", global_position.x))
	var e_y := float(data.get("y", global_position.y))
	var r3d: float = radius * s_factor

	# Elevar al terreno real para no quedar enterrado
	var _h = 0.0
	if map_node and map_node.has_method("get_terrain_height_at_pos"):
		_h = map_node.get_terrain_height_at_pos(Vector2(e_x, e_y))
		var _tn = map_node.get("terrain_node")
		if is_instance_valid(_tn):
			var _pos3 = Vector3(e_x * map_node.scale_factor, 0.0, e_y * map_node.scale_factor * map_node.correction_z)
			if _tn.has_method("get_height"):
				var _hh = _tn.get_height(_pos3)
				if not is_nan(_hh) and not is_inf(_hh):
					_h = _hh
			elif "data" in _tn and is_instance_valid(_tn.data) and _tn.data.has_method("get_height"):
				var _hh2 = _tn.data.get_height(_pos3)
				if not is_nan(_hh2) and not is_inf(_hh2):
					_h = _hh2
	_ground_3d = Node3D.new()
	_ground_3d.name = "BurrowGround_" + name
	_ground_3d.position = Vector3(e_x * s_factor, _h + 0.05, e_y * s_factor * correction_z)
	vp.add_child(_ground_3d)

	# Disco conformante al relieve
	var disc := MeshInstance3D.new()
	var disc_mesh: Mesh = CylinderMesh.new()
	# Intentar disco conformante denso si hay terreno
	var _map_b = map_node
	if is_instance_valid(_map_b) and is_instance_valid(_map_b.get("terrain_node")):
		var _em = get_tree().get_first_node_in_group("world_node")
		if _em and _em.has_node("EntityManager"):
			var _mgr = _em.get_node("EntityManager")
			if _mgr and _mgr.has_method("_make_circle_disc_conforming"):
				disc_mesh = _mgr._make_circle_disc_conforming(Vector2(e_x, e_y), radius, _map_b)
			else:
				var _tmp = CylinderMesh.new()
				_tmp.top_radius = r3d
				_tmp.bottom_radius = r3d
				_tmp.height = 0.01
				disc_mesh = _tmp
		else:
			# fallback denso local
			var _cyl = CylinderMesh.new()
			_cyl.top_radius = r3d
			_cyl.bottom_radius = r3d
			_cyl.height = 0.01
			disc_mesh = _cyl
	else:
		var _cyl = CylinderMesh.new()
		_cyl.top_radius = r3d
		_cyl.bottom_radius = r3d
		_cyl.height = 0.01
		disc_mesh = _cyl
	disc.mesh = disc_mesh
	var disc_mat := StandardMaterial3D.new()
	if burst_mode == "zone":
		disc_mat.albedo_color = Color(0.6, 0.3, 0.1, 0.22)
		disc_mat.emission_enabled = true
		disc_mat.emission = Color(0.7, 0.35, 0.1)
		disc_mat.emission_energy_multiplier = 0.8
	else:
		disc_mat.albedo_color = Color(0.6, 0.32, 0.12, 0.35)
		disc_mat.emission_enabled = true
		disc_mat.emission = Color(0.8, 0.45, 0.12)
		disc_mat.emission_energy_multiplier = 1.2
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc_mat.no_depth_test = true
	disc_mat.render_priority = 2
	disc.material_override = disc_mat
	_ground_3d.add_child(disc)

	# Anillo exterior brillante
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = r3d * 0.97
	ring_mesh.outer_radius = r3d
	ring.mesh = ring_mesh
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.85, 0.45, 0.1, 0.7)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.9, 0.5, 0.12)
	ring_mat.emission_energy_multiplier = 2.0
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.no_depth_test = true
	ring_mat.render_priority = 2
	ring.material_override = ring_mat
	ring.position.y = 0.06
	_ground_3d.add_child(ring)

func float_node(v) -> float:
	return float(v)

func _exit_tree() -> void:
	if is_instance_valid(_ground_3d) and is_instance_valid(_ground_3d.get_parent()):
		_ground_3d.queue_free()
	_ground_3d = null

func end_zone() -> void:
	_zone_active = false

func _process(delta: float) -> void:
	_life_elapsed += delta
	var now = Time.get_ticks_msec() / 1000.0

	if _phase == "dive":
		# Seguir al enemigo mientras se hunde
		if is_instance_valid(enemy_node):
			global_position = enemy_node.global_position
		var p = clamp((now - _phase_start) / _dive_duration, 0.0, 1.0)
		if p >= 1.0:
			_phase = "travel"
			_crack_trail = PackedVector2Array([global_position])
			_last_crack_step = now
	elif _phase == "travel":
		if is_instance_valid(enemy_node):
			global_position = enemy_node.global_position
		# Rastro de grieta irregular: agregar punto con jitter cuando el enemigo avanza
		if _crack_trail.size() == 0 or global_position.distance_to(_crack_trail[_crack_trail.size() - 1]) > 14.0:
			var dir = Vector2.RIGHT.rotated(randf() * TAU)
			var jit = dir * randf_range(2.0, 9.0)
			_crack_trail.append(global_position + jit)
			if _crack_trail.size() > _trail_max:
				_crack_trail.remove_at(0)
		if _life_elapsed > 0.07:
			_life_elapsed = 0.0
			_spawn_dirt(global_position, 1.0)
	elif _phase == "warn":
		queue_redraw()
	elif _phase == "emerge":
		queue_redraw()

	queue_redraw()

func _spawn_dirt(pos: Vector2, amount: float) -> void:
	var em = Node2D.new()
	em.z_index = 7
	em.position = pos - global_position
	add_child(em)
	var t = create_tween()
	t.tween_interval(0.9)
	t.finished.connect(em.queue_free)
	for i in int(amount * 8):
		var particle = Node2D.new()
		particle.modulate = Color(0.45, 0.3, 0.15, 1)
		em.add_child(particle)
		var sp = randf_range(40, 130)
		var dir = Vector2.RIGHT.rotated(randf() * TAU)
		var tw = create_tween()
		tw.tween_property(particle, "position", dir * sp, 0.5)
		tw.parallel().tween_property(particle, "modulate:a", 0.0, 0.5)
		tw.finished.connect(particle.queue_free)

func _draw() -> void:
	if _phase == "dive":
		# Grietas radiales creciendo mientras se hunde
		var p = clamp((_life_elapsed / _dive_duration), 0.0, 1.0)
		_draw_radial_cracks(Vector2.ZERO, 20.0 + p * 70.0, 5)
	elif _phase == "travel":
		# Línea de grieta que avanza
		if _crack_trail.size() >= 2:
			draw_polyline(_crack_trail, CRACK_COLOR, 5.0, true)
		draw_arc(Vector2.ZERO, 8.0, 0, TAU, 10, CRACK_COLOR, 3.0, true)
	elif _phase == "warn":
		# Círculo de peligro pulsante mientras el enemigo está oculto
		var pulse = 0.5 + 0.5 * sin(_life_elapsed * 9.0)
		draw_circle(Vector2.ZERO, radius, Color(0.9, 0.3, 0.1, 0.12 + 0.10 * pulse))
		draw_arc(Vector2.ZERO, radius, 0, TAU, 64, Color(0.95, 0.4, 0.12, 0.65 + 0.3 * pulse), 5.0, true)
		draw_arc(Vector2.ZERO, radius * 0.65, 0, TAU, 48, Color(0.95, 0.45, 0.15, 0.4 + 0.3 * pulse), 3.0, true)
	elif _phase == "emerge":
		# Rompimiento: círculo agrietado en el suelo
		_draw_radial_cracks(Vector2.ZERO, radius, 10)
		if _zone_active:
			draw_circle(Vector2.ZERO, radius, ZONE_COLOR)
			var pulse = 0.6 + 0.4 * sin(_life_elapsed * 6.0)
			draw_arc(Vector2.ZERO, radius, 0, TAU, 64, Color(0.9, 0.5, 0.15, pulse), 6.0, true)
			draw_arc(Vector2.ZERO, radius * 0.7, 0, TAU, 48, Color(0.9, 0.5, 0.15, pulse * 0.5), 3.0, true)
		else:
			draw_arc(Vector2.ZERO, radius, 0, TAU, 64, Color(0.85, 0.45, 0.1, 0.9), 8.0, true)
			draw_arc(Vector2.ZERO, radius * 0.6, 0, TAU, 48, Color(0.85, 0.45, 0.1, 0.6), 4.0, true)

func _draw_radial_cracks(center: Vector2, r: float, count: int) -> void:
	for i in range(count):
		var a := (TAU / count) * i + randf() * 0.4
		var crack_len := r * randf_range(0.7, 1.0)
		var p1 := center + Vector2.RIGHT.rotated(a) * crack_len
		var p2 := center + Vector2.RIGHT.rotated(a + 0.18) * (crack_len * 0.55)
		var p3 := center + Vector2.RIGHT.rotated(a + 0.32) * (crack_len * 0.3)
		draw_line(center, p1, CRACK_COLOR, 3.0, true)
		draw_line(p1 * 0.35, p2, CRACK_COLOR, 2.0, true)
		draw_line(p2 * 0.6, p3, CRACK_COLOR, 1.5, true)

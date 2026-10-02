extends Node2D
# EnraizadaVisual.gd (v902.0 - Mecánica "Enraizada")
# VFX 100% procedural (sin escenas ni assets externos) de raíces que brotan del piso
# y abrazan a la(s) nave(s).
#
# Fases:
#   1. AVISO   (enraizada_start): aro/tanque de tierra pulsante en el suelo durante castTimeMs.
#   2. BROTES  (enraizada_end)  : N racimos de raíces que se retuercen hacia arriba en cada
#                                 posición atrapada, se mantienen "duration" ms y se disuelven.
#
# Soporta mapas 3D (SubViewport, raíces como cintas verticales) y fallback 2D puro.

var map_node: Node = null
var radius: float = 140.0
var duration: float = 4.0
var cast_time: float = 0.0

var _is_3d := false
var _sf := 0.02
var _cz := 1.41421356

var _elapsed := 0.0
var _phase := "warn"      # "warn" -> "burst" -> "fade"
var _warn_elapsed := 0.0
var _warn_pts: Array[Vector2] = [] # Posiciones (mundo 2D) donde se telegrafia el atrapamiento
var _burst_root: Node3D = null
var _racimos: Array = []  # [{pos, seed, host, roots3d, line2d, tip_off}]
var _freed := false

var _enemy_pos := Vector2.ZERO

# ------------------------------------------------------------------------------
# SETUP
# ------------------------------------------------------------------------------
func setup(p_data: Dictionary, p_map: Node) -> void:
	map_node = p_map
	radius = maxf(20.0, float(p_data.get("radius", 140.0)))
	duration = maxf(0.5, float(p_data.get("duration", 4000.0)) / 1000.0)
	cast_time = maxf(0.0, float(p_data.get("castTimeMs", 0.0)) / 1000.0)
	_enemy_pos = Vector2(float(p_data.get("x", 0.0)), float(p_data.get("y", 0.0)))

	# Nodo top-level: todas las coordenadas se dibujan relativas a la posición del enemigo
	global_position = _enemy_pos

	# Posiciones de telegrafo: los targets elegidos (fallback: el enemigo)
	_warn_pts.clear()
	var tg: Array = p_data.get("targets", [])
	for t in tg:
		_warn_pts.append(Vector2(float(t.get("x", _enemy_pos.x)), float(t.get("y", _enemy_pos.y))))
	if _warn_pts.is_empty():
		_warn_pts.append(_enemy_pos)

	_check_3d()

	if cast_time <= 0.0:
		_enter_burst(p_data)
	else:
		_phase = "warn"
		_warn_elapsed = 0.0
		if _is_3d:
			_build_warn_3d()

	# Autoliberación de seguridad
	var max_life := cast_time + duration + 3.0
	var tw := create_tween()
	tw.tween_interval(max_life)
	tw.finished.connect(_force_free)

func _check_3d() -> void:
	var map: Node = map_node if is_instance_valid(map_node) else get_tree().get_first_node_in_group("map")
	map_node = map
	_is_3d = is_instance_valid(map) and map.get("sub_viewport") != null and is_instance_valid(map.sub_viewport)
	if _is_3d:
		_sf = map.scale_factor if "scale_factor" in map else 0.02
		_cz = map.correction_z if "correction_z" in map else 1.41421356

func _p2d_to_3d(p2d: Vector2, h: float) -> Vector3:
	return Vector3(p2d.x * _sf, h, p2d.y * _sf * _cz)

func _terrain_h(p2d: Vector2, off: float = 0.06) -> float:
	if not is_instance_valid(map_node): return off
	var em_n = get_tree().get_first_node_in_group("world_node")
	if em_n and em_n.has_node("EntityManager"):
		var mgr = em_n.get_node("EntityManager")
		if mgr and mgr.has_method("_sample_terrain_height"):
			return mgr._sample_terrain_height(p2d, map_node) + off
	if map_node.has_method("get_terrain_height_at_pos"):
		return map_node.get_terrain_height_at_pos(p2d) + off
	return off

# ------------------------------------------------------------------------------
# FASE 1: AVISO (tierra agrietada pulsante)
# ------------------------------------------------------------------------------
func _build_warn_3d() -> void:
	if not _is_3d or not is_instance_valid(map_node): return
	var vp: Node = map_node.sub_viewport
	if not is_instance_valid(vp): return

	_burst_root = Node3D.new()
	_burst_root.name = "EnraizadaWarn_" + name
	_burst_root.position = _p2d_to_3d(_enemy_pos, _terrain_h(_enemy_pos))
	vp.add_child(_burst_root)

	var h_base := _terrain_h(_enemy_pos)
	for pt in _warn_pts:
		var h_pt := _terrain_h(pt)
		var off := Vector3(
			(pt.x - _enemy_pos.x) * _sf,
			h_pt - h_base,
			(pt.y - _enemy_pos.y) * _sf * _cz
		)
		var zone := Node3D.new()
		zone.name = "WarnZone"
		zone.position = off
		_burst_root.add_child(zone)
		zone.add_child(_make_warn_disc())
		zone.add_child(_make_warn_ring())

func _make_warn_disc() -> MeshInstance3D:
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = radius * _sf
	dm.bottom_radius = radius * _sf
	dm.height = 0.01
	disc.mesh = dm
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.24, 0.15, 0.06, 0.45)
	dmat.emission_enabled = true
	dmat.emission = Color(0.35, 0.55, 0.12)
	dmat.emission_energy_multiplier = 0.6
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.no_depth_test = true
	disc.material_override = dmat
	return disc

func _make_warn_ring() -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius * _sf * 0.92
	tm.outer_radius = radius * _sf
	tm.rings = 40
	tm.ring_segments = 5
	ring.mesh = tm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.55, 0.85, 0.25, 0.85)
	rmat.emission_enabled = true
	rmat.emission = Color(0.45, 0.9, 0.2)
	rmat.emission_energy_multiplier = 3.0
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.no_depth_test = true
	ring.material_override = rmat
	return ring

# ------------------------------------------------------------------------------
# FASE 2: BROTES
# ------------------------------------------------------------------------------
# API pública: llamada desde BossActionHandler en "enraizada_end"
func trigger_burst(p_data: Dictionary) -> void:
	_enter_burst(p_data)

func _enter_burst(p_data: Dictionary) -> void:
	# Reentra siempre: libera los racimos previos (aviso-brotes de respaldo) y
	# reconstruye con las posiciones reales de "enraizada_end". Sin duplicados.
	_phase = "burst"
	_elapsed = 0.0

	# El evento de fin trae la duración real del root
	if p_data.has("duration"):
		duration = maxf(0.5, float(p_data["duration"]) / 1000.0)
	if p_data.has("radius"):
		radius = maxf(20.0, float(p_data["radius"]))

	_free_racimos()
	if is_instance_valid(_burst_root):
		_burst_root.queue_free()
		_burst_root = null

	# Seguridad: autoliberación tras el tiempo de vida de los brotes
	var tw := create_tween()
	tw.tween_interval(duration + 2.0)
	tw.finished.connect(_force_free)

	var trapped: Array = p_data.get("trapped", [])
	if trapped.size() == 0:
		# Resiliencia: si no llegaron posiciones, brota en el centro del aviso
		trapped = [{ "x": _enemy_pos.x, "y": _enemy_pos.y }]

	for t in trapped:
		var p2 := Vector2(float(t.get("x", _enemy_pos.x)), float(t.get("y", _enemy_pos.y)))
		_spawn_racimo(p2, randi())

	# Limpieza del aviso 2D
	queue_redraw()

func _free_racimos() -> void:
	for r in _racimos:
		if r.has("host") and is_instance_valid(r["host"]):
			r["host"].queue_free()
		if r.has("line2d") and is_instance_valid(r["line2d"]):
			r["line2d"].queue_free()
	_racimos.clear()

func _spawn_racimo(p2: Vector2, p_seed: int) -> void:
	var racimo := {
		"pos": p2,
		"seed": p_seed,
		"t": 0.0,
		"roots3d": [],
		"line2d": null
	}
	if _is_3d and is_instance_valid(map_node) and is_instance_valid(map_node.sub_viewport):
		var host := Node3D.new()
		host.name = "RootRacimo"
		host.position = _p2d_to_3d(p2, _terrain_h(p2))
		map_node.sub_viewport.add_child(host)
		racimo["host"] = host
		# 5 raíces curvas por racimo
		var n = 5
		for i in range(n):
			var ang: float = (float(i) / float(n)) * TAU + randf_range(-0.35, 0.35)
			var dist: float = radius * randf_range(0.35, 0.85)
			var tip_off := Vector2(cos(ang), sin(ang)) * dist
			var root_inst := _make_root_3d(host, tip_off, randf_range(0.7, 1.35))
			racimo["roots3d"].append(root_inst)
	else:
		var line := Line2D.new()
		line.width = 10.0
		line.default_color = Color(0.32, 0.62, 0.18, 0.95)
		line.z_index = 12
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.position = p2 - _enemy_pos # relativo al nodo top-level
		add_child(line)
		racimo["line2d"] = line
		racimo["tip_off"] = Vector2(radius * 0.7, 0.0)

	_racimos.append(racimo)

# Cinta 3D vertical: del suelo hacia arriba con curvatura hacia el objetivo
func _make_root_3d(host: Node3D, tip_off_2d: Vector2, height_scale: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Root"
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.30, 0.60, 0.16, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.75, 0.15)
	mat.emission_energy_multiplier = 1.4
	mi.material_override = mat
	host.add_child(mi)
	mi.set_meta("tip_off", tip_off_2d)
	mi.set_meta("height_scale", height_scale)
	mi.set_meta("phase", randf() * TAU)
	mi.mesh = _build_root_mesh(0.0, tip_off_2d, height_scale, randf() * TAU)
	return mi

func _build_root_mesh(grow: float, tip_off_2d: Vector2, height_scale: float, phase: float) -> ArrayMesh:
	# grow: 0..1 (altura de brotación). Curva con quiebre orgánico.
	var segs := 10
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var base := Vector3.ZERO
	var tip3 := Vector3(tip_off_2d.x * _sf, 0.0, tip_off_2d.y * _sf * _cz)
	var total_h := (radius * 0.9) * _sf * height_scale
	var up := Vector3(0.0, total_h * grow, 0.0)

	var pts: Array[Vector3] = []
	for i in range(segs + 1):
		var u := float(i) / float(segs)
		# Curva parabólica con desplazamiento lateral orgánico
		var p := base.lerp(tip3, u * u)
		p.y = up.y * sin(u * PI * 0.5)
		var wob := sin(u * 5.0 + phase) * (radius * 0.06) * _sf * u
		p.x += wob
		p.z += wob * 0.6
		pts.append(p)

	var cam_dir := Vector3(0.0, 0.85, -0.52).normalized()
	for i in range(segs):
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]
		var tang := (p2 - p1)
		if tang.length_squared() < 0.0000001:
			tang = Vector3.UP
		var side := tang.cross(cam_dir).normalized()
		if side.length_squared() < 0.0001:
			side = Vector3.RIGHT
		var u1 := float(i) / float(segs)
		var u2 := float(i + 1) / float(segs)
		# Grosor: ancho en la base, afilado en la punta
		var w1 := lerpf(0.075, 0.006, u1) * _sf * 8.0
		var w2 := lerpf(0.075, 0.006, u2) * _sf * 8.0
		var a1 := p1 + side * w1
		var b1 := p1 - side * w1
		var a2 := p2 + side * w2
		var b2 := p2 - side * w2
		st.set_uv(Vector2(u1, 0.0)); st.add_vertex(a1)
		st.set_uv(Vector2(u2, 0.0)); st.add_vertex(a2)
		st.set_uv(Vector2(u1, 1.0)); st.add_vertex(b1)
		st.set_uv(Vector2(u1, 1.0)); st.add_vertex(b1)
		st.set_uv(Vector2(u2, 0.0)); st.add_vertex(a2)
		st.set_uv(Vector2(u2, 1.0)); st.add_vertex(b2)
	return st.commit()

# ------------------------------------------------------------------------------
# LOOP
# ------------------------------------------------------------------------------
func _process(delta: float) -> void:
	if _freed: return

	if _phase == "warn":
		_warn_elapsed += delta
		queue_redraw()
		if _is_3d and is_instance_valid(_burst_root):
			var pulse := 0.5 + 0.5 * sin(_warn_elapsed * 10.0)
			for zone in _burst_root.get_children():
				for c in zone.get_children():
					if c is MeshInstance3D and c.material_override is StandardMaterial3D:
						c.material_override.emission_energy_multiplier = 1.5 + 2.5 * pulse
		if _warn_elapsed >= cast_time:
			# Fallback: si "enraizada_end" no llega, brota en las posiciones telegrafiadas
			var fb: Array = []
			for pt in _warn_pts:
				fb.append({ "x": pt.x, "y": pt.y })
			_enter_burst({ "x": _enemy_pos.x, "y": _enemy_pos.y, "trapped": fb })
		return

	if _phase == "burst":
		_elapsed += delta
		var grow := clampf(_elapsed / 0.45, 0.0, 1.0)  # brotación rápida
		for r in _racimos:
			r["t"] = _elapsed
			if not r.get("roots3d", []).is_empty():
				for mi in r["roots3d"]:
					if is_instance_valid(mi):
						mi.mesh = _build_root_mesh(grow, mi.get_meta("tip_off"), mi.get_meta("height_scale"), mi.get_meta("phase"))
			elif is_instance_valid(r.get("line2d")):
				_draw_root_line_2d(r, grow)
		queue_redraw()
		if _elapsed >= duration:
			_phase = "fade"
		return

	if _phase == "fade":
		_elapsed += delta
		var fade := 1.0 - clampf((_elapsed - duration) / 0.6, 0.0, 1.0)
		for r in _racimos:
			if not r.get("roots3d", []).is_empty():
				for mi in r["roots3d"]:
					if is_instance_valid(mi) and mi.material_override is StandardMaterial3D:
						var m: StandardMaterial3D = mi.material_override
						var col := m.albedo_color
						col.a = fade
						m.albedo_color = col
						m.emission_energy_multiplier = 1.4 * fade
			elif is_instance_valid(r.get("line2d")):
				r["line2d"].modulate.a = fade
		if fade <= 0.0:
			_force_free()

func _draw_root_line_2d(r: Dictionary, grow: float) -> void:
	var line: Line2D = r["line2d"]
	if not is_instance_valid(line): return
	var base: Vector2 = Vector2.ZERO
	var tip: Vector2 = r.get("tip_off", Vector2(radius * 0.7, 0.0)) * grow
	var pts := PackedVector2Array()
	var segs := 12
	for i in range(segs + 1):
		var u := float(i) / float(segs)
		var p := base.lerp(tip, u * u)
		var wob := sin(u * 5.0 + float(r.get("seed", 0))) * radius * 0.07 * u
		pts.append(p + Vector2(wob, wob * 0.4))
	line.points = pts

func _draw() -> void:
	if _is_3d: return
	if _phase == "warn" and cast_time > 0.0:
		var prog := clampf(_warn_elapsed / maxf(cast_time, 0.001), 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(_warn_elapsed * 10.0)
		for pt in _warn_pts:
			var c := pt - _enemy_pos
			draw_circle(c, radius * prog, Color(0.30, 0.55, 0.14, 0.12 + 0.08 * pulse))
			draw_arc(c, radius * prog, 0.0, TAU, 56, Color(0.5, 0.85, 0.25, 0.55 + 0.35 * pulse), 3.0, true)
			# Grietas radiales
			for i in range(8):
				var a := (float(i) / 8.0) * TAU + _warn_elapsed * 0.6
				var p0 := c + Vector2(cos(a), sin(a)) * radius * 0.25 * prog
				var p1 := c + Vector2(cos(a), sin(a)) * radius * 0.95 * prog
				draw_line(p0, p1, Color(0.4, 0.75, 0.2, 0.25 + 0.2 * pulse), 2.0, true)

# ------------------------------------------------------------------------------
# LIMPIEZA
# ------------------------------------------------------------------------------
func _force_free() -> void:
	if _freed: return
	_freed = true
	_free_racimos()
	if is_instance_valid(_burst_root):
		_burst_root.queue_free()
		_burst_root = null
	queue_free()

func _exit_tree() -> void:
	_free_racimos()
	if is_instance_valid(_burst_root):
		_burst_root.queue_free()
		_burst_root = null

# API de compatibilidad con el resto de handlers
func finish() -> void:
	_force_free()

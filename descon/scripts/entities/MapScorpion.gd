extends "res://scripts/entities/RockCritter_Base.gd"

## Escorpión Emperador (Pandinus imperator) 3D Realista para el Mapa 2
## Modelo 100% opaco, sólido, negro azabache carbón con telson caoba rojizo,
## quelas masivas al frente y cola en arco erguido amenazante sobre el lomo.

const GROUND_REFRESH := 0.15

var terrain: Node3D
var bounds_override := AABB()
var body_node: Node3D
var tail_root: Node3D

# Articulaciones anatómicas
var leg_pivots: Array[Node3D] = []
var leg_knees: Array[Node3D] = []
var leg_sides: Array[float] = []
var leg_phases: Array[float] = []

var claw_pivots: Array[Node3D] = []
var claw_fingers: Array[Node3D] = []

var _walked := 0.0
var _next_pause_at := 8.0
var _pause_left := 0.0
var _stalking := false
var _amp := 0.0
var _g_y := 0.0
var _g_n := Vector3.UP
var _g_t := 0.0

# Materiales PBR 100% opacos (sin transparencias que causen invisibilidad o fallos de orden de render)
static var _sm_chitin_black: StandardMaterial3D   # Cutícula negra azabache sólida
static var _sm_telson_caoba: StandardMaterial3D   # Telson / vesícula caoba rojiza
static var _sm_aculeus_needle: StandardMaterial3D # Aguijón negro agudo

# Mallas volumétricas compartidas
static var _mesh_shared_ok := false
static var _mesh_carapace: ArrayMesh
static var _mesh_tergite: ArrayMesh
static var _mesh_tail_seg: ArrayMesh
static var _mesh_telson: ArrayMesh
static var _mesh_aculeus: ArrayMesh
static var _mesh_arm_humerus: ArrayMesh
static var _mesh_arm_patella: ArrayMesh
static var _mesh_claw_palm: ArrayMesh
static var _mesh_fixed_finger: ArrayMesh
static var _mesh_movable_finger: ArrayMesh
static var _mesh_femur: ArrayMesh
static var _mesh_tibia: ArrayMesh
static var _mesh_eye: SphereMesh


static func _ensure_shared() -> void:
	if _mesh_shared_ok:
		return

	# Cutícula principal: 100% sólida opaca, negro carbón azabache, sin clearcoat ni rim que quemen la luz
	_sm_chitin_black = StandardMaterial3D.new()
	_sm_chitin_black.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_sm_chitin_black.albedo_color = Color(0.045, 0.042, 0.040)
	_sm_chitin_black.roughness = 0.42
	_sm_chitin_black.metallic = 0.0
	_sm_chitin_black.metallic_specular = 0.28
	_sm_chitin_black.cull_mode = BaseMaterial3D.CULL_BACK
	_sm_chitin_black.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX

	# Telson / vesícula: Caoba rojizo profundo y sólido
	_sm_telson_caoba = StandardMaterial3D.new()
	_sm_telson_caoba.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_sm_telson_caoba.albedo_color = Color(0.22, 0.07, 0.03)
	_sm_telson_caoba.roughness = 0.32
	_sm_telson_caoba.metallic = 0.0
	_sm_telson_caoba.metallic_specular = 0.35
	_sm_telson_caoba.cull_mode = BaseMaterial3D.CULL_BACK

	# Aguijón (acúleo): Negro pulido
	_sm_aculeus_needle = StandardMaterial3D.new()
	_sm_aculeus_needle.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_sm_aculeus_needle.albedo_color = Color(0.02, 0.02, 0.02)
	_sm_aculeus_needle.roughness = 0.20
	_sm_aculeus_needle.metallic = 0.15
	_sm_aculeus_needle.metallic_specular = 0.40
	_sm_aculeus_needle.cull_mode = BaseMaterial3D.CULL_BACK

	# Ojos diminutos frontales
	_mesh_eye = SphereMesh.new()
	_mesh_eye.radius = 0.012
	_mesh_eye.height = 0.024
	_mesh_eye.radial_segments = 6
	_mesh_eye.rings = 4
	_mesh_eye.material = _sm_aculeus_needle

	# Mallas anatómicas con normales hacia el exterior
	_mesh_carapace = _build_emperor_carapace()
	_mesh_tergite = _build_emperor_tergite()
	_mesh_tail_seg = _build_tail_seg_mesh(0.09, 0.036)
	_mesh_telson = _build_emperor_telson()
	_mesh_aculeus = _build_emperor_aculeus()
	_mesh_arm_humerus = _build_arm_segment(0.12, 0.032, 0.026)
	_mesh_arm_patella = _build_arm_segment(0.14, 0.038, 0.032)
	_mesh_claw_palm = _build_emperor_claw_palm()
	_mesh_fixed_finger = _build_emperor_claw_finger(false)
	_mesh_movable_finger = _build_emperor_claw_finger(true)
	_mesh_femur = _build_femur_mesh()
	_mesh_tibia = _build_tibia_mesh()

	_mesh_shared_ok = true


## Carapacho (Prosoma): Escudo trapezoidal ancho y abovedado
static func _build_emperor_carapace() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rings := 6
	var segs := 12
	var prev_ring: Array[Vector3] = []

	for r in range(rings + 1):
		var t := float(r) / float(rings)
		var z := lerpf(0.12, -0.11, t)
		var w := lerpf(0.10, 0.16, sin(t * PI * 0.75 + 0.2))
		var h := lerpf(0.025, 0.055, sin(t * PI * 0.9 + 0.1))

		var cur_ring: Array[Vector3] = []
		for s in range(segs):
			var a := float(s) / float(segs) * TAU
			var y_scale := 1.1 if sin(a) > 0.0 else 0.55
			cur_ring.append(Vector3(cos(a) * w, sin(a) * h * y_scale, z))

		if r > 0:
			for s in range(segs):
				var nxt := (s + 1) % segs
				st.add_vertex(prev_ring[s])
				st.add_vertex(cur_ring[s])
				st.add_vertex(prev_ring[nxt])

				st.add_vertex(prev_ring[nxt])
				st.add_vertex(cur_ring[s])
				st.add_vertex(cur_ring[nxt])

		prev_ring = cur_ring

	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, _sm_chitin_black)
	return m


## Terguito de mesosoma: Placa transversal ancha y abovedada
static func _build_emperor_tergite() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var w := 0.17
	var h := 0.040
	var len_z := 0.065
	var segs := 12

	var v_front: Array[Vector3] = []
	var v_back: Array[Vector3] = []

	for s in range(segs):
		var a := float(s) / float(segs) * TAU
		var y_mod := 1.15 if sin(a) > 0.0 else 0.65
		v_front.append(Vector3(cos(a) * w, sin(a) * h * y_mod, len_z * 0.5))
		v_back.append(Vector3(cos(a) * w * 0.98, sin(a) * h * y_mod * 0.95, -len_z * 0.5))

	for s in range(segs):
		var nxt := (s + 1) % segs
		st.add_vertex(v_front[s])
		st.add_vertex(v_back[s])
		st.add_vertex(v_front[nxt])

		st.add_vertex(v_front[nxt])
		st.add_vertex(v_back[s])
		st.add_vertex(v_back[nxt])

	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, _sm_chitin_black)
	return m


## Palma masiva de la quela (pinzas gigantes)
static func _build_emperor_claw_palm() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var steps := 8
	var segs := 12
	var prev_ring: Array[Vector3] = []

	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var z := lerpf(-0.10, 0.11, t)

		var bulb := sin(t * PI)
		var rx := lerpf(0.038, 0.095, bulb)
		var ry := lerpf(0.025, 0.065, bulb)

		var cur_ring: Array[Vector3] = []
		for s in range(segs):
			var ang := float(s) / float(segs) * TAU
			var x_mod := (1.18 if cos(ang) > 0.0 else 0.88)
			cur_ring.append(Vector3(cos(ang) * rx * x_mod, sin(ang) * ry, z))

		if i > 0:
			for s in range(segs):
				var nxt := (s + 1) % segs
				st.add_vertex(prev_ring[s])
				st.add_vertex(cur_ring[s])
				st.add_vertex(prev_ring[nxt])

				st.add_vertex(prev_ring[nxt])
				st.add_vertex(cur_ring[s])
				st.add_vertex(cur_ring[nxt])

		prev_ring = cur_ring

	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, _sm_chitin_black)
	return m


## Dedo de la pinza curvado con gancho interior
static func _build_emperor_claw_finger(is_movable: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var steps := 7
	var segs := 8
	var prev_ring: Array[Vector3] = []

	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var len_z := t * 0.13
		var curve_dir := -1.0 if not is_movable else 1.0
		var x_curve := sin(t * 0.95) * 0.045 * curve_dir
		var y_curve := (sin(t * 0.6) * 0.015) if is_movable else 0.0
		var r := lerpf(0.024, 0.003, t)

		var cur_ring: Array[Vector3] = []
		for s in range(segs):
			var ang := float(s) / float(segs) * TAU
			cur_ring.append(Vector3(x_curve + cos(ang) * r, y_curve + sin(ang) * r * 1.3, len_z))

		if i > 0:
			for s in range(segs):
				var nxt := (s + 1) % segs
				st.add_vertex(prev_ring[s])
				st.add_vertex(cur_ring[s])
				st.add_vertex(prev_ring[nxt])

				st.add_vertex(prev_ring[nxt])
				st.add_vertex(cur_ring[s])
				st.add_vertex(cur_ring[nxt])

		prev_ring = cur_ring

	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, _sm_chitin_black)
	return m


## Segmentos de brazo de pinza (Húmero y Patela)
static func _build_arm_segment(length: float, r_base: float, r_end: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var segs := 10
	var v_front: Array[Vector3] = []
	var v_back: Array[Vector3] = []

	for s in range(segs):
		var a := float(s) / float(segs) * TAU
		v_front.append(Vector3(cos(a) * r_end, sin(a) * r_end * 0.85, length * 0.5))
		v_back.append(Vector3(cos(a) * r_base, sin(a) * r_base * 0.85, -length * 0.5))

	for s in range(segs):
		var nxt := (s + 1) % segs
		st.add_vertex(v_back[s])
		st.add_vertex(v_front[s])
		st.add_vertex(v_back[nxt])

		st.add_vertex(v_back[nxt])
		st.add_vertex(v_front[s])
		st.add_vertex(v_front[nxt])

	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, _sm_chitin_black)
	return m


## Segmento de cola metasoma cilíndrico/prismático orientado a lo largo de Z
static func _build_tail_seg_mesh(length: float, radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var segs := 10
	var v_front: Array[Vector3] = []
	var v_back: Array[Vector3] = []

	for s in range(segs):
		var a := float(s) / float(segs) * TAU
		v_front.append(Vector3(cos(a) * radius * 0.90, sin(a) * radius * 0.95, length * 0.5))
		v_back.append(Vector3(cos(a) * radius * 1.05, sin(a) * radius * 1.05, -length * 0.5))

	for s in range(segs):
		var nxt := (s + 1) % segs
		st.add_vertex(v_back[s])
		st.add_vertex(v_front[s])
		st.add_vertex(v_back[nxt])

		st.add_vertex(v_back[nxt])
		st.add_vertex(v_front[s])
		st.add_vertex(v_front[nxt])

	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, _sm_chitin_black)
	return m


## Telson / Bulbo de veneno caoba rojizo
static func _build_emperor_telson() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rings := 6
	var segs := 12
	var grid: Array = []

	for r in range(rings + 1):
		var row: Array[Vector3] = []
		var f := float(r) / float(rings)
		var phi := f * PI
		var y := cos(phi) * 0.045
		var rad := sin(phi) * (0.040 + 0.015 * (1.0 - f))
		for s in range(segs):
			var theta := float(s) / float(segs) * TAU
			row.append(Vector3(cos(theta) * rad * 0.90, y, sin(theta) * rad * 1.20))
		grid.append(row)

	for r in range(rings):
		for s in range(segs):
			var nxt := (s + 1) % segs
			var p0 = grid[r][s]
			var p1 = grid[r][nxt]
			var p2 = grid[r + 1][s]
			var p3 = grid[r + 1][nxt]
			if r > 0:
				st.add_vertex(p0); st.add_vertex(p1); st.add_vertex(p2)
			if r < rings - 1:
				st.add_vertex(p1); st.add_vertex(p3); st.add_vertex(p2)

	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, _sm_telson_caoba)
	return m


## Acúleo / Aguijón afilado en arco hacia abajo
static func _build_emperor_aculeus() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var steps := 8
	var prev_pts: Array[Vector3] = []

	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var ang := t * 1.6
		var center := Vector3(0.0, -sin(ang) * 0.045, cos(ang) * 0.045 - 0.045)
		var rad := lerpf(0.013, 0.0012, t)

		var cur_pts: Array[Vector3] = [
			center + Vector3(rad, 0.0, 0.0),
			center + Vector3(0.0, rad, 0.0),
			center + Vector3(-rad, 0.0, 0.0),
			center + Vector3(0.0, -rad, 0.0),
		]

		if i > 0:
			for p in range(4):
				var pn := (p + 1) % 4
				st.add_vertex(prev_pts[p])
				st.add_vertex(cur_pts[p])
				st.add_vertex(prev_pts[pn])

				st.add_vertex(prev_pts[pn])
				st.add_vertex(cur_pts[p])
				st.add_vertex(cur_pts[pn])

		prev_pts = cur_pts

	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, _sm_aculeus_needle)
	return m


## Fémur de pata
static func _build_femur_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var len_h := 0.16
	var w := 0.020
	var segs := 8

	var v_top: Array[Vector3] = []
	var v_bot: Array[Vector3] = []

	for s in range(segs):
		var a := float(s) / float(segs) * TAU
		v_top.append(Vector3(cos(a) * w, len_h * 0.5, sin(a) * w * 0.7))
		v_bot.append(Vector3(cos(a) * w * 0.75, -len_h * 0.5, sin(a) * w * 0.55))

	for s in range(segs):
		var nxt := (s + 1) % segs
		st.add_vertex(v_bot[s]); st.add_vertex(v_top[s]); st.add_vertex(v_bot[nxt])
		st.add_vertex(v_bot[nxt]); st.add_vertex(v_top[s]); st.add_vertex(v_top[nxt])

	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, _sm_chitin_black)
	return m


## Tibia y tarso
static func _build_tibia_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var len_h := 0.18
	var segs := 8

	var v_top: Array[Vector3] = []
	var v_bot: Array[Vector3] = []

	for s in range(segs):
		var a := float(s) / float(segs) * TAU
		v_top.append(Vector3(cos(a) * 0.015, len_h * 0.5, sin(a) * 0.012))
		v_bot.append(Vector3(cos(a) * 0.003, -len_h * 0.5, sin(a) * 0.003))

	for s in range(segs):
		var nxt := (s + 1) % segs
		st.add_vertex(v_bot[s]); st.add_vertex(v_top[s]); st.add_vertex(v_bot[nxt])
		st.add_vertex(v_bot[nxt]); st.add_vertex(v_top[s]); st.add_vertex(v_top[nxt])

	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, _sm_chitin_black)
	return m


func setup_scorpion(p_root: Node3D, p_terrain: Node3D, p_bounds: AABB) -> void:
	rock = p_root
	terrain = p_terrain
	bounds_override = p_bounds
	rng.randomize()
	_read_map_scale_factors()
	_vision_check_timer = rng.randf_range(0.0, 0.25)
	_measure()
	_ensure_shared()

	size = rng.randf_range(0.55, 0.75)
	walk_speed = size * rng.randf_range(2.6, 4.0)
	_build()
	idle_time = rng.randf_range(0.5, 2.0)
	_next_pause_at = rng.randf_range(5.0, 12.0)


func place_now() -> void:
	_placed = false
	_place_initial()


func _place_initial() -> void:
	var inset_x := world_aabb.size.x * 0.08
	var inset_z := world_aabb.size.z * 0.08
	var found := false
	for i in 25:
		var rx := rng.randf_range(world_aabb.position.x + inset_x, world_aabb.end.x - inset_x)
		var rz := rng.randf_range(world_aabb.position.z + inset_z, world_aabb.end.z - inset_z)
		var g := _sample_ground(rx, rz)
		var gy: float = g["y"]
		if not is_nan(gy):
			pos = Vector3(rx, gy, rz)
			_g_y = gy
			var norm: Vector3 = g["normal"]
			up = norm.normalized() if norm.length_squared() > 0.001 else Vector3.UP
			_g_n = up
			found = true
			break
	if not found:
		var c := world_aabb.get_center()
		var g := _sample_ground(c.x, c.z)
		var gy: float = g["y"] if not is_nan(g["y"]) else 0.0
		pos = Vector3(c.x, gy, c.z)
		_g_y = gy
		up = Vector3.UP
		_g_n = Vector3.UP

	yaw = rng.randf_range(0.0, TAU)
	_apply_transform()
	_placed = true
	_read_map_scale_factors()
	_is_in_player_vision = _check_in_player_vision()
	visible = _is_in_player_vision
	_pick_target()


func _measure() -> void:
	world_aabb = bounds_override


func _terrain_h(x: float, z: float) -> float:
	if not is_instance_valid(terrain):
		return 0.0
	var th: float = TerrainCollisionBaker2D.get_height_at_3d_pos(terrain, Vector3(x, 10.0, z))
	if is_nan(th) or is_inf(th):
		return NAN
	return th


func _sample_ground(x: float, z: float) -> Dictionary:
	var th := _terrain_h(x, z)
	var base_y := 0.0
	var normal := Vector3.UP
	if not is_nan(th):
		base_y = th
		var s := 1.5
		var hx := _terrain_h(x + s, z)
		var hz := _terrain_h(x, z + s)
		if not is_nan(hx) and not is_nan(hz):
			normal = Vector3(-(hx - th) / s, 1.0, -(hz - th) / s).normalized()
	var ws := get_world_3d()
	if ws != null:
		var space := ws.direct_space_state
		if space != null:
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, base_y + 25.0, z), Vector3(x, base_y - 1.5, z), RAY_MASK)
			var hit := space.intersect_ray(q)
			if not hit.is_empty() and hit["position"].y > base_y + 0.02:
				var hn: Vector3 = hit["normal"]
				return {"y": hit["position"].y, "normal": hn.normalized() if hn.length_squared() > 0.001 else Vector3.UP}
	return {"y": base_y, "normal": normal}


func _ray_down(x: float, z: float) -> Dictionary:
	var g := _sample_ground(x, z)
	var y: float = g["y"]
	if is_nan(y):
		return {}
	return {"position": Vector3(x, y, z), "normal": g["normal"]}


func _spot_ok(x: float, z: float) -> bool:
	var th := _terrain_h(x, z)
	if is_nan(th):
		return false
	var s := 1.5
	var hx := _terrain_h(x + s, z)
	var hz := _terrain_h(x, z + s)
	if is_nan(hx) or is_nan(hz):
		return false
	if absf(hx - th) > 2.4 or absf(hz - th) > 2.4:
		return false
	if _placed and absf(th - pos.y) > 30.0:
		return false
	return true


func _pick_target() -> void:
	var inset_x := world_aabb.size.x * 0.05
	var inset_z := world_aabb.size.z * 0.05
	for i in 12:
		var x := rng.randf_range(world_aabb.position.x + inset_x, world_aabb.end.x - inset_x)
		var z := rng.randf_range(world_aabb.position.z + inset_z, world_aabb.end.z - inset_z)
		if not _spot_ok(x, z):
			continue
		var g := _sample_ground(x, z)
		var gy: float = g["y"]
		if is_nan(gy):
			continue
		target = Vector3(x, gy, z)
		walking = true
		return
	walking = false
	idle_time = rng.randf_range(0.6, 2.5)


func _refresh_ground() -> void:
	var g := _sample_ground(pos.x, pos.z)
	if not g.is_empty() and not is_nan(g["y"]):
		_g_y = g["y"]
		_g_n = g["normal"]


func _physics_process(delta: float) -> void:
	if rock == null or not is_instance_valid(rock):
		return
	if not _placed:
		_place_initial()
		return

	# --- CULLING POR RANGO DE VISIÓN DEL JUGADOR / CÁMARA ---
	_vision_check_timer -= delta
	if _vision_check_timer <= 0.0:
		_vision_check_timer = 0.25
		_is_in_player_vision = _check_in_player_vision()
		if visible != _is_in_player_vision:
			visible = _is_in_player_vision

	if not _is_in_player_vision:
		return # Cortocircuito: fuera de visión no se renderiza (visible=false) ni gasta CPU

	if _pause_left > 0.0:
		_pause_left -= delta
		_stalking = true
		phase += delta * 4.0
		_apply_ground(delta)
		_apply_transform()
		_animate(delta)
		if _pause_left <= 0.0:
			_stalking = false
		return

	_stalking = false
	if walking:
		var flat := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
		var dist := flat.length()
		if dist < size * 0.4:
			walking = false
			idle_time = rng.randf_range(1.0, 3.5)
			_walked = 0.0
			_next_pause_at = rng.randf_range(5.0, 14.0)
		else:
			var dir := flat / dist
			var step := walk_speed * _walk_speed_scale() * delta
			pos += dir * step
			_walked += step
			phase += delta * (walk_speed / size) * 4.0
			yaw = _lerp_yaw(yaw, atan2(dir.x, dir.z), minf(1.0, delta * 6.5))
			if _walked >= _next_pause_at and dist > size * 4.0:
				_walked = 0.0
				_next_pause_at = rng.randf_range(6.0, 18.0)
				_pause_left = rng.randf_range(1.2, 2.6)
				_stalking = true
				return
	else:
		idle_time -= delta
		phase += delta * 1.5
		if idle_time <= 0.0:
			_pick_target()

	_apply_ground(delta)
	_apply_transform()
	_animate(delta)


func _apply_ground(delta: float) -> void:
	_g_t -= delta
	if _g_t <= 0.0:
		_refresh_ground()
		_g_t = GROUND_REFRESH
	pos.y = lerpf(pos.y, _g_y, minf(1.0, delta * 12.0))
	var un := up.normalized() if up.length_squared() > 0.001 else Vector3.UP
	var tn := _g_n.normalized() if _g_n.length_squared() > 0.001 else Vector3.UP
	up = un.lerp(tn, minf(1.0, delta * 5.0))
	up = up.normalized() if up.length_squared() > 0.001 else Vector3.UP


func _apply_transform() -> void:
	var upn := up.normalized() if up.length_squared() > 0.001 else Vector3.UP
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := upn.cross(fwd)
	if right.length_squared() < 0.0001:
		right = upn.cross(Vector3.RIGHT)
		if right.length_squared() < 0.0001:
			right = upn.cross(Vector3.FORWARD)
	right = right.normalized()
	var f2 := right.cross(upn)
	if f2.length_squared() < 0.0001:
		f2 = fwd
	f2 = f2.normalized()
	global_transform = Transform3D(Basis(right, upn, f2).orthonormalized(), pos)


func _mk(mesh: Mesh, pos_l: Vector3, scale_l: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos_l
	mi.scale = scale_l
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Ensamblado anatómico de alta fidelidad basado en Pandinus imperator
func _build() -> void:
	_ensure_shared()
	var L := size

	body_node = Node3D.new()
	add_child(body_node)

	# 1. Carapacho ancho y acorazado
	var carapace := _mk(_mesh_carapace, Vector3(0.0, L * 0.09, L * 0.06), Vector3(L * 1.15, L * 1.0, L * 1.05))
	body_node.add_child(carapace)

	# Ojos medianos sobre el tubérculo
	for side in [-1.0, 1.0]:
		var eye := _mk(_mesh_eye, Vector3(side * L * 0.024, L * 0.145, L * 0.08), Vector3(L * 0.8, L * 0.8, L * 0.8))
		body_node.add_child(eye)

	# 2. Mesosoma: 7 Terguitos muy anchos y abovedados con canales transversales profundos
	var tergite_count := 7
	for i in range(tergite_count):
		var fi := float(i)
		var taper: float = 1.0 - (fi / float(tergite_count)) * 0.28
		var z_off: float = -L * (0.05 + fi * 0.070)
		var tergite := _mk(
			_mesh_tergite,
			Vector3(0.0, L * (0.088 - fi * 0.004), z_off),
			Vector3(L * 1.15 * taper, L * 1.0 * taper, L * 1.0)
		)
		body_node.add_child(tergite)

	# 3. Pedipalpos y Quelas Masivas (pinzas gigantes de escorpión emperador)
	for side in [-1.0, 1.0]:
		var claw_base := Node3D.new()
		claw_base.position = Vector3(side * L * 0.11, L * 0.08, L * 0.14)
		claw_base.rotation.y = side * 0.38
		body_node.add_child(claw_base)
		claw_pivots.append(claw_base)

		# Húmero (primer segmento del brazo, corto y grueso)
		var arm1 := _mk(
			_mesh_arm_humerus,
			Vector3(side * L * 0.07, 0.0, L * 0.07),
			Vector3(L * 1.1, L * 1.1, L * 1.1),
			Vector3(0.14, side * 0.65, -0.12)
		)
		claw_base.add_child(arm1)

		# Patela (antebrazo robusto curvado hacia adentro)
		var arm2 := _mk(
			_mesh_arm_patella,
			Vector3(side * L * 0.16, 0.0, L * 0.18),
			Vector3(L * 1.15, L * 1.15, L * 1.15),
			Vector3(-0.08, -side * 0.50, 0.08)
		)
		claw_base.add_child(arm2)

		# Mano de la quela (propodus masivo y bulboso)
		var palm := _mk(
			_mesh_claw_palm,
			Vector3(side * L * 0.20, L * 0.01, L * 0.32),
			Vector3(L * 1.25, L * 1.25, L * 1.25),
			Vector3(0.0, side * 0.25, 0.0)
		)
		claw_base.add_child(palm)

		# Dedo fijo exterior
		var fixed_finger := _mk(
			_mesh_fixed_finger,
			Vector3(side * L * 0.22, 0.0, L * 0.40),
			Vector3(L * 1.2, L * 1.2, L * 1.2),
			Vector3(0.0, side * 0.16, 0.0)
		)
		claw_base.add_child(fixed_finger)

		# Dedo móvil interior articulado
		var movable_pivot := Node3D.new()
		movable_pivot.position = Vector3(side * L * 0.18, 0.0, L * 0.38)
		claw_base.add_child(movable_pivot)

		var movable_finger := _mk(
			_mesh_movable_finger,
			Vector3(0.0, 0.0, L * 0.03),
			Vector3(L * 1.15, L * 1.15, L * 1.15),
			Vector3(0.0, -side * 0.12, 0.0)
		)
		movable_pivot.add_child(movable_finger)
		claw_fingers.append(movable_pivot)

	# 4. 8 Patas arácnidas compactas
	var leg_z_offsets := [0.08, 0.01, -0.06, -0.13]
	var leg_angles := [0.45, 0.12, -0.18, -0.48]
	for pair in range(4):
		var p_z: float = leg_z_offsets[pair]
		var p_ang: float = leg_angles[pair]
		for side in [-1.0, 1.0]:
			var hip := Node3D.new()
			hip.position = Vector3(side * L * 0.10, L * 0.07, L * p_z)
			hip.rotation.y = side * (PI * 0.5 + p_ang)
			body_node.add_child(hip)
			leg_pivots.append(hip)
			leg_sides.append(side)

			# Desfase de marcha alterna de arácnido
			var phase_off: float = (float(pair) * PI * 0.5) if side < 0.0 else (float(pair) * PI * 0.5 + PI)
			leg_phases.append(phase_off)

			# Fémur robusto
			var femur := _mk(
				_mesh_femur,
				Vector3(0.0, L * 0.05, L * 0.07),
				Vector3(L * 1.0, L * 1.0, L * 1.0),
				Vector3(-0.65, 0.0, 0.0)
			)
			hip.add_child(femur)

			# Rodilla y Tibia/Tarso que apoya en el suelo
			var knee := Node3D.new()
			knee.position = Vector3(0.0, L * 0.10, L * 0.14)
			knee.rotation.x = 1.30
			hip.add_child(knee)
			leg_knees.append(knee)

			var tibia := _mk(
				_mesh_tibia,
				Vector3(0.0, 0.0, L * 0.08),
				Vector3(L * 1.0, L * 1.0, L * 1.0),
				Vector3(0.0, 0.0, 0.0)
			)
			knee.add_child(tibia)

	# 5. Cola Metasoma: Arco erguido y majestuoso sobre el lomo
	tail_root = Node3D.new()
	body_node.add_child(tail_root)

	# Puntos paramétricos del arco de la cola en el aire (elevada de Y=0.10 a Y=0.45)
	var tail_pts: Array[Vector3] = [
		Vector3(0.0, L * 0.10, -L * 0.50), # Segmento 1: Base trasera
		Vector3(0.0, L * 0.22, -L * 0.56), # Segmento 2: Sube hacia atrás
		Vector3(0.0, L * 0.36, -L * 0.50), # Segmento 3: Sube vertical
		Vector3(0.0, L * 0.44, -L * 0.36), # Segmento 4: Curva hacia adelante (cúspide)
		Vector3(0.0, L * 0.43, -L * 0.20), # Segmento 5: Avanza sobre la espalda
	]

	var telson_pt := Vector3(0.0, L * 0.38, -L * 0.08)

	for i in range(4):
		var p0 = tail_pts[i]
		var p1 = tail_pts[i + 1]
		var mid = (p0 + p1) * 0.5
		var dir = (p1 - p0).normalized()
		var seg_len = p0.distance_to(p1)

		var seg := _mk(
			_mesh_tail_seg,
			mid,
			Vector3(L * (1.15 - float(i) * 0.08), L * (1.15 - float(i) * 0.08), seg_len / 0.09)
		)
		# Orientar el segmento a lo largo de la dirección de la curva
		seg.look_at_from_position(mid, mid + dir, Vector3.UP)
		tail_root.add_child(seg)

	# Último segmento hacia el telson
	var p_last = tail_pts[4]
	var mid_last = (p_last + telson_pt) * 0.5
	var dir_last = (telson_pt - p_last).normalized()
	var seg_last := _mk(
		_mesh_tail_seg,
		mid_last,
		Vector3(L * 0.85, L * 0.85, p_last.distance_to(telson_pt) / 0.09)
	)
	seg_last.look_at_from_position(mid_last, mid_last + dir_last, Vector3.UP)
	tail_root.add_child(seg_last)

	# Telson (vesícula bulbosa caoba rojiza suspendida sobre la espalda)
	var telson := _mk(
		_mesh_telson,
		telson_pt,
		Vector3(L * 1.25, L * 1.25, L * 1.25),
		Vector3(0.55, 0.0, 0.0)
	)
	tail_root.add_child(telson)

	# Acúleo (aguijón en arco hiperafilado negro azabache)
	var aculeus := _mk(
		_mesh_aculeus,
		telson_pt + Vector3(0.0, -L * 0.02, L * 0.03),
		Vector3(L * 1.15, L * 1.15, L * 1.15),
		Vector3(0.25, 0.0, 0.0)
	)
	tail_root.add_child(aculeus)


func _animate(delta: float) -> void:
	var L := size
	var want := 0.0
	if _stalking:
		want = 0.0
	elif walking:
		want = 0.45
	_amp = lerpf(_amp, want, minf(1.0, delta * 10.0))

	# 1. Marcha arácnida de 8 patas
	for i in range(leg_pivots.size()):
		var leg_phase: float = phase + leg_phases[i]
		var s := sin(leg_phase)
		var c := cos(leg_phase)

		leg_pivots[i].rotation.y = lerpf(leg_pivots[i].rotation.y, (leg_sides[i] * (PI * 0.5)) + s * _amp * 0.38, minf(1.0, delta * 14.0))
		var lift: float = maxf(0.0, c) * _amp * 0.32
		leg_knees[i].rotation.x = lerpf(leg_knees[i].rotation.x, 1.30 - lift, minf(1.0, delta * 14.0))

	# 2. Leve cabeceo orgánico al caminar
	var sway := 0.0
	if walking and not _stalking:
		sway = sin(phase * 2.0) * 0.025
	body_node.rotation.y = lerpf(body_node.rotation.y, sway, minf(1.0, delta * 10.0))

	# 3. Postura y tanteo amenazante de la cola (balanceo suave en el aire)
	var tail_wag := sin(phase * 1.6) * 0.08 if walking else sin(phase * 0.8) * 0.04
	var tail_nod := sin(phase * 3.5) * 0.06 if _stalking else 0.0
	tail_root.rotation.y = lerpf(tail_root.rotation.y, tail_wag, minf(1.0, delta * 8.0))
	tail_root.rotation.x = lerpf(tail_root.rotation.x, tail_nod, minf(1.0, delta * 8.0))

	# 4. Chasquido de las pinzas emperador
	var claw_snap := 0.0
	if _stalking:
		claw_snap = absf(sin(phase * 3.8)) * 0.42
	elif walking:
		claw_snap = absf(sin(phase * 1.4)) * 0.18
	
	for f_idx in range(claw_fingers.size()):
		var side: float = -1.0 if f_idx == 0 else 1.0
		claw_fingers[f_idx].rotation.y = lerpf(claw_fingers[f_idx].rotation.y, side * claw_snap, minf(1.0, delta * 12.0))

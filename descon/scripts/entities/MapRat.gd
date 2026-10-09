extends "res://scripts/entities/RockCritter_Base.gd"

const GROUND_REFRESH := 0.15

var terrain: Node3D
var bounds_override := AABB()
var body_node: Node3D
var head_node: Node3D
var hips: Array[Node3D] = []
var leg_sides: Array[float] = []
var ears: Array[MeshInstance3D] = []
var tail_segs: Array[Node3D] = []
var _ear_twitch := 0.0
var _ear_timer := 0.0
var _walked := 0.0
var _next_sniff_at := 10.0
var _pause_left := 0.0
var _sniffing := false
var _g_y := 0.0
var _g_n := Vector3.UP
var _g_t := 0.0

static var _sm_body: StandardMaterial3D
static var _sm_skin: StandardMaterial3D
static var _sm_dark: StandardMaterial3D
static var _sm_nose: StandardMaterial3D
static var _mesh_shared_ok := false
static var _mesh_body: SphereMesh
static var _mesh_head: SphereMesh
static var _mesh_nose: SphereMesh
static var _mesh_eye: SphereMesh
static var _mesh_ear: SphereMesh
static var _mesh_haunch: SphereMesh
static var _mesh_shin: CylinderMesh
static var _mesh_foot: SphereMesh
static var _mesh_tail: CylinderMesh


static func _ensure_shared() -> void:
	if _mesh_shared_ok:
		return
	_sm_body = StandardMaterial3D.new()
	_sm_body.albedo_color = Color(0.28, 0.24, 0.22) # Pelaje marrón grisáceo oscuro de rata silvestre
	_sm_body.roughness = 0.85
	_sm_skin = StandardMaterial3D.new()
	_sm_skin.albedo_color = Color(0.78, 0.55, 0.52) # Piel rosada desaturada natural (hocico, patas, cola)
	_sm_skin.roughness = 0.65
	_sm_dark = StandardMaterial3D.new()
	_sm_dark.albedo_color = Color(0.04, 0.04, 0.04) # Ojos negros brillantes
	_sm_dark.roughness = 0.15
	_sm_nose = StandardMaterial3D.new()
	_sm_nose.albedo_color = Color(0.85, 0.48, 0.48)
	_sm_nose.roughness = 0.55
	
	# Cuerpo ahusado y alargado
	_mesh_body = SphereMesh.new()
	_mesh_body.radius = 0.12
	_mesh_body.height = 0.32
	_mesh_body.radial_segments = 10
	_mesh_body.rings = 6
	_mesh_body.material = _sm_body

	# Cabeza cónica y afinada hacia el hocico
	_mesh_head = SphereMesh.new()
	_mesh_head.radius = 0.08
	_mesh_head.height = 0.18
	_mesh_head.radial_segments = 8
	_mesh_head.rings = 5
	_mesh_head.material = _sm_body

	_mesh_nose = SphereMesh.new()
	_mesh_nose.radius = 0.02
	_mesh_nose.height = 0.04
	_mesh_nose.radial_segments = 6
	_mesh_nose.rings = 4
	_mesh_nose.material = _sm_nose

	_mesh_eye = SphereMesh.new()
	_mesh_eye.radius = 0.018
	_mesh_eye.height = 0.036
	_mesh_eye.radial_segments = 6
	_mesh_eye.rings = 4
	_mesh_eye.material = _sm_dark

	# Orejas redondeadas delgadas
	_mesh_ear = SphereMesh.new()
	_mesh_ear.radius = 0.05
	_mesh_ear.height = 0.10
	_mesh_ear.radial_segments = 8
	_mesh_ear.rings = 5
	_mesh_ear.material = _sm_skin

	_mesh_haunch = SphereMesh.new()
	_mesh_haunch.radius = 0.04
	_mesh_haunch.height = 0.09
	_mesh_haunch.radial_segments = 7
	_mesh_haunch.rings = 4
	_mesh_haunch.material = _sm_body

	_mesh_shin = CylinderMesh.new()
	_mesh_shin.top_radius = 0.010
	_mesh_shin.bottom_radius = 0.007
	_mesh_shin.height = 0.12
	_mesh_shin.radial_segments = 5
	_mesh_shin.material = _sm_skin

	_mesh_foot = SphereMesh.new()
	_mesh_foot.radius = 0.012
	_mesh_foot.height = 0.032
	_mesh_foot.radial_segments = 5
	_mesh_foot.rings = 3
	_mesh_foot.material = _sm_skin

	# Segmentos cilíndricos de cola anillada larga
	_mesh_tail = CylinderMesh.new()
	_mesh_tail.top_radius = 0.012
	_mesh_tail.bottom_radius = 0.016
	_mesh_tail.height = 0.14
	_mesh_tail.radial_segments = 6
	_mesh_tail.material = _sm_skin
	_mesh_shared_ok = true


func setup_rat(p_root: Node3D, p_terrain: Node3D, p_bounds: AABB) -> void:
	rock = p_root
	terrain = p_terrain
	bounds_override = p_bounds
	rng.randomize()
	_measure()
	_ensure_shared()
	# Tamaño proporcionado a la escala del mapa: roedor ágil y pequeño
	size = rng.randf_range(0.45, 0.65)
	walk_speed = size * rng.randf_range(3.2, 4.8)
	_build()
	idle_time = rng.randf_range(0.3, 1.8)
	_next_sniff_at = rng.randf_range(4.0, 10.0)


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
	idle_time = rng.randf_range(0.6, 2.4)


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
	if _pause_left > 0.0:
		_pause_left -= delta
		_sniffing = true
		phase += delta * 7.0
		_apply_ground(delta)
		_apply_transform()
		_animate(delta)
		if _pause_left <= 0.0:
			_sniffing = false
		return
	_sniffing = false
	if walking:
		var flat := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
		var dist := flat.length()
		if dist < size * 0.4:
			walking = false
			idle_time = rng.randf_range(0.9, 3.2)
			_walked = 0.0
			_next_sniff_at = rng.randf_range(6.0, 16.0)
		else:
			var dir := flat / dist
			var step := walk_speed * _walk_speed_scale() * delta
			pos += dir * step
			_walked += step
			phase += delta * (walk_speed / size) * 3.5
			yaw = _lerp_yaw(yaw, atan2(dir.x, dir.z), minf(1.0, delta * 7.0))
			if _walked >= _next_sniff_at and dist > size * 4.0:
				_walked = 0.0
				_next_sniff_at = rng.randf_range(8.0, 20.0)
				_pause_left = rng.randf_range(0.9, 2.2)
				_sniffing = true
				return
	else:
		idle_time -= delta
		phase += delta * 1.4
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


func _build() -> void:
	_ensure_shared()
	var L := size

	body_node = Node3D.new()
	add_child(body_node)

	# Cuerpo arqueado y esbelto de rata: más estrecho adelante, ensanchado en las caderas traseras
	var body := _mk(_mesh_body, Vector3(0.0, L * 0.18, -L * 0.05), Vector3(L * 0.82, L * 0.75, L * 2.3))
	body_node.add_child(body)

	head_node = Node3D.new()
	head_node.position = Vector3(0.0, L * 0.19, L * 0.28)
	body_node.add_child(head_node)

	# Cabeza alargada
	var head := _mk(_mesh_head, Vector3.ZERO, Vector3(L * 0.72, L * 0.68, L * 1.5))
	head_node.add_child(head)

	# Hocico puntiagudo característico de roedor
	var snout := _mk(_mesh_head, Vector3(0.0, -L * 0.02, L * 0.14), Vector3(L * 0.38, L * 0.32, L * 0.70))
	head_node.add_child(snout)

	# Nariz pequeña rosada
	var nose := _mk(_mesh_nose, Vector3(0.0, -L * 0.02, L * 0.22), Vector3(L * 0.8, L * 0.8, L * 0.8))
	head_node.add_child(nose)

	# Ojos laterales oscuros
	for side in [-1.0, 1.0]:
		var eye := _mk(_mesh_eye, Vector3(side * L * 0.065, L * 0.035, L * 0.08), Vector3(L, L, L))
		head_node.add_child(eye)

		# Orejas redondeadas y translúcidas bien posicionadas arriba y atrás
		var ear := _mk(_mesh_ear, Vector3(side * L * 0.075, L * 0.09, -L * 0.03), Vector3(L * 1.1, L * 1.1, L * 0.25), Vector3(-0.15, side * 0.35, -side * 0.25))
		head_node.add_child(ear)
		ears.append(ear)

	# Patas: delanteras más cortas, traseras musculosas y flexionadas cerca del suelo
	var leg_data := [
		[-1.0, 1.0],  # Delantera izq
		[1.0, 1.0],   # Delantera der
		[-1.0, -1.0], # Trasera izq
		[1.0, -1.0],  # Trasera der
	]
	for ld in leg_data:
		var side: float = ld[0]
		var fz: float = ld[1]
		var is_back := fz < 0.0
		var hip := Node3D.new()
		hip.position = Vector3(side * L * (0.085 if is_back else 0.07), L * 0.14, fz * L * (0.17 if is_back else 0.14))
		add_child(hip)
		hips.append(hip)
		leg_sides.append(side)

		if is_back:
			var haunch := _mk(_mesh_haunch, Vector3(side * L * 0.015, -L * 0.01, -L * 0.01), Vector3(L * 0.65, L * 0.95, L * 1.1))
			hip.add_child(haunch)

		var shin_h := L * (0.13 if is_back else 0.10)
		var shin := _mk(_mesh_shin, Vector3(side * L * 0.02, -shin_h * 0.50, fz * L * 0.005), Vector3(L, shin_h / (L * 0.12), L), Vector3(-fz * 0.12, 0.0, -side * 0.10))
		hip.add_child(shin)

		var foot := _mk(_mesh_foot, Vector3(side * L * 0.025, -shin_h * 0.98, fz * L * 0.025), Vector3(L * 0.80, L * 0.35, L * (1.9 if is_back else 1.5)))
		hip.add_child(foot)

	# Cola auténtica de rata: larga, delgada y segmentada (7 eslabones continuos con curvatura natural)
	var seg_count := 7
	for i in seg_count:
		var seg := Node3D.new()
		seg.position = Vector3(0.0, L * 0.12, -L * (0.28 + 0.10 * float(i)))
		add_child(seg)
		var taper: float = 1.0 - (float(i) / float(seg_count)) * 0.65
		var tip := _mk(_mesh_tail, Vector3.ZERO, Vector3(L * taper, L * taper, L * 0.9), Vector3(PI * 0.5, 0.0, 0.0))
		seg.add_child(tip)
		tail_segs.append(seg)


func _animate(delta: float) -> void:
	var L := size
	var want := 0.0
	if _sniffing:
		want = 0.0
	elif walking:
		want = 0.55
	_amp = lerpf(_amp, want, minf(1.0, delta * 10.0))
	var gait := [0.0, PI, PI, 0.0]
	for i in hips.size():
		var s := sin(phase + gait[i])
		hips[i].rotation.x = s * _amp
		hips[i].rotation.z = leg_sides[i] * maxf(0.0, s) * _amp * 0.45
	var bob := 0.0
	if walking and not _sniffing:
		bob = absf(sin(phase * 2.0)) * L * 0.035
	body_node.position.y = lerpf(body_node.position.y, bob, minf(1.0, delta * 12.0))
	
	# Ondulación fluida de la cola según la velocidad de carrera o curiosidad
	var tail_speed := 1.2 if walking else 0.5
	if _sniffing:
		tail_speed = 0.35
	for i in tail_segs.size():
		var f := float(i + 1) / float(tail_segs.size())
		var sway := sin(phase * 0.95 - f * 2.2) * L * (0.05 + 0.15 * f) * tail_speed
		var sag := sin(phase * 1.9 - f * 1.5) * L * 0.02 * f
		tail_segs[i].position.x = lerpf(tail_segs[i].position.x, sway, minf(1.0, delta * 10.0))
		tail_segs[i].position.y = lerpf(tail_segs[i].position.y, L * 0.12 - (f * f * L * 0.05) + sag, minf(1.0, delta * 10.0))
	if _sniffing:
		var sniff_nod := sin(phase * 11.0) * 0.18 + 0.08
		head_node.rotation.x = lerpf(head_node.rotation.x, sniff_nod, minf(1.0, delta * 14.0))
		head_node.rotation.y = lerpf(head_node.rotation.y, sin(phase * 5.0) * 0.28, minf(1.0, delta * 9.0))
	elif walking:
		var hp := absf(sin(phase * 2.0)) * 0.04
		head_node.rotation.x = lerpf(head_node.rotation.x, hp, minf(1.0, delta * 8.0))
		head_node.rotation.y = lerpf(head_node.rotation.y, 0.0, minf(1.0, delta * 8.0))
	else:
		var hpi := sin(phase * 0.9) * 0.08
		head_node.rotation.x = lerpf(head_node.rotation.x, hpi, minf(1.0, delta * 8.0))
		head_node.rotation.y = lerpf(head_node.rotation.y, sin(phase * 0.5) * 0.15, minf(1.0, delta * 6.0))
	_ear_timer -= delta
	if _ear_timer <= 0.0:
		_ear_timer = rng.randf_range(1.0, 3.0)
		_ear_twitch = 1.0
	_ear_twitch = maxf(0.0, _ear_twitch - delta * 6.0)
	var ear_boost := 1.25 if _sniffing else 1.0
	for e in ears:
		e.scale = Vector3(size * 1.05, (1.0 + _ear_twitch * 0.40) * ear_boost * size * 1.05, size * 0.30)
	if not walking and not _sniffing:
		var br := 1.0 + sin(phase * 0.8) * 0.015
		body_node.scale = Vector3(br, br, 1.0)

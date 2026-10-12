extends Node3D

const RAY_MASK := 1 << 29

var rock: Node3D
var size := 0.25
var walk_speed := 0.5
var pos := Vector3.ZERO
var yaw := 0.0
var up := Vector3.UP
var walking := false
var idle_time := 0.0
var target := Vector3.ZERO
var phase := 0.0
var world_aabb := AABB()
var rng := RandomNumberGenerator.new()
var _placed := false

# Optimización: Culling por rango de visión del jugador y cámara
var _is_in_player_vision: bool = true
var _vision_check_timer: float = 0.0
var _cached_player: Node2D = null
var _scale_factor_cached: float = 0.02
var _correction_z_cached: float = 1.4142


func setup(p_rock: Node3D) -> void:
	rock = p_rock
	rng.randomize()
	_read_map_scale_factors()
	_vision_check_timer = rng.randf_range(0.0, 0.25)
	_measure()
	var w: float = maxf(world_aabb.size.x, world_aabb.size.z)
	var rng_size := _size_range()
	size = w * rng.randf_range(rng_size[0], rng_size[1])
	var clamp_r := _size_clamp()
	size = clampf(size, clamp_r[0], clamp_r[1])
	walk_speed = size * rng.randf_range(1.4, 2.4)
	_build()
	idle_time = rng.randf_range(0.4, 2.2)


func _size_range() -> Array:
	return [0.07, 0.10]


func _size_clamp() -> Array:
	return [0.10, 0.30]


func _walk_speed_scale() -> float:
	return 1.0


func _measure() -> void:
	var first := true
	var total := AABB()
	var stack: Array[Node] = [rock]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var wa: AABB = mi.global_transform * mi.get_aabb()
			if first:
				total = wa
				first = false
			else:
				total = total.merge(wa)
		for c in n.get_children():
			if c is Node3D:
				stack.append(c)
	if first:
		var p: Vector3 = rock.global_position
		total = AABB(p - Vector3(0.5, 0.5, 0.5), Vector3.ONE)
	world_aabb = total


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

	if walking:
		var flat := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
		var dist := flat.length()
		if dist < size * 0.4:
			walking = false
			idle_time = rng.randf_range(0.9, 3.2)
		else:
			var dir := flat / dist
			pos += dir * (walk_speed * _walk_speed_scale() * delta)
			phase += delta * (walk_speed / size) * 3.5
			yaw = _lerp_yaw(yaw, atan2(dir.x, dir.z), minf(1.0, delta * 7.0))
	else:
		idle_time -= delta
		phase += delta * 1.4
		if idle_time <= 0.0:
			_pick_target()
	var hit := _ray_down(pos.x, pos.z)
	if not hit.is_empty():
		pos.y = lerpf(pos.y, hit["position"].y, minf(1.0, delta * 12.0))
		var norm: Vector3 = hit["normal"]
		if norm.length_squared() > 0.001:
			up = up.lerp(norm.normalized(), minf(1.0, delta * 5.0)).normalized()
	_apply_transform()
	_animate(delta)


func _place_initial() -> void:
	_pick_target()
	if walking:
		pos = target
	else:
		pos = world_aabb.get_center()
	var hit := _ray_down(pos.x, pos.z)
	if not hit.is_empty():
		pos = hit["position"]
		var norm: Vector3 = hit["normal"]
		if norm.length_squared() > 0.001:
			up = norm.normalized()
		else:
			up = Vector3.UP
	else:
		up = Vector3.UP
	yaw = rng.randf_range(0.0, TAU)
	_apply_transform()
	_placed = true
	_read_map_scale_factors()
	_is_in_player_vision = _check_in_player_vision()
	visible = _is_in_player_vision


func _pick_target() -> void:
	var inset_x := world_aabb.size.x * 0.15
	var inset_z := world_aabb.size.z * 0.15
	for i in 8:
		var x := rng.randf_range(world_aabb.position.x + inset_x, world_aabb.end.x - inset_x)
		var z := rng.randf_range(world_aabb.position.z + inset_z, world_aabb.end.z - inset_z)
		var hit := _ray_down(x, z)
		if not hit.is_empty():
			target = hit["position"]
			walking = true
			return
	walking = false
	idle_time = rng.randf_range(0.6, 2.4)


func _ray_down(x: float, z: float) -> Dictionary:
	var from := Vector3(x, world_aabb.end.y + size * 3.0 + 0.5, z)
	var to := Vector3(x, world_aabb.position.y - size - 0.5, z)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, RAY_MASK)
	return space.intersect_ray(q)


func _apply_transform() -> void:
	var upn := up.normalized() if up.length_squared() > 0.001 else Vector3.UP
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := upn.cross(fwd)
	if right.length_squared() < 0.0001:
		right = upn.cross(Vector3.RIGHT)
		if right.length_squared() < 0.0001:
			right = upn.cross(Vector3.FORWARD)
	right = right.normalized()
	var f2 := right.cross(upn).normalized()
	global_transform = Transform3D(Basis(right, upn, f2), pos)


func _lerp_yaw(from: float, to: float, t: float) -> float:
	var diff := fmod(to - from, TAU)
	if diff > PI:
		diff -= TAU
	elif diff < -PI:
		diff += TAU
	return from + diff * t


func _build() -> void:
	pass


func _animate(_delta: float) -> void:
	pass


func _read_map_scale_factors() -> void:
	var p: Node = get_parent()
	while p:
		if p.has_meta("correction_z"):
			_correction_z_cached = p.get_meta("correction_z")
		if "scale_factor" in p:
			_scale_factor_cached = p.scale_factor
		p = p.get_parent()


func _check_in_player_vision() -> bool:
	if not is_inside_tree():
		return false

	# 1. Localizar al jugador local si no está cacheado
	if not is_instance_valid(_cached_player):
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0 and is_instance_valid(players[0]):
			_cached_player = players[0]

	var my_pos := global_position if _placed else pos
	var max_vision_dist := 34.0 # Fallback 3D (aprox 1700px 2D)

	if is_instance_valid(_cached_player):
		var vr_2d := 1300.0
		if "vision_range" in _cached_player:
			vr_2d = float(_cached_player.vision_range)
		max_vision_dist = (vr_2d * _scale_factor_cached) + 8.0

		var p_pos_3d := Vector3.ZERO
		var wr3d = _cached_player.get("world_root_3d")
		if is_instance_valid(wr3d):
			p_pos_3d = wr3d.global_position
		else:
			var p2d: Vector2 = _cached_player.global_position
			p_pos_3d = Vector3(p2d.x * _scale_factor_cached, my_pos.y, p2d.y * _scale_factor_cached * _correction_z_cached)

		# Margen de histéresis: si ya era visible, tolerancia extra de 4m para evitar flickering al borde
		var threshold := max_vision_dist if not _is_in_player_vision else (max_vision_dist + 4.0)
		var dist_h := Vector2(my_pos.x - p_pos_3d.x, (my_pos.z - p_pos_3d.z) / _correction_z_cached).length()
		if dist_h <= threshold:
			return true

	# 2. Compatibilidad con Cámara Libre (Free Camera / Orbit) o cámara activa
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if is_instance_valid(cam):
		var cam_pos := cam.global_position
		var dist_cam := my_pos.distance_to(cam_pos)
		if dist_cam <= (max_vision_dist + 12.0):
			if cam.is_position_in_frustum(my_pos):
				return true

	return false

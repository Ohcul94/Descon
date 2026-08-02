extends Node2D

# WormVisual.gd (v1.1 - Gusano Bumerán / Worm Boomerang)
# Visual determinístico del gusano: IDA -> PARQUEO -> VUELTA con homing
# hacia la posición ACTUAL del enemigo (el servidor aplica el daño con el mismo criterio).

var worm_data: Dictionary = {}
var map_node: Node = null
var enemy_node: Node = null

# Parámetros derivados
var _start_pos := Vector2.ZERO
var _dir := Vector2.RIGHT
var _perp := Vector2.DOWN
var _speed := 0.0
var _range := 0.0
var _park_time := 0.0
var _phase := "out"
var _dist := 0.0
var _park_timer := 0.0

# Visual 2D
var _body: Line2D = null
var _segment_count := 9
var _segment_spacing := 8.0
var _amp := 5.0

# Visual 3D (overlay en sub_viewport del mapa)
var world_root_3d: Node3D = null
var _segments_3d: Array = []
var _y_3d := 1.2

func setup(p_data: Dictionary, p_map: Node, p_enemy: Node = null) -> void:
	worm_data = p_data
	map_node = p_map
	enemy_node = p_enemy

	_start_pos = Vector2(float(p_data.get("startX", 0.0)), float(p_data.get("startY", 0.0)))
	var angle := float(p_data.get("angle", 0.0))
	_dir = Vector2.RIGHT.rotated(angle)
	_perp = Vector2(-_dir.y, _dir.x)
	_speed = float(p_data.get("speed", 600.0))
	_range = float(p_data.get("range", 600.0))
	_park_time = float(p_data.get("parkTimeMs", 1000.0)) / 1000.0

	global_position = _start_pos
	rotation = angle

	_build_2d_body()
	_build_3d_body()

func _build_2d_body() -> void:
	_body = Line2D.new()
	_body.width = 7.0
	_body.default_color = Color(0.22, 1.0, 0.35, 0.95)
	_body.joint_mode = Line2D.LINE_JOINT_ROUND
	_body.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_body.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(_body)

func _build_3d_body() -> void:
	if not is_instance_valid(map_node):
		return
	if not map_node.get("sub_viewport"):
		return
	var target_vp = map_node.sub_viewport
	world_root_3d = Node3D.new()
	world_root_3d.name = "Worm3D_" + str(get_instance_id())
	target_vp.add_child(world_root_3d)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 1.0, 0.35)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 1.0, 0.35)
	mat.emission_energy_multiplier = 3.0

	for i in _segment_count:
		var seg := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.055
		sphere.height = 0.11
		seg.mesh = sphere
		seg.material_override = mat
		world_root_3d.add_child(seg)
		_segments_3d.append(seg)

	tree_exiting.connect(func():
		if is_instance_valid(world_root_3d):
			world_root_3d.queue_free()
	)

func _process(delta: float) -> void:
	match _phase:
		"out":
			_dist += _speed * delta
			if _dist >= _range:
				_dist = _range
				_phase = "park"
				_park_timer = _park_time
			global_position = _start_pos + _dir * _dist
		"park":
			_park_timer -= delta
			if _park_timer <= 0.0:
				_phase = "return"
		"return":
			# v372.2: Homing hacia la posición ACTUAL del enemigo (donde se movió)
			var target := _start_pos
			if is_instance_valid(enemy_node):
				target = enemy_node.global_position
			var to_target := target - global_position
			var dist_to_target := to_target.length()
			var step := _speed * delta
			if dist_to_target <= maxf(step, 18.0):
				_finish()
				return
			_dir = to_target.normalized()
			_perp = Vector2(-_dir.y, _dir.x)
			global_position += _dir * step
			rotation = _dir.angle()

	_sync_body()
	queue_redraw()

func _sync_body() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var pts := PackedVector2Array()
	for i in _segment_count:
		var lx := -float(i) * _segment_spacing
		var ly := sin(t * 9.0 + float(i) * 0.9) * _amp
		pts.append(Vector2(lx, ly))
	if is_instance_valid(_body):
		_body.points = pts

	if not is_instance_valid(world_root_3d):
		return
	if _segments_3d.size() == 0:
		return

	var s_factor := 0.02
	var correction_z := 1.41421356
	if is_instance_valid(map_node):
		if "scale_factor" in map_node:
			s_factor = map_node.scale_factor
		if "correction_z" in map_node:
			correction_z = map_node.correction_z

	if is_instance_valid(enemy_node) and is_instance_valid(enemy_node.get("world_root_3d")):
		_y_3d = enemy_node.world_root_3d.position.y
	else:
		_y_3d = 1.2

	for i in _segment_count:
		var lx := -float(i) * _segment_spacing
		var ly := sin(t * 9.0 + float(i) * 0.9) * _amp
		var seg_pos_2d := global_position + _dir * lx + _perp * ly
		var seg_pos_3d := Vector3(
			seg_pos_2d.x * s_factor,
			_y_3d,
			seg_pos_2d.y * s_factor * correction_z
		)
		if is_instance_valid(_segments_3d[i]):
			_segments_3d[i].position = seg_pos_3d

func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	draw_circle(Vector2.ZERO, 6.0, Color(0.3, 1.0, 0.45, 1.0))
	draw_circle(Vector2.ZERO, 2.8, Color(1.0, 1.0, 0.9, 1.0))
	draw_arc(Vector2.ZERO, 9.0 + sin(t * 6.0) * 1.5, 0.0, TAU, 16, Color(0.2, 1.0, 0.35, 0.35), 2.0, true)

func _finish() -> void:
	if is_instance_valid(VFXSystem):
		VFXSystem.spawn_explosion(global_position, 0.8)
	queue_free()

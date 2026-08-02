extends Node2D

# WindWallVisual.gd (v1.1 - Aluvión de Viento / Wind Wall)
# La pared aparece en el enemigo durante la carga (FASE 1) y al completarse
# el casteo el servidor envía wind_fire y la pared "launch" viaja hacia afuera
# hasta su rango. El daño/expulsión/debuffs los aplica el servidor (BaseAI wind_wall).

var wall_data: Dictionary = {}
var map_node: Node = null
var enemy_node: Node = null

var _start_pos := Vector2.ZERO
var _dir := Vector2.RIGHT
var _perp := Vector2.DOWN
var _speed := 0.0
var _range := 0.0
var _width := 0.0
var _elapsed := 0.0

var _phase := "charge"
var _launched := false
var _charge_time := 0.0
var _charge_duration := 2.0
var _launch_offset := 50.0

# Visual 2D
var _band: Polygon2D = null
var _spine: Line2D = null

# Visual 3D (overlay en sub_viewport del mapa)
var world_root_3d: Node3D = null
var _sheet_3d: MeshInstance3D = null
var _sheet_mat: StandardMaterial3D = null

func setup(p_data: Dictionary, p_map: Node, p_enemy: Node = null) -> void:
	wall_data = p_data
	map_node = p_map
	enemy_node = p_enemy

	_start_pos = Vector2(float(p_data.get("x", float(p_data.get("startX", 0.0)))), float(p_data.get("y", float(p_data.get("startY", 0.0)))))
	var angle := float(p_data.get("angle", 0.0))
	_dir = Vector2.RIGHT.rotated(angle)
	_perp = Vector2(-_dir.y, _dir.x)
	_speed = float(p_data.get("speed", 500.0))
	_range = float(p_data.get("range", 500.0))
	_width = float(p_data.get("width", 140.0))
	_charge_duration = maxf(float(p_data.get("duration", 2000.0)) / 1000.0, 0.1)
	_launch_offset = float(p_data.get("launchOffset", 50.0))
	_phase = "charge" if p_data.get("mode", "charge") == "charge" else "moving"
	_launched = _phase == "moving"

	global_position = _start_pos
	rotation = angle

	_build_2d_body()
	_build_3d_body()

func launch() -> void:
	if _launched:
		return
	_launched = true
	_phase = "moving"
	_start_pos = global_position
	_elapsed = 0.0
	if is_instance_valid(_sheet_3d):
		_sheet_3d.scale = Vector3.ONE

func _build_2d_body() -> void:
	var hw := _width / 2.0
	_band = Polygon2D.new()
	_band.z_index = -1
	_band.color = Color(0.72, 0.95, 1.0, 0.22)
	_band.polygon = PackedVector2Array([Vector2(-4.0, -hw), Vector2(4.0, -hw), Vector2(4.0, hw), Vector2(-4.0, hw)])
	add_child(_band)

	_spine = Line2D.new()
	_spine.width = 7.0
	_spine.default_color = Color(0.85, 0.98, 1.0, 0.6)
	_spine.joint_mode = Line2D.LINE_JOINT_ROUND
	_spine.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_spine.end_cap_mode = Line2D.LINE_CAP_ROUND
	_spine.points = PackedVector2Array([Vector2(0, -hw), Vector2(0, hw)])
	add_child(_spine)

func _build_3d_body() -> void:
	if not is_instance_valid(map_node):
		return
	if not map_node.get("sub_viewport"):
		return
	world_root_3d = Node3D.new()
	world_root_3d.name = "WindWall3D_" + str(get_instance_id())
	map_node.sub_viewport.add_child(world_root_3d)

	var s_factor := 0.02
	if is_instance_valid(map_node):
		if "scale_factor" in map_node:
			s_factor = map_node.scale_factor

	_sheet_3d = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(_width * s_factor, 2.2, 0.16)
	_sheet_3d.mesh = box
	_sheet_setup_mat()
	world_root_3d.add_child(_sheet_3d)

	tree_exiting.connect(func():
		if is_instance_valid(world_root_3d):
			world_root_3d.queue_free()
	)

func _sheet_setup_mat() -> void:
	_sheet_mat = StandardMaterial3D.new()
	_sheet_mat.albedo_color = Color(0.82, 0.97, 1.0, 0.55)
	_sheet_mat.emission_enabled = true
	_sheet_mat.emission = Color(0.7, 0.95, 1.0)
	_sheet_mat.emission_energy_multiplier = 1.4
	_sheet_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_sheet_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_sheet_3d.material_override = _sheet_mat

func _process(delta: float) -> void:
	if _phase == "charge":
		_charge_time += delta
		var progress := clampf(_charge_time / _charge_duration, 0.0, 1.0)
		# La pared sigue al enemigo (adelantada) mientras carga
		if is_instance_valid(enemy_node):
			global_position = enemy_node.global_position + _dir * _launch_offset
		if is_instance_valid(_band):
			_band.color.a = lerpf(0.14, 0.35, progress)
		if is_instance_valid(_spine):
			_spine.default_color.a = lerpf(0.35, 0.8, progress)
		if is_instance_valid(_sheet_mat):
			_sheet_mat.emission_energy_multiplier = lerpf(0.8, 2.6, progress)
		if is_instance_valid(world_root_3d):
			world_root_3d.scale.x = lerpf(0.55, 1.0, progress)
		_sync_3d()
		queue_redraw()
		return

	_elapsed += delta
	var traveled := _speed * _elapsed
	if traveled >= _range:
		traveled = _range
		global_position = _start_pos + _dir * traveled
		_finish()
		return
	global_position = _start_pos + _dir * traveled
	_sync_3d()
	queue_redraw()

func _sync_3d() -> void:
	if not is_instance_valid(world_root_3d) or not is_instance_valid(map_node):
		return
	var s_factor := 0.02
	var correction_z := 1.41421356
	if is_instance_valid(map_node):
		if "scale_factor" in map_node:
			s_factor = map_node.scale_factor
		if "correction_z" in map_node:
			correction_z = map_node.correction_z

	var y_3d := 1.15
	if is_instance_valid(enemy_node) and is_instance_valid(enemy_node.get("world_root_3d")):
		y_3d = enemy_node.world_root_3d.position.y

	world_root_3d.position = Vector3(global_position.x * s_factor, y_3d, global_position.y * s_factor * correction_z)
	var diff_3d := Vector3(_dir.x * s_factor, 0.0, _dir.y * s_factor * correction_z)
	world_root_3d.rotation.y = atan2(-diff_3d.x, -diff_3d.z)

func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var hw := _width / 2.0
	# Remolinos/estrías que viajan a lo largo de la pared
	for i in 6:
		var base_y := lerpf(-hw, hw, (i + 0.5) / 6.0)
		var off := fmod(t * 24.0 + float(i) * 0.6, 1.0)
		var x0 := -30.0 + off * 60.0
		draw_line(Vector2(x0, base_y), Vector2(x0 + 8.0, base_y), Color(0.9, 1.0, 1.0, 0.35 - float(i) * 0.04), 2.5)
	draw_arc(Vector2.ZERO, 10.0 + sin(t * 7.0) * 1.0, 0.0, TAU, 12, Color(0.7, 0.95, 1.0, 0.3), 2.0, true)

func _finish() -> void:
	if is_instance_valid(_band):
		_band.queue_free()
	if is_instance_valid(VFXSystem):
		VFXSystem.spawn_explosion(global_position, 0.9)
	queue_free()

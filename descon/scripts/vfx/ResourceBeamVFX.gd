extends Node3D

# ResourceBeamVFX.gd
# Rayo volumétrico 3D de extracción de plasma celeste entre la nave y el nodo de recurso en el piso.
# Conecta la posición 3D real de la nave con la posición 3D real del recurso sobre el terreno,
# con haz de plasma aditivo, núcleo incandescente, destello en el impacto y motes de materia.

var resource_node: Node2D = null
var player_node: Node2D = null
var active: bool = false

var elapsed: float = 0.0
var progress: float = 0.0

var _beam_holder: Node3D = null
var _glow_cyl: MeshInstance3D = null
var _main_cyl: MeshInstance3D = null
var _core_cyl: MeshInstance3D = null

var _glow_mat: StandardMaterial3D = null
var _main_mat: StandardMaterial3D = null
var _core_mat: StandardMaterial3D = null

var _ship_flash: MeshInstance3D = null
var _ground_flash: MeshInstance3D = null
var _ground_light: OmniLight3D = null

var _motes: Array = []
const MOTE_COUNT: int = 6

func _ready():
	_build_beam_mesh()

func _build_beam_mesh() -> void:
	_beam_holder = Node3D.new()
	_beam_holder.name = "BeamHolder"
	add_child(_beam_holder)

	# 1. Haz exterior de plasma (Glow)
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow_mat.albedo_color = Color(0.18, 0.72, 1.0, 0.45)
	_glow_mat.emission_enabled = true
	_glow_mat.emission = Color(0.15, 0.7, 1.0)
	_glow_mat.emission_energy_multiplier = 4.5

	_glow_cyl = MeshInstance3D.new()
	var g_mesh = CylinderMesh.new()
	g_mesh.top_radius = 0.22
	g_mesh.bottom_radius = 0.26
	g_mesh.radial_segments = 10
	_glow_cyl.mesh = g_mesh
	_glow_cyl.material_override = _glow_mat
	_glow_cyl.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_beam_holder.add_child(_glow_cyl)

	# 2. Haz intermedio eléctrico
	_main_mat = StandardMaterial3D.new()
	_main_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_main_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_main_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_main_mat.albedo_color = Color(0.35, 0.88, 1.0, 0.85)
	_main_mat.emission_enabled = true
	_main_mat.emission = Color(0.3, 0.85, 1.0)
	_main_mat.emission_energy_multiplier = 7.0

	_main_cyl = MeshInstance3D.new()
	var m_mesh = CylinderMesh.new()
	m_mesh.top_radius = 0.10
	m_mesh.bottom_radius = 0.12
	m_mesh.radial_segments = 8
	_main_cyl.mesh = m_mesh
	_main_cyl.material_override = _main_mat
	_main_cyl.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_beam_holder.add_child(_main_cyl)

	# 3. Núcleo incandescente
	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_core_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_core_mat.albedo_color = Color(0.95, 0.98, 1.0, 1.0)
	_core_mat.emission_enabled = true
	_core_mat.emission = Color(0.9, 0.98, 1.0)
	_core_mat.emission_energy_multiplier = 12.0

	_core_cyl = MeshInstance3D.new()
	var c_mesh = CylinderMesh.new()
	c_mesh.top_radius = 0.04
	c_mesh.bottom_radius = 0.04
	c_mesh.radial_segments = 6
	_core_cyl.mesh = c_mesh
	_core_cyl.material_override = _core_mat
	_core_cyl.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_beam_holder.add_child(_core_cyl)

	# 4. Destello en la nave (emisor)
	_ship_flash = MeshInstance3D.new()
	var s_mesh = SphereMesh.new()
	s_mesh.radius = 0.22
	s_mesh.height = 0.44
	_ship_flash.mesh = s_mesh
	_ship_flash.material_override = _main_mat
	add_child(_ship_flash)

	# 5. Destello e impacto en el recurso (receptor en el piso)
	_ground_flash = MeshInstance3D.new()
	var gf_mesh = SphereMesh.new()
	gf_mesh.radius = 0.35
	gf_mesh.height = 0.70
	_ground_flash.mesh = gf_mesh
	_ground_flash.material_override = _glow_mat
	add_child(_ground_flash)

	_ground_light = OmniLight3D.new()
	_ground_light.light_color = Color(0.25, 0.82, 1.0)
	_ground_light.light_energy = 3.5
	_ground_light.omni_range = 8.0
	add_child(_ground_light)

	# 6. Motes de extracción que viajan desde el suelo a la nave
	_motes.clear()
	for i in range(MOTE_COUNT):
		var mi = MeshInstance3D.new()
		var sp = SphereMesh.new()
		sp.radius = 0.08
		sp.height = 0.16
		mi.mesh = sp
		mi.material_override = _core_mat
		_beam_holder.add_child(mi)
		_motes.append({
			"node": mi,
			"t": float(i) / float(MOTE_COUNT),
			"speed": randf_range(0.85, 1.35)
		})

func setup(p_resource_node: Node2D, p_player_node: Node2D) -> void:
	resource_node = p_resource_node
	player_node = p_player_node
	active = is_instance_valid(resource_node) and is_instance_valid(player_node)
	visible = active
	set_process(active)

func set_progress(p: float) -> void:
	progress = clampf(p, 0.0, 1.0)

func _process(delta: float) -> void:
	if not active:
		return
	if not is_instance_valid(resource_node) or not is_instance_valid(player_node):
		fade_out_and_free()
		return

	# Si el recurso dejó de canalizar o se desactivó
	if not resource_node.get("collecting"):
		fade_out_and_free()
		return

	elapsed += delta

	# Apuntar la nave hacia el recurso en coordenadas 2D suavemente
	var diff_2d = resource_node.global_position - player_node.global_position
	if diff_2d.length_squared() > 1.0:
		var target_ang = diff_2d.angle()
		player_node.rotation = lerp_angle(player_node.rotation, target_ang, 12.0 * delta)

	# Obtener posiciones 3D exactas
	var map = get_tree().get_first_node_in_group("map")
	var s_factor: float = map.scale_factor if (is_instance_valid(map) and "scale_factor" in map) else 0.02
	var c_z: float = map.correction_z if (is_instance_valid(map) and "correction_z" in map) else 1.41421356

	# 1. Posición 3D del emisor (la nave)
	var p_pos_3d: Vector3 = Vector3.ZERO
	if is_instance_valid(player_node.get("world_root_3d")):
		p_pos_3d = player_node.world_root_3d.global_position + Vector3(0.0, -0.15, 0.0)
	else:
		var h_p = _get_terrain_h(map, player_node.global_position) + 2.2
		p_pos_3d = Vector3(player_node.global_position.x * s_factor, h_p, player_node.global_position.y * s_factor * c_z)

	# 2. Posición 3D del receptor (el recurso en el piso)
	var r_pos_3d: Vector3 = Vector3.ZERO
	if is_instance_valid(resource_node.get("world_root_3d")):
		r_pos_3d = resource_node.world_root_3d.global_position + Vector3(0.0, 0.45, 0.0)
	else:
		var h_r = _get_terrain_h(map, resource_node.global_position) + 0.45
		r_pos_3d = Vector3(resource_node.global_position.x * s_factor, h_r, resource_node.global_position.y * s_factor * c_z)

	# Actualizar destellos en los extremos
	if is_instance_valid(_ship_flash):
		_ship_flash.global_position = p_pos_3d
		var s_pulse = 1.0 + sin(elapsed * 25.0) * 0.18 + progress * 0.4
		_ship_flash.scale = Vector3.ONE * s_pulse
	if is_instance_valid(_ground_flash):
		_ground_flash.global_position = r_pos_3d
		var g_pulse = 1.0 + cos(elapsed * 22.0) * 0.22 + progress * 0.6
		_ground_flash.scale = Vector3.ONE * g_pulse
	if is_instance_valid(_ground_light):
		_ground_light.global_position = r_pos_3d + Vector3(0.0, 0.5, 0.0)
		_ground_light.light_energy = (3.5 + sin(elapsed * 18.0) * 1.0) * (1.0 + progress * 0.5)

	# Orientar y estirar el haz entre p_pos_3d y r_pos_3d
	var diff_3d: Vector3 = r_pos_3d - p_pos_3d
	var dist: float = diff_3d.length()
	if dist < 0.15:
		return

	global_position = p_pos_3d
	var dir_norm = diff_3d / dist
	var up = Vector3.UP
	if absf(dir_norm.dot(up)) > 0.96:
		up = Vector3.FORWARD
	look_at(r_pos_3d, up)

	# Los cilindros están orientados con rotación X = 90° en _beam_holder,
	# por lo que el eje del cilindro se extiende a lo largo del eje local Z.
	# look_at apunta el eje local -Z hacia r_pos_3d, por lo que el centro del cilindro
	# queda en Z = -dist * 0.5
	var half_z = -dist * 0.5
	var jitter = sin(elapsed * 32.0) * 0.04
	var boost = 1.0 + progress * 0.5

	if is_instance_valid(_glow_cyl):
		var gm = _glow_cyl.mesh as CylinderMesh
		if gm:
			gm.height = dist
			gm.top_radius = (0.20 + jitter) * boost
			gm.bottom_radius = (0.26 + jitter) * boost
		_glow_cyl.position = Vector3(0.0, 0.0, half_z)

	if is_instance_valid(_main_cyl):
		var mm = _main_cyl.mesh as CylinderMesh
		if mm:
			mm.height = dist
			mm.top_radius = 0.09 * boost
			mm.bottom_radius = 0.12 * boost
		_main_cyl.position = Vector3(0.0, 0.0, half_z)

	if is_instance_valid(_core_cyl):
		var cm = _core_cyl.mesh as CylinderMesh
		if cm:
			cm.height = dist
			cm.top_radius = 0.04 * boost
			cm.bottom_radius = 0.04 * boost
		_core_cyl.position = Vector3(0.0, 0.0, half_z)

	# Animar motes viajando desde el recurso (-dist) hacia la nave (0.0)
	for m in _motes:
		var mi = m["node"] as MeshInstance3D
		if not is_instance_valid(mi):
			continue
		m["t"] += delta * m["speed"] * 0.65
		if m["t"] > 1.0:
			m["t"] -= 1.0
		# t va de 0.0 (en el recurso) a 1.0 (en la nave)
		var mote_z = lerpf(-dist, 0.0, m["t"])
		var wave_x = sin(elapsed * 12.0 + m["t"] * 8.0) * 0.06
		var wave_y = cos(elapsed * 14.0 + m["t"] * 9.0) * 0.06
		mi.position = Vector3(wave_x, wave_y, mote_z)
		var mote_fade = sin(m["t"] * PI)
		mi.scale = Vector3.ONE * (mote_fade * 1.3)

func _get_terrain_h(map_node: Node, pos_2d: Vector2) -> float:
	if not is_instance_valid(map_node):
		return 0.0
	if map_node.has_method("get_terrain_height_at_pos"):
		return map_node.get_terrain_height_at_pos(pos_2d)
	elif map_node.has_method("get_height_at"):
		return map_node.get_height_at(pos_2d.x, pos_2d.y)
	return 0.0

func fade_out_and_free() -> void:
	if not active:
		return
	active = false
	set_process(false)
	var tw = create_tween().set_parallel(true)
	if is_instance_valid(_glow_mat):
		tw.tween_property(_glow_mat, "albedo_color:a", 0.0, 0.2)
	if is_instance_valid(_main_mat):
		tw.tween_property(_main_mat, "albedo_color:a", 0.0, 0.18)
	if is_instance_valid(_core_mat):
		tw.tween_property(_core_mat, "albedo_color:a", 0.0, 0.15)
	if is_instance_valid(_ground_light):
		tw.tween_property(_ground_light, "light_energy", 0.0, 0.2)
	tw.chain().tween_callback(queue_free)

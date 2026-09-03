extends Node2D
# Visual de Zona Persistente de Meteorito
# Se crea cuando el meteorito cae con persistentZone habilitado.
# Renderiza un disco pulsante en 2D + área 3D en el piso del sub_viewport.
# Se destruye automáticamente al expirar.

var map_node = null
var radius: float = 150.0
var zone_duration: float = 4.0
var zone_tick_ms: float = 1.0
var _elapsed: float = 0.0
var _is_3d: bool = false
var _ground_3d: Node3D = null

const ZONE_COLOR := Color(0.8, 0.25, 0.05, 0.25)
const ZONE_RING_COLOR := Color(0.95, 0.35, 0.08, 0.7)

func setup(data: Dictionary, p_map) -> void:
	map_node = p_map
	radius = float(data.get("radius", 150.0))
	zone_duration = float(data.get("zoneDuration", 4000.0)) / 1000.0
	zone_tick_ms = float(data.get("zoneTickMs", 1000.0)) / 1000.0
	_is_3d = is_instance_valid(map_node) and map_node.get("sub_viewport") != null
	_spawn_ground_area(data)

func _spawn_ground_area(data: Dictionary) -> void:
	if not _is_3d or not is_instance_valid(map_node):
		return
	var s_factor: float = map_node.scale_factor if "scale_factor" in map_node else 0.02
	var correction_z: float = map_node.correction_z if "correction_z" in map_node else 1.41421356
	var vp = map_node.sub_viewport
	if not is_instance_valid(vp):
		return

	var e_x := float(data.get("x", global_position.x))
	var e_y := float(data.get("y", global_position.y))
	var r3d: float = radius * s_factor

	# altura real del terreno como IceStorm / Meteor warning
	var h_zone = 0.05
	if is_instance_valid(map_node.get("terrain_node")):
		var em_n = get_tree().get_first_node_in_group("world_node")
		if em_n and em_n.has_node("EntityManager"):
			var mgr = em_n.get_node("EntityManager")
			if mgr and mgr.has_method("_sample_terrain_height"):
				h_zone = mgr._sample_terrain_height(Vector2(e_x, e_y), map_node) + 0.06
			elif map_node.has_method("get_terrain_height_at_pos"):
				h_zone = map_node.get_terrain_height_at_pos(Vector2(e_x, e_y)) + 0.06
		elif map_node.has_method("get_terrain_height_at_pos"):
			h_zone = map_node.get_terrain_height_at_pos(Vector2(e_x, e_y)) + 0.06

	_ground_3d = Node3D.new()
	_ground_3d.name = "MeteorZone_" + name
	_ground_3d.position = Vector3(e_x * s_factor, h_zone, e_y * s_factor * correction_z)
	vp.add_child(_ground_3d)

	# Disco de área (fuego en el piso) - usar disco conformante si hay terreno como warnings
	var disc := MeshInstance3D.new()
	var disc_mesh: Mesh = CylinderMesh.new()
	disc_mesh.top_radius = r3d
	disc_mesh.bottom_radius = r3d
	disc_mesh.height = 0.01
	if is_instance_valid(map_node.get("terrain_node")):
		var em_n2 = get_tree().get_first_node_in_group("world_node")
		if em_n2 and em_n2.has_node("EntityManager"):
			var mgr2 = em_n2.get_node("EntityManager")
			if mgr2 and mgr2.has_method("_make_circle_disc_conforming"):
				disc_mesh = mgr2._make_circle_disc_conforming(Vector2(e_x, e_y), radius, map_node)
	disc.mesh = disc_mesh
	var disc_mat := StandardMaterial3D.new()
	disc_mat.albedo_color = Color(0.8, 0.25, 0.05, 0.22)
	disc_mat.emission_enabled = true
	disc_mat.emission = Color(0.9, 0.3, 0.08)
	disc_mat.emission_energy_multiplier = 0.8
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc_mat.no_depth_test = true
	disc_mat.render_priority = 2
	disc.material_override = disc_mat
	_ground_3d.add_child(disc)

	# Anillo exterior pulsante - Torus ya es plano XZ, sin PI/2 (como IceStorm correcto)
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = r3d * 0.95
	ring_mesh.outer_radius = r3d
	ring.mesh = ring_mesh
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.95, 0.35, 0.08, 0.6)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.4, 0.1)
	ring_mat.emission_energy_multiplier = 2.0
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.no_depth_test = true
	ring_mat.render_priority = 2
	ring.material_override = ring_mat
	ring.position.y = 0.02
	_ground_3d.add_child(ring)

func _exit_tree() -> void:
	if is_instance_valid(_ground_3d) and is_instance_valid(_ground_3d.get_parent()):
		_ground_3d.queue_free()
	_ground_3d = null

func _process(delta: float) -> void:
	_elapsed += delta

	# Parpadeo del 3D (anillo sube/baja intensidad)
	if _is_3d and is_instance_valid(_ground_3d) and _ground_3d.get_child_count() > 1:
		var ring_inst = _ground_3d.get_child(1)
		if ring_inst is MeshInstance3D and ring_inst.material_override:
			var pulse = 0.5 + 0.5 * sin(_elapsed * 8.0)
			ring_inst.material_override.emission_energy_multiplier = 1.2 + 0.8 * pulse

	# Expiración: fundido a透明 y liberar
	if _elapsed >= zone_duration:
		var tw = create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.5)
		tw.finished.connect(queue_free)
		set_process(false)
		return

	queue_redraw()

func _draw() -> void:
	# Disco de fuego pulsante (2D)
	var pulse = 0.5 + 0.5 * sin(_elapsed * 7.0)
	draw_circle(Vector2.ZERO, radius, Color(0.8, 0.25, 0.05, 0.15 + 0.10 * pulse))
	# Anillo exterior
	draw_arc(Vector2.ZERO, radius, 0, TAU, 64, Color(0.95, 0.35, 0.08, 0.6 + 0.3 * pulse), 4.0, true)
	# Anillo interior decorativo
	draw_arc(Vector2.ZERO, radius * 0.6, 0, TAU, 48, Color(0.9, 0.4, 0.1, 0.3 + 0.2 * pulse), 2.0, true)

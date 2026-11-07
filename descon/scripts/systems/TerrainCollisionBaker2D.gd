@tool
class_name TerrainCollisionBaker2D
extends RefCounted

## TerrainCollisionBaker2D
## Módulo de calidad AAA para muestrear alturas de Terrain 3D y generar
## colisiones físicas 2D (StaticBody2D + CollisionPolygon2D) automáticas
## compatibles con la proyección isométrica 2.5D del proyecto.

const DEFAULT_SCALE_FACTOR: float = 0.02
const DEFAULT_CORRECTION_Z: float = 1.41421356
const CONTAINER_NODE_NAME: String = "TerrainColliders"

## Muestrea el nodo Terrain3D y genera un Array de PackedVector2Array con las coordenadas lógicas 2D
static func generate_terrain_polygons(
	terrain_node: Node,
	map_width_2d: float = 10000.0,
	map_height_2d: float = 10000.0,
	scale_factor: float = DEFAULT_SCALE_FACTOR,
	correction_z: float = DEFAULT_CORRECTION_Z,
	height_threshold: float = 0.8,
	grid_step_3d: float = 1.0,
	min_polygon_area: float = 400.0,
	simplification_epsilon: float = 2.0
) -> Array:
	var result: Array = []
	if not is_instance_valid(terrain_node):
		push_warning("[TerrainCollisionBaker2D] Nodo Terrain3D inválido o nulo.")
		return result
		
	# 1. Definir los límites del mundo 3D a muestrear
	var max_x_3d = map_width_2d * scale_factor
	var max_z_3d = map_height_2d * scale_factor * correction_z
	
	if max_x_3d <= 0.0 or max_z_3d <= 0.0:
		push_warning("[TerrainCollisionBaker2D] Dimensiones de mapa inválidas: %sx%s" % [map_width_2d, map_height_2d])
		return result
		
	var step_x = max(0.2, grid_step_3d)
	var step_z = max(0.2, grid_step_3d)
	
	var grid_w = int(ceil(max_x_3d / step_x))
	var grid_h = int(ceil(max_z_3d / step_z))
	
	if grid_w <= 1 or grid_h <= 1:
		return result
		
	print("[TerrainCollisionBaker2D] Iniciando muestreo: Cuadrícula %dx%d (%d celdas), umbral altura >= %.2fm..." % [grid_w, grid_h, grid_w * grid_h, height_threshold])
	var start_time = Time.get_ticks_msec()
	
	# 2. Construir la máscara de bits (BitMap) donde la altura supere el umbral
	var bitmap = BitMap.new()
	bitmap.create(Vector2i(grid_w, grid_h))
	
	var blocked_cells = 0
	for gz in range(grid_h):
		var pos_z = float(gz) * step_z
		for gx in range(grid_w):
			var pos_x = float(gx) * step_x
			var pos_3d = Vector3(pos_x, 0.0, pos_z)
			
			var h = get_height_at_3d_pos(terrain_node, pos_3d)
			if not is_nan(h) and not is_inf(h) and h >= height_threshold:
				bitmap.set_bit(gx, gz, true)
				blocked_cells += 1
				
	var sample_duration = Time.get_ticks_msec() - start_time
	print("[TerrainCollisionBaker2D] Muestreo completado en %d ms. Celdas bloqueadas: %d / %d" % [sample_duration, blocked_cells, grid_w * grid_h])
	
	if blocked_cells == 0:
		print("[TerrainCollisionBaker2D] No se encontraron elevaciones de terreno por encima de %.2fm." % height_threshold)
		return result
		
	# 3. Extraer contornos poligonales usando la función nativa de Godot BitMap.opaque_to_polygons
	var raw_polygons = bitmap.opaque_to_polygons(Rect2(0, 0, grid_w, grid_h), simplification_epsilon)
	print("[TerrainCollisionBaker2D] Contornos vectorizados brutos: %d" % raw_polygons.size())
	
	# 4. Proyectar cada vértice al espacio lógico 2D del juego
	for poly in raw_polygons:
		if poly.size() < 3:
			continue
			
		var world_points_2d = PackedVector2Array()
		for pt in poly:
			var world_x_3d = pt.x * step_x
			var world_z_3d = pt.y * step_z
			
			var logic_x_2d = world_x_3d / scale_factor
			var logic_y_2d = world_z_3d / (scale_factor * correction_z)
			world_points_2d.append(Vector2(logic_x_2d, logic_y_2d))
			
		# Filtrar polígonos degenerados o de ruido menor a min_polygon_area
		var area = _calculate_polygon_area(world_points_2d)
		if area >= min_polygon_area:
			result.append(world_points_2d)
			
	print("[TerrainCollisionBaker2D] Polígonos 2D finales generados: %d (tiempo total: %d ms)" % [result.size(), Time.get_ticks_msec() - start_time])
	return result

## Obtiene la altura real del Terrain3D de forma resiliente a versiones de Terrain3D (v0.9 a v1.0+)
static func get_height_at_3d_pos(terrain_node: Node, pos_3d: Vector3) -> float:
	if not is_instance_valid(terrain_node):
		return NAN
	# 1. Método directo en el nodo
	if terrain_node.has_method("get_height"):
		return terrain_node.get_height(pos_3d)
	# 2. Objeto data (Terrain3D v1.0.2+)
	var data_obj = terrain_node.get("data")
	if is_instance_valid(data_obj) and data_obj.has_method("get_height"):
		return data_obj.get_height(pos_3d)
	# 3. Objeto storage (Terrain3D v0.9)
	var storage_obj = terrain_node.get("storage")
	if is_instance_valid(storage_obj) and storage_obj.has_method("get_height"):
		return storage_obj.get_height(pos_3d)
	return NAN

## Instancia cuerpos StaticBody2D en el árbol 2D del mapa
static func spawn_2d_colliders(
	parent_2d: Node,
	polygons_2d: Array,
	base_name: String = "TerrainWall"
) -> Array[StaticBody2D]:
	var created_bodies: Array[StaticBody2D] = []
	if not is_instance_valid(parent_2d):
		return created_bodies
		
	# Limpiar colisionadores anteriores si existen bajo el mismo prefijo
	for child in parent_2d.get_children():
		if child is StaticBody2D and child.name.begins_with(base_name):
			child.queue_free()
			
	for i in range(polygons_2d.size()):
		var pts = polygons_2d[i] as PackedVector2Array
		if pts.size() < 3:
			continue
			
		var body = StaticBody2D.new()
		body.name = "%s_%d" % [base_name, i]
		body.collision_layer = 2 # Capa física de muros y obstáculos (bloquea a Player y Enemies)
		body.collision_mask = 0
		body.add_to_group("walls")
		body.add_to_group("obstacles")
		body.add_to_group("terrain_walls")
		
		var col_poly = CollisionPolygon2D.new()
		col_poly.polygon = pts
		body.add_child(col_poly)
		
		parent_2d.add_child(body)
		created_bodies.append(body)
		
	print("[TerrainCollisionBaker2D] Instanciados %d StaticBody2D en capa 2 para el terreno." % created_bodies.size())
	return created_bodies

## Hornea en la escena del editor (MapEditor3D): guarda los polígonos como metadata y genera visualización 3D
static func bake_to_editor_scene(
	scene_root: Node3D,
	terrain_node: Node,
	map_w: float,
	map_h: float,
	scale_factor: float,
	correction_z: float,
	height_threshold: float = 0.8,
	grid_step: float = 1.0,
	min_area: float = 400.0,
	simplification_epsilon: float = 2.0
) -> bool:
	if not is_instance_valid(scene_root) or not is_instance_valid(terrain_node):
		push_error("[TerrainCollisionBaker2D] scene_root o terrain_node nulo.")
		return false
		
	# Generar polígonos
	var polys = generate_terrain_polygons(
		terrain_node,
		map_w,
		map_h,
		scale_factor,
		correction_z,
		height_threshold,
		grid_step,
		min_area,
		simplification_epsilon
	)
	
	# Buscar o crear nodo contenedor "TerrainColliders"
	var container = scene_root.get_node_or_null(CONTAINER_NODE_NAME)
	if is_instance_valid(container):
		container.free()
		
	container = Node3D.new()
	container.name = CONTAINER_NODE_NAME
	scene_root.add_child(container)
	if Engine.is_editor_hint():
		container.owner = scene_root.get_tree().edited_scene_root if scene_root.get_tree() else scene_root
		
	# Guardar metadata esencial en el nodo contenedor
	container.set_meta("terrain_polygons", polys)
	container.set_meta("baked_height_threshold", height_threshold)
	container.set_meta("baked_timestamp", Time.get_datetime_string_from_system())
	container.set_meta("polygon_count", polys.size())
	
	# Generar visualización 3D de depuración para que el diseñador vea las áreas bloqueadas
	_generate_editor_3d_debug_visuals(container, polys, scale_factor, correction_z, height_threshold, terrain_node)
	
	print("[TerrainCollisionBaker2D] Horneado exitoso. Nodo '%s' creado con %d polígonos." % [CONTAINER_NODE_NAME, polys.size()])
	return true

## Limpia el contenedor de colisiones de terreno de la escena del editor
static func clear_editor_colliders(scene_root: Node3D) -> void:
	if not is_instance_valid(scene_root):
		return
	var container = scene_root.get_node_or_null(CONTAINER_NODE_NAME)
	if is_instance_valid(container):
		container.free()
		print("[TerrainCollisionBaker2D] Nodo '%s' eliminado." % CONTAINER_NODE_NAME)

## Genera mallas 3D para previsualizar los contornos de colisión en el editor de Godot
static func _generate_editor_3d_debug_visuals(
	parent: Node3D,
	polygons_2d: Array,
	scale_factor: float,
	correction_z: float,
	height_threshold: float,
	terrain_node: Node
) -> void:
	var line_mat = StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.1, 1.0, 0.5, 0.9)
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	for i in range(polygons_2d.size()):
		var poly_2d = polygons_2d[i] as PackedVector2Array
		if poly_2d.size() < 3:
			continue
			
		var immediate_mesh = ImmediateMesh.new()
		immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, line_mat)
		
		for pt in poly_2d:
			var world_x = pt.x * scale_factor
			var world_z = pt.y * scale_factor * correction_z
			var h = get_height_at_3d_pos(terrain_node, Vector3(world_x, 0.0, world_z))
			if is_nan(h):
				h = height_threshold
			var vert_pos = Vector3(world_x, h + 0.25, world_z)
			immediate_mesh.surface_add_vertex(vert_pos)
			
		# Cerrar el lazo
		var pt0 = poly_2d[0]
		var x0 = pt0.x * scale_factor
		var z0 = pt0.y * scale_factor * correction_z
		var h0 = get_height_at_3d_pos(terrain_node, Vector3(x0, 0.0, z0))
		if is_nan(h0):
			h0 = height_threshold
		immediate_mesh.surface_add_vertex(Vector3(x0, h0 + 0.25, z0))
		immediate_mesh.surface_end()
		
		var mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "VisualDebug_Poly_%d" % i
		mesh_instance.mesh = immediate_mesh
		parent.add_child(mesh_instance)
		if Engine.is_editor_hint():
			mesh_instance.owner = parent.owner

## Calcula el área de un polígono 2D usando el algoritmo de la lazada (Shoelace formula)
static func _calculate_polygon_area(points: PackedVector2Array) -> float:
	var n = points.size()
	if n < 3:
		return 0.0
	var area = 0.0
	for i in range(n):
		var j = (i + 1) % n
		area += points[i].x * points[j].y - points[j].x * points[i].y
	return abs(area) * 0.5

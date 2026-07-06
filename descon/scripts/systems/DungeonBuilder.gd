extends Node

# DungeonBuilder.gd
# Sistema de Construcción Dinámica de Dungeon desde la Configuración del Admin Dash
#
# Arquitectura:
#   - Lee config.mapsConfig[zoneId].objects filtrado por tipo "wall"
#   - Spawnea los GLB en el SubViewport 3D del mapa actual (Lienzo Único)
#   - La conversión 2D→3D usa el scale_factor del mapa (por defecto 0.02)
#   - Las colisiones siguen siendo 2D (StaticBody2D separados en la escena)
#
# Integración:
#   - Se inyecta dinámicamente desde World.gd al cargar cada mapa
#   - Se llama con dungeon_builder.build_for_zone(zone_id, map_node)

var _spawned_walls: Array[Node3D] = []

# ─── ENTRADA PRINCIPAL ────────────────────────────────────────────────────────
func build_for_zone(zone_id, map_node: Node) -> void:
	# 1. Limpiar paredes anteriores
	clear_walls()
	
	# 2. Verificar que el mapa tenga un SubViewport 3D disponible
	if not is_instance_valid(map_node):
		return
	if not "sub_viewport" in map_node or not is_instance_valid(map_node.sub_viewport):
		return
	
	var target_viewport: SubViewport = map_node.sub_viewport
	var scale_factor: float = map_node.get("scale_factor") if "scale_factor" in map_node else 0.02
	
	# 3. Obtener objetos del mapa desde GameConstants (limpiar float "200.0" -> "200")
	var zone_key = str(zone_id)
	if "." in zone_key and zone_key.is_valid_float():
		var z_float = float(zone_key)
		if z_float == int(z_float):
			zone_key = str(int(z_float))
	if not GameConstants.MAPS_CONFIG.has(zone_key):
		push_warning("[DungeonBuilder] No se encontró configuración para zona: " + zone_key)
		return
	
	var map_cfg = GameConstants.MAPS_CONFIG[zone_key]
	var objects: Array = map_cfg.get("objects", [])
	
	# 4. Filtrar y spawnear solo los objetos de tipo "wall"
	var wall_count = 0
	for obj in objects:
		if obj.get("type", "") == "wall":
			_spawn_wall(obj, target_viewport, scale_factor)
			wall_count += 1
	
	if wall_count > 0:
		print("[DungeonBuilder] Zona %s: %d pared(es) spawneada(s)." % [zone_key, wall_count])

# ─── SPAWN DE UNA PARED ───────────────────────────────────────────────────────
func _spawn_wall(obj: Dictionary, viewport: SubViewport, scale_factor: float) -> void:
	var asset_path: String = obj.get("assetPath", "")
	if asset_path == "" or not ResourceLoader.exists(asset_path):
		push_warning("[DungeonBuilder] Asset no encontrado: " + asset_path)
		return
	
	# Convertir coordenadas 2D del mapa a posición 3D del viewport
	# Convención: X_2D → X_3D,  Y_2D → Z_3D (el plano del suelo en 3D)
	var pos2d_x: float = float(obj.get("x", 5000))
	var pos2d_y: float = float(obj.get("y", 5000))
	var rot_y_deg: float = float(obj.get("rotY", 0))
	var obj_scale: float  = float(obj.get("scale", 1.0))
	
	var pos3d = Vector3(pos2d_x * scale_factor, 0.0, pos2d_y * scale_factor)
	
	# Cargar e instanciar el GLB
	var model_scene = load(asset_path)
	if not model_scene:
		push_warning("[DungeonBuilder] No se pudo cargar: " + asset_path)
		return
	
	var model_instance = model_scene.instantiate()
	
	# Crear un contenedor Node3D para controlar posición, rotación y escala
	var container = Node3D.new()
	container.name = "Wall_" + str(obj.get("label", "Pared"))
	container.position = pos3d
	container.rotation_degrees.y = rot_y_deg
	container.scale = Vector3.ONE * obj_scale
	container.add_child(model_instance)
	
	viewport.add_child(container)
	_spawned_walls.append(container)

# ─── LIMPIEZA ─────────────────────────────────────────────────────────────────
func clear_walls() -> void:
	for wall in _spawned_walls:
		if is_instance_valid(wall):
			wall.queue_free()
	_spawned_walls.clear()

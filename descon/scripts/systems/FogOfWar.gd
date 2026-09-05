extends Node
class_name FogOfWarManager

# v900.0 NIEBLA DE GUERRA OPTIMIZADA
# Grid 64x64 = 4096 celdas por mapa. Persistencia por zona via Server (DB: exploredMaps).
# Optimizaciones: viewports UPDATE_ONCE + dirty flag por movimiento + tex 256px + early discard en shader.

var parent_map: BaseMap = null
var map_size: Vector2 = Vector2(4000.0, 4000.0)

# Grid config compartido con servidor (Server/systems/fogHandlers.js GRID_RES)
const GRID_RES: int = 64
const GRID_TEX_SIZE: int = 256
const CELL_PX: float = float(GRID_TEX_SIZE) / float(GRID_RES) # 4.0

# Viewports off-screen de renderizado de niebla
var vision_viewport: SubViewport
var history_viewport: SubViewport

# Drawers
var vision_drawer: VisionDrawer
var history_drawer: HistoryDrawer

# Recursos 3D
var radial_gradient_tex: GradientTexture2D
var post_process_quad: MeshInstance3D
var shader_mat: ShaderMaterial

# Persistencia
var current_zone_id: String = "1"
var explored_by_zone: Dictionary = {} # zone_id -> { cell_idx: true }
var _pending_sync_cells: Array[int] = []
var _sync_timer: float = 0.0
const SYNC_INTERVAL: float = 2.0
const MAX_CELLS_PER_SYNC: int = 120
var _has_requested: bool = false
var _restoration_pending: bool = false
var _restoration_cells: Array = []
var _history_cleared: bool = false
var _server_grid_res: int = 64
var _draw_timer: float = 0.0
const DRAW_INTERVAL: float = 0.05 # 20 FPS

# Dirty flag: evita redibujar cuando el jugador no se movio
var _vision_dirty: bool = true
var _last_player_pos: Vector2 = Vector2(-9999.0, -9999.0)
const MOVE_THRESHOLD: float = 12.0 # unidades 2D minimas para marcar dirty

const FOG_SHADER = preload("res://resources/shaders/fog_of_war.gdshader")
const TEXTURE_NOISE_21D = preload("res://VFX/textures/T_VFX_Noise21d_tiled.png")

class VisionDrawer extends Node2D:
	var parent_fow: FogOfWarManager = null
	func _draw():
		if is_instance_valid(parent_fow):
			parent_fow._draw_vision(self)

class HistoryDrawer extends Node2D:
	var parent_fow: FogOfWarManager = null
	func _draw():
		if is_instance_valid(parent_fow):
			parent_fow._draw_history(self)

func setup(map: BaseMap):
	parent_map = map
	map_size = Vector2(map.world_size, map.map_height)
	current_zone_id = str(map.zone_id) if "zone_id" in map else "1"
	
	_init_gradient_texture()
	_create_viewports()
	_setup_post_process_quad()
	_connect_fog_signals()
	
	# Pedir niebla persistida al servidor
	request_fog_data()

func _connect_fog_signals():
	if NetworkManager:
		if not NetworkManager.socket_event_received.is_connected(_on_socket_event):
			NetworkManager.socket_event_received.connect(_on_socket_event)
		# Si NetworkManager tiene señal específica fog_data, conectar también
		if NetworkManager.has_signal("fog_data") and not NetworkManager.fog_data.is_connected(_on_fog_data):
			NetworkManager.fog_data.connect(_on_fog_data)

func _on_socket_event(event_name: String, data: Variant):
	if event_name == "fogData":
		_on_fog_data(data)

func _on_fog_data(data: Variant):
	if typeof(data) != TYPE_DICTIONARY:
		return
	var zid = str(data.get("zone", current_zone_id))
	# Ignorar datos de otra zona (puede llegar tarde tras cambio)
	if zid != current_zone_id:
		# Guardar igualmente para cache pero no restaurar ahora
		if not explored_by_zone.has(zid):
			explored_by_zone[zid] = {}
		var cells_arr = data.get("cells", [])
		if typeof(cells_arr) == TYPE_ARRAY:
			for c in cells_arr:
				explored_by_zone[zid][int(c)] = true
		return
	
	var grid_res = int(data.get("gridRes", GRID_RES))
	_server_grid_res = grid_res
	var cells = data.get("cells", [])
	if typeof(cells) != TYPE_ARRAY:
		cells = []
	
	if not explored_by_zone.has(zid):
		explored_by_zone[zid] = {}
	else:
		explored_by_zone[zid].clear()
	
	for c in cells:
		var ci = int(c)
		if ci >= 0 and ci < grid_res * grid_res:
			# Si el server usa 64 y nosotros 64, directo
			# Si difiere, re-escalar (no debería pasar)
			if grid_res != GRID_RES:
				var x = ci % grid_res
				var y = int(ci / grid_res)
				var nx = int(float(x) / float(grid_res) * float(GRID_RES))
				var ny = int(float(y) / float(grid_res) * float(GRID_RES))
				ci = ny * GRID_RES + nx
			explored_by_zone[zid][ci] = true
	
	_restoration_cells = cells.duplicate()
	_restoration_pending = true
	_has_requested = true
	# Forzar redibujado de historial para pintar celdas guardadas
	if is_instance_valid(history_drawer):
		history_drawer.queue_redraw()
	print("[FogOfWar] Niebla restaurada zona ", zid, ": ", cells.size(), " celdas (grid ", GRID_RES, ")")

func request_fog_data():
	if _has_requested:
		return
	_has_requested = true
	if NetworkManager and NetworkManager.has_method("send_event"):
		NetworkManager.send_event("requestFog", {"zone": current_zone_id})
		print("[FogOfWar] Solicitando niebla persistida zona ", current_zone_id)

func _init_gradient_texture():
	var grad = Gradient.new()
	# El gradiente es 100% visible hasta el 80% de su tamaño, y se desvanece suavemente hacia el 100%.
	# Al instanciarlo un 25% más grande, el 80% encaja exactamente con el límite real de visión,
	# haciendo que el desvanecimiento ocurra estrictamente "desde donde no veo, para afuera".
	grad.offsets = PackedFloat32Array([0.0, 0.80, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	radial_gradient_tex = GradientTexture2D.new()
	radial_gradient_tex.gradient = grad
	radial_gradient_tex.fill = GradientTexture2D.FILL_RADIAL
	radial_gradient_tex.fill_from = Vector2(0.5, 0.5)
	radial_gradient_tex.fill_to = Vector2(1.0, 0.5)
	radial_gradient_tex.width = 256
	radial_gradient_tex.height = 256

func _create_viewports():
	vision_viewport = SubViewport.new()
	vision_viewport.name = "VisionViewport"
	vision_viewport.size = Vector2i(GRID_TEX_SIZE, GRID_TEX_SIZE)
	vision_viewport.own_world_3d = false
	vision_viewport.transparent_bg = false
	# UPDATE_ONCE: solo renderiza cuando queue_redraw() activa el redibujado
	# Ahorra un draw call por frame cuando el jugador no se mueve
	vision_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	vision_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(vision_viewport)
	
	vision_drawer = VisionDrawer.new()
	vision_drawer.name = "VisionDrawer"
	vision_drawer.parent_fow = self
	vision_viewport.add_child(vision_drawer)
	
	history_viewport = SubViewport.new()
	history_viewport.name = "HistoryViewport"
	history_viewport.size = Vector2i(GRID_TEX_SIZE, GRID_TEX_SIZE)
	history_viewport.own_world_3d = false
	history_viewport.transparent_bg = false
	# UPDATE_ONCE: CLEAR_MODE_NEVER garantiza que lo explorado persiste entre frames
	history_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	history_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	add_child(history_viewport)
	
	history_drawer = HistoryDrawer.new()
	history_drawer.name = "HistoryDrawer"
	history_drawer.parent_fow = self
	history_viewport.add_child(history_drawer)

func _setup_post_process_quad():
	if not is_instance_valid(parent_map) or not is_instance_valid(parent_map.camera_3d):
		return
	var camera = parent_map.camera_3d
	var old_quad = camera.get_node_or_null("FogOfWarQuad")
	if is_instance_valid(old_quad):
		old_quad.queue_free()
	post_process_quad = MeshInstance3D.new()
	post_process_quad.name = "FogOfWarQuad"
	post_process_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	post_process_quad.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(2.0, 2.0)
	post_process_quad.mesh = quad_mesh
	shader_mat = ShaderMaterial.new()
	shader_mat.shader = FOG_SHADER
	shader_mat.render_priority = -128
	var map_size_3d = Vector2(
		parent_map.world_size * parent_map.scale_factor,
		parent_map.map_height * parent_map.scale_factor * parent_map.correction_z
	)
	shader_mat.set_shader_parameter("map_size_3d", map_size_3d)
	shader_mat.set_shader_parameter("vision_texture", vision_viewport.get_texture())
	shader_mat.set_shader_parameter("history_texture", history_viewport.get_texture())
	shader_mat.set_shader_parameter("noise_texture", TEXTURE_NOISE_21D)
	# v802.0 NIEBLA PANTANO VOLUMÉTRICA 80% - unos metros para arriba, degradé sin línea dura
	shader_mat.set_shader_parameter("fog_opacity", 0.80)
	shader_mat.set_shader_parameter("shroud_opacity", 0.32)
	shader_mat.set_shader_parameter("fog_color_dark", Vector3(0.14, 0.16, 0.17))
	shader_mat.set_shader_parameter("fog_color_mid", Vector3(0.34, 0.36, 0.39))
	shader_mat.set_shader_parameter("fog_color_light", Vector3(0.60, 0.62, 0.64))
	shader_mat.set_shader_parameter("swamp_tint", Vector3(0.30, 0.34, 0.28))
	shader_mat.set_shader_parameter("swamp_mix", 0.20)
	shader_mat.set_shader_parameter("fog_desaturate", 0.62)
	shader_mat.set_shader_parameter("cloud_scale1", 0.0085)
	shader_mat.set_shader_parameter("cloud_scale2", 0.017)
	shader_mat.set_shader_parameter("cloud_speed1", 0.014)
	shader_mat.set_shader_parameter("cloud_speed2", -0.011)
	shader_mat.set_shader_parameter("elevation_speed", 0.007)
	shader_mat.set_shader_parameter("cloud_contrast", 1.18)
	shader_mat.set_shader_parameter("noise_scale", 0.011)
	shader_mat.set_shader_parameter("noise_speed", 0.018)
	shader_mat.set_shader_parameter("fog_height", 30.0)
	shader_mat.set_shader_parameter("fog_density", 0.55)
	shader_mat.set_shader_parameter("fog_vertical_fade", 1.2)
	post_process_quad.material_override = shader_mat
	post_process_quad.extra_cull_margin = 16384.0
	camera.add_child(post_process_quad)

var _cached_providers: Array = []
var _provider_update_timer: float = 0.0

func _update_providers_cache():
	var list = []
	var player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and player.get("is_dead") != true:
		list.append(player)
	var entities = get_tree().get_nodes_in_group("entities")
	for entity in entities:
		if is_instance_valid(entity) and entity.get("is_dead") != true:
			if entity.get("_is_ally") == true:
				list.append(entity)
	_cached_providers = list

func get_vision_providers() -> Array:
	return _cached_providers

# === GRID HELPERS ===
func _world_to_cell_idx(pos: Vector2) -> int:
	var mx = map_size.x if map_size.x > 0.0 else 4000.0
	var my = map_size.y if map_size.y > 0.0 else 4000.0
	var cx = clampi(int((pos.x / mx) * float(GRID_RES)), 0, GRID_RES - 1)
	var cy = clampi(int((pos.y / my) * float(GRID_RES)), 0, GRID_RES - 1)
	return cy * GRID_RES + cx

func _get_cells_in_circle(center: Vector2, radius: float) -> Array[int]:
	var cells: Array[int] = []
	var mx = map_size.x if map_size.x > 0.0 else 4000.0
	var my = map_size.y if map_size.y > 0.0 else 4000.0
	var cell_w = mx / float(GRID_RES)
	var cell_h = my / float(GRID_RES)
	# Radio en celdas
	var r_cells_x = int(ceil(radius / cell_w)) + 1
	var r_cells_y = int(ceil(radius / cell_h)) + 1
	var center_cx = clampi(int((center.x / mx) * float(GRID_RES)), 0, GRID_RES - 1)
	var center_cy = clampi(int((center.y / my) * float(GRID_RES)), 0, GRID_RES - 1)
	var r_sq = radius * radius
	for dy in range(-r_cells_y, r_cells_y + 1):
		for dx in range(-r_cells_x, r_cells_x + 1):
			var cx = center_cx + dx
			var cy = center_cy + dy
			if cx < 0 or cx >= GRID_RES or cy < 0 or cy >= GRID_RES:
				continue
			# Centro de la celda en mundo
			var cell_center_x = (float(cx) + 0.5) * cell_w
			var cell_center_y = (float(cy) + 0.5) * cell_h
			var ddx = cell_center_x - center.x
			var ddy = cell_center_y - center.y
			if ddx * ddx + ddy * ddy <= r_sq:
				var idx = cy * GRID_RES + cx
				cells.append(idx)
	return cells

func _collect_new_explored_cells() -> Array[int]:
	var new_cells: Array[int] = []
	if not explored_by_zone.has(current_zone_id):
		explored_by_zone[current_zone_id] = {}
	var zone_set = explored_by_zone[current_zone_id]
	var providers = get_vision_providers()
	for prov in providers:
		var pos_2d = prov.global_position
		var vr = prov.get("vision_range") if "vision_range" in prov else 1300.0
		var circle_cells = _get_cells_in_circle(pos_2d, vr)
		for ci in circle_cells:
			if not zone_set.has(ci):
				zone_set[ci] = true
				new_cells.append(ci)
	return new_cells

func _draw_vision(drawer: Node2D):
	# Solo ejecutado cuando _vision_dirty = true (optimizacion)
	drawer.draw_rect(Rect2(0, 0, GRID_TEX_SIZE, GRID_TEX_SIZE), Color.BLACK)
	_draw_all_vision_circles(drawer)
	# Tras redibujar, disparar actualizacion del viewport
	if is_instance_valid(vision_viewport):
		vision_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _draw_history(drawer: Node2D):
	if not _history_cleared:
		drawer.draw_rect(Rect2(0, 0, GRID_TEX_SIZE, GRID_TEX_SIZE), Color.BLACK)
		_history_cleared = true
	# Restaurar celdas persistidas (solo una vez, CLEAR_MODE_NEVER las mantiene)
	if _restoration_pending:
		if explored_by_zone.has(current_zone_id):
			var zset = explored_by_zone[current_zone_id]
			var overlap = 1.0
			for ci in zset.keys():
				var ci_int = int(ci)
				var cx = ci_int % GRID_RES
				var cy = int(ci_int / GRID_RES)
				var x = float(cx) * CELL_PX
				var y = float(cy) * CELL_PX
				drawer.draw_rect(Rect2(x - overlap*0.5, y - overlap*0.5, CELL_PX + overlap, CELL_PX + overlap), Color.WHITE)
		_restoration_pending = false
	_draw_all_vision_circles(drawer)
	# Tras redibujar, disparar actualizacion del viewport
	if is_instance_valid(history_viewport):
		history_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _draw_all_vision_circles(drawer: Node2D):
	var providers = get_vision_providers()
	var should_log = Engine.get_frames_drawn() % 600 == 0
	if should_log and providers.size() > 0:
		print("[FogOfWar] Vision providers: ", providers.size(), " Zone: ", current_zone_id, " MapSize: ", map_size)
	for provider in providers:
		var pos_2d = provider.global_position
		var vr = provider.get("vision_range") if "vision_range" in provider else 1300.0
		
		# Aumentamos el tamaño visual un 25%. Dado que el gradiente ahora es 100% blanco 
		# hasta el 80% (1.0 / 1.25 = 0.8), el radio 2D de visión perfecto (vr) queda 100% blanco.
		# El sobrante (el degradado) cae HASTA AFUERA, garantizando que el degrade empieza
		# "desde donde no ves, para afuera".
		var visual_vr = vr * 1.25
		
		var mx = map_size.x if map_size.x > 0.0 else 4000.0
		var my = map_size.y if map_size.y > 0.0 else 4000.0
		var x = (pos_2d.x / mx) * float(GRID_TEX_SIZE)
		var y = (pos_2d.y / my) * float(GRID_TEX_SIZE)
		var rx = (visual_vr / mx) * float(GRID_TEX_SIZE)
		var ry = (visual_vr / my) * float(GRID_TEX_SIZE)
		var rect = Rect2(x - rx, y - ry, rx * 2.0, ry * 2.0)
		drawer.draw_texture_rect(radial_gradient_tex, rect, false)
		if should_log:
			print(" - [FOW] ", provider.name, " Pos2D: ", pos_2d, " VpPos: ", Vector2(x,y), " Rad: ", Vector2(rx,ry))

func _process(_delta):
	if is_instance_valid(parent_map):
		map_size = Vector2(parent_map.world_size, parent_map.map_height)
		# Sincronizar zona si cambio (warp)
		var nz = str(parent_map.zone_id)
		if nz != current_zone_id:
			current_zone_id = nz
			_has_requested = false
			_history_cleared = false
			_restoration_pending = false
			_vision_dirty = true
			request_fog_data()
		var map_size_3d = Vector2(
			parent_map.world_size * parent_map.scale_factor,
			parent_map.map_height * parent_map.scale_factor * parent_map.correction_z
		)
		if is_instance_valid(shader_mat):
			shader_mat.set_shader_parameter("map_size_3d", map_size_3d)
			if is_instance_valid(vision_viewport):
				shader_mat.set_shader_parameter("vision_texture", vision_viewport.get_texture())
			if is_instance_valid(history_viewport):
				shader_mat.set_shader_parameter("history_texture", history_viewport.get_texture())
	
	# --- DIRTY FLAG: detectar movimiento del jugador ---
	var player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		var ppos = Vector2(player.global_position.x, player.global_position.y)
		var dist_moved = _last_player_pos.distance_to(ppos)
		if dist_moved > MOVE_THRESHOLD:
			_vision_dirty = true
			_last_player_pos = ppos
	
	# Sincronizacion periodica de exploracion al servidor
	_sync_timer += _delta
	if _sync_timer >= SYNC_INTERVAL:
		_sync_timer = 0.0
		var new_cells = _collect_new_explored_cells()
		if new_cells.size() > 0:
			for c in new_cells:
				_pending_sync_cells.append(c)
			# El historial necesita redibujar las celdas nuevas
			if is_instance_valid(history_drawer):
				history_drawer.queue_redraw()
			_flush_pending_sync()
			
	_provider_update_timer -= _delta
	if _provider_update_timer <= 0.0:
		_provider_update_timer = 0.5
		_update_providers_cache()
	
	# Solo redibujar vision si el jugador se movio (_vision_dirty)
	_draw_timer -= _delta
	if _draw_timer <= 0.0:
		_draw_timer = DRAW_INTERVAL
		if _vision_dirty or _restoration_pending:
			if is_instance_valid(vision_drawer):
				vision_drawer.queue_redraw()
			_vision_dirty = false
		if _restoration_pending:
			if is_instance_valid(history_drawer):
				history_drawer.queue_redraw()

func _flush_pending_sync():
	if _pending_sync_cells.is_empty():
		return
	# Enviar en lotes de MAX_CELLS_PER_SYNC para respetar límite anticheat servidor
	var to_send: Array[int] = []
	var count = mini(_pending_sync_cells.size(), MAX_CELLS_PER_SYNC)
	for i in range(count):
		to_send.append(_pending_sync_cells[i])
	# Remover enviados
	_pending_sync_cells = _pending_sync_cells.slice(count, _pending_sync_cells.size())
	if to_send.size() > 0 and NetworkManager and NetworkManager.has_method("send_event"):
		NetworkManager.send_event("updateFog", {"zone": current_zone_id, "cells": to_send})
		if to_send.size() >= 10:
			print("[FogOfWar] Sync niebla zona ", current_zone_id, " +", to_send.size(), " celdas (pendientes ", _pending_sync_cells.size(), ")")


# API publica para debug / reset
func get_explored_count(zid: String = "") -> int:

	var z = zid if zid != "" else current_zone_id
	if explored_by_zone.has(z):
		return explored_by_zone[z].size()
	return 0

func get_explored_percent(zid: String = "") -> float:
	var c = get_explored_count(zid)
	return float(c) / float(GRID_RES * GRID_RES) * 100.0

func debug_reset_zone():
	if NetworkManager and NetworkManager.has_method("send_event"):
		NetworkManager.send_event("resetFog", {"zone": current_zone_id})
		if explored_by_zone.has(current_zone_id):
			explored_by_zone[current_zone_id].clear()
		_history_cleared = false
		print("[FogOfWar] Reset solicitado zona ", current_zone_id)

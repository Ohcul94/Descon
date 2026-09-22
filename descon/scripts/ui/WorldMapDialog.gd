extends CanvasLayer
class_name WorldMapDialog

# WorldMapDialog.gd
# Vista completa panorámica e interactiva de cada mapa/sector (World Map Sci-Fi)
# Permite ver el mapa completo de punta a punta, zonas, portales, altares y jugador.
# Layer 130: se renderiza con máxima prioridad por encima del Menú de Mapas (Inventory z_index=100).

var target_zone_id: String = "1"
var _redraw_accum: float = 0.0
var root_control: Control = null
var map_canvas: Control = null
var title_lbl: Label = null
var coord_lbl: Label = null
var is_dialog_open: bool = false

func _init():
	name = "WorldMapDialog"
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 130 # Máxima prioridad visual por encima de menús
	visible = false

func _ready():
	terrain_cache_by_zone.clear()
	_build_ui()

func _build_ui():
	# 1. Overlay semi-transparente de fondo para oscurecer la vista
	var overlay = ColorRect.new()
	overlay.name = "Backdrop"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.0, 0.02, 0.05, 0.75)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	
	# Al hacer clic en el backdrop fuera de la ventana, también se puede cerrar
	overlay.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			close()
	)

	# 2. Panel principal de la ventana (Estilo Sci-Fi Holo)
	var main_panel = PanelContainer.new()
	main_panel.name = "MainPanel"
	main_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	main_panel.custom_minimum_size = Vector2(860, 680)
	main_panel.offset_left = -430
	main_panel.offset_right = 430
	main_panel.offset_top = -340
	main_panel.offset_bottom = 340
	
	var panel_sb = StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.015, 0.04, 0.08, 0.96)
	panel_sb.border_width_left = 2
	panel_sb.border_width_top = 2
	panel_sb.border_width_right = 2
	panel_sb.border_width_bottom = 2
	panel_sb.border_color = Color(0.0, 0.85, 1.0, 0.8)
	panel_sb.set_corner_radius_all(4)
	panel_sb.shadow_color = Color(0.0, 0.85, 1.0, 0.25)
	panel_sb.shadow_size = 12
	main_panel.add_theme_stylebox_override("panel", panel_sb)
	add_child(main_panel)

	var v_box = VBoxContainer.new()
	v_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v_box.add_theme_constant_override("separation", 8)
	main_panel.add_child(v_box)

	# 3. Header de la ventana
	var header_bar = HBoxContainer.new()
	header_bar.custom_minimum_size.y = 36
	v_box.add_child(header_bar)

	var spacer_h = Control.new()
	spacer_h.custom_minimum_size.x = 12
	header_bar.add_child(spacer_h)

	title_lbl = Label.new()
	title_lbl.text = "🗺️ MAPA CARTOGRÁFICO COMPLETO"
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", Color(0.0, 1.0, 1.0))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_bar.add_child(title_lbl)

	coord_lbl = Label.new()
	coord_lbl.text = "COORDENADAS"
	coord_lbl.add_theme_font_size_override("font_size", 11)
	coord_lbl.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 0.8))
	header_bar.add_child(coord_lbl)

	var spacer_btn = Control.new()
	spacer_btn.custom_minimum_size.x = 12
	header_bar.add_child(spacer_btn)

	# Botón de cerrar estilizado
	var btn_close = Button.new()
	btn_close.name = "BtnClose"
	btn_close.text = " ✕ CERRAR "
	btn_close.custom_minimum_size = Vector2(90, 28)
	var btn_sb = StyleBoxFlat.new()
	btn_sb.bg_color = Color(0.12, 0.03, 0.05, 0.8)
	btn_sb.border_width_left = 1
	btn_sb.border_width_top = 1
	btn_sb.border_width_right = 1
	btn_sb.border_width_bottom = 1
	btn_sb.border_color = Color(1.0, 0.3, 0.3, 0.8)
	btn_sb.set_corner_radius_all(3)
	btn_close.add_theme_stylebox_override("normal", btn_sb)
	
	var btn_sb_h = btn_sb.duplicate()
	btn_sb_h.bg_color = Color(0.35, 0.05, 0.08, 0.95)
	btn_sb_h.border_color = Color(1.0, 0.5, 0.5, 1.0)
	btn_close.add_theme_stylebox_override("hover", btn_sb_h)
	btn_close.add_theme_font_size_override("font_size", 10)
	btn_close.pressed.connect(close)
	header_bar.add_child(btn_close)

	var spacer_end = Control.new()
	spacer_end.custom_minimum_size.x = 10
	header_bar.add_child(spacer_end)

	# Separador sutil
	var sep = ColorRect.new()
	sep.custom_minimum_size.y = 1
	sep.color = Color(0.0, 0.85, 1.0, 0.3)
	v_box.add_child(sep)

	# 4. Área del lienzo del mapa completo
	var center_container = CenterContainer.new()
	center_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v_box.add_child(center_container)

	map_canvas = Control.new()
	map_canvas.name = "MapCanvas"
	map_canvas.custom_minimum_size = Vector2(800, 580)
	map_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	center_container.add_child(map_canvas)
	
	map_canvas.draw.connect(_on_canvas_draw)
	map_canvas.gui_input.connect(_on_canvas_gui_input)

	# 5. Barra inferior con leyenda
	var footer_bar = HBoxContainer.new()
	footer_bar.custom_minimum_size.y = 26
	footer_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	footer_bar.add_theme_constant_override("separation", 24)
	v_box.add_child(footer_bar)

	_add_legend_item(footer_bar, "⚪ Tu Nave", Color.WHITE)
	_add_legend_item(footer_bar, "🟢 Clan / 🔵 Escuadrón", Color(0.0, 1.0, 0.8))
	_add_legend_item(footer_bar, "💠 [P] Portales", Color(0.0, 0.9, 1.0))
	_add_legend_item(footer_bar, "✨ [A] Altares", Color(0.0, 1.0, 0.5))
	_add_legend_item(footer_bar, "🟡 [B] Baúles", Color(1.0, 0.85, 0.0))
	_add_legend_item(footer_bar, "🔴 [N] Nexos / Pilares", Color(1.0, 0.3, 0.3))
	_add_legend_item(footer_bar, "🖱️ Clic Derecho / Toque: Fijar Rumbo", Color(0.7, 0.9, 1.0, 0.7))

func _add_legend_item(parent: Container, label_text: String, col: Color):
	var lbl = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", col)
	parent.add_child(lbl)

func open(zone_id_to_show: String = ""):
	var player = get_tree().get_first_node_in_group("player")
	if zone_id_to_show != "":
		target_zone_id = zone_id_to_show
	elif is_instance_valid(player) and "current_zone" in player:
		target_zone_id = str(player.current_zone)
	else:
		target_zone_id = "1"

	visible = true
	is_dialog_open = true
	_update_header()
	if is_instance_valid(map_canvas):
		map_canvas.queue_redraw()

func close():
	visible = false
	is_dialog_open = false

func toggle(zone_id_to_show: String = ""):
	if is_dialog_open:
		close()
	else:
		open(zone_id_to_show)

func _input(event):
	if not visible: return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_map"):
		close()
		get_viewport().set_input_as_handled()

func _process(delta):
	if not visible: return
	_redraw_accum += delta
	if _redraw_accum >= 0.05: # 20 FPS de refresco para el mapa completo es ideal y ultra fluido
		_redraw_accum = 0.0
		_update_header()
		if is_instance_valid(map_canvas):
			map_canvas.queue_redraw()

func _update_header():
	if not is_instance_valid(title_lbl): return
	var z_name = "SECTOR DESCONOCIDO"
	if target_zone_id in GameConstants.MAPS_CONFIG:
		z_name = GameConstants.MAPS_CONFIG[target_zone_id].name
	elif int(target_zone_id) >= 500:
		z_name = "INSTANCIA PRIVADA"
	else:
		z_name = "SECTOR " + str(target_zone_id).pad_zeros(2)

	title_lbl.text = "🗺️ MAPA CARTOGRÁFICO COMPLETO — %s" % z_name.to_upper()
	
	var player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		var p_zone = str(player.current_zone) if "current_zone" in player else "1"
		if p_zone == target_zone_id:
			coord_lbl.text = "POSICIÓN ACTUAL: X: %d, Y: %d" % [int(player.global_position.x), int(player.global_position.y)]
		else:
			coord_lbl.text = "VISTA REMOTA (Estás en Sector %s)" % p_zone
	else:
		coord_lbl.text = ""

func get_zone_dimensions(zone_id: String) -> Vector2:
	return get_zone_rect(zone_id, get_tree()).size

func _on_canvas_gui_input(event: InputEvent):
	# PC: clic derecho. Móvil: toque nativo (InputEventScreenTouch).
	var is_nav = false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		is_nav = true
	elif event is InputEventScreenTouch and event.pressed:
		is_nav = true

	if not is_nav:
		return

	var player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player): return
	var p_zone = str(player.current_zone) if "current_zone" in player else "1"
	if p_zone != target_zone_id: return # Solo fijar rumbo si es el mapa en que se encuentra el jugador
	
	var world_rect = get_zone_rect(target_zone_id, get_tree())
	var worldW = world_rect.size.x
	var worldH = world_rect.size.y
	var canvas_size = map_canvas.size
	var scale_val = min(canvas_size.x / worldW, canvas_size.y / worldH)
	var map_draw_size = Vector2(worldW * scale_val, worldH * scale_val)
	var map_draw_offset = (canvas_size - map_draw_size) / 2.0
	
	var m_pos = event.position - map_draw_offset
	if m_pos.x >= 0 and m_pos.x <= map_draw_size.x and m_pos.y >= 0 and m_pos.y <= map_draw_size.y:
		var target_world_pos = world_rect.position + Vector2(m_pos.x / scale_val, m_pos.y / scale_val)
		target_world_pos.x = clamp(target_world_pos.x, world_rect.position.x, world_rect.end.x)
		target_world_pos.y = clamp(target_world_pos.y, world_rect.position.y, world_rect.end.y)
		if player.has_method("set_autopilot"):
			player.set_autopilot(target_world_pos)
			print("[WorldMap] Rumbo fijado desde mapa completo a: ", target_world_pos)
			get_viewport().set_input_as_handled()

static var terrain_cache_by_zone: Dictionary = {}
static var terrain_image_by_zone: Dictionary = {}
static var terrain_bounds_by_zone: Dictionary = {}

static func export_terrain_texture_to_png(zone_id: Variant, tree: SceneTree, file_path: String) -> bool:
	var z_key = str(zone_id)
	var img: Image = null
	if terrain_image_by_zone.has(z_key):
		img = terrain_image_by_zone[z_key]
	else:
		get_or_create_terrain_texture(zone_id, tree)
		if terrain_image_by_zone.has(z_key):
			img = terrain_image_by_zone[z_key]
	if img:
		var dir_path = file_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(dir_path):
			DirAccess.make_dir_recursive_absolute(dir_path)
		var err = img.save_png(file_path)
		if err == OK:
			print("[WorldMap] 💾 Textura PNG exportada exitosamente a: ", file_path)
			return true
		else:
			print("[WorldMap] ❌ Error guardando PNG: ", err)
	return false

static func _find_terrain_node_recursive(node: Node) -> Node:
	if not is_instance_valid(node):
		return null
	if node.is_class("Terrain3D") or "Terrain3D" in node.name:
		return node
	for child in node.get_children():
		var found = _find_terrain_node_recursive(child)
		if found:
			return found
	return null

static func _get_scene_candidates(z_key: String) -> Array[String]:
	var candidates: Array[String] = []
	if z_key == "1":
		candidates = [
			"res://tools/MapEditor3D_1_Loby.tscn",
			"res://tools/MapEditor3D_1_Lobby.tscn",
			"res://tools/MapEditor3D_1_Mapa_1.tscn"
		]
	else:
		candidates = [
			"res://tools/MapEditor3D_" + z_key + "_Mapa_" + z_key + ".tscn",
			"res://tools/MapEditor3D_" + z_key + "_Loby.tscn",
			"res://tools/MapEditor3D_" + z_key + "_Lobby.tscn"
		]
		var full_cfg = GameConstants.get("FULL_CONFIG")
		if full_cfg and full_cfg.has("gameModes"):
			if full_cfg.gameModes.has("altar_defense"):
				var ad_maps = full_cfg.gameModes.altar_defense.get("maps", [])
				for m in ad_maps:
					if str(m) == z_key:
						candidates.push_front("res://tools/MapEditor3D_Evento_2_Defensa_Altar.tscn")
						break
			if full_cfg.gameModes.has("extraction"):
				var ext_maps = full_cfg.gameModes.extraction.get("maps", [])
				if typeof(ext_maps) == TYPE_ARRAY:
					for m in ext_maps:
						if str(m) == z_key:
							candidates.push_front("res://tools/MapEditor3D_Evento_1_Extraccion.tscn")
							break
			if full_cfg.gameModes.has("arenas"):
				var am = full_cfg.gameModes.arenas.get("maps", [])
				for m in am:
					if str(m) == z_key:
						candidates.push_front("res://tools/MapEditor3D_Evento_3_PVP.tscn")
						break
		if z_key == "11" and not "res://tools/MapEditor3D_Evento_2_Defensa_Altar.tscn" in candidates:
			candidates.push_front("res://tools/MapEditor3D_Evento_2_Defensa_Altar.tscn")
		if z_key == "10" and not "res://tools/MapEditor3D_Evento_1_Extraccion.tscn" in candidates:
			candidates.push_front("res://tools/MapEditor3D_Evento_1_Extraccion.tscn")
		if z_key == "9" and not "res://tools/MapEditor3D_Evento_3_PVP.tscn" in candidates:
			candidates.push_front("res://tools/MapEditor3D_Evento_3_PVP.tscn")
	return candidates

static func _add_temp_child(tree: SceneTree, child: Node) -> Node:
	if not tree: return null
	var candidates = ["AudioManager", "GameConstants", "VFXSystem", "NetworkManager"]
	for c_name in candidates:
		var n = tree.root.get_node_or_null(c_name)
		if is_instance_valid(n):
			n.add_child(child)
			return n
	if tree.current_scene and not tree.current_scene.is_queued_for_deletion():
		tree.current_scene.add_child(child)
		return tree.current_scene
	if tree.root:
		tree.root.add_child(child)
		return tree.root
	return null

static func _remove_temp_child(parent: Node, child: Node) -> void:
	if is_instance_valid(parent) and is_instance_valid(child) and child.get_parent() == parent:
		parent.remove_child(child)

static func get_zone_rect(zone_id: Variant = "", tree: SceneTree = null) -> Rect2:
	var z_key = str(zone_id)
	if terrain_bounds_by_zone.has(z_key):
		return terrain_bounds_by_zone[z_key]

	var terrain_node: Node = null
	var scale_factor: float = 0.02
	var correction_z: float = 1.41421356
	var temp_scene_to_free: Node = null
	var host_parent: Node = null

	if tree:
		var map_node = tree.get_first_node_in_group("map")
		var player = tree.get_first_node_in_group("player")
		var cur_zone = str(player.current_zone) if is_instance_valid(player) and "current_zone" in player else ""

		# 1. Intentar obtener el nodo de terreno del mapa activo en el juego
		if is_instance_valid(map_node) and (cur_zone == z_key or z_key == ""):
			terrain_node = map_node.get("terrain_node")
			if not is_instance_valid(terrain_node):
				if is_instance_valid(map_node.get("custom_scene_instance")):
					terrain_node = _find_terrain_node_recursive(map_node.custom_scene_instance)
				elif is_instance_valid(map_node.get("sub_viewport")):
					terrain_node = map_node.sub_viewport.find_child("Terrain3D", true, false)
			if not is_instance_valid(terrain_node):
				terrain_node = map_node.find_child("Terrain3D", true, false)
			if "scale_factor" in map_node: scale_factor = float(map_node.scale_factor)
			if "correction_z" in map_node: correction_z = float(map_node.correction_z)

		# 2. Si es una zona remota o no se encontró en el mapa activo, cargar la escena pre-diseñada
		if not is_instance_valid(terrain_node):
			var candidates = _get_scene_candidates(z_key)
			for p in candidates:
				if ResourceLoader.exists(p):
					var sc_res = load(p)
					if sc_res:
						temp_scene_to_free = sc_res.instantiate()
						_disable_free_editor_textures_recursive(temp_scene_to_free)
						host_parent = _add_temp_child(tree, temp_scene_to_free)
						terrain_node = temp_scene_to_free.find_child("Terrain3D", true, false)
						if not is_instance_valid(terrain_node):
							terrain_node = _find_terrain_node_recursive(temp_scene_to_free)
						if is_instance_valid(terrain_node):
							if "scale_factor" in temp_scene_to_free: scale_factor = float(temp_scene_to_free.scale_factor)
							if "correction_z" in temp_scene_to_free: correction_z = float(temp_scene_to_free.correction_z)
							break
						else:
							_remove_temp_child(host_parent, temp_scene_to_free)
							temp_scene_to_free.queue_free()
							temp_scene_to_free = null
							host_parent = null

	if is_instance_valid(terrain_node):
		var data = terrain_node.get("data")
		if not is_instance_valid(data) and terrain_node.has_method("get_data"):
			data = terrain_node.get_data()

		if is_instance_valid(data) and data.has_method("get_region_locations"):
			var locs = data.get_region_locations()
			if locs.size() > 0:
				var r_size = float(terrain_node.region_size) if "region_size" in terrain_node else 64.0
				if terrain_node.has_method("get_region_size"):
					r_size = float(terrain_node.get_region_size())
				var v_spacing = float(terrain_node.vertex_spacing) if "vertex_spacing" in terrain_node else 1.0
				if terrain_node.has_method("get_vertex_spacing"):
					v_spacing = float(terrain_node.get_vertex_spacing())
				r_size *= v_spacing

				var min_rx = 999999
				var max_rx = -999999
				var min_rz = 999999
				var max_rz = -999999
				for loc in locs:
					if loc.x < min_rx: min_rx = loc.x
					if loc.x > max_rx: max_rx = loc.x
					if loc.y < min_rz: min_rz = loc.y
					if loc.y > max_rz: max_rz = loc.y

				var t_pos = terrain_node.global_position if terrain_node.is_inside_tree() else terrain_node.position
				var min_x_3d = float(min_rx) * r_size + t_pos.x
				var max_x_3d = float(max_rx + 1) * r_size + t_pos.x
				var min_z_3d = float(min_rz) * r_size + t_pos.z
				var max_z_3d = float(max_rz + 1) * r_size + t_pos.z

				var min_x_2d = min_x_3d / scale_factor
				var max_x_2d = max_x_3d / scale_factor
				var min_y_2d = min_z_3d / (scale_factor * correction_z)
				var max_y_2d = max_z_3d / (scale_factor * correction_z)

				var calculated_rect = Rect2(min_x_2d, min_y_2d, max_x_2d - min_x_2d, max_y_2d - min_y_2d)

				if is_instance_valid(temp_scene_to_free):
					_remove_temp_child(host_parent, temp_scene_to_free)
					temp_scene_to_free.queue_free()
					temp_scene_to_free = null
					host_parent = null

				terrain_bounds_by_zone[z_key] = calculated_rect
				return calculated_rect

	if is_instance_valid(temp_scene_to_free):
		_remove_temp_child(host_parent, temp_scene_to_free)
		temp_scene_to_free.queue_free()
		temp_scene_to_free = null
		host_parent = null

	# Fallback si no hay Terrain3D: leer de MAPS_CONFIG o dimensiones base
	var fallback_w = 10000.0
	var fallback_h = 10000.0
	if GameConstants.get("MAPS_CONFIG") and z_key in GameConstants.MAPS_CONFIG:
		var mc = GameConstants.MAPS_CONFIG[z_key]
		if mc.has("width") and float(mc.width) > 0: fallback_w = float(mc.width)
		if mc.has("height") and float(mc.height) > 0: fallback_h = float(mc.height)

	var fallback_rect = Rect2(0.0, 0.0, fallback_w, fallback_h)
	terrain_bounds_by_zone[z_key] = fallback_rect
	return fallback_rect

static func get_or_create_terrain_texture(zone_id: Variant, rect_or_width: Variant = null, height_or_tree: Variant = null, tree_arg: SceneTree = null) -> ImageTexture:
	var z_key = str(zone_id)
	if terrain_cache_by_zone.has(z_key) and is_instance_valid(terrain_cache_by_zone[z_key]):
		return terrain_cache_by_zone[z_key]

	var tree: SceneTree = null
	var world_rect: Rect2 = Rect2(0.0, 0.0, 0.0, 0.0)
	if rect_or_width is SceneTree:
		tree = rect_or_width
	elif rect_or_width is Rect2:
		world_rect = rect_or_width
		if height_or_tree is SceneTree:
			tree = height_or_tree
		elif tree_arg is SceneTree:
			tree = tree_arg
	elif rect_or_width != null and typeof(rect_or_width) in [TYPE_FLOAT, TYPE_INT]:
		var w = float(rect_or_width)
		var h = float(height_or_tree) if height_or_tree != null and typeof(height_or_tree) in [TYPE_FLOAT, TYPE_INT] else w
		world_rect = Rect2(0.0, 0.0, w, h)
		if tree_arg is SceneTree:
			tree = tree_arg
	elif height_or_tree is SceneTree:
		tree = height_or_tree
	elif tree_arg is SceneTree:
		tree = tree_arg

	if world_rect.size.x <= 0.0 or world_rect.size.y <= 0.0:
		world_rect = get_zone_rect(z_key, tree)

	var res = 256  # Resolución óptima para mapas topográficos AAA
	var img = Image.create(res, res, false, Image.FORMAT_RGBA8)
	var heights = []
	heights.resize(res * res)
	for i in range(res * res):
		heights[i] = 0.0
		
	var min_h = 99999.0
	var max_h = -99999.0
	
	var terrain_node = null
	var scale_factor = 0.02
	var correction_z = 1.41421356
	var temp_scene_to_free = null
	var host_parent = null
	
	if tree:
		var map_node = tree.get_first_node_in_group("map")
		var player = tree.get_first_node_in_group("player")
		var cur_zone = str(player.current_zone) if is_instance_valid(player) and "current_zone" in player else ""
		
		# 1. Intentar obtener el nodo de terreno del mapa activo en el juego
		if is_instance_valid(map_node) and (cur_zone == z_key or z_key == ""):
			terrain_node = map_node.get("terrain_node")
			if not is_instance_valid(terrain_node):
				if map_node.has_method("_find_terrain_node_recursive") and is_instance_valid(map_node.get("custom_scene_instance")):
					terrain_node = map_node._find_terrain_node_recursive(map_node.custom_scene_instance)
				elif is_instance_valid(map_node.get("sub_viewport")):
					terrain_node = map_node.sub_viewport.find_child("Terrain3D", true, false)
			if not is_instance_valid(terrain_node):
				terrain_node = map_node.find_child("Terrain3D", true, false)
			if "scale_factor" in map_node: scale_factor = float(map_node.scale_factor)
			if "correction_z" in map_node: correction_z = float(map_node.correction_z)
			
		# 2. Si es una zona remota o no se encontró en el mapa activo, cargar la escena pre-diseñada
		if not is_instance_valid(terrain_node):
			var candidates = _get_scene_candidates(z_key)
			for p in candidates:
				if ResourceLoader.exists(p):
					var sc_res = load(p)
					if sc_res:
						temp_scene_to_free = sc_res.instantiate()
						_disable_free_editor_textures_recursive(temp_scene_to_free)
						host_parent = _add_temp_child(tree, temp_scene_to_free)
						terrain_node = temp_scene_to_free.find_child("Terrain3D", true, false)
						if not is_instance_valid(terrain_node):
							terrain_node = _find_terrain_node_recursive(temp_scene_to_free)
						if is_instance_valid(terrain_node):
							if "scale_factor" in temp_scene_to_free: scale_factor = float(temp_scene_to_free.scale_factor)
							if "correction_z" in temp_scene_to_free: correction_z = float(temp_scene_to_free.correction_z)
							break
						else:
							_remove_temp_child(host_parent, temp_scene_to_free)
							temp_scene_to_free.queue_free()
							temp_scene_to_free = null
							host_parent = null

	var has_real_terrain = is_instance_valid(terrain_node)
	var step_x = world_rect.size.x / float(res)
	var step_y = world_rect.size.y / float(res)

	if has_real_terrain:
		for y in range(res):
			var wy = world_rect.position.y + (float(y) + 0.5) * step_y
			for x in range(res):
				var wx = world_rect.position.x + (float(x) + 0.5) * step_x
				var pos_3d = Vector3(wx * scale_factor, 0.0, wy * scale_factor * correction_z)
				var h = TerrainCollisionBaker2D.get_height_at_3d_pos(terrain_node, pos_3d)
				if is_nan(h) or is_inf(h): h = 0.0
				heights[y * res + x] = h
				if h < min_h: min_h = h
				if h > max_h: max_h = h

	# Incorporar elevaciones de muros estáticos definidos en MAPS_CONFIG (CSGBox3D, rocas, etc.)
	if GameConstants.get("MAPS_CONFIG") and z_key in GameConstants.MAPS_CONFIG:
		var z_objs = GameConstants.MAPS_CONFIG[z_key].get("objects", [])
		for obj in z_objs:
			if str(obj.get("type", "")) == "wall":
				var ox = float(obj.get("x", 0.0))
				var oy = float(obj.get("y", 0.0))
				var cw = float(obj.get("colWidth", 300.0))
				var ch = float(obj.get("colHeight", 300.0))
				var wall_h = 10.0
				var min_gx = clampi(int(((ox - cw * 0.5) - world_rect.position.x) / step_x), 0, res - 1)
				var max_gx = clampi(int(((ox + cw * 0.5) - world_rect.position.x) / step_x), 0, res - 1)
				var min_gy = clampi(int(((oy - ch * 0.5) - world_rect.position.y) / step_y), 0, res - 1)
				var max_gy = clampi(int(((oy + ch * 0.5) - world_rect.position.y) / step_y), 0, res - 1)
				for gy in range(min_gy, max_gy + 1):
					for gx in range(min_gx, max_gx + 1):
						var idx = gy * res + gx
						heights[idx] = max(heights[idx], wall_h)
						if heights[idx] > max_h: max_h = heights[idx]

	# Liberar escena temporal usada para muestreo
	if is_instance_valid(temp_scene_to_free):
		if temp_scene_to_free.get_parent():
			temp_scene_to_free.get_parent().remove_child(temp_scene_to_free)
		temp_scene_to_free.queue_free()
		temp_scene_to_free = null

	var has_elevation = (max_h - min_h) >= 0.5

	# Si no se detectaron elevaciones (mapa plano o sin datos 3D cargados), usar ruido topográfico armónico SOLO si no hay terreno real
	if not has_elevation and not has_real_terrain:
		var fn = FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX
		fn.seed = int(z_key.to_int()) * 31337 + 1013
		fn.frequency = 0.02
		fn.fractal_type = FastNoiseLite.FRACTAL_RIDGED
		fn.fractal_octaves = 4
		fn.fractal_lacunarity = 2.0
		fn.fractal_gain = 0.5
		
		min_h = 0.0
		max_h = 25.0
		for y in range(res):
			for x in range(res):
				var n = fn.get_noise_2d(float(x), float(y))
				var h = max(0.0, (n + 0.2) * 20.0)
				heights[y * res + x] = h
				if h > max_h: max_h = h
		has_elevation = true

	var h_range = max(max_h - min_h, 0.001)
	var light_dir = Vector2(-0.707, -0.707).normalized()  # Luz procedente del Noroeste (hillshading estándar)
	
	for y in range(res):
		for x in range(res):
			var idx = y * res + x
			var h = heights[idx]
			var norm_h = clamp((h - min_h) / h_range, 0.0, 1.0)
			
			# Suelo base navegable plano: fondo translúcido oscuro perfectamente integrado con el radar (¡SIN CAPA CELESTE!)
			if norm_h < 0.03:
				img.set_pixel(x, y, Color(0.012, 0.03, 0.055, 0.20))
				continue
				
			var x_prev = max(x - 1, 0)
			var x_next = min(x + 1, res - 1)
			var y_prev = max(y - 1, 0)
			var y_next = min(y + 1, res - 1)
			
			var dx = (heights[y * res + x_next] - heights[y * res + x_prev]) / (2.0 * step_x)
			var dy = (heights[y_next * res + x] - heights[y_prev * res + x]) / (2.0 * step_y)
			var slope = Vector2(dx, dy)
			
			# Hillshading: luz y sombra 3D sobre las pendientes
			var hill = slope.dot(light_dir) * 4.5
			var shade = clamp(0.55 + hill, 0.15, 1.40)
			
			# Paleta topográfica AAA (Base oscura mineral -> laderas esmeralda/teal profundo -> crestas cian neón)
			var col_base   = Color(0.02, 0.06, 0.09, 0.85)  # Inicio elevación
			var col_slope  = Color(0.04, 0.16, 0.22, 0.95)  # Ladera
			var col_ridge  = Color(0.08, 0.35, 0.42, 1.00)  # Cresta
			var col_peak   = Color(0.18, 0.65, 0.72, 1.00)  # Cima
			var col_summit = Color(0.60, 0.95, 1.00, 1.00)  # Pico más alto brillante
			
			var c: Color
			if norm_h < 0.25:
				c = col_base.lerp(col_slope, norm_h / 0.25)
			elif norm_h < 0.55:
				c = col_slope.lerp(col_ridge, (norm_h - 0.25) / 0.30)
			elif norm_h < 0.85:
				c = col_ridge.lerp(col_peak, (norm_h - 0.55) / 0.30)
			else:
				c = col_peak.lerp(col_summit, (norm_h - 0.85) / 0.15)
				
			# Aplicar volumen 3D con luz y sombra
			c.r = clamp(c.r * shade, 0.0, 1.0)
			c.g = clamp(c.g * shade, 0.0, 1.0)
			c.b = clamp(c.b * shade, 0.0, 1.0)
			
			# Curvas de nivel topográficas sutiles
			var contour = fmod(norm_h * 12.0, 1.0)
			if contour < 0.09 and norm_h > 0.08:
				c = c.lerp(Color(0.2, 0.9, 1.0, 1.0), 0.45)
			
			# Suavizado de bordes del mapa (evitar costuras duras en los límites del mundo)
			var edge_dist = min(min(x, res - 1 - x), min(y, res - 1 - y))
			if edge_dist < 4:
				c.a *= float(edge_dist) / 4.0
				
			img.set_pixel(x, y, c)
		
	terrain_image_by_zone[z_key] = img
	var tex = ImageTexture.create_from_image(img)
	terrain_cache_by_zone[z_key] = tex
	print("[WorldMap] ✅ Textura relieve AAA generada para Zona ", z_key, " Rect: ", world_rect)
	return tex


func _on_canvas_draw():
	if not is_instance_valid(map_canvas): return
	var canvas = map_canvas
	var world_rect = get_zone_rect(target_zone_id, get_tree())
	var worldW = world_rect.size.x
	var worldH = world_rect.size.y
	if worldW <= 0 or worldH <= 0: return

	var canvas_size = canvas.size
	var scale_val = min(canvas_size.x / worldW, canvas_size.y / worldH)
	var map_draw_size = Vector2(worldW * scale_val, worldH * scale_val)
	var map_draw_offset = (canvas_size - map_draw_size) / 2.0

	var player = get_tree().get_first_node_in_group("player")
	var is_player_in_zone = false
	if is_instance_valid(player):
		var p_zone = str(player.current_zone) if "current_zone" in player else "1"
		is_player_in_zone = (p_zone == target_zone_id)

	# 1. Fondo del lienzo
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas_size), Color(0.01, 0.025, 0.04, 1.0), true)

	# Transformación al área del mapa
	canvas.draw_set_transform(map_draw_offset)

	var map_rect = Rect2(Vector2.ZERO, map_draw_size)

	# 2. Textura de relieve de terreno AAA con curvas de nivel y sombreado topográfico
	var terrain_tex = get_or_create_terrain_texture(target_zone_id, world_rect, get_tree())
	if is_instance_valid(terrain_tex):
		canvas.draw_texture_rect(terrain_tex, map_rect, false)
	else:
		# Fondo holográfico de sector
		canvas.draw_rect(map_rect, Color(0.02, 0.06, 0.09, 0.9), true)

	# 3. Retícula y borde del sector
	canvas.draw_rect(map_rect, Color(0.0, 0.85, 1.0, 0.6), false, 1.5)
	
	var grid_spacing = 2000.0
	var grid_color = Color(0.0, 0.7, 0.9, 0.12)
	var start_x = ceil(world_rect.position.x / grid_spacing) * grid_spacing
	var cur_x = start_x
	while cur_x < world_rect.end.x:
		var lx = (cur_x - world_rect.position.x) * scale_val
		canvas.draw_line(Vector2(lx, 0), Vector2(lx, map_draw_size.y), grid_color, 1.0)
		cur_x += grid_spacing
		
	var start_y = ceil(world_rect.position.y / grid_spacing) * grid_spacing
	var cur_y = start_y
	while cur_y < world_rect.end.y:
		var ly = (cur_y - world_rect.position.y) * scale_val
		canvas.draw_line(Vector2(0, ly), Vector2(map_draw_size.x, ly), grid_color, 1.0)
		cur_y += grid_spacing

	var font = canvas.get_theme_font("font")

	# 4. Dibujar Objetos y estructuras del mapa desde GameConstants.MAPS_CONFIG
	if target_zone_id in GameConstants.MAPS_CONFIG:
		var zone_cfg = GameConstants.MAPS_CONFIG[target_zone_id]
		if zone_cfg.has("objects") and zone_cfg.objects is Array:
			for obj in zone_cfg.objects:
				if not (obj is Dictionary and obj.has("x") and obj.has("y")): continue
				var obj_pos = Vector2(
					(float(obj.x) - world_rect.position.x) * scale_val,
					(float(obj.y) - world_rect.position.y) * scale_val
				)
				var obj_type = str(obj.get("type", "chest"))
				var show_explicit = obj.get("show_on_minimap", false) == true or obj.get("showOnMinimap", false) == true
				var obj_label = str(obj.get("label", "")).to_lower()
				var asset_path = str(obj.get("assetPath", "")).to_lower()
				if obj_type == "wall" and (obj_label.contains("altar") or asset_path.contains("altar")):
					obj_type = "altar"

				match obj_type:
					"altar":
						canvas.draw_circle(obj_pos, 7.0, Color(0.0, 1.0, 0.5, 0.95))
						canvas.draw_circle(obj_pos, 10.0, Color(0.0, 1.0, 0.5, 0.3), false, 1.5)
						canvas.draw_string(font, obj_pos + Vector2(-3.5, 3.5), "A", HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color.WHITE)
					"chest", "vault":
						canvas.draw_circle(obj_pos, 6.0, Color(1.0, 0.85, 0.0, 0.95))
						canvas.draw_circle(obj_pos, 8.5, Color(1.0, 0.85, 0.0, 0.25), false, 1.5)
						canvas.draw_string(font, obj_pos + Vector2(-3.0, 3.0), "B", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)
					"door", "portal":
						var target_zone = str(obj.get("targetZoneId", obj.get("targetZone", "")))
						if GameConstants.get("MAPS_CONFIG") and GameConstants.MAPS_CONFIG.has(target_zone):
							var t_cfg = GameConstants.MAPS_CONFIG[target_zone]
							if t_cfg.has("visible") and t_cfg.get("visible") == false:
								continue
						canvas.draw_circle(obj_pos, 7.0, Color(0.0, 0.9, 1.0, 0.9))
						canvas.draw_circle(obj_pos, 10.0, Color(0.0, 0.9, 1.0, 0.3), false, 1.5)
						canvas.draw_string(font, obj_pos + Vector2(-3.0, 3.5), "P", HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color.WHITE)
						
						# Label con el nombre del destino del portal
						var p_dest_name = ""
						if GameConstants.MAPS_CONFIG.has(target_zone):
							p_dest_name = GameConstants.MAPS_CONFIG[target_zone].get("name", "Sector " + target_zone)
						else:
							p_dest_name = "Sector " + target_zone
						canvas.draw_string(font, obj_pos + Vector2(12, 4), p_dest_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.0, 0.9, 1.0, 0.85))
					"nexus":
						var team = str(obj.get("team", "red")).to_lower()
						var base_color = Color(1.0, 0.15, 0.15) if team == "red" else Color(0.15, 0.5, 1.0)
						canvas.draw_circle(obj_pos, 7.0, base_color)
						canvas.draw_circle(obj_pos, 11.0, Color(base_color.r, base_color.g, base_color.b, 0.3), false, 1.5)
						canvas.draw_string(font, obj_pos + Vector2(-3.5, 3.5), "N", HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color.WHITE)
					"pillar":
						var team = str(obj.get("team", "neutral")).to_lower()
						var base_color = Color(0.85, 0.85, 0.85)
						if team == "red": base_color = Color(0.9, 0.2, 0.2)
						elif team == "blue": base_color = Color(0.2, 0.4, 0.9)
						canvas.draw_circle(obj_pos, 5.5, base_color)
						canvas.draw_string(font, obj_pos + Vector2(-3.0, 3.0), "P", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)
					"tower":
						canvas.draw_circle(obj_pos, 6.0, Color(1.0, 0.55, 0.0, 0.9))
						canvas.draw_string(font, obj_pos + Vector2(-3.0, 3.0), "T", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)
					_:
						if show_explicit:
							canvas.draw_circle(obj_pos, 5.0, Color(0.0, 0.9, 1.0, 0.85))
							var ml = obj.get("minimap_letter", obj.get("letter", "*"))
							canvas.draw_string(font, obj_pos + Vector2(-2.5, 3.0), str(ml), HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)

	# 5. Dibujar Jugadores Remotos si estamos en este sector
	if is_player_in_zone:
		var pm = get_node_or_null("/root/PartyManager")
		for ent in get_tree().get_nodes_in_group("remote_players"):
			if is_instance_valid(ent) and not ent.get("is_dead") and ent.visible:
				var rpos = Vector2(
					(ent.global_position.x - world_rect.position.x) * scale_val,
					(ent.global_position.y - world_rect.position.y) * scale_val
				)
				var ent_name = str(ent.get("username")).to_upper()
				var is_party = false
				var is_clan = false
				if pm and pm.current_party and pm.current_party.get("names", []) is Array:
					for n in pm.current_party.names:
						if str(n).to_upper() == ent_name:
							is_party = true; break
				if not is_party and is_instance_valid(player):
					var my_clan = player.get("clanId")
					var remote_clan = ent.get("clanId")
					if my_clan != null and str(my_clan) != "" and str(my_clan) != "0" and str(my_clan) == str(remote_clan):
						is_clan = true

				var dot_col = Color(1, 1, 0)
				if is_clan: dot_col = Color(0, 1, 0)
				elif is_party: dot_col = Color(0, 1, 1)
				canvas.draw_circle(rpos, 3.5, dot_col)

		# 6. Jugador Local en el mapa completo
		if is_instance_valid(player):
			var p_pos = Vector2(
				(player.global_position.x - world_rect.position.x) * scale_val,
				(player.global_position.y - world_rect.position.y) * scale_val
			)
			canvas.draw_circle(p_pos, 7.0, Color(0.0, 0.9, 1.0, 0.35))
			canvas.draw_circle(p_pos, 4.5, Color.WHITE)
			var cone_len = 16.0
			var cone_spread = 0.35
			var cone_angle = player.rotation
			var cone_left = p_pos + Vector2.RIGHT.rotated(cone_angle + cone_spread) * cone_len
			var cone_right = p_pos + Vector2.RIGHT.rotated(cone_angle - cone_spread) * cone_len
			canvas.draw_colored_polygon(PackedVector2Array([p_pos, cone_left, cone_right]), Color(0.0, 0.9, 1.0, 0.85))

			# Trayectoria de autopiloto si está activo
			if player.get("is_autopilot_active") and player.get("target_position"):
				var tgt_pos = Vector2(
					(player.target_position.x - world_rect.position.x) * scale_val,
					(player.target_position.y - world_rect.position.y) * scale_val
				)
				canvas.draw_line(p_pos, tgt_pos, Color(0.0, 1.0, 0.5, 0.6), 1.5)
				canvas.draw_circle(tgt_pos, 4.0, Color(0.0, 1.0, 0.5, 0.9))

	# 7. Indicadores cardinales (N, S, E, O)
	var margin_px = 14.0
	var cardinals = [
		{"label": "N", "pos": Vector2(map_draw_size.x / 2.0, margin_px)},
		{"label": "S", "pos": Vector2(map_draw_size.x / 2.0, map_draw_size.y - margin_px)},
		{"label": "E", "pos": Vector2(map_draw_size.x - margin_px, map_draw_size.y / 2.0)},
		{"label": "O", "pos": Vector2(margin_px, map_draw_size.y / 2.0)}
	]
	for c in cardinals:
		canvas.draw_string(font, c.pos - Vector2(4, -4), c.label, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.0, 1.0, 1.0, 0.75))

	canvas.draw_set_transform(Vector2.ZERO)

static func _disable_free_editor_textures_recursive(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if "free_editor_textures" in node:
		node.set("free_editor_textures", false)
	for child in node.get_children():
		_disable_free_editor_textures_recursive(child)

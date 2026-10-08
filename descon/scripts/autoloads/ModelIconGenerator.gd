extends Node

# ==============================================================================
# ModelIconGenerator.gd - ICONOS 3D GENERADOS EN TIEMPO DE EJECUCIÓN (v1.0)
# Algunos ítems (materiales recolectables) no tienen PNG de icono pero sí un
# asset 3D (.glb). Este autoload renderiza ese modelo una sola vez en un
# SubViewport off-screen, guarda el resultado en caché y lo entrega como
# Texture2D para que el inventario pueda mostrarlo.
#
# Uso desde cualquier UI:
#   var rect = ModelIconGenerator.make_icon_rect(item, icon_path, Vector2(38, 38))
#   if rect: parent.add_child(rect)
# El rect se rellena solo cuando el render termina (señal thumbnail_ready).
# ==============================================================================

signal thumbnail_ready(model_path: String)

const THUMB_SIZE: int = 128
# Tamaño (en unidades de mundo) al que se ajusta el modelo dentro del viewport
const FIT_SIZE: float = 1.5

var _thumbnails: Dictionary = {}       # model_path -> ImageTexture
var _model_path_cache: Dictionary = {} # item_id en minúsculas -> model_path
var _queue: Array = []                 # model_path pendientes de render
var _queued: Dictionary = {}           # model_path -> true (evita duplicados)
var _busy: bool = false

var _viewport: SubViewport = null
var _camera: Camera3D = null
var _holder: Node3D = null


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "IconViewport"
	_viewport.size = Vector2i(THUMB_SIZE, THUMB_SIZE)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(_viewport)

	_camera = Camera3D.new()
	_camera.fov = 38.0
	_camera.near = 0.01
	_camera.far = 100.0
	_viewport.add_child(_camera)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	key_light.light_energy = 1.7
	_viewport.add_child(key_light)

	var fill_light := OmniLight3D.new()
	fill_light.position = Vector3(-1.5, 1.0, 1.5)
	fill_light.light_energy = 0.9
	fill_light.omni_range = 10.0
	_viewport.add_child(fill_light)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.83, 0.95)
	env.ambient_light_energy = 1.5
	env_node.environment = env
	_viewport.add_child(env_node)

	_holder = Node3D.new()
	_holder.name = "IconHolder"
	_viewport.add_child(_holder)

	# Si el admin cambia la config, las rutas de asset 3D pueden variar
	var nm = _find_singleton("NetworkManager")
	if is_instance_valid(nm):
		for signal_name in ["config_updated", "admin_config_updated"]:
			if nm.has_signal(signal_name) and not nm.is_connected(signal_name, _on_config_changed):
				nm.connect(signal_name, _on_config_changed)


func _on_config_changed(_cfg = {}) -> void:
	_model_path_cache.clear()


func _process(_delta: float) -> void:
	if _busy or _queue.is_empty():
		return
	_render_next()


# ==============================================================================
# API PÚBLICA
# ==============================================================================

# Devuelve la textura del icono 2D si existe; si no, la miniatura 3D del asset.
# Si la miniatura aún no está renderizada devuelve null y encola el render.
func get_item_texture(item: Dictionary, icon_path: String = "") -> Texture2D:
	var path := icon_path.strip_edges()
	if path == "" or path == "null":
		path = str(item.get("icon", "")).strip_edges()
	if path != "" and path != "null" and ResourceLoader.exists(path):
		var cached := InventoryCache.get_texture(path)
		if cached != null:
			return cached
		var loaded = load(path)
		if loaded is Texture2D:
			return loaded

	var model_path := resolve_model_path(item)
	if model_path != "":
		return get_thumbnail(model_path)
	return null


# Miniatura 3D cacheada. Devuelve null y encola el render si aún no existe.
func get_thumbnail(model_path: String) -> Texture2D:
	if model_path == "":
		return null
	if _thumbnails.has(model_path):
		return _thumbnails[model_path]
	_request_render(model_path)
	return null


# Crea un TextureRect listo para añadir a la UI.
# - Con icono 2D válido: lo pone enseguida.
# - Con solo asset 3D: lo rellena cuando el render termina (thumbnail_ready).
# - Sin nada que mostrar: devuelve null.
func make_icon_rect(item: Dictionary, icon_path: String = "", size: Vector2 = Vector2.ZERO) -> TextureRect:
	var rect := TextureRect.new()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if size.x > 0.0 and size.y > 0.0:
		rect.custom_minimum_size = size

	var tex := get_item_texture(item, icon_path)
	if tex != null:
		rect.texture = tex
		return rect

	var model_path := resolve_model_path(item)
	if model_path == "":
		return null
	_apply_when_ready(rect, model_path)
	return rect


# Ruta del asset 3D asociado a un ítem (assetPath propio o lookup por id).
func resolve_model_path(item: Dictionary) -> String:
	if item.is_empty():
		return ""
	var direct := str(item.get("assetPath", "")).strip_edges()
	if _is_usable_model(direct):
		return direct
	return resolve_model_path_by_id(str(item.get("id", "")))


func resolve_model_path_by_id(item_id: String) -> String:
	var key := item_id.to_lower()
	if key == "":
		return ""
	if _model_path_cache.has(key):
		return _model_path_cache[key]

	var found := ""
	for shop in _collect_shops():
		found = _find_asset_in_shop(shop, key)
		if found != "":
			break
	if found != "":
		_model_path_cache[key] = found
	return found


# ==============================================================================
# RENDER 3D -> TEXTURA
# ==============================================================================

func _request_render(model_path: String) -> void:
	if _thumbnails.has(model_path) or _queued.has(model_path):
		return
	if not ResourceLoader.exists(model_path):
		return
	_queued[model_path] = true
	_queue.append(model_path)


func _render_next() -> void:
	_busy = true
	var path: String = _queue.pop_front()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var mounted := _mount_model(path)
	if mounted:
		# Dejamos dos frames para que el viewport dibuje el modelo
		await get_tree().process_frame
		await get_tree().process_frame
		var img: Image = _viewport.get_texture().get_image()
		if img != null and not img.is_empty():
			_thumbnails[path] = ImageTexture.create_from_image(img)

	_unmount_model()
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_queued.erase(path)
	_busy = false
	thumbnail_ready.emit(path)


func _mount_model(path: String) -> bool:
	_unmount_model()
	var scene: PackedScene = InventoryCache.get_model(path)
	if scene == null:
		return false

	var model = scene.instantiate()
	if not (model is Node3D):
		model.free()
		return false

	# Luces quemadas dentro del asset no aportan nada en la miniatura
	for child_light in model.find_children("*", "Light3D", true):
		child_light.free()

	_holder.add_child(model)

	var aabb := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true):
		var local_aabb := _global_aabb(mi)
		if first:
			aabb = local_aabb
			first = false
		else:
			aabb = aabb.merge(local_aabb)

	if first:
		# Sin mallas detectadas: modelo vacío, no sirve como icono
		return false

	var max_dim: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if max_dim <= 0.0001:
		max_dim = 1.0

	var s := FIT_SIZE / max_dim
	_holder.scale = Vector3.ONE * s
	_holder.position = -aabb.get_center() * s

	var dist: float = (FIT_SIZE * 0.5) / tan(deg_to_rad(_camera.fov * 0.5)) * 1.6
	var dir := Vector3(0.35, 0.5, 1.0).normalized()
	_camera.position = dir * dist
	_camera.look_at(Vector3.ZERO)
	return true


func _unmount_model() -> void:
	if not is_instance_valid(_holder):
		return
	for child in _holder.get_children():
		_holder.remove_child(child)
		child.free()
	_holder.scale = Vector3.ONE
	_holder.position = Vector3.ZERO


# AABB de una malla en coordenadas del mundo (Godot 4 no tiene AABB.transformed)
func _global_aabb(mesh_instance: MeshInstance3D) -> AABB:
	var local := mesh_instance.get_aabb()
	var gt := mesh_instance.global_transform
	var min_v := Vector3(INF, INF, INF)
	var max_v := Vector3(-INF, -INF, -INF)
	for i in range(8):
		var p: Vector3 = gt * local.get_endpoint(i)
		min_v = Vector3(minf(min_v.x, p.x), minf(min_v.y, p.y), minf(min_v.z, p.z))
		max_v = Vector3(maxf(max_v.x, p.x), maxf(max_v.y, p.y), maxf(max_v.z, p.z))
	return AABB(min_v, max_v - min_v)


func _apply_when_ready(rect: TextureRect, model_path: String) -> void:
	if not ResourceLoader.exists(model_path):
		return
	while true:
		if not is_instance_valid(rect):
			return
		var ready_path: String = await thumbnail_ready
		if ready_path != model_path:
			continue
		if is_instance_valid(rect):
			var tex = _thumbnails.get(model_path, null)
			if tex is Texture2D:
				rect.texture = tex
		return


# ==============================================================================
# LOOKUP DE ASSETS 3D EN LA CONFIGURACIÓN DEL SERVIDOR
# ==============================================================================

func _is_usable_model(path: String) -> bool:
	return path != "" and path != "null" and ResourceLoader.exists(path)


func _collect_shops() -> Array:
	var shops: Array = []
	var gc = _find_singleton("GameConstants")
	if is_instance_valid(gc):
		if "FULL_CONFIG" in gc:
			var full_config = gc.get("FULL_CONFIG")
			if typeof(full_config) == TYPE_DICTIONARY:
				shops.append(full_config.get("shopItems", {}))
		if "SHOP_ITEMS" in gc:
			var shop_items = gc.get("SHOP_ITEMS")
			if typeof(shop_items) == TYPE_DICTIONARY:
				shops.append(shop_items)

	var nm = _find_singleton("NetworkManager")
	if is_instance_valid(nm) and "server_config" in nm:
		var server_config = nm.get("server_config")
		if typeof(server_config) == TYPE_DICTIONARY:
			shops.append(server_config.get("shopItems", {}))
	return shops


func _find_singleton(node_name: String) -> Node:
	var main_loop = Engine.get_main_loop()
	if main_loop is SceneTree:
		var tree_root: Node = (main_loop as SceneTree).root
		if is_instance_valid(tree_root):
			return tree_root.get_node_or_null(node_name)
	return null


func _find_asset_in_shop(shop, id_lower: String) -> String:
	if typeof(shop) != TYPE_DICTIONARY:
		return ""
	# Prioridad: materiales recolectables
	var found := _find_asset_in_list(shop.get("resources", []), id_lower)
	if found != "":
		return found
	for cat_key in shop:
		if str(cat_key) == "resources":
			continue
		found = _find_asset_in_list(shop[cat_key], id_lower)
		if found != "":
			return found
	return ""


func _find_asset_in_list(lst, id_lower: String) -> String:
	if lst is Array:
		for entry in lst:
			if entry is Dictionary and str(entry.get("id", "")).to_lower() == id_lower:
				var asset := str(entry.get("assetPath", "")).strip_edges()
				if _is_usable_model(asset):
					return asset
	elif lst is Dictionary:
		for sub_key in lst:
			var found := _find_asset_in_list(lst[sub_key], id_lower)
			if found != "":
				return found
	return ""

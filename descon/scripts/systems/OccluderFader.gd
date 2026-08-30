extends Node
class_name OccluderFader
# OccluderFader.gd (v950.0) - Oclusión compatible basada en 90ca0a6
# Integra duplicación segura de materiales base y dither shader en overlay.
# Incorpora lectura de materiales embebidos nativos del GLB y fallback de transparencia nativa.

const DITHER_SHADER := preload("res://resources/shaders/occluder_dither.gdshader")
const OCCLUDER_TYPES := ["wall", "decor", "tower", "pillar", "altar", "vault", "chest", "custom"]

# Config
@export var faded_alpha: float = 0.18 # transparencia del albedo del material base (0.18)
@export var dither_fade_target: float = 0.18 # target de dither overlay (0.18)
@export var fade_duration: float = 0.22
@export var check_interval: float = 0.045
@export var occlusion_extra_radius: float = 0.9
@export var min_proj_dist: float = 1.0
@export var use_dither: bool = true
@export var debug_log: bool = false

var _occluders: Array[Node3D] = []
var _cache: Dictionary = {} # Node3D -> { meshes: Array[MeshInstance3D], mats: Array[Material], orig_alphas: Array[float], dither_mats: Array[ShaderMaterial] }
var _faded_state: Dictionary = {} # Node3D -> bool
var _time_accum: float = 0.0
var _map_ref: Node = null

func _ready() -> void:
	_map_ref = get_parent()
	if _map_ref == null:
		_map_ref = get_tree().get_first_node_in_group("map")

func is_occluder_type(t: String) -> bool:
	return t.to_lower() in OCCLUDER_TYPES

# REGISTRO
func register_occluder(node: Node3D, force: bool = false) -> void:
	if not is_instance_valid(node):
		return
	if node in _occluders and not force:
		return
	if node.is_class("Terrain3D") or "Terrain3D" in node.name:
		return
	if node is Camera3D or node is Light3D:
		return
	if node.get_class() == "WorldEnvironment":
		return
		

	var meshes := _collect_meshes(node)
	if meshes.is_empty():
		return
		
	_occluders.append(node)
	_faded_state[node] = false
	_setup_materials_for(node, meshes)
	if debug_log:
		print("[OccluderFader] Registrado: ", node.name, " meshes=", meshes.size())

func unregister_occluder(node: Node3D) -> void:
	_cleanup_materials(node)
	if node in _occluders:
		_occluders.erase(node)
	if node in _faded_state:
		_faded_state.erase(node)

func update_occlusion(camera_pos: Vector3, target_pos: Vector3, delta: float) -> void:
	if _occluders.is_empty():
		return
	_time_accum += delta
	if _time_accum < check_interval:
		return
	_time_accum = 0.0
	
	if camera_pos.distance_squared_to(target_pos) < 0.01:
		return
	var dir := (target_pos - camera_pos).normalized()
	var max_dist := camera_pos.distance_to(target_pos)
	if max_dist < 0.1:
		return

	var to_fade: Dictionary = {}
	for occ in _occluders:
		if not is_instance_valid(occ):
			continue
		var to_occ: Vector3 = occ.global_position - camera_pos
		var proj: float = to_occ.dot(dir)
		if proj < min_proj_dist or proj > max_dist - 0.5:
			continue
		var closest: Vector3 = camera_pos + dir * proj
		var radius: float = _estimate_radius(occ) + occlusion_extra_radius
		if occ.global_position.distance_to(closest) > radius:
			continue
		var ray_y_at_proj: float = lerpf(camera_pos.y, target_pos.y, proj / max_dist)
		var occ_top_y: float = _estimate_top_y(occ)
		if occ_top_y < ray_y_at_proj - 0.6:
			continue
		to_fade[occ] = true

	for occ in _occluders:
		if not is_instance_valid(occ):
			continue
		var should_fade: bool = to_fade.has(occ)
		var is_faded: bool = _faded_state.get(occ, false)
		if should_fade != is_faded:
			_set_faded(occ, should_fade)

# ---- INTERNOS ----

func _setup_materials_for(node: Node3D, meshes: Array[MeshInstance3D]) -> void:
	var mats: Array = []
	var orig_alphas: Array[float] = []
	var dither_mats: Array[ShaderMaterial] = []
	
	for mi in meshes:
		var cur_mat: Material = mi.material_override
		if cur_mat == null:
			cur_mat = mi.get_active_material(0)
		if cur_mat == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			cur_mat = mi.mesh.surface_get_material(0)
			
		# Si ya preparamos este mesh, reutilizar
		if mi.has_meta("_occluder_prepared") and is_instance_valid(cur_mat):
			mats.append(cur_mat)
			orig_alphas.append(mi.get_meta("_orig_alpha", 1.0))
			var dm = mi.get_meta("_dither_mat", null)
			dither_mats.append(dm)
			continue

		var work_mat: Material = null
		var orig_a: float = 1.0
		
		if cur_mat is BaseMaterial3D:
			# Duplicar de forma segura para no alterar el original en el disco
			var bm: BaseMaterial3D = cur_mat.duplicate() as BaseMaterial3D
			orig_a = bm.albedo_color.a
			bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mi.material_override = bm
			work_mat = bm
		elif cur_mat is ShaderMaterial:
			var shm: ShaderMaterial = (cur_mat as ShaderMaterial).duplicate() as ShaderMaterial
			mi.material_override = shm
			work_mat = shm
			orig_a = 1.0
		elif cur_mat != null:
			work_mat = cur_mat
		else:
			# Evitar asignar un override de StandardMaterial3D blanco si no tiene material visible en el slot
			work_mat = null

		mi.set_meta("_occluder_prepared", true)
		mi.set_meta("_orig_alpha", orig_a)
		mats.append(work_mat)
		orig_alphas.append(orig_a)

		if use_dither:
			var dmat: ShaderMaterial = ShaderMaterial.new()
			dmat.shader = DITHER_SHADER
			dmat.set_shader_parameter("dither_fade", 1.0)
			mi.material_overlay = dmat
			mi.set_meta("_dither_mat", dmat)
			dither_mats.append(dmat)
		else:
			dither_mats.append(null)

	_cache[node] = { "meshes": meshes, "mats": mats, "orig_alphas": orig_alphas, "dither_mats": dither_mats }

func _cleanup_materials(node: Node3D) -> void:
	var data = _cache.get(node, null)
	if data == null:
		return
	var meshes: Array = data.get("meshes", [])
	for mi in meshes:
		if is_instance_valid(mi):
			if mi.material_overlay is ShaderMaterial and (mi.material_overlay as ShaderMaterial).shader == DITHER_SHADER:
				mi.material_overlay = null
			mi.remove_meta("_occluder_prepared")
			mi.remove_meta("_orig_alpha")
			mi.remove_meta("_dither_mat")
			mi.transparency = 0.0
			mi.material_override = null
	_cache.erase(node)

func _set_faded(node: Node3D, faded: bool) -> void:
	if not is_instance_valid(node):
		return
	_faded_state[node] = faded
	var data = _cache.get(node, null)
	if data == null:
		var meshes2 := _collect_meshes(node)
		if meshes2.is_empty():
			return
		_setup_materials_for(node, meshes2)
		data = _cache[node]
		
	var meshes: Array = data.get("meshes", [])
	var mats: Array = data.get("mats", [])
	var orig_alphas: Array = data.get("orig_alphas", [])
	var dither_mats: Array = data.get("dither_mats", [])
	
	# El usuario solicitó opacidad fija al 20% para todos los objetos por igual
	var effective_fade_alpha: float = 0.20
	var effective_dither: float = 0.20

	var target_a: float = effective_fade_alpha if faded else 1.0
	var target_dither: float = effective_dither if faded else 1.0
	
	for i in range(mats.size()):
		var mi = meshes[i]
		if not is_instance_valid(mi):
			continue
		var m = mats[i]
		var orig_a: float = orig_alphas[i] if i < orig_alphas.size() else 1.0
		var final_a := orig_a * target_a
		
		if is_instance_valid(m) and m is BaseMaterial3D:
			var tw := create_tween()
			tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.tween_property(m, "albedo_color:a", final_a, fade_duration)
		elif is_instance_valid(m) and m is ShaderMaterial:
			var sm := m as ShaderMaterial
			for param in ["alpha", "fade", "opacity", "albedo_alpha", "transparency"]:
				if sm.get_shader_parameter(param) != null:
					var tw2 := create_tween()
					tw2.tween_property(sm, "shader_parameter/" + param, final_a, fade_duration)
					break
		else:
			# Fallback: Usar la transparencia nativa del MeshInstance3D si no pudimos duplicar el material
			var tw_trans := create_tween()
			tw_trans.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw_trans.tween_property(mi, "transparency", (1.0 - target_a), fade_duration)

		if i < dither_mats.size():
			var dm = dither_mats[i]
			if is_instance_valid(dm):
				var twd := create_tween()
				twd.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				twd.tween_property(dm, "shader_parameter/dither_fade", target_dither, fade_duration)

func _collect_meshes(root: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var n = stack.pop_back()
		if n is MeshInstance3D:
			if n.visible:
				out.append(n as MeshInstance3D)
		for c in n.get_children():
			if c is Node3D:
				stack.append(c)
	return out

func _estimate_radius(node: Node3D) -> float:
	var aabb := _calculate_aabb(node)
	if aabb.size.length_squared() > 0.01:
		var rad = max(aabb.size.x, aabb.size.z) * 0.55 + aabb.size.y * 0.15
		return clampf(rad, 1.0, 15.0)
	return 1.5

func _estimate_top_y(node: Node3D) -> float:
	var aabb := _calculate_aabb(node)
	if aabb.size.length_squared() > 0.01:
		return aabb.position.y + aabb.size.y
	return node.global_position.y + 1.0

func _calculate_aabb(node: Node3D) -> AABB:
	var total := AABB()
	var first := true
	var meshes := _collect_meshes(node)
	if meshes.is_empty():
		return total
	for mi in meshes:
		var local_aabb: AABB = mi.get_aabb()
		var world_aabb := mi.global_transform * local_aabb
		if first:
			total = world_aabb
			first = false
		else:
			total = total.merge(world_aabb)
	return total

extends Node
class_name OccluderFader
# OccluderFader.gd - Sistema A+B sin romper nada (fade + dither)
# Hace fade dithered a paredes/objetos que tapan la linea cámara -> jugador.
# No requiere StaticBody3D ni modificar materiales originales de forma destructiva.
# Usa overlay con shader occluder_dither.gdshader (descartado screen-door) + tween de fade.

const DITHER_SHADER := preload("res://resources/shaders/occluder_dither.gdshader")
# Tipos que pueden ocluir (altos). door/market/spawn/nexus son bajos o interactivos, no ocluyen.
const OCCLUDER_TYPES := ["wall", "decor", "tower", "pillar", "altar", "vault", "chest", "custom"]

# Config - tweakable desde BaseMap o SettingsManager
@export var faded_alpha: float = 0.18 # cuando está ocluyendo - 0.18 ~ 82% invisible (A: alpha)
@export var dither_fade_target: float = 0.18 # para B: dither 0.18 ~ 18% pixeles quedan
@export var fade_duration: float = 0.22
@export var check_interval: float = 0.045 # ~22hz, muy barato
@export var occlusion_extra_radius: float = 0.9 # margen extra al AABB
@export var min_proj_dist: float = 1.0 # ignorar muy cerca de cámara
@export var debug_log: bool = false
@export var use_dither: bool = true # true = B (dither screen-door, sin sorting issues), false = solo alpha

var _occluders: Array[Node3D] = []
var _cache: Dictionary = {} # Node3D -> { meshes: Array[MeshInstance3D], mats: Array[Material], orig_alphas: Array[float], dither_mats: Array[ShaderMaterial] }
var _faded_state: Dictionary = {} # Node3D -> bool
var _time_accum: float = 0.0
var _map_ref: Node = null # BaseMap ref para scale_factor/correction_z

func _ready() -> void:
	_map_ref = get_parent() # BaseMap nos añade como hijo
	if _map_ref == null:
		_map_ref = get_tree().get_first_node_in_group("map")

func is_occluder_type(t: String) -> bool:
	return t.to_lower() in OCCLUDER_TYPES

# REGISTRO - llamado por BaseMap al instanciar cada objeto 3D
func register_occluder(node: Node3D, force: bool = false) -> void:
	if not is_instance_valid(node):
		return
	if node in _occluders and not force:
		return
	# Evitar registrar Terrain3D, Camera, luces, etc
	if node.is_class("Terrain3D") or "Terrain3D" in node.name:
		return
	if node is Camera3D or node is Light3D:
		return
	if node.get_class() == "WorldEnvironment":
		return
	# Solo registrar si tiene meshes visibles con altura relevante
	var meshes := _collect_meshes(node)
	if meshes.is_empty():
		return
	# Filtro altura: si está muy bajo (y < 0.1) y es decor pequeño, igual ocluye si es grande, así que no filtramos agresivo
	_occluders.append(node)
	_faded_state[node] = false
	_setup_materials_for(node, meshes)
	if debug_log:
		print("[OccluderFader] Registrado: ", node.name, " meshes=", meshes.size(), " pos=", node.global_position)

func unregister_occluder(node: Node3D) -> void:
	if node in _occluders:
		_occluders.erase(node)
		_cleanup_materials(node)
		_faded_state.erase(node)

func clear_all() -> void:
	for occ in _occluders.duplicate():
		_cleanup_materials(occ)
	_occluders.clear()
	_faded_state.clear()
	_cache.clear()

# API principal - llamado cada frame desde BaseMap._process
func update_occlusion(camera_pos: Vector3, target_pos: Vector3, delta: float) -> void:
	if _occluders.is_empty():
		return
	_time_accum += delta
	if _time_accum < check_interval:
		return
	_time_accum = 0.0
	# Validar que cámara y target sean válidos
	if camera_pos.distance_squared_to(target_pos) < 0.01:
		return
	var dir := (target_pos - camera_pos).normalized()
	var max_dist := camera_pos.distance_to(target_pos)
	if max_dist < 0.1:
		return

	var to_fade: Dictionary = {}
	# Pre-calcular para cada occluder si está entre cámara y player y cerca del rayo
	for occ in _occluders:
		if not is_instance_valid(occ):
			continue
		# Distancia proyectada sobre el rayo
		var to_occ: Vector3 = occ.global_position - camera_pos
		var proj: float = to_occ.dot(dir)
		if proj < min_proj_dist or proj > max_dist - 0.5:
			continue
		var closest: Vector3 = camera_pos + dir * proj
		# Radio aproximado del occluder (AABB /2 + margen)
		var radius: float = _estimate_radius(occ) + occlusion_extra_radius
		# Chequeo cilíndrico al rayo
		if occ.global_position.distance_to(closest) > radius:
			continue
		# Chequeo altura: si el objeto está muy por debajo del rayo, no ocluye (ej suelo)
		# El rayo va de cámara (y alto) a target (y ~0.5-1.0). Si el mesh top está por debajo del rayo en ese punto, no tapa.
		var ray_y_at_proj: float = lerpf(camera_pos.y, target_pos.y, proj / max_dist)
		var occ_top_y: float = _estimate_top_y(occ)
		if occ_top_y < ray_y_at_proj - 0.6:
			continue
		to_fade[occ] = true

	# Aplicar cambios solo si estado cambió (evita tween spam)
	for occ in _occluders:
		if not is_instance_valid(occ):
			continue
		var should_fade: bool = to_fade.has(occ)
		var is_faded: bool = _faded_state.get(occ, false)
		if should_fade != is_faded:
			_set_faded(occ, should_fade)

# ---- INTERNOS ----

func _collect_meshes(root: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var n = stack.pop_back()
		if n is MeshInstance3D:
			if n.mesh != null and n.visible:
				# Ignorar meshes de helper/colisión del editor (verde semitransparente) - ya no están en runtime pero por seguridad
				out.append(n as MeshInstance3D)
		for c in n.get_children():
			if c is Node3D:
				stack.append(c)
	return out

func _setup_materials_for(node: Node3D, meshes: Array[MeshInstance3D]) -> void:
	# Prepara materiales únicos para fade seguro sin romper el original.
	# A: Para StandardMaterial3D -> duplicate + TRANSPARENCY_ALPHA + tween albedo.a
	# B: Si use_dither -> además creamos dither overlay next_pass con el shader (screen-door) para evitar sorting issues de GL Compatibility.
	var mats: Array = []
	var orig_alphas: Array[float] = []
	var dither_mats: Array[ShaderMaterial] = []
	for mi in meshes:
		var cur_mat: Material = mi.material_override
		if cur_mat == null:
			cur_mat = mi.get_active_material(0)
		# Si ya preparamos este mesh, reutilizar
		if mi.has_meta("_occluder_prepared") and is_instance_valid(cur_mat):
			mats.append(cur_mat)
			orig_alphas.append(mi.get_meta("_orig_alpha", 1.0))
			var dm = mi.get_meta("_dither_mat", null)
			dither_mats.append(dm)
			continue

		var work_mat: Material = null
		var orig_a: float = 1.0
		if cur_mat is StandardMaterial3D:
			var sm: StandardMaterial3D = (cur_mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			orig_a = sm.albedo_color.a
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			# Evitar que el fondo atraviese: mantener cull_back y depth_draw_opaque
			mi.material_override = sm
			work_mat = sm
		elif cur_mat is ShaderMaterial:
			# Intentar duplicar ShaderMaterial y buscar param alpha/fade
			var shm: ShaderMaterial = (cur_mat as ShaderMaterial).duplicate() as ShaderMaterial
			mi.material_override = shm
			work_mat = shm
			orig_a = 1.0
		elif cur_mat != null:
			# Otro tipo (ej. ORMMaterial) -> envolver en StandardMaterial simple que respete textura si existe
			var sm2 := StandardMaterial3D.new()
			# Intentar copiar albedo_texture si existía en el original via resource
			mi.material_override = sm2
			work_mat = sm2
		else:
			# Sin material -> crear uno por defecto
			var sm3 := StandardMaterial3D.new()
			sm3.albedo_color = Color(1,1,1,1)
			sm3.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mi.material_override = sm3
			work_mat = sm3

		mi.set_meta("_occluder_prepared", true)
		mi.set_meta("_orig_alpha", orig_a)
		mats.append(work_mat)
		orig_alphas.append(orig_a)

		# B: Dither next_pass (opcional, se tweenea en paralelo al alpha para efecto screen-door + alpha)
		if use_dither:
			var dmat: ShaderMaterial = ShaderMaterial.new()
			dmat.shader = DITHER_SHADER
			var init_fade: float = 1.0
			dmat.set_shader_parameter("dither_fade", init_fade)
			# next_pass se encadena DESPUÉS del material base. Con nuestro shader, el discard del next_pass
			# hará agujeritos en la segunda pasada, pero la base ya es semi-transparente por alpha -> combinamos ambos.
			# Para que no duplique geometría, usamos material_overlay en su lugar con el mismo shader pero ahora
			# lo dejamos como overlay que recorta con dither: el alpha ya hace translúcido y el dither rompe sorting.
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
	# No restauramos material_override a null para no perder el duplicado (ya es único y seguro).
	# Solo limpiamos overlay dither y metas.
	for mi in meshes:
		if is_instance_valid(mi):
			if mi.material_overlay is ShaderMaterial and (mi.material_overlay as ShaderMaterial).shader == DITHER_SHADER:
				mi.material_overlay = null
			mi.remove_meta("_occluder_prepared")
			mi.remove_meta("_orig_alpha")
			mi.remove_meta("_dither_mat")
			# Restaurar alpha original
			var orig_idx = meshes.find(mi)
			if orig_idx != -1:
				var mats: Array = data.get("mats", [])
				var orig_as: Array = data.get("orig_alphas", [])
				if orig_idx < mats.size() and orig_idx < orig_as.size():
					var m = mats[orig_idx]
					if m is StandardMaterial3D:
						(m as StandardMaterial3D).albedo_color.a = orig_as[orig_idx]
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
	var mats: Array = data.get("mats", [])
	var orig_alphas: Array = data.get("orig_alphas", [])
	var dither_mats: Array = data.get("dither_mats", [])
	var target_a := (faded_alpha if faded else 1.0)
	var target_dither := (dither_fade_target if faded else 1.0)
	for i in range(mats.size()):
		var m = mats[i]
		if not is_instance_valid(m):
			continue
		var orig_a: float = orig_alphas[i] if i < orig_alphas.size() else 1.0
		var final_a := orig_a * target_a
		if m is StandardMaterial3D:
			var tw := create_tween()
			tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			# Tween directo a albedo_color.a es válido en 4.x
			tw.tween_property(m, "albedo_color:a", final_a, fade_duration)
		elif m is ShaderMaterial:
			# Intentar tweenear uniforms comunes
			var sm := m as ShaderMaterial
			var found := false
			for param in ["alpha", "fade", "opacity", "albedo_alpha", "transparency"]:
				if sm.get_shader_parameter(param) != null:
					var tw2 := create_tween()
					tw2.tween_property(sm, "shader_parameter/" + param, final_a, fade_duration)
					found = true
					break
			if not found and sm.shader == null:
				# Fallback hard cut
				pass
		# B: tween dither en paralelo
		if i < dither_mats.size():
			var dm = dither_mats[i]
			if is_instance_valid(dm):
				var twd := create_tween()
				twd.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				twd.tween_property(dm, "shader_parameter/dither_fade", target_dither, fade_duration)
	if debug_log:
		print("[OccluderFader] ", node.name, " -> ", "FADED" if faded else "OPAQUE", " alpha=", target_a, " dither=", target_dither)

func _estimate_radius(node: Node3D) -> float:
	# Usa AABB global si hay MeshInstance, si no fallback 1.5
	var aabb := _calculate_aabb(node)
	if aabb.size.length_squared() > 0.01:
		# radio = max de xz + y/2, aproximado a cilindro
		return max(aabb.size.x, aabb.size.z) * 0.55 + aabb.size.y * 0.15
	return 1.5

func _estimate_top_y(node: Node3D) -> float:
	var aabb := _calculate_aabb(node)
	if aabb.size.length_squared() > 0.01:
		return aabb.position.y + aabb.size.y
	return node.global_position.y + 1.0

func _calculate_aabb(node: Node3D) -> AABB:
	# Similar a BaseMap._calculate_local_aabb pero en espacio global y solo meshes
	var total := AABB()
	var first := true
	var stack: Array = [[node, Transform3D.IDENTITY]]
	# Necesitamos el global_transform del root para pasar a global, simplificamos acumulando world
	# Si el node ya está en el árbol, podemos usar global_transform * local aabb directamente para cada mesh
	var meshes := _collect_meshes(node)
	if meshes.is_empty():
		return total
	for mi in meshes:
		if mi.mesh == null:
			continue
		var local_aabb: AABB
		if mi.has_method("get_aabb"):
			local_aabb = mi.get_aabb()
		else:
			local_aabb = mi.mesh.get_aabb()
		var world_aabb := mi.global_transform * local_aabb
		if first:
			total = world_aabb
			first = false
		else:
			total = total.merge(world_aabb)
	return total

# Limpieza automática al salir objetos
func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		clear_all()

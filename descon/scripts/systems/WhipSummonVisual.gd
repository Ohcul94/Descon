extends Node2D

# WhipSummonVisual.gd (v415.0 - Latigo Dominante)
# VFX del látigo que golpea a un objetivo N veces a una cadencia dada.
# El servidor es el dueño de la verdad (spawn, posición, daño, cadencia salen de Server).
# Aquí SOLO se renderiza.

var map_node: Node = null
var enemy_node: Node = null
var target_node: Node = null

var _is_3d := false
var _sf := 0.02
var _cz := 1.41421356

var _active := false
var _hits_done := 0
var _total_hits := 3
var _cadence := 300
var _damage := 50
var _target_pos := Vector2.ZERO
var _enemy_pos := Vector2.ZERO
var _whip_timer := 0.0
var _active_whip := null
var _hit_effects: Array = []

const WHIP_TEX := preload("res://VFX/textures/T_VFX_sparks42.jpg")
const WHIP_GLOW_TEX := preload("res://VFX/textures/T_VFX_FireBall_s1_alpha.jpg")

# ------------------------------------------------------------------------------
# API llamada desde BossActionHandler.handle_whip_summon_action()
# ------------------------------------------------------------------------------
func setup(p_data: Dictionary, p_map: Node, p_enemy: Node = null) -> void:
	map_node = p_map
	enemy_node = p_enemy
	_active = true
	_hits_done = 0
	_total_hits = int(p_data.get("hits", 3))
	_cadence = int(p_data.get("cadence", 300))
	_damage = int(p_data.get("damage", 50))
	_enemy_pos = Vector2(float(p_data.get("x", 0.0)), float(p_data.get("y", 0.0)))
	_target_pos = Vector2(float(p_data.get("targetX", 0.0)), float(p_data.get("targetY", 0.0)))
	_target_node = null
	# Buscar nodo objetivo en el mapa
	if enemy_node and is_instance_valid(enemy_node):
		enemy_node.get_parent().get_node_or_null("target") # placeholder
	# Spawn efecto inicial del látigo saliendo del enemigo
	_spawn_whip_effect()

func update_hit(data: Dictionary) -> void:
	_hits_done += 1
	_target_pos = Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
	# Crear efecto de impacto del látigo en el objetivo
	_spawn_hit_effect(_target_pos)
	# Spawn siguiente whip si quedan más golpes
	if _hits_done < _total_hits:
		_whip_timer = _cadence / 1000.0
		_spawn_whip_effect()

# ------------------------------------------------------------------------------
# Spawn del efecto de látigo desde el enemigo hacia el target
# ------------------------------------------------------------------------------
func _spawn_whip_effect() -> void:
	if not is_instance_valid(enemy_node):
		return
	var map = get_tree().get_first_node_in_group("map")
	var has_3d = is_instance_valid(map) and map.get("sub_viewport") != null and is_instance_valid(map.sub_viewport)

	if has_3d:
		var s_factor: float = map.scale_factor if "scale_factor" in map else 0.02
		var corr_z: float = map.correction_z if "correction_z" in map else 1.41421356
		var vp: SubViewport = map.sub_viewport
		var enemy_pos3d = Vector3(_enemy_pos.x * s_factor, 0.5, _enemy_pos.y * s_factor * corr_z)
		var target_pos3d = Vector3(_target_pos.x * s_factor, 0.5, _target_pos.y * s_factor * corr_z)

		# Crear nodo 3D del látigo como línea de fuego
		var whip_3d = Node3D.new()
		whip_3d.name = "Whip_3D_" + str(_hits_done)
		whip_3d.position = enemy_pos3d
		vp.add_child(whip_3d)

		# Crear mesh de línea (cylinder delgado representando el látigo)
		var mesh_inst = MeshInstance3D.new()
		var seg_length = 1.0
		var seg_rad = 0.03
		var pts = PackedVector3Array()
		var dir = (target_pos3d - enemy_pos3d)
		var dist = dir.length()
		dir = dir.normalized()
		var steps = int(dist / seg_length)
		for i in range(steps + 1):
			var t = float(i) / float(steps)
			pts.append(enemy_pos3d + dir * t * dist)

		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_LINES)
		for i in range(pts.size() - 1):
			st.add_vertex(pts[i])
			st.add_vertex(pts[i + 1])
		st.set_normal(Vector3.DOWN)
		mesh_inst.mesh = st.commit()
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.8, 0.2, 0.9)
		mat.emission = Color(1.0, 0.4, 0.0)
		mat.emission_energy = 2.0
		mat.no_depth_test = true
		mesh_inst.material_override = mat
		whip_3d.add_child(mesh_inst)

		# Add glow effect
		var glow = PointLight3D.new()
		glow.energy = 3.0
		glow.light_color = Color(1.0, 0.6, 0.2)
		whip_3d.add_child(glow)

		# Animar: grow from enemy to target then fade
		var tween = create_tween().set_parallel(true)
		tween.tween_property(mesh_inst, "scale", Vector3(1.0, 1.0, 1.0), 0.1)
		tween.tween_property(mesh_inst, "modulate:a", 0.0, 0.15)
		whip_3d.set_meta("fade_tween", tween)

		# Auto-limpiar tras animación
		await tween.finished
		if is_instance_valid(whip_3d):
			whip_3d.queue_free()
	else:
		# Fallback 2D: crear un Node2D con Line2D
		var line = Line2D.new()
		line.name = "Whip_2D_" + str(_hits_done)
		line.width = 3.0
		line.default_color = Color(1.0, 0.8, 0.2, 0.9)
		line.z_index = 15
		line.points = PackedVector2Array([_enemy_pos, _target_pos])
		add_child(line)
		# Fade y limpiar
		var tween = create_tween().set_parallel(true)
		tween.tween_property(line, "modulate:a", 0.0, 0.15)
		await tween.finished
		if is_instance_valid(line):
			line.queue_free()

func _spawn_hit_effect(pos: Vector2) -> void:
	if not is_instance_valid(enemy_node):
		return
	var map = get_tree().get_first_node_in_group("map")
	var has_3d = is_instance_valid(map) and map.get("sub_viewport") != null and is_instance_valid(map.sub_viewport)

	if has_3d:
		var s_factor: float = map.scale_factor if "scale_factor" in map else 0.02
		var corr_z: float = map.correction_z if "correction_z" in map else 1.41421356
		var vp: SubViewport = map.sub_viewport
		var hit_pos3d = Vector3(pos.x * s_factor, 0.5, pos.y * s_factor * corr_z)

		var hit_3d = Node3D.new()
		hit_3d.name = "WhipHit_" + str(_hits_done)
		hit_3d.position = hit_pos3d
		vp.add_child(hit_3d)

		# Crear disco de impacto
		var disc = MeshInstance3D.new()
		var disc_mesh = CircleMesh.new()
		disc_mesh.radius = 0.15
		disc_mesh.radial_segments = 16
		disc_mesh.face_outside = true
		disc.mesh = disc_mesh
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.6, 0.2, 0.8)
		mat.emission = Color(1.0, 0.3, 0.0)
		mat.emission_energy = 3.0
		disc.material_override = mat
		hit_3d.add_child(disc)

		# Sparkle particles
		var particles = GPUParticles3D.new()
		particles.amount = 20
		particles.lifetime = 0.3
		particles.one_shot = true
		var particle_material = BaseMaterial3D.new()
		particle_material.albedo_color = Color(1.0, 0.8, 0.2)
		particles.process_material = particle_material
		hit_3d.add_child(particles)
		particles.emitting = true

		# Auto-limpiar
		await get_tree().create_timer(0.4).timeout
		if is_instance_valid(hit_3d):
			hit_3d.queue_free()
	else:
		# Fallback 2D: CircleArea2D con sprite
		var area = Area2D.new()
		area.name = "WhipHit_2D_" + str(_hits_done)
		area.position = pos
		area.set_as_top_level(true)
		area.z_index = 15
		var circle = CircleShape2D.new()
		circle.radius = 20.0
		area.collision_shape = circle
		var sprite = Sprite2D.new()
		sprite.texture = WHIP_GLOW_TEX
		sprite.modulate = Color(1.0, 0.8, 0.2, 0.8)
		area.add_child(sprite)
		add_child(area)
		# Fade
		var tween = create_tween().set_parallel(true)
		tween.tween_property(sprite, "modulate:a", 0.0, 0.3)
		await tween.finished
		if is_instance_valid(area):
			area.queue_free()

func _process(delta: float) -> void:
	if not _active:
		return
	if _whip_timer > 0:
		_whip_timer -= delta
		if _whip_timer <= 0:
			_spawn_whip_effect()

func queue_free() -> void:
	_active = false
	for effect in _hit_effects:
		if is_instance_valid(effect):
			effect.queue_free()
	_hit_effects.clear()
	if is_instance_valid(get_parent()):
		get_parent().remove_child(self)
	queue_free()

class_name StrangeDimensionVFX
extends Node2D

# StrangeDimensionVFX.gd
# VFX de la Dimensión Extraña — Estilo Mordekaiser R (League of Legends)
# Efecto de portal violeta/tenebroso con partículas espectrales,
# oscurecimiento de pantalla y transformación de la estética del área.

@export var portal_radius: float = 200.0
@export var portal_duration: float = 5.0
@export var violet_color: Color = Color(0.6, 0.1, 0.9, 1.0)
@export var dark_overlay_opacity: float = 0.85
@export var particle_count: int = 100
@export var fade_out_delay: float = 0.5

var _caster_node: Node2D = null
var _epicenter_pos: Vector2 = Vector2.ZERO
var _start_time: float = 0.0
var _active: bool = false
var _vfx_container: Node2D = null
var _darkness_overlay: ColorRect = null
var _violet_tint: ColorRect = null
var _portal_rings: Array = []

func init(caster_node: Node2D, epicenter_pos: Vector2, duration: float = 5.0) -> void:
	_caster_node = caster_node
	_epicenter_pos = epicenter_pos
	portal_duration = duration
	_start_time = Time.get_ticks_msec() / 1000.0
	_active = true
	
	var parent = get_parent()
	if not is_instance_valid(parent):
		parent = caster_node.get_parent()
		if not is_instance_valid(parent):
			parent = get_tree().get_first_node_in_group("world_node")
	
	# Crear contenedor VFX
	_vfx_container = Node2D.new()
	_vfx_container.name = "StrangeDimensionVFX"
	_vfx_container.z_index = 999
	parent.add_child(_vfx_container)
	
	# 1. Overlay de oscuridad total
	_darkness_overlay = ColorRect.new()
	_darkness_overlay.name = "DimensionDarkness"
	_darkness_overlay.color = Color(0.0, 0.0, 0.0, dark_overlay_opacity)
	_darkness_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_darkness_overlay.z_index = 1000
	_vfx_container.add_child(_darkness_overlay)
	
	# 2. Tinte violeta sobre la oscuridad
	_violet_tint = ColorRect.new()
	_violet_tint.name = "VioletTint"
	_violet_tint.color = Color(0.4, 0.0, 0.6, 0.35)
	_violet_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_violet_tint.z_index = 1001
	_vfx_container.add_child(_violet_tint)
	
	# 3. Anillos del portal (múltiples capas para efecto Mordekaiser)
	for i in range(4):
		var ring = Node2D.new()
		ring.name = "PortalRing_" + str(i)
		ring.global_position = _epicenter_pos
		ring.z_index = 1002 + i
		_vfx_container.add_child(ring)
		_portal_rings.append(ring)
	
	# 4. Partículas espectrales violetas
	_spawn_spectral_particles()
	
	# 5. Auto-destruir después de la duración
	get_tree().create_timer(portal_duration + fade_out_delay).timeout.connect(_fade_out)
	
	# Tween de entrada para el overlay
	if _darkness_overlay:
		_darkness_overlay.modulate = Color(0.0, 0.0, 0.0, 0.0)
		var tw = create_tween()
		tw.tween_property(_darkness_overlay, "modulate", Color(0.0, 0.0, 0.0, dark_overlay_opacity), 0.5)
	if _violet_tint:
		_violet_tint.modulate = Color(0.4, 0.0, 0.6, 0.0)
		var tw2 = create_tween()
		tw2.tween_property(_violet_tint, "modulate", Color(0.4, 0.0, 0.6, 0.35), 0.5)

func _spawn_spectral_particles() -> void:
	var particles = GPUParticles2D.new()
	particles.name = "SpectralParticles"
	particles.amount = particle_count
	particles.lifetime = portal_duration
	particles.one_shot = false
	particles.explosiveness = 0.3
	particles.emitting = true
	particles.position = _epicenter_pos
	
	var proc_mat = ParticleProcessMaterial.new()
	proc_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_CIRCLE
	proc_mat.emission_circle_radius = portal_radius * 0.8
	proc_mat.direction = Vector2(0, 0)
	proc_mat.spread = 180.0
	proc_mat.initial_velocity_min = 10.0
	proc_mat.initial_velocity_max = 40.0
	proc_mat.gravity = Vector2(0, 0)
	proc_mat.scale_min = 0.5
	proc_mat.scale_max = 2.0
	proc_mat.color = violet_color
	
	var grad = Gradient.new()
	grad.set_color(0, Color(violet_color.r, violet_color.g, violet_color.b, 1.0))
	grad.set_color(1, Color(violet_color.r, violet_color.g, violet_color.b, 0.0))
	var grad_tex = GradientTexture1D.new()
	grad_tex.gradient = grad
	proc_mat.color_ramp = grad_tex
	particles.process_material = proc_mat
	
	var mesh = QuadMesh.new()
	mesh.size = Vector2(8.0, 8.0)
	var mat = ShaderMaterial.new()
	mesh.material = mat
	particles.draw_pass_1 = mesh
	
	_vfx_container.add_child(particles)

func _process(delta: float) -> void:
	if not _active:
		set_process(false)
		return
	
	var current_time = Time.get_ticks_msec() / 1000.0
	var elapsed = current_time - _start_time
	var progress = clamp(elapsed / portal_duration, 0.0, 1.0)
	
	# Animar los anillos del portal con pulso violeta
	for i in range(_portal_rings.size()):
		var ring = _portal_rings[i]
		if not is_instance_valid(ring):
			continue
		
		var base_radius = portal_radius * (0.2 + 0.8 * (1.0 - progress))
		var pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 200.0 + float(i) * 0.5)
		var ring_radius = base_radius * (1.0 + pulse * 0.15)
		var alpha = max(0.0, (0.6 - float(i) * 0.12) * pulse)
		var scale_val = ring_radius / 10.0
		
		ring.scale = Vector2(scale_val, scale_val)
		ring.modulate = Color(violet_color.r, violet_color.g, violet_color.b, alpha)
	
	# Hacer parpadear el tinte violeta
	if is_instance_valid(_violet_tint):
		var pulse = 0.3 + 0.3 * sin(Time.get_ticks_msec() / 250.0)
		_violet_tint.modulate = Color(0.4, 0.0, 0.6, pulse)

func _fade_out() -> void:
	_active = false
	set_process(false)
	
	if _darkness_overlay and is_instance_valid(_darkness_overlay):
		var tw = create_tween()
		tw.tween_property(_darkness_overlay, "modulate:a", 0.0, 0.5)
	
	if _violet_tint and is_instance_valid(_violet_tint):
		var tw2 = create_tween()
		tw2.tween_property(_violet_tint, "modulate:a", 0.0, 0.5)
	
	# Desvanecer cada anillo
	for ring in _portal_rings:
		if is_instance_valid(ring):
			var tw = create_tween()
			tw.tween_property(ring, "modulate:a", 0.0, 0.4)
	
	# Esperar y destruir contenedor
	var tw_free = create_tween()
	tw_free.tween_interval(0.7)
	tw_free.tween_callback(_vfx_container.queue_free)
	
	queue_free()

func _exit_tree() -> void:
	if _vfx_container and is_instance_valid(_vfx_container):
		_vfx_container.queue_free()

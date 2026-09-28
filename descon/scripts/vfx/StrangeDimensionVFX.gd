extends Node2D

# StrangeDimensionVFX.gd (v902.0)
# VFX de la Dimensión Extraña — efecto de oscuridad pantalla completa + partículas violetas
# Se instancia como Node2D con un CanvasLayer hijo para el overlay de pantalla completa.
# EntityManager lo agrega al árbol de escena cuando el jugador es capturado.

@export var portal_radius: float = 300.0
@export var portal_duration: float = 5.0
@export var violet_color: Color = Color(0.55, 0.0, 0.85, 1.0)
@export var dark_overlay_opacity: float = 0.82
@export var fade_out_delay: float = 0.5

var _caster_node: Node2D = null
var _epicenter_pos: Vector2 = Vector2.ZERO
var _start_time: float = 0.0
var _active: bool = false

# Nodos internos
var _canvas_layer: CanvasLayer = null
var _ui_root: Control = null
var _darkness_overlay: ColorRect = null
var _violet_tint: ColorRect = null
var _particles: GPUParticles2D = null
var _border_ring: Node2D = null

func init(caster_node: Node2D, epicenter_pos: Vector2, duration: float = 5.0) -> void:
	_caster_node = caster_node
	_epicenter_pos = epicenter_pos
	portal_duration = duration
	_start_time = Time.get_ticks_msec() / 1000.0
	_active = true
	add_to_group("strange_dimension_vfx")

	# --- CanvasLayer propio para overlay de pantalla completa ---
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.name = "StrangeDimensionCanvas"
	_canvas_layer.layer = 128  # Por encima de todo el HUD normal
	add_child(_canvas_layer)

	# Raíz de Control para los rects full-screen
	_ui_root = Control.new()
	_ui_root.name = "SDRoot"
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas_layer.add_child(_ui_root)

	# 1. Overlay de oscuridad (pantalla completa)
	_darkness_overlay = ColorRect.new()
	_darkness_overlay.name = "DimensionDarkness"
	_darkness_overlay.color = Color(0.0, 0.0, 0.0, dark_overlay_opacity)
	_darkness_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_darkness_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_darkness_overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)  # Empieza transparente
	_ui_root.add_child(_darkness_overlay)

	# 2. Tinte violeta pulsante encima
	_violet_tint = ColorRect.new()
	_violet_tint.name = "VioletTint"
	_violet_tint.color = Color(violet_color.r, violet_color.g, violet_color.b, 0.28)
	_violet_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_violet_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_violet_tint.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_ui_root.add_child(_violet_tint)

	# 3. Fade in de los overlays
	var tw = create_tween().set_parallel(true)
	tw.tween_property(_darkness_overlay, "modulate:a", 1.0, 0.6)
	tw.tween_property(_violet_tint, "modulate:a", 1.0, 0.6)

	# 4. Partículas espectrales en el mundo (posición lógica del jugador)
	_spawn_spectral_particles()

	# 5. Anillo de borde pulsante en la posición del jugador
	_border_ring = Node2D.new()
	_border_ring.name = "DimBorderRing"
	_border_ring.global_position = _epicenter_pos
	_border_ring.z_index = 50
	add_child(_border_ring)

	# 6. Auto-destruir tras la duración
	get_tree().create_timer(portal_duration + fade_out_delay).timeout.connect(_fade_out)

func _spawn_spectral_particles() -> void:
	if not is_inside_tree():
		return
	_particles = GPUParticles2D.new()
	_particles.name = "SpectralParticles"
	_particles.amount = 80
	_particles.lifetime = 2.5
	_particles.one_shot = false
	_particles.explosiveness = 0.15
	_particles.emitting = true
	_particles.position = _epicenter_pos
	_particles.z_index = 60
	_particles.modulate = Color(1.0, 1.0, 1.0, 0.0)

	var proc_mat = ParticleProcessMaterial.new()
	proc_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_CIRCLE
	proc_mat.emission_circle_radius = portal_radius * 0.6
	proc_mat.direction = Vector3(0.0, -1.0, 0.0)
	proc_mat.spread = 180.0
	proc_mat.initial_velocity_min = 8.0
	proc_mat.initial_velocity_max = 35.0
	proc_mat.gravity = Vector3(0.0, -15.0, 0.0)
	proc_mat.scale_min = 0.4
	proc_mat.scale_max = 1.8

	var grad = Gradient.new()
	grad.set_color(0, Color(violet_color.r, violet_color.g, violet_color.b, 1.0))
	grad.set_color(1, Color(violet_color.r * 0.6, violet_color.g, violet_color.b * 0.8, 0.0))
	var grad_tex = GradientTexture1D.new()
	grad_tex.gradient = grad
	proc_mat.color_ramp = grad_tex
	_particles.process_material = proc_mat

	# Quad simple como sprite de partícula
	var quad = QuadMesh.new()
	quad.size = Vector2(10.0, 10.0)
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = violet_color
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	quad.material = mat
	_particles.draw_pass_1 = quad

	add_child(_particles)

	# Fade in de partículas
	var tw2 = create_tween()
	tw2.tween_property(_particles, "modulate:a", 1.0, 0.5)

func _process(_delta: float) -> void:
	if not _active:
		set_process(false)
		return

	var t := Time.get_ticks_msec() / 1000.0
	var elapsed := t - _start_time

	# Pulso del tinte violeta
	if is_instance_valid(_violet_tint) and _violet_tint.modulate.a > 0.5:
		var pulse := 0.25 + 0.25 * sin(t * 3.5)
		_violet_tint.modulate.a = clamp(0.75 + pulse * 0.25, 0.0, 1.0)

	# Hacer seguir las partículas al jugador si se mueve
	if is_instance_valid(_caster_node) and is_instance_valid(_particles):
		_particles.position = _caster_node.global_position

	# Anillo de borde pulsante dibujado vía _draw
	if is_instance_valid(_border_ring):
		if is_instance_valid(_caster_node):
			_border_ring.global_position = _caster_node.global_position
		_border_ring.queue_redraw()

	# Ocultar automáticamente si ya pasó el tiempo (failsafe)
	if elapsed >= portal_duration + fade_out_delay + 0.5:
		_fade_out()

func _fade_out() -> void:
	if not _active:
		return
	_active = false
	set_process(false)

	# Fade out de overlays y partículas
	if is_instance_valid(_darkness_overlay):
		var tw = create_tween()
		tw.tween_property(_darkness_overlay, "modulate:a", 0.0, 0.6)
	if is_instance_valid(_violet_tint):
		var tw2 = create_tween()
		tw2.tween_property(_violet_tint, "modulate:a", 0.0, 0.5)
	if is_instance_valid(_particles):
		_particles.emitting = false
		var tw3 = create_tween()
		tw3.tween_property(_particles, "modulate:a", 0.0, 0.4)

	# Destruir todo tras el fade
	var tw_kill = create_tween()
	tw_kill.tween_interval(0.8)
	tw_kill.tween_callback(queue_free)

func _exit_tree() -> void:
	remove_from_group("strange_dimension_vfx")
	if is_instance_valid(_canvas_layer):
		_canvas_layer.queue_free()

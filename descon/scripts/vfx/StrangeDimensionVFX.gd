extends Node2D

# StrangeDimensionVFX.gd (v904.0)
# Domo de Tinieblas y Dimensión Extraña
# - CanvasModulate: Oscurece las luces del mapa como si fuesen tinieblas profundas
# - Domo dimensional: Círculo de energía mística violeta alrededor del jugador
# - Overlay de pantalla: Tinte violeta cósmico y viñeta de tinieblas
# - 100% nativo sin partículas GPU para compatibilidad absoluta con todas las versiones de Godot

@export var dome_radius: float = 480.0
@export var portal_duration: float = 5.0
@export var violet_color: Color = Color(0.65, 0.15, 0.95, 1.0)
@export var fade_out_delay: float = 0.5

var _caster_node: Node2D = null
var _epicenter_pos: Vector2 = Vector2.ZERO
var _start_time: float = 0.0
var _active: bool = false

# Nodos visuales
var _canvas_layer: CanvasLayer = null
var _ui_root: Control = null
var _darkness_overlay: ColorRect = null
var _violet_overlay: ColorRect = null
var _title_label: Label = null
var _sub_label: Label = null
var _canvas_modulate: CanvasModulate = null
var _dome_visual: Node2D = null

func init(caster_node: Node2D, epicenter_pos: Vector2, duration: float = 5.0) -> void:
	_caster_node = caster_node
	_epicenter_pos = epicenter_pos
	portal_duration = duration
	_start_time = Time.get_ticks_msec() / 1000.0
	_active = true
	add_to_group("strange_dimension_vfx")

	# 1. CanvasModulate en el mundo: Oscurece las luces y el mapa a tinieblas
	_canvas_modulate = CanvasModulate.new()
	_canvas_modulate.name = "DimensionTinieblasModulate"
	_canvas_modulate.color = Color(1.0, 1.0, 1.0, 1.0)
	add_child(_canvas_modulate)
	
	var tw_mod = create_tween()
	# Transición suave hacia oscuridad con tinte violeta tenebroso
	tw_mod.tween_property(_canvas_modulate, "color", Color(0.08, 0.04, 0.14, 1.0), 0.4)

	# 2. Domo dimensional en el piso (siguiendo al jugador)
	_dome_visual = Node2D.new()
	_dome_visual.name = "DimensionDomeCircle"
	_dome_visual.z_index = 25
	_dome_visual.global_position = _epicenter_pos
	add_child(_dome_visual)
	_dome_visual.draw.connect(_on_dome_draw)

	# 3. CanvasLayer propio para atmósfera en pantalla
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.name = "StrangeDimensionCanvas"
	_canvas_layer.layer = 95
	add_child(_canvas_layer)

	_ui_root = Control.new()
	_ui_root.name = "SDRoot"
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas_layer.add_child(_ui_root)

	# 3a. Overlay de oscuridad de fondo
	_darkness_overlay = ColorRect.new()
	_darkness_overlay.name = "DarknessOverlay"
	_darkness_overlay.color = Color(0.02, 0.01, 0.05, 0.72)
	_darkness_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_darkness_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_darkness_overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_ui_root.add_child(_darkness_overlay)

	# 3b. Tinte violeta cósmico
	_violet_overlay = ColorRect.new()
	_violet_overlay.name = "VioletTintOverlay"
	_violet_overlay.color = Color(violet_color.r, violet_color.g, violet_color.b, 0.18)
	_violet_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_violet_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_violet_overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_ui_root.add_child(_violet_overlay)

	# 3c. Banner superior elegante
	var banner = VBoxContainer.new()
	banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner.offset_top = 35.0
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(banner)

	_title_label = Label.new()
	_title_label.text = "✦ DIMENSIÓN EXTRAÑA ✦"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_color_override("font_color", Color(0.9, 0.7, 1.0, 1.0))
	_title_label.add_theme_color_override("font_shadow_color", Color(0.35, 0.0, 0.65, 0.9))
	_title_label.add_theme_constant_override("shadow_offset_y", 2)
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	banner.add_child(_title_label)

	_sub_label = Label.new()
	_sub_label.text = "Domo de tinieblas — Realidad paralela aislada"
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.add_theme_color_override("font_color", Color(0.75, 0.55, 0.95, 0.75))
	_sub_label.add_theme_font_size_override("font_size", 13)
	_sub_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	banner.add_child(_sub_label)

	# Fade in de la atmósfera
	var tw = create_tween().set_parallel(true)
	tw.tween_property(_darkness_overlay, "modulate:a", 1.0, 0.4)
	tw.tween_property(_violet_overlay, "modulate:a", 1.0, 0.4)
	tw.tween_property(_title_label, "modulate:a", 1.0, 0.5)
	tw.tween_property(_sub_label, "modulate:a", 1.0, 0.5)

	# Failsafe de duración
	get_tree().create_timer(portal_duration + fade_out_delay).timeout.connect(_fade_out)

func _on_dome_draw() -> void:
	if not _active or not is_instance_valid(_dome_visual):
		return

	var t := Time.get_ticks_msec() / 1000.0
	var pulse := 0.15 * sin(t * 4.0)
	var current_radius := dome_radius * (1.0 + pulse * 0.03)

	# Relleno etéreo semitransparente del domo
	_dome_visual.draw_circle(Vector2.ZERO, current_radius, Color(0.2, 0.05, 0.35, 0.12))

	# Anillos concéntricos del domo
	var edge_col = Color(violet_color.r, violet_color.g, violet_color.b, 0.75 + pulse)
	_dome_visual.draw_arc(Vector2.ZERO, current_radius, 0.0, TAU, 64, edge_col, 3.5, true)
	_dome_visual.draw_arc(Vector2.ZERO, current_radius * 0.98, 0.0, TAU, 64, Color(0.9, 0.7, 1.0, 0.4), 1.5, true)
	_dome_visual.draw_arc(Vector2.ZERO, current_radius * 0.75, 0.0, TAU, 48, Color(violet_color.r, violet_color.g, violet_color.b, 0.2), 1.0, true)

	# Runa / marcas cardinales en el borde
	for i in range(8):
		var angle := (float(i) / 8.0) * TAU + (t * 0.2)
		var p1 := Vector2(cos(angle), sin(angle)) * (current_radius - 12.0)
		var p2 := Vector2(cos(angle), sin(angle)) * (current_radius + 12.0)
		_dome_visual.draw_line(p1, p2, Color(0.9, 0.7, 1.0, 0.8), 2.0)

func _process(_delta: float) -> void:
	if not _active:
		set_process(false)
		return

	var t := Time.get_ticks_msec() / 1000.0
	var elapsed := t - _start_time

	# Seguir al jugador con el domo
	if is_instance_valid(_caster_node) and is_instance_valid(_dome_visual):
		_dome_visual.global_position = _caster_node.global_position
		_dome_visual.queue_redraw()

	# Pulso del tinte violeta
	if is_instance_valid(_violet_overlay):
		var p := 0.15 + 0.1 * sin(t * 3.0)
		_violet_overlay.modulate.a = clamp(0.75 + p, 0.0, 1.0)

	# Failsafe
	if elapsed >= portal_duration + fade_out_delay + 1.0:
		_fade_out()

func _fade_out() -> void:
	if not _active:
		return
	_active = false
	set_process(false)

	# Restaurar CanvasModulate (vuelve la iluminación normal del mapa)
	if is_instance_valid(_canvas_modulate):
		var tw_m = create_tween()
		tw_m.tween_property(_canvas_modulate, "color", Color.WHITE, 0.5)

	# Fade out de overlays
	if is_instance_valid(_darkness_overlay):
		var tw1 = create_tween()
		tw1.tween_property(_darkness_overlay, "modulate:a", 0.0, 0.5)
	if is_instance_valid(_violet_overlay):
		var tw2 = create_tween()
		tw2.tween_property(_violet_overlay, "modulate:a", 0.0, 0.5)
	if is_instance_valid(_title_label):
		var tw3 = create_tween()
		tw3.tween_property(_title_label, "modulate:a", 0.0, 0.3)
	if is_instance_valid(_sub_label):
		var tw4 = create_tween()
		tw4.tween_property(_sub_label, "modulate:a", 0.0, 0.3)
	if is_instance_valid(_dome_visual):
		var tw5 = create_tween()
		tw5.tween_property(_dome_visual, "modulate:a", 0.0, 0.4)

	# Destrucción final
	var tw_kill = create_tween()
	tw_kill.tween_interval(0.6)
	tw_kill.tween_callback(queue_free)

func _exit_tree() -> void:
	remove_from_group("strange_dimension_vfx")
	if is_instance_valid(_canvas_layer):
		_canvas_layer.queue_free()
	if is_instance_valid(_canvas_modulate):
		_canvas_modulate.queue_free()

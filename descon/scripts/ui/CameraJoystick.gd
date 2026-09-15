extends Control

# CameraJoystick.gd (v1.0 - Segundo Joystick y Panel Táctil de Cámara 3D para Celular)
# Proporciona control de órbita 360°, inclinación vertical, zoom in/out, reset y bloqueo seguro.

signal camera_pad_closed()

@export var border_color: Color = Color(0.0, 0.9, 1.0, 0.9)
@export var stick_color: Color = Color(0.0, 0.95, 1.0, 0.85)
@export var bg_color: Color = Color(0.02, 0.08, 0.16, 0.65)

var is_dragging: bool = false
var stick_pos: Vector2 = Vector2.ZERO
var max_dist: float = 48.0
var active_touch_index: int = -1
var _last_drag_pos: Vector2 = Vector2.ZERO

var _pad_center: Vector2 = Vector2(95, 105)
var _pad_radius: float = 60.0

var _btn_zoom_in: Button = null
var _btn_zoom_out: Button = null
var _btn_reset: Button = null
var _btn_lock: Button = null

func _ready():
	custom_minimum_size = Vector2(190, 240)
	size = Vector2(190, 240)
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	_setup_ui()

func _setup_ui():
	# 1. Panel de Fondo Cyberpunk
	var panel_bg = Panel.new()
	panel_bg.name = "BackgroundPanel"
	panel_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var sb_bg = StyleBoxFlat.new()
	sb_bg.bg_color = Color(0.01, 0.05, 0.10, 0.72)
	sb_bg.border_width_left = 1
	sb_bg.border_width_top = 1
	sb_bg.border_width_right = 1
	sb_bg.border_width_bottom = 1
	sb_bg.border_color = Color(0.0, 0.85, 1.0, 0.6)
	sb_bg.set_corner_radius_all(10)
	panel_bg.add_theme_stylebox_override("panel", sb_bg)
	add_child(panel_bg)
	
	# 2. Barra de Título Superior
	var title_bar = HBoxContainer.new()
	title_bar.name = "TitleBar"
	title_bar.position = Vector2(8, 6)
	title_bar.size = Vector2(174, 26)
	title_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_bar)
	
	var title_lbl = Label.new()
	title_lbl.name = "TitleLabel"
	title_lbl.text = "🎥 CÁMARA 3D"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", 11)
	title_lbl.add_theme_color_override("font_color", Color(0.0, 0.95, 1.0, 0.95))
	title_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	title_lbl.add_theme_constant_override("outline_size", 2)
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_bar.add_child(title_lbl)
	
	# Botón de Bloqueo / Ocultar (Mantiene la cámara 3D fija donde la dejaste)
	_btn_lock = Button.new()
	_btn_lock.name = "LockBtn"
	_btn_lock.text = "🔒"
	_btn_lock.tooltip_text = "Fijar ángulo y ocultar panel"
	_btn_lock.custom_minimum_size = Vector2(28, 24)
	_style_button(_btn_lock, Color(0.05, 0.15, 0.25, 0.85))
	_btn_lock.pressed.connect(_on_lock_pressed)
	title_bar.add_child(_btn_lock)
	
	# 3. Área Interactiva del Joystick / TouchPad Central
	var touch_area = Control.new()
	touch_area.name = "TouchArea"
	touch_area.position = Vector2(15, 34)
	touch_area.size = Vector2(160, 140)
	touch_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_pad_center = touch_area.size / 2.0
	_pad_radius = 54.0
	max_dist = 42.0
	
	touch_area.gui_input.connect(_on_touch_area_gui_input)
	touch_area.draw.connect(_draw_joystick.bind(touch_area))
	add_child(touch_area)
	
	# 4. Botonera Inferior (Zoom In, Zoom Out, Reset)
	var hbox = HBoxContainer.new()
	hbox.name = "ButtonRow"
	hbox.position = Vector2(10, 182)
	hbox.size = Vector2(170, 46)
	hbox.add_theme_constant_override("separation", 8)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(hbox)
	
	# Botón Zoom In (+ Zoom)
	_btn_zoom_in = Button.new()
	_btn_zoom_in.name = "ZoomInBtn"
	_btn_zoom_in.text = "🔍+"
	_btn_zoom_in.tooltip_text = "Acercar cámara"
	_btn_zoom_in.custom_minimum_size = Vector2(50, 40)
	_style_button(_btn_zoom_in, Color(0.05, 0.14, 0.24, 0.9))
	_btn_zoom_in.pressed.connect(_on_zoom_in_pressed)
	hbox.add_child(_btn_zoom_in)
	
	# Botón Zoom Out (- Zoom)
	_btn_zoom_out = Button.new()
	_btn_zoom_out.name = "ZoomOutBtn"
	_btn_zoom_out.text = "🔍-"
	_btn_zoom_out.tooltip_text = "Alejar cámara"
	_btn_zoom_out.custom_minimum_size = Vector2(50, 40)
	_style_button(_btn_zoom_out, Color(0.05, 0.14, 0.24, 0.9))
	_btn_zoom_out.pressed.connect(_on_zoom_out_pressed)
	hbox.add_child(_btn_zoom_out)
	
	# Botón Reset (↺)
	_btn_reset = Button.new()
	_btn_reset.name = "ResetBtn"
	_btn_reset.text = "↺"
	_btn_reset.tooltip_text = "Restablecer ángulo por defecto"
	_btn_reset.custom_minimum_size = Vector2(50, 40)
	_style_button(_btn_reset, Color(0.05, 0.14, 0.24, 0.9))
	_btn_reset.pressed.connect(_on_reset_pressed)
	hbox.add_child(_btn_reset)

func _style_button(btn: Button, bg: Color):
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.0, 0.85, 1.0, 0.75)
	sb.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", sb)
	
	var h_sb = sb.duplicate()
	h_sb.bg_color = Color(0.08, 0.25, 0.38, 0.95)
	h_sb.border_color = Color(0.2, 1.0, 1.0, 1.0)
	btn.add_theme_stylebox_override("hover", h_sb)
	
	var p_sb = sb.duplicate()
	p_sb.bg_color = Color(0.12, 0.35, 0.50, 1.0)
	p_sb.border_color = Color.WHITE
	btn.add_theme_stylebox_override("pressed", p_sb)

func _draw_joystick(touch_area: Control):
	var center = _pad_center
	
	# Base Circular con estilo futurista
	touch_area.draw_circle(center, _pad_radius, Color(0.02, 0.08, 0.16, 0.65))
	touch_area.draw_arc(center, _pad_radius, 0, TAU, 64, border_color, 2.0, true)
	
	# Círculo interior guía (deadzone / referencia)
	touch_area.draw_arc(center, max_dist * 0.35, 0, TAU, 32, Color(0.0, 0.8, 1.0, 0.25), 1.0)
	
	# Marcas azimutales cardinales (retícula Sci-Fi)
	var tick_len = 7.0
	touch_area.draw_line(center + Vector2(0, -_pad_radius), center + Vector2(0, -_pad_radius + tick_len), Color(0.0, 0.95, 1.0, 0.7), 1.5)
	touch_area.draw_line(center + Vector2(0, _pad_radius), center + Vector2(0, _pad_radius - tick_len), Color(0.0, 0.95, 1.0, 0.7), 1.5)
	touch_area.draw_line(center + Vector2(-_pad_radius, 0), center + Vector2(-_pad_radius + tick_len, 0), Color(0.0, 0.95, 1.0, 0.7), 1.5)
	touch_area.draw_line(center + Vector2(_pad_radius, 0), center + Vector2(_pad_radius - tick_len, 0), Color(0.0, 0.95, 1.0, 0.7), 1.5)
	
	# Indicador de palanca (Stick Knob)
	var current_knob_pos = center + stick_pos
	# Resplandor exterior del stick
	touch_area.draw_circle(current_knob_pos, 22.0, Color(0.0, 0.9, 1.0, 0.2))
	# Centro del stick
	touch_area.draw_circle(current_knob_pos, 16.0, stick_color)
	touch_area.draw_arc(current_knob_pos, 16.0, 0, TAU, 32, Color.WHITE, 1.5, true)
	
	# Punto central luminoso
	touch_area.draw_circle(current_knob_pos, 4.0, Color.WHITE)

func _on_touch_area_gui_input(event: InputEvent):
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.get("is_editing_layout"):
		return
		
	var map_node = get_tree().get_first_node_in_group("map")
	if not is_instance_valid(map_node): return
	
	var sens = SettingsManager.mobile_camera_sensitivity if SettingsManager else 1.0
	
	var is_touch = event is InputEventScreenTouch or event is InputEventScreenDrag
	var is_mouse = event is InputEventMouseButton or event is InputEventMouseMotion
	if not (is_touch or is_mouse): return
	
	var ev_idx = event.index if is_touch else 0
	
	# --- 1. Toque Inicial ---
	if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		get_viewport().set_input_as_handled()
		if active_touch_index == -1:
			active_touch_index = ev_idx
			is_dragging = true
			_last_drag_pos = event.position
			_update_stick_pos(event.position)
			_ensure_free_cam_active(map_node)
			
	# --- 2. Toque Final (Release) ---
	elif (event is InputEventScreenTouch and not event.pressed) or (event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		if ev_idx == active_touch_index:
			get_viewport().set_input_as_handled()
			_reset_stick()
			if map_node.has_method("_save_camera_state"):
				map_node._save_camera_state()
				
	# --- 3. Arrastre / Drag ---
	elif event is InputEventScreenDrag or (event is InputEventMouseMotion and is_dragging):
		if is_dragging and (ev_idx == active_touch_index or active_touch_index == 0):
			get_viewport().set_input_as_handled()
			_ensure_free_cam_active(map_node)
			
			# Respuesta inmediata al swipe/arrastre táctil
			var delta_drag = event.position - _last_drag_pos
			_last_drag_pos = event.position
			
			var inv_x = -1.0 if (SettingsManager and SettingsManager.mobile_camera_invert_x) else 1.0
			var inv_y = -1.0 if (SettingsManager and SettingsManager.mobile_camera_invert_y) else 1.0
			
			map_node.free_cam_h += delta_drag.x * 0.35 * sens * inv_x
			map_node.free_cam_v = clamp(map_node.free_cam_v + delta_drag.y * 0.35 * sens * inv_y, 10.0, 85.0)
			
			_update_stick_pos(event.position)

func _update_stick_pos(p: Vector2):
	var diff = p - _pad_center
	stick_pos = diff.limit_length(max_dist)
	var touch_area = get_node_or_null("TouchArea")
	if touch_area: touch_area.queue_redraw()

func _reset_stick():
	is_dragging = false
	active_touch_index = -1
	stick_pos = Vector2.ZERO
	var touch_area = get_node_or_null("TouchArea")
	if touch_area: touch_area.queue_redraw()

func _process(delta: float):
	# Rotación continua al mantener la palanca desplazada (Curva AAA Exponencial)
	if is_dragging and stick_pos.length() > 8.0:
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node):
			var sens = SettingsManager.mobile_camera_sensitivity if SettingsManager else 1.0
			var inv_x = -1.0 if (SettingsManager and SettingsManager.mobile_camera_invert_x) else 1.0
			var inv_y = -1.0 if (SettingsManager and SettingsManager.mobile_camera_invert_y) else 1.0
			
			var norm = stick_pos / max_dist
			var stick_len = norm.length()
			var deadzone = 0.16 # Zona muerta suave (16%)
			
			if stick_len > deadzone:
				var remapped = (stick_len - deadzone) / (1.0 - deadzone)
				# Curva cuadrática suave para control quirúrgico en micro-ajustes y giro rápido en borde
				var curved_len = pow(remapped, 1.35)
				var dir = norm.normalized()
				var drive = dir * curved_len
				
				_ensure_free_cam_active(map_node)
				
				var rot_speed_h = 80.0 # Grados por segundo en velocidad máxima
				var rot_speed_v = 45.0
				map_node.free_cam_h += drive.x * rot_speed_h * delta * sens * inv_x
				map_node.free_cam_v = clamp(map_node.free_cam_v + drive.y * rot_speed_v * delta * sens * inv_y, 10.0, 85.0)

func _ensure_free_cam_active(map_node: Node):
	if not is_instance_valid(map_node): return
	if not map_node.get("free_cam_active"):
		map_node.free_cam_active = true
		if map_node.has_method("_sync_free_from_fixed"):
			map_node._sync_free_from_fixed()

func _on_zoom_in_pressed():
	var map_node = get_tree().get_first_node_in_group("map")
	if is_instance_valid(map_node):
		_ensure_free_cam_active(map_node)
		map_node.free_cam_zoom = clamp(map_node.free_cam_zoom - 4.0, 10.0, 100.0)
		if map_node.has_method("_sync_zooms_from_free"): map_node._sync_zooms_from_free()
		if map_node.has_method("_save_camera_state"): map_node._save_camera_state()

func _on_zoom_out_pressed():
	var map_node = get_tree().get_first_node_in_group("map")
	if is_instance_valid(map_node):
		_ensure_free_cam_active(map_node)
		map_node.free_cam_zoom = clamp(map_node.free_cam_zoom + 4.0, 10.0, 100.0)
		if map_node.has_method("_sync_zooms_from_free"): map_node._sync_zooms_from_free()
		if map_node.has_method("_save_camera_state"): map_node._save_camera_state()

func _on_reset_pressed():
	var map_node = get_tree().get_first_node_in_group("map")
	if is_instance_valid(map_node):
		_ensure_free_cam_active(map_node)
		map_node.free_cam_h = 180.0
		map_node.free_cam_v = 40.0
		map_node.free_cam_zoom = 28.0
		if map_node.has_method("_sync_zooms_from_free"): map_node._sync_zooms_from_free()
		if map_node.has_method("_save_camera_state"): map_node._save_camera_state()
		var hud = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("notify"):
			hud.notify("VISTA REINICIADA", "info")

func _on_lock_pressed():
	# Bloquear y ocultar el panel (Estado 2: Libre Bloqueada)
	if SettingsManager:
		SettingsManager.mobile_camera_edit_enabled = 2
		SettingsManager.save_settings()
		
		var map_node = get_tree().get_first_node_in_group("map")
		if map_node and map_node.has_method("_on_mobile_camera_edit_toggled"):
			map_node._on_mobile_camera_edit_toggled(2)
			
		var hud = get_tree().get_first_node_in_group("hud")
		if hud:
			if hud.has_method("_update_icon_state"):
				hud._update_icon_state("CamEdit", 2)
			if hud.has_method("notify"):
				hud.notify("CÁMARA: LIBRE BLOQUEADA (PANEL OCULTO)", "warn")
	visible = false
	camera_pad_closed.emit()

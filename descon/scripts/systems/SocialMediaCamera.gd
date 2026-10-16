extends Node

class_name SocialCameraSystem

## Camera Modes
enum CameraMode {
	FREE = 0,           # Free camera (orbit/WASD)
	PLAYER_VIEW = 1,    # Follow player from behind
	BOSS_POV = 2,       # Primera persona del Boss mirando al frente
	ENEMY_VIEW = 3,     # Órbita / Enfoque externo al Boss o enemigo
	PANORAMIC = 4,      # Slow panoramic rotation
	CINEMATIC = 5,      # Cinematic camera with smooth movements
	LANDSCAPE = 6,      # Landscape/environment focus
	CUSTOM = 7          # Custom target/follow
}

## Platform Presets
enum PlatformPreset {
	YOUTUBE = 0,        # 16:9 (1920x1080)
	INSTAGRAM_FEED = 1, # 1:1 (1080x1080)
	INSTAGRAM_STORY = 2,# 9:16 (1080x1920)
	TIKTOK = 3,         # 9:16 (1080x1920)
	CUSTOM = 4
}

## Camera State
var current_mode: CameraMode = CameraMode.FREE
var current_platform: PlatformPreset = PlatformPreset.YOUTUBE
var is_active: bool = false
var is_recording: bool = false

# Modo Picture-in-Picture: Si es true, el jugador sigue jugando normal en pantalla completa
# y la cámara graba/visualiza de forma independiente en un recuadro secundario.
var is_pip_mode: bool = true

## References
var _base_map: Node = null
var _camera_3d: Camera3D = null # Cámara principal del mapa
var _player: Node = null
var _target_entity: Node = null
var _recording_manager: Node = null
var _ui: Node = null

# SubViewport y Camera3D dedicados para el recuadro PiP y la grabación independiente
var pip_viewport: SubViewport = null
var pip_camera_3d: Camera3D = null

## Configuration
@export_group("Camera Settings")
@export var free_cam_speed: float = 2.0
@export var free_cam_sensitivity: float = 0.5
@export var orbit_distance_min: float = 5.0
@export var orbit_distance_max: float = 200.0
@export var orbit_distance: float = 35.0
@export var orbit_height: float = 4.0
@export var orbit_h: float = 180.0
@export var orbit_v: float = 25.0
@export var orbit_relative_to_target: bool = true
@export var follow_smoothing: float = 0.12
@export var cinematic_smoothing: float = 0.05

@export_group("POV Settings")
@export var eye_height_offset: float = 0.0
@export var eye_forward_offset: float = 0.8
@export var pov_pitch: float = 0.0
@export var pov_fov: float = 75.0
@export var pov_smoothing: float = 0.35

@export_group("Panoramic Settings")
@export var panoramic_speed: float = 10.0
@export var panoramic_auto_rotate: bool = true

@export_group("Cinematic Settings")
@export var cinematic_speed: float = 1.0
@export var cinematic_distance: float = 35.0
@export var cinematic_height: float = 14.0
@export var cinematic_shake_intensity: float = 0.5
@export var cinematic_dof_enabled: bool = true
@export var cinematic_dof_focal_distance: float = 35.0
@export var cinematic_dof_blur_amount: float = 1.5

@export_group("Landscape Settings")
@export var landscape_height: float = 100.0
@export var landscape_look_down_angle: float = 60.0

@export_group("Platform Presets (Resolution)")
@export var youtube_res: Vector2i = Vector2i(1920, 1080)
@export var instagram_feed_res: Vector2i = Vector2i(1080, 1080)
@export var instagram_story_res: Vector2i = Vector2i(1080, 1920)
@export var tiktok_res: Vector2i = Vector2i(1080, 1920)
@export var custom_res: Vector2i = Vector2i(1920, 1080)

@export_group("Recording")
@export var recording_fps: int = 60
@export var recording_quality: int = 90
@export var recording_path: String = "user://social_media_recordings/"

## Internal State
var _original_camera_state: Dictionary = {}
var _panoramic_angle: float = 0.0
var _cinematic_time: float = 0.0
var _custom_target: Node = null
var _free_cam_pivot: Vector3 = Vector3.ZERO
var _free_cam_dragging: bool = false

signal mode_changed(new_mode: CameraMode)
signal platform_changed(new_platform: PlatformPreset)
signal recording_started(platform: PlatformPreset, resolution: Vector2i)
signal recording_stopped(file_path: String)
signal camera_activated()
signal camera_deactivated()
signal pip_mode_toggled(is_pip: bool)
signal bosses_updated(bosses: Array)

func _ready():
	_load_config()
	_recording_manager = get_node_or_null("/root/RecManager")
	if not _recording_manager:
		_recording_manager = load("res://scripts/systems/RecordingManager.gd").new()
		get_tree().root.add_child(_recording_manager)
	
	call_deferred("_connect_to_ui")
	call_deferred("_setup_pip_system")

func _ensure_references() -> bool:
	if not is_instance_valid(_base_map):
		_base_map = get_tree().get_first_node_in_group("map")
		if _base_map:
			_camera_3d = _base_map.get("camera_3d")
			if _base_map.has_signal("camera_mode_changed"):
				if not _base_map.camera_mode_changed.is_connected(_on_base_map_camera_mode_changed):
					_base_map.camera_mode_changed.connect(_on_base_map_camera_mode_changed)
	if not is_instance_valid(_camera_3d) and is_instance_valid(_base_map):
		_camera_3d = _base_map.get("camera_3d")
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(_ui):
		_connect_to_ui()
	if not is_instance_valid(pip_viewport) and is_instance_valid(_base_map):
		_setup_pip_system()
	return is_instance_valid(_base_map)

func _setup_pip_system():
	if is_instance_valid(pip_viewport): return
	if not is_instance_valid(_base_map):
		_base_map = get_tree().get_first_node_in_group("map")
	if not is_instance_valid(_base_map): return
	
	var map_subviewport = _base_map.get("sub_viewport")
	if not is_instance_valid(map_subviewport):
		return
	
	# Crear SubViewport para renderizar el mundo 3D en el recuadro PiP de grabación
	pip_viewport = SubViewport.new()
	pip_viewport.name = "SocialPiPViewport"
	pip_viewport.size = get_current_resolution()
	pip_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	pip_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	pip_viewport.own_world_3d = false
	
	# Compartir el mismo World3D para ver todos los asteroides, naves, bosses y VFX en tiempo real
	pip_viewport.world_3d = map_subviewport.find_world_3d()
	
	pip_camera_3d = Camera3D.new()
	pip_camera_3d.name = "SocialPiPCamera"
	pip_camera_3d.current = true
	pip_camera_3d.fov = 70.0
	pip_viewport.add_child(pip_camera_3d)
	
	add_child(pip_viewport)
	print("[SocialMediaCamera] Sistema PiP inicializado correctamente compartiendo World3D.")

func get_active_camera() -> Camera3D:
	if not is_instance_valid(pip_camera_3d):
		_setup_pip_system()
	if is_instance_valid(pip_camera_3d):
		return pip_camera_3d
	return _camera_3d

func _connect_to_ui():
	var ui = get_tree().get_first_node_in_group("social_camera_ui")
	if not is_instance_valid(ui):
		var hud = get_tree().get_first_node_in_group("hud")
		if hud:
			ui = hud.get_node_or_null("SocialMediaCameraUI")
	if not is_instance_valid(ui):
		ui = get_node_or_null("/root/SocialMediaCameraUI")
	
	if is_instance_valid(ui):
		_ui = ui
		if not _ui.mode_changed.is_connected(_on_ui_mode_changed):
			_ui.mode_changed.connect(_on_ui_mode_changed)
		if not _ui.platform_changed.is_connected(_on_ui_platform_changed):
			_ui.platform_changed.connect(_on_ui_platform_changed)
		if not _ui.recording_toggled.is_connected(_on_ui_recording_toggled):
			_ui.recording_toggled.connect(_on_ui_recording_toggled)
		if not _ui.config_changed.is_connected(_on_ui_config_changed):
			_ui.config_changed.connect(_on_ui_config_changed)
		_ui.set_camera_system(self)

func _load_config():
	var config = ConfigFile.new()
	var path = "user://social_camera_config.cfg"
	if config.load(path) == OK:
		current_mode = int(config.get_value("camera", "mode", 0)) as CameraMode
		current_platform = int(config.get_value("camera", "platform", 0)) as PlatformPreset
		# Siempre asegurar que PiP esté activo para proteger la cámara del jugador
		is_pip_mode = true
		orbit_distance = float(config.get_value("camera", "orbit_distance", 35.0))
		orbit_height = float(config.get_value("camera", "orbit_height", 4.0))
		orbit_h = float(config.get_value("camera", "orbit_h", 180.0))
		orbit_v = float(config.get_value("camera", "orbit_v", 25.0))
		orbit_relative_to_target = bool(config.get_value("camera", "orbit_relative_to_target", true))
		follow_smoothing = float(config.get_value("camera", "follow_smoothing", 0.12))
		eye_height_offset = float(config.get_value("camera", "eye_height_offset", 0.0))
		eye_forward_offset = float(config.get_value("camera", "eye_forward_offset", 0.8))
		pov_pitch = float(config.get_value("camera", "pov_pitch", 0.0))
		pov_fov = float(config.get_value("camera", "pov_fov", 75.0))
		pov_smoothing = float(config.get_value("camera", "pov_smoothing", 0.35))
		panoramic_speed = float(config.get_value("camera", "panoramic_speed", 10.0))
		cinematic_speed = float(config.get_value("camera", "cinematic_speed", 1.0))
		cinematic_distance = float(config.get_value("camera", "cinematic_distance", 35.0))
		cinematic_height = float(config.get_value("camera", "cinematic_height", 14.0))
		cinematic_smoothing = float(config.get_value("camera", "cinematic_smoothing", 0.05))
		cinematic_dof_blur_amount = float(config.get_value("camera", "cinematic_dof_blur_amount", 1.5))
		landscape_height = float(config.get_value("camera", "landscape_height", 100.0))
		landscape_look_down_angle = float(config.get_value("camera", "landscape_look_down_angle", 60.0))
		free_cam_speed = float(config.get_value("camera", "free_cam_speed", 2.0))
		recording_fps = int(config.get_value("recording", "fps", 60))
		recording_quality = int(config.get_value("recording", "quality", 90))
		recording_path = config.get_value("recording", "path", "user://social_media_recordings/")

func _save_config():
	var config = ConfigFile.new()
	config.set_value("camera", "mode", int(current_mode))
	config.set_value("camera", "platform", int(current_platform))
	config.set_value("camera", "is_pip_mode", is_pip_mode)
	config.set_value("camera", "orbit_distance", orbit_distance)
	config.set_value("camera", "orbit_height", orbit_height)
	config.set_value("camera", "orbit_h", orbit_h)
	config.set_value("camera", "orbit_v", orbit_v)
	config.set_value("camera", "orbit_relative_to_target", orbit_relative_to_target)
	config.set_value("camera", "follow_smoothing", follow_smoothing)
	config.set_value("camera", "eye_height_offset", eye_height_offset)
	config.set_value("camera", "eye_forward_offset", eye_forward_offset)
	config.set_value("camera", "pov_pitch", pov_pitch)
	config.set_value("camera", "pov_fov", pov_fov)
	config.set_value("camera", "pov_smoothing", pov_smoothing)
	config.set_value("camera", "panoramic_speed", panoramic_speed)
	config.set_value("camera", "cinematic_speed", cinematic_speed)
	config.set_value("camera", "cinematic_distance", cinematic_distance)
	config.set_value("camera", "cinematic_height", cinematic_height)
	config.set_value("camera", "cinematic_smoothing", cinematic_smoothing)
	config.set_value("camera", "cinematic_dof_blur_amount", cinematic_dof_blur_amount)
	config.set_value("camera", "landscape_height", landscape_height)
	config.set_value("camera", "landscape_look_down_angle", landscape_look_down_angle)
	config.set_value("camera", "free_cam_speed", free_cam_speed)
	config.set_value("recording", "fps", recording_fps)
	config.set_value("recording", "quality", recording_quality)
	config.set_value("recording", "path", recording_path)
	var path = "user://social_camera_config.cfg"
	config.save(path)

func _on_base_map_camera_mode_changed(enabled: bool):
	if enabled and not is_active and not is_pip_mode:
		_activate_camera()
	elif not enabled and is_active and not is_pip_mode:
		_deactivate_camera()

func set_pip_mode(enabled: bool):
	is_pip_mode = enabled
	pip_mode_toggled.emit(is_pip_mode)
	_save_config()
	if not is_pip_mode:
		if _base_map:
			_base_map.set_meta("social_camera_override", true)
			_base_map.free_cam_active = false
	else:
		if _base_map:
			_base_map.set_meta("social_camera_override", false)
			if _original_camera_state.has("free_cam_active"):
				_base_map.free_cam_active = _original_camera_state.get("free_cam_active", false)
	_apply_mode()

func _activate_camera():
	_ensure_references()
	if is_active: return
	
	_save_original_camera_state()
	
	if _base_map:
		_base_map.set_meta("social_camera_override", not is_pip_mode)
		if not is_pip_mode:
			_base_map.free_cam_active = false
	
	if not _player:
		_player = get_tree().get_first_node_in_group("player")
	
	is_active = true
	camera_activated.emit()
	_apply_mode()
	print("[SocialMediaCamera] Activated - Mode: ", get_mode_name(), " (PiP=", is_pip_mode, ")")

func _deactivate_camera():
	if not is_active: return
	
	_restore_original_camera_state()
	
	if _base_map:
		_base_map.set_meta("social_camera_override", false)
		if not is_pip_mode:
			_base_map.free_cam_active = false
	
	is_active = false
	if is_recording:
		stop_recording()
	
	camera_deactivated.emit()
	print("[SocialMediaCamera] Deactivated")

func _save_original_camera_state():
	if not _base_map: return
	_original_camera_state = {
		"free_cam_active": _base_map.free_cam_active,
		"free_cam_h": _base_map.free_cam_h,
		"free_cam_v": _base_map.free_cam_v,
		"free_cam_zoom": _base_map.free_cam_zoom,
		"free_orbit_mode": _base_map.free_orbit_mode,
		"free_cam_center": _base_map.free_cam_center,
	}

func _restore_original_camera_state():
	if not _base_map: return
	for key in _original_camera_state:
		if key in _base_map:
			_base_map.set(key, _original_camera_state[key])
	if _base_map.has_method("_sync_zooms_from_free"):
		_base_map._sync_zooms_from_free()

func _process(delta: float):
	if not is_active:
		return
	if not _ensure_references():
		return
	
	_handle_input()
	_update_camera_mode(delta)

func _handle_input():
	if not is_active: return
	if Input.is_action_just_pressed("social_camera_toggle"):
		toggle_camera()
	elif Input.is_action_just_pressed("social_camera_mode_next"):
		cycle_mode(1)
	elif Input.is_action_just_pressed("social_camera_mode_prev"):
		cycle_mode(-1)
	elif Input.is_action_just_pressed("social_camera_record"):
		toggle_recording()

func _unhandled_input(event: InputEvent):
	if not is_active: return
	# En modo PiP (ventana flotante), solo procesar si el panel de cámara F7 está abierto
	if is_pip_mode and (not is_instance_valid(_ui) or not _ui.visible):
		return
	
	# Interacción con mouse en cámara libre y modos orbitales
	if current_mode == CameraMode.FREE or current_mode == CameraMode.PLAYER_VIEW or current_mode == CameraMode.ENEMY_VIEW or current_mode == CameraMode.PANORAMIC:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
				_free_cam_dragging = event.pressed
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
				orbit_distance = clampf(orbit_distance - 2.5, orbit_distance_min, orbit_distance_max)
				_save_config()
				if _ui and _ui.has_method("notify_orbit_changed"):
					_ui.notify_orbit_changed(orbit_distance, orbit_h, orbit_v)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
				orbit_distance = clampf(orbit_distance + 2.5, orbit_distance_min, orbit_distance_max)
				_save_config()
				if _ui and _ui.has_method("notify_orbit_changed"):
					_ui.notify_orbit_changed(orbit_distance, orbit_h, orbit_v)
		elif event is InputEventMouseMotion and _free_cam_dragging:
			orbit_h = fmod(orbit_h + event.relative.x * 0.25 * free_cam_sensitivity, 360.0)
			if orbit_h < 0.0: orbit_h += 360.0
			orbit_v = clampf(orbit_v + event.relative.y * 0.2 * free_cam_sensitivity, 5.0, 85.0)
			if _ui and _ui.has_method("notify_orbit_changed"):
				_ui.notify_orbit_changed(orbit_distance, orbit_h, orbit_v)

func _update_camera_mode(delta: float):
	match current_mode:
		CameraMode.FREE:
			_update_free_camera(delta)
		CameraMode.PLAYER_VIEW:
			_update_player_view(delta)
		CameraMode.BOSS_POV:
			_update_boss_pov(delta)
		CameraMode.ENEMY_VIEW:
			_update_enemy_view(delta)
		CameraMode.PANORAMIC:
			_update_panoramic(delta)
		CameraMode.CINEMATIC:
			_update_cinematic(delta)
		CameraMode.LANDSCAPE:
			_update_landscape(delta)
		CameraMode.CUSTOM:
			_update_custom(delta)

func get_current_target() -> Node:
	if is_instance_valid(_target_entity):
		if ("is_dead" in _target_entity and _target_entity.is_dead) or not _target_entity.is_inside_tree():
			_target_entity.set_meta("is_camera_target", false)
			_target_entity = null
		else:
			return _target_entity
	if is_instance_valid(_player):
		return _player
	_player = get_tree().get_first_node_in_group("player")
	return _player

func get_target_3d_info(target: Node) -> Dictionary:
	var base_pos = Vector3.ZERO
	var head_height = 2.2
	var rot_2d = 0.0
	
	if not is_instance_valid(target):
		return {
			"base_pos": base_pos,
			"head_height": head_height,
			"head_pos": base_pos + Vector3(0, head_height, 0),
			"forward": Vector3.FORWARD,
			"rot_2d": rot_2d
		}
	
	if "rotation" in target:
		rot_2d = target.rotation
	
	# Forzar sincronización visual 3D inmediata
	if target.has_method("_update_3d_root_sync"):
		target._update_3d_root_sync()
	
	# Determinar base 3D de la entidad
	if "world_root_3d" in target and is_instance_valid(target.world_root_3d):
		base_pos = target.world_root_3d.global_position
	elif "global_position" in target:
		base_pos = _get_3d_pos_from_2d(target.global_position, 0.0)
	
	# Determinar altura real de cabeza / ojos según la escala del modelo
	var is_player = target.is_in_group("player")
	if is_player:
		head_height = 2.2
	else:
		var entity_type = int(target.get("entity_type") if "entity_type" in target else 1)
		var raw_type = str(target.get("raw_entity_type") if "raw_entity_type" in target else str(entity_type))
		var max_h = float(target.get("max_hp") if "max_hp" in target else 1000.0)
		var is_boss_flag = target.has_meta("is_boss") or max_h >= 10000.0 or entity_type >= 101
		
		# Altura base inteligente según configuración de enemigos
		var gc = get_node_or_null("/root/GameConstants")
		if is_instance_valid(gc) and "ENEMY_MODELS" in gc:
			var cfg = gc.ENEMY_MODELS.get(raw_type, gc.ENEMY_MODELS.get(str(entity_type), {}))
			if cfg.has("hudHeight"):
				head_height = float(cfg.hudHeight) * 0.85
			elif cfg.has("scale") and float(cfg.scale) > 5.0:
				head_height = float(cfg.scale) * 1.5
			elif is_boss_flag:
				head_height = 8.5
			else:
				head_height = 2.4
		else:
			head_height = 8.5 if is_boss_flag else 2.4
		
		# Si tiene mallas 3D instanciadas, calcular AABB para máxima fidelidad
		if "world_root_3d" in target and is_instance_valid(target.world_root_3d):
			var max_mesh_y = 0.0
			var meshes = target.world_root_3d.find_children("*", "MeshInstance3D", true, false)
			for m in meshes:
				if m is MeshInstance3D and m.mesh:
					var aabb = m.get_aabb()
					var top_y = (m.global_position.y - base_pos.y) + (aabb.size.y * m.global_basis.get_scale().y)
					if top_y > max_mesh_y:
						max_mesh_y = top_y
			if max_mesh_y > 1.0:
				head_height = max_mesh_y * 0.88
	
	var corr_z = float(_base_map.correction_z) if (_base_map and "correction_z" in _base_map) else 1.4142
	# En Descon 2D, las naves y enemigos apuntan hacia arriba (-Y en 2D, es decir rotation = angle + PI/2).
	# Por lo tanto, el ángulo frontal hacia donde mira la proa es: visual_angle = rot_2d - (PI * 0.5)
	var visual_angle = rot_2d - (PI * 0.5)
	var forward = Vector3(cos(visual_angle), 0.0, sin(visual_angle) * corr_z).normalized()
	
	var final_head_pos = base_pos + Vector3(0.0, max(0.5, head_height + eye_height_offset), 0.0) + forward * eye_forward_offset
	
	return {
		"base_pos": base_pos,
		"head_height": head_height,
		"head_pos": final_head_pos,
		"forward": forward,
		"rot_2d": rot_2d
	}

func _get_3d_pos_from_2d(pos_2d: Vector2, height: float = 0.0) -> Vector3:
	if not _base_map:
		return Vector3(pos_2d.x * 0.02, height, pos_2d.y * 0.02)
	var s_f = float(_base_map.scale_factor) if "scale_factor" in _base_map else 0.02
	var c_z = float(_base_map.correction_z) if "correction_z" in _base_map else 1.414
	return Vector3(pos_2d.x * s_f, height, pos_2d.y * (s_f * c_z))

func reset_free_cam_to_target():
	var target = get_current_target()
	if is_instance_valid(target):
		var info = get_target_3d_info(target)
		_free_cam_pivot = info.base_pos
	elif _base_map and "free_cam_center" in _base_map and _base_map.free_cam_center != Vector3.ZERO:
		_free_cam_pivot = _base_map.free_cam_center
	else:
		_free_cam_pivot = Vector3.ZERO
	orbit_h = 180.0
	orbit_v = 35.0
	orbit_distance = 35.0
	orbit_height = 4.0

func _update_free_camera(delta: float):
	var cam = get_active_camera()
	if not cam: return
	cam.fov = 70.0
	
	if _free_cam_pivot == Vector3.ZERO:
		reset_free_cam_to_target()
	
	var corr_z = float(_base_map.correction_z) if (_base_map and "correction_z" in _base_map) else 1.4142
	var rad_h = deg_to_rad(orbit_h)
	
	# Vector hacia adelante en el plano horizontal de la vista actual
	var fwd = Vector3(-sin(rad_h), 0.0, -cos(rad_h) * corr_z).normalized()
	var rgt = Vector3(cos(rad_h), 0.0, -sin(rad_h) * corr_z).normalized()
	
	var is_shift = Input.is_key_pressed(KEY_SHIFT)
	var move_speed = (free_cam_speed * 15.0) * (2.5 if is_shift else 1.0)
	
	var move_dir = Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move_dir += fwd
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move_dir -= fwd
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move_dir += rgt
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move_dir -= rgt
	
	if move_dir.length_squared() > 0.001:
		_free_cam_pivot += move_dir.normalized() * (move_speed * delta)
	
	# Altura del pivote (Q / E o Space / C)
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE):
		_free_cam_pivot.y += move_speed * delta
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_C):
		_free_cam_pivot.y = max(0.5, _free_cam_pivot.y - move_speed * delta)
	
	var rad_v = deg_to_rad(orbit_v)
	var dist = orbit_distance
	var r_horiz = dist * cos(rad_v)
	var y_offset = (dist * sin(rad_v)) + orbit_height
	var x_offset = r_horiz * sin(rad_h)
	var z_offset = r_horiz * cos(rad_h) * corr_z
	
	var dest = _free_cam_pivot + Vector3(x_offset, y_offset, z_offset)
	cam.global_position = cam.global_position.lerp(dest, 0.25)
	cam.look_at(_free_cam_pivot, Vector3.UP)
	
	if not is_pip_mode and _base_map and is_instance_valid(_camera_3d):
		_base_map.set_meta("social_camera_override", true)
		_camera_3d.global_position = cam.global_position
		_camera_3d.global_transform = cam.global_transform
	elif _base_map and _base_map.has_meta("social_camera_override") and _base_map.get_meta("social_camera_override"):
		_base_map.set_meta("social_camera_override", false)

func _update_player_view(delta: float):
	_update_orbit_target(delta)

func _update_enemy_view(delta: float):
	_update_orbit_target(delta)

func _update_orbit_target(_delta: float):
	"""Cámara orbital 3ª Persona sobre el objetivo actual (Jugador o Boss)"""
	var cam = get_active_camera()
	if not cam: return
	cam.fov = 70.0
	
	var target = get_current_target()
	var info = get_target_3d_info(target)
	var target_center = info.base_pos + Vector3(0, max(0.5, info.head_height * 0.5), 0)
	
	# Ángulo horizontal: si es relativo, se orienta con la nave/target para mantenerse detrás al volar
	var base_rot = 0.0
	if orbit_relative_to_target and "rotation" in target:
		base_rot = -(target.rotation - (PI * 0.5))
	
	var rad_h = base_rot + deg_to_rad(orbit_h)
	var rad_v = deg_to_rad(orbit_v)
	var corr_z = float(_base_map.correction_z) if (_base_map and "correction_z" in _base_map) else 1.4142
	
	var r_horiz = orbit_distance * cos(rad_v)
	var y_offset = (orbit_distance * sin(rad_v)) + orbit_height
	var x_offset = r_horiz * sin(rad_h)
	var z_offset = r_horiz * cos(rad_h) * corr_z
	
	var cam_dest = target_center + Vector3(x_offset, y_offset, z_offset)
	cam.global_position = cam.global_position.lerp(cam_dest, clampf(follow_smoothing * 2.5, 0.02, 1.0))
	cam.look_at(target_center, Vector3.UP)
	
	# Si no estamos en PiP (pantalla completa), sincronizar la cámara principal del mapa
	if not is_pip_mode and _base_map and is_instance_valid(_camera_3d):
		_base_map.set_meta("social_camera_override", true)
		_camera_3d.global_position = cam.global_position
		_camera_3d.global_transform = cam.global_transform
	elif _base_map and _base_map.has_meta("social_camera_override") and _base_map.get_meta("social_camera_override"):
		_base_map.set_meta("social_camera_override", false)

func _update_boss_pov(_delta: float):
	"""Cámara en Primera Persona (POV) desde los ojos de la entidad seleccionada mirando al frente"""
	var cam = get_active_camera()
	if not cam: return
	
	var target = get_current_target()
	var info = get_target_3d_info(target)
	var head_pos = info.head_pos
	var forward = info.forward
	
	cam.fov = pov_fov
	
	# Look target con compensación de pitch
	var pitch_offset = Vector3(0.0, pov_pitch * 0.8, 0.0)
	var look_target = head_pos + forward * 80.0 + pitch_offset
	
	# Si la cámara está lejos de la cabeza (cambio reciente de target), reubicarla inmediatamente
	if cam.global_position.distance_to(head_pos) > 30.0:
		cam.global_position = head_pos
	else:
		cam.global_position = cam.global_position.lerp(head_pos, clampf(pov_smoothing * 2.5, 0.15, 1.0))
	
	cam.look_at(look_target, Vector3.UP)

func _update_panoramic(delta: float):
	var cam = get_active_camera()
	if not cam: return
	cam.fov = 70.0
	
	if panoramic_auto_rotate:
		_panoramic_angle += panoramic_speed * delta
		orbit_h = fmod(_panoramic_angle, 360.0)
	
	_update_orbit_target(delta)

func _update_cinematic(delta: float):
	"""Tomas cinematográficas continuas y fluidas de drone/cine alrededor del objetivo"""
	var cam = get_active_camera()
	if not cam: return
	cam.fov = 68.0
	
	_cinematic_time += delta
	
	var target = get_current_target()
	var info = get_target_3d_info(target)
	var target_center = info.base_pos + Vector3(0, info.head_height * 0.45, 0)
	
	var corr_z = float(_base_map.correction_z) if (_base_map and "correction_z" in _base_map) else 1.4142
	var angle = _cinematic_time * cinematic_speed * 0.12
	var dist = cinematic_distance
	var cur_height = max(2.0, cinematic_height + sin(_cinematic_time * 0.4) * (cinematic_height * 0.3))
	
	var cam_dest = target_center + Vector3(
		dist * cos(angle),
		cur_height,
		dist * sin(angle) * corr_z
	)
	
	cam.global_position = cam.global_position.lerp(cam_dest, clampf(cinematic_smoothing * 3.0, 0.02, 0.5))
	cam.look_at(target_center, Vector3.UP)
	
	# Ajustar foco DOF dinámico en el centro del objetivo
	if cinematic_dof_enabled and cam.attributes is CameraAttributesPractical and cam.attributes.dof_blur_far_enabled:
		var target_dist = cam.global_position.distance_to(target_center)
		cam.attributes.dof_blur_far_distance = target_dist

func _update_landscape(_delta: float):
	var cam = get_active_camera()
	if not cam: return
	cam.fov = 70.0
	
	var target = get_current_target()
	var info = get_target_3d_info(target)
	var center = info.base_pos
	center.y = landscape_height
	
	var rad_h = deg_to_rad(orbit_h)
	var rad_v = deg_to_rad(landscape_look_down_angle)
	var dist = orbit_distance * 2.2
	
	var offset = Vector3(
		dist * sin(rad_v) * cos(rad_h),
		dist * cos(rad_v),
		dist * sin(rad_v) * sin(rad_h)
	)
	
	cam.global_position = cam.global_position.lerp(center + offset, 0.1)
	cam.look_at(center, Vector3.UP)

func _update_custom(delta: float):
	if is_instance_valid(_custom_target):
		_target_entity = _custom_target
		_update_orbit_target(delta)
	else:
		_update_orbit_target(delta)

func _apply_mode():
	if not _ensure_references(): return
	var cam = get_active_camera()
	if not cam: return
	
	match current_mode:
		CameraMode.FREE:
			if _free_cam_pivot == Vector3.ZERO:
				reset_free_cam_to_target()
			cam.fov = 70.0
			cam.attributes = null
		CameraMode.PLAYER_VIEW, CameraMode.ENEMY_VIEW:
			orbit_distance = 35.0
			orbit_h = 180.0
			orbit_v = 30.0
			cam.fov = 70.0
			cam.attributes = null
		CameraMode.BOSS_POV:
			cam.fov = pov_fov
			cam.attributes = null
		CameraMode.PANORAMIC:
			_panoramic_angle = orbit_h
			cam.fov = 70.0
			cam.attributes = null
		CameraMode.CINEMATIC:
			_cinematic_time = 0.0
			_setup_cinematic_dof()
		CameraMode.LANDSCAPE:
			orbit_v = landscape_look_down_angle
			cam.fov = 70.0
			cam.attributes = null
		CameraMode.CUSTOM:
			cam.fov = 70.0
			cam.attributes = null
	
	_update_camera_mode(0.016)

func _setup_cinematic_dof():
	var cam = get_active_camera()
	if not cam: return
	# Depth of Field solo está soportado por Godot 4 en Forward+ o Mobile (RenderingDevice).
	# En el renderer Compatibility (OpenGL) emite un warning de C++ al activarlo.
	var supports_dof = RenderingServer.get_rendering_device() != null
	if cinematic_dof_enabled and supports_dof:
		var dof = CameraAttributesPractical.new()
		dof.dof_blur_far_enabled = true
		dof.dof_blur_far_distance = cinematic_dof_focal_distance
		dof.dof_blur_amount = cinematic_dof_blur_amount
		cam.attributes = dof
	else:
		cam.attributes = null

func set_mode(mode: CameraMode):
	_ensure_references()
	if not is_active:
		_activate_camera()
	current_mode = mode
	_apply_mode()
	mode_changed.emit(mode)
	_save_config()
	if _ui:
		_ui.update_mode_display(int(mode))

func set_platform(platform: PlatformPreset):
	current_platform = platform
	if is_instance_valid(pip_viewport):
		var vp_parent = pip_viewport.get_parent()
		# Si el padre es un SubViewportContainer con stretch activo, su tamaño se controla por layout
		if not (vp_parent is SubViewportContainer and vp_parent.stretch):
			pip_viewport.size = get_current_resolution()
	platform_changed.emit(platform)
	_save_config()
	if _ui:
		_ui.update_platform_display(int(platform))

func cycle_mode(direction: int):
	var modes = [CameraMode.FREE, CameraMode.PLAYER_VIEW, CameraMode.BOSS_POV, CameraMode.ENEMY_VIEW, 
				 CameraMode.PANORAMIC, CameraMode.CINEMATIC, CameraMode.LANDSCAPE, CameraMode.CUSTOM]
	var idx = modes.find(current_mode)
	idx = (idx + direction) % modes.size()
	if idx < 0: idx += modes.size()
	set_mode(modes[idx])

func get_current_resolution() -> Vector2i:
	match current_platform:
		PlatformPreset.YOUTUBE: return youtube_res
		PlatformPreset.INSTAGRAM_FEED: return instagram_feed_res
		PlatformPreset.INSTAGRAM_STORY: return instagram_story_res
		PlatformPreset.TIKTOK: return tiktok_res
		PlatformPreset.CUSTOM: return custom_res
	return youtube_res

func get_platform_name() -> String:
	match current_platform:
		PlatformPreset.YOUTUBE: return "YouTube (16:9)"
		PlatformPreset.INSTAGRAM_FEED: return "Instagram Feed (1:1)"
		PlatformPreset.INSTAGRAM_STORY: return "Instagram Story (9:16)"
		PlatformPreset.TIKTOK: return "TikTok (9:16)"
		PlatformPreset.CUSTOM: return "Custom"
	return "Unknown"

func get_mode_name() -> String:
	match current_mode:
		CameraMode.FREE: return "Libre (WASD)"
		CameraMode.PLAYER_VIEW: return "Vista Jugador"
		CameraMode.BOSS_POV: return "1ª Persona Boss (POV)"
		CameraMode.ENEMY_VIEW: return "Órbita Boss / Enemigo"
		CameraMode.PANORAMIC: return "Panorámica 360°"
		CameraMode.CINEMATIC: return "Cinemática"
		CameraMode.LANDSCAPE: return "Paisaje Aéreo"
		CameraMode.CUSTOM: return "Objetivo Fijo"
	return "Desconocido"

func toggle_camera():
	if is_active:
		_deactivate_camera()
	else:
		_activate_camera()

func toggle_recording():
	if is_recording:
		stop_recording()
	else:
		start_recording()

func start_recording():
	if is_recording: return
	if not is_active:
		_activate_camera()
	
	var res = get_current_resolution()
	var target_vp = pip_viewport if (is_pip_mode and is_instance_valid(pip_viewport)) else null
	
	if _recording_manager:
		if "_render_target" in _recording_manager and is_instance_valid(target_vp):
			_recording_manager.set("_render_target", target_vp)
		_recording_manager.start_recording(int(current_platform), res, recording_fps, recording_quality, recording_path)
	
	is_recording = true
	recording_started.emit(current_platform, res)
	if _ui:
		_ui.set_recording_state(true)

func stop_recording() -> String:
	if not is_recording: return ""
	var file_path = ""
	if _recording_manager:
		file_path = _recording_manager.stop_recording()
	is_recording = false
	recording_stopped.emit(file_path)
	if _ui:
		_ui.set_recording_state(false)
	return file_path

func open_recordings_folder():
	if _recording_manager and _recording_manager.has_method("open_output_folder"):
		_recording_manager.open_output_folder()

func set_config(config: Dictionary):
	for key in config:
		if key in self:
			set(key, config[key])
	_apply_mode()
	_save_config()

func get_config() -> Dictionary:
	return {
		"mode": int(current_mode),
		"platform": int(current_platform),
		"is_pip_mode": is_pip_mode,
		"orbit_distance": orbit_distance,
		"orbit_height": orbit_height,
		"orbit_h": orbit_h,
		"orbit_v": orbit_v,
		"orbit_relative_to_target": orbit_relative_to_target,
		"follow_smoothing": follow_smoothing,
		"eye_height_offset": eye_height_offset,
		"eye_forward_offset": eye_forward_offset,
		"pov_pitch": pov_pitch,
		"pov_fov": pov_fov,
		"pov_smoothing": pov_smoothing,
		"panoramic_speed": panoramic_speed,
		"cinematic_speed": cinematic_speed,
		"cinematic_distance": cinematic_distance,
		"cinematic_height": cinematic_height,
		"cinematic_smoothing": cinematic_smoothing,
		"cinematic_dof_blur_amount": cinematic_dof_blur_amount,
		"landscape_height": landscape_height,
		"landscape_look_down_angle": landscape_look_down_angle,
		"free_cam_speed": free_cam_speed,
		"recording_fps": recording_fps,
		"recording_quality": recording_quality,
		"recording_path": recording_path,
	}

func _on_ui_mode_changed(mode: int):
	set_mode(mode as CameraMode)

func _on_ui_platform_changed(platform: int):
	set_platform(platform as PlatformPreset)

func _on_ui_recording_toggled(recording: bool):
	if recording:
		start_recording()
	else:
		stop_recording()

func _on_ui_config_changed(config: Dictionary):
	set_config(config)

func toggle_ui():
	if _ui:
		_ui.visible = not _ui.visible

## --- SISTEMA DE DETECCIÓN Y SELECCIÓN DE BOSSES ---
func get_available_bosses() -> Array[Dictionary]:
	var bosses: Array[Dictionary] = []
	var enemies = get_tree().get_nodes_in_group("enemies")
	
	for node in enemies:
		if not is_instance_valid(node): continue
		if "is_dead" in node and node.is_dead: continue
		
		var name_str = ""
		if "username" in node and str(node.username) != "" and str(node.username) != "Unknown":
			name_str = str(node.username)
		else:
			name_str = str(node.name)
		
		var hp = float(node.get("current_hp") if "current_hp" in node else 1000.0)
		var max_h = float(node.get("max_hp") if "max_hp" in node else 1000.0)
		var is_b = false
		
		if node.has_meta("is_boss") and node.get_meta("is_boss"):
			is_b = true
		elif max_h >= 10000.0:
			is_b = true
		else:
			var n_lower = name_str.to_lower()
			if n_lower.contains("boss") or n_lower.contains("titan") or n_lower.contains("reaper") or n_lower.contains("dragon") or n_lower.contains("lord") or n_lower.contains("almirante") or n_lower.contains("matriarca"):
				is_b = true
		
		bosses.append({
			"node": node,
			"name": name_str,
			"is_boss": is_b,
			"hp": hp,
			"max_hp": max_h,
			"pos": node.global_position if "global_position" in node else Vector2.ZERO
		})
	
	# Ordenar: Bosses confirmados primero, luego por mayor vida
	bosses.sort_custom(func(a, b):
		if a["is_boss"] != b["is_boss"]:
			return a["is_boss"] and not b["is_boss"]
		return a["max_hp"] > b["max_hp"]
	)
	
	bosses_updated.emit(bosses)
	return bosses

func select_boss_by_node(target_node: Node, change_mode: bool = false, enter_pov: bool = false) -> bool:
	if not is_instance_valid(target_node):
		return false
	
	if is_instance_valid(_target_entity) and _target_entity != target_node:
		_target_entity.set_meta("is_camera_target", false)
	
	_target_entity = target_node
	_target_entity.set_meta("is_camera_target", true)
	if _target_entity.has_method("_update_3d_root_sync"):
		_target_entity._update_3d_root_sync()
	
	if not is_active:
		_activate_camera()
	
	if change_mode:
		if enter_pov:
			set_mode(CameraMode.BOSS_POV)
		else:
			set_mode(CameraMode.ENEMY_VIEW)
	else:
		_apply_mode()
	return true

func select_player_target():
	if is_instance_valid(_target_entity):
		_target_entity.set_meta("is_camera_target", false)
	_target_entity = null
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if not is_active:
		_activate_camera()
	_apply_mode()

func select_nearest_boss() -> bool:
	var list = get_available_bosses()
	if list.is_empty(): return false
	
	var target = list[0]["node"] as Node
	return select_boss_by_node(target, false)

func select_nearest_enemy() -> bool:
	return select_nearest_boss()

func set_target_entity(entity: Node):
	if is_instance_valid(_target_entity) and _target_entity != entity:
		_target_entity.set_meta("is_camera_target", false)
	_target_entity = entity
	if is_instance_valid(_target_entity) and not _target_entity.is_in_group("player"):
		_target_entity.set_meta("is_camera_target", true)
		if _target_entity.has_method("_update_3d_root_sync"):
			_target_entity._update_3d_root_sync()
	if not is_active:
		_activate_camera()
	_apply_mode()

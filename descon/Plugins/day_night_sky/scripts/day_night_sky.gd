@tool
class_name DayNightSky
extends Node

@export_category("Camera")
@export var current_camera : Camera3D

@export_category("Time")
@export var editor_time: bool = false
@export var game_time: bool = true
@export var update_day: bool = true

var _current_time : float = 9.0
var _current_day : int = 1
var _current_month : int = 1
var _update_interval : float = 0.05

@export_range(0.0, 23.9998, 0.01) var current_time: float = 9.0:
	set(value):
		_current_time = fmod(value, 24.0)
		if _current_time < 0:
			_current_time += 24.0
	get:
		return _current_time

@export_range(1, 28, 1) var current_day: int = 1:
	set(value):
		_current_day = clamp(value, 1, DAYS_PER_MONTH)
	get:
		return _current_day

@export_range(1, 12, 1) var current_month: int = 1:
	set(value):
		_current_month = clamp(value, 1, MONTHS_PER_YEAR)
	get:
		return _current_month

@export_category("Time Settings")
# 1 = real time, 60
@export_range(-3600.0, 3600.0) var time_scale: float = 60.0

@export_category("Update Intervals")
@export_range(0.0, 1.0, 0.01) var update_interval : float = 0.05:
	set(value):
		_update_interval = value
	get:
		return _update_interval

@export_category("World Settings")
@export_range(-90, 90.0) var tilt : float = 23.45
@export_range(-90, 90.0) var latitude : float = 14.10194
@export_range(-180, 180.0) var longitude : float = -87.30695
@export_range(2.0, 10000000.0) var altitude : float = 990.0

@export_category("Sky Settings")
@export_range(1.0, 100.0) var sun_scale : float = 1.0
@export_range(1.0, 100.0) var moon_scale : float = 1.0
@export_range(-180, 180.0, 0.01) var moon_offset : float = 6.42
@export_range(0.0, 10.0, 0.01) var lunar_shadow_scale : float = 1.5

@export_category("Clouds Settings")
@export var clouds_layer : bool = false
@export var clouds_texture : Texture2D
@export var separated_clouds_layer : bool = false
@export var clouds_texture_1 : Texture2D
@export var clouds_texture_2 : Texture2D
@export var clouds_texture_3 : Texture2D
@export var clouds_texture_4 : Texture2D
@export_range(0.0, 1.0) var clouds_opacity : float = 1.0
@export_range(0.0, 1.0) var clouds_r_opacity : float = 1.0
@export_range(0.0, 1.0) var clouds_g_opacity : float = 0.0
@export_range(0.0, 1.0) var clouds_b_opacity : float = 0.0
@export_range(0.0, 1.0) var clouds_a_opacity : float = 0.0
@export var clouds_ray_marching : bool = false

const HOURS_PER_SECOND = 1.0 / 3600.0;
const SECONDS_PER_HOUR : int = 3600
const HOURS_PER_DAY: int = 24
const DAYS_PER_MONTH: int = 28
const MONTHS_PER_YEAR: int = 12

var _delta : float

func get_current_time(): return _current_time
func get_update_interval(): return _update_interval
func get_current_day(): return _current_day
func get_current_month(): return _current_month
func get_tilt(): return tilt
func get_latitude(): return latitude
func get_longitude(): return longitude
func get_altitude(): return altitude
func get_sun_scale(): return sun_scale
func get_moon_scale(): return moon_scale
func get_moon_offset(): return moon_offset
func get_lunar_shadow_scale(): return lunar_shadow_scale
func get_hours_per_day(): return HOURS_PER_DAY
func get_days_per_month(): return DAYS_PER_MONTH
func get_months_per_year(): return MONTHS_PER_YEAR

func _ready() -> void:
	_initialize()
	
#if TOOLS
	if Engine.is_editor_hint():
		var editor_interface = Engine.get_singleton("EditorInterface")
		if editor_interface:
			current_camera = editor_interface.get_editor_viewport_3d(0).get_viewport().get_camera_3d()
#endif
	if !Engine.is_editor_hint():
		if current_camera == null:
			current_camera = get_viewport().get_camera_3d()

func _process(delta: float) -> void:
	_delta = delta

	if Engine.is_editor_hint():
		if editor_time:
			if not _is_user_interacting_with_inspector():
				_update_time(_delta)
	if !Engine.is_editor_hint():
		if game_time:
			_update_time(_delta)
		if current_camera:
			altitude = current_camera.global_position.y

func _initialize() -> void:
#if TOOLS
	if Engine.is_editor_hint():
		await get_tree().process_frame
		_cache_editor_camera()
#else
	if !Engine.is_editor_hint():
		current_camera = get_viewport().get_camera_3d()
#endif

#if TOOLS
func _cache_editor_camera() -> void:
	var editor_interface = Engine.get_singleton("EditorInterface")
	if editor_interface:
			current_camera = editor_interface.get_editor_viewport_3d(0).get_viewport().get_camera_3d()
#endif

func _update_time(delta: float) -> void:
	if is_zero_approx(time_scale):
		return
	
	var delta_hours = delta * HOURS_PER_SECOND * time_scale
	_current_time += delta_hours
	
	var day_delta = floori(_current_time / HOURS_PER_DAY)
	if day_delta != 0:
		_current_time -= day_delta * HOURS_PER_DAY
		if update_day: _update_day(day_delta)

	_current_time = fmod(_current_time, HOURS_PER_DAY)
	if _current_time < 0:
		_current_time += HOURS_PER_DAY

	current_time = _current_time
	current_day = _current_day
	current_month = _current_month

	if Engine.is_editor_hint():
		notify_property_list_changed()

func _update_day(delta_day: int) -> void:
	_current_day += delta_day

	while _current_day > DAYS_PER_MONTH:
		_current_day -= DAYS_PER_MONTH
		_update_month(1)

	while _current_day < 1:
		_current_day += DAYS_PER_MONTH
		_update_month(-1)

func _update_month(delta_month: int) -> void:
	_current_month += delta_month

	while _current_month > MONTHS_PER_YEAR:
		_current_month -= MONTHS_PER_YEAR

	while _current_month < 1:
		_current_month += MONTHS_PER_YEAR

func _is_user_interacting_with_inspector() -> bool:
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

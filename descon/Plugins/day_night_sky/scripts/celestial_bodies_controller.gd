@tool
class_name CelestialBodiesController
extends Node

@export var day_night_sky: DayNightSky

@export var world : Node3D
@export var sun : Node3D
@export var sun_light : LightEmission
@export var moon : Node3D
@export var moon_light : LightEmission
@export var stars : Node3D

@export_group("Shadow Settings")
@export var sun_shadows_enabled : bool = true
@export var moon_shadows_enabled : bool = false

@export var use_solar_eclipse : bool = true
@export var use_lunar_eclipse : bool = false

@export_range(-180, 180.0, 0.01) var _moon_offset : float = 6.42

var _update_interval : float = 0.05
var _time_since_last_update : float = 0.0

const PLANET_RADIUS : float = 6371000.0;
const SUN_ANGULAR_RADIUS : float = 0.00464233333333;
const MOON_ANGULAR_RADIUS : float = 0.00452133194589;

const SUN_DIAMETER : float = 1392700.0;
const SUN_DISTANCE : float = 150000000.0;

const MOON_DIAMETER : float = 3476000.0;
const MOON_DISTANCE : float = 384400000.0;

@export var _lunar_shadow_scale: float = 1.5
const EARTH_UMBRA_RADIUS := deg_to_rad(0.7)
const EARTH_PENUMBRA_RADIUS := deg_to_rad(1.0)

var _current_time : float = 9.0
var _current_day : float = 1.0
var _current_month : float = 1.0
var _tilt : float = 23.45
var _latitude : float = 14.10194
var _longitude : float = -87.30695
var _altitude : float = 0.1
var _sun_scale : float = 1.0
var _moon_scale : float = 1.0
var _hours_per_day: int = 24
var _days_per_month: int = 28
var _months_per_year:  int = 12

var _solar_eclipse : bool = false
var _lunar_eclipse : bool = false

var _horizon_from_vertical_down : float
var _horizon_zenith_angle : float
var _sun_dir : Vector3
var _moon_dir : Vector3
var _sun_zenith_angle : float
var _moon_zenith_angle : float

var _sun_visibility : float
var _moon_visibility : float

var _sun_horizon_factor : float = 0.0
var _sun_eclipse_factor : float = 1.0

const INTENSITY_EPS := 0.005
const KELVIN_EPS := 5.0

func _ready() -> void:
	_initialize()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_interval_update(delta)
	
	if !Engine.is_editor_hint():
		_interval_update(delta)

func _initialize() -> void:
	if day_night_sky == null: day_night_sky = get_parent() as DayNightSky
	if sun == null: sun = day_night_sky.get_node("Sun") as Node3D
	if sun_light == null: sun_light = sun.get_node("SunLight") as LightEmission
	if moon == null: moon = day_night_sky.get_node("Moon") as Node3D
	if moon_light == null: moon_light = moon.get_node("MoonLight") as LightEmission
	if stars == null: stars = day_night_sky.get_node("Stars") as Node3D
	
	if sun_light:
		if sun_light.shadow_enabled != sun_shadows_enabled:
			sun_light.shadow_enabled = sun_shadows_enabled
	
	if moon_light:
		if moon_light.shadow_enabled != moon_shadows_enabled:
			moon_light.shadow_enabled = moon_shadows_enabled

func _interval_update(delta: float) -> void:
	if _update_interval <= 0.0:
		_update(delta)
		return

	_time_since_last_update += delta
	
	if _time_since_last_update >= _update_interval:
		_update(_time_since_last_update)
		_time_since_last_update = 0.0

func _update(delta: float) -> void:
	var r := PLANET_RADIUS + _altitude
	
	# Horizon angle
	_horizon_from_vertical_down = acos(PLANET_RADIUS / r)
	_horizon_zenith_angle = PI * 0.5 + _horizon_from_vertical_down
	
	# Sun angle
	_sun_dir = sun_light.global_transform.basis.z.normalized()
	_sun_zenith_angle = _sun_dir.angle_to(Vector3.UP)
	
	# Moon angle
	_moon_dir = moon_light.global_transform.basis.z.normalized()
	_moon_zenith_angle = _moon_dir.angle_to(Vector3.UP)
	
	_update_values()
	
	if world != null:
		_world_rotation(_current_time, world)
	
	if moon != null:
		_moon_rotation(_current_time, moon)
		
	if stars != null:
		_stars_rotation(_current_time, stars)
	
	if sun_light != null:
		_update_sun()
	
	if moon_light != null:
		_update_moon()
	
	_eclipse(delta, _sun_dir, _moon_dir)
	
	_update_sun_intensity(delta)

func _update_values() -> void:
	if day_night_sky == null: return
	
	if _current_time != day_night_sky.get_current_time():
		_current_time = day_night_sky.get_current_time()
	if _current_day != day_night_sky.get_current_day():
		_current_day = day_night_sky.get_current_day()
	if _current_month != day_night_sky.get_current_month():
		_current_month = day_night_sky.get_current_month()
	if _tilt != day_night_sky.get_tilt():
		_tilt = day_night_sky.get_tilt()
	if _latitude != day_night_sky.get_latitude():
		_latitude = day_night_sky.get_latitude()
	if _longitude != day_night_sky.get_longitude():
		_longitude = day_night_sky.get_longitude()
	if _altitude != day_night_sky.get_altitude():
		_altitude = day_night_sky.get_altitude()
	if _sun_scale != day_night_sky.get_sun_scale():
		_sun_scale = day_night_sky.get_sun_scale()
	if _moon_scale != day_night_sky.get_moon_scale():
		_moon_scale = day_night_sky.get_moon_scale()
	if _hours_per_day != day_night_sky.get_hours_per_day():
		_hours_per_day = day_night_sky.get_hours_per_day()
	if _days_per_month != day_night_sky.get_days_per_month():
		_days_per_month = day_night_sky.get_days_per_month()
	if _months_per_year != day_night_sky.get_months_per_year():
		_months_per_year = day_night_sky.get_months_per_year()
	if _moon_offset != day_night_sky.get_moon_offset():
		_moon_offset = day_night_sky.get_moon_offset()
	if _lunar_shadow_scale != day_night_sky.get_lunar_shadow_scale():
		_lunar_shadow_scale = day_night_sky.get_lunar_shadow_scale()
	if _update_interval != day_night_sky.get_update_interval():
		_update_interval = day_night_sky.get_update_interval()

func _world_rotation(current_time: float, world_node: Node3D) -> void:
	var time_angle: float = wrapf(current_time * 15.0, 0.0, 360.0)
	world_node.rotation_degrees = Vector3(_latitude, -_tilt, time_angle)

func _moon_rotation(current_time: float, moon_node: Node3D) -> void:
	var day_index : float = _current_day - 1 + (current_time / _hours_per_day)
	var monthly_angle : float = (day_index / _days_per_month) * 360.0
	var target_angle : float = wrapf(180.0 + monthly_angle + _moon_offset, 0.0, 360.0)
	moon_node.rotation_degrees.z = target_angle

func _stars_rotation(current_time: float, stars_node: Node3D) -> void:
	var total_day_index: float = ((_current_month - 1) * _days_per_month) + (_current_day - 1) + (current_time / _hours_per_day)
	var totals_day_in_year: int = _months_per_year * _days_per_month
	var target_angle: float = wrapf((total_day_index / totals_day_in_year) * 360.0, 0.0, 360.0)
	stars_node.rotation_degrees.z = target_angle

func _update_sun() -> void:
	_sun_visibility = get_light_visibility(
		_sun_zenith_angle,
		_horizon_zenith_angle,
		SUN_ANGULAR_RADIUS,
		deg_to_rad(5.0),
		deg_to_rad(0.0)
	)
	
	_sun_horizon_factor = _sun_visibility
	#if sun_light.intensity_multiplier != _sun_visibility && !_solar_eclipse: 
		#sun_light.intensity_multiplier = move_toward(sun_light.intensity_multiplier, _sun_visibility, 0.1)

func _update_moon() -> void:
	_moon_visibility = get_light_visibility(
		_moon_zenith_angle,
		_horizon_zenith_angle,
		MOON_ANGULAR_RADIUS,
		deg_to_rad(5.0),
		deg_to_rad(0.0)
	)
	
	if moon_light.intensity_multiplier != _moon_visibility && _sun_visibility < 0.25:
		moon_light.intensity_multiplier = move_toward(moon_light.intensity_multiplier, _moon_visibility * 0.1, 0.1)

func get_light_visibility(
	light_zenith_angle: float,
	horizon_zenith_angle: float,
	angular_radius: float,
	angular_offset: float = 0.0,
	horizon_offset: float = 0.0
) -> float:
	var effective_radius : float = max(angular_radius + angular_offset, 0.000001) + horizon_offset
	
	var d := light_zenith_angle - horizon_zenith_angle
	
	# above horizon
	if d <= -effective_radius: return 1.0
	
	# below horizon
	if d >= effective_radius: return 0.0
	
	# Partial visibility
	return clamp((effective_radius - d) / (2.0 * effective_radius), 0.0, 1.0)

func _get_angular_separation(dir_a: Vector3, dir_b: Vector3) -> float:
	# Returns angle in radians
	var dot : float = clamp(dir_a.normalized().dot(dir_b.normalized()), -1.0, 1.0)
	return acos(dot)

func _get_solar_eclipse_factor(
	sun_dir: Vector3,
	moon_dir: Vector3,
	sun_radius: float,
	moon_radius: float
) -> float:
	var d := _get_angular_separation(sun_dir, moon_dir)

	# No overlap
	if d >= sun_radius + moon_radius:
		return 0.0

	# Full eclipse
	if d <= abs(moon_radius - sun_radius) and moon_radius >= sun_radius:
		return 1.0

	# Partial overlap
	var r1 := sun_radius
	var r2 := moon_radius

	var x1 : float = clamp((d*d + r1*r1 - r2*r2) / (2.0*d*r1), -1.0, 1.0)
	var x2 : float = clamp((d*d + r2*r2 - r1*r1) / (2.0*d*r2), -1.0, 1.0)

	var a1 := r1*r1 * acos(x1)
	var a2 := r2*r2 * acos(x2)

	var a3 := 0.5 * sqrt(max(
		0.0,
		(-d + r1 + r2) *
		(d + r1 - r2) *
		(d - r1 + r2) *
		(d + r1 + r2)
	))

	var overlap_area := a1 + a2 - a3
	var sun_area := PI * r1 * r1

	return clamp(overlap_area / sun_area, 0.0, 1.0)

func _get_lunar_eclipse_factor(
	sun_dir: Vector3,
	moon_dir: Vector3,
	_sun_radius: float,
	_moon_radius: float
) -> float:
	var d : float = _get_angular_separation(sun_dir, moon_dir)

	# How far from perfect opposition
	var _delta : float = abs(PI - d)

	#var max_delta : float = sun_radius + moon_radius

	if _delta >= 0.2:
		return 0.0

	return clamp(
		1.0 - (_delta),
		0.0,
		1.0
	)

func _compute_target_value(
	factor: float,
	min_value: float = 0.0,
	max_value: float = 1.0
) -> float:
	var t := smoothstep(0.0, 1.0, clamp(factor, 0.0, 1.0))
	return lerp(max_value, min_value, t)

func _eclipse(delta: float, sun_dir: Vector3, moon_dir: Vector3) -> void:
	if sun_light == null or moon_light == null:
		return
	
	_update_solar_eclipse(delta, sun_dir, moon_dir)
	_update_lunar_eclipse(delta, sun_dir, moon_dir)

func _update_solar_eclipse(_delta: float, sun_dir: Vector3, moon_dir: Vector3) -> void:
	var overlap_factor := 0.0
	if use_solar_eclipse:
		overlap_factor = _get_solar_eclipse_factor(
			sun_dir, moon_dir,
			SUN_ANGULAR_RADIUS * _sun_scale,
			MOON_ANGULAR_RADIUS * _moon_scale
		)
	
	_sun_eclipse_factor = _compute_target_value(overlap_factor, 0.1, 1.0)
	_solar_eclipse = overlap_factor > 0.001

func _update_sun_intensity(_delta: float) -> void:
	var target_total = _sun_horizon_factor * _sun_eclipse_factor
	sun_light.intensity_multiplier = target_total

func _get_lunar_shadow_factor(
	shadow_sep: float,
	moon_radius: float
) -> float:
	#lunar_shadow_scale
	var earth_penumbra_radius : float = EARTH_PENUMBRA_RADIUS * _lunar_shadow_scale
	var earth_umbra_radius : float = EARTH_UMBRA_RADIUS * _lunar_shadow_scale
	# Fully outside penumbra
	if shadow_sep >= earth_penumbra_radius + moon_radius:
		return 0.0
	
	# Fully inside umbra
	if shadow_sep <= earth_umbra_radius - moon_radius:
		return 1.0
	
	# Penumbra → umbra transition
	return clamp(
		inverse_lerp(
			earth_penumbra_radius + moon_radius,
			earth_umbra_radius - moon_radius,
			shadow_sep
		),
		0.0,
		1.0
	)

func _update_lunar_eclipse(
	delta: float,
	sun_dir: Vector3,
	moon_dir: Vector3
) -> void:
	var factor := 0.0

	if use_lunar_eclipse:
		# Moon must be opposite the Sun
		var earth_shadow_dir := -sun_dir  # important
		var shadow_sep := _get_angular_separation(
			earth_shadow_dir,
			moon_dir
		)

		factor = _get_lunar_shadow_factor(
			shadow_sep,
			MOON_ANGULAR_RADIUS * _moon_scale
		)

	var target_kelvin := _compute_target_value(
		factor,
		1000.0,
		6500.0
	)

	if abs(moon_light.kelvin - target_kelvin) > KELVIN_EPS:
		moon_light.kelvin = lerp(
			moon_light.kelvin,
			target_kelvin,
			1.0 - exp(-1.0 * delta)
		)
	_lunar_eclipse = factor > 0.001

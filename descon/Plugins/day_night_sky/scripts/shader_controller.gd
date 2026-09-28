@tool
class_name ShaderController
extends Node

@export_category("References")
@export var sky_material: ShaderMaterial
@export var day_night_sky: DayNightSky
@export var celestial_bodies: CelestialBodiesController

var _last: Dictionary = {}

func _ready() -> void:
	_initialize()
	_sync_sky_to_shader()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or not Engine.is_editor_hint():
		_sync_sky_to_shader()

func _initialize() -> void:
	if day_night_sky == null:
		day_night_sky = get_parent() as DayNightSky

	if celestial_bodies == null:
		celestial_bodies = get_node("../CelestialBodiesController") as CelestialBodiesController

func _update_shader_value(param_name: String, value: Variant) -> void:
	if sky_material == null:
		return

	if _last.get(param_name) == value:
		return

	_last[param_name] = value
	sky_material.set_shader_parameter(param_name, value)

func _sync_sky_to_shader() -> void:
	_sync_celestial_bodies()
	_sync_day_night_sky()

func _sync_celestial_bodies() -> void:
	if celestial_bodies == null:
		return

	_update_shader_value("latitude", celestial_bodies._latitude)
	_update_shader_value("longitude", celestial_bodies._longitude)
	_update_shader_value("altitude", celestial_bodies._altitude)
	_update_shader_value("sun_scale", celestial_bodies._sun_scale)
	_update_shader_value("moon_scale", celestial_bodies._moon_scale)

	if celestial_bodies.moon_light:
		_update_shader_value(
			"moon_matrix",
			celestial_bodies.moon_light.global_basis.transposed()
		)

	if celestial_bodies.stars:
		_update_shader_value(
			"stars_matrix",
			celestial_bodies.stars.global_basis.transposed()
		)

func _sync_day_night_sky() -> void:
	if day_night_sky == null:
		return

	_update_shader_value("show_clouds", day_night_sky.clouds_layer)
	_update_shader_value("clouds_texture", day_night_sky.clouds_texture)
	_update_shader_value("separate_clouds_layers", day_night_sky.separated_clouds_layer)
	_update_shader_value("clouds_texture_1", day_night_sky.clouds_texture_1)
	_update_shader_value("clouds_texture_2", day_night_sky.clouds_texture_2)
	_update_shader_value("clouds_texture_3", day_night_sky.clouds_texture_3)
	_update_shader_value("clouds_texture_4", day_night_sky.clouds_texture_4)
	_update_shader_value("use_ray_marching", day_night_sky.clouds_ray_marching)
	_update_shader_value("clouds_opacity", day_night_sky.clouds_opacity)
	_update_shader_value("clouds_r_opacity", day_night_sky.clouds_r_opacity)
	_update_shader_value("clouds_g_opacity", day_night_sky.clouds_g_opacity)
	_update_shader_value("clouds_b_opacity", day_night_sky.clouds_b_opacity)
	_update_shader_value("clouds_a_opacity", day_night_sky.clouds_a_opacity)

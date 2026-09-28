@tool
class_name LightEmission
extends DirectionalLight3D

@export var filter: Color = Color.WHITE
@export var temperature: Gradient

@export_range(1000.0, 20000.0, 100.0)
var kelvin: float = 6500.0

@export_range(0.0, 260000.0, 1.0) var intensity: float = 130000.0 # lux
@export_range(0.0, 1.0) var intensity_multiplier : float = 1.0

const MAX_LUX := 130000.0
@export var log_curve_strength : float = 20.0

@export_category("Shadow")
@export var enable_shadow : bool = true

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_update_light()
	if !Engine.is_editor_hint():
		_update_light()

func _update_light() -> void:
	_update_intensity()
	_update_color()
	_update_shadow()

func _update_intensity() -> void:
	light_energy = (intensity * intensity_multiplier) / MAX_LUX

func _update_color() -> void:
	if temperature == null:
		return

	var t := inverse_lerp(1000.0, 20000.0, kelvin)
	t = clamp(t, 0.0, 1.0)

	var kelvin_color := temperature.sample(t)
	light_color = kelvin_color * filter

func _update_shadow() -> void:
	if shadow_enabled != enable_shadow:
		shadow_enabled = enable_shadow
		

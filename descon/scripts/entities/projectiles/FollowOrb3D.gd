extends Node3D
class_name FollowOrb3D

# FollowOrb3D.gd - Script precompilado para orbes de seguimiento 3D (sifón, cura, sleep, etc.)
# Evita la compilación dinámica de GDScript en caliente durante el combate.

var target_node: Node2D = null
var s_factor: float = 0.02
var corr_z: float = 1.4142
var speed: float = 9.0
var life: float = 0.0
var max_life: float = 0.65
var accelerate_with_life: bool = true

func setup(p_target: Node2D, p_start: Vector3, p_s_factor: float, p_corr_z: float, p_speed: float = 9.0, p_max_life: float = 0.65, p_accel: bool = true):
	target_node = p_target
	global_position = p_start
	s_factor = p_s_factor
	corr_z = p_corr_z
	speed = p_speed
	max_life = p_max_life
	accelerate_with_life = p_accel

func _process(delta: float):
	life += delta
	if is_instance_valid(target_node):
		var dest = Vector3(target_node.global_position.x * s_factor, 0.5, target_node.global_position.y * s_factor * corr_z)
		var spd_mult = (1.0 + (life / max_life)) if accelerate_with_life else 1.0
		global_position = global_position.lerp(dest, delta * speed * spd_mult)
		if global_position.distance_to(dest) > 0.02:
			look_at(dest, Vector3.UP)
		var dist = global_position.distance_to(dest)
		if dist < 0.45:
			scale = scale.lerp(Vector3.ZERO, delta * 20.0)
			if dist < 0.08:
				queue_free()
				return
	if life >= max_life:
		queue_free()
		return

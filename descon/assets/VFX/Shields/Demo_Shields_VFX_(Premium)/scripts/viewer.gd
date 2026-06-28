extends Node3D

const RAY_LENGTH = 1000.0

@onready var cam:Camera3D = $Camera3D
@onready var ray_cast:RayCast3D = $Camera3D/RayCast3D

var projectile:Resource = load("res://scenes/projectile.tscn")
var projectile_inst:Node3D
var target_pos:Vector3


#  Being able to move the camera and click
func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(_event: InputEvent) -> void:
	
	if Input.is_action_just_pressed("Esc"):
		get_tree().quit()
	
	if _event is InputEventMouseMotion:
		self.rotate_y(-_event.relative.x * 0.002)
		cam.rotate_x(-_event.relative.y * 0.002)
		
	
	if Input.is_action_just_pressed("key_shoot"):
		_shoot_out()


#  See where the camera is aiming before shoot the projectile
func _physics_process(_delta)->void:
	var space_state:PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var mousepos:Vector2 = get_viewport().get_mouse_position()

	var origin:Vector3 = cam.project_ray_origin(mousepos)
	var end:Vector3 = origin + cam.project_ray_normal(mousepos) * RAY_LENGTH
	var query:PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, end)
	query.collide_with_areas = true

	var result:Dictionary = space_state.intersect_ray(query)
	
	if result.size()>0:
		target_pos = result.position
		ray_cast.look_at(target_pos)
	else:
		ray_cast.rotation = Vector3(0.0,0.0,0.0)


#  A Special Function to Shoot the Projectile
func _shoot_out()->void:
	projectile_inst = projectile.instantiate()
	projectile_inst.position = ray_cast.global_position
	projectile_inst.transform.basis = ray_cast.global_transform.basis
	get_parent().add_child(projectile_inst)

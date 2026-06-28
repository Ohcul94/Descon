extends Node3D



@export var SPEED: float = 40



@onready var ray_cast:RayCast3D = $RayCast3D

var m_hit:Node3D
var projectile:Node3D
var character:Node3D




# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(_delta: float) -> void:
	
	if (projectile != null):
		
		if GameManager.get_single_projectile():
			#moving the projectile
			self.position += transform.basis * Vector3(0.0,0.0,-SPEED) * _delta 

			#detect collision
		if ray_cast.is_colliding():
			DeployProjectile()




# if the projectile didn't hit anything, destroy it after 3 sec
func _on_timer_timeout() -> void:
	DeployProjectile()


func DeployProjectile()->void:
	
	#Hide FireBall and stop
	print(" -- Projectile Impacted")
	projectile.visible = false
	ray_cast.enabled = false
	SPEED = 0
	
	#VFX Hit impact creation
	m_hit = GameManager.hit[GameManager.get_vfx_number()].instantiate()
	get_tree().root.get_child(1).add_child(m_hit)
	
	m_hit.global_position = self.global_position
	print("Created Hit VFX")
	
	#Free memory
	projectile.queue_free()
	print("Destroyed Fire Ball VFX")
	
	await m_hit.find_child("AnimationPlayer").animation_finished
	m_hit.queue_free()
	print("Destroyed Hit VFX")
	
	self.queue_free()
	print("Destroyed Projectiler")

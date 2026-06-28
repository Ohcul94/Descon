extends Node3D


var SPEED: float = 20

@onready var mesh:MeshInstance3D = $MeshInstance3D
@onready var ray_cast:RayCast3D = $RayCast3D
@onready var particles:GPUParticles3D = $GPUParticles3D

# Pre-Load all the Hit VFX 
@onready var sphere_hit:Array[PackedScene] = [
	preload("res://VFX/scenes/VFX_Hit_sphere_green.tscn"),
	preload("res://VFX/scenes/VFX_Hit_sphere_bbasic.tscn"),
	preload("res://VFX/scenes/VFX_Hit_blue_wild.tscn"),
	preload("res://VFX/scenes/VFX_Hit_sphere_demon.tscn"),
	preload("res://VFX/scenes/VFX_Hit_Hex_Sphere.tscn")
	]


func _physics_process(_delta: float) -> void:
	
	# MOVE the bullet really fast
	self.position += transform.basis * Vector3(0.0,0.0,-SPEED) * _delta 
	
	#check if the bullet is colliding
	if ray_cast.is_colliding():
		mesh.visible = false
		ray_cast.enabled = false
		SPEED = 0
		$Hit_VFX/AnimationPlayer.play("hit_animation")
		
		#check if its colliding with the shield
		if ray_cast.get_collider().name.contains("shield_collider"):
			
			#Create the hit shield impact
			var sphere_hit_inst:GPUParticles3D = sphere_hit[SceneManager.number].instantiate();
			sphere_hit_inst.emitting = true;
			get_parent().get_node("Sphere_Spammer").add_child(sphere_hit_inst);
			
			
			#Rotate the shield towards the bullet impact point
			var rotator:Vector3 = (self.global_position - sphere_hit_inst.global_position).normalized();
			var cross_p:Vector3 = Vector3.UP.cross(rotator).normalized();
			var angle:float = acos(rotator.dot(Vector3.UP));

			sphere_hit_inst.rotate(cross_p,angle);

			#Wait and destroy the bullet and hit effect
			await $Hit_VFX/AnimationPlayer.animation_finished
			if sphere_hit_inst.emitting == true:
				await sphere_hit_inst.finished
				sphere_hit_inst.queue_free();
			queue_free();



func _on_timer_timeout() -> void:
	queue_free()

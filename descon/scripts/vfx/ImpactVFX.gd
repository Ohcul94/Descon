extends Node2D

func _ready():
	# Crear partículas programáticamente si no hay escena
	var particles = GPUParticles2D.new()
	add_child(particles)
	
	var mat = ParticleProcessMaterial.new()
	mat.spread = 180.0
	mat.initial_velocity_min = 100.0
	mat.initial_velocity_max = 200.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 2.0
	mat.scale_max = 4.0
	mat.color = Color(1, 0.8, 0.2) # Oro/Chispas
	
	particles.process_material = mat
	particles.amount = 15
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.emitting = true
	
	# Autodestrucción
	await get_tree().create_timer(1.0).timeout
	queue_free()

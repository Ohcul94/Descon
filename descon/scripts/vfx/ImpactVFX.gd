extends Node2D

# v312.0: Caché estática de ParticleProcessMaterial para evitar su instanciación en caliente
static var _proc_material: ParticleProcessMaterial = null

func _ready():
	# Crear partículas programáticamente si no hay escena
	var particles = GPUParticles2D.new()
	add_child(particles)
	
	if not _proc_material:
		_proc_material = ParticleProcessMaterial.new()
		_proc_material.spread = 180.0
		_proc_material.initial_velocity_min = 100.0
		_proc_material.initial_velocity_max = 200.0
		_proc_material.gravity = Vector3.ZERO
		_proc_material.scale_min = 2.0
		_proc_material.scale_max = 4.0
		_proc_material.color = Color(1, 0.8, 0.2) # Oro/Chispas
		
	particles.process_material = _proc_material
	particles.amount = 15
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.emitting = true
	
	# Autodestrucción
	await get_tree().create_timer(1.0).timeout
	queue_free()

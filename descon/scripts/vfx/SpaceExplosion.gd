# SpaceExplosion.gd
# Explosión de Alta Fidelidad con Fuego Orgánico Procedural
# Usa Shaders de Ruido para evitar el look "gris plano"

extends Node3D

const FIRE_SHADER = preload("res://shaders/vfx/fire_explosion.gdshader")


func _ready():
	# 1. EL NÚCLEO (The Core - Incandescencia pura)
	_create_core_explosion()
	
	# 2. CHISPAS DE COMBUSTIÓN (Ember)
	_create_embers()
	
	# 3. FRAGMENTOS METÁLICOS (Debris)
	_create_debris()
	
	# 4. AUTODESTRUCCIÓN SEGURA (Evita fugas de memoria en pooling/instanciación directa)
	get_tree().create_timer(2.0).timeout.connect(queue_free)


func _create_core_explosion():
	var core = GPUParticles3D.new()
	core.amount = 8
	core.lifetime = 0.8
	core.explosiveness = 1.0
	core.one_shot = true
	
	var mat = ParticleProcessMaterial.new()
	mat.gravity = Vector3.ZERO
	mat.spread = 180.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 5.0
	mat.scale_min = 3.0
	mat.scale_max = 5.0
	core.process_material = mat
	
	var shader_mat = ShaderMaterial.new()
	shader_mat.shader = FIRE_SHADER
	core.draw_pass_1 = QuadMesh.new()

	core.draw_pass_1.material = shader_mat
	
	add_child(core)
	core.emitting = true

func _create_embers():
	var embers = GPUParticles3D.new()
	embers.amount = 40
	embers.lifetime = 1.2
	embers.explosiveness = 0.9
	embers.one_shot = true
	
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.5
	mat.direction = Vector3(1, 1, 1)
	mat.spread = 180.0
	mat.gravity = Vector3(0, 0, 0)
	mat.initial_velocity_min = 2.5
	mat.initial_velocity_max = 5.0
	mat.damping_min = 2.0
	mat.damping_max = 4.0
	mat.scale_min = 0.05
	mat.scale_max = 0.15
	
	# Desvanecimiento progresivo al final del tiempo de vida
	var grad = Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var grad_tex = GradientTexture1D.new()
	grad_tex.gradient = grad
	mat.color_ramp = grad_tex
	
	embers.process_material = mat
	
	var m_mat = StandardMaterial3D.new()
	m_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	m_mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	m_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_mat.vertex_color_use_as_albedo = true
	m_mat.albedo_color = Color(2.0, 1.2, 0.4) # Brillo HDR Naranja
	
	embers.draw_pass_1 = SphereMesh.new()
	embers.draw_pass_1.material = m_mat
	
	add_child(embers)
	embers.emitting = true

func _create_debris():
	var debris = GPUParticles3D.new()
	debris.amount = 12
	debris.lifetime = 1.5
	debris.explosiveness = 1.0
	debris.one_shot = true
	
	var mat = ParticleProcessMaterial.new()
	mat.direction = Vector3(1, 1, 1)
	mat.spread = 180.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 6.0
	mat.damping_min = 3.0
	mat.damping_max = 5.0
	mat.scale_min = 0.1
	mat.scale_max = 0.4
	
	# Desvanecimiento progresivo de los fragmentos metálicos
	var grad = Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var grad_tex = GradientTexture1D.new()
	grad_tex.gradient = grad
	mat.color_ramp = grad_tex
	
	debris.process_material = mat
	
	var m_mat = StandardMaterial3D.new()
	m_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_mat.vertex_color_use_as_albedo = true
	m_mat.albedo_color = Color(0.1, 0.1, 0.1)
	m_mat.metallic = 1.0
	
	debris.draw_pass_1 = BoxMesh.new()
	debris.draw_pass_1.material = m_mat
	
	add_child(debris)
	debris.emitting = true

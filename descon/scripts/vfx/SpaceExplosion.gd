# SpaceExplosion.gd
# Explosión de Alta Fidelidad con Fuego Orgánico Procedural
# Usa Shaders de Ruido para evitar el look "gris plano"

extends Node3D

const FIRE_SHADER = preload("res://shaders/vfx/fire_explosion.gdshader")

# v312.0: Caché estática de recursos para evitar sobrecarga del recolector de basura
# e instanciación costosa de texturas, materiales y mallas en caliente durante el juego.
static var _core_proc_material: ParticleProcessMaterial = null
static var _core_shader_material: ShaderMaterial = null
static var _core_mesh: QuadMesh = null

static var _embers_proc_material: ParticleProcessMaterial = null
static var _embers_material: StandardMaterial3D = null
static var _embers_mesh: SphereMesh = null

static var _debris_proc_material: ParticleProcessMaterial = null
static var _debris_material: StandardMaterial3D = null
static var _debris_mesh: BoxMesh = null

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
	
	if not _core_proc_material:
		_core_proc_material = ParticleProcessMaterial.new()
		_core_proc_material.gravity = Vector3.ZERO
		_core_proc_material.spread = 180.0
		_core_proc_material.initial_velocity_min = 2.0
		_core_proc_material.initial_velocity_max = 5.0
		_core_proc_material.scale_min = 3.0
		_core_proc_material.scale_max = 5.0
	core.process_material = _core_proc_material
	
	if not _core_shader_material:
		_core_shader_material = ShaderMaterial.new()
		_core_shader_material.shader = FIRE_SHADER
		
	if not _core_mesh:
		_core_mesh = QuadMesh.new()
		_core_mesh.material = _core_shader_material
	core.draw_pass_1 = _core_mesh
	
	add_child(core)
	core.emitting = true

func _create_embers():
	var embers = GPUParticles3D.new()
	embers.amount = 40
	embers.lifetime = 1.2
	embers.explosiveness = 0.9
	embers.one_shot = true
	
	if not _embers_proc_material:
		_embers_proc_material = ParticleProcessMaterial.new()
		_embers_proc_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		_embers_proc_material.emission_sphere_radius = 0.5
		_embers_proc_material.direction = Vector3(1, 1, 1)
		_embers_proc_material.spread = 180.0
		_embers_proc_material.gravity = Vector3(0, 0, 0)
		_embers_proc_material.initial_velocity_min = 2.5
		_embers_proc_material.initial_velocity_max = 5.0
		_embers_proc_material.damping_min = 2.0
		_embers_proc_material.damping_max = 4.0
		_embers_proc_material.scale_min = 0.05
		_embers_proc_material.scale_max = 0.15
		
		# Desvanecimiento progresivo al final del tiempo de vida
		var grad = Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 1))
		grad.set_color(1, Color(1, 1, 1, 0))
		var grad_tex = GradientTexture1D.new()
		grad_tex.gradient = grad
		_embers_proc_material.color_ramp = grad_tex
	embers.process_material = _embers_proc_material
	
	if not _embers_material:
		_embers_material = StandardMaterial3D.new()
		_embers_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		_embers_material.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
		_embers_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_embers_material.vertex_color_use_as_albedo = true
		_embers_material.albedo_color = Color(2.0, 1.2, 0.4) # Brillo HDR Naranja
		
	if not _embers_mesh:
		_embers_mesh = SphereMesh.new()
		_embers_mesh.material = _embers_material
	embers.draw_pass_1 = _embers_mesh
	
	add_child(embers)
	embers.emitting = true

func _create_debris():
	var debris = GPUParticles3D.new()
	debris.amount = 12
	debris.lifetime = 1.5
	debris.explosiveness = 1.0
	debris.one_shot = true
	
	if not _debris_proc_material:
		_debris_proc_material = ParticleProcessMaterial.new()
		_debris_proc_material.direction = Vector3(1, 1, 1)
		_debris_proc_material.spread = 180.0
		_debris_proc_material.initial_velocity_min = 3.0
		_debris_proc_material.initial_velocity_max = 6.0
		_debris_proc_material.damping_min = 3.0
		_debris_proc_material.damping_max = 5.0
		_debris_proc_material.scale_min = 0.1
		_debris_proc_material.scale_max = 0.4
		
		# Desvanecimiento progresivo de los fragmentos metálicos
		var grad = Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 1))
		grad.set_color(1, Color(1, 1, 1, 0))
		var grad_tex = GradientTexture1D.new()
		grad_tex.gradient = grad
		_debris_proc_material.color_ramp = grad_tex
	debris.process_material = _debris_proc_material
	
	if not _debris_material:
		_debris_material = StandardMaterial3D.new()
		_debris_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_debris_material.vertex_color_use_as_albedo = true
		_debris_material.albedo_color = Color(0.1, 0.1, 0.1)
		_debris_material.metallic = 1.0
		
	if not _debris_mesh:
		_debris_mesh = BoxMesh.new()
		_debris_mesh.material = _debris_material
	debris.draw_pass_1 = _debris_mesh
	
	add_child(debris)
	debris.emitting = true

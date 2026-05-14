# SpaceExplosion.gd
# Explosión de Alta Fidelidad con Fuego Orgánico Procedural
# Usa Shaders de Ruido para evitar el look "gris plano"

extends Node3D

func _ready():
	# 1. EL NÚCLEO (The Core - Incandescencia pura)
	_create_core_explosion()
	
	# 2. CHISPAS DE COMBUSTIÓN (Ember)
	_create_embers()
	
	# 3. FRAGMENTOS METÁLICOS (Debris)
	_create_debris()

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
	shader_mat.shader = _get_fire_shader()
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
	mat.initial_velocity_min = 8.0
	mat.initial_velocity_max = 15.0
	mat.damping_min = 5.0
	mat.damping_max = 10.0
	mat.scale_min = 0.05
	mat.scale_max = 0.15
	embers.process_material = mat
	
	var m_mat = StandardMaterial3D.new()
	m_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	m_mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
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
	mat.initial_velocity_min = 10.0
	mat.initial_velocity_max = 25.0
	mat.scale_min = 0.1
	mat.scale_max = 0.4
	debris.process_material = mat
	
	var m_mat = StandardMaterial3D.new()
	m_mat.albedo_color = Color(0.1, 0.1, 0.1)
	m_mat.metallic = 1.0
	debris.draw_pass_1 = BoxMesh.new()
	debris.draw_pass_1.material = m_mat
	
	add_child(debris)
	debris.emitting = true

func _get_fire_shader() -> Shader:
	var shader = Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_test_disabled;

const vec3 COLOR_HOT = vec3(4.0, 3.0, 1.0);
const vec3 COLOR_MID = vec3(2.0, 0.5, 0.0);
const vec3 COLOR_COLD = vec3(0.1, 0.05, 0.02);

varying float lifetime_percent;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

void vertex() {
	lifetime_percent = INSTANCE_CUSTOM.y;
	
	// BILLBOARD MANUAL (GLES3 Compatible)
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 uv_noise = UV * 3.0 + vec2(0.0, -TIME * 0.5);
	float n = noise(uv_noise);
	
	float d = distance(UV, vec2(0.5));
	float mask = smoothstep(0.5, 0.1, d + n * 0.2);
	
	if (mask < 0.1) discard;

	vec3 final_color;
	if (lifetime_percent < 0.2) {
		final_color = mix(COLOR_HOT, COLOR_MID, lifetime_percent * 5.0);
	} else {
		final_color = mix(COLOR_MID, COLOR_COLD, (lifetime_percent - 0.2) * 1.25);
	}
	
	final_color *= (0.8 + n * 0.4);
	
	ALPHA = mask * (1.0 - smoothstep(0.7, 1.0, lifetime_percent));
	ALBEDO = final_color;
}
"""
	return shader

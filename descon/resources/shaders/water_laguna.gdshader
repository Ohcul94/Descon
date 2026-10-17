shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

// Agua de laguna / pantano - estilo artistico turbio, barato para GL Compatibility
// TRANSLUCIDA + forma irregular redondeada por mascara (el plano cuadrado se recorta solo).
// Todo procedural, sin texturas externas. 3 lagunas = 3 draw calls, sin refraccion.

uniform vec4 deep_color : source_color = vec4(0.02, 0.07, 0.045, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.10, 0.19, 0.07, 1.0);
uniform vec4 algae_color : source_color = vec4(0.20, 0.30, 0.08, 1.0);
uniform vec4 sky_tint : source_color = vec4(0.65, 0.70, 0.68, 1.0);
uniform vec4 foam_color : source_color = vec4(0.45, 0.52, 0.35, 1.0);

uniform float wave_height : hint_range(0.0, 0.5) = 0.12;
uniform float wave_speed : hint_range(0.0, 4.0) = 1.2;
uniform float wave_scale : hint_range(0.1, 4.0) = 0.8;

uniform float algae_amount : hint_range(0.0, 1.0) = 0.55;
uniform float algae_scale : hint_range(0.5, 20.0) = 3.0;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.3;
uniform float fresnel_power : hint_range(0.5, 8.0) = 3.0;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.28;
uniform float specular_val : hint_range(0.0, 1.0) = 0.55;

uniform float base_alpha : hint_range(0.0, 1.0) = 0.78;
uniform float shape_irregularity : hint_range(0.0, 1.2) = 0.55;
// En false: plano completo para rellenar por altura (oasis). En true: charco redondo.
uniform bool use_rounded_shape = true;

varying vec2 v_world_xz;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// 2 octavas para maximo rendimiento en GLES3 / Compatibility
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 2; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	// Oleaje leve: 2 senos cruzados + chop corto, todo en GPU
	v_world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	float t = TIME * wave_speed;
	vec3 p = VERTEX;
	float w = sin(p.x * wave_scale * 0.8 + t) * cos(p.z * wave_scale * 0.7 + t * 0.8);
	w += sin((p.x + p.z) * wave_scale * 0.35 + t * 0.6) * 0.5;
	w += sin(p.z * wave_scale * 2.2 - t * 1.4) * cos(p.x * wave_scale * 1.9 + t * 1.1) * 0.18;
	VERTEX.y += w * wave_height;
}

void fragment() {
	// Forma: redondeada irregular (charco) o plano completo (relleno por altura).
	float shape = 1.0;
	float foam_ring = 0.0;
	float d = 0.0;
	if (use_rounded_shape) {
		float edge_n = fbm(v_world_xz * 0.045);
		d = length(UV - vec2(0.5)) * 2.0;
		d += (edge_n - 0.5) * shape_irregularity * 2.0;
		shape = 1.0 - smoothstep(0.68, 0.95, d);
		if (shape < 0.02) discard;
		foam_ring = smoothstep(0.35, 0.68, d) * shape;
	}

	// Nata verde estancada que deriva lento (estilo pantano)
	vec2 big_uv = UV * algae_scale + vec2(TIME * 0.02, TIME * 0.012);
	float big_n = fbm(big_uv * 3.0);
	float scum_mask = smoothstep(1.0 - algae_amount - 0.25, 1.0 - algae_amount + 0.25, big_n);

	// Ripple fino animado para romper el reflejo
	vec2 rip_uv = UV * 40.0;
	float r1 = noise(rip_uv + vec2(TIME * 0.6, TIME * 0.3));
	float r2 = noise(rip_uv * 1.7 - vec2(TIME * 0.4, TIME * 0.5));
	float ripple = (r1 + r2 - 1.0) * ripple_strength;

	// Perturbar normal para specular animado (barato, sin normal map)
	NORMAL = normalize(NORMAL + vec3(ripple, 0.0, ripple * 0.7));

	// Fresnel para tinte de cielo en angulos rasantes
	float fres = pow(clamp(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), fresnel_power);

	// Color base: profundo -> orilla + nata + espuma de borde
	vec3 col = mix(deep_color.rgb, shallow_color.rgb, clamp(big_n * 0.7 + ripple * 0.5 + 0.15, 0.0, 1.0));
	col = mix(col, algae_color.rgb, scum_mask * 0.75);
	col = mix(col, foam_color.rgb, foam_ring * 0.35);
	col = mix(col, sky_tint.rgb, fres * 0.45);

	ALBEDO = col;
	ROUGHNESS = roughness_val;
	SPECULAR = specular_val;
	METALLIC = 0.08;
	// Centro mas transparente (se ve el fondo), borde y nata mas opacos
	float alpha = base_alpha * shape;
	alpha = mix(alpha * 0.62, alpha, clamp(fres * 0.8 + scum_mask * 0.5 + foam_ring * 0.6, 0.0, 1.0));
	ALPHA = clamp(alpha, 0.0, 1.0);
}

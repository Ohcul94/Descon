shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, diffuse_lambert, unshaded, shadows_disabled, fog_disabled;

// Shader de Distorsión para escudos 3D - compatible con SubViewport transparente 2.5D
// NOTA: se eliminó hint_screen_texture ya que no es compatible con viewports transparentes.
// En su lugar se usa un efecto de borde Fresnel + ruido animado para simular refracción.

uniform float Size_Sphere = 0.0;
uniform vec2 details_scale = vec2(1.0, 1.0);
uniform vec2 details_velocity = vec2(0.0, 0.0);
uniform sampler2D Normal_Distortion_Texture : hint_normal, filter_linear, repeat_enable;
uniform float RefStrenght = 0.02;
uniform vec2 Disolver_Scale = vec2(1.0, 1.0);
uniform sampler2D Disolver_Noise_Line : source_color, filter_linear, repeat_enable;
uniform float Line_Distortion_Divider = 5.0;
uniform sampler2D Gradient_Disappear : source_color, filter_linear, repeat_disable;
uniform float Gradient_Line : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	vec3 n_out2p0 = VERTEX;
	vec3 n_out3p0 = NORMAL;
	float n_out6p0 = Size_Sphere;
	vec3 n_out5p0 = n_out3p0 * vec3(n_out6p0);
	vec3 n_out4p0 = n_out2p0 + n_out5p0;
	VERTEX = n_out4p0;
}

void fragment() {
	// --- Ruido animado para distorsión visual ---
	vec2 n_out10p0 = details_scale;
	vec2 n_out9p0 = (UV - vec2(0.0)) * n_out10p0 + vec2(0.0);
	vec2 n_out27p0 = details_velocity;
	float n_out29p0 = TIME;
	vec2 n_out28p0 = n_out27p0 * vec2(n_out29p0);
	vec2 n_out26p0 = n_out28p0 * vec2(1.0, 1.0) + n_out9p0;

	vec4 n_out21p0 = texture(Normal_Distortion_Texture, n_out26p0);
	float n_out21p1 = n_out21p0.r;
	float n_out21p2 = n_out21p0.g;

	vec2 n_out17p0 = vec2(n_out21p1, n_out21p2);
	vec2 n_out8p0 = (n_out17p0 * vec2(2.0, 2.0)) + vec2(-1.0, -1.0);
	float n_out7p0 = RefStrenght;
	vec2 n_out6p0 = n_out8p0 * vec2(n_out7p0);

	// --- Disolver por ruido + Gradient_Line ---
	vec2 n_out83p0 = Disolver_Scale;
	vec2 n_out82p0 = (UV - vec2(0.0)) * n_out83p0 + vec2(0.0);
	vec4 n_out77p0 = texture(Disolver_Noise_Line, n_out82p0);
	float n_out77p1 = n_out77p0.r;

	float n_out91p0 = Line_Distortion_Divider;
	float n_out80p0 = n_out77p1 / n_out91p0;

	vec2 n_out79p0 = UV + vec2(n_out80p0);
	vec4 n_out86p0 = texture(Gradient_Disappear, n_out79p0);
	float n_out86p1 = n_out86p0.r;

	float n_out56p0 = Gradient_Line;
	float n_out57p0 = step(n_out86p1, n_out56p0);

	// --- Efecto Fresnel para el borde luminoso (reemplaza refracción de pantalla) ---
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);

	// Color de distorsión: brillante semi-transparente basado en ruido y fresnel
	float distort_intensity = clamp(n_out21p2 * 1.5 + fresnel * 0.8, 0.0, 1.0);
	ALBEDO = vec3(distort_intensity);
	ALPHA = distort_intensity * n_out57p0 * 0.45;
}

shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, unshaded, shadows_disabled, fog_disabled;

// Shader de escudo con color+distorsión - compatible con SubViewport transparente 2.5D
// NOTA: eliminado hint_screen_texture (no funciona en viewports transparentes).
// La refracción fue reemplazada por un efecto de distorsión interna con Fresnel.

uniform float Gradient_Line : hint_range(0, 1) = 0;
uniform float Line_Baias = 0.01999999955297;
uniform vec2 Disolver_Scale = vec2(1.0, 1.0);
uniform sampler2D Disolver_Noise_Line : source_color, filter_linear, repeat_enable;
uniform float Line_Distortion_Divider = 5.0;
uniform sampler2D Gradient_Disappear : source_color, filter_linear, repeat_disable;
uniform sampler2D Line_Gradient : source_color, filter_linear, repeat_disable;
uniform vec2 Details_Scale = vec2(1.0, 1.0);
uniform vec2 Velocity = vec2(0.0, 0.0);
uniform sampler2D Normal_Distortion_Texture : hint_normal, filter_linear, repeat_enable;
uniform float RefStrenght = 0.02;
uniform vec2 Overlay_Scale = vec2(1.0, 1.0);
uniform vec2 Overlay_Velocity = vec2(0.0, 0.0);
uniform sampler2D Overlay_Texture : source_color, hint_default_black, filter_linear;
uniform float Overlay_Power = 2.0;
uniform float Color_Details = 1.0;
uniform float Proximity_light = 0.5;
uniform float Proximity_Power = 0.5;
uniform bool Fresnel_invert;
uniform float fresnel_power = 0.683;
uniform float darkness = 0.0;
uniform sampler2D Gradient_1D_Color : source_color, filter_linear;

void fragment() {
	float n_out56p0 = Gradient_Line;
	float n_out61p0 = Line_Baias;
	float n_out59p0 = n_out56p0 - n_out61p0;

	vec2 n_out83p0 = Disolver_Scale;
	vec2 n_out82p0 = (UV - vec2(0.0)) * n_out83p0 + vec2(0.0);
	vec4 n_out77p0 = texture(Disolver_Noise_Line, n_out82p0);
	float n_out77p1 = n_out77p0.r;

	float n_out91p0 = Line_Distortion_Divider;
	float n_out80p0 = n_out77p1 / n_out91p0;
	vec2 n_out79p0 = UV + vec2(n_out80p0);

	vec4 n_out86p0 = texture(Gradient_Disappear, n_out79p0);
	float n_out86p1 = n_out86p0.r;

	float n_out84p0 = smoothstep(n_out59p0, 0.80000, n_out86p1);
	vec4 n_out90p0 = texture(Line_Gradient, vec2(n_out84p0));

	// Normal distortion (detalles animados del escudo)
	vec2 n_out10p0 = Details_Scale;
	vec2 n_out9p0 = (UV - vec2(0.0)) * n_out10p0 + vec2(0.0);
	vec2 n_out27p0 = Velocity;
	float n_out29p0 = TIME;
	vec2 n_out28p0 = n_out27p0 * vec2(n_out29p0);
	vec2 n_out26p0 = n_out28p0 * vec2(1.0, 1.0) + n_out9p0;

	vec4 n_out21p0 = texture(Normal_Distortion_Texture, n_out26p0);
	float n_out21p1 = n_out21p0.r;
	float n_out21p2 = n_out21p0.g;

	// Overlay animado
	vec2 n_out43p0 = Overlay_Scale;
	vec2 n_out42p0 = (UV - vec2(0.0)) * n_out43p0 + vec2(0.0);
	vec2 n_out44p0 = Overlay_Velocity;
	float n_out47p0 = TIME;
	vec2 n_out45p0 = n_out44p0 * vec2(n_out47p0);
	vec2 n_out46p0 = n_out45p0 * vec2(1.0, 1.0) + n_out42p0;

	vec4 n_out41p0 = texture(Overlay_Texture, n_out46p0);
	float n_out41p1 = n_out41p0.r;

	float n_out49p0 = Overlay_Power;
	float n_out48p0 = pow(n_out41p1, n_out49p0);

	float n_out24p0 = Color_Details;
	float n_out23p0 = pow(n_out21p2, n_out24p0);

	// Fresnel (reemplaza ProximityFade y screen_texture)
	float n_out11p0 = Fresnel_invert
		? (pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power))
		: (pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power));

	float proximity_faked = 1.0; // no hay depth buffer en viewport transparente
	float n_out35p0 = pow(proximity_faked, Proximity_Power);
	float n_out33p0 = 1.0 - n_out35p0;

	float n_out32p0 = n_out33p0 + n_out11p0;
	float n_out22p0 = n_out23p0 * n_out32p0;
	float n_out39p0 = n_out48p0 + n_out22p0;
	float n_out25p0 = clamp(n_out39p0, 0.0, 1.0);

	float n_out13p0 = n_out25p0 - darkness;

	vec4 n_out38p0 = texture(Gradient_1D_Color, vec2(n_out13p0));

	// NOTA: el screen_texture original hacía refracción; aquí usamos el color del gradiente directamente
	// como base del ALBEDO para preservar el efecto visual de color del escudo.
	vec3 n_out12p0 = vec3(n_out38p0.xyz); // antes era screen_color + gradiente
	vec3 n_out63p0 = vec3(n_out90p0.xyz) + n_out12p0;

	float n_out57p0 = step(n_out56p0, n_out86p1);

	ALBEDO = n_out63p0;
	ALPHA = n_out38p0.a * n_out57p0;
}

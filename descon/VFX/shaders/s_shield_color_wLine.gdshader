shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_schlick_ggx, unshaded, shadows_disabled, fog_disabled;

uniform float Size_Sphere = 0;
uniform float Gradient_Line : hint_range(0, 0.83999997377396) = 0;
uniform float Line_Baias = 0.01999999955297;
uniform float SmoothStep : hint_range(0, 1) = 0.80000001192093;
uniform vec2 Disolver_Scale = vec2(1.000000, 1.000000);
uniform sampler2D Disolver_Noise_Line : source_color, filter_linear, repeat_enable;
uniform float Line_Distortion_Divider = 5;
uniform sampler2D Gradient_Disappear : source_color, filter_linear, repeat_disable;
uniform sampler2D Line_Gradient : source_color, filter_linear, repeat_disable;
uniform vec2 Overlay_Scale = vec2(1.000000, 1.000000);
uniform vec2 Overlay_Velocity = vec2(0.000000, 0.000000);
uniform sampler2D Overlay_Texture : source_color, hint_default_black, filter_linear;
uniform float Overlay_Power = 2;
uniform float Proximity_light = 0.5;
uniform float Proximity_Power = 0.5;
uniform bool Fresnel_invert;
uniform float fresnel_power = 0.68300002813339;
uniform float darkness = 0;
uniform sampler2D Gradient_1D_Color : source_color, filter_linear;

void vertex() {
	vec3 n_out2p0 = VERTEX;
	vec3 n_out4p0 = NORMAL;
	float n_out6p0 = Size_Sphere;
	vec3 n_out5p0 = n_out4p0 * vec3(n_out6p0);
	vec3 n_out3p0 = n_out2p0 + n_out5p0;
	VERTEX = n_out3p0;
}

void fragment() {
	float n_out56p0 = Gradient_Line;
	float n_out61p0 = Line_Baias;
	float n_out59p0 = n_out56p0 - n_out61p0;
	float n_out95p0 = SmoothStep;
	vec2 n_out78p0 = UV;
	vec2 n_out83p0 = Disolver_Scale;
	vec2 n_out82p0 = (UV - vec2(0.0)) * n_out83p0 + vec2(0.0);

	vec4 n_out77p0 = texture(Disolver_Noise_Line, n_out82p0);
	float n_out77p1 = n_out77p0.r;

	float n_out91p0 = Line_Distortion_Divider;
	float n_out80p0 = n_out77p1 / n_out91p0;
	vec2 n_out79p0 = n_out78p0 + vec2(n_out80p0);

	vec4 n_out86p0 = texture(Gradient_Disappear, n_out79p0);
	float n_out86p1 = n_out86p0.r;

	float n_out94p0 = pow(n_out86p1, 0.59000);
	float n_out84p0 = smoothstep(n_out59p0, n_out95p0, n_out94p0);

	vec4 n_out90p0 = texture(Line_Gradient, vec2(n_out84p0));

	vec2 n_out50p0 = UV;
	vec2 n_out43p0 = Overlay_Scale;
	vec2 n_out42p0 = (n_out50p0 - vec2(0.0)) * n_out43p0 + vec2(0.0);
	vec2 n_out44p0 = Overlay_Velocity;
	float n_out47p0 = TIME;
	vec2 n_out45p0 = n_out44p0 * vec2(n_out47p0);
	vec2 n_out46p0 = n_out45p0 * vec2(1.00000, 1.00000) + n_out42p0;

	vec4 n_out41p0 = texture(Overlay_Texture, n_out46p0);
	float n_out41p1 = n_out41p0.r;

	float n_out49p0 = Overlay_Power;
	float n_out48p0 = pow(n_out41p1, n_out49p0);

	// Removido ProximityFade para evitar fallos en Viewports transparentes 2.5D
	float n_out31p0 = 1.0; 

	float n_out36p0 = Proximity_Power;
	float n_out35p0 = pow(n_out31p0, n_out36p0);
	float n_out33p0 = 1.0 - n_out35p0;

	bool n_out19p0 = Fresnel_invert;
	float n_out14p0 = fresnel_power;
	float n_out11p0 = n_out19p0 ? (pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), n_out14p0)) : (pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), n_out14p0));

	float n_out32p0 = n_out33p0 + n_out11p0;
	float n_out39p0 = n_out48p0 + n_out32p0;
	float n_out25p0 = clamp(n_out39p0, 0.0, 1.0);

	float n_out15p0 = darkness;
	float n_out13p0 = n_out25p0 - n_out15p0;
	float n_out97p0 = n_out84p0 + n_out13p0;

	vec4 n_out38p0 = texture(Gradient_1D_Color, vec2(n_out97p0));
	float n_out38p4 = n_out38p0.a;

	vec3 n_out63p0 = vec3(n_out90p0.xyz) + vec3(n_out38p0.xyz);
	float n_out57p0 = step(n_out86p1, n_out56p0);
	float n_out96p0 = n_out38p4 * n_out57p0;

	ALBEDO = n_out63p0;
	ALPHA = n_out96p0;
}

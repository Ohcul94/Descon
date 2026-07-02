shader_type spatial;
render_mode blend_add, cull_disabled, unshaded;

uniform sampler2D u_noise_tex : source_color;
uniform vec4 u_color_a : source_color = vec4(0.15, 0.02, 0.25, 0.5);
uniform vec4 u_color_b : source_color = vec4(0.0, 0.3, 0.5, 0.25);
uniform vec4 u_color_c : source_color = vec4(0.5, 0.05, 0.3, 0.35);
uniform float u_speed : hint_range(0.0, 2.0) = 0.25;
uniform float u_alpha_scale : hint_range(0.0, 2.0) = 0.8;

void vertex() {
	float ring_uv = UV.x;
	float width_uv = UV.y;
	vec3 pos = VERTEX;
	pos.y += sin(ring_uv * 20.0 + TIME * 0.5) * 0.2;
	pos.y += sin(ring_uv * 7.0 + TIME * 1.2) * 0.15;
	pos.z += sin(ring_uv * 13.0 + TIME * 0.8) * 0.15;
	pos.z += cos(ring_uv * 9.0 + TIME * 1.0) * 0.1;
	VERTEX = pos;
}

void fragment() {
	float ring_uv = UV.x;
	float width_uv = UV.y;
	float time = TIME * u_speed;

	vec2 uv_a = vec2(ring_uv * 3.0 + time * 0.08, width_uv * 2.0 + time * 0.04);
	vec2 uv_b = vec2(ring_uv * 2.5 - time * 0.06, width_uv * 3.0 + time * 0.07);
	vec2 uv_c = vec2(ring_uv * 4.0 + time * 0.12 + 1.5, width_uv + time * 0.02);

	float noise_a = texture(u_noise_tex, uv_a).r;
	float noise_b = texture(u_noise_tex, uv_b).g;
	float noise_c = texture(u_noise_tex, uv_c).b;

	vec3 nebula = mix(u_color_a.rgb, u_color_b.rgb, noise_a);
	nebula = mix(nebula, u_color_c.rgb, noise_b * 0.6 + 0.2);
	nebula += vec3(0.1, 0.02, 0.15) * noise_c * 0.3;

	float edge_fade = 1.0 - abs(width_uv - 0.5) * 2.0;
	edge_fade = smoothstep(0.0, 1.0, edge_fade);

	float alpha = (noise_a * 0.4 + noise_b * 0.35 + noise_c * 0.25) * u_alpha_scale * edge_fade;
	alpha = clamp(alpha, 0.0, 1.0);

	ALBEDO = nebula;
	ALPHA = alpha;
	EMISSION = nebula * 0.9;
}

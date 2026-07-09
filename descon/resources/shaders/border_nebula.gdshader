shader_type spatial;
render_mode blend_add, cull_disabled, unshaded;

uniform sampler2D u_noise_tex : source_color;
uniform vec4 u_color_a : source_color = vec4(0.12, 0.01, 0.22, 0.6);
uniform vec4 u_color_b : source_color = vec4(0.01, 0.18, 0.38, 0.35);
uniform vec4 u_color_c : source_color = vec4(0.45, 0.03, 0.28, 0.4);
uniform float u_speed : hint_range(0.0, 2.0) = 0.3;
uniform float u_alpha_scale : hint_range(0.0, 2.0) = 0.9;
uniform float u_horizon_fade : hint_range(0.0, 2.0) = 0.5;

void vertex() {
	float ring_uv = UV.x;
	float width_uv = UV.y;
	vec3 pos = VERTEX;
	pos.y += sin(ring_uv * 15.0 + TIME * 0.4) * 0.3;
	pos.y += sin(ring_uv * 6.0 + TIME * 1.0) * 0.2;
	pos.z += sin(ring_uv * 10.0 + TIME * 0.7) * 0.2;
	pos.z += cos(ring_uv * 8.0 + TIME * 0.9) * 0.15;
	pos.x += sin(ring_uv * 12.0 + TIME * 0.6) * 0.1;
	VERTEX = pos;
}

void fragment() {
	float ring_uv = UV.x;
	float width_uv = UV.y;
	float time = TIME * u_speed;

	vec2 uv_a = vec2(ring_uv * 3.0 + time * 0.06, width_uv * 2.5 + time * 0.03);
	vec2 uv_b = vec2(ring_uv * 2.2 - time * 0.05, width_uv * 3.5 + time * 0.06);
	vec2 uv_c = vec2(ring_uv * 4.5 + time * 0.10 + 1.5, width_uv * 1.5 + time * 0.02);

	float noise_a = texture(u_noise_tex, uv_a).r;
	float noise_b = texture(u_noise_tex, uv_b).g;
	float noise_c = texture(u_noise_tex, uv_c).b;

	vec3 col_a = mix(u_color_a.rgb, u_color_b.rgb, noise_a);
	vec3 nebula = mix(col_a, u_color_c.rgb, noise_b * 0.5 + 0.25);
	nebula += vec3(0.08, 0.01, 0.12) * noise_c * 0.25;

	float edge_x = 1.0 - abs(ring_uv - 0.5) * 2.0;
	edge_x = smoothstep(0.0, 1.0, edge_x);

	float horizon_fade = pow(width_uv, u_horizon_fade);

	float alpha = (noise_a * 0.35 + noise_b * 0.30 + noise_c * 0.20) * u_alpha_scale;
	alpha *= edge_x * horizon_fade;
	alpha = clamp(alpha * 0.7, 0.0, 0.85);

	ALBEDO = nebula;
	ALPHA = alpha;
	EMISSION = nebula * 0.8;
}

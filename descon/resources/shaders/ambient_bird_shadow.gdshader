shader_type spatial;
render_mode cull_disabled, unshaded, blend_mix, depth_draw_never;

// Sombra difusa suave proyectada en el suelo
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.35);
uniform float softness : hint_range(0.1, 1.0) = 0.6;
uniform float fade_alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float dist = length(uv);
	float alpha = smoothstep(1.0, 1.0 - softness, dist);
	ALBEDO = shadow_color.rgb;
	ALPHA = alpha * shadow_color.a * fade_alpha;
}

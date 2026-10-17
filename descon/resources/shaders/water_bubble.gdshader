shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4 bubble_color : source_color = vec4(0.70, 0.90, 0.88, 0.45);
uniform vec4 rim_color : source_color = vec4(0.92, 0.98, 0.96, 0.85);

void fragment() {
	float fresnel = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 2.5);
	vec3 col = mix(bubble_color.rgb, rim_color.rgb, fresnel);
	float alpha = mix(bubble_color.a, rim_color.a, fresnel);
	ALBEDO = col;
	ALPHA = alpha;
}

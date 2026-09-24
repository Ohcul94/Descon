shader_type spatial;
render_mode blend_add, depth_draw_always, cull_disabled, unshaded;

// Onda expansiva de tick — anillo que se irradia desde el centro en el suelo
uniform vec4 ring_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float thickness : hint_range(0.01, 0.3) = 0.08;
uniform float intensity : hint_range(0.0, 4.0) = 1.0;

void fragment() {
	vec2 center = UV - vec2(0.5);
	float dist = length(center) * 2.0;
	if (dist > 1.0) {
		discard;
	}

	// El anillo se expande de 0 a 1 con el progreso
	float ring_pos = progress;
	float d = abs(dist - ring_pos);
	float ring = 1.0 - smoothstep(0.0, thickness, d);

	// Cola suave detrás del anillo
	float trail = 1.0 - smoothstep(0.0, thickness * 3.0, d);
	trail *= step(dist, ring_pos + thickness);

	// Desvanecimiento general con el progreso
	float fade = 1.0 - progress;
	fade = pow(fade, 1.2);

	float alpha = (ring * 0.9 + trail * 0.35) * fade * intensity;
	vec3 col = ring_color.rgb * (1.0 + ring * 1.5);

	ALBEDO = col;
	EMISSION = col * (2.0 + ring * 2.0) * intensity;
	ALPHA = clamp(alpha, 0.0, 1.0);
}

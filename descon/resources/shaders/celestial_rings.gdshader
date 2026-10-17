shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform float u_visibility : hint_range(0.0, 1.0) = 1.0;
uniform float u_time : hint_range(0.0, 100000.0) = 0.0;

void fragment() {
	vec2 uv = (UV - 0.5) * 2.0;
	float r = length(uv);

	// Límites del anillo: radio interno 0.44, radio externo 0.96
	if (r < 0.44 || r > 0.96) {
		discard;
	}

	float theta = atan(uv.y, uv.x);

	// Rotación diferencial suave (Kepleriana continua)
	float orbit_speed = 0.012 / max(0.2, sqrt(r));
	float orbit_angle = theta + u_time * orbit_speed;

	// Bandas concéntricas ricas y continuas (Saturno-like)
	float b1 = sin(r * 160.0 + sin(orbit_angle * 12.0) * 0.4) * 0.18;
	float b2 = sin(r * 340.0) * 0.12;
	float b3 = sin(r * 720.0) * 0.06;
	float density_profile = 0.76 + b1 + b2 + b3;

	// Brecha de Cassini definida (r~0.69 a r~0.73)
	float cassini = 1.0 - smoothstep(0.68, 0.70, r) * smoothstep(0.74, 0.72, r) * 0.92;
	// Brecha secundaria de Encke (r~0.87)
	float encke = 1.0 - smoothstep(0.86, 0.87, r) * smoothstep(0.89, 0.88, r) * 0.75;
	float gap_mask = cassini * encke;

	// Desvanecimiento suave en los bordes para volumen espeso
	float r_fade = smoothstep(0.44, 0.48, r) * smoothstep(0.96, 0.92, r);

	// Paleta mineral rocosa rica y espesa (anillo planetario real)
	// Zona interior densa (blanco-crema/silicato), zona media ocre-dorada, zona exterior basalto oscuro
	vec3 col_inner = vec3(0.72, 0.65, 0.55);
	vec3 col_mid = vec3(0.58, 0.49, 0.40);
	vec3 col_outer = vec3(0.40, 0.35, 0.32);
	vec3 col_dust_sheen = vec3(0.82, 0.75, 0.65);

	vec3 ring_base = mix(col_inner, col_mid, smoothstep(0.48, 0.70, r));
	ring_base = mix(ring_base, col_outer, smoothstep(0.70, 0.92, r));

	// Brillo y profundidad de la densidad rocosa
	vec3 final_color = ring_base * density_profile + col_dust_sheen * (b1 * 0.35);

	// Densidad espesa y presencia sólida
	float alpha = clamp(density_profile * gap_mask * r_fade * 0.92, 0.0, 0.95) * u_visibility;

	ALBEDO = final_color;
	ALPHA = alpha;
}

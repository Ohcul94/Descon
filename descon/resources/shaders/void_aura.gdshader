shader_type spatial;
render_mode blend_add, depth_draw_always, cull_disabled, unshaded;

// Aura del Vacío — disco de suelo con remolino que succiona hacia el centro
uniform vec4 core_color : source_color = vec4(0.04, 0.015, 0.07, 1.0);
uniform vec4 mid_color : source_color = vec4(0.48, 0.12, 0.64, 1.0);
uniform vec4 rim_color : source_color = vec4(0.88, 0.25, 1.0, 1.0);
uniform float swirl_speed : hint_range(0.0, 5.0) = 1.2;
uniform float noise_scale : hint_range(1.0, 20.0) = 6.0;
uniform float rim_power : hint_range(0.5, 8.0) = 2.5;
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
uniform float pulse : hint_range(0.0, 2.0) = 0.0;

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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 center = UV - vec2(0.5);
	float dist = length(center) * 2.0;
	if (dist > 1.0) {
		discard;
	}

	float angle = atan(center.y, center.x);
	// Remolino: el ángulo se desplaza con la distancia y el tiempo (succión hacia adentro)
	float swirl = angle + (1.0 - dist) * 4.0 - TIME * swirl_speed;
	vec2 swirl_uv = vec2(cos(swirl), sin(swirl)) * dist * noise_scale;
	float n = fbm(swirl_uv + vec2(TIME * 0.3, -TIME * 0.5));

	// Bandas concéntricas pulsantes
	float rings = sin(dist * 18.0 - TIME * 3.0) * 0.5 + 0.5;
	rings = pow(rings, 3.0);

	// Aro perimetral brillante
	float rim = smoothstep(0.75, 1.0, dist);
	rim = pow(rim, rim_power);

	// Núcleo denso
	float core = 1.0 - smoothstep(0.0, 0.45, dist);

	vec3 col = core_color.rgb;
	col = mix(col, mid_color.rgb, smoothstep(0.1, 0.7, dist) * (0.4 + 0.6 * n));
	col = mix(col, rim_color.rgb, rim);
	col += rim_color.rgb * rings * 0.35 * (1.0 - rim);
	col += mid_color.rgb * n * 0.5;
	col *= intensity * (1.0 + pulse);

	float alpha = (0.35 + 0.45 * n) * (1.0 - smoothstep(0.9, 1.0, dist));
	alpha += rim * 0.9;
	alpha += core * 0.5;
	alpha *= intensity;
	alpha = clamp(alpha, 0.0, 1.0);

	ALBEDO = col;
	EMISSION = col * (1.5 + pulse * 2.0);
	ALPHA = alpha;
}

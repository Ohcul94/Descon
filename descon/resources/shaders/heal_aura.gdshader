shader_type spatial;
render_mode blend_add, depth_draw_always, cull_disabled, unshaded;

// Aura Curativa — disco de suelo con gradiente cálido suave
uniform vec4 core_color : source_color = vec4(1.0, 0.95, 0.75, 1.0);
uniform vec4 mid_color : source_color = vec4(0.36, 1.0, 0.54, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.84, 0.31, 1.0);
uniform float noise_scale : hint_range(1.0, 20.0) = 5.0;
uniform float rim_power : hint_range(0.5, 8.0) = 2.0;
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
	for (int i = 0; i < 3; i++) {
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

	// Solo ondas suaves concéntricas (bienestar) — sin runas/rayas que giren
	float rings = sin(dist * 14.0 - TIME * 2.0) * 0.5 + 0.5;
	rings = pow(rings, 2.0);

	// Aro perimetral
	float rim = smoothstep(0.7, 1.0, dist);
	rim = pow(rim, rim_power);

	// Núcleo luminoso cálido
	float core = 1.0 - smoothstep(0.0, 0.4, dist);

	float n = fbm(center * noise_scale + vec2(0.0, -TIME * 0.4));

	vec3 col = core_color.rgb * (0.6 + 0.4 * n);
	col = mix(col, mid_color.rgb, smoothstep(0.05, 0.65, dist) * (0.5 + 0.5 * n));
	col = mix(col, rim_color.rgb, rim);
	col += mid_color.rgb * rings * 0.25;
	col *= intensity * (1.0 + pulse);

	float alpha = (0.3 + 0.4 * n) * (1.0 - smoothstep(0.9, 1.0, dist));
	alpha += rim * 0.8;
	alpha += core * 0.55;
	alpha *= intensity;
	alpha = clamp(alpha, 0.0, 1.0);

	ALBEDO = col;
	EMISSION = col * (1.6 + pulse * 2.0);
	ALPHA = alpha;
}

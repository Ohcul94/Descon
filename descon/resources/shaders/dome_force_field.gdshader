shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Campo de fuerza del Domo de Supervivencia
// Burbuja translúcida dorada (mismo ADN visual que el aura del vacío: ruido + bandas
// pulsantes + borde brillante) con onda de impacto cuando la explosión la golpea.

uniform vec4 deep_color : source_color = vec4(0.55, 0.26, 0.02, 1.0);
uniform vec4 base_color : source_color = vec4(1.0, 0.7, 0.16, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.72, 1.0);
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.4;
uniform float noise_scale : hint_range(1.0, 40.0) = 7.0;
uniform float flow_speed : hint_range(0.0, 5.0) = 0.9;
uniform float band_scale : hint_range(1.0, 80.0) = 30.0;
uniform float base_alpha : hint_range(0.0, 1.0) = 0.22;
uniform float alpha_scale : hint_range(0.0, 2.0) = 1.0;
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
uniform float pulse : hint_range(0.0, 3.0) = 0.0;
uniform float impact : hint_range(0.0, 1.0) = 0.0;
uniform vec3 impact_dir = vec3(1.0, 0.0, 0.0);

varying vec3 v_world_normal;

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

void vertex() {
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Energía interna: remolino suave recorriendo la cáscara
	float swirl = UV.x * 6.2831853 + TIME * flow_speed * 0.6;
	vec2 nuv = vec2(cos(swirl), sin(swirl)) * (UV.y * noise_scale) + vec2(UV.y * noise_scale, TIME * 0.35);
	float n = fbm(nuv);

	// Bandas latitudinales pulsantes
	float bands = sin(UV.y * band_scale - TIME * 3.0) * 0.5 + 0.5;
	bands = pow(bands, 3.0);

	// Borde de la burbuja
	float fresnel = pow(clamp(1.0 - abs(dot(NORMAL, VIEW)), 0.0, 1.0), fresnel_power);

	// Onda de impacto: barre el domo desde el lado donde pega la explosión
	float wave = 0.0;
	if (impact > 0.001) {
		float idl = length(impact_dir);
		float d = idl > 0.001 ? dot(normalize(v_world_normal), impact_dir / idl) : -1.0;
		float wave_pos = 1.0 - impact * 2.0;
		wave = smoothstep(0.24, 0.0, abs(d - wave_pos)) * (1.0 - impact);
	}

	vec3 col = mix(deep_color.rgb, base_color.rgb, smoothstep(0.15, 0.85, n));
	col = mix(col, rim_color.rgb, clamp(fresnel, 0.0, 1.0));
	col += base_color.rgb * bands * 0.4;
	col += rim_color.rgb * wave * 2.2;

	float alpha = base_alpha + n * 0.3 + fresnel * 0.6 + bands * 0.12 + wave * 0.75;
	alpha *= alpha_scale;

	ALBEDO = col;
	EMISSION = col * (1.3 + pulse + wave * 3.0) * max(intensity, 0.0);
	ALPHA = clamp(alpha, 0.0, 1.0) * clamp(intensity, 0.0, 1.0);
}

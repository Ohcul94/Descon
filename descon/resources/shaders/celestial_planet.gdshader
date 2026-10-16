shader_type spatial;
render_mode unshaded, cull_back, depth_draw_always, fog_disabled;

uniform float u_visibility : hint_range(0.0, 1.0) = 1.0;
uniform float u_time : hint_range(0.0, 100000.0) = 0.0;
uniform vec3 u_sun_direction = vec3(-0.65, 0.45, 0.60);

// Hash 3D sin fisuras
float hash3D(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Ruido de valor 3D trilineal continuo (sin costuras UV)
float vnoise3D(vec3 x) {
	vec3 p = floor(x);
	vec3 w = fract(x);
	vec3 u = w * w * (3.0 - 2.0 * w);

	float n000 = hash3D(p + vec3(0.0, 0.0, 0.0));
	float n100 = hash3D(p + vec3(1.0, 0.0, 0.0));
	float n010 = hash3D(p + vec3(0.0, 1.0, 0.0));
	float n110 = hash3D(p + vec3(1.0, 1.0, 0.0));
	float n001 = hash3D(p + vec3(0.0, 0.0, 1.0));
	float n101 = hash3D(p + vec3(1.0, 0.0, 1.0));
	float n011 = hash3D(p + vec3(0.0, 1.0, 1.0));
	float n111 = hash3D(p + vec3(1.0, 1.0, 1.0));

	float n00 = mix(n000, n100, u.x);
	float n10 = mix(n010, n110, u.x);
	float n01 = mix(n001, n101, u.x);
	float n11 = mix(n011, n111, u.x);

	float n0 = mix(n00, n10, u.y);
	float n1 = mix(n01, n11, u.y);

	return mix(n0, n1, u.z);
}

float fbm3D(vec3 p) {
	float val = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		val += amp * vnoise3D(p);
		p *= 2.04;
		amp *= 0.5;
	}
	return val;
}

void fragment() {
	vec3 norm = normalize(NORMAL);
	vec3 view_dir = normalize(VIEW);

	// Rotación lenta de la textura de la superficie sobre su eje polar
	float rot_angle = u_time * 0.006;
	float s = sin(rot_angle);
	float c = cos(rot_angle);
	vec3 p_rot = vec3(norm.x * c - norm.z * s, norm.y, norm.x * s + norm.z * c);

	// Relieve marciano en 3D (tierras altas, planicies basálticas y cañones)
	float geo1 = fbm3D(p_rot * 3.5);
	float geo2 = fbm3D(p_rot * 7.5 + vec3(3.2, 1.5, 0.8));
	float mars_relief = geo1 * 0.7 + geo2 * 0.3;

	// Paleta Marciana (Gama de los Rojos / Terracota / Óxido de Hierro)
	vec3 col_basalt_dark = vec3(0.22, 0.09, 0.06);     // Planicies basálticas oscuras
	vec3 col_rust_red = vec3(0.62, 0.20, 0.08);        // Tierra roja oxidada (hematita)
	vec3 col_terracotta = vec3(0.82, 0.34, 0.12);      // Dunas y tierras altas terracota
	vec3 col_sand_orange = vec3(0.92, 0.48, 0.18);     // Polvo marciano brillante suspendido

	vec3 surface = mix(col_basalt_dark, col_rust_red, smoothstep(0.25, 0.55, mars_relief));
	surface = mix(surface, col_terracotta, smoothstep(0.50, 0.75, mars_relief));
	surface = mix(surface, col_sand_orange, smoothstep(0.70, 0.90, mars_relief) * 0.6);

	// Casquete polar blanco sutil en los polos
	float polar = smoothstep(0.84, 0.96, abs(norm.y));
	surface = mix(surface, vec3(0.92, 0.90, 0.88), polar * 0.85);

	// Fase de iluminación solar con terminador suave
	float diff = max(0.0, dot(norm, normalize(u_sun_direction)));
	float sun_light = smoothstep(0.02, 0.40, diff);

	// Resplandor atmosférico de polvo rojizo/naranja en el borde (Atmospheric Rim)
	float rim = pow(1.0 - max(0.0, dot(norm, view_dir)), 2.6);
	vec3 atm_rim = vec3(0.96, 0.42, 0.18) * rim * 1.35;

	// Composición final
	vec3 final_color = surface * (sun_light * 0.85 + 0.15) + atm_rim;

	ALBEDO = final_color;
	ALPHA = u_visibility;
}

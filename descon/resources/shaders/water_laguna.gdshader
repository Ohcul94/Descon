shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

// Agua de laguna / pantano - estilo artistico turbio, barato para GL Compatibility
// TRANSLUCIDA + forma irregular redondeada por mascara (el plano cuadrado se recorta solo).
// Todo procedural, sin texturas externas. 3 lagunas = 3 draw calls, sin refraccion.

uniform vec4 deep_color : source_color = vec4(0.02, 0.07, 0.045, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.10, 0.19, 0.07, 1.0);
uniform vec4 algae_color : source_color = vec4(0.20, 0.30, 0.08, 1.0);
uniform vec4 sky_tint : source_color = vec4(0.65, 0.70, 0.68, 1.0);
uniform vec4 foam_color : source_color = vec4(0.45, 0.52, 0.35, 1.0);

uniform float wave_height : hint_range(0.0, 0.5) = 0.12;
uniform float wave_speed : hint_range(0.0, 4.0) = 1.2;
uniform float wave_scale : hint_range(0.1, 4.0) = 0.8;

uniform float algae_amount : hint_range(0.0, 1.0) = 0.55;
uniform float algae_scale : hint_range(0.5, 20.0) = 3.0;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.3;
uniform float fresnel_power : hint_range(0.5, 8.0) = 3.0;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.28;
uniform float specular_val : hint_range(0.0, 1.0) = 0.55;

uniform float base_alpha : hint_range(0.0, 1.0) = 0.78;
uniform float shape_irregularity : hint_range(0.0, 1.2) = 0.55;
// En false: plano completo para rellenar por altura (oasis). En true: charco redondo.
uniform bool use_rounded_shape = true;

// Burbujas y aureolas que emergen a la superficie y se expanden
uniform bool enable_bubbles = true;
uniform float bubble_density : hint_range(0.0, 5.0) = 0.8;
uniform float bubble_speed : hint_range(0.1, 3.0) = 0.5;
uniform vec4 bubble_ring_color : source_color = vec4(0.80, 0.94, 0.90, 1.0);

// Pirañas mutantes nadando bajo el agua
uniform bool enable_mutant_fish = true;

varying vec2 v_world_xz;

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

// 2 octavas para maximo rendimiento en GLES3 / Compatibility
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 2; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

// Calcula aureolas redondeadas, muy dispersas y espaciadas en el tiempo
float calc_bubble_ring(vec2 p, float time_offset, float speed) {
	vec2 cell_id = floor(p);
	vec2 cell_uv = fract(p);

	float h1 = hash(cell_id * 13.37 + vec2(1.7, 9.2));
	float h2 = hash(cell_id * 27.53 + vec2(7.3, 3.1));
	float h3 = hash(cell_id * 41.19 + vec2(11.5, 5.8));
	float h4 = hash(cell_id * 53.81 + vec2(19.4, 3.7));

	// Muy dispersas: solo ~22% de las celdas generan burbujas
	if (h1 > 0.22) return 0.0;

	// Distintos tamanos organicos: pequenas (0.50x), medianas (0.9x) y grandes (1.35x)
	float size_mult = mix(0.50, 1.35, h4);

	// Centro aleatorio seguro dentro de la celda
	vec2 center = vec2(0.35 + 0.30 * h2, 0.35 + 0.30 * h3);
	vec2 delta = cell_uv - center;
	float raw_dist = length(delta);

	// Ciclo muy espaciado: activa solo el 18% del ciclo; 82% del tiempo en calma absoluta
	float cycle = fract(TIME * (speed * 0.11) + time_offset + h1 * 9.17);
	float active_dur = 0.18;
	if (cycle > active_dur) return 0.0;

	// Progreso del evento activo (0.0 a 1.0)
	float prog = cycle / active_dur;

	// Forma redondeada pero con sutil irregularidad organica natural (tirando a redonda)
	float angle = atan(delta.y, delta.x);
	float wobble = sin(angle * 2.0 + h2 * 6.28) * 0.045 + cos(angle * 3.0 + h3 * 6.28) * 0.025;
	float dist = raw_dist * (1.0 + wobble);

	// Fase 1 (prog < 0.30): Burbuja emerge suavemente
	if (prog < 0.30) {
		float grow = prog / 0.30;
		float r = mix(0.015, 0.060, grow) * size_mult;
		float dome = smoothstep(r, 0.0, dist);
		float rim = smoothstep(r + 0.010, r, dist) * (1.0 - smoothstep(r, r - 0.015, dist));
		return (dome * 0.30 + rim * 0.80) * grow;
	} else {
		// Fase 2 (prog >= 0.30): Revienta y se expande la aureola redondeada que se disipa
		float exp_t = (prog - 0.30) / 0.70;
		float max_r = mix(0.11, 0.26, h4) * size_mult;
		float ring_r = mix(0.060 * size_mult, max_r, sqrt(exp_t));
		float ring_w = mix(0.018 * size_mult, 0.005, exp_t);
		float ring = smoothstep(ring_r - ring_w, ring_r, dist) * (1.0 - smoothstep(ring_r, ring_r + ring_w, dist));
		float fade = (1.0 - exp_t) * (1.0 - exp_t);
		return ring * fade * 0.80;
	}
}

// Calcula sombras y brillo bioluminiscente de pirañas mutantes nadando bajo el agua
void calc_mutant_fish(vec2 w_pos, float shape_mask, out float f_shadow, out vec3 f_glow) {
	f_shadow = 0.0;
	f_glow = vec3(0.0);
	if (shape_mask < 0.20) return;

	// 3 pirañas mutantes patrullando bajo el agua en trayectorias elípticas suaves
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float speed = 0.28 + fi * 0.07;
		float t = TIME * speed + fi * 5.23;

		// Trayectoria eliptica / lemniscata suave dentro de la laguna
		float rad_x = 7.0 + sin(fi * 2.1) * 2.5;
		float rad_z = 4.5 + cos(fi * 1.8) * 2.0;
		vec2 center = vec2(sin(fi * 3.4) * 2.5, cos(fi * 2.9) * 2.5);
		vec2 p1 = center + vec2(sin(t) * rad_x, sin(t * 2.0 + fi) * rad_z * 0.5);
		vec2 p2 = center + vec2(sin(t + 0.06) * rad_x, sin((t + 0.06) * 2.0 + fi) * rad_z * 0.5);

		vec2 v = p2 - p1;
		float v_len = length(v);
		if (v_len < 0.0001) continue;
		vec2 f_dir = v / v_len;
		vec2 f_side = vec2(-f_dir.y, f_dir.x);

		// Distancias locales relativas a la piraña
		vec2 d = w_pos - p1;
		float lx = dot(d, f_dir);   // Cabeza (+) a cola (-)
		float ly = dot(d, f_side);  // Lateral

		// Variantes mutantes: longitud y ancho distintos
		float f_len = 1.35 + fi * 0.40;  // Longitud (1.35m piraña corta, 1.75m mediana, 2.15m serpiente)
		float f_width = 0.36 - fi * 0.06; // Ancho (piraña más gorda, serpiente más fina)

		// Coleo natural
		float wag = sin(TIME * (5.0 + fi * 0.7) + lx * 2.5) * 0.12;
		float tail_w = clamp(-lx / f_len, 0.0, 1.2);
		ly += wag * tail_w;

		// Cuerpo
		if (lx > -f_len && lx < f_len * 0.55) {
			float nx = (lx + f_len) / (f_len * 1.55); // 0 (cola) a 1 (hocico)
			float body_h = f_width * sin(nx * 3.14159) * (0.8 + 0.35 * nx);

			// Espinas dorsales mutantes en la variante 1
			if (i == 1 && ly > 0.0) {
				body_h += max(0.0, sin(lx * 7.5)) * 0.07;
			}

			float b_dist = abs(ly) / max(0.001, body_h);
			if (b_dist < 1.0) {
				float b_mask = smoothstep(1.0, 0.3, b_dist);
				f_shadow = max(f_shadow, b_mask * 0.82);

				// Colores mutantes: 0 = Verde Tóxico, 1 = Violeta Cibernético, 2 = Cyan Bioluminiscente
				vec3 col_mut = vec3(0.12, 0.85, 0.40);
				if (i == 1) col_mut = vec3(0.85, 0.18, 0.75);
				if (i == 2) col_mut = vec3(0.18, 0.75, 0.95);

				float spine = smoothstep(0.35, 0.0, abs(ly)) * smoothstep(0.0, 0.4, nx);
				f_glow += col_mut * spine * b_mask * 0.70;
			}
		}

		// Aleta caudal / cola
		float t_start = -f_len * 0.85;
		float t_end = -f_len * 1.35;
		if (lx <= t_start && lx >= t_end) {
			float t_norm = (lx - t_end) / (t_start - t_end);
			float t_fin = (1.0 - t_norm) * (f_width * 1.25);
			float fin_dist = abs(ly) / max(0.001, t_fin);
			if (fin_dist < 1.0) {
				float f_mask = smoothstep(1.0, 0.2, fin_dist) * (1.0 - t_norm);
				f_shadow = max(f_shadow, f_mask * 0.60);
			}
		}
	}

	// Atenuar suavemente cerca de la costa para no salir a tierra
	float border_fade = smoothstep(0.20, 0.50, shape_mask);
	f_shadow *= border_fade;
	f_glow *= border_fade;
}

void vertex() {
	// Oleaje leve: 2 senos cruzados + chop corto, todo en GPU
	v_world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	float t = TIME * wave_speed;
	vec3 p = VERTEX;
	float w = sin(p.x * wave_scale * 0.8 + t) * cos(p.z * wave_scale * 0.7 + t * 0.8);
	w += sin((p.x + p.z) * wave_scale * 0.35 + t * 0.6) * 0.5;
	w += sin(p.z * wave_scale * 2.2 - t * 1.4) * cos(p.x * wave_scale * 1.9 + t * 1.1) * 0.18;
	VERTEX.y += w * wave_height;
}

void fragment() {
	// Forma: redondeada irregular (charco) o plano completo (relleno por altura).
	float shape = 1.0;
	float foam_ring = 0.0;
	float d = 0.0;
	if (use_rounded_shape) {
		float edge_n = fbm(v_world_xz * 0.045);
		d = length(UV - vec2(0.5)) * 2.0;
		d += (edge_n - 0.5) * shape_irregularity * 2.0;
		shape = 1.0 - smoothstep(0.68, 0.95, d);
		if (shape < 0.02) discard;
		foam_ring = smoothstep(0.35, 0.68, d) * shape;
	}

	// Nata verde estancada que deriva lento (estilo pantano)
	vec2 big_uv = UV * algae_scale + vec2(TIME * 0.02, TIME * 0.012);
	float big_n = fbm(big_uv * 3.0);
	float scum_mask = smoothstep(1.0 - algae_amount - 0.25, 1.0 - algae_amount + 0.25, big_n);

	// Ripple fino animado para romper el reflejo
	vec2 rip_uv = UV * 40.0;
	float r1 = noise(rip_uv + vec2(TIME * 0.6, TIME * 0.3));
	float r2 = noise(rip_uv * 1.7 - vec2(TIME * 0.4, TIME * 0.5));
	float ripple = (r1 + r2 - 1.0) * ripple_strength;

	// Efecto de aureolas superficiales redondeadas, muy dispersas y espaciadas
	float bubble_effect = 0.0;
	if (enable_bubbles && shape > 0.08) {
		float b1 = calc_bubble_ring(v_world_xz * (0.09 * bubble_density), 0.0, bubble_speed);
		float b2 = calc_bubble_ring((v_world_xz + vec2(23.7, 14.3)) * (0.11 * bubble_density), 0.55, bubble_speed * 0.90);
		bubble_effect = clamp(b1 + b2, 0.0, 1.0);
		bubble_effect *= smoothstep(0.08, 0.35, shape);
	}

	// Sombras y brillo de pirañas mutantes nadando bajo el agua
	float fish_shadow = 0.0;
	vec3 fish_glow = vec3(0.0);
	if (enable_mutant_fish) {
		calc_mutant_fish(v_world_xz, shape, fish_shadow, fish_glow);
	}

	// Perturbar normal para specular animado y relieve de burbujas
	NORMAL = normalize(NORMAL + vec3(ripple + bubble_effect * 0.18, 0.0, ripple * 0.7 + bubble_effect * 0.18));

	// Fresnel para tinte de cielo en angulos rasantes
	float fres = pow(clamp(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), fresnel_power);

	// Color base: profundo -> orilla
	vec3 col = mix(deep_color.rgb, shallow_color.rgb, clamp(big_n * 0.7 + ripple * 0.5 + 0.15, 0.0, 1.0));

	// Sombra de pirañas mutantes nadando en la profundidad (bloquea la luz de fondo)
	col = mix(col, deep_color.rgb * 0.25, fish_shadow * 0.85);
	// Destello bioluminiscente de las pirañas atravesando el agua
	col += fish_glow * 0.65;

	// Capas superiores: nata verde, espuma de borde, reflejo de cielo y aureolas
	col = mix(col, algae_color.rgb, scum_mask * 0.75);
	col = mix(col, foam_color.rgb, foam_ring * 0.35);
	col = mix(col, sky_tint.rgb, fres * 0.45);
	col = mix(col, bubble_ring_color.rgb, bubble_effect * 0.55);

	ALBEDO = col;
	ROUGHNESS = mix(roughness_val, 0.15, bubble_effect * 0.5);
	SPECULAR = mix(specular_val, 0.80, bubble_effect * 0.6);
	METALLIC = 0.08;
	// Centro mas transparente (se ve el fondo), borde y nata mas opacos
	float alpha = base_alpha * shape;
	alpha = mix(alpha * 0.62, alpha, clamp(fres * 0.8 + scum_mask * 0.5 + foam_ring * 0.6, 0.0, 1.0));
	ALPHA = clamp(alpha, 0.0, 1.0);
}

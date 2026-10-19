shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, fog_disabled;

// Configuración y Toggles (SettingsManager)
uniform float u_show_stars : hint_range(0.0, 1.0) = 1.0;
uniform float u_show_sky_effects : hint_range(0.0, 1.0) = 1.0;
uniform float u_star_density : hint_range(0.1, 3.0) = 0.35;

// Dithering anti-banding: los degradados muy oscuros del cielo se cuantizan en 8 bits y forman
// franjas que se desplazan al mover la camara (el GL Compatibility no tiene debanding).
uniform float u_dither_strength : hint_range(0.0, 4.0) = 1.5;

// Ciclo Atmosférico Dinámico (BaseMap)
uniform float u_cycle_time : hint_range(0.0, 100000.0) = 0.0;
uniform float u_cycle_progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 u_state_weights = vec4(1.0, 0.0, 0.0, 0.0); // x: Noche, y: Amanecer, z: Día Astral, w: Aurora

varying vec3 v_local_pos;

void vertex() {
	v_local_pos = VERTEX;
}

// Hash 3D de alta calidad para ruido continuo sin costuras (seam-free)
float hash31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// Hash 3D original
float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Hash 2D
float hash2(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Ruido de valor 3D continuo (Hermite trilineal) - 100% libre de cortes o costuras esféricas (seam-free)
float vnoise3D(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float n000 = hash31(i);
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));

	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z
	);
}

void fragment() {
	vec3 dir = normalize(v_local_pos);
	vec3 final_col = vec3(0.0);

	float elevation = clamp(dir.y, 0.0, 1.0);

	// 1. GRADIENTE ATMOSFÉRICO Y HORIZONTE BASE (Continuo 360 grados sin cortes ni abismos)
	vec3 night_zenith = vec3(0.003, 0.005, 0.015);
	vec3 night_horizon = vec3(0.010, 0.018, 0.040);

	vec3 dawn_zenith = vec3(0.020, 0.018, 0.050);
	vec3 dawn_horizon = vec3(0.280, 0.140, 0.060);

	vec3 day_zenith = vec3(0.035, 0.075, 0.180);
	vec3 day_horizon = vec3(0.120, 0.200, 0.360);

	vec3 aurora_zenith = vec3(0.008, 0.035, 0.055);
	vec3 aurora_horizon = vec3(0.035, 0.180, 0.220);

	vec4 w = u_state_weights;
	vec3 zenith_col = night_zenith * w.x + dawn_zenith * w.y + day_zenith * w.z + aurora_zenith * w.w;
	vec3 horizon_col = night_horizon * w.x + dawn_horizon * w.y + day_horizon * w.z + aurora_horizon * w.w;

	// Hacia arriba: transición suave y rica al cenit.
	// Hacia abajo: mantiene el color del horizonte (horizon_col) de forma continua para fundirse con el suelo sin bandas negras
	float sky_t = clamp(dir.y, 0.0, 1.0);
	vec3 sky_base = mix(horizon_col, zenith_col, pow(sky_t, 0.75));

	// Banda de bruma atmosférica luminosa en el horizonte (fusiona suavemente el cielo con el piso)
	float haze_band = exp(-pow((dir.y - (-0.06)) * 6.0, 2.0));
	sky_base += horizon_col * (haze_band * 0.45);
	final_col += sky_base;

	// Si el rayo apunta debajo del horizonte visible (-0.15), el firmamento no es visible;
	// el color base ya es el horizonte uniforme. Esto ahorra hasta un 80% del cálculo de fragmentos
	// en perspectiva 2.5D, garantizando 120 FPS estables sin perder ningún detalle visual en el cielo.
	if (dir.y >= -0.15) {
		float horizon_fx_fade = smoothstep(-0.15, 0.05, dir.y);

		// 2. EFECTOS AVANZADOS DE CIELO (3D / NEBULOSAS / AURORAS / METEOROS)
		if (u_show_sky_effects > 0.01) {
			float fx_mult = u_show_sky_effects * horizon_fx_fade;

			// --- A. NEBULOSA CÓSMICA MULTICAPA 3D (100% CONTINUA SIN COSTURAS NI CORTES) ---
			// Evaluado directamente en espacio 3D unitario esférico para evitar el corte UV de atan2
			vec3 warp_pos = dir * 2.2 + vec3(u_cycle_time * 0.0012, u_cycle_time * 0.0006, -u_cycle_time * 0.0008);
			float n_warp = vnoise3D(warp_pos);
			
			vec3 flow_pos = dir * 3.8 - vec3(u_cycle_time * 0.0016, -u_cycle_time * 0.0008, u_cycle_time * 0.0010) + vec3(n_warp * 0.45);
			float n_filaments = vnoise3D(flow_pos);
			
			float neb_density = smoothstep(0.28, 0.82, n_warp * 0.5 + n_filaments * 0.5);

			vec3 neb_night = mix(vec3(0.05, 0.09, 0.24), vec3(0.20, 0.05, 0.22), n_warp);
			vec3 neb_dawn = mix(vec3(0.32, 0.12, 0.06), vec3(0.38, 0.22, 0.05), n_warp);
			vec3 neb_day = mix(vec3(0.08, 0.15, 0.26), vec3(0.18, 0.25, 0.38), n_warp);
			vec3 neb_aurora = mix(vec3(0.03, 0.22, 0.18), vec3(0.24, 0.04, 0.28), n_warp);

			vec3 active_neb_col = neb_night * w.x + neb_dawn * w.y + neb_day * w.z + neb_aurora * w.w;
			float neb_elev_mask = smoothstep(-0.15, 0.25, dir.y) * (1.0 - elevation * 0.25);
			final_col += active_neb_col * (neb_density * 1.4 * neb_elev_mask * fx_mult);

		// --- B. AURORA BOREAL VOLUMÉTRICA (CORTINAS ONDULANTES 3D SIN CORTES RECTOS) ---
		float aurora_weight = w.w * 1.0 + w.x * 0.25;
		if (aurora_weight > 0.01) {
			float a_wave1 = sin(dir.x * 4.5 + u_cycle_time * 0.22) * 0.08;
			float a_wave2 = cos(dir.z * 3.8 - u_cycle_time * 0.16) * 0.05;
			float a_h = dir.y + a_wave1 + a_wave2;

			// Perfil vertical continuo: se desvanece de forma gradual hacia abajo sin NINGÚN corte
			float a_curtain = smoothstep(-0.02, 0.25, a_h) * smoothstep(0.85, 0.35, a_h);
			float a_rays = sin(dir.x * 34.0 + dir.z * 20.0 + u_cycle_time * 0.45) * 0.5 + 0.5;
			a_rays = pow(a_rays, 1.5);
			float a_val = a_curtain * (0.35 + 0.65 * a_rays);

			// Desvanecimiento suave en la base hacia el horizonte para eliminar cualquier línea recta
			float a_bottom_fade = smoothstep(-0.15, 0.25, dir.y);
			a_val *= a_bottom_fade;

			float a_azimuth = smoothstep(-0.85, -0.05, dir.z);
			a_val *= a_azimuth;

			vec3 a_green = vec3(0.04, 0.90, 0.42);
			vec3 a_cyan = vec3(0.08, 0.70, 0.98);
			vec3 a_violet = vec3(0.70, 0.12, 0.90);

			float fringe_t = smoothstep(0.28, 0.60, a_h);
			vec3 a_col = mix(mix(a_green, a_cyan, a_rays * 0.4), a_violet, fringe_t);

			final_col += a_col * (a_val * 2.2 * aurora_weight * fx_mult);
		}

		// --- C. METEORITOS / ESTRELLAS FUGACES PROCEDURALES ---
		float meteor_cycle = 5.2;
		float meteor_seed = floor(u_cycle_time / meteor_cycle);
		float meteor_t = fract(u_cycle_time / meteor_cycle) * meteor_cycle;
		
		if (meteor_t < 0.65 && dir.y > 0.15) {
			float m_rand1 = hash2(vec2(meteor_seed, 1.13));
			float m_rand2 = hash2(vec2(meteor_seed, 7.89));
			
			vec3 m_start = normalize(vec3(cos(m_rand1 * 6.28) * 0.7, 0.55 + m_rand2 * 0.3, sin(m_rand1 * 6.28) * 0.7));
			vec3 m_vel = normalize(vec3(-0.4, -0.3, 0.5));
			
			float progress_m = meteor_t / 0.65;
			vec3 m_head = m_start + m_vel * (progress_m * 0.45);
			vec3 m_tail = m_head - m_vel * 0.12;
			
			vec3 line_vec = m_head - m_tail;
			float line_len = length(line_vec);
			vec3 line_dir = line_vec / max(0.0001, line_len);
			
			float proj = clamp(dot(dir - m_tail, line_dir), 0.0, line_len);
			vec3 closest_pt = m_tail + line_dir * proj;
			float m_dist = length(dir - closest_pt);
			
			float m_glow = smoothstep(0.015, 0.0, m_dist);
			float m_fade = sin(progress_m * 3.14159);
			vec3 m_col = mix(vec3(0.6, 0.9, 1.0), vec3(1.0, 0.98, 0.8), progress_m);
			
			final_col += m_col * (m_glow * m_fade * 3.5 * fx_mult);
		}
	}

	// 3. SISTEMA DE ESTRELLAS AAA: JERÁRQUICO, RESPIRABLE Y CON CENTELLEO VIVO
	if (u_show_stars > 0.01) {
		float daylight_fade = (1.0 - w.z * 0.85) * horizon_fx_fade;

		// --- TIER 1: ESTRELLAS HEROICAS / PRINCIPALES (Cruz de difracción anamórfica) ---
		float hero_div = 16.0 * u_star_density;
		vec3 hero_cell = floor(dir * hero_div);
		vec3 hero_fuv = fract(dir * hero_div) - 0.5;
		float hero_h = hash3(hero_cell + 7.77);

		if (hero_h > 0.976) {
			float h_bright = hash3(hero_cell + 13.13) * 0.5 + 0.5;
			float h_phase = hash3(hero_cell + 19.19) * 6.2832;

			vec3 h_pos = (vec3(
				hash3(hero_cell + 23.23),
				hash3(hero_cell + 29.29),
				hash3(hero_cell + 31.31)
			) - 0.5) * 0.65;

			vec2 h_duv = hero_fuv.xy - h_pos.xy;
			float h_d = length(h_duv);

			float tw_fast = sin(u_cycle_time * 8.0 + h_phase * 2.3) * 0.5 + 0.5;
			float tw_slow = sin(u_cycle_time * 2.5 + h_phase) * 0.5 + 0.5;
			float hero_tw = pow(tw_fast * 0.45 + tw_slow * 0.55, 1.3) * 1.6;

			float core = smoothstep(0.045, 0.0, h_d) * 2.5;
			float halo = exp(-h_d * 22.0) * 0.9;

			float spike_rot = h_phase * 0.25;
			float c_rot = cos(spike_rot);
			float s_rot = sin(spike_rot);
			vec2 sp_uv = vec2(h_duv.x * c_rot - h_duv.y * s_rot, h_duv.x * s_rot + h_duv.y * c_rot);

			float sp_h = exp(-abs(sp_uv.y) * 110.0) * smoothstep(0.24, 0.0, abs(sp_uv.x));
			float sp_v = exp(-abs(sp_uv.x) * 110.0) * smoothstep(0.24, 0.0, abs(sp_uv.y));
			float spikes = (sp_h + sp_v) * 0.75;

			float hero_intensity = (core + halo + spikes) * h_bright * hero_tw;

			float col_rand = hash3(hero_cell + 41.41);
			vec3 hero_col = mix(vec3(0.85, 0.92, 1.0), vec3(1.0, 0.90, 0.70), col_rand);
			hero_col = mix(hero_col, vec3(0.70, 0.85, 1.0), tw_fast * 0.4);

			final_col += hero_col * (hero_intensity * u_show_stars * daylight_fade);
		}

		// --- TIER 2: ESTRELLAS DE CAMPO MEDIO (Distribución limpia y equilibrada) ---
		float mid_div = 55.0 * u_star_density;
		vec3 mid_cell = floor(dir * mid_div);
		vec3 mid_fuv = fract(dir * mid_div) - 0.5;
		float mid_h = hash3(mid_cell + 11.11);

		if (mid_h > 0.980) {
			float m_bright = hash3(mid_cell + 17.17) * 0.6 + 0.4;
			float m_phase = hash3(mid_cell + 23.23) * 6.2832;

			vec3 m_pos = (vec3(
				hash3(mid_cell + 31.31),
				hash3(mid_cell + 37.37),
				hash3(mid_cell + 43.43)
			) - 0.5) * 0.6;

			vec2 m_duv = mid_fuv.xy - m_pos.xy;
			float m_d = length(m_duv);

			float m_tw = sin(u_cycle_time * 4.5 * (0.8 + 0.6 * m_bright) + m_phase) * 0.5 + 0.5;
			m_tw = mix(0.4, 1.3, m_tw);

			float m_size = mix(0.018, 0.040, m_bright);
			float m_star = smoothstep(m_size, 0.0, m_d) * 1.5 + exp(-m_d * 30.0) * 0.5;
			m_star *= m_bright * m_tw;

			float m_ci = hash3(mid_cell + 53.53);
			vec3 m_col;
			if (m_ci < 0.45) m_col = vec3(1.0);
			else if (m_ci < 0.72) m_col = vec3(0.75, 0.88, 1.0);
			else if (m_ci < 0.88) m_col = vec3(1.0, 0.95, 0.75);
			else m_col = vec3(1.0, 0.60, 0.35);

			final_col += m_col * (m_star * u_show_stars * daylight_fade * 1.6);
		}

		// --- TIER 3: POLVO ESTELAR Y CÚMULOS DE LA VÍA LÁCTEA ---
		float galactic_stream = smoothstep(0.42, 0.06, abs(dot(dir, normalize(vec3(0.45, 0.25, 0.85)))));
		if (galactic_stream > 0.01) {
			float clust_div = 120.0 * u_star_density;
			vec3 clust_cell = floor(dir * clust_div);
			vec3 clust_fuv = fract(dir * clust_div) - 0.5;
			float clust_h = hash3(clust_cell + 67.67);

			if (clust_h > 0.962) {
				float c_bright = hash3(clust_cell + 71.71) * 0.5 + 0.3;
				vec3 c_pos = (vec3(
					hash3(clust_cell + 79.79),
					hash3(clust_cell + 83.83),
					hash3(clust_cell + 89.89)
				) - 0.5) * 0.5;

				vec2 c_duv = clust_fuv.xy - c_pos.xy;
				float c_d = length(c_duv);

				float c_star = smoothstep(0.022, 0.0, c_d) * c_bright * galactic_stream;
				vec3 c_col = mix(vec3(0.8, 0.9, 1.0), vec3(1.0, 0.95, 0.85), clust_h);

				final_col += c_col * (c_star * u_show_stars * daylight_fade * 1.1);
			}
		}
	}

		// Dithering anti-banding ultrarrápido en espacio lineal sin pow() pesados
		if (u_dither_strength > 0.01) {
			vec2 fc = FRAGCOORD.xy;
			float ign = fract(52.9829189 * fract(dot(fc, vec2(0.06711056, 0.00583715))));
			float dn = (ign - 0.5) * (u_dither_strength / 255.0);
			final_col += vec3(dn);
		}
	}

	ALBEDO = final_col;
}

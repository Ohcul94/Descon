shader_type spatial;
// v920.0 FOG OF WAR - Atmósfera de Neblina Realista (Efecto Autopista):
//   - Degradés orgánicos de entrada y salida progresivos sin cortes secos.
//   - Multi-capa de nubes, jirones y partículas en suspensión que impiden la visión.
//   - Anclaje exacto al suelo y geometría (100% alineado con el jugador sin desfasaje).
//   - Desaturación y dispersión atmosférica (Beer-Lambert) idéntica a la niebla en carretera.
//   - Compatible 100% con GLES3 y Forward+ (sin return en fragment, ultra optimizado 60+ FPS).
render_mode unshaded, depth_draw_never, cull_disabled, depth_test_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform sampler2D depth_texture  : hint_depth_texture,  filter_nearest;
uniform sampler2D vision_texture  : filter_linear, repeat_disable;
uniform sampler2D history_texture : filter_linear, repeat_disable;
uniform sampler2D noise_texture   : filter_linear, repeat_enable;

uniform vec2  map_offset_3d = vec2(0.0, 0.0);
uniform vec2  map_size_3d   = vec2(80.0, 113.0);
uniform float fog_opacity    : hint_range(0.0, 1.0) = 0.96;
uniform float shroud_opacity : hint_range(0.0, 1.0) = 0.44;

uniform vec3  fog_color_dark  : source_color = vec3(0.14, 0.16, 0.18);
uniform vec3  fog_color_mid   : source_color = vec3(0.36, 0.38, 0.42);
uniform vec3  fog_color_light : source_color = vec3(0.65, 0.67, 0.70);
uniform vec3  swamp_tint      : source_color = vec3(0.28, 0.33, 0.27);
uniform float swamp_mix       : hint_range(0.0, 0.5)  = 0.18;
uniform float fog_desaturate  : hint_range(0.0, 1.0)  = 0.72;

uniform float cloud_scale1    = 0.0075;
uniform float cloud_scale2    = 0.016;
uniform float cloud_speed1    = 0.012;
uniform float cloud_speed2    = -0.010;
uniform float elevation_speed = 0.006;
uniform float cloud_contrast  : hint_range(0.5, 2.5) = 1.25;

uniform float noise_scale = 0.010;
uniform float noise_speed = 0.016;
uniform bool  flip_y      = false;

uniform float fog_height        : hint_range(0.5, 60.0) = 25.0;
uniform float fog_density       : hint_range(0.1, 2.5)  = 1.25;
uniform float fog_vertical_fade : hint_range(0.2, 3.0)  = 1.2;

varying vec3 v_ray_dir;
varying vec3 v_camera_pos;

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.0, 1.0);
	vec4 vp_ray  = INV_PROJECTION_MATRIX * vec4(VERTEX.xy, 1.0, 1.0);
	vp_ray /= vp_ray.w;
	v_ray_dir    = (INV_VIEW_MATRIX * vec4(vp_ray.xyz, 0.0)).xyz;
	v_camera_pos = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

void fragment() {
	vec3 screen_color = texture(screen_texture, SCREEN_UV).rgb;
	vec3 ray_dir      = normalize(v_ray_dir);
	vec3 ray_origin   = v_camera_pos;
	float cam_y       = ray_origin.y;

	// 1. Reconstrucción precisa de la posición del píxel en coordenadas de mundo
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	vec3 frag_world = vec3(0.0);
	bool has_geom   = false;

	if (raw_depth < 0.9999 && raw_depth > 0.0001) {
		vec3 ndc_d = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth * 2.0 - 1.0);
		vec4 vp_d  = INV_PROJECTION_MATRIX * vec4(ndc_d, 1.0);
		vp_d /= vp_d.w;
		vec3 cand = (INV_VIEW_MATRIX * vp_d).xyz;
		// En el juego 2.5D la geometría real se encuentra entre Y = -10.0 y Y = 60.0.
		// Si en móviles OpenGL ES3 la depth texture no está soportada o arroja valores fuera de rango,
		// se utiliza el fallback analítico exacto al plano de suelo Y=0.
		if (cand.y >= -10.0 && cand.y <= 60.0) {
			frag_world = cand;
			has_geom   = true;
		}
	}
	if (!has_geom) {
		if (ray_dir.y < -0.0001) {
			// Fallback universal al suelo Y=0 (para cielo, vacío o móviles GLES3 sin depth copia)
			float t_ground = -cam_y / ray_dir.y;
			if (t_ground > 0.0) {
				frag_world = ray_origin + ray_dir * t_ground;
				frag_world.y = 0.0;
				has_geom   = true;
			}
		}
		// Rayos hacia el horizonte o cielo sin geometría: has_geom permanece false y no proyectan niebla en el espacio
	}

	vec3 final_color = screen_color;

	// Coordenadas UV del mapa 2D calculadas fielmente a frag_world.xz
	vec2 sample_xz = frag_world.xz;
	vec2 fog_uv    = (sample_xz - map_offset_3d) / map_size_3d;
	bool in_map    = (fog_uv.x >= 0.0 && fog_uv.x <= 1.0 &&
	                  fog_uv.y >= 0.0 && fog_uv.y <= 1.0);

	// Suavizado en el perímetro exterior del mapa
	float edge_fade = smoothstep(0.0, 0.05, min(min(fog_uv.x, 1.0 - fog_uv.x),
	                                            min(fog_uv.y, 1.0 - fog_uv.y)));

	if (has_geom && in_map && edge_fade > 0.001) {
		// Bruma y viento suave en los bordes
		vec2 wind_uv = sample_xz * 0.012 + vec2(TIME * noise_speed, TIME * noise_speed * 0.65);
		float noise_val = texture(noise_texture, wind_uv).r;

		// Perturbación contenida para que los bordes de la niebla no sean matemáticamente rígidos
		vec2 dist_uv = clamp(fog_uv + (noise_val - 0.5) * noise_scale, 0.0, 1.0);
		vec2 s_uv    = vec2(dist_uv.x, flip_y ? 1.0 - dist_uv.y : dist_uv.y);

		float current_vision = texture(vision_texture, s_uv).r;

		// Si el fragmento está completamente descubierto bajo la nave, no procesar niebla
		if (current_vision < 0.999) {
			float explored = texture(history_texture, s_uv).r;

			// --- DEGRADÉ DE ENTRADA Y SALIDA (EFECTO AUTOPISTA) ---
			// Visibilidad base: zona explorada (shroud) vs zona oculta virgen (fog)
			float base_vis   = max(explored * (1.0 - shroud_opacity), 1.0 - fog_opacity);
			float visibility = base_vis + (1.0 - base_vis) * current_vision;

			// Rampa de degradé suave y progresiva
			float raw_fog = clamp(1.0 - visibility, 0.0, 1.0);
			float fog_gradient = smoothstep(0.0, 0.95, raw_fog) * edge_fade;

			if (fog_gradient > 0.002) {
				// --- BANCOS DE NUBES Y PARTÍCULAS EN SUSPENSIÓN ---
				// Capa 1: Bancos grandes de niebla densa que se desplazan lentamente
				vec2 c_uv1 = sample_xz * cloud_scale1 + vec2(TIME * cloud_speed1, TIME * elevation_speed);
				float cloud_layer1 = texture(noise_texture, c_uv1).r;

				// Capa 2: Volutas / jirones de niebla que cruzan en ángulo
				vec2 c_uv2 = sample_xz * cloud_scale2 + vec2(TIME * cloud_speed2, -TIME * cloud_speed1 * 0.5);
				float cloud_layer2 = texture(noise_texture, c_uv2).r;

				// Capa 3: Micro-partículas de vapor y humedad en suspensión (gotitas en el aire)
				vec2 c_uv3 = sample_xz * 0.038 + vec2(TIME * noise_speed * 1.4, TIME * noise_speed * 0.8);
				float particles = texture(noise_texture, c_uv3).r;

				// Síntesis de nubes de niebla
				float cloud_structure = cloud_layer1 * 0.50 + cloud_layer2 * 0.35 + particles * 0.15;
				cloud_structure = pow(clamp(cloud_structure, 0.0, 1.0), cloud_contrast);
				cloud_structure = smoothstep(0.15, 0.85, cloud_structure);

				// --- TECHO IRREGULAR DE NIEBLA (EVITA EL CORTE PLANO DE CAJA) ---
				// Variación orgánica de la altura de las copas de niebla con el viento
				float top_variation = (cloud_layer1 * 0.60 + cloud_layer2 * 0.40 - 0.5) * (fog_height * 0.40);
				float effective_top = max(fog_height + top_variation, 6.0);

				// Límite vertical inferior: cubre terreno hundido / cráteres hasta varios metros bajo Y=0,
				// y se desvanece suavemente a 0 más abajo (-8.0m) para no pintar bajo el suelo del mapa.
				float bottom_fade = smoothstep(-8.0, -3.5, frag_world.y);

				// Desvanecimiento suave e irregular hacia arriba
				float top_fade = 1.0;
				if (frag_world.y > 0.1) {
					// El umbral de desvanecimiento ondula dinámicamente con la densidad de cada jirón
					float fade_start = mix(0.35, 0.65, cloud_structure);
					float norm_y     = clamp(frag_world.y / effective_top, 0.0, 1.0);
					top_fade         = 1.0 - smoothstep(fade_start, 1.0, norm_y);
				}
				float height_factor = bottom_fade * top_fade;

				// En la entrada de la niebla, las volutas más densas penetran primero
				float billow_mod = mix(0.80, 1.35, cloud_structure);
				float density    = clamp(fog_gradient * billow_mod * height_factor, 0.0, 1.0);

				// Modelo de extinción atmosférica exponencial (Beer-Lambert suave y espeso como en carretera)
				float optical_fog = 1.0 - exp(-density * fog_density * 3.8);
				optical_fog = clamp(optical_fog, 0.0, 1.0);

				// Límite según zona explorada (Shroud) o niebla completa
				float max_density = mix(fog_opacity, shroud_opacity, explored * (1.0 - current_vision));
				optical_fog = min(optical_fog, max_density);

				if (optical_fog > 0.003) {
					// --- PALETA DE COLOR DE LA NIEBLA ---
					// De sombra densa a crestas de niebla iluminadas por la atmósfera
					vec3 fog_palette = mix(fog_color_dark, fog_color_mid, smoothstep(0.22, 0.62, cloud_structure));
					fog_palette      = mix(fog_palette, fog_color_light, smoothstep(0.55, 0.90, cloud_layer1) * 0.45);
					fog_palette      = mix(fog_palette, swamp_tint, cloud_structure * swamp_mix);

					// Zonas exploradas en memoria: tono más frío y diáfano
					vec3 explored_tint  = mix(fog_palette, vec3(0.60, 0.62, 0.65), 0.35);
					vec3 target_fog_col = mix(fog_palette, explored_tint, explored * (1.0 - current_vision));

					// --- DISPERSIÓN ATMOSFÉRICA & DESATURACIÓN ---
					// La niebla quita la saturación y el contraste del fondo
					float lum = dot(screen_color, vec3(0.299, 0.587, 0.114));
					vec3 desaturated = mix(screen_color, vec3(lum), fog_desaturate * optical_fog);

					// Mezcla con el velo de niebla
					final_color = mix(desaturated, target_fog_col, optical_fog);

					// Relieve tridimensional suave de nubes y partículas en suspensión
					final_color += (cloud_structure - 0.5) * 0.075 * optical_fog;
					final_color += (particles - 0.5) * 0.030 * optical_fog;

					final_color = clamp(final_color, vec3(0.0), vec3(1.0));
				}
			}
		}
	}

	ALBEDO = final_color;
}

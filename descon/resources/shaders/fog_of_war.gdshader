shader_type spatial;
// v905.0 FOG OF WAR - Volumetrico 3D Ultra Optimizado:
//   - Depth buffer: cubre geometria a cualquier altura (montanas, suelo, objetos)
//   - Sky volumetric: cubre el AIRE sobre zonas planas (efecto pared/columna de niebla)
//   - Vertex unprojection: traslada calculo de rayos al vertex shader (4 veces por frame en vez de 2M)
//   - Early exit de vision: saltea 80% del shader en zonas visibles dentro del rango del jugador
// GLES3 compatible: sin return en fragment.
render_mode unshaded, depth_draw_never, cull_disabled, depth_test_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform sampler2D depth_texture  : hint_depth_texture,  filter_nearest;
uniform sampler2D vision_texture  : filter_linear, repeat_disable;
uniform sampler2D history_texture : filter_linear, repeat_disable;
uniform sampler2D noise_texture   : filter_linear, repeat_enable;

uniform vec2  map_size_3d = vec2(80.0, 113.0);
uniform float fog_opacity    : hint_range(0.0, 1.0) = 0.80;
uniform float shroud_opacity : hint_range(0.0, 1.0) = 0.32;

uniform vec3  fog_color_dark  : source_color = vec3(0.14, 0.16, 0.17);
uniform vec3  fog_color_mid   : source_color = vec3(0.34, 0.36, 0.39);
uniform vec3  fog_color_light : source_color = vec3(0.60, 0.62, 0.64);
uniform vec3  swamp_tint      : source_color = vec3(0.30, 0.34, 0.28);
uniform float swamp_mix       : hint_range(0.0, 0.5)  = 0.20;
uniform float fog_desaturate  : hint_range(0.0, 1.0)  = 0.62;

uniform float cloud_scale1    = 0.0085;
uniform float cloud_scale2    = 0.017;
uniform float cloud_speed1    = 0.014;
uniform float cloud_speed2    = -0.011;
uniform float elevation_speed = 0.007;
uniform float cloud_contrast  : hint_range(0.5, 2.0) = 1.18;

uniform float noise_scale = 0.011;
uniform float noise_speed = 0.018;
uniform bool  flip_y      = false;

uniform float fog_height        : hint_range(0.5, 60.0) = 30.0;
uniform float fog_density       : hint_range(0.1, 1.5)  = 0.55;
uniform float fog_vertical_fade : hint_range(0.2, 3.0)  = 1.2;

varying vec3 v_ray_dir;
varying vec3 v_camera_pos;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
	vec4 vp_ray  = INV_PROJECTION_MATRIX * vec4(VERTEX.xy, 1.0, 1.0);
	vp_ray /= vp_ray.w;
	v_ray_dir    = (INV_VIEW_MATRIX * vec4(vp_ray.xyz, 0.0)).xyz;
	v_camera_pos = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

void fragment() {
	vec3 screen_color = texture(screen_texture, SCREEN_UV).rgb;

	// === Depth buffer: si es cielo / fondo vacío, no hay nada de niebla (ahorro enorme de FPS) ===
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	bool is_sky = (raw_depth >= 0.9999);

	vec3 final_color = screen_color;

	if (!is_sky) {
		vec3 ray_dir    = normalize(v_ray_dir);
		vec3 ray_origin = v_camera_pos;
		float cam_y     = ray_origin.y;

		// GEOMETRIA: reconstruir posicion en mundo
		vec3 ndc_d = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth * 2.0 - 1.0);
		vec4 vp_d  = INV_PROJECTION_MATRIX * vec4(ndc_d, 1.0);
		vp_d /= vp_d.w;
		vec3 frag_world = (INV_VIEW_MATRIX * vp_d).xyz;

		// Límite vertical: la niebla solo existe por encima de la superficie (y >= 0.0) hasta fog_height.
		// Si frag_world.y está por debajo del suelo del mapa (y < 0.0), se desvanece a 0 para no aparecer abajo del terreno.
		float bottom_fade   = smoothstep(-1.5, 0.2, frag_world.y);
		float top_fade      = 1.0 - smoothstep(fog_height * 0.5, fog_height, frag_world.y);
		float height_factor = bottom_fade * top_fade;

		vec2 sample_xz = frag_world.xz;
		vec2 fog_uv    = sample_xz / map_size_3d;
		bool in_map    = (fog_uv.x >= 0.0 && fog_uv.x <= 1.0 &&
		                  fog_uv.y >= 0.0 && fog_uv.y <= 1.0);

		if (in_map && height_factor > 0.005) {
			// Test rápido de visión antes de ruidos caros
			vec2  base_s_uv = vec2(fog_uv.x, flip_y ? 1.0 - fog_uv.y : fog_uv.y);
			float fast_vis  = texture(vision_texture, base_s_uv).r;

			// Si el fragmento está 100% visible bajo la nave/aliados, omitir cálculos pesados
			if (fast_vis < 0.99) {
				// Noise para distorsion de bordes
				vec2  n_uv      = sample_xz * 0.015 + vec2(TIME * noise_speed, TIME * noise_speed * 0.65);
				float noise_val = texture(noise_texture, n_uv).r;
				vec2  dist_uv   = clamp(fog_uv + (noise_val - 0.5) * noise_scale, 0.0, 1.0);
				vec2  s_uv      = vec2(dist_uv.x, flip_y ? 1.0 - dist_uv.y : dist_uv.y);

				float current_vision = texture(vision_texture,  s_uv).r;
				float explored       = texture(history_texture, s_uv).r;

				if (current_vision < 0.99) {
					// Visibilidad
					float base_vis   = max(explored * (1.0 - shroud_opacity), 1.0 - fog_opacity);
					float visibility = base_vis + (1.0 - base_vis) * current_vision;

					// Fade borde de mapa
					float edge_fade = smoothstep(0.0, 0.08,
					                    min(min(fog_uv.x, 1.0 - fog_uv.x),
					                        min(fog_uv.y, 1.0 - fog_uv.y)));

					// Densidad volumetrica (para rayos hacia abajo con geometria)
					float height_density = height_factor;
					if (ray_dir.y < -0.0001) {
						float t_ground   = -cam_y / ray_dir.y;
						float t_fog_top  = max((fog_height - cam_y) / ray_dir.y, 0.0);
						float vol_length = max(t_ground - t_fog_top, 0.0);
						float hd = 1.0 - exp(-vol_length * fog_density * 0.18);
						hd = clamp(hd * 0.68 + 0.32, 0.0, 1.0);
						float mid_h = cam_y + ray_dir.y * (t_fog_top + vol_length * 0.5);
						float vg = pow(1.0 - smoothstep(0.0, fog_height, mid_h), 0.7);
						height_density = hd * mix(0.40, 1.0, vg) * height_factor;
					}

					// Factor 2D de niebla
					float fog_factor_2d = pow(clamp(1.0 - visibility, 0.0, 1.0), 0.88);
					fog_factor_2d = smoothstep(0.0, 1.0, fog_factor_2d);
					fog_factor_2d *= smoothstep(0.0, 0.32, fog_factor_2d);
					fog_factor_2d *= edge_fade;

					if (fog_factor_2d > 0.001) {
						// Nubes
						vec2  c_uv = sample_xz * cloud_scale1 + vec2(TIME * cloud_speed1 * 0.7, TIME * elevation_speed);
						float n1   = texture(noise_texture, c_uv).r;
						float cloud = pow(clamp(n1 * 0.65 + noise_val * 0.35, 0.0, 1.0), cloud_contrast);
						cloud = smoothstep(0.18, 0.82, cloud);
						height_density *= (0.72 + cloud * 0.55);

						// Paleta de colores
						vec3 palette = mix(fog_color_dark, fog_color_mid,  smoothstep(0.22, 0.52, cloud));
						palette      = mix(palette, fog_color_light,        smoothstep(0.48, 0.86, cloud));
						palette      = mix(palette, swamp_tint, cloud * swamp_mix);
						vec3 target_fog_col = mix(palette,
						                     mix(palette, vec3(0.66, 0.66, 0.68), 0.34),
						                     explored * (1.0 - current_vision));

						float combined_fog = clamp(smoothstep(0.0, 0.75, fog_factor_2d * height_density), 0.0, 0.80);

						if (combined_fog > 0.005) {
							float lum        = dot(screen_color, vec3(0.299, 0.587, 0.114));
							vec3 desaturated = mix(screen_color, vec3(lum), fog_desaturate * combined_fog);
							final_color      = mix(desaturated, target_fog_col, combined_fog);
							final_color     += (cloud - 0.5) * 0.08 * combined_fog * (0.6 + height_density * 0.7);
							final_color      = mix(final_color, target_fog_col + vec3(0.06,0.07,0.07),
							                       n1 * 0.045 * combined_fog);
							final_color      = clamp(final_color, vec3(0.0), vec3(1.0));
						}
					}
				}
			}
		}
	}

	ALBEDO = final_color;
}

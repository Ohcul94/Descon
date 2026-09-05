shader_type spatial;
// v904.0 FOG OF WAR - Volumetrico 3D completo:
//   - Depth buffer: cubre geometria a cualquier altura (montanas, suelo, objetos)
//   - Sky volumetric: cubre el AIRE sobre zonas planas (efecto pared/columna de niebla)
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

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec3 screen_color = texture(screen_texture, SCREEN_UV).rgb;

	// === Reconstruir rayo de vista ===
	vec3 ndc_ray = vec3(SCREEN_UV * 2.0 - 1.0, 1.0);
	vec4 vp_ray  = INV_PROJECTION_MATRIX * vec4(ndc_ray, 1.0);
	vp_ray /= vp_ray.w;
	vec3 ray_dir    = normalize((INV_VIEW_MATRIX * vec4(vp_ray.xyz, 0.0)).xyz);
	vec3 ray_origin = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float cam_y = ray_origin.y;

	// === Depth buffer: posicion 3D real del fragmento ===
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	bool is_sky = (raw_depth >= 0.9999);

	vec3 ndc_d = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth * 2.0 - 1.0);
	vec4 vp_d  = INV_PROJECTION_MATRIX * vec4(ndc_d, 1.0);
	vp_d /= vp_d.w;
	vec3 frag_world = (INV_VIEW_MATRIX * vp_d).xyz;

	// Direccion horizontal del rayo (para muestreo de cielo)
	vec2 look_xz = (length(ray_dir.xz) > 0.001) ? normalize(ray_dir.xz) : vec2(1.0, 0.0);

	// === Punto de muestreo primario en el mapa ===
	vec2 sample_xz;
	float height_factor;

	if (!is_sky) {
		// GEOMETRIA: usar la posicion XZ real del fragmento (montana, suelo, etc.)
		sample_xz    = frag_world.xz;
		height_factor = 1.0 - smoothstep(0.0, fog_height, max(frag_world.y, 0.0));
	} else {
		// CIELO: muestrear a ~28 unidades adelante en XZ (cerca de la frontera de niebla)
		// Clampeado al mapa para no quedar fuera de bounds
		sample_xz    = clamp(ray_origin.xz + look_xz * 28.0, vec2(0.1), map_size_3d - 0.1);
		// Cobertura angular completa: max en horizontal, 0 mirando recto arriba/abajo
		height_factor = 1.0 - smoothstep(0.0, 1.0, abs(ray_dir.y));
	}

	vec2 fog_uv = sample_xz / map_size_3d;
	bool in_map = (fog_uv.x >= 0.0 && fog_uv.x <= 1.0 &&
	               fog_uv.y >= 0.0 && fog_uv.y <= 1.0);

	// ===================================================================
	// Resultados del fog primario — usados tambien en la salida final
	// ===================================================================
	float combined_fog    = 0.0;
	vec3  target_fog_col  = fog_color_dark;
	float cloud_out       = 0.0;
	float hd_out          = 0.0;
	float n1_out          = 0.0;
	float explored_out    = 0.0;

	if (in_map && height_factor > 0.005) {
		// Noise para distorsion de bordes
		vec2  n_uv      = sample_xz * 0.015 + vec2(TIME * noise_speed, TIME * noise_speed * 0.65);
		float noise_val = texture(noise_texture, n_uv).r;
		vec2  dist_uv   = clamp(fog_uv + (noise_val - 0.5) * noise_scale, 0.0, 1.0);
		vec2  s_uv      = vec2(dist_uv.x, flip_y ? 1.0 - dist_uv.y : dist_uv.y);

		float current_vision = texture(vision_texture,  s_uv).r;
		float explored       = texture(history_texture, s_uv).r;
		explored_out = explored;

		// Visibilidad
		float base_vis   = max(explored * (1.0 - shroud_opacity), 1.0 - fog_opacity);
		float visibility = base_vis + (1.0 - base_vis) * current_vision;

		// Fade borde de mapa
		float edge_fade = smoothstep(0.0, 0.08,
		                    min(min(fog_uv.x, 1.0 - fog_uv.x),
		                        min(fog_uv.y, 1.0 - fog_uv.y)));

		// Densidad volumetrica (para rayos hacia abajo con geometria)
		float height_density = height_factor;
		if (!is_sky && ray_dir.y < -0.0001) {
			float t_ground   = -cam_y / ray_dir.y;
			float t_fog_top  = max((fog_height - cam_y) / ray_dir.y, 0.0);
			float vol_length = max(t_ground - t_fog_top, 0.0);
			float hd = 1.0 - exp(-vol_length * fog_density * 0.18);
			hd = clamp(hd * 0.68 + 0.32, 0.0, 1.0);
			float mid_h = cam_y + ray_dir.y * (t_fog_top + vol_length * 0.5);
			float vg = pow(1.0 - smoothstep(0.0, fog_height, mid_h), 0.7);
			height_density = hd * mix(0.40, 1.0, vg) * height_factor;
		}
		hd_out = height_density;

		// Factor 2D de niebla
		float fog_factor_2d = pow(clamp(1.0 - visibility, 0.0, 1.0), 0.88);
		fog_factor_2d = smoothstep(0.0, 1.0, fog_factor_2d);
		fog_factor_2d *= smoothstep(0.0, 0.32, fog_factor_2d);
		fog_factor_2d *= edge_fade;

		// Nubes
		vec2  c_uv = sample_xz * cloud_scale1 + vec2(TIME * cloud_speed1 * 0.7, TIME * elevation_speed);
		float n1   = texture(noise_texture, c_uv).r;
		float cloud = pow(clamp(n1 * 0.65 + noise_val * 0.35, 0.0, 1.0), cloud_contrast);
		cloud = smoothstep(0.18, 0.82, cloud);
		height_density *= (0.72 + cloud * 0.55);
		cloud_out = cloud;
		n1_out    = n1;

		// Paleta de colores
		vec3 palette = mix(fog_color_dark, fog_color_mid,  smoothstep(0.22, 0.52, cloud));
		palette      = mix(palette, fog_color_light,        smoothstep(0.48, 0.86, cloud));
		palette      = mix(palette, swamp_tint, cloud * swamp_mix);
		target_fog_col = mix(palette,
		                     mix(palette, vec3(0.66, 0.66, 0.68), 0.34),
		                     explored * (1.0 - current_vision));

		combined_fog = clamp(smoothstep(0.0, 0.75, fog_factor_2d * height_density), 0.0, 0.80);
	}

	// ===================================================================
	// VOLUMEN EN CIELO: para TODOS los pixels de cielo que miran hacia la
	// zona de niebla, muestrear tambien a 35 unidades para cubrir el AIRE
	// sobre suelo plano. Esto es lo que da la "pared de niebla" volumetrica.
	// ===================================================================
	if (is_sky) {
		// Segundo muestreo a 35 unidades (mas alla de la frontera de niebla)
		vec2 far_xz  = clamp(ray_origin.xz + look_xz * 35.0, vec2(0.1), map_size_3d - 0.1);
		vec2 far_uv  = far_xz / map_size_3d;
		bool far_ok  = (far_uv.x >= 0.0 && far_uv.x <= 1.0 &&
		                far_uv.y >= 0.0 && far_uv.y <= 1.0);

		if (far_ok) {
			float far_vision   = texture(vision_texture,  far_uv).r;
			float far_explored = texture(history_texture, far_uv).r;
			float far_base     = max(far_explored * (1.0 - shroud_opacity), 1.0 - fog_opacity);
			float far_vis      = far_base + (1.0 - far_base) * far_vision;
			// Factor de fog en este punto del cielo, pesado por angulo horizontal
			float far_fog_amount = (1.0 - far_vis) * height_factor * 0.80;
			// Tomar el mayor de los dos muestreos
			combined_fog = max(combined_fog, far_fog_amount);
			// Si el fog secundario domina, usar su color de target
			if (far_fog_amount > combined_fog * 0.5) {
				float pal_t = far_explored * (1.0 - far_vision);
				target_fog_col = mix(fog_color_dark, mix(fog_color_mid, vec3(0.66,0.66,0.68), 0.34), pal_t);
			}
		}
	}

	// === Aplicar fog final ===
	vec3 final_color = screen_color;

	if (combined_fog > 0.005) {
		float lum        = dot(screen_color, vec3(0.299, 0.587, 0.114));
		vec3 desaturated = mix(screen_color, vec3(lum), fog_desaturate * combined_fog);
		final_color      = mix(desaturated, target_fog_col, combined_fog);
		// Detalles de textura de nube (solo cuando el muestreo primario fue valido)
		if (!is_sky) {
			final_color += (cloud_out - 0.5) * 0.08 * combined_fog * (0.6 + hd_out * 0.7);
			final_color  = mix(final_color, target_fog_col + vec3(0.06,0.07,0.07),
			                   n1_out * 0.045 * combined_fog);
		}
		final_color = clamp(final_color, vec3(0.0), vec3(1.0));
	}

	ALBEDO = final_color;
}

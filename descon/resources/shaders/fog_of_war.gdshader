shader_type spatial;
// v903.0 FOG OF WAR - Depth-buffer based: cubre suelo, montanas y cielo.
// La niebla sube en 3D y tapa TODO lo que este en la zona de niebla a cualquier altura.
// GLES3 compatible: sin return en fragment, usa if/else.
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

// fog_height: altura maxima de la niebla en metros 3D.
// Sube la niebla para que tape montanas y objetos altos en la zona de niebla.
uniform float fog_height        : hint_range(0.5, 60.0) = 30.0;
uniform float fog_density       : hint_range(0.1, 1.5)  = 0.55;
uniform float fog_vertical_fade : hint_range(0.2, 3.0)  = 1.2;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec3 screen_color = texture(screen_texture, SCREEN_UV).rgb;

	// === Reconstruir rayo de vista (para cielo/fallback) ===
	vec3 ndc_ray = vec3(SCREEN_UV * 2.0 - 1.0, 1.0);
	vec4 vp_ray  = INV_PROJECTION_MATRIX * vec4(ndc_ray, 1.0);
	vp_ray /= vp_ray.w;
	vec3 ray_dir    = normalize((INV_VIEW_MATRIX * vec4(vp_ray.xyz, 0.0)).xyz);
	vec3 ray_origin = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float cam_y = ray_origin.y;

	// === Reconstruir posicion 3D real del fragmento desde depth buffer ===
	// Esto incluye montanas, terreno a cualquier altura, etc.
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	bool is_sky = (raw_depth >= 0.9999); // cielo / sin geometria

	vec3 ndc_d = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth * 2.0 - 1.0);
	vec4 vp_d  = INV_PROJECTION_MATRIX * vec4(ndc_d, 1.0);
	vp_d /= vp_d.w;
	vec3 frag_world = (INV_VIEW_MATRIX * vp_d).xyz;

	// === Elegir punto de muestreo en el mapa ===
	// Para geometria real: usar la posicion XZ del fragmento (montana, suelo).
	// Para cielo: proyectar rayo hacia el horizonte de niebla.
	vec2 sample_xz;
	float height_factor;

	if (!is_sky) {
		// Geometria: la niebla usa la posicion XZ real del objeto
		sample_xz = frag_world.xz;
		// Atenuar niebla segun altura del objeto: pleno en suelo, disminuye hacia arriba
		// fog_height grande (30) permite cubrir montanas altas
		height_factor = 1.0 - smoothstep(0.0, fog_height, max(frag_world.y, 0.0));
	} else {
		// Cielo: proyectar rayo en la direccion horizontal para detectar zona de niebla
		if (ray_dir.y < -0.0001) {
			// Rayo hacia abajo: proyectar al plano y=0
			float t_ground = -cam_y / ray_dir.y;
			sample_xz = ray_origin.xz + ray_dir.xz * t_ground;
		} else {
			// Rayo horizontal o hacia arriba: usar punto adelante en XZ
			vec2 look_xz = length(ray_dir.xz) > 0.001 ? normalize(ray_dir.xz) : vec2(1.0, 0.0);
			sample_xz = ray_origin.xz + look_xz * (length(map_size_3d) * 0.6);
		}
		// El cielo se niebla solo cerca del horizonte (atenuar segun angulo vertical)
		height_factor = smoothstep(0.5, 0.0, abs(ray_dir.y));
	}

	vec2 fog_uv = sample_xz / map_size_3d;
	bool in_map = (fog_uv.x >= 0.0 && fog_uv.x <= 1.0 &&
	               fog_uv.y >= 0.0 && fog_uv.y <= 1.0);

	vec3 final_color = screen_color;

	if (in_map && height_factor > 0.005) {
		// === Noise para distorsion de bordes ===
		vec2 n_uv = sample_xz * 0.015 + vec2(TIME * noise_speed, TIME * noise_speed * 0.65);
		float noise_val = texture(noise_texture, n_uv).r;
		vec2 dist_uv = clamp(fog_uv + (noise_val - 0.5) * noise_scale, 0.0, 1.0);
		vec2 s_uv = vec2(dist_uv.x, flip_y ? 1.0 - dist_uv.y : dist_uv.y);

		float current_vision = texture(vision_texture,  s_uv).r;
		float explored       = texture(history_texture, s_uv).r;

		float base_vis   = max(explored * (1.0 - shroud_opacity), 1.0 - fog_opacity);
		float visibility = base_vis + (1.0 - base_vis) * current_vision;

		// Fade de bordes del mapa
		float edge_fade = smoothstep(0.0, 0.08, min(min(fog_uv.x, 1.0 - fog_uv.x),
		                                             min(fog_uv.y, 1.0 - fog_uv.y)));

		// Densidad volumetrica: para rayos hacia abajo con geometria, usar vol_length real
		float height_density = height_factor;
		if (!is_sky && ray_dir.y < -0.0001) {
			float t_ground  = -cam_y / ray_dir.y;
			float t_fog_top = max((fog_height - cam_y) / ray_dir.y, 0.0);
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

		// Nubes (1 muestra + reutilizacion de noise_val)
		vec2 c_uv = sample_xz * cloud_scale1 + vec2(TIME * cloud_speed1 * 0.7, TIME * elevation_speed);
		float n1  = texture(noise_texture, c_uv).r;
		float cloud = pow(clamp(n1 * 0.65 + noise_val * 0.35, 0.0, 1.0), cloud_contrast);
		cloud = smoothstep(0.18, 0.82, cloud);
		height_density *= (0.72 + cloud * 0.55);

		// Paleta de colores (identica al original)
		vec3 palette = mix(fog_color_dark, fog_color_mid,  smoothstep(0.22, 0.52, cloud));
		palette      = mix(palette, fog_color_light,        smoothstep(0.48, 0.86, cloud));
		palette      = mix(palette, swamp_tint, cloud * swamp_mix);
		vec3 target_fog = mix(palette,
		                      mix(palette, vec3(0.66, 0.66, 0.68), 0.34),
		                      explored * (1.0 - current_vision));

		float combined_fog = clamp(smoothstep(0.0, 0.75, fog_factor_2d * height_density), 0.0, 0.80);

		float lum        = dot(screen_color, vec3(0.299, 0.587, 0.114));
		vec3 desaturated = mix(screen_color, vec3(lum), fog_desaturate * combined_fog);
		final_color  = mix(desaturated, target_fog, combined_fog);
		final_color += (cloud - 0.5) * 0.08 * combined_fog * (0.6 + height_density * 0.7);
		final_color  = mix(final_color, target_fog + vec3(0.06, 0.07, 0.07), n1 * 0.045 * combined_fog);
		final_color  = clamp(final_color, vec3(0.0), vec3(1.0));
	}

	ALBEDO = final_color;
}

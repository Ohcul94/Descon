shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, depth_test_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform sampler2D vision_texture : filter_linear, repeat_disable;
uniform sampler2D history_texture : filter_linear, repeat_disable;
uniform sampler2D noise_texture : filter_linear, repeat_enable;

uniform vec2 map_size_3d = vec2(80.0, 113.0);

// v802.0 NIEBLA PANTANO VOLUMÉTRICA - 80% opacidad, 3-4m elevación, degradé suave sin línea dura
uniform float fog_opacity : hint_range(0.0, 1.0) = 0.80;
uniform float shroud_opacity : hint_range(0.0, 1.0) = 0.32;

uniform vec3 fog_color_dark : source_color = vec3(0.14, 0.16, 0.17);
uniform vec3 fog_color_mid : source_color = vec3(0.34, 0.36, 0.39);
uniform vec3 fog_color_light : source_color = vec3(0.60, 0.62, 0.64);
uniform vec3 swamp_tint : source_color = vec3(0.30, 0.34, 0.28);
uniform float swamp_mix : hint_range(0.0, 0.5) = 0.20;
uniform float fog_desaturate : hint_range(0.0, 1.0) = 0.62;

uniform float cloud_scale1 = 0.0085;
uniform float cloud_scale2 = 0.017;
uniform float cloud_speed1 = 0.014;
uniform float cloud_speed2 = -0.011;
uniform float elevation_speed = 0.007;
uniform float cloud_contrast : hint_range(0.5, 2.0) = 1.18;

uniform float noise_scale = 0.011;
uniform float noise_speed = 0.018;
uniform bool flip_y = false;

// Volumetría vertical (metros 3D)
uniform float fog_height : hint_range(0.5, 8.0) = 3.8;
uniform float fog_density : hint_range(0.1, 1.5) = 0.55;
uniform float fog_vertical_fade : hint_range(0.2, 3.0) = 1.2;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec3 screen_color = texture(screen_texture, SCREEN_UV).rgb;

	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, 1.0);
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos /= view_pos.w;
	
	vec3 ray_dir = (INV_VIEW_MATRIX * vec4(view_pos.xyz, 0.0)).xyz;
	ray_dir = normalize(ray_dir);
	
	vec3 ray_origin = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

	if (ray_dir.y < -0.0001) {
		float t_ground = -ray_origin.y / ray_dir.y;
		vec3 world_pos = ray_origin + ray_dir * t_ground;
		
		vec2 fog_uv = world_pos.xz / map_size_3d;
		
		if (fog_uv.x >= 0.0 && fog_uv.x <= 1.0 && fog_uv.y >= 0.0 && fog_uv.y <= 1.0) {
			vec2 base_noise_uv = world_pos.xz * 0.015 + vec2(TIME * noise_speed, TIME * noise_speed * 0.65);
			float noise_val = texture(noise_texture, base_noise_uv).r;
			vec2 distorted_uv = clamp(fog_uv + (noise_val - 0.5) * noise_scale, 0.0, 1.0);
			
			vec2 sample_uv = vec2(distorted_uv.x, flip_y ? 1.0 - distorted_uv.y : distorted_uv.y);
			
			float current_vision  = texture(vision_texture,  sample_uv).r;
			float explored        = texture(history_texture, sample_uv).r;
			
			// Calcular visibilidad base del terreno (penumbra si está explorado, oscuro si no)
			float base_vis = max(explored * (1.0 - shroud_opacity), 1.0 - fog_opacity);
			
			// Aplicar la visión de la nave de forma suave. 
			// En lugar de usar max() que corta el degradado creando un círculo duro,
			// sumamos la visión progresivamente. Esto permite que el borde del rango
			// de visión se desvanezca de a poco de forma ultra suave.
			float visibility = base_vis + (1.0 - base_vis) * current_vision;
			
			// --- DIFUMINADO SUAVE DE BORDES Y HORIZONTE ---
			float edge_dist_x = min(fog_uv.x, 1.0 - fog_uv.x);
			float edge_dist_y = min(fog_uv.y, 1.0 - fog_uv.y);
			float min_edge = min(edge_dist_x, edge_dist_y);
			float edge_fade = smoothstep(0.0, 0.08, min_edge);
			
			// --- VOLUMEN VERTICAL (Analítico original) ---
			float cam_y = ray_origin.y;
			float t_top = (fog_height - cam_y) / ray_dir.y;
			float fog_entry = max(t_top, 0.0);
			float fog_exit = t_ground;
			float vol_length = max(fog_exit - fog_entry, 0.0);
			
			// Densidad base volumétrica
			float height_density = 1.0 - exp(-vol_length * fog_density * 0.18);
			height_density = clamp(height_density * 0.68 + 0.32, 0.0, 1.0);
			
			// El desvanecimiento suave vertical arreglado (que quitaba la malla plana)
			float mid_height = cam_y + ray_dir.y * (fog_entry + vol_length * 0.5);
			float vertical_gradient = 1.0 - smoothstep(0.0, fog_height, mid_height);
			vertical_gradient = pow(vertical_gradient, 0.7);
			height_density *= mix(0.40, 1.0, vertical_gradient);
			
			// Factor de niebla
			float fog_factor_2d = 1.0 - visibility;
			fog_factor_2d = pow(clamp(fog_factor_2d, 0.0, 1.0), 0.88);
			fog_factor_2d = smoothstep(0.0, 1.0, fog_factor_2d);
			
			// Transición suave original restaurada
			float start_feather = smoothstep(0.0, 0.32, fog_factor_2d);
			fog_factor_2d *= start_feather;
			fog_factor_2d *= edge_fade;
			
			// NUBES OPTIMIZADAS (1 sola muestra en lugar de 3)
			vec2 cloud_uv = world_pos.xz * cloud_scale1 + vec2(TIME * cloud_speed1 * 0.7, TIME * elevation_speed);
			float n1 = texture(noise_texture, cloud_uv).r;
			// Usamos el noise_val (ya sampleado arriba) como segunda capa simulada
			float cloud = n1 * 0.65 + noise_val * 0.35;
			
			cloud = pow(clamp(cloud, 0.0, 1.0), cloud_contrast);
			cloud = smoothstep(0.18, 0.82, cloud);
			// Ondas pesadas con sin/cos eliminadas para optimizar
			
			height_density *= (0.72 + cloud * 0.55);
			
			vec3 palette = mix(fog_color_dark, fog_color_mid, smoothstep(0.22, 0.52, cloud));
			palette = mix(palette, fog_color_light, smoothstep(0.48, 0.86, cloud));
			palette = mix(palette, swamp_tint, cloud * swamp_mix);
			
			vec3 unexploredFog = palette;
			vec3 exploredFog = mix(palette, vec3(0.66, 0.66, 0.68), 0.34);
			float is_explored = explored;
			vec3 target_fog = mix(unexploredFog, exploredFog, is_explored * (1.0 - current_vision));
			
			// Mezclar
			float combined_fog = fog_factor_2d * height_density;
			combined_fog = smoothstep(0.0, 0.75, combined_fog);
			combined_fog = clamp(combined_fog, 0.0, 0.80);
			
			float lum = dot(screen_color, vec3(0.299, 0.587, 0.114));
			vec3 desaturated = mix(screen_color, vec3(lum), fog_desaturate * combined_fog);
			
			vec3 final_color = mix(desaturated, target_fog, combined_fog);
			final_color += (cloud - 0.5) * 0.08 * combined_fog * (0.6 + height_density * 0.7);
			final_color = mix(final_color, target_fog + vec3(0.06, 0.07, 0.07), n1 * 0.045 * combined_fog);
			// Extra noise decay removed for performance
			
			ALBEDO = clamp(final_color, vec3(0.0), vec3(1.0));
		} else {
			ALBEDO = screen_color;
		}
	} else {
		ALBEDO = screen_color;
	}
}

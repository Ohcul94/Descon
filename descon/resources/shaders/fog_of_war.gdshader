shader_type spatial;
// v935.0 FOG OF WAR - Volumetría Atmosférica Real + Cielo Despejado:
// - Quad en cámara (cobertura total 100% en cualquier mapa y resolución).
// - Si el rayo apunta al cielo sobre las montañas: DESCARTE TOTAL (estrellas y cúpula 100% limpias).
// - En valles y huecos entre montañas (horizonte): calcula el espesor de la bruma atmosférica en el aire, rellenando el desfiladero sin agujeros negros.
// - En montañas y suelo: extinción volumétrica Beer-Lambert real según la distancia recorrida en el estrato de niebla (no queda pegada como aerosol).
// - Compatible con GLES3 y Forward+ (120 FPS sin caídas).
render_mode unshaded, depth_draw_never, cull_disabled;

uniform sampler2D screen_texture  : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture   : hint_depth_texture, filter_nearest;
uniform sampler2D vision_texture  : filter_linear, repeat_disable;
uniform sampler2D history_texture : filter_linear, repeat_disable;
uniform sampler2D noise_texture   : filter_linear, repeat_enable;

uniform vec2  map_offset_3d;
uniform vec2  map_size_3d;
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
	vec3 ray_dir    = normalize(v_ray_dir);
	vec3 ray_origin = v_camera_pos;
	float cam_y     = ray_origin.y;

	// Techo y piso del estrato volumétrico de niebla en el mundo
	float fog_floor   = -6.0;
	float fog_ceiling = fog_height;

	// 1. Reconstrucción de la profundidad de escena
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	vec3 solid_world = vec3(0.0);
	bool has_solid   = false;
	float t_solid    = 99999.0;

	if (raw_depth < 0.9999 && raw_depth > 0.0001) {
		vec3 ndc_d = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth * 2.0 - 1.0);
		vec4 vp_d  = INV_PROJECTION_MATRIX * vec4(ndc_d, 1.0);
		vp_d /= vp_d.w;
		vec3 cand = (INV_VIEW_MATRIX * vp_d).xyz;
		// Rango vertical de geometría válida en el mapa (-12m a 50m)
		if (cand.y >= -12.0 && cand.y <= 50.0) {
			solid_world = cand;
			has_solid   = true;
			t_solid     = length(solid_world - ray_origin);
		}
	}

	// 2. Si no hay geometría sólida (cielo o hueco entre montañas):
	if (!has_solid) {
		// Si el rayo apunta hacia el cielo (por encima del horizonte de niebla):
		// DESCARTE INMEDIATO -> El cielo y las estrellas quedan 100% nítidos y libres.
		if (ray_dir.y >= -0.015) {
			discard;
		}
		
		// El rayo apunta hacia abajo o hacia el horizonte bajo (hueco / desfiladero entre montañas)
		// Simular el trayecto a través de la masa de niebla hacia el fondo
		float t_ground = (0.0 - cam_y) / ray_dir.y;
		t_solid = min(t_ground, 180.0);
		solid_world = ray_origin + ray_dir * t_solid;
	}

	// 3. Cálculo volumétrico de entrada y salida del estrato de niebla [fog_floor, fog_ceiling]
	float t_enter = 0.0;
	if (cam_y > fog_ceiling) {
		// La cámara está por encima del estrato de niebla
		if (ray_dir.y >= -0.0001) {
			discard; // Apunta hacia arriba, nunca entra en la niebla
		}
		t_enter = (fog_ceiling - cam_y) / ray_dir.y;
	} else if (cam_y < fog_floor) {
		// La cámara está por debajo del suelo
		if (ray_dir.y <= 0.0001) {
			discard;
		}
		t_enter = (fog_floor - cam_y) / ray_dir.y;
	}

	t_enter = max(0.0, t_enter);
	float t_end = min(t_solid, t_enter + 130.0);
	float fog_path_length = max(0.0, t_end - t_enter);

	if (fog_path_length <= 0.05) {
		discard;
	}

	// 4. Punto de muestreo para UV del mapa de visión y texturas de ruido
	vec3 sample_world = has_solid ? solid_world : (ray_origin + ray_dir * mix(t_enter, t_end, 0.5));
	vec2 sample_xz    = sample_world.xz;
	vec2 fog_uv       = (sample_xz - map_offset_3d) / map_size_3d;

	// Si está en el horizonte lejano fuera del mapa, sujetar UV para que no queden huecos
	vec2 clamped_uv = clamp(fog_uv, vec2(0.0), vec2(1.0));
	vec2 s_uv       = vec2(clamped_uv.x, flip_y ? 1.0 - clamped_uv.y : clamped_uv.y);

	// Suavizado del borde del mapa (fade en el confín)
	float edge_dist = min(min(fog_uv.x, 1.0 - fog_uv.x), min(fog_uv.y, 1.0 - fog_uv.y));
	float edge_fade = smoothstep(-0.12, 0.04, edge_dist);
	if (edge_fade <= 0.001) {
		discard;
	}

	// 5. Muestreo de Visión y Memoria
	float current_vision = texture(vision_texture, s_uv).r;
	if (current_vision >= 0.999) {
		discard; // Área totalmente despejada por la visión del jugador
	}
	float explored = texture(history_texture, s_uv).r;

	// 6. Variación atmosférica suave y homogénea (sin grano ni ruido de aerosol)
	vec2 c_uv1 = sample_xz * cloud_scale1 + vec2(TIME * cloud_speed1, TIME * elevation_speed);
	float cloud_layer1 = texture(noise_texture, c_uv1).r;

	vec2 c_uv2 = sample_xz * cloud_scale2 + vec2(TIME * cloud_speed2, -TIME * cloud_speed1 * 0.5);
	float cloud_layer2 = texture(noise_texture, c_uv2).r;

	float cloud_structure = mix(cloud_layer1, cloud_layer2, 0.40);

	// 7. Atenuación vertical orgánica (copas de nubes suaves con el viento)
	float top_variation = (cloud_layer1 * 0.60 + cloud_layer2 * 0.40 - 0.5) * (fog_height * 0.35);
	float effective_top = max(fog_height + top_variation, 6.0);
	float bottom_fade   = smoothstep(fog_floor, fog_floor + 2.5, sample_world.y);
	float top_fade      = 1.0 - smoothstep(effective_top * 0.35, effective_top, sample_world.y);
	float vertical_factor = bottom_fade * top_fade;

	// 8. Visibilidad y extinción física Beer-Lambert en el volumen
	float base_vis   = max(explored * (1.0 - shroud_opacity), 1.0 - fog_opacity);
	float visibility = base_vis + (1.0 - base_vis) * current_vision;
	float raw_fog    = clamp(1.0 - visibility, 0.0, 1.0);
	float fog_gradient = smoothstep(0.0, 0.95, raw_fog) * edge_fade;

	float billow_mod = mix(0.92, 1.08, cloud_structure);
	
	// ¡VOLUMETRÍA REAL!: La densidad óptica escala con el espesor de la bruma atravesada
	float path_factor = clamp(fog_path_length * 0.045, 0.12, 1.0);
	float optical_depth = fog_gradient * billow_mod * vertical_factor * path_factor * fog_density * 3.5;
	float optical_fog = 1.0 - exp(-optical_depth);
	optical_fog = clamp(optical_fog, 0.0, 1.0);

	float max_density = mix(fog_opacity, shroud_opacity, explored * (1.0 - current_vision));
	optical_fog = min(optical_fog, max_density);

	if (optical_fog <= 0.005) {
		discard;
	}

	// 9. Paleta de colores atmosférica (alineada con WorldEnvironment)
	vec3 fog_palette = mix(fog_color_dark, fog_color_mid, smoothstep(0.25, 0.75, cloud_structure));
	fog_palette      = mix(fog_palette, fog_color_light, pow(cloud_layer1, 3.0) * 0.25);
	fog_palette      = mix(fog_palette, swamp_tint, cloud_structure * swamp_mix);

	vec3 explored_tint  = mix(fog_palette, vec3(0.18, 0.20, 0.23), 0.35);
	vec3 target_fog_col = mix(fog_palette, explored_tint, explored * (1.0 - current_vision));

	// 10. Desaturación y dispersión sobre el color de pantalla
	vec3 screen_color = texture(screen_texture, SCREEN_UV).rgb;
	float lum = dot(screen_color, vec3(0.299, 0.587, 0.114));
	vec3 desaturated = mix(screen_color, vec3(lum), fog_desaturate * optical_fog);

	vec3 final_color = mix(desaturated, target_fog_col, optical_fog);

	ALBEDO = clamp(final_color, vec3(0.0), vec3(1.0));
}

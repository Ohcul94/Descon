shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, depth_test_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform sampler2D vision_texture : filter_linear, repeat_disable;
uniform sampler2D history_texture : filter_linear, repeat_disable;
uniform sampler2D noise_texture : filter_linear, repeat_enable;

uniform vec2 map_size_3d = vec2(80.0, 113.0);
uniform float fog_opacity : hint_range(0.0, 1.0) = 0.92;
uniform float shroud_opacity : hint_range(0.0, 1.0) = 0.55;
uniform float noise_scale = 0.012;
uniform float noise_speed = 0.025;
uniform bool flip_y = false;

void vertex() {
	// Forzar el quad a ocupar toda la pantalla en NDC
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec3 screen_color = texture(screen_texture, SCREEN_UV).rgb;

	// Reconstruir la dirección del rayo de la cámara en el espacio del mundo sin invertir Y
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, 1.0);
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos /= view_pos.w;
	
	vec3 ray_dir = (INV_VIEW_MATRIX * vec4(view_pos.xyz, 0.0)).xyz;
	ray_dir = normalize(ray_dir);
	
	// Usar la matriz de vista inversa para la posición de la cámara (evita bugs de GLES3)
	vec3 ray_origin = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

	// Intersección del rayo con el plano de juego Y = 0
	if (ray_dir.y < -0.0001) {
		float t = -ray_origin.y / ray_dir.y;
		vec3 world_pos = ray_origin + ray_dir * t;
		
		// UV de la niebla mapeada al tamaño del mapa en 3D
		vec2 fog_uv = world_pos.xz / map_size_3d;
		
		if (fog_uv.x >= 0.0 && fog_uv.x <= 1.0 && fog_uv.y >= 0.0 && fog_uv.y <= 1.0) {
			// Distorsión del borde con ruido animado (bruma espacial)
			vec2 noise_uv = world_pos.xz * 0.02 + vec2(TIME * noise_speed, TIME * noise_speed * 0.7);
			float noise_val = texture(noise_texture, noise_uv).r;
			vec2 distorted_uv = clamp(fog_uv + (noise_val - 0.5) * noise_scale, 0.0, 1.0);
			
			// Determinar si es necesario el volteo vertical de la textura del Viewport
			vec2 sample_uv = vec2(distorted_uv.x, flip_y ? 1.0 - distorted_uv.y : distorted_uv.y);
			
			float current_vision  = texture(vision_texture,  sample_uv).r;
			float explored        = texture(history_texture, sample_uv).r;
			
			// Visión activa → sin niebla / Explorado → penumbra / Sin explorar → oscuro
			float visibility = max(current_vision, explored * (1.0 - shroud_opacity));
			visibility = max(visibility, 1.0 - fog_opacity);
			
			// --- EFECTO DE HUMO VOLUMÉTRICO SUAVE ---
			// 1. Difuminar suavemente la niebla hacia los bordes del mapa para ver el exterior
			float edge_dist_x = min(fog_uv.x, 1.0 - fog_uv.x);
			float edge_dist_y = min(fog_uv.y, 1.0 - fog_uv.y);
			float min_edge = min(edge_dist_x, edge_dist_y);
			float edge_fade = smoothstep(0.0, 0.05, min_edge); // 0.0 en borde exacto, 1.0 hacia adentro
			
			// 2. Difuminar suavemente la niebla en la altura (horizonte) para objetos altos
			float horizon_fade = smoothstep(0.0, 0.15, -ray_dir.y); // 0.0 en horizonte, 1.0 hacia abajo
			
			// Interpolar de regreso a 1.0 (sin niebla) en los bordes y horizonte
			float total_fade = min(edge_fade, horizon_fade);
			visibility = mix(1.0, visibility, total_fade);
			
			ALBEDO = screen_color * visibility;
		} else {
			// Fuera del área de juego: dejar ver completamente las estructuras y montañas exteriores
			ALBEDO = screen_color;
		}
	} else {
		// Rayos horizontales o hacia arriba: dejar ver las cimas de estructuras altas y cielo
		ALBEDO = screen_color;
	}
}

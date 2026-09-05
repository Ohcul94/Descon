shader_type spatial;
// Niebla volumetrica 3D del Fog of War - v1.0
// Vive como MeshInstance3D (BoxMesh) en el mundo. La caja abarca todo el mapa
// en XZ y va desde y=0 hasta fog_height metros.
// Esto le da "gordura" 3D visible en el horizonte, igual que la bomba de humo.
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Texturas del FOW (compartidas con el post-process quad)
uniform sampler2D vision_texture  : filter_linear, repeat_disable;
uniform sampler2D history_texture : filter_linear, repeat_disable;
uniform sampler2D noise_texture   : filter_linear, repeat_enable;

// Dimensiones del mundo 3D (metros). Se pasan desde FogOfWar.gd
uniform vec2 map_size_3d  = vec2(80.0, 113.0);
// Offset del origen del mapa (esquina XZ minima del terreno en coords mundo)
uniform vec2 map_origin_3d = vec2(0.0, 0.0);

// Colores
uniform vec3 fog_color_dark  : source_color = vec3(0.14, 0.16, 0.17);
uniform vec3 fog_color_mid   : source_color = vec3(0.34, 0.36, 0.39);
uniform vec3 fog_color_light : source_color = vec3(0.60, 0.62, 0.64);
uniform vec3 swamp_tint      : source_color = vec3(0.30, 0.34, 0.28);
uniform float swamp_mix      : hint_range(0.0, 0.5) = 0.20;

// Opacidad
uniform float fog_opacity    : hint_range(0.0, 1.0) = 0.78;
uniform float shroud_opacity : hint_range(0.0, 1.0) = 0.30;

// Altura de la caja volumetrica (metros). Debe coincidir con la escala Y del BoxMesh.
uniform float fog_height     : hint_range(0.5, 12.0) = 5.0;
// Fade vertical: que tan rapido se desvanece hacia arriba
uniform float vertical_fade  : hint_range(0.3, 4.0) = 1.8;

// Noise
uniform float noise_scale    : hint_range(0.001, 0.05) = 0.012;
uniform float noise_speed    : hint_range(0.0, 0.1)    = 0.016;
uniform float cloud_scale    : hint_range(0.001, 0.05) = 0.009;
uniform float cloud_speed    : hint_range(0.0, 0.1)    = 0.011;
uniform float cloud_contrast : hint_range(0.5, 2.5)    = 1.15;

void fragment() {
	// Posicion del fragmento en el mundo 3D
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// UV del mapa a partir de posicion mundial
	vec2 fog_uv = (wpos.xz - map_origin_3d) / map_size_3d;

	// Descartar si estamos fuera del mapa
	if (fog_uv.x < 0.0 || fog_uv.x > 1.0 || fog_uv.y < 0.0 || fog_uv.y > 1.0) {
		ALPHA = 0.0;
		return;
	}

	// Fade suave en los bordes del mapa
	float ex = min(fog_uv.x, 1.0 - fog_uv.x);
	float ey = min(fog_uv.y, 1.0 - fog_uv.y);
	float edge_fade = smoothstep(0.0, 0.06, min(ex, ey));

	// Fade vertical: maximo en y=0, cero en y=fog_height
	float norm_y = clamp(wpos.y / fog_height, 0.0, 1.0);
	float vert_alpha = pow(1.0 - norm_y, vertical_fade);

	// Noise base para distorsion UV
	vec2 n_uv = wpos.xz * noise_scale + vec2(TIME * noise_speed, TIME * noise_speed * 0.7);
	float noise_val = texture(noise_texture, n_uv).r;

	// Distorsionar UV del FOW con el noise
	vec2 distorted_uv = clamp(fog_uv + (noise_val - 0.5) * noise_scale * 0.6, 0.0, 1.0);

	// Leer visibilidad
	float current_vision = texture(vision_texture,  distorted_uv).r;
	float explored       = texture(history_texture, distorted_uv).r;

	// Visibilidad combinada
	float base_vis   = max(explored * (1.0 - shroud_opacity), 1.0 - fog_opacity);
	float visibility = base_vis + (1.0 - base_vis) * current_vision;

	// Factor de niebla 2D
	float fog_factor = 1.0 - visibility;
	fog_factor = pow(clamp(fog_factor, 0.0, 1.0), 0.88);
	fog_factor = smoothstep(0.05, 1.0, fog_factor);
	float start_feather = smoothstep(0.0, 0.28, fog_factor);
	fog_factor *= start_feather * edge_fade;

	// Nubes volumetricas (1 sola muestra extra)
	vec2 c_uv = wpos.xz * cloud_scale + vec2(TIME * cloud_speed, -TIME * cloud_speed * 0.6);
	float cloud = texture(noise_texture, c_uv).r;
	cloud = cloud * 0.65 + noise_val * 0.35;
	cloud = pow(clamp(cloud, 0.0, 1.0), cloud_contrast);
	cloud = smoothstep(0.18, 0.82, cloud);

	// Paleta de colores
	vec3 palette = mix(fog_color_dark, fog_color_mid,   smoothstep(0.22, 0.52, cloud));
	palette      = mix(palette, fog_color_light,          smoothstep(0.48, 0.86, cloud));
	palette      = mix(palette, swamp_tint, cloud * swamp_mix);

	vec3 explored_color  = mix(palette, vec3(0.66, 0.66, 0.68), 0.34);
	vec3 fog_color_final = mix(palette, explored_color, explored * (1.0 - current_vision));
	fog_color_final += (cloud - 0.5) * 0.07;
	fog_color_final = clamp(fog_color_final, vec3(0.0), vec3(1.0));

	ALBEDO = fog_color_final;

	// Alpha final: 2D x vertical x clouds
	float cloud_mod  = 0.75 + cloud * 0.50;
	float final_alpha = fog_factor * vert_alpha * cloud_mod;
	ALPHA = clamp(final_alpha, 0.0, 0.80);
}

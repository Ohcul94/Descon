shader_type spatial;
render_mode blend_mix, cull_disabled;

uniform sampler2D u_albedo_tex : source_color;
uniform vec4 u_tint_color : source_color = vec4(0.55, 0.52, 0.48, 1.0);
uniform float u_height_scale : hint_range(0.0, 5.0) = 1.8;
uniform float u_metallic = 0.2;
uniform float u_roughness = 0.85;
uniform vec3 u_emission = vec3(0.04, 0.03, 0.08);
uniform float u_emission_energy = 0.3;
uniform vec2 u_tiling = vec2(5.0, 5.0);

uniform float u_detail_strength : hint_range(0.0, 2.0) = 0.4;
uniform sampler2D u_detail_tex : source_color;

uniform vec4 u_fog_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float u_fog_start = 30.0;
uniform float u_fog_end = 120.0;
uniform vec3 u_horizon_glow_color : source_color = vec3(0.005, 0.01, 0.02);

void fragment() {
	vec2 uv = UV * u_tiling;

	float height = texture(u_albedo_tex, uv).r;

	vec2 eps = vec2(0.002, 0.0);
	float hx = texture(u_albedo_tex, uv + eps).r;
	float hz = texture(u_albedo_tex, uv + eps.yx).r;
	vec3 normal = normalize(vec3(
		(height - hx) * u_height_scale,
		1.0,
		(height - hz) * u_height_scale
	));

	vec2 detail_uv = UV * u_tiling * 3.0;
	float detail = texture(u_detail_tex, detail_uv + TIME * vec2(0.005, 0.003)).r;
	float detail_hx = texture(u_detail_tex, detail_uv + eps + TIME * vec2(0.005, 0.003)).r;
	float detail_hz = texture(u_detail_tex, detail_uv + eps.yx + TIME * vec2(0.005, 0.003)).r;
	vec3 detail_normal = normalize(vec3(
		(detail - detail_hx) * u_detail_strength,
		1.0,
		(detail - detail_hz) * u_detail_strength
	));
	NORMAL = normalize(vec3(
		normal.x + detail_normal.x * 0.3,
		normal.y,
		normal.z + detail_normal.z * 0.3
	));

	vec3 tex_color = texture(u_albedo_tex, uv).rgb;
	vec3 base_albedo = tex_color * u_tint_color.rgb;

	METALLIC = u_metallic + (height - 0.5) * 0.08;
	float base_roughness = u_roughness - (height - 0.5) * 0.1;

	float emissive_variation = 0.7 + height * 0.6 + detail * 0.15;
	vec3 base_emission = u_emission * u_emission_energy * emissive_variation;

	float dist = length(VERTEX);
	float fog = smoothstep(u_fog_start, u_fog_end, dist);

	float horizon_mask = smoothstep(0.1, 0.5, fog) * (1.0 - smoothstep(0.7, 1.0, fog));
	vec3 horizon_glow = u_horizon_glow_color * horizon_mask * 0.6;

	ALBEDO = mix(base_albedo, u_fog_color.rgb, fog);
	ROUGHNESS = mix(base_roughness, 0.0, fog * 0.7);
	EMISSION = mix(base_emission + horizon_glow, u_fog_color.rgb * 0.3, fog);
}

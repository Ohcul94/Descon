shader_type sky;
//render_mode use_debanding;
render_mode use_half_res_pass;

#include "sky_shader_include.gdshaderinc"
#include "physical_sky_parameters.gdshaderinc"

const float PLANET_RADIUS = 6371000.0;
const float ATMOSPHERE_HEIGHT = 100000.0;

group_uniforms SunSettings;
uniform float sun_scale : hint_range(1.0, 100.0) = 1.0;
uniform float sun_intensity : hint_range(1.0, 1000.0) = 10.0;
uniform float sun_emission : hint_range(0.0, 1000.0, 0.1) = 2.0;

group_uniforms MoonSettings;
uniform sampler2D moon_texture : source_color, filter_linear_mipmap;
uniform vec2 moon_texture_offset = vec2(-90.0, 100.0);
uniform float moon_scale : hint_range(1.0, 100.0) = 1.0;
uniform float moon_emission : hint_range(0.0, 10000.0, 0.1) = 500.0;
uniform float moon_emission_sharpness : hint_range(1.0, 10.0, 0.1) = 2.0;
uniform mat3 moon_matrix;

group_uniforms PlanetSettings;
uniform sampler2D planet_texture : source_color, filter_linear_mipmap;
uniform vec4 ground_color : source_color = vec4(0.1, 0.07, 0.034, 1.0);
uniform float ground_color_influence : hint_range(0.0, 1.0, 0.01) = 0.75;
uniform float max_ground_color_influence_altitude : hint_range(0.0, 10000000) = 100000.0;
uniform float latitude : hint_range(-90.0, 90.0) = 14.10194;
uniform float longitude : hint_range(-180.0, 180.0) = -87.30695;
uniform float altitude : hint_range(1.0, 10000000.0, 0.1) = 2.0;

group_uniforms StarsSettings;
uniform sampler2D stars_texture : source_color, filter_linear_mipmap;
uniform vec2 stars_texture_offset = vec2(0.0, 90.0);
uniform mat3 stars_matrix;
uniform float stars_intensity : hint_range(0.0, 5.0) = 1.0;
uniform float stars_threshold : hint_range(-1.0, 1.0) = 0.0;

group_uniforms CloudsSettings;
uniform bool show_clouds = true;
uniform bool separate_clouds_layers = true;
uniform sampler2D clouds_texture : source_color, filter_linear_mipmap;
uniform sampler2D clouds_texture_1 : source_color, filter_linear_mipmap;
uniform sampler2D clouds_texture_2 : source_color, filter_linear_mipmap;
uniform sampler2D clouds_texture_3 : source_color, filter_linear_mipmap;
uniform sampler2D clouds_texture_4 : source_color, filter_linear_mipmap;
uniform float clouds_opacity : hint_range(0.0, 1.0) = 1.0;
uniform float clouds_r_opacity : hint_range(0.0, 1.0) = 1.0;
uniform float clouds_g_opacity : hint_range(0.0, 1.0) = 0.0;
uniform float clouds_b_opacity : hint_range(0.0, 1.0) = 0.0;
uniform float clouds_a_opacity : hint_range(0.0, 1.0) = 0.0;
uniform float clouds_rotation : hint_range(-180, 180.0) = 0.0;
uniform vec4 clouds_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

group_uniforms RayMarching;
uniform bool use_ray_marching = false;
uniform int rm_num_steps : hint_range(0, 128, 1) = 8;
uniform float rm_step_size : hint_range(1.0, 100.0, 1.0) = 100.0;
uniform int num_light_steps : hint_range(0, 128, 1) = 2;
uniform float light_step_size : hint_range(1.0, 100.0, 1.0) = 50.0;
uniform float light_absorb : hint_range(0.0, 10.0, 0.1) = 2.5;
uniform float darkness_threshold : hint_range(0.0, 1.0, 0.01) = 0.02;
//uniform bool _is_daytime;

const vec3 UP = vec3( 0.0, 1.0, 0.0 );

struct SkyView {
	vec3 eye_dir;
	float view_zenith;
	float cos_horizon;
	float atmosphere_fade;
	float optical_mass;
	float space_fade;
};

SkyView compute_sky_view(vec3 eye_dir) {
	SkyView v;
	v.eye_dir = eye_dir;

	float r = PLANET_RADIUS;
	float R = r + altitude;

	v.space_fade = 1.0 - clamp(altitude / ATMOSPHERE_HEIGHT, 0.0, 1.0);

	v.cos_horizon = -sqrt(max(0.0, 1.0 - (r * r) / (R * R)));
	v.view_zenith = dot(UP, eye_dir);

	v.atmosphere_fade = smoothstep(
		v.cos_horizon - 0.05,
		v.cos_horizon + 0.01,
		v.view_zenith
	);

	float h = max(0.01, v.view_zenith - v.cos_horizon);
	v.optical_mass = 1.0 / (h + 0.15 * pow(3.885 + 54.5 * h, -1.253));

	return v;
}

struct AtmosphereResult {
	vec3 scattering;
	vec3 extinction;
	vec3 transmittance;
};

AtmosphereResult compute_atmosphere(SkyView v) {
	AtmosphereResult a;

	float sun_zenith = dot(UP, LIGHT0_DIRECTION);
	float sun_fade = 1.0 - clamp(1.0 - exp(sun_zenith), 0.0, 1.0);

	float sun_visibility = smoothstep(
		v.cos_horizon - 0.1,
		v.cos_horizon + 0.1,
		LIGHT0_DIRECTION.y
	);

	float sun_energy =
		0.757 * LIGHT0_ENERGY *
		sun_visibility *
		v.atmosphere_fade;

	// Rayleigh
	float rayleigh_coeff = rayleigh - (1.0 * (1.0 - sun_fade));
	vec3 rayleigh_beta =
		rayleigh_coeff *
		rayleigh_color.rgb *
		0.0001 *
		v.space_fade;

	// Mie
	float mie_alt_fade = mix(
		1.0,
		0.1,
		clamp(altitude / ATMOSPHERE_HEIGHT, 0.0, 1.0)
	);

	vec3 mie_beta =
		turbidity *
		mie *
		mie_color.rgb *
		0.000434 *
		mie_alt_fade;

	float rayleigh_scatter = rayleigh_zenith_size * v.optical_mass;
	float mie_scatter = mie_zenith_size * v.optical_mass;

	a.extinction = exp(
		-(rayleigh_beta * rayleigh_scatter +
		  mie_beta * mie_scatter)
	);

	// Phase
	float cos_theta = dot(v.eye_dir, normalize(LIGHT0_DIRECTION));

	float rayleigh_phase =
		(3.0 / (16.0 * PI)) *
		(1.0 + pow(cos_theta * 0.5 + 0.5, 2.0));

	float mie_phase =
		henyey_greenstein(cos_theta, mie_eccentricity);

	vec3 beta_theta =
		rayleigh_beta * rayleigh_phase +
		mie_beta * mie_phase;

	a.scattering = pow(
		sun_energy *
		(beta_theta / (rayleigh_beta + mie_beta)) *
		(1.0 - a.extinction),
		vec3(1.5)
	);

	a.scattering *= v.atmosphere_fade;

	a.transmittance = mix(
		a.extinction,
		vec3(1.0),
		1.0 - v.space_fade
	);

	return a;
}

vec3 get_planet(
	vec3 cam_pos,
	vec3 eye_dir,
	float hit_dist
) {
	vec3 normal = normalize(cam_pos + eye_dir * hit_dist);

	vec3 pos = rotate_x(normal, PI * -0.5);
	pos = rotate_x(pos, radians(-latitude));
	pos = rotate_y(pos, radians(-longitude - 90.0));

	vec2 uv;
	uv.x = atan(pos.z, pos.x) / (2.0 * PI) + 0.5;
	uv.y = asin(pos.y) / PI + 0.5;

	vec3 tex = texture(planet_texture, uv).rgb;

	float diffuse = clamp(dot(normal, LIGHT0_DIRECTION), 0.0, 1.0);
	tex *= (diffuse + 0.02);

	float height_factor = clamp(altitude / max_ground_color_influence_altitude, 0.0, 1.0);
	float fade = 1.0 - height_factor;
	return mix(tex, ground_color.rgb, ground_color_influence * fade);
}

float get_sun_mask(float cos_theta) {
	float sun_angular_radius = 0.00464233333333 * sun_scale;
	float sun_threshold = cos(sun_angular_radius);
	float sun_mask = smoothstep(sun_threshold - 0.0001, sun_threshold, cos_theta);
	return sun_mask;
}

float get_moon_mask(vec3 eye_dir) {
	float moon_angular_radius = 0.0050 * moon_scale;
	float cos_moon_radius = cos(moon_angular_radius);
	float moon_dot = dot(eye_dir, LIGHT1_DIRECTION);
	float moon_mask = smoothstep(cos_moon_radius - 0.0001, cos_moon_radius, moon_dot);
	return moon_mask;
}

vec3 get_stars(vec3 eye_dir, vec3 sun_dir, float sun_energy) {
	vec3 rotated_dir = stars_matrix * eye_dir;
	rotated_dir = rotate_y(rotated_dir, radians(stars_texture_offset.x));
	rotated_dir = rotate_x(rotated_dir, radians(stars_texture_offset.y));
	vec2 uv = get_spherical_uv(rotated_dir, true, true);
	vec3 stars = texture(stars_texture, uv).rgb;
	
	float sun_visibility = smoothstep(stars_threshold - 0.1, stars_threshold + 0.1, sun_dir.y);
	float star_fade = 1.0 - sun_visibility;
	star_fade *= clamp(1.0 - (sun_energy / 10.0), 0.0, 1.0);
	float sun_horizon_mask = smoothstep(stars_threshold + 0.1, stars_threshold - 0.1, sun_dir.y);
	float sun_energy_mask = clamp(1.0 - (sun_energy / 1.0), 0.0, 1.0);
	float space_factor = smoothstep(0.0, ATMOSPHERE_HEIGHT, altitude);
	//float visibility = max(star_fade, space_factor);
	float visibility = max(max(sun_horizon_mask, sun_energy_mask), space_factor);
	return stars * visibility * stars_intensity;
}

vec3 get_sun(vec3 eye_dir, vec3 sun_dir, vec3 sun_color, vec3 transmittance) {
	float sun_angular_radius = 0.00464233333333 * sun_scale;
	float cos_theta = dot(eye_dir, sun_dir);
	float sun_threshold = cos(sun_angular_radius);
	float sun_mask = smoothstep(sun_threshold - 0.0001, sun_threshold, cos_theta);
	vec3 final_sun = sun_color * (sun_intensity + sun_emission);
	return sun_mask * final_sun * transmittance;
}

vec3 get_moon(vec3 eye_dir, vec3 sun_dir, vec3 moon_dir, vec3 moon_color, vec3 transmittance) {
	float moon_angular_radius = 0.0050 * moon_scale;
	float cos_theta = dot(eye_dir, moon_dir);
	
	float moon_hit = simple_sphere_intersect(eye_dir, moon_dir, moon_angular_radius);
	vec3 moon_disk = vec3(0.0);

	if (moon_hit > 0.0) {
		vec3 moon_normal = normalize((eye_dir * moon_hit) - moon_dir);
		vec3 local_normal = moon_matrix * moon_normal;
		local_normal = rotate_y(local_normal, radians(moon_texture_offset.x));
		local_normal = rotate_x(local_normal, radians(moon_texture_offset.y));

		vec2 moon_uv = get_spherical_uv(local_normal, true, true);
		float moon_phase = clamp(dot(moon_normal, sun_dir), 0.0, 1.0);

		vec3 tex = texture(moon_texture, moon_uv).rgb;
		moon_disk = tex * moon_color * (moon_phase + (pow(moon_phase, moon_emission_sharpness) * moon_emission * LIGHT1_ENERGY));
	}
	
	float glow_radius = moon_angular_radius * 15.0;
	float glow_threshold = cos(glow_radius);
	float glow_mask = smoothstep(glow_threshold, cos(moon_angular_radius), cos_theta);
	glow_mask = pow(glow_mask, 100.0);
	float night_mask = smoothstep(0.1, -0.1, sun_dir.y);
	float space_mask = clamp(altitude / ATMOSPHERE_HEIGHT, 0.0, 1.0);
	float glow_visibility = max(night_mask, space_mask);
	vec3 moon_glow = moon_color * glow_mask * (moon_emission * 0.00005) * glow_visibility;
	
	return (moon_disk + moon_glow) * transmittance;
}

float sample_cloud_density(vec2 uv) {
	vec4 tex = texture(clouds_texture, uv);
	
	vec4 channel_weights = vec4(
		clouds_r_opacity,
		clouds_g_opacity,
		clouds_b_opacity,
		clouds_a_opacity
	);
	
	if (separate_clouds_layers) {
		float r = texture(clouds_texture_1, uv).r;
		float g = texture(clouds_texture_2, uv).r;
		float b = texture(clouds_texture_3, uv).r;
		float a = texture(clouds_texture_4, uv).r;
		
		tex = vec4(r, g, b, a);
	}

	float density = dot(tex, channel_weights);
	return clamp(density * clouds_opacity, 0.0, 1.0);
}

vec3 get_clouds_raymarched(vec3 sky_color, vec3 eye_dir, vec3 sun_dir, vec3 sun_color, float cloud_alpha) {
	if (eye_dir.y <= 0.0) return sky_color;

	float cloud_start = 2000.0; 
	float t_entry = cloud_start / eye_dir.y;
	
	float dither = hash(eye_dir * 100.0);
	float current_t = t_entry + dither * rm_step_size;
	
	float transmittance = 1.0;
	vec3 cloud_light = vec3(0.0);
	
	float sun_look = clamp(dot(eye_dir, sun_dir), 0.0, 1.0);
	vec3 base_cloud_color = clouds_color.rgb * (sun_color * (0.5 + 0.5 * sun_look));

	for (int i = 0; i < rm_num_steps; i++) {
		vec3 p = eye_dir * current_t;
		vec2 uv = get_equirect_uv(normalize(p));
		uv.x += clouds_rotation / 360.0;

		float density = clamp(sample_cloud_density(uv) * cloud_alpha, 0.0, 1.0);
		
		if (density > 0.001) {
			float light_density = 0.0;
			for (int j = 0; j < num_light_steps; j++) {
				vec3 lp = p + sun_dir * (float(j + 1) * light_step_size);
				vec2 l_uv = get_equirect_uv(normalize(lp));
				l_uv.x += clouds_rotation / 360.0;
				light_density += sample_cloud_density(l_uv);
			}
			
			float light_received = exp(-light_density * light_absorb);
			float attenuation = darkness_threshold + light_received * (1.0 - darkness_threshold);
			
			cloud_light += base_cloud_color * attenuation * density * transmittance;
			transmittance *= (1.0 - density);
		}
		
		current_t += rm_step_size;
		if (transmittance <= 0.01) break;
	}
	
	return (cloud_light) + (sky_color * transmittance);
}

vec3 get_clouds(vec3 sky_color, vec3 eye_dir, vec3 sun_dir, vec3 sun_color) {
	float r = PLANET_RADIUS;
	float R = r + altitude;
	float cos_horizon = -sqrt(max(0.0, 1.0 - (r * r) / (R * R)));
	
	if (eye_dir.y <= cos_horizon) return sky_color;
	
	float altitude_progress = clamp(altitude / ATMOSPHERE_HEIGHT, 0.0, 1.0);
	float clear_threshold = altitude_progress * 1.1; 
	float horizon_fade = smoothstep(clear_threshold, clear_threshold + 0.2, eye_dir.y);
	
	float global_fade = 1.0 - smoothstep(0.8, 1.0, altitude_progress);

	float cloud_alpha = clouds_opacity * global_fade * horizon_fade;
	if (cloud_alpha <= 0.0) return sky_color;
	
	if (use_ray_marching) {
		return get_clouds_raymarched(sky_color, eye_dir, sun_dir, sun_color, cloud_alpha);
	}
	
	vec2 uv = get_equirect_uv(normalize(eye_dir));
	uv.x += clouds_rotation / 360.0;
	
	vec3 clouds = clouds_color.rgb;
	float sun_look = clamp(dot(eye_dir, sun_dir), 0.0, 1.0);
	clouds *= (sun_color * (0.5 + 0.5 * sun_look));
	
	vec4 channel_weights = vec4(
		clouds_r_opacity * 2.0,
		clouds_g_opacity * 2.0,
		clouds_b_opacity * 5.0,
		clouds_a_opacity * 1.0
	);
	
	vec4 tex = texture(clouds_texture, uv);
	if (separate_clouds_layers) {
		float r = texture(clouds_texture_1, uv).r;
	   float g = texture(clouds_texture_2, uv).r;
	   float b = texture(clouds_texture_3, uv).r;
	   float a = texture(clouds_texture_4, uv).r;
		
		tex = vec4(r, g, b, a);
	}
	float density = clamp((dot(tex, channel_weights)) * cloud_alpha, 0.0, 1.0);
	
	return mix(sky_color, clouds, density);
}

vec3 get_sky(vec3 eye_dir) {
	vec3 sky_color = vec3(1.0);
	vec3 cam_pos = vec3(0.0, PLANET_RADIUS + altitude, 0.0);

	float planet_hit = get_planet_hit(cam_pos, eye_dir, PLANET_RADIUS);
	if (planet_hit > 0.0) {
		return get_planet(cam_pos, eye_dir, planet_hit);
	}

	SkyView view = compute_sky_view(eye_dir);
	AtmosphereResult atm = compute_atmosphere(view);

	float cos_theta = dot(eye_dir, normalize(LIGHT0_DIRECTION));

	float sun_mask = get_sun_mask(cos_theta);
	float moon_mask = get_moon_mask(eye_dir);

	sky_color = pow(
		atm.scattering,
		vec3(1.0 / (1.2 + (1.2 * view.space_fade)))
	) * exposure;

	vec3 stars = get_stars(eye_dir, LIGHT0_DIRECTION, LIGHT0_ENERGY);
	stars *= (1.0 - sun_mask) * (1.0 - moon_mask);
	sky_color += stars;

	vec3 sun_disk =
		get_sun(eye_dir, LIGHT0_DIRECTION, LIGHT0_COLOR, atm.transmittance);
	sun_disk *= (1.0 - moon_mask);
	sky_color += sun_disk;

	vec3 moon =
		get_moon(
			eye_dir,
			LIGHT0_DIRECTION,
			LIGHT1_DIRECTION,
			LIGHT1_COLOR,
			atm.transmittance
		) * atm.extinction;

	sky_color += moon;
	
	if (show_clouds) {
		float night_factor = clamp(-LIGHT0_DIRECTION.y * 2.0, 0.0, 1.0);
		vec3 cloud_light_dir = normalize(mix(LIGHT0_DIRECTION, LIGHT1_DIRECTION, night_factor));
		vec3 cloud_light_color = normalize(mix(LIGHT0_COLOR, LIGHT1_COLOR, night_factor));
		//float cloud_light_energy = normalize(mix(LIGHT0_ENERGY, LIGHT1_ENERGY, night_factor));
		
		vec3 sun_cloud_color = LIGHT0_COLOR * LIGHT0_ENERGY;
		vec3 moon_cloud_color = LIGHT1_COLOR * 0.1;
		
		float moon_weight = pow(night_factor, 0.5);
		
		vec3 cloud_color = mix(sun_cloud_color, moon_cloud_color, moon_weight);
		cloud_light_color += vec3(0.02, 0.03, 0.05) * night_factor;
		sky_color = get_clouds(
			sky_color,
			eye_dir,
			cloud_light_dir,
			cloud_color
		);
	}

	return sky_color;
}

void sky() {
	vec3 eye_dir = normalize(EYEDIR);

	COLOR = get_sky(eye_dir);
}

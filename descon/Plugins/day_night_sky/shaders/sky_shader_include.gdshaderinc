// sky shader include
vec3 rotate_x(vec3 p, float a) {
	float s = sin(a);
	float c = cos(a);
	return vec3(
		p.x,
		c * p.y - s * p.z,
		s * p.y + c * p.z
	);
}

vec3 rotate_y(vec3 v, float a) {
	float s = sin(a);
	float c = cos(a);
	return vec3(
		c * v.x + s * v.z,
		v.y,
		-s * v.x + c * v.z
	);
}

vec2 get_equirect_uv(vec3 dir) {
	float u = atan(-dir.z, dir.x) / (2.0 * PI) + 0.5;
	float v = 1.0 - (asin(dir.y) / PI + 0.5) * 1.0;
	return vec2(u, v);
}

vec2 get_equirect_uv_hemisphere(vec3 dir) {
	float u = atan(-dir.z, dir.x) / (2.0 * PI) + 0.5;
	float v = 1.0 - (asin(dir.y) / PI + 0.5) * 2.0;
	return vec2(u, v);
}

vec2 get_spherical_uv(vec3 normal, bool flip_x, bool flip_y) {
	float u = atan(normal.z, normal.x) / (2.0 * PI) + 0.5;
	if (flip_x) {
		u = 1.0 - u;
	}
	
	float angle_v = asin(clamp(normal.y, -1.0, 1.0)) / PI;
	float v = flip_y ? (0.5 + angle_v) : (0.5 - angle_v);
	
	return vec2(u, v);
}

vec2 get_cylindrical_uv(vec3 dir) {
    float u = atan(-dir.z, dir.x) / (2.0 * PI) + 0.5;
    float v = dir.y * 0.5 + 0.5; // linear, no asin
    return vec2(u, v);
}

float sample_triplanar(
    sampler2D tex,
    vec3 dir,
    float scale
) {
    dir = normalize(dir);

    vec3 w = abs(dir);
    w /= (w.x + w.y + w.z);

    vec3 p = dir * scale;

    vec2 uv_x = p.yz;
    vec2 uv_y = p.xz;
    vec2 uv_z = p.xy;

    float x = texture(tex, uv_x).r;
    float y = texture(tex, uv_y).r;
    float z = texture(tex, uv_z).r;

    return x * w.x + y * w.y + z * w.z;
}

float simple_sphere_intersect(vec3 ray_dir, vec3 sphere_pos, float angular_radius) {
	vec3 oc = -sphere_pos;
	float b = dot(oc, ray_dir);
	float radius = sin(angular_radius);
	float h = b * b - (dot(oc, oc) - radius * radius);

	if (h < 0.0) {
		return -1.0;
	}
	return -b - sqrt(h);
}

float get_planet_hit(vec3 cam_pos, vec3 eye_dir, float radius) {
	float b = dot(cam_pos, eye_dir);
	float c = dot(cam_pos, cam_pos) - radius * radius;
	float h = b * b - c;
	return (h < 0.0) ? -1.0 : -b - sqrt(h);
}

float hash(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

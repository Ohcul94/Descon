shader_type spatial;
render_mode unshaded, blend_add, depth_test_disabled;

const vec3 COLOR_HOT = vec3(4.0, 3.0, 1.0);
const vec3 COLOR_MID = vec3(2.0, 0.5, 0.0);
const vec3 COLOR_COLD = vec3(0.1, 0.05, 0.02);

varying float lifetime_percent;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

void vertex() {
	lifetime_percent = INSTANCE_CUSTOM.y;
	
	// BILLBOARD MANUAL (GLES3 Compatible)
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 uv_noise = UV * 3.0 + vec2(0.0, -TIME * 0.5);
	float n = noise(uv_noise);
	
	float d = distance(UV, vec2(0.5));
	float mask = smoothstep(0.5, 0.1, d + n * 0.2);
	
	if (mask < 0.1) discard;

	vec3 final_color;
	if (lifetime_percent < 0.2) {
		final_color = mix(COLOR_HOT, COLOR_MID, lifetime_percent * 5.0);
	} else {
		final_color = mix(COLOR_MID, COLOR_COLD, (lifetime_percent - 0.2) * 1.25);
	}
	
	final_color *= (0.8 + n * 0.4);
	
	ALPHA = mask * (1.0 - smoothstep(0.7, 1.0, lifetime_percent));
	ALBEDO = final_color;
}

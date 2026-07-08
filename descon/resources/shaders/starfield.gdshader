shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform float u_star_density : hint_range(0.5, 3.0) = 1.5;
uniform float u_twinkle_speed : hint_range(0.0, 3.0) = 1.0;
uniform float u_twinkle_amount : hint_range(0.0, 1.0) = 0.5;

float hash(vec2 p) {
	p = fract(p * vec2(443.8975, 397.2973));
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}

vec2 hash2(vec2 p) {
	return vec2(hash(p + 17.0), hash(p + 31.0));
}

void fragment() {
	vec2 uv = UV;
	vec3 bg = vec3(0.003, 0.003, 0.008);
	vec2 nuv = uv * 1.5;
	float n1 = sin(nuv.x * 2.3 + nuv.y * 1.7 + TIME * 0.008);
	float n2 = cos(nuv.x * 1.9 - nuv.y * 2.1 + TIME * 0.006);
	float n3 = sin((nuv.x - nuv.y) * 3.1 + TIME * 0.01);
	vec3 nebula1 = vec3(0.06, 0.01, 0.10) * (n1 * 0.5 + 0.5);
	vec3 nebula2 = vec3(0.01, 0.02, 0.12) * (n2 * 0.5 + 0.5);
	vec3 nebula3 = vec3(0.08, 0.005, 0.03) * (n3 * 0.5 + 0.5);
	vec3 nebula = (nebula1 + nebula2 + nebula3) * 0.25;
	float divs[3];
	divs[0] = 60.0 * u_star_density;
	divs[1] = 120.0 * u_star_density;
	divs[2] = 240.0 * u_star_density;
	float thresholds[3];
	thresholds[0] = 0.975;
	thresholds[1] = 0.94;
	thresholds[2] = 0.87;
	float layer_mult[3];
	layer_mult[0] = 2.0;
	layer_mult[1] = 1.0;
	layer_mult[2] = 0.5;
	vec3 stars = vec3(0.0);
	for (int i = 0; i < 3; i++) {
		float div = divs[i];
		float thresh = thresholds[i];
		float mult = layer_mult[i];
		vec2 cell = floor(uv * div);
		vec2 fuv = fract(uv * div) - 0.5;
		float h = hash(cell + float(i) * 7.0);
		if (h > thresh) {
			float brightness = hash(cell + float(i) * 13.0);
			float phase = hash(cell + float(i) * 19.0) * 6.2832;
			vec2 pos = (hash2(cell + float(i) * 23.0) - 0.5) * 0.7;
			vec2 duv = fuv - pos;
			float d = length(duv);
			float size = mix(0.008, 0.04, brightness) / (float(i) * 0.7 + 1.0);
			float tw = sin(u_twinkle_speed * TIME * mix(0.5, 2.5, brightness) + phase);
			tw = mix(1.0 - u_twinkle_amount, 1.0, tw * 0.5 + 0.5);
			float alpha = smoothstep(size, 0.0, d);
			float glow = exp(-d * 25.0 / max(size, 0.001)) * 0.4;
			float star_val = (alpha + glow) * brightness * tw;
			float ci = hash(cell + float(i) * 31.0);
			vec3 col;
			if (ci < 0.65) col = vec3(1.0);
			else if (ci < 0.82) col = vec3(0.75, 0.85, 1.0);
			else if (ci < 0.95) col = vec3(1.0, 0.95, 0.7);
			else col = vec3(1.0, 0.6, 0.3);
			stars += col * star_val * mult;
		}
	}
	vec3 final_color = bg + nebula + stars;
	COLOR = vec4(final_color, 1.0);
}

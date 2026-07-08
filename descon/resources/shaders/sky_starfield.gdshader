shader_type sky;

uniform float u_star_density : hint_range(0.5, 3.0) = 1.5;
uniform float u_twinkle_speed : hint_range(0.0, 3.0) = 1.0;
uniform float u_twinkle_amount : hint_range(0.0, 1.0) = 0.5;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 col = vec3(0.001, 0.001, 0.003);
	vec3 ndir = dir * 1.5;
	float n1 = sin(ndir.x * 2.3 + ndir.y * 1.7 + ndir.z * 0.5 + TIME * 0.005);
	float n2 = cos(ndir.x * 1.9 - ndir.z * 2.1 + TIME * 0.004);
	float n3 = sin((ndir.x - ndir.y) * 3.1 + ndir.z * 1.3 + TIME * 0.008);
	col += vec3(0.04, 0.005, 0.08) * (n1 * 0.5 + 0.5) * 0.2;
	col += vec3(0.005, 0.01, 0.08) * (n2 * 0.5 + 0.5) * 0.2;
	col += vec3(0.06, 0.003, 0.02) * (n3 * 0.5 + 0.5) * 0.2;
	for (int i = 0; i < 3; i++) {
		float div = i == 0 ? 60.0 * u_star_density : (i == 1 ? 150.0 * u_star_density : 350.0 * u_star_density);
		float thresh = i == 0 ? 0.97 : (i == 1 ? 0.93 : 0.85);
		float mult = i == 0 ? 2.0 : (i == 1 ? 1.0 : 0.5);
		vec3 cell = floor(dir * div);
		vec3 fuv = fract(dir * div) - 0.5;
		float h = hash(cell + float(i) * 7.0);
		if (h > thresh) {
			float bright = hash(cell + float(i) * 13.0);
			float phase = hash(cell + float(i) * 17.0) * 6.2832;
			vec3 pos = (vec3(
				hash(cell + float(i) * 19.0),
				hash(cell + float(i) * 23.0),
				hash(cell + float(i) * 29.0)
			) - 0.5) * 0.7;
			vec3 duv = fuv - pos;
			float d = length(duv);
			float size = mix(0.01, 0.06, bright) / (float(i) * 0.5 + 1.0);
			float tw = sin(u_twinkle_speed * TIME * mix(0.5, 2.5, bright) + phase);
			tw = tw * 0.5 + 0.5;
			tw = mix(1.0 - u_twinkle_amount, 1.0, tw);
			float alpha = smoothstep(size, 0.0, d);
			float glow = exp(-d * 20.0 / max(size, 0.001)) * 0.3;
			float sv = (alpha + glow) * bright * tw;
			float ci = hash(cell + float(i) * 31.0);
			vec3 sc;
			if (ci < 0.65) sc = vec3(1.0);
			else if (ci < 0.82) sc = vec3(0.75, 0.85, 1.0);
			else if (ci < 0.95) sc = vec3(1.0, 0.95, 0.7);
			else sc = vec3(1.0, 0.6, 0.3);
			col += sc * sv * mult;
		}
	}
	COLOR = col;
}

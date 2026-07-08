shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float u_star_density : hint_range(0.1, 3.0) = 0.3;

varying vec3 v_local_pos;

void vertex() {
	v_local_pos = VERTEX;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void fragment() {
	vec3 dir = normalize(v_local_pos);
	vec3 col = vec3(0.0);

	vec3 ndir = dir * 1.5;
	float n1 = sin(ndir.x * 2.3 + ndir.y * 1.7 + ndir.z * 0.5 + TIME * 0.005);
	float n2 = cos(ndir.x * 1.9 - ndir.z * 2.1 + TIME * 0.004);
	float n3 = sin((ndir.x - ndir.y) * 3.1 + ndir.z * 1.3 + TIME * 0.008);
	col += vec3(0.005, 0.01, 0.03) * (n1 * 0.5 + 0.5);
	col += vec3(0.002, 0.005, 0.02) * (n2 * 0.5 + 0.5);
	col += vec3(0.004, 0.008, 0.015) * (n3 * 0.5 + 0.5);

	float mw1 = 1.0 - abs(dot(dir, normalize(vec3(0.4, 0.1, 0.9))));
	float mw2 = 1.0 - abs(dot(dir, normalize(vec3(-0.6, 0.2, 0.7))));
	float mw = smoothstep(0.3, 0.0, mw1) + smoothstep(0.3, 0.0, mw2) * 0.7;
	col += vec3(0.005, 0.008, 0.02) * mw;

	for (int i = 0; i < 3; i++) {
		float div = i == 0 ? 60.0 * u_star_density : (i == 1 ? 160.0 * u_star_density : 400.0 * u_star_density);
		float thresh = i == 0 ? 0.99 : (i == 1 ? 0.98 : 0.95);
		float mult = i == 0 ? 8.0 : (i == 1 ? 4.0 : 2.0);
		vec3 cell = floor(dir * div);
		vec3 fuv = fract(dir * div) - 0.5;
		float h = hash(cell + float(i) * 7.0);
		if (h > thresh) {
			float bright = hash(cell + float(i) * 13.0) * 0.6 + 0.4;
			float phase = hash(cell + float(i) * 17.0) * 6.2832;
			vec3 pos = (vec3(
				hash(cell + float(i) * 19.0),
				hash(cell + float(i) * 23.0),
				hash(cell + float(i) * 29.0)
			) - 0.5) * 0.6;
			vec2 duv = fuv.xy - pos.xy;
			float d = length(duv);
			float size = mix(0.03, 0.12, bright) / (float(i) * 0.4 + 1.0);
			float sv = smoothstep(size, 0.0, d) * bright * mult;
			float glow = exp(-d * 10.0 / max(size, 0.001)) * 0.8 * bright * mult;
			sv += glow;
			float ci = hash(cell + float(i) * 31.0);
			vec3 sc;
			if (ci < 0.60) sc = vec3(1.0);
			else if (ci < 0.78) sc = vec3(0.7, 0.82, 1.0);
			else if (ci < 0.92) sc = vec3(1.0, 0.95, 0.7);
			else sc = vec3(1.0, 0.5, 0.25);
			col += sc * sv;
		}
	}

	ALBEDO = col;
}

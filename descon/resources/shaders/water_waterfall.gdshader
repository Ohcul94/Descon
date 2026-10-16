shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, unshaded;

// Cascada estilizada - barata para GL Compatibility, todo procedural sin texturas.
// Se usa sobre un plano vertical (la escena VFX_Waterfall ya lo trae parado).
// La espuma sale en ambos extremos para que no importe el flip del UV.

uniform vec4 top_color : source_color = vec4(0.55, 0.75, 0.74, 1.0);
uniform vec4 body_color : source_color = vec4(0.22, 0.47, 0.47, 1.0);
uniform vec4 foam_color : source_color = vec4(0.9, 0.97, 0.95, 1.0);
uniform float flow_speed : hint_range(-4.0, 4.0) = 1.6;
uniform float stripes : hint_range(4.0, 64.0) = 24.0;
uniform float base_alpha : hint_range(0.0, 1.0) = 0.85;
uniform float sway : hint_range(0.0, 0.5) = 0.08;
uniform float edge_erode : hint_range(0.0, 0.5) = 0.16;
// Arco superior: la caída viene del río de atrás (-Z local)
uniform float arch : hint_range(0.0, 4.0) = 2.0;
uniform float mesh_h : hint_range(1.0, 20.0) = 8.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// 3 octavas nomas para no matar FPS en GLES3
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	// La cortina respira: serpenteo lateral y en profundidad
	VERTEX.x += sin(UV.y * 6.0 + TIME * 2.0) * sway * (0.3 + 0.7 * UV.y);
	VERTEX.x += (noise(vec2(UV.y * 4.0, TIME * 1.5)) - 0.5) * sway * 1.5;
	VERTEX.z += (noise(vec2(UV.y * 3.0 + 7.0, TIME * 1.2)) - 0.5) * sway * 1.5;
	// Arco del río: arriba se curva hacia atrás (parábola del labio)
	float htop = smoothstep(0.45, 1.0, (VERTEX.y + mesh_h * 0.5) / mesh_h);
	VERTEX.z -= htop * htop * arch;
	VERTEX.y += htop * arch * 0.3;
}

void fragment() {
	// Vetones verticales de agua cayendo (si se ve subir, poner flow_speed negativo)
	float n = fbm(vec2(UV.x * stripes, UV.y * 6.0 + TIME * flow_speed * 3.0));
	float streak = fbm(vec2(UV.x * stripes * 2.0, UV.y * 3.0 + TIME * flow_speed * 4.5));
	float body = clamp(n * 0.65 + streak * 0.35, 0.0, 1.0);
	// Bordes irregulares: muerde la silueta con ruido animado (adiós rectángulo)
	float eu = fbm(vec2(UV.x * 5.0, UV.y * 2.5 - TIME * flow_speed * 0.8));
	float ex = min(UV.x, 1.0 - UV.x);
	float ey = min(UV.y, 1.0 - UV.y);
	float er = min(ex * 1.4, ey) + (eu - 0.5) * edge_erode * 2.0;
	if (er < 0.0) discard;
	float edge_fade = smoothstep(0.0, 0.1, er);

	vec3 col = mix(body_color.rgb, top_color.rgb, body);

	// Espuma en labio superior e impacto inferior
	float foam_ends = (1.0 - smoothstep(0.0, 0.12, UV.y)) + smoothstep(0.88, 1.0, UV.y);
	float foam_n = fbm(vec2(UV.x * 30.0, UV.y * 8.0 - TIME * flow_speed * 5.0));
	float foam = clamp(foam_ends * (0.5 + foam_n), 0.0, 1.0);
	col = mix(col, foam_color.rgb, foam * 0.8);

	// Desfuminado por ángulo: las caras de canto se desvanecen (no más bloque)
	float ndv = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float face_fade = smoothstep(0.05, 0.45, ndv);

	ALBEDO = col;
	EMISSION = col * 0.25;
	ALPHA = clamp((base_alpha * (0.55 + body * 0.45) + foam * 0.3) * (0.35 + 0.65 * edge_fade) * face_fade, 0.0, 1.0);
}

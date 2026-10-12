shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_lambert;

// Shader para palomas y aves pequeñas 3D con iluminación y aleteo natural
uniform vec4 body_color : source_color = vec4(0.92, 0.94, 0.97, 1.0);       // Blanco perlado / gris paloma suave
uniform vec4 wing_tip_color : source_color = vec4(0.45, 0.50, 0.60, 1.0);   // Puntas de alas gris azulado
uniform vec4 beak_color : source_color = vec4(0.95, 0.68, 0.42, 1.0);       // Piquito cálido
uniform vec4 belly_color : source_color = vec4(0.85, 0.87, 0.90, 1.0);      // Vientre suavemente sombreado

uniform float flap_speed : hint_range(5.0, 35.0) = 18.0;
uniform float flap_amplitude : hint_range(0.0, 1.2) = 0.55;
uniform float flap_strength : hint_range(0.0, 1.0) = 1.0;
uniform float fade_alpha : hint_range(0.0, 1.0) = 1.0;

varying float v_wing_ratio;
varying float v_beak_ratio;
varying float v_belly_ratio;

void vertex() {
	float wing_dist = abs(VERTEX.x);
	// Normalizar distancia del ala (0.0 en el cuerpo, 1.0 en la punta del ala)
	v_wing_ratio = clamp((wing_dist - 0.08) / 0.45, 0.0, 1.0);
	v_beak_ratio = step(VERTEX.z, -0.32);
	v_belly_ratio = clamp(-VERTEX.y * 5.0, 0.0, 1.0);

	// Aleteo con curvatura no-lineal (las puntas se doblan más rápido que los hombros)
	float phase = TIME * flap_speed;
	float flap_cycle = sin(phase);
	
	// Ángulo dihedral de paloma: en reposo / planeo las alas apuntan levemente hacia arriba
	float dihedral = v_wing_ratio * 0.08;
	
	// Flexión del ala: movimiento principal + desfase en la punta
	float wing_flex = (flap_cycle * flap_amplitude * v_wing_ratio) + (sin(phase - 0.3) * flap_amplitude * 0.35 * pow(v_wing_ratio, 2.0));
	VERTEX.y += (wing_flex * flap_strength) + dihedral;
	
	// Leve cabeceo rítmico del cuerpo de la paloma al aletear
	VERTEX.y += flap_cycle * 0.02 * flap_strength;
	
	// Retracción aerodinámica hacia atrás al bajar las alas
	VERTEX.z -= abs(wing_flex) * 0.12 * flap_strength;
}

void fragment() {
	// Mezcla de colores según la zona del modelo
	vec3 col = mix(body_color.rgb, belly_color.rgb, v_belly_ratio);
	
	// Degradado en las puntas de las alas
	col = mix(col, wing_tip_color.rgb, smoothstep(0.45, 1.0, v_wing_ratio));
	
	// Piquito en la punta delantera
	col = mix(col, beak_color.rgb, v_beak_ratio);
	
	ALBEDO = col;
	ROUGHNESS = 0.65;
	SPECULAR = 0.25;
	ALPHA = body_color.a * fade_alpha;
}

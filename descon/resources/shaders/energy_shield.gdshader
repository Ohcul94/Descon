shader_type spatial;
render_mode blend_add, depth_draw_always; 

uniform vec4 color_escudo : source_color = vec4(0.1, 0.5, 1.0, 1.0);
uniform float fuerza_borde : hint_range(0.0, 10.0) = 3.5;
uniform float velocidad_onda : hint_range(0.0, 5.0) = 0.8;
uniform float escala_rejilla : hint_range(1.0, 100.0) = 25.0;
uniform bool modo_curacion = false;

void fragment() {
    // 1. Fresnel para el borde (Efecto esfera 3D)
    float fresnel = pow(1.0 - dot(NORMAL, VIEW), fuerza_borde);
    
    float pattern = 0.0;
    
    if (modo_curacion) {
        // Efecto de Onda Expansiva para Curación
        float dist = distance(UV, vec2(0.5));
        pattern = sin(dist * 20.0 - TIME * velocidad_onda * 10.0) * 0.5 + 0.5;
        pattern = pow(pattern, 3.0) * (1.0 - dist * 2.0); // Desvanecer hacia los bordes
    } else {
        // Patrón de Rejilla / Malla para Escudo/Reflect
        vec2 grid_uv = UV * escala_rejilla;
        grid_uv.x += TIME * velocidad_onda;
        grid_uv.y -= TIME * velocidad_onda * 0.5;
        
        pattern = abs(sin(grid_uv.x) * cos(grid_uv.y));
        pattern = smoothstep(0.7, 1.0, pattern) * 0.4; 
    }
    
    // 3. Brillo y Opacidad
    float alpha_final = clamp(fresnel + pattern, 0.0, 1.0);
    
    ALBEDO = color_escudo.rgb;
    EMISSION = color_escudo.rgb * (fresnel * 2.0 + pattern * 3.0); 
    ALPHA = alpha_final * color_escudo.a;
}

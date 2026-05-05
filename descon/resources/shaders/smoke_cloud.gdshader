shader_type spatial;
render_mode blend_mix, depth_draw_always, unshaded;

uniform vec4 color_smoke : source_color = vec4(0.85, 0.85, 0.9, 0.7); // Blanco-grisáceo suave
uniform float density : hint_range(0.0, 10.0) = 4.0;
uniform float speed : hint_range(0.0, 5.0) = 0.3;

void fragment() {
    // 1. Ruido procedural de "nube" (más suave)
    vec2 uv = UV * 1.5;
    float n = sin(uv.x * 2.0 + TIME * speed) * cos(uv.y * 2.0 - TIME * speed * 0.4);
    n += sin(uv.x * 4.0 - TIME * speed * 0.7) * 0.4;
    n += cos(uv.y * 6.0 + TIME * speed * 0.9) * 0.3;
    n = n * 0.5 + 0.5;
    
    // 2. Máscara de Nube (Borde MUY suave)
    float dist = distance(UV, vec2(0.5));
    float mask = smoothstep(0.5, 0.1, dist); // Transición muy larga para suavidad
    
    // 3. Combinar
    float alpha = n * mask * density;
    
    ALBEDO = color_smoke.rgb;
    // Efecto de profundidad simple
    ALBEDO *= (1.0 - dist * 0.5); 
    
    ALPHA = clamp(alpha * color_smoke.a, 0.0, 0.85);
}

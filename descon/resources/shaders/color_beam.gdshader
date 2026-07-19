shader_type spatial;
render_mode blend_add, depth_draw_always, cull_disabled, unshaded;

uniform vec4 beam_color : source_color = vec4(0.0, 0.7, 1.0, 1.0);
uniform float speed : hint_range(0.0, 5.0) = 1.5;
uniform float scale_y : hint_range(0.1, 20.0) = 5.0; // Estiramiento vertical de los rayos
uniform float scale_x : hint_range(1.0, 50.0) = 15.0; // Cantidad/frecuencia de rayos en el contorno
uniform float fresnel_power : hint_range(0.1, 10.0) = 2.0;

// Ruido pseudo-aleatorio para generar los rayos de energía verticales
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2(0.0,0.0)), hash(i + vec2(1.0,0.0)), u.x),
               mix(hash(i + vec2(0.0,1.0)), hash(i + vec2(1.0,1.0)), u.x), u.y);
}

void fragment() {
    // Ruido estirado verticalmente y en constante movimiento hacia arriba (flujo de energía)
    vec2 uv_noise = vec2(UV.x * scale_x, UV.y * scale_y - TIME * speed);
    float ray = noise(uv_noise);
    
    // Potenciación del ruido para crear contrastes de haces verticales definidos
    ray = pow(ray, 2.5);
    
    // Desvanecimiento suave en los extremos del cilindro (especialmente en la parte superior)
    float vertical_fade = smoothstep(0.0, 0.2, UV.y) * smoothstep(1.0, 0.35, UV.y);
    
    // Fresnel para acentuar el contorno cilíndrico en 3D
    float fresnel = pow(1.0 - dot(NORMAL, VIEW), fresnel_power);
    
    // Combinación de componentes de opacidad
    float alpha = ray * vertical_fade * (fresnel * 1.5 + 0.2);
    
    ALBEDO = beam_color.rgb;
    EMISSION = beam_color.rgb * alpha * 4.0;
    ALPHA = clamp(alpha * beam_color.a * 1.8, 0.0, 1.0);
}

shader_type spatial;
render_mode blend_add, depth_draw_always, cull_disabled, unshaded;

uniform vec4 aura_color : source_color = vec4(0.0, 0.7, 1.0, 1.0);
uniform float edge_strength : hint_range(0.1, 10.0) = 3.0;
uniform float wave_speed : hint_range(0.0, 5.0) = 1.0;
uniform float noise_scale : hint_range(0.1, 10.0) = 3.0;
uniform float distortion : hint_range(0.0, 0.5) = 0.08;
uniform float pulse_speed : hint_range(0.0, 5.0) = 1.5;
uniform float pulse_amount : hint_range(0.0, 0.2) = 0.03;

// Función de pseudo-ruido de 3D para generar textura de plasma orgánico
float hash(vec3 p) {
    p = fract(p * vec3(443.8975, 397.2973, 491.1871));
    p += dot(p.xyz, p.yzx + 19.19);
    return fract(p.x * p.y * p.z);
}

float noise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    vec3 u = f * f * (3.0 - 2.0 * f);
    
    return mix(mix(mix(hash(i + vec3(0.0,0.0,0.0)), hash(i + vec3(1.0,0.0,0.0)), u.x),
                   mix(hash(i + vec3(0.0,1.0,0.0)), hash(i + vec3(1.0,1.0,0.0)), u.x), u.y),
               mix(mix(hash(i + vec3(0.0,0.0,1.0)), hash(i + vec3(1.0,0.0,1.0)), u.x),
                   mix(hash(i + vec3(0.0,1.0,1.0)), hash(i + vec3(1.0,1.0,1.0)), u.x), u.y), u.z);
}

// Movimiento Browniano Fraccionario (FBM) para mayor detalle en el ruido
float fbm(vec3 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 3; i++) {
        value += amplitude * noise(p);
        p *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

void vertex() {
    // Distorsión tridimensional de los vértices basada en ruido y tiempo
    vec3 noise_pos = VERTEX * noise_scale + vec3(0.0, TIME * wave_speed, 0.0);
    float wave = fbm(noise_pos);
    
    // Añadimos una pulsación rítmica a la escala local
    float pulse = sin(TIME * pulse_speed) * pulse_amount;
    
    // Desplazamiento radial de los vértices (vertex shader displacement)
    VERTEX += NORMAL * (wave * distortion + pulse) * length(VERTEX);
}

void fragment() {
    // Fresnel: calcula la inclinación respecto a la cámara. 
    // Centro transparente, bordes opacos y brillantes.
    float fresnel = pow(1.0 - dot(NORMAL, VIEW), edge_strength);
    
    // Ruido animado en las coordenadas de fragmento para simular flujo o turbulencia interna
    vec3 noise_pos = vec3(UV * noise_scale, TIME * wave_speed * 0.4);
    float noise_pattern = fbm(noise_pos);
    
    // Suavizado del patrón de ruido
    noise_pattern = smoothstep(0.15, 0.85, noise_pattern);
    
    // Combinamos fresnel con el ruido para dar el efecto de llamarada de energía
    float energy = fresnel * (0.6 + 0.4 * noise_pattern);
    
    // Albedo y Emisión (Multiplicado para efecto HDR)
    ALBEDO = aura_color.rgb;
    EMISSION = aura_color.rgb * energy * 4.0;
    ALPHA = clamp(energy * aura_color.a * 2.0, 0.0, 1.0);
}

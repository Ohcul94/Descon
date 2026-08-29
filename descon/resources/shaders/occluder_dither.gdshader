shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;
// Occluder Dither - B para paredes que tapan la cámara (GL Compatibility safe)
// Se usa como overlay/next_pass. No rompe el material base: solo hace discard dithered.
// Cuando fade=1 -> opaco, fade=0 -> totalmente descartado. Valores intermedios = screen-door transparency.
// Mantiene ordenamiento correcto sin los artefactos de TRANSPARENCY_ALPHA.
uniform float dither_fade : hint_range(0.0, 1.0) = 1.0;

// Bayer 4x4 - mucho más estable que hash aleatorio, sin textura externa.
float bayer4x4(vec2 p) {
    int x = int(mod(p.x, 4.0));
    int y = int(mod(p.y, 4.0));
    int idx = y * 4 + x;
    // Matriz 4x4 normalizada a 0-1 (16 niveles)
    if (idx == 0) return 0.0 / 16.0;
    if (idx == 1) return 8.0 / 16.0;
    if (idx == 2) return 2.0 / 16.0;
    if (idx == 3) return 10.0 / 16.0;
    if (idx == 4) return 12.0 / 16.0;
    if (idx == 5) return 4.0 / 16.0;
    if (idx == 6) return 14.0 / 16.0;
    if (idx == 7) return 6.0 / 16.0;
    if (idx == 8) return 3.0 / 16.0;
    if (idx == 9) return 11.0 / 16.0;
    if (idx == 10) return 1.0 / 16.0;
    if (idx == 11) return 9.0 / 16.0;
    if (idx == 12) return 15.0 / 16.0;
    if (idx == 13) return 7.0 / 16.0;
    if (idx == 14) return 13.0 / 16.0;
    return 5.0 / 16.0;
}

void fragment() {
    // Si no está desvanecido (dither_fade cerca de 1.0), descartamos por completo
    // el overlay para que no tape el material base con color negro.
    if (dither_fade >= 0.95) {
        discard;
    }

    // FRAGCOORD es estable en pantalla y no requiere sampler.
    float d = bayer4x4(FRAGCOORD.xy);
    // Si el dither supera el fade, descartamos el fragmento -> se ve el fondo / se transparenta.
    // Con fade 0.25, solo 25% de pixeles pasan -> apariencia 75% transparente sin sorting issues.
    if (d >= dither_fade) {
        discard;
    }
    // El overlay no necesita ALBEDO, solo debe no descartar. Ponemos alpha 1 para que el pass sea válido.
    ALBEDO = vec3(0.0);
    ALPHA = 1.0;
}

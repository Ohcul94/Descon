shader_type spatial;

render_mode blend_mix;

uniform sampler2D cloud_texture : source_color, filter_linear_mipmap, repeat_enable;

// Per-channel visibility sliders
uniform float red_opacity : hint_range(0.0, 1.0) = 1.0;
uniform float green_opacity : hint_range(0.0, 1.0) = 1.0;
uniform float blue_opacity : hint_range(0.0, 1.0) = 1.0;
uniform float alpha_opacity : hint_range(0.0, 1.0) = 1.0;

varying vec3 _vertex;

void vertex() {
    _vertex = VERTEX;
}

vec2 dir_to_uv(vec3 dir) {
    float phi = atan(dir.z, dir.x);
    float theta = acos(clamp(dir.y, -1.0, 1.0));
    float u = (phi + 3.14159265) / (2.0 * 3.14159265);
    float v = theta / 3.14159265;
    return vec2(u, v);
}

void fragment() {
    // Sample the equirectangular texture
    vec3 dir = normalize(_vertex);
    vec2 uv = dir_to_uv(dir);
    vec4 tex = texture(cloud_texture, uv);

    // Invert each channel (black = solid)
    tex.r = 1.0 - tex.r;
    tex.g = 1.0 - tex.g;
    tex.b = 1.0 - tex.b;
    tex.a = 1.0 - tex.a;

    // Apply per-channel visibility
    tex.r *= red_opacity;
    tex.g *= green_opacity;
    tex.b *= blue_opacity;
    tex.a *= alpha_opacity;

    // Combine channels to get alpha (max channel = solid)
    ALPHA = clamp(max(max(tex.r, tex.g), max(tex.b, tex.a)), 0.0, 1.0);

    // Color can be white (or black, doesn't matter)
    ALBEDO = vec3(1.0);
}

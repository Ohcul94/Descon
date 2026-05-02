shader_type canvas_item;

uniform float hit_opacity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	// v260.10: Reducimos el factor de mezcla para que sea más sutil (transparente)
	vec3 final_color = mix(tex_color.rgb, flash_color.rgb, hit_opacity * 0.5);
	COLOR = vec4(final_color, tex_color.a);
}

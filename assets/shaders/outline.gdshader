// Inverted-hull outline. Used as `next_pass` of the toon material.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.04, 0.03, 0.12, 1.0);
uniform float outline_width : hint_range(0.0, 0.2) = 0.03;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}

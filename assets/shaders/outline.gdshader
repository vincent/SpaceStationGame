// Inverted-hull outline. Used as `next_pass` of the toon materials.
// The width never drops below `outline_pixels` screen pixels (orthographic
// camera), so silhouettes stay inked in the zoomed-out station view.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

#include "res://assets/shaders/cutaway.gdshaderinc"

uniform vec4 outline_color : source_color = vec4(0.04, 0.03, 0.12, 1.0);
uniform float outline_width : hint_range(0.0, 0.2) = 0.03;
uniform float outline_pixels : hint_range(0.0, 4.0) = 1.2;
// True on station structure: outlines must not float over the cut opening.
uniform bool clip_enabled = false;

void vertex() {
	// Orthographic: PROJECTION_MATRIX[1][1] = 2 / view height (world units).
	float world_per_px = 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	VERTEX += NORMAL * max(outline_width, outline_pixels * world_per_px);
	v_world_pos = cut_world(MODEL_MATRIX, VERTEX);
}

void fragment() {
	if (clip_enabled && cut_enabled && cut_inside(v_world_pos, 0.0)) {
		discard;
	}
	ALBEDO = outline_color.rgb;
}

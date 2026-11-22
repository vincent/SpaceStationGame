// Cel shading for everything that is NOT cut by the cutaway (characters,
// furniture, floors, props). Station structure uses toon_cut.gdshader.
shader_type spatial;
render_mode cull_back;

#include "res://assets/shaders/toon_common.gdshaderinc"

// Imported art props: vertex colour G (emissive mask) glows in the texture colour.
uniform bool mask_emission = false;
uniform float mask_emission_energy : hint_range(0.0, 8.0) = 2.5;

void vertex() {
	v_paint_uv = use_paint ? paint_uv_for(paint_dir, UV2, CUSTOM0, CUSTOM1) : vec2(-1.0);
}

void fragment() {
	ALBEDO = albedo.rgb * texture(albedo_texture, UV).rgb;
	// Night: emissives dominate a dimmed interior.
	EMISSION = emission_color.rgb * emission_energy * (1.0 + 0.5 * interior_warmth);
	if (use_paint && v_paint_uv.x >= 0.0) {
		vec3 paint = texture(paint_texture, v_paint_uv).rgb;
		ALBEDO = paint * (1.0 - paint_flatness);
		EMISSION += paint * paint_flatness;
	}
	if (mask_emission) {
		EMISSION += texture(albedo_texture, UV).rgb * COLOR.g * mask_emission_energy;
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

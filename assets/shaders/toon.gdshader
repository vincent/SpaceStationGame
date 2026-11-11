// Cel shading for everything that is NOT cut by the cutaway (characters,
// furniture, floors, props). Station structure uses toon_cut.gdshader.
shader_type spatial;
render_mode cull_back;

#include "res://assets/shaders/toon_common.gdshaderinc"

void fragment() {
	ALBEDO = albedo.rgb * texture(albedo_texture, UV).rgb;
	// Night: emissives dominate a dimmed interior.
	EMISSION = emission_color.rgb * emission_energy * (1.0 + 0.5 * interior_warmth);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

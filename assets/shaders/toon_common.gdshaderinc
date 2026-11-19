// Cel-shading light model shared by toon.gdshader and toon_cut.gdshader:
// hard light bands, colored shadows (from the environment ambient light) and
// a neon rim light.

uniform vec4 albedo : source_color = vec4(0.5, 0.5, 0.55, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_white;
uniform float bands : hint_range(1.0, 6.0, 1.0) = 3.0;
uniform float band_softness : hint_range(0.0, 0.2) = 0.02;
uniform vec4 rim_color : source_color = vec4(0.87, 0.89, 1.0, 1.0);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.15;
uniform float rim_width : hint_range(0.0, 1.0) = 0.25;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 8.0) = 0.0;

// 0 = cool work light (day), 1 = warm night light. Set by ClockLighting.
global uniform float interior_warmth;

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	// Quantize into hard bands; band_softness smooths the edges a bit.
	float scaled = ndl * bands;
	float band = floor(scaled);
	float edge = smoothstep(0.5 - band_softness, 0.5 + band_softness, fract(scaled));
	float lit = (band + edge) / bands;
	DIFFUSE_LIGHT += lit * LIGHT_COLOR / PI;

	// Rim light on silhouettes facing the light.
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	rim = step(1.0 - rim_width, rim) * step(0.05, ndl);
	SPECULAR_LIGHT += rim * rim_strength * rim_color.rgb * LIGHT_COLOR / PI;
}

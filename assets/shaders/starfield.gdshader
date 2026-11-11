// Procedural deep-space background drawn on the Backdrop quad (a child of
// the camera). Screen-space, so it suits the orthographic camera.
shader_type spatial;
render_mode unshaded, shadows_disabled, cull_disabled, fog_disabled;

uniform vec4 top_color : source_color = vec4(0.043, 0.039, 0.141, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.26, 0.09, 0.42, 1.0);
uniform float star_density : hint_range(0.0, 1.0) = 0.05;
// Size in pixels of the grid cell that holds at most one star.
uniform float cell_pixels = 6.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec3 col = mix(top_color.rgb, bottom_color.rgb, pow(SCREEN_UV.y, 1.6));
	vec2 cell = floor(FRAGCOORD.xy / cell_pixels);
	float h = hash(cell);
	if (h < star_density) {
		vec2 local = fract(FRAGCOORD.xy / cell_pixels) - 0.5;
		float twinkle = 0.6 + 0.4 * sin(TIME * (1.0 + h * 40.0) + h * 100.0);
		float star = smoothstep(0.35, 0.0, length(local)) * twinkle;
		vec3 tint = mix(vec3(1.0, 0.95, 0.8), vec3(0.6, 0.9, 1.0), hash(cell + 7.0));
		col += tint * star * (h / star_density);
	}
	ALBEDO = col;
}

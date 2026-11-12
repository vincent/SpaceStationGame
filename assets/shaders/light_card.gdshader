// Fake light: an additive radial pool on the floor under each interior light.
// Cheaper than real lights on the Mobile renderer.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.6, 0.95, 1.0, 1.0);
// Per card (each card has its own material copy, set by Module).
uniform float intensity = 1.0;
// Overrides `color` when set (clock lighting tints the pools at night).
uniform vec4 tint : source_color = vec4(0.0);

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float a = pow(clamp(1.0 - r, 0.0, 1.0), 2.2);
	vec3 c = tint.a > 0.0 ? tint.rgb : color.rgb;
	ALBEDO = c * a * intensity * 0.45;
}

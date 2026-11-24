// Nebula baked once into a tileable texture (Backdrop's SubViewport, then
// sampled by starfield.gdshader). Domain-warped fBm clouds, tinted along a
// deep blue -> violet -> teal ramp, crossed by a diagonal galactic band and
// cut by darker dust lanes. RGB = colour, A = density (0..1).
shader_type canvas_item;
render_mode blend_disabled;

#include "res://assets/shaders/noise.gdshaderinc"

uniform vec4 color_deep : source_color = vec4(0.106, 0.165, 0.42, 1.0);
uniform vec4 color_violet : source_color = vec4(0.353, 0.227, 0.541, 1.0);
uniform vec4 color_teal : source_color = vec4(0.184, 0.498, 0.561, 1.0);
uniform vec4 color_core : source_color = vec4(0.62, 0.66, 0.9, 1.0);
// Changes the whole sky (cells of every noise field).
uniform int seed = 3;
// Base noise cells per tile (integer, keeps the texture tileable).
uniform float period = 4.0;

void fragment() {
	uint s = uint(seed) * 31u;
	vec2 p = UV * period;
	// Domain warp: the clouds curl instead of looking like plain fBm blobs.
	vec2 q = vec2(fbm_tiled(p, period, 4, s + 1u), fbm_tiled(p + 5.2, period, 4, s + 2u));
	vec2 r = vec2(fbm_tiled(p + 3.0 * q, period, 4, s + 3u),
			fbm_tiled(p + 3.0 * q + 1.7, period, 4, s + 4u));
	float body = fbm_tiled(p + 2.5 * r, period, 5, s + 5u);
	float hue = fbm_tiled(p * 1.0 + 2.0 * q, period, 3, s + 6u);
	float dust = fbm_tiled(p * 2.0 + 4.0 * r, period * 2.0, 4, s + 7u);

	// Diagonal galactic band, periodic over the tile (one band per tile).
	float along = UV.x - UV.y + (r.x - 0.5) * 0.25;
	float band = pow(0.5 + 0.5 * cos(6.2831853 * along), 3.0);

	float density = smoothstep(0.38, 0.8, body) * (0.3 + 0.7 * band);
	density += band * 0.18;                                  // faint glow of the band itself
	density *= 1.0 - 0.75 * smoothstep(0.5, 0.75, dust);     // dust lanes
	density = clamp(density, 0.0, 1.0);

	// Hue drifts deep blue <-> violet across the sky; the dense parts of the
	// bluer regions turn teal, the densest cores pale. Brightness follows density
	// (an emission nebula glows where it's thick).
	vec3 col = mix(color_deep.rgb, color_violet.rgb, smoothstep(0.38, 0.62, hue));
	float teal = smoothstep(0.25, 0.65, density) * (1.0 - smoothstep(0.42, 0.58, hue));
	col = mix(col, color_teal.rgb, teal * 0.85);
	col = mix(col, color_core.rgb, smoothstep(0.6, 1.0, density) * 0.45);
	col *= 0.7 + 0.6 * density;
	COLOR = vec4(col, density);
}

// Procedural deep-space background drawn on the Backdrop quad (a child of
// the camera). Screen-space, so it suits the orthographic camera.
// Layers, back to front: a 3-stop diagonal gradient with a soft vignette, the
// nebula (baked once by Backdrop into `nebula_tex`, tileable), then three star
// layers (dim specks, stars, rare "+" sparkles), each jittered in its own grid
// cell with an integer hash. The specks crowd into the nebula band; bright
// stars carry a soft coloured halo. Deeper layers drift less (parallax).
shader_type spatial;
render_mode unshaded, shadows_disabled, cull_disabled, fog_disabled;

#include "res://assets/shaders/noise.gdshaderinc"

uniform vec4 top_color : source_color = vec4(0.063, 0.063, 0.161, 1.0);
uniform vec4 mid_color : source_color = vec4(0.078, 0.098, 0.208, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.11, 0.082, 0.2, 1.0);
uniform float vignette : hint_range(0.0, 1.0) = 0.35;
uniform sampler2D nebula_tex : source_color, repeat_enable, filter_linear;
uniform float nebula_strength : hint_range(0.0, 1.0) = 0.45;
// Nebula tile size as a multiple of the screen height.
uniform float nebula_scale = 1.6;
uniform float halo_strength : hint_range(0.0, 2.0) = 1.0;
uniform float star_density : hint_range(0.0, 1.0) = 0.025;
// Size in pixels of the grid cell that holds at most one star (smallest layer).
uniform float cell_pixels = 6.0;
// Slow parallax drift (pixels), set by Backdrop from the camera position.
uniform vec2 parallax = vec2(0.0);

// Star colours: warm white, pale yellow, teal, blue.
vec3 star_tint(float t) {
	if (t < 0.4) return vec3(1.0, 0.95, 0.86);
	if (t < 0.6) return vec3(1.0, 0.86, 0.55);
	if (t < 0.8) return vec3(0.55, 0.95, 0.92);
	return vec3(0.7, 0.8, 1.0);
}

// One star in cell `id` of a layer, seen from pixel `px`.
// `halo` = soft glow radius in px (0 = none).
vec3 star_at(vec2 px, vec2 id, float cell, float density, float size, float bright,
		uint layer, bool sparkle, float halo) {
	vec2 r = rand2(id, layer);
	if (r.x >= density) {
		return vec3(0.0);
	}
	vec2 j = rand2(id, layer + 17u);
	vec2 centre = (id + 0.2 + 0.6 * j) * cell;            // jittered inside the cell
	vec2 d = px - centre;
	float dist = length(d);
	float k = min(r.x / max(density, 1e-4), 1.0);          // 0..1: per-star brightness
	float s = size * (0.6 + 0.6 * j.x);
	float star = smoothstep(s, 0.0, dist);
	if (sparkle) {                                         // thin "+" rays
		float ray = s * 2.6;
		star += smoothstep(0.9, 0.0, abs(d.y)) * smoothstep(ray, 0.0, abs(d.x)) * 0.6;
		star += smoothstep(0.9, 0.0, abs(d.x)) * smoothstep(ray, 0.0, abs(d.y)) * 0.6;
	}
	float twinkle = 0.75 + 0.25 * sin(TIME * (0.6 + j.y * 2.5) + j.x * 50.0);
	vec3 tint = star_tint(rand2(id, layer + 31u).x);
	float b = bright * (0.45 + 0.55 * k) * twinkle;
	vec3 col = tint * star * b;
	// Halo only on the brightest stars of the layer.
	if (halo > 0.0 && k > 0.55) {
		float h = halo * (0.6 + 0.8 * j.y);
		col += tint * exp(-dist * dist / (h * h)) * b * 0.3 * halo_strength;
	}
	return col;
}

// One layer: `cell` px grid, `density` = chance a cell holds a star, `size` px
// radius. With a halo, the 3x3 neighbour cells are visited so glows aren't
// clipped at cell borders.
vec3 star_layer(vec2 px, float cell, float density, float size, float bright, uint layer,
		bool sparkle, float halo) {
	vec2 id = floor(px / cell);
	if (halo <= 0.0) {
		return star_at(px, id, cell, density, size, bright, layer, sparkle, 0.0);
	}
	vec3 col = vec3(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			col += star_at(px, id + vec2(float(x), float(y)), cell, density, size, bright,
					layer, sparkle, halo);
		}
	}
	return col;
}

// Clusters and voids: the density follows a slow noise over the sky.
float clump(vec2 px, uint layer) {
	return smoothstep(0.25, 0.85, value_noise(px / 260.0 + float(layer) * 3.7));
}

void fragment() {
	vec2 aspect = vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0);
	vec2 uv = SCREEN_UV;
	// Diagonal 3-stop gradient (top-left -> bottom-right).
	float t = clamp(dot(uv - 0.5, normalize(vec2(0.45, 1.0))) + 0.5, 0.0, 1.0);
	vec3 col = t < 0.5 ? mix(top_color.rgb, mid_color.rgb, t * 2.0)
			: mix(mid_color.rgb, bottom_color.rgb, t * 2.0 - 1.0);

	vec2 px = FRAGCOORD.xy;
	// Nebula: slowest layer (same drift as the dim specks).
	vec2 neb_px = px + parallax * 0.5;
	vec4 neb = texture(nebula_tex, neb_px / (VIEWPORT_SIZE.y * nebula_scale));
	col = mix(col, neb.rgb, neb.a * nebula_strength);

	// Specks crowd into the nebula band, avoid dust lanes.
	float speck_density = star_density * 0.5 * (0.25 + 1.6 * neb.a + 0.5 * clump(neb_px, 1u));
	col += star_layer(neb_px, cell_pixels, speck_density, 0.9, 0.45, 1u, false, 0.0);
	vec2 p2 = px + parallax;
	col += star_layer(p2, cell_pixels * 3.0, star_density * 3.2 * (0.35 + 1.3 * clump(p2, 2u)),
			1.7, 1.3, 2u, false, 0.0);
	vec2 p3 = px + parallax * 1.4;
	col += star_layer(p3, cell_pixels * 16.0, star_density * 6.0 * (0.35 + 1.3 * clump(p3, 3u)),
			1.6, 1.1, 3u, true, 9.0);

	// Soft vignette: corners darker, centre untouched.
	float v = smoothstep(0.35, 1.05, length((uv - 0.5) * aspect));
	col *= 1.0 - vignette * v;
	// Dither against gradient banding (8-bit targets on mobile).
	col += (rand2(floor(px), 5u).x - 0.5) * 0.4 / 255.0;
	ALBEDO = col;
}

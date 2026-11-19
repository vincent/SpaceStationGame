// Procedural deep-space background drawn on the Backdrop quad (a child of
// the camera). Screen-space, so it suits the orthographic camera.
// Three star layers (dim specks, stars, rare "+" sparkles), each jittered in its
// own grid cell with an integer hash (no sin(): it turns into visible patterns at
// large coordinates), thinned by a low-frequency noise so they cluster instead of
// spreading evenly. Deeper layers drift less (parallax).
shader_type spatial;
render_mode unshaded, shadows_disabled, cull_disabled, fog_disabled;

uniform vec4 top_color : source_color = vec4(0.078, 0.082, 0.149, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.106, 0.11, 0.18, 1.0);
// Soft glow in the middle of the screen (the mockups' vignette).
uniform vec4 glow_color : source_color = vec4(0.13, 0.137, 0.212, 1.0);
uniform float star_density : hint_range(0.0, 1.0) = 0.025;
// Size in pixels of the grid cell that holds at most one star (smallest layer).
uniform float cell_pixels = 6.0;
// Slow parallax drift (pixels), set by Backdrop from the camera position.
uniform vec2 parallax = vec2(0.0);

uvec2 pcg2d(uvec2 v) {
	v = v * 1664525u + 1013904223u;
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v = v ^ (v >> 16u);
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v = v ^ (v >> 16u);
	return v;
}

// Two uniform randoms in [0, 1) for an integer cell (any sign).
vec2 rand2(vec2 cell, uint layer) {
	uvec2 h = pcg2d(uvec2(ivec2(cell) + ivec2(40000)) + uvec2(layer * 7919u, layer * 104729u));
	return vec2(h) / 4294967296.0;
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = rand2(i, 9u).x;
	float b = rand2(i + vec2(1.0, 0.0), 9u).x;
	float c = rand2(i + vec2(0.0, 1.0), 9u).x;
	float d = rand2(i + vec2(1.0, 1.0), 9u).x;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// One layer: `cell` px grid, `density` = chance a cell holds a star, `size` px radius.
vec3 star_layer(vec2 px, float cell, float density, float size, float bright, uint layer, bool sparkle) {
	vec2 g = px / cell;
	vec2 id = floor(g);
	vec2 r = rand2(id, layer);
	// Clusters and voids: the density follows a slow noise over the sky.
	float clump = smoothstep(0.25, 0.85, value_noise(px / 260.0 + float(layer) * 3.7));
	if (r.x >= density * (0.35 + 1.3 * clump)) {
		return vec3(0.0);
	}
	vec2 j = rand2(id, layer + 17u);
	vec2 centre = (id + 0.2 + 0.6 * j) * cell;            // jittered inside the cell
	vec2 d = px - centre;
	float k = r.x / max(density, 1e-4);                    // 0..~1.6: per-star brightness
	float s = size * (0.6 + 0.6 * j.x);
	float star = smoothstep(s, 0.0, length(d));
	if (sparkle) {                                         // thin "+" rays
		float ray = s * 3.2;
		star += smoothstep(0.9, 0.0, abs(d.y)) * smoothstep(ray, 0.0, abs(d.x)) * 0.7;
		star += smoothstep(0.9, 0.0, abs(d.x)) * smoothstep(ray, 0.0, abs(d.y)) * 0.7;
	}
	float twinkle = 0.75 + 0.25 * sin(TIME * (0.6 + j.y * 2.5) + j.x * 50.0);
	vec3 tint = mix(vec3(1.0, 0.95, 0.85), vec3(0.75, 0.85, 1.0), j.y);
	return tint * star * bright * (0.45 + 0.55 * min(k, 1.0)) * twinkle;
}

void fragment() {
	vec3 col = mix(top_color.rgb, bottom_color.rgb, pow(SCREEN_UV.y, 1.6));
	vec2 aspect = vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0);
	float glow = 1.0 - smoothstep(0.0, 0.75, length((SCREEN_UV - 0.5) * aspect));
	col = mix(col, glow_color.rgb, glow * 0.6);
	vec2 px = FRAGCOORD.xy;
	col += star_layer(px + parallax * 0.5, cell_pixels, star_density * 0.5, 0.9, 0.45, 1u, false);
	col += star_layer(px + parallax, cell_pixels * 3.0, star_density * 3.2, 1.7, 1.4, 2u, false);
	col += star_layer(px + parallax * 1.4, cell_pixels * 16.0, star_density * 6.0, 1.6, 1.1, 3u, true);
	ALBEDO = col;
}

// Shared hash + value noise for the space backdrop (starfield, nebula bake).
// Integer hash (pcg2d): no sin(), which turns into visible patterns at large
// coordinates.

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

// Value noise that tiles every `period` cells (integer period).
float value_noise_tiled(vec2 p, float period, uint layer) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	vec2 i0 = mod(i, period);
	vec2 i1 = mod(i + 1.0, period);
	float a = rand2(i0, layer).x;
	float b = rand2(vec2(i1.x, i0.y), layer).x;
	float c = rand2(vec2(i0.x, i1.y), layer).x;
	float d = rand2(i1, layer).x;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Tileable fBm over p in [0, period): each octave doubles the frequency and
// the period, so the result wraps seamlessly at `period`.
float fbm_tiled(vec2 p, float period, int octaves, uint layer) {
	float sum = 0.0;
	float amp = 0.5;
	float norm = 0.0;
	for (int o = 0; o < octaves; o++) {
		sum += amp * value_noise_tiled(p, period, layer + uint(o) * 13u);
		norm += amp;
		p *= 2.0;
		period *= 2.0;
		amp *= 0.5;
	}
	return sum / norm;
}

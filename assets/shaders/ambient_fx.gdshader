// Node-free ambient animation for small props:
//   mode 0 = blinking LEDs (vertex colour R = phase)
//   mode 1 = flickering screen with scanlines
//   mode 2 = spinning fan (rotates around local Y)
//   mode 3 = swaying cable (bends along local -Y)
shader_type spatial;
render_mode cull_disabled;

#include "res://assets/shaders/cutaway.gdshaderinc"

uniform int mode = 0;
uniform vec4 color : source_color = vec4(0.18, 0.89, 0.9, 1.0);
uniform float energy = 3.0;
uniform float speed = 1.0;
// Driven by the module (powered_fx group); each fx mesh has its own material.
uniform float active = 1.0;

void vertex() {
	if (mode == 2) {
		float a = TIME * speed * 6.0;
		VERTEX.xz = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * VERTEX.xz;
	} else if (mode == 3) {
		float k = clamp(-VERTEX.y, 0.0, 2.0);
		VERTEX.x += sin(TIME * speed + k) * 0.06 * k * k;
	}
	v_world_pos = cut_world(MODEL_MATRIX, VERTEX);
}

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	if (cut_enabled && cut_inside(v_world_pos, 0.0) && mode >= 2) {
		discard;
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	if (mode == 0) {
		float on = step(0.45, fract(TIME * speed * (0.6 + COLOR.r) + COLOR.r * 7.0));
		ALBEDO = color.rgb * 0.2;
		EMISSION = color.rgb * energy * on * active;
	} else if (mode == 1) {
		float t = floor(TIME * 12.0);
		float flicker = 0.85 + 0.15 * hash(t) - 0.6 * step(0.97, hash(t + 3.0));
		float scan = 0.75 + 0.25 * sin(UV.y * 90.0 + TIME * 4.0);
		float bars = step(0.35, fract(UV.x * 3.0 + hash(floor(UV.y * 8.0) + floor(TIME * 0.5))));
		ALBEDO = vec3(0.02);
		EMISSION = color.rgb * energy * flicker * scan * mix(0.55, 1.0, bars) * active;
	} else {
		ALBEDO = color.rgb;
	}
}

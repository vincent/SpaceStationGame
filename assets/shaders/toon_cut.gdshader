// Cel shading for the station structure (hull, bulkheads, greebles, parts).
// Fragments inside the global cut box are discarded; back faces seen through
// the opening are painted as a flat "section" fill and an ink line runs along
// the cut edge. Meshes must be watertight with real thickness.
//
// Vertex colour masks (see docs/ART_PIPELINE.md):
//   R = wear mask (where rust and grime appear first)
//   G = emissive mask (running lights, screens) — lit only when powered
//   B = trim mask (mixes albedo towards trim_color: panels, stripes)
shader_type spatial;
render_mode cull_disabled;

#include "res://assets/shaders/cutaway.gdshaderinc"
#include "res://assets/shaders/toon_common.gdshaderinc"

uniform vec4 trim_color : source_color = vec4(0.16, 0.17, 0.2, 1.0);
uniform vec4 strip_color : source_color = vec4(0.18, 0.89, 0.9, 1.0);
uniform float strip_energy : hint_range(0.0, 8.0) = 3.0;
uniform vec4 rust_color : source_color = vec4(0.55, 0.25, 0.12, 1.0);
uniform vec4 sweep_color : source_color = vec4(1.0, 0.83, 0.1, 1.0);
// Imported art: the G-mask glow takes its colour from albedo_texture (the palette
// swatch) instead of strip_color, so a lamp glows amber and a screen cyan.
uniform bool emission_from_texture = false;

// Per module: each Module owns copies of its cut materials and sets these on
// them (plain uniforms: per-instance ones ran out of global slots past ~40 modules).
uniform vec4 cap_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float wear = 0.0;
uniform float power_level = 1.0;
// x = world X where power/repair sweeps start, y = where they end.
uniform vec2 sweep_range = vec2(-10.0, 10.0);
// 0 = idle, (0, 1] = repair sweep band position.
uniform float repair_flash = 0.0;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

void vertex() {
	v_world_pos = cut_world(MODEL_MATRIX, VERTEX);
	v_paint_uv = use_paint ? paint_uv_for(paint_dir, UV2, CUSTOM0, CUSTOM1) : vec2(-1.0);
}

void fragment() {
	if (cut_enabled && cut_inside(v_world_pos, 0.0)) {
		discard;
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	if (!FRONT_FACING) {
		// Looking into the wall thickness through the cut: flat section fill.
		vec3 cap = debug_backfaces ? vec3(1.0, 0.0, 1.0) : cut_cap_color.rgb * cap_tint.rgb;
		ALBEDO = cap * 0.35;
		EMISSION = cap * 0.55;
		NORMAL = vec3(0.0, 0.0, 1.0);
	} else {
		bool painted = use_paint && v_paint_uv.x >= 0.0;
		vec3 base = painted ? texture(paint_texture, v_paint_uv).rgb
				: mix(albedo.rgb, trim_color.rgb, COLOR.b) * texture(albedo_texture, UV).rgb;
		// Wear: 3D grunge noise in world space, gated by the R mask.
		float grunge = noise3(v_world_pos * 1.3) * 0.65 + noise3(v_world_pos * 4.7) * 0.35;
		float mask = COLOR.r * 0.35 + grunge * 0.7;
		float rust = smoothstep(1.0 - wear * 0.75, 1.05 - wear * 0.75, mask);
		base = mix(base, rust_color.rgb * (0.7 + 0.5 * grunge), rust * 0.85);
		base *= 1.0 - wear * (0.25 + 0.35 * grunge);

		// Emissive strips light up along X as power_level goes 0 -> 1.
		float front = mix(sweep_range.x - 1.0, sweep_range.y + 1.0, power_level);
		float powered = clamp((front - v_world_pos.x) * 2.0, 0.0, 1.0) * step(0.001, power_level);
		vec3 strip = emission_from_texture ? texture(albedo_texture, UV).rgb : strip_color.rgb;
		if (painted) {
			// The painting shows the lights on: dim the glow areas while unpowered.
			base *= mix(1.0, mix(0.35, 1.0, powered), COLOR.g);
			ALBEDO = base * (1.0 - paint_flatness);
			EMISSION = base * paint_flatness;
			EMISSION += strip * strip_energy * 0.35 * COLOR.g * powered * (1.0 + 0.5 * interior_warmth);
		} else {
			ALBEDO = base;
			EMISSION = strip * strip_energy * COLOR.g * powered * (1.0 + 0.5 * interior_warmth);
		}
		EMISSION += emission_color.rgb * emission_energy * power_level;

		if (repair_flash > 0.0) {
			float center = mix(sweep_range.x - 1.0, sweep_range.y + 1.0, repair_flash);
			float band = 1.0 - smoothstep(0.0, 0.7, abs(v_world_pos.x - center));
			EMISSION += sweep_color.rgb * band * 2.0;
		}
		if (cut_enabled && cut_inside(v_world_pos, cut_ink_width)) {
			// Thin band right next to the cut boundary: ink line along the edge.
			ALBEDO = ink_color.rgb;
			EMISSION = vec3(0.0);
		}
	}
}

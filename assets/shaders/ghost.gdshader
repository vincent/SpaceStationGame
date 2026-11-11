// Ghost outlines (empty slots, locked upgrade parts): glowing dashed ink,
// no fill. Used on thin edge geometry built by GhostMesher.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.18, 0.89, 0.9, 1.0);
uniform float dash_per_meter = 1.5;
uniform float intensity = 1.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = fract((v_world.x + v_world.y + v_world.z) * dash_per_meter - TIME * 0.4);
	if (d > 0.6) {
		discard;
	}
	float pulse = 0.7 + 0.3 * sin(TIME * 3.0);
	ALBEDO = color.rgb * pulse * intensity;
}

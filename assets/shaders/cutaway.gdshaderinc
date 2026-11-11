// Cutaway clipping shared by every material that belongs to the station
// structure (hull, bulkheads, greebles, module parts). The cut box is a
// world-space AABB driven by CutawayController through shader globals
// (declared in project.godot > [shader_globals]).

global uniform vec3 cut_min;
global uniform vec3 cut_max;
global uniform bool cut_enabled;
global uniform vec4 cut_cap_color;
global uniform float cut_ink_width;
global uniform vec4 ink_color;
// Debug: paint every visible back face magenta (a back face seen without a
// cut means the mesh has a hole).
global uniform bool debug_backfaces;

varying vec3 v_world_pos;

// From vertex(): `v_world_pos = cut_world(MODEL_MATRIX, VERTEX);`
// (Godot doesn't allow assigning varyings inside helper functions.)
vec3 cut_world(mat4 model, vec3 vertex) {
	return (model * vec4(vertex, 1.0)).xyz;
}

bool cut_inside(vec3 p, float grow) {
	return all(greaterThan(p, cut_min - grow)) && all(lessThan(p, cut_max + grow));
}

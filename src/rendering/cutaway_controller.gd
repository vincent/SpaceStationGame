class_name CutawayController
extends Node
## Drives the cutaway shader globals (project.godot > [shader_globals]): a
## world-space box around the focused module, from the cut height up to above
## its roof. Hull fragments inside the box are discarded, revealing the
## interior. The camera zoom opens and closes it:
##   t < 0.3      closed (beauty shot)
##   0.3 .. 0.7   the box grows down from the roof (the station "opens")
##   t > 0.7      fully open on the focused module
## Switching focus while open closes the old module, then opens the new one.

## Walls are sliced this high above the module floor (m).
const CUT_HEIGHT := 1.15
const OPEN_START := 0.3
const OPEN_END := 0.7
## Kept below Slot.GAP * 2 so a neighbour's hull is never nicked.
const MARGIN := 0.08
## Open/close animation speed (full range per second).
const SPEED := 3.5
## Below this zoom, small greebles are hidden (station view).
const DETAIL_T := 0.25

@export var camera: DioramaCamera
@export var enabled: bool = true
## Hold the hull closed whatever the zoom (exploded view, debug).
@export var force_closed: bool = false

var focus: Module
## Displayed opening, 0 = closed, 1 = fully open.
var open := 0.0
## Mirrors the `cut_enabled` global (readable in headless tests).
var cut_on := false

var _pending: Module
var _has_pending := false
var _shown_interior: Module
var _detail_on := true
var _visibility_dirty := true


func _ready() -> void:
	add_to_group(&"cutaway_controller")
	if camera:
		camera.focus_changed.connect(set_focus)
	RenderingServer.global_shader_parameter_set(&"cut_ink_width", 0.06)
	_apply()


func set_focus(target: Node3D) -> void:
	var module := target as Module
	if module == focus:
		_has_pending = false
		return
	if focus == null or open <= 0.01:
		focus = module
		_has_pending = false
	else:
		_pending = module
		_has_pending = true


## Opening wanted for zoom position `t`.
static func open_amount(t: float) -> float:
	return smoothstep(OPEN_START, OPEN_END, t)


## The cut box for a module whose (world) bounds are `module_aabb` and whose
## floor is at `floor_y`, opened by `amount` (0..1).
static func compute_box(
		module_aabb: AABB, floor_y: float, amount: float, cut_height: float = CUT_HEIGHT, margin: float = MARGIN
) -> AABB:
	var top := module_aabb.end.y + margin
	var bottom := lerpf(top, floor_y + cut_height, clampf(amount, 0.0, 1.0))
	var lo := Vector3(module_aabb.position.x - margin, bottom, module_aabb.position.z - margin)
	var hi := Vector3(module_aabb.end.x + margin, top, module_aabb.end.z + margin)
	return AABB(lo, hi - lo)


func get_box() -> AABB:
	if focus == null or not is_instance_valid(focus):
		return AABB()
	return compute_box(focus.get_cut_aabb(), focus.global_position.y, open)


func _process(delta: float) -> void:
	if focus != null and not is_instance_valid(focus):
		focus = null
	var goal := 0.0
	if not _has_pending and not force_closed and enabled and camera:
		goal = open_amount(camera.t)
	open = move_toward(open, goal, delta * SPEED)
	if _has_pending and open <= 0.01:
		focus = _pending
		_has_pending = false
	_apply()
	_update_visibility()


func _update_visibility() -> void:
	var show: Module = focus if cut_on else null
	var detail_on := camera == null or camera.t >= DETAIL_T
	if show == _shown_interior and detail_on == _detail_on and not _visibility_dirty:
		return
	_shown_interior = show
	_detail_on = detail_on
	_visibility_dirty = false
	for node in get_tree().get_nodes_in_group(&"station_module"):
		var m := node as Module
		m.set_interior_visible(m == show)
		m.set_detail_visible(detail_on)


## Call when modules were added or rebuilt.
func mark_visibility_dirty() -> void:
	_visibility_dirty = true


func _apply() -> void:
	var on := enabled and focus != null and open > 0.001
	cut_on = on
	RenderingServer.global_shader_parameter_set(&"cut_enabled", on)
	if on:
		var box := get_box()
		RenderingServer.global_shader_parameter_set(&"cut_min", box.position)
		RenderingServer.global_shader_parameter_set(&"cut_max", box.end)

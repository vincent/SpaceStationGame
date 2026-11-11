class_name DioramaCamera
extends Node3D
## Fixed oblique orthographic camera rig: the station is one object seen from
## outside, like a technical cutaway illustration. It never rotates from
## input. Zoom moves continuously between two tiers:
##   t = 0  station view: the whole station AABB (+ margin) fits the frame
##   t = 1  room view:    the focused module fits the frame
## Drag pans (clamped to the station), pinch/wheel zooms, focus_on() tweens.

signal zoom_changed(t: float)
signal focus_changed(target: Node3D)

enum Tier { STATION, ROOM }

@export_range(-89.0, 0.0) var pitch_deg: float = -28.0:
	set(value):
		pitch_deg = value
		_apply_rotation()
@export_range(-180.0, 180.0) var yaw_deg: float = 25.0:
	set(value):
		yaw_deg = value
		_apply_rotation()
## Camera distance from the look-at point (ortho: only affects clipping).
@export var distance: float = 80.0
@export var station_margin: float = 1.12
@export var room_margin: float = 1.25
@export var focus_seconds: float = 0.6
## Extra pan allowed beyond the station's projected bounds (world units).
@export var pan_margin: float = 4.0

## Zoom position: 0 = station view, 1 = room view.
var t := 0.0
## Look-at offset added by dragging (world units, in the camera plane).
var pan := Vector3.ZERO
var focus_target: Node3D
## Overrides the computed ortho size when > 0 (debug slider).
var size_override := 0.0
## False while a screen holds the camera (exploded view).
var input_enabled := true

var _station_aabb := AABB(Vector3(-10, -1, -10), Vector3(20, 4, 20))
var _focus_aabb := AABB(Vector3(-4, -1, -4), Vector3(8, 4, 8))
var _tween: Tween
var _touches: Dictionary[int, Vector2] = {}
var _pinch_start_distance := 0.0
var _pinch_start_size := 0.0
var _last_gesture_msec := -10000
var _drag_from := Vector2.INF
var _dragging := false

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = distance * 2.0
	camera.position = Vector3(0, 0, distance)
	_apply_rotation()
	_update_camera()


func set_station_aabb(aabb: AABB) -> void:
	_station_aabb = aabb
	_update_camera()


func get_station_aabb() -> AABB:
	return _station_aabb


## Focus a node (a Module, or anything with get_world_aabb()). Tweens to the
## room tier unless `tier` is STATION; `instant` skips the tween.
func focus_on(target: Node3D, tier: Tier = Tier.ROOM, instant: bool = false) -> void:
	var changed := target != focus_target
	focus_target = target
	if target and target.has_method(&"get_world_aabb"):
		_focus_aabb = target.call(&"get_world_aabb")
	var goal := 1.0 if tier == Tier.ROOM else 0.0
	if _tween:
		_tween.kill()
	if instant:
		pan = Vector3.ZERO
		_set_t(goal)
	else:
		_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_tween.tween_method(_set_t, t, goal, focus_seconds)
		_tween.tween_property(self, "pan", Vector3.ZERO, focus_seconds)
	if changed:
		focus_changed.emit(target)


func is_tweening() -> bool:
	return _tween != null and _tween.is_running()


## True while (or right after) a multi-touch gesture or a drag, so the
## release that ends it isn't treated as a tap.
func is_gesturing() -> bool:
	return _dragging or _touches.size() >= 2 or Time.get_ticks_msec() - _last_gesture_msec < 250


func get_view_size() -> float:
	return camera.size


## Ortho size for zoom position `zoom_t` (geometric blend between tiers).
func size_at(zoom_t: float) -> float:
	var aspect := _aspect()
	var s0 := fit(_station_aabb, global_basis, aspect, station_margin).size as float
	var s1 := fit(_focus_aabb, global_basis, aspect, room_margin).size as float
	s1 = minf(s1, s0)
	return s0 * pow(s1 / s0, clampf(zoom_t, 0.0, 1.0))


## Zoom position giving ortho size `size` (inverse of size_at()).
func t_for_size(size: float) -> float:
	var s0 := size_at(0.0)
	var s1 := size_at(1.0)
	if is_equal_approx(s0, s1):
		return t
	return clampf(log(size / s0) / log(s1 / s0), 0.0, 1.0)


## Ortho size and centre that frame `aabb` seen through `basis`.
## Returns {size: float, center: Vector3}.
static func fit(aabb: AABB, basis: Basis, aspect: float, margin: float) -> Dictionary:
	var right := basis.x
	var up := basis.y
	var fwd := -basis.z
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var p := aabb.get_endpoint(i)
		var v := Vector2(p.dot(right), p.dot(up))
		lo = lo.min(v)
		hi = hi.max(v)
	var extent := hi - lo
	var size := maxf(extent.y, extent.x / maxf(aspect, 0.01)) * margin
	var mid := (lo + hi) * 0.5
	var center := right * mid.x + up * mid.y + fwd * aabb.get_center().dot(fwd)
	return {"size": size, "center": center}


## Clamps a look-at point so the view never leaves the station (+ margin).
static func clamp_to_aabb(point: Vector3, aabb: AABB, basis: Basis, margin: float) -> Vector3:
	var right := basis.x
	var up := basis.y
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var p := aabb.get_endpoint(i)
		var v := Vector2(p.dot(right), p.dot(up))
		lo = lo.min(v)
		hi = hi.max(v)
	var v := Vector2(point.dot(right), point.dot(up))
	var c := v.clamp(lo - Vector2.ONE * margin, hi + Vector2.ONE * margin)
	return point + right * (c.x - v.x) + up * (c.y - v.y)


func _aspect() -> float:
	if not is_inside_tree():
		return 16.0 / 9.0
	var view := get_viewport().get_visible_rect().size
	return view.x / maxf(view.y, 1.0)


func _set_t(value: float) -> void:
	var before := t
	t = clampf(value, 0.0, 1.0)
	_update_camera()
	if not is_equal_approx(before, t):
		zoom_changed.emit(t)


func _apply_rotation() -> void:
	rotation_degrees = Vector3(pitch_deg, yaw_deg, 0.0)
	if is_inside_tree() and camera:
		_update_camera()


func _update_camera() -> void:
	if camera == null:
		return
	var aspect := _aspect()
	var c0: Vector3 = fit(_station_aabb, global_basis, aspect, station_margin).center
	var c1: Vector3 = fit(_focus_aabb, global_basis, aspect, room_margin).center
	var look := c0.lerp(c1, t) + pan
	look = clamp_to_aabb(look, _station_aabb, global_basis, pan_margin)
	pan = look - c0.lerp(c1, t)
	global_position = look
	camera.size = size_override if size_override > 0.0 else size_at(t)


func _process(_delta: float) -> void:
	# Keeps framing right when the window is resized / rotated.
	if Engine.get_process_frames() % 30 == 0:
		_update_camera()


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(1.0 / 0.9)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(0.9)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_drag_from = event.position if event.pressed else Vector2.INF
			if not event.pressed and _dragging:
				_dragging = false
				_last_gesture_msec = Time.get_ticks_msec()
	elif event is InputEventMouseMotion and _drag_from != Vector2.INF and _touches.size() < 2:
		if not _dragging and event.position.distance_to(_drag_from) > 18.0:
			_dragging = true
		if _dragging:
			_pan_pixels(event.relative)
	elif event is InputEventMagnifyGesture:
		_zoom_by(event.factor)
		_last_gesture_msec = Time.get_ticks_msec()
	elif event is InputEventPanGesture:
		_pan_pixels(-event.delta * 8.0)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		_pinch_start_distance = 0.0
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() == 2:
			_update_pinch()


## factor > 1 zooms in (towards room view).
func _zoom_by(factor: float) -> void:
	if _tween:
		_tween.kill()
	_set_t(t_for_size(camera.size / factor))


func _pan_pixels(relative: Vector2) -> void:
	if _tween:
		_tween.kill()
	var world_per_px := camera.size / maxf(get_viewport().get_visible_rect().size.y, 1.0)
	pan += (-global_basis.x * relative.x + global_basis.y * relative.y) * world_per_px
	_update_camera()


func _update_pinch() -> void:
	var points := _touches.values()
	var dist: float = (points[0] as Vector2).distance_to(points[1])
	if _pinch_start_distance <= 0.0:
		_pinch_start_distance = dist
		_pinch_start_size = camera.size
	elif dist > 1.0:
		if _tween:
			_tween.kill()
		_set_t(t_for_size(_pinch_start_size * _pinch_start_distance / dist))
	_last_gesture_msec = Time.get_ticks_msec()

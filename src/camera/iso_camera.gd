class_name IsoCamera
extends Camera3D
## Orthographic isometric camera that follows a target.
## Zoom: mouse wheel, trackpad pinch, or two-finger pinch on touch screens.

const ISO_ROTATION := Vector3(-35.264, 45.0, 0.0)

@export var target: Node3D
@export var distance: float = 40.0
@export var zoom: float = 18.0
@export var min_zoom: float = 8.0
@export var max_zoom: float = 36.0
@export var follow_speed: float = 6.0

var _touches: Dictionary[int, Vector2] = {}
var _pinch_start_distance := 0.0
var _pinch_start_zoom := 0.0
var _last_gesture_msec := -10000


func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	rotation_degrees = ISO_ROTATION
	size = zoom
	near = 0.1
	far = distance * 2.0
	snap_to_target()


func snap_to_target() -> void:
	if target:
		global_position = _desired_position()


## True while (or right after) a multi-touch gesture, so taps can be ignored.
func is_gesturing() -> bool:
	return _touches.size() >= 2 or Time.get_ticks_msec() - _last_gesture_msec < 250


func set_zoom(value: float) -> void:
	zoom = clampf(value, min_zoom, max_zoom)


func _process(delta: float) -> void:
	var t := 1.0 - exp(-follow_speed * delta)
	if target:
		global_position = global_position.lerp(_desired_position(), t)
	size = lerpf(size, zoom, t)


func _desired_position() -> Vector3:
	return target.global_position + global_basis.z * distance


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_zoom(zoom * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_zoom(zoom * 1.1)
	elif event is InputEventMagnifyGesture:
		set_zoom(zoom / event.factor)
		_last_gesture_msec = Time.get_ticks_msec()
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


func _update_pinch() -> void:
	var points := _touches.values()
	var dist: float = (points[0] as Vector2).distance_to(points[1])
	if _pinch_start_distance <= 0.0:
		_pinch_start_distance = dist
		_pinch_start_zoom = zoom
	elif dist > 1.0:
		set_zoom(_pinch_start_zoom * _pinch_start_distance / dist)
	_last_gesture_msec = Time.get_ticks_msec()

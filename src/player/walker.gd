class_name Walker
extends CharacterBody3D
## A character that walks along the station's navigation mesh (the castaway,
## crew). Modules are joined by NavigationLink3D, so one target anywhere on
## the station is enough. Expects a `NavigationAgent3D` and a `Model` child.

signal move_started(target: Vector3)
signal arrived

## Blocked this long (s) while walking: hop to the next path point. Safety
## net for doorways where a navigation link cuts a corner past a collider.
const STUCK_SECONDS := 0.6
## Below this fraction of the expected step, a frame counts as blocked.
const STUCK_RATIO := 0.15

@export var speed: float = 3.5
@export var turn_speed: float = 12.0

## False until the navigation map has synced after the runtime bake; orders
## given before that are kept and executed once it is ready.
var navigation_ready := false:
	set(value):
		navigation_ready = value
		if value and _moving:
			agent.target_position = agent.target_position  # force a repath

var _moving := false
var _stuck := 0.0

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var model: Node3D = $Model


func _ready() -> void:
	collision_mask = Layers.WORLD | Layers.WALLS
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	# Baked path points float ~1 navmesh cell above the floor; these distances
	# must stay larger than that or the agent never advances along its path.
	agent.path_height_offset = 0.25
	agent.path_desired_distance = 0.5
	agent.target_desired_distance = 0.4


## Toon colors: meshes named Accent* glow in `accent`, the rest is `body`.
func paint(body: Color, accent: Color) -> void:
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var is_accent := mesh.name.begins_with("Accent")
		mesh.material_override = ToonMaterials.get_material(accent if is_accent else body, 2.5 if is_accent else 0.0)


func is_moving() -> bool:
	return _moving


func move_to(target: Vector3) -> void:
	_go(target)


func stop() -> void:
	_moving = false
	velocity = Vector3.ZERO


func teleport(pos: Vector3) -> void:
	stop()
	global_position = pos


## Waits until the navigation map (which syncs asynchronously after the
## per-module bakes) contains this walker's position, then sets
## `navigation_ready`. Returns false if it never does.
func await_navigation(frames: int = 600) -> bool:
	navigation_ready = false
	var map := get_world_3d().navigation_map
	for i in frames:
		await get_tree().physics_frame
		if not is_inside_tree():
			return false
		if NavigationServer3D.map_get_iteration_id(map) > 0 and \
				NavigationServer3D.map_get_closest_point(map, global_position).distance_to(global_position) < 1.0:
			navigation_ready = true
			return true
	return false


func _go(target: Vector3) -> void:
	agent.target_position = target
	_moving = true
	move_started.emit(target)


func _physics_process(delta: float) -> void:
	if not _moving or not navigation_ready:
		return
	if agent.is_navigation_finished():
		_arrive()
		return
	var to_next := agent.get_next_path_position() - global_position
	to_next.y = 0.0
	if to_next.length_squared() < 0.0001:
		return
	var dir := to_next.normalized()
	velocity = dir * speed
	var before := global_position
	move_and_slide()
	_face(dir, delta)
	_check_stuck(before, delta)


func _check_stuck(before: Vector3, delta: float) -> void:
	if _flat_distance(before, global_position) >= speed * delta * STUCK_RATIO:
		_stuck = 0.0
		return
	_stuck += delta
	if _stuck < STUCK_SECONDS:
		return
	_stuck = 0.0
	var next := agent.get_next_path_position()
	print_verbose("%s stuck at %s: hopping to %s" % [name, global_position, next])
	global_position = Vector3(next.x, global_position.y, next.z)


func _arrive() -> void:
	_moving = false
	velocity = Vector3.ZERO
	arrived.emit()


func _face(dir: Vector3, delta: float) -> void:
	var target_angle := atan2(dir.x, dir.z)
	model.rotation.y = lerp_angle(model.rotation.y, target_angle, 1.0 - exp(-turn_speed * delta))


## Turns the model to look at `point` (no tween).
func face_point(point: Vector3) -> void:
	var to := point - global_position
	to.y = 0.0
	if to.length_squared() > 0.001:
		model.rotation.y = atan2(to.x, to.z)


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

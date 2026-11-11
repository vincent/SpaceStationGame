class_name Player
extends CharacterBody3D
## The castaway. Walks along the navigation mesh to a tapped point, or to an
## object's approach point and then asks for its action menu.

signal move_started(target: Vector3)
signal arrived

@export var speed: float = 3.5
@export var turn_speed: float = 12.0
## How close (m) the player must get to an object's approach point.
@export var interact_reach: float = 0.8

## False until the navigation map has synced after the runtime bake; orders
## given before that are kept and executed once it is ready.
var navigation_ready := false:
	set(value):
		navigation_ready = value
		if value and _moving:
			agent.target_position = agent.target_position  # force a repath

var _pending: Interactable
var _moving := false

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var model: Node3D = $Model


func _ready() -> void:
	add_to_group(&"player")
	collision_layer = Layers.PLAYER
	collision_mask = Layers.WORLD | Layers.WALLS
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	# Baked path points float ~1 navmesh cell above the floor; these distances
	# must stay larger than that or the agent never advances along its path.
	agent.path_height_offset = 0.25
	agent.path_desired_distance = 0.5
	agent.target_desired_distance = 0.4
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var accent := mesh.name.begins_with("Accent")
		mesh.material_override = ToonMaterials.get_material(
			Palette.NEON_CYAN if accent else Palette.YELLOW, 2.5 if accent else 0.0)


func is_moving() -> bool:
	return _moving


func move_to(target: Vector3) -> void:
	_pending = null
	_go(target)


func interact_with(target: Interactable) -> void:
	_pending = target
	var approach := target.get_approach_position()
	if _flat_distance(global_position, approach) <= interact_reach:
		_arrive()
	else:
		_go(approach)


func stop() -> void:
	_moving = false
	_pending = null
	velocity = Vector3.ZERO


func teleport(pos: Vector3) -> void:
	stop()
	global_position = pos


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
	move_and_slide()
	_face(dir, delta)


func _arrive() -> void:
	_moving = false
	velocity = Vector3.ZERO
	arrived.emit()
	if _pending == null:
		return
	var target := _pending
	_pending = null
	if _flat_distance(global_position, target.get_approach_position()) > interact_reach * 1.5:
		EventBus.toast.emit("Can't reach the %s." % target.display_name.to_lower())
		return
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() > 0.001:
		model.rotation.y = atan2(to_target.x, to_target.z)
	EventBus.interaction_requested.emit(target)


func _face(dir: Vector3, delta: float) -> void:
	var target_angle := atan2(dir.x, dir.z)
	model.rotation.y = lerp_angle(model.rotation.y, target_angle, 1.0 - exp(-turn_speed * delta))


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

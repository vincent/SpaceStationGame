class_name CutawayController
extends Node
## Lowers walls standing between the camera and the player so the interior
## stays visible ("walls down" like in The Sims). Works on every node in the
## "cutaway" group: its child named "Visual" (or the node itself) is scaled
## on Y. Collisions are untouched.

enum Mode { AUTO, ALL_DOWN, ALL_UP }

@export var player: Node3D
@export var camera: Camera3D
@export var mode: Mode = Mode.AUTO
## Walls further than this from the player (m) stay up in AUTO mode.
@export var radius: float = 9.0
@export var lowered_height: float = 0.12
@export var speed: float = 6.0


func _ready() -> void:
	add_to_group(&"cutaway_controller")


func cycle_mode() -> void:
	mode = ((mode + 1) % Mode.size()) as Mode
	EventBus.toast.emit("Walls: %s" % Mode.keys()[mode])


func _process(delta: float) -> void:
	if player == null or camera == null:
		return
	var view_dir := -camera.global_basis.z
	view_dir.y = 0.0
	view_dir = view_dir.normalized()
	var step := speed * delta
	for node: Node3D in get_tree().get_nodes_in_group(&"cutaway"):
		var visual := node.get_node_or_null(^"Visual") as Node3D
		if visual == null:
			visual = node
		var target := 1.0
		match mode:
			Mode.ALL_DOWN:
				target = lowered_height
			Mode.AUTO:
				if should_cut(node.global_position, player.global_position, view_dir, radius):
					target = lowered_height
		visual.scale.y = move_toward(visual.scale.y, target, step)


## A wall is cut when it is on the camera side of the player and close enough.
static func should_cut(wall_pos: Vector3, player_pos: Vector3, view_dir: Vector3, max_dist: float) -> bool:
	var to_wall := wall_pos - player_pos
	to_wall.y = 0.0
	return to_wall.dot(view_dir) < -0.5 and to_wall.length() < max_dist

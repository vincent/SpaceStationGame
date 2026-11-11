extends Node3D
## Test double: any node exposing get_world_aabb() can be a camera focus.

var box := AABB()


func get_world_aabb() -> AABB:
	return box

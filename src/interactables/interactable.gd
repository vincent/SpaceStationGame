class_name Interactable
extends Area3D
## Base class for every station object the player can tap (bed, kitchen,
## window, machines...). Subclasses override `get_actions()`.
##
## Scene convention: an Area3D root on the "interactable" physics layer, with
## an optional StaticBody3D child so the object blocks movement. Meshes named
## "Accent*" get `accent_color`, all others `base_color`.

@export var display_name: String = "Object"
@export var base_color: Color = Palette.STEEL
@export var accent_color: Color = Palette.NEON_CYAN
@export_range(0.0, 8.0) var accent_emission: float = 2.0

## World-space point the player walks to before interacting. StationBuilder
## sets it to the nearest free floor cell; otherwise 1.2 m in front (+Z).
var approach_point: Vector3 = Vector3.INF


func _ready() -> void:
	collision_layer = 1 << 2
	collision_mask = 0
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if mesh.material_override != null:
			continue
		if mesh.name.begins_with("Accent"):
			mesh.material_override = ToonMaterials.get_material(accent_color, accent_emission)
		else:
			mesh.material_override = ToonMaterials.get_material(base_color)


## Override: the actions shown in the menu, rebuilt each time it opens so
## enabled/disabled state reflects the current inventory and needs.
func get_actions() -> Array[InteractionAction]:
	return []


func get_approach_position() -> Vector3:
	if approach_point != Vector3.INF:
		return approach_point
	return global_position + global_basis.z * 1.2


## Finds the Interactable owning a physics collider (the Area3D itself or a
## StaticBody3D child), or null.
static func from_collider(collider: Object) -> Interactable:
	var node := collider as Node
	while node != null:
		if node is Interactable:
			return node
		node = node.get_parent()
	return null

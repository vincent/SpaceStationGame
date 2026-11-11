class_name Interactable
extends Area3D
## Base class for every station object the player can tap (bed, kitchen,
## window, machines...). Subclasses override `get_actions()`.
##
## Scene convention: an Area3D root on the "interactable" physics layer, with
## an optional StaticBody3D child so the object blocks movement. Meshes named
## "Accent*" get `accent_color`, all others `base_color`. Meshes in the
## "powered_fx" group keep their own material; their module drives them.

@export var display_name: String = "Object"
@export var base_color: Color = Palette.STEEL
@export var accent_color: Color = Palette.NEON_CYAN
@export_range(0.0, 8.0) var accent_emission: float = 2.0
## Part of the station structure (e.g. a window in the hull): its meshes are
## cut by the cutaway like the hull instead of staying whole like furniture.
@export var structural: bool = false
## What character routines use it for (&"sleep", &"eat", &"stargaze",
## &"work"...), or empty. See PlayerRoutine.
@export var routine_tag: StringName = &""
## How long (game minutes) a routine keeps the character busy here.
@export var routine_minutes: float = 30.0

## How far in front (+Z) of the object the player stands to use it.
## StationBuilder sets it so the point lands on the free neighbour cell.
var approach_distance: float = 1.2


func _ready() -> void:
	collision_layer = Layers.INTERACTABLE
	collision_mask = 0
	if routine_tag != &"":
		add_to_group(&"routine_%s" % routine_tag)
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if mesh.material_override != null or mesh.is_in_group(&"powered_fx"):
			continue
		var accent := mesh.name.begins_with("Accent")
		var color := accent_color if accent else base_color
		var emission := accent_emission if accent else 0.0
		if structural:
			mesh.material_override = ToonMaterials.get_cut_material(color, emission)
		else:
			mesh.material_override = ToonMaterials.get_material(color, emission)


## Routine use, step 1: the character arrived. Returns the activity
## (a GameState.ACTIVITY_RATES key) held for `routine_minutes` while time
## flows, or &"" to skip holding.
func perform_routine() -> StringName:
	return &""


## Routine use, step 2: the hold finished (rewards go here).
func finish_routine() -> void:
	pass


## Override: the actions shown in the menu, rebuilt each time it opens so
## enabled/disabled state reflects the current inventory and needs.
func get_actions() -> Array[InteractionAction]:
	return []


func get_approach_position() -> Vector3:
	return global_position + global_basis.z * approach_distance


## Finds the Interactable owning a physics collider (the Area3D itself or a
## StaticBody3D child), or null.
static func from_collider(collider: Object) -> Interactable:
	var node := collider as Node
	while node != null:
		if node is Interactable:
			return node
		node = node.get_parent()
	return null

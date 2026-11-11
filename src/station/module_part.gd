@tool
class_name ModulePart
extends Node3D
## An explodable / upgradable piece of a module ("part_*" nodes under the
## module's Parts node). Placeholder geometry is procedural (`kind`); parts
## imported from Blender use Kind.CUSTOM and keep their own child meshes.
## UpgradeDef.part_node names the part an upgrade reveals; parts with
## `always_visible` belong to the module itself.

enum Kind { CUSTOM, SOLAR_WING, ANTENNA, THRUSTER, REACTOR, RADIATOR, DISH, GARDEN, PANEL_ARRAY, CLAMP }

const PLAIN := Color(0.3, 0.0, 0.0)
const TRIM := Color(0.3, 0.0, 1.0)
const PANEL := Color(0.2, 0.0, 0.85)
const GLOW := Color(0.0, 1.0, 0.0)

@export var kind: Kind = Kind.CUSTOM
## Main dimension in metres (wing span, mast height...).
@export var length: float = 4.0
## Build the geometry mirrored on -X too (pairs of wings, fins...).
@export var mirror: bool = false
## Exploded-view direction (module local). Zero = away from the module centre.
@export var explode_dir: Vector3 = Vector3.ZERO
@export var always_visible: bool = false

var mesh_instance: MeshInstance3D


## (Re)builds the placeholder mesh with the module's material.
func build(material: Material) -> void:
	if kind == Kind.CUSTOM:
		for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
			mesh.material_override = material
		return
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "Mesh"
		add_child(mesh_instance)
	var kit := MeshKit.new()
	_emit(kit)
	if mirror:
		kit.xform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
		_emit(kit)
	mesh_instance.mesh = kit.commit()
	mesh_instance.material_override = material


## Every GeometryInstance3D of the part (for instance uniforms).
func geometries() -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	for node in find_children("*", "GeometryInstance3D", true, false):
		out.append(node as GeometryInstance3D)
	return out


## AABB of the part's geometry expressed in `space`'s local coordinates.
func get_aabb_in(space: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var to_space := space.global_transform.affine_inverse()
	for geo in geometries():
		var box := (to_space * geo.global_transform) * geo.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


func _emit(k: MeshKit) -> void:
	var l := length
	match kind:
		Kind.SOLAR_WING:
			k.box_between(Vector3(0, -0.08, -0.08), Vector3(l * 0.3, 0.08, 0.08), TRIM)
			k.box(Vector3(l * 0.65, 0, 0), Vector3(l * 0.7, 0.06, 1.9), PANEL)
			for i in 3:
				k.box(Vector3(l * (0.35 + 0.23 * (i + 0.5)), 0.05, 0), Vector3(0.05, 0.04, 1.9), PLAIN)
		Kind.ANTENNA:
			k.box(Vector3(0, l * 0.5, 0), Vector3(0.1, l, 0.1), TRIM)
			k.box(Vector3(0, l * 0.7, 0), Vector3(1.1, 0.06, 0.06), TRIM)
			k.box(Vector3(0, l * 0.5, 0), Vector3(0.06, 0.06, 0.8), TRIM)
			k.box(Vector3(0, l + 0.1, 0), Vector3(0.2, 0.2, 0.2), GLOW)
		Kind.THRUSTER:
			k.cylinder(Vector3(-l * 0.5, 0, 0), 0.65, l, 0, PLAIN, 12)
			k.cylinder(Vector3(-l - 0.2, 0, 0), 0.85, 0.4, 0, TRIM, 12)
			k.cylinder(Vector3(-l - 0.42, 0, 0), 0.55, 0.04, 0, GLOW, 12)
		Kind.REACTOR:
			k.cylinder(Vector3(0, l * 0.5, 0), 1.1, l, 1, PLAIN, 14)
			for f: float in [0.3, 0.7]:
				k.cylinder(Vector3(0, l * f, 0), 1.16, 0.14, 1, GLOW, 14)
			k.box(Vector3(0, l + 0.15, 0), Vector3(1.4, 0.3, 1.4), TRIM)
		Kind.RADIATOR:
			k.box(Vector3(0, 0.1, 0), Vector3(0.3, 0.2, 2.2), TRIM)
			for i in 6:
				k.box(Vector3(0.3 + i * 0.32, 0.1, 0), Vector3(0.06, 0.12, 2.0), PLAIN)
				k.box(Vector3(0.3 + i * 0.32, l * 0.5, 0), Vector3(0.05, l, 1.6), PANEL)
		Kind.DISH:
			k.box(Vector3(0, 0.7, 0), Vector3(0.18, 1.4, 0.18), TRIM)
			k.xform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-35.0)), Vector3(0, 1.5, 0))
			k.cylinder(Vector3.ZERO, l * 0.5, 0.16, 1, PLAIN, 16)
			k.cylinder(Vector3(0, 0.45, 0), 0.08, 0.8, 1, TRIM, 6)
			k.box(Vector3(0, 0.9, 0), Vector3(0.18, 0.18, 0.18), GLOW)
			k.xform = Transform3D.IDENTITY
		Kind.GARDEN:
			k.box(Vector3(0, 0.08, 0), Vector3(l, 0.16, 1.8), TRIM)
			k.box(Vector3(0, 0.7, 0), Vector3(l - 0.2, 1.0, 1.6), PANEL)
			k.box(Vector3(0, 1.26, 0), Vector3(l - 0.4, 0.06, 1.4), GLOW)
		Kind.PANEL_ARRAY:
			k.box(Vector3(0, 0.9, 0), Vector3(0.2, 1.8, 0.2), TRIM)
			k.box_between(Vector3(0, 1.75, -0.1), Vector3(l, 1.95, 0.1), TRIM)
			for i in 3:
				var w := (l - 1.0) / 3.0
				k.box(Vector3(1.0 + i * w + w * 0.5, 1.9, 0), Vector3(w - 0.15, 0.06, 2.6), PANEL)
		Kind.CLAMP:
			for s: float in [-1.0, 1.0]:
				k.box(Vector3(0, 1.2, s * 1.1), Vector3(0.5, 0.3, 0.3), TRIM)
				k.box(Vector3(0.35, 1.2, s * 1.1), Vector3(0.2, 0.5, 0.5), GLOW)

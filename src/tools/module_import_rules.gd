@tool
class_name ModuleImportRules
## Naming conventions for module art exported from Blender (glTF), applied by
## the editor post-import script (module_import.gd). See docs/ART_PIPELINE.md.
##
##   hull            the watertight, thick outer shell (cut + capped)
##   slot_<X>        attachment point "X" (+Z points out of the module)
##   part_<name>     explodable / upgradable part (ModulePart, kind CUSTOM);
##                   glTF extras "explode_dir": [x, y, z] sets its direction
##   light_<name>    interior light anchor (Module adds an OmniLight there)
##   <name>-col      collision (Godot's own import hint, kept as is)
##   <name>-nav      navigation source: becomes a hidden floor collider on
##                   the "world" layer so the runtime navmesh bake sees it

enum Kind { NONE, HULL, SLOT, PART, LIGHT, COLLISION, NAV }


static func classify(node_name: String) -> Kind:
	var n := node_name.to_lower()
	if n == "hull":
		return Kind.HULL
	if n.begins_with("slot_"):
		return Kind.SLOT
	if n.begins_with("part_"):
		return Kind.PART
	if n.begins_with("light_"):
		return Kind.LIGHT
	if n.ends_with("-col") or n.ends_with("_col"):
		return Kind.COLLISION
	if n.ends_with("-nav") or n.ends_with("_nav"):
		return Kind.NAV
	return Kind.NONE


## Slot name from a node name: "slot_a" -> &"A".
static func slot_name(node_name: String) -> StringName:
	return StringName(node_name.substr(5).to_upper())


## Rewrites an imported scene in place. Returns the number of nodes converted.
static func apply(root: Node) -> int:
	var converted := 0
	var parts_root := root.get_node_or_null(^"Parts")
	for node in root.find_children("*", "", true, false):
		match classify(node.name):
			Kind.SLOT:
				_replace(node, Marker3D.new())
				converted += 1
			Kind.LIGHT:
				var anchor := Marker3D.new()
				_replace(node, anchor)
				anchor.add_to_group(&"light_anchor", true)
				converted += 1
			Kind.PART:
				if parts_root == null:
					parts_root = Node3D.new()
					parts_root.name = "Parts"
					root.add_child(parts_root)
					parts_root.owner = root
				_make_part(node as Node3D, parts_root, root)
				converted += 1
			Kind.NAV:
				_make_nav_source(node as MeshInstance3D, root)
				converted += 1
	return converted


static func _replace(old: Node, replacement: Node3D) -> void:
	var parent := old.get_parent()
	var scene_owner := old.owner
	var index := old.get_index()
	replacement.transform = (old as Node3D).transform if old is Node3D else Transform3D.IDENTITY
	for child in old.get_children():
		old.remove_child(child)
		replacement.add_child(child)
	parent.remove_child(old)
	replacement.name = old.name
	parent.add_child(replacement)
	parent.move_child(replacement, index)
	replacement.owner = scene_owner
	for child in replacement.find_children("*", "", true, false):
		child.owner = scene_owner  # moved nodes must keep the scene owner to be saved
	old.free()


static func _make_part(node: Node3D, parts_root: Node, root: Node) -> void:
	if node.get_parent() != parts_root:
		# Keep the local transform: the scene isn't in a tree during import (no
		# global transforms) and Parts sits at the root's origin.
		node.reparent(parts_root, false)
		node.owner = root
		for child in node.find_children("*", "", true, false):
			child.owner = root
	var extras: Variant = node.get_meta(&"extras", {})
	node.set_script(load("res://src/station/module_part.gd"))
	node.set(&"kind", ModulePart.Kind.CUSTOM)
	if extras is Dictionary and extras.has("explode_dir"):
		var d: Array = extras.explode_dir
		node.set(&"explode_dir", Vector3(d[0], d[1], d[2]))


static func _make_nav_source(mesh: MeshInstance3D, root: Node) -> void:
	if mesh == null or mesh.mesh == null:
		return
	var body := StaticBody3D.new()
	body.name = mesh.name.trim_suffix("-nav").trim_suffix("_nav") + "_navsource"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	col.shape = mesh.mesh.create_trimesh_shape()
	body.add_child(col)
	mesh.add_child(body)
	body.owner = root
	col.owner = root
	mesh.visible = false

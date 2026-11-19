extends GutTest
## Imported kit art: how Module styles the non-hull pieces (docs/ART_PIPELINE.md).


func _build(id: StringName) -> Module:
	var db := ModuleDB.new()
	db.load_dirs()
	var def := db.get_module(id)
	var module := (load(def.scene_path) as PackedScene).instantiate() as Module
	module.def = def
	add_child_autofree(module)
	module.build()
	return module


func _frame_meshes(module: Module) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in module.get_children():
		if String(child.name).begins_with("frame"):
			if child is MeshInstance3D:
				out.append(child as MeshInstance3D)
			for mesh: MeshInstance3D in child.find_children("*", "MeshInstance3D", true, false):
				out.append(mesh)
	return out


func test_canopy_frame_is_never_cut() -> void:
	var module := _build(&"greenhouse")
	var frames := _frame_meshes(module)
	assert_gt(frames.size(), 0, "greenhouse has a frame")
	for mesh in frames:
		var mat := mesh.material_override as ShaderMaterial
		assert_not_null(mat, "frame has the art material")
		if mat:
			assert_eq(mat.shader, ToonMaterials.TOON_SHADER, "frame uses the uncut toon shader")


func test_canopy_frame_stays_visible() -> void:
	var module := _build(&"greenhouse")
	module.set_interior_visible(false)
	module.set_detail_visible(false)
	for mesh in _frame_meshes(module):
		assert_true(mesh.is_visible_in_tree(), "frame visible with the hull closed in station view")

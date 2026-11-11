@tool
extends EditorScenePostImport
## Post-import script for module scenes exported from Blender. Set it in the
## glTF's Import dock (Scene > Import Script) — see docs/ART_PIPELINE.md.


func _post_import(scene: Node) -> Object:
	var n := ModuleImportRules.apply(scene)
	print("Module import: %s — %d nodes converted" % [get_source_file(), n])
	return scene

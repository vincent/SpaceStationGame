@tool
class_name ToonMaterials
## Factory + cache for cel-shaded materials, so every placeholder mesh shares
## the same look. Real art can keep using the same shader.

const TOON_SHADER := preload("res://assets/shaders/toon.gdshader")
const OUTLINE_SHADER := preload("res://assets/shaders/outline.gdshader")

static var _cache: Dictionary[String, ShaderMaterial] = {}


static func get_material(color: Color, emission: float = 0.0, outline: bool = true) -> ShaderMaterial:
	var key := "%s|%.2f|%s" % [color.to_html(), emission, outline]
	if _cache.has(key):
		return _cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = TOON_SHADER
	mat.set_shader_parameter("albedo", color)
	if emission > 0.0:
		mat.set_shader_parameter("emission_color", color)
		mat.set_shader_parameter("emission_energy", emission)
	if outline:
		var outline_mat := ShaderMaterial.new()
		outline_mat.shader = OUTLINE_SHADER
		mat.next_pass = outline_mat
	_cache[key] = mat
	return mat


## Applies a toon material to every MeshInstance3D under `root` that has no
## material yet.
static func apply_to_tree(root: Node, color: Color, emission: float = 0.0) -> void:
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mesh.material_override == null and mesh.get_active_material(0) == null:
			mesh.material_override = get_material(color, emission)

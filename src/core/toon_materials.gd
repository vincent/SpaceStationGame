@tool
class_name ToonMaterials
## Factory + cache for cel-shaded materials, so every placeholder mesh shares
## the same look. Real art can keep using the same shaders.
##   get_material()     furniture, characters, props: never cut
##   get_cut_material() station structure (hull, bulkheads, parts): clipped by
##                      the cutaway, back faces drawn as the section fill

const TOON_SHADER := preload("res://assets/shaders/toon.gdshader")
const TOON_CUT_SHADER := preload("res://assets/shaders/toon_cut.gdshader")
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
		mat.next_pass = _outline(false)
	_cache[key] = mat
	return mat


## Material for station structure. `trim` is mixed in by the vertex colour B
## mask; per-module values (wear, power, cap tint) are instance uniforms.
static func get_cut_material(
		color: Color, emission: float = 0.0, outline: bool = true, trim: Color = Color(0.16, 0.17, 0.2)
) -> ShaderMaterial:
	var key := "cut|%s|%s|%.2f|%s" % [color.to_html(), trim.to_html(), emission, outline]
	if _cache.has(key):
		return _cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = TOON_CUT_SHADER
	mat.set_shader_parameter("albedo", color)
	mat.set_shader_parameter("trim_color", trim)
	if emission > 0.0:
		mat.set_shader_parameter("emission_color", color)
		mat.set_shader_parameter("emission_energy", emission)
	if outline:
		mat.next_pass = _outline(true)
	_cache[key] = mat
	return mat


static func _outline(clip: bool) -> ShaderMaterial:
	var key := "outline|%s" % clip
	if not _cache.has(key):
		var outline_mat := ShaderMaterial.new()
		outline_mat.shader = OUTLINE_SHADER
		outline_mat.set_shader_parameter("clip_enabled", clip)
		_cache[key] = outline_mat
	return _cache[key]


## Applies a toon material to every MeshInstance3D under `root` that has no
## material yet.
static func apply_to_tree(root: Node, color: Color, emission: float = 0.0) -> void:
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mesh.material_override == null and mesh.get_active_material(0) == null:
			mesh.material_override = get_material(color, emission)

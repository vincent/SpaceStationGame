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
## mask. Shared: Module swaps in its own copies for per-module values (wear,
## power, cap tint, sweeps).
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


## Material for imported Blender art (docs/ART_PIPELINE.md): colours come from
## the palette texture (each face's UV points at a swatch), wear / glow / trim
## from the vertex colour masks. `cut` = station structure (hull, greebles,
## parts); otherwise interior props (never cut).
static func get_art_material(palette: Texture2D, cut: bool) -> ShaderMaterial:
	var key := "art|%s|%s" % [palette.resource_path, cut]
	if _cache.has(key):
		return _cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = TOON_CUT_SHADER if cut else TOON_SHADER
	mat.set_shader_parameter("albedo", Color.WHITE)
	mat.set_shader_parameter("albedo_texture", palette)
	if cut:
		mat.set_shader_parameter("trim_color", Color.WHITE)  # the palette already holds trim colours
		mat.set_shader_parameter("emission_from_texture", true)
	else:
		mat.set_shader_parameter("mask_emission", true)
	mat.next_pass = _outline(cut)
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

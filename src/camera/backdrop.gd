class_name Backdrop
extends MeshInstance3D
## Space background: a quad parented to the camera, kept just inside the far
## plane and sized to fill the orthographic view. (Sky shaders and the Canvas
## background mode don't behave consistently across renderers with an
## orthographic camera, this does.) The stars drift slowly (the station
## turns) with a slight parallax when the camera pans; they never rotate.
## The nebula is low-frequency and costly (domain-warped fBm), so it is baked
## once into a tileable texture by a SubViewport and only sampled per frame.

const STARFIELD := preload("res://assets/shaders/starfield.gdshader")
const NEBULA_BAKE := preload("res://assets/shaders/nebula_bake.gdshader")
## Parallax strength: star offset in px per px of camera movement.
const PARALLAX := 0.12
## Slow drift in px per second.
const DRIFT := Vector2(1.6, 0.4)
## Baked nebula texture size (px, square, tileable).
const NEBULA_SIZE := 1024
const NEBULA_STRENGTH := 0.45
const HALO_STRENGTH := 1.0

var nebula_strength := NEBULA_STRENGTH:
	set(v):
		nebula_strength = v
		if _material:
			_material.set_shader_parameter(&"nebula_strength", v)
var halo_strength := HALO_STRENGTH:
	set(v):
		halo_strength = v
		if _material:
			_material.set_shader_parameter(&"halo_strength", v)

var _material: ShaderMaterial
var _drift := Vector2.ZERO
var _bake: SubViewport


func _ready() -> void:
	mesh = QuadMesh.new()
	_material = ShaderMaterial.new()
	_material.shader = STARFIELD
	_material.set_shader_parameter(&"top_color", Palette.SPACE_TOP)
	_material.set_shader_parameter(&"mid_color", Palette.SPACE_MID)
	_material.set_shader_parameter(&"bottom_color", Palette.SPACE_BOTTOM)
	_material.set_shader_parameter(&"nebula_strength", nebula_strength)
	_material.set_shader_parameter(&"halo_strength", halo_strength)
	_material.set_shader_parameter(&"nebula_tex", _bake_nebula())
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0


func get_nebula_texture() -> Texture2D:
	return _bake.get_texture() if _bake else null


## Renders the nebula once into a SubViewport; its texture stays valid.
func _bake_nebula() -> Texture2D:
	_bake = SubViewport.new()
	_bake.name = "NebulaBake"
	_bake.size = Vector2i(NEBULA_SIZE, NEBULA_SIZE)
	_bake.transparent_bg = true
	_bake.disable_3d = true
	_bake.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(NEBULA_SIZE, NEBULA_SIZE)
	var mat := ShaderMaterial.new()
	mat.shader = NEBULA_BAKE
	mat.set_shader_parameter(&"color_deep", Palette.NEBULA_DEEP)
	mat.set_shader_parameter(&"color_violet", Palette.NEBULA_VIOLET)
	mat.set_shader_parameter(&"color_teal", Palette.NEBULA_TEAL)
	mat.set_shader_parameter(&"color_core", Palette.NEBULA_CORE)
	rect.material = mat
	_bake.add_child(rect)
	add_child(_bake)
	return _bake.get_texture()


func _process(delta: float) -> void:
	var cam := get_parent() as Camera3D
	if cam == null:
		return
	var view := get_viewport().get_visible_rect().size
	var height := cam.size * 1.1
	scale = Vector3(height * view.x / maxf(view.y, 1.0), height, 1.0)
	position = Vector3(0.0, 0.0, -cam.far * 0.95)
	_drift += DRIFT * delta
	var px_per_m := view.y / maxf(cam.size, 0.01)
	var p := cam.global_position
	var shift := Vector2(p.dot(cam.global_basis.x), -p.dot(cam.global_basis.y)) * px_per_m * PARALLAX
	_material.set_shader_parameter(&"parallax", shift + _drift)

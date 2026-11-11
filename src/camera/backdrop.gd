class_name Backdrop
extends MeshInstance3D
## Space background: a quad parented to the camera, kept just inside the far
## plane and sized to fill the orthographic view. (Sky shaders and the Canvas
## background mode don't behave consistently across renderers with an
## orthographic camera, this does.) The stars drift slowly (the station
## turns) with a slight parallax when the camera pans; they never rotate.

const STARFIELD := preload("res://assets/shaders/starfield.gdshader")
## Parallax strength: star offset in px per px of camera movement.
const PARALLAX := 0.12
## Slow drift in px per second.
const DRIFT := Vector2(1.6, 0.4)

var _material: ShaderMaterial
var _drift := Vector2.ZERO


func _ready() -> void:
	mesh = QuadMesh.new()
	_material = ShaderMaterial.new()
	_material.shader = STARFIELD
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0


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

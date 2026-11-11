class_name Backdrop
extends MeshInstance3D
## Space background: a quad parented to the camera, kept just inside the far
## plane and sized to fill the orthographic view. (Sky shaders and the Canvas
## background mode don't behave consistently across renderers with an
## orthographic camera, this does.)

const STARFIELD := preload("res://assets/shaders/starfield.gdshader")


func _ready() -> void:
	mesh = QuadMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = STARFIELD
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0


func _process(_delta: float) -> void:
	var cam := get_parent() as Camera3D
	if cam == null:
		return
	var view := get_viewport().get_visible_rect().size
	var height := cam.size * 1.1
	scale = Vector3(height * view.x / maxf(view.y, 1.0), height, 1.0)
	position = Vector3(0.0, 0.0, -cam.far * 0.95)

extends Interactable
## Wall-less standing console with a screen. The screen flickers on when its
## module is powered (Module drives every "powered_fx" mesh).

const FX_SHADER := preload("res://assets/shaders/ambient_fx.gdshader")


func _ready() -> void:
	var screen := get_node_or_null(^"Screen") as MeshInstance3D
	if screen:
		var mat := ShaderMaterial.new()
		mat.shader = FX_SHADER
		mat.set_shader_parameter("mode", 1)
		mat.set_shader_parameter("color", accent_color)
		screen.material_override = mat
	super()


func get_actions() -> Array[InteractionAction]:
	return [InteractionAction.new("Check station status", _status, true, "", "Power and modules")]


func _status() -> void:
	var st := GameState.station
	EventBus.toast.emit("Power %s / %s · %d modules" % [
		snappedf(st.power_draw(), 0.1), snappedf(st.power_output(), 0.1), st.uids().size()])

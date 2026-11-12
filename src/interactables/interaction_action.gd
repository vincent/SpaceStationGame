class_name InteractionAction
extends RefCounted
## One entry of an object's action menu ("Sleep 8 h", "Cook a meal"...).

var label: String
var callback: Callable
var enabled: bool
## Shown when disabled ("No food in stock").
var hint: String


func _init(p_label: String, p_callback: Callable, p_enabled: bool = true, p_hint: String = "") -> void:
	label = p_label
	callback = p_callback
	enabled = p_enabled
	hint = p_hint

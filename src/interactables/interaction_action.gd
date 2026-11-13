class_name InteractionAction
extends RefCounted
## One action of a station object ("Sleep 8 h", "Eat food"...), shown as a
## button of the object's HUD card: `label` on top, `detail` under it.

var label: String
var callback: Callable
var enabled: bool
## Shown instead of `detail` when disabled ("No food in stock").
var hint: String
## Second line of the button: duration, cost, status ("30 min", "4 scrap").
var detail: String


func _init(p_label: String, p_callback: Callable, p_enabled: bool = true, p_hint: String = "",
		p_detail: String = "") -> void:
	label = p_label
	callback = p_callback
	enabled = p_enabled
	hint = p_hint
	detail = p_detail


## The button's second line: the hint when disabled, else the detail.
func subtitle() -> String:
	return hint if not enabled and hint != "" else detail

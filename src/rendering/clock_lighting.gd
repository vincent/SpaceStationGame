class_name ClockLighting
extends Node
## Interior mood from the station clock: sets the `interior_warmth` shader
## global (0 = cool work light, 1 = warm night light). Modules dim their own
## lights with DayCycle.light_scale(). The exterior stays constant: it's space.

var warmth := 0.0


func _process(_delta: float) -> void:
	var w := DayCycle.warmth(GameClock.total_minutes / GameClock.MINUTES_PER_HOUR)
	if not is_equal_approx(w, warmth) or Engine.get_process_frames() < 2:
		warmth = w
		RenderingServer.global_shader_parameter_set(&"interior_warmth", w)

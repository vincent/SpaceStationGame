extends Interactable
## Bay window. Watching the stars restores morale.


## Set into a real wall `depth` thick (art / thin walls): the frame shrinks to the
## wall so it doesn't stick out of the hull; collision and approach stay the same.
func fit_wall(depth: float) -> void:
	$Visual/Frame.scale.z = depth / 2.0
	$Visual/AccentPane.position.z = depth / 2.0 + 0.02
	$Visual/AccentPaneOutside.position.z = -depth / 2.0 - 0.02


func get_actions() -> Array[InteractionAction]:
	return [
		InteractionAction.new("Watch the stars", _stargaze.bind(30.0), true, "", "30 min · +morale"),
		InteractionAction.new("Watch the stars", _stargaze.bind(120.0), true, "", "2 h · +morale"),
	]


func _stargaze(minutes: float) -> void:
	GameState.spend_time(minutes, &"stargazing")
	EventBus.toast.emit("The void is quiet tonight.")


func perform_routine() -> StringName:
	return &"stargazing"

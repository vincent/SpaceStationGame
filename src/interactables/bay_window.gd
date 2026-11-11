extends Interactable
## Bay window. Watching the stars restores morale.


func get_actions() -> Array[InteractionAction]:
	return [
		InteractionAction.new("Watch the stars (30 min)", _stargaze.bind(30.0)),
		InteractionAction.new("Watch the stars (2 h)", _stargaze.bind(120.0)),
	]


func _stargaze(minutes: float) -> void:
	GameState.spend_time(minutes, &"stargazing")
	EventBus.toast.emit("The void is quiet tonight.")


func perform_routine() -> StringName:
	return &"stargazing"

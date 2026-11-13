extends Interactable
## Bay window. Watching the stars restores morale.


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

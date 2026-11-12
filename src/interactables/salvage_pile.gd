extends Interactable
## Pile of wreckage. Sorting through it yields scrap metal (the build and
## repair currency) at the cost of time and energy.

const SALVAGE_MINUTES := 60.0
const SALVAGE_YIELD: Dictionary[StringName, int] = {&"scrap_metal": 2}


func get_actions() -> Array[InteractionAction]:
	return [InteractionAction.new("Salvage scrap (1 h)", _salvage)]


func _salvage() -> void:
	GameState.spend_time(SALVAGE_MINUTES, &"working")
	GameState.give(SALVAGE_YIELD)
	EventBus.toast.emit("+%d scrap." % SALVAGE_YIELD[&"scrap_metal"])


func perform_routine() -> StringName:
	return &"working"


func finish_routine() -> void:
	GameState.give({&"scrap_metal": 1})

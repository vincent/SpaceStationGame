extends Interactable
## Improvised kitchen: turns rations + water into a real meal.

const MEAL_COST: Dictionary[StringName, int] = {&"ration": 1, &"water": 1}
const MEAL_MINUTES := 30.0
const MEAL_EFFECTS: Dictionary[StringName, float] = {Needs.FOOD: 40.0, Needs.MORALE: 5.0}


func get_actions() -> Array[InteractionAction]:
	var can_cook := GameState.inventory.has_all(MEAL_COST)
	return [
		InteractionAction.new("Cook a meal (30 min)", _cook, can_cook, "Needs 1 ration + 1 water"),
	]


func _cook() -> void:
	if GameState.perform(MEAL_COST, MEAL_MINUTES, MEAL_EFFECTS, &"cooking"):
		EventBus.toast.emit("A hot meal. Almost like home.")


func perform_routine() -> StringName:
	if GameState.inventory.has_all(MEAL_COST):
		_cook()
	return &""

extends Interactable
## Improvised bed. Sleeping skips time and restores energy.

const SLEEP_OPTIONS: Array[int] = [1, 4, 8]


func get_actions() -> Array[InteractionAction]:
	var actions: Array[InteractionAction] = []
	for hours in SLEEP_OPTIONS:
		actions.append(InteractionAction.new("Sleep %d h" % hours, GameState.sleep.bind(float(hours)),
			true, "", "+energy"))
	return actions


func perform_routine() -> StringName:
	return &"sleeping"

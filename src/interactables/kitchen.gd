extends Interactable
## Improvised kitchen: a meal takes one unit of a food resource from the
## station stock. Its effects are the item's `use_effects`.

const MEAL_MINUTES := 30.0


## Bulk items you can eat here (usable, tagged "food"), in id order.
static func meal_items() -> Array[ItemData]:
	var out: Array[ItemData] = []
	for id in GameState.item_db.ids():
		var item := GameState.item_db.get_item(id)
		if item.bulk and item.usable and item.tags.has("food"):
			out.append(item)
	return out


func get_actions() -> Array[InteractionAction]:
	var actions: Array[InteractionAction] = []
	for item in meal_items():
		var gain := roundi(item.use_effects.get(Needs.FOOD, 0.0))
		actions.append(InteractionAction.new("Eat (+%d food) · %d left" % [gain, GameState.count(item.id)],
			_eat.bind(item), GameState.count(item.id) >= 1, "No %s in stock" % item.display_name.to_lower()))
	return actions


func _eat(item: ItemData) -> void:
	if GameState.perform({item.id: 1}, MEAL_MINUTES, item.use_effects, &"cooking"):
		EventBus.toast.emit("A hot meal. Almost like home.")


func perform_routine() -> StringName:
	for item in meal_items():
		if GameState.count(item.id) >= 1:
			_eat(item)
			break
	return &""

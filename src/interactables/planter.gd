extends Interactable
## Planter row of an agri bay. The bay grows food on its own (Production);
## tending the plants is a small morale break and shows how the bay is doing.

const TEND_MINUTES := 30.0
const TEND_MORALE := 4.0


func get_actions() -> Array[InteractionAction]:
	return [InteractionAction.new("Tend the plants (30 min) · %s" % crop_report(), _tend)]


## "food +0.15/h", "unpowered", "needs water"... for the bay holding this planter.
func crop_report() -> String:
	var module := _module()
	if module == null or not GameState.station.has_module(module.uid):
		return "no bay"
	var info := Production.module_rates(GameState.station, GameState.stock, module.uid)
	match info.status:
		Production.Status.DERELICT:
			return "derelict"
		Production.Status.UNPOWERED:
			return "unpowered"
		Production.Status.STARVED:
			return "needs %s" % GameState.item_db.get_item(info.missing).display_name.to_lower() \
				if info.missing != &"" else "starved"
	var parts: PackedStringArray = []
	for id: StringName in info.rates:
		if info.rates[id] > 0.0:
			parts.append("%s +%s/h" % [GameState.item_db.get_item(id).display_name.to_lower(), snappedf(info.rates[id], 0.01)])
	return ", ".join(parts) if not parts.is_empty() else "idle"


func _tend() -> void:
	if GameState.perform({}, TEND_MINUTES, {Needs.MORALE: TEND_MORALE}):
		EventBus.toast.emit("Green leaves, wet soil. It smells like a planet.")


func _module() -> Module:
	var node := get_parent()
	while node != null and not node is Module:
		node = node.get_parent()
	return node as Module

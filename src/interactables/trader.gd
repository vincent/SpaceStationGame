extends Interactable
## Merchant aboard a docked visitor ship. Trades are simple swaps paid from
## (and delivered to) the station stock or the inventory.

## [label, cost, get]
const OFFERS: Array = [
	["Buy 3 food for 4 scrap", {&"scrap_metal": 4}, {&"food": 3}],
	["Buy 4 water for 2 scrap", {&"scrap_metal": 2}, {&"water": 4}],
	["Buy a power cell for 5 scrap", {&"scrap_metal": 5}, {&"power_cell": 1}],
	["Sell 2 food for 4 scrap", {&"food": 2}, {&"scrap_metal": 4}],
]


## A hand looking for work hops off the ship (needs a free bunk).
const HIRE_COST: Dictionary[StringName, int] = {&"scrap_metal": 6, &"food": 2}


func get_actions() -> Array[InteractionAction]:
	var actions: Array[InteractionAction] = []
	var crew := GameState.station.crew
	actions.append(InteractionAction.new("Hire a hand (%s)" % GameState.format_cost(HIRE_COST), _hire,
		crew.free_beds() > 0 and GameState.has_all(HIRE_COST),
		"No free bunk" if crew.free_beds() <= 0 else "Can't afford"))
	for offer: Array in OFFERS:
		var cost: Dictionary = offer[1]
		actions.append(InteractionAction.new(offer[0], _trade.bind(cost, offer[2]),
			GameState.has_all(cost), "Can't afford"))
	return actions


func _hire() -> void:
	if GameState.station.crew.free_beds() > 0 and GameState.pay(HIRE_COST):
		GameState.station.crew.add()
		EventBus.trade_completed.emit()


func _trade(cost: Dictionary, get_items: Dictionary) -> void:
	if GameState.trade(cost, get_items):
		EventBus.toast.emit("Pleasure doing business.")
		EventBus.trade_completed.emit()

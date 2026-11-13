extends Interactable
## Merchant aboard a docked visitor ship. Trades are simple swaps paid from
## (and delivered to) the station stock or the inventory.

## [label, cost, get]
const OFFERS: Array = [
	["Buy 3 food", {&"scrap_metal": 4}, {&"food": 3}],
	["Buy 4 water", {&"scrap_metal": 2}, {&"water": 4}],
	["Buy a power cell", {&"scrap_metal": 5}, {&"power_cell": 1}],
	["Sell 2 food", {&"food": 2}, {&"scrap_metal": 4}],
]


## A hand looking for work hops off the ship (needs a free bunk).
const HIRE_COST: Dictionary[StringName, int] = {&"scrap_metal": 6, &"food": 2}


func get_actions() -> Array[InteractionAction]:
	var actions: Array[InteractionAction] = []
	var crew := GameState.station.crew
	var hire_cost := GameState.format_cost(HIRE_COST)
	actions.append(InteractionAction.new("Hire a hand", _hire,
		crew.free_beds() > 0 and GameState.has_all(HIRE_COST),
		"No free bunk" if crew.free_beds() <= 0 else "Can't afford %s" % hire_cost, hire_cost))
	for offer: Array in OFFERS:
		var cost: Dictionary = offer[1]
		var price := "for %s" % GameState.format_cost(cost)
		actions.append(InteractionAction.new(offer[0], _trade.bind(cost, offer[2]),
			GameState.has_all(cost), "Can't afford: %s" % price, price))
	return actions


func _hire() -> void:
	if GameState.station.crew.free_beds() > 0 and GameState.pay(HIRE_COST):
		GameState.station.crew.add()
		EventBus.trade_completed.emit()


func _trade(cost: Dictionary, get_items: Dictionary) -> void:
	if GameState.trade(cost, get_items):
		EventBus.toast.emit("Pleasure doing business.")
		EventBus.trade_completed.emit()
